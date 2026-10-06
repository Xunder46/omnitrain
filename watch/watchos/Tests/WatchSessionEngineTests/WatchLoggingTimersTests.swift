//
//  WatchLoggingTimersTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`
//  — timestamp-derived countdowns and their haptics, proved the same way the
//  Flutter client proves them in `test/watch_logging_timers_test.dart`.
//
//  A haptic is owed when a countdown reaches zero, and the instant it is owed
//  at comes from the timer's own timestamps. Nothing here counts down: every
//  case below moves a clock, never a ticker, which is what makes the screen-off
//  case the same case as the on-screen one.
//

import XCTest

@testable import WatchSessionEngine

final class WatchLoggingTimersTests: XCTestCase {

    private func surface(
        _ harness: Harness,
        engine: WatchSessionEngine,
        restSeconds: Int = WatchLoggingDefaults.restSeconds
    ) -> WatchLoggingState {
        WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            restSeconds: restSeconds
        )
    }

    private func slot(_ id: String, capabilities: [String]) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
    }

    // MARK: - S-005 rest timer with screen-off haptic

    func testS005LoggingASetStartsARestCountdownOfTheSurfaceLength() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let surface = surface(harness, engine: engine)

        try await surface.log()

        let rest = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(rest.startedAt, harness.clock.now)
        XCTAssertEqual(rest.plannedDurationMs, 90_000)
    }

    func testS005TheHapticIsOwedExactlyAtTheInstantTheCountdownEnds() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await surface(harness, engine: engine).log()

        let haptics = WatchTimerHaptics(engine)
        let deadline = harness.clock.now.addingTimeInterval(90)

        XCTAssertTrue(
            haptics.poll(now: deadline.addingTimeInterval(-1)).isEmpty,
            "a second early is early"
        )
        XCTAssertEqual(
            haptics.poll(now: deadline),
            [WatchTimerMilestone(kind: WatchTimerKind.rest, at: deadline)]
        )
        XCTAssertTrue(
            haptics.poll(now: deadline.addingTimeInterval(600)).isEmpty,
            "a countdown the user has been told about is told once"
        )
    }

    func testS005AScreenOffGapFiresTheHapticAtTheMomentItWasDue() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await surface(harness, engine: engine).log()

        let haptics = WatchTimerHaptics(engine)
        let startedAt = harness.clock.now

        // Ten minutes pass with the screen off: no poll happened in between.
        harness.clock.advance(600)

        XCTAssertEqual(
            haptics.poll(now: harness.clock.now),
            [
                WatchTimerMilestone(
                    kind: WatchTimerKind.rest,
                    at: startedAt.addingTimeInterval(90)
                )
            ]
        )
    }

    func testS005APauseMovesTheDeadlineByThePause() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await surface(harness, engine: engine).log()

        let haptics = WatchTimerHaptics(engine)
        let startedAt = harness.clock.now

        harness.clock.advance(30)
        _ = await engine.pauseTimer(kind: WatchTimerKind.rest)
        harness.clock.advance(30)
        _ = await engine.resumeTimer(kind: WatchTimerKind.rest)

        XCTAssertTrue(
            haptics.poll(now: startedAt.addingTimeInterval(90)).isEmpty,
            "the paused half-minute has not been counted yet"
        )
        XCTAssertEqual(
            haptics.poll(now: startedAt.addingTimeInterval(120)),
            [
                WatchTimerMilestone(
                    kind: WatchTimerKind.rest,
                    at: startedAt.addingTimeInterval(120)
                )
            ]
        )
    }

    func testS005ARestTimerIsAWallClockAfterAKillNotACounter() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await surface(harness, engine: engine).log()

        let deadline = harness.clock.now.addingTimeInterval(90)

        // A relaunch: a brand-new engine over the same storage, nothing handed
        // across in memory, and the same clock the watch would be holding.
        let relaunched = await harness.runningEngine(harness.newEngine())

        XCTAssertEqual(
            WatchTimerHaptics(relaunched).poll(now: deadline),
            [WatchTimerMilestone(kind: WatchTimerKind.rest, at: deadline)],
            "the countdown reads its own timestamp, not a counter"
        )
    }

    // MARK: - S-003 round countdown

    func testS003LoggingARoundStartsTheNextRoundCountdown() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-round", capabilities: ["time", "rounds"])]
        )
        let surface = surface(harness, engine: engine)

        try await surface.log()

        let round = try XCTUnwrap(engine.timerFor(WatchTimerKind.round))
        XCTAssertEqual(round.plannedDurationMs, 180_000)
    }

    func testS003TheRoundHapticFiresAtTheInstantTheRoundEnds() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-round", capabilities: ["time", "rounds"])]
        )
        try await surface(harness, engine: engine).log()

        let haptics = WatchTimerHaptics(engine)
        let roundEnd = harness.clock.now.addingTimeInterval(180)

        XCTAssertTrue(haptics.poll(now: roundEnd.addingTimeInterval(-1)).isEmpty)
        XCTAssertEqual(
            haptics.poll(now: roundEnd),
            [WatchTimerMilestone(kind: WatchTimerKind.round, at: roundEnd)]
        )
    }

    func testS003ANewRoundIsANewCountdownSoItFiresAgain() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-round", capabilities: ["time", "rounds"])]
        )
        let surface = surface(harness, engine: engine)

        try await surface.log()
        let haptics = WatchTimerHaptics(engine)

        harness.clock.advance(180)
        XCTAssertEqual(haptics.poll(now: harness.clock.now).count, 1)

        try await surface.log()
        harness.clock.advance(180)
        XCTAssertEqual(
            haptics.poll(now: harness.clock.now).count,
            1,
            "round two is owed its own haptic"
        )
    }

    // MARK: - The shared contract (S-007)

    /// The values both clients are held to. The Flutter suite reads this same
    /// file, so a change to the table on either platform fails on both.
    func testSteppingMatchesTheSharedContract() throws {
        let contract = try Fixtures.loggingContract()
        let stepping = try doubles(contract["stepping"])
        let conversion = try doubles(contract["unitConversion"])

        XCTAssertEqual(
            WatchMetricStepping.kilogramsPerDetent,
            try XCTUnwrap(stepping["kilogramsPerDetent"])
        )
        XCTAssertEqual(
            WatchMetricStepping.poundsPerDetent,
            try XCTUnwrap(stepping["poundsPerDetent"])
        )
        XCTAssertEqual(
            WatchMetricStepping.secondsPerDetent,
            try XCTUnwrap(stepping["secondsPerDetent"])
        )
        XCTAssertEqual(
            WatchMetricStepping.tenthsOfDistanceUnitPerDetent,
            try XCTUnwrap(stepping["tenthsOfDistanceUnitPerDetent"])
        )
        XCTAssertEqual(
            WatchMetricStepping.countPerDetent,
            try XCTUnwrap(stepping["countPerDetent"])
        )

        XCTAssertEqual(
            WatchMetricKey.all,
            try XCTUnwrap(contract["metricKeys"] as? [String])
        )

        // The conversion constants, pinned by what the mirrors compute with them.
        let pound = try XCTUnwrap(conversion["kilogramsPerPound"])
        let mile = try XCTUnwrap(conversion["kilometresPerMile"])
        XCTAssertEqual(
            WatchMetricStepping.toKilograms(1, unit: "lbs"),
            1 / pound,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            WatchMetricStepping.fromKilograms(1, unit: "lbs"),
            pound,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            WatchMetricStepping.metresPerUnit("miles"),
            1000 / mile,
            accuracy: 1e-6
        )
    }

    /// JSON numbers arrive as `Int` or `Double` depending on how they were
    /// written, so the contract's numbers are read through one door.
    private func doubles(_ object: Any?) throws -> [String: Double] {
        let raw = try XCTUnwrap(object as? [String: Any])
        return try raw.mapValues { try XCTUnwrap($0 as? NSNumber).doubleValue }
    }

    // MARK: - The surface the user turns (S-001, S-005)

    /// The model is main-actor isolated, as a view model is: these two drive it
    /// from the main actor, exactly as the view does.

    @MainActor
    func testCrownTurnsAccumulateIntoWholeDetents() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let model = WatchLoggingModel(
            state: WatchLoggingState(engine: engine, clock: harness.clock.call),
            haptics: RecordingHaptics()
        )
        var reps = model.state.fields.first { $0.metricKey == WatchMetricKey.reps }!.value

        // A turn smaller than a detent moves nothing; the next one tops it up.
        model.turn(WatchMetricKey.reps, to: WatchLoggingModel.pointsPerDetent / 2)
        XCTAssertEqual(
            model.state.fields.first { $0.metricKey == WatchMetricKey.reps }!.value,
            reps
        )

        model.turn(WatchMetricKey.reps, to: WatchLoggingModel.pointsPerDetent)
        reps = model.state.fields.first { $0.metricKey == WatchMetricKey.reps }!.value
        XCTAssertEqual(reps, 11)
    }

    @MainActor
    func testTheModelFiresTheHapticTheEngineOwed() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let haptics = RecordingHaptics()
        let model = WatchLoggingModel(
            state: WatchLoggingState(engine: engine, clock: harness.clock.call),
            haptics: haptics
        )

        await model.log()
        let deadline = harness.clock.now.addingTimeInterval(90)
        XCTAssertNotNil(model.countdown, "a rest countdown is running after a set")

        // The screen was off for ten minutes: the first poll after it sees the
        // countdown already over, and fires once at the instant it was due.
        harness.clock.advance(600)
        model.poll()
        model.poll()

        XCTAssertEqual(
            haptics.milestones,
            [WatchTimerMilestone(kind: WatchTimerKind.rest, at: deadline)]
        )
        XCTAssertEqual(model.countdown, 0, "the countdown is over")
    }

    // MARK: - Derivation

    func testATimerWithNoPlannedDurationNeverCountsDown() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-row")])
        _ = try await engine.startTimer(WatchTimerKind.elapsed)

        let haptics = WatchTimerHaptics(engine)
        harness.clock.advance(10_800)
        XCTAssertTrue(haptics.poll(now: harness.clock.now).isEmpty)
    }

    func testACountdownTheUserEndedEarlyNeverFires() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = try await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 90_000)

        let haptics = WatchTimerHaptics(engine)
        harness.clock.advance(60)
        _ = await engine.stopTimer(kind: WatchTimerKind.rest)

        harness.clock.advance(300)
        XCTAssertTrue(haptics.poll(now: harness.clock.now).isEmpty)
    }

    func testACountdownTheUserEndedLateDidCompleteAndFiresOnce() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = try await engine.startTimer(WatchTimerKind.round, plannedDurationMs: 60_000)

        let haptics = WatchTimerHaptics(engine)
        harness.clock.advance(90)
        _ = await engine.stopTimer(kind: WatchTimerKind.round)

        XCTAssertEqual(
            haptics.poll(now: harness.clock.now),
            [
                WatchTimerMilestone(
                    kind: WatchTimerKind.round,
                    at: harness.clock.now.addingTimeInterval(-30)
                )
            ]
        )
        XCTAssertTrue(haptics.poll(now: harness.clock.now.addingTimeInterval(60)).isEmpty)
    }

    // MARK: - Metric stepping (S-007)

    func testS007CountsStepByOneAndLoadStepsByThePreferredIncrement() {
        XCTAssertEqual(WatchMetricStepping.step(for: WatchMetricKey.reps), 1)
        XCTAssertEqual(WatchMetricStepping.step(for: WatchMetricKey.rounds), 1)
        XCTAssertEqual(WatchMetricStepping.step(for: WatchMetricKey.weight), 2.5)
        XCTAssertEqual(WatchMetricStepping.step(for: WatchMetricKey.extraWeight), 2.5)
    }

    func testS007APoundPreferenceStepsInPoundsStoredInKilograms() {
        let pounds = WatchUnitPreferences(weightUnit: "lbs")
        let step = WatchMetricStepping.step(for: WatchMetricKey.weight, units: pounds)

        XCTAssertEqual(step, WatchMetricStepping.toKilograms(5, unit: "lbs"), accuracy: 0.0001)
        XCTAssertEqual(
            WatchMetricStepping.fromKilograms(80 + step, unit: "lbs")
                - WatchMetricStepping.fromKilograms(80, unit: "lbs"),
            5,
            accuracy: 0.001,
            "one detent is five pounds on the wrist, whatever it is in kg"
        )
    }

    func testS007DurationStepsByFiveSecondsAndDistanceByItsOwnIncrement() {
        XCTAssertEqual(WatchMetricStepping.step(for: WatchMetricKey.duration), 5)
        XCTAssertEqual(WatchMetricStepping.step(for: WatchMetricKey.roundDuration), 5)
        XCTAssertEqual(WatchMetricStepping.step(for: WatchMetricKey.distance), 100)

        let miles = WatchUnitPreferences(distanceUnit: "miles")
        XCTAssertEqual(
            WatchMetricStepping.step(for: WatchMetricKey.distance, units: miles),
            0.1 * WatchMetricStepping.metresPerUnit("miles"),
            accuracy: 0.001
        )
    }

    func testS007AnUnknownMetricDoesNotMove() {
        XCTAssertEqual(WatchMetricStepping.step(for: "metric-nonsense"), 0)
        XCTAssertEqual(
            WatchMetricStepping.adjust(80, metricKey: "metric-nonsense", detents: 3),
            80
        )
    }

    func testS007TurningForwardAndBackIsSymmetricAndDriftFree() {
        var value = 80.0
        for _ in 0..<3 {
            value = WatchMetricStepping.adjust(value, metricKey: WatchMetricKey.weight, detents: 1)
        }
        XCTAssertEqual(value, 87.5)

        for _ in 0..<3 {
            value = WatchMetricStepping.adjust(value, metricKey: WatchMetricKey.weight, detents: -1)
        }
        XCTAssertEqual(value, 80)
    }

    func testS007FractionalDetentsMoveProportionally() {
        XCTAssertEqual(
            WatchMetricStepping.adjust(10, metricKey: WatchMetricKey.reps, detents: 2.5),
            12.5
        )
    }

    func testS007ACountNeverFallsBelowOne() {
        XCTAssertEqual(
            WatchMetricStepping.adjust(1, metricKey: WatchMetricKey.reps, detents: -5),
            1
        )
        XCTAssertEqual(
            WatchMetricStepping.adjust(2, metricKey: WatchMetricKey.rounds, detents: -9),
            1
        )
    }

    func testS007DurationAndDistanceNeverGoNegative() {
        XCTAssertEqual(
            WatchMetricStepping.adjust(0, metricKey: WatchMetricKey.duration, detents: -1),
            0
        )
        XCTAssertEqual(
            WatchMetricStepping.adjust(0, metricKey: WatchMetricKey.distance, detents: -1),
            0
        )
    }

    func testS061AnAssistedLoadStopsAtTheWireFloor() {
        let kg = WatchUnitPreferences()
        let lbs = WatchUnitPreferences(weightUnit: "lbs")

        // The floor itself: the same canonical kilograms in both units.
        XCTAssertEqual(WatchMetricStepping.clamp(-240, metricKey: WatchMetricKey.weight), -200)
        XCTAssertEqual(WatchMetricStepping.clamp(-200.1, metricKey: WatchMetricKey.weight), -200)
        XCTAssertEqual(WatchMetricStepping.clamp(-200, metricKey: WatchMetricKey.weight), -200)

        for units in [kg, lbs] {
            let step = WatchMetricStepping.step(for: WatchMetricKey.weight, units: units)
            func turn(_ from: Double, _ detents: Double) -> Double {
                WatchMetricStepping.adjust(from, metricKey: WatchMetricKey.weight, detents: detents, units: units)
            }

            // A normal step below zero still works.
            XCTAssertEqual(turn(-100, -1), -100 - step, accuracy: 0.001)
            // The dial crosses zero into an assist.
            XCTAssertEqual(turn(0, -1), -step, accuracy: 0.001)
            // A positive load dialled down lands on zero.
            XCTAssertEqual(turn(step, -1), 0)
        }

        // The last step onto the floor lands exactly on it, and stays there.
        XCTAssertEqual(
            WatchMetricStepping.adjust(-197.5, metricKey: WatchMetricKey.weight, detents: -1),
            -200
        )
        XCTAssertEqual(
            WatchMetricStepping.adjust(-200, metricKey: WatchMetricKey.weight, detents: -1),
            -200
        )
    }

    func testS061ExtraLoadStaysSignedAndUnbounded() {
        XCTAssertEqual(
            WatchMetricStepping.adjust(0, metricKey: WatchMetricKey.extraWeight, detents: -4),
            -10,
            "extra load is signed and unbounded; extraLoadKg is not the carrier for a set's assist (D-58)"
        )
    }

    /// The dial's floor must be the schema's floor, read from the repository so
    /// the two cannot drift (D-58/D-59): `$defs.entry.properties.loadKg.minimum`,
    /// the same site the phone's `WireLimits` test reads.
    func testS059TheWireFloorMatchesTheSchema() throws {
        let envelope = try Fixtures.json("schemas/envelope.schema.json")
        let defs = try XCTUnwrap(envelope["$defs"] as? [String: Any])
        let entry = try XCTUnwrap(defs["entry"] as? [String: Any])
        let properties = try XCTUnwrap(entry["properties"] as? [String: Any])
        let loadKg = try XCTUnwrap(properties["loadKg"] as? [String: Any])
        let minimum = try XCTUnwrap(loadKg["minimum"] as? NSNumber).doubleValue

        XCTAssertEqual(
            minimum,
            WatchMetricStepping.minimumLoadKg,
            "the dial's floor is the wire's own floor"
        )
        XCTAssertNotEqual(minimum, 0, "the floor is no longer zero")
    }
}
