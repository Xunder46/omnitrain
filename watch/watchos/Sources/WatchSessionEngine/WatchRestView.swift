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
//  no pause.
//

#if os(watchOS)

import SwiftUI

public struct WatchRestView: View {
    private let state: WatchLoggingState
    private let onNext: () -> Void

    /// Wrist-scale inset, as the other wrist surfaces use.
    private static let surfaceInset = 4.0

    public init(state: WatchLoggingState, onNext: @escaping () -> Void) {
        self.state = state
        self.onNext = onNext
    }

    public var body: some View {
        // The timeline is the ticker: the elapsed is derived from the row, and
        // re-reading it once a second is what makes the count-up move.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
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
