import Foundation

// At configure-time, we don't know whether last session ended in a
// real crash or in a force-quit/normal exit. So instead of POSTing
// immediately (which produced a flood of false positives), we move
// the stale marker to PendingCrashStore and let MetricKitSubscriber
// decide later — when it sees an MXAppExitMetric or MXCrashDiagnostic
// covering the same period — whether to promote the pending marker
// to a real issue or discard it.
@MainActor
enum CrashReporter {

    static func reportCrashIfAny() {
        // ADR-0003 Decision 9 §2 + §6. A terminated install must not
        // start crash tracking at all: promoting last session's marker
        // into PendingCrashStore here is what *repopulates* the queue
        // on every launch, so the purge done at the transition would
        // otherwise be undone by the very next `configure()`. Re-purge
        // (cheap, idempotent) to catch an install that was terminated
        // by a build without the transition-time purge, and drop the
        // live session marker so nothing is left to promote later.
        guard !LifecycleStore.shared.isTerminated else {
            PendingCrashStore.shared.purgeAll()
            CrashDetector.shared.clearUnfinishedMarker()
            return
        }

        if let marker = CrashDetector.shared.readUnfinishedSession() {
            let crumbs = BreadcrumbStore.shared.snapshot()
            BreadcrumbStore.shared.clear()
            PendingCrashStore.shared.add(PendingCrashMarker(
                sessionId: marker.sessionId,
                startedAt: marker.startedAt,
                endedAt: marker.endedAt,
                appVersion: marker.appVersion,
                osVersion: marker.osVersion,
                lastLifecycleState: marker.lastLifecycleState,
                breadcrumbs: crumbs
            ))
            CrashDetector.shared.startNewSession()
            CrashDetector.shared.clearUnfinishedMarker()
        } else {
            CrashDetector.shared.startNewSession()
        }

        PendingCrashStore.shared.prune()
    }

    static func sendConfirmedCrash(
        runtime: Runtime,
        marker: PendingCrashMarker,
        cause: ConfirmedCrashCause
    ) async {
        // ADR-0003 Decision 9 §2 pre-flight gate, the twin of the one
        // in `ReportingSession.present`. MetricKit delivers 0–24h after
        // the event and calls straight in here, so without this a
        // terminated install keeps POSTing `createIssueFromSdk` from
        // the background where no manual test would ever see it.
        guard !LifecycleStore.shared.isTerminated else { return }

        let description = buildDescription(marker: marker, cause: cause)
        var crashReport: [String: Any] = [
            "detectedAt": Int(Date().timeIntervalSince1970 * 1000),
            "sessionId": marker.sessionId,
            "cause": cause.wireValue,
        ]
        if let extra = cause.metricPayloadJSON {
            crashReport["metricPayload"] = extra
        }
        if let exceptionName = cause.exceptionName {
            crashReport["exceptionName"] = exceptionName
        }
        if let exceptionReason = cause.exceptionReason {
            crashReport["exceptionReason"] = exceptionReason
        }

        var payload: [String: Any] = [
            "apiKey": runtime.apiKey,
            "title": cause.title,
            "type": "bug",
            "description": description,
            "context": await MainActor.run { ContextCollector.collect() },
            "reporter": ReporterIdentity.payload(),
            "crashReport": crashReport,
        ]
        if !marker.breadcrumbs.isEmpty {
            payload["breadcrumbs"] = marker.breadcrumbs.map { b -> [String: Any] in
                var dict: [String: Any] = [
                    "timestamp": Int(b.timestamp.timeIntervalSince1970 * 1000),
                    "action": b.action,
                ]
                if let metadata = b.metadata {
                    dict["metadata"] = metadata
                }
                return dict
            }
        }
        // Auto crash reports carry attestation too — on testers-only
        // projects an unattested crash report is (correctly) rejected
        // at ingest, and the catch below drops it silently.
        if let testerToken = await MainActor.run(body: { AttestationStore.shared.testerToken }) {
            payload["testerToken"] = testerToken
        }

        struct CreateResult: Decodable { let issueId: String }
        do {
            let _: CreateResult = try await APIClient.call(
                endpoint: runtime.endpoint,
                function: "createIssueFromSdk",
                payload: payload
            )
        } catch let err as APIClient.CallableError {
            // ADR-0003 Decision 9 §1: dispatch on `details.error`, not
            // on the HTTP status, and do it on *every* path that talks
            // to the callable — a project deleted while the app was
            // backgrounded is first learned about here, and swallowing
            // it left the SDK live until some later foreground submit
            // happened to hit the same wall. Same predicate
            // (`SdkErrorReason.isTerminal`) as the config and submit
            // paths, so tester-gating rejections (ADR-0005) stay
            // non-terminal here too: an unattested crash upload is
            // correctly rejected without killing the install.
            if let reason = err.sdkErrorReason, reason.isTerminal {
                LifecycleStore.shared.transitionToTerminated(
                    reason: reason,
                    callback: runtime.onConfigurationError
                )
            }
            print("[Issuetracker] crash report upload failed: \(err)")
        } catch {
            print("[Issuetracker] crash report upload failed: \(error)")
        }
    }

