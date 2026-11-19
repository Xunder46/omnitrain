//
//  WatchWaterSnapshotTests.swift
//  WatchSessionEngineTests
//
//  Phase 1 of `docs/plans/2026-11-01-96-watch-water-follow-up-plan/`: one
//  redraw of the water bar reads the tap log once and parses only the taps
//  whose session id can fall on local today (D-40, D-41, D-45). Scenarios
//  S-94c-1 to S-94c-4.
//
//  Fixture X (as plan 95): the calendar is Gregorian at UTC+3, so the local
//  day turns at 21:00Z; the clock reads 2026-11-01T09:00:00Z unless a test
//  says otherwise; the engine mints `w-1`, `w-2`, … in call order. History H
//  is 2,920 unconfirmed adds, 8 a day at 06:00Z to 13:00Z, for 2025-11-01
//  through 2026-10-31. Thousands of taps are appended to the store as rows
//  shaped exactly like `logWaterGlass`'s, then read back by `engine.restore()`.
//

import XCTest

@testable import WatchSessionEngine

private func at(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)!
}

private func calendar(_ zone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

/// A store that forwards every operation and counts `readAll`.
private final class CountingStore: WatchSessionStore {
    private let backing: WatchSessionStore
    private(set) var reads = 0

    init(_ backing: WatchSessionStore = InMemoryWatchSessionStore()) {
        self.backing = backing
    }

    func append(_ record: StoredWatchRecord) async -> StoredWatchRecord {
        await backing.append(record)
    }

    func readAll() async -> WatchStoreContents {
        reads += 1
        return await backing.readAll()
    }

    func pruneConfirmed() async -> [String] { await backing.pruneConfirmed() }

    func pruneSensorSamples(_ sessionIds: [String]) async -> [String] {
        await backing.pruneSensorSamples(sessionIds)
    }

    func pruneExerciseBatches(keepingVersion: String) async -> [String] {
        await backing.pruneExerciseBatches(keepingVersion: keepingVersion)
    }

    func pruneBests(keepingRecordId: String) async -> [String] {
        await backing.pruneBests(keepingRecordId: keepingRecordId)
    }

    func pruneWater(keepingRecordId: String) async -> [String] {
        await backing.pruneWater(keepingRecordId: keepingRecordId)
    }

    func pruneWaterTaps(loggedBefore cutoff: Date) async -> [String] {
        await backing.pruneWaterTaps(loggedBefore: cutoff)
    }
}

/// One engine over a counting store; water states built over it count every
/// tap-log read and every `loggedAt` parse through D-45's seams.
private final class Counted {
    let clock: TestClock
    let store: CountingStore
    let engine: WatchSessionEngine
    private(set) var emitted: [[String: Any]] = []
    var reads = 0
    var parses = 0
    private var ids = 0

    init(now: String = "2026-11-01T09:00:00Z") {
        let clock = TestClock(at(now))
        let store = CountingStore()
        self.clock = clock
        self.store = store
        var mint: () -> String = { UUID().uuidString }
        var sink: ([String: Any]) -> Void = { _ in }
        engine = WatchSessionEngine(
            store: store,
            onEmit: { sink($0) },
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { mint() },
            sessionIdFactory: { "w9" }
        )
        mint = { [unowned self] in
            self.ids += 1
            return "w-\(self.ids)"
        }
        sink = { [unowned self] in self.emitted.append($0) }
    }

    /// A water state over this engine and store, in `calendar`, counting.
    func water(_ calendar: Calendar = Fixture.utcPlusThree) -> WatchWaterState {
        let engine = engine
        return WatchWaterState(
            engine: engine,
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            calendar: calendar,
            tapLog: { [unowned self] in
                self.reads += 1
                return engine.waterLog
            },
            parseLoggedAt: { [unowned self] value in
                self.parses += 1
                return try parseUtcIso(value)
            }
        )
    }

    /// "Tap c at t": a stored row shaped exactly like
    /// `logWaterGlass(c, loggedAt: t)`'s, recorded at the fixture clock.
    func seed(_ id: String, _ change: WatchGlassChange, _ instant: Date) async {
        _ = await store.append(.observation(Self.row(id, change, instant, recordedAt: clock.now)))
    }

    static func row(
        _ id: String,
        _ change: WatchGlassChange,
        _ instant: Date,
        recordedAt: Date
    ) -> WatchObservationRecord {
        WatchObservationRecord(
            recordId: id,
            sessionId: WatchNutritionSession.idFor(instant),
            recordedAt: recordedAt,
            kind: WatchObservationKind.waterGlass,
            payload: [
                "entryId": id,
                "eventId": id,
                "kind": WatchObservationKind.waterGlass,
                "loggedAt": utcIso(instant),
                "glassChange": change.rawValue,
            ]
        )
    }

    /// History H: 2,920 unconfirmed adds, 8 a day at 06:00Z + i h, i = 0..7,
    /// for every day of 2025-11-01 through 2026-10-31.
    func seedHistory() async {
        var day = at("2025-11-01T00:00:00Z")
        let last = at("2026-10-31T00:00:00Z")
        var n = 0
        while day <= last {
            for hour in 0..<8 {
                n += 1
                await seed("h-\(n)", .add, day.addingTimeInterval(Double(6 + hour) * 3600))
            }
            day = day.addingTimeInterval(86_400)
        }
        XCTAssertEqual(n, 2920, "History H is 365 days × 8 taps")
    }

    /// Resets the three counters before one read.
    func resetCounters() {
        reads = 0
        parses = 0
        storeBaseline = store.reads
    }

    private var storeBaseline = 0

    var storeReads: Int { store.reads - storeBaseline }
}

private enum Fixture {
    static let utcPlusThree = calendar(TimeZone(secondsFromGMT: 10800)!)
}

final class WatchWaterSnapshotTests: XCTestCase {

    // MARK: - S-94c-1 one tap-log read and candidate-only parses, on 2,924 taps

    func testS94c1OneTapLogReadAndCandidateOnlyParsesOn2924Taps() async throws {
        let x = Counted()
        await x.seedHistory()
        await x.engine.restore()
        let water = x.water()
        await water.restore()

        try await x.engine.logWaterGlass(.add, loggedAt: at("2026-11-01T06:00:00Z"))
        try await x.engine.logWaterGlass(.add, loggedAt: at("2026-11-01T06:30:00Z"))
        try await x.engine.logWaterGlass(.remove, loggedAt: at("2026-11-01T07:00:00Z"))
        try await x.engine.logWaterGlass(.add, loggedAt: at("2026-11-01T07:30:00Z"))
        XCTAssertEqual(x.engine.waterLog.count, 2924)

        // One seeded row equals one logged row, field for field.
        let logged = try XCTUnwrap(x.engine.waterLog.first { $0.recordId == "w-1" })
        let seeded = Counted.row("w-1", .add, at("2026-11-01T06:00:00Z"), recordedAt: x.clock.now)
        XCTAssertEqual(seeded.recordId, logged.recordId)
        XCTAssertEqual(seeded.sessionId, logged.sessionId)
        XCTAssertEqual(seeded.recordedAt, logged.recordedAt)
        XCTAssertEqual(seeded.kind, logged.kind)
        XCTAssertNil(logged.confirmedAt)
        XCTAssertEqual(NSDictionary(dictionary: seeded.payload), NSDictionary(dictionary: logged.payload))

        let expected = WatchWaterSnapshot(glasses: 2, canAdd: true, canRemove: true, spokenCount: "2 glasses")
        let model = WatchWaterModel(state: water)

        let reads: [(String, () -> Any)] = [
            ("snapshot", { water.snapshot }),
            ("glasses", { water.glasses }),
            ("canAdd", { water.canAdd }),
            ("canRemove", { water.canRemove }),
            ("model.snapshot", { model.snapshot }),
        ]
        for (name, read) in reads {
            x.resetCounters()
            let value = read()
            switch name {
            case "snapshot", "model.snapshot":
                XCTAssertEqual(value as? WatchWaterSnapshot, expected, "S-94c-1 \(name): 0 +1 +1 −1 +1")
            case "glasses": XCTAssertEqual(value as? Int, 2, "S-94c-1 glasses")
            case "canAdd": XCTAssertEqual(value as? Bool, true, "S-94c-1 canAdd: 4 < tapsPerDay")
            default: XCTAssertEqual(value as? Bool, true, "S-94c-1 canRemove")
            }
            XCTAssertEqual(x.reads, 1, "S-94c-1 \(name) reads the tap log once")
            XCTAssertEqual(x.storeReads, 0, "S-94c-1 \(name) never reads the store")
            XCTAssertLessThanOrEqual(
                x.parses,
                12,
                "S-94c-1 \(name) parses only 10-31's 8 and today's 4; the other 2,912 are skipped unparsed"
            )
        }
    }

    // MARK: - S-94c-2 the filter is exact across zones, DST and local midnight

    func testS94c2TheFilterIsExactAcrossZonesDstAndLocalMidnight() async throws {
        let x = Counted(now: "2026-11-01T11:00:00Z")
        let taps: [(String, WatchGlassChange, String)] = [
            ("p1", .add, "2026-10-31T11:59:59Z"),
            ("p2", .add, "2026-10-31T12:00:00Z"),
            ("p3", .add, "2026-10-31T18:15:00Z"),
            ("p4", .add, "2026-10-31T20:59:59Z"),
            ("p5", .add, "2026-10-31T21:00:00Z"),
            ("p6", .remove, "2026-11-01T03:59:59Z"),
            ("p7", .add, "2026-11-01T04:00:00Z"),
            ("p8", .add, "2026-11-01T10:00:00Z"),
            ("p9", .add, "2026-11-01T10:59:59Z"),
        ]
        for (id, change, instant) in taps {
            await x.seed(id, change, at(instant))
        }
        let firstDistractor = at("2026-10-01T00:00:00Z")
        for k in 0..<300 {
            await x.seed("d-\(k)", .add, firstDistractor.addingTimeInterval(Double(k) * 7200))
        }
        await x.engine.restore()
        XCTAssertEqual(x.engine.waterLog.count, 309)

        let cases: [(String, TimeZone, Int, Int)] = [
            ("UTC+3", TimeZone(secondsFromGMT: 10800)!, 3, 9),
            ("UTC+14", TimeZone(secondsFromGMT: 50400)!, 2, 4),
            ("UTC−12", TimeZone(secondsFromGMT: -43200)!, 6, 9),
            ("America/New_York", try XCTUnwrap(TimeZone(identifier: "America/New_York")), 3, 4),
            ("Asia/Kathmandu", try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu")), 5, 9),
        ]
        for (name, zone, glasses, maxParses) in cases {
            let water = x.water(calendar(zone))
            await water.restore()
            x.resetCounters()
            let snapshot = water.snapshot
            XCTAssertEqual(snapshot.glasses, glasses, "S-94c-2 \(name): today's taps fold to \(glasses)")
            XCTAssertEqual(x.reads, 1, "S-94c-2 \(name) reads the tap log once")
            XCTAssertLessThanOrEqual(
                x.parses,
                maxParses,
                "S-94c-2 \(name) parses only the taps whose UTC date local today touches; no distractor"
            )
        }
    }

    // MARK: - S-94c-3 the cap holds with a long history

    func testS94c3TheCapHoldsWithALongHistory() async throws {
        let x = Counted()
        await x.seedHistory()
        let morning = at("2026-11-01T00:00:00Z")  // 03:00 local
        for i in 0..<500 {
            await x.seed("t-\(i)", .add, morning.addingTimeInterval(Double(i)))
        }
        await x.engine.restore()
        let water = x.water()
        await water.restore()
        XCTAssertEqual(x.engine.waterLog.count, 3420)

        x.resetCounters()
        let snapshot = water.snapshot
        XCTAssertEqual(snapshot.glasses, 500, "S-94c-3 500 adds today")
        XCTAssertFalse(snapshot.canAdd, "S-94c-3 the cap is reached")
        XCTAssertFalse(snapshot.canRemove, "S-94c-3 minus is off at the cap too")
        XCTAssertEqual(x.reads, 1, "S-94c-3 one tap-log read per snapshot")
        XCTAssertLessThanOrEqual(x.parses, 508, "S-94c-3 10-31's 8 plus today's 500")

        let rows = await x.store.readAll().observations.count
        let added = await water.press(.add)
        let removed = await water.press(.remove)
        XCTAssertFalse(added, "S-94c-3 a plus past the cap stores nothing")
        XCTAssertFalse(removed, "S-94c-3 a minus past the cap stores nothing")
        let rowsAfter = await x.store.readAll().observations.count
        XCTAssertEqual(rowsAfter, rows, "S-94c-3 no row is stored")
        XCTAssertTrue(x.emitted.isEmpty, "S-94c-3 nothing is emitted")
        XCTAssertEqual(x.engine.waterLog.count, 3420)
    }

    // MARK: - S-94c-4 an empty store

    func testS94c4AnEmptyStore() async throws {
        let x = Counted()
        await x.engine.restore()
        let water = x.water()
        await water.restore()

        x.resetCounters()
        let snapshot = water.snapshot

        XCTAssertEqual(
            snapshot,
            WatchWaterSnapshot(glasses: 0, canAdd: true, canRemove: false, spokenCount: "0 glasses"),
            "S-94c-4 nothing stored: 0, plus on, minus off"
        )
        XCTAssertEqual(x.reads, 1, "S-94c-4 one tap-log read")
        XCTAssertEqual(x.parses, 0, "S-94c-4 nothing to parse")
        XCTAssertEqual(x.storeReads, 0, "S-94c-4 the store is never read")
    }
}
