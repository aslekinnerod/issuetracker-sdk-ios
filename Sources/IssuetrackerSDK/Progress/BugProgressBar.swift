import SwiftUI

public struct BugProgressBar: View {
    let state: IssueProgressState
    let title: String
    let copy: IssueProgressCopy

    public init(
        state: IssueProgressState,
        title: String = "Crash on tap › Inbox",
        copy: IssueProgressCopy = .bugDefault
    ) {
        self.state = state
        self.title = title
        self.copy = copy
    }

    public var body: some View {
        ProgressBarBody(variant: .bug, state: state, title: title, copy: copy)
    }
}
