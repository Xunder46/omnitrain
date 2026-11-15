//
//  WatchHealthActivityTests.swift
//  WatchSessionEngineTests
//
//  Plan 75 Phase 1b: the Health kind the phone names for a distance exercise
//  rides to the wrist and picks the platform workout type — `docs/plans/
//  2026-10-24-75-health-type-per-exercise-plan/2026-10-24-75-health-type-per-exercise-plan.md`.
//
//  Scenario mapping:
//    S-10502 the type table, one test per value        → `testS10502...`
//    S-10503 hold still beats distance                 → `testS10503...`
//    S-10504 majority with mixed activities            → `testS10504...`
//    S-10505 the records round-trip                    → `testS10505...`
//    S-10506 the store's source carries the exact arms → `testS10506...`
//    S-10508 a routine effort round-trips and starts   → `testS10508...`
//              the right Health type
//
//  Plan 170 (D-17003): the Health kind is consulted before capability
//  inference, every contract kind resolves, and an unknown name falls through.
//
//    S-17004 the kind table resolves on the wrist     → `testS17004...`
//    S-17005 the kind beats hold and the modality     → `testS17005...`
//    S-17006 majority, ties and start-fixing          → `testS17006...`
//    S-17007 sports record as their sport             → `testS17007...`
//
//  Nothing here touches the platform's health service: the type table is
//  asserted through `WatchActivityTypes`, the records through their own
//  round-trips, and the app target's store through its source text.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchHealthActivityTests: XCTestCase {

    // MARK: - Fixtures

    /// One protocol slot carrying `capabilities` — the shape
    /// `WatchWorkoutTypeFromExercisesTests.slot(_:_:)` uses.
    private func slot(_ id: String, _ capabilities: [String]) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
    }

    private func ride(_ id: String = "sx-ride") -> [String: Any] {
        var exercise = slot(id, ["time", "distance"])
        exercise["healthActivity"] = "cycling"
        return exercise
    }

    private func bench(_ id: String = "sx-bench") -> [String: Any] {
        slot(id, ["reps", "sets", "load"])
    }

    /// The app target's store, from the repository root, with every comment
    /// line blanked out — the shape `WatchMenuTests.menuSource(_:)` uses, so a
    /// sentence of prose can neither satisfy a guard nor trip one.
    private func storeSource() throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/HealthKitWorkoutStore.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - S-10502 the type table, one test per value

    func testS10502CyclingNamesCyclingAndBiking() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["time", "distance"],
            healthActivity: "cycling"
        )
        XCTAssertEqual(type.watchOs, "cycling")
        XCTAssertEqual(type.wear, "exercise_type_biking")
    }

    func testS10502RowingNamesRowingAndRowing() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["time", "distance"],
            healthActivity: "rowing"
        )
        XCTAssertEqual(type.watchOs, "rowing")
        XCTAssertEqual(type.wear, "exercise_type_rowing")
    }

    func testS10502WalkingNamesWalkingAndWalking() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["time", "distance"],
            healthActivity: "walking"
        )
        XCTAssertEqual(type.watchOs, "walking")
        XCTAssertEqual(type.wear, "exercise_type_walking")
    }

    func testS10502HikingNamesHikingAndHiking() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["time", "distance"],
            healthActivity: "hiking"
        )
        XCTAssertEqual(type.watchOs, "hiking")
        XCTAssertEqual(type.wear, "exercise_type_hiking")
    }

    func testS10502RunningStaysRunning() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["time", "distance"],
            healthActivity: "running"
        )
        XCTAssertEqual(type.watchOs, "running")
        XCTAssertEqual(type.wear, "exercise_type_running")
    }

    func testS10502NilStaysRunning() {
        let type = WatchActivityTypes.forExercise(capabilities: ["time", "distance"])
        XCTAssertEqual(type.watchOs, "running")
        XCTAssertEqual(type.wear, "exercise_type_running")
    }

    func testS10502AnUnknownKindStaysRunning() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["time", "distance"],
            healthActivity: "unreal-kind"
        )
        XCTAssertEqual(type.watchOs, "running")
        XCTAssertEqual(type.wear, "exercise_type_running")
    }

    // MARK: - S-10503 the named kind beats hold and capability inference

    func testS10503ACyclingKindBeatsHold() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["hold", "time", "distance"],
            healthActivity: "cycling"
        )
        XCTAssertEqual(
            type.watchOs,
            "cycling",
            "the exercise's own kind is consulted first (D-17003)"
        )
        XCTAssertEqual(type.wear, "exercise_type_biking")
    }

    func testS10503RepsOnlyWithACyclingKindIsCycling() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["reps", "sets", "load"],
            healthActivity: "cycling"
        )
        XCTAssertEqual(
            type.watchOs,
            "cycling",
            "the kind no longer depends on the distance capability (D-17003)"
        )
    }

    // MARK: - S-10504 majority with mixed activities

    func testS10504AMajorityOfRidesIsCycling() {
        let exercises = [ride(), ride(), bench()]
        XCTAssertEqual(
            WatchActivityTypes.forExercises(exercises)?.watchOs,
            "cycling"
        )
    }

    func testS10504ATieGoesToTheEarliestExercise() {
        let exercises = [ride(), slot("sx-run", ["time", "distance"]), bench()]
        XCTAssertEqual(
            WatchActivityTypes.forExercises(exercises)?.watchOs,
            "cycling",
            "a tie answers the earliest exercise's type"
        )
    }

    func testS10504AFreeWorkoutWhoseFirstSlotIsARideOpensCycling() {
        let exercises = [ride(), bench()]
        XCTAssertEqual(
            WatchActivityTypes.forExercises(exercises)?.watchOs,
            "cycling"
        )
    }

    // MARK: - S-10505 the records round-trip

    func testS10505CatalogJsonRoundTripsTheKind() throws {
        let json: [String: Any] = [
            "exerciseId": "ex-ride-77",
            "name": "Ride 77",
            "capabilities": ["time", "distance"],
            "healthActivity": "cycling",
        ]
        let exercise = try WatchCatalogExercise(json: json)
        XCTAssertEqual(exercise.healthActivity, "cycling")
        XCTAssertEqual(
            try WatchCatalogExercise(json: exercise.toJson()),
            exercise,
            "toJson carries what init(json:) read"
        )
    }

    func testS10505CatalogJsonWithoutTheKindStaysWithoutIt() throws {
        let json: [String: Any] = [
            "exerciseId": "ex-bench-77",
            "name": "Bench 77",
            "capabilities": ["reps", "sets", "load"],
        ]
        let exercise = try WatchCatalogExercise(json: json)
        XCTAssertNil(exercise.healthActivity)
        XCTAssertFalse(
            exercise.toJson().keys.contains(WatchCatalogExercise.healthActivityKey),
            "a nil kind keeps today's payload: the key is absent, not null"
        )
    }

    func testS10505SlotRoundTripsTheKind() throws {
        let json: [String: Any] = [
            "exerciseId": "ex-hike-77",
            "name": "Hike 77",
            "capabilities": ["time", "distance"],
            "healthActivity": "hiking",
        ]
        let exercise = try WatchCatalogExercise(json: json)
        let slot = exercise.toSlot()
        XCTAssertEqual(
            WatchCatalogExercise(slot: slot)?.healthActivity,
            "hiking",
            "init(slot:) reads what toSlot wrote"
        )
    }

    func testS10505SlotWithoutTheKindStaysWithoutIt() throws {
        let json: [String: Any] = [
            "exerciseId": "ex-lift-77",
            "name": "Lift 77",
            "capabilities": ["reps", "sets", "load"],
        ]
        let exercise = try WatchCatalogExercise(json: json)
        XCTAssertFalse(
            exercise.toSlot().keys.contains(WatchCatalogExercise.healthActivityKey),
            "a nil kind keeps today's slot: the key is absent, not null"
        )
    }

    // MARK: - S-10506 the store's source carries the exact arms

    func testS10506ActivityTypeCarriesTheFourDistanceArms() throws {
        let source = try storeSource()
        for (name, type) in [
            ("cycling", ".cycling"),
            ("rowing", ".rowing"),
            ("walking", ".walking"),
            ("hiking", ".hiking"),
        ] {
            XCTAssertTrue(
                source.contains("case \"\(name)\": return \(type)"),
                "activityType(for:) has to carry the exact arm for \(name)"
            )
        }
    }

    func testS10506NameCarriesTheFourReverseArms() throws {
        let source = try storeSource()
        for name in ["cycling", "rowing", "walking", "hiking"] {
            XCTAssertTrue(
                source.contains("case .\(name): return \"\(name)\""),
                "name(for:) has to carry the exact reverse arm for \(name)"
            )
        }
    }

    // MARK: - S-10508 a routine effort round-trips and starts the right type

    func testS10508AnEffortRoundTripsTheKindIntoItsSlot() throws {
        let json: [String: Any] = [
            "effortId": "effort-ride-77",
            "exerciseId": "ex-ride-77",
            "exerciseName": "Ride 77",
            "effortKind": "timed",
            "capabilities": ["time", "distance"],
            "healthActivity": "cycling",
        ]
        let effort = try WatchRoutineEffort(json: json)
        XCTAssertEqual(effort.healthActivity, "cycling")
        XCTAssertEqual(effort.slot(token: "testtoken")["healthActivity"] as? String, "cycling")
        XCTAssertEqual(
            try WatchRoutineEffort(json: effort.toJson()).healthActivity,
            "cycling",
            "toJson carries what init(json:) read"
        )
    }

    func testS10508AnEffortWithoutTheKindLeavesItOutOfSlotAndJson() throws {
        let json: [String: Any] = [
            "effortId": "effort-bench-77",
            "exerciseId": "ex-bench-77",
            "exerciseName": "Bench 77",
            "effortKind": "reps",
            "capabilities": ["reps", "sets", "load"],
        ]
        let effort = try WatchRoutineEffort(json: json)
        XCTAssertNil(effort.healthActivity)
        XCTAssertFalse(
            effort.slot(token: "testtoken").keys.contains(WatchCatalogExercise.healthActivityKey),
            "an absent key stays absent in the slot"
        )
        XCTAssertFalse(
            effort.toJson().keys.contains(WatchCatalogExercise.healthActivityKey)
        )
    }

    func testS10508RideThenBenchOpensCycling() throws {
        let rideEffort = try WatchRoutineEffort(
            json: [
                "effortId": "effort-ride-77",
                "exerciseId": "ex-ride-77",
                "exerciseName": "Ride 77",
                "effortKind": "timed",
                "capabilities": ["time", "distance"],
                "healthActivity": "cycling",
            ]
        )
        let benchEffort = try WatchRoutineEffort(
            json: [
                "effortId": "effort-bench-77",
                "exerciseId": "ex-bench-77",
                "exerciseName": "Bench 77",
                "effortKind": "reps",
                "capabilities": ["reps", "sets", "load"],
            ]
        )
        XCTAssertEqual(
            WatchActivityTypes.forExercises([rideEffort.slot(token: "testtoken"), benchEffort.slot(token: "testtoken")])?.watchOs,
            "cycling"
        )
    }

    func testS10508BenchThenRideOpensStrength() throws {
        let rideEffort = try WatchRoutineEffort(
            json: [
                "effortId": "effort-ride-77",
                "exerciseId": "ex-ride-77",
                "exerciseName": "Ride 77",
                "effortKind": "timed",
                "capabilities": ["time", "distance"],
                "healthActivity": "cycling",
            ]
        )
        let benchEffort = try WatchRoutineEffort(
            json: [
                "effortId": "effort-bench-77",
                "exerciseId": "ex-bench-77",
                "exerciseName": "Bench 77",
                "effortKind": "reps",
                "capabilities": ["reps", "sets", "load"],
            ]
        )
        XCTAssertEqual(
            WatchActivityTypes.forExercises([benchEffort.slot(token: "testtoken"), rideEffort.slot(token: "testtoken")])?.watchOs,
            "traditionalStrengthTraining"
        )
    }

    // MARK: - S-17004 every contract kind resolves; unknown falls through

    /// The contract's Health-kind table, the same file both clients resolve
    /// against (`watch/contract/watch_sensor_contract.json`).
    private func contractKinds() throws -> [String: [String: String]] {
        let contract = try Fixtures.sensorContract()
        return try XCTUnwrap(
            contract["healthActivityTypes"] as? [String: [String: String]],
            "the contract carries the exercise-discipline → platform type table"
        )
    }

    private func named(
        _ id: String,
        _ capabilities: [String],
        _ healthActivity: String
    ) -> [String: Any] {
        var exercise = slot(id, capabilities)
        exercise["healthActivity"] = healthActivity
        return exercise
    }

    func testS17004EveryContractKindResolvesToItsRow() throws {
        let kinds = try contractKinds()
        XCTAssertEqual(
            kinds.count,
            32,
            "the contract carries every discipline's kind and the Hike/Rucking `hiking`"
        )

        for (kind, mapped) in kinds {
            let type = WatchActivityTypes.forExercise(
                capabilities: ["time"],
                healthActivity: kind
            )
            XCTAssertEqual(
                type.watchOs,
                mapped["watchos"],
                "\(kind) resolves to its watchOS row, not to the generic type"
            )
            XCTAssertEqual(
                type.wear,
                mapped["wear"],
                "\(kind) resolves to its Health Connect row"
            )
        }
    }

    func testS17004AnUnknownKindFallsThroughAndNeverMislabelsAStrengthExercise() {
        XCTAssertEqual(
            WatchActivityTypes.forExercise(
                capabilities: ["reps", "sets", "load"],
                healthActivity: "unreal-kind"
            ).watchOs,
            "traditionalStrengthTraining",
            "an unknown kind is absent: the capability chain answers (D-17003)"
        )
        XCTAssertEqual(
            WatchActivityTypes.forExercise(capabilities: ["hold", "time", "sets"]).watchOs,
            "flexibility",
            "no kind with a hold stays flexibility, as before"
        )
        XCTAssertEqual(
            WatchActivityTypes.forExercise(capabilities: ["time", "distance"]).watchOs,
            "running",
            "a distance exercise that names no kind stays a run, as before"
        )
    }

    // MARK: - S-17005 the kind beats hold and the modality

    func testS17005TheDisciplineBeatsHoldInference() {
        let plank = WatchActivityTypes.forExercise(
            capabilities: ["hold", "time", "sets"],
            healthActivity: "isometricHolds"
        )
        XCTAssertEqual(plank.watchOs, "functionalStrengthTraining")
        XCTAssertEqual(plank.wear, "exercise_type_strength_training")

        let yoga = WatchActivityTypes.forExercise(
            capabilities: ["hold", "time"],
            healthActivity: "yoga"
        )
        XCTAssertEqual(yoga.watchOs, "yoga")
        XCTAssertEqual(yoga.wear, "exercise_type_yoga")
    }

    func testS17005ASwimBeatsTheCardioModality() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [named("sx-swim", ["time", "distance"], "swimming")]
        )

        XCTAssertEqual(
            WatchActivityTypes.forSession(session)?.watchOs,
            "swimming",
            "the exercise's kind beats the modality (D-17003, S-16804's rule)"
        )
    }

    func testS17005AYogaSessionRecordsAsYogaNotTheMobilityModality() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "mobility_flexibility",
            exercises: [
                named("sx-yoga-a", ["hold", "time"], "yoga"),
                named("sx-yoga-b", ["hold", "time"], "yoga"),
            ]
        )

        XCTAssertEqual(WatchActivityTypes.forSession(session)?.watchOs, "yoga")
    }

    // MARK: - S-17006 majority, ties and start-fixing over the widened set

    func testS17006TheMajorityOfTheWidenedKindsDecides() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let lifts = (0..<5).map {
            named("sx-lift-\($0)", ["reps", "sets", "load"], "traditionalStrengthTraining")
        }
        let session = await engine.createSession(
            modality: "resistance_lifting",
            exercises: lifts + [named("sx-swim", ["time", "distance"], "swimming")]
        )

        XCTAssertEqual(
            WatchActivityTypes.forSession(session)?.watchOs,
            "traditionalStrengthTraining",
            "five named lifts outvote one named swim"
        )
    }

    func testS17006ATieGoesToTheEarliestNamedKind() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: nil,
            exercises: [
                named("sx-swim", ["time", "distance"], "swimming"),
                named("sx-run", ["time", "distance"], "running"),
            ]
        )

        XCTAssertEqual(
            WatchActivityTypes.forSession(session)?.watchOs,
            "swimming",
            "a tie answers the earliest named exercise"
        )
    }

    func testS17006ALaterExerciseNeverRetypesTheOpenWorkout() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: nil,
            exercises: [named("sx-swim", ["time", "distance"], "swimming")]
        )

        let store = ScriptedPlatformStore()
        let platform = WatchPlatformWorkout(store: store)
        let coordinator = WatchWorkoutCoordinator(platform: platform)
        await coordinator.refresh(session)
        XCTAssertEqual(store.begun, ["swimming"])

        _ = await engine.insertExercise(bench(), moveTo: true)
        await coordinator.refresh(try XCTUnwrap(engine.session))

        XCTAssertEqual(store.begun.count, 1, "the open workout is not begun again")
        XCTAssertEqual(
            platform.running?.watchOs,
            "swimming",
            "HealthKit cannot retype an open session (D-17007)"
        )
    }

    // MARK: - S-17007 sports record as their sport; unmapped stays other

    func testS17007ASportsSessionRecordsAsItsSport() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "sports",
            exercises: [named("sx-soccer", ["time", "rounds"], "soccer")]
        )

        XCTAssertEqual(WatchActivityTypes.forSession(session)?.watchOs, "soccer")
    }

    func testS17007AnUnmappedDisciplineInASportsSessionStaysOther() async throws {
        // Padel: the phone has no honest kind, so it sends none.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: "sports",
                exercises: [slot("sx-padel", ["time", "rounds"])]
            )

            XCTAssertEqual(WatchActivityTypes.forSession(session)?.watchOs, "other")
        }

        // A discipline-less exercise: the same generic answer.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(
                modality: "sports",
                exercises: [slot("sx-untyped", ["time", "rounds"])]
            )

            XCTAssertEqual(WatchActivityTypes.forSession(session)?.watchOs, "other")
        }
    }
}
