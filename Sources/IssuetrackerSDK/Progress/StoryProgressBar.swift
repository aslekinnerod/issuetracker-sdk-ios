import SwiftUI

public struct StoryProgressBar: View {
    let state: IssueProgressState
    let title: String
    let copy: IssueProgressCopy

    public init(
        state: IssueProgressState,
        title: String = "Onboarding for first‑time users",
        copy: IssueProgressCopy = .storyDefault
    ) {
        self.state = state
        self.title = title
        self.copy = copy
    }

    public var body: some View {
        ProgressBarBody(variant: .story, state: state, title: title, copy: copy)
    }
}
