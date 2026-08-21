import SwiftUI
import UIKit
import XCTest
@testable import IssuetrackerSDK

// WCAG contrast regression tests for the design tokens (ISU-39).
//
// Every pair below encodes a claim made in DesignTokens.swift /
// ProgressTokens.swift (text contrast 1.4.3 at 4.5:1, non-text
// contrast 1.4.11 at 3:1). The colors are read straight from the
// production `Tokens` / `ProgressTokens` enums via @testable import,
// so a palette tweak that silently drops a pair below its threshold
// fails here instead of in the next audit.
final class ContrastTests: XCTestCase {

    // MARK: - WCAG 2.x math

    /// Relative luminance of linear-ish sRGB components per WCAG 2.x.
    private func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private func contrastRatio(
        _ a: (r: Double, g: Double, b: Double),
        _ b: (r: Double, g: Double, b: Double)
    ) -> Double {
        let la = relativeLuminance(r: a.r, g: a.g, b: a.b)
        let lb = relativeLuminance(r: b.r, g: b.g, b: b.b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    // MARK: - Color extraction

    /// sRGB components of a SwiftUI Color. All tokens are defined as
    /// opaque sRGB values, so the CGColor round-trip is exact.
    private func srgbComponents(of color: Color) throws -> (r: Double, g: Double, b: Double) {
        let cgColor = UIColor(color).cgColor
        let srgbSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let converted = try XCTUnwrap(
            cgColor.converted(to: srgbSpace, intent: .defaultIntent, options: nil),
            "Color is not convertible to sRGB"
        )
        let components = try XCTUnwrap(converted.components)
        XCTAssertGreaterThanOrEqual(components.count, 3)
        return (Double(components[0]), Double(components[1]), Double(components[2]))
    }

    /// Parses "#RRGGBB" (leading "#" optional) into sRGB components.
    private func srgbComponents(hex: String) throws -> (r: Double, g: Double, b: Double) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        XCTAssertEqual(digits.count, 6, "Expected 6 hex digits in \(hex)")
        let value = try XCTUnwrap(UInt32(digits, radix: 16), "Invalid hex string \(hex)")
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    // MARK: - Helper sanity checks

    func testContrastHelperBlackOnWhiteIs21() throws {
        let ratio = try contrastRatio(srgbComponents(hex: "#000000"), srgbComponents(hex: "#FFFFFF"))
        XCTAssertEqual(ratio, 21.0, accuracy: 0.001)
        // Order must not matter.
        let flipped = try contrastRatio(srgbComponents(hex: "#FFFFFF"), srgbComponents(hex: "#000000"))
        XCTAssertEqual(flipped, 21.0, accuracy: 0.001)
    }

    func testContrastHelperMatchesKnownRatios() throws {
        // #767676 is the classic "just passes AA" grey: 4.54:1 on white.
        let grey = try contrastRatio(srgbComponents(hex: "#767676"), srgbComponents(hex: "#FFFFFF"))
        XCTAssertEqual(grey, 4.54, accuracy: 0.01)
        // accentStrong's documented ratio (DesignTokens.swift): ~4.9:1.
        let accent = try contrastRatio(srgbComponents(hex: "#1577AD"), srgbComponents(hex: "#FFFFFF"))
        XCTAssertEqual(accent, 4.91, accuracy: 0.01)
    }

    func testTokenExtractionMatchesSourceHex() throws {
        // Cross-check the Color -> sRGB extraction path against the
        // raw hex the token is defined with in DesignTokens.swift.
        let extracted = try srgbComponents(of: Tokens.accentStrong)
        let expected = try srgbComponents(hex: "#1577AD")
        XCTAssertEqual(extracted.r, expected.r, accuracy: 0.001)
        XCTAssertEqual(extracted.g, expected.g, accuracy: 0.001)
        XCTAssertEqual(extracted.b, expected.b, accuracy: 0.001)
    }

    // MARK: - Token contrast requirements

    private struct ContrastRequirement {
        let name: String
        let foreground: Color
        let background: Color
        let minimumRatio: Double
    }

    /// One row per audited pairing. Text pairs need 4.5:1 (1.4.3 AA),
    /// non-text UI/graphics pairs need 3:1 (1.4.11).
    private let requirements: [ContrastRequirement] = [
        // Text on white (1.4.3, 4.5:1)
        .init(
            name: "Tokens.accentStrong on white (primary button fill / accent text)",
            foreground: Tokens.accentStrong, background: .white, minimumRatio: 4.5
        ),
        .init(
            name: "Tokens.warningStrong on white (warning body text)",
            foreground: Tokens.warningStrong, background: .white, minimumRatio: 4.5
        ),
        .init(
            name: "Tokens.disabledFg on Tokens.disabledFill (disabled button label)",
            foreground: Tokens.disabledFg, background: Tokens.disabledFill, minimumRatio: 4.5
        ),
        // Non-text UI components and graphics (1.4.11, 3:1)
        .init(
            name: "Tokens.lineControl on white (chip / text-field border)",
            foreground: Tokens.lineControl, background: .white, minimumRatio: 3.0
        ),
        .init(
            name: "ProgressTokens.StoryColor.graphic on NeutralColor.paper (story icon glyph)",
            foreground: ProgressTokens.StoryColor.graphic,
            background: ProgressTokens.NeutralColor.paper, minimumRatio: 3.0
        ),
        .init(
            name: "ProgressTokens.StoryColor.graphic on StoryColor.soft (story icon frame)",
            foreground: ProgressTokens.StoryColor.graphic,
            background: ProgressTokens.StoryColor.soft, minimumRatio: 3.0
        ),
        .init(
            name: "ProgressTokens.StoryColor.graphic on NeutralColor.track (fill head cap / sweep)",
            foreground: ProgressTokens.StoryColor.graphic,
            background: ProgressTokens.NeutralColor.track, minimumRatio: 3.0
        ),
        .init(
            name: "ProgressTokens.NeutralColor.subtle on NeutralColor.paper (phase dots)",
            foreground: ProgressTokens.NeutralColor.subtle,
            background: ProgressTokens.NeutralColor.paper, minimumRatio: 3.0
        ),
    ]

    func testDesignTokenPairsMeetWcagContrast() throws {
        for requirement in requirements {
            let foreground = try srgbComponents(of: requirement.foreground)
            let background = try srgbComponents(of: requirement.background)
            let ratio = contrastRatio(foreground, background)
            XCTAssertGreaterThanOrEqual(
                ratio,
                requirement.minimumRatio,
                "\(requirement.name): contrast \(String(format: "%.2f", ratio)):1 "
                    + "is below the required \(requirement.minimumRatio):1"
            )
        }
    }
}
