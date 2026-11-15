//
//  WatchRelaunchRecoveryTests.swift
//  WatchSessionEngineTests
//
//  Plan `docs/plans/2026-11-14-168-health-walk-type-and-relaunch-plan/2026-11-14-168-health-walk-type-and-relaunch-plan.md`:
//  a relaunch runs the launch recovery twice — the system's workout-recovery
//  relaunch (`OmniTrainApp`) and `restore()` — and the second call used to undo
//  the first one's adoption: `recoverInProgress(saving:)` cleared `running`
//  unconditionally, so the next apply opened a SECOND `HKWorkoutSession` and
//  HealthKit's replace rule discarded the adopted builder. The owner's walk lost
//  its first 25 minutes to exactly that.
//
//  Scenario mapping:
//    S-16801 the second recovery keeps the adoption   → `testS16801...`
//    S-16802 nothing stranded leaves a held workout open → `testS16802...`
//    S-16803 an honest second recovery adds no end    → `testS16803...`
//
//  Nothing here touches the platform's health service: `ScriptedPlatformStore`
//  (`WatchWorkoutCoordinatorTests.swift`) already models HealthKit's consume-once
//  recovery, so the whole file runs on macOS beside `swift test`.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchRelaunchRecoveryTests: XCTestCase {

    private struct Setup {
        let engine: WatchSessionEngine
        let session: WatchSessionRecord
        let store: ScriptedPlatformStore
        let platform: WatchPlatformWorkout
        let coordinator: WatchWorkoutCoordinator
    }

    /// A live session of `modality` with a workout a killed process left open,
    /// and the coordinator that is about to adopt it.
    private func relaunch(
        _ modality: String = "cardio_endurance"
    ) async -> Setup {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: modality)
        let type = WatchActivityTypes.forModality(modality).watchOs
        let store = ScriptedPlatformStore(inProgress: [type], adoptsInProgress: type)
        let platform = WatchPlatformWorkout(store: store)
        let coordinator = WatchWorkoutCoordinator(platform: platform)
        return Setup(
            engine: engine,
            session: session,
            store: store,
            platform: platform,
            coordinator: coordinator
        )
    }

    // MARK: - S-16801 the relaunch's second recovery keeps the adopted workout

    func testS16801TheSecondRecoveryKeepsTheAdoptedWorkout() async throws {
        let setup = await relaunch()

        // The system's workout-recovery relaunch (`OmniTrainApp`).
        await setup.coordinator.recoverInProgress(
            storedSession: { await setup.engine.storedSession() }
        )
        XCTAssertEqual(setup.store.adopted, 1, "S-16801 the first recovery adopts")
        XCTAssertEqual(setup.platform.running?.watchOs, "running", "S-16801 and holds it")

        // The same path again, from `restore()`.
        await setup.coordinator.recoverInProgress(
            storedSession: { await setup.engine.storedSession() }
        )
        XCTAssertEqual(setup.platform.running?.watchOs, "running", "S-16801 the second recovery leaves it held")
        XCTAssertEqual(setup.store.ended, 0, "S-16801 and ends nothing")

        // The relaunch's real order: the delegate, restore()'s recovery, the
        // restore-finished apply, then a revision emission.
        await setup.coordinator.restoreFinished(session: setup.session)
        XCTAssertEqual(setup.platform.running?.watchOs, "running", "S-16801 the restored session keeps it open")

        await setup.coordinator.refresh(setup.session)
        XCTAssertEqual(setup.platform.running?.watchOs, "running", "S-16801 and a revision changes nothing")

        XCTAssertEqual(setup.store.adopted, 1, "S-16801 exactly one adoption")
        XCTAssertEqual(setup.store.begun, [], "S-16801 no second workout for the session that already has one")
        XCTAssertEqual(setup.store.ended, 0, "S-16801 the adopted builder is never discarded")
    }

    // MARK: - S-16802 recovery with nothing stranded leaves a held workout open

    func testS16802RecoveryWithNothingStrandedLeavesAHeldWorkoutOpen() async throws {
        let setup = await relaunch()
        await setup.coordinator.recoverInProgress(
            storedSession: { await setup.engine.storedSession() }
        )
        XCTAssertEqual(setup.store.adopted, 1, "S-16802 the fixture adopts first")
        XCTAssertEqual(setup.store.inProgress, [], "S-16802 so the orphan is consumed")

        // The hardening on its own, past D-16801's guard: the store reports
        // nothing stranded, so nothing may be unregistered.
        let ended = await setup.platform.recoverInProgress(saving: true)

        XCTAssertEqual(ended, [], "S-16802 nothing was ended")
        XCTAssertEqual(setup.store.ended, 0, "S-16802 no end reaches the store")
        XCTAssertEqual(
            setup.store.calls,
            ["inProgressActivityTypes"],
            "S-16802 the only call is the question"
        )
        XCTAssertEqual(
            setup.platform.running?.watchOs,
            "running",
            "S-16802 a workout this process holds is not unregistered by a store that has nothing"
        )
    }

    // MARK: - S-16803 an honest second recovery after a fall-through adds no end

    func testS16803ASecondRecoveryAfterAFallThroughAddsNoEnd() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "cardio_endurance")
        _ = await engine.finishSession()
        let stored = await engine.storedSession()
        XCTAssertEqual(
            stored?.status,
            WatchSessionStatus.completed,
            "S-16803 the fixture's stored session is finished"
        )

        let store = ScriptedPlatformStore(inProgress: ["running"])
        let platform = WatchPlatformWorkout(store: store)
        let coordinator = WatchWorkoutCoordinator(platform: platform)

        await coordinator.recoverInProgress(storedSession: { await engine.storedSession() })
        XCTAssertEqual(store.ended, 1, "S-16803 the first recovery ends the stranded workout")
        XCTAssertNil(platform.running, "S-16803 and the watch holds nothing")

        await coordinator.recoverInProgress(storedSession: { await engine.storedSession() })

        XCTAssertEqual(store.ended, 1, "S-16803 the second recovery adds no end")
        XCTAssertEqual(
            store.calls.filter { $0 == "end" }.count,
            1,
            "S-16803 exactly one end in the whole call log: \(store.calls)"
        )
        XCTAssertEqual(store.begun, [], "S-16803 and opens nothing")
    }
}
