//
//  WatchFileStoreTests.swift
//  WatchSessionEngineTests
//
//  S-44 to S-47 and S-49 to S-51, S-53 and S-54 of
//  `docs/plans/2026-10-06-15e-watch-session-sync-pr4-plan/` — the durable,
//  append-only JSON-lines store the watch app builds so a logged set survives
//  the process that logged it.
//
//  A kill is simulated the way the watch experiences it: a brand-new store
//  instance over the same directory, and a brand-new engine restored from it.
//  Nothing else crosses the boundary — no shared object, no in-memory state.
//

import XCTest

@testable import WatchSessionEngine

private let markerText = #"{"format":"omnitrain-watch-store","version":1}"#

private func fileInstant(_ text: String) -> Date {
    (try? parseUtcIso(text)) ?? Date(timeIntervalSince1970: 0)
}

private func fileSlot(_ slotId: String, capabilities: [String]) -> [String: Any] {
    [
        "sessionExerciseId": slotId,
        "exerciseId": "ex-\(slotId)",
        "name": slotId,
        "capabilities": capabilities,
    ]
}

private func fileJSON(_ record: StoredWatchRecord) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: record.toJson(), options: [.sortedKeys]))
        ?? Data()
    return String(data: data, encoding: .utf8) ?? ""
}

/// Every family of `contents`, each row serialised with sorted keys — records
/// are not `Equatable`, so this is how two stores are compared.
private func fileFamilyJSON(_ contents: WatchStoreContents) -> [[String]] {
    [
        contents.sessions.map { fileJSON(.session($0)) },
        contents.observations.map { fileJSON(.observation($0)) },
        contents.timers.map { fileJSON(.timer($0)) },
        contents.confirmations.map { fileJSON(.confirmation($0)) },
        contents.sensorSamples.map { fileJSON(.sensorSample($0)) },
        contents.routineCatalogs.map { fileJSON(.routineCatalog($0)) },
        contents.foodCatalogs.map { fileJSON(.foodCatalog($0)) },
        contents.preferences.map { fileJSON(.preferences($0)) },
        contents.ratingPrompts.map { fileJSON(.ratingPrompt($0)) },
    ]
}

private func fileSessionRow(_ id: String, sessionId: String = "s-file", at: Date) -> StoredWatchRecord {
    .session(
        WatchSessionRecord(
            recordId: id,
            sessionId: sessionId,
            recordedAt: at,
            startedAt: at,
            modality: nil,
            source: "watch",
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0
        )
    )
}

/// A wrist with its engine, the phone's preferences and the rating state, all
/// over one directory — and a fresh set of objects on every `launch()`, which
/// is also how a relaunch after a kill is simulated.
private final class FileStoreHarness {
    let directory: URL
    let clock = TestClock(testInstant())

    private(set) var store: FileWatchSessionStore
    private(set) var engine: WatchSessionEngine!
    private(set) var preferences: WatchPhonePreferences!
    private(set) var rating: WatchEffortRatingState!

    private var recordIds = 0
    private var sessionIds: [String]

    init(directory: URL, sessionIds: [String] = ["s-watch-1"]) {
        self.directory = directory
        self.store = FileWatchSessionStore(directory: directory)
        self.sessionIds = sessionIds
    }

    @discardableResult
    func launch() async -> FileStoreHarness {
        store = FileWatchSessionStore(directory: directory)
        engine = WatchSessionEngine(
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.recordIds += 1
                return "rec-\(self.recordIds)"
            },
            sessionIdFactory: { [weak self] in
                guard let self, !self.sessionIds.isEmpty else { return UUID().uuidString }
                return self.sessionIds.removeFirst()
            }
        )
        preferences = WatchPhonePreferences(store: store, validator: Harness.validator(), clock: clock.call)
        rating = WatchEffortRatingState(
            engine: engine,
            store: store,
            preferences: preferences,
            clock: clock.call
        )

