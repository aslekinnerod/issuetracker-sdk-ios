import Foundation

@MainActor
final class UploadProgressMachine {
    private let onState: (IssueProgressState) -> Void
    private let stallThreshold: UInt64
    private var lastProgress: Double = 0
    private var phase: IssueProgressPhase = .idle
    private var stallTask: Task<Void, Never>?

    init(
        stallThresholdMs: Double = 3000,
        onState: @escaping (IssueProgressState) -> Void
    ) {
        self.stallThreshold = UInt64(stallThresholdMs * 1_000_000)
        self.onState = onState
    }

    func reportStart() {
        phase = .uploading
        lastProgress = 0
        emit()
        scheduleStallTimer()
    }

    func reportProgress(_ fraction: Double) {
        // Recover from stalled when bytes start flowing again. Width never
        // regresses (clamped to monotonically non-decreasing while uploading).
        if phase == .stalled {
            phase = .uploading
        }
        lastProgress = max(lastProgress, min(1.0, max(0, fraction)))
        emit()
        scheduleStallTimer()
    }

    func reportProcessing() {
        cancelStallTimer()
        phase = .processing
        lastProgress = 1.0
        emit()
    }

    func reportDone(issueId: String?) {
        cancelStallTimer()
        phase = .done
        lastProgress = 1.0
        onState(IssueProgressState(progress: 1.0, phase: .done, issueId: issueId))
    }

    func reportError(_ message: String) {
        cancelStallTimer()
        phase = .error
        onState(IssueProgressState(progress: lastProgress, phase: .error, error: message))
    }

    private func scheduleStallTimer() {
        cancelStallTimer()
        let threshold = stallThreshold
        stallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: threshold)
            guard !Task.isCancelled, let self else { return }
            guard self.phase == .uploading else { return }
            self.phase = .stalled
            self.emit()
        }
    }

    private func cancelStallTimer() {
        stallTask?.cancel()
        stallTask = nil
    }

    private func emit() {
        onState(IssueProgressState(progress: lastProgress, phase: phase))
    }
}
