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
//  interval the phone last sent, the wrist taps (D-250).
//

#if os(watchOS)

import SwiftUI

public struct WatchRestView: View {
    private let state: WatchLoggingState

    /// The phone's interval, read on each tick rather than captured at
    /// construction: a sync landing mid-rest is heard on the next tick, and the
    /// newest copy is what the wrist honours (D-250).
    private let restPingSeconds: () -> Int
    private let haptics: WatchHaptics
    private let onNext: () -> Void

    /// The ping rule's state — which boundary this rest row has already pinged
    /// at. A class, so the tick mutates it in place instead of writing state
    /// during the view update.
    @State private var ping = WatchRestPing()

    /// Wrist-scale inset, as the other wrist surfaces use.
    private static let surfaceInset = 4.0

    public init(
        state: WatchLoggingState,
        restPingSeconds: @escaping () -> Int,
        haptics: WatchHaptics = WristHaptics(),
        onNext: @escaping () -> Void
    ) {
        self.state = state
        self.restPingSeconds = restPingSeconds
        self.haptics = haptics
        self.onNext = onNext
    }

    public var body: some View {
        // The timeline is the ticker: the elapsed is derived from the row, and
        // re-reading it once a second is what makes the count-up move and what
        // the ping is asked on.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let _ = pingIfOwed()
            VStack(spacing: Self.surfaceInset) {
                Text(state.exerciseName ?? "No exercise")
                    .font(.caption2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(elapsed)
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer(minLength: 0)
                nextButton
            }
            .padding(.horizontal, Self.surfaceInset)
        }
    }

    /// Asks the rule whether this tick owes a ping, and plays it if so. A rest
    /// that is not open has no row and no elapsed to consult, so a tick after
    /// the rest ended pings nothing (S-224); Off never pings (S-242).
    private func pingIfOwed() {
        guard ping.isOwed(
            restId: state.engine.timerFor(WatchTimerKind.rest)?.recordId,
            elapsed: state.restElapsedSeconds(),
            interval: restPingSeconds()
        ) else { return }
        haptics.playRestPing()
    }

    /// The rest's elapsed time as "m:ss", read from the persisted row at this
    /// instant rather than counted by the view.
    private var elapsed: String {
        WatchLoggingState.clock(Double(state.restElapsedSeconds() ?? 0))
    }

    /// The surface's one control: ending the rest and returning to logging.
    private var nextButton: some View {
        Button {
            Task {
                await state.endRest()
                onNext()
            }
        } label: {
            Text("Next").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}

#endif
