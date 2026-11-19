//
//  WatchOneWorkoutPerSessionTests.swift
//  WatchSessionEngineTests
//
//  The wrist registers ONE Fitness workout for a Free outdoor walk: one begin,
//  typed from the exercise and outdoors, and one saving end when the session
//  completes. Plan
//  `docs/plans/2026-10-28-89c1-one-workout-per-session-plan/2026-10-28-89c1-one-workout-per-session-plan.md`,
//  scenario S-89c1-6: the second workout the owner saw is the phone's, not a
//  second one from the wrist.
//
//  The store records the activity type and the outdoors answer of each begin as
//  one call, and the flag of each end, over a real engine and coordinator.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// Records every begin as (type, outdoors) and every end's saving flag.
private final class RecordingBeginEndStore: WatchPlatformWorkoutStore {
    private(set) var begins: [(activityType: String, outdoors: Bool)] = []
    private(set) var endSavings: [Bool] = []

    func begin(_ activityType: String, outdoors: Bool) async {
        begins.append((activityType, outdoors))
    }

    func end(saving: Bool) async {
        endSavings.append(saving)
    }

    func inProgressActivityTypes() async -> [String] { [] }
}

final class WatchOneWorkoutPerSessionTests: XCTestCase {

    func testS89c1_6AFreeOutdoorWalkBeginsOneWalkingWorkoutAndSavesItOnce() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let store = RecordingBeginEndStore()
        let coordinator = WatchWorkoutCoordinator(platform: WatchPlatformWorkout(store: store))

        // A Free session (no modality): nothing to register until the walk.
        _ = await engine.createSession(modality: nil)
        await coordinator.refresh(try XCTUnwrap(engine.session))

        let walk: [String: Any] = [
            "sessionExerciseId": "sx-walk",
            "exerciseId": "ex-walk",
            "name": "Outdoor Walk",
            "capabilities": ["time", "distance"],
            "healthActivity": "walking",
        ]
        _ = await engine.insertExercise(walk, moveTo: true)
        await coordinator.refresh(try XCTUnwrap(engine.session))
        // A later refresh while it runs (a set logged, the screen raised).
        await coordinator.refresh(try XCTUnwrap(engine.session))

        await coordinator.refresh(await engine.finishSession())

        XCTAssertEqual(store.begins.count, 1, "S-89c1-6 one begin, never two")
        XCTAssertEqual(store.begins.first?.activityType, "walking", "S-89c1-6 typed from the exercise")
        XCTAssertEqual(store.begins.first?.outdoors, true, "S-89c1-6 an outdoor workout")
        XCTAssertEqual(store.endSavings, [true], "S-89c1-6 one saving end when completed")
    }
}
