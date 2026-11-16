//
//  WatchRestNextHoldTests.swift
//  WatchSessionEngineTests
//
//  A second hold must land on the exercise the screen shows. The rest screen's
//  one Next button ends the rest and, when the next line names an exercise,
//  moves the session there; the logger that comes back must be that exercise's,
//  and the next Log must write to it. A hold may now carry a planned count: the
//  phone sends it as `plannedEfforts` (plan 149 PR 1) and plan 149 PR 2 counts
//  it per kind. This file's fixtures carry no plan — the no-plan world, where a
//  hold exercise with one hold logged is "done" and Next names the next not-done
//  exercise; the planned half is asserted below in the plan 149 cases.
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

/// A hold slot carrying the phone's plan for it (plan 149 PR 1's wire).
private func plannedHoldSlot(_ id: String, _ name: String, plannedEfforts: Int) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": name,
        "capabilities": ["hold", "time"],
        "plannedEfforts": plannedEfforts,
    ]
}

/// A round slot carrying the phone's plan: how many periods it holds.
private func roundSlot(_ id: String, _ name: String, plannedEfforts: Int) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": name,
        "capabilities": ["time", "rounds"],
        "effortKind": WatchEffortKind.round,
        "plannedEfforts": plannedEfforts,
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
        XCTAssertEqual(state.restLabels.next, "Next set: Set 2 of 3")

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

        // Everything is logged once: the list starts over (plan 201, D-20101).
        XCTAssertEqual(state.restLabels.nextSlotId, "A")
        XCTAssertEqual(state.restLabels.next, "Next exercise: Plank")
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
        XCTAssertEqual(state.restLabels.next, "Next exercise: Plank")
    }

    func testS20105TheListStartsOverAfterTheLastExerciseAndKeepsCycling() async throws {
        let (harness, state) = await holdLadder()

        try await expectHold(harness, state, on: "A")
        await harness.menu.jump(to: "B")
        await state.endRest()
        try await expectHold(harness, state, on: "B")
        await harness.menu.jump(to: "C")
        await state.endRest()
        try await expectHold(harness, state, on: "C")
        await harness.menu.jump(to: "D")
        await state.endRest()
        try await expectHold(harness, state, on: "D")

        // The last exercise is followed by the first (plan 201, D-20101).
        XCTAssertEqual(state.restLabels.nextSlotId, "A")
        await state.leaveRest { await harness.menu.jump(to: $0) }
        XCTAssertEqual(currentSlotId(harness), "A", "S-20105 the session moves back to the top")

        try await expectHold(harness, state, on: "A")
        XCTAssertEqual(loggedCount(harness, "A"), 2, "S-20105 the second hold lands on A")
        XCTAssertEqual(loggedCount(harness, "B"), 1, "S-20105 B holds exactly its own entry")
        XCTAssertEqual(loggedCount(harness, "C"), 1, "S-20105 C holds exactly its own entry")
        XCTAssertEqual(loggedCount(harness, "D"), 1, "S-20105 D holds exactly its own entry")
        XCTAssertEqual(
            state.restLabels.nextSlotId,
            "B",
            "S-20105 the cycle goes on from A"
        )
    }

    // MARK: - Plan 149 PR 2: a planned amount on the wrist

    /// A planned-hold ladder: A plans 3 holds, B plans 2, and the surface starts
    /// on A.
    private func plannedLadder() async -> (FocusHarness, WatchLoggingState) {
        let harness = await FocusHarness().launch()
        _ = await harness.engine.createSession(
            modality: "isometric_stretching",
            exercises: [
                plannedHoldSlot("A", "Plank", plannedEfforts: 3),
                plannedHoldSlot("B", "Wall Sit", plannedEfforts: 2),
            ]
        )
        let state = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)
        return (harness, state)
    }

    func testS14921APlannedRoundMovesOnWhenItsPlanIsMet() async throws {
        let harness = await FocusHarness().launch()
        _ = await harness.engine.createSession(
            modality: "sports",
            exercises: [
                roundSlot("A", "Sports Drill", plannedEfforts: 3),
                plannedSetSlot("B", "Bench", planned: 2),
            ]
        )
        let state = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        await logRound(harness, state)
        XCTAssertEqual(
            state.restLabels.next,
            "Next set: Period 2 of 3",
            "S-14921 a planned round stays with its count, not today's unbounded line"
        )
        XCTAssertNil(state.restLabels.nextSlotId, "S-14921 the plan is not met, so the round stays")

        await logRound(harness, state)
        XCTAssertEqual(state.restLabels.next, "Next set: Period 3 of 3")

        await logRound(harness, state)
        XCTAssertEqual(
            state.restLabels.next,
            "Next exercise: Bench · Set 1 of 2",
            "S-14921 the plan met, the planned round moves on — the wedge is gone"
        )
        XCTAssertEqual(state.restLabels.nextSlotId, "B")
    }

    func testS14924AFourthPlannedHoldIsAccepted() async throws {
        let (harness, state) = await plannedLadder()

        for _ in 0..<3 {
            try await expectHold(harness, state, on: "A")
        }
        XCTAssertEqual(state.restLabels.next, "Next exercise: Wall Sit · Hold 1 of 2")

        // Past the plan the wrist still logs: the fourth hold is the user's, not
        // an error (P-2).
        await state.endRest()
        try await expectHold(harness, state, on: "A")
        XCTAssertEqual(loggedCount(harness, "A"), 4, "S-14924 the fourth hold is accepted")
        XCTAssertEqual(
            state.restLabels.next,
            "Next exercise: Wall Sit · Hold 1 of 2",
            "S-14924 four holds are at least the plan of three, so the line moves on"
        )
        XCTAssertEqual(state.restLabels.nextSlotId, "B")
        XCTAssertFalse(state.restLabels.next.contains("4 of 3"), "S-14924 no count prints past its plan")
    }

    func testS14925APlannedLadderCountsOutOfOrderPerSlot() async throws {
        let harness = await FocusHarness().launch()
        _ = await harness.engine.createSession(
            modality: "isometric_stretching",
            exercises: [
                plannedHoldSlot("A", "Plank", plannedEfforts: 2),
                plannedHoldSlot("B", "Wall Sit", plannedEfforts: 2),
                plannedHoldSlot("C", "Bridge", plannedEfforts: 2),
            ]
        )
        let state = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        await harness.menu.jump(to: "C")
        try await expectHold(harness, state, on: "C")
        XCTAssertEqual(state.restLabels.next, "Next set: Hold 2 of 2", "S-14925 C's own count is one")

        await harness.menu.jump(to: "A")
        await state.endRest()
        try await expectHold(harness, state, on: "A")
        XCTAssertEqual(
            state.restLabels.next,
            "Next set: Hold 2 of 2",
            "S-14925 C's hold never completes A's plan"
        )
        XCTAssertNil(state.restLabels.nextSlotId, "S-14925 A is short of its plan, so Next stays")

        await state.endRest()
        try await expectHold(harness, state, on: "A")
        XCTAssertEqual(
            state.restLabels.next,
            "Next exercise: Wall Sit · Hold 1 of 2",
            "S-14925 B's own logged count is zero, so the move line reads k = 1"
        )
        XCTAssertEqual(state.restLabels.nextSlotId, "B")
    }

    func testS14926NoPlanKeepsTodaysRule() async throws {
        let (harness, state) = await holdLadder()

        try await logHold(harness, state)

        XCTAssertEqual(
            state.restLabels.next,
            "Next exercise: Wall Sit",
            "S-14926 a hold with no plan is done after one effort and the line moves"
        )
        XCTAssertEqual(state.restLabels.nextSlotId, "B")
    }

    func testS14927TheSameFrameAppliedTwiceChangesNothing() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let frame = plannedEffortSnapshot(
            messageId: "msg-149b-repeat",
            exercises: [
                plannedHoldSlot("A", "Plank", plannedEfforts: 3),
                plannedHoldSlot("B", "Wall Sit", plannedEfforts: 2),
            ],
            entries: [holdEntry("entry-A-0", slot: "A")]
        )
        XCTAssertTrue(
            Harness.validator().validateEnvelope(frame).isEmpty,
            "\(Harness.validator().validateEnvelope(frame))"
        )
        _ = try await engine.applyMessage(frame)

        let state = WatchLoggingState(engine: engine, clock: harness.clock.call)
        let first = state.restLabels
        XCTAssertEqual(first.next, "Next set: Hold 2 of 3", "S-14927 the imported hold counts")
        XCTAssertNil(first.nextSlotId)
        let entriesBefore = engine.entries.count

        _ = try await engine.applyMessage(frame)

        XCTAssertEqual(state.restLabels, first, "S-14927 the same frame twice changes nothing")
        let entriesAfter = engine.entries.count
        XCTAssertEqual(entriesAfter, entriesBefore, "S-14927 and adds no entry")
        let exercises = engine.session?.exercises ?? []
        XCTAssertEqual(
            exercises.first.flatMap { $0["plannedEfforts"] as? Int },
            3,
            "S-14927 the plan is still the phone's"
        )
    }

    /// One round on whatever exercise the surface is on: Start, run, Log.
    private func logRound(_ harness: FocusHarness, _ state: WatchLoggingState) async {
        await state.startWork()
        harness.clock.advance(30)
        _ = try? await state.log()
    }

    /// A phone frame carrying planned efforts, as PR 1's schema declares them.
    private func plannedEffortSnapshot(
        messageId: String,
        revision: Int = 1,
        exercises: [[String: Any]],
        entries: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": "s-next",
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-11-12T18:00:00Z",
            "payload": [
                "sessionId": "s-next",
                "revision": revision,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 0,
                "exercises": exercises,
                "entries": entries,
                "timers": [String: Any](),
            ] as [String: Any],
        ]
    }

    /// One hold entry as a phone frame carries it.
    private func holdEntry(_ entryId: String, slot: String) -> [String: Any] {
        [
            "entryId": entryId,
            "eventId": entryId,
            "kind": WatchObservationKind.hold,
            "loggedAt": "2026-11-12T17:59:00Z",
            "sessionExerciseId": slot,
            "exerciseId": "ex-\(slot)",
        ]
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
