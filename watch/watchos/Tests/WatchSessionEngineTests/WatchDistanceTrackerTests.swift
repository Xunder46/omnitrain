//
//  WatchDistanceTrackerTests.swift
//  WatchSessionEngineTests
//
//  Phase 1A of
//  `docs/plans/2026-10-10-19e-watch-distance-tracking-plan/2026-10-10-19e-watch-distance-tracking-plan.md`:
//  the wrist's own distance, turned from raw fixes into a monotonic total, and
//  the adapter that feeds the existing sensor seam.
//
//  Scenario mapping:
//    S-3200 accepted fixes accumulate the great-circle total → `testS3200...`
//    S-3201 the accuracy gate                              → `testS3201...`
//    S-3202 the jump gate                                  → `testS3202...`
//    S-3203 stillness never accumulates                    → `testS3203...`
//    S-3204 a slow creep clears the floor and adds         → `testS3204...`
//    S-3205 a fix not after the last accepted one          → `testS3205...`
//    S-3206 the adapter maps a fresh tracker per call      → `testS3206...`
//    S-3207 the recorder end to end, denial included       → `testS3207...`
//    S-3220 the floor scales with the fix's own accuracy   → `testS3220...`
//    S-3303 a cached fix never becomes the origin          → `testS3303...`
//    S-3304 the gate boundary is inclusive                 → `testS3304...`
//    S-3306 the clock is read once per fixes() call        → `testS3306...`
//    S-3307 a late-arriving fix stamped after the start     → `testS3307...`
//
//  The arithmetic is inline and asserted with an accuracy of ±0.01 m: at 52° N
//  0.0010° of latitude is 111.194927 m, 0.0020° is 222.389853 m, 0.00002° is
//  2.223899 m, 0.00005° is 5.559746 m, 0.0003° is 33.358478 m, and a 0.045°
//  jump one second later is 5003.772 m/s (asserted as a rejection, never as
//  that number).
//

import XCTest

@testable import WatchSessionEngine

private final class FinishedFlag: @unchecked Sendable { var done = false }

/// The raw fixes, as the platform would hand them over: the permission it
/// answers with, a stream the test feeds, and a count of subscriptions so "a
/// fresh stream per call" is an assertion rather than an assumption.
final class ScriptedRawFixSource: WatchRawFixSource {
    var grant: WatchSensorPermission = .granted

    private(set) var subscriptions = 0

    /// Whether the raw stream has ended — closed by the test, or cancelled by
    /// its consumer.
    private(set) var rawStreamEnded = false

    private var continuation: AsyncStream<WatchRawFix>.Continuation?

    init(grant: WatchSensorPermission = .granted) {
        self.grant = grant
    }

    func permission() async -> WatchSensorPermission { grant }

    func rawFixes() -> AsyncStream<WatchRawFix> {
        // The stream's build closure runs inside the initializer, so counting
        // the subscription afterwards is what lets a test know the source is
        // ready to be fed.
        let stream = AsyncStream<WatchRawFix> { continuation in
            continuation.onTermination = { [weak self] _ in self?.rawStreamEnded = true }
            self.continuation = continuation
        }
        subscriptions += 1
        return stream
    }

    func fix(_ raw: WatchRawFix) { continuation?.yield(raw) }

    func close() { continuation?.finish() }
}

/// The recorder's sensor source: location is a `WatchTrackedLocation`'s stream,
/// and its permission answer is the raw source's. Heart rate and steps say
/// `unavailable`, so the only subscription a test can see is the location one.
///
/// The clock is the test's own, because this file's fixes are stamped months
/// before the wall clock: with `WatchTrackedLocation`'s default clock every one
/// of them would be older than the freshness limit and dropped.
final class TrackedLocationSensorSource: WatchSensorSource {
    let raw: ScriptedRawFixSource
    let tracked: WatchTrackedLocation

    init(raw: ScriptedRawFixSource, clock: @escaping () -> Date) {
        self.raw = raw
        self.tracked = WatchTrackedLocation(source: raw, clock: clock)
    }

    func heartRatePermission() async -> WatchSensorPermission { .unavailable }
    func locationPermission() async -> WatchSensorPermission { await tracked.permission() }
    func stepsPermission() async -> WatchSensorPermission { .unavailable }

    func heartRate() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func location() -> AsyncStream<WatchLocationFix> { tracked.fixes() }
    func steps() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
}

/// Every fix in this file is stamped from the same instant the harness uses, so
/// the arithmetic is the only thing under test.
final class WatchDistanceTrackerTests: XCTestCase {

