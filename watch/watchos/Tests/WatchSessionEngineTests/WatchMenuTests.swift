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
//  Plan: `docs/plans/2026-10-13-31-watch-qa-fixes-3-plan/2026-10-13-31-watch-qa-fixes-3-plan.md`,
//  scenarios S-3101 to S-3104 and S-3111 (decisions D-3101, D-3102, D-3103,
//  D-3109, D-3114): the menu's extra gap above Add Exercise, the list button the
//  rest screen carries, the one sheet both surfaces open, and the rest a jump or
//  an add leaves running while a log closes it and starts the next one.
//
//  Plan: `docs/plans/2026-11-15-199-watch-exercise-list-modality-first-plan/2026-11-15-199-watch-exercise-list-modality-first-plan.md`,
//  phase P1 (decisions D-19901, D-19902, D-19905, D-19912): the letter grid and
//  the letter sections are gone from both exercise lists, and the S-19912
//  source guard that the deleted symbols occur nowhere in Sources.
//
//  Plan: `docs/plans/2026-10-13-31-watch-qa-fixes-3-plan/2026-10-13-31-watch-qa-fixes-3-plan.md`,
//  Phase 2B, scenario S-3106 (decisions D-3105, D-3106, D-3112): both entry
//  points render the one shared exercise list, and the lazy stack whose
//  unmeasured rows placed them by estimate is gone from all three files.
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

