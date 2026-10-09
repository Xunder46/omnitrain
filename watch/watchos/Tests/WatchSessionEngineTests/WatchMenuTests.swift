//
//  WatchMenuTests.swift
//  WatchSessionEngineTests
//
//  S-1100 to S-1113 of
//  `docs/plans/2026-10-09-20-watch-menu-plan/2026-10-09-20-watch-menu-plan.md`:
//  the session menu's derived rows and its two actions, proven on the desktop
//  toolchain. The wrist's view over them is Phase 2, compiled only by the watch
//  scheme build.
//
//  S-1200 to S-1202 of
//  `docs/plans/2026-10-09-20b-watch-menu-session-only-plan/2026-10-09-20b-watch-menu-session-only-plan.md`:
//  the menu is the session and nothing else, and it reaches for no catalog.
//
//  Fixture A is the register's three-slot ladder: two live efforts on `s1`, none
//  on `s2`, one on `s3`, and a fourth `s1` effort the phone deleted.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// One slot of a menu fixture ladder.
private func menuSlot(_ id: String, _ name: String) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": name,
        "capabilities": ["reps", "sets", "load"],
    ]
}

/// One stored observation of a menu fixture. A rest carries the `afterEntryId`
/// the register names; work kinds carry the set's metrics.
private func menuEntry(
    _ entryId: String,
    slot: String,
    at loggedAt: String,
    kind: String = WatchObservationKind.set,
    afterEntryId: String? = nil
) -> StoredWatchRecord {
    var payload: [String: Any] = [
        "entryId": entryId,
        "eventId": entryId,
        "kind": kind,
        "loggedAt": loggedAt,
        "sessionExerciseId": slot,
        "exerciseId": "ex-\(slot)",
    ]
    if kind == WatchObservationKind.set {
        payload["reps"] = 5
        payload["loadKg"] = 80
    }
    if let afterEntryId { payload["afterEntryId"] = afterEntryId }
    return .observation(
        WatchObservationRecord(
            recordId: entryId,
            sessionId: "s-menu",
            recordedAt: instant(loggedAt),
            kind: kind,
            payload: payload
        )
    )
}

/// A wrist with one engine, its start paths, the phone's preferences, the
/// rating state and the menu over them — the shape of `WatchStartHarness` and
/// `RatingHarness`, over one store so a fixture and an action see the same rows.
final class WatchMenuHarness {
    let clock: TestClock
    let store: WatchSessionStore
    let sessionId = "s-menu"

    private(set) var engine: WatchSessionEngine!
    private(set) var paths: WatchSessionStartPaths!
    private(set) var preferences: WatchPhonePreferences!
    private(set) var rating: WatchEffortRatingState!
    private(set) var menu: WatchMenuState!

    init(store: WatchSessionStore = InMemoryWatchSessionStore()) {
        clock = TestClock(instant("2026-07-13T06:00:00Z"))
        self.store = store
    }

    /// A wrist that has restored, with the menu over the same objects.
    @discardableResult
    func launch() async -> WatchMenuHarness {
        var ids = 0
        func nextId(_ prefix: String) -> String {
            ids += 1
            return "\(prefix)-\(ids)"
        }

        engine = WatchSessionEngine(
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { nextId("rec") },
            sessionIdFactory: { [sessionId] in sessionId }
        )
        paths = WatchSessionStartPaths(
            engine: engine,
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { nextId("cat") }
        )
        preferences = WatchPhonePreferences(
            store: store,
            validator: Harness.validator(),
            clock: clock.call
        )
        rating = WatchEffortRatingState(
            engine: engine,
            store: store,
            preferences: preferences,
            clock: clock.call
        )
        menu = WatchMenuState(engine: engine, paths: paths, rating: rating)

        await engine.restore()
        await paths.restore()
        await preferences.restore()
        await rating.restore()
        return self
    }

    /// Fixture A, appended to storage and restored the way a relaunch would.
    @discardableResult
    func fixtureA() async -> WatchMenuHarness {
        let at = instant("2026-07-13T06:00:00Z")
        _ = await store.append(
            .session(
                WatchSessionRecord(
                    recordId: "menu-row-1",
                    sessionId: sessionId,
                    recordedAt: at,
                    startedAt: at,
                    modality: nil,
                    source: "watch",
                    status: WatchSessionStatus.active,
                    currentExerciseIndex: 1,
                    exercises: [
                        menuSlot("s1", "Squat"),
                        menuSlot("s2", "Bench Press"),
                        menuSlot("s3", "Row"),
                    ],
                    deletedEntryIds: ["e-s1-deleted"]
                )
            )
        )
        _ = await store.append(menuEntry("e-s1-1", slot: "s1", at: "2026-07-13T06:01:00Z"))
        _ = await store.append(menuEntry("e-s1-2", slot: "s1", at: "2026-07-13T06:03:00Z"))
        _ = await store.append(menuEntry("e-s3-1", slot: "s3", at: "2026-07-13T06:05:00Z"))
        _ = await store.append(menuEntry("e-s1-deleted", slot: "s1", at: "2026-07-13T06:07:00Z"))
        await engine.restore()
        return self
    }

