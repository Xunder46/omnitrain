//
//  WatchPersonalBestsStoreTests.swift
//  WatchSessionEngineTests
//
//  Phase 1 of `docs/plans/2026-10-27-87b-wrist-new-pr-detection-and-banner-plan/`:
//  the store side of the phone's standing bests. The store is append-only, so
//  what these tests pin is that a `bests` row survives a relaunch and that
//  `pruneBests(keepingRecordId:)` leaves exactly the one row the caller names —
//  the copy the wrist holds as newest (D-11, D-17).
//

import XCTest

@testable import WatchSessionEngine

private func bestsInstant(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

private func bestsJSON(_ record: StoredWatchRecord) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: record.toJson(), options: [.sortedKeys]))
        ?? Data()
    return String(data: data, encoding: .utf8) ?? ""
}

/// Every family of `contents`, each row serialised with sorted keys — records
/// are not `Equatable`, so this is how two stores are compared.
private func bestsFamilyJSON(_ contents: WatchStoreContents) -> [[String]] {
    [
        contents.sessions.map { bestsJSON(.session($0)) },
        contents.observations.map { bestsJSON(.observation($0)) },
        contents.timers.map { bestsJSON(.timer($0)) },
        contents.confirmations.map { bestsJSON(.confirmation($0)) },
        contents.sensorSamples.map { bestsJSON(.sensorSample($0)) },
        contents.routineCatalogs.map { bestsJSON(.routineCatalog($0)) },
        contents.foodCatalogs.map { bestsJSON(.foodCatalog($0)) },
        contents.preferences.map { bestsJSON(.preferences($0)) },
        contents.ratingPrompts.map { bestsJSON(.ratingPrompt($0)) },
        contents.exerciseBatches.map { bestsJSON(.exerciseBatch($0)) },
        contents.bests.map { bestsJSON(.bests($0)) },
    ]
}

/// One stored `bests_down` frame, as the wrist keeps it: the frame's `bests`
/// array stored as it arrived.
private func bestsRow(
    _ recordId: String,
    generatedAt seconds: TimeInterval,
    entries: [[String: Any]] = [["exerciseId": "ex-bench", "e1rmKg": 116.6667]]
) -> StoredWatchRecord {
    .bests(
        WatchBestsRecord(
            recordId: recordId,
            recordedAt: bestsInstant(seconds),
            generatedAt: bestsInstant(seconds),
            entries: entries
        )
    )
}

private func bestsSessionRow(_ id: String, at seconds: TimeInterval) -> StoredWatchRecord {
    .session(
        WatchSessionRecord(
            recordId: id,
            sessionId: "s-bests",
            recordedAt: bestsInstant(seconds),
            startedAt: bestsInstant(seconds),
            modality: nil,
            source: "watch",
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0
        )
    )
}

