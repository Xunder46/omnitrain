//
//  WatchRestPingScheduler.swift
//  WatchSessionEngine
//
//  Plan 61, D-1:
//  `docs/plans/2026-10-23-61-wrist-down-rest-pings-plan/2026-10-23-61-wrist-down-rest-pings-plan.md`.
//
//  Who asks the rest ping rule: the host, not the rest view. The rest view is
//  redrawn only while the screen is lit, so a ping asked from its timeline came
//  late or never with the wrist down. The workout session keeps the app
//  running; this keeps its own clock and wakes just after each boundary of the
//  persisted rest row.
//

import Foundation

/// The wrist's rest-ping scheduler: one `WatchRestPing` rule driven on a wait
/// loop the host arms, instead of the rest view's redraw ticks.
@MainActor
public final class WatchRestPingScheduler {
    private let state: WatchLoggingState
    private let interval: () -> Int
    private let haptics: WatchHaptics
    private let sleep: (TimeInterval) async -> Void
    private let rule = WatchRestPing()
    private var loop: Task<Void, Never>?

    public nonisolated static let realSleep: (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    public init(
        state: WatchLoggingState,
        interval: @escaping () -> Int,
        haptics: WatchHaptics,
        sleep: @escaping (TimeInterval) async -> Void = WatchRestPingScheduler.realSleep
    ) {
        self.state = state
        self.interval = interval
        self.haptics = haptics
        self.sleep = sleep
    }

    /// Asks the rule once, taps if a ping is owed, and returns how long to wait
    /// for the next boundary (nil when no rest is open or the interval is Off).
    public func step() -> TimeInterval? {
        let seconds = interval()
        let elapsedMs = state.restElapsedMilliseconds()
        if rule.isOwed(
            restId: state.engine.timerFor(WatchTimerKind.rest)?.recordId,
            elapsed: elapsedMs.map { $0 / 1000 },
            interval: seconds
        ) {
            haptics.playRestPing()
        }
        guard let elapsedMs else { return nil }
        return Self.nextWait(elapsedMs: elapsedMs, interval: seconds)
    }

    /// Starts (or restarts) the wait loop. `step()` runs first, so arming also
    /// catches up a boundary crossed while nobody was looking.
    public func arm() {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, let wait = self.step() {
                await self.sleep(wait)
            }
        }
    }

    public func disarm() {
        loop?.cancel()
        loop = nil
    }

    /// Waits for the current loop to end (tests).
    public func finished() async {
        await loop?.value
    }

    /// Seconds from `elapsedMs` of a rest to just after its next boundary, nil
    /// when the interval is Off or the elapsed is negative. The 50 ms lands the
    /// wake after the boundary, never before it.
    public static func nextWait(elapsedMs: Int, interval: Int) -> TimeInterval? {
        guard interval > 0, elapsedMs >= 0 else { return nil }
        let step = interval * 1000
        return Double(step - elapsedMs % step + 50) / 1000
    }
}
