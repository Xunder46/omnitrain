//
//  WatchOpenFailureTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-10-26-82-wrist-health-failure-and-haptics-plan/2026-10-26-82-wrist-health-failure-and-haptics-plan.md`
//  — the wrist knows when the Health workout failed to open:
//    S-15101 a begin that fails leaves `openFailed` set, and the next
//            successful start clears it
//    S-15102 the coordinator carries the flag across refreshes: a session
//            ending does not clear it, only the next successful start does
//
//  Nothing here touches the platform's health service: the stores are fakes,
//  so the whole file runs on macOS beside `swift test`.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// A store whose registration always fails, the way a thrown
/// `HKWorkoutSession` init or a failed `beginCollection` does (plan 82 D-1):
/// the flag is the only thing it sets.
final class FailingBeginStore: WatchPlatformWorkoutStore {
    var lastBeginFailed = false

    func begin(_ activityType: String, outdoors: Bool) async {
        lastBeginFailed = true
    }

    func end() async {}

    func inProgressActivityTypes() async -> [String] { [] }
}

/// A store whose registration always succeeds, and which records what it was
/// asked for.
final class SucceedingBeginStore: WatchPlatformWorkoutStore {
    private(set) var begun: [String] = []

    func begin(_ activityType: String, outdoors: Bool) async {
        begun.append(activityType)
    }

    func end() async {}

    func inProgressActivityTypes() async -> [String] { [] }
}

final class WatchOpenFailureTests: XCTestCase {

    /// S-15101, first arm: a begin the store fails leaves `openFailed` set and
    /// the registration contract unchanged — the workout counts as running.
    func testS15101AFailedBeginLeavesOpenFailedSet() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: "sports")

        let platform = WatchPlatformWorkout(store: FailingBeginStore())
        await platform.start(session)

        XCTAssertTrue(platform.openFailed, "the failed begin is reported")
        XCTAssertNotNil(platform.running, "the registration is recorded however the store answered")
    }

    /// S-15101, second arm (plan item 6): the existing denial path — a store
    /// that answers a begin with nothing, as a refused permission does — is
    /// still not a failure, and a succeeding store never sets the flag.
    func testS15101DenialAndSuccessLeaveOpenFailedClear() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: "sports")

        let denied = WatchPlatformWorkout(store: ScriptedPlatformStore(deniesBegins: true))
        await denied.start(session)
        XCTAssertFalse(denied.openFailed, "a refusal that throws nothing is not a failure")

        let succeeding = SucceedingBeginStore()
        let succeeded = WatchPlatformWorkout(store: succeeding)
        await succeeded.start(session)
        XCTAssertFalse(succeeded.openFailed, "a begin the store answered is not a failure")
        XCTAssertEqual(succeeding.begun.count, 1, "the succeeding store was asked once")
    }

    /// S-15102: the coordinator carries the flag. A session ending does not
    /// clear it — the summary reads it after the session is over — only the
    /// next active session's successful start does.
    func testS15102TheCoordinatorCarriesTheFailureAcrossRefreshes() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: "sports")

        let failing = WatchWorkoutCoordinator(
            platform: WatchPlatformWorkout(store: FailingBeginStore())
        )
        await failing.refresh(session)
        XCTAssertTrue(failing.openFailed, "the failed begin reaches the coordinator")

        await failing.refresh(nil)
        XCTAssertTrue(failing.openFailed, "the session ending does not clear it")

        // The next active session, over a store that succeeds.
        let nextHarness = Harness(sessionId: "s-watch-2")
        let nextEngine = await nextHarness.runningEngine()
        let nextSession = await nextEngine.createSession(modality: "sports")

        let succeeding = WatchWorkoutCoordinator(
            platform: WatchPlatformWorkout(store: SucceedingBeginStore())
        )
        await succeeding.refresh(nextSession)
        XCTAssertFalse(succeeding.openFailed, "the next successful start clears it")
    }

    /// Plan 82 review: a failure belongs to its own session. When another
    /// session goes live, the flag no longer reads the last one's outcome, even
    /// if the new session has no workout to open yet (an empty Free workout).
    func testS15110AnotherSessionGoingLiveDropsTheLastFailure() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let first = await engine.createSession(modality: "sports")

        let coordinator = WatchWorkoutCoordinator(
            platform: WatchPlatformWorkout(store: FailingBeginStore())
        )
        await coordinator.refresh(first)
        XCTAssertTrue(coordinator.openFailed, "the first session's begin failed")

        let nextHarness = Harness(sessionId: "s-watch-2")
        let nextEngine = await nextHarness.runningEngine()
        let empty = await nextEngine.createSession(modality: nil)
        await coordinator.refresh(empty)
        XCTAssertFalse(
            coordinator.openFailed,
            "a new, still empty session has no failure of its own"
        )
    }
}
