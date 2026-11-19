//
//  WatchLaunchParseTests.swift
//  WatchSessionEngineTests
//
//  S-17301 to S-17307 of
//  `docs/plans/2026-11-14-173-watch-launch-parse-plan/2026-11-14-173-watch-launch-parse-plan.md`:
//  a launch reads the small rows and stops parsing the whole stored history.
//
//  These run over the real `FileWatchSessionStore` in a temporary directory,
//  because the cost this plan is about is a cost on disk. A `launch()` here is a
//  new store and a new engine over the same file — what a relaunch is.
//

import XCTest

@testable import WatchSessionEngine

private let launchDay: TimeInterval = 24 * 60 * 60

/// The kinds a seeded reading cycles through, so a fixture has more than one
/// kind of reading in it.
private let launchKinds = [WatchSensorKind.heartRate, WatchSensorKind.gps]

/// A wrist over one directory. Every `launch()` builds a fresh store and a fresh
/// engine over the same file, minting record ids that never repeat across
/// launches so a row written by one launch cannot collide with another's.
private final class LaunchWrist {
    let directory: URL
    let clock = TestClock(testInstant())

    private(set) var store: FileWatchSessionStore
    private var recordIds = 0

    init(directory: URL) {
        self.directory = directory
        self.store = FileWatchSessionStore(directory: directory)
    }

    /// A launch: a new store, a new engine, and `restore()`. Nothing else
    /// crosses the boundary.
    func launch() async -> WatchSessionEngine {
        store = FileWatchSessionStore(directory: directory)
        let engine = WatchSessionEngine(
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.recordIds += 1
                return "l-\(self.recordIds)"
            },
            sessionIdFactory: { "s-launch-\(UUID().uuidString)" }
        )
        await engine.restore()
        return engine
    }

    /// Two readings a second apart, so they are two rows rather than one
    /// instant's duplicate.
    func readTwo(_ engine: WatchSessionEngine) async {
        _ = await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 118)
        clock.advance(1)
        _ = await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 4.2)
        clock.advance(1)
    }

    /// The phone's receipt for `entryIds`, shaped as the radio delivers it.
    func receiptFrame(_ entryIds: [String]) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-receipt-\(entryIds.joined(separator: "-"))",
            "type": "receipt",
            "origin": "phone",
            "sentAt": utcIso(clock.now),
            "payload": ["entryIds": entryIds],
        ]
    }
}

private func launchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("watch-launch-parse-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func launchMainURL(_ directory: URL) -> URL {
    directory.appendingPathComponent("watch-session.jsonl")
}

private func launchSideURL(_ directory: URL, sessionId: String) -> URL {
    directory.appendingPathComponent("watch-samples-\(sessionId).jsonl")
}

/// The store file's identity: its inode and its bytes. Identity is what a
/// rewrite changes even when the bytes come out the same.
private func launchStoreFile(_ directory: URL) throws -> (inode: Int, bytes: Data) {
    let url = launchMainURL(directory)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (
        inode: (attributes[.systemFileNumber] as? NSNumber)?.intValue ?? -1,
        bytes: try Data(contentsOf: url)
    )
}

private func launchJsonLine(_ record: StoredWatchRecord) throws -> String {
    let data = try JSONSerialization.data(
        withJSONObject: record.toJson(),
        options: [.sortedKeys]
    )
    return String(decoding: data, as: UTF8.self)
}

/// Writes a store file holding exactly `rows`: the shape a former launch leaves
/// behind — the format marker, then one JSON line per row.
private func launchWriteMain(_ directory: URL, rows: [StoredWatchRecord]) throws {
    let marker = #"{"format":"omnitrain-watch-store","version":1}"#
    let lines = try rows.map(launchJsonLine)
    let text = ([marker] + lines).joined(separator: "\n") + "\n"
    try text.write(to: launchMainURL(directory), atomically: true, encoding: .utf8)
}

