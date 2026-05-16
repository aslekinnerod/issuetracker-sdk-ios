import SwiftUI
import UIKit

// Orchestrates the "show popover → submit → dismiss" flow, plus the
// side-trip through screen recording when the user taps Record video.
// Owns the hosting controller while it's on-screen so it doesn't get
// dropped.
enum ReportingSession {
    @MainActor
    private static var presented = false
    // Preserves in-progress draft data when we dismiss the sheet to
    // start a recording and re-present it afterwards.
    @MainActor
    private static var pendingDraft: ReportDraft?

    @MainActor
    static func present(runtime: Runtime) {
        // ADR-0003 Decision 9 pre-flight gate. When the SDK has been
        // terminated (project deleted, key revoked, workspace
        // suspended), every trigger that lands here shows the terminal
        // message instead of the report form — no retry, no error
        // code, no link back to our service. Survives app launches via
        // LifecycleStore's UserDefaults persistence.
        if LifecycleStore.shared.isTerminated {
            presentTerminated()
            return
        }
        if ReporterIdentity.name == nil {
            presentNamePrompt(runtime: runtime, resumingDraft: nil)
        } else {
            presentInternal(runtime: runtime, draft: nil, initialScreenshot: nil)
        }
    }

    @MainActor
    private static func presentTerminated() {
        guard !presented else { return }
        presented = true

        let view = TerminatedView(onClose: {
            topViewController()?.dismiss(animated: true) {
                presented = false
            }
        })
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .formSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }

