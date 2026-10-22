//
//  WatchLoggingModel.swift
//  WatchSessionEngine
//
//  The logging surface's clock: a ticker for the readout, the haptic poll on
//  every tick, and the crown's turn accumulation. Mirrors the Flutter client's
//  `_WatchLoggingScreenState` in `lib/watch/logging/watch_logging_screen.dart`.
//
//  Deliberately outside the watchOS-only view: this is the part with a rule in
//  it — when a haptic is owed, and what a crown detent does — so it builds and
//  is tested on the desktop toolchain like the rest of the module.
//

import Combine
import Foundation

/// The view's model: publishes the readout and fires what the wrist is owed.
@MainActor
public final class WatchLoggingModel: ObservableObject {
    public let state: WatchLoggingState

    /// Points of crown travel that count as one detent — the same value the
    /// Flutter surface accumulates against, so a detent means the same thing on
    /// both wrists.
    public static let pointsPerDetent: Double = WatchMetricStepping.pointsPerDetent

    private let haptics: WatchHaptics
    private lazy var milestones = WatchTimerHaptics(state.engine)
    private var ticker: Timer?

    /// Where the crown last was, in points. A crown reports one absolute position
    /// for the whole surface, so it is remembered once and stays continuous
    /// across a change of the armed row: arming must not step a value by the
    /// distance the crown had already travelled.
    private var crownPoint: Double = 0

    /// Crown travel not yet worth a whole detent. Dropped when another row is
    /// armed, so half a detent aimed at one value never finishes on another.
    private var carry: Double = 0

    /// The row the user last chose, if any; `armedMetricKey` checks it is still
    /// a row the crown may drive.
    private var armedKey: String?

    /// The row the crown steps: the one the user armed while it is still on
    /// screen and not measured, else the first row a sensor is not keeping, else
    /// nil.
    public var armedMetricKey: String? {
        let open = state.fields.filter { !$0.isMeasured }
        if let armedKey, open.contains(where: { $0.metricKey == armedKey }) { return armedKey }
        return open.first?.metricKey
    }

    public var crownPosition: Double { crownPoint }

    /// Chooses the row the crown steps. A key that is not an open row is ignored.
    public func arm(_ metricKey: String) {
        guard state.fields.contains(where: { $0.metricKey == metricKey && !$0.isMeasured }) else { return }
        armedKey = metricKey
        carry = 0
        objectWillChange.send()
    }

    /// A crown event: the absolute position it now reports, turned into whole
    /// detents against where it last was and applied to the armed row. Travel
    /// short of a detent is carried to the next event.
    public func turn(to position: Double) {
        let moved = position - crownPoint
        crownPoint = position

        let waiting = carry + moved
        let detents = (waiting / Self.pointsPerDetent).rounded(.towardZero)
        carry = waiting - detents * Self.pointsPerDetent
        guard detents != 0, let key = armedMetricKey else { return }

        state.adjust(key, detents: detents)
        poll()
    }

    public init(state: WatchLoggingState, haptics: WatchHaptics) {
        self.state = state
        self.haptics = haptics
    }

    /// One second is enough to watch a countdown move without a rebuild storm.
    private static let tick: TimeInterval = 1

