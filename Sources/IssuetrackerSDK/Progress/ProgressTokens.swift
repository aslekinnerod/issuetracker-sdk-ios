import SwiftUI

enum ProgressTokens {
    enum NeutralColor {
        static let ink = Color(hex: 0x0B0B0F)
        static let paper = Color.white
        static let track = Color(hex: 0xF1EEE8)
        static let muted = Color(hex: 0x6E6A62)
        static let subtle = Color(hex: 0x9A958A)
        static let line = Color(.sRGB, red: 11.0/255, green: 11.0/255, blue: 15.0/255, opacity: 0.05)
        static let statusBody = Color(hex: 0x3A3A3A)
    }

    enum ErrorColor {
        static let accent = Color(hex: 0xC0392B)
        static let dark = Color(hex: 0x8A1F10)
        static let soft = Color(hex: 0xFBE0DC)
    }

    enum BugColor {
        static let accent = Color(hex: 0xE64A36)
        static let dark = Color(hex: 0xA8341F)
        static let soft = Color(hex: 0xFCE4DE)
    }

    enum TaskColor {
        static let accent = Color(hex: 0x3F4FE0)
        static let dark = Color(hex: 0x23308F)
        static let soft = Color(hex: 0xE5E8FB)
        static let fillEnd = Color(hex: 0x6675F0)
    }

    enum StoryColor {
        static let accent = Color(hex: 0xE0A23F)
        static let dark = Color(hex: 0x7D5614)
        static let soft = Color(hex: 0xFBEFD8)
        static let fillStart = Color(hex: 0xF4D38A)
    }

    enum Card {
        static let padding: CGFloat = 16
        static let radius: CGFloat = 18
        static let borderWidth: CGFloat = 1
    }

    enum Icon {
        static let frame: CGFloat = 36
        static let frameRadius: CGFloat = 10
        static let glyph: CGFloat = 22
    }

    enum Track {
        static let height: CGFloat = 10
        static let heightCompact: CGFloat = 6
    }

    enum Badge {
        static let paddingV: CGFloat = 5
        static let paddingH: CGFloat = 8
        static let radius: CGFloat = 8
        static let minWidth: CGFloat = 46
    }

    enum Gap {
        static let header: CGFloat = 12
        static let headerToTrack: CGFloat = 12
        static let trackToStatus: CGFloat = 12
    }

    enum TypeSize {
        static let kind: CGFloat = 10
        static let title: CGFloat = 15
        static let badge: CGFloat = 11
        static let status: CGFloat = 12.5
    }

    enum TypeWeight {
        static let kind: Font.Weight = .semibold
        static let title: Font.Weight = .semibold
        static let badge: Font.Weight = .semibold
        static let status: Font.Weight = .medium
    }

    enum Motion {
        static let fillDurationMs: Double = 120
        static let sweepDurationMs: Double = 1400
        static let sweepHighlightWidthFraction: Double = 0.4
        static let doneCheckmarkDurationMs: Double = 360
        static let phaseDotPulseDurationMs: Double = 1000
        static let iconWobblePeriodMs: Double = 754
        static let iconWobbleAmplitudeDeg: Double = 8
    }

    static let stallThresholdMs: Double = 3000
}
