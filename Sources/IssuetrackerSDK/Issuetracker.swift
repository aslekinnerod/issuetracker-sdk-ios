import Foundation
import UIKit

// Public facade for the Issuetracker SDK. Apps integrate by calling
// `configure(apiKey:)` once at launch; everything else is driven by
// shake-to-report plus the optional programmatic `report()` trigger.
// The type is `enum` with static members so there's no instance to
// retain — same shape as Firebase's own SDKs.
public enum Issuetracker {
    @MainActor
    private static var runtime: Runtime?

    /// Call once, as early as possible (e.g. `App.init`). The key is
    /// stored for the lifetime of the app; subsequent calls replace
    /// the configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Raw API key created in the Issuetracker web UI.
    ///     The environment (production vs. staging) is derived from
    ///     the key prefix — there is no endpoint to configure.
    ///   - shakeToReport: If `true` (default), a device shake brings up
    ///     the reporter from anywhere in the app.
    ///   - longPressToReport: If `true` (default), a two-finger
    ///     long-press for 3 seconds anywhere in the app brings up the
    ///     reporter. Same gesture as the web SDK uses on touch
    ///     devices, so users only learn one trigger across platforms.
    ///   - enableCrashReporting: If `true` (default), the SDK detects
    ///     unexpectedly-ended sessions (crash, OOM kill, watchdog) and
    ///     opens an issue for them automatically. The decision is
    ///     deferred until MetricKit confirms the cause — Apple delivers
    ///     `MXCrashDiagnostic` and `MXAppExitMetric` 0–24h after the
    ///     event, on the next launch. Force-quits and normal exits are
    ///     suppressed silently.
    @MainActor
    public static func configure(
        apiKey: String,
        shakeToReport: Bool = true,
        longPressToReport: Bool = true,
        enableCrashReporting: Bool = true
    ) {
        let rt = Runtime(apiKey: apiKey, endpoint: Runtime.resolveEndpoint(for: apiKey))
        runtime = rt
        if shakeToReport {
            ShakeObserver.install { Self.report() }
        }
        if longPressToReport {
            LongPressObserver.install { Self.report() }
        }
        if enableCrashReporting {
            // Must run BEFORE anything else starts touching the
            // breadcrumb store in this session — the previous
            // session's crumbs are captured here and moved into the
            // pending marker before the new session overwrites them.
            CrashReporter.reportCrashIfAny()
            // MetricKit delivers crash diagnostics and exit metrics
            // 0–24h after the event. The subscriber owns the decision
            // to promote pending markers into issues — heartbeat alone
            // can't tell crashes from force-quits.
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
    /// and attaches them to any report the user submits, and to any
    /// auto-generated crash report (which lands once MetricKit confirms
    /// the previous session crashed — typically within 24h).
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
    /// auto-generated crash report flow. The crash is detected by
    /// MetricKit, so the resulting issue lands 0–24h after the next
    /// launch — not immediately. Run on a real device; MetricKit does
    /// not deliver in the simulator. Only intended for SDK integration
    /// testing — do not ship calls to this from production code.
    public static func _testCrash() -> Never {
        fatalError("Issuetracker._testCrash() triggered")
    }
}

struct Runtime {
    let apiKey: String
    let endpoint: URL

    // Staging-prefixed keys hit the staging environment; everything
    // else hits production. Integrators never see either URL — they
    // just paste the key the web UI gave them.
    static func resolveEndpoint(for apiKey: String) -> URL {
        if apiKey.hasPrefix("it_staging_") {
            return URL(string: "https://issuetracker-api-staging.web.app/v1")!
        }
        return URL(string: "https://api.issuetracker.no/v1")!
    }
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
