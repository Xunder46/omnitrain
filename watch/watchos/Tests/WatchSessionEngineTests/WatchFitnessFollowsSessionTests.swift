//
//  WatchFitnessFollowsSessionTests.swift
//  WatchSessionEngineTests
//
//  The wrist's Apple Fitness workout follows how the session ended: a finished
//  session saves its workout, an abandoned, vanished or replaced one discards
//  it, and a workout a killed process left open is saved only while its session
//  is still active. Plan
//  `docs/plans/2026-10-28-89-fitness-workouts-follow-the-session-plan/2026-10-28-89-fitness-workouts-follow-the-session-plan.md`,
//  scenarios S-89-1 and S-89-2 (decisions D-1 to D-3, OQ-1).
//
//  Asserted through `ScriptedPlatformStore` (`WatchWorkoutCoordinatorTests.swift`),
//  which records the flag each end carried, over a real engine and its store.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchFitnessFollowsSessionTests: XCTestCase {

    private func makeCoordinator(
        _ store: ScriptedPlatformStore
    ) -> (coordinator: WatchWorkoutCoordinator, platform: WatchPlatformWorkout) {
        let platform = WatchPlatformWorkout(store: store)
        return (WatchWorkoutCoordinator(platform: platform), platform)
    }

    // MARK: - S-89-1 the coordinator saves only a completed session's workout

    func testS89_1AnAbandonedSessionDiscardsItsWorkout() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.refresh(await engine.createSession(modality: "sports"))
        await coordinator.refresh(await engine.abandonSession())

        XCTAssertEqual(store.endSavings, [false], "S-89-1 active then abandoned ends the workout with saving == false")
        XCTAssertNil(platform.running, "S-89-1 and nothing is left open")
    }

    func testS89_1ACompletedSessionSavesItsWorkout() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.refresh(await engine.createSession(modality: "sports"))
        await coordinator.refresh(await engine.finishSession())

        XCTAssertEqual(store.endSavings, [true], "S-89-1 active then completed ends the workout with saving == true")
        XCTAssertNil(platform.running)
    }

    func testS89_1AVanishedSessionDiscardsItsWorkout() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.refresh(await engine.createSession(modality: "sports"))
        await coordinator.refresh(nil)

        XCTAssertEqual(store.endSavings, [false], "S-89-1 active then nil ends the workout with saving == false")
        XCTAssertNil(platform.running)
    }

    func testS89_1AReplacedSessionDiscardsTheOldWorkout() async throws {
        let harnessA = Harness()
        let engineA = await harnessA.runningEngine()
        let sessionA = await engineA.createSession(modality: "sports")
        let harnessB = Harness(sessionId: "s-watch-2")
        let engineB = await harnessB.runningEngine()
        let sessionB = await engineB.createSession(modality: "cardio_endurance")
        XCTAssertNotEqual(sessionA.sessionId, sessionB.sessionId)

        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.refresh(sessionA)
        await coordinator.refresh(sessionB)

        XCTAssertEqual(store.endSavings, [false], "S-89-1 a replaced session id ends the old workout with saving == false")
        XCTAssertEqual(store.calls, ["begin(other)", "end", "begin(running)"], "S-89-1 and the new one opens after it")
        XCTAssertEqual(platform.running?.watchOs, "running")
    }

    // MARK: - S-89-2 recovery saves only while the persisted session is active

    /// The relaunch the recovery runs in: a fresh engine over the store the
    /// killed process wrote, not yet restored, so the answer comes from what
    /// was persisted.
    private func relaunchedEngine(_ harness: Harness) -> WatchSessionEngine {
        harness.newEngine()
    }

    func testS89_2AStrandedWorkoutWithAnActiveSessionIsSaved() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        _ = await killed.createSession(modality: "cardio_endurance")

        let relaunched = relaunchedEngine(harness)
        XCTAssertNil(relaunched.session, "the relaunched engine has restored nothing yet")
        let store = ScriptedPlatformStore(inProgress: ["running"])
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        XCTAssertEqual(store.endSavings, [true], "S-89-2 an active persisted session keeps the workout up to now (OQ-1)")
        XCTAssertNil(platform.running, "S-89-2 and nothing is left open")
    }

    func testS89_2AStrandedWorkoutWithAnAbandonedSessionIsDiscarded() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        _ = await killed.createSession(modality: "cardio_endurance")
        _ = await killed.abandonSession()

        let relaunched = relaunchedEngine(harness)
        let store = ScriptedPlatformStore(inProgress: ["running"])
        let (coordinator, _) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        XCTAssertEqual(store.endSavings, [false], "S-89-2 an abandoned persisted session discards the workout")
    }

    func testS89_2AStrandedWorkoutWithACompletedSessionIsDiscarded() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        _ = await killed.createSession(modality: "cardio_endurance")
        _ = await killed.finishSession()

        let relaunched = relaunchedEngine(harness)
        let store = ScriptedPlatformStore(inProgress: ["running"])
        let (coordinator, _) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        XCTAssertEqual(store.endSavings, [false], "S-89-2 only a still-active session saves at recovery (D-3)")
    }

    func testS89_2AStrandedWorkoutWithNoSessionIsDiscarded() async throws {
        let harness = Harness()
        let relaunched = relaunchedEngine(harness)
        let store = ScriptedPlatformStore(inProgress: ["running"])
        let (coordinator, _) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        XCTAssertEqual(store.endSavings, [false], "S-89-2 a missing session discards the workout")
    }

    func testS89_2NothingStrandedMeansNoEnd() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        _ = await killed.createSession(modality: "cardio_endurance")

        let relaunched = relaunchedEngine(harness)
        let store = ScriptedPlatformStore()
        let (coordinator, _) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        XCTAssertEqual(store.ended, 0, "S-89-2 with nothing stranded no end reaches the store")
        XCTAssertEqual(store.endSavings, [])
        XCTAssertEqual(store.calls, ["inProgressActivityTypes"], "S-89-2 only the question is asked")
    }

    /// The reader is the engine's persisted answer and leaves the engine as it
    /// was: the launch task's own `restore()` still runs after recovery.
    func testS89_2TheStoredSessionIsReadWithoutRestoring() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        let session = await killed.createSession(modality: "cardio_endurance")

        let relaunched = relaunchedEngine(harness)
        let stored = await relaunched.storedSession()

        XCTAssertEqual(stored?.sessionId, session.sessionId)
        XCTAssertEqual(stored?.status, WatchSessionStatus.active)
        XCTAssertNil(relaunched.session, "reading the stored session restores nothing")
    }
}
