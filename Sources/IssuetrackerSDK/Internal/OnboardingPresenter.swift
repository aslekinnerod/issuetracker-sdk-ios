import SwiftUI
import UIKit

// Owns the lifetime of the onboarding popover. The hosting controller
// must be retained for as long as it's on screen; once the user taps
// "Got it" we dismiss + drop the reference.
//
// Two entry points:
// - `presentIfNeeded(...)` is the configure-time path: checks the
//   "has been shown" flag, drops out silently if the user has seen
//   it before or if both gestures are disabled.
// - `presentForced(...)` is the public `Issuetracker.showOnboarding()`
//   path: bypasses the flag but still respects the both-gestures-
//   disabled no-op (there's literally nothing to teach).
enum OnboardingPresenter {
    @MainActor
    private static var presented = false

    @MainActor
    static func presentIfNeeded(shakeEnabled: Bool, longPressEnabled: Bool) {
        guard !OnboardingStore.hasBeenShown else { return }
        present(shakeEnabled: shakeEnabled, longPressEnabled: longPressEnabled, markShown: true)
    }

    @MainActor
    static func presentForced(shakeEnabled: Bool, longPressEnabled: Bool) {
        present(shakeEnabled: shakeEnabled, longPressEnabled: longPressEnabled, markShown: false)
    }

    @MainActor
    private static func present(shakeEnabled: Bool, longPressEnabled: Bool, markShown: Bool) {
        // With both gestures off there is nothing the popover can
        // teach the user — programmatic-only integrations don't need
        // a UI nudge. We still mark "shown" in the configure-time path
        // so flipping a gesture on later doesn't surprise the user
        // with an out-of-context popover.
        guard shakeEnabled || longPressEnabled else {
            if markShown { OnboardingStore.markShown() }
            return
        }
        guard !presented else { return }
        presented = true

        let view = OnboardingView(
            showsShake: shakeEnabled,
            showsLongPress: longPressEnabled,
            onDismiss: {
                topViewController()?.dismiss(animated: true) {
                    presented = false
                }
            }
        )
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .formSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }

        // Defer one runloop tick so the host app's own root view
        // controller has a chance to mount before we present on top
        // of it. Without this, presentation from `App.init` reliably
        // no-ops on a window that doesn't have a root yet.
        DispatchQueue.main.async {
            guard let presenter = topViewController() else {
                presented = false
                return
            }
            presenter.present(host, animated: true) {
                if markShown { OnboardingStore.markShown() }
            }
        }
    }

    // Same top-controller walker the reporting session uses. Lives in
    // its own scope here (rather than importing ReportingSession's
    // private helper) because the two flows can outlive each other —
    // the onboarding popover doesn't depend on ReportingSession state.
    @MainActor
    private static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let root: UIViewController? = base ?? UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .keyWindow?
            .rootViewController
        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }
}
