//
//  WatchRatingSkipTests.swift
//  WatchSessionEngineTests
//
//  S-9610 – S-9613 of
//  `docs/plans/2026-10-23-66a-wrist-workout-summary-and-skip-plan.md`: Skip on
//  the effort question (plan 66a D-3). Skipping records nothing — no row, no
//  event — so the phone still asks and the first real answer still wins. The
//  skip is remembered only while the app runs.
//
//  The harness is the rating suite's: everything built afresh over one store,
//  and a relaunch simulated by restoring new objects over the same storage.
//

import Combine
import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchRatingSkipTests: XCTestCase {
    // MARK: - S-9610

    /// S-9610: skipping an owed prompt closes it without recording anything.
    func testS9610SkipRecordsNothing() async throws {
        let harness = await RatingHarness().launch()
        await harness.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        try await harness.loggedSession(
            start: "2026-09-25T10:00:00Z",
            set: "e-1",
            logged: "2026-09-25T10:05:00Z",
            end: "2026-09-25T10:10:00Z"
        )
        let sid = "s-r-1"
        XCTAssertTrue(harness.rating.isPromptOwed, "S-9610 the question is owed")

        let before = await harness.store.readAll()
        harness.rating.select(3)
        harness.rating.skipPrompt()

        XCTAssertFalse(harness.rating.isPromptOwed, "S-9610 the question is closed")
        XCTAssertTrue(harness.rating.owedSessionIds.isEmpty, "S-9610 nothing is owed")
        XCTAssertNil(harness.rating.selected, "S-9610 nothing stays picked")

        let after = await harness.store.readAll()
        XCTAssertEqual(after.sessions.count, before.sessions.count, "S-9610 no session row")
        XCTAssertEqual(after.observations.count, before.observations.count, "S-9610 no observation row")
        XCTAssertEqual(
            after.ratingPrompts.count, before.ratingPrompts.count,
            "S-9610 no prompt row and none taken back"
        )
        XCTAssertFalse(
            harness.engine.hasEffortRating(sid),
            "S-9610 the session stays unrated"
        )
    }

    // MARK: - S-9611

    /// S-9611: Skip is per session. Skipping the newest asks the older one;
    /// skipping that leaves nothing; a prompt owed later still asks.
    func testS9611SkipIsPerSession() async throws {
        let harness = await RatingHarness(sessionIds: ["s-a", "s-b", "s-c"]).launch()
        await harness.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        try await harness.loggedSession(
            start: "2026-09-25T10:00:00Z",
            set: "e-a",
            logged: "2026-09-25T10:05:00Z",
            end: "2026-09-25T10:10:00Z"
        )
        try await harness.loggedSession(
            start: "2026-09-25T11:00:00Z",
            set: "e-b",
            logged: "2026-09-25T11:05:00Z",
            end: "2026-09-25T11:10:00Z"
        )
        XCTAssertEqual(
            harness.rating.owedSessionIds, ["s-b", "s-a"],
            "S-9611 the newest prompt is asked first"
        )

        harness.rating.skipPrompt()
        XCTAssertEqual(
            harness.rating.promptSessionId, "s-a",
            "S-9611 skipping the newest asks the older one"
        )

        harness.rating.skipPrompt()
        XCTAssertTrue(harness.rating.owedSessionIds.isEmpty, "S-9611 nothing is owed")

        try await harness.loggedSession(
            start: "2026-09-25T12:00:00Z",
            set: "e-c",
            logged: "2026-09-25T12:05:00Z",
            end: "2026-09-25T12:10:00Z"
        )
        XCTAssertEqual(
            harness.rating.promptSessionId, "s-c",
            "S-9611 a prompt owed later still asks: the skip set is by id"
        )
    }

    // MARK: - S-9612

    /// S-9612: Skip keeps the first answer winning. A rating recorded after a
    /// skip is stored; and the skipped prompt returns after a relaunch, because
    /// the skip is remembered only while the app runs (the documented limit).
    func testS9612SkipKeepsTheFirstAnswerWinning() async throws {
        let harness = await RatingHarness().launch()
        await harness.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        try await harness.loggedSession(
            start: "2026-09-25T10:00:00Z",
            set: "e-1",
            logged: "2026-09-25T10:05:00Z",
            end: "2026-09-25T10:10:00Z"
        )
        let sid = "s-r-1"
        harness.rating.skipPrompt()
        XCTAssertFalse(harness.rating.isPromptOwed, "S-9612 the question is closed")

        let recorded = try await harness.engine.recordEffortRating(4, sessionId: sid)
        XCTAssertNotNil(recorded, "S-9612 the answer is recorded")
        XCTAssertTrue(harness.engine.hasEffortRating(sid), "S-9612 the session is rated")

        let stored = await harness.store.readAll()
        let ratingRow = stored.observations.first {
            $0.entryId == WatchSessionCapture.effortRatingId(sid)
        }
        XCTAssertEqual(
            ratingRow?.payload["rating"] as? Int, 4,
            "S-9612 the stored rating is the one the phone sent"
        )
    }

    /// S-9612, the documented limit: the skip is remembered only while the app
    /// runs, so a fresh state over the same store asks the skipped prompt again.
    func testS9612SkippedPromptReturnsAfterRelaunch() async throws {
        let harness = await RatingHarness().launch()
        await harness.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        try await harness.loggedSession(
            start: "2026-09-25T10:00:00Z",
            set: "e-1",
            logged: "2026-09-25T10:05:00Z",
            end: "2026-09-25T10:10:00Z"
        )
        let sid = "s-r-1"
        harness.rating.skipPrompt()
        XCTAssertFalse(harness.rating.isPromptOwed, "S-9612 the question is closed")

        // The documented limit: a fresh state over the same store asks again.
        let relaunched = await RatingHarness(sessionIds: [], store: harness.store).launch()
        XCTAssertEqual(
            relaunched.rating.promptSessionId, sid,
            "S-9612 the skipped prompt returns after a relaunch"
        )
    }

    // MARK: - S-9613

    /// S-9613: Skip with nothing owed does nothing, and a picked number does
    /// not survive a skip — the next owed prompt starts with nothing picked.
    func testS9613SkipWithNothingOwedDoesNothing() async throws {
        let harness = await RatingHarness().launch()
        await harness.sync(true, generatedAt: "2026-09-25T09:00:00Z")

        harness.rating.skipPrompt()
        XCTAssertFalse(harness.rating.isPromptOwed, "S-9613 still nothing owed")
        XCTAssertNil(harness.rating.selected, "S-9613 nothing picked")

        try await harness.loggedSession(
            start: "2026-09-25T10:00:00Z",
            set: "e-1",
            logged: "2026-09-25T10:05:00Z",
            end: "2026-09-25T10:10:00Z"
        )
        XCTAssertTrue(harness.rating.isPromptOwed, "S-9613 the question is owed")

        harness.rating.select(3)
        XCTAssertEqual(harness.rating.selected, 3, "S-9613 the pick is made")
        harness.rating.skipPrompt()
        XCTAssertNil(
            harness.rating.selected,
            "S-9613 the pick does not survive the skip"
        )
    }
}
