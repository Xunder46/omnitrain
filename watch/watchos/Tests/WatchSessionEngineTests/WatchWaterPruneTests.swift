//
//  WatchWaterPruneTests.swift
//  WatchSessionEngineTests
//
//  Phase 2 of `docs/plans/2026-11-01-96-watch-water-follow-up-plan/`: a launch
//  drops the water taps the phone confirmed and that were logged before
//  `WatchWaterLimits.confirmedTapRetention` ago, and nothing else (D-43, D-44).
//  Scenarios S-94c-10 to S-94c-12.
//
//  Fixture X (as plan 95): the calendar is Gregorian at UTC+3, so the local
//  day turns at 21:00Z; the clock reads 2026-11-01T09:00:00Z unless a test
//  says otherwise; the engine mints `w-1`, `w-2`, … in call order.
//

import XCTest

@testable import WatchSessionEngine

private func at(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)!
}

private func calendar(_ secondsFromGMT: Int) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)!
    return calendar
}

private let utcPlusThree = 10800

/// `fixtures/valid/water_down.json` with the scenario's payload, under the
/// phone's message-id rule (plan 94 D-6).
private func waterFrame(_ generatedAt: String, day: String, glasses: Int, ids: [String]) throws -> [String: Any] {
    var envelope = try Fixtures.json("fixtures/valid/water_down.json")
    let ms = Int((at(generatedAt).timeIntervalSince1970 * 1000).rounded())
    envelope["messageId"] = "msg-water-\(ms)-\(glasses)-\(ids.count)"
    envelope["sentAt"] = generatedAt
    envelope["payload"] = [
        "generatedAt": generatedAt,
        "day": day,
        "glasses": glasses,
        "appliedTapIds": ids,
    ] as [String: Any]
    return envelope
}

/// `fixtures/valid/receipt.json` naming `ids`.
private func receipt(_ ids: [String]) throws -> [String: Any] {
    var envelope = try Fixtures.json("fixtures/valid/receipt.json")
    envelope["payload"] = ["entryIds": ids]
    return envelope
}

/// One launch of the wrist: an engine and a water state over `store`, minting
/// `w-1`, `w-2`, … as entry ids, counting every `onWaterChanged`.
private final class Wrist {
    let clock: TestClock
    let store: WatchSessionStore
    private(set) var engine: WatchSessionEngine!
    private(set) var water: WatchWaterState!
    private(set) var changes = 0
    private var ids = 0

    init(store: WatchSessionStore, now: String = "2026-11-01T09:00:00Z", zone: Int = utcPlusThree) {
        self.clock = TestClock(at(now))
        self.store = store
        engine = WatchSessionEngine(
            store: store,
            onEmit: { _ in },
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.ids += 1
                return "w-\(self.ids)"
            },
            sessionIdFactory: { "w9" }
        )
        water = WatchWaterState(
            engine: engine,
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            calendar: calendar(zone)
        )
        water.onWaterChanged = { [weak self] in self?.changes += 1 }
    }

    /// The launch: the engine, then the water state, read the store back.
    func launch() async {
        await engine.restore()
        await water.restore()
    }

    var waterLogIds: [String] { engine.waterLog.map(\.recordId) }

    /// The water taps the phone has not acknowledged, in store order.
    var unconfirmedTapIds: [String] {
        engine.unconfirmedObservations
            .filter { $0.kind == WatchObservationKind.waterGlass }
            .map(\.recordId)
    }

    /// The message ids under which the unconfirmed water taps are re-sent.
    var pendingTapMessageIds: [String] {
        engine.pendingObservations().compactMap { envelope -> String? in
            let payload = envelope["payload"] as? [String: Any]
            let events = payload?["events"] as? [[String: Any]]
            guard events?.first?["kind"] as? String == WatchObservationKind.waterGlass else { return nil }
            return envelope["messageId"] as? String
        }
    }
}

/// The water taps a store holds, read back without any engine, in store order.
private func storedTapIds(_ store: WatchSessionStore) async -> [String] {
    await store.readAll().observations
        .filter { $0.kind == WatchObservationKind.waterGlass }
        .map(\.recordId)
}

