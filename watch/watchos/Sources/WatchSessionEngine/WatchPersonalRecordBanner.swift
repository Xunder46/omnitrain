//
//  WatchPersonalRecordBanner.swift
//  WatchSessionEngine
//
//  The one "New PR" banner both wrist surfaces overlay. Plan
//  `docs/plans/2026-10-28-88-pr-banner-on-rest-screen-plan/2026-10-28-88-pr-banner-on-rest-screen-plan.md`,
//  D-1: the logging surface shows it while the wrist stays on that surface, and
//  the rest surface the app shell swaps in the instant a log starts a rest shows
//  the same view — so a record logged as the rest begins is not torn down with
//  the logging screen.
//
//  Compiled only into a watch target, like the other views in this module.
//

#if os(watchOS)

import SwiftUI

/// The "New PR" banner: a trophy and two words over the top of a surface while
/// the state's window is open (plan 87b D-7; plan 88 D-1).
///
/// Opacity is the only thing that can change it — no movement, no repeating
/// animation — so Reduce Motion needs nothing extra. VoiceOver reads the one
/// label; the trophy and the words are decoration under it. It lets taps
/// through, so the button under it stays the surface's own.
public struct WatchPersonalRecordBanner: View {
    private let state: WatchLoggingState
    private let accent: WatchAccent?

    public init(state: WatchLoggingState, accent: WatchAccent?) {
        self.state = state
        self.accent = accent
    }

    public var body: some View {
        if state.isPersonalRecordBannerVisible(at: state.now()) {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                Text("New PR")
            }
            .font(.caption)
            .bold()
            .foregroundStyle(Color.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(accent?.color ?? Color.yellow))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WatchSpokenText.personalRecord)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

#endif
