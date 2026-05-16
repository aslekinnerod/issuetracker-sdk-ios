import SwiftUI

/// Shown in place of the report form when the SDK is in the
/// `.terminated` state — the server has signalled that the bound
/// project is gone, the API key is revoked, or the workspace is
/// suspended. No retry button, no raw error code, no link back to our
/// service. ADR-0003 Decision 9.
///
/// TODO (Phase C): localise these strings. Held as hardcoded English
/// in Phase B because the rest of the SDK has no i18n infrastructure
/// yet — localising only the terminal view would create inconsistent
/// UX. When i18n lands across the SDK, swap `Text("...")` for the
/// localised lookups in one pass.
struct TerminatedView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: Tokens.Space.s5) {
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .foregroundStyle(Tokens.fg2)
            }
            .padding(.horizontal, Tokens.Space.s5)
            .padding(.top, Tokens.Space.s4)

            Spacer()

            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Tokens.fg3)

            VStack(spacing: Tokens.Space.s3) {
                Text("Bug reporting is no longer available.")
                    .font(.headline)
                    .foregroundStyle(Tokens.fg1)
                    .multilineTextAlignment(.center)

                Text("Contact your team.")
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