/// Writes one session's side file, the shape the store leaves behind once it has
/// moved a finished workout's readings out of the main file.
private func launchWriteSide(
    _ directory: URL,
    sessionId: String,
    rows: [WatchSensorSampleRecord]
) throws {
    let lines = try rows.map { try launchJsonLine(StoredWatchRecord.sensorSample($0)) }
    let text = lines.joined(separator: "\n") + "\n"
    try text.write(to: launchSideURL(directory, sessionId: sessionId), atomically: true, encoding: .utf8)
}

/// Every row the main file holds, parsed the way the store parses it.
private func launchMainRows(_ directory: URL) throws -> [StoredWatchRecord] {
    let text = try String(contentsOf: launchMainURL(directory), encoding: .utf8)
    return text
        .split(separator: "\n")
        .compactMap { line -> StoredWatchRecord? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return try? StoredWatchRecord.fromJson(json)
        }
}

/// One session's side file, parsed the way the store parses it. An absent file
/// is an empty list, which is what a launch sees after a release.
private func launchSideRows(
    _ directory: URL,
    sessionId: String
) throws -> [WatchSensorSampleRecord] {
    let url = launchSideURL(directory, sessionId: sessionId)
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let text = try String(contentsOf: url, encoding: .utf8)
    return text
        .split(separator: "\n")
        .compactMap { line -> WatchSensorSampleRecord? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["recordType"] as? String) == StoredWatchRecord.sensorSampleType
            else { return nil }
            return try? WatchSensorSampleRecord.fromJson(json)
        }
}

private func launchInlineSamples(_ rows: [StoredWatchRecord]) -> [WatchSensorSampleRecord] {
    rows.compactMap { row -> WatchSensorSampleRecord? in
        guard case .sensorSample(let sample) = row else { return nil }
        return sample
    }
}

// MARK: - Fixtures

/// `count` readings for `sessionId`, cycling through `launchKinds`, each with a
/// record id derived from its session, kind and ordinal.
private func launchSamples(
    _ sessionId: String,
    count: Int,
    base: Int,
    at: Date
) -> [WatchSensorSampleRecord] {
    (1...count).map { ordinal in
        let kind = launchKinds[(ordinal - 1) % launchKinds.count]
        return WatchSensorSampleRecord(
            recordId: "sen-\(sessionId)-\(kind)-\(ordinal)",
            sessionId: sessionId,
            recordedAt: at.addingTimeInterval(Double(ordinal)),
            kind: kind,
            value: Double(ordinal),
            sequence: base + ordinal
        )
    }
}

private func launchSessionRow(
    _ sessionId: String,
    status: String,
    sequence: Int,
    at: Date
) -> StoredWatchRecord {
    .session(
        WatchSessionRecord(
            recordId: "row-\(sessionId)-\(sequence)",
            sessionId: sessionId,
            recordedAt: at,
            startedAt: at,
            modality: "outdoor_run",
            source: "watch",
            status: status,
            currentExerciseIndex: 0
        )
    )
}

private func launchEndRow(
    _ sessionId: String,
    sequence: Int,
    at: Date
) -> StoredWatchRecord {
    .observation(
        WatchObservationRecord(
            recordId: WatchSessionCapture.sessionEndId(sessionId),
            sessionId: sessionId,
            recordedAt: at,
            kind: WatchObservationKind.sessionEnd,
            payload: [
                "entryId": WatchSessionCapture.sessionEndId(sessionId),
                "eventId": "evt-\(sessionId)",
                "kind": WatchObservationKind.sessionEnd,
                "startedAt": utcIso(at),
                "endedAt": utcIso(at.addingTimeInterval(600)),
                "status": WatchSessionStatus.completed,
            ],
            sequence: sequence
        )
    )
}

