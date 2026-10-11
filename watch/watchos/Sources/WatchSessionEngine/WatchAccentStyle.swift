//
//  WatchAccentStyle.swift
//  WatchSessionEngine
//
//  The SwiftUI half of D-3704: how the phone's theme accent reaches the wrist's
//  buttons. `WatchAccent` (`WatchAccent.swift`) decides what the accent is and
//  which label reads on it; this file carries it through the environment and
//  applies it. Plan:
//  `docs/plans/2026-10-11-23d-watch-accent-color-plan/2026-10-11-23d-watch-accent-color-plan.md`.
//
//  A view asks for the accent rather than deciding it: `watchProminent()` reads
//  the environment value the app's root sets from `WatchPhonePreferences`, so a
//  surface handed no accent — before the first Sync, or when the copy carried
//  none — is exactly `.buttonStyle(.borderedProminent)`, today's look.
//
//  Compiled only into a watch target, like the other views in this module:
//  `swift test` compiles and runs the package's platform-independent half and
//  never these views.
//

#if os(watchOS)

import SwiftUI

/// The accent the wrist's prominent buttons wear, or nil when there is none.
/// Carried in the environment so one read at the root reaches every surface,
/// the sheets and alerts presented from them included (D-3704).
private struct WatchAccentKey: EnvironmentKey {
    static let defaultValue: WatchAccent? = nil
}

extension EnvironmentValues {
    /// Set by the app's root from the phone's `accentColorHex`. nil means the
    /// wrist keeps its default look.
    public var watchAccent: WatchAccent? {
        get { self[WatchAccentKey.self] }
        set { self[WatchAccentKey.self] = newValue }
    }
}

extension WatchAccent {
    /// The accent as SwiftUI draws it. The channels are already 0...1 sRGB, the
    /// space `#RRGGBB` names.
    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// The label that reads on `color`: black where black has the higher
    /// contrast, white otherwise (`labelIsDark`, D-3704).
    public var labelColor: Color { labelIsDark ? .black : .white }
}

/// Applies the accent to a button that is already prominent. With no accent in
/// the environment the result is `.buttonStyle(.borderedProminent)` alone.
private struct WatchProminentModifier: ViewModifier {
    @Environment(\.watchAccent) private var accent

    @ViewBuilder
    func body(content: Content) -> some View {
        if let accent {
            content
                .buttonStyle(.borderedProminent)
                .tint(accent.color)
                .foregroundStyle(accent.labelColor)
        } else {
            content
                .buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    /// The style a wrist's prominent button wears: the accent in the environment
    /// when there is one, and exactly the default look when there is not
    /// (D-3704). Every prominent wrist button asks with this rather than naming
    /// the style itself, so no view decides the color.
    public func watchProminent() -> some View {
        modifier(WatchProminentModifier())
    }
}

#endif