    /// The phone's fallback list, of which the menu must show nothing. Squat is
    /// on the ladder; Pull-up and Dip are not.
    @discardableResult
    func applyFallbackCatalog() async -> WatchMenuHarness {
        _ = await store.append(
            .routineCatalog(
                WatchRoutineCatalogRecord(
                    recordId: "cat-menu-1",
                    recordedAt: instant("2026-07-13T06:00:00Z"),
                    generatedAt: instant("2026-07-13T06:00:00Z"),
                    fallbackExercises: [
                        ["exerciseId": "ex-s1", "name": "Squat", "capabilities": ["reps"]],
                        ["exerciseId": "ex-pullup", "name": "Pull-up", "capabilities": ["reps"]],
                        ["exerciseId": "ex-dip", "name": "Dip", "capabilities": ["reps"]],
                    ]
                )
            )
        )
        await paths.restore()
        return self
    }

    /// The phone's setting arriving at a wrist sync.
    func syncRatingPrompt(_ asks: Bool) async {
        _ = await preferences.applyPreferencesDown(
            preferencesDown(asks, generatedAt: "2026-07-13T06:10:00Z")
        )
    }
}

/// One `session_snapshot` from the phone over the fixture's session, carrying
/// one entry so a correction can be applied to a held id.
private func menuSnapshot(
    messageId: String,
    sessionId: String,
    entry: [String: Any]
) -> [String: Any] {
    [
        "protocolVersion": SyncProtocolValidator.protocolVersion,
        "messageId": messageId,
        "sessionId": sessionId,
        "type": "session_snapshot",
        "origin": "phone",
        "sentAt": "2026-07-13T06:30:00Z",
        "payload": [
            "sessionId": sessionId,
            "revision": 1,
            "status": WatchSessionStatus.active,
            "currentExerciseIndex": 1,
            "exercises": [
                menuSlot("s1", "Squat"),
                menuSlot("s2", "Bench Press"),
                menuSlot("s3", "Row"),
            ],
            "entries": [entry],
            "timers": [String: Any](),
        ] as [String: Any],
    ]
}

final class WatchMenuTests: XCTestCase {

    // MARK: - S-1100 the derived rows

    func testS1100MenuRowsCarryNameCountAndCurrent() async {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()

        let rows = harness.menu.rows

        XCTAssertEqual(rows.map(\.slotId), ["s1", "s2", "s3"], "S-1100 the rows key by the slot's sessionExerciseId")
        XCTAssertEqual(rows.map(\.name), ["Squat", "Bench Press", "Row"], "S-1100 the rows follow the ladder's order")
        XCTAssertEqual(
            rows.map(\.loggedCount),
            [2, 0, 1],
            "S-1100 the deleted s1 entry is not counted: 2 on Squat, 0 on Bench Press, 1 on Row"
        )
        XCTAssertEqual(
            rows.map(\.countLabel),
            ["2 logged", nil, "1 logged"],
            "S-1100 a slot with no effort says nothing rather than \"0 logged\""
        )
        XCTAssertEqual(rows.map(\.isCurrent), [false, true, false], "S-1100 exactly one row is current")
    }

    // MARK: - S-1101 / S-1110 / S-1111 the derivation's edges

    func testS1101EmptyLadderAndNamelessSlot() {
        XCTAssertEqual(
            deriveMenuRows(sessionExercises: [], entries: [], currentIndex: 0),
            [],
            "S-1101 an empty ladder has no rows"
        )

        let rows = deriveMenuRows(
            sessionExercises: [["sessionExerciseId": "s1"], menuSlot("s2", "Bench Press")],
            entries: [],
            currentIndex: 0
        )
        XCTAssertEqual(
            rows.map(\.name),
            ["Bench Press"],
            "S-1101 a slot with no name is skipped, and the others keep their order"
        )
    }