    private let t0 = testInstant()

    private func fix(
        _ latitude: Double,
        _ longitude: Double,
        accuracy: Double,
        at seconds: Double
    ) -> WatchRawFix {
        WatchRawFix(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: accuracy,
            timestamp: t0.addingTimeInterval(seconds)
        )
    }

    // MARK: - S-3200 accepted fixes accumulate the great-circle total

    func testS3200AcceptedFixesAccumulateTheGreatCircleTotal() throws {
        var tracker = WatchDistanceTracker()

        XCTAssertNil(
            tracker.accept(fix(52.0000, 5.0, accuracy: 5, at: 0)),
            "the first accepted fix is the origin and measures nothing"
        )
        XCTAssertEqual(tracker.totalMeters, 0, accuracy: 0.01)

        let firstStep = try XCTUnwrap(tracker.accept(fix(52.0010, 5.0, accuracy: 5, at: 30)))
        XCTAssertEqual(firstStep.distanceMeters, 111.195, accuracy: 0.01)

        let secondStep = try XCTUnwrap(tracker.accept(fix(52.0020, 5.0, accuracy: 5, at: 60)))
        XCTAssertEqual(secondStep.distanceMeters, 222.390, accuracy: 0.01)
        XCTAssertEqual(tracker.totalMeters, 222.390, accuracy: 0.01)
    }

    // MARK: - S-3201 the accuracy gate

    func testS3201AnInaccurateFixIsNeverAnOriginAndNeverAdds() throws {
        var tracker = WatchDistanceTracker()

        XCTAssertNil(tracker.accept(fix(52.0000, 5.0, accuracy: 80, at: 0)))
        XCTAssertNil(tracker.accept(fix(52.0000, 5.0, accuracy: 80, at: 10)))
        XCTAssertEqual(tracker.totalMeters, 0, accuracy: 0.01)

        XCTAssertNil(
            tracker.accept(fix(52.0000, 5.0, accuracy: 5, at: 20)),
            "the first accurate fix is the origin"
        )

        XCTAssertNil(tracker.accept(fix(52.0010, 5.0, accuracy: -1, at: 30)))
        XCTAssertNil(tracker.accept(fix(52.0010, 5.0, accuracy: 31, at: 40)))
        XCTAssertEqual(tracker.totalMeters, 0, accuracy: 0.01)

        let boundary = try XCTUnwrap(
            tracker.accept(fix(52.0010, 5.0, accuracy: 30, at: 50)),
            "accuracy 30 is still accepted"
        )
        XCTAssertEqual(boundary.distanceMeters, 111.195, accuracy: 0.01)
    }

    // MARK: - S-3202 the jump gate

    func testS3202AJumpIsIgnoredAndLeavesTheReferenceWhereItWas() throws {
        var tracker = WatchDistanceTracker()
        XCTAssertNil(tracker.accept(fix(52.0000, 5.0, accuracy: 5, at: 0)))

        let step = try XCTUnwrap(tracker.accept(fix(52.0010, 5.0, accuracy: 5, at: 30)))
        XCTAssertEqual(step.distanceMeters, 111.195, accuracy: 0.01)

        XCTAssertNil(
            tracker.accept(fix(52.0450, 5.0, accuracy: 5, at: 31)),
            "5003.772 m in one second is a jump, not a person"
        )

        let afterTheJump = try XCTUnwrap(
            tracker.accept(fix(52.0020, 5.0, accuracy: 5, at: 60)),
            "the reference did not move, so this step is measured from 52.0010"
        )
        XCTAssertEqual(afterTheJump.distanceMeters, 222.390, accuracy: 0.01)
        XCTAssertEqual(tracker.totalMeters, 222.390, accuracy: 0.01)
    }

    // MARK: - S-3203 stillness never accumulates

    func testS3203AStillWristsDriftNeverAccumulates() {
        var tracker = WatchDistanceTracker()
        XCTAssertNil(tracker.accept(fix(52.0000, 5.0, accuracy: 10, at: 0)))

        for step in 1...10 {
            let latitude = step.isMultiple(of: 2) ? 52.0 : 52.00002
            XCTAssertNil(
                tracker.accept(fix(latitude, 5.0, accuracy: 10, at: Double(step) * 5)),
                "2.224 m is under the max(2, 0.5 × 10) = 5 m floor"
            )
        }

        XCTAssertEqual(tracker.totalMeters, 0, accuracy: 0.01)
    }

