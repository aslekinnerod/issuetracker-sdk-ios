import SwiftUI

enum EditorMode: Hashable {
    case pen, highlighter, eraser, box, crop
}

// Five colours keep the picker to one row. Red dominates for bug
// reports so it's first.
let editorColorPalette: [Color] = [
    .red, .orange, .yellow, .green, .blue,
]

struct EditorToolbar: View {
    @Binding var mode: EditorMode
    @Binding var color: Color
    var hasPendingBox: Bool
    var onUndo: () -> Void
    var onResetCrop: () -> Void
    var onPlaceBox: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                modeButton(.pen, system: "pencil.tip", label: "Pen")
                modeButton(.highlighter, system: "highlighter", label: "Highlight")
                modeButton(.eraser, system: "eraser", label: "Eraser")
                modeButton(.box, system: "rectangle", label: "Box")
                modeButton(.crop, system: "crop", label: "Crop")
                Spacer()
                if mode == .crop {
                    Button(action: onResetCrop) {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Reset crop")
                } else if mode == .box {
                    // Commits the pending box into the drawing layer —
                    // the non-drag path to finish the annotation.
                    Button(action: onPlaceBox) {
                        Image(systemName: "checkmark")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(!hasPendingBox)
                    .accessibilityLabel("Place highlight box")
                } else {
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Undo")
                }
            }
            .font(.title3)
            .padding(.horizontal, 4)

            if mode == .pen || mode == .highlighter || mode == .box {
                HStack(spacing: 4) {
                    ForEach(editorColorPalette, id: \.self) { c in
                        Button {
                            color = c
                        } label: {
                            Circle()
                                .fill(c)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: color == c ? 2 : 0)
                                )
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(colorName(c))
                        .accessibilityAddTraits(color == c ? .isSelected : [])
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
            // 50pt (down from 54) so five modes + the trailing action
            // still fit a 375pt-wide phone; stays above the 44pt
            // target minimum.
            .frame(width: 50, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    private func colorName(_ c: Color) -> String {
        switch c {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        default: return "Color"
        }
    }
}
