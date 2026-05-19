import SwiftUI
import IssuetrackerSDK

/// Single-screen demo. Every meaningful SDK surface gets a section
/// card with one or two affordances + a short explanation, so a
/// person who's never seen the SDK can shake-test it in 30 seconds.
///
/// Same feature checklist as the Android, Flutter, and RN sample
/// apps — see example-app/README.md.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LifecycleSection()
                    ReportingSection()
                    IdentitySection()
                    BreadcrumbSection()
                    OnboardingSection()
                    I18nSection()
                    DestructiveSection()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Issuetracker SDK demo")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Section Card

private struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            content()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Lifecycle

private struct LifecycleSection: View {
    @State private var lastError: String? = UserDefaults.standard.string(forKey: PREF_LAST_ERROR)
    @State private var lastErrorAt: Double = UserDefaults.standard.double(forKey: PREF_LAST_ERROR_AT)

    var body: some View {
        SectionCard(title: "Lifecycle", subtitle: subtitleText) {
            Button("Reset last error") {
                UserDefaults.standard.removeObject(forKey: PREF_LAST_ERROR)
                UserDefaults.standard.removeObject(forKey: PREF_LAST_ERROR_AT)
                lastError = nil
                lastErrorAt = 0
            }
            .buttonStyle(.bordered)
        }
    }

    private var subtitleText: String {
        guard let lastError, lastErrorAt > 0 else {
            return "Listening for onConfigurationError. Nothing fired yet."
        }
        let mins = Int((Date().timeIntervalSince1970 - lastErrorAt) / 60)
        let when = mins < 1 ? "just now" : "\(mins) min ago"
        return "Last onConfigurationError: \(lastError) (\(when))"
    }
}

// MARK: - Reporting

private struct ReportingSection: View {
    var body: some View {
        SectionCard(
            title: "Reporting",
            subtitle: "Shake the device, two-finger long-press (3s), or tap the button."
        ) {
            Button {
                Issuetracker.report()
            } label: {
                Text("Report a bug")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Identity

private struct IdentitySection: View {
    @State private var name: String = ""
    @State private var feedback: String? = nil

    var body: some View {
        SectionCard(
            title: "Identity",
            subtitle: "Skips the in-form name prompt and stamps every report."
        ) {
            TextField("Display name (e.g. Kari Nordmann)", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Button {
                    let v = name.trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty {
                        Issuetracker.identify(name: v)
                        feedback = "Saved \"\(v)\""
                    }
                } label: {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Issuetracker.clearIdentity()
                    name = ""
                    feedback = "Cleared."
                } label: {
                    Text("Clear").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Breadcrumbs

private struct BreadcrumbSection: View {
    @State private var recent: [String] = []

    var body: some View {
        SectionCard(
            title: "Breadcrumbs",
            subtitle: "Last 5 actions ride along with every report."
        ) {
            HStack(spacing: 8) {
                Button {
                    Issuetracker.recordAction("viewed_home")
                    recent = (recent + ["viewed_home"]).suffix(5).map { $0 }
                } label: {
                    Text("viewed_home").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Issuetracker.recordAction("tapped_button", metadata: ["id": "settings"])
                    recent = (recent + ["tapped_button"]).suffix(5).map { $0 }
                } label: {
                    Text("tapped_button").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if !recent.isEmpty {
                Text("Recorded: " + recent.joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Onboarding

private struct OnboardingSection: View {
    var body: some View {
        SectionCard(
            title: "Onboarding",
            subtitle: "Re-show the trigger introduction popover regardless of whether it has been shown before."
        ) {
            Button("Show intro again") {
                Issuetracker.showOnboarding()
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - i18n

private struct I18nSection: View {
    @State private var useNorwegian: Bool = UserDefaults.standard.bool(forKey: PREF_USE_NORWEGIAN)

    var body: some View {
        SectionCard(
            title: "TERMINATED-UI i18n",
            subtitle: "When ON, the SDK shows the terminal screen in Norwegian. Restart the app to apply (configure(...) runs once in App.init)."
        ) {
            Toggle(isOn: $useNorwegian) {
                Text("Norwegian strings")
            }
            .onChange(of: useNorwegian) { newValue in
                UserDefaults.standard.set(newValue, forKey: PREF_USE_NORWEGIAN)
            }
        }
    }
}

// MARK: - Destructive

private struct DestructiveSection: View {
    @State private var confirm = false

    var body: some View {
        SectionCard(
            title: "Destructive",
            subtitle: "Test the crash-reporting flow. The app will die immediately and the SDK files an issue on next launch."
        ) {
            Button(role: .destructive) {
                confirm = true
            } label: {
                Text("Force crash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .confirmationDialog(
            "Force crash",
            isPresented: $confirm,
            titleVisibility: .visible
        ) {
            Button("Crash now", role: .destructive) {
                Issuetracker._testCrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will throw and the app process will die. Re-open the app and the SDK will queue a crash report on the next launch.")
        }
    }
}

#Preview {
    ContentView()
}
