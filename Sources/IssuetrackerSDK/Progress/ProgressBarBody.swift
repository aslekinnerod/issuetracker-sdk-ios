import SwiftUI

struct ProgressBarBody: View {
    let variant: ProgressVariant
    let state: IssueProgressState
    let title: String
    let copy: IssueProgressCopy

    private var presentation: ProgressPresentation {
        ProgressPresentation.make(variant: variant, state: state, copy: copy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, ProgressTokens.Gap.headerToTrack)

            ProgressFill(presentation: presentation, variant: variant)
                .frame(height: variant.trackHeight)
                .padding(.bottom, ProgressTokens.Gap.trackToStatus)

            statusRow
        }
        .padding(ProgressTokens.Card.padding)
        .background(
            RoundedRectangle(cornerRadius: ProgressTokens.Card.radius, style: .continuous)
                .fill(ProgressTokens.NeutralColor.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ProgressTokens.Card.radius, style: .continuous)
                .stroke(ProgressTokens.NeutralColor.line, lineWidth: ProgressTokens.Card.borderWidth)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 0, x: 0, y: 1)
        .shadow(color: Color.black.opacity(0.06), radius: 24, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(variant.kindText))
        .accessibilityValue(accessibilityValue)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: ProgressTokens.Gap.header) {
            iconFrame
            VStack(alignment: .leading, spacing: 2) {
                Text(variant.kindText)
                    .brandFont(ProgressTokens.TypeSize.kind, ProgressTokens.TypeWeight.kind, relativeTo: .caption2, design: .monospaced)
                    .tracking(ProgressTokens.TypeSize.kind * 0.12)
                    .foregroundStyle(presentation.tintIsError ? ProgressTokens.ErrorColor.accent : variant.accentDark)
                Text(title)
                    .brandFont(ProgressTokens.TypeSize.title, ProgressTokens.TypeWeight.title, relativeTo: .body)
                    .foregroundStyle(ProgressTokens.NeutralColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            badge
        }
    }

    private var iconFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ProgressTokens.Icon.frameRadius, style: .continuous)
                .fill(presentation.tintIsError ? ProgressTokens.ErrorColor.soft : variant.accentSoft)

            glyph
        }
        .frame(width: ProgressTokens.Icon.frame, height: ProgressTokens.Icon.frame)
    }

    @ViewBuilder
    private var glyph: some View {
        // WCAG 1.4.11: the glyph is a meaningful graphic — use the
        // variant's graphic colour where defined (story), else accent.
        let color: Color = presentation.tintIsError ? ProgressTokens.ErrorColor.accent : variant.graphicOrAccent
        switch variant {
        case .bug:
            BugGlyph(color: color, wobble: presentation.iconWobbles)
        case .task:
            TaskGlyph(color: color)
        case .story:
            StoryGlyph(color: color)
        }
    }

    private var badge: some View {
        Text(presentation.badgeText)
            .brandFont(ProgressTokens.TypeSize.badge, ProgressTokens.TypeWeight.badge, relativeTo: .caption, design: .monospaced)
            .tracking(ProgressTokens.TypeSize.badge * 0.04)
            .monospacedDigit()
            .foregroundStyle(presentation.tintIsError ? ProgressTokens.ErrorColor.accent : variant.accentDark)
            .padding(.vertical, ProgressTokens.Badge.paddingV)
            .padding(.horizontal, ProgressTokens.Badge.paddingH)
            .frame(minWidth: ProgressTokens.Badge.minWidth)
            .background(
                RoundedRectangle(cornerRadius: ProgressTokens.Badge.radius, style: .continuous)
                    .fill(presentation.tintIsError ? ProgressTokens.ErrorColor.soft : variant.accentSoft)
            )
    }

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 8) {
            PhaseDot(phase: state.phase, accent: variant.accent)
                .frame(width: 14, alignment: .center)
            Text(presentation.statusText)
                .brandFont(ProgressTokens.TypeSize.status, ProgressTokens.TypeWeight.status, relativeTo: .footnote)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var statusColor: Color {
        if presentation.tintIsError { return ProgressTokens.ErrorColor.accent }
        if state.phase == .done { return variant.accentDark }
        return ProgressTokens.NeutralColor.statusBody
    }

    private var accessibilityValue: Text {
        switch state.phase {
        case .processing, .stalled:
            return Text(presentation.statusText)
        default:
            return Text("\(Int(presentation.fillWidthPercent)) percent")
        }
    }
}
