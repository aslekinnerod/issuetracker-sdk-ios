import SwiftUI

// Trace design tokens lifted from `colors_and_type.css`. SwiftUI
// equivalents — colors are concrete values, type uses the system
// font (San Francisco) with the same weights/sizes Trace specifies.
// Geist isn't bundled to keep the SDK at zero asset overhead; SF is
// also a geometric sans and renders the brand impression close enough
// for an in-app reporter.
enum Tokens {
    // ---------- Surface ----------
    static let surfaceApp = Color(hex: 0xF4F7FA)
    static let surfaceCard = Color.white
    static let surface1 = Color(hex: 0xEAF0F6)
    static let surface2 = Color(hex: 0xDCE4ED)
    static let surfaceInverse = Color(hex: 0x0E1A2B)

    // ---------- Ink ----------
    static let fg1 = Color(hex: 0x0E1A2B)
    static let fg2 = Color(hex: 0x43536B)
    static let fg3 = Color(hex: 0x6E7E94)
    static let fg4 = Color(hex: 0xA8B3C2)

    // ---------- Lines ----------
    static let line = Color(hex: 0xDCE4ED)
    static let lineFaint = Color(hex: 0xECF1F6)

    // ---------- Brand ----------
    static let accent = Color(hex: 0x1FA2E8)
    static let accent2 = Color(hex: 0x22D3C5)
    static let accent3 = Color(hex: 0x0D7C8A)
    static let accentSoft = Color(hex: 0xDDF2FB)
    static let accentHover = Color(hex: 0x1A8FCF)

    // ---------- Status ----------
    static let critical = Color(hex: 0xE03A4E)
    static let criticalSoft = Color(hex: 0xFBE3E7)
    static let warning = Color(hex: 0xE9A23B)
    static let warningSoft = Color(hex: 0xFBEFD9)
    static let success = Color(hex: 0x1F9E72)
    static let successSoft = Color(hex: 0xDCF1E9)

    // ---------- Radius ----------
    static let radiusSm: CGFloat = 4
    static let radiusMd: CGFloat = 8
    static let radiusLg: CGFloat = 12

    // ---------- Spacing ----------
    enum Space {
        static let s1: CGFloat = 2
        static let s2: CGFloat = 4
        static let s3: CGFloat = 8
        static let s4: CGFloat = 12
        static let s5: CGFloat = 16
        static let s6: CGFloat = 24
        static let s7: CGFloat = 32
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// ---------- Reusable styled components ----------

// Branded button — primary / secondary / ghost / danger variants
// matching the Trace JSX reference. Heights and paddings match the
// Trace `md` size (32pt-ish); on iOS we bump slightly so touch
// targets land at the recommended 44pt.
struct BrandButton: View {
    enum Variant { case primary, secondary, ghost, danger }
    let title: String
    let icon: String?
    let variant: Variant
    let isDisabled: Bool
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        variant: Variant = .secondary,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(fg)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .tracking(-0.1)
            }
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tokens.Space.s5)
            .background(bg)
            .foregroundStyle(fg)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.radiusSm)
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSm))
            .opacity(isDisabled || isLoading ? 0.4 : 1)
        }
        .disabled(isDisabled || isLoading)
        .buttonStyle(.plain)
    }

    private var bg: Color {
        switch variant {
        case .primary: return Tokens.accent
        case .secondary: return Tokens.surfaceCard
        case .ghost: return .clear
        case .danger: return Tokens.surfaceCard
        }
    }
    private var fg: Color {
        switch variant {
        case .primary: return .white
        case .secondary, .ghost: return Tokens.fg1
        case .danger: return Tokens.critical
        }
    }
    private var border: Color {
        switch variant {
        case .primary, .ghost: return .clear
        case .secondary, .danger: return Tokens.line
        }
    }
}

// Pill-style chip used for severity / type pickers. Mirrors the JSX
// `Chip` primitive — soft cyan tint when active, neutral when not.
struct BrandChip: View {
    let title: String
    let icon: String?
    let isActive: Bool
    let action: () -> Void

    init(_ title: String, icon: String? = nil, isActive: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .regular))
                }
                Text(title).font(.system(size: 13, weight: .medium)).tracking(-0.1)
            }
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tokens.Space.s4)
            .background(isActive ? Tokens.accentSoft : Tokens.surfaceCard)
            .foregroundStyle(isActive ? Tokens.accent3 : Tokens.fg2)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.radiusSm)
                    .stroke(isActive ? Tokens.accent : Tokens.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSm))
        }
        .buttonStyle(.plain)
    }
}

// Form-row label — uppercase-ish caption above each input. Trace's
// "label" type style: 12px medium, tracking 0.06em on web; we use
// SF at 12pt medium with positive tracking.
struct FieldLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Tokens.fg2)
    }
}

// Bordered text input used by Title and What-happened fields. Single-
// line by default; pass `axis: .vertical` with multi-line text-field
// for the description.
struct BrandTextField: View {
    @Binding var value: String
    let placeholder: String
    var multiline: Bool = false

    var body: some View {
        Group {
            if multiline {
                TextField(placeholder, text: $value, axis: .vertical)
                    .lineLimit(3...8)
            } else {
                TextField(placeholder, text: $value)
                    .textInputAutocapitalization(.sentences)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(Tokens.fg1)
        .padding(.horizontal, 12)
        .padding(.vertical, multiline ? 10 : 0)
        .frame(minHeight: multiline ? 0 : 40)
        .background(Tokens.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.radiusSm)
                .stroke(Tokens.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSm))
    }
}

// Header with the brand mark + a title and optional subtitle. Used
// at the top of ReportView and NamePromptView.
struct BrandHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s4) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Tokens.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.fg1)
                    .tracking(-0.3)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Tokens.fg3)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
