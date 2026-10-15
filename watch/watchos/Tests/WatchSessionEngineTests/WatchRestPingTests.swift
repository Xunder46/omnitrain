//
//  WatchRestPingTests.swift
//  WatchSessionEngineTests
//
//  Phase 2 of
//  `docs/plans/2026-10-08-22-rest-ping-on-watch-plan/2026-10-08-22-rest-ping-on-watch-plan.md`:
//  the wrist half of the rest ping (D-243, D-244, D-250, D-251, S-247).
//
//  Every expectation is read from
//  `watch/contract/watch_rest_ping_contract.json` — the table the Dart half, the
//  view and this suite share — so a number here is the contract rather than a
//  restatement of it. The rule (`WatchRestPing`) is UI-free on purpose: the rest
//  view consults it once per tick, and `RestPingTable.drive` below consults it
//  the same way.
//

import XCTest

@testable import WatchSessionEngine

final class WatchRestPingTests: XCTestCase {

    /// One case of the shared table.
    private struct RestPingCase {
        let name: String
        let interval: Int
        let polls: [Int]
        let taps: [Int]

        /// The scenario id the case is named after, e.g. `S-241`.
        var scenario: String { String(name.prefix(5)) }
    }

    private struct RestPingTable {
        /// The interval a wrist reads before its first sync (S-242).
        let off: Int
        let cases: [RestPingCase]

        static func load() throws -> RestPingTable {
            let contract = try Fixtures.restPingContract()
            let rows = try XCTUnwrap(
                contract["cases"] as? [[String: Any]],
                "the contract carries its cases"
            )
            let cases = try rows.map { row in
                RestPingCase(
                    name: try XCTUnwrap(row["name"] as? String, "a case's name"),
                    interval: try XCTUnwrap(
                        (row["intervalSeconds"] as? NSNumber)?.intValue,
                        "a case's intervalSeconds"
                    ),
                    polls: try XCTUnwrap(
                        (row["pollsSeconds"] as? [NSNumber])?.map(\.intValue),
                        "a case's pollsSeconds"
                    ),
                    taps: try XCTUnwrap(
                        (row["tapSeconds"] as? [NSNumber])?.map(\.intValue),
                        "a case's tapSeconds"
                    )
                )
            }
            return RestPingTable(
                off: try XCTUnwrap(
                    (contract["beforeFirstSync"] as? NSNumber)?.intValue,
                    "the contract's beforeFirstSync"
                ),
                cases: cases
            )
        }

        func named(_ scenario: String) -> [RestPingCase] {
            cases.filter { $0.scenario == scenario }
        }

        func one(_ scenario: String) throws -> RestPingCase {
            try XCTUnwrap(named(scenario).first, "no contract case named \(scenario)")
        }

        /// Drives the rule the way the rest view does: one consultation per
        /// tick, `restId` naming the open rest row.
        ///
        /// A case whose polls do not start at 0 is one where the interval
        /// arrived mid-rest: the seconds before its first poll are ticked with
        /// the setting Off, and Off taps nothing (S-222).
        func drive(_ ping: WatchRestPing, restId: String, _ restCase: RestPingCase) -> [Int] {
            var taps: [Int] = []
            if let first = restCase.polls.first, first > 0 {
                for second in 0..<first {
                    XCTAssertFalse(
                        ping.isOwed(restId: restId, elapsed: second, interval: off),
                        "\(restCase.name): a tick before the interval arrives is Off and taps nothing"
                    )
                }
            }
            for elapsed in restCase.polls
            where ping.isOwed(restId: restId, elapsed: elapsed, interval: restCase.interval) {
                taps.append(elapsed)
            }
            return taps
        }
    }

    private var table: RestPingTable!

    override func setUpWithError() throws {
        table = try RestPingTable.load()
    }

    // MARK: - S-241 the table, one tick per second

    func testS241AnIntervalTapsAtItsMultiplesAndNowhereElse() throws {
        let restCase = try table.one("S-241")
        XCTAssertEqual(
            table.drive(WatchRestPing(), restId: "rest-a", restCase),
            restCase.taps,
            "S-241: an interval of 30 polled every second taps at each multiple"
        )
    }

    func testS241TheTablesOwnExpectationIsEachMultiple() throws {
        let restCase = try table.one("S-241")
        XCTAssertEqual(
            restCase.taps,
            restCase.polls.filter { $0 > 0 && $0 % restCase.interval == 0 },
            "S-241: the expectation is each multiple of the interval among the polls, which keeps the case adversarial"
        )
    }

    // MARK: - S-242 Off, and a wrist that has never synced

