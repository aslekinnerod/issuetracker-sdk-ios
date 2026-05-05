import UIKit

// Red floating pill that's visible over the host app while a
// screen recording is active. Lives in its own UIWindow so sheets,
// presented view controllers and rotation changes don't bury it.
//
// Hit-testing is scoped to just the pill itself — touches elsewhere
// fall through to the app as usual.
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

        let pill = UIButton(type: .system)
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = UIColor.systemRed
        pill.setTitleColor(.white, for: .normal)
        pill.setImage(
            UIImage(systemName: "stop.fill")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        pill.tintColor = .white
        pill.setTitle("  Stop", for: .normal)
        pill.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        pill.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 12)
        pill.layer.cornerRadius = 14
        pill.layer.shadowColor = UIColor.black.cgColor
        pill.layer.shadowOffset = CGSize(width: 0, height: 2)
        pill.layer.shadowOpacity = 0.25
        pill.layer.shadowRadius = 4
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
    }

    func hide() {
        window?.isHidden = true
        window = nil
        tapHandler = nil
    }

    @objc private func handleTap() {
        tapHandler?()
    }
}

// UIWindow subclass that only intercepts touches that land on its
// single hit-testable subview. Everything else falls through to the
// underlying window (the host app).
private final class PassThroughWindow: UIWindow {
    weak var hitTestView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitTestView else { return nil }
        let pointInView = convert(point, to: hitTestView)
        if hitTestView.point(inside: pointInView, with: event) {
            return super.hitTest(point, with: event)
        }
        return nil
    }
}
