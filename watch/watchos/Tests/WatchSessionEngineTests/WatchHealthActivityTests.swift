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
            healthActivity: "swimming"
        )
        XCTAssertEqual(type.watchOs, "running")
        XCTAssertEqual(type.wear, "exercise_type_running")
    }

    // MARK: - S-10503 hold still beats distance

    func testS10503AHoldBeatsDistanceEvenWithACyclingKind() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["hold", "time", "distance"],
            healthActivity: "cycling"
        )
        XCTAssertEqual(
            type,
            WatchActivityTypes.byModality["isometric_stretching"],
            "hold is tested first: a plank with a distance capability is not a ride"
        )
    }

    func testS10503RepsOnlyWithACyclingKindIsStrength() {
        let type = WatchActivityTypes.forExercise(
            capabilities: ["reps", "sets", "load"],
            healthActivity: "cycling"
        )
        XCTAssertEqual(
            type.watchOs,
            "traditionalStrengthTraining",
            "the kind is read only with distance"
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
        XCTAssertEqual(effort.slot["healthActivity"] as? String, "cycling")
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
            effort.slot.keys.contains(WatchCatalogExercise.healthActivityKey),
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
            WatchActivityTypes.forExercises([rideEffort.slot, benchEffort.slot])?.watchOs,
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
            WatchActivityTypes.forExercises([benchEffort.slot, rideEffort.slot])?.watchOs,
            "traditionalStrengthTraining"
        )
    }
}
