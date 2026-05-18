import SwiftUI

/// Shown in place of the report form when the SDK is in the
/// `.terminated` state — the server has signalled that the bound
/// project is gone, the API key is revoked, or the workspace is
/// suspended. No retry button, no raw error code, no link back to our
/// service. ADR-0003 Decision 9.
///
/// Strings come from ``Issuetracker/configure(apiKey:...)``'s
/// `terminatedUI` argument; English defaults apply for any field the
/// host doesn't override. Sister i18n hooks exist on sdk-android and
/// sdk-web.
struct TerminatedView: View {
    let strings: TerminatedUiStrings?
    let onClose: () -> Void

    private static let defaultTitle = "Bug reporting is no longer available."
    private static let defaultSubtitle = "Contact your team."
    private static let defaultCloseLabel = "Close"

    var body: some View {
        VStack(spacing: Tokens.Space.s5) {
            HStack {
                Spacer()
                Button(strings?.closeLabel ?? Self.defaultCloseLabel, action: onClose)
                    .foregroundStyle(Tokens.fg2)
            }
            .padding(.horizontal, Tokens.Space.s5)
            .padding(.top, Tokens.Space.s4)

            Spacer()

            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Tokens.fg3)

            VStack(spacing: Tokens.Space.s3) {
                Text(strings?.title ?? Self.defaultTitle)
                    .font(.headline)
                    .foregroundStyle(Tokens.fg1)
                    .multilineTextAlignment(.center)

                Text(strings?.subtitle ?? Self.defaultSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Tokens.fg2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Tokens.Space.s6)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.surfaceApp)
    }
}
