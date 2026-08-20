import UIKit

// Screen-reader activation path for the reporter (ADR-0008 Decision
// 2). While VoiceOver is running, appends a "Report a bug"
// UIAccessibilityCustomAction to the key window's root view
// controller so VoiceOver users — who typically can't reach the shake
// or two-finger-long-press triggers because the screen reader claims
// those inputs — get a rotor action that invokes the same code path
// as the public `report()` API.
//
// Lifecycle mirrors the other trigger observers (ShakeObserver /
// LongPressObserver): `enum` with static state, installed from
// `configure()`. Unlike the gesture observers it also tears down —
// registration is the AND of the config flag and VoiceOver state, and
// either side can flip at runtime:
//
//   - `voiceOverStatusDidChangeNotification` → reconcile.
//   - re-`configure(accessibilityAction:)` → setEnabled → reconcile.
//   - key window / scene changes → reconcile re-attaches to the new
//     root view controller (multi-scene and window-swap safe).
//
// Hygiene rules for touching a host view hierarchy from library code:
// always APPEND to `accessibilityCustomActions` (never replace the
// host's own actions) and on teardown remove exactly our own action
// instance by identity.
@MainActor
enum AccessibilityActionObserver {
    private static var enabled = false
    private static var notificationTokens: [NSObjectProtocol] = []
    private static var action: UIAccessibilityCustomAction?
    private static weak var attachedRoot: UIViewController?

    static func setEnabled(_ flag: Bool) {
        enabled = flag
        if flag {
            startObservingIfNeeded()
        } else {
            stopObserving()
        }
        reconcile()
    }

    static var isInstalled: Bool { enabled }

    // MARK: - Notification plumbing

    private static func startObservingIfNeeded() {
        guard notificationTokens.isEmpty else { return }
        let names: [Notification.Name] = [
            UIAccessibility.voiceOverStatusDidChangeNotification,
            // Key-window churn: scene connects late (configure() often
            // runs before the first scene attaches), host apps swap
            // windows, multi-scene apps change which scene is
            // foreground-active. Any of these can move the root VC we
            // must be attached to.
            UIWindow.didBecomeKeyNotification,
            UIScene.didActivateNotification,
            // TERMINATED must tear the action down (ADR-0003 D9 /
            // TRIGGER_ACCESSIBILITY.md: both flags disabled in the
            // terminal state), matching the Android SDK.
            LifecycleStore.terminatedNotification,
        ]
        notificationTokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in reconcile() }
            }
        }
    }

    private static func stopObserving() {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens = []
    }

    // MARK: - Attach / detach

    private static func reconcile() {
        guard enabled, UIAccessibility.isVoiceOverRunning,
              !LifecycleStore.shared.isTerminated else {
            detach()
            return
        }
        guard let root = keyWindow()?.rootViewController else {
            // No window yet — the didBecomeKey/didActivate observers
            // will call us again once one attaches.
            detach()
            return
        }
        if root === attachedRoot { return }
        // Key window changed — move our action to the new root.
        detach()

        let a = UIAccessibilityCustomAction(name: "Report a bug") { _ in
            MainActor.assumeIsolated {
                // Reentry guard: while the reporter (or name prompt /
                // terminated sheet) is already up, the action is a
                // no-op — same protection the gesture triggers get
                // from ReportingSession's `presented` gate, surfaced
                // here as an explicit failure so VoiceOver doesn't
                // announce success.
                guard !ReportingSession.isPresented else { return false }
                Issuetracker.report()
                return true
            }
        }
        root.accessibilityCustomActions = (root.accessibilityCustomActions ?? []) + [a]
        action = a
        attachedRoot = root
    }

    private static func detach() {
        if let action, let attachedRoot,
           let existing = attachedRoot.accessibilityCustomActions {
            let remaining = existing.filter { $0 !== action }
            // Hand back nil rather than [] when we were the only
            // action, so the host VC reads as "never touched".
            attachedRoot.accessibilityCustomActions = remaining.isEmpty ? nil : remaining
        }
        action = nil
        attachedRoot = nil
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        // Never attach to our own floating-chrome windows — the action
        // belongs on the host app's root VC.
        let hostWindows = active?.windows.filter { !($0 is PassThroughWindow) }
        return hostWindows?.first(where: { $0.isKeyWindow }) ?? hostWindows?.first
    }
}
