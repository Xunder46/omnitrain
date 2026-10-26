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
//  Plan: `docs/plans/2026-10-13-31-watch-qa-fixes-3-plan/2026-10-13-31-watch-qa-fixes-3-plan.md`,
//  scenarios S-3101 to S-3104 and S-3111 (decisions D-3101, D-3102, D-3103,
//  D-3109, D-3114): the menu's extra gap above Add Exercise, the list button the
//  rest screen carries, the one sheet both surfaces open, and the rest a jump or
//  an add leaves running while a log closes it and starts the next one.
//
//  Plan: `docs/plans/2026-10-13-31-watch-qa-fixes-3-plan/2026-10-13-31-watch-qa-fixes-3-plan.md`,
//  Phase 2A, scenarios S-3105 and S-3108 (decisions D-3104, D-3110): the list
//  the user reads split into the runs the grid jumps by, and the one
//  `addLetterGridThreshold` site both surfaces read.
//
//  Plan: `docs/plans/2026-10-13-31-watch-qa-fixes-3-plan/2026-10-13-31-watch-qa-fixes-3-plan.md`,
//  Phase 2B, scenario S-3106 (decisions D-3105, D-3106, D-3112): both entry
//  points render the one shared exercise list, and the lazy stack whose
//  unmeasured rows made the letter jump miss is gone from all three files.
//
//  Plan: `docs/plans/2026-10-13-31-watch-qa-fixes-3-plan/2026-10-13-31-watch-qa-fixes-3-plan.md`,
//  fix round 1, scenario S-3114 (decision D-3117): a key that opens two runs of
//  the list carries one scroll id, on its first run, and the shared list derives
//  its ids from `scrollTargetLetters(of:)`.
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

// MARK: - Reading source text (the app target has no test target to run in)

/// A repository file, read from `Fixtures.repositoryRoot`, with every comment
/// line blanked out — the shape `WatchSensorSourceSourceTests.source(_:)` uses,
/// so a sentence of prose can neither satisfy a guard nor trip one. A trailing
/// `//` on a code line is blanked with it; the guarded files keep no `//` inside
/// a string literal.
private func menuSource(_ path: String) throws -> String {
    let url = Fixtures.repositoryRoot.appendingPathComponent(path)
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
            guard let comment = line.range(of: "//") else { return String(line) }
            return String(line[..<comment.lowerBound])
        }
        .joined(separator: "\n")
}

private func sourceLines(_ source: String) -> [String] {
    source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

/// The index of the line whose trimmed text is exactly `text`: the *use* of a
/// row builder, not its declaration, which carries a signature after the name.
private func usageLine(of text: String, in lines: [String]) -> Int? {
    lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == text }
}

/// The line after `index`, trimmed, or `""` at the end of the file.
private func nextLine(after index: Int, in lines: [String]) -> String {
    guard lines.indices.contains(index + 1) else { return "" }
    return lines[index + 1].trimmingCharacters(in: .whitespaces)
}

