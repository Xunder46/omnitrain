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

    /// A log the wrist recorded (plan 51e D-1).
    public func playLogged() {
        WKInterfaceDevice.current().play(.success)
    }

    /// Next on the rest screen: lighter than the log's tap and unlike the rest
    /// ping's click.
    public func playNext() {
        WKInterfaceDevice.current().play(.directionUp)
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

    /// Height the name sits below the top edge so it clears the menu button,
    /// which sits in the top corner beside the clock.
    private static let titleClearance = 14.0

    @StateObject private var model: WatchLoggingModel
    @FocusState private var crownFocused: Bool
    @Environment(\.watchAccent) private var accent

    /// Side of the single row's − / + buttons, and the height of the shared pair:
    /// small, so Log stays on a 40 mm screen; the Crown does most of the stepping.
    private static let stepSide: CGFloat = 32

    /// Called after a successful log, so the app shell can re-evaluate which
    /// surface it shows — logging a set starts a rest, and the shell swaps to
    /// the rest surface on that nudge (D-161).
    private let onLogged: (() -> Void)?

    /// The page counter the pager passes down ("2/5"), or nil when the session
    /// has one exercise; the pager keeps the counter on the locked single page
    /// (an effort clock running).
    private let pageLabel: String?

    public init(
        state: WatchLoggingState,
        haptics: WatchHaptics = WristHaptics(),
        onLogged: (() -> Void)? = nil,
        pageLabel: String? = nil
    ) {
        _model = StateObject(wrappedValue: WatchLoggingModel(state: state, haptics: haptics))
        self.onLogged = onLogged
        self.pageLabel = pageLabel
    }

    public var body: some View {
        crownDriven(surface)
            .onAppear {
                model.start()
                crownFocused = true
            }
            .onDisappear { model.stop() }
            // The poll after a suspension is the one that matters: the countdown
            // kept running while the screen did not, and it fires at the instant it
            // was due. Coming back to the foreground also gives the Crown its focus
            // back.
            .onReceive(
                NotificationCenter.default.publisher(
                    for: WKApplication.willEnterForegroundNotification
                )
            ) { _ in
                model.poll()
                crownFocused = true
            }
    }

    /// The rows, the readout and the one button, titled with the exercise.
    private var surface: some View {
        VStack(spacing: Self.surfaceInset) {
            header
            Spacer(minLength: 0)
            fieldControls
            if let readout = model.workReadout {
                Text(readout)
                    .font(.largeTitle)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            primaryButton
        }
        .padding(.horizontal, Self.surfaceInset)
    }

    /// One Crown binding for the whole surface. It steps the armed row; a
    /// binding per row left every one of them without focus, so no turn
    /// reached any of them.
    private func crownDriven<Content: View>(_ content: Content) -> some View {
        content
            .focusable(true)
            .focused($crownFocused)
            .digitalCrownRotation(
                detent: crownBinding,
                from: -WatchLoggingModel.pointsPerDetent * Self.crownRangeDetents,
                through: WatchLoggingModel.pointsPerDetent * Self.crownRangeDetents,
                by: WatchLoggingModel.pointsPerDetent,
                sensitivity: .medium,
                isContinuous: true,
                isHapticFeedbackEnabled: true
            )
    }

    private var crownBinding: Binding<Double> {
        Binding(
            get: { model.crownPosition },
            set: { model.turn(to: $0) }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(model.state.exerciseName ?? "No exercise")
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if let pageLabel {
                    Text(pageLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, Self.titleClearance)
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
            if let status = model.statusLine {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // Plan 59, D-4: why a sensor is silent, only while access is off.
            ForEach(model.sensorNotices, id: \.self) { notice in
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        // A couple of points of headroom, so the lines sit under the exercise
        // name above them.
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The period the next log will record, in this modality's own word and
    /// singular ("Period 2"), or nil for the kinds without periods (D-1307).
    private var roundLine: String? { model.periodLine }

    /// The value controls: one value keeps its own row with − and + around it;
    /// two values (reps and weight) share one − / + pair under two tiles, so the
    /// pair stays a thumb wide and Log stays on the screen.
    @ViewBuilder
    private var fieldControls: some View {
        let fields = model.state.fields
        if fields.count > 1 {
            VStack(spacing: Self.surfaceInset) {
                HStack(spacing: Self.surfaceInset) {
                    ForEach(fields, id: \.metricKey) { field in
                        tile(field)
                    }
                }
                sharedStepper
            }
        } else if let only = fields.first {
            row(only)
        }
    }

    /// The label and the numerals of one value.
    private func valueFace(_ field: WatchMetricField) -> some View {
        VStack(spacing: 0) {
            Text(field.label)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(field.displayValue)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !field.unitLabel.isEmpty {
                    Text(field.unitLabel).font(.caption2)
                }
            }
        }
    }

    /// One value as a tile. The one the Crown steps wears an outline in the
    /// accent; a tap on a tile moves it.
    private func tile(_ field: WatchMetricField) -> some View {
        let armed = model.armedMetricKey == field.metricKey
        let outline: Color = armed ? (accent?.color ?? Color.white) : Color.clear
        return valueFace(field)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(outline, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !field.isMeasured else { return }
                model.arm(field.metricKey)
                crownFocused = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(field.label) \(field.displayValue) \(field.unitLabel)")
    }

    /// One value's row: − and + around its tile.
    private func row(_ field: WatchMetricField) -> some View {
        HStack {
            stepButton(
                systemName: "minus",
                label: "Less \(field.label)",
                enabled: !field.isMeasured,
                width: Self.stepSide
            ) {
                model.arm(field.metricKey)
                model.adjust(field.metricKey, detents: -1)
            }

            tile(field)

            stepButton(
                systemName: "plus",
                label: "More \(field.label)",
                enabled: !field.isMeasured,
                width: Self.stepSide
            ) {
                model.arm(field.metricKey)
                model.adjust(field.metricKey, detents: 1)
            }
        }
    }

    /// The shared − / + under two tiles: both step the outlined tile.
    private var sharedStepper: some View {
        let label = model.state.fields.first { $0.metricKey == model.armedMetricKey }?.label ?? ""
        let enabled = model.armedMetricKey != nil
        return HStack(spacing: Self.surfaceInset) {
            stepButton(systemName: "minus", label: "Less \(label)", enabled: enabled, width: nil) {
                model.stepArmed(-1)
            }
            stepButton(systemName: "plus", label: "More \(label)", enabled: enabled, width: nil) {
                model.stepArmed(1)
            }
        }
    }

    /// A step button: a fixed-size plain-style capsule. The bordered style draws
    /// larger than any frame it is given, which is what overlapped the rows.
    /// `width` nil fills the available width (the shared pair).
    private func stepButton(
        systemName: String,
        label: String,
        enabled: Bool = true,
        width: CGFloat?,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            crownFocused = true
            action()
        } label: {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .foregroundStyle(enabled ? Color.white : Color.gray)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: Self.stepSide)
                .background(Capsule().fill(Color.white.opacity(enabled ? 0.18 : 0.08)))
        }
        .buttonStyle(.plain)
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
        .watchProminent()
        .disabled(!model.state.canLog)
    }
}

#endif
