//
//  WatchSlotTokenTests.swift
//  WatchSessionEngineTests
//
//  Plan 81: every slot id the wrist mints carries a per-session token —
//  `<base>~<token>`, where the token is the first 8 characters of the live
//  session's id, or of the id the start paths mint when the slots are built
//  before the session exists. Scenarios S-15002, S-15003, S-15004 and S-15010
//  of `docs/plans/2026-10-26-81-wrist-sessions-do-not-share-efforts-plan/…`.
//
//  The tokened expectations are derived from the contract's plain ids
//  (`watch/contract/watch_start_paths_contract.json`), which no phase edits.
//

import XCTest

@testable import WatchSessionEngine

private func slotIds(_ session: WatchSessionRecord) -> [String] {
    session.exercises.compactMap { $0["sessionExerciseId"] as? String }
}

/// One engine and its start paths over a fresh store, with both id sources
/// injected: the session id factory hands out the given values in order, and
/// the start paths' factory counts "alpha-<n>" (each value's first 8
/// characters differ, which is what keeps two sessions' tokens apart).
private final class TokenHarness {
    let store: WatchSessionStore
    private(set) var engine: WatchSessionEngine!
    private(set) var paths: WatchSessionStartPaths!

    init(sessionIds: [String] = ["s-w1", "s-w2"]) {
        self.store = InMemoryWatchSessionStore()

        var sessionQueue = sessionIds
        var engineId = 0
        var pathId = 0
        let engine = WatchSessionEngine(
            store: store,
            onEmit: nil,
            validator: nil,
            clock: { testInstant() },
            idFactory: { engineId += 1; return "rec-\(engineId)" },
            sessionIdFactory: { sessionQueue.isEmpty ? "s-extra" : sessionQueue.removeFirst() }
        )
        paths = WatchSessionStartPaths(
            engine: engine,
            store: store,
            validator: nil,
            clock: { testInstant() },
            idFactory: { pathId += 1; return "alpha-\(pathId)" }
        )
        self.engine = engine
    }

    /// The contract's own `routines_down`: plain slot ids the wrist tokens
    /// when it starts the routine.
    func routinesDown() throws -> [String: Any] {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/contract/watch_start_paths_contract.json")
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "watch_start_paths_contract.json"
        )
        let fallback = try XCTUnwrap(object["fallback"] as? [String: Any])
        return try XCTUnwrap(fallback["routinesDown"] as? [String: Any])
    }
}

final class WatchSlotTokenTests: XCTestCase {

    // MARK: - S-15010 the token helper

    func testS15010SessionTokenTakesTheFirstEightCharacters() {
        XCTAssertEqual(sessionToken(from: "s-w1"), "s-w1", "an id shorter than 8 is used whole")
        XCTAssertEqual(sessionToken(from: "3f2a1b4c-5678-90ab-cdef"), "3f2a1b4c")
        XCTAssertNotEqual(
            sessionToken(from: "s-w1"),
            sessionToken(from: "s-w2"),
            "two short ids still give different tokens"
        )
    }

    // MARK: - S-15004 the base id is unchanged

    func testS15004SlotIdStaysTheBaseAndSlotIdTokenAppendsTheToken() {
        let exercise = WatchCatalogExercise(
            exerciseId: "ex-bench",
            name: "Bench",
            capabilities: ["sets", "reps", "load"]
        )
        XCTAssertEqual(exercise.slotId, "sx-ex-bench", "the base id the menu and picker read")
        XCTAssertEqual(exercise.slotId(token: "ab12cd34"), "sx-ex-bench~ab12cd34")
    }

    /// The menu's fallback: a slot with no own id answers to the exercise's
    /// base id (S-15004).
    func testS15004MenuRowFallsBackToTheBaseIdForASlotWithNoOwnId() {
        let rows = deriveMenuRows(
            sessionExercises: [[
                "exerciseId": "ex-bench",
                "name": "Bench",
                "capabilities": ["sets", "reps", "load"],
            ]],
            entries: [],
            currentIndex: 0
        )
        XCTAssertEqual(rows.map(\.slotId), ["sx-ex-bench"])
    }