final class WatchWaterPruneTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-water-prune-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private var fileURL: URL { directory.appendingPathComponent("watch-session.jsonl") }

    // MARK: - S-94c-10 launch drops only old confirmed taps (both stores)

    /// Builds S-94c-10's population through one engine and state over `store`:
    /// eight taps w-1..w-8, the food w-9, a set s-1 in workout session w9, the
    /// receipt and the held frame. Returns the wrist that built it.
    private func populate(_ store: WatchSessionStore, _ label: String) async throws -> Wrist {
        let x = Wrist(store: store)
        await x.launch()
        let taps: [(WatchGlassChange, String)] = [
            (.add, "2026-10-20T08:00:00Z"),  // w-1 confirmed, dropped
            (.add, "2026-10-29T08:59:59Z"),  // w-2 confirmed, 1 s before the cutoff: dropped
            (.add, "2026-10-29T09:00:00Z"),  // w-3 confirmed, exactly the cutoff: kept
            (.add, "2026-10-31T19:00:00Z"),  // w-4 confirmed, yesterday 22:00 local: kept
            (.add, "2026-10-29T06:30:00Z"),  // w-5 unconfirmed, older than the cutoff: kept
            (.remove, "2026-10-25T10:00:00Z"),  // w-6 unconfirmed: kept
            (.add, "2026-11-01T06:00:00Z"),  // w-7 confirmed, today: kept
            (.add, "2026-11-01T07:00:00Z"),  // w-8 unconfirmed, today: kept
        ]
        for (change, instant) in taps {
            try await x.engine.logWaterGlass(change, loggedAt: at(instant))
        }
        let food = try await x.engine.logNutrition(foodId: "f-1", servings: 1, loggedAt: at("2026-10-20T08:00:00Z"))
        XCTAssertEqual(food.recordId, "w-9", "\(label) the food is w-9")

        // The set is logged long before the cutoff too, so a prune that ignored
        // the kind would drop it as well as the food.
        _ = await x.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        var setLog = setEvent(x.clock, entryId: "s-1")
        setLog["loggedAt"] = "2026-10-20T08:00:00Z"
        let setRow = try await x.engine.appendObservation(setLog)
        XCTAssertEqual(setRow.sessionId, "w9", "\(label) s-1 is a set of workout session w9")

        try await x.engine.applyMessage(try receipt(["w-1", "w-2", "w-3", "w-4", "w-7", "w-9", "s-1"]))
        let held = await x.water.applyWaterDown(try waterFrame("2026-11-01T08:30:00Z", day: "2026-11-01", glasses: 4, ids: ["w-7"]))
        XCTAssertTrue(held.applied, "\(label) the frame is held")
        XCTAssertEqual(x.waterLogIds, ["w-1", "w-2", "w-3", "w-4", "w-5", "w-6", "w-7", "w-8"])
        return x
    }

    /// The population, then a launch over `relaunched` (the same store, or a
    /// fresh file store over the same directory), checked against S-94c-10.
    private func assertTheLaunchDropsOnlyOldConfirmedTaps(
        _ store: WatchSessionStore,
        relaunched: () -> WatchSessionStore,
        _ label: String
    ) async throws {
        let before = try await populate(store, label)
        XCTAssertEqual(before.water.glasses, 5, "\(label) shown 5 before: base 4, w-7 listed, w-8 +1")
        XCTAssertEqual(before.unconfirmedTapIds, ["w-5", "w-6", "w-8"], "\(label) unconfirmed taps before")
        let contentsBefore = await store.readAll()
        let confirmationRows = contentsBefore.confirmations.count
        XCTAssertEqual(confirmationRows, 1, "\(label) one receipt, one confirmation row")

        let launch = Wrist(store: relaunched())
        await launch.launch()

        XCTAssertEqual(
            launch.waterLogIds,
            ["w-3", "w-4", "w-5", "w-6", "w-7", "w-8"],
            "S-94c-10 \(label): exactly w-1 and w-2 leave engine.waterLog, the rest in store order"
        )
        let stored = await storedTapIds(launch.store)
        XCTAssertEqual(stored, ["w-3", "w-4", "w-5", "w-6", "w-7", "w-8"], "S-94c-10 \(label): and the store")
        XCTAssertTrue(
            launch.engine.nutritionLog.contains { $0.recordId == "w-9" },
            "S-94c-10 \(label): the confirmed old food w-9 is another kind and stays"
        )
        let contents = await launch.store.readAll()
        XCTAssertTrue(
            contents.observations.contains { $0.recordId == "s-1" },
            "S-94c-10 \(label): the confirmed old set s-1 is another kind and stays"
        )
        XCTAssertEqual(contents.confirmations.count, confirmationRows, "S-94c-10 \(label): confirmation rows kept")
        XCTAssertEqual(contents.water.count, 1, "S-94c-10 \(label): one water frame row remains")
        XCTAssertEqual(launch.unconfirmedTapIds, ["w-5", "w-6", "w-8"], "S-94c-10 \(label): unconfirmed taps after")
        XCTAssertEqual(launch.water.glasses, 5, "S-94c-10 \(label): shown 5 after the launch")
        XCTAssertEqual(launch.changes, 1, "S-94c-10 \(label): the launch fires one onWaterChanged")
    }

    func testS94c10TheLaunchDropsOnlyOldConfirmedTapsInMemory() async throws {
        let store = InMemoryWatchSessionStore()
        try await assertTheLaunchDropsOnlyOldConfirmedTaps(store, relaunched: { store }, "in memory")
    }

    func testS94c10TheLaunchDropsOnlyOldConfirmedTapsOnFile() async throws {
        let folder: URL = directory
        try await assertTheLaunchDropsOnlyOldConfirmedTaps(
            FileWatchSessionStore(directory: folder),
            relaunched: { FileWatchSessionStore(directory: folder) },
            "on file"
        )
        let reread = await storedTapIds(FileWatchSessionStore(directory: folder))
        XCTAssertEqual(reread, ["w-3", "w-4", "w-5", "w-6", "w-7", "w-8"], "S-94c-10 on file: the file itself")
    }

    func testS94c10TheRetentionOutlastsTheLongestLocalDayByADay() {
        XCTAssertGreaterThanOrEqual(
            WatchWaterLimits.confirmedTapRetention,
            49 * 3600,
            "S-94c-10 D-43: 25 h (the longest local day) + a 24 h margin"
        )
    }

    // MARK: - S-94c-11 relaunch after pruning

    func testS94c11RelaunchAfterPruning() async throws {
        let folder: URL = directory
        let first = try await populate(FileWatchSessionStore(directory: folder), "S-94c-11")
        let pendingBeforeFirstLaunch = first.pendingTapMessageIds
        XCTAssertEqual(pendingBeforeFirstLaunch, ["msg-w-5", "msg-w-6", "msg-w-8"])
        await Wrist(store: FileWatchSessionStore(directory: folder)).launch()

        // (a) A second launch drops nothing and writes nothing.
        let bytesBefore = try Data(contentsOf: fileURL)
        let second = Wrist(store: FileWatchSessionStore(directory: folder))
        await second.launch()
        XCTAssertEqual(try Data(contentsOf: fileURL), bytesBefore, "S-94c-11 (a) nothing dropped, nothing written")
        XCTAssertEqual(second.waterLogIds, ["w-3", "w-4", "w-5", "w-6", "w-7", "w-8"])
        XCTAssertEqual(second.water.glasses, 5, "S-94c-11 (a) shown 5")
        XCTAssertEqual(second.unconfirmedTapIds, ["w-5", "w-6", "w-8"])
        XCTAssertEqual(
            second.pendingTapMessageIds,
            pendingBeforeFirstLaunch,
            "S-94c-11 (a) the unconfirmed taps are still owed under msg-w-5, msg-w-6, msg-w-8"
        )

        // (b) A prune that finds nothing writes nothing, torn tail included.
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"recordType":"obs"#.utf8))
        try handle.close()
        let tornBytes = try Data(contentsOf: fileURL)
        let fresh = FileWatchSessionStore(directory: folder)
        let dropped = await fresh.pruneWaterTaps(loggedBefore: at("2026-10-29T09:00:00Z"))
        XCTAssertEqual(dropped, [], "S-94c-11 (b) nothing left to drop")
        XCTAssertEqual(try Data(contentsOf: fileURL), tornBytes, "S-94c-11 (b) the file is byte-identical")

        // (c) Three days on, the taps confirmed then are past the cutoff.
        let third = Wrist(store: FileWatchSessionStore(directory: folder), now: "2026-11-04T09:00:01Z")
        await third.launch()
        XCTAssertEqual(third.waterLogIds, ["w-5", "w-6", "w-8"], "S-94c-11 (c) drops w-3, w-4, w-7")
        let reread = await storedTapIds(FileWatchSessionStore(directory: folder))
        XCTAssertEqual(reread, ["w-5", "w-6", "w-8"], "S-94c-11 (c) and the file")
        XCTAssertEqual(third.water.glasses, 0, "S-94c-11 (c) frame day 11-01 is not local 11-04; no tap today")
        XCTAssertFalse(third.water.canRemove, "S-94c-11 (c) minus is off at 0")
    }

    // MARK: - S-94c-12 a time-zone change across a relaunch

    func testS94c12ATimeZoneChangeAcrossARelaunch() async throws {
        let store = InMemoryWatchSessionStore()
        let build = Wrist(store: store)
        await build.launch()
        try await build.engine.logWaterGlass(.add, loggedAt: at("2026-10-31T12:00:00Z"))  // A = w-1
        try await build.engine.logWaterGlass(.add, loggedAt: at("2026-10-31T09:59:00Z"))  // C = w-2
        try await build.engine.logWaterGlass(.add, loggedAt: at("2026-11-01T08:00:00Z"))  // B = w-3
        try await build.engine.applyMessage(try receipt(["w-1", "w-2"]))
        let held = await build.water.applyWaterDown(try waterFrame("2026-11-01T08:30:00Z", day: "2026-11-01", glasses: 2, ids: []))
        XCTAssertTrue(held.applied)

        let utc3 = Wrist(store: store)
        await utc3.launch()
        XCTAssertEqual(utc3.water.glasses, 3, "S-94c-12 (a) UTC+3: base 2, plus B; A and C are 10-31 local")

        let utcMinus10 = Wrist(store: store, zone: -36000)
        await utcMinus10.launch()
        XCTAssertEqual(
            utcMinus10.water.glasses,
            2,
            "S-94c-12 (b) UTC−10: 10-31 23:00 local; frame day 11-01 is not today, so A + B, C excluded"
        )
        XCTAssertEqual(utcMinus10.waterLogIds, ["w-1", "w-2", "w-3"], "S-94c-12 (b) A and C are 21 h and 23 h old: kept")
        let stored = await storedTapIds(store)
        XCTAssertEqual(stored, ["w-1", "w-2", "w-3"])

        let utc14 = Wrist(store: store, zone: 50400)
        await utc14.launch()
        XCTAssertEqual(utc14.water.glasses, 4, "S-94c-12 (c) UTC+14: 11-01 23:00 local; frame day matches: 2 + A + B")
    }
}