    private static func buildDescription(
        marker: PendingCrashMarker,
        cause: ConfirmedCrashCause
    ) -> String {
        var lines: [String] = []
        lines.append(cause.descriptionHeadline)
        lines.append("")
        lines.append("Session ID: \(marker.sessionId)")
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        lines.append("Started: \(df.string(from: marker.startedAt))")
        if let endedAt = marker.endedAt {
            lines.append("Last seen: \(df.string(from: endedAt))")
        }
        lines.append("Last state: \(marker.lastLifecycleState.rawValue)")
        if let appVersion = marker.appVersion {
            lines.append("App version: \(appVersion)")
        }
        if let osVersion = marker.osVersion {
            lines.append("iOS: \(osVersion)")
        }
        if !marker.breadcrumbs.isEmpty {
            lines.append("")
            lines.append("Recent actions (oldest first):")
            for b in marker.breadcrumbs {
                var line = "- [\(df.string(from: b.timestamp))] \(b.action)"
                if let metadata = b.metadata, !metadata.isEmpty {
                    let pairs = metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
                    line += " (\(pairs))"
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct ConfirmedCrashCause {
    let title: String
    let descriptionHeadline: String
    let wireValue: String
    let exceptionName: String?
    let exceptionReason: String?
    let metricPayloadJSON: String?

    static func crashDiagnostic(
        exceptionName: String?,
        exceptionReason: String?,
        signal: Int?,
        payloadJSON: String?
    ) -> ConfirmedCrashCause {
        var headline = "System-reported crash from MetricKit."
        if let exceptionName {
            headline += "\n\nException: \(exceptionName)"
        }
        if let exceptionReason, !exceptionReason.isEmpty {
            headline += "\nReason: \(exceptionReason)"
        }
        if let signal {
            headline += "\nSignal: \(signal)"
        }
        return ConfirmedCrashCause(
            title: "Crash (\(exceptionName ?? "unknown"))",
            descriptionHeadline: headline,
            wireValue: "crash_diagnostic",
            exceptionName: exceptionName,
            exceptionReason: exceptionReason,
            metricPayloadJSON: payloadJSON
        )
    }

    static func appExit(reason: String) -> ConfirmedCrashCause {
        ConfirmedCrashCause(
            title: "Crash (\(reason))",
            descriptionHeadline: "System-reported abnormal exit (\(reason)). No symbolicated stack available — Apple did not deliver a crash diagnostic for this session.",
            wireValue: "app_exit_\(reason)",
            exceptionName: nil,
            exceptionReason: nil,
            metricPayloadJSON: nil
        )
    }
}
