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
/// The token arrives from the companion-app handshake
/// (``CompanionHandshake``), or is injected by the host via
/// ``Issuetracker/setTesterToken(_:expiresAt:)`` — which is how our
/// own dogfood builds attest on dev and staging keys, since no
/// companion is published for those environments.
@MainActor
final class AttestationStore {
    static let shared = AttestationStore()

    private let defaults: UserDefaults
    private let configApiKeyKey = "io.issuetracker.sdk.remoteConfig.apiKey"
    private let configRequireKey = "io.issuetracker.sdk.remoteConfig.requireTesterAttestation"
    private let tokenKey = "io.issuetracker.sdk.testerToken"
    private let tokenExpiresKey = "io.issuetracker.sdk.testerTokenExpiresAt"
    // ADR-0005 Decision 9: the token slot is apiKey-bound, mirroring
    // the config cache line for line. Without this a token minted for
    // one project survives a reconfigure onto another and gets
    // attached to reports it has no business attesting — which the
    // server rejects, so the visible symptom is a tester whose
    // gestures work and whose reports silently fail.
    private let tokenApiKeyKey = "io.issuetracker.sdk.testerTokenApiKey"

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
        bindToken(apiKey: runtime.apiKey)
    }

    /// Resolves the stored token against the key now in force
    /// (ADR-0005 Decision 9).
    ///
    /// Three cases, and the middle one is the reason this exists at
    /// all: a token written BEFORE `configure()` — which
    /// ``Issuetracker/setTesterToken(_:expiresAt:)`` explicitly
    /// permits — is stored unbound, and the first configure adopts it.
    /// A token bound to a different key is cleared, never carried
    /// forward.
    func bindToken(apiKey: String) {
        guard defaults.string(forKey: tokenKey) != nil else { return }
        switch defaults.string(forKey: tokenApiKeyKey) {
        case apiKey:
            break
        case nil:
            defaults.set(apiKey, forKey: tokenApiKeyKey)
        default:
            clearTesterToken()
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
    ///
    /// The expiry rule is unified across all four SDK stores
    /// (ADR-0005 Decision 10): **absent or `<= 0` means no local
    /// expiry; a positive expiry in the past means treat as absent
    /// AND clear.** iOS previously read a stored `0` as
    /// `Date(timeIntervalSince1970: 0)` — 1970, therefore expired —
    /// which is the opposite of what Android and web have always done
    /// with the same value.
    ///
    /// The clear is a write from a getter, which is unusual enough to
    /// justify: it is the only self-healing path for a stale token.
    /// Without it an expired token sits on disk forever, keeps being
    /// attached to reports, and keeps being rejected — and the
    /// renew-on-use extension that would have prevented the expiry
    /// only fires on a token the server still accepts.
    var testerToken: String? {
        guard let token = defaults.string(forKey: tokenKey) else { return nil }
        if let expires = defaults.object(forKey: tokenExpiresKey) as? Double,
           expires > 0,
           expires <= Date().timeIntervalSince1970 {
            clearTesterToken()
            return nil
        }
        return token
    }

    func setTesterToken(_ token: String, expiresAt: Date?) {
        defaults.set(token, forKey: tokenKey)
        // Bound when a key is in force, unbound when the host called
        // this before `configure()`. An unbound token is adopted by
        // the next `install(runtime:)`.
        if let currentApiKey {
            defaults.set(currentApiKey, forKey: tokenApiKeyKey)
        } else {
            defaults.removeObject(forKey: tokenApiKeyKey)
        }
        if let expiresAt {
            defaults.set(expiresAt.timeIntervalSince1970, forKey: tokenExpiresKey)
        } else {
            defaults.removeObject(forKey: tokenExpiresKey)
        }
    }

    /// Adopts a server-extended expiry (renew-on-use, ADR-0005
    /// Decision 10). The server slides `expiresAt` out on any use
    /// inside the renewal window and hands the new value back on the
    /// ingest response; a client that ignored it would keep its old
    /// expiry, treat a live token as dead, and re-handshake for
    /// nothing.
    ///
    /// Only ever moves the expiry FORWARD, and only for a token that
    /// is still there: a response arriving after a sign-out or a
    /// reconfigure must not resurrect a slot that was cleared.
    func adoptRenewedExpiry(millisecondsSince1970 ms: Double) {
        guard ms > 0, defaults.string(forKey: tokenKey) != nil else { return }
        let seconds = ms / 1000
        let current = defaults.object(forKey: tokenExpiresKey) as? Double
        guard current == nil || seconds > (current ?? 0) else { return }
        defaults.set(seconds, forKey: tokenExpiresKey)
    }

    func clearTesterToken() {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: tokenExpiresKey)
        defaults.removeObject(forKey: tokenApiKeyKey)
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
