//
//  WatchTimerMath.swift
//  WatchSessionEngine
//
//  Timer derivation. A watch timer is nothing but persisted timestamps and
//  pause bookkeeping; what the user sees is computed from the record and the
//  current instant (PROTOCOL.md, "Timer state (normative)").
//
//  One implementation, two platforms, byte-for-byte the same arithmetic as
//  `lib/watch/session/watch_timer_math.dart`.
//

import Foundation

/// How long `timer` has actually been counting, as of `now`. A paused or
/// stopped timer stops moving.
public func activeElapsedMs(_ timer: WatchTimerRecord, now: Date) -> Int {
    let countedUntil = timer.stoppedAt ?? timer.pausedAt ?? now
    let elapsed = Int(countedUntil.timeIntervalSince(timer.startedAt) * 1000)
        - timer.accumulatedPauseMs
    return elapsed < 0 ? 0 : elapsed
}

/// What is left of a countdown timer at `now`, or nil when the timer has no
/// planned duration (an elapsed timer counts up, it never counts down).
public func remainingMs(_ timer: WatchTimerRecord, now: Date) -> Int? {
    guard let planned = timer.plannedDurationMs else { return nil }
    let remaining = planned - activeElapsedMs(timer, now: now)
    return remaining < 0 ? 0 : remaining
}
