import SwiftUI

enum ProgressVariant {
    case bug
    case task
    case story

    var kindText: String {
        switch self {
        case .bug: return "BUG REPORT"
        case .task: return "TASK"
        case .story: return "STORY"
        }
    }

    var defaultTitle: String {
        switch self {
        case .bug: return "Crash on tap › Inbox"
        case .task: return "Add empty state to Inbox"
        case .story: return "Onboarding for first‑time users"
        }
    }

    var fallbackIssueId: String {
        switch self {
        case .bug: return "BUG-—"
        case .task: return "TSK-—"
        case .story: return "STY-—"
        }
    }

    var accent: Color {
        switch self {
        case .bug: return ProgressTokens.BugColor.accent
        case .task: return ProgressTokens.TaskColor.accent
        case .story: return ProgressTokens.StoryColor.accent
        }
    }

    var accentDark: Color {
        switch self {
        case .bug: return ProgressTokens.BugColor.dark
        case .task: return ProgressTokens.TaskColor.dark
        case .story: return ProgressTokens.StoryColor.dark
        }
    }

    var accentSoft: Color {
        switch self {
        case .bug: return ProgressTokens.BugColor.soft
        case .task: return ProgressTokens.TaskColor.soft
        case .story: return ProgressTokens.StoryColor.soft
        }
    }

    // WCAG 1.4.11 — a variant whose accent falls below 3:1 against the
    // track defines a dedicated graphic colour, used for the icon glyph,
    // the indeterminate sweep highlight, and the determinate fill head
    // cap. Variants whose accent already meets 3:1 (bug, task) return
    // nil and render no head cap.
    var graphic: Color? {
        switch self {
        case .bug, .task: return nil
        case .story: return ProgressTokens.StoryColor.graphic
        }
    }

    /// Colour for meaningful graphics: `graphic` where defined, else `accent`.
    var graphicOrAccent: Color { graphic ?? accent }

    var fillGradient: [Color] {
        switch self {
        case .bug: return [ProgressTokens.BugColor.dark, ProgressTokens.BugColor.accent]
        case .task: return [ProgressTokens.TaskColor.accent, ProgressTokens.TaskColor.fillEnd]
        case .story: return [ProgressTokens.StoryColor.fillStart, ProgressTokens.StoryColor.accent]
        }
    }

    var trackHeight: CGFloat {
        switch self {
        case .task: return ProgressTokens.Track.heightCompact
        case .bug, .story: return ProgressTokens.Track.height
        }
    }
}
