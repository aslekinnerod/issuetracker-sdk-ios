import SwiftUI
import UIKit

// Popover shown when the user shakes the device (or calls report()
// explicitly). Deliberately minimal — title, optional description,
// type picker, screenshot thumbnail, optional video, submit. No
// priority/assignee/labels from the SDK; server-side everything
// defaults (priority=none, unassigned, state=todo, source=sdk).
//
// Draft state survives the sheet being dismissed during recording.
// Populated from the current ReportView on "Record video" and
// re-applied when the sheet comes back. Everything's optional so the
// initial sheet can pass nil.
struct ReportDraft {
    var title: String = ""
    var description: String = ""
    var type: IssueReportType = .bug
    var screenshot: UIImage?
    var videoURL: URL?
}

struct ReportView: View {
    // @State because the editor can replace it with an annotated
    // version. Original is retained via the editor only emitting an
    // edited image when the user confirms.
    @State var screenshot: UIImage?
    @State var videoURL: URL?
    let initialDraft: ReportDraft?
    let reporterName: String
    let submit: (_ title: String, _ description: String, _ type: IssueReportType, _ includeScreenshot: Bool, _ videoURL: URL?) async -> Result<Void, Error>
    let onStartRecording: (ReportDraft) -> Void
    let onChangeName: (ReportDraft) -> Void
    let onClose: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var type: IssueReportType = .bug
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var includeScreenshot: Bool = true
    @State private var includeVideo: Bool = true
    @State private var showingEditor: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Tokens.lineFaint)
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                    if !reporterName.isEmpty {
                        reportingAsRow
                    }
                    titleField
                    typeField
                    descriptionField
                    if let screenshot { screenshotSection(screenshot: screenshot) }
                    videoSection
                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.critical)
                    }
                }
                .padding(Tokens.Space.s5)
            }
            Divider().background(Tokens.lineFaint)
            footer
        }
        .background(Tokens.surfaceCard)
        .fullScreenCover(isPresented: $showingEditor) {
            if let current = screenshot {
                ScreenshotEditorView(originalImage: current) { edited in
                    showingEditor = false
                    if let edited { screenshot = edited }
                }
            }
        }
        .onAppear {
            guard let d = initialDraft else { return }
            if title.isEmpty { title = d.title }
            if description.isEmpty { description = d.description }
            type = d.type
            if screenshot == nil { screenshot = d.screenshot }
            if videoURL == nil { videoURL = d.videoURL }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s4) {
            BrandHeader(
                title: "Tell us what broke",
                subtitle: "Goes to the team triaging this app."
            )
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Tokens.fg3)
                    .frame(width: 32, height: 32)
            }
            .disabled(isSubmitting)
        }
        .padding(.horizontal, Tokens.Space.s5)
        .padding(.vertical, Tokens.Space.s4)
    }

    private var reportingAsRow: some View {
        HStack(spacing: 8) {
            Text("Reporting as \(reporterName)")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.fg3)
            Spacer()
            Button("Not you?") {
                onChangeName(currentDraft())
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Tokens.accent)
            .disabled(isSubmitting)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: "Title")
            BrandTextField(
                value: $title,
                placeholder: "Short summary, e.g. checkout button does nothing"
            )
        }
    }

    private var typeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: "Type")
            HStack(spacing: 6) {
                ForEach(IssueReportType.allCases, id: \.self) { t in
                    BrandChip(
                        t.displayName,
                        icon: sfSymbol(for: t),
                        isActive: type == t
                    ) {
                        type = t
                    }
                }
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: "What happened?")
            BrandTextField(
                value: $description,
                placeholder: "What did you expect, and what happened instead?",
                multiline: true
            )
        }
    }

    private func screenshotSection(screenshot: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FieldLabel(title: "Screenshot")
                Spacer()
                Toggle("", isOn: $includeScreenshot)
                    .labelsHidden()
                    .tint(Tokens.accent)
            }
            if includeScreenshot {
                Button {
                    showingEditor = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: screenshot)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusMd))
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.radiusMd)
                                    .stroke(Tokens.line, lineWidth: 1)
                            )
                        HStack(spacing: 4) {
                            Image(systemName: "pencil.tip")
                                .font(.system(size: 11, weight: .medium))
                            Text("Edit")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Tokens.surfaceCard)
                        .foregroundStyle(Tokens.fg1)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.radiusSm)
                                .stroke(Tokens.line, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSm))
                        .padding(8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "Recording")
            if let videoURL {
                videoRow(url: videoURL)
            } else {
                BrandButton("Record video", icon: "record.circle", variant: .secondary) {
                    onStartRecording(currentDraft())
                }
            }
        }
    }

    private func videoRow(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .foregroundStyle(Tokens.accent)
                    .font(.system(size: 14, weight: .medium))
                Text(videoSummary(url: url))
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.fg1)
                Spacer()
                Toggle("", isOn: $includeVideo)
                    .labelsHidden()
                    .tint(Tokens.accent)
                Button {
                    self.videoURL = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.fg3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Tokens.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.radiusSm)
                    .stroke(Tokens.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSm))
            if videoTooLarge(url: url) {
                Text("Recording is larger than 20 MB — trim it to include it with the report.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.warning)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            BrandButton("Cancel", variant: .ghost, isDisabled: isSubmitting) {
                onClose()
            }
            .frame(maxWidth: 100)
            BrandButton(
                "Send report",
                icon: "paperplane.fill",
                variant: .primary,
                isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty,
                isLoading: isSubmitting
            ) {
                Task { await perform() }
            }
            .frame(maxWidth: 160)
        }
        .padding(Tokens.Space.s4)
        .background(Tokens.surfaceApp)
    }

    // MARK: - Actions

    private func perform() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let result = await submit(
            title.trimmingCharacters(in: .whitespaces),
            description,
            type,
            includeScreenshot && screenshot != nil,
            (includeVideo ? videoURL : nil)
        )
        switch result {
        case .success:
            onClose()
        case .failure(let err):
            error = err.localizedDescription
        }
    }

    private func currentDraft() -> ReportDraft {
        ReportDraft(
            title: title,
            description: description,
            type: type,
            screenshot: screenshot,
            videoURL: videoURL
        )
    }

    private func videoSummary(url: URL) -> String {
        let bytes = fileSizeBytes(url: url)
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "Recording · %.1f MB", mb)
    }

    private func videoTooLarge(url: URL) -> Bool {
        return fileSizeBytes(url: url) > 20 * 1024 * 1024
    }

    private func fileSizeBytes(url: URL) -> Int64 {
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func sfSymbol(for type: IssueReportType) -> String {
        // Map IssueReportType to an SF Symbol that's roughly equivalent
        // to the Lucide icons in the design system reference (`bug`,
        // `checkmark.square`, `book.closed`).
        switch type {
        case .bug: return "ladybug.fill"
        case .task: return "checklist"
        case .story: return "book.closed.fill"
        }
    }
}
