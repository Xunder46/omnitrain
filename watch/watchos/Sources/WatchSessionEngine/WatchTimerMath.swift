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

/// The wall-clock instant `timer` reaches zero, or nil when it has no planned
/// duration.
///
/// A pause postpones the instant, and the postponement is exactly the pause
/// bookkeeping the record carries. Whether the countdown got there is
/// `remainingMs`'s answer, not this one: a timer paused before its instant has
/// one in the past and still has time left.
public func completionInstant(_ timer: WatchTimerRecord) -> Date? {
    guard let planned = timer.plannedDurationMs else { return nil }
    let plannedMs = Double(planned + timer.accumulatedPauseMs)
    return timer.startedAt.addingTimeInterval(plannedMs / 1000)
}
