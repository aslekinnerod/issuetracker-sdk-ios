import SwiftUI
import UIKit

// Popover shown when the user shakes the device (or calls report()
// explicitly). Deliberately minimal — title, optional description,
// screenshot thumbnail, submit. No priority/assignee/labels from the
// SDK; server-side everything defaults (priority=none, unassigned,
// state=todo, source=sdk).
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
    // Now @State because the editor can replace it with an annotated
    // version. Original is retained via editedScreenshot being nil.
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
        NavigationStack {
            Form {
                if !reporterName.isEmpty {
                    Section {
                        HStack {
                            Text("Reporting as \(reporterName)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Not you?") {
                                onChangeName(currentDraft())
                            }
                            .font(.footnote)
                            .disabled(isSubmitting)
                        }
                    }
                }

                Section {
                    Picker("Type", selection: $type) {
                        ForEach(IssueReportType.allCases, id: \.self) { t in
                            Label(t.displayName, systemImage: t.icon).tag(t)
                        }
                    }
                    TextField("What happened?", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Steps, expected vs. actual, anything else…",
                              text: $description,
                              axis: .vertical)
                        .lineLimit(3...8)
                }

                if let screenshot {
                    Section {
                        Toggle("Include screenshot", isOn: $includeScreenshot)
                        if includeScreenshot {
                            Button {
                                showingEditor = true
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: screenshot)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    Image(systemName: "pencil.tip.crop.circle")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .font(.title2)
                                        .padding(6)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    if let videoURL {
                        Toggle("Include video", isOn: $includeVideo)
                        if includeVideo {
                            HStack {
                                Image(systemName: "video.fill")
                                    .foregroundStyle(.red)
                                Text(videoSummary(url: videoURL))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    self.videoURL = nil
                                }
                                .font(.footnote)
                            }
                            if videoTooLarge(url: videoURL) {
                                Text("Recording is larger than 20 MB — trim it to include it with the report.")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Button {
                            onStartRecording(currentDraft())
                        } label: {
                            Label("Record video", systemImage: "record.circle")
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Report an issue")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showingEditor) {
                if let current = screenshot {
                    ScreenshotEditorView(originalImage: current) { edited in
                        showingEditor = false
                        if let edited { screenshot = edited }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await perform() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(isSubmitting || title.trimmingCharacters(in: .whitespaces).isEmpty)
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
    }

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
}

