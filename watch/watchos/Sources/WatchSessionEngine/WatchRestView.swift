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
//  ends the rest and returns to logging (D-161), opening the exercise the next
//  line names when the line names one (plan 79, D-6). No End, no picker, no
//  dial, no pause. The one cue a rest has is the ping: at each multiple of the
//  interval the phone last sent, the wrist taps (D-250). The host's
//  `WatchRestPingScheduler` asks for that ping on its own clock, so a screen
//  that is off or dimmed pings on time; this view only shows the clock, and
//  shows whole minutes while the display is dimmed (plan 61).
//
//  Plan 88 D-1: the shell swaps this surface in the instant a record log starts
//  a rest, so this surface overlays the same "New PR" banner the logging surface
//  does, from its own timeline tick rather than a timer (D-2).
//

#if os(watchOS)

import SwiftUI

public struct WatchRestView: View {
    private let state: WatchLoggingState

    /// True while the display is dimmed (Always On, wrist down): the clock then
    /// shows whole minutes and the timeline ticks once a minute (plan 61, D-3).
    @Environment(\.isLuminanceReduced) private var dimmed

    /// The phone's accent, for the "New PR" banner's capsule — the same value
    /// the logging surface reads (plan 88 D-1).
    @Environment(\.watchAccent) private var accent

    private let haptics: WatchHaptics
    /// Moves the session to the slot id the next line announced (plan 79, D-6).
    /// The default refuses, so a caller without the menu keeps today's behaviour.
    private let advance: (String) async -> Bool
    private let onNext: () -> Void

    /// Wrist-scale inset, as the other wrist surfaces use.
    private static let surfaceInset = 4.0

    public init(
        state: WatchLoggingState,
        haptics: WatchHaptics = WristHaptics(),
        advance: @escaping (String) async -> Bool = { _ in false },
        onNext: @escaping () -> Void
    ) {
        self.state = state
        self.haptics = haptics
        self.advance = advance
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
                    .accessibilityLabel("Rest time")
                    .accessibilityValue(WatchSpokenText.duration(seconds: state.restElapsedSeconds() ?? 0))
                    .accessibilityAddTraits(.updatesFrequently)
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
            // A record log starts the rest and the shell swaps this screen in
            // at once (D-161), so the banner the logging surface shows is
            // continued here rather than torn down with it (plan 88 D-1). It is
            // built inside the timeline's closure, so its window is read on this
            // screen's existing tick and it needs no timer of its own (D-2).
            .overlay(alignment: .top) {
                WatchPersonalRecordBanner(state: state, accent: accent)
            }
        }
        // One announcement per record, whichever surface is up when it is due
        // (plan 88 D-3): appearing is the moment a record logged before the swap
        // is announced, and a record logged while the rest is up arrives as a new
        // stamp. The state hands it out once, so a record already announced on
        // the logging surface stays silent here.
        .onAppear { announcePersonalRecordIfDue() }
        .onChange(of: state.personalRecordBannerUntil) { _ in announcePersonalRecordIfDue() }
    }

    /// Posts the record's one announcement when the state still owes it (plan 88
    /// D-3). Guarded like the logging surface's, because the package's floor is
    /// watchOS 9; there the banner's own label is what VoiceOver reads.
    private func announcePersonalRecordIfDue() {
        guard state.takePersonalRecordAnnouncement() else { return }
        if #available(watchOS 10.0, *) {
            AccessibilityNotification.Announcement(WatchSpokenText.personalRecord).post()
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
                let target = state.restLabels.nextSlotId
                await state.endRest()
                if let target { _ = await advance(target) }
                haptics.playNext()
                onNext()
            }
        } label: {
            Text("Next").frame(maxWidth: .infinity)
        }
        .watchProminent()
        .accessibilityHint(state.restLabels.next)
    }
}

#endif