    public func start() {
        ticker = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    public func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Fires what is owed and republishes the readout.
    public func poll() {
        for milestone in milestones.poll(now: state.now()) {
            haptics.play(milestone)
        }
        objectWillChange.send()
    }

    /// What is left of the running round countdown, in seconds, or nil when
    /// none is running. A rest is a count-up and has no remaining time (D-160).
    public var countdown: Double? {
        guard let timer = state.timer(for: WatchTimerKind.round),
              timer.state != WatchTimerState.stopped else { return nil }
        guard let remaining = remainingMs(timer, now: state.now()) else { return nil }
        return Double(remaining) / 1000
    }

    public func adjust(_ metricKey: String, detents: Double) {
        state.adjust(metricKey, detents: detents)
        poll()
    }

    /// Steps the armed row by `detents`: what the shared − / + under two value
    /// tiles does. No armed row (every row is a sensor's reading, or there are
    /// none) is a no-op.
    public func stepArmed(_ detents: Double) {
        guard let key = armedMetricKey else { return }
        state.adjust(key, detents: detents)
        poll()
    }

    /// The header's one status line: the set caption and what the sensors read,
    /// joined with a dot, either alone when the other is absent, nil when
    /// neither is there. Two short captions cost a whole row on a 40 mm screen.
    public var statusLine: String? {
        let parts = [state.setCaption, sensorLine].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What the sensors are reading, as one line: the heart rate, the distance,
    /// and the pace it is being covered at. Absent pieces are left out rather
    /// than shown as zero — a session with no reading has nothing to report, and
    /// the line disappears entirely when there is nothing at all.
    private var sensorLine: String? {
        let readout = state.sensorLabels
        let unit = state.units.isMiles ? "mi" : "km"
        var parts: [String] = []
        if let beats = readout.heartRate { parts.append("\(beats) bpm") }
        if let distance = readout.distance { parts.append("\(distance) \(unit)") }
        if let pace = readout.pace { parts.append(pace) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Starts the effort's work clock (D-1308).
    public func startWork() async {
        await state.startWork()
        poll()
    }

    /// Whether the one button is still offering Start: a timed effort whose
    /// clock has not begun. A set is never awaiting a start, and neither is an
    /// effort already running (D-1316).
    private var isAwaitingStart: Bool { state.isTimedWork && !state.isWorkRunning }

    /// What the one button says: Start until the effort's clock is running, then
    /// Log — and always Log for a set, whose button never starts anything
    /// (D-1316).
    public var primaryTitle: String { isAwaitingStart ? "Start" : "Log" }

    /// What the one button does: starts the clock when nothing is running, and
    /// logs the effort otherwise (D-1316).
    public func primaryAction() async {
        if isAwaitingStart {
            await state.startWork()
        } else {
            _ = try? await state.log()
        }
        poll()
    }

    /// The readout, or nil for a set, whose rows are what it shows instead: a
    /// period's remaining time (its preset before Start), and the elapsed time
    /// for the kinds that count up (D-1316).
    public var workReadout: String? {
        guard state.isTimedWork else { return nil }
        if let remaining = state.workRemainingSeconds() {
            return WatchLoggingState.clock(Double(remaining))
        }
        return WatchLoggingState.clock(Double(state.workElapsedSeconds()))
    }

    /// The period the next log will record, in this modality's own word and
    /// singular ("Period 2"), or nil for the kinds without periods (D-1307).
    /// The view renders this line; the rule lives here so the desktop toolchain
    /// can assert it (D-1316).
    public var periodLine: String? {
        guard state.effortKind == WatchEffortKind.round else { return nil }
        return "\(Self.singular(state.roundsLabel)) \(state.nextRoundNumber)"
    }

    private static func singular(_ label: String) -> String {
        label.hasSuffix("s") ? String(label.dropLast()) : label
    }

    public func log() async {
        _ = try? await state.log()
        poll()
    }
}

/// A haptic player that records instead of buzzing, so the rule about when the
/// wrist is owed one can be asserted.
public final class RecordingHaptics: WatchHaptics {
    public private(set) var milestones: [WatchTimerMilestone] = []
    public private(set) var restPings = 0

    public init() {}

    public func play(_ milestone: WatchTimerMilestone) {
        milestones.append(milestone)
    }

    public func playRestPing() {
        restPings += 1
    }
}

/// How the wrist is told a countdown ended, and that a rest has reached another
/// multiple of its interval. The watchOS implementation lives in
/// `WatchLoggingView.swift`, behind the platform guard; this is the contract.
public protocol WatchHaptics {
    func play(_ milestone: WatchTimerMilestone)

    /// The rest ping: a rest counts up and is owed nothing when it ends, so this
    /// is its own cue rather than a `WatchTimerMilestone` case (D-244, D-251).
    func playRestPing()
}
