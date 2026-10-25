//
//  HealthKitRouteRecorder.swift
//  OmniTrain Watch App
//
//  The wrist's Health workout route: the fixes the workout's GPS already
//  produces, handed to HealthKit in batches through the package's
//  `WatchRouteKeeper`.
//
//  Plan: `docs/plans/2026-10-24-68-run-route-map-plan/2026-10-24-68-run-route-map-plan.md`
//

#if os(watchOS)

import Foundation
@preconcurrency import CoreLocation
import HealthKit
import WatchSessionEngine

/// What closing a route leaves to finish: the points not yet handed to Health, the package's
/// verdict, and the route builder (nil when no route was recorded).
nonisolated struct HealthKitRouteClose {
    let remainder: [WatchRawFix]
    let verdict: WatchRouteVerdict
    let builder: HKWorkoutRouteBuilder?
}

/// Feeds a Health workout route from the fixes the workout's GPS already produces (plan 68).
/// The package's `WatchRouteKeeper` decides which points enter and when the route is kept; this
/// class only turns them into `CLLocation`s and hands them to HealthKit. It never errors
/// outward: the workout's save never depends on the route (store rule 1).
nonisolated final class HealthKitRouteRecorder: @unchecked Sendable {
    private let keeper = WatchRouteKeeper()
    private let lock = NSLock()
    private var builder: HKWorkoutRouteBuilder?

    /// Starts a route for the live `workout` and answers whether it records. The route builder
    /// comes from the live builder's series builder (D-8), never from `HKWorkoutRouteBuilder(healthStore:`.
    func open(
        on workout: HKLiveWorkoutBuilder,
        routeSharingAllowed: Bool,
        beganAt: Date
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        builder = nil
        guard keeper.open(
            routeSharingAllowed: routeSharingAllowed,
            beganAt: beganAt
        ) else { return false }
        guard let route = workout.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder else {
            _ = keeper.close()
            return false
        }
        builder = route
        return true
    }

    /// One raw fix from the workout's GPS. When it completes a batch of ten, the batch goes to Health.
    func offer(_ fix: WatchRawFix) {
        lock.lock()
        defer { lock.unlock() }
        let batch = keeper.offer(fix)
        guard !batch.isEmpty, let route = builder else { return }
        route.insertRouteData(Self.locations(from: batch)) { _, _ in }
    }

    /// Closes the route (D-6): after this no point is accepted. The builder is handed to the caller
    /// and forgotten here, so it is finished or discarded exactly once.
    func close() -> HealthKitRouteClose {
        lock.lock()
        defer { lock.unlock() }
        let end = keeper.close()
        let closed = HealthKitRouteClose(remainder: end.remainder, verdict: end.verdict, builder: builder)
        builder = nil
        return closed
    }

    /// Finishes the closed route once the workout is saved (F-1, F-3, F-5): `save` with a saved
    /// workout inserts the remainder and finishes the route with it; every other case discards the
    /// builder. Errors are swallowed. The builder is never called again afterwards.
    func finish(_ closed: HealthKitRouteClose, workout: HKWorkout?) async {
        guard let route = closed.builder else { return }
        guard closed.verdict == .save, let workout else {
            route.discard()
            return
        }
        if !closed.remainder.isEmpty {
            try? await route.insertRouteData(Self.locations(from: closed.remainder))
        }
        _ = try? await route.finishRoute(with: workout, metadata: nil)
    }

    /// The route builder of a workout this process recovered after a kill (D-9), asked before the
    /// workout is finished. nil when HealthKit gives none.
    func recoveredBuilder(from recovered: HKLiveWorkoutBuilder) -> HKWorkoutRouteBuilder? {
        recovered.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
    }

    /// Finishes a recovered route with the saved workout. Failure (no points, F-3) is swallowed.
    func finishRecovered(_ route: HKWorkoutRouteBuilder?, workout: HKWorkout?) async {
        guard let route, let workout else { return }
        _ = try? await route.finishRoute(with: workout, metadata: nil)
    }

    /// The raw fixes as `CLLocation`s (D-10). A nil rich field becomes altitude 0 with vertical
    /// accuracy -1, course -1 and speed -1 (CoreLocation's "invalid").
    static func locations(from fixes: [WatchRawFix]) -> [CLLocation] {
        fixes.map { fix in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude),
                altitude: fix.altitudeMeters ?? 0,
                horizontalAccuracy: fix.horizontalAccuracyMeters,
                verticalAccuracy: fix.verticalAccuracyMeters ?? -1,
                course: fix.courseDegrees ?? -1,
                speed: fix.speedMetersPerSecond ?? -1,
                timestamp: fix.timestamp
            )
        }
    }
}

#endif
