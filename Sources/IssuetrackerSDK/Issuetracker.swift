import Foundation
import UIKit

// Public facade for the Issuetracker SDK. Apps integrate by calling
// `configure(apiKey:endpoint:)` once at launch; everything else is
// driven by shake-to-report plus the optional programmatic `report()`
// trigger. The type is `enum` with static members so there's no
// instance to retain — same shape as Firebase's own SDKs.
public enum Issuetracker {
    @MainActor
    private static var runtime: Runtime?

    /// Call once, as early as possible (e.g. `App.init`). The key and
    /// endpoint are stored for the lifetime of the app; subsequent
    /// calls replace the configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Raw API key created in the Issuetracker web UI.
    ///   - endpoint: Firebase Functions base URL, e.g.
    ///     `https://europe-west1-<project>.cloudfunctions.net`.
    ///   - shakeToReport: If `true` (default), a device shake brings up
    ///     the reporter from anywhere in the app.
    ///   - enableCrashReporting: If `true` (default), the SDK writes a
    ///     session-alive marker at launch and auto-sends a crash
    ///     report on the next launch if the previous session ended
    ///     without calling willTerminate (crash, OOM kill, or
    ///     force-quit).
    @MainActor
    public static func configure(
        apiKey: String,
        endpoint: URL,
        shakeToReport: Bool = true,
        enableCrashReporting: Bool = true
    ) {
        let rt = Runtime(apiKey: apiKey, endpoint: endpoint)
        runtime = rt
        if shakeToReport {
            ShakeObserver.install { Self.report() }
        }
        if enableCrashReporting {
            // Must run BEFORE anything else starts touching the
            // breadcrumb store in this session — CrashReporter reads
            // and clears crumbs from the crashed session before the
            // new one starts writing.
            CrashReporter.reportCrashIfAny(runtime: rt)
            // MetricKit delivers its own, slower but richer crash
            // diagnostics independently. Subscribing here means we
            // pick them up any time during this session.
            MetricKitSubscriber.shared.start(runtime: rt)
        }
    }

    /// Programmatically triggers the reporter — useful for a "report
    /// a bug" button in your app's settings.
    @MainActor
    public static func report() {
        guard let runtime else {
            assertionFailure("Issuetracker.report() called before configure()")
            return
        }
        ReportingSession.present(runtime: runtime)
    }

    /// Sets the display name shown on reports submitted from this
    /// install. Call this if your app already knows who the user is
    /// (e.g. after login) — the SDK will skip the "What should we
    /// call you?" prompt the first time a user triggers a report.
    /// Safe to call before `configure()`.
    public static func identify(name: String) {
        ReporterIdentity.setName(name)
    }

    /// Clears the stored display name. The next report will re-prompt
    /// the user. The anonymous install ID is preserved so the server
    /// can still group reports from this install.
    public static func clearIdentity() {
        ReporterIdentity.clearName()
    }

    /// Records a single user action. The SDK keeps the most recent 5
    /// and attaches them to any report the user submits (and, when
    /// enabled, to an auto-generated crash report on the next launch).
    ///
    /// Safe to call before `configure()` — breadcrumbs are persisted
    /// locally and will be included in the next report.
    ///
    /// - Parameters:
    ///   - action: Short identifier — e.g. `"login_tapped"` or
    ///     `"viewed_product"`. Truncated to 80 chars.
    ///   - metadata: Optional string:string pairs for richer context.
    ///     Truncated to 5 entries, 64-char keys, 256-char values.
    public static func recordAction(
        _ action: String,
        metadata: [String: String]? = nil
    ) {
        BreadcrumbStore.shared.record(action, metadata: metadata)
    }

    /// Deliberately crashes the app so you can verify the
    /// auto-generated crash report flows through on the next launch.
    /// Only intended for SDK integration testing — do not ship calls
    /// to this from production code.
    public static func _testCrash() -> Never {
        fatalError("Issuetracker._testCrash() triggered")
    }
}

struct Runtime {
    let apiKey: String
    let endpoint: URL
}

/// Issue classification sent to the server. Raw values match the
/// server-side `IssueType` enum so we can transmit over the wire as
/// plain strings without depending on the shared schema package.
public enum IssueReportType: String, CaseIterable, Sendable {
    case bug
    case task
    case story

    public var displayName: String {
        switch self {
        case .bug: return "Bug"
        case .task: return "Task"
        case .story: return "Story"
        }
    }

    public var icon: String {
        switch self {
        case .bug: return "ant.fill"
        case .task: return "checkmark.square"
        case .story: return "book.closed"
        }
    }
}
