//
//  WatchWorkoutAdoptBeforeRestoreTests.swift
//  WatchSessionEngineTests
//
//  Plan `docs/plans/2026-11-12-150-watch-crash-fix-plan/2026-11-12-150-watch-crash-fix-plan.md`,
//  Task B: a workout adopted at launch — the killed process's workout, taken
//  over so the session continues it (plan 140) — was ended a moment later by
//  the first `revision` emission, which carries the empty session from before
//  `restore()` finished. The device log read `workout_adopted running` followed
//  by `workout_end discarded`, and the session's first minutes never reached
//  Fitness.
//
//  Scenario mapping:
//    S-15002 a refresh before restore keeps it      → `testS15002...`
//    S-15003 the restored session adds no begin/end → `testS15003...`
//    S-15004 restore finished with no session ends  → `testS15004...`
//    S-15005 a different session replaces it        → `testS15005...`
//    S-15006 no adoption: a nil refresh ends it     → `testS15006...`
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchWorkoutAdoptBeforeRestoreTests: XCTestCase {

    private struct Setup {
        let engine: WatchSessionEngine
        let session: WatchSessionRecord
        let store: ScriptedPlatformStore
        let platform: WatchPlatformWorkout
        let coordinator: WatchWorkoutCoordinator
    }

    /// A live session whose workout a killed process left open, and the
    /// coordinator that has just adopted it.
    private func adopted(_ modality: String = "cardio_endurance") async -> Setup {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: modality)
        let type = WatchActivityTypes.forModality(modality).watchOs
        let store = ScriptedPlatformStore(inProgress: [type], adoptsInProgress: type)
        let platform = WatchPlatformWorkout(store: store)
        let coordinator = WatchWorkoutCoordinator(platform: platform)

        await coordinator.recoverInProgress(storedSession: { await engine.storedSession() })

        XCTAssertEqual(store.adopted, 1, "the launch adopted the workout")
        XCTAssertEqual(store.calls, [], "and asked the health store nothing else")
        XCTAssertEqual(platform.running?.watchOs, type, "and the watch holds it")
        return Setup(
            engine: engine,
            session: session,
            store: store,
            platform: platform,
            coordinator: coordinator
        )
    }

    /// S-15002: the launch's `revision` emission arrives before `restore()`
    /// has made the session current. It carries no session, but it is not the
    /// session's end.
    func testS15002ARefreshBeforeRestoreKeepsTheAdoptedWorkout() async throws {
        let setup = await adopted()

        await setup.coordinator.refresh(nil)

        XCTAssertEqual(setup.store.ended, 0, "the adopted workout is not discarded")
        XCTAssertEqual(
            setup.platform.running?.watchOs,
            WatchActivityTypes.forModality("cardio_endurance").watchOs,
            "and it is still running"
        )
    }

    /// S-15003: the emission from `restore()` carries the adopted session. It
    /// is the workout's own session, so nothing opens and nothing closes.
    func testS15003TheRestoredSessionOpensNothingNew() async throws {
        let setup = await adopted()

        await setup.coordinator.refresh(nil)
        await setup.coordinator.refresh(setup.session)
        await setup.coordinator.refresh(setup.session)

        XCTAssertEqual(setup.store.begun, [], "no second workout for the session that already has one")
        XCTAssertEqual(setup.store.ended, 0, "and the adopted one stays open")
        XCTAssertEqual(
            setup.platform.running?.watchOs,
            WatchActivityTypes.forModality("cardio_endurance").watchOs
        )
    }

    /// S-15005: the replacement rule is unchanged — a different session after
    /// adoption ends the adopted workout, then opens its own.
    func testS15005ADifferentSessionReplacesTheAdoptedWorkout() async throws {
        let setup = await adopted()

        // The phone's reset: a session with an id of its own.
        let other = Harness(sessionId: "s-watch-2")
        let otherEngine = await other.runningEngine()
        let replacement = await otherEngine.createSession(modality: "cardio_endurance")
        XCTAssertNotEqual(replacement.sessionId, setup.session.sessionId)

        await setup.coordinator.refresh(replacement)

        XCTAssertEqual(setup.store.ended, 1, "the adopted workout is closed exactly once")
        XCTAssertEqual(setup.store.begun, ["running"], "and the replacement opens its own")
        XCTAssertEqual(
            setup.store.calls,
            ["end", "begin(running)"],
            "the begin never precedes the end"
        )
        XCTAssertEqual(setup.platform.running?.watchOs, "running", "the replacement's is the one left open")
    }

    /// S-15004: the restore finished and the wrist has no session. From here a
    /// nil session is the adopted workout's own end, discarded as today.
    func testS15004RestoreFinishingWithNoSessionDiscardsTheAdoptedWorkout() async throws {
        let setup = await adopted()

        await setup.coordinator.restoreFinished(session: nil)

        XCTAssertEqual(setup.store.ended, 1, "the adopted workout is closed once the restore has answered")
        XCTAssertEqual(setup.store.endSavings, [false], "and discarded: its session is gone")
        XCTAssertNil(setup.platform.running)
        XCTAssertEqual(
            setup.store.calls,
            ["end"],
            "no workout is opened for a session that is not there"
        )
    }

    /// S-15006: the early return belongs to an adoption only. A workout this
    /// process opened for a session is still ended by a nil refresh.
    func testS15006ARefreshWithNoAdoptionEndsTheWorkout() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: "cardio_endurance")
        let store = ScriptedPlatformStore()
        let platform = WatchPlatformWorkout(store: store)
        let coordinator = WatchWorkoutCoordinator(platform: platform)

        await coordinator.refresh(session)
        XCTAssertEqual(store.begun, ["running"])

        await coordinator.refresh(nil)

        XCTAssertEqual(store.ended, 1, "a session that is gone closes its workout, as before")
        XCTAssertEqual(store.endSavings, [false])
        XCTAssertNil(platform.running)
    }
}
