import SwiftUI

public struct TaskProgressBar: View {
    let state: IssueProgressState
    let title: String
    let copy: IssueProgressCopy

    public init(
        state: IssueProgressState,
        title: String = "Add empty state to Inbox",
        copy: IssueProgressCopy = .taskDefault
    ) {
        self.state = state
        self.title = title
        self.copy = copy
    }

    public var body: some View {
        ProgressBarBody(variant: .task, state: state, title: title, copy: copy)
    }
}
