import UIKit

// Shared window plumbing for the SDK's floating chrome (the recording
// stop pill and the ADR-0008 report button). Each floater lives in its
// own UIWindow so sheets, presented view controllers and rotation
// changes don't bury it; hit-testing is scoped to just the floater so
// touches elsewhere fall through to the host app.

// UIWindow subclass that only intercepts touches that land on its
// single hit-testable subview. Everything else falls through to the
// underlying window (the host app).
final class PassThroughWindow: UIWindow {
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

// UIButton whose touch target is expanded to at least 44×44pt even
// when the visual control is shorter (the stop pill is ~27pt tall).
// `point(inside:)` is what both normal hit-testing and
// PassThroughWindow consult, so the enlarged area works with the
// pass-through window too.
final class MinTouchTargetButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let minSide: CGFloat = 44
        let dx = max(0, (minSide - bounds.width) / 2)
        let dy = max(0, (minSide - bounds.height) / 2)
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }
}