/// Ten finished workouts whose readings already live in side files, and one
/// running workout whose readings do not: what a wrist that has been through
/// this plan for a while holds. `57,000` old readings in all.
private func launchSteadyState(
    _ directory: URL,
    sideFileRows: Int = 5_700
) throws {
    let at = testInstant()
    var sequence = 0
    // The running workout's row comes first: a seeded row carries no order of
    // its own, so `restore()` reads the file's first session row as the current
    // one.
    var rows: [StoredWatchRecord] = [
        launchSessionRow("s-live", status: WatchSessionStatus.active, sequence: 1, at: at)
    ]
    for index in 1...10 {
        sequence += 1
        rows.append(
            launchSessionRow(
                "s-old-\(index)",
                status: WatchSessionStatus.completed,
                sequence: sequence + 1,
                at: at
            )
        )
    }
    for index in 1...10 {
        sequence += 1
        rows.append(launchEndRow("s-old-\(index)", sequence: sequence + 11, at: at))
    }
    try launchWriteMain(directory, rows: rows)
    for index in 1...10 {
        try launchWriteSide(
            directory,
            sessionId: "s-old-\(index)",
            rows: sideFileRows == 0
                ? []
                : launchSamples(
                    "s-old-\(index)",
                    count: sideFileRows,
                    base: index * 10_000,
                    at: at
                )
        )
    }
}

/// The October shape: the same eleven sessions with every reading still inline
/// in one file, and a hundred of them belonging to the running workout.
private func launchOctoberState(_ directory: URL) throws {
    let at = testInstant()
    var sequence = 1
    var rows: [StoredWatchRecord] = [
        launchSessionRow("s-live", status: WatchSessionStatus.active, sequence: sequence, at: at)
    ]
    for index in 1...10 {
        sequence += 1
        rows.append(
            launchSessionRow(
                "s-old-\(index)",
                status: WatchSessionStatus.completed,
                sequence: sequence,
                at: at
            )
        )
    }
    for index in 1...10 {
        sequence += 1
        rows.append(launchEndRow("s-old-\(index)", sequence: sequence, at: at))
    }
    for index in 1...10 {
        for sample in launchSamples(
            "s-old-\(index)",
            count: 5_700,
            base: index * 10_000,
            at: at
        ) {
            rows.append(.sensorSample(sample))
        }
    }
    for sample in launchSamples("s-live", count: 100, base: 500_000, at: at) {
        rows.append(.sensorSample(sample))
    }
    try launchWriteMain(directory, rows: rows)
}

/// Records are not `Equatable`; their ids, sessions, kinds and values are what
/// the two stores must reproduce value for value. The store assigns `sequence`
/// itself, so it is not part of the signature.
private func launchSignatures(_ rows: [WatchSensorSampleRecord]) -> [String] {
    rows.map { "\($0.recordId)|\($0.sessionId)|\($0.kind)|\($0.value)" }.sorted()
}

