import PencilKit
import SwiftUI
import UIKit

// Full-screen editor the user opens by tapping the screenshot
// thumbnail in ReportView. Runde 1 does drawing + eraser; crop + save
// land in later rundes.
struct ScreenshotEditorView: View {
    let originalImage: UIImage
    // Receives the flattened edited image (or nil if the user cancels
    // without changes). Caller decides what to do with it.
    let onDone: (UIImage?) -> Void

    @State private var canvas = PKCanvasView()
    @State private var mode: EditorMode = .pen
    @State private var color: Color = .red
    // Crop rectangle in display-space (points of the on-screen image).
    // Initialised to the full image on first show; translated back to
    // source-pixel space when the user taps Done.
    @State private var cropRect: CropRect?
    // Displayed image size in points — needed to convert cropRect to
    // image-pixel coordinates at flatten time.
    @State private var displayedSize: CGSize = .zero
    @State private var showingCancelConfirm = false
    // Pending "highlight box" annotation (Box tool) in display points.
    // Lives here — not in the PencilKit drawing — until the user
    // commits it with Place; Remove just discards it.
    @State private var pendingBox: CGRect?
    @AccessibilityFocusState private var boxFocused: Bool

    var body: some View {
        NavigationStack {
            // VStack instead of a bottom-aligned ZStack so the toolbar
            // takes its own space; otherwise the image and crop frame
            // extend behind it and the bottom handles get eaten.
            VStack(spacing: 0) {
                GeometryReader { geo in
                    // Leave room around the image so the corner-
                    // handles of the crop rectangle (which are 20pt
                    // circles centred on the rect corners) don't get
                    // clipped by the toolbar or notch.
                    let inset: CGFloat = 16
                    let available = CGSize(
                        width: max(0, geo.size.width - inset * 2),
                        height: max(0, geo.size.height - inset * 2)
                    )
                    let size = fittedSize(for: originalImage.size, in: available)
                    let _ = DispatchQueue.main.async {
                        if displayedSize != size { displayedSize = size }
                    }
                    ZStack {
                        Image(uiImage: originalImage)
                            .resizable()
                            .scaledToFit()
                        DrawingCanvas(canvas: $canvas, tool: currentTool)
                            .allowsHitTesting(mode != .crop && mode != .box)
                        if mode == .box, pendingBox != nil {
                            BoxAnnotationOverlay(
                                rect: Binding(
                                    get: { pendingBox ?? centeredBox(in: size) },
                                    set: { pendingBox = $0 }
                                ),
                                color: color,
                                imageSize: size,
                                onPlace: { placePendingBox() },
                                onRemove: { removePendingBox() }
                            )
                            .accessibilityFocused($boxFocused)
                        }
                        if mode == .crop {
                            CropOverlay(
                                rect: Binding(
                                    get: {
                                        cropRect ?? CropRect(origin: .zero, size: size)
                                    },
                                    set: { cropRect = $0 }
                                ),
                                imageSize: size
                            )
                            .onAppear {
                                if cropRect == nil {
                                    cropRect = CropRect(origin: .zero, size: size)
                                }
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                EditorToolbar(
                    // Intercepted so entering Box mode seeds the
                    // pending box and leaving it commits the box —
                    // switching tools never silently drops work.
                    mode: Binding(get: { mode }, set: { setMode($0) }),
                    color: $color,
                    hasPendingBox: pendingBox != nil,
                    onUndo: { canvas.undoManager?.undo() },
                    onResetCrop: {
                        if displayedSize.width > 0 {
                            cropRect = CropRect(origin: .zero, size: displayedSize)
                        }
                    },
                    onPlaceBox: { placePendingBox() }
                )
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Edit screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges() {
                            showingCancelConfirm = true
                        } else {
                            onDone(nil)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // A positioned-but-unplaced box is intentional
                        // work — commit it rather than dropping it.
                        commitPendingBoxIfNeeded()
                        onDone(flatten())
                    }
                }
            }
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showingCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { onDone(nil) }
                Button("Keep editing", role: .cancel) {}
            }
        }
    }

    private func hasChanges() -> Bool {
        if !canvas.drawing.strokes.isEmpty { return true }
        if pendingBox != nil { return true }
        if cropRect != nil && isCropMeaningful() { return true }
        return false
    }

    // MARK: - Box tool (non-drag annotation, ISU-38)

    // Routes every toolbar mode change so Box entry/exit stays
    // consistent: entering seeds a centred pending box, leaving
    // commits whatever the user positioned.
    private func setMode(_ newMode: EditorMode) {
        if mode == .box, newMode != .box {
            commitPendingBoxIfNeeded()
        }
        mode = newMode
        if newMode == .box, pendingBox == nil, displayedSize.width > 0 {
            pendingBox = centeredBox(in: displayedSize)
            // Move VoiceOver to the new box so its custom actions are
            // immediately discoverable.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                boxFocused = true
            }
        }
    }

    // ~30% of the image wide, centred — big enough to see, small
    // enough to make the "what does this highlight" question obvious.
    private func centeredBox(in size: CGSize) -> CGRect {
        let w = size.width * 0.3
        let h = size.height * 0.2
        return CGRect(
            x: (size.width - w) / 2,
            y: (size.height - h) / 2,
            width: w,
            height: h
        )
    }

    private func placePendingBox() {
        guard commitPendingBoxIfNeeded() else { return }
        mode = .pen
        UIAccessibility.post(notification: .announcement, argument: "Highlight box placed")
    }

    private func removePendingBox() {
        pendingBox = nil
        mode = .pen
        UIAccessibility.post(notification: .announcement, argument: "Highlight box removed")
    }

    @discardableResult
    private func commitPendingBoxIfNeeded() -> Bool {
        guard let box = pendingBox else { return false }
        let stroke = BoxAnnotation.stroke(for: box, color: UIColor(color))
        var drawing = canvas.drawing
        drawing.strokes.append(stroke)
        Self.setDrawing(drawing, on: canvas)
        pendingBox = nil
        return true
    }

    // Programmatic PKDrawing changes bypass PKCanvasView's own undo
    // registration, so register one ourselves. The mutual re-
    // registration inside the closure gives redo for free, and the
    // whole box lands as a single undo step — same stack, same Undo
    // button as freehand strokes.
    private static func setDrawing(_ drawing: PKDrawing, on canvas: PKCanvasView) {
        let previous = canvas.drawing
        canvas.undoManager?.registerUndo(withTarget: canvas) { target in
            setDrawing(previous, on: target)
        }
        canvas.drawing = drawing
    }

    private var currentTool: PKTool {
        switch mode {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(color), width: 4)
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(color).withAlphaComponent(0.45), width: 18)
        case .eraser:
            return PKEraserTool(.vector)
        case .box, .crop:
            // Placeholder while drawing is locked — any inking tool
            // works, the canvas has hit-testing disabled in these modes.
            return PKInkingTool(.pen, color: UIColor(color), width: 4)
        }
    }

    private func fittedSize(for image: CGSize, in container: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return container }
        let ratio = min(container.width / image.width, container.height / image.height)
        return CGSize(width: image.width * ratio, height: image.height * ratio)
    }

    // Composes the edited image: drawing strokes rasterised over the
    // original, then optionally cropped. Returns nil if nothing changed
    // (no strokes and no crop) so the caller can keep the original.
    private func flatten() -> UIImage? {
        let drawing = canvas.drawing
        let hasStrokes = !drawing.strokes.isEmpty
        let hasCrop = cropRect != nil && isCropMeaningful()
        if !hasStrokes && !hasCrop { return nil }

        // Render at the image's natural size so strokes don't look
        // blurry on high-dpi screenshots. The canvas was drawn over a
        // display-sized image, so we upscale the drawing to match.
        let imageSize = originalImage.size
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let composed = renderer.image { ctx in
            originalImage.draw(in: CGRect(origin: .zero, size: imageSize))
            if hasStrokes, displayedSize.width > 0 {
                let scale = imageSize.width / displayedSize.width
                ctx.cgContext.saveGState()
                ctx.cgContext.scaleBy(x: scale, y: scale)
                let strokesImage = drawing.image(
                    from: CGRect(origin: .zero, size: displayedSize),
                    scale: UIScreen.main.scale
                )
                strokesImage.draw(in: CGRect(origin: .zero, size: displayedSize))
                ctx.cgContext.restoreGState()
            }
        }

        guard hasCrop, let cropRect, displayedSize.width > 0, displayedSize.height > 0 else {
            return composed
        }

        // cropRect is in display points. We first map that to image
        // points (logical), then to pixels — CGImage.cropping(to:)
        // operates in pixel space. Skipping the pixel multiplication
        // was the bug that cropped a tiny top-left region on retina
        // devices instead of the selected area.
        let sx = imageSize.width / displayedSize.width
        let sy = imageSize.height / displayedSize.height
        let pixelScale = composed.scale
        let cropInPixels = CGRect(
            x: cropRect.origin.x * sx * pixelScale,
            y: cropRect.origin.y * sy * pixelScale,
            width: cropRect.size.width * sx * pixelScale,
            height: cropRect.size.height * sy * pixelScale
        )
        guard let cg = composed.cgImage?.cropping(to: cropInPixels) else { return composed }
        return UIImage(cgImage: cg, scale: pixelScale, orientation: composed.imageOrientation)
    }

    // "Meaningful" = within 1pt of fitting the entire image, we treat
    // the crop as a no-op to skip the extra work.
    private func isCropMeaningful() -> Bool {
        guard let r = cropRect else { return false }
        let epsilon: CGFloat = 1
        return r.origin.x > epsilon
            || r.origin.y > epsilon
            || abs(r.size.width - displayedSize.width) > epsilon
            || abs(r.size.height - displayedSize.height) > epsilon
    }
}