final class WatchPersonalBestsStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-bests-store-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - S-87b-11 the held copy survives a relaunch

    func testS87b11AStoredBestsRowReadsBackAfterRelaunch() async throws {
        let row = bestsRow(
            "bst-1000",
            generatedAt: 1000,
            entries: [
                ["exerciseId": "ex-bench", "e1rmKg": 116.6667],
                ["exerciseId": "ex-pushup", "repsBest": 12],
            ]
        )

        let first = FileWatchSessionStore(directory: directory)
        _ = await first.append(row)

        // A relaunch: a brand-new store over the same directory, nothing shared.
        let relaunched = await FileWatchSessionStore(directory: directory).readAll()
        XCTAssertEqual(
            relaunched.bests.map(\.recordId),
            ["bst-1000"],
            "S-87b-11 the stored frame is the one the relaunched wrist reads"
        )
        let held = try XCTUnwrap(relaunched.bests.first)
        XCTAssertEqual(
            held.generatedAt,
            bestsInstant(1000),
            "S-87b-11 the frame's generatedAt comes back with the row"
        )
        XCTAssertEqual(
            held.entries.map { $0["exerciseId"] as? String },
            ["ex-bench", "ex-pushup"],
            "S-87b-11 the entries come back in the phone's order"
        )
        XCTAssertEqual(
            held.entries.first?["e1rmKg"] as? Double,
            116.6667,
            "S-87b-11 the estimate comes back at the precision the phone computed it"
        )

        let memoryStore = InMemoryWatchSessionStore()
        _ = await memoryStore.append(row)
        let memoryContents = await memoryStore.readAll()
        XCTAssertEqual(
            bestsFamilyJSON(relaunched),
            bestsFamilyJSON(memoryContents),
            "S-87b-11 both stores answer the same, family by family"
        )
    }

    func testS87b11TheSameFrameStoredTwiceIsOneRow() async throws {
        let at = 1000.0
        let fileStore = FileWatchSessionStore(directory: directory)
        let memoryStore = InMemoryWatchSessionStore()

        _ = await fileStore.append(bestsRow("bst-1000", generatedAt: at))
        _ = await fileStore.append(bestsRow("bst-1000", generatedAt: at))
        _ = await memoryStore.append(bestsRow("bst-1000", generatedAt: at))
        _ = await memoryStore.append(bestsRow("bst-1000", generatedAt: at))

        let fileContents = await fileStore.readAll()
        let memoryContents = await memoryStore.readAll()
        XCTAssertEqual(
            fileContents.bests.map(\.recordId),
            ["bst-1000"],
            "S-87b-11 the same row twice is still one row"
        )
        XCTAssertEqual(
            memoryContents.bests.map(\.recordId),
            ["bst-1000"],
            "S-87b-11 the in-memory store appends it once too"
        )
        XCTAssertEqual(
            try fileLines().count,
            2,
            "S-87b-11 the file holds the marker and one row, not two"
        )
    }

    func testS87b11ThreeFramesLeaveTheNewestOneAfterThePrune() async throws {
        let fileStore = FileWatchSessionStore(directory: directory)
        let memoryStore = InMemoryWatchSessionStore()
        let script: [StoredWatchRecord] = [
            bestsSessionRow("sess-1", at: 1000),
            bestsRow("bst-1000", generatedAt: 1000, entries: [["exerciseId": "ex-bench", "e1rmKg": 110.0]]),
            bestsRow("bst-2000", generatedAt: 2000, entries: [["exerciseId": "ex-bench", "e1rmKg": 113.0]]),
            bestsRow("bst-3000", generatedAt: 3000, entries: [["exerciseId": "ex-bench", "e1rmKg": 120.0]]),
        ]
        for record in script {
            _ = await fileStore.append(record)
            _ = await memoryStore.append(record)
        }

        let fileDropped = await fileStore.pruneBests(keepingRecordId: "bst-3000")
        let memoryDropped = await memoryStore.pruneBests(keepingRecordId: "bst-3000")
        XCTAssertEqual(
            fileDropped.sorted(),
            ["bst-1000", "bst-2000"],
            "S-87b-11 every frame but the named one is dropped"
        )
        XCTAssertEqual(fileDropped, memoryDropped, "S-87b-11 both stores drop the same rows")

        let fileContents = await fileStore.readAll()
        let memoryContents = await memoryStore.readAll()
        XCTAssertEqual(
            fileContents.bests.map(\.recordId),
            ["bst-3000"],
            "S-87b-11 the newest frame is the only one left"
        )
        XCTAssertEqual(
            fileContents.sessions.map(\.recordId),
            ["sess-1"],
            "S-87b-11 a session row is not a bests row and stays"
        )
        XCTAssertEqual(
            bestsFamilyJSON(fileContents),
            bestsFamilyJSON(memoryContents),
            "S-87b-11 the two stores answer family by family after the prune"
        )

        let relaunched = await FileWatchSessionStore(directory: directory).readAll()
        XCTAssertEqual(
            bestsFamilyJSON(relaunched),
            bestsFamilyJSON(fileContents),
            "S-87b-11 the prune reached the disk, not just the cache"
        )
        XCTAssertEqual(
            relaunched.bests.first?.entries.first?["e1rmKg"] as? Double,
            120.0,
            "S-87b-11 the surviving row is the newest frame's entries"
        )
    }

    // MARK: - S-87b-19 the prune keeps the row it is told to keep

    func testS87b19APruneKeepsExactlyTheNamedRow() async throws {
        let fileStore = FileWatchSessionStore(directory: directory)
        let memoryStore = InMemoryWatchSessionStore()
        for record in [
            bestsRow("bst-1000", generatedAt: 1000),
            bestsRow("bst-2000", generatedAt: 2000),
        ] {
            _ = await fileStore.append(record)
            _ = await memoryStore.append(record)
        }

        let dropped = await fileStore.pruneBests(keepingRecordId: "bst-2000")
        let memoryDropped = await memoryStore.pruneBests(keepingRecordId: "bst-2000")
        XCTAssertEqual(dropped, ["bst-1000"], "S-87b-19 the older row is the one dropped")
        XCTAssertEqual(memoryDropped, dropped, "S-87b-19 the in-memory store agrees")

        let fileContents = await fileStore.readAll()
        let memoryContents = await memoryStore.readAll()
        XCTAssertEqual(
            fileContents.bests.map(\.generatedAt),
            [bestsInstant(2000)],
            "S-87b-19 exactly the row named as newest is left"
        )
        XCTAssertEqual(
            memoryContents.bests.map(\.generatedAt),
            [bestsInstant(2000)],
            "S-87b-19 the in-memory store keeps exactly it too"
        )
    }

    func testS87b19APruneNamingAnAbsentRowDropsNothing() async throws {
        let fileStore = FileWatchSessionStore(directory: directory)
        _ = await fileStore.append(bestsSessionRow("sess-1", at: 1000))
        _ = await fileStore.append(bestsRow("bst-1000", generatedAt: 1000))
        let bytesBefore = try Data(contentsOf: fileURL)

        let pruned = await fileStore.pruneBests(keepingRecordId: "bst-not-stored")
        XCTAssertEqual(pruned, [], "S-87b-19 an id that is not stored drops nothing")
        XCTAssertEqual(
            try Data(contentsOf: fileURL),
            bytesBefore,
            "S-87b-19 the file is byte-identical: a prune that finds nothing is not a write"
        )

        let memoryStore = InMemoryWatchSessionStore()
        _ = await memoryStore.append(bestsRow("bst-1000", generatedAt: 1000))
        let memoryPruned = await memoryStore.pruneBests(keepingRecordId: "bst-not-stored")
        XCTAssertEqual(memoryPruned, [], "S-87b-19 the in-memory store drops nothing either")
        let memoryContents = await memoryStore.readAll()
        XCTAssertEqual(
            memoryContents.bests.map(\.recordId),
            ["bst-1000"],
            "S-87b-19 the held row is still there"
        )

        // A store that has never been written stays that way: no file appears.
        let untouched = directory.appendingPathComponent("untouched", isDirectory: true)
        let fresh = FileWatchSessionStore(directory: untouched)
        let freshPruned = await fresh.pruneBests(keepingRecordId: "bst-1000")
        XCTAssertEqual(freshPruned, [], "S-87b-19 a never-written store drops nothing")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: untouched.path),
            "S-87b-19 a prune creates nothing"
        )
    }

    // MARK: - S-87b-11 a held frame is a stored row

    func testS87b11ABestsRowAloneMakesTheStoreNotEmpty() async {
        let memoryStore = InMemoryWatchSessionStore()
        _ = await memoryStore.append(bestsRow("bst-1000", generatedAt: 1000))

        let contents = await memoryStore.readAll()
        XCTAssertFalse(
            contents.isEmpty,
            "S-87b-11 a store holding a frame is not an empty store"
        )
    }
}
