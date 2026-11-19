//
//  WatchSheetBackground.swift
//  WatchSessionEngine
//
//  The one solid backdrop every wrist sheet wears (plan 223, D-22301, D-22308).
//  On watchOS 26 a sheet is see-through glass, so whatever sits behind it (the
//  modality tiles, the menu's red Discard) bleeds into it. One modifier, one
//  colour, applied once to each sheet's root content. Compiled only into a
//  watch target, like the other views in this module.
//

#if os(watchOS)

import SwiftUI

extension View {
    /// The solid black backdrop of a wrist sheet (D-22308).
    public func solidSheetBackground() -> some View {
        modifier(WatchSolidSheetBackground())
    }
}

/// The package's floor is watchOS 9 and `presentationBackground` arrived in
/// watchOS 9.4, so the floor paints the content's own background instead.
private struct WatchSolidSheetBackground: ViewModifier {
    /// The one colour a sheet's backdrop is.
    static let color = Color.black

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(watchOS 9.4, *) {
            content.presentationBackground(Self.color)
        } else {
            content.background(Self.color, ignoresSafeAreaEdges: .all)
        }
    }
}

#endif