    func testS242WithTheIntervalOffNothingTaps() throws {
        let restCase = try table.one("S-242")
        XCTAssertEqual(
            restCase.interval,
            table.off,
            "the Off case polls at the interval a wrist reads before its first sync"
        )
        XCTAssertEqual(
            table.drive(WatchRestPing(), restId: "rest-a", restCase),
            [],
            "S-242: Off never taps, however long the rest runs"
        )
    }

    func testS242AWristThatNeverSyncedReadsOff() async throws {
        let harness = Harness()
        let preferences = WatchPhonePreferences(
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call
        )
        XCTAssertNil(preferences.current, "no copy has arrived from the phone")
        XCTAssertEqual(
            preferences.restPingSeconds,
            table.off,
            "S-242: a wrist that never synced reads the contract's before-first-sync interval"
        )

        let restCase = try table.one("S-242")
        let ping = WatchRestPing()
        for elapsed in restCase.polls {
            XCTAssertFalse(
                ping.isOwed(
                    restId: "rest-a",
                    elapsed: elapsed,
                    interval: preferences.restPingSeconds
                ),
                "S-242: what that wrist reads never taps"
            )
        }
    }

    // MARK: - S-243 a gap

    func testS243AGapTapsOnceForTheBoundariesItCrossed() throws {
        let restCase = try table.one("S-243")
        let taps = table.drive(WatchRestPing(), restId: "rest-a", restCase)
        XCTAssertEqual(taps, restCase.taps, "S-243: a late poll taps once, not once per boundary it skipped")

        let boundaries = (restCase.polls.map { $0 / restCase.interval }.max() ?? 0)
        XCTAssertLessThan(
            taps.count,
            boundaries,
            "S-243: the case passes several boundaries and the rule taps fewer times than that"
        )
    }

    // MARK: - S-244 the interval is lowered mid-rest

    func testS244ALoweredIntervalDoesNotRefireAPingedBoundary() throws {
        let restCase = try table.one("S-244")
        XCTAssertEqual(
            table.drive(WatchRestPing(), restId: "rest-a", restCase),
            restCase.taps,
            "S-244: the boundary already pinged is not pinged again when the interval drops past it"
        )
    }

    func testS244TheNextUnpingedBoundaryOfTheLoweredIntervalStillTaps() throws {
        let restCase = try table.one("S-244")
        let ping = WatchRestPing()
        let taps = table.drive(ping, restId: "rest-a", restCase)
        let last = try XCTUnwrap(taps.last, "the case pinged at least once")
        let lowered = restCase.interval / 2

        XCTAssertFalse(
            ping.isOwed(restId: "rest-a", elapsed: last + lowered / 2, interval: lowered),
            "S-244: a boundary already pinged stays quiet after the interval drops"
        )
        XCTAssertTrue(
            ping.isOwed(restId: "rest-a", elapsed: last + lowered, interval: lowered),
            "S-244: the lowered interval's next boundary taps"
        )
    }

    // MARK: - S-221 one tick per elapsed second

    func testS221ASecondPolledThreeTimesPingsOnce() throws {
        let restCase = try table.one("S-221")
        XCTAssertGreaterThan(
            restCase.polls.count,
            Set(restCase.polls).count,
            "the case polls one elapsed second more than once"
        )
        XCTAssertEqual(
            table.drive(WatchRestPing(), restId: "rest-a", restCase),
            restCase.taps,
            "S-221: a boundary polled three times pings once"
        )
    }

    // MARK: - S-222 the interval arrives mid-rest

    func testS222TheIntervalArrivingMidRestTapsFromItsNextBoundary() throws {
        let cases = table.named("S-222")
        XCTAssertEqual(cases.count, 2, "both readings of the arrival are in the table")
        for restCase in cases {
            XCTAssertEqual(
                table.drive(WatchRestPing(), restId: "rest-a", restCase),
                restCase.taps,
                "S-222: \(restCase.name)"
            )
        }
    }

    // MARK: - S-223 a large interval

    func testS223ALargeIntervalTapsAtItsFirstBoundary() throws {
        let restCase = try table.one("S-223")
        XCTAssertEqual(
            table.drive(WatchRestPing(), restId: "rest-a", restCase),
            restCase.taps,
            "S-223: an interval longer than the rest taps nothing until its first boundary"
        )
    }

    // MARK: - S-245 a rest ends, the next one starts clean

    func testS245ANewRestRowStartsFromZero() throws {
        let restCase = try table.one("S-241")
        let ping = WatchRestPing()
        let first = table.drive(ping, restId: "rest-a", restCase)
        let second = table.drive(ping, restId: "rest-b", restCase)
        XCTAssertEqual(first, restCase.taps, "S-245: the first rest pings at its boundaries")
        XCTAssertEqual(
            second,
            restCase.taps,
            "S-245: the next rest row pings at the same boundaries instead of inheriting what the last rest pinged"
        )
    }

    // MARK: - S-224 a closed rest is never evaluated