    // MARK: - S-3204 a slow creep clears the floor and adds up

    func testS3204ASlowCreepClearsTheFloorAndMovesTheReference() throws {
        var tracker = WatchDistanceTracker()
        XCTAssertNil(tracker.accept(fix(52.0000, 5.0, accuracy: 3, at: 0)))

        let crept = try XCTUnwrap(
            tracker.accept(fix(52.00002, 5.0, accuracy: 3, at: 30)),
            "2.224 m clears the max(2, 0.5 × 3) = 2 m floor"
        )
        XCTAssertEqual(crept.distanceMeters, 2.224, accuracy: 0.01)

        let nextCrept = try XCTUnwrap(
            tracker.accept(fix(52.00004, 5.0, accuracy: 3, at: 60)),
            "the reference moved with the creep, so the next 2.224 m adds too"
        )
        XCTAssertEqual(nextCrept.distanceMeters, 4.448, accuracy: 0.01)
    }

    // MARK: - S-3220 the floor scales with the fix's own accuracy

    func testS3220TheFloorScalesWithTheFixesOwnAccuracy() throws {
        var tracker = WatchDistanceTracker()
        XCTAssertNil(tracker.accept(fix(52.0000, 5.0, accuracy: 5, at: 0)))

        // 0.00005° is 5.560 m: over a fixed 2 m floor, under the
        // max(2, 0.5 × 20) = 10 m floor an accuracy-20 fix sets.
        XCTAssertNil(
            tracker.accept(fix(52.00005, 5.0, accuracy: 20, at: 30)),
            "5.560 m is under the max(2, 0.5 × 20) = 10 m floor"
        )
        XCTAssertEqual(tracker.totalMeters, 0, accuracy: 0.01)

        // The reference did not move, so this is measured from the origin:
        // 0.0003° is 33.358 m, over the max(2, 0.5 × 5) = 2.5 m floor.
        let accepted = try XCTUnwrap(tracker.accept(fix(52.0003, 5.0, accuracy: 5, at: 60)))
        XCTAssertEqual(accepted.distanceMeters, 33.358, accuracy: 0.01)
        XCTAssertEqual(tracker.totalMeters, 33.358, accuracy: 0.01)
    }

    // MARK: - S-3205 a fix that is not after the last accepted one

    func testS3205AFixNotAfterTheLastAcceptedOneIsIgnored() throws {
        var tracker = WatchDistanceTracker()
        XCTAssertNil(tracker.accept(fix(52.0000, 5.0, accuracy: 5, at: 0)))

        let step = try XCTUnwrap(tracker.accept(fix(52.0010, 5.0, accuracy: 5, at: 30)))

        XCTAssertNil(
            tracker.accept(fix(52.0020, 5.0, accuracy: 5, at: 30)),
            "two fixes on one instant are one measurement"
        )
        XCTAssertNil(
            tracker.accept(fix(52.0020, 5.0, accuracy: 5, at: 10)),
            "and time does not run backwards"
        )
        XCTAssertEqual(tracker.totalMeters, step.distanceMeters, accuracy: 0.01)
    }

    // MARK: - S-3206 the adapter

    func testS3206TheAdapterPassesTheSourcesPermissionThrough() async {
        let raw = ScriptedRawFixSource()
        let adapter = WatchTrackedLocation(source: raw)

        for grant in [WatchSensorPermission.denied, .unavailable, .granted] {
            raw.grant = grant
            let answer = await adapter.permission()
            XCTAssertEqual(answer, grant)
        }
    }

    func testS3206TheAdapterMapsTheSourcesFixesIntoOneMonotonicTotal() async throws {
        let raw = ScriptedRawFixSource()
        let base = t0
        let adapter = WatchTrackedLocation(source: raw, clock: { base })

        // Subscribe first, and wait for the source to be listening: a fix is
        // handed to whoever is subscribed, the way a real stream behaves.
        var first = adapter.fixes().makeAsyncIterator()
        await eventually { raw.subscriptions == 1 }
        raw.fix(fix(52.0000, 5.0, accuracy: 5, at: 0))
        raw.fix(fix(52.0010, 5.0, accuracy: 5, at: 30))
        raw.fix(fix(52.0020, 5.0, accuracy: 5, at: 60))

        let firstMapped = await first.next()
        let firstValue = try XCTUnwrap(firstMapped, "the origin yields nothing")
        XCTAssertEqual(firstValue.distanceMeters, 111.195, accuracy: 0.01)
        let secondMapped = await first.next()
        let secondValue = try XCTUnwrap(secondMapped)
        XCTAssertEqual(secondValue.distanceMeters, 222.390, accuracy: 0.01)

        // A second subscription is a fresh tracker, not the first one's total.
        // The same coordinates are fed again, stamped after the first feed so
        // that a tracker shared across calls would accept them and show its
        // carried total, instead of rejecting them outright on time order.
        var second = adapter.fixes().makeAsyncIterator()
        await eventually { raw.subscriptions == 2 }
        raw.fix(fix(52.0000, 5.0, accuracy: 5, at: 90))
        raw.fix(fix(52.0010, 5.0, accuracy: 5, at: 120))

        let restartedMapped = await second.next()
        let restarted = try XCTUnwrap(restartedMapped)
        XCTAssertEqual(restarted.distanceMeters, 111.195, accuracy: 0.01)
        XCTAssertEqual(raw.subscriptions, 2, "each call asks for its own raw stream")
    }

