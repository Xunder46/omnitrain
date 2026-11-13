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
}
