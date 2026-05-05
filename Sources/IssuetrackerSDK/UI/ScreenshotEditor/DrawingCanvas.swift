import PencilKit
import SwiftUI

// Thin wrapper around PKCanvasView so we can drive it from SwiftUI
// state. PencilKit gives us strokes, erasing and undo for free; we
// just switch the ink tool when the user picks a different mode.
struct DrawingCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    var tool: PKTool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = tool
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if type(of: uiView.tool) != type(of: tool) || !toolsEqual(uiView.tool, tool) {
            uiView.tool = tool
        }
    }

    // PKTool doesn't conform to Equatable, and cross-casting between
    // PKInkingTool and PKEraserTool is the only way to detect a
    // meaningful change without re-assigning on every render.
    private func toolsEqual(_ a: PKTool, _ b: PKTool) -> Bool {
        if let ai = a as? PKInkingTool, let bi = b as? PKInkingTool {
            return ai.inkType == bi.inkType && ai.color == bi.color && ai.width == bi.width
        }
        if let ae = a as? PKEraserTool, let be = b as? PKEraserTool {
            return ae.eraserType == be.eraserType
        }
        return false
    }
}
