import SwiftUI

// Shown as a modal sheet the first time the user triggers a report
// on a fresh install (no stored name). Once the user fills in a name
// and taps Continue, the name is persisted to ReporterIdentity and
// this view is replaced by the normal ReportView. Canceling closes
// the whole report flow without submitting anything.
struct NamePromptView: View {
    let onContinue: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.continue)
                        .onSubmit(submitIfValid)
                } header: {
                    Text("What should we call you?")
                } footer: {
                    Text("This name appears on the issues you report so the team knows who filed them. Stored only on this device.")
                }
            }
            .navigationTitle("One thing first")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: submitIfValid)
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func submitIfValid() {
        guard !trimmed.isEmpty else { return }
        onContinue(trimmed)
    }
}