    func testS3206TheMappedStreamFinishesWhenTheRawOneDoes() async {
        let raw = ScriptedRawFixSource()
        let base = t0
        let adapter = WatchTrackedLocation(source: raw, clock: { base })

        // The finish is observed through a deadline (`eventually`) rather than
        // awaited directly: a mapped stream that never finishes would hang the
        // direct await forever, and a hang proves nothing.
        let finished = FinishedFlag()
        let ended = Task {
            var last: WatchLocationFix?
            for await mapped in adapter.fixes() { last = mapped }
            finished.done = true
            return last
        }
        await eventually { raw.subscriptions == 1 }
        raw.fix(fix(52.0000, 5.0, accuracy: 5, at: 0))
        raw.close()

        await eventually({ finished.done }, "a closed raw stream finishes the map")

        if finished.done {
            let finalValue = await ended.value
            XCTAssertNil(
                finalValue,
                "the origin yields nothing, and closed input finishes the map"
            )
        }
    }

    func testS3206CancellingTheMappedStreamStopsConsumingTheRawOne() async {
        let raw = ScriptedRawFixSource()
        let adapter = WatchTrackedLocation(source: raw)

        let consumed = Task { for await _ in adapter.fixes() {} }
        await eventually { raw.subscriptions == 1 }

        consumed.cancel()
        await eventually({ raw.rawStreamEnded }, "cancelling the map cancels the raw stream")
    }

    // MARK: - S-3207 the recorder end to end

    func testS3207TheRecorderCarriesTheTrackedTotalAndSettlesIt() async throws {
        let harness = Harness()
        let raw = ScriptedRawFixSource()
        let base = t0
        let source = TrackedLocationSensorSource(raw: raw, clock: { base })
        let engine = await harness.runningEngine()
        let live = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [[
                "sessionExerciseId": "sx-1",
                "exerciseId": "ex-1",
                "name": "sx-1",
                "capabilities": ["time", "distance"],
            ]]
        )
        let recorder = WatchSensorRecorder(
            engine: engine,
            source: source,
            clock: harness.clock.call
        )

        await recorder.start(live)
        XCTAssertTrue(recorder.isMeasuringDistance)
        await eventually { raw.subscriptions == 1 }

        raw.fix(fix(52.0000, 5.0, accuracy: 5, at: 0))
        harness.clock.advance(30)
        raw.fix(fix(52.0010, 5.0, accuracy: 5, at: 30))
        await eventually { (recorder.readings.distanceMeters ?? 0) > 100 }
        XCTAssertEqual(
            try XCTUnwrap(recorder.readings.distanceMeters),
            111.195,
            accuracy: 0.01
        )

        harness.clock.advance(30)
        raw.fix(fix(52.0020, 5.0, accuracy: 5, at: 60))
        await eventually { (recorder.readings.distanceMeters ?? 0) > 200 }
        XCTAssertEqual(
            try XCTUnwrap(recorder.readings.distanceMeters),
            222.390,
            accuracy: 0.01
        )
        XCTAssertTrue(recorder.isMeasuringDistance)

        harness.clock.advance(30)
        await recorder.stop()
        XCTAssertFalse(recorder.isMeasuringDistance)