    func testS224AClosedRestIsNeverEvaluated() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let state = WatchLoggingState(engine: engine, clock: harness.clock.call)
        let interval = try table.one("S-241").interval
        let ping = WatchRestPing()

        try await state.log()
        harness.clock.advance(Double(interval))
        let open = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest)?.recordId, "the rest row")
        XCTAssertEqual(
            state.restElapsedSeconds(),
            interval,
            "the open rest's elapsed is what a tick reads"
        )
        XCTAssertTrue(
            ping.isOwed(restId: open, elapsed: state.restElapsedSeconds(), interval: interval),
            "a boundary with the rest open pings"
        )

        await state.endRest()
        harness.clock.advance(Double(interval))
        XCTAssertNil(state.restElapsedSeconds(), "a closed rest has no elapsed to consult")
        XCTAssertFalse(
            ping.isOwed(restId: open, elapsed: state.restElapsedSeconds(), interval: interval),
            "S-224: the rule is not consulted for a closed rest, so a tick after the rest ended pings nothing"
        )

        // A rule that never saw this rest open — a freshly drawn screen's —
        // pings nothing for it either, and neither does a tick with no rest row
        // at all: there is no open row to be owed a ping on.
        let fresh = WatchRestPing()
        XCTAssertFalse(
            fresh.isOwed(restId: open, elapsed: state.restElapsedSeconds(), interval: interval),
            "S-224: a closed rest pings nothing, however much of it the rule walked"
        )
        XCTAssertFalse(
            fresh.isOwed(restId: nil, elapsed: interval, interval: interval),
            "S-224: a tick with no rest row pings nothing"
        )
    }

    // MARK: - S-225 the ping is not the countdown path

    func testS225ThePingIsItsOwnEventAndNotACountdownAlert() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let state = WatchLoggingState(engine: engine, clock: harness.clock.call)
        let restCase = try table.one("S-241")

        try await state.log()
        let startedAt = harness.clock.now
        let restId = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest)?.recordId, "the rest row")
        let countdown = WatchTimerHaptics(engine)
        let haptics = RecordingHaptics()
        let ping = WatchRestPing()

        var alerts: [WatchTimerMilestone] = []
        for elapsed in restCase.polls {
            alerts += countdown.poll(now: startedAt.addingTimeInterval(Double(elapsed)))
            if ping.isOwed(restId: restId, elapsed: elapsed, interval: restCase.interval) {
                haptics.playRestPing()
            }
        }

        XCTAssertEqual(alerts, [], "S-225: a count-up rest is owed no countdown alert")
        XCTAssertEqual(haptics.milestones, [], "S-225: a rest ping is not a countdown milestone")
        XCTAssertEqual(
            haptics.restPings,
            restCase.taps.count,
            "S-225: the ping goes out on its own path, where the table says"
        )
    }

    // MARK: - S-247 the wrist stores the interval and reads the newest copy

    func testS247TheWristStoresTheIntervalItReceives() async throws {
        let harness = Harness()
        let preferences = WatchPhonePreferences(
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call
        )
        let wire = try Fixtures.json("fixtures/valid/preferences_down.json")
        let sent = try XCTUnwrap(
            ((wire["payload"] as? [String: Any])?["restPingSeconds"] as? NSNumber)?.intValue,
            "the valid fixture carries the interval"
        )
        let other = try table.one("S-241").interval
        XCTAssertNotEqual(sent, other, "the fixtures carry different intervals, so a stale copy is distinguishable")

        XCTAssertEqual(preferences.restPingSeconds, table.off, "before the first sync")
        let first = await preferences.applyPreferencesDown(wire)
        XCTAssertTrue(first.applied, "the fixture conforms to the schema")
        XCTAssertEqual(preferences.restPingSeconds, sent, "S-247: the wrist reads the copy it stored")

        var payload = try XCTUnwrap(wire["payload"] as? [String: Any])
        payload["restPingSeconds"] = other

        var stale = wire
        stale["messageId"] = "msg-preferences-stale"
        payload["generatedAt"] = "2026-09-25T08:00:00Z"
        stale["payload"] = payload
        _ = await preferences.applyPreferencesDown(stale)
        XCTAssertEqual(
            preferences.restPingSeconds,
            sent,
            "S-247: a copy generated earlier that arrives late does not replace the one that applies"
        )

        var newer = wire
        newer["messageId"] = "msg-preferences-newer"
        payload["generatedAt"] = "2026-09-25T10:00:00Z"
        newer["payload"] = payload
        _ = await preferences.applyPreferencesDown(newer)
        XCTAssertEqual(preferences.restPingSeconds, other, "S-247: a newer copy does apply")

        await preferences.restore()
        XCTAssertEqual(
            preferences.restPingSeconds,
            other,
            "S-247: the interval survives a relaunch, read back out of storage"
        )
    }

    func testS247TheRecordRoundTripsAndARowWithoutTheKeyReadsOff() async throws {
        let wire = try Fixtures.json("fixtures/valid/preferences_down.json")
        let sent = try XCTUnwrap(
            ((wire["payload"] as? [String: Any])?["restPingSeconds"] as? NSNumber)?.intValue,
            "the valid fixture carries the interval"
        )
        let record = WatchPreferencesRecord(
            recordId: "pref-1",
            recordedAt: instant("2026-10-08T10:00:00Z"),
            generatedAt: instant("2026-10-08T10:00:00Z"),
            effortRatingPrompt: true,
            restPingSeconds: sent
        )
        XCTAssertEqual(
            (record.toJson()["restPingSeconds"] as? NSNumber)?.intValue,
            sent,
            "S-247: the row carries the interval"
        )
        XCTAssertEqual(
            try WatchPreferencesRecord.fromJson(record.toJson()).restPingSeconds,
            sent,
            "S-247: the interval round-trips through the row's JSON"
        )
        XCTAssertEqual(
            record.withSequence(3).restPingSeconds,
            sent,
            "S-247: a re-sequenced copy keeps the interval"
        )

        // A row written before this feature carries no key at all.
        let legacy = try WatchPreferencesRecord.fromJson([
            "recordType": StoredWatchRecord.preferencesType,
            "recordId": "pref-legacy",
            "sessionId": "",
            "recordedAt": "2026-10-08T10:00:00Z",
            "sequence": 0,
            "generatedAt": "2026-10-08T10:00:00Z",
            "effortRatingPrompt": false,
        ])
        XCTAssertEqual(legacy.restPingSeconds, 0, "S-247: a row without the key reads the Off default")

        let harness = Harness()
        _ = await harness.store.append(.preferences(legacy))
        let preferences = WatchPhonePreferences(
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call
        )
        await preferences.restore()
        XCTAssertEqual(
            preferences.restPingSeconds,
            0,
            "S-247: a wrist restoring a pre-feature row reads Off, not an invented interval"
        )
    }

    func testS247AMalformedIntervalIsRefusedAndNothingIsStored() async throws {
        let harness = Harness()
        // No validator: the store's own guard has to hold even when nothing has
        // checked the bytes first.
        let preferences = WatchPhonePreferences(store: harness.store, clock: harness.clock.call)

        let wire = try Fixtures.json("fixtures/valid/preferences_down.json")
        let accepted = await preferences.applyPreferencesDown(wire)
        XCTAssertTrue(accepted.applied, "the well-formed copy is stored")
        let sent = preferences.restPingSeconds
        XCTAssertNotEqual(sent, table.off, "and it is a real interval")

        for path in [
            "fixtures/invalid/preferences_down_missing_rest_ping.json",
            "fixtures/invalid/preferences_down_negative_rest_ping.json",
            "fixtures/invalid/preferences_down_string_rest_ping.json",
        ] {
            let refused = await preferences.applyPreferencesDown(try Fixtures.json(path))
            XCTAssertFalse(refused.applied, "\(path) is refused, not stored")
        }

        var payload = try XCTUnwrap(wire["payload"] as? [String: Any])
        payload["restPingSeconds"] = true
        payload["generatedAt"] = "2026-10-08T10:00:00Z"
        var boolean = wire
        boolean["messageId"] = "msg-preferences-boolean-rest-ping"
        boolean["payload"] = payload
        let booleanRefused = await preferences.applyPreferencesDown(boolean)
        XCTAssertFalse(booleanRefused.applied, "a boolean is not a whole number of seconds")

        // The phone's validator refuses a JSON `90.0` as an integer too (F-10),
        // so the wrist has to refuse it without one.
        payload["restPingSeconds"] = 90.0
        var fraction = wire
        fraction["messageId"] = "msg-preferences-fraction-rest-ping"
        fraction["payload"] = payload
        let fractionRefused = await preferences.applyPreferencesDown(fraction)
        XCTAssertFalse(fractionRefused.applied, "90.0 is not a whole number of seconds")

        await preferences.restore()
        XCTAssertEqual(
            preferences.restPingSeconds,
            sent,
            "S-247: nothing malformed replaced the interval the wrist holds"
        )
    }

    // MARK: - the table itself

    func testTheTableCarriesACaseForEveryScenario() throws {
        XCTAssertEqual(
            table.cases.count,
            Set(table.cases.map(\.name)).count,
            "no case is listed twice"
        )
        for scenario in ["S-221", "S-222", "S-223", "S-241", "S-242", "S-243", "S-244"] {
            XCTAssertFalse(
                table.named(scenario).isEmpty,
                "the shared table carries a \(scenario) case"
            )
        }
    }
}
