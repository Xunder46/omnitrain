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
//  S-3611 to S-3618 of
//  `docs/plans/2026-10-11-23c-watch-add-exercise-plan/2026-10-11-23c-watch-add-exercise-plan.md`:
//  the menu's own Add Exercise list — its order, the append it makes at the end
//  of the ladder, the frame that announcement emits, and the lock it ignores.
//
//  S-3900 to S-3907 of
//  `docs/plans/2026-10-11-23e3-watch-add-exercise-letters-plan/2026-10-11-23e3-watch-add-exercise-letters-plan.md`:
//  the letters a long Add Exercise list carries, the threshold below which it
//  carries none, and the label of one letter button. S-3908, added with the
//  23e3 order-retention fix, pins that the entries follow the list's order even
//  when the `#` key sorts last.
//
//  Fixture A is the register's three-slot ladder: two live efforts on `s1`, none
//  on `s2`, one on `s3`, and a fourth `s1` effort the phone deleted.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// One slot of a menu fixture ladder.
private func menuSlot(
    _ id: String,
    _ name: String,
    capabilities: [String] = ["reps", "sets", "load"]
) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": name,
        "capabilities": capabilities,
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

/// The key the list's own order implies for a name: its FIRST character,
/// whitespace and all, uppercased when that character is a letter, otherwise
/// `"#"`, and `"#"` for a name with no character at all (D-3850). Written out
/// here so the S-3905 property checks the rule rather than restating the
/// production code.
private func letterKey(of name: String) -> String {
    guard let first = name.first else { return "#" }
    return first.isLetter ? String(first).uppercased() : "#"
}

