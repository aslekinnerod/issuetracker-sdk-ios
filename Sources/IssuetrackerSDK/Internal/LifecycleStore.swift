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
    private static var _shared = LifecycleStore()

    /// Process-wide lifecycle. Every dispatch site (`AttestationStore`,
    /// `ReportingSession`, `CrashReporter`) and every trigger surface
    /// reads this instance.
    static var shared: LifecycleStore { _shared }

    #if DEBUG
    /// Test-only seam. The dispatch paths reach the lifecycle through
    /// ``shared``, so an end-to-end test of "server says the project is
    /// gone → SDK terminates" has to swap in a store backed by a
    /// throwaway `UserDefaults` suite — otherwise the one-way
    /// transition would leak into `UserDefaults.standard` and into
    /// every later test in the process. Returns the previous instance
    /// so the caller can restore it in `tearDown`. Compiled out of
    /// release builds.
    @discardableResult
    static func _swapSharedForTesting(_ store: LifecycleStore) -> LifecycleStore {
        let previous = _shared
        _shared = store
        return previous
    }
    #endif

    /// Posted (main queue) on the one-way OK → TERMINATED transition.
    /// Lets UI surfaces owned by the SDK (the ADR-0008 floating report
    /// button) tear themselves down without this Foundation-only state
    /// machine importing UIKit.
    static let terminatedNotification = Notification.Name("io.issuetracker.sdk.terminated")

    enum State: Sendable {
        case ok
        case suspended
        case terminated(reason: SdkErrorReason, at: Date)
    }

    private(set) var state: State

    private let defaults: UserDefaults
    private let reasonKey = "io.issuetracker.sdk.terminatedReason"
    private let atKey = "io.issuetracker.sdk.terminatedAt"

    init(defaults: UserDefaults = .standard) {
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
    ///
    /// Both halves of ADR-0003 Decision 9 §6 happen here, in this
    /// order: the `terminatedAt` marker is persisted first, then the
    /// on-disk queue is dropped. Marker-before-purge is the safe
    /// ordering — a process death between the two leaves an install
    /// that is already terminated (so it re-purges on the next
    /// `configure()` and never delivers), whereas purge-before-marker
    /// would leave an install that lost its queue but still believes
    /// it is `OK`.
    func transitionToTerminated(
        reason: SdkErrorReason,
        callback: ((SdkErrorReason) -> Void)?
    ) {
        guard !isTerminated else { return }
        let now = Date()
        state = .terminated(reason: reason, at: now)
        defaults.set(reason.rawValue, forKey: reasonKey)
        defaults.set(now.timeIntervalSince1970, forKey: atKey)
        purgeLocalQueue()
        NotificationCenter.default.post(name: Self.terminatedNotification, object: nil)
        callback?(reason)
    }

    /// Drops the SDK's on-disk delivery queue.
    ///
    /// Scope is deliberately narrow: only reports that are queued *for
    /// delivery to the now-dead project* go. `PendingCrashStore` is the
    /// SDK's sole such queue — crash markers awaiting MetricKit
    /// confirmation, addressed to the one bound project, on an install
    /// whose lifecycle is one-way. Nothing in it can ever be delivered
    /// again, so keeping it would only burn disk and risk a later
    /// delivery attempt.
    ///
    /// What is NOT purged, on purpose: breadcrumbs the host app
    /// recorded via `recordAction` (host-owned data, not a queued
    /// report), the reporter identity, and any report the user is
    /// composing right now — the submit path hands that user the
    /// terminal view instead of silently queueing a report that could
    /// never be sent. `CrashDetector`'s live session marker is cleared
    /// by `CrashReporter` rather than here, so this stays a
    /// Foundation-only state machine.
    private func purgeLocalQueue() {
        PendingCrashStore.shared.purgeAll()
    }
}
