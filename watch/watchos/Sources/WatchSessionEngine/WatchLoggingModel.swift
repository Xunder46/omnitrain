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
    public static let pointsPerDetent: Double = 32

    private let haptics: WatchHaptics
    private lazy var milestones = WatchTimerHaptics(state.engine)
    private var ticker: Timer?

    /// Where the crown last was, per metric key. A crown reports a position
    /// rather than a delta, so the row has to remember the previous one.
    private var crownPositions: [String: Double] = [:]

    /// Crown travel not yet worth a whole detent, per metric key. A wrist turn
    /// is continuous and a step is discrete; the leftover is what keeps a slow
    /// turn from being silently rounded away.
    private var carry: [String: Double] = [:]

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

    /// What is left of the running countdown, in seconds, or nil when none is
    /// running.
    public var countdown: Double? {
        let timer = state.timer(for: WatchTimerKind.round)
            ?? state.timer(for: WatchTimerKind.rest)
        guard let timer, timer.state != WatchTimerState.stopped else { return nil }
        guard let remaining = remainingMs(timer, now: state.now()) else { return nil }
        return Double(remaining) / 1000
    }

    public func adjust(_ metricKey: String, detents: Double) {
        state.adjust(metricKey, detents: detents)
        poll()
    }

    public func log() async {
        _ = try? await state.log()
        poll()
    }

    // MARK: - Crown binding

    /// The crown's last position for a row, in points.
    public func crownPosition(for metricKey: String) -> Double {
        crownPositions[metricKey] ?? 0
    }

    /// A crown event: the position it now reports, turned into whole detents
    /// against where the row last saw it. Travel short of a detent is carried
    /// to the next event rather than rounding the value off its step.
    public func turn(_ metricKey: String, to position: Double) {
        let moved = position - crownPosition(for: metricKey)
        crownPositions[metricKey] = position

        let waiting = (carry[metricKey] ?? 0) + moved
        let detents = (waiting / Self.pointsPerDetent).rounded(.towardZero)
        carry[metricKey] = waiting - detents * Self.pointsPerDetent
        guard detents != 0 else { return }

        state.adjust(metricKey, detents: detents)
        poll()
    }
}

/// A haptic player that records instead of buzzing, so the rule about when the
/// wrist is owed one can be asserted.
public final class RecordingHaptics: WatchHaptics {
    public private(set) var milestones: [WatchTimerMilestone] = []

    public init() {}

    public func play(_ milestone: WatchTimerMilestone) {
        milestones.append(milestone)
    }
}

/// How the wrist is told a countdown ended. The watchOS implementation lives in
/// `WatchLoggingView.swift`, behind the platform guard; this is the contract.
public protocol WatchHaptics {
    func play(_ milestone: WatchTimerMilestone)
}
