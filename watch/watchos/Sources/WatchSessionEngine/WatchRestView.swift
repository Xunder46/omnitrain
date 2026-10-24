//
//  WatchRestView.swift
//  WatchSessionEngine
//
//  The native watchOS rest surface. Plan:
//  `docs/plans/2026-10-08-18b-watch-rest-count-up-plan.md`, D-160 and D-161.
//
//  Compiled only into a watch target, like the other views in this module. The
//  rest rule lives in `WatchLoggingState` (`isResting`, `endRest`,
//  `restElapsedSeconds`) and is what the suite covers; this view binds to it
//  and carries nothing of its own.
//
//  Rest is a count-up from the moment a set is logged; there is no preset
//  length. The elapsed is re-read every second from the persisted timer row, so
//  a screen that was off comes back showing the truth. One control, Next: it
//  ends the rest and returns to logging (D-161). No End, no picker, no dial,
//  no pause. The one cue a rest has is the ping: at each multiple of the
//  interval the phone last sent, the wrist taps (D-250). The host's
//  `WatchRestPingScheduler` asks for that ping on its own clock, so a screen
//  that is off or dimmed pings on time; this view only shows the clock, and
//  shows whole minutes while the display is dimmed (plan 61).
//

#if os(watchOS)

import SwiftUI

public struct WatchRestView: View {
    private let state: WatchLoggingState

    /// True while the display is dimmed (Always On, wrist down): the clock then
    /// shows whole minutes and the timeline ticks once a minute (plan 61, D-3).
    @Environment(\.isLuminanceReduced) private var dimmed

    private let haptics: WatchHaptics
    private let onNext: () -> Void

    /// Wrist-scale inset, as the other wrist surfaces use.
    private static let surfaceInset = 4.0

    public init(
        state: WatchLoggingState,
        haptics: WatchHaptics = WristHaptics(),
        onNext: @escaping () -> Void
    ) {
        self.state = state
        self.haptics = haptics
        self.onNext = onNext
    }

    public var body: some View {
        // The timeline is the ticker: the elapsed is derived from the row, and
        // re-reading it makes the count-up move; dimmed, once a minute on the
        // rest's own minute marks.
        TimelineView(.periodic(from: state.restStartedAt ?? Date(), by: dimmed ? 60 : 1)) { _ in
            let labels = state.restLabels
            VStack(spacing: Self.surfaceInset) {
                Text(WatchRestSurfaceCopy.restCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(labels.now)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(elapsed)
                    .font(.largeTitle)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(labels.next)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                nextButton
            }
            .padding(.horizontal, Self.surfaceInset)
        }
    }

    /// The rest's elapsed time as "m:ss", read from the persisted row at this
    /// instant rather than counted by the view; dimmed, whole minutes.
    private var elapsed: String {
        let seconds = state.restElapsedSeconds() ?? 0
        return dimmed
            ? WatchLoggingState.dimmedRestClock(seconds: seconds)
            : WatchLoggingState.clock(Double(seconds))
    }

    /// The surface's one control: ending the rest and returning to logging.
    private var nextButton: some View {
        Button {
            Task {
                await state.endRest()
                haptics.playNext()
                onNext()
            }
        } label: {
            Text("Next").frame(maxWidth: .infinity)
        }
        .watchProminent()
    }
}

#endif
