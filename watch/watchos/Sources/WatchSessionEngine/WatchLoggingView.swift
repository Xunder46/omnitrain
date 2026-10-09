//
//  WatchLoggingView.swift
//  WatchSessionEngine
//
//  The native watchOS logging surface: one effort, its values, one confirm.
//  Native half of
//  `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`.
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

    /// A rest ping is not a countdown ending: it is a shorter nudge, so it does
    /// not share the countdown's alert (D-251).
    public func playRestPing() {
        WKInterfaceDevice.current().play(.click)
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

    /// Called after a successful log, so the app shell can re-evaluate which
    /// surface it shows — logging a set starts a rest, and the shell swaps to
    /// the rest surface on that nudge (D-161).
    private let onLogged: (() -> Void)?

    public init(
        state: WatchLoggingState,
        haptics: WatchHaptics = WristHaptics(),
        onLogged: (() -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: WatchLoggingModel(state: state, haptics: haptics))
        self.onLogged = onLogged
    }

    public var body: some View {
        VStack(spacing: Self.surfaceInset) {
            header
            Spacer(minLength: 0)
            ForEach(model.state.fields, id: \.metricKey) { field in
                row(field)
            }
            if let readout = model.workReadout {
                Text(readout)
                    .font(.largeTitle)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            primaryButton
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
            if let round = roundLine {
                Text(round)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // The readout already carries the period's time, so the header drops
            // its own countdown line rather than repeating it.
            if model.workReadout == nil, let countdown = model.countdown {
                Text("\(WatchLoggingState.clock(countdown)) left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let sensors = sensorLine {
                Text(sensors)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The period the next log will record, in this modality's own word and
    /// singular ("Period 2"), or nil for the kinds without periods (D-1307).
    private var roundLine: String? { model.periodLine }

    /// What the sensors are reading, as one line: the heart rate, the distance,
    /// and the pace it is being covered at. Absent pieces are left out rather
    /// than shown as zero — a session with no reading has nothing to report, and
    /// the line disappears entirely when there is nothing at all.
    private var sensorLine: String? {
        let readout = model.state.sensorLabels
        let unit = model.state.units.isMiles ? "mi" : "km"
        var parts: [String] = []
        if let beats = readout.heartRate { parts.append("\(beats) bpm") }
        if let distance = readout.distance { parts.append("\(distance) \(unit)") }
        if let pace = readout.pace { parts.append(pace) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    /// One value: the label, the numerals, and both ways to move it. The crown
    /// drives whichever row carries focus, which is the row the user last
    /// touched.
    ///
    /// A row a sensor is keeping has neither: its controls are inert and it takes
    /// no crown focus, so a turn aimed at the row does nothing rather than
    /// replacing a measurement with a guess.
    private func row(_ field: WatchMetricField) -> some View {
        HStack {
            stepButton(systemName: "minus", label: "Less \(field.label)", enabled: !field.isMeasured) {
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
            .focusable(!field.isMeasured)
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

            stepButton(systemName: "plus", label: "More \(field.label)", enabled: !field.isMeasured) {
                model.adjust(field.metricKey, detents: 1)
            }
        }
    }

    private func stepButton(
        systemName: String,
        label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// The primary action, and the largest thing on the screen: a wrist log is
    /// one glance and one confirm. It reads Start while the effort's clock is
    /// stopped and Log once it runs (D-1307).
    private var primaryButton: some View {
        Button {
            Task {
                await model.primaryAction()
                onLogged?()
            }
        } label: {
            Text(model.primaryTitle).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.state.canLog)
    }
}

#endif
