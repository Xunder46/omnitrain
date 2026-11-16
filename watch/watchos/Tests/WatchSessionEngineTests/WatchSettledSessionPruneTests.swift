//
//  WatchSettledSessionPruneTests.swift
//  WatchSessionEngineTests
//
//  S-20701 to S-20708, S-20711 and S-20712 of
//  `docs/plans/2026-11-15-207-watch-store-retire-old-workouts-plan/`
//  `2026-11-15-207-watch-store-retire-old-workouts-plan.md`: the store-level
//  retire of settled, fully-synced workouts beyond the newest 20.
//
//  The workouts are real ones: logged through the engine over a
//  `FileWatchSessionStore` in a temporary directory, the way
//  `WatchStoreGrowthTests` builds a wrist. The gate is the rows, never the
//  clock, so no test here reads a time threshold.
//

import XCTest

@testable import WatchSessionEngine

/// The observation kinds the phone must receipt before a session may retire —
/// the list `retiredSessionIds` reads. Water and food taps are not in it.
private let pruneReceiptKinds: Set<String> = [
    WatchObservationKind.set,
    WatchObservationKind.timed,
    WatchObservationKind.round,
    WatchObservationKind.hold,
    WatchObservationKind.rest,
    WatchObservationKind.sessionEnd,
    WatchObservationKind.effortRating,
]

/// A wrist over one directory, on the `WatchStoreGrowthTests` pattern: a fresh
/// store and a fresh engine per launch, minting record ids that never repeat.
private final class PruneWrist {
    let directory: URL
    let clock = TestClock(testInstant())

    private(set) var store: FileWatchSessionStore
    private var recordIds = 0

    init(directory: URL) {
        self.directory = directory
        self.store = FileWatchSessionStore(directory: directory)
    }

    /// A launch: a new store, a new engine, `restore()`. Nothing else crosses.
    func launch() async -> WatchSessionEngine {
        store = FileWatchSessionStore(directory: directory)
        let engine = WatchSessionEngine(
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.recordIds += 1
                return "p-\(self.recordIds)"
            },
            sessionIdFactory: { "s-prune-\(UUID().uuidString)" }
        )
        await engine.restore()
        return engine
    }

    /// One settled workout: a session with one reading and one set entry,
    /// finished, and a receipt for every owed entry id and the end id. The
    /// order workouts are created in is their age — the first is the oldest.
    @discardableResult
    func settledWorkout(
        _ n: Int,
        confirmEntries: Bool = true,
        confirmEnd: Bool = true
    ) async throws -> String {
        let engine = await launch()
        let session = await engine.createSession(
            modality: "outdoor_run",
            exercises: [exercise("sx-bench")]
        )
        _ = await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: Double(110 + n))
        let entryId = "e-prune-\(n)-1"
        _ = try await engine.appendObservation(setEvent(clock, entryId: entryId))
        _ = await engine.finishSession()

        var owed: [String] = []
        if confirmEntries { owed.append(entryId) }
        if confirmEnd { owed.append(WatchSessionCapture.sessionEndId(session.sessionId)) }
        if !owed.isEmpty { _ = await engine.confirmObservations(owed) }
        return session.sessionId
    }
}

private func pruneSideFileExists(_ directory: URL, _ sessionId: String) -> Bool {
    FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("watch-samples-\(sessionId).jsonl").path
    )
}

/// Rows per session across every session-scoped family of `readAll()`.
private func pruneRowsPerSession(_ contents: WatchStoreContents) -> [String: Int] {
    var counts: [String: Int] = [:]
    func count(_ id: String) { counts[id, default: 0] += 1 }
    for row in contents.sessions { count(row.sessionId) }
    for row in contents.observations { count(row.sessionId) }
    for row in contents.timers { count(row.sessionId) }
    for row in contents.confirmations { count(row.sessionId) }
    for row in contents.sensorSamples { count(row.sessionId) }
    for row in contents.ratingPrompts { count(row.sessionId) }
    return counts
}

/// The record ids of the families a retire may drop. The sensor samples are
/// kept out: on the file store a settled session's readings have already moved
/// to their side file, so they leave with the session but are not part of the
/// returned ids.
private func pruneMainRecordIds(_ contents: WatchStoreContents) -> Set<String> {
    var ids = Set(contents.sessions.map(\.recordId))
    ids.formUnion(contents.observations.map(\.recordId))
    ids.formUnion(contents.timers.map(\.recordId))
    ids.formUnion(contents.confirmations.map(\.recordId))
    ids.formUnion(contents.ratingPrompts.map(\.recordId))
    return ids
}

/// Every record id of every family — for a comparison that must see no change
/// at all.
private func pruneAllRecordIds(_ contents: WatchStoreContents) -> Set<String> {
    var ids = pruneMainRecordIds(contents)
    ids.formUnion(contents.sensorSamples.map(\.recordId))
    return ids
}

final class WatchSettledSessionPruneTests: XCTestCase {
    private var directory: URL!
    private var wrist: PruneWrist!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-prune-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        wrist = PruneWrist(directory: directory)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private var storeFileURL: URL {
        directory.appendingPathComponent("watch-session.jsonl")
    }

    private func storeLines() throws -> Int {
        try Data(contentsOf: storeFileURL).split(separator: 0x0A).count
    }

    /// `sessionId` has no row of any retired kind left in `contents`.
    private func assertRetired(_ sessionId: String, _ contents: WatchStoreContents) {
        XCTAssertFalse(
            contents.sessions.contains { $0.sessionId == sessionId },
            "\(sessionId): a retired session's session rows are gone"
        )
        XCTAssertFalse(
            contents.timers.contains { $0.sessionId == sessionId },
            "\(sessionId): a retired session's timer rows are gone"
        )
        XCTAssertFalse(
            contents.confirmations.contains { $0.sessionId == sessionId },
            "\(sessionId): a retired session's confirmation rows are gone"
        )
        XCTAssertFalse(
            contents.sensorSamples.contains { $0.sessionId == sessionId },
            "\(sessionId): a retired session's readings are gone"
        )
        XCTAssertFalse(
            contents.ratingPrompts.contains { $0.sessionId == sessionId },
            "\(sessionId): a retired session's rating prompts are gone"
        )
        XCTAssertFalse(
            contents.observations.contains {
                $0.sessionId == sessionId && pruneReceiptKinds.contains($0.kind)
            },
            "\(sessionId): a retired session's owed observation rows are gone"
        )
    }

    // MARK: - S-20701

