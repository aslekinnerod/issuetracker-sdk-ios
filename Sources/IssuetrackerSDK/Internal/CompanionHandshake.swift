import Foundation
import UIKit

/// The iOS half of the companion handshake (ADR-0005 Decisions 2 and
/// 11).
///
/// Android's SDK queries a ContentProvider and gets the token back
/// silently, because the OS authenticates the caller before the
/// companion ever sees the request. iOS has nothing equivalent: App
/// Groups and shared Keychain require both apps to be signed by the
/// same team, and the only channel between apps from different teams
/// is a URL that any app registering the scheme can receive.
///
/// So the token never travels in a URL. The callback carries a
/// one-time CLAIM CODE, and redeeming it needs two more things the
/// legitimate flow holds and nobody else does: the API key baked into
/// this binary, and the nonce generated below — which lives in memory
/// for the duration of one app switch and is never written to disk.
/// A malicious app that forges a callback into this app holds a code
/// it cannot spend, and the real callback it might race has a nonce
/// it cannot guess.
///
///     out  issuetracker-testers://attest/v1
///            ?v=1&apiKey=it_…&callback=<this bundle id>
///            &nonce=<base64url 16B>&app=<display name>
///     back <this bundle id>://issuetracker-attest/v1
///            ?nonce=<echo>&claim=<one-time code>
///            (or &error=not_enrolled|plan|cancelled|failed)
///
/// Every string here is frozen forever — they are baked into shipped
/// customer binaries, and an iOS bundle identifier cannot be renamed
/// on the App Store at all. The companion side is
/// `iOS/Testers/Packages/TestersCore/Sources/TestersCore/AttestationContract.swift`
/// and the Android side is `CompanionContract.kt`. All three must
/// agree.
@MainActor
enum CompanionHandshake {

    // MARK: - Frozen contract

    static let companionScheme = "issuetracker-testers"
    static let outboundHost = "attest"
    static let outboundPath = "/v1"
    static let callbackHost = "issuetracker-attest"
    static let callbackPath = "/v1"
    static let protocolVersion = "1"

    // MARK: - State

    /// One handshake in flight at a time. In memory only: persisting
    /// the nonce would defeat the point of it, since the disk is
    /// exactly what a device-backup attacker reads.
    private struct Pending {
        let nonce: String
        let apiKey: String
        let startedAt: Date
        /// Whether the tester was trying to file a report when this
        /// started. If so, activation should land them in the
        /// reporter rather than back in an app that looks unchanged.
        let resumeReport: Bool
    }

    private static var pending: Pending?

    /// How long an unanswered handshake stays in memory. The claim it
    /// is waiting for expires server-side after two minutes, so a
    /// longer window here would only keep a nonce alive past the
    /// point where anything could be redeemed with it.
    private static let pendingLifetime: TimeInterval = 5 * 60

    /// The callback scheme the host app registered, from
    /// `configure(attestationCallbackURLScheme:)`. Without it there is
    /// nowhere for the companion to answer, so the handshake is never
    /// started — silently, because a host that did not configure it
    /// did not ask for this.
    private static var callbackScheme: String?

    static func install(callbackURLScheme: String?) {
        callbackScheme = callbackURLScheme?.trimmingCharacters(in: .whitespacesAndNewlines)
        // A re-configure abandons anything in flight: the nonce
        // belongs to the previous configuration and an answer arriving
        // for it can no longer be trusted to mean what it said.
        pending = nil
    }

    // MARK: - Starting

    /// Whether activation can be offered at all.
    ///
    /// `canOpenURL` is used exactly as ADR-0005 Decision 2 intends:
    /// not as security, but as the presence check that decides
    /// whether to offer. Someone without the companion installed is
    /// not a tester, and invariant 5 says they must see nothing.
    static func canOffer(runtime: Runtime) -> Bool {
        // ADR-0003 Decision 9 §2: a TERMINATED install never attempts
        // attestation. Checked before `canOpenURL` rather than after,
        // so a dead install does not even probe the device for what
        // else is on it.
        guard !LifecycleStore.shared.isTerminated else { return false }
        guard callbackScheme != nil else { return false }
        guard let probe = URL(string: "\(companionScheme)://\(outboundHost)") else { return false }
        return UIApplication.shared.canOpenURL(probe)
    }

    /// Starts the handshake if this install both needs one and can
    /// have one. Returns true when the companion was actually opened.
    ///
    /// "Needs one" is deliberately narrow: testers-only mode, and no
    /// usable token. In open mode the triggers already work and an app
    /// switch would be an interruption with nothing on the other side
    /// of it.
    @discardableResult
    static func offerIfNeeded(runtime: Runtime, resumeReport: Bool) -> Bool {
        guard !AttestationStore.shared.canTriggerReport else { return false }
        guard canOffer(runtime: runtime) else { return false }
        return begin(runtime: runtime, resumeReport: resumeReport)
    }