/// The 25-name list S-3900 walks: two names on A and on B, then one per letter
/// through W, in the order the list's own lowercase sort gives.
private let letterCatalogNames = [
    "apple", "Avocado", "banana", "Blueberry", "cherry", "date", "elderberry",
    "fig", "grape", "honeydew", "iceberg lettuce", "jackfruit", "kiwi", "lemon",
    "mango", "nectarine", "olive", "papaya", "quince", "raspberry", "strawberry",
    "tangerine", "ugli fruit", "vanilla bean", "watermelon",
]

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

    /// The phone's fallback list. Squat is on the ladder; Pull-up and Dip are
    /// not — the menu's own rows show only the ladder (S-1200), while the Add
    /// Exercise list offers all three (S-3611).
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

    /// The phone's catalog with the four names S-3611 sorts: "apple", "Banana",
    /// "cherry" and "Apple Pie". Separate from `applyFallbackCatalog` so no
    /// existing scenario's list changes.
    @discardableResult
    func applySortCatalog() async -> WatchMenuHarness {
        _ = await store.append(
            .routineCatalog(
                WatchRoutineCatalogRecord(
                    recordId: "cat-menu-sort",
                    recordedAt: instant("2026-07-13T06:00:00Z"),
                    generatedAt: instant("2026-07-13T06:00:00Z"),
                    fallbackExercises: [
                        ["exerciseId": "ex-apple", "name": "apple", "capabilities": ["reps"]],
                        ["exerciseId": "ex-banana", "name": "Banana", "capabilities": ["reps"]],
                        ["exerciseId": "ex-cherry", "name": "cherry", "capabilities": ["reps"]],
                        ["exerciseId": "ex-apple-pie", "name": "Apple Pie", "capabilities": ["reps"]],
                    ]
                )
            )
        )
        await paths.restore()
        return self
    }

    /// The phone's catalog with one exercise per name, in the order the phone
    /// sent them: the long lists the letter grid is about (S-3900…S-3907). Ids
    /// are `ex-l<position>` so a scenario can name an exercise by where the
    /// phone put it, whatever its name sorts to.
    @discardableResult
    func applyLetterCatalog(_ names: [String]) async -> WatchMenuHarness {
        _ = await store.append(
            .routineCatalog(
                WatchRoutineCatalogRecord(
                    recordId: "cat-menu-letters",
                    recordedAt: instant("2026-07-13T06:00:00Z"),
                    generatedAt: instant("2026-07-13T06:00:00Z"),
                    fallbackExercises: names.enumerated().map { index, name in
                        [
                            "exerciseId": "ex-l\(index)",
                            "name": name,
                            "capabilities": ["reps"],
                        ]
                    }
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

    // MARK: - S-1307 the menu lock

    func testS1307TheMenuDoesNotJumpWhileAWorkClockRuns() async throws {
        let harness = await WatchMenuHarness().launch()
        _ = await harness.engine.createSession(
            modality: "cardio_endurance",
            exercises: [
                menuSlot("sx-run", "Run", capabilities: ["time", "distance"]),
                menuSlot("sx-row", "Row"),
            ]
        )
        let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        await surface.startWork()

        XCTAssertTrue(harness.menu.isLocked, "S-1307 a running effort clock locks the menu")
        let refused = await harness.menu.jump(to: "sx-row")
        XCTAssertFalse(refused, "S-1307 the locked menu refuses the jump")
        XCTAssertEqual(
            harness.engine.session?.currentExerciseIndex,
            0,
            "S-1307 the refused jump leaves the session where it was"
        )

        harness.clock.advance(754)
        try await surface.log()

        XCTAssertFalse(harness.menu.isLocked, "S-1307 logging ends the clock, so the menu frees up")
        let moved = await harness.menu.jump(to: "sx-row")
        XCTAssertTrue(moved, "S-1307 the jump goes through once the clock has stopped")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 1, "S-1307 and moves the session")
    }

    func testS1307APeriodCountdownLocksTheMenu() async {
        let harness = await WatchMenuHarness().launch()
        _ = await harness.engine.createSession(
            modality: "sports",
            exercises: [
                menuSlot("sx-period", "Period", capabilities: ["rounds"]),
                menuSlot("sx-row", "Row"),
            ]
        )
        let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        await surface.startWork()

        XCTAssertTrue(harness.menu.isLocked, "S-1307 a running period countdown locks the menu")
        let refused = await harness.menu.jump(to: "sx-row")
        XCTAssertFalse(refused, "S-1307 the locked menu refuses the jump")
        XCTAssertEqual(
            harness.engine.session?.currentExerciseIndex,
            0,
            "S-1307 the session stays on the period"
        )
    }

    func testS1307ARunningRestDoesNotLockTheMenu() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        try await surface.log()

        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.running,
            "S-1307 the fixture is resting, so the rest case is the one exercised"
        )
        XCTAssertFalse(harness.menu.isLocked, "S-1307 a rest is not work, so it leaves the menu free")
        let moved = await harness.menu.jump(to: "s3")
        XCTAssertTrue(moved, "S-1307 the jump goes through while a rest runs")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 2, "S-1307 and moves the session")
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

    // MARK: - S-3611…S-3618 the menu's Add Exercise list (23c)

    /// The order the user reads. Lowercase text, so "apple" and "Apple Pie" sit
    /// together before "Banana", and the id breaks a tie the case hid.
    func testS3611TheAddListSortsCaseInsensitivelyByName() async {
        let harness = await WatchMenuHarness().launch()
        await harness.applySortCatalog()

        XCTAssertEqual(
            harness.menu.addableExercises.map(\.name),
            ["apple", "Apple Pie", "Banana", "cherry"],
            "S-3611 the list is A to Z and ignores case"
        )
        XCTAssertEqual(
            harness.paths.addableExercises.map(\.exerciseId),
            harness.menu.addableExercises.map(\.exerciseId),
            "S-3611 the menu offers exactly the paths' list"
        )
    }

    /// The append: last on the ladder, the position untouched, no count on the
    /// new row because nothing is logged on it yet.
    func testS3612AddExerciseAppendsAtTheEndAndKeepsThePosition() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        await harness.applyFallbackCatalog()
        let dip = try XCTUnwrap(harness.menu.addableExercises.first { $0.exerciseId == "ex-dip" })

        let added = await harness.menu.addExercise(dip)

        XCTAssertTrue(added, "S-3612 an active session takes the add")
        XCTAssertEqual(harness.engine.session?.exercises.count, 4, "S-3612 the ladder grows by exactly one")
        XCTAssertEqual(
            harness.engine.session?.exercises.last?["exerciseId"] as? String,
            "ex-dip",
            "S-3612 the new slot is the last one"
        )
        XCTAssertEqual(
            harness.engine.session?.currentExerciseIndex,
            1,
            "S-3612 the user stays on the exercise they were logging"
        )
        let rows = harness.menu.rows
        XCTAssertEqual(rows.count, 4, "S-3612 the menu shows the ladder it now holds")
        XCTAssertEqual(rows.last?.name, "Dip", "S-3612 the new slot is the last row")
        XCTAssertNil(rows.last?.countLabel, "S-3612 and it says no count yet")
    }

    /// A superset is two slots of the same exercise, so the second add must not
    /// wear the first's id.
    func testS3613TheSameExerciseTwiceGetsTwoSlots() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        await harness.applyFallbackCatalog()
        let dip = try XCTUnwrap(harness.menu.addableExercises.first { $0.exerciseId == "ex-dip" })

        _ = await harness.menu.addExercise(dip)
        _ = await harness.menu.addExercise(dip)

        let ids = (harness.engine.session?.exercises ?? [])
            .compactMap { $0["sessionExerciseId"] as? String }
        XCTAssertEqual(ids.count, 5, "S-3613 two adds make two slots beside the fixture's three")
        XCTAssertEqual(Set(ids).count, 5, "S-3613 no slot id repeats")
        XCTAssertEqual(
            ids.filter { $0.hasPrefix("sx-ex-dip") }.count,
            2,
            "S-3613 both new slots hold the exercise the user picked twice"
        )
    }

    /// The announcement is what carries a wrist-added slot to the phone, so the
    /// add must go through the engine's own insert rather than patching the
    /// ladder. Read over the start harness, whose engine records every frame.
    func testS3614TheAddAnnouncesTheLadderChangeToThePhone() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = await harness.store.append(
            .routineCatalog(
                WatchRoutineCatalogRecord(
                    recordId: "cat-menu-emit",
                    recordedAt: instant("2026-07-13T06:00:00Z"),
                    generatedAt: instant("2026-07-13T06:00:00Z"),
                    fallbackExercises: [
                        ["exerciseId": "ex-dip", "name": "Dip", "capabilities": ["reps"]],
                    ]
                )
            )
        )
        await harness.paths.restore()
        let started = await harness.paths.startFreeWorkout()
        let dip = try XCTUnwrap(harness.paths.addableExercises.first)
        let before = harness.emitted("session_snapshot").count

        let live = await harness.paths.addExerciseToEnd(dip)

        XCTAssertEqual(
            harness.emitted("session_snapshot").count,
            before + 1,
            "S-3614 the add announces itself exactly once"
        )
        let snapshot = try XCTUnwrap(harness.emitted("session_snapshot").last)
        let payload = try XCTUnwrap(snapshot["payload"] as? [String: Any])
        XCTAssertEqual(
            (payload["exercises"] as? [[String: Any]])?.last?["sessionExerciseId"] as? String,
            "sx-ex-dip",
            "S-3614 the announced snapshot carries the new slot"
        )
        XCTAssertEqual(
            payload["revision"] as? Int,
            started.revision + 1,
            "S-3614 and its revision has moved one past the start's"
        )
        XCTAssertEqual(live.revision, started.revision + 1, "S-3614 the live session is the announced shape")
    }

    /// Adding moves nothing the running effort is logging, so the lock that
    /// protects the rows does not protect this action (D-3607).
    func testS3615AddExerciseWorksWhileAWorkClockRuns() async throws {
        let harness = await WatchMenuHarness().launch()
        _ = await harness.engine.createSession(
            modality: "cardio_endurance",
            exercises: [
                menuSlot("sx-run", "Run", capabilities: ["time", "distance"]),
                menuSlot("sx-row", "Row"),
            ]
        )
        await harness.applyFallbackCatalog()
        let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        await surface.startWork()
        XCTAssertTrue(harness.menu.isLocked, "S-3615 a running work clock locks the menu's rows")

        let dip = try XCTUnwrap(harness.menu.addableExercises.first { $0.exerciseId == "ex-dip" })
        let added = await harness.menu.addExercise(dip)

        XCTAssertTrue(added, "S-3615 Add Exercise is not blocked by the lock")
        XCTAssertEqual(harness.engine.session?.exercises.count, 3, "S-3615 the ladder grows")
        XCTAssertEqual(
            harness.engine.session?.currentExerciseIndex,
            0,
            "S-3615 and the running effort's exercise does not change"
        )

        let refused = await harness.menu.jump(to: "sx-row")
        XCTAssertFalse(refused, "S-3615 the jump is still refused while the clock runs")
        XCTAssertEqual(
            harness.engine.session?.currentExerciseIndex,
            0,
            "S-3615 the refused jump leaves the session on the running effort"
        )
    }

    /// The new copy, in one place the suite can read (D-3608).
    func testS3616TheAddCopyIsTheOwnersWords() {
        XCTAssertEqual(WatchMenuCopy.addExerciseLabel, "Add Exercise")
        XCTAssertEqual(WatchMenuCopy.addExerciseTitle, "Add Exercise")
        XCTAssertEqual(WatchMenuCopy.addExerciseEmpty, "No exercises yet. Sync with your phone.")
    }

    /// With no session to grow — or one already closed — the menu's add changes
    /// nothing and says so.
    func testS3618AddExerciseWithNoSessionChangesNothing() async throws {
        let bare = await WatchMenuHarness().launch()
        await bare.applyFallbackCatalog()
        let dip = try XCTUnwrap(bare.menu.addableExercises.first { $0.exerciseId == "ex-dip" })

        let added = await bare.menu.addExercise(dip)

        XCTAssertFalse(added, "S-3618 with no session there is nowhere to add")
        XCTAssertNil(bare.engine.session, "S-3618 and no session is invented for it")

        let ended = await WatchMenuHarness().launch()
        await ended.fixtureA()
        await ended.applyFallbackCatalog()
        await ended.menu.finish()

        let late = await ended.menu.addExercise(dip)

        XCTAssertFalse(late, "S-3618 a finished session refuses the add")
        XCTAssertEqual(ended.engine.session?.exercises.count, 3, "S-3618 and its ladder is untouched")
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

    // MARK: - S-3401 the menu's fixed copy

    /// The menu's own words, and the confirmation's, which the phone's sibling
    /// dialog already carries (`workout_session_finish.dart`): one source, both
    /// ends. The view's constant is the watchOS-only one the Xcode build reads.
    func testS3401TheMenuCopyIsTheOwnersWords() {
        XCTAssertEqual(WatchMenuCopy.finishLabel, "End Session")
        XCTAssertEqual(WatchMenuCopy.confirmTitle, "Finish Workout?")
        XCTAssertEqual(
            WatchMenuCopy.confirmBody,
            "This action will save and close the workout session."
        )
        XCTAssertEqual(WatchMenuCopy.confirmCancel, "Cancel")
        XCTAssertEqual(WatchMenuCopy.confirmFinish, "Finish")
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

    // MARK: - S-3617 the add list is its own surface

    /// The owner reversed S-1202's owner rule on 2026-10-11: the menu now adds
    /// from the phone's whole list (23c). What stays forbidden is the free
    /// workout's picker: the Add list is its own surface, not that picker.
    func testS3617TheMenuAddsFromItsOwnListNotTheStartPicker() throws {
        for file in ["WatchMenu.swift", "WatchMenuView.swift"] {
            let url = Fixtures.sourcesRoot.appendingPathComponent(file)
            let source = try String(contentsOf: url, encoding: .utf8)

            for token in ["WatchExercisePickerView", "pickerRows"] {
                XCTAssertFalse(source.contains(token), "S-3617 \(file) must not name \(token)")
            }
        }
    }

    // MARK: - S-3900…S-3907 the Add Exercise letter grid (23e3)

    /// The letters a long list carries: one entry per first letter the list
    /// has, in the list's own order, each naming the exercise its run starts
    /// with. A second name on the same letter adds no second entry.
    func testS3900TheLettersFollowTheListsOwnOrder() async {
        let harness = await WatchMenuHarness().launch()
        await harness.applyLetterCatalog(letterCatalogNames)

        let offered = harness.menu.addableExercises
        let letters = harness.menu.addExerciseLetters

        XCTAssertEqual(
            letters.map(\.letter),
            [
                "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
                "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W",
            ],
            "S-3900 one entry per first letter, in list order"
        )
        XCTAssertEqual(letters.count, 23, "S-3900 the two second names on A and B add no entry")
        XCTAssertEqual(
            letters.first?.firstExerciseId,
            offered.first { $0.name == "apple" }?.exerciseId,
            "S-3900 the A entry starts at the list's first exercise"
        )
        XCTAssertEqual(
            letters.first { $0.letter == "B" }?.firstExerciseId,
            offered.first { $0.name == "banana" }?.exerciseId,
            "S-3900 each entry starts at its own first exercise"
        )
        XCTAssertEqual(offered.first?.name, "apple", "S-3900 plain lowercase text puts apple before Avocado")
    }

    /// Digits and symbols open one shared `#` entry, and it sorts first because
    /// the list sorts by plain lowercase text.
    func testS3901DigitsAndSymbolsShareOneHashEntryFirst() async {
        let harness = await WatchMenuHarness().launch()
        await harness.applyLetterCatalog(
            ["1 min sprint", "5 minute plank", "(warm up)"] + (1...20).map { "b\($0)" }
        )

        let offered = harness.menu.addableExercises
        let letters = harness.menu.addExerciseLetters

        XCTAssertEqual(
            letters.map(\.letter),
            ["#", "B"],
            "S-3901 the three non-letter names share one entry, ahead of every letter"
        )
        XCTAssertEqual(
            letters.first?.firstExerciseId,
            offered.first { $0.name == "(warm up)" }?.exerciseId,
            "S-3901 the # entry starts at the first of its names in list order"
        )
        XCTAssertEqual(offered.first?.name, "(warm up)", "S-3901 a symbol sorts before a digit before a letter")
    }

    /// The threshold is the owner's number, and it is a floor on the list, not
    /// an exclusive bound: exactly 20 shows nothing.
    func testS3902TheGridNeedsMoreThanTheThreshold() async {
        XCTAssertEqual(WatchMenuCopy.addLetterGridThreshold, 20, "S-3902 the owner's threshold")

        let short = await WatchMenuHarness().launch()
        await short.applyLetterCatalog((1...20).map { "exercise \($0)" })
        XCTAssertEqual(
            short.menu.addableExercises.count,
            WatchMenuCopy.addLetterGridThreshold,
            "S-3902 the short list holds exactly the threshold"
        )
        XCTAssertEqual(short.menu.addExerciseLetters, [], "S-3902 at the threshold there is no grid")

        let long = await WatchMenuHarness().launch()
        await long.applyLetterCatalog((1...21).map { "exercise \($0)" })
        XCTAssertFalse(long.menu.addExerciseLetters.isEmpty, "S-3902 one past the threshold there is a grid")
    }

    /// Case is not a letter of its own: "apple" and "Avocado" are one `A`.
    func testS3903CaseIsOneLetterPerFirstCharacter() async {
        let harness = await WatchMenuHarness().launch()
        await harness.applyLetterCatalog(
            ["apple", "Avocado", "banana"] + (1...20).map { "berry \($0)" }
        )

        let offered = harness.menu.addableExercises
        let a = harness.menu.addExerciseLetters.filter { $0.letter == "A" }

        XCTAssertEqual(a.count, 1, "S-3903 apple and Avocado are one A entry")
        XCTAssertEqual(
            a.first?.firstExerciseId,
            offered.first { $0.name == "apple" }?.exerciseId,
            "S-3903 the A entry starts at the exercise the list shows first"
        )
    }

    /// An accented initial has its own letter and sits where the list puts it:
    /// plain lowercase text puts "Élan" after "zebra", so `É` is the last entry.
    func testS3904AnAccentedInitialIsItsOwnLetterAndSortsLast() async {
        let harness = await WatchMenuHarness().launch()
        await harness.applyLetterCatalog(["zebra", "Élan"] + (1...20).map { "berry \($0)" })

        let offered = harness.menu.addableExercises
        let letters = harness.menu.addExerciseLetters

        XCTAssertEqual(letters.last?.letter, "É", "S-3904 the accent keeps its own letter, at the end")
        XCTAssertEqual(
            letters.last?.firstExerciseId,
            offered.last?.exerciseId,
            "S-3904 Élan is the list's own last exercise"
        )
        XCTAssertEqual(offered.last?.name, "Élan", "S-3904 the list puts the accent after z")
        XCTAssertEqual(
            letters.first { $0.letter == "Z" }?.firstExerciseId,
            offered.first { $0.name == "zebra" }?.exerciseId,
            "S-3904 zebra is its own Z entry"
        )
    }

    /// The letters partition the list with no gap and no overlap: entry *i*
    /// covers exactly the exercises from its own first exercise up to the next
    /// entry's, and every entry names an exercise the list holds.
    func testS3905EveryLetterEntryCoversAContiguousRun() async throws {
        let harness = await WatchMenuHarness().launch()
        var names: [String] = ["  apple"]
        for index in 0..<120 {
            switch index % 8 {
            case 0: names.append("apple \(index)")
            case 1: names.append("Banana \(index)")
            case 2: names.append("\(index) reps")
            case 3: names.append("(hold) \(index)")
            case 4: names.append("cherry \(index)")
            case 5: names.append("Élan \(index)")
            case 6: names.append("dip \(index)")
            default: names.append("  zebra \(index)")
            }
        }
        await harness.applyLetterCatalog(names)

        let offered = harness.menu.addableExercises
        let letters = harness.menu.addExerciseLetters
        XCTAssertFalse(letters.isEmpty, "S-3905 a 120-name list carries letters")

        var positionOf: [String: Int] = [:]
        for (position, exercise) in offered.enumerated() {
            positionOf[exercise.exerciseId] = position
        }

        for (entryIndex, entry) in letters.enumerated() {
            let start = try XCTUnwrap(
                positionOf[entry.firstExerciseId],
                "S-3905 \(entry.letter) names an exercise the list holds"
            )
            let end = entryIndex + 1 < letters.count
                ? try XCTUnwrap(positionOf[letters[entryIndex + 1].firstExerciseId])
                : offered.count
            XCTAssertLessThan(start, end, "S-3905 the entries are in list order")
            for position in start..<end {
                XCTAssertEqual(
                    letterKey(of: offered[position].name),
                    entry.letter,
                    "S-3905 every exercise in an entry's run wears its letter"
                )
            }
        }

        XCTAssertEqual(letters.first?.firstExerciseId, offered.first?.exerciseId, "S-3905 the first entry opens the list")
        XCTAssertEqual(
            letters.last?.firstExerciseId,
            offered.first { letterKey(of: $0.name) == letters.last?.letter }?.exerciseId,
            "S-3905 the last entry opens its own run"
        )
    }

    /// The one string a letter button says to VoiceOver (D-3852).
    func testS3906TheJumpLabelNamesTheLetter() {
        XCTAssertEqual(WatchMenuCopy.addLetterJumpLabel("A"), "Jump to A")
        XCTAssertEqual(WatchMenuCopy.addLetterJumpLabel("#"), "Jump to #")
    }

    /// A name with no character at all — or only whitespace, leading or not — is
    /// `#`, not a crash and not a letter: a leading space sorts before every
    /// letter, so it belongs in the `#` run and adds no `A` entry of its own.
    func testS3907AnEmptyNameIsHashedAndDoesNotCrash() async {
        let harness = await WatchMenuHarness().launch()
        await harness.applyLetterCatalog(["" , "   ", " apple"] + (1...20).map { "berry \($0)" })

        let offered = harness.menu.addableExercises
        let letters = harness.menu.addExerciseLetters

        XCTAssertEqual(letters.map(\.letter), ["#", "B"], "S-3907 an empty name, a spaces-only name and a leading-space name are hashed")
        XCTAssertFalse(
            letters.contains { $0.letter == "A" },
            "S-3907 a leading-space name adds no A entry: it sits in the # run"
        )
        XCTAssertEqual(
            letters.first?.firstExerciseId,
            offered.first?.exerciseId,
            "S-3907 the empty name is the list's first exercise"
        )
    }

    /// The entries follow the LIST's order, not the alphabetical order of their
    /// keys: `~` is above `z` in the plain-lowercase sort, so a "~stretch" name
    /// sits last and its `#` entry comes last too, unlike S-3901's `#` run that
    /// opens a list of digits and symbols.
    func testS3908ASymbolThatSortsAfterZGetsItsHashEntryAtTheEnd() async {
        let harness = await WatchMenuHarness().launch()
        await harness.applyLetterCatalog(letterCatalogNames + ["~stretch"])

        let offered = harness.menu.addableExercises
        let letters = harness.menu.addExerciseLetters

        XCTAssertGreaterThan(
            offered.count,
            WatchMenuCopy.addLetterGridThreshold,
            "S-3908 the list is long enough to carry the grid"
        )
        XCTAssertEqual(
            letters.map(\.letter),
            [
                "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
                "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "#",
            ],
            "S-3908 one entry per key, in the list's own order, the # run last"
        )
        XCTAssertEqual(offered.last?.name, "~stretch", "S-3908 the list sorts a tilde name after z")
        XCTAssertEqual(letters.last?.letter, "#", "S-3908 the last entry is the # run")
        XCTAssertEqual(
            letters.last?.firstExerciseId,
            offered.last?.exerciseId,
            "S-3908 the # entry opens its run at the tilde name"
        )
    }
}
