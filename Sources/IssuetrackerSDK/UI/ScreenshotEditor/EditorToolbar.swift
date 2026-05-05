import SwiftUI

enum EditorMode: Hashable {
    case pen, highlighter, eraser, crop
}

// Five colours keep the picker to one row. Red dominates for bug
// reports so it's first.
let editorColorPalette: [Color] = [
    .red, .orange, .yellow, .green, .blue,
]

struct EditorToolbar: View {
    @Binding var mode: EditorMode
    @Binding var color: Color
    var onUndo: () -> Void
    var onResetCrop: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                modeButton(.pen, system: "pencil.tip", label: "Pen")
                modeButton(.highlighter, system: "highlighter", label: "Highlight")
                modeButton(.eraser, system: "eraser", label: "Eraser")
                modeButton(.crop, system: "crop", label: "Crop")
                Spacer()
                if mode == .crop {
                    Button(action: onResetCrop) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                } else {
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
            }
            .font(.title3)
            .padding(.horizontal, 4)

            if mode == .pen || mode == .highlighter {
                HStack(spacing: 10) {
                    ForEach(editorColorPalette, id: \.self) { c in
                        Circle()
                            .fill(c)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: color == c ? 2 : 0)
                            )
                            .onTapGesture { color = c }
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(10)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func modeButton(_ m: EditorMode, system: String, label: String) -> some View {
        Button {
            mode = m
        } label: {
            VStack(spacing: 2) {
                Image(systemName: system)
                Text(label).font(.caption2)
            }
            .foregroundStyle(mode == m ? Color.accentColor : Color.primary)
            .frame(width: 54)
        }
    }
}