    // MARK: - S-15002 the add paths

    func testS15002TwoSessionsOfTheSameExerciseGetDifferentTokens() async throws {
        let harness = TokenHarness()
        let bench = WatchCatalogExercise(
            exerciseId: "ex-bench",
            name: "Bench",
            capabilities: ["sets", "reps", "load"]
        )

        _ = await harness.paths.startFreeWorkout()
        let first = await harness.paths.addExerciseToEnd(bench)
        XCTAssertEqual(slotIds(first), ["sx-ex-bench~s-w1"], "the token is the session's own id")

        _ = await harness.engine.finishSession()

        _ = await harness.paths.startFreeWorkout()
        let second = await harness.paths.addExerciseToEnd(bench)
        XCTAssertEqual(slotIds(second), ["sx-ex-bench~s-w2"])
        XCTAssertNotEqual(slotIds(first), slotIds(second), "the two sessions share no slot id")
    }

    func testS15002TheSameExerciseTwiceInOneSessionGetsMinusTwoBeforeTheToken() async throws {
        let harness = TokenHarness()
        let bench = WatchCatalogExercise(
            exerciseId: "ex-bench",
            name: "Bench",
            capabilities: ["sets", "reps", "load"]
        )

        _ = await harness.paths.startFreeWorkout()
        _ = await harness.paths.addExerciseToEnd(bench)
        let again = await harness.paths.addExerciseToEnd(bench)

        XCTAssertEqual(
            slotIds(again),
            ["sx-ex-bench~s-w1", "sx-ex-bench-2~s-w1"],
            "the -n de-duplication comes before the token; the token is always last"
        )
    }

    // MARK: - S-15003 startFromRoutine

    func testS15003TwoRoutineStartsShareNoSlotIdAndEachCarriesItsOwnToken() async throws {
        let harness = TokenHarness()
        _ = await harness.paths.applyRoutinesDown(try harness.routinesDown())

        let first = try await harness.paths.startFromRoutine("routine-push-a")
        // The create branch builds the slots before the session exists, so the
        // token comes from the id factory: the routines_down sync took
        // "alpha-1", the start mints "alpha-2" (plan 81 D-9).
        XCTAssertEqual(
            slotIds(first),
            ["sx-eff-bench~alpha-2", "sx-eff-plank~alpha-2", "sx-eff-pullup~alpha-2"]
        )

        _ = await harness.engine.finishSession()

        let second = try await harness.paths.startFromRoutine("routine-push-a")
        XCTAssertEqual(
            slotIds(second),
            ["sx-eff-bench~alpha-3", "sx-eff-plank~alpha-3", "sx-eff-pullup~alpha-3"]
        )
        XCTAssertTrue(
            Set(slotIds(first)).isDisjoint(with: Set(slotIds(second))),
            "the two sessions have no slot id in common"
        )
        XCTAssertTrue(
            slotIds(second).allSatisfy { $0.hasPrefix("sx-eff-") && $0.contains("~") },
            "each slot id starts with the effort's own base"
        )
    }

    func testS15003FillInPlaceUsesTheLiveSessionToken() async throws {
        let harness = TokenHarness()
        _ = await harness.paths.applyRoutinesDown(try harness.routinesDown())

        let empty = await harness.paths.startFreeWorkout()
        let filled = try await harness.paths.startFromRoutine("routine-push-a")

        XCTAssertEqual(filled.sessionId, empty.sessionId, "the routine fills the live session")
        XCTAssertEqual(
            slotIds(filled),
            ["sx-eff-bench~s-w1", "sx-eff-plank~s-w1", "sx-eff-pullup~s-w1"],
            "the token is the live session's own id"
        )
    }
}
