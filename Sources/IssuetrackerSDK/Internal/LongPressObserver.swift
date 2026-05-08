import UIKit

// Two-finger long-press (3s) trigger. Same gesture as the web SDK so
// users on a multi-platform product only need to learn one gesture.
//
// Attached to the key window at install time. cancelsTouchesInView is
// false and the delegate allows simultaneous recognition so we don't
// interfere with the host app's own gestures (pinch-to-zoom, pan,
// other long-presses, etc.).
@MainActor
enum LongPressObserver {
    private static let coordinator = Coordinator()
    private static var onTrigger: (() -> Void)?
    private static var attached = false

    static func install(onTrigger handler: @escaping () -> Void) {
        self.onTrigger = handler
        attach()
    }

    private static func attach() {
        guard !attached else { return }
        guard let window = keyWindow() else {
            // No window yet (configure called before scene attaches).
            // Re-try on the next run loop tick.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                attach()
            }
            return
        }
        let recognizer = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.fired(_:))
        )
        recognizer.minimumPressDuration = 3.0
        recognizer.numberOfTouchesRequired = 2
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = coordinator
        window.addGestureRecognizer(recognizer)
        attached = true
    }

    fileprivate static func fire() {
        onTrigger?()
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return active?.windows.first(where: { $0.isKeyWindow }) ?? active?.windows.first
    }

    private final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func fired(_ gr: UIGestureRecognizer) {
            guard gr.state == .began else { return }
            Task { @MainActor in LongPressObserver.fire() }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Let host-app gestures keep working alongside ours.
            return true
        }
    }
}
