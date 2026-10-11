//
//  WatchTrackedLocation.swift
//  WatchSessionEngine
//
//  The seam between the platform's raw fixes and the sensor layer that already
//  exists: `WatchTrackedLocation` is a `WatchSensorSource`'s location stream,
//  made of `WatchLocationFix` values the wrist computed itself.
//
//  Plan: `docs/plans/2026-10-10-19e-watch-distance-tracking-plan/2026-10-10-19e-watch-distance-tracking-plan.md`,
//  scenarios S-3206, S-3207 (D-2203).
//
//  The adapter is deliberately thin: it owns a permission passthrough and a
//  mapping, nothing else. `WatchSensorRecorder` already knows what to do with a
//  `WatchLocationFix` stream — store each value and settle the last one on stop
//  — so a wrist that measures its own distance plugs into that recorder without
//  either side learning about the other's types.
//

import Foundation

/// Where raw fixes and their permission come from.
///
/// This is the part the watch app target binds to a real sensor (19f); nothing
/// in this module imports an OS location type, so the rules stay testable.
public protocol WatchRawFixSource {
    func permission() async -> WatchSensorPermission

    func rawFixes() -> AsyncStream<WatchRawFix>
}

/// A raw fix source, seen as the sensor layer's location stream.
public final class WatchTrackedLocation {
    private let source: WatchRawFixSource

    public init(source: WatchRawFixSource) {
        self.source = source
    }

    /// The platform's answer, unchanged: the watch's decision to listen is made
    /// by `WatchSensorRecorder`, not here.
    public func permission() async -> WatchSensorPermission {
        await source.permission()
    }

    /// The source's fixes, accumulated into cumulative metres.
    ///
    /// Each call is its own effort: a new tracker, a new total, and its own raw
    /// stream. The returned stream yields only the fixes that added something,
    /// finishes when the raw one does, and cancelling it stops consuming the
    /// raw one. Anything the source does not answer — the refused radio, the
    /// fix the tracker ignored — simply never appears.
    public func fixes() -> AsyncStream<WatchLocationFix> {
        AsyncStream { continuation in
            let task = Task {
                var tracker = WatchDistanceTracker()
                for await raw in source.rawFixes() {
                    if let fix = tracker.accept(raw) {
                        continuation.yield(fix)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
