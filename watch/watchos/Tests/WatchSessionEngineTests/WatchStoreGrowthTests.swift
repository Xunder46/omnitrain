//
//  WatchStoreGrowthTests.swift
//  WatchSessionEngineTests
//
//  S-15601 to S-15606 of
//  `docs/plans/2026-11-13-156-watch-store-growth-plan/2026-11-13-156-watch-store-growth-plan.md`:
//  the watch's store stops growing forever, and stops costing more as it grows.
//
//  These run over the real `FileWatchSessionStore` in a temporary directory,
//  because the growth this plan is about is growth on disk. A `launch()` here is
//  a new store and a new engine over the same file — what a relaunch is.
//

import XCTest

@testable import WatchSessionEngine

private let growthDay: TimeInterval = 24 * 60 * 60

/// A wrist over one directory. Every `launch()` builds a fresh store and a fresh
/// engine over the same file, minting record ids that never repeat across
/// launches so a row written by one launch cannot collide with another's.
private final class GrowthWrist {
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
                return "g-\(self.recordIds)"
            },
            sessionIdFactory: { "s-growth-\(UUID().uuidString)" }
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

private func growthDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("watch-store-growth-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// The store file's identity: its inode and its bytes. Identity is what a
/// rewrite changes even when the bytes come out the same.
private func growthStoreFile(_ directory: URL) throws -> (inode: Int, bytes: Data) {
    let url = directory.appendingPathComponent("watch-session.jsonl")
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (
        inode: (attributes[.systemFileNumber] as? NSNumber)?.intValue ?? -1,
        bytes: try Data(contentsOf: url)
    )
}

/// The body of a `func` given its opening line, up to the closing brace at the
/// declaration's own indentation.
private func growthFunctionBody(_ header: String, in source: String) -> String? {
    guard let start = source.range(of: header) else { return nil }
    let tail = source[start.upperBound...]
    guard let end = tail.range(of: "\n    }\n") else { return String(tail) }
    return String(tail[..<end.lowerBound])
}

// MARK: - Phase B part 2 fixtures (D-15605, S-15606)

/// A reading for a store seeded directly, so a test can hold tens of thousands
/// of old workouts' rows without appending them one at a time.
private func growthSample(
    _ sessionId: String,
    kind: String,
    value: Double,
    sequence: Int,
    at: Date
) -> WatchSensorSampleRecord {
    WatchSensorSampleRecord(
        recordId: "sen-\(sessionId)-\(kind)-\(sequence)",
        sessionId: sessionId,
        recordedAt: at,
        kind: kind,
        value: value,
        sequence: sequence
    )
}

/// Writes a store file holding exactly `sensorSamples`, the shape a former
/// launch leaves behind: the format marker, then one JSON line per reading.
private func growthWriteStore(
    _ directory: URL,
    sensorSamples: [WatchSensorSampleRecord]
) throws {
    let marker = #"{"format":"omnitrain-watch-store","version":1}"#
    let lines = try sensorSamples.map { row -> String in
        let data = try JSONSerialization.data(
            withJSONObject: StoredWatchRecord.sensorSample(row).toJson(),
            options: [.sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }
    let text = ([marker] + lines).joined(separator: "\n") + "\n"
    try text.write(
        to: directory.appendingPathComponent("watch-session.jsonl"),
        atomically: true,
        encoding: .utf8
    )
}

/// `rows`' own filter for one session — the answer the per-session views must
/// reproduce without scanning anything else.
private func growthBruteSamples(
    _ rows: [WatchSensorSampleRecord],
    sessionId: String
) -> [WatchSensorSampleRecord] {
    rows.filter { $0.sessionId == sessionId }
}

/// The newest row per kind the way the whole log used to resolve it: the
/// greatest `sequence` wins, and an equal one keeps the row already held.
private func growthBruteNewest(
    _ rows: [WatchSensorSampleRecord],
    sessionId: String
) -> [String: WatchSensorSampleRecord] {
    var newest: [String: WatchSensorSampleRecord] = [:]
    for row in rows where row.sessionId == sessionId {
        if let existing = newest[row.kind], existing.sequence >= row.sequence { continue }
        newest[row.kind] = row
    }
    return newest
}

/// Records are not `Equatable`; their ids, kinds, values and sequences are what
/// the per-session views must reproduce.
private func growthSignatures(_ rows: [WatchSensorSampleRecord]) -> [String] {
    rows.map { "\($0.recordId)|\($0.kind)|\($0.value)|\($0.sequence)" }
}

private func growthNewestSignatures(
    _ newest: [String: WatchSensorSampleRecord]
) -> [String: String] {
    newest.mapValues { "\($0.recordId)|\($0.sequence)|\($0.value)" }
}

final class WatchStoreGrowthTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories.removeAll()
        super.tearDown()
    }

    private func makeWrist() throws -> GrowthWrist {
        let directory = try growthDirectory()
        directories.append(directory)
        return GrowthWrist(directory: directory)
    }

    /// S-15601: ten finished workouts the phone holds, one still running and one
    /// ended that the phone never acknowledged — a relaunch, the launch prune,
    /// and only the readings nobody can still be shown go.
    func testS15601TheLaunchPruneReleasesFinishedReadingsOnly() async throws {
        let wrist = try makeWrist()

        var settled: [String] = []
        for index in 1...10 {
            let engine = await wrist.launch()
            let session = await engine.createSession(
                modality: "outdoor_run",
                exercises: [exercise("sx-bench")]
            )
            await wrist.readTwo(engine)
            _ = try await engine.appendObservation(setEvent(wrist.clock, entryId: "e-\(index)"))
            _ = await engine.finishSession()
            _ = await engine.confirmObservations([
                "e-\(index)",
                WatchSessionCapture.sessionEndId(session.sessionId),
            ])
            settled.append(session.sessionId)
        }

        let endedUnacked = await wrist.launch()
        let unacked = await endedUnacked.createSession(
            modality: "outdoor_run",
            exercises: [exercise("sx-bench")]
        )
        await wrist.readTwo(endedUnacked)
        _ = try await endedUnacked.appendObservation(setEvent(wrist.clock, entryId: "e-unacked"))
        _ = await endedUnacked.finishSession()

        let running = await wrist.launch()
        let live = await running.createSession(
            modality: "outdoor_run",
            exercises: [exercise("sx-bench")]
        )
        await wrist.readTwo(running)
        _ = try await running.appendObservation(setEvent(wrist.clock, entryId: "e-live"))

        let engine = await wrist.launch()
        let released = await engine.pruneSettledSensorSamples()

        XCTAssertEqual(
            released.count,
            settled.count * 2,
            "every finished workout's readings are released at launch (S-15601)"
        )
        XCTAssertEqual(Set(released).count, released.count, "each reading is released once")

        let disk = await FileWatchSessionStore(directory: wrist.directory).readAll()
        XCTAssertEqual(
            Set(disk.sensorSamples.map(\.sessionId)),
            Set([live.sessionId, unacked.sessionId]),
            "what stays is the running workout's readings and the ended one the phone "
                + "never acknowledged: nobody has been shown either"
        )
        XCTAssertTrue(
            settled.allSatisfy { id in !disk.sensorSamples.contains { $0.sessionId == id } },
            "no finished workout keeps a reading on disk"
        )
        XCTAssertEqual(
            disk.observations.filter { $0.sessionId == settled[0] }.count,
            2,
            "a finished workout's entries and its end are not readings; the prune is "
                + "not theirs to drop"
        )
        XCTAssertEqual(
            engine.sensorSamples.count,
            2,
            "the running workout's readings are still the engine's after the launch prune"
        )
    }

    /// S-15601, the wiring half: the prune is only a launch prune if the launch
    /// asks for it. The app target has no test target and does not build on
    /// macOS, so the call is held by its source — the pattern
    /// `WatchWorkoutStoreSourceTests` uses for the same reason.
    func testS15601TheLaunchRestoreAsksForThePrunes() throws {
        let source = try String(
            contentsOf: Fixtures.repositoryRoot
                .appendingPathComponent("ios/OmniTrain Watch App/ContentView.swift"),
            encoding: .utf8
        )
        let body = try XCTUnwrap(
            growthFunctionBody("func restore() async {", in: source),
            "the app root has a restore() to hang the launch prune on"
        )
        let restored = try XCTUnwrap(
            body.range(of: "await engine.restore()"),
            "restore() restores the engine before anything reads it"
        )

        let settled = try XCTUnwrap(
            body.range(of: "await engine.pruneSettledSensorSamples()"),
            "restore() prunes the settled readings: without it the store grows forever (D-15601)"
        )
        XCTAssertTrue(
            settled.lowerBound > restored.upperBound,
            "the prune runs after the engine restored — a prune before it sees nothing"
        )
        // Plan 96 D-43: `pruneConfirmed()` would drop water taps the water count
        // still reads, so it has no production caller. The settled prune is the
        // one the launch needs.
        XCTAssertFalse(
            body.contains("pruneConfirmed("),
            "the launch does not call pruneConfirmed(): it would drop acknowledged water taps (plan 96 D-43)"
        )
    }

    /// S-15602: a receipt that clears the last owed entry releases the readings
    /// with no relaunch. The phone holding the summary is what makes them safe
    /// to drop, so the release rides on the receipt rather than waiting for the
    /// next launch.
    func testS15602TheLastReceiptReleasesTheReadingsInPlace() async throws {
        let wrist = try makeWrist()
        let engine = await wrist.launch()
        let session = await engine.createSession(
            modality: "outdoor_run",
            exercises: [exercise("sx-bench")]
        )
        await wrist.readTwo(engine)
        _ = try await engine.appendObservation(setEvent(wrist.clock, entryId: "e-1"))
        _ = await engine.finishSession()
        XCTAssertEqual(engine.sensorSamples.count, 2, "fixture: two readings to release")

        let endId = WatchSessionCapture.sessionEndId(session.sessionId)
        _ = try await engine.applyMessage(wrist.receiptFrame([endId]))
        XCTAssertEqual(
            engine.sensorSamples.count,
            2,
            "an entry still owed keeps the readings: the phone has not been shown it"
        )

        _ = try await engine.applyMessage(wrist.receiptFrame(["e-1"]))

        XCTAssertTrue(
            engine.sensorSamples.isEmpty,
            "the receipt that clears the last owed entry releases the readings (S-15602)"
        )
        let disk = await FileWatchSessionStore(directory: wrist.directory).readAll()
        XCTAssertTrue(disk.sensorSamples.isEmpty, "the release reached the file, not just memory")
    }

    /// S-15603: the valve. An ended workout the phone never acknowledged keeps
    /// its readings for a fortnight and loses them after: the summaries ride on
    /// the end, so an owed end is the phone's next contact, not an eternity.
    func testS15603AnUnacknowledgedWorkoutKeepsItsReadingsForFourteenDays() async throws {
        let wrist = try makeWrist()
        let engine = await wrist.launch()
        let session = await engine.createSession(
            modality: "outdoor_run",
            exercises: [exercise("sx-bench")]
        )
        await wrist.readTwo(engine)
        _ = try await engine.appendObservation(setEvent(wrist.clock, entryId: "e-1"))
        _ = await engine.finishSession()
        XCTAssertFalse(
            engine.unconfirmedObservations.isEmpty,
            "fixture: the phone acknowledged nothing"
        )

        wrist.clock.advance(13 * growthDay)
        let kept = await engine.pruneSettledSensorSamples()
        XCTAssertEqual(
            kept,
            [],
            "at thirteen days the readings are still the only copy of the summaries the "
                + "end was computed from"
        )
        XCTAssertEqual(engine.sensorSamples.count, 2, "the readings stay inside the valve")

        wrist.clock.advance(2 * growthDay)
        let released = await engine.pruneSettledSensorSamples()
        XCTAssertEqual(
            released.count,
            2,
            "past fourteen days the readings go even though nobody acknowledged the end "
                + "(D-15602)"
        )
        XCTAssertTrue(engine.sensorSamples.isEmpty)

        let disk = await FileWatchSessionStore(directory: wrist.directory).readAll()
        XCTAssertTrue(disk.sensorSamples.isEmpty, "the file loses them too")
        XCTAssertEqual(
            disk.observations.filter { $0.sessionId == session.sessionId }.count,
            2,
            "the entry and the end stay: only readings have a retention valve"
        )
    }

    /// S-15604: a prune that drops nothing is not a write. The file is compared
    /// by identity, so a rewrite that happens to produce the same bytes still
    /// fails — what matters is that the store did not rewrite itself.
    func testS15604APruneThatDropsNothingDoesNotRewriteTheFile() async throws {
        let wrist = try makeWrist()
        let engine = await wrist.launch()
        _ = await engine.createSession(modality: "outdoor_run", exercises: [exercise("sx-bench")])
        _ = await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 118)
        _ = try await engine.appendObservation(setEvent(wrist.clock, entryId: "e-1"))
        let before = try growthStoreFile(wrist.directory)

        let confirmed = await wrist.store.pruneConfirmed()
        let samples = await wrist.store.pruneSensorSamples(["s-nobody"])

        XCTAssertEqual(confirmed, [], "nothing is confirmed, so nothing drops")
        XCTAssertEqual(samples, [], "no session by that id has readings, so nothing drops")

        let after = try growthStoreFile(wrist.directory)
        XCTAssertEqual(
            after.inode,
            before.inode,
            "a prune that drops nothing must not rewrite the store: a rewrite per "
                + "launch costs a full copy of a file that can be tens of megabytes"
        )
        XCTAssertEqual(after.bytes, before.bytes, "and must not change a byte")

        let disk = await FileWatchSessionStore(directory: wrist.directory).readAll()
        XCTAssertEqual(disk.sensorSamples.count, 1, "the reading is still stored")
        XCTAssertEqual(disk.observations.count, 1, "the entry is still stored")
    }

    /// S-15605: appending a reading costs nothing that is already stored. The
    /// store is filled the way a stale watch fills it — one reading a second for
    /// twenty thousand seconds — and the cost of an append at the end of the run
    /// must be about the cost at the start. Measured as a ratio of the same
    /// machine's own timings, so it holds in a slow (Thread Sanitizer) build too:
    /// with a scan per append the last thousand cost about ten times the first.
    func testS15605TwentyThousandAppendsStayInsideTheBound() async throws {
        let wrist = try makeWrist()
        let engine = await wrist.launch()
        _ = await engine.createSession(modality: "outdoor_run", exercises: [exercise("sx-bench")])

        var firstThousand: TimeInterval = 0
        var lastThousand: TimeInterval = 0
        for index in 0..<20_000 {
            let kind = index.isMultiple(of: 2) ? WatchSensorKind.heartRate : WatchSensorKind.gps
            let began = Date()
            _ = await engine.appendSensorSample(kind: kind, value: Double(index))
            let took = Date().timeIntervalSince(began)
            if index < 1_000 { firstThousand += took }
            if index >= 19_000 { lastThousand += took }
            wrist.clock.advance(1)
        }

        XCTAssertLessThan(
            lastThousand,
            firstThousand * 3,
            "S-15605 the last 1,000 appends took \(lastThousand) s and the first 1,000 took "
                + "\(firstThousand) s: an append must not cost more as the store grows "
                + "(a scan per append makes the last thousand about ten times the first)"
        )
        XCTAssertEqual(
            engine.sensorSamples.count,
            20_000,
            "S-15605 every reading reached the engine's log"
        )
        let disk = await FileWatchSessionStore(directory: wrist.directory).readAll()
        XCTAssertEqual(disk.sensorSamples.count, 20_000, "and the file holds them all (S-15605)")

        // The index that makes the append cheap must not change what a duplicate
        // is: the same reading twice is still one row, at any size.
        let stored = engine.sensorSamples.count
        _ = await engine.appendSensorSample(kind: WatchSensorKind.steps, value: 42)
        _ = await engine.appendSensorSample(kind: WatchSensorKind.steps, value: 42)
        XCTAssertEqual(
            engine.sensorSamples.count,
            stored + 1,
            "the same instant's reading twice is one row (S-15605)"
        )
    }

    // MARK: - S-15606 the tick reads the current workout's rows only

    /// S-15606: with fifty thousand readings of old workouts stored, a tick's
    /// reads visit the current workout's rows and nothing else. Measured as a
    /// count of rows visited, not wall time: the same thousand ticks cost the
    /// same rows with no old readings and with fifty thousand of them.
    func testS15606AThousandTicksVisitTheCurrentSessionsRowsOnly() async throws {
        let withoutOldRows = try await growthTickedRows(oldRows: 0)
        let withOldRows = try await growthTickedRows(oldRows: 50_000)

        XCTAssertEqual(
            withOldRows,
            withoutOldRows,
            "S-15606 a tick visits the same rows whatever other workouts have stored"
        )
        XCTAssertEqual(
            withOldRows,
            1_000 * (6 + 4),
            "S-15606 1,000 ticks visit the current session's 6 rows and its 4 newest "
                + "rows, and none of the 50,000 old ones"
        )
    }

    /// The rows a thousand `newestSensorSamples()` and `sensorSamples` reads
    /// visit, over a store already holding `oldRows` readings of finished
    /// workouts (written straight to the file, not appended one at a time).
    private func growthTickedRows(oldRows: Int) async throws -> Int {
        let wrist = try makeWrist()
        if oldRows > 0 {
            let kinds = [
                WatchSensorKind.heartRate,
                WatchSensorKind.gps,
                WatchSensorKind.steps,
                WatchSensorKind.activeEnergy,
            ]
            let rows = (0..<oldRows).map { index in
                growthSample(
                    "s-old-\(index % 10)",
                    kind: kinds[index % kinds.count],
                    value: Double(index),
                    sequence: index + 1,
                    at: wrist.clock.now.addingTimeInterval(Double(index))
                )
            }
            try growthWriteStore(wrist.directory, sensorSamples: rows)
        }

        let engine = await wrist.launch()
        _ = await engine.createSession(modality: "outdoor_run", exercises: [exercise("sx-bench")])
        for (index, kind) in [
            WatchSensorKind.heartRate,
            WatchSensorKind.gps,
            WatchSensorKind.heartRate,
            WatchSensorKind.steps,
            WatchSensorKind.gps,
            WatchSensorKind.activeEnergy,
        ].enumerated() {
            _ = await engine.appendSensorSample(kind: kind, value: Double(index))
            wrist.clock.advance(1)
        }
        XCTAssertEqual(engine.sensorSamples.count, 6, "fixture: six readings of this workout")

        let before = engine.sensorRowsVisitedForTesting
        for _ in 0..<1_000 {
            _ = engine.newestSensorSamples()
            _ = engine.sensorSamples
        }
        return engine.sensorRowsVisitedForTesting - before
    }

    /// S-15606, the behaviour half: the per-session views are a filter of the
    /// same rows — arrival order kept, a repeated reading one row, the newest
    /// row per kind chosen by `sequence` with a tie keeping the row already
    /// held — and they still agree after a prune and after a fill.
    func testS15606ThePerSessionViewsMatchABruteForceFilter() {
        let first = "s-first"
        let second = "s-second"
        let at = testInstant()
        let fixture = [
            growthSample(first, kind: WatchSensorKind.heartRate, value: 118, sequence: 1, at: at),
            growthSample(
                first,
                kind: WatchSensorKind.gps,
                value: 10,
                sequence: 2,
                at: at.addingTimeInterval(1)
            ),
            growthSample(
                first,
                kind: WatchSensorKind.heartRate,
                value: 119,
                sequence: 3,
                at: at.addingTimeInterval(2)
            ),
            // The same sequence as the beat already held, arriving later: a tie
            // keeps the row already held. Written by hand because `growthSample`
            // derives the id from the sequence.
            WatchSensorSampleRecord(
                recordId: "sen-\(first)-\(WatchSensorKind.heartRate)-tie",
                sessionId: first,
                recordedAt: at.addingTimeInterval(3),
                kind: WatchSensorKind.heartRate,
                value: 117,
                sequence: 3
            ),
            growthSample(
                second,
                kind: WatchSensorKind.heartRate,
                value: 150,
                sequence: 9,
                at: at.addingTimeInterval(4)
            ),
        ]

        let log = WatchSensorSampleLog()
        for row in fixture {
            log.append(row)
        }
        log.append(fixture[0])

        XCTAssertEqual(
            growthSignatures(log.samples(forSession: first)),
            growthSignatures(growthBruteSamples(fixture, sessionId: first)),
            "S-15606 one session's rows in arrival order, the repeated reading in one row"
        )
        XCTAssertEqual(
            growthSignatures(log.samples(forSession: second)),
            growthSignatures(growthBruteSamples(fixture, sessionId: second)),
            "S-15606 a second session's rows are its own"
        )
        XCTAssertFalse(
            growthSignatures(log.samples(forSession: first)).contains { $0.contains(second) },
            "S-15606 another session's rows never appear in this one's reads"
        )
        XCTAssertEqual(
            growthNewestSignatures(log.newest(forSession: first)),
            growthNewestSignatures(growthBruteNewest(fixture, sessionId: first)),
            "S-15606 the newest row per kind is the greatest sequence, a tie keeping the row held"
        )
        XCTAssertEqual(
            log.newest(forSession: first)[WatchSensorKind.heartRate]?.value,
            119,
            "S-15606 the newest beat is the one with the greatest sequence"
        )
        XCTAssertTrue(log.contains(sessionId: first))
        XCTAssertTrue(log.contains(sessionId: second))
        XCTAssertFalse(log.contains(sessionId: "s-absent"))
        XCTAssertEqual(log.count(forSession: first, kind: WatchSensorKind.heartRate), 3)
        XCTAssertEqual(log.count(forSession: first, kind: WatchSensorKind.gps), 1)
        XCTAssertEqual(log.count(forSession: first, kind: WatchSensorKind.steps), 0)

        // After a prune every per-session view is what the survivors say.
        log.prune { $0.recordId == fixture[1].recordId }
        let survivors = fixture.filter { $0.recordId != fixture[1].recordId }
        XCTAssertEqual(
            growthSignatures(log.samples(forSession: first)),
            growthSignatures(growthBruteSamples(survivors, sessionId: first)),
            "S-15606 the pruned session reads its survivors"
        )
        XCTAssertEqual(
            growthNewestSignatures(log.newest(forSession: first)),
            growthNewestSignatures(growthBruteNewest(survivors, sessionId: first)),
            "S-15606 the pruned session's newest rows are rebuilt from the survivors"
        )
        XCTAssertEqual(log.count(forSession: first, kind: WatchSensorKind.gps), 0)

        // And after a fill — what a relaunch does — they are the stored rows'.
        log.fill(with: fixture)
        XCTAssertEqual(
            growthSignatures(log.samples(forSession: first)),
            growthSignatures(growthBruteSamples(fixture, sessionId: first))
        )
        XCTAssertEqual(
            growthNewestSignatures(log.newest(forSession: first)),
            growthNewestSignatures(growthBruteNewest(fixture, sessionId: first))
        )
        XCTAssertEqual(
            growthSignatures(log.samples(forSession: second)),
            growthSignatures(growthBruteSamples(fixture, sessionId: second))
        )
        XCTAssertEqual(log.count(forSession: first, kind: WatchSensorKind.heartRate), 3)
    }

    /// S-15606, the pace half: the window start is the answer a brute-force
    /// read gives — across a counter restart, where the newest run begins — and
    /// the filter and sort run once per new GPS row rather than once per tick.
    func testS15606ThePaceWindowIsCachedUntilANewGpsRowArrives() async throws {
        let harness = Harness()
        let clock = harness.clock
        let engine = await harness.runningEngine()
        let startedAt = clock.now
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [[
                "sessionExerciseId": "sx-run",
                "exerciseId": "ex-run",
                "name": "sx-run",
                "capabilities": ["time", "distance"],
            ]]
        )

        await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 0, recordedAt: startedAt)
        await engine.appendSensorSample(
            kind: WatchSensorKind.gps,
            value: 800,
            recordedAt: startedAt.addingTimeInterval(300)
        )
        let restart = startedAt.addingTimeInterval(1260)
        await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 0, recordedAt: restart)
        await engine.appendSensorSample(
            kind: WatchSensorKind.gps,
            value: 160.9344,
            recordedAt: restart.addingTimeInterval(120)
        )
        clock.advance(1380)

        func state() -> WatchLoggingState {
            WatchLoggingState(
                engine: engine,
                clock: clock.call,
                units: WatchUnitPreferences(weightUnit: "kg", distanceUnit: "mi"),
                sensors: WatchSensorRecorder(
                    engine: engine,
                    source: FakeSensorSource(),
                    clock: clock.call
                )
            )
        }

        let cached = state()
        XCTAssertEqual(
            cached.paceLabel,
            "20:00 /mi",
            "S-15606 the window starts at the restart: 0.1 mi in the two minutes since it"
        )
        let computed = cached.paceWindowComputationsForTesting
        XCTAssertEqual(computed, 1, "fixture: the first read computes the window once")

        for _ in 0..<1_000 { _ = cached.paceLabel }
        XCTAssertEqual(
            cached.paceWindowComputationsForTesting,
            computed,
            "S-15606 a tick that adds no GPS row reuses the window instead of filtering and "
                + "sorting the whole log again"
        )

        clock.advance(10)
        await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 240, recordedAt: clock.now)
        let afterFix = cached.paceLabel
        XCTAssertEqual(
            cached.paceWindowComputationsForTesting,
            computed + 1,
            "S-15606 a new GPS row recomputes the window, once"
        )
        XCTAssertEqual(
            afterFix,
            state().paceLabel,
            "S-15606 the cached window start is the one a brute-force read computes"
        )
    }
}
