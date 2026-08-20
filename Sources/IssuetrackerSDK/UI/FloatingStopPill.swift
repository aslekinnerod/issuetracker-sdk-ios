import UIKit

// Red floating pill that's visible over the host app while a
// screen recording is active. Lives in its own UIWindow so sheets,
// presented view controllers and rotation changes don't bury it.
// Window plumbing (PassThroughWindow, MinTouchTargetButton) is shared
// with FloatingReportButton — see PassThroughWindow.swift.
@MainActor
final class FloatingStopPill {
    static let shared = FloatingStopPill()

    private var window: PassThroughWindow?
    private var tapHandler: (() -> Void)?

    private init() {}

    func show(in scene: UIWindowScene, onTap: @escaping () -> Void) {
        guard window == nil else { return }
        tapHandler = onTap

        let w = PassThroughWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        w.rootViewController = root

        let pill = MinTouchTargetButton(type: .system)
        pill.translatesAutoresizingMaskIntoConstraints = false
        // Trace `--status-critical` (#E03A4E). Slightly more brand-on
        // than systemRed without losing the "stop now" affordance.
        pill.backgroundColor = UIColor(red: 0xE0/255.0, green: 0x3A/255.0, blue: 0x4E/255.0, alpha: 1)
        pill.setTitleColor(.white, for: .normal)
        pill.setImage(
            UIImage(systemName: "stop.fill")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        pill.tintColor = .white
        pill.setTitle("  Stop", for: .normal)
        // Scale with Dynamic Type (1.4.4) — anchored to caption1 to
        // match the 12pt base size.
        pill.titleLabel?.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
        pill.titleLabel?.adjustsFontForContentSizeCategory = true
        pill.accessibilityLabel = "Stop recording"
        pill.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 12)
        pill.layer.cornerRadius = 14
        // Soft cyan halo, mirrors `--shadow-glow` on web — keeps the
        // shadow restrained and on-brand instead of generic black.
        pill.layer.shadowColor = UIColor(red: 0x1F/255.0, green: 0xA2/255.0, blue: 0xE8/255.0, alpha: 1).cgColor
        pill.layer.shadowOffset = CGSize(width: 0, height: 4)
        pill.layer.shadowOpacity = 0.18
        pill.layer.shadowRadius = 16
        pill.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        root.view.addSubview(pill)
        // Dynamic Island can't be driven from a library-only Swift
        // package (Live Activities need a widget extension in the
        // host app). Next best thing: sit right under the status bar
        // so we're out of the scroll and content area. On notched and
        // DI phones the pill slides to the right so the Island stays
        // clear; on older phones we centre it.
        let topAnchor = root.view.safeAreaLayoutGuide.topAnchor
        let hasDynamicIsland = UIDevice.current.userInterfaceIdiom == .phone
            && (root.view.safeAreaInsets.top >= 50)
        if hasDynamicIsland {
            NSLayoutConstraint.activate([
                pill.trailingAnchor.constraint(
                    equalTo: root.view.safeAreaLayoutGuide.trailingAnchor,
                    constant: -8
                ),
                pill.topAnchor.constraint(equalTo: topAnchor, constant: -4),
            ])
        } else {
            NSLayoutConstraint.activate([
                pill.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
                pill.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            ])
        }
        w.hitTestView = pill
        w.isHidden = false
        window = w
        // The report button (ADR-0008) yields while the pill is up —
        // one floater at a time, and the pill's stop action is the
        // only thing that should be tappable during a recording.
        FloatingReportButton.shared.setStopPillVisible(true)
    }

    func hide() {
        window?.isHidden = true
        window = nil
        tapHandler = nil
        FloatingReportButton.shared.setStopPillVisible(false)
    }

    @objc private func handleTap() {
        tapHandler?()
    }
}

