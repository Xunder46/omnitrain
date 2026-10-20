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
//  A beat arrives through two paths. A read that knows when its sample ended —
//  both paths' usual case — goes through one gate (`yieldHeartRateIfNewer`), so
//  a repeated read is never a second row. When the statistics carry no interval
//  there is nothing to compare: the pull drops that beat rather than dating it
//  `Date()`, where the builder's own push, which has just collected the sample,
//  yields it as it arrives (D-3108, D-3113, D-3118):
//
//  * the builder's push — `workoutBuilder(_:didCollectDataOf:)`, which is the
//    only path while the app runs in the foreground, and
//  * a pull — while at least one heart-rate listener is live, the feed re-reads
//    the builder's newest beat every `heartRatePullSeconds` and whenever the app
//    becomes active. HealthKit's callback can be missed while the app is
//    suspended with the wrist down, and nothing else re-reads the builder on
//    wake.
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

    /// How often the pull re-reads the builder's newest beat. Three seconds is
    /// short enough for a readout that follows the wrist and long enough that a
    /// suspended app is not woken for it (D-3113).
    private let heartRatePullSeconds: TimeInterval = 3

    /// The builder the store handed over in `begin`, or nil between workouts.
    /// The pull reads this one and holds nothing of its own (D-3113).
    private var heartRateBuilder: HKLiveWorkoutBuilder?

    /// The end instant of the last beat this feed yielded, from either path. A
    /// read of a beat that is not strictly newer than this is a repeat, and a
    /// repeat is never a second row (D-3113).
    private var lastHeartRateEnd: Date?

    /// The live pull, while at least one heart-rate listener is held. nil when
    /// none is: nothing here outlives a subscription (D-3113).
    private var heartRatePull: Task<Void, Never>?

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
            let isFirstListener = heartRateContinuations.isEmpty
            heartRateContinuations[id] = continuation
            // The pull belongs to the listeners: the first one starts it, the
            // last one's termination stops it (D-3113).
            if isFirstListener { heartRatePull = startPull() }
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
    ///
    /// A pushed beat is yielded as it arrives: the builder has just collected it,
    /// so it is no repeat of an earlier read, and it is handed over without a
    /// fabricated instant when the statistics carry no interval (D-3118).
    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for collected in collectedTypes {
            guard let type = collected as? HKQuantityType else { continue }

            if type == HKQuantityType(.heartRate) {
                guard let statistics = workoutBuilder.statistics(for: type),
                      let quantity = statistics.mostRecentQuantity()
                else { continue }

                let bpm = quantity.doubleValue(
                    for: HKUnit.count().unitDivided(by: HKUnit.minute())
                )
                guard bpm.isFinite, bpm >= 1 else { continue }

                if let end = statistics.mostRecentQuantityDateInterval()?.end {
                    yieldHeartRateIfNewer(bpm, end: end)
                } else {
                    yieldHeartRate(bpm)
                }
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

    // MARK: - The pull

    /// Stores the builder the pull reads, or clears it — clearing the last
    /// yielded end with it, so the next workout starts from nothing.
    ///
    /// The store hands the builder over in `begin`, once the collection it
    /// belongs to exists, and drops it in `end`: the feed reads exactly the
    /// workout the session opened (D-3113).
    func refreshHeartRate(from builder: HKLiveWorkoutBuilder?) {
        lock.lock()
        heartRateBuilder = builder
        if builder == nil { lastHeartRateEnd = nil }
        lock.unlock()

        refreshHeartRate()
    }

    /// Reads the stored builder's newest beat once. What a pull tick and the
    /// app's return to the foreground both do: the builder's callback is missed
    /// while the app is suspended with the wrist down, and nothing else re-reads
    /// it on wake (D-3108, D-3113).
    ///
    /// A beat whose statistics carry no interval ends the read here: nothing can
    /// tell that beat from the one already yielded, and dating it `Date()` would
    /// make it newer than every read that follows it (D-3118).
    func refreshHeartRate() {
        lock.lock()
        let builder = heartRateBuilder
        lock.unlock()

        guard let builder,
              let statistics = builder.statistics(for: HKQuantityType(.heartRate)),
              let quantity = statistics.mostRecentQuantity()
        else { return }

        let bpm = quantity.doubleValue(
            for: HKUnit.count().unitDivided(by: HKUnit.minute())
        )
        guard bpm.isFinite, bpm >= 1 else { return }
        guard let end = statistics.mostRecentQuantityDateInterval()?.end else { return }

        yieldHeartRateIfNewer(bpm, end: end)
    }

    /// The pull's task: one read every `heartRatePullSeconds`, until the last
    /// listener's termination cancels it. A `Task` loop rather than a timer, so
    /// nothing has to be invalidated on a run loop HealthKit's queues do not own
    /// (D-3113).
    private func startPull() -> Task<Void, Never> {
        let interval = UInt64(heartRatePullSeconds * 1_000_000_000)
        return Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard let self else { return }
                self.refreshHeartRate()
            }
        }
    }

    // MARK: - Subscriptions

    private func forgetHeartRate(_ id: UUID) {
        lock.lock()
        heartRateContinuations[id] = nil
        let stopping = heartRateContinuations.isEmpty ? heartRatePull : nil
        if stopping != nil { heartRatePull = nil }
        lock.unlock()

        stopping?.cancel()
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

    /// The gate a heart-rate read goes through when its sample's end instant is
    /// known: the beat is yielded only when `end` is strictly later than the last
    /// one yielded, and that instant becomes the new mark. A tick that re-reads a
    /// beat already stored therefore yields nothing, so the push path and the pull
    /// path cannot make two rows of one beat (D-3113).
    private func yieldHeartRateIfNewer(_ bpm: Double, end: Date) {
        lock.lock()
        let isNewer = lastHeartRateEnd.map { end > $0 } ?? true
        if isNewer { lastHeartRateEnd = end }
        lock.unlock()

        guard isNewer else { return }
        yieldHeartRate(bpm)
    }

    private func yieldSteps(_ count: Double) {
        lock.lock()
        let listeners = Array(stepContinuations.values)
        lock.unlock()

        for listener in listeners { listener.yield(count) }
    }
}

#endif
