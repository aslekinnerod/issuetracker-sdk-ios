import Foundation

// Tracks whether the onboarding popover has been shown on this install.
// Persisted in UserDefaults.standard alongside ReporterIdentity — the
// SDK never shows the popover twice for the same user on the same
// install, unless the host app explicitly calls
// `Issuetracker.showOnboarding()` (which bypasses the flag).
//
// Cleared on app uninstall along with the rest of UserDefaults. There
// is no explicit "reset" API surface — re-onboarding after a real
// reinstall is the right UX.
enum OnboardingStore {
    private static let shownKey = "com.issuetracker.sdk.onboarding.shown"

    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: shownKey)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: shownKey)
    }
}
