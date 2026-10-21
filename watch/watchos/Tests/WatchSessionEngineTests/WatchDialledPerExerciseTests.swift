//
//  WatchDialledPerExerciseTests.swift
//  WatchSessionEngineTests
//
//  S-6410 to S-6413 and S-6415 of
//  `docs/plans/2026-10-20-46a-wrist-logging-basics-plan/2026-10-20-46a-wrist-logging-basics-plan.md`
//  — each exercise keeps its own dialled numbers (D-4): a value dialled on the
//  bench is not carried to the squat when the menu moves the session, and a Log
//  clears only the exercise it confirms.
//
//  S-6414 (the period-length rule, S3406) is the existing
//  `testS3406ARunningPeriodHasNoLengthRowAndKeepsTheDialledLength` in
//  `WatchTimedWorkTests.swift`, run unchanged.
//

import XCTest

@testable import WatchSessionEngine

final class WatchDialledPerExerciseTests: XCTestCase {

    private func slot(_ id: String, capabilities: [String]) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
    }

    private func state(_ engine: WatchSessionEngine, _ harness: Harness) -> WatchLoggingState {
        WatchLoggingState(engine: engine, clock: harness.clock.call)
    }

    private func value(_ state: WatchLoggingState, _ metricKey: String) -> Double? {
        state.fields.first { $0.metricKey == metricKey }?.value
    }

    /// Two planned sets of the same shape, so each keeps its own numbers.
    private func ladders(_ engine: WatchSessionEngine) async -> WatchSessionRecord {
        await engine.createSession(
            modality: nil,
            exercises: [
                slot("sx-bench", capabilities: ["reps", "sets", "load"]),
                slot("sx-squat", capabilities: ["reps", "sets", "load"]),
            ]
        )
    }

    // MARK: - S-6410 a dialled value stays with its exercise

    func testS6410ADialledValueStaysWithItsExercise() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await ladders(engine)
        let surface = state(engine, harness)

        surface.adjust(WatchMetricKey.reps, detents: 4)
        XCTAssertEqual(value(surface, WatchMetricKey.reps), 14)

        await engine.selectExercise(slotId: "sx-squat")
        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            10,
            "the squat starts from its own reps, not the bench's"
        )

        await engine.selectExercise(slotId: "sx-bench")
        XCTAssertEqual(value(surface, WatchMetricKey.reps), 14, "the bench kept what was dialled")
    }

    // MARK: - S-6411 a log clears only the exercise it confirms

    func testS6411ALogClearsOnlyTheExerciseItConfirms() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await ladders(engine)
        let surface = state(engine, harness)

        surface.adjust(WatchMetricKey.reps, detents: 4)
        surface.adjust(WatchMetricKey.weight, detents: 2)

        await engine.selectExercise(slotId: "sx-squat")
        surface.adjust(WatchMetricKey.reps, detents: 1)
        surface.adjust(WatchMetricKey.weight, detents: 5)

        let logged = try await surface.log()
        XCTAssertEqual(logged.payload["reps"] as? Int, 11)
        XCTAssertEqual(logged.payload["loadKg"] as? Double, 12.5)
        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            11,
            "the squat is back to the set it just logged"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 12.5)

        await engine.selectExercise(slotId: "sx-bench")
        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            14,
            "the bench's dialled reps survived a log on another exercise"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 5)
    }

    // MARK: - S-6415 a log clears the exercise it logged, not the one in flight

    /// Bounded poll: never an unbounded wait on the store.
    private func spin(until condition: () -> Bool, limit: Int = 100_000) async -> Bool {
        var spins = 0
        while !condition() && spins < limit {
            await Task.yield()
            spins += 1
        }
        return condition()
    }

    func testS6415ALogClearsTheExerciseItLoggedNotTheOneInFlight() async throws {
        let store = SuspendingStore()
        let harness = Harness(store: store)
        let engine = await harness.runningEngine()
        _ = await ladders(engine)
        let surface = state(engine, harness)

        surface.adjust(WatchMetricKey.reps, detents: 4)
        XCTAssertEqual(value(surface, WatchMetricKey.reps), 14)

        store.arm()
        let logging = Task { try await surface.log() }

        let reached = await spin(until: { store.suspended })
        guard reached else {
            XCTFail("S-6415 the log's commit never reached the store")
            return
        }

        await engine.selectExercise(slotId: "sx-squat")
        surface.adjust(WatchMetricKey.reps, detents: 2)
        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            12,
            "S-6415 the squat was dialled while the bench's log was in flight"
        )

        store.resume()
        let logged = try await logging.value
        XCTAssertEqual(logged.payload["reps"] as? Int, 14, "S-6415 the bench's dial is what was logged")
        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            12,
            "S-6415 the log consumed the bench's dial, not the squat's"
        )
    }

    // MARK: - S-6412 a weight dialled on one exercise does not appear on another

    func testS6412AWeightDialledOnOneExerciseDoesNotAppearOnAnother() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await ladders(engine)
        let surface = state(engine, harness)

        surface.adjust(WatchMetricKey.weight, detents: 5)
        let step = try XCTUnwrap(surface.fields.first { $0.metricKey == WatchMetricKey.weight }?.step)
        XCTAssertEqual(step, 2.5)
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 12.5)

        await engine.selectExercise(slotId: "sx-squat")
        XCTAssertEqual(
            value(surface, WatchMetricKey.weight),
            0,
            "the squat shows its own starting weight, not the bench's 12.5"
        )

        await engine.selectExercise(slotId: "sx-bench")
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 12.5)
    }

    // MARK: - S-6413 a session with no exercise yet

    func testS6413AFreeStartBeforeAnyExerciseHasNoRowsAndDialsNothing() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [])
        let surface = state(engine, harness)

        XCTAssertTrue(surface.fields.isEmpty, "there is no exercise, so no row")

        surface.adjust(WatchMetricKey.reps, detents: 1)
        XCTAssertTrue(surface.fields.isEmpty, "a dial before the first pick changes nothing")
        XCTAssertNil(surface.exerciseName)
    }
}
