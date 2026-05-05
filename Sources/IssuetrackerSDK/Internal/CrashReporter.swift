import Foundation

// Ties together CrashDetector + BreadcrumbStore + APIClient. On
// configure, if the previous session didn't reach willTerminate, we
// build an auto-report and POST it to createIssueFromSdk.
@MainActor
enum CrashReporter {

    // Called from Issuetracker.configure. Fires-and-forgets in a Task
    // so app startup isn't blocked on the network round-trip. A
    // failure just leaves the marker in place — next launch retries.
    static func reportCrashIfAny(runtime: Runtime) {
        guard let marker = CrashDetector.shared.readUnfinishedSession() else {
            // Clean previous shutdown; nothing to report. Just start
            // a fresh session.
            CrashDetector.shared.startNewSession()
            return
        }

        // Grab breadcrumbs from the crashed session before we clear
        // them for the new one.
        let crumbs = BreadcrumbStore.shared.snapshot()
        BreadcrumbStore.shared.clear()
        CrashDetector.shared.startNewSession()
        CrashDetector.shared.clearUnfinishedMarker()

        Task.detached {
            await sendCrashReport(runtime: runtime, marker: marker, breadcrumbs: crumbs)
        }
    }

    private static func sendCrashReport(
        runtime: Runtime,
        marker: SessionMarker,
        breadcrumbs: [Breadcrumb]
    ) async {
        let description = buildDescription(marker: marker, breadcrumbs: breadcrumbs)
        var payload: [String: Any] = [
            "apiKey": runtime.apiKey,
            "title": "Crash in previous session",
            "type": "bug",
            "description": description,
            "context": await MainActor.run { ContextCollector.collect() },
            "reporter": ReporterIdentity.payload(),
            "crashReport": [
                "detectedAt": Int(Date().timeIntervalSince1970 * 1000),
            ] as [String: Any],
        ]
        if !breadcrumbs.isEmpty {
            payload["breadcrumbs"] = breadcrumbs.map { b -> [String: Any] in
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

        struct CreateResult: Decodable { let issueId: String }
        do {
            let _: CreateResult = try await APIClient.call(
                endpoint: runtime.endpoint,
                function: "createIssueFromSdk",
                payload: payload
            )
        } catch {
            print("[Issuetracker] crash report upload failed: \(error)")
        }
    }

    private static func buildDescription(
        marker: SessionMarker,
        breadcrumbs: [Breadcrumb]
    ) -> String {
        var lines: [String] = []
        lines.append("The previous app session ended unexpectedly.")
        lines.append("")
        lines.append("Session ID: \(marker.sessionId)")
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        lines.append("Started: \(df.string(from: marker.startedAt))")
        if let appVersion = marker.appVersion {
            lines.append("App version: \(appVersion)")
        }
        if let osVersion = marker.osVersion {
            lines.append("iOS: \(osVersion)")
        }
        if !breadcrumbs.isEmpty {
            lines.append("")
            lines.append("Recent actions (oldest first):")
            for b in breadcrumbs {
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