        let settled = engine.sensorSamples.filter { $0.kind == WatchSensorKind.distance }
        XCTAssertEqual(settled.count, 1, "the settle writes one distance row")
        XCTAssertEqual(try XCTUnwrap(settled.first).value, 222.390, accuracy: 0.01)
    }

    func testS3207DeniedRawPermissionSkipsLocationAndLoggingCarriesOn() async throws {
        let harness = Harness()
        let raw = ScriptedRawFixSource(grant: .denied)
        let base = t0
        let source = TrackedLocationSensorSource(raw: raw, clock: { base })
        let engine = await harness.runningEngine()
        let live = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [[
                "sessionExerciseId": "sx-1",
                "exerciseId": "ex-1",
                "name": "sx-1",
                "capabilities": ["time", "distance"],
            ]]
        )
        let recorder = WatchSensorRecorder(
            engine: engine,
            source: source,
            clock: harness.clock.call
        )

        await recorder.start(live)
        raw.fix(fix(52.0000, 5.0, accuracy: 5, at: 0))

        XCTAssertFalse(recorder.isMeasuringDistance)
        XCTAssertEqual(raw.subscriptions, 0, "a denied radio is never subscribed to")
        XCTAssertNil(recorder.readings.distanceMeters)
        XCTAssertTrue(
            engine.sensorSamples.filter { $0.kind == WatchSensorKind.gps }.isEmpty
        )

        let state = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )
        await state.startWork()
        harness.clock.advance(1200)
        let logged = try await state.log()

        XCTAssertNil(
            logged.payload["distanceMeters"],
            "nothing was measured, so the observation carries no distance"
        )
        XCTAssertEqual(engine.observations.count, 1, "denial is not failure")
    }

    // MARK: - S-3303 a cached fix never becomes the origin

    func testS3303ACachedFixNeverBecomesTheOrigin() async throws {
        let raw = ScriptedRawFixSource()
        let base = t0
        let adapter = WatchTrackedLocation(source: raw, clock: { base })

        var mapped = adapter.fixes().makeAsyncIterator()
        await eventually { raw.subscriptions == 1 }
        // The platform's cached position, a minute before the call started: 0.0050°
        // from the first live fix, i.e. 555.975 m over 60 s (9.27 m/s, under the
        // jump gate) — it would be the origin without the freshness gate.
        raw.fix(fix(52.0050, 5.0, accuracy: 5, at: -60))
        raw.fix(fix(52.0000, 5.0, accuracy: 5, at: 0))
        raw.fix(fix(52.0010, 5.0, accuracy: 5, at: 30))
        raw.fix(fix(52.0020, 5.0, accuracy: 5, at: 60))
        raw.close()

        let cachedMapped = await mapped.next()
        let first = try XCTUnwrap(
            cachedMapped,
            "the cached fix is dropped, so the live origin yields nothing"
        )
        XCTAssertEqual(first.distanceMeters, 111.195, accuracy: 0.01)
        let secondMapped = await mapped.next()
        let second = try XCTUnwrap(secondMapped)
        XCTAssertEqual(second.distanceMeters, 222.390, accuracy: 0.01)
        let extra = await mapped.next()
        XCTAssertNil(extra, "and the dropped fix never appears as a value of its own")
    }

    // MARK: - S-3304 the gate boundary is inclusive

    func testS3304TheGateBoundaryIsInclusive() async throws {
        // A fix exactly at the limit is kept: it becomes the origin, so the next
        // fix measures from it.
        do {
            let raw = ScriptedRawFixSource()
            let base = t0
            let adapter = WatchTrackedLocation(source: raw, clock: { base })

            var mapped = adapter.fixes().makeAsyncIterator()
            await eventually { raw.subscriptions == 1 }
            raw.fix(fix(52.0000, 5.0, accuracy: 5, at: -10))
            raw.fix(fix(52.0010, 5.0, accuracy: 5, at: 0))
            raw.close()

            let keptMapped = await mapped.next()
            let kept = try XCTUnwrap(
                keptMapped,
                "a fix exactly at the limit is kept and becomes the origin"
            )
            XCTAssertEqual(kept.distanceMeters, 111.195, accuracy: 0.01)
        }

        // A fix older than the limit by any amount is dropped.
        do {
            let raw = ScriptedRawFixSource()
            let base = t0
            let adapter = WatchTrackedLocation(source: raw, clock: { base })

            var mapped = adapter.fixes().makeAsyncIterator()
            await eventually { raw.subscriptions == 1 }
            raw.fix(fix(52.0050, 5.0, accuracy: 5, at: -10.001))
            raw.fix(fix(52.0000, 5.0, accuracy: 5, at: 0))
            raw.fix(fix(52.0010, 5.0, accuracy: 5, at: 30))
            raw.close()

            let firstMapped = await mapped.next()
            let first = try XCTUnwrap(
                firstMapped,
                "the dropped fix is not the origin, so the live fix at t0 is"
            )
            XCTAssertEqual(first.distanceMeters, 111.195, accuracy: 0.01)
        }
    }

    // MARK: - S-3306 the clock is read once per fixes() call

    func testS3306TheClockIsReadOncePerCall() async throws {
        let raw = ScriptedRawFixSource()
        let clock = TestClock(t0)
        let adapter = WatchTrackedLocation(source: raw, clock: clock.call)

        var first = adapter.fixes().makeAsyncIterator()
        await eventually { raw.subscriptions == 1 }
        raw.fix(fix(52.0000, 5.0, accuracy: 5, at: 0))
        raw.fix(fix(52.0010, 5.0, accuracy: 5, at: 30))

        let firstMapped = await first.next()
        let firstValue = try XCTUnwrap(
            firstMapped,
            "t0 + 100 s is fresh for the call that started at t0"
        )
        XCTAssertEqual(firstValue.distanceMeters, 111.195, accuracy: 0.01)

        raw.fix(fix(52.0050, 5.0, accuracy: 5, at: 100))
        raw.close()

        // An hour later the same fix is long stale: the second call reads the
        // clock again, so its gate is its own start, not the first call's.
        clock.advance(3600)
        var second = adapter.fixes().makeAsyncIterator()
        await eventually { raw.subscriptions == 2 }
        // First a fix stamped t0 + 100 s — fresh for the first call, stale for
        // this one. It is what tells the two clocks apart, and here is the
        // arithmetic both ways:
        //   per-call clock (this call's start = t0 + 3600): the gate's oldest
        //     instant is t0 + 3590, so the t0 + 100 fix is dropped and the
        //     t0 + 3610 fix (52.0100) becomes the origin; the t0 + 3640 fix
        //     (52.0110) then measures 0.0010° = 111.195 m — the value asserted
        //     below.
        //   clock read once at init (start = t0): the t0 + 100 fix (52.0050) is
        //     kept and becomes the origin; the t0 + 3610 fix (52.0100) then
        //     measures 0.0050° = 555.975 m over 3510 s = 0.16 m/s, under the
        //     jump gate, so it is accepted and the first yield would read
        //     555.975 — red against the 111.195 below.
        raw.fix(fix(52.0050, 5.0, accuracy: 5, at: 100))
        raw.fix(fix(52.0100, 5.0, accuracy: 5, at: 3610))
        raw.fix(fix(52.0110, 5.0, accuracy: 5, at: 3640))
        raw.close()

        let secondMapped = await second.next()
        let secondValue = try XCTUnwrap(
            secondMapped,
            "the fix fresh for the first call is stale 3600 s later"
        )
        XCTAssertEqual(secondValue.distanceMeters, 111.195, accuracy: 0.01)
    }

    // MARK: - S-3307 a late-arriving fix stamped after the start is kept

    func testS3307ALateArrivingFixStampedAfterTheStartIsKept() async throws {
        let raw = ScriptedRawFixSource()
        let clock = TestClock(t0)
        let adapter = WatchTrackedLocation(source: raw, clock: clock.call)

        var first = adapter.fixes().makeAsyncIterator()
        await eventually { raw.subscriptions == 1 }

        // The gate's clock was read when the task started (subscriptions == 1
        // means `rawFixes()` was already entered, so `oldest` is fixed at
        // t0 - 10). Advancing the clock now separates the two variants:
        //   per-call gate (oldest = t0 - 10): the origin stamped t0 + 5 and the
        //     fix stamped t0 + 30 are both fresh; the origin yields nothing and
        //     the t0 + 30 fix measures 0.0010° = 111.195 m — asserted below.
        //   per-fix gate (clock read inside the loop, oldest = t0 + 40 for
        //     every fix): both fixes are stale, nothing is ever yielded, and
        //     `next()` after the close returns nil — red against the unwrap.
        clock.advance(50)
        raw.fix(fix(52.0000, 5.0, accuracy: 5, at: 5))
        raw.fix(fix(52.0010, 5.0, accuracy: 5, at: 30))
        raw.close()

        let firstMapped = await first.next()
        let firstValue = try XCTUnwrap(
            firstMapped,
            "a fix stamped after the call's start is fresh even when it arrives late"
        )
        XCTAssertEqual(firstValue.distanceMeters, 111.195, accuracy: 0.01)
        let extra = await first.next()
        XCTAssertNil(extra, "the origin yields nothing of its own")
    }
}
