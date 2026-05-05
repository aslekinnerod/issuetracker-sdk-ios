import Foundation
import MetricKit

// Subscribes to MetricKit's diagnostic payloads. The system delivers
// crash + hang diagnostics within 24h of the event, so this is a
// slower path than CrashDetector's heartbeat — but gives us the
// actual exception name/reason and call stacks when the heartbeat
// can only say "something went wrong".
//
// Heartbeat and MetricKit can both fire for the same crash and
// produce two separate issues. That's acceptable for MVP; triagers
// can link manually. Dedup by incident-id is future work.
@MainActor
final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitSubscriber()

    private var runtime: Runtime?

    func start(runtime: Runtime) {
        self.runtime = runtime
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        // We don't use metric (perf) payloads — only diagnostic.
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Task { @MainActor in
            guard let runtime else { return }
            for payload in payloads {
                for crash in payload.crashDiagnostics ?? [] {
                    await sendCrash(runtime: runtime, crash: crash, payload: payload)
                }
            }
        }
    }

    private func sendCrash(
        runtime: Runtime,
        crash: MXCrashDiagnostic,
        payload: MXDiagnosticPayload
    ) async {
        let metaData = crash.metaData
        let name = crash.exceptionType?.stringValue
        // MXCrashDiagnostic.exceptionReason landed in iOS 17. Older
        // systems still deliver a crash via MetricKit, we just skip
        // the reason line.
        let reason: String? = {
            if #available(iOS 17, *) {
                return crash.exceptionReason?.composedMessage
            }
            return nil
        }()
        var description = "System-reported crash from MetricKit.\n\n"
        if let name { description += "Exception: \(name)\n" }
        if let reason, !reason.isEmpty { description += "Reason: \(reason)\n" }
        if let signal = crash.signal?.intValue {
            description += "Signal: \(signal)\n"
        }
        description += "App version: \(metaData.applicationBuildVersion)\n"
        description += "OS: \(metaData.osVersion)\n"

        // MetricKit's JSON representation is reasonably compact; we
        // cap at 20 KB to match the schema.
        let json = String(data: payload.jsonRepresentation(), encoding: .utf8) ?? ""
        let capped = String(json.prefix(20_000))

        var crashReport: [String: Any] = [
            "detectedAt": Int(Date().timeIntervalSince1970 * 1000),
            "metricPayload": capped,
        ]
        if let name { crashReport["exceptionName"] = name }
        if let reason, !reason.isEmpty { crashReport["exceptionReason"] = reason }

        let payloadDict: [String: Any] = [
            "apiKey": runtime.apiKey,
            "title": "System-reported crash (\(name ?? "unknown"))",
            "type": "bug",
            "description": description,
            "context": ContextCollector.collect(),
            "reporter": ReporterIdentity.payload(),
            "crashReport": crashReport,
        ]

        struct CreateResult: Decodable { let issueId: String }
        do {
            let _: CreateResult = try await APIClient.call(
                endpoint: runtime.endpoint,
                function: "createIssueFromSdk",
                payload: payloadDict
            )
        } catch {
            print("[Issuetracker] MetricKit crash upload failed: \(error)")
        }
    }
}
