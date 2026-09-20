//
//  WatchLoggingView.swift
//  WatchSessionEngine
//
//  The native watchOS logging surface: one effort, its values, one confirm.
//  Native half of
//  `.github/agents/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`.
//
//  Another deliberate choice of the same kind `Package.swift` makes: this
//  module is platform-independent so the engine, the stepping table, and the
//  haptic derivation build and test today with `swift test`. The view is the
//  one part that cannot be — `DigitalCrownRotation` and `WKInterfaceDevice`
//  exist only on watchOS — so it is compiled only into a watch target. The
//  behaviour it drives is the behaviour the tests cover.
//
//  The four effort kinds are one view varying by the fields the state hands it
//  (S-001 to S-004): the wrist should not make the user learn four layouts to
//  log four kinds of work. The crown is primary and the value row's own
//  controls are the touch fallback. Nothing counts down — the readout is
//  derived from stored timestamps on every tick, and the poll on scene
//  activation is the one that fires a haptic the user was owed while the screen
//  was off.
//

#if os(watchOS)

import SwiftUI
import WatchKit

/// The watch's own haptic device. No plugin, no dependency: the hardware the
/// plan names.
public struct WristHaptics: WatchHaptics {
    public init() {}

    public func play(_ milestone: WatchTimerMilestone) {
        WKInterfaceDevice.current().play(.notification)
    }
}

public struct WatchLoggingView: View {
    /// Crown travel the system reports to each side of the scroll origin, in
    /// detents. Wide enough that the crown never hits an end while a value is
    /// still moving.
    private static let crownRangeDetents = 100.0

    /// Wrist-scale inset, on both axes. The phone's spacing tokens are sized for
    /// a full-width screen; this surface has roughly 40 pt of usable height, so
    /// the watch carries its own value rather than scaling a phone token down.
    private static let surfaceInset = 4.0

    @StateObject private var model: WatchLoggingModel

    public init(
        state: WatchLoggingState,
        haptics: WatchHaptics = WristHaptics()
    ) {
        _model = StateObject(wrappedValue: WatchLoggingModel(state: state, haptics: haptics))
    }

    public var body: some View {
        VStack(spacing: Self.surfaceInset) {
            header
            Spacer(minLength: 0)
            ForEach(model.state.fields, id: \.metricKey) { field in
                row(field)
            }
            Spacer(minLength: 0)
            logButton
        }
        .padding(.horizontal, Self.surfaceInset)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        // The poll after a suspension is the one that matters: the countdown
        // kept running while the screen did not, and it fires at the instant it
        // was due.
        .onReceive(
            NotificationCenter.default.publisher(
                for: WKApplication.willEnterForegroundNotification
            )
        ) { _ in model.poll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.state.exerciseName ?? "No exercise")
                .font(.caption2)
                .lineLimit(1)
            if let countdown = model.countdown {
                Text("\(WatchLoggingState.clock(countdown)) left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One value: the label, the numerals, and both ways to move it. The crown
    /// drives whichever row carries focus, which is the row the user last
    /// touched.
    private func row(_ field: WatchMetricField) -> some View {
        HStack {
            stepButton(systemName: "minus", label: "Less \(field.label)") {
                model.adjust(field.metricKey, detents: -1)
            }

            VStack(spacing: 0) {
                Text(field.label)
                    .font(.caption2)
                    .lineLimit(1)
                Text(field.displayValue)
                    .font(.title3)
                    .fontWeight(.bold)
                if !field.unitLabel.isEmpty {
                    Text(field.unitLabel).font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .focusable()
            .digitalCrownRotation(
                detent: Binding(
                    get: { model.crownPosition(for: field.metricKey) },
                    set: { model.turn(field.metricKey, to: $0) }
                ),
                from: -WatchLoggingModel.pointsPerDetent * Self.crownRangeDetents,
                through: WatchLoggingModel.pointsPerDetent * Self.crownRangeDetents,
                by: WatchLoggingModel.pointsPerDetent,
                sensitivity: .medium,
                isContinuous: true,
                isHapticFeedbackEnabled: true
            )

            stepButton(systemName: "plus", label: "More \(field.label)") {
                model.adjust(field.metricKey, detents: 1)
            }
        }
    }

    private func stepButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }

    /// The primary action, and the largest thing on the screen: a wrist log is
    /// one glance and one confirm.
    private var logButton: some View {
        Button {
            Task { await model.log() }
        } label: {
            Text("Log").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.state.canLog)
    }
}

#endif
