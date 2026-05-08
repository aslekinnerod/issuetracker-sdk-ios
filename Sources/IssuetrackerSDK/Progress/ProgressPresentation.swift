import Foundation

struct ProgressPresentation: Equatable {
    var fillWidthPercent: Double
    var badgeText: String
    var statusText: String
    var tintIsError: Bool
    var indeterminateActive: Bool
    var deterministicFillVisible: Bool
    var iconWobbles: Bool
    var fillIsAnimating: Bool

    static func make(
        variant: ProgressVariant,
        state: IssueProgressState,
        copy: IssueProgressCopy
    ) -> ProgressPresentation {
        let clamped = max(0.0, min(1.0, state.progress))
        let percent = Int(clamped * 100.0)

        let isError = state.phase == .error
        let isProcessing = state.phase == .processing
        let isDone = state.phase == .done
        let isStalled = state.phase == .stalled
        let isUploading = state.phase == .uploading

        let badgeText: String
        if isDone {
            badgeText = state.issueId ?? variant.fallbackIssueId
        } else {
            badgeText = "\(percent)%"
        }

        let statusText: String = {
            switch state.phase {
            case .error: return state.error ?? "Something went wrong"
            case .stalled: return copy.stalled
            case .done: return copy.done
            case .processing: return copy.processing
            case .idle: return copy.idle
            case .uploading: return state.stage ?? copy.uploadingText(percent: percent)
            }
        }()

        return ProgressPresentation(
            fillWidthPercent: clamped * 100.0,
            badgeText: badgeText,
            statusText: statusText,
            tintIsError: isError,
            indeterminateActive: isProcessing,
            deterministicFillVisible: !isProcessing,
            iconWobbles: isUploading && variant == .bug,
            fillIsAnimating: isUploading && !isStalled && !isError && !isDone
        )
    }
}
