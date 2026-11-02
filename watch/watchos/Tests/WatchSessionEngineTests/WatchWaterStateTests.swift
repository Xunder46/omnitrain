//
//  WatchWaterStateTests.swift
//  WatchSessionEngineTests
//
//  Phase 2 of `docs/plans/2026-11-01-95-watch-water-bar-plan/`: the wrist's
//  water count. `WatchWaterState` holds the newest `water_down` frame (plan 95
//  D-24), shows the phone's count plus the wrist's own taps the phone has not
//  counted yet (D-25, plan 94 D-7), caps a day's taps at the schema's
//  `appliedTapIds.maxItems` (D-26) and gates its two presses (D-27).
//
//  Fixture X: the calendar is Gregorian at UTC+3, so the local day turns at
//  21:00Z; the clock reads 2026-11-01T09:00:00Z (12:00 local) unless a test
//  says otherwise; the id factory yields `w-1`, `w-2`, … in call order.
//

import Combine
import XCTest

@testable import WatchSessionEngine

private func at(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)!
}

/// Local time is UTC+3 in every scenario: 21:00Z is the local midnight.
private func utcPlusThree() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 10800)!
    return calendar
}

/// `fixtures/valid/water_down.json` with the scenario's payload: `sentAt` is
/// the generation instant and `messageId` follows the phone's rule
/// `msg-water-<generatedAtMs>-<glasses>-<appliedTapIds.count>` (plan 94 D-6).
private func waterFrame(
    _ generatedAt: String,
    day: String = "2026-11-01",
    glasses: Any,
    ids: [String]
) throws -> [String: Any] {
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

private func rowId(_ frame: [String: Any]) -> String {
    "water-\(frame["messageId"] as? String ?? "")"
}

/// One engine and one water state over one store, minting `w-1`, `w-2`, … as
/// entry ids, counting every `onWaterChanged`.
private final class WaterState {
    let clock: TestClock
    let store: WatchSessionStore
    let calendar: Calendar
    private(set) var engine: WatchSessionEngine!
    private(set) var water: WatchWaterState!
    private(set) var emitted: [[String: Any]] = []
    private(set) var changes = 0
    private var ids = 0

    init(
        store: WatchSessionStore = InMemoryWatchSessionStore(),
        now: String = "2026-11-01T09:00:00Z",
        calendar: Calendar = utcPlusThree(),
        validated: Bool = true
    ) {
        self.clock = TestClock(at(now))
        self.store = store
        self.calendar = calendar
        engine = WatchSessionEngine(
            store: store,
            onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
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
            validator: validated ? Harness.validator() : nil,
            clock: clock.call,
            calendar: calendar
        )
        water.onWaterChanged = { [weak self] in self?.changes += 1 }
    }

    /// The launch: the engine and the water state read the store back.
    func launch() async {
        await engine.restore()
        await water.restore()
    }

    /// "Tap at t": a stored tap with an explicit instant.
    @discardableResult
    func tap(_ change: WatchGlassChange, _ instant: String) async throws -> WatchObservationRecord {
        try await engine.logWaterGlass(change, loggedAt: at(instant))
    }

    func hold(_ frame: [String: Any]) async -> WatchCatalogSyncResult {
        await water.applyWaterDown(frame)
    }

    var sentTaps: [[String: Any]] {
        emitted.filter { $0["type"] as? String == "observations_up" }
    }

    func waterRowIds() async -> [String] {
        await store.readAll().water.map(\.recordId)
    }
}

/// The schema's `appliedTapIds.maxItems`: the per-day number of taps the phone
/// lists, which the wrist's cap must equal (plan 95 D-26).
private func schemaTapsPerDay() throws -> Int {
    let schema = try Fixtures.json("schemas/messages/water_down.schema.json")
    let parts = try XCTUnwrap(schema["allOf"] as? [[String: Any]])
    for part in parts {
        let properties = part["properties"] as? [String: Any]
        let payload = properties?["payload"] as? [String: Any]
        let fields = payload?["properties"] as? [String: Any]
        if let ids = fields?["appliedTapIds"] as? [String: Any],
           let maxItems = ids["maxItems"] as? Int {
            return maxItems
        }
    }
    throw Fixtures.FixtureError.malformed("water_down.schema.json carries no appliedTapIds.maxItems")
}

final class WatchWaterStateTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-water-state-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    // MARK: - S-94b-3 (count half) the local day, not the UTC day

    func testS94b3TheLocalDayNotTheUtcDayDecidesTheCount() async throws {
        // 21:30Z on 10-31 is 00:30 on 11-01 local.
        let x = WaterState(now: "2026-10-31T21:30:00Z")
        await x.launch()
        _ = await x.hold(try waterFrame("2026-10-31T21:20:00Z", glasses: 2, ids: []))

        let stored = await x.water.press(.add)

        XCTAssertTrue(stored)
        XCTAssertEqual(
            x.sentTaps.last?["sessionId"] as? String,
            "nutrition-2026-10-31",
            "S-94b-3 the wire id is the UTC date (plan 94 D-2)"
        )
        XCTAssertEqual(
            x.water.glasses,
            3,
            "S-94b-3 the frame's 11-01 is the wrist's local today: base 2, plus the tap"
        )
    }

    // MARK: - S-94b-4 (restore half) one frame row, kept across relaunch

    func testS94b4OneFrameRowAfterEachApplyAndARelaunchHoldsTheNewest() async throws {
        let frames = [
            try waterFrame("2026-11-01T08:00:00Z", glasses: 2, ids: ["w-1"]),
            try waterFrame("2026-11-01T08:05:00Z", glasses: 3, ids: ["w-1", "w-2"]),
            try waterFrame("2026-11-01T08:10:00Z", glasses: 3, ids: ["w-1", "w-2", "w-3"]),
        ]
        let memory = InMemoryWatchSessionStore()
        let folder: URL = directory
        let stores: [(String, WatchSessionStore, () -> WatchSessionStore)] = [
            ("in-memory", memory, { memory }),
            ("file", FileWatchSessionStore(directory: folder), { FileWatchSessionStore(directory: folder) }),
        ]

        for (name, store, reopen) in stores {
            let x = WaterState(store: store)
            await x.launch()
            for frame in frames {
                let result = await x.hold(frame)
                XCTAssertTrue(result.applied, "S-94b-4 (\(name)) a newer frame applies")
                let rows = await x.waterRowIds()
                XCTAssertEqual(
                    rows,
                    [rowId(frame)],
                    "S-94b-4 (\(name)) after each apply the store holds one frame: the one just applied"
                )
            }

            let relaunched = WaterState(store: reopen())
            await relaunched.launch()
            XCTAssertEqual(relaunched.water.glasses, 3, "S-94b-4 (\(name)) the restored frame's count, no taps")
            XCTAssertEqual(relaunched.changes, 1, "S-94b-4 (\(name)) a restore tells the screen once")
            let rows = await relaunched.waterRowIds()
            XCTAssertEqual(rows.count, 1)
        }
    }

    func testS94b4ARestoreHoldsTheGreatestGeneratedAtThenSequence() async throws {
        // Rows a crash left unpruned: the restore still picks the newest frame.
        let store = InMemoryWatchSessionStore()
        func row(_ id: String, _ generated: String, _ glasses: Int) -> StoredWatchRecord {
            .water(
                WatchWaterRecord(
                    recordId: id,
                    recordedAt: at(generated),
                    generatedAt: at(generated),
                    day: "2026-11-01",
                    glasses: glasses
                )
            )
        }
        _ = await store.append(row("water-newest", "2026-11-01T08:10:00Z", 5))
        _ = await store.append(row("water-older", "2026-11-01T08:00:00Z", 1))
        _ = await store.append(row("water-tie-earlier", "2026-11-01T08:10:00Z", 6))

        let x = WaterState(store: store)
        await x.launch()

        XCTAssertEqual(
            x.water.glasses,
            6,
            "S-94b-4 the greatest generatedAt wins, a tie going to the later stored row"
        )
    }

    // MARK: - S-94b-5 the newest frame wins; a repeat writes nothing

    func testS94b5TheNewestFrameWinsAndARepeatWritesNothing() async throws {
        let x = WaterState()
        await x.launch()
        let f2 = try waterFrame("2026-11-01T08:05:00Z", glasses: 3, ids: ["w-1", "w-2"])
        let held = await x.hold(f2)
        XCTAssertTrue(held.applied)
        XCTAssertEqual(x.water.glasses, 3)

        // (a) an older frame
        let a = await x.hold(try waterFrame("2026-11-01T08:00:00Z", glasses: 2, ids: ["w-1"]))
        XCTAssertFalse(a.applied, "S-94b-5 (a) an older frame is dropped")
        XCTAssertTrue(a.rejections.isEmpty)
        XCTAssertEqual(x.water.glasses, 3, "S-94b-5 (a) base 3")

        // (b) the same instant, different content
        let f2b = try waterFrame("2026-11-01T08:05:00Z", glasses: 4, ids: ["w-1", "w-2", "w-3"])
        let changesBeforeB = x.changes
        let b = await x.hold(f2b)
        XCTAssertTrue(b.applied, "S-94b-5 (b) a tie goes to the later received")
        XCTAssertEqual(x.water.glasses, 4, "S-94b-5 (b) base 4")
        XCTAssertEqual(x.changes, changesBeforeB + 1, "S-94b-5 (b) an applied frame tells the screen")
        let rowsAfterB = await x.waterRowIds()
        XCTAssertEqual(rowsAfterB, [rowId(f2b)])

        // (c) newer, same content as held
        let changesBeforeC = x.changes
        let c = await x.hold(try waterFrame("2026-11-01T08:20:00Z", glasses: 4, ids: ["w-1", "w-2", "w-3"]))
        XCTAssertFalse(c.applied, "S-94b-5 (c) the held content again is not applied")
        let rowsAfterC = await x.waterRowIds()
        XCTAssertEqual(rowsAfterC, [rowId(f2b)], "S-94b-5 (c) nothing is written: the row is still F2b")
        XCTAssertEqual(x.changes, changesBeforeC, "S-94b-5 (c) no onWaterChanged for an unchanged frame")

        // (d) older than the 08:20Z the wrist now holds in memory
        let d = await x.hold(
            try waterFrame("2026-11-01T08:15:00Z", glasses: 5, ids: ["w-1", "w-2", "w-3", "w-4"])
        )
        XCTAssertFalse(d.applied, "S-94b-5 (d) older than the 08:20Z held in memory")
        XCTAssertEqual(x.water.glasses, 4, "S-94b-5 (d) base 4")
        let rowsAfterD = await x.waterRowIds()
        XCTAssertEqual(rowsAfterD, [rowId(f2b)])
        XCTAssertEqual(x.changes, changesBeforeC, "S-94b-5 (d) no onWaterChanged for a dropped frame")
    }

    // MARK: - S-94b-6 a frame the wrist cannot read changes nothing

    func testS94b6AFrameTheWristCannotReadChangesNothing() async throws {
        let x = WaterState()
        await x.launch()
        let f2 = try waterFrame("2026-11-01T08:05:00Z", glasses: 3, ids: ["w-1", "w-2"])
        _ = await x.hold(f2)
        let changesHeld = x.changes
        let invalid = try Fixtures.entries("invalid")

        for name in ["water_down_unknown_field.json", "water_down_duplicate_tap.json"] {
            let path = "invalid/\(name)"
            let entry = try XCTUnwrap(invalid.first { $0["path"] as? String == path })
            let code = try XCTUnwrap(entry["expectedCode"] as? String)

            let result = await x.hold(try Fixtures.json("fixtures/\(path)"))

            XCTAssertFalse(result.applied, "S-94b-6 \(name) is refused")
            XCTAssertTrue(
                result.rejections.map(\.code).contains(code),
                "S-94b-6 \(name) is refused with the manifest's code \(code), got \(result.rejections.map(\.code))"
            )
            let rows = await x.waterRowIds()
            XCTAssertEqual(rows, [rowId(f2)], "S-94b-6 \(name) stores nothing")
            XCTAssertEqual(x.water.glasses, 3, "S-94b-6 base 3 throughout")
        }

        // A state built without a validator must still not read a string count.
        let unvalidated = WaterState(store: x.store, validated: false)
        await unvalidated.launch()
        let changesUnvalidated = unvalidated.changes
        let stringCount = await unvalidated.hold(
            try waterFrame("2026-11-01T08:05:00Z", glasses: "3", ids: ["w-1", "w-2"])
        )
        XCTAssertFalse(stringCount.applied, "S-94b-6 a string count is not applied")
        let rows = await x.waterRowIds()
        XCTAssertEqual(rows, [rowId(f2)], "S-94b-6 and nothing is stored for it")
        XCTAssertEqual(unvalidated.water.glasses, 3, "S-94b-6 base 3 throughout")
        XCTAssertEqual(x.changes, changesHeld, "S-94b-6 no onWaterChanged for a refused frame")
        XCTAssertEqual(unvalidated.changes, changesUnvalidated, "S-94b-6 nor for an unreadable one")
    }

    func testS94b6UnreadableFieldsAreNotAppliedEvenWhenNewer() async throws {
        // Every frame here is newer than the held one, so only the reader's
        // refusal keeps it out (D-24 step 2).
        let x = WaterState(validated: false)
        await x.launch()
        _ = await x.hold(try waterFrame("2026-11-01T08:05:00Z", glasses: 3, ids: []))
        let held = await x.waterRowIds()
        let changesHeld = x.changes

        var noMessageId = try waterFrame("2026-11-01T08:30:00Z", glasses: 5, ids: [])
        noMessageId.removeValue(forKey: "messageId")
        var noDay = try waterFrame("2026-11-01T08:31:00Z", glasses: 5, ids: [])
        var payload = try XCTUnwrap(noDay["payload"] as? [String: Any])
        payload.removeValue(forKey: "day")
        noDay["payload"] = payload
        var noGeneratedAt = try waterFrame("2026-11-01T08:32:00Z", glasses: 5, ids: [])
        payload = try XCTUnwrap(noGeneratedAt["payload"] as? [String: Any])
        payload.removeValue(forKey: "generatedAt")
        noGeneratedAt["payload"] = payload
        var idsNotStrings = try waterFrame("2026-11-01T08:33:00Z", glasses: 5, ids: [])
        payload = try XCTUnwrap(idsNotStrings["payload"] as? [String: Any])
        payload["appliedTapIds"] = [1, 2]
        idsNotStrings["payload"] = payload
        let unreadable: [(String, [String: Any])] = [
            ("a string count", try waterFrame("2026-11-01T08:34:00Z", glasses: "5", ids: [])),
            ("a boolean count", try waterFrame("2026-11-01T08:35:00Z", glasses: true, ids: [])),
            ("a fractional count", try waterFrame("2026-11-01T08:36:00Z", glasses: 2.5, ids: [])),
            ("no messageId", noMessageId),
            ("no day", noDay),
            ("no generatedAt", noGeneratedAt),
            ("tap ids that are not strings", idsNotStrings),
        ]

        for (what, frame) in unreadable {
            let result = await x.hold(frame)
            XCTAssertFalse(result.applied, "S-94b-6 \(what) is not applied")
            let rows = await x.waterRowIds()
            XCTAssertEqual(rows, held, "S-94b-6 \(what) stores nothing")
            XCTAssertEqual(x.water.glasses, 3, "S-94b-6 \(what) leaves base 3")
        }
        XCTAssertEqual(x.changes, changesHeld)
    }

    // MARK: - S-94b-7 phone count plus the wrist's uncounted taps

    func testS94b7ThePhonesCountPlusTheWristsUncountedTaps() async throws {
        let x = WaterState()
        await x.launch()
        try await x.tap(.add, "2026-11-01T07:00:00Z")
        try await x.tap(.add, "2026-11-01T07:30:00Z")
        try await x.tap(.remove, "2026-11-01T08:00:00Z")
        try await x.tap(.add, "2026-11-01T08:30:00Z")
        XCTAssertEqual(x.engine.waterLog.map(\.recordId), ["w-1", "w-2", "w-3", "w-4"])

        _ = await x.hold(try waterFrame("2026-11-01T08:40:00Z", glasses: 2, ids: ["w-1"]))

        XCTAssertEqual(
            x.water.glasses,
            3,
            "S-94b-7 base 2; w-1 listed; w-2 → 3; w-3 → 2; w-4 → 3"
        )
    }

    func testS94b7TapsFoldInLoggedAtOrderTiesByStoreOrder() async throws {
        // Stored add-then-remove but logged remove-first: by loggedAt the remove
        // meets 0 and the add makes 1; by store order the count would be 0.
        let byInstant = WaterState()
        await byInstant.launch()
        try await byInstant.tap(.add, "2026-11-01T08:30:00Z")
        try await byInstant.tap(.remove, "2026-11-01T08:00:00Z")
        XCTAssertEqual(byInstant.water.glasses, 1, "D-25 taps fold in loggedAt order")

        // The same instant: store order decides — remove (stays 0), then add.
        let tied = WaterState()
        await tied.launch()
        try await tied.tap(.remove, "2026-11-01T08:00:00Z")
        try await tied.tap(.add, "2026-11-01T08:00:00Z")
        XCTAssertEqual(tied.water.glasses, 1, "D-25 a tie in loggedAt goes by store order")
    }

    // MARK: - S-94b-8 before the first sync

    func testS94b8BeforeTheFirstSync() async throws {
        let x = WaterState()
        await x.launch()
        let changesAfterLaunch = x.changes

        XCTAssertEqual(x.water.glasses, 0, "S-94b-8 0 before the first sync")
        XCTAssertFalse(x.water.canRemove, "S-94b-8 minus is off at 0")
        XCTAssertTrue(x.water.canAdd)

        let removed = await x.water.press(.remove)
        XCTAssertFalse(removed, "S-94b-8 a minus at 0 stores nothing")
        XCTAssertTrue(x.engine.waterLog.isEmpty, "S-94b-8 no observation")
        XCTAssertTrue(x.sentTaps.isEmpty, "S-94b-8 no emit")
        XCTAssertEqual(x.changes, changesAfterLaunch, "S-94b-8 a press that stored nothing changes nothing")

        let first = await x.water.press(.add)
        XCTAssertTrue(first)
        XCTAssertEqual(x.water.glasses, 1, "S-94b-8 then 1")
        XCTAssertEqual(x.changes, changesAfterLaunch + 1, "S-94b-8 a stored tap tells the screen")
        let second = await x.water.press(.add)
        XCTAssertTrue(second)
        XCTAssertEqual(x.water.glasses, 2, "S-94b-8 then 2")
        XCTAssertTrue(x.water.canRemove)
        XCTAssertEqual(x.engine.waterLog.map { $0.payload["glassChange"] as? String }, ["add", "add"])
        XCTAssertEqual(x.sentTaps.count, 2)
        XCTAssertEqual(
            try parseUtcIso(x.engine.waterLog.first?.payload["loggedAt"]),
            at("2026-11-01T09:00:00Z"),
            "S-94b-8 a press is logged at the state's clock"
        )
    }

    // MARK: - S-94b-9 a frame for another day

    func testS94b9AFrameForYesterdayCountsFromZero() async throws {
        let x = WaterState()
        await x.launch()
        _ = await x.hold(try waterFrame("2026-10-31T20:00:00Z", day: "2026-10-31", glasses: 5, ids: ["w-0"]))
        try await x.tap(.add, "2026-10-31T19:00:00Z")  // 22:00 on 10-31: yesterday's
        try await x.tap(.add, "2026-10-31T21:30:00Z")  // 00:30 on 11-01: today's

        XCTAssertEqual(
            x.water.glasses,
            1,
            "S-94b-9 (a) base 0 (day mismatch); w-1 is yesterday's; w-2 → 1"
        )
    }

    func testS94b9APhoneAheadOfTheWristCountsFromZero() async throws {
        let x = WaterState(now: "2026-11-01T20:59:00Z")  // 23:59 on 11-01
        await x.launch()
        _ = await x.hold(try waterFrame("2026-11-01T20:58:00Z", day: "2026-11-02", glasses: 4, ids: []))
        try await x.tap(.add, "2026-11-01T20:00:00Z")

        XCTAssertEqual(x.water.glasses, 1, "S-94b-9 (b) base 0 (the phone's day is tomorrow); the tap → 1")
    }

    // MARK: - S-94b-10 minus at 0, and both devices removing while apart

    func testS94b10MinusAtZeroAndBothDevicesRemovingWhileApart() async throws {
        let x = WaterState()
        await x.launch()
        _ = await x.hold(try waterFrame("2026-11-01T08:00:00Z", glasses: 1, ids: []))
        try await x.tap(.remove, "2026-11-01T08:30:00Z")

        XCTAssertEqual(x.water.glasses, 0, "S-94b-10 the wrist's minus took it to 0")
        XCTAssertFalse(x.water.canRemove)
        let again = await x.water.press(.remove)
        XCTAssertFalse(again, "S-94b-10 a further minus stores nothing")
        XCTAssertEqual(x.engine.waterLog.count, 1)

        _ = await x.hold(try waterFrame("2026-11-01T08:45:00Z", glasses: 0, ids: []))
        XCTAssertEqual(x.water.glasses, 0, "S-94b-10 base 0, w-1 remove → max(0, −1) = 0")

        _ = await x.hold(try waterFrame("2026-11-01T08:50:00Z", glasses: 0, ids: ["w-1"]))
        XCTAssertEqual(x.water.glasses, 0, "S-94b-10 the phone applied w-1 at 0 ml")
        XCTAssertEqual(x.engine.waterLog.count, 1, "S-94b-10 one tap was ever stored")
    }

    // MARK: - S-94b-11 (state half) the receipt is lost and the tap is delivered again

    func testS94b11ALostReceiptThenTheAnswerAndItsRepeat() async throws {
        let x = WaterState()
        await x.launch()
        _ = await x.hold(try waterFrame("2026-11-01T08:00:00Z", glasses: 2, ids: []))

        let stored = await x.water.press(.add)
        XCTAssertTrue(stored)
        XCTAssertEqual(x.water.glasses, 3)
        let firstEmission = try XCTUnwrap(x.sentTaps.last)
        XCTAssertEqual(
            x.engine.pendingObservations().map { $0["messageId"] as? String },
            [firstEmission["messageId"] as? String],
            "S-94b-11 with no receipt the tap is still owed, under msg-w-1"
        )
        XCTAssertEqual(firstEmission["messageId"] as? String, "msg-w-1")

        try await x.engine.applyMessage(try receipt(["w-1"]))
        let answer = try waterFrame("2026-11-01T09:01:00Z", glasses: 3, ids: ["w-1"])
        let answered = await x.hold(answer)
        XCTAssertTrue(answered.applied)
        XCTAssertEqual(x.water.glasses, 3, "S-94b-11 after the answer 3, not 4")
        XCTAssertTrue(x.engine.unconfirmedObservations.isEmpty)

        let changesBeforeRepeat = x.changes
        try await x.engine.applyMessage(try receipt(["w-1"]))
        let repeated = await x.hold(try waterFrame("2026-11-01T09:02:00Z", glasses: 3, ids: ["w-1"]))
        XCTAssertFalse(repeated.applied, "S-94b-11 the repeat changes nothing (D-24 (4))")
        let rows = await x.waterRowIds()
        XCTAssertEqual(rows, [rowId(answer)], "S-94b-11 the repeat writes no water row")
        XCTAssertEqual(x.water.glasses, 3)
        XCTAssertEqual(x.changes, changesBeforeRepeat)
    }

    // MARK: - S-94b-12 the receipt arrives, the frame is lost

    func testS94b12TheReceiptArrivesTheFrameIsLost() async throws {
        let x = WaterState()
        await x.launch()
        _ = await x.hold(try waterFrame("2026-11-01T08:00:00Z", glasses: 2, ids: []))
        _ = await x.water.press(.add)

        try await x.engine.applyMessage(try receipt(["w-1"]))

        XCTAssertNotNil(x.engine.waterLog.first?.confirmedAt, "S-94b-12 w-1 is confirmed")
        XCTAssertEqual(
            x.water.glasses,
            3,
            "S-94b-12 a receipt never takes a tap out of the count; only the frame's list does"
        )

        _ = await x.hold(try waterFrame("2026-11-01T09:05:00Z", glasses: 3, ids: ["w-1"]))
        XCTAssertEqual(x.water.glasses, 3, "S-94b-12 after the frame 3")
    }

    // MARK: - S-94b-13 both devices tapped while apart

    func testS94b13BothDevicesTappedWhileApart() async throws {
        let x = WaterState()
        await x.launch()
        _ = await x.hold(try waterFrame("2026-11-01T08:00:00Z", glasses: 2, ids: []))
        try await x.tap(.add, "2026-11-01T08:30:00Z")
        XCTAssertEqual(x.water.glasses, 3, "S-94b-13 3 before the phone hears")

        try await x.engine.applyMessage(try receipt(["w-1"]))
        _ = await x.hold(try waterFrame("2026-11-01T09:00:00Z", glasses: 4, ids: ["w-1"]))

        XCTAssertEqual(x.water.glasses, 4, "S-94b-13 4 after: base 4, w-1 listed")
    }

    // MARK: - S-94b-14 the watch's local midnight

    func testS94b14TheWatchsLocalMidnight() async throws {
        let x = WaterState(now: "2026-11-01T20:59:30Z")  // 23:59:30 local
        await x.launch()
        try await x.tap(.add, "2026-11-01T20:50:00Z")
        try await x.tap(.add, "2026-11-01T20:59:10Z")
        _ = await x.hold(try waterFrame("2026-11-01T20:59:00Z", glasses: 3, ids: ["w-1"]))

        XCTAssertEqual(x.water.glasses, 4, "S-94b-14 3 + w-2 before midnight")

        x.clock.advance(60)  // 00:00:30 on 11-02 local
        XCTAssertEqual(x.water.glasses, 0, "S-94b-14 the new day starts at 0")
        XCTAssertFalse(x.water.canRemove)

        let stored = await x.water.press(.add)
        XCTAssertTrue(stored)
        XCTAssertEqual(x.water.glasses, 1, "S-94b-14 the new tap counts for local 11-02")
        let tap = try XCTUnwrap(x.engine.waterLog.last)
        XCTAssertEqual(tap.recordId, "w-3")
        XCTAssertEqual(tap.sessionId, "nutrition-2026-11-01", "S-94b-14 the wire id is still the UTC date")
    }

    // MARK: - S-94b-15 taps past the cap

    func testS94b15TapsPastTheCap() async throws {
        let tapsPerDay = try schemaTapsPerDay()
        XCTAssertEqual(
            WatchWaterLimits.tapsPerDay,
            tapsPerDay,
            "S-94b-15 the wrist's cap is water_down.schema.json's appliedTapIds.maxItems"
        )

        let x = WaterState()
        await x.launch()
        try await x.tap(.add, "2026-10-31T20:00:00Z")  // 23:00 on 10-31: yesterday's
        let morning = at("2026-11-01T06:00:00Z")
        for i in 0..<(tapsPerDay - 1) {
            _ = try await x.engine.logWaterGlass(.add, loggedAt: morning.addingTimeInterval(Double(i)))
        }

        XCTAssertTrue(x.water.canAdd, "S-94b-15 yesterday's tap does not count toward today's cap")
        let last = await x.water.press(.add)
        XCTAssertTrue(last, "S-94b-15 the last allowed tap is stored")

        XCTAssertFalse(x.water.canAdd, "S-94b-15 the cap is reached")
        XCTAssertFalse(x.water.canRemove, "S-94b-15 minus is off at the cap too")
        XCTAssertEqual(x.water.glasses, tapsPerDay)
        let logged = x.engine.waterLog.count
        let sent = x.sentTaps.count
        let changes = x.changes
        let addPast = await x.water.press(.add)
        let removePast = await x.water.press(.remove)
        XCTAssertFalse(addPast, "S-94b-15 a plus past the cap stores nothing")
        XCTAssertFalse(removePast, "S-94b-15 a minus past the cap stores nothing")
        XCTAssertEqual(x.engine.waterLog.count, logged, "S-94b-15 no new observation")
        XCTAssertEqual(x.sentTaps.count, sent, "S-94b-15 no emit")
        XCTAssertEqual(x.changes, changes)

        x.clock.now = at("2026-11-01T21:00:01Z")  // 00:00:01 on 11-02 local
        XCTAssertTrue(x.water.canAdd, "S-94b-15 after local midnight the cap starts over")
        XCTAssertEqual(x.water.glasses, 0)
    }

    // MARK: - S-94b-16 (state half) relaunch with unsent taps

    func testS94b16ARelaunchWithUnsentTaps() async throws {
        let first = WaterState(store: FileWatchSessionStore(directory: directory))
        await first.launch()
        _ = await first.hold(try waterFrame("2026-11-01T08:00:00Z", glasses: 2, ids: []))
        try await first.tap(.add, "2026-11-01T09:00:00Z")
        try await first.tap(.add, "2026-11-01T09:01:00Z")
        let owed = first.engine.pendingObservations().map { $0["messageId"] as? String }
        XCTAssertEqual(owed, ["msg-w-1", "msg-w-2"])

        let relaunched = WaterState(store: FileWatchSessionStore(directory: directory))
        await relaunched.launch()

        XCTAssertEqual(relaunched.water.glasses, 4, "S-94b-16 the held 2 plus two unsent taps")
        XCTAssertEqual(relaunched.engine.unconfirmedObservations.count, 2)
        XCTAssertEqual(
            relaunched.engine.pendingObservations().map { $0["messageId"] as? String },
            owed,
            "S-94b-16 the relaunched wrist owes the same messages"
        )
    }

    // MARK: - S-94b-21 the model

    /// The bar's model reads the state on every access, speaks the count as
    /// VoiceOver says it, presses through the state, and tells SwiftUI on the
    /// main queue whenever the state changes — a tap or a frame (D-33, D-35).
    func testS94b21TheModel() async throws {
        let x = WaterState()
        await x.launch()
        let model = WatchWaterModel(state: x.water)

        XCTAssertEqual(model.glasses, 0, "S-94b-21 0 before anything")
        XCTAssertFalse(model.canRemove, "S-94b-21 minus is off at 0")
        XCTAssertTrue(model.canAdd)
        XCTAssertEqual(model.spokenCount, "0 glasses", "S-94b-21 VoiceOver reads 0 glasses")

        let afterTap = expectation(description: "S-94b-21 a stored tap redraws on the main queue")
        var tapOnMain = false
        var sink = model.objectWillChange.sink { _ in
            tapOnMain = Thread.isMainThread
            afterTap.fulfill()
        }
        let added = await model.press(.add)
        XCTAssertTrue(added, "S-94b-21 a plus returns that it stored a tap")
        await fulfillment(of: [afterTap], timeout: 5)
        XCTAssertTrue(tapOnMain, "S-94b-21 the nudge after a tap is on the main queue")
        XCTAssertEqual(model.glasses, 1)
        XCTAssertEqual(model.spokenCount, "1 glass", "S-94b-21 one glass is singular")
        XCTAssertTrue(model.canRemove)
        sink.cancel()

        let afterFrame = expectation(description: "S-94b-21 an applied frame redraws on the main queue")
        var frameOnMain = false
        sink = model.objectWillChange.sink { _ in
            frameOnMain = Thread.isMainThread
            afterFrame.fulfill()
        }
        let result = await x.hold(try waterFrame("2026-11-01T09:01:00Z", glasses: 3, ids: ["w-1"]))
        XCTAssertTrue(result.applied)
        await fulfillment(of: [afterFrame], timeout: 5)
        XCTAssertTrue(frameOnMain, "S-94b-21 the nudge after a frame is on the main queue")
        XCTAssertEqual(model.glasses, 3, "S-94b-21 the phone's 3, w-1 listed")
        XCTAssertEqual(model.spokenCount, "3 glasses")
        sink.cancel()

        XCTAssertEqual(WatchWaterCopy.addLabel, "Add one glass", "S-94b-21 D-33")
        XCTAssertEqual(WatchWaterCopy.removeLabel, "Remove one glass", "S-94b-21 D-33")
        XCTAssertEqual(WatchWaterCopy.countLabel, "Water", "S-94b-21 D-33")
        XCTAssertEqual(WatchWaterCopy.spokenCount(0), "0 glasses")
        XCTAssertEqual(WatchWaterCopy.spokenCount(1), "1 glass")
        XCTAssertEqual(WatchWaterCopy.spokenCount(12), "12 glasses")
    }
}
