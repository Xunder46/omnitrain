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
//  Plan 168 (D-16803): the exercises' agreed Health kind beats the modality.
//
//    S-16804 a named walk beats the Cardio modality       → `testS16804...`
//    S-16805 named kinds: majority, ties earliest         → `testS16805...`
//    S-16806 unnamed exercises keep the modality          → `testS16806...`
//    S-16807 a Free workout keeps its exercise answer     → `testS16807...`
//    S-16808 a later named kind never retypes the open one → `testS16808...`
//
//  Nothing here touches the platform's health service: the stores are the seam
//  the workout is asserted through, so the file runs on macOS beside
//  `swift test`.
//

import XCTest

@testable import WatchSessionEngine

final class WatchWorkoutTypeFromExercisesTests: XCTestCase {

    // MARK: - Fixtures

    /// One protocol slot carrying `capabilities`, and the Health kind the phone
    /// named for it when the fixture needs one.
    private func slot(
        _ id: String,
        _ capabilities: [String],
        healthActivity: String? = nil
    ) -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
        if let healthActivity { slot["healthActivity"] = healthActivity }
        return slot
    }

    private func lift(_ id: String = "sx-lift") -> [String: Any] {
        slot(id, ["reps", "sets", "load"])
    }

    private func run(_ id: String = "sx-run") -> [String: Any] {
        slot(id, ["time", "distance"])
    }

    /// A distance slot whose exercise the phone named `walking` — the Brisk
    /// Walk fixture (seed `exercise-brisk-walk`, discipline walking).
    private func walk(_ id: String = "sx-walk") -> [String: Any] {
        slot(id, ["time", "distance"], healthActivity: "walking")
    }

    /// A distance slot whose exercise the phone named `running`.
    private func namedRun(_ id: String = "sx-named-run") -> [String: Any] {
        slot(id, ["time", "distance"], healthActivity: "running")
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

    // MARK: - S-16804 a named walking kind beats the Cardio modality

    func testS16804AWalkNamedByTheExerciseBeatsTheCardioModality() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [walk()]
        )

        XCTAssertEqual(
            WatchActivityTypes.forSession(session)?.watchOs,
            "walking",
            "S-16804 the exercise's named kind beats the modality (D-16803)"
        )

        let store = ScriptedPlatformStore()
        let (coordinator, _) = makeCoordinator(store)
        await coordinator.refresh(session)

        XCTAssertEqual(store.begun, ["walking"], "S-16804 and Health is opened as Outdoor Walk")
    }

    // MARK: - S-16805 named kinds disagree: majority, ties earliest

    func testS16805TheNamedKindsMajorityAndItsTie() async throws {
        // A majority of the named kinds.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: "cardio_endurance",
                exercises: [walk(), namedRun(), namedRun()]
            )

            XCTAssertEqual(
                WatchActivityTypes.forSession(session)?.watchOs,
                "running",
                "S-16805 two named runs outnumber one named walk"
            )
        }

        // A tie between named kinds.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: "cardio_endurance",
                exercises: [walk(), namedRun()]
            )

            XCTAssertEqual(
                WatchActivityTypes.forSession(session)?.watchOs,
                "walking",
                "S-16805 a tie goes to the earliest named exercise"
            )
        }
    }

    // MARK: - S-16806 unnamed exercises keep the modality

    func testS16806UnnamedExercisesKeepTheModality() async throws {
        // A Cardio routine whose only slot names no Health kind.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: "cardio_endurance",
                exercises: [lift()]
            )

            XCTAssertEqual(
                WatchActivityTypes.forSession(session)?.watchOs,
                "running",
                "S-16806 an unnamed slot leaves the modality's own type"
            )
        }

        // The same slot under another modality.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: "sports",
                exercises: [lift()]
            )

            XCTAssertEqual(
                WatchActivityTypes.forSession(session)?.watchOs,
                "other",
                "S-16806 sports still answers its generic type"
            )
        }
    }

    // MARK: - S-16807 a Free workout keeps its exercise answer

    func testS16807AFreeWorkoutKeepsItsExerciseAnswer() async throws {
        // A Free workout whose first exercise names walking.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: nil,
                exercises: [walk()]
            )

            XCTAssertEqual(
                WatchActivityTypes.forSession(session)?.watchOs,
                "walking",
                "S-16807 with no modality the named exercise answers"
            )
        }

        // A Free workout with a distance slot that names nothing: the
        // capability default, unchanged.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: nil,
                exercises: [run()]
            )

            XCTAssertEqual(
                WatchActivityTypes.forSession(session)?.watchOs,
                "running",
                "S-16807 a capability-only distance slot stays running"
            )
        }
    }

    // MARK: - S-16808 a later named kind never retypes the open workout

    func testS16808ALaterNamedKindNeverRetypesTheOpenWorkout() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil)

        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.refresh(try XCTUnwrap(engine.session))
        _ = await engine.insertExercise(walk(), moveTo: true)
        await coordinator.refresh(try XCTUnwrap(engine.session))
        XCTAssertEqual(store.begun, ["walking"], "S-16808 the first known answer opens it as a walk")

        _ = await engine.insertExercise(namedRun(), moveTo: true)
        await coordinator.refresh(try XCTUnwrap(engine.session))

        XCTAssertEqual(store.begun.count, 1, "S-16808 the open workout is not begun again")
        XCTAssertEqual(
            platform.running?.watchOs,
            "walking",
            "S-16808 HealthKit cannot retype an open session, so the type stays the first answer"
        )
    }
}
