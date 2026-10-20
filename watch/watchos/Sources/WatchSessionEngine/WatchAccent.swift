//
//  WatchAccent.swift
//  WatchSessionEngine
//
//  The phone's theme accent, as the wrist wears it. Plan:
//  `docs/plans/2026-10-11-23d-watch-accent-color-plan/2026-10-11-23d-watch-accent-color-plan.md`,
//  D-3704 and D-3705.
//
//  The wrist never trusts the string it is given to be renderable: it parses the
//  hex itself, and an accent too dark to carry black labels is refused here, so
//  no view has to decide. The luminance and both contrast ratios are WCAG 2.x,
//  the formula the phone uses for its own accessibility checks, and the six
//  accents the two clients agree on are `watch/contract/watch_accent_contract.json`.
//

import Foundation

/// One accent color, and what can be said about it.
public struct WatchAccent: Equatable {
    /// The sRGB channels, each 0...1, as `#RRGGBB` names them.
    public let red: Double
    public let green: Double
    public let blue: Double

    /// Parses `#RRGGBB` and nothing else — the shape `preferences_down`'s
    /// `accentColorHex` is validated against. No short form, no alpha, no bare
    /// hex: a string the schema refuses reads nil rather than a wrong color.
    public init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let value = Int(digits, radix: 16) else {
            return nil
        }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    /// WCAG 2.x relative luminance: each sRGB channel linearized, then weighted.
    public var relativeLuminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    /// Contrast against black, 1...21.
    public var contrastAgainstBlack: Double { (relativeLuminance + 0.05) / 0.05 }

    /// Contrast against white, 1...21.
    public var contrastAgainstWhite: Double { 1.05 / (relativeLuminance + 0.05) }

    /// Whether dark labels belong on this accent: true exactly when black text
    /// reads better on it than white text does (D-3705).
    public var labelIsDark: Bool { contrastAgainstBlack >= contrastAgainstWhite }

    /// Whether the wrist wears this accent at all: an accent that does not
    /// clear `minContrastAgainstBlack` is ignored, and the wrist keeps its
    /// default look rather than wearing one nothing can be read on (D-3704).
    public var isUsable: Bool { contrastAgainstBlack >= Self.minContrastAgainstBlack }

    /// The floor an accent must clear to be worn, the value the shared table
    /// carries as `minContrastAgainstBlack`.
    public static let minContrastAgainstBlack = 3.0

    /// The accent a preference copy names, or nil when there is none, when the
    /// string is not `#RRGGBB`, and when the accent is too dark to wear (D-3704).
    public static func usable(hex: String?) -> WatchAccent? {
        guard let hex, let accent = WatchAccent(hex: hex), accent.isUsable else { return nil }
        return accent
    }

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}
