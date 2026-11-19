//
//  WatchWaterStoreTests.swift
//  WatchSessionEngineTests
//
//  Phase 1 of `docs/plans/2026-11-01-95-watch-water-bar-plan/`: the wrist's
//  water tap and the stored water frame. A tap is a `water_glass` observation
//  stored before it is emitted, always under the day's nutrition id (plan 95
//  D-22); a `water_down` frame is a `water` row that `pruneWater` trims to the
//  one copy the caller holds as newest, with `pruneBests`' semantics (D-23).
//
//  Fixture X: the clock reads 2026-11-01T09:00:00Z unless a test says
//  otherwise, and the id factory yields `w-1`, `w-2`, … in call order.
//

import XCTest

@testable import WatchSessionEngine

private func waterInstant(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)!
}

private func waterJSON(_ record: StoredWatchRecord) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: record.toJson(), options: [.sortedKeys]))
        ?? Data()
    return String(data: data, encoding: .utf8) ?? ""
}

/// One stored `water_down` frame, named the way the wrist names it:
/// `water-<messageId>`, with the phone's `messageId` rule (plan 94 D-6).
private func waterRow(
    generatedAt text: String,
    day: String = "2026-11-01",
    glasses: Int,
    appliedTapIds: [String]
) -> StoredWatchRecord {
    let generatedAt = waterInstant(text)
    let ms = Int((generatedAt.timeIntervalSince1970 * 1000).rounded())
    let messageId = "msg-water-\(ms)-\(glasses)-\(appliedTapIds.count)"
    return .water(
        WatchWaterRecord(
            recordId: "water-\(messageId)",
            recordedAt: generatedAt,
            generatedAt: generatedAt,
            day: day,
            glasses: glasses,
            appliedTapIds: appliedTapIds
        )
    )
}

/// One engine over one store, minting `w-1`, `w-2`, … as entry ids.
private final class WaterHarness {
    let clock: TestClock
    let store: WatchSessionStore
    private(set) var emitted: [[String: Any]] = []
    private(set) var engine: WatchSessionEngine!
    private var ids = 0
    private var idPrefix = "w-"

    init(store: WatchSessionStore = InMemoryWatchSessionStore(), now: String = "2026-11-01T09:00:00Z") {
        self.clock = TestClock(waterInstant(now))
        self.store = store
        engine = WatchSessionEngine(
            store: store,
            onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.ids += 1
                return "\(self.idPrefix)\(self.ids)"
            },
            sessionIdFactory: { "w9" }
        )
    }

    /// Runs `body` with setup ids, then restarts the tap ids at `w-1`, so a test
    /// that needs a session first still sees its first tap as `w-1`.
    func withSetupIds(_ body: () async -> Void) async {
        idPrefix = "setup-"
        await body()
        idPrefix = "w-"
        ids = 0
    }

    func emitted(_ type: String) -> [[String: Any]] {
        emitted.filter { $0["type"] as? String == type }
    }
}

private func events(_ envelope: [String: Any]) -> [[String: Any]] {
    ((envelope["payload"] as? [String: Any])?["events"] as? [[String: Any]]) ?? []
}

