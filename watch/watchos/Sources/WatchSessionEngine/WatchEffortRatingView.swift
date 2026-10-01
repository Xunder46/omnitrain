//
//  WatchEffortRatingView.swift
//  WatchSessionEngine
//
//  The native watchOS effort-rating prompt and End control. Plan:
//  `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`, D-118
//  and D-119.
//
//  Compiled only into a watch target, like the other views in this module:
//  crown rotation exists only on watchOS. Every decision behind what these
//  views show is `WatchEffortRatingState`'s, which the suite covers; the views
//  bind to it and nothing else. Placing them in the app's navigation — and
//  presenting an owed prompt at launch before anything else — belongs to the
//  app shell.
//

#if os(watchOS)

import SwiftUI

/// The prompt: the question, the scale, one confirm. Its only way out is an
/// answer, so it carries no other button, hides the back button when pushed,
/// and cannot be swiped away when presented as a sheet.
public struct WatchEffortRatingView: View {
    @ObservedObject private var state: WatchEffortRatingState

    /// Wrist-scale inset, as the other wrist surfaces use.
    private static let surfaceInset = 4.0

    public init(state: WatchEffortRatingState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: Self.surfaceInset) {
            Text(state.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            HStack(spacing: Self.surfaceInset) {
                ForEach(state.scale, id: \.self) { value in
                    scaleButton(value)
                }
            }
            HStack {
                Text(state.lowestLabel)
                Spacer(minLength: 0)
                Text(state.highestLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            confirmButton
        }
        .padding(.horizontal, Self.surfaceInset)
        .focusable(true)
        // A discontinuous crown stops at the ends of its range instead of
        // wrapping: a wrapped reading would be an unasked-for jump of the whole
        // scale, which the state refuses behind this (F-7).
        .digitalCrownRotation(
            detent: Binding(
                get: { state.crownPoints },
                set: { state.turnCrown(to: $0) }
            ),
            from: -WatchMetricStepping.pointsPerDetent * WatchEffortRatingState.crownRangeDetents,
            through: WatchMetricStepping.pointsPerDetent * WatchEffortRatingState.crownRangeDetents,
            by: WatchMetricStepping.pointsPerDetent,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
    }

    /// One number of the scale. `.borderedProminent` and `.bordered` are
    /// distinct types, so the picked and unpicked branches are separate views.
    @ViewBuilder
    private func scaleButton(_ value: Int) -> some View {
        let button = Button("\(value)") { state.select(value) }
        if value == state.selected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var confirmButton: some View {
        Button {
            Task { _ = try? await state.confirm() }
        } label: {
            Text("Confirm").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!state.canConfirm)
    }
}

/// The End control: ends the session the wrist is on. Whether a prompt follows
/// is the state's decision.
public struct WatchEndSessionView: View {
    @ObservedObject private var state: WatchEffortRatingState

    public init(state: WatchEffortRatingState) {
        self.state = state
    }

    public var body: some View {
        Button {
            Task { await state.end() }
        } label: {
            Text("End").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!state.canEnd)
    }
}

#endif
