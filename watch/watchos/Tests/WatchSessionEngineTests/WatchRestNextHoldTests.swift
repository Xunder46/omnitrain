//
//  WatchRestNextHoldTests.swift
//  WatchSessionEngineTests
//
//  A second hold must land on the exercise the screen shows. The rest screen's
//  one Next button ends the rest and, when the next line names an exercise,
//  moves the session there; the logger that comes back must be that exercise's,
//  and the next Log must write to it. Holds carry no planned count on the wire
//  (`plannedSets` is sent for set efforts only), so a hold exercise with one hold
//  logged is "done" and Next names the next not-done exercise.
//
//  Also the out-of-order rules: logging an exercise reached from the list counts
//  against that exercise's own slot, and Next names the first not-done exercise
//  after the one just logged, then from the top.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

private func holdSlot(_ id: String, _ name: String) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": name,
        "capabilities": ["hold", "time"],
    ]
}

private func plannedSetSlot(_ id: String, _ name: String, planned: Int) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": name,
        "capabilities": ["reps", "sets", "load"],
        "plannedSets": (0..<planned).map { _ in ["reps": 10] },
    ]
}

@MainActor
final class WatchRestNextHoldTests: XCTestCase {

    /// A wrist on a ladder of four hold exercises (Plank, Wall Sit, Bridge, Hollow),
    /// sitting on the first.
    private func holdLadder() async -> (FocusHarness, WatchLoggingState) {
        let harness = await FocusHarness().launch()
        _ = await harness.engine.createSession(
            modality: "isometric_stretching",
            exercises: [
                holdSlot("A", "Plank"), holdSlot("B", "Wall Sit"),
                holdSlot("C", "Bridge"), holdSlot("D", "Hollow"),
            ]
        )
        let state = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)
        return (harness, state)
    }

    /// One hold on whatever exercise the surface is on: Start, hold, Log. Returns
    /// the slot the entry was written to.
    @discardableResult
    private func logHold(_ harness: FocusHarness, _ state: WatchLoggingState) async throws -> String {
        await state.startWork()
        harness.clock.advance(30)
        let stored = try await state.log()
        return try XCTUnwrap(stored.payload["sessionExerciseId"] as? String)
    }

    /// Logs one hold and checks which slot it was written to.
    private func expectHold(
        _ harness: FocusHarness, _ state: WatchLoggingState, on slotId: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let written = try await logHold(harness, state)
        XCTAssertEqual(written, slotId, file: file, line: line)
    }

    private func currentSlotId(_ harness: FocusHarness) -> String? {
        harness.menu.rows.first { $0.isCurrent }?.slotId
    }

    private func loggedCount(_ harness: FocusHarness, _ slotId: String) -> Int {
        harness.menu.rows.first { $0.slotId == slotId }?.loggedCount ?? -1
    }

    // MARK: - Next and the next log

    func testNextMovesTheSessionBeforeTheRestSurfaceIsReleased() async throws {
        let (harness, state) = await holdLadder()
        try await logHold(harness, state)
        XCTAssertEqual(state.restLabels.nextSlotId, "B", "a hold has no plan, so Plank is done")

        var restWasStillUpWhenTheSessionMoved: Bool?
        let moved = await state.leaveRest { target in
            // The shell swaps the rest surface for the logger the instant the
            // rest is over; the session must already be on the target then, or
            // the logger is built on the exercise the user just left.
            restWasStillUpWhenTheSessionMoved = state.isResting
            return await harness.menu.jump(to: target)
        }

        XCTAssertEqual(moved, "B")
        XCTAssertEqual(
            restWasStillUpWhenTheSessionMoved,
            true,
            "the rest surface must still be up while the session moves, so no logger is built on the old exercise"
        )
        XCTAssertFalse(state.isResting)
    }

    func testTheLoggerAfterNextAndTheNextLogAreTheSameExercise() async throws {
        let (harness, state) = await holdLadder()
        try await logHold(harness, state)

        await state.leaveRest { await harness.menu.jump(to: $0) }

        XCTAssertEqual(state.exerciseName, "Wall Sit", "the logger shows the announced exercise")
        XCTAssertEqual(currentSlotId(harness), "B", "the pager's page is the announced exercise")
        let written = try await logHold(harness, state)
        XCTAssertEqual(written, "B", "the log lands on the exercise on screen")
        XCTAssertEqual(loggedCount(harness, "A"), 1)
        XCTAssertEqual(loggedCount(harness, "B"), 1)
    }

    func testARefusedMoveLeavesTheScreenAndTheLogOnTheSameExercise() async throws {
        let (harness, state) = await holdLadder()
        try await logHold(harness, state)

        let moved = await state.leaveRest { _ in false }

        XCTAssertNil(moved)
        XCTAssertEqual(state.exerciseName, "Plank")
        let written = try await logHold(harness, state)
        XCTAssertEqual(written, "A", "no move, so the next hold is the same exercise's second")
        XCTAssertEqual(loggedCount(harness, "A"), 2)
    }

    func testASetWithSetsLeftStaysOnItsExerciseAfterNext() async throws {
        let harness = await FocusHarness().launch()
        _ = await harness.engine.createSession(
            modality: "resistance_lifting",
            exercises: [plannedSetSlot("A", "Squat", planned: 3), plannedSetSlot("B", "Bench", planned: 3)]
        )
        let state = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)
        try await state.log()
        XCTAssertEqual(state.restLabels.next, "Next: Set 2 of 3")

        var advanced = false
        let moved = await state.leaveRest { _ in advanced = true; return true }

        XCTAssertNil(moved)
        XCTAssertFalse(advanced, "a set with sets left names no exercise to move to")
        let written = try await state.log()
        XCTAssertEqual(written.payload["sessionExerciseId"] as? String, "A")
    }

    // MARK: - Out of order

    func testLoggingOutOfOrderCountsPerSlotAndNextGoesForwardFromTheLoggedOne() async throws {
        let (harness, state) = await holdLadder()

        // Jump to C from the list and log it.
        await harness.menu.jump(to: "C")
        try await expectHold(harness, state, on: "C")
        // Back to A from the list (the rest is still running), log it.
        await harness.menu.jump(to: "A")
        await state.endRest()
        try await expectHold(harness, state, on: "A")

        // Forward from A: B is the first not-done exercise (C is done).
        XCTAssertEqual(state.restLabels.now, "Plank")
        XCTAssertEqual(state.restLabels.nextSlotId, "B")
        await state.leaveRest { await harness.menu.jump(to: $0) }
        try await expectHold(harness, state, on: "B")

        // Forward from B: C is done, so D.
        XCTAssertEqual(state.restLabels.nextSlotId, "D")
        await state.leaveRest { await harness.menu.jump(to: $0) }
        try await expectHold(harness, state, on: "D")

        // Everything is logged once: nothing is left to announce.
        XCTAssertNil(state.restLabels.nextSlotId)
        XCTAssertEqual(state.restLabels.next, WatchRestLabelCopy.nothingNext)
        for id in ["A", "B", "C", "D"] {
            XCTAssertEqual(loggedCount(harness, id), 1, "\(id) holds exactly its own entry")
        }
        let perSlot = Dictionary(grouping: harness.engine.entries) {
            $0.payload["sessionExerciseId"] as? String ?? ""
        }
        XCTAssertEqual(perSlot.mapValues(\.count), ["A": 1, "B": 1, "C": 1, "D": 1])
    }

    func testNextWrapsToTheTopWhenNothingIsLeftAfterTheLoggedExercise() async throws {
        let (harness, state) = await holdLadder()

        await harness.menu.jump(to: "D")
        try await expectHold(harness, state, on: "D")
        // D is last: nothing after it, so the search wraps to the top.
        XCTAssertEqual(state.restLabels.nextSlotId, "A")

        await harness.menu.jump(to: "B")
        await state.endRest()
        try await expectHold(harness, state, on: "B")
        // After B: C is the first not-done exercise.
        XCTAssertEqual(state.restLabels.nextSlotId, "C")

        await harness.menu.jump(to: "C")
        await state.endRest()
        try await expectHold(harness, state, on: "C")
        // After C: D is done, so the search wraps to A (B is done too).
        XCTAssertEqual(state.restLabels.nextSlotId, "A")
        XCTAssertEqual(state.restLabels.next, "Next: Plank")
    }

    // MARK: - The watch-only views stay on the same rule

    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testTheRestSurfaceLeavesThroughTheOneOrderedStep() throws {
        let source = try engineSource("WatchRestView.swift")
        XCTAssertTrue(source.contains("state.leaveRest(advance: advance)"))
        XCTAssertFalse(
            source.contains("state.endRest()"),
            "the view never ends the rest itself: that would release the logger before the session moves"
        )
    }

    func testThePagerShowsTheEnginesPageUnlessASwipeIsLanding() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")
        XCTAssertTrue(source.contains("state.focusSlotId != nil ? selection : pager.currentIndex"))
        XCTAssertTrue(source.contains("pager.rows[shownIndex].slotId"), "the logger's identity is the page shown")
        XCTAssertTrue(source.contains("\\(shownIndex + 1)/\\(pager.pageCount)"), "so is its counter")
        XCTAssertFalse(
            source.contains("pager.rows[selection].slotId"),
            "the logger is never keyed on the swipe's bookkeeping alone"
        )
    }
}