    func testS20701TheOldestSettledWorkoutsLeaveAndTheNewestTwentyStayWhole() async throws {
        var sessionIds: [String] = []
        for n in 1...25 {
            sessionIds.append(try await wrist.settledWorkout(n))
        }
        let oldest = sessionIds[0]

        // The oldest session's water and food taps, its rating prompt, and the
        // phone's reference rows — nothing a retire may drop.
        let at = wrist.clock.now
        _ = await wrist.store.append(.observation(WatchObservationRecord(
            recordId: "tap-water-oldest",
            sessionId: oldest,
            recordedAt: at,
            kind: WatchObservationKind.waterGlass,
            payload: ["entryId": "tap-water-oldest", "glassChange": "add",
                      "loggedAt": utcIso(at)]
        )))
        _ = await wrist.store.append(.observation(WatchObservationRecord(
            recordId: "tap-food-oldest",
            sessionId: oldest,
            recordedAt: at,
            kind: WatchObservationKind.nutritionQuickLog,
            payload: ["entryId": "tap-food-oldest", "foodId": "food-prune-1",
                      "servings": 1, "loggedAt": utcIso(at)]
        )))
        _ = await wrist.store.append(.ratingPrompt(WatchRatingPromptRecord(
            recordId: WatchRatingPromptRecord.recordIdFor(oldest),
            sessionId: oldest,
            recordedAt: at
        )))
        _ = await wrist.store.append(.routineCatalog(
            WatchRoutineCatalogRecord(recordId: "rou-prune-1", recordedAt: at, generatedAt: at)
        ))
        _ = await wrist.store.append(.foodCatalog(
            WatchFoodCatalogRecord(recordId: "foo-prune-1", recordedAt: at, generatedAt: at)
        ))
        _ = await wrist.store.append(.preferences(
            WatchPreferencesRecord(
                recordId: "pre-prune-1",
                recordedAt: at,
                generatedAt: at,
                effortRatingPrompt: true
            )
        ))

        let before = await wrist.store.readAll()
        for id in sessionIds.prefix(5) {
            XCTAssertTrue(
                pruneSideFileExists(directory, id),
                "S-20701 fixture: \(id) has a side file for the prune to remove"
            )
        }

        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        let after = await wrist.store.readAll()

        for id in sessionIds.prefix(5) {
            assertRetired(id, after)
            XCTAssertFalse(
                pruneSideFileExists(directory, id),
                "S-20701 \(id)'s side file leaves with the session"
            )
        }
        let beforeRows = pruneRowsPerSession(before)
        let afterRows = pruneRowsPerSession(after)
        for id in sessionIds.suffix(20) {
            XCTAssertEqual(
                afterRows[id], beforeRows[id],
                "S-20701 \(id) is inside the newest 20 and every row of it stays"
            )
        }
        XCTAssertTrue(
            after.observations.contains { $0.recordId == "tap-water-oldest" },
            "S-20701 the oldest session's water tap survives it"
        )
        XCTAssertTrue(
            after.observations.contains { $0.recordId == "tap-food-oldest" },
            "S-20701 the oldest session's food tap survives it"
        )
        XCTAssertEqual(
            after.routineCatalogs.map(\.recordId), ["rou-prune-1"],
            "S-20701 the routine catalog row survives"
        )
        XCTAssertEqual(
            after.foodCatalogs.map(\.recordId), ["foo-prune-1"],
            "S-20701 the food catalog row survives"
        )
        XCTAssertEqual(
            after.preferences.map(\.recordId), ["pre-prune-1"],
            "S-20701 the preferences row survives"
        )
        XCTAssertEqual(
            Set(dropped),
            pruneMainRecordIds(before).subtracting(pruneMainRecordIds(after)),
            "S-20701 the returned ids are exactly the dropped rows"
        )
    }

    // MARK: - S-20702

    func testS20702AnUnsyncedWorkoutIsKeptWhateverItsAge() async throws {
        var sessionIds: [String] = []
        sessionIds.append(try await wrist.settledWorkout(1, confirmEntries: false))
        for n in 2...25 {
            sessionIds.append(try await wrist.settledWorkout(n))
        }

        let before = await wrist.store.readAll()
        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        let after = await wrist.store.readAll()

        XCTAssertEqual(
            pruneRowsPerSession(after)[sessionIds[0]],
            pruneRowsPerSession(before)[sessionIds[0]],
            "S-20702 the unsynced workout is kept whole, whatever its age"
        )
        XCTAssertTrue(
            pruneSideFileExists(directory, sessionIds[0]),
            "S-20702 the unsynced workout keeps its side file too"
        )
        XCTAssertTrue(
            after.observations.contains { $0.recordId == "e-prune-1-1" },
            "S-20702 the entry the phone never receipted is still stored"
        )
        for id in sessionIds[1..<5] {
            assertRetired(id, after)
        }
        for id in sessionIds[5...] {
            XCTAssertEqual(
                pruneRowsPerSession(after)[id],
                pruneRowsPerSession(before)[id],
                "S-20702 \(id) is inside the newest 20 and every row of it stays"
            )
        }
        XCTAssertEqual(
            Set(dropped),
            pruneMainRecordIds(before).subtracting(pruneMainRecordIds(after)),
            "S-20702 the returned ids are exactly the dropped rows"
        )
        XCTAssertFalse(dropped.isEmpty, "S-20702 four older workouts leave")
    }

    // MARK: - S-20703

    func testS20703AWristWorkoutWhoseEndIsUnacknowledgedIsKept() async throws {
        var sessionIds: [String] = []
        sessionIds.append(try await wrist.settledWorkout(1, confirmEnd: false))
        for n in 2...25 {
            sessionIds.append(try await wrist.settledWorkout(n))
        }

        let before = await wrist.store.readAll()
        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        let after = await wrist.store.readAll()

        XCTAssertEqual(
            pruneRowsPerSession(after)[sessionIds[0]],
            pruneRowsPerSession(before)[sessionIds[0]],
            "S-20703 a wrist workout whose end is unacknowledged is kept whole"
        )
        XCTAssertTrue(
            pruneSideFileExists(directory, sessionIds[0]),
            "S-20703 the kept workout's side file stays"
        )
        for id in sessionIds[1..<5] {
            assertRetired(id, after)
        }
        for id in sessionIds[5...] {
            XCTAssertEqual(
                pruneRowsPerSession(after)[id],
                pruneRowsPerSession(before)[id],
                "S-20703 \(id) is inside the newest 20 and every row of it stays"
            )
        }
        XCTAssertEqual(
            Set(dropped),
            pruneMainRecordIds(before).subtracting(pruneMainRecordIds(after)),
            "S-20703 the returned ids are exactly the dropped rows"
        )
    }

    // MARK: - S-20704

