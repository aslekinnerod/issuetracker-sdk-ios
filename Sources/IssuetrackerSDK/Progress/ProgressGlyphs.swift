import SwiftUI

struct BugGlyph: View {
    let color: Color
    let wobble: Bool

    var body: some View {
        TimelineView(.animation(paused: !wobble)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 1000.0
            let angle = wobble ? sin(t / 120.0) * ProgressTokens.Motion.iconWobbleAmplitudeDeg : 0
            let leg = wobble ? sin(t / 90.0) * 1.5 : 0
            BugShape(legWiggle: leg)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .background(BugBody(color: color))
                .rotationEffect(.degrees(angle))
        }
        .frame(width: ProgressTokens.Icon.glyph, height: ProgressTokens.Icon.glyph)
    }
}

private struct BugShape: Shape {
    let legWiggle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height) / 24.0
        let lw = legWiggle

        // 6 legs
        path.move(to: CGPoint(x: 6 * s, y: 9 * s))
        path.addLine(to: CGPoint(x: (2 + lw) * s, y: (7 - lw) * s))

        path.move(to: CGPoint(x: 6 * s, y: 13 * s))
        path.addLine(to: CGPoint(x: (2 - lw) * s, y: 13 * s))

        path.move(to: CGPoint(x: 6 * s, y: 17 * s))
        path.addLine(to: CGPoint(x: (2 + lw) * s, y: (19 + lw) * s))

        path.move(to: CGPoint(x: 18 * s, y: 9 * s))
        path.addLine(to: CGPoint(x: (22 - lw) * s, y: (7 + lw) * s))

        path.move(to: CGPoint(x: 18 * s, y: 13 * s))
        path.addLine(to: CGPoint(x: (22 + lw) * s, y: 13 * s))

        path.move(to: CGPoint(x: 18 * s, y: 17 * s))
        path.addLine(to: CGPoint(x: (22 - lw) * s, y: (19 - lw) * s))

        // 2 antennas
        path.move(to: CGPoint(x: 9 * s, y: 5 * s))
        path.addQuadCurve(
            to: CGPoint(x: 6 * s, y: 2 * s),
            control: CGPoint(x: 7 * s, y: (2 + lw) * s)
        )

        path.move(to: CGPoint(x: 15 * s, y: 5 * s))
        path.addQuadCurve(
            to: CGPoint(x: 18 * s, y: 2 * s),
            control: CGPoint(x: 17 * s, y: (2 - lw) * s)
        )

        return path
    }
}

private struct BugBody: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 24.0
            ZStack {
                Ellipse()
                    .fill(color)
                    .frame(width: 11 * s, height: 14 * s)
                    .position(x: 12 * s, y: 13 * s)

                Path { p in
                    p.move(to: CGPoint(x: 12 * s, y: 7 * s))
                    p.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
                }
                .stroke(Color.white.opacity(0.55), lineWidth: 1.2)

                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 1.8 * s, height: 1.8 * s)
                    .position(x: 10.4 * s, y: 10 * s)
            }
        }
    }
}

struct TaskGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 24.0
            ZStack {
                RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 18 * s, height: 18 * s)
                    .position(x: 12 * s, y: 12 * s)

                RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 18 * s, height: 18 * s)
                    .position(x: 12 * s, y: 12 * s)

                Path { p in
                    p.move(to: CGPoint(x: 7.5 * s, y: 12.2 * s))
                    p.addLine(to: CGPoint(x: 10.5 * s, y: 15 * s))
                    p.addLine(to: CGPoint(x: 16.5 * s, y: 8.5 * s))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: ProgressTokens.Icon.glyph, height: ProgressTokens.Icon.glyph)
    }
}

struct StoryGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 24.0
            ZStack {
                BookShape()
                    .fill(color.opacity(0.16))
                BookShape()
                    .stroke(color, lineWidth: 1.4)
                Path { p in
                    p.move(to: CGPoint(x: 12 * s, y: 4.2 * s))
                    p.addLine(to: CGPoint(x: 12 * s, y: 18.2 * s))
                }
                .stroke(color, lineWidth: 1.2)
            }
        }
        .frame(width: ProgressTokens.Icon.glyph, height: ProgressTokens.Icon.glyph)
    }
}

private struct BookShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height) / 24.0
        path.move(to: CGPoint(x: 3 * s, y: 5 * s))
        path.addQuadCurve(
            to: CGPoint(x: 21 * s, y: 5 * s),
            control: CGPoint(x: 12 * s, y: 3 * s)
        )
        path.addLine(to: CGPoint(x: 21 * s, y: 19 * s))
        path.addQuadCurve(
            to: CGPoint(x: 3 * s, y: 19 * s),
            control: CGPoint(x: 12 * s, y: 17 * s)
        )
        path.closeSubpath()
        return path
    }
}
