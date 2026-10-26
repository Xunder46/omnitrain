//
//  WatchWorkoutTypeFromExercisesTests.swift
//  WatchSessionEngineTests
//
//  Plan 58 P1: the Health workout type follows the session's exercises, not
//  just its modality — `docs/plans/2026-10-23-58-health-workout-type-and-calories-plan/2026-10-23-58-health-workout-type-and-calories-plan.md`.
//
//  Scenario mapping:
//    S-8801 a lift session registers as strength   → `testS8801...`
//    S-8802 a run session registers as running     → `testS8802...`
//    S-8803 a hold registers as flexibility        → `testS8803...`
//    S-8804 the majority decides                   → `testS8804...`
//    S-8805 a tie goes to the earliest exercise    → `testS8805...`
//    S-8806 a timed slot is generic, a majority is not → `testS8806...`
//    S-8807 a free workout waits for its first exercise → `testS8807...`
//    S-8808 a later exercise never changes the open workout → `testS8808...`
//    S-8809 a modality wins over the exercises     → `testS8809...`
//    S-8810 the lifecycle waits for a known type   → `testS8810...`
//    S-8811 empty is unknown; no capabilities is generic → `testS8811...`
//
//  Nothing here touches the platform's health service: the stores are the seam
//  the workout is asserted through, so the file runs on macOS beside
//  `swift test`.
//

import XCTest

@testable import WatchSessionEngine

final class WatchWorkoutTypeFromExercisesTests: XCTestCase {

    // MARK: - Fixtures