        guard let presenter = topViewController() else {
            presented = false
            return
        }
        presenter.present(host, animated: true)
    }

    // Shown before the report UI on first use (or when the user taps
    // "Not you?" on an in-progress report). `resumingDraft` carries
    // the in-progress report forward across the re-prompt so the user
    // doesn't lose what they'd already typed.
    @MainActor
    private static func presentNamePrompt(runtime: Runtime, resumingDraft: ReportDraft?) {
        guard !presented else { return }
        presented = true
        pendingDraft = resumingDraft

        let view = NamePromptView(
            onContinue: { name in
                ReporterIdentity.setName(name)
                topViewController()?.dismiss(animated: true) {
                    presented = false
                    let draft = pendingDraft
                    pendingDraft = nil
                    presentInternal(
                        runtime: runtime,
                        draft: draft,
                        initialScreenshot: draft?.screenshot
                    )
                }
            },
            onCancel: {
                pendingDraft = nil
                topViewController()?.dismiss(animated: true) {
                    presented = false
                }
            }
        )
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .formSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }

        guard let presenter = topViewController() else {
            presented = false
            pendingDraft = nil
            return
        }
        presenter.present(host, animated: true)
    }

    @MainActor
    private static func changeReporterName(runtime: Runtime, draft: ReportDraft) {
        ReporterIdentity.clearName()
        topViewController()?.dismiss(animated: true) {
            presented = false
            presentNamePrompt(runtime: runtime, resumingDraft: draft)
        }
    }

    @MainActor
    private static func presentInternal(
        runtime: Runtime,
        draft: ReportDraft?,
        initialScreenshot: UIImage?
    ) {
        guard !presented else { return }
        presented = true

        // If we're coming back from a recording, the draft already has
        // a screenshot (or none). Otherwise capture fresh.
        let screenshot = initialScreenshot ?? draft?.screenshot ?? ScreenshotCapture.captureCurrentWindow()
        let videoURL = draft?.videoURL

        let view = ReportView(
            screenshot: screenshot,
            videoURL: videoURL,
            initialDraft: draft,
            reporterName: ReporterIdentity.name ?? "",
            submit: { title, description, type, includeScreenshot, includeVideoURL, onState in
                await submit(
                    runtime: runtime,
                    title: title,
                    description: description,
                    type: type,
                    screenshot: includeScreenshot ? screenshot : nil,
                    videoURL: includeVideoURL,
                    onState: onState
                )
            },
            onStartRecording: { capturedDraft in
                startRecording(runtime: runtime, draft: capturedDraft)
            },
            onChangeName: { capturedDraft in
                changeReporterName(runtime: runtime, draft: capturedDraft)
            },
            onClose: { dismiss() }
        )
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .formSheet

        guard let presenter = topViewController() else {
            presented = false
            return
        }
        presenter.present(host, animated: true)
    }

    @MainActor
    private static func startRecording(runtime: Runtime, draft: ReportDraft) {
        pendingDraft = draft
        // Drop the sheet so the user can navigate the host app freely.
        topViewController()?.dismiss(animated: true) {
            Task { @MainActor in
                do {
                    try await RecordingController.shared.start()
                    if let scene = keyWindowScene() {
                        FloatingStopPill.shared.show(in: scene) {
                            Task { @MainActor in await stopAndResume(runtime: runtime) }
                        }
                    }
                    presented = false
                } catch {
                    // Recording failed to start — re-present the sheet
                    // with an error so the user knows why.
                    presented = false
                    var draft = pendingDraft ?? ReportDraft()
                    draft.videoURL = nil
                    pendingDraft = nil
                    presentInternal(runtime: runtime, draft: draft, initialScreenshot: draft.screenshot)
                    // The sheet's error text is set by the caller; we
                    // print here so consumers see what happened.
                    print("[Issuetracker] recording failed: \(error)")
                }
            }
        }
    }

    @MainActor
    private static func stopAndResume(runtime: Runtime) async {
        FloatingStopPill.shared.hide()
        let url: URL?
        do {
            url = try await RecordingController.shared.stop()
        } catch {
            print("[Issuetracker] recording stop failed: \(error)")
            url = nil
        }
        var draft = pendingDraft ?? ReportDraft()
        draft.videoURL = url
        pendingDraft = nil
        presentInternal(runtime: runtime, draft: draft, initialScreenshot: draft.screenshot)
    }

    @MainActor
    private static func dismiss() {
        topViewController()?.dismiss(animated: true)
        presented = false
        pendingDraft = nil
    }

    @MainActor
    private static func submit(
        runtime: Runtime,
        title: String,
        description: String,
        type: IssueReportType,
        screenshot: UIImage?,
        videoURL: URL?,
        onState: @MainActor @escaping (IssueProgressState) -> Void
    ) async -> Result<Void, Error> {
        struct CreateResult: Decodable { let issueId: String }
        let machine = UploadProgressMachine(onState: onState)
        do {
            var payload: [String: Any] = [
                "apiKey": runtime.apiKey,
                "title": title,
                "type": type.rawValue,
                "context": ContextCollector.collect(),
                "reporter": ReporterIdentity.payload(),
            ]
            if !description.isEmpty {
                payload["description"] = description
            }
            if let screenshot,
               let data = screenshot.jpegData(compressionQuality: 0.85) {
                payload["screenshot"] = [
                    "base64": data.base64EncodedString(),
                    "contentType": "image/jpeg",
                    "name": "screenshot-\(Int(Date().timeIntervalSince1970)).jpg",
                ]
            }
            // Video: read the file and base64-encode inline. 20 MiB
            // client cap leaves headroom under Firebase's 32 MiB
            // callable payload limit after the 33% base64 overhead.
            // Anything larger is silently dropped — UI shows a warning
            // before the user tries to submit.
            if let videoURL,
               let data = try? Data(contentsOf: videoURL),
               data.count <= 20 * 1024 * 1024 {
                payload["video"] = [
                    "base64": data.base64EncodedString(),
                    "contentType": "video/mp4",
                    "name": "recording-\(Int(Date().timeIntervalSince1970)).mp4",
                ]
            }
            let crumbs = BreadcrumbStore.shared.snapshot()
            if !crumbs.isEmpty {
                payload["breadcrumbs"] = crumbs.map { b -> [String: Any] in
                    var dict: [String: Any] = [
                        "timestamp": Int(b.timestamp.timeIntervalSince1970 * 1000),
                        "action": b.action,
                    ]
                    if let metadata = b.metadata {
                        dict["metadata"] = metadata
                    }
                    return dict
                }
            }
            machine.reportStart()
            let result: CreateResult = try await APIClient.uploadWithProgress(
                endpoint: runtime.endpoint,
                function: "createIssueFromSdk",
                payload: payload,
                onProgress: { fraction in machine.reportProgress(fraction) },
                onProcessing: { machine.reportProcessing() }
            )
            machine.reportDone(issueId: result.issueId)
            return .success(())
        } catch let err as APIClient.CallableError {
            // ADR-0003 Decision 9: non-recoverable failures flip the
            // SDK into one-way TERMINATED. The user sees this submit's
            // error message in the current sheet; the next trigger
            // (shake / long-press / programmatic) will hit the
            // pre-flight gate in present() and surface TerminatedView.
            if let reason = err.sdkErrorReason, !reason.isRecoverable {
                LifecycleStore.shared.transitionToTerminated(
                    reason: reason,
                    callback: runtime.onConfigurationError
                )
            }
            machine.reportError(err.localizedDescription)
            return .failure(err)
        } catch {
            machine.reportError(error.localizedDescription)
            return .failure(error)
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        guard
            let scene = keyWindowScene(),
            let root = scene.windows
                .first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController
        else {
            return nil
        }
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }

    @MainActor
    private static func keyWindowScene() -> UIWindowScene? {
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
    }
}
