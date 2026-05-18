import SwiftUI

// First-launch popover that teaches the user which gestures trigger
// the reporter. Shown only when the host app opts in via
// `Issuetracker.configure(showOnboarding: true)` AND at least one
// gesture is enabled. Persisted via OnboardingStore so we never
// nag the same install twice — unless the host app calls
// `Issuetracker.showOnboarding()` explicitly.
//
// The illustrations are loaded from Resources/Onboarding.xcassets as
// vector assets (`Image("onboarding-shake", bundle: .module)` /
// `Image("onboarding-longpress", bundle: .module)`). Until the SVGs
// land, an SF Symbol placeholder is rendered so layout + spacing can
// be validated end-to-end.
struct OnboardingView: View {
    let showsShake: Bool
    let showsLongPress: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top brand bar — same shield+title pattern as ReportView,
            // so the popover feels like the same product.
            BrandHeader(
                title: "Report bugs from anywhere",
                subtitle: visibleTriggerCount == 1
                    ? "One quick gesture is all it takes"
                    : "Two quick gestures, your choice"
            )
            .padding(.horizontal, Tokens.Space.s6)
            .padding(.top, Tokens.Space.s7)
            .padding(.bottom, Tokens.Space.s6)

            // Body — one tile per enabled trigger. The view above
            // guarantees `visibleTriggerCount >= 1`, so we always
            // render at least one tile here.
            VStack(spacing: Tokens.Space.s5) {
                if showsShake {
                    TriggerTile(
                        illustration: "onboarding-shake",
                        placeholderSymbol: "iphone.gen3.radiowaves.left.and.right",
                        title: "Shake your phone",
                        caption: "Shake to open the reporter."
                    )
                }
                if showsLongPress {
                    TriggerTile(
                        illustration: "onboarding-longpress",
                        placeholderSymbol: "hand.tap.fill",
                        title: "Two-finger press",
                        caption: "Hold with two fingers for 3 seconds."
                    )
                }
            }
            .padding(.horizontal, Tokens.Space.s6)

            Spacer(minLength: Tokens.Space.s7)

            BrandButton("Got it", variant: .primary, action: onDismiss)
                .padding(.horizontal, Tokens.Space.s6)
                .padding(.bottom, Tokens.Space.s6)
        }
        .background(Tokens.surfaceApp.ignoresSafeArea())
    }

    private var visibleTriggerCount: Int {
        (showsShake ? 1 : 0) + (showsLongPress ? 1 : 0)
    }
}

// Single illustration + copy block. Uses the bundled asset if it
// resolves at runtime, otherwise falls back to an SF Symbol so the
// layout works during development before the final SVGs land.
private struct TriggerTile: View {
    let illustration: String
    let placeholderSymbol: String
    let title: String
    let caption: String

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s5) {
            illustrationView
                .frame(width: 88, height: 88)
                .background(Tokens.surface1)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusMd))

            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.fg1)
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s4)
        .background(Tokens.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.radiusMd)
                .stroke(Tokens.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusMd))
    }

    @ViewBuilder
    private var illustrationView: some View {
        // Bundle.module lookup; falls back to an SF Symbol placeholder
        // if the asset hasn't been added to Resources/Onboarding.xcassets
        // (e.g. during initial SDK development).
        if UIImage(named: illustration, in: .module, with: nil) != nil {
            Image(illustration, bundle: .module)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .padding(Tokens.Space.s4)
        } else {
            Image(systemName: placeholderSymbol)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Tokens.accent)
        }
    }
}