/// How many times `needle` occurs in `source`.
private func occurrences(of needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
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

    // MARK: - S-3106 the one list both entry points render (plan 31 Phase 2B)

    /// One shared component serves both entry points, and the lazy stack whose
    /// unmeasured rows made the letter jump miss is gone from all three files
    /// (D-3105, D-3106, D-3112). A source scan: these views are drawn only by
    /// the watch target, which `swift test` does not compile, and the landing
    /// itself is the owner's device check. Comment lines are stripped, so the
    /// files may name `LazyVStack` in prose without failing.
    func testS3106AOneListServesBothEntryPoints() throws {
        let sources = "watch/watchos/Sources/WatchSessionEngine"

        for file in ["WatchMenuView.swift", "WatchStartView.swift"] {
            let source = try menuSource("\(sources)/\(file)")
            XCTAssertTrue(
                source.contains("WatchExerciseLetterList"),
                "S-3106 \(file) renders the shared exercise list"
            )
            XCTAssertFalse(
                source.contains("LazyVStack"),
                "S-3106 \(file) no longer places a row by estimate"
            )
        }

        let shared = try menuSource("\(sources)/WatchExerciseListView.swift")
        XCTAssertTrue(
            shared.contains("WatchExerciseLetterList"),
            "S-3106 the shared component is what both entry points render"
        )
        XCTAssertFalse(
            shared.contains("LazyVStack"),
            "S-3106 the shared list places no row by estimate"
        )
    }

    // MARK: - S-3101…S-3104, S-3111 the rest screen's menu (plan 31 Phase 1)

    /// The extra gap belongs to the horizontal line: it sits between the divider
    /// and Add Exercise, so Add Exercise and End Session keep the menu's normal
    /// row spacing (D-3101). A source scan — the menu is drawn only by the watch
    /// target, which `swift test` does not compile.
    func testS3104ATheMenuGapSitsAboveAddExercise() throws {
        let lines = sourceLines(
            try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        )

        let add = try XCTUnwrap(
            usageLine(of: "addExerciseRow", in: lines),
            "S-3104 the menu carries the Add Exercise row"
        )
        let finish = try XCTUnwrap(
            usageLine(of: "finishRow", in: lines),
            "S-3104 the menu carries the End Session row"
        )

        XCTAssertTrue(
            nextLine(after: add, in: lines).hasPrefix(".padding(.top"),
            "S-3104 the extra gap sits between the divider and Add Exercise"
        )
        XCTAssertFalse(
            nextLine(after: finish, in: lines).hasPrefix(".padding(.top"),
            "S-3104 End Session sits at the normal row spacing"
        )
    }

    /// The rest screen carries the same list button the logging surface does, and
    /// the menu is built once and hosted where a rest ending cannot tear it down
    /// (D-3102, D-3114). A source scan: the app target has no test target, so the
    /// button and the one sheet are held here and proven on the wrist by the
    /// owner's check.
    func testS3103ATheRestScreenCarriesTheMenuButton() throws {
        let source = try menuSource("ios/OmniTrain Watch App/ContentView.swift")

        let lines = sourceLines(source)
        let rest = try XCTUnwrap(
            lines.firstIndex { $0.contains("host.logging.isResting") },
            "S-3103 the shell has a rest branch"
        )
        let logging = try XCTUnwrap(
            lines.firstIndex { $0.contains("private var loggingSurface") },
            "S-3103 the logging surface is where it was"
        )
        let branch = lines[rest...logging].joined(separator: "\n")

        XCTAssertTrue(
            branch.contains("NavigationStack"),
            "S-3103 the rest branch is a navigation surface of its own"
        )
        XCTAssertTrue(
            branch.contains("Image(systemName: \"list.bullet\")"),
            "S-3103 the rest screen carries the list button the logging surface has"
        )
        XCTAssertEqual(
            occurrences(of: "WatchMenuState(", in: source),
            1,
            "S-3103 one menu construction serves both surfaces"
        )
    }

    /// A jump made during a rest moves the session and leaves the rest alone: the
    /// rest is not the work a jump is refused by, and a jump is neither a log nor
    /// a Next, so it neither ends the rest nor starts a new one (D-3103).
    func testS3101AJumpDuringARestKeepsTheRestRunning() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        try await surface.log()
        let resting = try XCTUnwrap(harness.engine.timerFor(WatchTimerKind.rest))
        XCTAssertTrue(
            surface.isResting,
            "S-3101 the fixture is resting, so the rest case is the one exercised"
        )

        let moved = await harness.menu.jump(to: "s3")

        XCTAssertTrue(moved, "S-3101 the jump goes through while a rest runs")
        XCTAssertEqual(
            harness.engine.session?.currentExerciseIndex,
            2,
            "S-3101 and moves the session to Row"
        )
        XCTAssertTrue(surface.isResting, "S-3101 the rest is not over: a jump is not a log and not a Next")
        let after = try XCTUnwrap(harness.engine.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(after.recordId, resting.recordId, "S-3101 the same rest, not a second one")
        XCTAssertEqual(after.startedAt, resting.startedAt, "S-3101 still counting up from where it started")
        XCTAssertNil(after.stoppedAt, "S-3101 with no end put on it")

        harness.clock.advance(20)
        XCTAssertEqual(
            surface.restElapsedSeconds(),
            20,
            "S-3101 and the clock keeps running through the jump"
        )
    }

    /// Adding an exercise moves nothing the running effort is logging, and it
    /// touches no timer either: the rest keeps counting under the add (D-3103).
    /// What closes that rest is the next log, and S-3111 pins that.
    func testS3102AAddingAnExerciseDuringARestKeepsTheRestRunning() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        await harness.applyFallbackCatalog()
        let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        try await surface.log()
        let resting = try XCTUnwrap(harness.engine.timerFor(WatchTimerKind.rest))
        let dip = try XCTUnwrap(harness.menu.addableExercises.first { $0.exerciseId == "ex-dip" })

        let added = await harness.menu.addExercise(dip)

        XCTAssertTrue(added, "S-3102 an active session takes the add while a rest runs")
        XCTAssertEqual(harness.engine.session?.exercises.count, 4, "S-3102 the ladder grows by exactly one")
        XCTAssertEqual(
            harness.engine.session?.exercises.last?["exerciseId"] as? String,
            "ex-dip",
            "S-3102 and the new slot is the last one"
        )
        XCTAssertEqual(
            harness.engine.session?.currentExerciseIndex,
            1,
            "S-3102 the user stays on the exercise they were logging"
        )
        XCTAssertTrue(surface.isResting, "S-3102 the rest is not over: an add moves nothing it logs")
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.rest)?.recordId,
            resting.recordId,
            "S-3102 and the running rest is the same record"
        )
    }

    /// The second half of the seeded S-3102, in D-3109's executable reading: the
    /// log closes the rest it was logged into — at the logged instant, so its
    /// window stops there — and then starts the next rest itself, so the wrist is
    /// resting again. Nothing here is new behaviour; it is the rest the owner's
    /// request depends on, pinned.
    func testS3111ALogClosesTheRunningRestAndStartsTheNext() async throws {
        let harness = await WatchMenuHarness().launch()
        _ = await harness.engine.createSession(
            modality: nil,
            exercises: [
                menuSlot("sx-bench", "Bench Press"),
                menuSlot("sx-plank", "Plank"),
            ]
        )
        let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)
        let t0 = harness.clock.now

        let first = try await surface.log()
        harness.clock.advance(30)
        _ = try await surface.log()

        // Each rest leaves two rows — the start and the stop — because a stop
        // is a row (the shape `WatchLoggingTimersTests.testS321` reads).
        let rests = harness.engine.timerRows(WatchTimerKind.rest)
        XCTAssertEqual(
            rests.filter { $0.stoppedAt != nil }.count,
            1,
            "S-3111 the log closes the rest it was logged into, and closes only that one"
        )
        let closed = try XCTUnwrap(rests.first { $0.stoppedAt != nil })
        XCTAssertEqual(closed.startedAt, t0, "S-3111 that rest starts where the first set was logged")
        XCTAssertEqual(
            closed.stoppedAt,
            t0.addingTimeInterval(30),
            "S-3111 and it stops at the instant the next set was logged (D-223)"
        )
        let following = try XCTUnwrap(
            harness.engine.timerFor(WatchTimerKind.rest),
            "S-3111 the wrist is resting again"
        )
        XCTAssertNotEqual(
            following.recordId,
            closed.recordId,
            "S-3111 the newest rest is a new row, not the one that was closed"
        )
        XCTAssertEqual(following.state, WatchTimerState.running, "S-3111 and it is the one that runs")
        XCTAssertEqual(
            following.startedAt,
            t0.addingTimeInterval(30),
            "S-3111 started at the logged instant, not a tick later"
        )
        XCTAssertTrue(surface.isResting, "S-3111 so the wrist is resting again")

        let travelled = harness.engine.observations.filter { $0.kind == WatchObservationKind.rest }
        XCTAssertEqual(travelled.count, 1, "S-3111 one rest ended, one event")
        let rest = try XCTUnwrap(travelled.first)
        XCTAssertEqual(rest.payload["startedAt"] as? String, utcIso(t0), "S-3111 the window it spanned")
        XCTAssertEqual(
            rest.payload["endedAt"] as? String,
            utcIso(t0.addingTimeInterval(30)),
            "S-3111 ends at the logged instant"
        )
        XCTAssertEqual(
            rest.payload["afterEntryId"] as? String,
            first.entryId,
            "S-3111 hung on the entry the rest followed (the shape WatchLoggingTimersTests.testS321 pins)"
        )
        XCTAssertEqual(
            harness.engine.observations.map(\.kind),
            ["set", "rest", "set"],
            "S-3111 the rest travels between the two sets, as the phone's importer reads it"
        )
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

    // MARK: - S-3105/S-3108 the sections the list is read in

    /// The list the user reads is the list the grid jumps by: one section per
    /// key, in the list's own order, and the concatenation of their exercises is
    /// `addableExercises` exactly — nothing dropped, nothing repeated, nothing
    /// reordered (D-3104, D-3110).
    func testS3105ASectionsFollowTheListAndTheLettersAgree() async throws {
        let harness = await WatchMenuHarness().launch()
        // 120 mixed names: four per letter A-Z, the three keys that sort before
        // every letter (a leading space, a symbol and a digit), one accented name
        // that sorts after `z`, and twelve lowercase names among the uppercase
        // ones.
        var names: [String] = [" stray", "-dash hold", "3x3 press", "Élan"]
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            names.append(contentsOf: [
                "\(letter)pple",
                "\(letter)nt",
                "\(letter)corn",
                "\(letter)lmond",
            ])
        }
        names.append(contentsOf: "ABCDEFGHIJKL".map { "\($0) route" })
        await harness.applyLetterCatalog(names)

        let offered = harness.menu.addableExercises
        let letters = harness.menu.addExerciseLetters
        let sections = deriveExerciseSections(offered)

        XCTAssertEqual(offered.count, 120, "S-3105 the fixture is the 120-name list")
        XCTAssertEqual(
            sections.map(\.letter),
            letters.map(\.letter),
            "S-3105 one section per key, in the list's own order"
        )
        XCTAssertEqual(
            sections.flatMap(\.exercises).map(\.exerciseId),
            offered.map(\.exerciseId),
            "S-3105 the sections are the list itself: in order, nothing dropped or repeated"
        )
        XCTAssertEqual(
            sections.compactMap { $0.exercises.first?.exerciseId },
            letters.map(\.firstExerciseId),
            "S-3105 each section opens at the exercise its letter entry names"
        )
        XCTAssertEqual(sections.first?.letter, "#", "S-3105 the keys that sort first open the list")
        XCTAssertEqual(sections.last?.letter, "É", "S-3105 the accent is its own section, last")
    }

    // MARK: - S-3114 the scroll id a repeated key's runs carry (plan 31 fix round 1)

    /// One key can open two runs — a digit name sorts before `A`, a `~` name
    /// after `Z`, and both key to `#` — so the run a `ScrollViewReader` keeps
    /// cannot be the whole list: two sections sharing one id are two views with
    /// one identity, and the `#` jump could land on either.
    ///
    /// `scrollTargetLetters(of:)` is the rule — the first run of every key, once
    /// each, in the sections' order — and the shared list derives its ids from
    /// that function and from nothing else (D-3117).
    func testS3114ARepeatedLetterRunsCarryOneScrollId() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.applyLetterCatalog(letterCatalogNames + ["3x3 press", "~stretch"])

        let offered = harness.menu.addableExercises
        let sections = deriveExerciseSections(offered)
        let targets = scrollTargetLetters(of: sections)

        XCTAssertEqual(
            sections.filter { $0.letter == "#" }.map(\.exercises.count),
            [1, 1],
            "S-3114 the fixture opens the # key twice, one exercise each"
        )
        XCTAssertEqual(
            sections.first?.exercises.first?.name,
            "3x3 press",
            "S-3114 the digit name opens the first # run"
        )
        XCTAssertEqual(
            sections.last?.exercises.first?.name,
            "~stretch",
            "S-3114 the tilde name opens the last # run"
        )
        XCTAssertEqual(
            targets.filter { $0 == "#" }.count,
            1,
            "S-3114 the repeated key carries one id, not one per run"
        )
        XCTAssertEqual(
            Set(targets).count,
            targets.count,
            "S-3114 no id appears twice in one reader"
        )
        XCTAssertEqual(
            targets,
            harness.menu.addExerciseLetters.map(\.letter),
            "S-3114 the ids are exactly the letters the grid jumps by, in order"
        )
        XCTAssertEqual(
            targets,
            sections.map(\.letter).reduce(into: [String]()) { letters, letter in
                if !letters.contains(letter) { letters.append(letter) }
            },
            "S-3114 every key is kept at its first run"
        )

        let shared = try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift")
        XCTAssertTrue(
            shared.contains("scrollTargetLetters(of:"),
            "S-3114 the shared list takes its scroll ids from the pinned rule"
        )
    }

    /// The grid's threshold is one gate over the rows a surface offers (D-3110):
    /// 20 carry none, 21 carry them, and what the menu shows is that gate's
    /// output — never a second reading of the literal.
    func testS3108ATheLetterGridAppearsOverTwentyRows() async {
        let twenty = await WatchMenuHarness().launch()
        await twenty.applyLetterCatalog((1...20).map { "berry \($0)" })

        XCTAssertEqual(twenty.menu.addableExercises.count, 20, "S-3108 the fixture is the threshold's own count")
        XCTAssertTrue(twenty.menu.addExerciseLetters.isEmpty, "S-3108 20 rows carry no grid")
        XCTAssertEqual(
            deriveExerciseListLetters(twenty.menu.addableExercises),
            [],
            "S-3108 the shared list function is empty at the threshold itself"
        )

        let twentyOne = await WatchMenuHarness().launch()
        await twentyOne.applyLetterCatalog((1...21).map { "berry \($0)" })

        XCTAssertEqual(twentyOne.menu.addableExercises.count, 21, "S-3108 one row past the threshold")
        XCTAssertEqual(twentyOne.menu.addExerciseLetters.map(\.letter), ["B"], "S-3108 21 rows carry the grid")
        XCTAssertEqual(
            twentyOne.menu.addExerciseLetters,
            deriveExerciseListLetters(twentyOne.menu.addableExercises),
            "S-3108 the menu's letters are the shared function's, not a second gate"
        )
    }
}