    func testS1102OutOfRangeIndexMarksTheLastRow() async {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()

        let rows = deriveMenuRows(
            sessionExercises: harness.engine.session?.exercises ?? [],
            entries: harness.engine.entries,
            currentIndex: 7
        )
        XCTAssertEqual(rows.map(\.isCurrent), [false, false, true], "S-1102 the clamp puts the mark on the last row")
    }

    func testS1110ARestIsNotACountedEffort() async {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        _ = await harness.store.append(
            menuEntry(
                "e-s1-rest",
                slot: "s1",
                at: "2026-07-13T06:02:00Z",
                kind: WatchObservationKind.rest,
                afterEntryId: "e-s1-1"
            )
        )
        await harness.engine.restore()

        let rows = harness.menu.rows
        XCTAssertEqual(
            rows.map(\.loggedCount),
            [2, 0, 1],
            "S-1110 a rest on Squat is not work in the slot, so Squat still reads 2"
        )
    }

    func testS1111ASkippedSlotDoesNotShiftTheMark() {
        let rows = deriveMenuRows(
            sessionExercises: [
                ["sessionExerciseId": "s1"],
                menuSlot("s2", "Bench Press"),
                menuSlot("s3", "Row"),
            ],
            entries: [],
            currentIndex: 2
        )

        XCTAssertEqual(rows.map(\.name), ["Bench Press", "Row"], "S-1111 the nameless slot is skipped")
        XCTAssertEqual(
            rows.map(\.isCurrent),
            [false, true],
            "S-1111 the mark rides the ladder index, so the skipped slot shifts nothing"
        )
    }

    func testS1112MenuRowsAreDerivedOnEveryRead() async {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()

        XCTAssertEqual(harness.menu.rows.count, 3, "S-1112 the menu starts with the ladder's three slots")

        _ = await harness.engine.insertExercise(menuSlot("s4", "Dip"), moveTo: false)

        let rows = harness.menu.rows
        XCTAssertEqual(rows.count, 4, "S-1112 a slot added after the first read is in the list the user sees")
        XCTAssertEqual(rows.last?.name, "Dip", "S-1112 the new slot is the last row")
        XCTAssertEqual(rows.last?.isCurrent, false, "S-1112 and it is not the session's position")
    }

    func testS1109MenuCountsReadTheCorrectedProjection() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()

        _ = try await harness.engine.applyMessage(
            menuSnapshot(
                messageId: "msg-menu-correct-s1",
                sessionId: harness.sessionId,
                entry: [
                    "entryId": "e-s1-1",
                    "eventId": "e-s1-1",
                    "kind": WatchObservationKind.set,
                    "loggedAt": "2026-07-13T06:01:00Z",
                    "sessionExerciseId": "s3",
                    "exerciseId": "ex-s3",
                    "reps": 5,
                    "loadKg": 80,
                ]
            )
        )

