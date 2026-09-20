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
    ///   - accessibilityAction: If `true`, and whenever VoiceOver is
    ///     running, the SDK registers a "Report a bug" accessibility
    ///     custom action on the key window's root view controller —
    ///     the screen-reader activation path for the reporter, since
    ///     VoiceOver claims multi-finger gestures and shake is not an
    ///     option for every user (WCAG 2.5.1/2.5.4, ADR-0008
    ///     Decision 2). The action is appended to (never replaces)
    ///     any custom actions the host app has set, follows key-window
    ///     changes, and is removed the moment VoiceOver stops or the
    ///     flag is re-configured off. Defaults to `false` so existing
    ///     integrators are unaffected.
    ///   - showReportButton: If `true`, shows a small SDK-provided
    ///     floating "Report" button (bottom-trailing, safe-area
    ///     aware) that opens the reporter — the no-code path to a
    ///     visible, single-pointer alternative to the gesture
    ///     triggers (ADR-0008 Decision 3). The button hides while the
    ///     reporter sheet or the recording stop pill is up, and is
    ///     removed for good when the SDK reaches the TERMINATED state
    ///     or the flag is re-configured off. Defaults to `false`;
    ///     hosts that prefer their own control should wire it to
    ///     ``Issuetracker/report()`` instead.
    ///   - enableCrashReporting: If `true` (default), the SDK detects
    ///     unexpectedly-ended sessions (crash, OOM kill, watchdog) and
    ///     opens an issue for them automatically. The decision is
    ///     deferred until MetricKit confirms the cause — Apple delivers
    ///     `MXCrashDiagnostic` and `MXAppExitMetric` 0–24h after the
    ///     event, on the next launch. Force-quits and normal exits are
    ///     suppressed silently.
    ///   - onConfigurationError: Optional callback invoked once when the
    ///     SDK transitions to the terminated state because the server
    ///     signalled a non-recoverable failure (project deleted, API
    ///     key revoked, workspace suspended, etc. — see
    ///     ``SdkErrorReason``). Default behaviour is silent in
    ///     production; host apps may forward this to their own
    ///     telemetry. Once invoked, the SDK makes no further network
    ///     calls for the lifetime of this install: it stops fetching
    ///     config, stops uploading crashes, drops its local queue, and
    ///     shows the terminal message to anyone who opens the reporting
    ///     surface. The state is persisted, one-way, and install-wide —
    ///     calling `configure(apiKey:)` again does NOT clear it, not
    ///     even with a different key. See ADR-0003 Decision 9.
    ///   - showOnboarding: If `true`, presents a one-time popover on
    ///     first launch that teaches the user which gestures trigger
    ///     the reporter — only the gestures currently enabled are
    ///     shown. Persisted per install via UserDefaults, so the
    ///   - attestationCallbackURLScheme: The URL scheme the companion
    ///     app answers on, which must be your own bundle identifier
    ///     (ADR-0005 Decision 11). Required only for projects using
    ///     tester-only reporting, and only on iOS. Three lines of
    ///     integration go with it, all in your Info.plist:
    ///     `LSApplicationQueriesSchemes` must list
    ///     `issuetracker-testers`, `CFBundleURLTypes` must register
    ///     `CFBundleURLSchemes = $(PRODUCT_BUNDLE_IDENTIFIER)`, and
    ///     your app must forward incoming URLs to
    ///     ``Issuetracker/handleAttestationCallback(_:)``. Leave it
    ///     nil and the SDK never opens the companion — which is the
    ///     right setting for every project in open mode.
    ///   - showOnboarding: If `true`, presents a one-time popover on
    ///     first launch that teaches the user which gestures trigger
    ///     the reporter — only the gestures currently enabled are
    ///     shown. Persisted per install via UserDefaults, so the
    ///     popover never appears twice unless the host app calls
    ///     ``Issuetracker/showOnboarding()`` explicitly. With both
    ///     `shakeToReport` and `longPressToReport` disabled the
    ///     popover is silently skipped — there's nothing to teach.
    ///     Defaults to `false` so existing integrators are unaffected.
    @MainActor
    public static func configure(
        apiKey: String,
        shakeToReport: Bool = true,
        longPressToReport: Bool = true,
        accessibilityAction: Bool = false,
        showReportButton: Bool = false,
        enableCrashReporting: Bool = true,
        onConfigurationError: ((SdkErrorReason) -> Void)? = nil,
        attestationCallbackURLScheme: String? = nil,
        showOnboarding: Bool = false,
        terminatedUI: TerminatedUiStrings? = nil
    ) {
        let rt = Runtime(
            apiKey: apiKey,
            endpoint: Runtime.resolveEndpoint(for: apiKey),
            onConfigurationError: onConfigurationError,
            terminatedUI: terminatedUI
        )
        runtime = rt
        // Seed remote config (testers-only gating, ADR-0005) from the
        // UserDefaults cache before the observers install, so the very
        // first gesture consults real data when we have any. The
        // network refresh runs async below.
        AttestationStore.shared.install(runtime: rt)
        CompanionHandshake.install(callbackURLScheme: attestationCallbackURLScheme)
        // Gesture triggers are gated per-fire rather than at install
        // time: config can flip while the app runs, and a fire-time
        // check reconciles instantly with no uninstall plumbing. In
        // testers-only mode without a token the gestures are silently
        // inert (ADR-0005 invariant 5). The programmatic report() is
        // deliberately ungated — a host app's own button should
        // surface the attestation message instead.
        if shakeToReport {
            ShakeObserver.install { Self.fireTrigger(runtime: rt) }
        }
        if longPressToReport {
            LongPressObserver.install { Self.fireTrigger(runtime: rt) }
        }
        // ADR-0008 accessible activation paths. Applied unconditionally
        // (unlike the fire-time-gated gestures) so a re-configure flips
        // them live in both directions — `false` tears down whatever an
        // earlier configure installed. Both funnel into the same
        // `report()` path as the host-app button the README asks for.
        AccessibilityActionObserver.setEnabled(accessibilityAction)
        FloatingReportButton.shared.setEnabled(showReportButton)

        // ADR-0003 Decision 9 §2: a TERMINATED install performs no
        // network calls and starts no background work, on this launch
        // or any future one. Everything below this point either talks
        // to the server or feeds something that eventually will, so it
        // is all skipped — the config refresh (otherwise a `getSdkConfig`
        // POST on every single launch, forever), the onboarding popover
        // (there is nothing left to teach), and the whole crash
        // pipeline (marker promotion + MetricKit subscription).
        //
        // The gesture triggers installed above deliberately stay: §5
        // requires that a tester who opens the reporting surface sees
        // the terminal message, and `ReportingSession.present` gates on
        // the same lifecycle to show it. Terminated means "stops
        // talking", not "goes silent on the tester".
        if LifecycleStore.shared.isTerminated {
            // Re-purge in case this install was terminated by an older
            // build that persisted the marker without dropping the
            // queue. Idempotent and disk-only.
            CrashReporter.reportCrashIfAny()
            return
        }

        Task { @MainActor in
            await AttestationStore.shared.refreshRemoteConfig(runtime: rt)
            // Onboarding waits for the config refresh so we never
            // advertise gestures that are gated off for this install —
            // and never wrongly suppress it on a prod key's first
            // launch just because the fail-closed default was still in
            // effect. A terminal error on that refresh flips the SDK
            // mid-launch, so re-check before advertising anything.
            if showOnboarding,
               !LifecycleStore.shared.isTerminated,
               AttestationStore.shared.canTriggerReport {
                OnboardingPresenter.presentIfNeeded(
                    shakeEnabled: shakeToReport,
                    longPressEnabled: longPressToReport
                )
            }
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

    /// Re-presents the onboarding popover regardless of whether it
    /// has been shown before on this install. Intended for a "Show
    /// introduction again"-style entry in the host app's own settings
    /// screen. Calling this with both gestures disabled is a no-op —
    /// there is nothing to teach. Must be called after
    /// ``configure(apiKey:shakeToReport:longPressToReport:accessibilityAction:showReportButton:enableCrashReporting:onConfigurationError:showOnboarding:terminatedUI:)``.
    @MainActor
    public static func showOnboarding() {
        guard let runtime else {
            assertionFailure("Issuetracker.showOnboarding() called before configure()")
            return
        }
        _ = runtime
        // The runtime carries the configured-trigger state implicitly
        // via the observers installed at configure-time. We re-derive
        // from the installed observers rather than threading another
        // flag through Runtime, so a single source of truth governs
        // both runtime behaviour and onboarding content.
        OnboardingPresenter.presentForced(
            shakeEnabled: ShakeObserver.isInstalled,
            longPressEnabled: LongPressObserver.isInstalled
        )
    }

    /// What a gesture trigger actually does.
    ///
    /// Three outcomes, and the middle one is the whole iOS handshake:
    ///
    ///  - attested (or open mode): open the reporter, as always;
    ///  - testers-only, no token, **and the companion app is
    ///    installed**: start the handshake, and open the reporter when
    ///    it comes back attested;
    ///  - anything else: nothing at all.
    ///
    /// The third case is ADR-0005 invariant 5 — triggers are silently
    /// inert for anyone who is not a tester, with no UI and no hint
    /// the SDK is there. The second case is why `canOpenURL` exists in
    /// this design: someone with the companion installed is plausibly
    /// a tester, and someone without it is not, so presence is what
    /// decides whether activation is offered at all.
    ///
    /// Without this the feature would be unreachable: a tester whose
    /// gestures are inert until they hold a token, and who can only
    /// get a token through a gesture, has no way in.
    @MainActor
    private static func fireTrigger(runtime: Runtime) {
        if AttestationStore.shared.canTriggerReport {
            Self.report()
            return
        }
        CompanionHandshake.offerIfNeeded(runtime: runtime, resumeReport: true)
    }

    /// Hands the SDK a URL your app was opened with, and returns
    /// whether it was one of ours.
    ///
    /// Call it from `onOpenURL` (SwiftUI) or
    /// `application(_:open:options:)` (UIKit) and pass every URL
    /// through — the SDK recognises its own and ignores the rest, so
    /// there is nothing to match on first:
    ///
    /// ```swift
    /// .onOpenURL { url in
    ///     Issuetracker.handleAttestationCallback(url)
    /// }
    /// ```
    ///
    /// Required only alongside
    /// `configure(attestationCallbackURLScheme:)`. Returning `true`
    /// means the SDK consumed the URL; it does **not** mean
    /// activation succeeded, and there is deliberately no callback
    /// for that — a tester who was refused has already been told why
    /// by the companion app, on its own screen, and the host app must
    /// not show anything to someone who turns out not to be a tester.
    @MainActor
    @discardableResult
    public static func handleAttestationCallback(_ url: URL) -> Bool {
        CompanionHandshake.handle(url, runtime: runtime)
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

    /// Stores a tester attestation token (ADR-0005). On projects in
    /// testers-only mode this is what unlocks the report triggers and
    /// gets reports past the server; in open mode it stamps reports
    /// with the tester's identity. The token normally arrives via the
    /// companion-app enrollment handshake; this API is the manual
    /// injection point until that ships (and for integration tests).
    @MainActor
    public static func setTesterToken(_ token: String, expiresAt: Date? = nil) {
        AttestationStore.shared.setTesterToken(token, expiresAt: expiresAt)
    }

    /// Removes the stored tester token. On testers-only projects the
    /// gesture triggers go inert again from the next gesture.
    @MainActor
    public static func clearTesterToken() {
        AttestationStore.shared.clearTesterToken()
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

/// Strings shown when the SDK has been terminated and a test-cohort
/// user opens the reporting surface. ADR-0003 Decision 9 mandates a
/// localised terminal message; English is the built-in default, and
/// host apps may inject translations via ``Issuetracker/configure(apiKey:...)``.
///
/// Each field is optional — fields the host doesn't override fall
/// back to English. A missing entire struct falls back to all-English.
public struct TerminatedUiStrings: Sendable {
    /// Big headline. Default: `"Bug reporting is no longer available."`
    public let title: String?
    /// One-line follow-up. Default: `"Contact your team."`
    public let subtitle: String?
    /// Close-button label. Default: `"Close"`.
    public let closeLabel: String?

    public init(title: String? = nil, subtitle: String? = nil, closeLabel: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.closeLabel = closeLabel
    }
}

struct Runtime {
    let apiKey: String
    let endpoint: URL
    // Invoked exactly once, on the OK → TERMINATED transition. Stored
    // here (rather than in LifecycleStore) because it's a configure-
    // time setting that the user owns; the store is the state machine.
    let onConfigurationError: ((SdkErrorReason) -> Void)?
    let terminatedUI: TerminatedUiStrings?

    // Routing is derived from the key prefix so integrators never see
    // any URL — they just paste the key the web UI gave them.
    //   it_dev_*      → dev backend (internal use only)
    //   it_staging_*  → staging backend
    //   it_*          → production (brand-domain)
    static func resolveEndpoint(for apiKey: String) -> URL {
        if apiKey.hasPrefix("it_dev_") {
            return URL(string: "https://issuetracker-api-dev.web.app/v1")!
        }
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
