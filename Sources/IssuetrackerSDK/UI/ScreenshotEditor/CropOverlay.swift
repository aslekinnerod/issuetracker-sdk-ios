import SwiftUI

// Draggable rectangle the user adjusts to crop the screenshot.
// Coordinates are in the displayed image's frame (points), not the
// source image — the editor translates them back when flattening.
//
// Keep the UI minimal: four corner handles + one centre pan. No
// numeric input, no aspect-ratio locks. Matches the project's
// "ekstremt enkelt" principle.
struct CropRect: Equatable {
    var origin: CGPoint
    var size: CGSize

    var minX: CGFloat { origin.x }
    var minY: CGFloat { origin.y }
    var maxX: CGFloat { origin.x + size.width }
    var maxY: CGFloat { origin.y + size.height }
}

struct CropOverlay: View {
    @Binding var rect: CropRect
    // The size of the displayed image. Handles get clamped to this.
    let imageSize: CGSize

    // Minimum crop size — below this the rectangle stops shrinking
    // so the user can't accidentally crop the image to nothing.
    private let minDimension: CGFloat = 40

    // DragGesture.translation is cumulative from drag start, so we
    // anchor on the rect-at-drag-start and apply the delta each tick.
    @State private var panAnchor: CGPoint?
    @State private var cornerAnchor: CropRect?

    var body: some View {
        ZStack {
            // Dim everything outside the crop rect using even-odd fill.
            Path { path in
                path.addRect(CGRect(origin: .zero, size: imageSize))
                path.addRect(CGRect(origin: rect.origin, size: rect.size))
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: rect.size.width, height: rect.size.height)
                .position(x: rect.minX + rect.size.width / 2,
                          y: rect.minY + rect.size.height / 2)
                .gesture(panGesture())

            // Corner handles
            handle(at: CGPoint(x: rect.minX, y: rect.minY), corner: .topLeft)
            handle(at: CGPoint(x: rect.maxX, y: rect.minY), corner: .topRight)
            handle(at: CGPoint(x: rect.minX, y: rect.maxY), corner: .bottomLeft)
            handle(at: CGPoint(x: rect.maxX, y: rect.maxY), corner: .bottomRight)
        }
        .frame(width: imageSize.width, height: imageSize.height)
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    @ViewBuilder
    private func handle(at point: CGPoint, corner: Corner) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
            .position(x: point.x, y: point.y)
            .gesture(cornerGesture(corner: corner))
    }

    private func panGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                let anchor = panAnchor ?? rect.origin
                if panAnchor == nil { panAnchor = rect.origin }
                var next = rect
                next.origin.x = clamp(
                    anchor.x + value.translation.width,
                    0,
                    imageSize.width - rect.size.width
                )
                next.origin.y = clamp(
                    anchor.y + value.translation.height,
                    0,
                    imageSize.height - rect.size.height
                )
                rect = next
            }
            .onEnded { _ in panAnchor = nil }
    }

    private func cornerGesture(corner: Corner) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let anchor = cornerAnchor ?? rect
                if cornerAnchor == nil { cornerAnchor = rect }
                let dx = value.translation.width
                let dy = value.translation.height
                var next = anchor
                switch corner {
                case .topLeft:
                    let newX = clamp(anchor.minX + dx, 0, anchor.maxX - minDimension)
                    let newY = clamp(anchor.minY + dy, 0, anchor.maxY - minDimension)
                    next.size.width = anchor.maxX - newX
                    next.size.height = anchor.maxY - newY
                    next.origin = CGPoint(x: newX, y: newY)
                case .topRight:
                    let newRight = clamp(anchor.maxX + dx, anchor.minX + minDimension, imageSize.width)
                    let newY = clamp(anchor.minY + dy, 0, anchor.maxY - minDimension)
                    next.size.width = newRight - anchor.minX
                    next.size.height = anchor.maxY - newY
                    next.origin.y = newY
                case .bottomLeft:
                    let newX = clamp(anchor.minX + dx, 0, anchor.maxX - minDimension)
                    let newBottom = clamp(anchor.maxY + dy, anchor.minY + minDimension, imageSize.height)
                    next.size.width = anchor.maxX - newX
                    next.size.height = newBottom - anchor.minY
                    next.origin.x = newX
                case .bottomRight:
                    let newRight = clamp(anchor.maxX + dx, anchor.minX + minDimension, imageSize.width)
                    let newBottom = clamp(anchor.maxY + dy, anchor.minY + minDimension, imageSize.height)
                    next.size.width = newRight - anchor.minX
                    next.size.height = newBottom - anchor.minY
                }
                rect = next
            }
            .onEnded { _ in cornerAnchor = nil }
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        return min(max(value, lower), upper)
    }
}