final class WatchWaterStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-water-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private var fileURL: URL {
        directory.appendingPathComponent("watch-session.jsonl")
    }

    // MARK: - S-94b-1 a press is stored, then sent, shaped like the fixture

    func testS94b1APressIsStoredThenSentShapedLikeTheFixture() async throws {
        let watch = WaterHarness()
        await watch.engine.restore()
        let tapAt = waterInstant("2026-11-01T09:00:00Z")

        let first = try await watch.engine.logWaterGlass(.add)
        let second = try await watch.engine.logWaterGlass(.remove)

        XCTAssertEqual(first.recordId, "w-1", "S-94b-1 the first tap is w-1")
        XCTAssertEqual(second.recordId, "w-2", "S-94b-1 the second tap is w-2")
        XCTAssertEqual(first.kind, WatchObservationKind.waterGlass)
        XCTAssertEqual(first.payload["glassChange"] as? String, "add")
        XCTAssertEqual(second.payload["glassChange"] as? String, "remove")
        for record in [first, second] {
            XCTAssertEqual(record.payload["entryId"] as? String, record.recordId)
            XCTAssertEqual(record.payload["eventId"] as? String, record.recordId)
            XCTAssertEqual(record.payload["kind"] as? String, "water_glass")
            XCTAssertEqual(
                record.payload["loggedAt"] as? String,
                utcIso(tapAt),
                "S-94b-1 loggedAt is the clock's instant in the wire shape"
            )
            XCTAssertEqual(try parseUtcIso(record.payload["loggedAt"]), tapAt)
        }

        let fixture = try Fixtures.json("fixtures/valid/observations_up_water.json")
        let fixtureEvent = try XCTUnwrap(events(fixture).first)
        XCTAssertEqual(
            Set(first.payload.keys),
            Set(fixtureEvent.keys),
            "S-94b-1 the wrist adds no field the fixture does not carry"
        )
        XCTAssertEqual(Set(second.payload.keys), Set(fixtureEvent.keys))

        let sent = watch.emitted("observations_up")
        XCTAssertEqual(sent.count, 2, "S-94b-1 one emission per press")
        XCTAssertEqual(sent.map { $0["sessionId"] as? String }, ["nutrition-2026-11-01", "nutrition-2026-11-01"])
        XCTAssertEqual(sent.map { $0["messageId"] as? String }, ["msg-w-1", "msg-w-2"])
        for envelope in sent {
            XCTAssertTrue(
                Harness.validator().validateEnvelope(envelope).isEmpty,
                "S-94b-1 every emitted tap conforms to the protocol"
            )
        }

        let stored = await watch.store.readAll()
        XCTAssertEqual(
            stored.observations.map(\.recordId),
            ["w-1", "w-2"],
            "S-94b-1 both presses reached storage"
        )
        XCTAssertEqual(watch.engine.waterLog.map(\.recordId), ["w-1", "w-2"])
        XCTAssertTrue(watch.engine.nutritionLog.isEmpty, "S-94b-1 a tap is not a food log")
        XCTAssertEqual(watch.engine.pendingObservations().count, 2)
    }

    func testS94b1TheWaterLogSurvivesARelaunch() async throws {
        let store = InMemoryWatchSessionStore()
        let watch = WaterHarness(store: store)
        await watch.engine.restore()
        _ = try await watch.engine.logWaterGlass(.add)

        let relaunched = WaterHarness(store: store)
        await relaunched.engine.restore()
        XCTAssertEqual(
            relaunched.engine.waterLog.map(\.recordId),
            ["w-1"],
            "S-94b-1 the stored tap is read back after a relaunch"
        )
        XCTAssertEqual(
            relaunched.engine.pendingObservations().map { $0["messageId"] as? String },
            ["msg-w-1"],
            "S-94b-1 the unreceipted tap is still owed, under the same message id"
        )
    }

    func testS94b1TheGlassChangeRawValuesAreTheWireValues() {
        XCTAssertEqual(WatchGlassChange.add.rawValue, "add")
        XCTAssertEqual(WatchGlassChange.remove.rawValue, "remove")
        XCTAssertEqual(WatchObservationKind.waterGlass, "water_glass")
        XCTAssertTrue(WatchObservationKind.all.contains(WatchObservationKind.waterGlass))
        XCTAssertFalse(
            WatchObservationKind.efforts.contains(WatchObservationKind.waterGlass),
            "S-94b-1 a glass of water records no work in a slot"
        )
    }

    // MARK: - S-94b-2 a press while a session is held never joins it

    func testS94b2APressWhileASessionIsHeldNeverJoinsIt() async throws {
        let watch = WaterHarness()
        await watch.engine.restore()
        await watch.withSetupIds {
            _ = await watch.engine.createSession(
                modality: "resistance_lifting",
                exercises: [exercise("sx-bench")]
            )
        }
        XCTAssertEqual(watch.engine.session?.sessionId, "w9")
        XCTAssertEqual(watch.engine.session?.status, WatchSessionStatus.active)

        let tap = try await watch.engine.logWaterGlass(.add)
        XCTAssertEqual(tap.recordId, "w-1")

        let sent = try XCTUnwrap(watch.emitted("observations_up").last)
        XCTAssertEqual(
            sent["sessionId"] as? String,
            "nutrition-2026-11-01",
            "S-94b-2 a tap carries the day's nutrition id even while a workout runs"
        )
        XCTAssertEqual(tap.sessionId, "nutrition-2026-11-01")
        XCTAssertFalse(
            watch.engine.observations.contains { $0.recordId == "w-1" },
            "S-94b-2 the workout's observations never hold a tap"
        )
        XCTAssertFalse(
            watch.engine.entries.contains { $0.recordId == "w-1" },
            "S-94b-2 the workout's entries never hold a tap"
        )
        let snapshot = try XCTUnwrap(watch.engine.sessionSnapshot())
        let snapshotEntries = ((snapshot["payload"] as? [String: Any])?["entries"] as? [[String: Any]]) ?? []
        XCTAssertFalse(
            snapshotEntries.contains { $0["entryId"] as? String == "w-1" },
            "S-94b-2 the session snapshot never carries a tap"
        )
        XCTAssertEqual(watch.engine.waterLog.map(\.recordId), ["w-1"])
    }

    // MARK: - S-94b-3 (envelope half) the tap's id is the UTC date

    func testS94b3TheEnvelopeCarriesTheUtcDateNotTheLocalOne() async throws {
        // 21:30Z on 10-31 is 00:30 on 11-01 at UTC+3: the wire id is still 10-31.
        let watch = WaterHarness(now: "2026-10-31T21:30:00Z")
        await watch.engine.restore()

        let tap = try await watch.engine.logWaterGlass(.add)

        let sent = try XCTUnwrap(watch.emitted("observations_up").last)
        XCTAssertEqual(
            sent["sessionId"] as? String,
            "nutrition-2026-10-31",
            "S-94b-3 the envelope's id follows plan 94 D-2 (the UTC date of loggedAt)"
        )
        XCTAssertEqual(tap.sessionId, "nutrition-2026-10-31")
        XCTAssertEqual(try parseUtcIso(tap.payload["loggedAt"]), waterInstant("2026-10-31T21:30:00Z"))
    }

    func testS94b3AnExplicitLoggedAtDecidesTheIdAndTheField() async throws {
        let watch = WaterHarness()
        await watch.engine.restore()
        let at = waterInstant("2026-10-31T19:00:00Z")

        let tap = try await watch.engine.logWaterGlass(.add, loggedAt: at)

        XCTAssertEqual(tap.sessionId, "nutrition-2026-10-31")
        XCTAssertEqual(tap.payload["loggedAt"] as? String, utcIso(at))
    }

    // MARK: - S-94b-4 (store half) one frame row, kept across relaunch

    func testS94b4OneFrameRowAfterEachPruneOnBothStores() async throws {
        let frames = [
            waterRow(generatedAt: "2026-11-01T08:00:00Z", glasses: 2, appliedTapIds: ["w-1"]),
            waterRow(generatedAt: "2026-11-01T08:05:00Z", glasses: 3, appliedTapIds: ["w-1", "w-2"]),
            waterRow(generatedAt: "2026-11-01T08:10:00Z", glasses: 3, appliedTapIds: ["w-1", "w-2", "w-3"]),
        ]
        let stores: [(String, WatchSessionStore)] = [
            ("in-memory", InMemoryWatchSessionStore()),
            ("file", FileWatchSessionStore(directory: directory)),
        ]

        for (name, store) in stores {
            for frame in frames {
                let stored = await store.append(frame)
                _ = await store.pruneWater(keepingRecordId: stored.recordId)
                let water = await store.readAll().water
                XCTAssertEqual(
                    water.map(\.recordId),
                    [frame.recordId],
                    "S-94b-4 (\(name)) after each apply the store holds the frame just written, alone"
                )
            }
        }

        let relaunched = await FileWatchSessionStore(directory: directory).readAll()
        let held = try XCTUnwrap(relaunched.water.first)
        XCTAssertEqual(relaunched.water.count, 1, "S-94b-4 the relaunched store holds one frame")
        XCTAssertEqual(held.recordId, frames[2].recordId)
        XCTAssertEqual(held.glasses, 3, "S-94b-4 the newest frame's count comes back")
        XCTAssertEqual(held.day, "2026-11-01")
        XCTAssertEqual(held.appliedTapIds, ["w-1", "w-2", "w-3"], "S-94b-4 the tap ids keep their order")
        XCTAssertEqual(held.generatedAt, waterInstant("2026-11-01T08:10:00Z"))
        XCTAssertEqual(held.sessionId, "", "S-94b-4 a frame belongs to no session")

        let memoryContents = await stores[0].1.readAll()
        XCTAssertEqual(
            relaunched.water.map { waterJSON(.water($0)) },
            memoryContents.water.map { waterJSON(.water($0)) },
            "S-94b-4 both stores answer the same row"
        )
    }

    func testS94b4APruneNamingAnAbsentRowDropsNothingAndWritesNothing() async throws {
        let fileStore = FileWatchSessionStore(directory: directory)
        _ = await fileStore.append(
            waterRow(generatedAt: "2026-11-01T08:10:00Z", glasses: 3, appliedTapIds: ["w-1"])
        )
        let bytesBefore = try Data(contentsOf: fileURL)

        let pruned = await fileStore.pruneWater(keepingRecordId: "water-missing")
        XCTAssertEqual(pruned, [], "S-94b-4 an unknown id drops nothing")
        XCTAssertEqual(
            try Data(contentsOf: fileURL),
            bytesBefore,
            "S-94b-4 the file is byte-identical: a prune that drops nothing is not a write"
        )
        let afterFile = await fileStore.readAll()
        XCTAssertEqual(afterFile.water.count, 1)

        let memoryStore = InMemoryWatchSessionStore()
        _ = await memoryStore.append(
            waterRow(generatedAt: "2026-11-01T08:10:00Z", glasses: 3, appliedTapIds: ["w-1"])
        )
        let memoryPruned = await memoryStore.pruneWater(keepingRecordId: "water-missing")
        XCTAssertEqual(memoryPruned, [], "S-94b-4 the in-memory store drops nothing either")
        let afterMemory = await memoryStore.readAll()
        XCTAssertEqual(afterMemory.water.count, 1)

        // The only frame is the named one: nothing to drop, nothing written.
        let onlyFrame = try XCTUnwrap(afterFile.water.first)
        let keptOnly = await fileStore.pruneWater(keepingRecordId: onlyFrame.recordId)
        XCTAssertEqual(keptOnly, [])
        XCTAssertEqual(try Data(contentsOf: fileURL), bytesBefore)

        // A store that has never been written stays that way: no file appears.
        let untouched = directory.appendingPathComponent("untouched", isDirectory: true)
        let freshPruned = await FileWatchSessionStore(directory: untouched)
            .pruneWater(keepingRecordId: "water-missing")
        XCTAssertEqual(freshPruned, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: untouched.path))
    }

    func testS94b4ThePruneTouchesNoOtherKindOfRow() async throws {
        let fileStore = FileWatchSessionStore(directory: directory)
        let memoryStore = InMemoryWatchSessionStore()
        let older = waterRow(generatedAt: "2026-11-01T08:00:00Z", glasses: 2, appliedTapIds: [])
        let newer = waterRow(generatedAt: "2026-11-01T08:05:00Z", glasses: 3, appliedTapIds: ["w-1"])
        let bests = StoredWatchRecord.bests(
            WatchBestsRecord(
                recordId: "bests-1",
                recordedAt: waterInstant("2026-11-01T08:00:00Z"),
                generatedAt: waterInstant("2026-11-01T08:00:00Z")
            )
        )
        for store in [fileStore as WatchSessionStore, memoryStore] {
            for row in [older, bests, newer] { _ = await store.append(row) }
            let dropped = await store.pruneWater(keepingRecordId: newer.recordId)
            XCTAssertEqual(dropped, [older.recordId], "S-94b-4 every other frame is dropped")
            let contents = await store.readAll()
            XCTAssertEqual(contents.water.map(\.recordId), [newer.recordId])
            XCTAssertEqual(contents.bests.map(\.recordId), ["bests-1"], "S-94b-4 a bests row stays")
        }

        let relaunched = await FileWatchSessionStore(directory: directory).readAll()
        XCTAssertEqual(relaunched.water.map(\.recordId), [newer.recordId], "S-94b-4 the prune reached the disk")
        XCTAssertEqual(relaunched.bests.map(\.recordId), ["bests-1"])
    }

    func testS94b4AWaterRowAloneMakesTheStoreNotEmptyAndRoundTrips() async throws {
        let row = waterRow(generatedAt: "2026-11-01T08:00:00Z", glasses: 2, appliedTapIds: ["w-1", "w-0"])
        let memoryStore = InMemoryWatchSessionStore()
        _ = await memoryStore.append(row)
        let contents = await memoryStore.readAll()
        XCTAssertFalse(contents.isEmpty, "S-94b-4 a store holding a frame is not an empty store")

        let json = row.toJson()
        XCTAssertEqual(json["recordType"] as? String, "water")
        XCTAssertEqual(StoredWatchRecord.waterType, "water")
        let back = try StoredWatchRecord.fromJson(json)
        XCTAssertEqual(waterJSON(back), waterJSON(row), "S-94b-4 a frame row reads back as written")
        XCTAssertEqual(back.recordType, "water")
        XCTAssertTrue(row.recordId.hasPrefix("water-msg-water-"))
    }
}