final class WatchLaunchParseTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories.removeAll()
        super.tearDown()
    }

    private func makeDirectory() throws -> URL {
        let directory = try launchDirectory()
        directories.append(directory)
        return directory
    }

    /// S-17301: ten finished workouts and one running one, fifty-seven thousand
    /// readings in ten side files. A launch decodes the twenty-two small rows and
    /// nothing else — and stays there when the side files grow fivefold.
    func testS17301TheLaunchDecodesTheSmallRowsOnly() async throws {
        let directory = try makeDirectory()
        try launchSteadyState(directory)

        let wrist = LaunchWrist(directory: directory)
        let engine = await wrist.launch()

        XCTAssertEqual(
            wrist.store.rowsDecodedForTesting,
            22,
            "a launch decodes the marker, eleven session rows and ten end rows (S-17301)"
        )
        XCTAssertTrue(engine.sensorSamples.isEmpty, "a finished workout's readings are not read at launch")

        for index in 1...10 {
            try launchWriteSide(
                directory,
                sessionId: "s-old-\(index)",
                rows: launchSamples(
                    "s-old-\(index)",
                    count: 28_500,
                    base: index * 10_000,
                    at: testInstant()
                )
            )
        }

        let grownWrist = LaunchWrist(directory: directory)
        let grown = await grownWrist.launch()
        XCTAssertEqual(
            grownWrist.store.rowsDecodedForTesting,
            22,
            "the side files grow fivefold and the launch still decodes twenty-two rows (S-17301)"
        )
        XCTAssertTrue(grown.sensorSamples.isEmpty)

        // The exclusion is the launch set's own, not a side effect of the move: a
        // store whose side file cannot be written — a directory sits where the
        // temporary copy belongs — still launches without the finished workout's
        // readings.
        let stuck = try makeDirectory()
        let stuckAt = testInstant()
        try launchWriteMain(
            stuck,
            rows: [
                launchSessionRow(
                    "s-stuck",
                    status: WatchSessionStatus.completed,
                    sequence: 1,
                    at: stuckAt
                )
            ] + launchSamples("s-stuck", count: 3, base: 0, at: stuckAt)
                .map { StoredWatchRecord.sensorSample($0) }
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: launchSideURL(stuck, sessionId: "s-stuck").path + ".tmp"),
            withIntermediateDirectories: true
        )
        let blocked = FileWatchSessionStore(directory: stuck)
        let blockedLaunch = await blocked.readLaunch()
        XCTAssertEqual(
            blockedLaunch.sensorSamples.map(\.recordId),
            [],
            "a launch hands out no finished workout's readings, even inline ones (S-17301)"
        )
        let blockedAll = await blocked.readAll()
        XCTAssertEqual(blockedAll.sensorSamples.count, 3, "a full read still finds them")
        XCTAssertEqual(
            launchInlineSamples(try launchMainRows(stuck)).count,
            3,
            "and the move that could not be written left the main file as it was"
        )
    }

    /// S-17302: the October file — every reading inline — is migrated at the
    /// first launch: the finished workouts' readings move to ten side files
    /// verbatim, the running workout's hundred stay put, nothing is dropped, and
    /// the second launch moves nothing.
    func testS17302TheOctoberFileIsMigratedAtTheFirstLaunch() async throws {
        let directory = try makeDirectory()
        try launchOctoberState(directory)

        let wrist = LaunchWrist(directory: directory)
        _ = await wrist.launch()

        let mainRows = try launchMainRows(directory)
        XCTAssertEqual(
            mainRows.filter { $0.recordType == StoredWatchRecord.sessionType }.count,
            11,
            "the migration keeps every session row"
        )
        XCTAssertEqual(
            mainRows.filter { $0.recordType == StoredWatchRecord.observationType }.count,
            10,
            "the migration keeps every observation row"
        )
        let inline = launchInlineSamples(mainRows)
        XCTAssertEqual(Set(inline.map(\.sessionId)), ["s-live"], "only the running workout keeps inline readings")
        XCTAssertEqual(inline.count, 100, "the running workout's hundred readings stay inline")

        for index in 1...10 {
            let side = try launchSideRows(directory, sessionId: "s-old-\(index)")
            let expected = launchSamples("s-old-\(index)", count: 5_700, base: index * 10_000, at: testInstant())
            XCTAssertEqual(
                side.map(\.recordId),
                expected.map(\.recordId),
                "the side file holds the finished workout's readings verbatim, in order"
            )
            XCTAssertEqual(side.map(\.value), expected.map(\.value))
        }

        let all = await FileWatchSessionStore(directory: directory).readAll()
        XCTAssertEqual(all.sensorSamples.count, 57_100, "every reading is still readable after the migration")
        XCTAssertEqual(
            Set(all.sensorSamples.map(\.recordId)).count,
            57_100,
            "every reading is readable exactly once"
        )

        let before = try launchStoreFile(directory)
        let second = LaunchWrist(directory: directory)
        _ = await second.launch()
        let after = try launchStoreFile(directory)
        XCTAssertEqual(
            after.inode,
            before.inode,
            "a launch with nothing to move does not rewrite the store (D-15603)"
        )
        XCTAssertEqual(after.bytes, before.bytes, "and changes none of its bytes")
    }

    /// S-17303: a kill between the side-file write and the compaction leaves the
    /// readings in both places. The next load heals it — the side file is
    /// rewritten from the inline rows, the inline ones go, and no reading is
    /// returned twice.
    func testS17303AKillBetweenTheTwoWritesIsHealedByTheNextLoad() async throws {
        let directory = try makeDirectory()
        let at = testInstant()
        let samples = launchSamples("s-both", count: 3, base: 10, at: at)
        try launchWriteMain(
            directory,
            rows: [launchSessionRow("s-both", status: WatchSessionStatus.completed, sequence: 1, at: at)]
                + samples.map(StoredWatchRecord.sensorSample)
        )
        try launchWriteSide(directory, sessionId: "s-both", rows: samples)

        let wrist = LaunchWrist(directory: directory)
        let engine = await wrist.launch()

        XCTAssertTrue(
            launchInlineSamples(try launchMainRows(directory)).isEmpty,
            "the next load moves the inline copies out"
        )
        XCTAssertEqual(
            try launchSideRows(directory, sessionId: "s-both").map(\.recordId),
            samples.map(\.recordId),
            "and the side file is the copy that survives"
        )
        XCTAssertTrue(engine.sensorSamples.isEmpty, "a finished workout's readings are not read at launch")

        let all = await FileWatchSessionStore(directory: directory).readAll()
        XCTAssertEqual(all.sensorSamples.count, 3, "each reading is readable once")
        XCTAssertEqual(Set(all.sensorSamples.map(\.recordId)).count, 3, "and no reading is readable twice")
    }

    /// S-17304: a workout recovered after a kill keeps its chain, then gives its
    /// readings up when it ends: they land in its side file, the launch after it
    /// decodes none of them, and nothing is deleted before the phone's receipt.
    func testS17304ARecoveredWorkoutKeepsItsChainAndGivesItsReadingsUpAtTheEnd() async throws {
        let directory = try makeDirectory()
        try launchOctoberState(directory)

        let migrator = LaunchWrist(directory: directory)
        _ = await migrator.launch()

        let recoveredWrist = LaunchWrist(directory: directory)
        let recovered = await recoveredWrist.launch()
        XCTAssertEqual(recovered.sensorSamples.count, 100, "the running workout's readings survive the kill")
        XCTAssertEqual(recovered.session?.sessionId, "s-live", "the running workout is still the current one")

        _ = await recovered.appendSensorSample(kind: WatchSensorKind.heartRate, value: 131)
        XCTAssertEqual(recovered.sensorSamples.count, 101, "and the next reading joins them")
        _ = await recovered.finishSession()
        XCTAssertEqual(
            try launchSideRows(directory, sessionId: "s-live").count,
            101,
            "ending the workout moves every one of its readings to its side file"
        )
        XCTAssertFalse(
            launchInlineSamples(try launchMainRows(directory)).contains { $0.sessionId == "s-live" },
            "and leaves none of them inline"
        )

        let afterEnd = LaunchWrist(directory: directory)
        let relaunched = await afterEnd.launch()
        XCTAssertEqual(
            afterEnd.store.rowsDecodedForTesting,
            24,
            "the launch after the end decodes eleven sessions, eleven end rows and the marker (S-17304)"
        )
        XCTAssertTrue(relaunched.sensorSamples.isEmpty)

        let all = await FileWatchSessionStore(directory: directory).readAll()
        XCTAssertEqual(
            all.sensorSamples.filter { $0.sessionId == "s-live" }.count,
            101,
            "the readings are still there until the phone holds what was computed from them"
        )
    }

    /// S-17305: the release gates reach the side files — a receipt deletes the
    /// file of a finished workout, the fourteen-day valve deletes one nobody
    /// confirmed, a younger unconfirmed file stays, and a second call does
    /// nothing.
    func testS17305TheReleaseGatesDeleteSideFiles() async throws {
        let directory = try makeDirectory()
        let wrist = LaunchWrist(directory: directory)

        let old = await wrist.launch()
        let oldSession = await old.createSession(modality: "outdoor_run", exercises: [exercise("sx-bench")])
        await wrist.readTwo(old)
        _ = try await old.appendObservation(setEvent(wrist.clock, entryId: "e-old"))
        _ = await old.finishSession()
        let oldReadings = old.sensorSamples.map(\.recordId)

        wrist.clock.advance(2 * launchDay)

        let young = await wrist.launch()
        let youngSession = await young.createSession(modality: "outdoor_run", exercises: [exercise("sx-bench")])
        await wrist.readTwo(young)
        _ = try await young.appendObservation(setEvent(wrist.clock, entryId: "e-young"))
        _ = await young.finishSession()
        let youngReadings = young.sensorSamples.map(\.recordId)

        let receipted = await wrist.launch()
        let receiptedSession = await receipted.createSession(
            modality: "outdoor_run",
            exercises: [exercise("sx-bench")]
        )
        await wrist.readTwo(receipted)
        _ = try await receipted.appendObservation(setEvent(wrist.clock, entryId: "e-receipted"))
        _ = await receipted.finishSession()
        _ = await receipted.confirmObservations([
            "e-receipted",
            WatchSessionCapture.sessionEndId(receiptedSession.sessionId),
        ])
        let receiptedReadings = receipted.sensorSamples.map(\.recordId)

        // The workout ended a moment ago: only the receipt can settle it, so any
        // reading the release takes now came through the receipt's gate.
        let receiptReleased = await receipted.pruneSettledSensorSamples()
        XCTAssertEqual(
            Set(receiptReleased),
            Set(receiptedReadings),
            "the receipt releases a finished workout's side file (S-17305)"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: launchSideURL(directory, sessionId: receiptedSession.sessionId).path),
            "the released side file is deleted"
        )
        XCTAssertFalse(
            receiptReleased.contains { youngReadings.contains($0) },
            "a workout nobody confirmed keeps its readings (S-17305)"
        )
        XCTAssertEqual(
            try launchSideRows(directory, sessionId: youngSession.sessionId).count,
            2,
            "and its side file is still there"
        )

        wrist.clock.advance(13 * launchDay)

        let sweep = await wrist.launch()
        let released = await sweep.pruneSettledSensorSamples()

        XCTAssertTrue(
            Set(released).isSuperset(of: oldReadings),
            "the fourteen-day valve releases a side file nobody confirmed (S-17305)"
        )
        XCTAssertFalse(
            released.contains { youngReadings.contains($0) },
            "a thirteen-day-old unconfirmed side file stays (S-17305)"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: launchSideURL(directory, sessionId: oldSession.sessionId).path),
            "the expired side file is deleted"
        )
        XCTAssertEqual(
            try launchSideRows(directory, sessionId: youngSession.sessionId).count,
            2,
            "the young side file keeps its readings"
        )

        let before = try launchStoreFile(directory)
        let secondRelease = await sweep.pruneSettledSensorSamples()
        XCTAssertEqual(secondRelease, [], "a second release finds nothing")
        let after = try launchStoreFile(directory)
        XCTAssertEqual(after.inode, before.inode, "and does not rewrite the store")
    }

    /// S-17306: the in-memory twin answers `readLaunch()` and
    /// `archiveSensorSamples` value for value, so a test double never disagrees
    /// with the runtime.
    func testS17306TheTwinAnswersTheNewMembersValueForValue() async throws {
        let at = testInstant()
        let settled = launchSamples("s-done", count: 4, base: 100, at: at)
        let live = launchSamples("s-live", count: 3, base: 200, at: at)
        let rows: [StoredWatchRecord] = [
            launchSessionRow("s-done", status: WatchSessionStatus.completed, sequence: 1, at: at),
            launchSessionRow("s-live", status: WatchSessionStatus.active, sequence: 2, at: at),
            launchEndRow("s-done", sequence: 3, at: at),
        ] + settled.map(StoredWatchRecord.sensorSample) + live.map(StoredWatchRecord.sensorSample)

        let twin = InMemoryWatchSessionStore()
        for row in rows {
            _ = await twin.append(row)
        }

        let directory = try makeDirectory()
        try launchWriteMain(directory, rows: rows)
        let file = FileWatchSessionStore(directory: directory)

        let twinLaunch = await twin.readLaunch()
        let fileLaunch = await file.readLaunch()
        XCTAssertEqual(twinLaunch.sessions.count, fileLaunch.sessions.count)
        XCTAssertEqual(twinLaunch.observations.count, fileLaunch.observations.count)
        XCTAssertEqual(
            launchSignatures(twinLaunch.sensorSamples),
            launchSignatures(fileLaunch.sensorSamples),
            "the twin keeps a running workout's readings at launch, as the file does"
        )
        XCTAssertEqual(
            launchSignatures(twinLaunch.sensorSamples).count,
            3,
            "only the running workout's readings are in the launch set"
        )

        let twinAll = await twin.readAll()
        let fileAll = await file.readAll()
        XCTAssertEqual(twinAll.sessions.count, fileAll.sessions.count)
        XCTAssertEqual(twinAll.observations.count, fileAll.observations.count)
        XCTAssertEqual(
            launchSignatures(twinAll.sensorSamples),
            launchSignatures(fileAll.sensorSamples),
            "and both stores read a finished workout's readings back in full"
        )
        XCTAssertEqual(twinAll.sensorSamples.count, 7)

        let twinArchived = await twin.archiveSensorSamples("s-done")
        XCTAssertEqual(Set(twinArchived), Set(settled.map(\.recordId)))
        let twinAfter = await twin.readAll()
        XCTAssertEqual(twinAfter.sensorSamples.count, 7, "the twin keeps every reading it archived")

        // The file store's load-time migration has already moved the finished
        // workout's readings, so the archive parity is checked on a session the
        // migration leaves alone — the call the engine makes when a workout ends.
        let archiveDirectory = try makeDirectory()
        try launchWriteMain(archiveDirectory, rows: rows)
        let freshFile = FileWatchSessionStore(directory: archiveDirectory)
        let freshTwin = InMemoryWatchSessionStore()
        for row in rows {
            _ = await freshTwin.append(row)
        }
        let freshTwinArchived = await freshTwin.archiveSensorSamples("s-live")
        let freshFileArchived = await freshFile.archiveSensorSamples("s-live")
        XCTAssertEqual(
            freshTwinArchived,
            freshFileArchived,
            "archiving announces the same readings on both stores (S-17306)"
        )
        XCTAssertEqual(Set(freshFileArchived), Set(live.map(\.recordId)))
        let freshTwinAll = await freshTwin.readAll()
        let freshFileAll = await freshFile.readAll()
        XCTAssertEqual(
            launchSignatures(freshTwinAll.sensorSamples),
            launchSignatures(freshFileAll.sensorSamples),
            "and leaves both stores holding every reading"
        )
        XCTAssertEqual(freshFileAll.sensorSamples.count, 7)
        let freshTwinMissing = await freshTwin.archiveSensorSamples("s-missing")
        let freshFileMissing = await freshFile.archiveSensorSamples("s-missing")
        XCTAssertEqual(freshTwinMissing, freshFileMissing)
        XCTAssertEqual(freshTwinMissing, [])
    }

    /// S-17307: a launch over fifty-seven thousand old rows costs about what a
    /// launch over none does. The bound is a ratio, not a duration, so the test
    /// says nothing about how fast this machine is.
    func testS17307ALaunchOverFiftySevenThousandOldRowsCostsAtMostThreeTimesALaunchOverNone() async throws {
        // Both directories have the same main file and the same ten side files;
        // only the side files' contents differ — 57,000 readings in one, none in
        // the other. Anything else would measure the directory listing.
        let bare = try makeDirectory()
        let full = try makeDirectory()
        try launchSteadyState(bare, sideFileRows: 0)
        try launchSteadyState(full)

        func launchCost(_ directory: URL) async -> TimeInterval {
            let wrist = LaunchWrist(directory: directory)
            let start = DispatchTime.now()
            _ = await wrist.launch()
            return TimeInterval(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        }

        // A warm store each: the first launch of a directory creates its file.
        _ = await launchCost(bare)
        _ = await launchCost(full)

        // The cheapest of several launches is the least noisy estimate of what a
        // launch costs: under load an iteration or two stall for reasons that
        // have nothing to do with the file.
        var cheapestBare = TimeInterval.greatestFiniteMagnitude
        var cheapestFull = TimeInterval.greatestFiniteMagnitude
        for _ in 0..<5 {
            cheapestBare = min(cheapestBare, await launchCost(bare))
            cheapestFull = min(cheapestFull, await launchCost(full))
        }

        XCTAssertLessThanOrEqual(
            cheapestFull,
            max(cheapestBare, 0.001) * 3,
            "a launch over 57,000 old rows costs at most three times a launch over none (S-17307)"
        )
    }
}