        await engine.restore()
        await preferences.restore()
        await rating.restore()
        return self
    }

    /// The phone's setting arriving at a wrist sync.
    func sync(_ asks: Bool, generatedAt: String) async {
        _ = await preferences.applyPreferencesDown(
            preferencesDown(asks, generatedAt: generatedAt)
        )
    }

    func startSession(_ slots: [[String: Any]]) async {
        _ = await engine.createSession(modality: nil, exercises: slots)
    }

    func logSet(_ entryId: String, advanceBy seconds: Double) async throws {
        try await engine.appendObservation(setEvent(clock, entryId: entryId))
        clock.advance(seconds)
    }

    /// S-44's fixture: a free session with two slots, three sets on the bench,
    /// the phone's receipts for the first two, a running rest timer and the
    /// ladder moved to the second exercise.
    func logS44Fixture() async throws {
        await startSession([
            fileSlot("sx-bench", capabilities: ["reps", "sets", "load"]),
            fileSlot("sx-run", capabilities: ["time", "distance"]),
        ])
        for entryId in ["entry-1", "entry-2", "entry-3"] {
            try await logSet(entryId, advanceBy: 30)
        }
        _ = await engine.confirmObservations(["entry-1", "entry-2"])
        _ = try await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 90_000)
        clock.advance(30)
        _ = await engine.advanceExercise()
    }
}

