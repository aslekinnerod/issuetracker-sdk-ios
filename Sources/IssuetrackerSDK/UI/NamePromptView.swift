import SwiftUI

// Shown as a modal sheet the first time the user triggers a report on
// a fresh install (no stored name). Once the user fills in a name and
// taps Continue, the name is persisted to ReporterIdentity and this
// view is replaced by the normal ReportView. Canceling closes the
// whole report flow without submitting anything.
struct NamePromptView: View {
    let onContinue: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: Tokens.Space.s4) {
                BrandHeader(
                    title: "One thing first",
                    subtitle: "Stored only on this device."
                )
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .brandFont(14, .medium, relativeTo: .subheadline)
                        .foregroundStyle(Tokens.fg3)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Tokens.Space.s5)
            .padding(.vertical, Tokens.Space.s4)
            Divider().background(Tokens.lineFaint)

            // Body — scrolls so large Dynamic Type sizes don't clip
            // (1.4.4 / 1.4.10).
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldLabel(title: "Your name")
                        BrandTextField(
                            value: $name,
                            label: "Your name",
                            placeholder: "What should we call you?"
                        )
                        .focused($focused)
                        .submitLabel(.continue)
                        .onSubmit(submitIfValid)
                    }
                    Text("This name appears on the issues you report so the team knows who filed them.")
                        .brandFont(12, relativeTo: .caption)
                        .foregroundStyle(Tokens.fg3)
                }
                .padding(Tokens.Space.s5)
            }

            Spacer(minLength: 0)
            Divider().background(Tokens.lineFaint)

            // Footer
            HStack(spacing: 8) {
                Spacer()
                BrandButton("Cancel", variant: .ghost) { onCancel() }
                    .frame(maxWidth: 100)
                BrandButton(
                    "Continue",
                    variant: .primary,
                    isDisabled: trimmed.isEmpty
                ) {
                    submitIfValid()
                }
                .frame(maxWidth: 140)
            }
            .padding(Tokens.Space.s4)
            .background(Tokens.surfaceApp)
        }
        .background(Tokens.surfaceCard)
        .onAppear { focused = true }
    }

    private func submitIfValid() {
        guard !trimmed.isEmpty else { return }
        onContinue(trimmed)
    }
}
