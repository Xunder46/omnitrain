//
//  WatchRouteKeeper.swift
//  WatchSessionEngine
//
//  The rules for which GPS points enter a Health route, and when the route is
//  kept: raw fixes in, batches of ten out, one verdict at close.
//
//  Plan: `docs/plans/2026-10-24-68-run-route-map-plan/2026-10-24-68-run-route-map-plan.md`,
//  scenarios S-9801..S-9814 (D-1, D-3, D-4, D-5). Plan 76 supersedes D-1: every
//  workout records while route sharing is allowed (`open`), and the 50 m spread
//  rule at close is what keeps a treadmill, a lift or a standing workout from
//  saving a route (S-10601..S-10604).
//
//  The keeper holds at most one batch in memory and never the whole route: a
//  point is either handed to Health in the batch it completes, or it is still
//  waiting in the current batch when the workout closes. Every gate below is a
//  reason to accept nothing, mirroring the distance tracker's own honesty: a
//  rejected fix is never corrected and never becomes the reference.
//

import Foundation

/// What a route keeper decided when its workout closed.
public enum WatchRouteVerdict: Equatable {
    /// No route was ever recorded (the workout did not qualify).
    case none
    /// Hand the route to Health.
    case save
    /// Throw the route away (a treadmill, no fix, one fix).
    case discard
}

/// The rules for which GPS points enter a Health route, and when the route is kept (plan 68
/// D-1, D-3, D-4, D-5). Pure Foundation: the app target feeds it fixes and hands what it
/// returns to HealthKit. It keeps at most `batchSize` points in memory, never the whole route.
public final class WatchRouteKeeper {
    /// Health asks for no fix less accurate than this (Apple: "Don't add any locations whose accuracy is greater than 50 meters").
    public static let maxAccuracyMeters = 50.0
    /// Points are handed out in batches of exactly this many; the remainder at close.
    public static let batchSize = 10
    /// A route is kept only when some accepted point got at least this far from the first one.
    public static let minimumSpreadMeters = 50.0

    private let lock = NSLock()
    private var recording = false
    private var beganAt = Date.distantPast
    private var origin: WatchRawFix?
    private var last: WatchRawFix?
    private var pending: [WatchRawFix] = []
    private var count = 0
    private var farthest = 0.0
    private var outcome = WatchRouteVerdict.none

    public init() {}

    /// Starts a fresh route for a workout and answers whether it will record. Everything from an earlier workout is dropped.
    /// Any workout records while route sharing is allowed, whatever it is saved as and wherever it opened (plan 76 D-1,
    /// superseding plan 68 D-1): the route is kept at close only when it covers 50 m or more, so a workout that never got
    /// a GPS fix, or stood in one place, saves nothing.
    @discardableResult
    public func open(
        routeSharingAllowed: Bool,
        beganAt: Date
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        origin = nil
        last = nil
        pending = []
        count = 0
        farthest = 0
        outcome = .none
        self.beganAt = beganAt
        recording = routeSharingAllowed
        return recording
    }

    /// How many fixes have been accepted since `open`.
    public var acceptedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Offers one raw fix. Answers the batch of exactly `batchSize` points to hand to Health when this fix completed one, else empty.
    /// A fix is accepted when, in this order: (a) its latitude is in [-90, 90] and longitude in [-180, 180], both finite;
    /// (b) its horizontal accuracy is finite, >= 0 and <= 50 m; (c) its timestamp is not before the workout began;
    /// (d) it is strictly later than the last accepted fix; (e) the speed from the last accepted fix is at most
    /// `WatchDistanceTracker.maxSpeedMetersPerSecond` (the first accepted fix is exempt). A rejected fix never becomes the reference.
    /// Nothing is accepted before `open` recorded, or after `close`.
    public func offer(_ fix: WatchRawFix) -> [WatchRawFix] {
        lock.lock()
        defer { lock.unlock() }
        guard recording, admits(fix) else { return [] }
        if origin == nil { origin = fix }
        if let first = origin {
            farthest = max(farthest, WatchDistanceTracker.meters(from: first, to: fix))
        }
        last = fix
        count += 1
        pending.append(fix)
        guard pending.count >= Self.batchSize else { return [] }
        let batch = pending
        pending = []
        return batch
    }

    /// Ends the route: the points not yet handed out and the verdict. `save` needs at least two accepted points and
    /// some accepted point at least `minimumSpreadMeters` (exactly 50.0 counts) from the first; otherwise `discard`.
    /// A keeper that never recorded answers an empty list and `none`. A second close answers an empty list and the same verdict.
    public func close() -> (remainder: [WatchRawFix], verdict: WatchRouteVerdict) {
        lock.lock()
        defer { lock.unlock() }
        guard recording else { return ([], outcome) }
        recording = false
        let rest = pending
        pending = []
        outcome = count >= 2 && farthest >= Self.minimumSpreadMeters ? .save : .discard
        return (rest, outcome)
    }

    private func admits(_ fix: WatchRawFix) -> Bool {
        guard fix.latitude.isFinite, fix.longitude.isFinite,
              (-90.0...90.0).contains(fix.latitude),
              (-180.0...180.0).contains(fix.longitude)
        else { return false }
        guard fix.horizontalAccuracyMeters.isFinite,
              fix.horizontalAccuracyMeters >= 0,
              fix.horizontalAccuracyMeters <= Self.maxAccuracyMeters
        else { return false }
        guard fix.timestamp >= beganAt else { return false }
        guard let previous = last else { return true }
        let elapsed = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return false }
        let metres = WatchDistanceTracker.meters(from: previous, to: fix)
        return metres / elapsed <= WatchDistanceTracker.maxSpeedMetersPerSecond
    }
}
