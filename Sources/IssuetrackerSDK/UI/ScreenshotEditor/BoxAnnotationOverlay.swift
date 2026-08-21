import PencilKit
import SwiftUI

// Pending "highlight box" annotation — the non-drag alternative to
// freehand drawing (WCAG 2.5.7 / 2.1.1, ISU-38). Activating the Box
// tool drops this overlay at the image centre; it can be nudged and
// resized entirely through VoiceOver custom actions (or dragged by
// pointer users) and is committed into the PencilKit drawing as a
// single stroke via Place.
struct BoxAnnotationOverlay: View {
    @Binding var rect: CGRect
    let color: Color
    // Displayed image size in points — movement/resize steps are
    // percentages of this so they feel consistent across zoom levels.
    let imageSize: CGSize
    var onPlace: () -> Void
    var onRemove: () -> Void

    // Smallest box that still reads as a highlight and stays grabbable.
    private let minDimension: CGFloat = 24

    // DragGesture.translation is cumulative from drag start (same
    // pattern as CropOverlay).
    @State private var dragAnchor: CGPoint?

    var body: some View {
        Rectangle()
            .stroke(color, lineWidth: 4)
            .background(Color.white.opacity(0.001)) // hit-testable interior for drag
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(moveGesture())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Highlight box")
            .accessibilityValue(positionDescription)
            .accessibilityHint("Not placed yet. Use the actions to move, resize, place, or remove it.")
            .accessibilityAction(named: "Move left") { move(dx: -stepX, dy: 0) }
            .accessibilityAction(named: "Move right") { move(dx: stepX, dy: 0) }
            .accessibilityAction(named: "Move up") { move(dx: 0, dy: -stepY) }
            .accessibilityAction(named: "Move down") { move(dx: 0, dy: stepY) }
            .accessibilityAction(named: "Bigger") { resize(by: 1) }
            .accessibilityAction(named: "Smaller") { resize(by: -1) }
            .accessibilityAction(named: "Place") { onPlace() }
            .accessibilityAction(named: "Remove") { onRemove() }
    }

    // 2% of the displayed image per nudge — fine enough to aim, coarse
    // enough that crossing the screen doesn't take forever.
    private var stepX: CGFloat { imageSize.width * 0.02 }
    private var stepY: CGFloat { imageSize.height * 0.02 }

    private var positionDescription: String {
        guard imageSize.width > 0, imageSize.height > 0 else { return "" }
        let x = Int((rect.midX / imageSize.width * 100).rounded())
        let y = Int((rect.midY / imageSize.height * 100).rounded())
        let w = Int((rect.width / imageSize.width * 100).rounded())
        return "Centre at \(x) percent across, \(y) percent down. Width \(w) percent of image."
    }

    private func move(dx: CGFloat, dy: CGFloat) {
        var next = rect
        next.origin.x = clamp(rect.origin.x + dx, 0, imageSize.width - rect.width)
        next.origin.y = clamp(rect.origin.y + dy, 0, imageSize.height - rect.height)
        rect = next
    }

    // Grows/shrinks around the centre by 2% of the image per side.
    private func resize(by direction: CGFloat) {
        let dw = imageSize.width * 0.04 * direction
        let dh = imageSize.height * 0.04 * direction
        var next = rect
        next.size.width = clamp(rect.width + dw, minDimension, imageSize.width)
        next.size.height = clamp(rect.height + dh, minDimension, imageSize.height)
        next.origin.x = clamp(rect.midX - next.width / 2, 0, imageSize.width - next.width)
        next.origin.y = clamp(rect.midY - next.height / 2, 0, imageSize.height - next.height)
        rect = next
    }

    private func moveGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                let anchor = dragAnchor ?? rect.origin
                if dragAnchor == nil { dragAnchor = rect.origin }
                var next = rect
                next.origin.x = clamp(anchor.x + value.translation.width, 0, imageSize.width - rect.width)
                next.origin.y = clamp(anchor.y + value.translation.height, 0, imageSize.height - rect.height)
                rect = next
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        return min(max(value, max(lower, 0)), max(upper, lower))
    }
}

// Builds the committed form of the box: a single closed PKStroke that
// traces the rectangle outline, so it lives in the same layer — and
// the same undo stack — as freehand pen strokes.
enum BoxAnnotation {
    static func stroke(for rect: CGRect, color: UIColor) -> PKStroke {
        let ink = PKInk(.pen, color: color)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY),
        ]
        var points: [PKStrokePoint] = []
        var time: TimeInterval = 0
        for i in 0..<(corners.count - 1) {
            let a = corners[i]
            let b = corners[i + 1]
            // Dense sampling keeps the pen ink's spline interpolation
            // from rounding the corners into a blob.
            let length = hypot(b.x - a.x, b.y - a.y)
            let steps = max(2, Int(length / 4))
            for s in 0...steps {
                // Skip the duplicate start point of every edge after
                // the first so the path stays monotonic in time.
                if i > 0 && s == 0 { continue }
                let t = CGFloat(s) / CGFloat(steps)
                let location = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                points.append(
                    PKStrokePoint(
                        location: location,
                        timeOffset: time,
                        size: CGSize(width: 4, height: 4),
                        opacity: 1,
                        force: 1,
                        azimuth: 0,
                        altitude: .pi / 2
                    )
                )
                time += 0.01
            }
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: ink, path: path)
    }
}
