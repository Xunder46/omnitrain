//
//  HealthKitSensorFeed.swift
//  OmniTrain Watch App
//
//  The wrist's live readings: `HKLiveWorkoutBuilderDelegate` behind the
//  package's `WatchSensorSource` seam.
//
//  Plan: `docs/plans/2026-10-10-19d-watch-heart-rate-and-steps-plan/2026-10-10-19d-watch-heart-rate-and-steps-plan.md`,
//  D-2103, D-2104 and D-2105. The rules about *when* a subscription runs, and
//  what a reading becomes once stored, live in the package, where `swift test`
//  exercises them on macOS (`WatchSensorRecording`, `WatchSensorRecordingTests`).
//  What is left here is the platform side: the builder hands its collected
//  samples to this object, and this object reduces each one to the wire's unit.
//
//  Three rules shape this file:
//
//  1. **The feed never prompts.** It is given one closure that answers whether
//     the store's single authorization request resolved to granted, and it only
//     reports: `.unavailable` with no health data, `.denied` on that answer,
//     `.granted` otherwise (D-2104). HealthKit never reveals whether a read was
//     refused, so a refused read simply produces no samples — and the package's
//     "no reading, no pair — never a zero" rule keeps the summary absent.
//  2. **A reading is yielded, never kept.** The delegate callbacks arrive on
//     HealthKit's own queues, so the continuations live behind a lock and are
//     copied out of it before anything is yielded. The class is `nonisolated`
//     on purpose: the target's default isolation is the main actor, and
//     HealthKit calls the delegate off it.
//  3. **Location is delegated, never built here.** The feed is given a
//     `WatchTrackedLocation` — the adapter over the app's CoreLocation source —
//     and hands its two location members straight through, so the permission
//     question and the fixes stay the adapter's (D-2304). This file imports no
//     location framework: a feed that owns no radio cannot leak one.
//

#if os(watchOS)

import Foundation
import HealthKit
import WatchSessionEngine

/// `HKLiveWorkoutBuilderDelegate` and `WatchSensorSource`, over the store's own
/// workout builder.
///
/// One feed per store, and one subscription per `heartRate()` / `steps()` call:
/// a caller that stops consuming terminates its stream, and the continuation is
/// dropped with it. Nothing here survives a session — the package starts and
/// stops subscriptions, this object only carries them (D-2103).
nonisolated final class HealthKitSensorFeed: NSObject, WatchSensorSource, HKLiveWorkoutBuilderDelegate {
    /// Answers whether the store's workout authorization resolved to granted.
    /// The store awaits its own single resolution inside this closure, so asking
    /// here never opens a second prompt (D-2104).
    private let authorization: () async -> Bool

    /// The app's tracked location adapter: the feed reports its permission and
    /// carries its fixes, and decides neither itself (D-2304).
    private let trackedLocation: WatchTrackedLocation

    /// The listeners someone is holding right now, keyed by subscription. The
    /// delegate callbacks arrive on arbitrary queues, so every read and every
    /// write of these goes through the lock.
    private let lock = NSLock()
    private var heartRateContinuations: [UUID: AsyncStream<Double>.Continuation] = [:]
    private var stepContinuations: [UUID: AsyncStream<Double>.Continuation] = [:]

    init(authorization: @escaping () async -> Bool, location: WatchTrackedLocation) {
        self.authorization = authorization
        self.trackedLocation = location
        super.init()
    }

    // MARK: - WatchSensorSource

    /// Whether a workout is running with permission to read the result. Without
    /// permission there is no workout, so there is no builder and no data: the
    /// answer is `.denied` rather than a prompt (D-2104).
    func heartRatePermission() async -> WatchSensorPermission {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        return await authorization() ? .granted : .denied
    }

    func stepsPermission() async -> WatchSensorPermission {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        return await authorization() ? .granted : .denied
    }

    /// The adapter's answer, unchanged: whether location is granted, refused or
    /// unavailable is the CoreLocation source's to know, and the feed never asks
    /// for it itself (D-2304).
    func locationPermission() async -> WatchSensorPermission {
        await trackedLocation.permission()
    }

    /// Beats per minute, as the builder's statistics report them.
    func heartRate() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            heartRateContinuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.forgetHeartRate(id)
            }
        }
    }

    /// The adapter's own fixes, unchanged: the wrist's metres are computed in the
    /// package, over the stream the CoreLocation source feeds (D-2304).
    func location() -> AsyncStream<WatchLocationFix> {
        trackedLocation.fixes()
    }

    /// The builder's cumulative step count since it began; each value supersedes
    /// the one before.
    func steps() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            stepContinuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.forgetSteps(id)
            }
        }
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    /// Reduces what the builder collected to the two things the wire carries.
    ///
    /// Heart rate is the newest quantity in beats per minute; a beat that is not
    /// finite or is below the wire's minimum of 1 is dropped rather than stored
    /// (`WatchSensorSummaries.lowestHeartRateBpm`). Steps are the builder's sum
    /// since it began, which the package treats as cumulative.
    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for collected in collectedTypes {
            guard let type = collected as? HKQuantityType else { continue }

            if type == HKQuantityType(.heartRate) {
                guard let quantity = workoutBuilder
                    .statistics(for: type)?
                    .mostRecentQuantity()
                else { continue }

                let bpm = quantity.doubleValue(
                    for: HKUnit.count().unitDivided(by: HKUnit.minute())
                )
                if bpm.isFinite, bpm >= 1 { yieldHeartRate(bpm) }
            } else if type == HKQuantityType(.stepCount) {
                guard let quantity = workoutBuilder
                    .statistics(for: type)?
                    .sumQuantity()
                else { continue }

                yieldSteps(quantity.doubleValue(for: HKUnit.count()))
            }
        }
    }

    /// Nothing to do: the package learns about a session's boundaries from its
    /// own store, not from the builder's events.
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    // MARK: - Subscriptions

    private func forgetHeartRate(_ id: UUID) {
        lock.lock()
        heartRateContinuations[id] = nil
        lock.unlock()
    }

    private func forgetSteps(_ id: UUID) {
        lock.lock()
        stepContinuations[id] = nil
        lock.unlock()
    }

    /// Copies the listeners out of the lock and yields outside it, so a consumer
    /// that takes its time cannot hold up the builder's queue.
    private func yieldHeartRate(_ bpm: Double) {
        lock.lock()
        let listeners = Array(heartRateContinuations.values)
        lock.unlock()

        for listener in listeners { listener.yield(bpm) }
    }

    private func yieldSteps(_ count: Double) {
        lock.lock()
        let listeners = Array(stepContinuations.values)
        lock.unlock()

        for listener in listeners { listener.yield(count) }
    }
}

#endif