        let rows = harness.menu.rows
        XCTAssertEqual(
            rows.map(\.loggedCount),
            [1, 0, 2],
            "S-1109 the phone's correction moves the entry's count to the slot it now names"
        )
    }

    // MARK: - S-1103 / S-1104 the jump

    func testS1103JumpMovesTheSessionAndLogsNothing() async {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        let beforeIds = harness.engine.entries.map(\.recordId)
        let beforeSequences = harness.engine.entries.map(\.sequence)
        let beforeRevision = harness.engine.session?.revision

        let moved = await harness.menu.jump(to: "s3")

        XCTAssertTrue(moved, "S-1103 the jump finds the slot on the ladder")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 2, "S-1103 the session moves to Row")
        XCTAssertEqual(
            WatchLoggingState(engine: harness.engine).exerciseName,
            "Row",
            "S-1103 the logging surface shows the exercise the jump landed on"
        )
        XCTAssertEqual(
            harness.engine.entries.map(\.recordId),
            beforeIds,
            "S-1103 a jump appends no observation"
        )
        XCTAssertEqual(
            harness.engine.entries.map(\.sequence),
            beforeSequences,
            "S-1103 and rewrites no entry's sequence"
        )
        XCTAssertEqual(harness.engine.session?.revision, beforeRevision, "S-1103 a jump is not a structure change")
        XCTAssertEqual(harness.engine.session?.exercises.count, 3, "S-1103 the ladder is untouched")
    }

    func testS1104JumpToAVanishedSlotChangesNothing() async {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()

        let moved = await harness.menu.jump(to: "s-gone")

        XCTAssertFalse(moved, "S-1104 a slot the session does not hold finds no row")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 1, "S-1104 the session stays where it was")
    }

    // MARK: - S-1200 / S-1201 the menu is the session alone

    func testS1200MenuRowsNeverReadTheFallbackCatalog() async {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        await harness.applyFallbackCatalog()

        XCTAssertEqual(
            harness.menu.rows.map(\.name),
            ["Squat", "Bench Press", "Row"],
            "S-1200 the fallback catalog's Pull-up and Dip stay out of the menu"
        )
    }

    func testS1201OneRowPerExerciseWhateverItsEffortCount() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        _ = await harness.store.append(menuEntry("e-s3-2", slot: "s3", at: "2026-07-13T06:06:00Z"))
        _ = await harness.store.append(menuEntry("e-s3-3", slot: "s3", at: "2026-07-13T06:07:00Z"))
        _ = await harness.store.append(menuEntry("e-s3-4", slot: "s3", at: "2026-07-13T06:08:00Z"))
        await harness.engine.restore()

        let rows = harness.menu.rows
        XCTAssertEqual(rows.count, 3, "S-1201 four efforts on Row still make one row")
        XCTAssertEqual(
            Set(rows.map(\.slotId)).count,
            rows.count,
            "S-1201 no slot id repeats, so no effort gets a row of its own"
        )
        let row = try XCTUnwrap(rows.first { $0.slotId == "s3" })
        XCTAssertEqual(row.loggedCount, 4, "S-1201 the row counts all four of Row's efforts")
        XCTAssertEqual(row.countLabel, "4 logged", "S-1201 the row says how many, not which set")
    }

    // MARK: - S-1107 / S-1113 Finish

    func testS1107FinishEndsAndOwesTheRating() async {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        await harness.syncRatingPrompt(true)

        await harness.menu.finish()

        XCTAssertEqual(
            harness.engine.session?.status,
            WatchSessionStatus.completed,
            "S-1107 Finish closes the session"
        )
        XCTAssertTrue(
            harness.rating.isPromptOwed,
            "S-1107 with the setting on and efforts logged, Finish owes the rating"
        )

        let quiet = await WatchMenuHarness().launch()
        await quiet.fixtureA()

        await quiet.menu.finish()

        XCTAssertEqual(
            quiet.engine.session?.status,
            WatchSessionStatus.completed,
            "S-1107 with no rating owed the session still finishes"
        )
        XCTAssertFalse(quiet.rating.isPromptOwed, "S-1107 and nothing prompts")
    }

    func testS1113FinishLeavesNothingToLogInto() async {
        let owing = await WatchMenuHarness().launch()
        await owing.fixtureA()
        await owing.syncRatingPrompt(true)

        await owing.menu.finish()

        XCTAssertEqual(owing.engine.session?.status, WatchSessionStatus.completed, "S-1113 the session is completed")
        XCTAssertTrue(owing.rating.isPromptOwed, "S-1113 a rating is owed, so the shell renders the prompt alone")
        XCTAssertNotEqual(
            owing.engine.session?.status,
            WatchSessionStatus.active,
            "S-1113 the logging branch's own test is false"
        )

        let quiet = await WatchMenuHarness().launch()
        await quiet.fixtureA()

        await quiet.menu.finish()

        XCTAssertEqual(quiet.engine.session?.status, WatchSessionStatus.completed, "S-1113 the session is completed")
        XCTAssertFalse(quiet.rating.isPromptOwed, "S-1113 nothing is owed")
        XCTAssertNotEqual(
            quiet.engine.session?.status,
            WatchSessionStatus.active,
            "S-1113 so the shell falls through to the start surface"
        )
    }

    // MARK: - S-1108 the source guard

    func testS1108TheMenuSourceNamesNoRestEditOrDelete() throws {
        for file in ["WatchMenu.swift", "WatchMenuView.swift"] {
            let url = Fixtures.sourcesRoot.appendingPathComponent(file)
            let source = try String(contentsOf: url, encoding: .utf8)

            for token in ["restSeconds", "plannedDurationMs", "deleteEntry", "removeExercise"] {
                XCTAssertFalse(source.contains(token), "S-1108 \(file) must not name \(token)")
            }
        }
    }

    // MARK: - S-1202 the menu reaches nothing but the session

    func testS1202TheMenuSourceNamesNoExercisePicker() throws {
        for file in ["WatchMenu.swift", "WatchMenuView.swift"] {
            let url = Fixtures.sourcesRoot.appendingPathComponent(file)
            let source = try String(contentsOf: url, encoding: .utf8)

            for token in [
                "WatchExercisePickerView",
                "addExercise",
                "pickerRows",
                "fallbackExercises",
                "Add exercise",
            ] {
                XCTAssertFalse(source.contains(token), "S-1202 \(file) must not name \(token)")
            }
        }
    }
}
