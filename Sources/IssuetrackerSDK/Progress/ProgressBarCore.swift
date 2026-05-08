import SwiftUI

struct IndeterminateSweep: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                let cycle = ProgressTokens.Motion.sweepDurationMs / 1000.0
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
                let ease = phase < 0.5
                    ? 2 * phase * phase
                    : 1 - pow(-2 * phase + 2, 2) / 2
                let trackWidth = proxy.size.width
                let highlightWidth = trackWidth * ProgressTokens.Motion.sweepHighlightWidthFraction
                let leftPx = -highlightWidth + (trackWidth + highlightWidth) * ease

                Rectangle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [.clear, color, .clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: highlightWidth)
                    .offset(x: leftPx)
            }
        }
        .background(color.opacity(0.13))
        .clipShape(Capsule())
    }
}

struct ProgressFill: View {
    let presentation: ProgressPresentation
    let variant: ProgressVariant

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ProgressTokens.NeutralColor.track)

                if presentation.deterministicFillVisible {
                    Capsule()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: max(0, proxy.size.width * presentation.fillWidthPercent / 100.0))
                        .animation(
                            .linear(duration: ProgressTokens.Motion.fillDurationMs / 1000.0),
                            value: presentation.fillWidthPercent
                        )
                } else {
                    IndeterminateSweep(color: variant.accent)
                }
            }
        }
    }

    private var gradientColors: [Color] {
        if presentation.tintIsError {
            return [ProgressTokens.ErrorColor.dark, ProgressTokens.ErrorColor.accent]
        }
        return variant.fillGradient
    }
}

struct PhaseDot: View {
    let phase: IssueProgressPhase
    let accent: Color

    var body: some View {
        switch phase {
        case .done:
            CheckDot(color: accent)
        case .error:
            Circle()
                .fill(ProgressTokens.ErrorColor.accent)
                .frame(width: 10, height: 10)
        case .stalled:
            Circle()
                .fill(ProgressTokens.NeutralColor.subtle)
                .frame(width: 8, height: 8)
        case .idle, .uploading, .processing:
            PulsingDot(color: accent)
        }
    }
}

private struct PulsingDot: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let cycle = ProgressTokens.Motion.phaseDotPulseDurationMs / 1000.0
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
            let p = (1 - cos(phase * 2 * .pi)) / 2
            let scale = 1.0 + 0.4 * p
            let opacity = 1.0 - 0.45 * p

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .frame(width: 12, height: 12)
    }
}

private struct CheckDot: View {
    let color: Color
    @State private var popped = false

    var body: some View {
        ZStack {
            Circle().fill(color)
            CheckMarkShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 9, height: 9)
        }
        .frame(width: 14, height: 14)
        .scaleEffect(popped ? 1.0 : 0.4)
        .opacity(popped ? 1.0 : 0.0)
        .onAppear {
            withAnimation(
                .timingCurve(0.34, 1.56, 0.64, 1, duration: ProgressTokens.Motion.doneCheckmarkDurationMs / 1000.0)
            ) {
                popped = true
            }
        }
    }
}

private struct CheckMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height) / 9.0
        path.move(to: CGPoint(x: 1.5 * s, y: 4.8 * s))
        path.addLine(to: CGPoint(x: 3.6 * s, y: 6.8 * s))
        path.addLine(to: CGPoint(x: 7.5 * s, y: 2.2 * s))
        return path
    }
}