    @discardableResult
    static func begin(runtime: Runtime, resumeReport: Bool) -> Bool {
        guard let callbackScheme, let nonce = makeNonce() else { return false }

        var components = URLComponents()
        components.scheme = companionScheme
        components.host = outboundHost
        components.path = outboundPath
        components.queryItems = [
            URLQueryItem(name: "v", value: protocolVersion),
            URLQueryItem(name: "apiKey", value: runtime.apiKey),
            URLQueryItem(name: "callback", value: callbackScheme),
            URLQueryItem(name: "nonce", value: nonce),
            // Cosmetic, and the companion treats it as hostile copy —
            // it is shown under the bundle identifier, never instead
            // of it. Omitted when the host app has no display name.
            appNameItem(),
        ].compactMap { $0 }

        guard let url = components.url else { return false }
        pending = Pending(
            nonce: nonce,
            apiKey: runtime.apiKey,
            startedAt: Date(),
            resumeReport: resumeReport
        )
        UIApplication.shared.open(url)
        return true
    }

    // MARK: - Finishing

    /// Handles a callback URL. Returns false for anything that is not
    /// one of ours, so the host app can pass every URL through
    /// without having to recognise them first.
    @discardableResult
    static func handle(_ url: URL, runtime: Runtime?) -> Bool {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.host?.lowercased() == callbackHost
        else {
            return false
        }
        let path = components.path
        guard path.isEmpty || path == callbackPath else { return false }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        // From here on the URL is ours, so every exit returns true:
        // the host app must not go looking for another handler for a
        // URL we have already consumed and decided about.
        guard let inFlight = takePending() else { return true }
        guard let echoed = value("nonce"), constantTimeEquals(echoed, inFlight.nonce) else {
            // Either a stale answer to a handshake we abandoned, or a
            // forgery from another app on the device. Both are
            // discarded in silence — this path has no legitimate
            // failure a tester could act on.
            return true
        }

        guard let claim = value("claim"), !claim.isEmpty else {
            // The companion refused, and said why in `&error=`. None
            // of the reasons produce UI here: invariant 5 keeps the
            // SDK silent toward someone who turns out not to be a
            // tester, and the companion has already told the tester
            // itself, on its own screen, in its own words.
            return true
        }

        guard let runtime, runtime.apiKey == inFlight.apiKey else {
            // Reconfigured mid-handshake. The claim was issued against
            // the old key and is bound to it server-side, so spending
            // it now would fail anyway.
            return true
        }

        Task { @MainActor in
            await redeem(claim: claim, nonce: inFlight.nonce, runtime: runtime)
            if inFlight.resumeReport, AttestationStore.shared.canTriggerReport {
                // They shook the device to file a report and got sent
                // to another app for two seconds. Landing them back in
                // an app that looks unchanged would read as the
                // gesture having failed.
                Issuetracker.report()
            }
        }
        return true
    }

    private static func redeem(claim: String, nonce: String, runtime: Runtime) async {
        struct RedeemResult: Decodable {
            let token: String
            let expiresAt: Double?
        }
        do {
            let result: RedeemResult = try await APIClient.call(
                endpoint: runtime.endpoint,
                function: "redeemTesterClaim",
                payload: ["apiKey": runtime.apiKey, "claim": claim, "nonce": nonce]
            )
            AttestationStore.shared.setTesterToken(
                result.token,
                expiresAt: result.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
            )
        } catch let err as APIClient.CallableError {
            // A terminal signal here is as authoritative as one on the
            // config or submit paths — the same dispatch ADR-0003
            // Decision 9 §1 requires on *every* path that talks to the
            // callable. Anything else (a spent claim, a lapsed one, no
            // connection) leaves this install exactly as it was, which
            // is un-attested, which is silent.
            if let reason = err.sdkErrorReason, reason.isTerminal {
                LifecycleStore.shared.transitionToTerminated(
                    reason: reason,
                    callback: runtime.onConfigurationError
                )
            }
        } catch {
            // Transport. The tester can activate again.
        }
    }

    // MARK: - Internals

    /// Takes the pending handshake if there is a live one. Expired
    /// entries are dropped rather than honoured: the claim they are
    /// waiting for cannot still be valid.
    private static func takePending() -> Pending? {
        guard let current = pending else { return nil }
        pending = nil
        guard Date().timeIntervalSince(current.startedAt) <= pendingLifetime else { return nil }
        return current
    }

    /// 16 random bytes, base64url without padding — 22 characters,
    /// matching what the server's `TesterNonceSchema` bounds and what
    /// the companion echoes back untouched.
    static func makeNonce() -> String? {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Compares two nonces without leaking their divergence point in
    /// the time taken.
    ///
    /// The realistic attack is an app on the same device opening
    /// `<host bundle id>://issuetracker-attest/v1?...` with a guessed
    /// nonce, repeatedly. Nothing rate-limits that locally, so the
    /// comparison is the only thing standing in front of it, and an
    /// early-exit `==` would hand back a byte at a time.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8)
        let rhs = Array(b.utf8)
        // The length itself is not a secret — the nonce format is
        // published in the ADR — so comparing it directly costs
        // nothing.
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }

    private static func appNameItem() -> URLQueryItem? {
        let info = Bundle.main.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
        guard let name, !name.isEmpty else { return nil }
        return URLQueryItem(name: "app", value: name)
    }
}
