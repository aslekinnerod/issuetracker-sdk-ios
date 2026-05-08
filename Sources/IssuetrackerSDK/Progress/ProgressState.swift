import Foundation

public enum IssueProgressPhase: String, Sendable, Equatable {
    case idle
    case uploading
    case processing
    case done
    case error
    case stalled
}

public struct IssueProgressState: Sendable, Equatable {
    public var progress: Double
    public var phase: IssueProgressPhase
    public var error: String?
    public var issueId: String?
    public var stage: String?

    public init(
        progress: Double = 0,
        phase: IssueProgressPhase = .idle,
        error: String? = nil,
        issueId: String? = nil,
        stage: String? = nil
    ) {
        self.progress = progress
        self.phase = phase
        self.error = error
        self.issueId = issueId
        self.stage = stage
    }
}

public struct IssueProgressCopy: Sendable, Equatable {
    public var idle: String
    public var uploadingFormat: String
    public var processing: String
    public var done: String
    public var stalled: String

    public init(
        idle: String,
        uploadingFormat: String,
        processing: String,
        done: String,
        stalled: String = "Waiting for connection…"
    ) {
        self.idle = idle
        self.uploadingFormat = uploadingFormat
        self.processing = processing
        self.done = done
        self.stalled = stalled
    }

    public static let bugDefault = IssueProgressCopy(
        idle: "Ready to send",
        uploadingFormat: "Uploading… {n}%",
        processing: "Reproducing on staging…",
        done: "Squashed. Engineer notified."
    )

    public static let taskDefault = IssueProgressCopy(
        idle: "Ready to file",
        uploadingFormat: "Filing task… {n}%",
        processing: "Syncing to Jira…",
        done: "Filed. Synced to sprint."
    )

    public static let storyDefault = IssueProgressCopy(
        idle: "Ready to publish",
        uploadingFormat: "Publishing story… {n}%",
        processing: "Routing for product review…",
        done: "Published to backlog."
    )

    func uploadingText(percent: Int) -> String {
        uploadingFormat.replacingOccurrences(of: "{n}", with: String(percent))
    }
}
