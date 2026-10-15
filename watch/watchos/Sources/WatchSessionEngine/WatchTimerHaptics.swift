//
//  WatchTimerHaptics.swift
//  WatchSessionEngine
//
//  When the wrist is owed a haptic, derived from the timer's own timestamps.
//  Mirrors `lib/watch/logging/watch_timer_haptics.dart`, so both watch clients
//  fire on the same instant given the same timer record.
//
//  Nothing here counts down. A countdown's end is a property of the timer
//  record and the current instant, so the case where the screen was off is not
//  a special case: the view polls on every tick, on every touch, and on
//  resume, and the first poll after the instant fires once and reports the
//  instant it was due.
//

import Foundation

/// A countdown that reached zero, and the wall-clock moment it did.
public struct WatchTimerMilestone: Equatable {
    public let kind: String
    public let at: Date

    public init(kind: String, at: Date) {
        self.kind = kind
        self.at = at
    }
}

/// Decides which countdowns the user is owed a haptic for.
public final class WatchTimerHaptics {
    private let engine: WatchSessionEngine

    /// Timer rows already announced. Keyed on the record rather than the kind,
    /// so the next round's countdown — a new row — is owed its own haptic.
    private var announced: Set<String> = []

    public init(_ engine: WatchSessionEngine) {
        self.engine = engine
    }

    /// The countdowns that reached zero as of `now` and have not been announced.
    ///
    /// A timer with no planned duration never reaches zero; one that was ended
    /// before its instant never got there; one that was ended afterwards did.
    public func poll(now: Date) -> [WatchTimerMilestone] {
        var milestones: [WatchTimerMilestone] = []

        for kind in WatchTimerKind.all {
            // No rest alarm whatever the row holds: a rest is a count-up, and a
            // row an older build wrote may still carry its old plan, which
            // `remainingMs` would clamp to zero (D-160, D-163).
            guard kind != WatchTimerKind.rest else { continue }
            guard let timer = engine.timerFor(kind) else { continue }
            guard remainingMs(timer, now: now) == 0 else { continue }
            guard announced.insert(timer.recordId).inserted else { continue }

            milestones.append(
                WatchTimerMilestone(
                    kind: kind,
                    at: completionInstant(timer) ?? now
                )
            )
        }

        return milestones
    }
}
