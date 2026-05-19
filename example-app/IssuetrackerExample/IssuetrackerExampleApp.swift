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

@main
struct IssuetrackerExampleApp: App {
    init() {
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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