final class WatchFileStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-file-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private var fileURL: URL {
        directory.appendingPathComponent("watch-session.jsonl")
    }

    private func fileLines() throws -> [String] {
        try Data(contentsOf: fileURL).split(separator: 0x0A).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - S-49 a torn last record

    func testS49ATornLastRecordCostsThatRecordOnly() async throws {
        let at = fileInstant("2026-10-06T12:00:00Z")
        let first = FileWatchSessionStore(directory: directory)
        for index in 1...3 {
            _ = await first.append(fileSessionRow("s-\(index)", at: at))
        }

        // The shape a kill during an append leaves: the last line ends mid-JSON.
        var torn = try Data(contentsOf: fileURL)
        torn.removeLast(5)
        try torn.write(to: fileURL)

        let second = FileWatchSessionStore(directory: directory)
        let read = await second.readAll()
        XCTAssertEqual(
            read.sessions.map(\.recordId),
            ["s-1", "s-2"],
            "S-49 the torn line is skipped and every intact row still reads"
        )

        _ = await second.append(fileSessionRow("s-4", at: at))

        let third = FileWatchSessionStore(directory: directory)
        let after = await third.readAll()
        XCTAssertEqual(
            after.sessions.map(\.recordId),
            ["s-1", "s-2", "s-4"],
            "S-49 the next append lands as the new final line"
        )
    }

    // MARK: - S-50 a first launch on an empty store

    func testS50AFirstLaunchOnAnEmptyStoreWritesOneMarker() async throws {
        let store = FileWatchSessionStore(directory: directory)
        let empty = await store.readAll()
        XCTAssertTrue(empty.isEmpty, "S-50 an empty directory reads as an empty store")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.path),
            "S-50 a read creates nothing"
        )

        let at = fileInstant("2026-10-06T12:00:00Z")
        let stored = await store.append(fileSessionRow("s-1", at: at))
        XCTAssertEqual(stored.sequence, 1, "S-50 the first append is sequence 1")

        let contents = await store.readAll()
        XCTAssertEqual(contents.sessions.map(\.recordId), ["s-1"], "S-50 the row reads back")
        XCTAssertEqual(contents.sessions.first?.sequence, 1, "S-50 with its sequence")

        let lines = try fileLines()
        XCTAssertEqual(lines.count, 2, "S-50 exactly one marker line and one record line")
        XCTAssertEqual(lines.first, markerText, "S-50 the marker is the file's first line")
    }

    // MARK: - S-51 two relaunches in a row

    func testS51TwoRelaunchesKeepEveryRowAndItsSequence() async throws {
        let at = fileInstant("2026-10-06T12:00:00Z")
        let first = FileWatchSessionStore(directory: directory)
        for index in 1...3 {
            _ = await first.append(fileSessionRow("s-\(index)", at: at))
        }

        let second = FileWatchSessionStore(directory: directory)
        _ = await second.append(fileSessionRow("s-4", at: at))

        let third = FileWatchSessionStore(directory: directory)
        _ = await third.append(fileSessionRow("s-5", at: at))

        let rows = (await third.readAll()).sessions
        XCTAssertEqual(rows.map(\.recordId), ["s-1", "s-2", "s-3", "s-4", "s-5"], "S-51 nothing is lost")
        XCTAssertEqual(rows.map(\.sequence), [1, 2, 3, 4, 5], "S-51 sequences keep climbing")

        let before = try fileLines().count
        let repeated = await third.append(fileSessionRow("s-3", at: at))
        XCTAssertEqual(repeated.sequence, 3, "S-51 a re-append returns the stored row")
        XCTAssertEqual(try fileLines().count, before, "S-51 a re-append adds no line")

        // A prune leaves a hole in the sequence, so the next append follows the
        // highest stored row rather than how many rows are left.
        for entryId in ["o-1", "o-2", "o-3"] {
            _ = await third.append(
                .observation(
                    WatchObservationRecord(
                        recordId: entryId,
                        sessionId: "s-file",
                        recordedAt: at,
                        kind: WatchObservationKind.set,
                        payload: ["entryId": entryId]
                    )
                )
            )
        }
        _ = await third.append(
            .confirmation(
                WatchConfirmationRecord(
                    recordId: "c-1",
                    sessionId: "s-file",
                    recordedAt: at,
                    observationIds: ["o-2"]
                )
            )
        )
        let pruned = await third.pruneConfirmed()
        XCTAssertEqual(pruned, ["o-2"], "S-51 the confirmed row is the one dropped")

        let afterPrune = await third.append(fileSessionRow("s-6", at: at))
        XCTAssertEqual(
            afterPrune.sequence,
            10,
            "S-51 the sequence follows the highest stored row, not the row count"
        )
    }

    // MARK: - S-53 a version this binary does not know

    func testS53AVersionThisBinaryDoesNotKnowIsNeverDamaged() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let at = fileInstant("2026-10-06T12:00:00Z")
        let existing = fileSessionRow("s-1", at: at)
        var bytes = Data(#"{"format":"omnitrain-watch-store","version":2}"#.utf8)
        bytes.append(0x0A)
        bytes.append(try JSONSerialization.data(withJSONObject: existing.toJson(), options: [.sortedKeys]))
        bytes.append(0x0A)
        try bytes.write(to: fileURL)

        let store = FileWatchSessionStore(directory: directory)
        let contents = await store.readAll()
        XCTAssertTrue(contents.isEmpty, "S-53 an unknown version reads as empty")

        let before = try Data(contentsOf: fileURL)
        let handed = fileSessionRow("s-2", at: at)
        let returned = await store.append(handed)
        XCTAssertEqual(fileJSON(returned), fileJSON(handed), "S-53 the append returns the record it was handed")
        XCTAssertEqual(returned.sequence, 0, "S-53 nothing was assigned")
        XCTAssertEqual(try Data(contentsOf: fileURL), before, "S-53 the file is byte-identical")
    }

    // MARK: - S-54 the two stores agree

    func testS54TheTwoStoresAgreeOnOneSequence() async throws {
        let at = fileInstant("2026-10-06T12:00:00.500Z")
        let sessionId = "s-parity"
        let fileStore = FileWatchSessionStore(directory: directory)
        let memoryStore = InMemoryWatchSessionStore()

        let script: [StoredWatchRecord] = [
            fileSessionRow("sess-1", sessionId: sessionId, at: at),
            .observation(
                WatchObservationRecord(
                    recordId: "obs-1",
                    sessionId: sessionId,
                    recordedAt: at,
                    kind: WatchObservationKind.set,
                    payload: [
                        "entryId": "e-1",
                        "eventId": "e-1",
                        "kind": WatchObservationKind.set,
                        "loggedAt": utcIso(at),
                    ]
                )
            ),
            .observation(
                WatchObservationRecord(
                    recordId: "obs-2",
                    sessionId: sessionId,
                    recordedAt: at,
                    kind: WatchObservationKind.set,
                    payload: [
                        "entryId": "e-2",
                        "eventId": "e-2",
                        "kind": WatchObservationKind.set,
                        "loggedAt": utcIso(at),
                    ]
                )
            ),
            .timer(
                WatchTimerRecord(
                    recordId: "tim-1",
                    sessionId: sessionId,
                    recordedAt: at,
                    kind: WatchTimerKind.rest,
                    startedAt: at,
                    plannedDurationMs: 90_000
                )
            ),
            .confirmation(
                WatchConfirmationRecord(
                    recordId: "con-1",
                    sessionId: sessionId,
                    recordedAt: at,
                    observationIds: ["obs-1"]
                )
            ),
            .sensorSample(
                WatchSensorSampleRecord(
                    recordId: "sen-1",
                    sessionId: sessionId,
                    recordedAt: at,
                    kind: WatchSensorKind.heartRate,
                    value: 128
                )
            ),
            .routineCatalog(WatchRoutineCatalogRecord(recordId: "rou-1", recordedAt: at, generatedAt: at)),
            .foodCatalog(WatchFoodCatalogRecord(recordId: "foo-1", recordedAt: at, generatedAt: at)),
            .preferences(
                WatchPreferencesRecord(
                    recordId: "pre-1",
                    recordedAt: at,
                    generatedAt: at,
                    effortRatingPrompt: true
                )
            ),
            .ratingPrompt(
                WatchRatingPromptRecord(
                    recordId: WatchRatingPromptRecord.recordIdFor(sessionId),
                    sessionId: sessionId,
                    recordedAt: at
                )
            ),
        ]

        for record in script {
            _ = await fileStore.append(record)
            _ = await memoryStore.append(record)
        }

        let filePruned = await fileStore.pruneConfirmed()
        let memoryPruned = await memoryStore.pruneConfirmed()
        XCTAssertEqual(filePruned, memoryPruned, "S-54 both prunes drop the same confirmed observations")

        let fileSensorPruned = await fileStore.pruneSensorSamples([sessionId])
        let memorySensorPruned = await memoryStore.pruneSensorSamples([sessionId])
        XCTAssertEqual(fileSensorPruned, memorySensorPruned, "S-54 both prunes drop the same sensor samples")

        let fileContents = await fileStore.readAll()
        let memoryContents = await memoryStore.readAll()
        XCTAssertEqual(
            fileFamilyJSON(fileContents),
            fileFamilyJSON(memoryContents),
            "S-54 the two stores answer family by family, in append order, with the same sequences"
        )
    }

    // MARK: - S-44 a logged set survives the process

    func testS44ALoggedSetSurvivesTheProcess() async throws {
        let wrist = FileStoreHarness(directory: directory)
        await wrist.launch()
        try await wrist.logS44Fixture()

        let relaunched = FileStoreHarness(directory: directory)
        relaunched.clock.now = wrist.clock.now
        await relaunched.launch()

        let session = try XCTUnwrap(relaunched.engine.session, "S-44 the session came back")
        XCTAssertEqual(session.status, WatchSessionStatus.active, "S-44 still active")
        XCTAssertEqual(
            session.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-bench", "sx-run"],
            "S-44 both slots, in order"
        )
        XCTAssertEqual(session.currentExerciseIndex, 1, "S-44 the ladder position survived")
        XCTAssertEqual(
            relaunched.engine.observations.map(\.entryId),
            ["entry-1", "entry-2", "entry-3"],
            "S-44 all three sets"
        )
        XCTAssertEqual(
            relaunched.engine.observations[0].payload["reps"] as? Int,
            5,
            "S-44 the payload survived"
        )
        XCTAssertNotNil(relaunched.engine.observations[0].confirmedAt, "S-44 entry-1 carries its receipt")
        XCTAssertNotNil(relaunched.engine.observations[1].confirmedAt, "S-44 entry-2 carries its receipt")
        XCTAssertNil(relaunched.engine.observations[2].confirmedAt, "S-44 entry-3 is unconfirmed")
        XCTAssertNotNil(
            relaunched.engine.timerFor(WatchTimerKind.rest),
            "S-44 the rest timer survived with its startedAt"
        )
    }

    // MARK: - S-45 exactly one delivery after a relaunch

    func testS45ExactlyOneDeliveryAfterARelaunch() async throws {
        let wrist = FileStoreHarness(directory: directory)
        await wrist.launch()
        try await wrist.logS44Fixture()

        let relaunched = FileStoreHarness(directory: directory)
        relaunched.clock.now = wrist.clock.now
        await relaunched.launch()

        let pending = relaunched.engine.pendingObservations()
        let events = pending.compactMap {
            (($0["payload"] as? [String: Any])?["events"] as? [[String: Any]])?.first
        }
        XCTAssertEqual(events.count, 1, "S-45 exactly one delivery")
        XCTAssertEqual(
            events.map { $0["entryId"] as? String },
            ["entry-3"],
            "S-45 the unconfirmed set and never the confirmed ones"
        )
    }

    // MARK: - S-46 a countdown that was running is still right

    func testS46ACountdownThatWasRunningIsStillRight() async throws {
        let wrist = FileStoreHarness(directory: directory)
        await wrist.launch()
        try await wrist.logS44Fixture()
        let killedAt = wrist.clock.now

        let relaunched = FileStoreHarness(directory: directory)
        relaunched.clock.now = wrist.clock.now
        await relaunched.launch()

        let rest = try XCTUnwrap(relaunched.engine.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(
            rest.startedAt,
            killedAt.addingTimeInterval(-30),
            "S-46 the stored startedAt is the timer's, untouched"
        )
        XCTAssertEqual(
            remainingMs(rest, now: relaunched.clock.now),
            60_000,
            "S-46 60 s left when the kill happened"
        )

        relaunched.clock.advance(30)
        XCTAssertEqual(
            remainingMs(rest, now: relaunched.clock.now),
            30_000,
            "S-46 the countdown derives from the stored startedAt, not a frozen counter"
        )
    }

    // MARK: - S-47 the owed rating question survives the kill

    func testS47TheOwedRatingQuestionSurvivesTheKill() async throws {
        let wrist = FileStoreHarness(directory: directory)
        await wrist.launch()
        await wrist.sync(true, generatedAt: "2026-10-06T11:00:00Z")
        await wrist.startSession([fileSlot("sx-bench", capabilities: ["reps", "sets", "load"])])
        try await wrist.logSet("entry-1", advanceBy: 60)
        try await wrist.logSet("entry-2", advanceBy: 60)
        _ = await wrist.engine.confirmObservations(["entry-1", "entry-2"])
        await wrist.rating.end()
        XCTAssertEqual(wrist.rating.owedSessionIds, ["s-watch-1"], "S-47 the End owed a rating")

        let relaunched = FileStoreHarness(directory: directory)
        relaunched.clock.now = wrist.clock.now
        await relaunched.launch()
        XCTAssertEqual(
            relaunched.rating.owedSessionIds,
            ["s-watch-1"],
            "S-47 the prompt row survived, so the question is asked again"
        )

        relaunched.clock.advance(120)
        relaunched.rating.select(4)
        try await relaunched.rating.confirm()

        let ratings = relaunched.engine.observations.filter {
            $0.kind == WatchObservationKind.effortRating
        }
        XCTAssertEqual(ratings.count, 1, "S-47 exactly one rating is recorded")
        XCTAssertEqual(ratings.first?.payload["rating"] as? Int, 4, "S-47 with the answer given")
        XCTAssertFalse(relaunched.rating.isPromptOwed, "S-47 the question is settled")

        let third = FileStoreHarness(directory: directory)
        third.clock.now = relaunched.clock.now
        await third.launch()
        XCTAssertFalse(third.rating.isPromptOwed, "S-47 a further relaunch asks nothing")
        XCTAssertEqual(
            third.engine.observations.filter { $0.kind == WatchObservationKind.effortRating }.count,
            1,
            "S-47 and the single rating is still the only one"
        )
    }
}
