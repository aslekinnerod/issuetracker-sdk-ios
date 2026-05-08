import Foundation
import MetricKit

// Owns the decision to promote pending crash markers into real issues.
//
// Two MetricKit signals matter:
//
//  - MXCrashDiagnostic (MXDiagnosticPayload): per-event, has exception
//    type and call stack. Authoritative when present, but only ~20–30%
//    of users opt in to share diagnostics.
//
//  - MXAppExitMetric (MXMetricPayload): aggregated 24h counters split
//    by foreground/background, no opt-in required. We use it to tell
//    whether a pending marker corresponds to a crashy exit (memory
//    pressure, watchdog, bad access, etc.) or a benign one (normal
//    exit, force-quit).
//
// A pending marker is matched to a payload when the marker's startedAt
// falls inside [timeStampBegin, timeStampEnd]. Markers that never get
// matched within the retention window are pruned silently.
@MainActor
final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitSubscriber()

    private var runtime: Runtime?

    func start(runtime: Runtime) {
        self.runtime = runtime
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        Task { @MainActor in
            guard let runtime else { return }
            for payload in payloads {
                handleMetricPayload(payload, runtime: runtime)
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in
            guard let runtime else { return }
            for payload in payloads {
                handleDiagnosticPayload(payload, runtime: runtime)
            }
        }
    }

    private func handleDiagnosticPayload(
        _ payload: MXDiagnosticPayload,
        runtime: Runtime
    ) {
        guard let crashes = payload.crashDiagnostics, !crashes.isEmpty else {
            return
        }
        var pending = PendingCrashStore.shared.list()
        let json = String(data: payload.jsonRepresentation(), encoding: .utf8) ?? ""
        let cappedPayload = String(json.prefix(20_000))

        for crash in crashes {
            let exceptionName = crash.exceptionType?.stringValue
            let exceptionReason: String? = {
                if #available(iOS 17, *) {
                    return crash.exceptionReason?.composedMessage
                }
                return nil
            }()
            let signal = crash.signal?.intValue

            // Take the most recent pending marker whose session falls
            // inside this payload's window — that's the best guess at
            // which session this crash came from. Drop it from the
            // working set so a second crash in the same payload picks
            // a different marker.
            let matched = popBestMatch(
                from: &pending,
                payloadStart: payload.timeStampBegin,
                payloadEnd: payload.timeStampEnd,
                appVersion: crash.metaData.applicationBuildVersion
            )

            let cause = ConfirmedCrashCause.crashDiagnostic(
                exceptionName: exceptionName,
                exceptionReason: exceptionReason,
                signal: signal,
                payloadJSON: cappedPayload
            )

            if let matched {
                Task.detached {
                    await CrashReporter.sendConfirmedCrash(
                        runtime: runtime,
                        marker: matched,
                        cause: cause
                    )
                }
                PendingCrashStore.shared.remove(sessionId: matched.sessionId)
            } else {
                // No pending marker matched — diagnostic still lands as
                // an issue, just without breadcrumbs.
                let standalone = PendingCrashMarker(
                    sessionId: UUID().uuidString,
                    startedAt: payload.timeStampBegin,
                    endedAt: payload.timeStampEnd,
                    appVersion: crash.metaData.applicationBuildVersion,
                    osVersion: crash.metaData.osVersion,
                    lastLifecycleState: .active,
                    breadcrumbs: []
                )
                Task.detached {
                    await CrashReporter.sendConfirmedCrash(
                        runtime: runtime,
                        marker: standalone,
                        cause: cause
                    )
                }
            }
        }
    }

    private func handleMetricPayload(
        _ payload: MXMetricPayload,
        runtime: Runtime
    ) {
        guard let exitMetric = payload.applicationExitMetrics else { return }
        let pending = PendingCrashStore.shared.list().filter { marker in
            marker.startedAt >= payload.timeStampBegin
                && marker.startedAt <= payload.timeStampEnd
        }
        guard !pending.isEmpty else { return }

        let foregroundCrashy = crashyExitReason(in: exitMetric.foregroundExitData)
        let backgroundCrashy = crashyExitReason(in: exitMetric.backgroundExitData)

        for marker in pending {
            let isBackground = marker.lastLifecycleState == .background
            let reason = isBackground ? backgroundCrashy : foregroundCrashy

            if let reason {
                let cause = ConfirmedCrashCause.appExit(reason: reason)
                Task.detached {
                    await CrashReporter.sendConfirmedCrash(
                        runtime: runtime,
                        marker: marker,
                        cause: cause
                    )
                }
                PendingCrashStore.shared.remove(sessionId: marker.sessionId)
            } else {
                // Period had only normal/force-quit exits in the
                // relevant lifecycle bucket. Discard — this is exactly
                // the false-positive we set out to suppress.
                PendingCrashStore.shared.remove(sessionId: marker.sessionId)
            }
        }
    }

    private func crashyExitReason(in data: MXForegroundExitData) -> String? {
        // MXForegroundExitData has no cumulativeCPUResourceLimitExitCount —
        // CPU caps only apply to background work.
        if data.cumulativeMemoryResourceLimitExitCount > 0 { return "memory_resource_limit" }
        if data.cumulativeBadAccessExitCount > 0 { return "bad_access" }
        if data.cumulativeIllegalInstructionExitCount > 0 { return "illegal_instruction" }
        if data.cumulativeAppWatchdogExitCount > 0 { return "watchdog" }
        if data.cumulativeAbnormalExitCount > 0 { return "abnormal" }
        return nil
    }

    private func crashyExitReason(in data: MXBackgroundExitData) -> String? {
        if data.cumulativeMemoryResourceLimitExitCount > 0 { return "memory_resource_limit" }
        if data.cumulativeBadAccessExitCount > 0 { return "bad_access" }
        if data.cumulativeIllegalInstructionExitCount > 0 { return "illegal_instruction" }
        if data.cumulativeAppWatchdogExitCount > 0 { return "watchdog" }
        if data.cumulativeCPUResourceLimitExitCount > 0 { return "cpu_resource_limit" }
        if data.cumulativeAbnormalExitCount > 0 { return "abnormal" }
        // BackgroundTaskAssertionTimeout is not a crash — the system
        // gave the app a fixed time budget and it ran out.
        return nil
    }

    private func popBestMatch(
        from pending: inout [PendingCrashMarker],
        payloadStart: Date,
        payloadEnd: Date,
        appVersion: String
    ) -> PendingCrashMarker? {
        let candidates = pending.enumerated().filter { _, m in
            m.startedAt >= payloadStart
                && m.startedAt <= payloadEnd
                && (m.appVersion == nil || m.appVersion == appVersion)
        }
        // Most recent session in the window is the most likely owner
        // of this crash — sort descending by startedAt.
        guard let pick = candidates.max(by: { $0.element.startedAt < $1.element.startedAt }) else {
            return nil
        }
        let marker = pick.element
        pending.remove(at: pick.offset)
        return marker
    }
}