    func testS20704AnUnfinishedOldSessionIsNeverRetired() async throws {
        // The unfinished session is the OLDEST session, appended before any
        // workout. The 25 settled workouts are built at store level: an engine
        // launch after the active row exists would adopt it (restore takes the
        // newest row, and a start while a session is held returns the held
        // session) and finish it, which is not this scenario.
        let at = wrist.clock.now
        _ = await wrist.store.append(.session(WatchSessionRecord(
            recordId: "srow-old-active",
            sessionId: "s-old-active",
            recordedAt: at,
            startedAt: at,
            modality: "outdoor_run",
            source: "watch",
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0
        )))
        _ = await wrist.store.append(.observation(WatchObservationRecord(
            recordId: "o-old-active",
            sessionId: "s-old-active",
            recordedAt: at,
            kind: WatchObservationKind.set,
            payload: ["entryId": "o-old-active", "loggedAt": utcIso(at),
                      "reps": 5, "loadKg": 80]
        )))
        var sessionIds = ["s-old-active"]
        for n in 1...25 {
            let sessionId = "s-old-w-\(n)"
            sessionIds.append(sessionId)
            _ = await wrist.store.append(.session(WatchSessionRecord(
                recordId: "srow-w-\(n)-a",
                sessionId: sessionId,
                recordedAt: at,
                startedAt: at,
                modality: "outdoor_run",
                source: "watch",
                status: WatchSessionStatus.active,
                currentExerciseIndex: 0
            )))
            _ = await wrist.store.append(.session(WatchSessionRecord(
                recordId: "srow-w-\(n)-c",
                sessionId: sessionId,
                recordedAt: at,
                startedAt: at,
                modality: "outdoor_run",
                source: "watch",
                status: WatchSessionStatus.completed,
                currentExerciseIndex: 0
            )))
            _ = await wrist.store.append(.observation(WatchObservationRecord(
                recordId: "e-old-w-\(n)",
                sessionId: sessionId,
                recordedAt: at,
                kind: WatchObservationKind.set,
                payload: ["entryId": "e-old-w-\(n)", "loggedAt": utcIso(at),
                          "reps": 5, "loadKg": 80],
                confirmedAt: at
            )))
            _ = await wrist.store.append(.observation(WatchObservationRecord(
                recordId: WatchSessionCapture.sessionEndId(sessionId),
                sessionId: sessionId,
                recordedAt: at,
                kind: WatchObservationKind.sessionEnd,
                payload: ["entryId": WatchSessionCapture.sessionEndId(sessionId)],
                confirmedAt: at
            )))
            _ = await wrist.store.append(.timer(WatchTimerRecord(
                recordId: "t-old-w-\(n)",
                sessionId: sessionId,
                recordedAt: at,
                kind: WatchTimerKind.rest,
                startedAt: at
            )))
            _ = await wrist.store.append(.ratingPrompt(WatchRatingPromptRecord(
                recordId: WatchRatingPromptRecord.recordIdFor(sessionId),
                sessionId: sessionId,
                recordedAt: at
            )))
            _ = await wrist.store.append(.confirmation(WatchConfirmationRecord(
                recordId: "c-old-w-\(n)",
                sessionId: sessionId,
                recordedAt: at,
                observationIds: ["e-old-w-\(n)",
                                 WatchSessionCapture.sessionEndId(sessionId)]
            )))
        }

        let before = await wrist.store.readAll()
        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        let after = await wrist.store.readAll()

        for recordId in ["srow-old-active", "o-old-active"] {
            XCTAssertTrue(
                pruneAllRecordIds(after).contains(recordId),
                "S-20704 \(recordId) of the unfinished session stays"
            )
        }
        XCTAssertEqual(
            pruneRowsPerSession(after)["s-old-active"],
            pruneRowsPerSession(before)["s-old-active"],
            "S-20704 the unfinished session is never retired, whatever its age"
        )
        for id in sessionIds[1..<6] {
            assertRetired(id, after)
        }
        for id in sessionIds[6...] {
            XCTAssertEqual(
                pruneRowsPerSession(after)[id],
                pruneRowsPerSession(before)[id],
                "S-20704 \(id) is inside the newest 20 and every row of it stays"
            )
        }
        XCTAssertEqual(
            Set(dropped),
            pruneMainRecordIds(before).subtracting(pruneMainRecordIds(after)),
            "S-20704 the returned ids are exactly the dropped rows"
        )
    }

    // MARK: - S-20706

    func testS20706ANothingToRetirePruneWritesNothing() async throws {
        for n in 1...3 {
            _ = try await wrist.settledWorkout(n)
        }
        let at = wrist.clock.now
        _ = await wrist.store.append(.routineCatalog(
            WatchRoutineCatalogRecord(recordId: "rou-prune-1", recordedAt: at, generatedAt: at)
        ))
        _ = await wrist.store.append(.foodCatalog(
            WatchFoodCatalogRecord(recordId: "foo-prune-1", recordedAt: at, generatedAt: at)
        ))
        _ = await wrist.store.append(.preferences(
            WatchPreferencesRecord(
                recordId: "pre-prune-1",
                recordedAt: at,
                generatedAt: at,
                effortRatingPrompt: true
            )
        ))
        _ = await wrist.store.append(.bests(
            WatchBestsRecord(
                recordId: "bests-prune-1",
                recordedAt: at,
                generatedAt: at,
                entries: [["exerciseId": "ex-bench", "e1rmKg": 116.6667]]
            )
        ))
        _ = await wrist.store.append(.water(
            WatchWaterRecord(
                recordId: "water-prune-1",
                recordedAt: at,
                generatedAt: at,
                day: "2026-07-13",
                glasses: 2
            )
        ))

        let before = try Data(contentsOf: storeFileURL)
        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)

