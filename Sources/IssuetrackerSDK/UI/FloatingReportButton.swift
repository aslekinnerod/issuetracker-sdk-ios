import UIKit

// SDK-provided floating "Report" entry point (ADR-0008 Decision 3).
// Opt-in via `configure(showReportButton: true)` — gives hosts that
// can't (or won't) build their own visible control a one-line path to
// the WCAG 2.5.1/2.5.4 single-pointer / non-motion alternative for
// the gesture triggers.
//
// Same PassThroughWindow approach as FloatingStopPill, one window
// level below it so the stop pill always wins while both exist.
// Visibility is the AND of four inputs, each pushed in by its owner
// and reconciled here:
//
//   - `enabled`            — configure(showReportButton:), live on
//                            re-configure like the other flags.
//   - `reporterPresented`  — ReportingSession's `presented` gate; the
//                            button hides under the reporter sheet
//                            and returns when it dismisses.
//   - `stopPillVisible`    — hidden during a screen recording.
//   - TERMINATED           — removed for good once LifecycleStore
//                            flips (ADR-0003 Decision 9), both at
//                            configure-time (persisted state) and
//                            live via the terminated notification.
@MainActor
final class FloatingReportButton {
    static let shared = FloatingReportButton()

    private var enabled = false
    private var reporterPresented = false
    private var stopPillVisible = false
    private var terminatedToken: NSObjectProtocol?
    private var window: PassThroughWindow?
    private var retryScheduled = false

    private init() {}

    func setEnabled(_ flag: Bool) {
        enabled = flag
        if flag, terminatedToken == nil {
            terminatedToken = NotificationCenter.default.addObserver(
                forName: LifecycleStore.terminatedNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in FloatingReportButton.shared.reconcile() }
            }
        } else if !flag, let terminatedToken {
            NotificationCenter.default.removeObserver(terminatedToken)
            self.terminatedToken = nil
        }
        reconcile()
    }

    func setReporterPresented(_ flag: Bool) {
        reporterPresented = flag
        reconcile()
    }

    func setStopPillVisible(_ flag: Bool) {
        stopPillVisible = flag
        reconcile()
    }

    // MARK: - Reconcile

    private var wantsWindow: Bool {
        enabled && !LifecycleStore.shared.isTerminated
    }

    private var wantsVisible: Bool {
        wantsWindow && !reporterPresented && !stopPillVisible
    }

    private func reconcile() {
        guard wantsWindow else {
            // Disabled or terminated — drop the window entirely.
            window?.isHidden = true
            window = nil
            return
        }
        guard wantsVisible else {
            // Temporarily covered (reporter sheet / stop pill): keep
            // the window around so re-show is instant and cheap.
            window?.isHidden = true
            return
        }
        if let window {
            window.isHidden = false
            return
        }
        attach()
    }

    private func attach() {
        guard let scene = keyWindowScene() else {
            // No scene yet (configure called before the scene attaches).
            // Re-try on a later run loop tick — same pattern as
            // LongPressObserver.
            guard !retryScheduled else { return }
            retryScheduled = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                retryScheduled = false
                reconcile()
            }
            return
        }

        let w = PassThroughWindow(windowScene: scene)
        // One below FloatingStopPill (.alert + 1): during a recording
        // the pill must always be the top floater. (The button is
        // hidden then anyway, but the ordering shouldn't depend on it.)
        w.windowLevel = .alert
        w.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        w.rootViewController = root

        let button = MinTouchTargetButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        // Trace `--accent-strong` (#1577AD) — the on-fill accent that
        // holds ≥4.5:1 with white, unlike the decorative #1FA2E8.
        button.backgroundColor = UIColor(red: 0x15/255.0, green: 0x77/255.0, blue: 0xAD/255.0, alpha: 1)
        button.setTitleColor(.white, for: .normal)
        button.setImage(
            UIImage(systemName: "exclamationmark.bubble.fill")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        button.tintColor = .white
        button.setTitle("  Report", for: .normal)
        // Scale with Dynamic Type (1.4.4) — anchored to caption1 like
        // the stop pill.
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityLabel = "Report a bug"
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 14)
        button.layer.cornerRadius = 16
        // Same restrained on-brand halo as the stop pill.
        button.layer.shadowColor = UIColor(red: 0x1F/255.0, green: 0xA2/255.0, blue: 0xE8/255.0, alpha: 1).cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowOpacity = 0.18
        button.layer.shadowRadius = 16
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        root.view.addSubview(button)
        // Bottom-trailing, inside the safe area — out of the way of
        // nav bars, tab bars and the home indicator, and mirrors the
        // web SDK's floating-button placement.
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(
                equalTo: root.view.safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            button.bottomAnchor.constraint(
                equalTo: root.view.safeAreaLayoutGuide.bottomAnchor,
                constant: -16
            ),
        ])
        w.hitTestView = button
        w.isHidden = false
        window = w
    }

    @objc private func handleTap() {
        // Reentry guard — the button hides while the reporter is up,
        // but a tap can race the hide.
        guard !ReportingSession.isPresented else { return }
        Issuetracker.report()
    }

    private func keyWindowScene() -> UIWindowScene? {
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
    }
}