/// The 25-name list S-19923 walks: two names on A and on B, then one per letter
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

    /// Every frame the engine handed to the wrist's uplink, in order — what the
    /// phone would have heard. The engine emits through `onEmit`, so the harness
    /// keeps the envelopes themselves rather than a summary of them.
    private(set) var emittedFrames: [[String: Any]] = []

    /// The frames of one `type`, in the order they were emitted.
    func emitted(_ type: String) -> [[String: Any]] {
        emittedFrames.filter { $0["type"] as? String == type }
    }

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
            onEmit: { [weak self] envelope in self?.emittedFrames.append(envelope) },
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
    /// sent them: the long lists the group shape is about (S-19907, S-19909). Ids
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
        // Plan 81: a slot the wrist mints ends with the session's token.
        let announcedSlot = (payload["exercises"] as? [[String: Any]])?.last?["sessionExerciseId"] as? String
        XCTAssertEqual(
            announcedSlot,
            "sx-ex-dip~\(sessionToken(from: started.sessionId))",
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

        // Plan 171 D-17104: the Discard row and its confirmation, in the
        // owner's words, with no em dash anywhere.
        XCTAssertEqual(WatchMenuCopy.discardLabel, "Discard Session")
        XCTAssertEqual(WatchMenuCopy.discardConfirmTitle, "Discard session?")
        XCTAssertEqual(
            WatchMenuCopy.discardConfirmBody,
            "This will permanently delete this session and all its data. You will return to the start screen."
        )
        XCTAssertEqual(WatchMenuCopy.discardConfirmCancel, "Cancel")
        XCTAssertEqual(WatchMenuCopy.discardConfirmDiscard, "Discard")
        for word in [
            WatchMenuCopy.discardLabel,
            WatchMenuCopy.discardConfirmTitle,
            WatchMenuCopy.discardConfirmBody,
            WatchMenuCopy.discardConfirmCancel,
            WatchMenuCopy.discardConfirmDiscard,
        ] {
            XCTAssertFalse(word.contains("\u{2014}"), "D-17104 the copy carries no em dash: \(word)")
        }
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
                source.contains("WatchExerciseGroupList"),
                "S-3106 \(file) renders the shared exercise list"
            )
            XCTAssertFalse(
                source.contains("LazyVStack"),
                "S-3106 \(file) no longer places a row by estimate"
            )
        }

        let shared = try menuSource("\(sources)/WatchExerciseListView.swift")
        XCTAssertTrue(
            shared.contains("WatchExerciseGroupList"),
            "S-3106 the shared component is what both entry points render"
        )
        XCTAssertFalse(
            shared.contains("LazyVStack"),
            "S-3106 the shared list places no row by estimate"
        )
    }

    // MARK: - S-22307, S-22308 one shape per row, titleless containers (plan 223)

    /// The list's rows are each their button's one shape: the platter is cleared
    /// right after the row's frame in both row builders, the styles stay, and the
    /// file keeps its single plain list (D-22311). A source scan, like S-3106A.
    func testS22307EachListRowIsOneShape() throws {
        let source = try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift")
        let lines = sourceLines(source)

        for (marker, keeps) in [
            ("private func rows(of", ".buttonStyle(.bordered)"),
            ("private func leadingButton(", ".watchProminent()"),
        ] {
            let row = try XCTUnwrap(
                block(from: marker, in: lines),
                "S-22307 the row builder is in the file"
            )
            let rowLines = row.map { $0.trimmingCharacters(in: .whitespaces) }
            let frame = try XCTUnwrap(
                rowLines.firstIndex { $0 == ".frame(maxWidth: .infinity, alignment: .leading)" },
                "S-22307 the row fills the list's width"
            )
            XCTAssertEqual(
                rowLines[frame + 1],
                ".listRowBackground(Color.clear)",
                "S-22307 the list draws no platter behind the row"
            )
            XCTAssertEqual(
                occurrences(of: ".listRowBackground(Color.clear)", in: row.joined(separator: "\n")),
                1,
                "S-22307 the row clears the platter once"
            )
            XCTAssertTrue(
                row.joined(separator: "\n").contains(keeps),
                "S-22307 the row keeps its own button style"
            )
        }

        XCTAssertEqual(occurrences(of: ".listStyle(.plain)", in: source), 1, "S-22307 the list stays plain")
    }

    /// Both entry points sit in a container that keeps their rows clear of the
    /// sheet's close button and the clock: the picker sheet wraps its list in a
    /// titleless stack, and the Add list stays a push inside the menu's own stack
    /// (D-22311, D-3608). A source scan, like S-3106A.
    func testS22308ThePickerSitsInATitlelessStack() throws {
        let start = try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift")
        let pickerStruct = try XCTUnwrap(
            block(from: "public struct WatchExercisePickerView: View", in: sourceLines(start)),
            "S-22308 the exercise picker is in the file"
        )
        let pickerBody = try XCTUnwrap(
            block(from: "public var body: some View {", in: pickerStruct),
            "S-22308 the picker's body is in the view"
        )

        let bodyLines = pickerBody
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        XCTAssertEqual(bodyLines[1], "NavigationStack {", "S-22308 the picker's body opens with a stack")
        XCTAssertEqual(bodyLines[2], "WatchExerciseGroupList(", "S-22308 and still renders the shared list")
        XCTAssertFalse(
            pickerBody.contains { $0.contains(".navigationTitle(") },
            "S-22308 the picker adds no title of its own"
        )

        let stackOpen = try XCTUnwrap(bodyLines.firstIndex { $0 == "NavigationStack {" })
        var depth = 0
        var stackClose: Int?
        for (offset, line) in bodyLines[stackOpen...].enumerated() {
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0, offset > 0 { stackClose = stackOpen + offset; break }
        }
        let backdrop = try XCTUnwrap(
            bodyLines.firstIndex { $0 == ".solidSheetBackground()" },
            "S-22308 the sheet content keeps its solid backdrop"
        )
        let close = try XCTUnwrap(stackClose, "S-22308 the stack closes inside the body")
        XCTAssertGreaterThan(backdrop, close, "S-22308 the backdrop sits on the stack, outside its braces")

        let menu = try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        let menuLines = sourceLines(menu)
        let addList = try XCTUnwrap(
            block(from: "private struct WatchAddExerciseList: View", in: menuLines),
            "S-22308 the Add list is in the file"
        )
        XCTAssertTrue(
            addList.contains { $0.contains("WatchExerciseGroupList(") },
            "S-22308 the Add list still renders the shared list"
        )
        XCTAssertFalse(
            addList.contains { $0.contains("NavigationStack") },
            "S-22308 the Add list brings no stack of its own (D-3608)"
        )
        let menuBlock = try XCTUnwrap(propertyBlock("menu", in: menuLines), "S-22308 the menu is in the file")
        let addRow = try XCTUnwrap(
            propertyBlock("addExerciseRow", in: menuLines),
            "S-22308 the Add row is in the file"
        )
        XCTAssertTrue(
            addRow.contains { $0.contains("NavigationLink {") },
            "S-22308 the Add row is a push, not a new container"
        )
        XCTAssertTrue(
            menuBlock.contains { $0.trimmingCharacters(in: .whitespaces) == "addExerciseRow" },
            "S-22308 the menu reaches the Add list through its own row"
        )
    }

    /// The two endings stand the section gap apart, Discard last (D-22313). A
    /// source scan, like S-3104B above.
    func testS22310TheEndingsStandASectionGapApart() throws {
        let menu = try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        let menuBlock = try XCTUnwrap(
            propertyBlock("menu", in: sourceLines(menu)),
            "S-22310 the menu is in the file"
        )

        let lines = menuBlock
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let stack = try XCTUnwrap(
            lines.firstIndex { $0 == "VStack(spacing: Self.sectionGap) {" },
            "S-22310 the endings share one gap-holding stack"
        )
        let finish = try XCTUnwrap(lines.firstIndex { $0 == "finishRow" }, "S-22310 the menu carries End Session")
        let discard = try XCTUnwrap(lines.firstIndex { $0 == "discardRow" }, "S-22310 the menu carries Discard Session")
        XCTAssertEqual(finish, stack + 1, "S-22310 End Session is the stack's first row")
        XCTAssertEqual(discard, finish + 1, "S-22310 Discard follows End Session with no line between")
        XCTAssertEqual(lines[discard + 1], "}", "S-22310 and nothing follows it in the stack (S-17101)")

        let rowUsages = lines.enumerated().compactMap { index, line -> Int? in
            (line == "finishRow" || line == "discardRow" || line == "addExerciseRow" || line == "rowButton(row)")
                ? index : nil
        }
        XCTAssertEqual(rowUsages.last, discard, "S-22310 Discard is the menu's last row usage")
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

    /// The same gap sits on both sides of the menu's separator and around the start
    /// screen's Sync separator (10 pt on top of the stack's own spacing), so the
    /// groups read the same everywhere. A source scan, like S-3104A above.
    func testS3104BTheSameGapSitsAroundEverySeparator() throws {
        let menu = try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        let start = try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift")
        XCTAssertTrue(menu.contains("fileprivate static let sectionGap = 10.0"), "S-3104B the menu's gap is 10 pt")
        XCTAssertTrue(start.contains("private static let sectionGap = 10.0"), "S-3104B the start screen's gap is the same 10 pt")

        let menuLines = sourceLines(menu)
        let divider = try XCTUnwrap(usageLine(of: "Divider()", in: menuLines), "S-3104B the menu has its separator")
        XCTAssertEqual(
            nextLine(after: divider, in: menuLines),
            ".padding(.top, Self.sectionGap)",
            "S-3104B the gap above the menu's separator"
        )
        let add = try XCTUnwrap(usageLine(of: "addExerciseRow", in: menuLines), "S-3104B Add Exercise follows")
        XCTAssertEqual(
            nextLine(after: add, in: menuLines),
            ".padding(.top, Self.sectionGap)",
            "S-3104B the gap below the menu's separator"
        )

        let startLines = sourceLines(start)
        let syncDivider = try XCTUnwrap(usageLine(of: "Divider()", in: startLines), "S-3104B the start screen has its Sync separator")
        XCTAssertEqual(
            nextLine(after: syncDivider, in: startLines),
            ".padding(.vertical, Self.sectionGap)",
            "S-3104B the gap on both sides of the Sync separator"
        )
        XCTAssertTrue(
            startLines.contains { $0.trimmingCharacters(in: .whitespaces) == ".padding(.bottom, Self.sectionGap)" },
            "S-3104B the gap under the modality grid"
        )
        XCTAssertTrue(
            startLines.contains { $0.trimmingCharacters(in: .whitespaces) == ".padding(.top, Self.sectionGap)" },
            "S-3104B the gap above the Nutrition button"
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

    // MARK: - S-19923/S-19912 the groups the list is read in (plan 199)

    /// The harness session has no modality, so the Add Exercise list over it is
    /// one untitled group whose names equal `addableExercises` in the list's own
    /// order (plan 199, D-19905, S-19923): the 25-name catalog, each exercise
    /// once, nothing reordered.
    func testS19923TheAddExerciseListIsOneUntitledGroupWithNoModality() async {
        let harness = await WatchMenuHarness().launch()
        await harness.applyLetterCatalog(letterCatalogNames)

        let offered = harness.menu.addableExercises
        let groups = harness.menu.addExerciseGroups

        XCTAssertEqual(groups.count, 1, "S-19923 the 25-name list is one group")
        XCTAssertNil(groups.first?.title, "S-19923 one group wears no title")
        XCTAssertEqual(
            groups.first?.exercises.map(\.name),
            offered.map(\.name),
            "S-19923 the group is the list itself, in the list's own order"
        )
        XCTAssertEqual(
            groups.first?.exercises.count,
            offered.count,
            "S-19923 each exercise appears once"
        )

        let small = await WatchMenuHarness().launch()
        await small.applyLetterCatalog(["apple", "banana", "cherry"])
        let smallGroups = small.menu.addExerciseGroups
        XCTAssertEqual(smallGroups.count, 1, "S-19923 a three-name list is one group too")
        XCTAssertNil(smallGroups.first?.title, "S-19923 and it wears no title")
        XCTAssertEqual(
            smallGroups.first?.exercises.map(\.name),
            ["apple", "banana", "cherry"],
            "S-19923 the input order is untouched"
        )

        let empty = await WatchMenuHarness().launch()
        XCTAssertTrue(empty.menu.addableExercises.isEmpty, "S-19923 the fresh wrist offers nothing")
        XCTAssertEqual(empty.menu.addExerciseGroups, [], "S-19923 an empty list has no groups")
    }

    /// The grid is deleted with every symbol that only served it (D-19901,
    /// S-19912): the list view carries no scroll machinery, and the deleted
    /// names occur in no file the watch package compiles.
    func testS19912TheLetterGridAndItsSymbolsAreGone() throws {
        let list = try menuSource(
            "watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift"
        )
        XCTAssertFalse(list.contains("LazyVGrid"), "S-19912 the list view has no LazyVGrid")
        XCTAssertFalse(list.contains("letterGrid"), "S-19912 the list view has no letterGrid")
        XCTAssertFalse(list.contains("ScrollViewReader"), "S-19912 the list view has no ScrollViewReader")
        XCTAssertFalse(list.contains("scrollTo"), "S-19912 the list view has no scrollTo")

        let files = try FileManager.default
            .contentsOfDirectory(at: Fixtures.sourcesRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        // The watch app target compiles its own Swift files beside the package's
        // Sources: the walk reaches those too, so a deleted symbol cannot hide
        // there.
        let appRoot = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App", isDirectory: true)
        var appFiles: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: appRoot,
            includingPropertiesForKeys: nil
        ) {
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                appFiles.append(url)
            }
        }
        XCTAssertFalse(
            appFiles.isEmpty,
            "S-19912 the watch app target directory was found and its Swift files walked"
        )

        for name in [
            "WatchAddExerciseLetter",
            "addExerciseLetterKey",
            "deriveAddExerciseLetters",
            "scrollTargetLetters",
            "deriveExerciseListLetters",
            "addLetterGridThreshold",
            "addLetterJumpLabel",
            "addExerciseLetters",
            "WatchExerciseLetterList",
        ] {
            for file in files + appFiles {
                let relative = file.path.dropFirst(Fixtures.repositoryRoot.path.count + 1)
                let source = try menuSource(String(relative))
                XCTAssertFalse(
                    source.contains(name),
                    "S-19912 \(name) occurs nowhere in Sources or the watch app target, found in \(file.lastPathComponent)"
                )
            }
        }
    }

    // MARK: - S-19907/S-19908/S-19917/S-19918/S-19919 the modality grouping (plan 199)

    /// The list's A-to-Z walk, each exercise named with the recommendation the
    /// phone sent for it. Pure `deriveExerciseGroups` — no harness.
    private func modalityList(
        _ exercises: [(name: String, recommendedFor: [String])]
    ) -> [WatchCatalogExercise] {
        exercises.map {
            WatchCatalogExercise(
                exerciseId: "ex-\($0.name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                name: $0.name,
                capabilities: ["reps"],
                recommendedFor: $0.recommendedFor
            )
        }
    }

    /// A stable partition, Recommended then Other, each keeping the A-to-Z
    /// order, titles the phone's own words (plan 199, D-19905, S-19907).
    func testS19907TheModalityListSplitsIntoRecommendedThenOther() {
        let input = modalityList([
            (name: "Arm Curl", recommendedFor: ["resistance_lifting"]),
            (name: "Bike", recommendedFor: ["cardio_endurance"]),
            (name: "Climb", recommendedFor: ["cardio_endurance"]),
            (name: "Dips", recommendedFor: ["resistance_lifting"]),
            (name: "Zumba", recommendedFor: ["cardio_endurance"]),
        ])

        let groups = deriveExerciseGroups(input, modality: "cardio_endurance")

        XCTAssertEqual(groups.count, 2, "S-19907 the list splits into two groups")
        XCTAssertEqual(
            groups.first?.title,
            WatchMenuCopy.recommendedGroupTitle,
            "S-19907 the first group wears the phone's Recommended word"
        )
        XCTAssertEqual(
            groups.last?.title,
            WatchMenuCopy.otherGroupTitle,
            "S-19907 the second group wears the phone's Other word"
        )
        XCTAssertEqual(
            groups.first?.exercises.map(\.name),
            ["Bike", "Climb", "Zumba"],
            "S-19907 the recommended exercises, in the input's own order"
        )
        XCTAssertEqual(
            groups.last?.exercises.map(\.name),
            ["Arm Curl", "Dips"],
            "S-19907 the others, in the input's own order"
        )
        XCTAssertEqual(
            groups.flatMap(\.exercises).map(\.name),
            ["Bike", "Climb", "Zumba", "Arm Curl", "Dips"],
            "S-19907 the concatenation holds each exercise exactly once"
        )
    }

    /// One non-empty group is untitled, whichever side is empty
    /// (plan 199, D-19905, S-19908).
    func testS19908OneNonEmptyGroupIsOneUntitledGroup() {
        let allRecommended = modalityList([
            (name: "Bike", recommendedFor: ["cardio_endurance"]),
            (name: "Climb", recommendedFor: ["cardio_endurance"]),
        ])
        let allGroups = deriveExerciseGroups(allRecommended, modality: "cardio_endurance")
        XCTAssertEqual(allGroups.count, 1, "S-19908 all recommended is one group")
        XCTAssertNil(allGroups.first?.title, "S-19908 and it wears no title")
        XCTAssertEqual(allGroups.first?.exercises, allRecommended, "S-19908 the input is returned untouched")

        let noneRecommended = modalityList([
            (name: "Arm Curl", recommendedFor: ["resistance_lifting"]),
            (name: "Dips", recommendedFor: ["resistance_lifting"]),
        ])
        let noneGroups = deriveExerciseGroups(noneRecommended, modality: "cardio_endurance")
        XCTAssertEqual(noneGroups.count, 1, "S-19908 none recommended is one group too")
        XCTAssertNil(noneGroups.first?.title, "S-19908 and it wears no title either")
        XCTAssertEqual(noneGroups.first?.exercises, noneRecommended, "S-19908 the input is returned untouched")
    }

    /// No modality is one plain A-to-Z run even when exercises carry keys, and
    /// an empty list has no groups (plan 199, D-19905, S-19909).
    func testS19909NoModalityIsOneUntitledGroupEvenWhenExercisesCarryKeys() {
        let input = modalityList([
            (name: "Bike", recommendedFor: ["cardio_endurance"]),
            (name: "Dips", recommendedFor: ["resistance_lifting"]),
        ])

        let groups = deriveExerciseGroups(input, modality: nil)
        XCTAssertEqual(groups.count, 1, "S-19909 no modality is one group")
        XCTAssertNil(groups.first?.title, "S-19909 and it wears no title")
        XCTAssertEqual(groups.first?.exercises, input, "S-19909 the input order is untouched")

        XCTAssertEqual(
            deriveExerciseGroups([], modality: "cardio_endurance"),
            [],
            "S-19909 an empty list has no groups"
        )
        XCTAssertEqual(
            deriveExerciseGroups([], modality: nil),
            [],
            "S-19909 an empty list has no groups with no modality either"
        )
    }

    /// An unknown key is kept in the model but matches no modality, so the
    /// exercise is Other (plan 199, D-19905, S-19917).
    func testS19917AnUnknownRecommendationIsKeptAndIsOther() {
        let input = modalityList([
            (name: "Broom Twist", recommendedFor: ["curling"]),
        ])

        let groups = deriveExerciseGroups(input, modality: "sports")
        XCTAssertEqual(groups.count, 1, "S-19917 curling is not sports, so one group")
        XCTAssertNil(groups.first?.title, "S-19917 and it is untitled: only the exercise is in it")
        XCTAssertEqual(groups.first?.exercises.first?.recommendedFor, ["curling"], "S-19917 the key is kept in the model")

        let both = deriveExerciseGroups(
            input + modalityList([(name: "Tennis Drill", recommendedFor: ["sports"])]),
            modality: "sports"
        )
        XCTAssertEqual(both.count, 2, "S-19917 beside a sports exercise the two split")
        XCTAssertEqual(both.last?.exercises.map(\.name), ["Broom Twist"], "S-19917 the curling exercise is Other")
    }

    /// The wire has no `uniqueItems` (D-19904): a repeated key matches once and
    /// the exercise appears exactly once in the concatenation
    /// (plan 199, D-19905, S-19918).
    func testS19918ARepeatedKeyMatchesOnceAndAppearsOnce() {
        let input = modalityList([
            (name: "Tennis Drill", recommendedFor: ["sports", "sports"]),
        ])

        let groups = deriveExerciseGroups(input, modality: "sports")
        XCTAssertEqual(
            groups.flatMap(\.exercises),
            input,
            "S-19918 the concatenation holds the exercise exactly once"
        )
        XCTAssertEqual(
            groups.first?.exercises.first?.recommendedFor,
            ["sports", "sports"],
            "S-19918 the wire's values are kept verbatim"
        )
    }

    /// An exercise whose name is empty keeps its input position within its
    /// group — no special case (plan 199, S-19919).
    func testS19919AnEmptyNameKeepsItsInputPositionWithinItsGroup() {
        let input = modalityList([
            (name: "Arm Curl", recommendedFor: ["resistance_lifting"]),
            (name: "", recommendedFor: ["cardio_endurance"]),
            (name: "Zumba", recommendedFor: ["cardio_endurance"]),
        ])

        let groups = deriveExerciseGroups(input, modality: "cardio_endurance")
        XCTAssertEqual(groups.count, 2, "S-19919 the list splits")
        XCTAssertEqual(
            groups.first?.exercises.map(\.name),
            ["", "Zumba"],
            "S-19919 the empty name keeps its place in its group"
        )
        XCTAssertEqual(
            groups.last?.exercises.map(\.name),
            ["Arm Curl"],
            "S-19919 and the others keep theirs"
        )
        XCTAssertEqual(
            groups.flatMap(\.exercises).map(\.name),
            ["", "Zumba", "Arm Curl"],
            "S-19919 the concatenation holds each exercise exactly once"
        )
    }

    // MARK: - S-19913/S-19920 the grouped surfaces' source guards (plan 199)

    /// Both entry points pass `listModality` — no nil modality anywhere
    /// (plan 199, D-19906, S-19913).
    func testS19913BothEntryPointsGroupWithTheRealModality() throws {
        let start = try menuSource(
            "watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift"
        )
        XCTAssertEqual(
            occurrences(
                of: "groups: deriveExerciseGroups(paths.availablePickerExercises, modality: paths.listModality),",
                in: start
            ),
            1,
            "S-19913 the picker passes the listModality grouping, exactly once"
        )
        XCTAssertFalse(
            start.contains("modality: nil"),
            "S-19913 no entry point passes a nil modality any more"
        )

        let menu = try menuSource(
            "watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift"
        )
        XCTAssertEqual(
            occurrences(of: "deriveExerciseGroups(addableExercises, modality: paths.listModality)", in: menu),
            1,
            "S-19913 the menu's Add Exercise list reads the same accessor, exactly once"
        )
    }

    /// The titled groups are section headers for VoiceOver; the untitled group
    /// adds none (plan 199, S-19920).
    func testS19920TheTitledGroupsAreHeadersAndTheUntitledAddsNone() throws {
        let list = try menuSource(
            "watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift"
        )
        XCTAssertTrue(
            list.contains("if let title = group.title {"),
            "S-19920 the header is drawn only for a titled group"
        )
        XCTAssertTrue(list.contains("Text(title)"), "S-19920 the header row is the group's title")
        XCTAssertTrue(list.contains("} header: {"), "S-19920 the titled group carries a header")
        XCTAssertFalse(
            list.contains("Section(header"),
            "S-19920 no header is built unconditionally"
        )
        XCTAssertFalse(
            list.contains("Text(group.title"),
            "S-19920 no header is drawn from the optional itself: an untitled group adds no header row"
        )
    }
}

// MARK: - Reading one property's body

/// The lines of the property `name`, from its declaration through the brace that
/// closes it, or nil when the file declares no such property.
private func propertyBlock(_ name: String, in lines: [String]) -> [String]? {
    guard let start = lines.firstIndex(where: { $0.contains("var \(name):") }) else {
        return nil
    }

    var depth = 0
    var block: [String] = []
    for line in lines[start...] {
        block.append(line)
        depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
        if depth == 0, block.count > 1 { return block }
    }
    return nil
}

/// The lines from the first line containing `marker` through the brace that
/// closes the block it opens, or nil when the file carries no such marker. A
/// marker whose line opens no brace walks to the first line that does, so a
/// multi-line signature is read whole.
private func block(from marker: String, in lines: [String]) -> [String]? {
    guard var start = lines.firstIndex(where: { $0.contains(marker) }) else {
        return nil
    }
    while !lines[start].contains("{") {
        start += 1
        guard start < lines.count else { return nil }
    }

    var depth = 0
    var block: [String] = []
    for line in lines[start...] {
        block.append(line)
        depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
        if depth == 0, block.count > 1 { return block }
    }
    return nil
}

// MARK: - S-17101 to S-17112 Discard Session (plan 171)

/// Plan: `docs/plans/2026-11-14-171-watch-discard-workout-plan/2026-11-14-171-watch-discard-workout-plan.md`,
/// phases 1 and 2: the menu's Discard row.
///
/// The model cases run over `WatchMenuHarness`, so the discard the row makes is
/// the engine's own abandonment and the frames below are the ones the phone
/// would receive. The view cases are source scans: the watch target's views are
/// compiled only by the watch scheme, so `swift test` can hold their shape but
/// not run them; the drawn row and its dialog are the owner's device check
/// (`docs/watch-app-qa-wrist-logging.md`, step 44).
final class WatchMenuDiscardTests: XCTestCase {

    // MARK: - S-17102 confirm-then-discard, and Cancel changes nothing

    /// D-17102: a discard is `abandonSession()`, so the session ends `abandoned`
    /// and the phone hears the terminal lifecycle frame the engine builds for
    /// it, stamped with the wrist's own instant (D-120). Cancel is the view's
    /// own no-op, asserted below in the source scan.
    func testS17102DiscardAbandonsAtTheWristsInstantAndTellsThePhone() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        XCTAssertEqual(harness.engine.session?.status, WatchSessionStatus.active, "S-17102 the fixture is live")
        XCTAssertTrue(harness.emitted("session_lifecycle").isEmpty, "S-17102 nothing has ended yet, so Cancel has nothing to undo")

        harness.clock.advance(120)
        let discarded = await harness.menu.discard()
        let ended = try XCTUnwrap(discarded, "S-17102 a discard hands back the ended record")

        XCTAssertEqual(harness.engine.session?.status, WatchSessionStatus.abandoned, "S-17102 the session ends abandoned")
        XCTAssertEqual(ended.status, WatchSessionStatus.abandoned, "S-17102 and the record says so")
        XCTAssertEqual(ended.recordedAt, harness.clock.call(), "D-120 the end is stamped at the wrist's instant")

        let frames = harness.emitted("session_lifecycle")
        XCTAssertEqual(frames.count, 1, "S-17102 one abandonment frame, no more")
        let payload = try XCTUnwrap(
            try XCTUnwrap(frames.first, "S-17102 the frame is emitted")["payload"] as? [String: Any],
            "S-17102 the frame carries a payload"
        )
        XCTAssertEqual(frames.first?["sessionId"] as? String, harness.sessionId, "S-17102 it names the session")
        XCTAssertEqual(payload["state"] as? String, WatchLifecycleState.abandoned, "S-17102 the phone hears `abandoned`")
        XCTAssertEqual(payload["at"] as? String, utcIso(harness.clock.call()), "S-17102 stamped with the discard's own instant")
    }

    /// The view's half of S-17102: `state.discard()` is reached from the
    /// question's destructive Discard alone, Cancel runs nothing, and no haptic
    /// plays (D-17104). The question is the menu's own screen
    /// (plan 223, D-22309), not a system alert.
    func testS17102TheViewDiscardsOnlyFromTheQuestionsDiscardButton() throws {
        let source = try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        let question = try XCTUnwrap(
            propertyBlock("discardQuestion", in: sourceLines(source)),
            "S-17102 the menu view has a discardQuestion"
        )

        XCTAssertEqual(occurrences(of: "state.discard()", in: source), 1, "S-17102 the model's discard is reached from one place")
        let confirm = try XCTUnwrap(
            question.firstIndex {
                $0.trimmingCharacters(in: .whitespaces)
                    == "Button(WatchMenuCopy.discardConfirmDiscard, role: .destructive) {"
            },
            "S-17102 the question carries a destructive Discard"
        )
        let cancel = try XCTUnwrap(
            question.firstIndex {
                $0.trimmingCharacters(in: .whitespaces)
                    == "Button(WatchMenuCopy.discardConfirmCancel, role: .cancel) {"
            },
            "S-17102 the question carries a Cancel"
        )
        let call = try XCTUnwrap(
            question.firstIndex { $0.contains("await state.discard()") },
            "S-17102 the question's Discard runs the model's discard"
        )
        XCTAssertGreaterThan(call, confirm, "S-17102 and only that button does")
        XCTAssertLessThan(call, cancel, "S-17102 the Discard runs before Cancel is reached")
        XCTAssertEqual(
            question[cancel + 1].trimmingCharacters(in: .whitespaces),
            "confirmingDiscard = false",
            "S-17102 Cancel is a no-op"
        )
        XCTAssertTrue(
            question.contains { $0.trimmingCharacters(in: .whitespaces) == "title: WatchMenuCopy.discardConfirmTitle," },
            "S-17102 the question is the discard's own"
        )
        XCTAssertTrue(
            question.contains { $0.trimmingCharacters(in: .whitespaces) == "message: WatchMenuCopy.discardConfirmBody" },
            "S-17102 and the message is its body"
        )
        XCTAssertTrue(
            question.contains { $0.trimmingCharacters(in: .whitespaces) == "onDiscard()" },
            "S-17102 the shell is handed the surface back after the discard"
        )
        XCTAssertFalse(question.contains { $0.contains("haptics") }, "D-17104 confirming a discard plays nothing")
    }

    // MARK: - S-17101 the row sits at the bottom of the menu

    /// D-17101: the Discard row is the menu's last row, below End Session, the
    /// one filled red row, and never disabled (D-17103).
    func testS17101TheDiscardRowIsTheMenusLastRow() throws {
        let lines = sourceLines(try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift"))
        let finish = try XCTUnwrap(usageLine(of: "finishRow", in: lines), "S-17101 the menu has its End Session row")
        let discard = try XCTUnwrap(usageLine(of: "discardRow", in: lines), "S-17101 the menu has a Discard row")
        XCTAssertGreaterThan(discard, finish, "S-17101 Discard is below End Session")
        XCTAssertEqual(nextLine(after: discard, in: lines), "}", "S-17101 and nothing follows it in the stack")

        let body = try XCTUnwrap(propertyBlock("discardRow", in: lines), "S-17101 the row is the menu's own builder")
        XCTAssertTrue(
            body.contains { $0.trimmingCharacters(in: .whitespaces) == ".buttonStyle(.borderedProminent)" },
            "S-17101 the Discard row is the one filled red row"
        )
        XCTAssertTrue(
            body.contains { $0.trimmingCharacters(in: .whitespaces) == ".tint(.red)" },
            "S-17101 the Discard row is the one filled red row"
        )
        XCTAssertFalse(
            body.contains { $0.trimmingCharacters(in: .whitespaces) == ".buttonStyle(.bordered)" },
            "S-17101 the Discard row is the one filled red row"
        )
        XCTAssertFalse(body.contains { $0.contains(".disabled") }, "D-17103 the row is never disabled")
        let question = try XCTUnwrap(
            propertyBlock("discardQuestion", in: lines),
            "S-17101 the row raises the menu's own question"
        )
        XCTAssertTrue(
            question.contains { $0.contains("role: .destructive") },
            "S-17101 its question's Discard is destructive"
        )
    }

    // MARK: - S-17103 Discard is reachable mid-set

    /// D-17103: the model has no lock guard, so a running work clock cannot
    /// strand a session the user wants to throw away. The clock ends with the
    /// session, on the engine's own terminal rule (D-14603).
    func testS17103DiscardIsReachableMidSet() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        _ = try await harness.engine.startTimer(WatchTimerKind.round, sessionExerciseId: "s1")
        XCTAssertTrue(harness.menu.isLocked, "S-17103 the fixture is mid-set, so the menu's rows are inert")

        harness.clock.advance(45)
        let discarded = await harness.menu.discard()
        let ended = try XCTUnwrap(discarded, "S-17103 a locked menu still discards")

        XCTAssertEqual(ended.status, WatchSessionStatus.abandoned, "S-17103 the session ends")
        let afterDiscard = (harness.engine.timerFor(WatchTimerKind.round)?.state, harness.engine.timerFor(WatchTimerKind.round)?.stoppedAt)

        // The control: the same fixture ended through End Session. Both go
        // through the engine's one transition, so the running clock must come
        // out of a discard exactly as it comes out of an End (D-14602/D-223).
        let control = await WatchMenuHarness().launch()
        await control.fixtureA()
        _ = try await control.engine.startTimer(WatchTimerKind.round, sessionExerciseId: "s1")
        control.clock.advance(45)
        await control.menu.finish()

        XCTAssertEqual(control.engine.session?.status, WatchSessionStatus.completed, "S-17103 the control ends")
        let afterFinish = (control.engine.timerFor(WatchTimerKind.round)?.state, control.engine.timerFor(WatchTimerKind.round)?.stoppedAt)
        XCTAssertEqual(
            afterDiscard.0.map { String(describing: $0) },
            afterFinish.0.map { String(describing: $0) },
            "D-14602 the running clock ends with the session, exactly as End's does"
        )
        XCTAssertEqual(afterDiscard.1, afterFinish.1, "D-14602 at the same kind of instant")
    }

    // MARK: - S-17104 Discard during a rest stops the rest

    /// D-223: the end stops the rest before the terminal row, and the rest that
    /// ran travels as its own observation, hung on the entry it followed
    /// (D-221) — the phone's session is then abandoned with its rest inside it.
    func testS17104DiscardDuringARestStopsTheRest() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)
        let logged = try await surface.log()
        XCTAssertTrue(surface.isResting, "S-17104 logging a set starts its rest")

        harness.clock.advance(30)
        _ = await harness.menu.discard()

        XCTAssertFalse(surface.isResting, "S-17104 the rest is stopped")
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.rest)?.stoppedAt,
            harness.clock.call(),
            "S-17104 at the discard's own instant"
        )

        let rest = try XCTUnwrap(
            harness.emitted("observations_up").compactMap { frame in
                ((frame["payload"] as? [String: Any])?["events"] as? [[String: Any]])?
                    .first { $0["kind"] as? String == WatchObservationKind.rest }
            }.first,
            "S-17104 the rest that ran is announced"
        )
        XCTAssertEqual(rest["afterEntryId"] as? String, logged.recordId, "D-221 the rest hangs on the entry it followed")
        XCTAssertEqual(rest["endedAt"] as? String, utcIso(harness.clock.call()), "S-17104 ending at the discard")
    }

    // MARK: - S-17105 no rating prompt for a discard

    /// D-17105: a discarded session owes no rating, because the rating state is
    /// never reached. The control at the end finishes the same fixture and does
    /// owe one, so the absence is the discard's doing and not the fixture's.
    func testS17105ADiscardOwesNoRatingPrompt() async throws {
        do {
            let harness = await WatchMenuHarness().launch()
            await harness.fixtureA()
            _ = await harness.preferences.applyPreferencesDown(
                preferencesDown(true, generatedAt: "2026-07-13T05:59:00Z")
            )
            await harness.rating.restore()
            XCTAssertTrue(harness.preferences.asksForEffortRating, "S-17105 the phone asks for a rating")

            _ = await harness.menu.discard()

            XCTAssertTrue(harness.rating.owedSessionIds.isEmpty, "S-17105 a discarded session owes no rating")
            let prompts = await harness.store.readAll().ratingPrompts
            XCTAssertTrue(prompts.isEmpty, "S-17105 and no prompt row is stored")
        }

        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        _ = await harness.preferences.applyPreferencesDown(
            preferencesDown(true, generatedAt: "2026-07-13T05:59:00Z")
        )
        await harness.rating.restore()
        await harness.menu.finish()
        XCTAssertEqual(
            harness.rating.owedSessionIds,
            [harness.sessionId],
            "S-17105 the control: finishing the same fixture owes one"
        )
    }

    // MARK: - S-17107 the first ending is final

    /// D-14602/D-17102: the engine hands back the held row when the status is
    /// already terminal, so a discard after a finish, or a second discard,
    /// appends nothing and announces nothing.
    func testS17107TheFirstEndingIsFinalForDiscard() async throws {
        do {
            let harness = await WatchMenuHarness().launch()
            await harness.fixtureA()
            await harness.menu.finish()
            XCTAssertEqual(harness.engine.session?.status, WatchSessionStatus.completed, "S-17107 the fixture is finished")
            let frames = harness.emitted("session_lifecycle").count
            let rows = await harness.store.readAll().observations.count

            harness.clock.advance(60)
            let held = await harness.menu.discard()

            XCTAssertEqual(held?.status, WatchSessionStatus.completed, "S-17107 the held record comes back unchanged")
            XCTAssertEqual(harness.engine.session?.status, WatchSessionStatus.completed, "S-17107 a finished session stays finished")
            XCTAssertEqual(harness.emitted("session_lifecycle").count, frames, "S-17107 nothing new is announced")
            let after = await harness.store.readAll().observations.count
            XCTAssertEqual(after, rows, "S-17107 and no row is appended")
        }

        do {
            let harness = await WatchMenuHarness().launch()
            await harness.fixtureA()
            let discarded = await harness.menu.discard()
            let first = try XCTUnwrap(discarded, "S-17107 the first discard ends the session")
            let frames = harness.emitted("session_lifecycle").count
            let rows = await harness.store.readAll().observations.count

            harness.clock.advance(60)
            let held = await harness.menu.discard()

            XCTAssertEqual(held?.recordId, first.recordId, "S-17107 a second discard hands back the same record")
            XCTAssertEqual(harness.emitted("session_lifecycle").count, frames, "S-17107 nothing new is announced")
            let after = await harness.store.readAll().observations.count
            XCTAssertEqual(after, rows, "S-17107 and no row is appended")
        }
    }

    // MARK: - S-17108 the platform workout is discarded, never saved

    /// The record the discard produced is what the coordinator sees, and a
    /// non-active session ends the platform workout with `saving: false`
    /// (plan 89 D-1) — so nothing reaches Health for a workout the user threw
    /// away.
    func testS17108TheDiscardedRecordEndsThePlatformWorkoutUnsaved() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        let active = try XCTUnwrap(harness.engine.session, "S-17108 the fixture has a live session")

        let store = ScriptedPlatformStore()
        let platform = WatchPlatformWorkout(store: store)
        let coordinator = WatchWorkoutCoordinator(platform: platform)
        await coordinator.refresh(active)
        XCTAssertEqual(store.begun.count, 1, "S-17108 the live session opened a workout")

        let discarded = await harness.menu.discard()
        let ended = try XCTUnwrap(discarded, "S-17108 the discard ends the session")
        await coordinator.refresh(ended)

        XCTAssertEqual(store.endSavings, [false], "S-17108 the workout is discarded, never saved")
        XCTAssertNil(platform.running, "S-17108 and nothing is left open")
    }

    // MARK: - S-17109 an empty End behaves as a Discard

    /// D-17105: an End with nothing logged is a discard — the phone's own empty
    /// finish discards too — so nothing empty is saved, no rating is asked for,
    /// and the phone hears an abandonment.
    func testS17109AnEmptyEndBehavesAsADiscard() async throws {
        do {
            let harness = await WatchMenuHarness().launch()
            let active = await harness.engine.createSession(modality: "sports")
            XCTAssertFalse(harness.menu.hasLoggedEfforts, "S-17109 nothing is logged yet")

            let store = ScriptedPlatformStore()
            let platform = WatchPlatformWorkout(store: store)
            let coordinator = WatchWorkoutCoordinator(platform: platform)
            await coordinator.refresh(active)

            await harness.menu.finish()

            XCTAssertEqual(harness.engine.session?.status, WatchSessionStatus.abandoned, "S-17109 an empty End discards")
            XCTAssertTrue(harness.rating.owedSessionIds.isEmpty, "S-17109 and asks for no rating")
            await coordinator.refresh(harness.engine.session)
            XCTAssertEqual(store.endSavings, [false], "S-17109 nothing empty is saved to Health")

            let payload = try XCTUnwrap(
                try XCTUnwrap(harness.emitted("session_lifecycle").last, "S-17109 the phone is told")["payload"] as? [String: Any]
            )
            XCTAssertEqual(payload["state"] as? String, WatchLifecycleState.abandoned, "S-17109 as an abandonment")
        }

        // A rest, a water tap and a food entry are not the workout: an End on a
        // session holding nothing but those is still an empty one.
        do {
            let harness = await WatchMenuHarness().launch()
            _ = await harness.engine.createSession(modality: "sports")
            _ = try await harness.engine.logWaterGlass(.add, loggedAt: harness.clock.call())
            _ = try await harness.engine.logNutrition(
                foodId: "food-oats",
                servings: 1,
                calories: 120,
                loggedAt: harness.clock.call()
            )
            XCTAssertFalse(harness.menu.hasLoggedEfforts, "S-17109 water and food are not an effort")

            await harness.menu.finish()

            XCTAssertEqual(
                harness.engine.session?.status,
                WatchSessionStatus.abandoned,
                "S-17109 a session holding only water and food is still empty"
            )
        }

        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        XCTAssertTrue(harness.menu.hasLoggedEfforts, "S-17109 fixture A holds efforts")
        await harness.menu.finish()
        XCTAssertEqual(
            harness.engine.session?.status,
            WatchSessionStatus.completed,
            "S-17109 an End with something logged finishes, as today"
        )
    }

    /// The view's half of S-17109: End reads the emptiness rule, and the empty
    /// path raises the discard question instead of the Finish one.
    func testS17109TheEmptyEndRaisesTheDiscardAlert() throws {
        let body = try XCTUnwrap(
            propertyBlock(
                "finishRow",
                in: sourceLines(try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift"))
            ),
            "S-17109 the menu view has a finishRow"
        )

        let rule = try XCTUnwrap(
            body.firstIndex { $0.contains("state.hasWorkToSave") },
            "S-17109 End reads the save rule"
        )
        let finish = try XCTUnwrap(
            body.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "confirmingFinish = true" },
            "S-17109 the Finish question is raised"
        )
        let discard = try XCTUnwrap(
            body.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "confirmingDiscard = true" },
            "S-17109 the discard question is raised"
        )
        XCTAssertGreaterThan(finish, rule, "S-17109 an End with something logged asks Finish")
        XCTAssertGreaterThan(discard, finish, "S-17109 and an empty one asks Discard instead")
    }

    // MARK: - S-17110 the logged entries stay; no summary appears

    /// `abandonSession` deletes nothing wrist-side: the entries stay readable,
    /// and an abandoned session owes no summary, so the wrist returns to the
    /// start surface rather than showing one (S-9605).
    func testS17110DiscardKeepsTheLoggedEntriesAndShowsNoSummary() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        let summary = WatchWorkoutSummaryState(engine: harness.engine)
        summary.note(harness.engine.session)
        XCTAssertNil(summary.pending, "S-17110 a live session shows no summary")

        _ = await harness.menu.discard()

        let efforts = harness.engine.entries.filter { WatchObservationKind.efforts.contains($0.kind) }
        XCTAssertEqual(
            Set(efforts.map(\.recordId)),
            ["e-s1-1", "e-s1-2", "e-s3-1"],
            "S-17110 the logged entries stay, and the phone's own deletion still wins"
        )

        summary.note(harness.engine.session)
        XCTAssertNil(summary.pending, "S-17110 an abandoned session owes no summary")
    }

    // MARK: - S-17111 water and food are unaffected

    /// Water and food are the wrist's own rows, outside the session, and the
    /// discard touches only the session's — so a discarded workout leaves the
    /// day's intake alone.
    func testS17111DiscardLeavesWaterAndFoodUntouched() async throws {
        let harness = await WatchMenuHarness().launch()
        await harness.fixtureA()
        let water = try await harness.engine.logWaterGlass(.add, loggedAt: harness.clock.call())
        let food = try await harness.engine.logNutrition(
            foodId: "food-oats",
            servings: 1.5,
            calories: 320,
            loggedAt: harness.clock.call()
        )

        _ = await harness.menu.discard()

        XCTAssertEqual(harness.engine.waterLog.map(\.recordId), [water.recordId], "S-17111 the water row is untouched")
        XCTAssertEqual(harness.engine.nutritionLog.map(\.recordId), [food.recordId], "S-17111 and so is the food row")
    }

    // MARK: - Plan 171 item 5: the shell hands the surface back

    /// The sheet's dismissal is the shell's, as it is for Close and Finish: the
    /// discard's confirmation closes the menu and tells the host the surface
    /// changed, so the wrist lands on whatever the session's status now means.
    /// No scenario id: the wiring is Phase 2 item 5, pinned by this scan.
    func testTheShellPassesTheDiscardClosure() throws {
        let lines = sourceLines(try menuSource("ios/OmniTrain Watch App/ContentView.swift"))
        let menu = try XCTUnwrap(lines.firstIndex { $0.contains("WatchMenuView(") }, "the shell builds the menu")
        let call = lines[menu...].prefix(24).joined(separator: "\n")

        XCTAssertTrue(call.contains("onClose:"), "the menu is handed its close")
        XCTAssertTrue(call.contains("onFinish:"), "and its finish")
        let discard = try XCTUnwrap(call.range(of: "onDiscard:"), "and its discard (plan 171)")
        let closure = String(call[discard.lowerBound...])
        XCTAssertTrue(closure.contains("isPresented.wrappedValue = false"), "which closes the sheet")
        XCTAssertTrue(closure.contains("host.noteSurfaceChange()"), "and tells the host the surface changed")
    }

    // MARK: - Plan 201: the rows wear their colours, End reads the save rule

    /// Plan: `docs/plans/2026-11-15-201-watch-flow-fixes-plan/2026-11-15-201-watch-flow-fixes-plan.md`,
    /// D-20103: the End row wears the accent fill, the Discard row is the one
    /// filled red row, and no other row's style changed.
    func testS20106TheMenuRowsWearTheirColours() throws {
        let source = try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift")
        let lines = sourceLines(source)

        let finish = try XCTUnwrap(propertyBlock("finishRow", in: lines), "S-20106 the menu view has a finishRow")
        XCTAssertTrue(
            finish.contains { $0.trimmingCharacters(in: .whitespaces) == ".watchProminent()" },
            "S-20106 the End row wears the accent fill"
        )
        XCTAssertFalse(
            finish.contains { $0.trimmingCharacters(in: .whitespaces) == ".buttonStyle(.bordered)" },
            "S-20106 the End row is not the plain row"
        )

        let discard = try XCTUnwrap(propertyBlock("discardRow", in: lines), "S-20106 the menu view has a discardRow")
        XCTAssertTrue(
            discard.contains { $0.trimmingCharacters(in: .whitespaces) == ".buttonStyle(.borderedProminent)" },
            "S-20106 the Discard row is the filled row"
        )
        XCTAssertTrue(
            discard.contains { $0.trimmingCharacters(in: .whitespaces) == ".tint(.red)" },
            "S-20106 the Discard row is red"
        )
        XCTAssertFalse(
            discard.contains { $0.trimmingCharacters(in: .whitespaces) == ".buttonStyle(.bordered)" },
            "S-20106 the Discard row is not the plain row"
        )
        XCTAssertEqual(
            occurrences(of: ".tint(.red)", in: source),
            1,
            "S-20106 the Discard row is the one red row in the menu"
        )
    }

    /// D-20104's view half: End reads `hasWorkToSave` — a running effort is
    /// work to save — and raises the Finish question first, the Discard question
    /// in its else branch.
    func testS20111TheEndRowRaisesTheFinishQuestionWhenThereIsWorkToSave() throws {
        let body = try XCTUnwrap(
            propertyBlock(
                "finishRow",
                in: sourceLines(try menuSource("watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift"))
            ),
            "S-20111 the menu view has a finishRow"
        )

        let rule = try XCTUnwrap(
            body.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "if state.hasWorkToSave {" },
            "S-20111 End reads the save rule"
        )
        let finish = try XCTUnwrap(
            body.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "confirmingFinish = true" },
            "S-20111 the Finish question is raised"
        )
        let discard = try XCTUnwrap(
            body.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "confirmingDiscard = true" },
            "S-20111 the discard question is raised"
        )
        XCTAssertGreaterThan(finish, rule, "S-20111 an End with work to save asks Finish")
        XCTAssertGreaterThan(discard, finish, "S-20111 and an empty one asks Discard instead")
        XCTAssertFalse(
            body.contains { $0.contains("hasLoggedEfforts") },
            "S-20111 End no longer reads hasLoggedEfforts"
        )
    }
}