        XCTAssertEqual(
            dropped, [],
            "S-20706 three settled workouts are inside the newest 20: nothing to retire"
        )
        XCTAssertEqual(
            try Data(contentsOf: storeFileURL), before,
            "S-20706 a prune that finds nothing is not a write"
        )
    }

    // MARK: - S-20708

    func testS20708APruneThatCannotBeWrittenDropsNothing() async throws {
        var sessionIds: [String] = []
        for n in 1...25 {
            sessionIds.append(try await wrist.settledWorkout(n))
        }
        let before = await wrist.store.readAll()

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: directory.path
        )
        try? FileManager.default.setAttributes([.immutable: true], ofItemAtPath: directory.path)
        let lockedDirectory = directory.path
        addTeardownBlock {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: lockedDirectory)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: lockedDirectory
            )
        }
        XCTAssertThrowsError(
            try Data("probe".utf8).write(to: directory.appendingPathComponent("probe")),
            "S-20708 the directory must actually be unwritable, or this case proves nothing"
        )

        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        XCTAssertEqual(dropped, [], "S-20708 a prune that cannot be written drops nothing")
        let after = await wrist.store.readAll()
        XCTAssertEqual(
            pruneAllRecordIds(after), pruneAllRecordIds(before),
            "S-20708 the cache still reads the pre-prune rows"
        )
        for id in sessionIds.prefix(5) {
            XCTAssertTrue(
                pruneSideFileExists(directory, id),
                "S-20708 \(id)'s side file stays with the rows the file still carries"
            )
        }

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    // MARK: - S-20701B

    func testS20701BTheInMemoryStoreRetiresTheSameWay() async throws {
        let store = InMemoryWatchSessionStore()
        let at = testInstant()
        var sessionIds: [String] = []
        for index in 1...25 {
            let sessionId = "s-m-\(index)"
            sessionIds.append(sessionId)
            _ = await store.append(.session(WatchSessionRecord(
                recordId: "srow-m-\(index)",
                sessionId: sessionId,
                recordedAt: at,
                startedAt: at,
                modality: nil,
                source: "watch",
                status: WatchSessionStatus.completed,
                currentExerciseIndex: 0
            )))
            _ = await store.append(.observation(WatchObservationRecord(
                recordId: "o-m-\(index)",
                sessionId: sessionId,
                recordedAt: at,
                kind: WatchObservationKind.set,
                payload: ["entryId": "o-m-\(index)"],
                confirmedAt: at
            )))
            _ = await store.append(.observation(WatchObservationRecord(
                recordId: WatchSessionCapture.sessionEndId(sessionId),
                sessionId: sessionId,
                recordedAt: at,
                kind: WatchObservationKind.sessionEnd,
                payload: ["entryId": WatchSessionCapture.sessionEndId(sessionId)],
                confirmedAt: at
            )))
            _ = await store.append(.timer(WatchTimerRecord(
                recordId: "t-m-\(index)",
                sessionId: sessionId,
                recordedAt: at,
                kind: WatchTimerKind.rest,
                startedAt: at
            )))
            _ = await store.append(.confirmation(WatchConfirmationRecord(
                recordId: "c-m-\(index)",
                sessionId: sessionId,
                recordedAt: at,
                observationIds: ["o-m-\(index)"]
            )))
        }

        let before = await store.readAll()
        let dropped = await store.pruneSettledSessions(keepingNewest: 20)
        let after = await store.readAll()

        XCTAssertFalse(dropped.isEmpty, "S-20701B the retire drops the oldest sessions' rows")
        XCTAssertEqual(
            Set(dropped),
            pruneMainRecordIds(before).subtracting(pruneMainRecordIds(after)),
            "S-20701B the returned ids are exactly the dropped rows"
        )
        let beforeRows = pruneRowsPerSession(before)
        let afterRows = pruneRowsPerSession(after)
        for id in sessionIds.prefix(5) {
            assertRetired(id, after)
        }
        for id in sessionIds.suffix(20) {
            XCTAssertEqual(
                afterRows[id], beforeRows[id],
                "S-20701B \(id) is inside the newest 20 and every row of it stays"
            )
        }
    }

    // MARK: - S-20712

    func testS20712AConfirmationThatNamesNothingIsNotRetired() async throws {
        var sessionIds: [String] = []
        for n in 1...25 {
            sessionIds.append(try await wrist.settledWorkout(n))
        }
        let at = wrist.clock.now
        _ = await wrist.store.append(.confirmation(WatchConfirmationRecord(
            recordId: "c-empty",
            sessionId: sessionIds[0],
            recordedAt: at,
            observationIds: []
        )))

        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        let after = await wrist.store.readAll()

        XCTAssertTrue(
            after.confirmations.contains { $0.recordId == "c-empty" },
            "S-20712 a confirmation that names nothing is not retired"
        )
        // c-empty carries the oldest session's id but stays by design, so the
        // oldest is asserted row family by family, without the blanket
        // confirmation check.
        XCTAssertFalse(
            after.sessions.contains { $0.sessionId == sessionIds[0] },
            "S-20712 the oldest session's session rows are gone"
        )
        XCTAssertFalse(
            after.timers.contains { $0.sessionId == sessionIds[0] },
            "S-20712 the oldest session's timer rows are gone"
        )
        XCTAssertFalse(
            after.sensorSamples.contains { $0.sessionId == sessionIds[0] },
            "S-20712 the oldest session's readings are gone"
        )
        XCTAssertFalse(
            after.observations.contains {
                $0.sessionId == sessionIds[0] && pruneReceiptKinds.contains($0.kind)
            },
            "S-20712 the oldest session's owed observation rows are gone"
        )
        XCTAssertFalse(dropped.isEmpty, "S-20712 fixture: the prune did retire the old sessions")
    }

    // MARK: - S-20711

    func testS20711AnEngineOverFortySettledWorkoutsKeepsTwentyAfterRelaunch() async throws {
        var sessionIds: [String] = []
        for n in 1...40 {
            sessionIds.append(try await wrist.settledWorkout(n))
        }
        let beforeLines = try storeLines()

        let engine = await wrist.launch()
        let dropped = await engine.pruneSettledSessions()
        XCTAssertFalse(dropped.isEmpty, "S-20711 forty settled workouts leave twenty to retire")

        let relaunched = await wrist.launch()
        XCTAssertEqual(
            relaunched.session?.sessionId, sessionIds.last,
            "S-20711 the restored engine's session is the newest workout"
        )

        let after = await wrist.store.readAll()
        XCTAssertEqual(
            Set(after.sessions.map(\.sessionId)),
            Set(sessionIds.suffix(20)),
            "S-20711 the store holds session rows for exactly the newest 20 sessions"
        )
        XCTAssertLessThan(
            try storeLines(), beforeLines,
            "S-20711 the main file is smaller after the retire"
        )
    }

    // MARK: - guard-arm fixtures

    /// The rows of one settled workout appended at store level, the shape the
    /// S-20704 fixture builds: two session rows, a confirmed set, a confirmed
    /// end, a timer, a rating prompt and a confirmation naming both. A fixture
    /// that must keep a non-settled session goes at store level, because an
    /// engine launch after it would adopt the newest row and finish it.
    private func appendSettledWorkout(
        _ store: FileWatchSessionStore,
        sessionId: String,
        at: Date
    ) async {
        _ = await store.append(.session(WatchSessionRecord(
            recordId: "srow-\(sessionId)-a",
            sessionId: sessionId,
            recordedAt: at,
            startedAt: at,
            modality: "outdoor_run",
            source: "watch",
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0
        )))
        _ = await store.append(.session(WatchSessionRecord(
            recordId: "srow-\(sessionId)-c",
            sessionId: sessionId,
            recordedAt: at,
            startedAt: at,
            modality: "outdoor_run",
            source: "watch",
            status: WatchSessionStatus.completed,
            currentExerciseIndex: 0
        )))
        let setId = "e-\(sessionId)"
        _ = await store.append(.observation(WatchObservationRecord(
            recordId: setId,
            sessionId: sessionId,
            recordedAt: at,
            kind: WatchObservationKind.set,
            payload: ["entryId": setId, "loggedAt": utcIso(at),
                      "reps": 5, "loadKg": 80],
            confirmedAt: at
        )))
        let endId = WatchSessionCapture.sessionEndId(sessionId)
        _ = await store.append(.observation(WatchObservationRecord(
            recordId: endId,
            sessionId: sessionId,
            recordedAt: at,
            kind: WatchObservationKind.sessionEnd,
            payload: ["entryId": endId],
            confirmedAt: at
        )))
        _ = await store.append(.timer(WatchTimerRecord(
            recordId: "t-\(sessionId)",
            sessionId: sessionId,
            recordedAt: at,
            kind: WatchTimerKind.rest,
            startedAt: at
        )))
        _ = await store.append(.ratingPrompt(WatchRatingPromptRecord(
            recordId: WatchRatingPromptRecord.recordIdFor(sessionId),
            sessionId: sessionId,
            recordedAt: at
        )))
        _ = await store.append(.confirmation(WatchConfirmationRecord(
            recordId: "c-\(sessionId)",
            sessionId: sessionId,
            recordedAt: at,
            observationIds: [setId, endId]
        )))
    }

    // MARK: - S-20704B

    /// The terminal-status gate is what keeps an active session, not the owed
    /// gate: one active session with NO observation rows at all, and one whose
    /// only observation is confirmed, both outlive the retire.
    func testS20704BAnOldActiveSessionWithNothingUnsyncedIsStillKept() async throws {
        let at = wrist.clock.now
        _ = await wrist.store.append(.session(WatchSessionRecord(
            recordId: "srow-old-plain",
            sessionId: "s-old-plain",
            recordedAt: at,
            startedAt: at,
            modality: "outdoor_run",
            source: "phone",
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0
        )))
        _ = await wrist.store.append(.session(WatchSessionRecord(
            recordId: "srow-old-synced",
            sessionId: "s-old-synced",
            recordedAt: at,
            startedAt: at,
            modality: "outdoor_run",
            source: "phone",
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0
        )))
        _ = await wrist.store.append(.observation(WatchObservationRecord(
            recordId: "o-old-synced",
            sessionId: "s-old-synced",
            recordedAt: at,
            kind: WatchObservationKind.set,
            payload: ["entryId": "o-old-synced", "loggedAt": utcIso(at),
                      "reps": 5, "loadKg": 80],
            confirmedAt: at
        )))

        var sessionIds = ["s-old-plain", "s-old-synced"]
        for n in 1...23 {
            let sessionId = "s-old-w-\(n)"
            sessionIds.append(sessionId)
            await appendSettledWorkout(wrist.store, sessionId: sessionId, at: at)
        }

        let before = await wrist.store.readAll()
        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        let after = await wrist.store.readAll()

        for id in sessionIds.prefix(2) {
            XCTAssertEqual(
                pruneRowsPerSession(after)[id],
                pruneRowsPerSession(before)[id],
                "S-20704B \(id), an active session with nothing unsynced, is still kept"
            )
        }
        XCTAssertTrue(
            pruneAllRecordIds(after).contains("srow-old-plain"),
            "S-20704B the plain active session's row is still stored"
        )
        XCTAssertTrue(
            pruneAllRecordIds(after).contains("o-old-synced"),
            "S-20704B the confirmed observation of the still-active session is still stored"
        )
        for id in sessionIds[2..<5] {
            assertRetired(id, after)
        }
        for id in sessionIds[5...] {
            XCTAssertEqual(
                pruneRowsPerSession(after)[id],
                pruneRowsPerSession(before)[id],
                "S-20704B \(id) is inside the newest 20 and every row of it stays"
            )
        }
        XCTAssertFalse(dropped.isEmpty, "S-20704B fixture: three settled workouts retired")
    }

    // MARK: - S-20703B

    /// An UNCONFIRMED end is caught by the owed gate; only the wrist-end block
    /// catches a workout whose `end-<sessionId>` row does not exist at all.
    func testS20703BAWristWorkoutWithNoEndRowAtAllIsKept() async throws {
        let at = wrist.clock.now
        let noEnd = "s-noend"
        for (recordId, status) in [
            ("srow-noend-a", WatchSessionStatus.active),
            ("srow-noend-c", WatchSessionStatus.completed),
        ] {
            _ = await wrist.store.append(.session(WatchSessionRecord(
                recordId: recordId,
                sessionId: noEnd,
                recordedAt: at,
                startedAt: at,
                modality: "outdoor_run",
                source: "watch",
                status: status,
                currentExerciseIndex: 0
            )))
        }
        _ = await wrist.store.append(.observation(WatchObservationRecord(
            recordId: "e-noend",
            sessionId: noEnd,
            recordedAt: at,
            kind: WatchObservationKind.set,
            payload: ["entryId": "e-noend", "loggedAt": utcIso(at),
                      "reps": 5, "loadKg": 80],
            confirmedAt: at
        )))
        _ = await wrist.store.append(.timer(WatchTimerRecord(
            recordId: "t-noend",
            sessionId: noEnd,
            recordedAt: at,
            kind: WatchTimerKind.rest,
            startedAt: at
        )))
        _ = await wrist.store.append(.ratingPrompt(WatchRatingPromptRecord(
            recordId: WatchRatingPromptRecord.recordIdFor(noEnd),
            sessionId: noEnd,
            recordedAt: at
        )))
        _ = await wrist.store.append(.confirmation(WatchConfirmationRecord(
            recordId: "c-noend",
            sessionId: noEnd,
            recordedAt: at,
            observationIds: ["e-noend"]
        )))

        var sessionIds = [noEnd]
        for n in 1...22 {
            let sessionId = "s-w-\(n)"
            sessionIds.append(sessionId)
            await appendSettledWorkout(wrist.store, sessionId: sessionId, at: at)
        }

        let before = await wrist.store.readAll()
        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        let after = await wrist.store.readAll()

        XCTAssertEqual(
            pruneRowsPerSession(after)[noEnd],
            pruneRowsPerSession(before)[noEnd],
            "S-20703B the wrist workout with no end row at all is kept whole"
        )
        XCTAssertTrue(
            pruneAllRecordIds(after).contains("e-noend"),
            "S-20703B the workout's confirmed entry is still stored"
        )
        for id in sessionIds[1..<3] {
            assertRetired(id, after)
        }
        for id in sessionIds[3...] {
            XCTAssertEqual(
                pruneRowsPerSession(after)[id],
                pruneRowsPerSession(before)[id],
                "S-20703B \(id) is inside the newest 20 and every row of it stays"
            )
        }
        XCTAssertEqual(
            Set(dropped),
            pruneMainRecordIds(before).subtracting(pruneMainRecordIds(after)),
            "S-20703B the returned ids are exactly the dropped rows"
        )
    }

    // MARK: - S-20713

    /// A confirmation whose ids are not ALL among the dropped observations
    /// stays whole: one row names a retired workout's effort observation and
    /// the same workout's water tap, which the retire never drops (D-20704).
    func testS20713AConfirmationThatAlsoNamesAKeptTapStaysWhole() async throws {
        let at = wrist.clock.now
        let oldest = "s-both"
        await appendSettledWorkout(wrist.store, sessionId: oldest, at: at)
        _ = await wrist.store.append(.observation(WatchObservationRecord(
            recordId: "e-effort-both",
            sessionId: oldest,
            recordedAt: at,
            kind: WatchObservationKind.effortRating,
            payload: ["entryId": "e-effort-both", "loggedAt": utcIso(at),
                      "rating": 4],
            confirmedAt: at
        )))
        _ = await wrist.store.append(.observation(WatchObservationRecord(
            recordId: "tap-water-both",
            sessionId: oldest,
            recordedAt: at,
            kind: WatchObservationKind.waterGlass,
            payload: ["entryId": "tap-water-both", "glassChange": "add",
                      "loggedAt": utcIso(at)],
            confirmedAt: at
        )))
        _ = await wrist.store.append(.confirmation(WatchConfirmationRecord(
            recordId: "c-both",
            sessionId: oldest,
            recordedAt: at,
            observationIds: ["e-effort-both", "tap-water-both"]
        )))

        var sessionIds = [oldest]
        for n in 1...22 {
            let sessionId = "s-w-\(n)"
            sessionIds.append(sessionId)
            await appendSettledWorkout(wrist.store, sessionId: sessionId, at: at)
        }

        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        let after = await wrist.store.readAll()

        XCTAssertFalse(dropped.isEmpty, "S-20713 fixture: the prune retired the old workouts")
        XCTAssertFalse(
            after.sessions.contains { $0.sessionId == oldest },
            "S-20713 the retired workout's session rows are gone"
        )
        XCTAssertFalse(
            after.timers.contains { $0.sessionId == oldest },
            "S-20713 the retired workout's timer rows are gone"
        )
        XCTAssertFalse(
            after.observations.contains { $0.recordId == "e-effort-both" },
            "S-20713 the retired workout's effort observation is gone"
        )
        XCTAssertTrue(
            after.observations.contains { $0.recordId == "tap-water-both" },
            "S-20713 the retired workout's water tap is kept (D-20704)"
        )
        XCTAssertEqual(
            after.confirmations.first { $0.recordId == "c-both" }?.observationIds,
            ["e-effort-both", "tap-water-both"],
            "S-20713 a confirmation that also names a kept tap stays whole, both ids intact"
        )
    }

    // MARK: - S-20706B

    /// A prune that finds nothing is not a write even when the file carries a
    /// torn tail: a plain compaction of an already-canonical file would drop
    /// the tail and rewrite the same bytes otherwise.
    func testS20706BANothingToRetirePruneKeepsATornTailAndTheMarker() async throws {
        for n in 1...3 {
            _ = try await wrist.settledWorkout(n)
        }

        // The shape a kill mid-append leaves: a partial line after the last
        // record, with no newline after it (the S-49 fixture's tail).
        var torn = try Data(contentsOf: storeFileURL)
        torn.append(contentsOf: "{\"type\":\"session\",\"recordId\":\"torn".utf8)
        try torn.write(to: storeFileURL)

        let beforeAttributes = try FileManager.default.attributesOfItem(
            atPath: storeFileURL.path
        )
        let beforeInode = (beforeAttributes[.systemFileNumber] as? NSNumber)?.intValue ?? -1
        let before = try Data(contentsOf: storeFileURL)

        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)

        XCTAssertEqual(
            dropped, [],
            "S-20706B three settled workouts are inside the newest 20: nothing to retire"
        )
        XCTAssertEqual(
            try Data(contentsOf: storeFileURL), before,
            "S-20706B a prune that finds nothing keeps every byte, torn tail and marker included"
        )
        let afterAttributes = try FileManager.default.attributesOfItem(
            atPath: storeFileURL.path
        )
        XCTAssertEqual(
            (afterAttributes[.systemFileNumber] as? NSNumber)?.intValue ?? -1,
            beforeInode,
            "S-20706B a prune that finds nothing does not rewrite the file"
        )
    }

    // MARK: - S-20714

    /// Every kind on the receipt list holds a workout while it is unconfirmed:
    /// one store per kind, each whose OLDEST workout carries one unconfirmed
    /// observation of that kind beside its confirmed rows.
    func testS20714AnyUnconfirmedOwedKindHoldsAWorkout() async throws {
        let at = wrist.clock.now
        for kind in [
            WatchObservationKind.set,
            WatchObservationKind.timed,
            WatchObservationKind.round,
            WatchObservationKind.hold,
            WatchObservationKind.rest,
            WatchObservationKind.effortRating,
        ] {
            let kindDirectory = directory.appendingPathComponent("owed-\(kind)")
            try FileManager.default.createDirectory(
                at: kindDirectory, withIntermediateDirectories: true
            )
            let store = FileWatchSessionStore(directory: kindDirectory)

            let sessionId = "s-owed-\(kind)"
            await appendSettledWorkout(store, sessionId: sessionId, at: at)
            let owedId = "o-owed-\(kind)"
            let payload: [String: Any]
            switch kind {
            case WatchObservationKind.effortRating:
                payload = ["entryId": owedId, "loggedAt": utcIso(at), "rating": 4]
            case WatchObservationKind.rest:
                payload = ["entryId": owedId, "loggedAt": utcIso(at)]
            default:
                payload = ["entryId": owedId, "loggedAt": utcIso(at),
                           "reps": 5, "loadKg": 80]
            }
            _ = await store.append(.observation(WatchObservationRecord(
                recordId: owedId,
                sessionId: sessionId,
                recordedAt: at,
                kind: kind,
                payload: payload
            )))

            var sessionIds = [sessionId]
            for n in 1...22 {
                let newer = "s-w-\(kind)-\(n)"
                sessionIds.append(newer)
                await appendSettledWorkout(store, sessionId: newer, at: at)
            }

            let before = await store.readAll()
            let dropped = await store.pruneSettledSessions(keepingNewest: 20)
            let after = await store.readAll()

            XCTAssertFalse(
                dropped.isEmpty,
                "S-20714 fixture (\(kind)): the prune retired the old settled workouts"
            )
            XCTAssertEqual(
                pruneRowsPerSession(after)[sessionId],
                pruneRowsPerSession(before)[sessionId],
                "S-20714 a \(kind) the phone has not receipted holds the workout"
            )
            XCTAssertTrue(
                after.observations.contains { $0.recordId == owedId },
                "S-20714 the unconfirmed \(kind) row is still stored"
            )
        }
    }

    // MARK: - S-20716

    /// A retired workout's readings leave both ways they can be held: the row
    /// still inline in the main file and the side file the end-of-session
    /// archive wrote.
    func testS20716InlineReadingsOfARetiredWorkoutLeaveAndItsSideFileToo() async throws {
        // A real workout: a reading recorded before the finish, so the archive
        // gives it a side file (the testS15601 way).
        let oldest = try await wrist.settledWorkout(1)
        for n in 2...23 {
            _ = try await wrist.settledWorkout(n)
        }

        // One reading still held inline, appended directly to the same store
        // instance — a later launch's load would migrate it into the side file,
        // and this scenario is about the retire dropping both.
        let at = wrist.clock.now
        _ = await wrist.store.append(.sensorSample(WatchSensorSampleRecord(
            recordId: "sen-inline-oldest",
            sessionId: oldest,
            recordedAt: at,
            kind: WatchSensorKind.heartRate,
            value: 111
        )))

        let before = await wrist.store.readAll()
        XCTAssertTrue(
            pruneSideFileExists(directory, oldest),
            "S-20716 fixture: the retired workout has a side file"
        )
        XCTAssertTrue(
            before.sensorSamples.contains {
                $0.sessionId == oldest && $0.recordId == "sen-inline-oldest"
            },
            "S-20716 fixture: the workout holds a reading inline in the main file"
        )

        let dropped = await wrist.store.pruneSettledSessions(keepingNewest: 20)
        let after = await wrist.store.readAll()

        XCTAssertFalse(dropped.isEmpty, "S-20716 fixture: the prune retired the old workouts")
        XCTAssertFalse(
            after.sensorSamples.contains { $0.sessionId == oldest },
            "S-20716 no reading row of the retired workout remains, inline or archived"
        )
        XCTAssertFalse(
            pruneSideFileExists(directory, oldest),
            "S-20716 the retired workout's side file leaves with it"
        )
    }

    // MARK: - S-20716B

    /// The arm `retiredRecordIds` holds for inline `sensorSample` rows: the
    /// file store cannot see it (its load migrates inline readings of ended
    /// sessions into side files before the prune runs), but the in-memory
    /// store keeps rows inline, so only there can the arm be told from gone.
    func testS20716BTheInMemoryStoreDropsTheInlineReadingsOfARetiredWorkout() async throws {
        let store = InMemoryWatchSessionStore()
        let at = testInstant()
        var sessionIds: [String] = []
        for index in 1...23 {
            let sessionId = "s-m-\(index)"
            sessionIds.append(sessionId)
            _ = await store.append(.session(WatchSessionRecord(
                recordId: "srow-m-\(index)",
                sessionId: sessionId,
                recordedAt: at,
                startedAt: at,
                modality: nil,
                source: "watch",
                status: WatchSessionStatus.completed,
                currentExerciseIndex: 0
            )))
            _ = await store.append(.observation(WatchObservationRecord(
                recordId: "o-m-\(index)",
                sessionId: sessionId,
                recordedAt: at,
                kind: WatchObservationKind.set,
                payload: ["entryId": "o-m-\(index)"],
                confirmedAt: at
            )))
            _ = await store.append(.observation(WatchObservationRecord(
                recordId: WatchSessionCapture.sessionEndId(sessionId),
                sessionId: sessionId,
                recordedAt: at,
                kind: WatchObservationKind.sessionEnd,
                payload: ["entryId": WatchSessionCapture.sessionEndId(sessionId)],
                confirmedAt: at
            )))
            _ = await store.append(.timer(WatchTimerRecord(
                recordId: "t-m-\(index)",
                sessionId: sessionId,
                recordedAt: at,
                kind: WatchTimerKind.rest,
                startedAt: at
            )))
            _ = await store.append(.confirmation(WatchConfirmationRecord(
                recordId: "c-m-\(index)",
                sessionId: sessionId,
                recordedAt: at,
                observationIds: ["o-m-\(index)"]
            )))
        }

        let oldest = sessionIds[0]
        let newest = sessionIds[22]
        _ = await store.append(.sensorSample(WatchSensorSampleRecord(
            recordId: "sen-m-oldest",
            sessionId: oldest,
            recordedAt: at,
            kind: WatchSensorKind.heartRate,
            value: 111
        )))
        _ = await store.append(.sensorSample(WatchSensorSampleRecord(
            recordId: "sen-m-newest",
            sessionId: newest,
            recordedAt: at,
            kind: WatchSensorKind.heartRate,
            value: 112
        )))

        let dropped = await store.pruneSettledSessions(keepingNewest: 20)
        let after = await store.readAll()

        XCTAssertFalse(dropped.isEmpty, "S-20716B fixture: the prune retired the old sessions")
        XCTAssertFalse(
            after.sensorSamples.contains { $0.sessionId == oldest },
            "S-20716B the retired workout's inline reading is dropped with it"
        )
        XCTAssertTrue(
            after.sensorSamples.contains { $0.recordId == "sen-m-newest" },
            "S-20716B the newest workout's inline reading stays with it"
        )
    }

    // MARK: - S-20717 to S-20719: engine-flow workouts

    /// A fixture step that must not fail silently.
    private enum PruneFixtureBroke: Error {
        case restTimerLost
    }

    /// One settled workout built through the engine's own flows — more than
    /// `PruneWrist.settledWorkout` does: a set, a rest started and stopped
    /// through the engine's own timer calls (the `WatchLoggingTimersTests`
    /// way), an effort rating recorded through the engine's own
    /// `recordEffortRating`, finished, and every owed entry id receipted
    /// except the ones `withhold` rejects. The withheld id is still owed.
    @discardableResult
    private func engineSettledWorkout(
        _ n: Int,
        withhold: ((String) -> Bool)? = nil
    ) async throws -> String {
        let engine = await wrist.launch()
        let session = await engine.createSession(
            modality: "outdoor_run",
            exercises: [exercise("sx-bench")]
        )
        _ = await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: Double(110 + n))
        let entryId = "e-prune-\(n)-1"
        _ = try await engine.appendObservation(setEvent(wrist.clock, entryId: entryId))

        wrist.clock.advance(30)
        _ = try await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 90_000)
        wrist.clock.advance(45)
        let stoppedRest = await engine.stopTimer(kind: WatchTimerKind.rest)
        guard let stoppedRest else {
            XCTFail("S-20717 fixture: the rest the engine started is the one it stopped")
            throw PruneFixtureBroke.restTimerLost
        }
        _ = await engine.finishSession()
        let rating = try await engine.recordEffortRating(4, sessionId: session.sessionId)
        XCTAssertNotNil(
            rating,
            "S-20717 fixture: the engine recorded the workout's effort rating"
        )

        let owed = [
            entryId,
            "\(stoppedRest.recordId)-rest",
            WatchSessionCapture.effortRatingId(session.sessionId),
            WatchSessionCapture.sessionEndId(session.sessionId),
        ]
        var receipt = owed
        if let withhold { receipt.removeAll(where: withhold) }
        XCTAssertFalse(
            receipt.isEmpty,
            "S-20717 fixture: a workout with nothing receipted is not this scenario"
        )
        _ = await engine.confirmObservations(receipt)
        return session.sessionId
    }

    /// A phone snapshot naming a session the wrist has already ended, the
    /// frame `WatchEndedIsFinalTests` drives `mergeLateEntries` with: the wrist
    /// holds a settled session, and the snapshot's entries are the only news
    /// such a frame can carry (D-14605).
    private func lateSnapshot(
        _ sessionId: String,
        messageId: String,
        sentAt: Date,
        entries: [[String: Any]]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": utcIso(sentAt),
            "payload": [
                "sessionId": sessionId,
                "revision": 9,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 0,
                "exercises": [exercise("sx-bench")],
                "entries": entries,
                "timers": [:],
            ] as [String: Any],
        ]
    }

    // MARK: - S-20717

    func testS20717AWorkoutWithAnAnsweredRatingAndEngineTimersRetiresThroughTheEngine() async throws {
        var sessionIds: [String] = []
        for n in 1...3 {
            sessionIds.append(try await engineSettledWorkout(n))
        }
        for n in 4...23 {
            sessionIds.append(try await wrist.settledWorkout(n))
        }
        let engine = await wrist.launch()

        let before = await wrist.store.readAll()
        let receipted = Set(before.confirmations.flatMap(\.observationIds))
        for id in sessionIds.prefix(3) {
            let owedIds = Set(before.observations.filter { $0.sessionId == id }.map(\.recordId))
            XCTAssertFalse(
                owedIds.isEmpty,
                "S-20717 fixture: \(id) carries the rows the engine flows wrote"
            )
            XCTAssertTrue(
                owedIds.isSubset(of: receipted),
                "S-20717 fixture: every owed observation of \(id) is receipted"
            )
            XCTAssertTrue(
                before.observations.contains {
                    $0.sessionId == id && $0.kind == WatchObservationKind.rest
                },
                "S-20717 fixture: \(id)'s rest was logged through the engine's own timer"
            )
            XCTAssertTrue(
                before.observations.contains {
                    $0.recordId == WatchSessionCapture.effortRatingId(id)
                },
                "S-20717 fixture: \(id)'s rating was recorded through the engine's own call"
            )
        }

        let dropped = await engine.pruneSettledSessions()
        let after = await wrist.store.readAll()

        for id in sessionIds.prefix(3) {
            assertRetired(id, after)
            XCTAssertEqual(
                after.observations.filter { $0.sessionId == id }.count,
                0,
                "S-20717 \(id) has no observation row of any kind left, rating and end included"
            )
            XCTAssertFalse(
                pruneSideFileExists(directory, id),
                "S-20717 \(id)'s side file leaves with it"
            )
        }
        let beforeRows = pruneRowsPerSession(before)
        let afterRows = pruneRowsPerSession(after)
        for id in sessionIds.suffix(20) {
            XCTAssertEqual(
                afterRows[id], beforeRows[id],
                "S-20717 \(id) is inside the newest 20 and every row of it stays"
            )
        }
        XCTAssertFalse(
            dropped.isEmpty,
            "S-20717 fixture: the prune retired the three engine-flow workouts"
        )
        XCTAssertEqual(
            Set(dropped),
            pruneMainRecordIds(before).subtracting(pruneMainRecordIds(after)),
            "S-20717 the returned ids are exactly the dropped rows"
        )
    }

    // MARK: - S-20718

    func testS20718ARatingThePhoneNeverReceiptedHoldsItsWorkout() async throws {
        let oldest = try await engineSettledWorkout(
            1,
            withhold: { $0.hasPrefix("rating-") }
        )
        var sessionIds = [oldest]
        for n in 2...23 {
            sessionIds.append(try await wrist.settledWorkout(n))
        }
        let engine = await wrist.launch()

        let before = await wrist.store.readAll()
        let receipted = Set(before.confirmations.flatMap(\.observationIds))
        let ratingId = WatchSessionCapture.effortRatingId(oldest)
        XCTAssertTrue(
            before.observations.contains {
                $0.recordId == ratingId && $0.kind == WatchObservationKind.effortRating
            },
            "S-20718 fixture: the workout carries the engine-recorded rating"
        )
        XCTAssertTrue(
            before.observations.filter { $0.sessionId == oldest }
                .allSatisfy { $0.recordId == ratingId || receipted.contains($0.recordId) },
            "S-20718 fixture: every observation but the rating is receipted"
        )

        let dropped = await engine.pruneSettledSessions()
        let after = await wrist.store.readAll()

        XCTAssertEqual(
            pruneRowsPerSession(after)[oldest],
            pruneRowsPerSession(before)[oldest],
            "S-20718 the workout whose rating the phone never receipted is kept whole"
        )
        XCTAssertTrue(
            after.observations.contains {
                $0.recordId == ratingId && $0.kind == WatchObservationKind.effortRating
            },
            "S-20718 the unreceipted rating row is still stored"
        )
        XCTAssertTrue(
            pruneSideFileExists(directory, oldest),
            "S-20718 the held workout keeps its side file too"
        )
        for id in sessionIds[1..<3] {
            assertRetired(id, after)
        }
        for id in sessionIds.suffix(20) {
            XCTAssertEqual(
                pruneRowsPerSession(after)[id],
                pruneRowsPerSession(before)[id],
                "S-20718 \(id) is inside the newest 20 and every row of it stays"
            )
        }
        XCTAssertFalse(dropped.isEmpty, "S-20718 fixture: two older workouts left")
        XCTAssertEqual(
            Set(dropped),
            pruneMainRecordIds(before).subtracting(pruneMainRecordIds(after)),
            "S-20718 the returned ids are exactly the dropped rows"
        )
    }

    // MARK: - S-20719

    func testS20719ALateEntryMergedIntoAnEndedWorkoutHoldsItUntilTheReceiptArrives() async throws {
        let oldest = try await engineSettledWorkout(1)
        var sessionIds = [oldest]
        for n in 2...23 {
            sessionIds.append(try await wrist.settledWorkout(n))
        }
        let engine = await wrist.launch()

        wrist.clock.advance(60)
        let merged = try await engine.applyMessage(
            lateSnapshot(
                oldest,
                messageId: "msg-prune-late",
                sentAt: wrist.clock.now,
                entries: [setEvent(wrist.clock, entryId: "e-prune-late-1")]
            )
        )
        XCTAssertTrue(merged, "S-20719 the late snapshot's entries are the news it carries")

        let mergedInto = await wrist.store.readAll()
        XCTAssertEqual(
            mergedInto.observations.filter { $0.recordId == "e-prune-late-1" }.count,
            1,
            "S-20719 the late entry is stored for the ended workout"
        )
        XCTAssertTrue(
            mergedInto.observations.contains {
                $0.recordId == "e-prune-late-1" && $0.sessionId == oldest && $0.confirmedAt == nil
            },
            "S-20719 the merged entry carries no confirmation"
        )
        XCTAssertTrue(
            engine.unconfirmedObservations.contains { $0.entryId == "e-prune-late-1" },
            "S-20719 a late snapshot is no receipt"
        )

        let firstDropped = await engine.pruneSettledSessions()
        let afterFirst = await wrist.store.readAll()

        XCTAssertEqual(
            pruneRowsPerSession(afterFirst)[oldest],
            pruneRowsPerSession(mergedInto)[oldest],
            "S-20719 the workout the late entry rides with is kept whole"
        )
        XCTAssertTrue(
            afterFirst.observations.contains { $0.recordId == "e-prune-late-1" },
            "S-20719 the unreceipted late entry is still stored"
        )
        for id in sessionIds[1..<3] {
            assertRetired(id, afterFirst)
        }
        for id in sessionIds.suffix(20) {
            XCTAssertEqual(
                pruneRowsPerSession(afterFirst)[id],
                pruneRowsPerSession(mergedInto)[id],
                "S-20719 \(id) is inside the newest 20 and every row of it stays"
            )
        }

        _ = await engine.confirmObservations(["e-prune-late-1"])
        let afterReceipt = await wrist.store.readAll()
        let secondDropped = await engine.pruneSettledSessions()
        let afterSecond = await wrist.store.readAll()

        assertRetired(oldest, afterSecond)
        XCTAssertEqual(
            afterSecond.observations.filter { $0.sessionId == oldest }.count,
            0,
            "S-20719 the workout whose late entry was receipted retires whole"
        )
        XCTAssertFalse(
            pruneSideFileExists(directory, oldest),
            "S-20719 the retired workout's side file leaves with it"
        )
        XCTAssertFalse(
            firstDropped.isEmpty,
            "S-20719 fixture: the first prune retired two older workouts"
        )
        XCTAssertFalse(
            secondDropped.isEmpty,
            "S-20719 the second prune retires the late-entry workout"
        )
        XCTAssertEqual(
            Set(secondDropped),
            pruneMainRecordIds(afterReceipt).subtracting(pruneMainRecordIds(afterSecond)),
            "S-20719 the second prune's ids are exactly the rows it dropped"
        )
        XCTAssertEqual(
            pruneMainRecordIds(afterSecond),
            pruneMainRecordIds(afterReceipt).subtracting(Set(secondDropped)),
            "S-20719 the second prune leaves exactly the main rows it did not drop"
        )
        XCTAssertEqual(
            Set(afterSecond.sensorSamples.map(\.recordId)),
            Set(afterReceipt.sensorSamples.map(\.recordId)).subtracting(
                Set(afterReceipt.sensorSamples.filter { $0.sessionId == oldest }.map(\.recordId))
            ),
            "S-20719 the second prune leaves every reading but the retired workout's"
        )
    }
}
