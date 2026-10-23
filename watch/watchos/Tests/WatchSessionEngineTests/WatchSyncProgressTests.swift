//
//  WatchSyncProgressTests.swift
//  WatchSessionEngineTests
//
//  S-8501 to S-8507 and S-8510 of
//  `docs/plans/2026-10-22-55-wrist-sync-progress-plan/2026-10-22-55-wrist-sync-progress-plan.md`
//  — when the wrist's Sync button is a spinner. The window is driven by an
//  injected clock, so every boundary is asserted exactly rather than waited for.
//

import XCTest

@testable import WatchSessionEngine

final class WatchSyncProgressTests: XCTestCase {

    private func makeClock() -> TestClock {
        TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    }

    // MARK: - S-8501 nothing is running until a sync begins

    func testS8501InactiveBeforeBeginAndActiveRightAfter() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)

        XCTAssertFalse(progress.isActive(), "S-8501 a sync that never began is not running")

        progress.begin()
        XCTAssertTrue(progress.isActive(), "S-8501 begin starts it at once")

        clock.advance(0.5)
        XCTAssertTrue(progress.isActive(), "S-8501 half a second later it is still running")
    }

    // MARK: - S-8502 the quiet window runs from the newest arrival

    func testS8502RoutinesReplyAloneEndsTheSyncTwoSecondsLater() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin()

        clock.advance(1)
        progress.noteArrival(type: "routines_down", at: clock.call())

        clock.advance(1.9)
        XCTAssertTrue(progress.isActive(), "S-8502 a tenth before the quiet window closes")

        clock.advance(0.1)
        XCTAssertFalse(
            progress.isActive(),
            "S-8502 inactive at exactly two seconds after the arrival — not two after the begin"
        )
    }

    // MARK: - S-8503 each later batch restarts the quiet window

    func testS8503EachExercisesBatchRestartsTheQuietWindow() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin()

        clock.advance(1)
        progress.noteArrival(type: "routines_down", at: clock.call())

        clock.advance(1.5)
        progress.noteArrival(type: "exercises_down", at: clock.call())
        clock.advance(0.5)
        XCTAssertTrue(
            progress.isActive(),
            "S-8503 three seconds in, still running — the first reply did not end it"
        )

        clock.advance(1)
        progress.noteArrival(type: "exercises_down", at: clock.call())

        clock.advance(1.9)
        XCTAssertTrue(progress.isActive(), "S-8503 a tenth before the newest batch goes quiet")

        clock.advance(0.1)
        XCTAssertFalse(progress.isActive(), "S-8503 inactive two seconds after the newest batch")
    }

    // MARK: - S-8504 a sync with no reply at all ends at the cap

    func testS8504NoReplyAtAllEndsAtTheCap() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin()

        clock.advance(19.9)
        XCTAssertTrue(progress.isActive(), "S-8504 still running just before the cap")

        clock.advance(0.1)
        XCTAssertFalse(progress.isActive(), "S-8504 inactive at the cap exactly")

        XCTAssertEqual(WatchSyncProgressCopy.capSeconds, 20, "S-8504 the cap is twenty seconds")
    }

    // MARK: - S-8505 a reply other than the routines does not finish the sync

    func testS8505AFoodsReplyAloneCannotSatisfyTheRoutinesGate() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin()

        clock.advance(1)
        progress.noteArrival(type: "foods_down", at: clock.call())

        clock.advance(2)
        XCTAssertTrue(
            progress.isActive(),
            "S-8505 two seconds after a foods reply alone: still waiting for the routines"
        )

        clock.advance(16.9)
        XCTAssertTrue(progress.isActive(), "S-8505 still running just before the cap")

        clock.advance(0.1)
        XCTAssertFalse(progress.isActive(), "S-8505 the cap ends it with the routines missing")
    }

    // MARK: - S-8506 a second begin while running is a no-op; a later one is fresh

    func testS8506BeginWhileRunningContinuesAndAFreshBeginForgets() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin()

        clock.advance(1)
        progress.noteArrival(type: "routines_down", at: clock.call())

        clock.advance(0.5)
        progress.begin()
        clock.advance(1.5)
        XCTAssertFalse(
            progress.isActive(),
            "S-8506 begin while running did not restart the window (it would run until 3.5)"
        )

        progress.begin()
        XCTAssertTrue(progress.isActive(), "S-8506 a begin after it ended starts a fresh sync")

        clock.advance(1)
        progress.noteArrival(type: "exercises_down", at: clock.call())

        clock.advance(3)
        XCTAssertTrue(
            progress.isActive(),
            "S-8506 the earlier routines reply does not finish the fresh sync"
        )

        clock.advance(9)
        XCTAssertTrue(
            progress.isActive(),
            "S-8506 a reply alone does not finish it: the fresh sync still waits for the routines"
        )

        clock.advance(7)
        XCTAssertFalse(progress.isActive(), "S-8506 the fresh sync ends at its own cap")
    }

    // MARK: - S-8507 a message that is not a reply neither ends nor extends it

    func testS8507ANonReplyMessageNeitherEndsNorExtendsTheSync() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin()

        clock.advance(0.5)
        progress.noteArrival(type: "timer_state", at: clock.call())
        clock.advance(0.5)
        XCTAssertTrue(progress.isActive(), "S-8507 a timer state alone does not end it")

        progress.noteArrival(type: "routines_down", at: clock.call())

        clock.advance(1.5)
        progress.noteArrival(type: "timer_state", at: clock.call())
        clock.advance(0.4)
        progress.noteArrival(type: "receipt", at: clock.call())

        clock.advance(0.1)
        XCTAssertFalse(
            progress.isActive(),
            "S-8507 the quiet window runs from the routines reply at 1.0, not the later timer state"
        )
    }

    // MARK: - S-8510 the replies may arrive in any order

    func testS8510RepliesArrivingInAnyOrderEndTheSyncAtTheNewest() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin()

        clock.advance(1)
        progress.noteArrival(type: "exercises_down", at: clock.call())

        clock.advance(2)
        progress.noteArrival(type: "routines_down", at: clock.call())

        clock.advance(1.9)
        XCTAssertTrue(progress.isActive(), "S-8510 a tenth before the newest reply goes quiet")

        clock.advance(0.1)
        XCTAssertFalse(
            progress.isActive(),
            "S-8510 inactive two seconds after the routines reply, which came second"
        )
    }
}