    /// One protocol slot carrying `capabilities`.
    private func slot(_ id: String, _ capabilities: [String]) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
    }

    private func lift(_ id: String = "sx-lift") -> [String: Any] {
        slot(id, ["reps", "sets", "load"])
    }

    private func run(_ id: String = "sx-run") -> [String: Any] {
        slot(id, ["time", "distance"])
    }

    private func hold(_ id: String = "sx-hold") -> [String: Any] {
        slot(id, ["hold", "time"])
    }

    /// A plank: `hold` and `sets` — the reason hold is tested first.
    private func plank(_ id: String = "sx-plank") -> [String: Any] {
        slot(id, ["hold", "sets"])
    }

    private func timed(_ id: String = "sx-timed") -> [String: Any] {
        slot(id, ["time"])
    }

    /// A coordinator over a scripted store, with the platform handed back so a
    /// test can read what the watch has open.
    private func makeCoordinator(
        _ store: ScriptedPlatformStore
    ) -> (coordinator: WatchWorkoutCoordinator, platform: WatchPlatformWorkout) {
        let platform = WatchPlatformWorkout(store: store)
        return (WatchWorkoutCoordinator(platform: platform), platform)
    }

    // MARK: - S-8801 a lift session registers as strength training

    func testS8801ALiftSessionRegistersAsStrengthTraining() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: nil, exercises: [lift()])

        let store = ScriptedPlatformStore()
        let (coordinator, _) = makeCoordinator(store)
        await coordinator.refresh(session)

        XCTAssertEqual(store.begun, ["traditionalStrengthTraining"])
    }

    // MARK: - S-8802 a run session registers as running, outdoors

    func testS8802ARunSessionRegistersAsRunningAndOutdoors() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: nil, exercises: [run()])

        let store = RecordingGpsOutdoorStore()
        await WatchPlatformWorkout(store: store).start(session)

        XCTAssertEqual(store.begins.map(\.activityType), ["running"])
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [true],
            "a distance exercise is outdoor work, as S-4807 already decided"
        )
    }

    // MARK: - S-8803 a hold registers as flexibility, and a plank stays one

    func testS8803AHoldRegistersAsFlexibilityAndAPlankStaysOne() async throws {
        // A hold.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(modality: nil, exercises: [hold()])

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["flexibility"])
        }

        // A plank: `hold` and `sets` — hold wins over sets.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(modality: nil, exercises: [plank()])

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["flexibility"], "hold is tested before sets")
        }
    }

    // MARK: - S-8804 the majority decides

    func testS8804TheMajorityDecides() async throws {
        // Two lifts and a run.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: nil,
                exercises: [lift(), lift(), run()]
            )

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["traditionalStrengthTraining"])
        }

        // Two runs and a lift: unlike the first exercise's type, so a
        // "first exercise decides" version fails here.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: nil,
                exercises: [run(), run(), lift()]
            )

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["running"])
        }
    }

    // MARK: - S-8805 a tie goes to the earliest exercise

    func testS8805ATieGoesToTheEarliestExercise() async throws {
        // Run first: the tie answers running.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: nil,
                exercises: [run(), lift()]
            )

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["running"])
        }

        // Lift first: the same tie answers strength.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: nil,
                exercises: [lift(), run()]
            )

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["traditionalStrengthTraining"])
        }
    }

    // MARK: - S-8806 a timed slot is generic, a majority is not

    func testS8806ATimedSlotIsGenericAndAMajorityIsNot() async throws {
        // One timed slot alone.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(modality: nil, exercises: [timed()])

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["other"])
        }

        // A timed slot among lifts: the lifts are the majority.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: nil,
                exercises: [timed(), lift(), lift()]
            )

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["traditionalStrengthTraining"])
        }
    }

    // MARK: - S-8807 a free workout waits for its first exercise

    func testS8807AFreeWorkoutWaitsForItsFirstExercise() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil)

        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.refresh(try XCTUnwrap(engine.session))
        XCTAssertEqual(store.begun, [], "an empty free workout waits")
        XCTAssertNil(platform.running, "and nothing is open yet")

        _ = await engine.insertExercise(lift(), moveTo: true)
        await coordinator.refresh(try XCTUnwrap(engine.session))
        XCTAssertEqual(store.begun, ["traditionalStrengthTraining"], "the first exercise opens it")
        XCTAssertEqual(platform.running?.watchOs, "traditionalStrengthTraining")

        await coordinator.refresh(try XCTUnwrap(engine.session))
        XCTAssertEqual(store.begun.count, 1, "a third refresh begins nothing more")
    }

    // MARK: - S-8808 a later exercise never changes the open workout

    func testS8808ALaterExerciseNeverChangesTheOpenWorkout() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil)

        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.refresh(try XCTUnwrap(engine.session))
        _ = await engine.insertExercise(lift(), moveTo: true)
        await coordinator.refresh(try XCTUnwrap(engine.session))
        XCTAssertEqual(store.begun, ["traditionalStrengthTraining"])

        _ = await engine.insertExercise(run(), moveTo: true)
        await coordinator.refresh(try XCTUnwrap(engine.session))

        XCTAssertEqual(store.begun.count, 1, "the open workout is not begun again")
        XCTAssertEqual(
            platform.running?.watchOs,
            "traditionalStrengthTraining",
            "and its type is what the first exercise decided"
        )
    }

    // MARK: - S-8809 a modality wins over the exercises

    func testS8809AModalityWinsOverTheExercises() async throws {
        // A modality with exercises: the modality's own type.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: "sports",
                exercises: [lift()]
            )

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["other"])
        }

        // A modality with no exercises: unchanged from testS1500.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(modality: "sports")

            let store = ScriptedPlatformStore()
            let (coordinator, _) = makeCoordinator(store)
            await coordinator.refresh(session)

            XCTAssertEqual(store.begun, ["other"])
        }
    }

    // MARK: - S-8810 the lifecycle waits for a known type

    func testS8810TheLifecycleWaitsForAKnownType() async throws {
        let emptyHarness = Harness()
        let emptyEngine = await emptyHarness.runningEngine()
        let empty = await emptyEngine.createSession(modality: nil)

        let liftHarness = Harness()
        let liftEngine = await liftHarness.runningEngine()
        let withLift = await liftEngine.createSession(modality: nil, exercises: [lift()])

        XCTAssertEqual(
            WatchWorkoutLifecycle.action(session: empty, running: nil),
            WatchWorkoutAction.none,
            "an active session whose type is not yet known waits"
        )
        XCTAssertEqual(
            WatchWorkoutLifecycle.action(session: withLift, running: nil),
            WatchWorkoutAction.start,
            "the first exercise makes the type known, and the workout opens"
        )
        XCTAssertEqual(
            WatchWorkoutLifecycle.action(session: empty, running: WatchActivityTypes.generic),
            WatchWorkoutAction.none,
            "already running is nothing to do, as before"
        )
        XCTAssertEqual(
            WatchWorkoutLifecycle.action(session: nil, running: WatchActivityTypes.generic),
            WatchWorkoutAction.end,
            "a workout nobody's session owns is an end, as before"
        )
    }

    // MARK: - S-8811 empty is unknown; no capabilities is generic

    func testS8811EmptyIsUnknownAndACapabilityLessSlotIsGeneric() {
        XCTAssertNil(
            WatchActivityTypes.forExercises([]),
            "no exercises: the type is not known yet"
        )
        XCTAssertEqual(
            WatchActivityTypes.forExercises([["sessionExerciseId": "sx-1", "name": "sx-1"]]),
            WatchActivityTypes.generic,
            "a slot with no `capabilities` key counts as the generic type"
        )
    }
}
