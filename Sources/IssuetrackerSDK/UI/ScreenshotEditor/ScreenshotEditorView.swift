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
                            .allowsHitTesting(mode != .crop)
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
                    mode: $mode,
                    color: $color,
                    onUndo: { canvas.undoManager?.undo() },
                    onResetCrop: {
                        if displayedSize.width > 0 {
                            cropRect = CropRect(origin: .zero, size: displayedSize)
                        }
                    }
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
        if cropRect != nil && isCropMeaningful() { return true }
        return false
    }

    private var currentTool: PKTool {
        switch mode {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(color), width: 4)
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(color).withAlphaComponent(0.45), width: 18)
        case .eraser:
            return PKEraserTool(.vector)
        case .crop:
            // Placeholder while drawing is locked — any inking tool
            // works, the canvas has hit-testing disabled in crop mode.
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
