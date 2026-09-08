import Foundation

/// Tester attestation + remote config (ADR-0005). The server owns one
/// flag today — `requireTesterAttestation` — which decides whether the
/// report triggers work for everyone (open mode) or only on installs
/// holding a valid tester token (testers-only mode).
///
/// Fail-mode (ADR-0005 Decision 4): the last cached value wins when
/// the config fetch fails. With no cache at all, prod-prefixed keys
/// fail CLOSED (triggers inert until the first successful fetch says
/// open) and dev/staging-prefixed keys fail OPEN. Conservative where
/// real end users are, frictionless where people develop and QA.
///
/// The token itself arrives from the companion-app handshake (phase
/// 2); until that lands, hosts can inject one programmatically via
/// ``Issuetracker/setTesterToken(_:expiresAt:)``.
@MainActor
final class AttestationStore {
    static let shared = AttestationStore()

    private let defaults: UserDefaults
    private let configApiKeyKey = "io.issuetracker.sdk.remoteConfig.apiKey"
    private let configRequireKey = "io.issuetracker.sdk.remoteConfig.requireTesterAttestation"
    private let tokenKey = "io.issuetracker.sdk.testerToken"
    private let tokenExpiresKey = "io.issuetracker.sdk.testerTokenExpiresAt"

    private var currentApiKey: String?
    // nil = no fetched/cached value for the current key; fall back to
    // the per-prefix fail-mode default.
    private var known: Bool?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Synchronous part of configure(): seed the in-memory value from
    /// the cache so the very first trigger fires against real data
    /// when we have any. The caller kicks the async refresh.
    func install(runtime: Runtime) {
        currentApiKey = runtime.apiKey
        if defaults.string(forKey: configApiKeyKey) == runtime.apiKey,
           defaults.object(forKey: configRequireKey) != nil {
            known = defaults.bool(forKey: configRequireKey)
        } else {
            // Reconfigured with a different key — a cached flag for the
            // old key must not leak onto the new project.
            known = nil
        }
    }

    func refreshRemoteConfig(runtime: Runtime) async {
        // ADR-0003 Decision 9 §2: a TERMINATED install makes no network
        // calls. Without this gate every launch of a terminated install
        // POSTs `getSdkConfig` forever — the config fetch is the one
        // call that runs unconditionally from `configure()`, so it is
        // exactly the path that turns one dead project into sustained
        // background traffic from the whole deployed cohort. Gated here
        // rather than only at the call site so every caller inherits it.
        guard !LifecycleStore.shared.isTerminated else { return }

        struct ConfigResult: Decodable { let requireTesterAttestation: Bool }
        do {
            let result: ConfigResult = try await APIClient.call(
                endpoint: runtime.endpoint,
                function: "getSdkConfig",
                payload: ["apiKey": runtime.apiKey]
            )
            adopt(requireTesterAttestation: result.requireTesterAttestation, apiKey: runtime.apiKey)
        } catch let err as APIClient.CallableError {
            // A terminal signal on the config fetch (key revoked,
            // project deleted, …) is as authoritative as one on
            // submission — flip to TERMINATED here too so a dead
            // cohort stops before it ever reaches the report endpoint.
            // Anything else (offline, transient) leaves the cached /
            // fail-mode value in charge.
            if let reason = err.sdkErrorReason, reason.isTerminal {
                LifecycleStore.shared.transitionToTerminated(
                    reason: reason,
                    callback: runtime.onConfigurationError
                )
            }
        } catch {
            // Network-level failure — keep the cached/fail-mode value.
        }
    }

    /// Internal seam for tests and for refreshRemoteConfig.
    func adopt(requireTesterAttestation: Bool, apiKey: String) {
        known = requireTesterAttestation
        defaults.set(apiKey, forKey: configApiKeyKey)
        defaults.set(requireTesterAttestation, forKey: configRequireKey)
    }

    /// The assumed `requireTesterAttestation` value with no data at
    /// all. Prod keys are exactly the ones without an env infix.
    nonisolated static func failModeDefault(for apiKey: String) -> Bool {
        !apiKey.hasPrefix("it_dev_") && !apiKey.hasPrefix("it_staging_")
    }

    private var requireAttestation: Bool {
        if let known { return known }
        guard let currentApiKey else { return false } // not configured yet
        return Self.failModeDefault(for: currentApiKey)
    }

    /// Valid (non-expired) tester token, or nil.
    var testerToken: String? {
        guard let token = defaults.string(forKey: tokenKey) else { return nil }
        if let expires = defaults.object(forKey: tokenExpiresKey) as? Double,
           Date(timeIntervalSince1970: expires) < Date() {
            return nil
        }
        return token
    }

    func setTesterToken(_ token: String, expiresAt: Date?) {
        defaults.set(token, forKey: tokenKey)
        if let expiresAt {
            defaults.set(expiresAt.timeIntervalSince1970, forKey: tokenExpiresKey)
        } else {
            defaults.removeObject(forKey: tokenExpiresKey)
        }
    }

    func clearTesterToken() {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: tokenExpiresKey)
    }

    /// Gesture-trigger gate. In testers-only mode without a token the
    /// triggers are silently inert — no UI, no hint the SDK exists
    /// (ADR-0005 invariant 5). The programmatic `report()` path is
    /// deliberately NOT gated on this: a host app's own "report a
    /// bug" button should surface the attestation error message
    /// rather than dying silently.
    var canTriggerReport: Bool {
        if !requireAttestation { return true }
        return testerToken != nil
    }
}
