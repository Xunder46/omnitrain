//
//  WatchRestPing.swift
//  WatchSessionEngine
//
//  The wrist's rest ping. Plan:
//  `docs/plans/2026-10-08-22-rest-ping-on-watch-plan/2026-10-08-22-rest-ping-on-watch-plan.md`,
//  D-243 and D-250.
//
//  A rest counts up, so there is no length to count down from and no end-of-rest
//  alarm: the ping is the one cue a rest gets, and it repeats at each multiple
//  of the interval the phone last sent (0 = Off, and Off never pings). The rule
//  is here, without UI, because the rest view is compiled only for watchOS and
//  this has to be testable on the host: the view asks it once per one-second
//  tick and plays the tap it is owed.
//
//  The state is per rest row: `lastPinged` belongs to the `recordId` being
//  walked, and a different row starts from nothing, so the next rest pings at
//  its own first boundary instead of inheriting the last rest's.
//

import Foundation

/// Whether the open rest is owed its next ping, and how far it has pings.
public final class WatchRestPing {
    /// The boundary the row being walked has already pinged at, in whole
    /// seconds.
    private var lastPinged = 0

    /// The row `lastPinged` belongs to.
    private var pingingRestId: String?

    public init() {}

    /// Whether a ping is owed at this instant of the rest.
    ///
    /// - Parameters:
    ///   - restId: the open rest row's `recordId`, nil when no rest is running.
    ///   - elapsed: the rest's elapsed whole seconds, nil when no rest is
    ///     running.
    ///   - interval: the phone's interval in seconds; 0 or less is Off.
    public func isOwed(restId: String?, elapsed: Int?, interval: Int) -> Bool {
        // A closed rest is not evaluated at all: there is nothing to ping.
        guard let restId, let elapsed else { return false }

        if pingingRestId != restId {
            pingingRestId = restId
            lastPinged = 0
        }

        // Off, or a wrist that has not heard from the phone yet.
        guard interval > 0 else { return false }

        // The multiple of the interval the rest has reached. A poll that lands
        // after a gap still catches up, once: the boundary is crossed rather
        // than counted, so the boundaries the gap skipped are never pinged.
        let boundary = (elapsed / interval) * interval
        guard boundary > 0, boundary > lastPinged else { return false }

        lastPinged = boundary
        return true
    }
}
