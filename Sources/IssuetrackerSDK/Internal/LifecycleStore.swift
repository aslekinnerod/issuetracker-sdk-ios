import Foundation

/// One-way SDK lifecycle state. See ADR-0003 Decision 9.
///
/// Starts in ``State/ok``. The first non-recoverable server error
/// transitions to ``State/terminated`` and the SDK stays there for
/// the lifetime of the install — recovery requires an explicit
/// host-app re-init, never a poll, so a deployed cohort cannot
/// hammer a dead endpoint regardless of scale.
///
/// ``State/suspended`` is reserved for a future per-report retry
/// queue (Phase B+/C) and is not produced today; recoverable
/// errors keep the SDK in ``State/ok`` and rely on the user
/// retrying via the existing UI.
@MainActor
final class LifecycleStore {
    static let shared = LifecycleStore()

    enum State: Sendable {
        case ok
        case suspended
        case terminated(reason: SdkErrorReason, at: Date)
    }

    private(set) var state: State

    private let defaults: UserDefaults
    private let reasonKey = "io.issuetracker.sdk.terminatedReason"
    private let atKey = "io.issuetracker.sdk.terminatedAt"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Restore from disk so a process restart doesn't re-attempt
        // delivery against an endpoint the server has already told us
        // is gone.
        if let raw = defaults.string(forKey: reasonKey),
           let reason = SdkErrorReason(rawValue: raw) {
            let at = defaults.double(forKey: atKey)
            self.state = .terminated(
                reason: reason,
                at: Date(timeIntervalSince1970: at)
            )
        } else {
            self.state = .ok
        }
    }

    var isTerminated: Bool {
        if case .terminated = state { return true }
        return false
    }

    /// Idempotent: re-terminating with a different reason keeps the
    /// first one. The first non-recoverable failure is authoritative;
    /// later failures should have been gated and only happen if a
    /// pre-flight check missed the state.
    func transitionToTerminated(
        reason: SdkErrorReason,
        callback: ((SdkErrorReason) -> Void)?
    ) {
        guard !isTerminated else { return }
        let now = Date()
        state = .terminated(reason: reason, at: now)
        defaults.set(reason.rawValue, forKey: reasonKey)
        defaults.set(now.timeIntervalSince1970, forKey: atKey)
        callback?(reason)
    }
}
