import SwiftUI
import IssuetrackerSDK

// Replace with a real key from the Issuetracker admin UI. The
// placeholder will trip the SDK's terminal path with invalid_api_key
// on the first report — useful for demoing the TERMINATED flow if
// you leave it in. For day-to-day work, copy this file to
// IssuetrackerExampleApp.local.swift (gitignore it) and edit the
// key there.
let API_KEY = "it_staging_REPLACE_ME"

let PREF_USE_NORWEGIAN = "useNorwegianTerminatedUI"
let PREF_LAST_ERROR = "lastConfigError"
let PREF_LAST_ERROR_AT = "lastConfigErrorAt"
let PREF_A11Y_ACTION = "accessibilityActionEnabled"
let PREF_SHOW_REPORT_BUTTON = "showReportButtonEnabled"

/// Single configure entry point. Called once from `App.init` and
/// again by the Accessibility section's toggles — the ADR-0008 flags
/// (and the trigger flags) apply live on re-configure, so the demo
/// re-reads all prefs and reconfigures in place.
@MainActor
func configureSdk() {
    let prefs = UserDefaults.standard
    let useNorwegian = prefs.bool(forKey: PREF_USE_NORWEGIAN)

    let terminatedUI: TerminatedUiStrings? = useNorwegian
        ? TerminatedUiStrings(
            title: "Feilrapportering er ikke lenger tilgjengelig.",
            subtitle: "Kontakt teamet ditt.",
            closeLabel: "Lukk"
        )
        : nil

    Issuetracker.configure(
        apiKey: API_KEY,
        shakeToReport: true,
        longPressToReport: true,
        accessibilityAction: prefs.bool(forKey: PREF_A11Y_ACTION),
        showReportButton: prefs.bool(forKey: PREF_SHOW_REPORT_BUTTON),
        enableCrashReporting: true,
        onConfigurationError: { reason in
            // Persist so the Lifecycle section can show what fired
            // after the next launch. The SDK has already
            // transitioned to TERMINATED by this point.
            prefs.set(reason.rawValue, forKey: PREF_LAST_ERROR)
            prefs.set(Date().timeIntervalSince1970, forKey: PREF_LAST_ERROR_AT)
        },
        showOnboarding: true,
        terminatedUI: terminatedUI
    )
}

@main
struct IssuetrackerExampleApp: App {
    init() {
        configureSdk()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
