//
//  WatchContinueRecoveredWorkoutTests.swift
//  WatchSessionEngineTests
//
//  Plan 140: a workout a killed watch process left running is CONTINUED after a
//  relaunch, not saved and replaced — the store adopts the still-running
//  session, one Fitness workout covers one session, and the Health energy
//  counter never restarts at 0. A store that cannot adopt answers nil and the
//  recovery of plan 89 runs unchanged.
//
//  Scenarios S-14001 to S-14005 of
//  `docs/plans/2026-11-09-140-watch-continue-recovered-workout-plan/…`
//  (asserted through an adoptable fake store over the real coordinator).
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// The health store as a script, with one extra seam over
/// `ScriptedPlatformStore` (`WatchWorkoutCoordinatorTests.swift`): it answers
/// `adoptInProgress()` with `adopts` when that is set, and records every call
/// in the order it arrived.
private final class AdoptablePlatformStore: WatchPlatformWorkoutStore {
    private let lock = NSLock()
    private var log: [String] = []
    private var stranded: [String]
    private var savings: [Bool] = []
    private var begins: [String] = []

    /// The name an adopting store hands back, or nil when it cannot adopt.
    let adopts: String?

    init(inProgress: [String] = [], adopts: String? = nil) {
        self.stranded = inProgress
        self.adopts = adopts
    }

    var calls: [String] { withState { log } }
    var endSavings: [Bool] { withState { savings } }
    var begun: [String] { withState { begins } }

    func adoptInProgress() async -> String? {
        withState { log.append("adoptInProgress") }
        return adopts
    }

    func begin(_ activityType: String) async {
        withState {
            log.append("begin(\(activityType))")
            begins.append(activityType)
        }
    }

    func end(saving: Bool) async {
        withState {
            log.append("end")
            savings.append(saving)
            if !stranded.isEmpty { stranded.removeFirst() }
        }
    }

    func inProgressActivityTypes() async -> [String] {
        withState {
            log.append("inProgressActivityTypes")
            return stranded
        }
    }

    private func withState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class WatchContinueRecoveredWorkoutTests: XCTestCase {

    private func makeCoordinator(
        _ store: AdoptablePlatformStore
    ) -> (coordinator: WatchWorkoutCoordinator, platform: WatchPlatformWorkout) {
        let platform = WatchPlatformWorkout(store: store)
        return (WatchWorkoutCoordinator(platform: platform), platform)
    }

    /// The relaunch the recovery runs in: a fresh engine over the store the
    /// killed process wrote, not yet restored, so the answer comes from what
    /// was persisted (`WatchFitnessFollowsSessionTests`' idiom).
    private func relaunchedEngine(_ harness: Harness) -> WatchSessionEngine {
        harness.newEngine()
    }

    // MARK: - S-14001 an active session whose store adopts continues the workout

    func testS14001AnAdoptedRecoveryContinuesWithoutSavingOrReplacing() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        _ = await killed.createSession(modality: "sports")

        let relaunched = relaunchedEngine(harness)
        let stored = await relaunched.storedSession()
        XCTAssertEqual(stored?.status, WatchSessionStatus.active)
        let session = try XCTUnwrap(stored)

        let store = AdoptablePlatformStore(adopts: "walking")
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        XCTAssertEqual(store.calls, ["adoptInProgress"], "S-14001 the store is asked to adopt and nothing else")
        XCTAssertEqual(store.endSavings, [], "S-14001 no end reaches the store")
        XCTAssertFalse(store.calls.contains("inProgressActivityTypes"), "S-14001 no in-progress question is asked")
        XCTAssertNotNil(platform.running, "S-14001 the adopted workout is the one running")

        await coordinator.refresh(session)

        XCTAssertEqual(store.begun, [], "S-14001 the same active session opens no second workout")
        XCTAssertEqual(store.calls, ["adoptInProgress"], "S-14001 and the refresh changes nothing")
        XCTAssertEqual(coordinator.openedForSessionId, session.sessionId, "S-14001 the workout belongs to the session")
    }

    // MARK: - S-14002 a store that cannot adopt keeps today's recovery

    func testS14002ANonAdoptingStoreSavesTheStrandedWorkoutAsBefore() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        _ = await killed.createSession(modality: "sports")

        let relaunched = relaunchedEngine(harness)
        let store = AdoptablePlatformStore(inProgress: ["walking"], adopts: nil)
        let (coordinator, _) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        XCTAssertEqual(store.calls, ["adoptInProgress", "inProgressActivityTypes", "end"], "S-14002 the non-adopting store is asked, then the old recovery runs")
        XCTAssertEqual(store.endSavings, [true], "S-14002 an active persisted session keeps the workout saved (plan 89 OQ-1)")
    }

    // MARK: - S-14003 a stored session that is not active is never adopted

    func testS14003ACompletedStoredSessionIsEndedDiscardingWithoutBeingAskedToAdopt() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        _ = await killed.createSession(modality: "sports")
        _ = await killed.finishSession()

        let relaunched = relaunchedEngine(harness)
        let stored = await relaunched.storedSession()
        XCTAssertEqual(stored?.status, WatchSessionStatus.completed)

        let store = AdoptablePlatformStore(inProgress: ["walking"], adopts: "walking")
        let (coordinator, _) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        XCTAssertEqual(store.calls, ["inProgressActivityTypes", "end"], "S-14003 adoptInProgress is never asked for a finished session")
        XCTAssertEqual(store.endSavings, [false], "S-14003 the stranded workout is ended discarding, as before")
    }

    // MARK: - S-14004 a completed session ends the adopted workout, saved

    func testS14004AnAdoptedWorkoutIsEndedSavedOnceWhenItsSessionCompletes() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        _ = await killed.createSession(modality: "sports")

        let relaunched = relaunchedEngine(harness)
        let store = AdoptablePlatformStore(adopts: "walking")
        let (coordinator, _) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        let completed = await killed.finishSession()
        let storedAfterFinish = await relaunched.storedSession()
        XCTAssertEqual(completed.sessionId, storedAfterFinish?.sessionId)
        await coordinator.refresh(completed)

        XCTAssertEqual(store.endSavings, [true], "S-14004 the completed session saves the workout it adopted")
        XCTAssertEqual(store.calls, ["adoptInProgress", "end"], "S-14004 exactly one end, and no begin")
        XCTAssertEqual(store.begun, [], "S-14004 the workout was never opened twice")
    }

    // MARK: - S-14005 a different session replaces the adopted workout

    func testS14005ADifferentSessionDiscardsTheAdoptedWorkoutAndBeginsItsOwn() async throws {
        let harness = Harness()
        let killed = await harness.runningEngine()
        _ = await killed.createSession(modality: "sports")

        let harnessB = Harness(sessionId: "s-watch-2")
        let engineB = await harnessB.runningEngine()
        let sessionB = await engineB.createSession(modality: "cardio_endurance")
        let storedA = await killed.storedSession()
        XCTAssertNotEqual(storedA?.sessionId, sessionB.sessionId)

        let relaunched = relaunchedEngine(harness)
        let store = AdoptablePlatformStore(adopts: "walking")
        let (coordinator, _) = makeCoordinator(store)

        await coordinator.recoverInProgress(storedSession: { await relaunched.storedSession() })

        await coordinator.refresh(sessionB)

        XCTAssertEqual(store.endSavings, [false], "S-14005 the replaced workout is discarded (plan 89 D-2)")
        XCTAssertEqual(store.begun, ["running"], "S-14005 and the new session opens its own workout")
        XCTAssertEqual(store.calls, ["adoptInProgress", "end", "begin(running)"], "S-14005 end then begin, in that order")
    }
}
