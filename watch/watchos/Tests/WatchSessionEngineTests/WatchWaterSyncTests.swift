//
//  WatchWaterSyncTests.swift
//  WatchSessionEngineTests
//
//  Phase 3 of `docs/plans/2026-11-01-95-watch-water-bar-plan/`: the wrist asks
//  for the day's water on every sync (plan 95 D-28, plan 94 D-9), routes the
//  phone's `water_down` to its water state (D-29), counts the frame as a sync
//  reply, and keeps re-sending its taps until a receipt names them (D-22).
//
//  Fixture X: the calendar is Gregorian at UTC+3, so the local day turns at
//  21:00Z; the clock reads 2026-11-01T09:00:00Z (12:00 local) unless a test
//  says otherwise; the id factory yields `w-1`, `w-2`, … in call order.
//

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
    glasses: Int,
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

/// One row of the contract's `transportRequests`.
private func transportRequest(_ name: String) throws -> NSDictionary {
    let url = Fixtures.repositoryRoot
        .appendingPathComponent("watch/contract/watch_start_paths_contract.json")
    let contract = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let rows = try XCTUnwrap(contract?["transportRequests"] as? [String: Any])
    return try XCTUnwrap(rows[name] as? [String: Any], "no transportRequests.\(name)") as NSDictionary
}

/// A wrist wired the way the app wires it: one engine, its start paths, one
/// water state, and the orchestrator over a recording transport — handed the
/// water state unless `withWater` is false. Rebuilt over the same store to
/// simulate a relaunch.
private final class WaterWrist {
    let clock: TestClock
    let store: WatchSessionStore
    let transport: RecordingTransport
    private(set) var engine: WatchSessionEngine!
    private(set) var paths: WatchSessionStartPaths!
    private(set) var water: WatchWaterState!
    private(set) var orchestrator: WatchSyncOrchestrator!
    private(set) var emitted: [[String: Any]] = []
    private var ids = 0

    init(
        store: WatchSessionStore = InMemoryWatchSessionStore(),
        now: String = "2026-11-01T09:00:00Z",
        withWater: Bool = true,
        isPhoneReachable: Bool = false
    ) {
        self.clock = TestClock(at(now))
        self.store = store
        self.transport = RecordingTransport(isPhoneReachable: isPhoneReachable)
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
        paths = WatchSessionStartPaths(
            engine: engine,
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { UUID().uuidString }
        )
        water = WatchWaterState(
            engine: engine,
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            calendar: utcPlusThree()
        )
        orchestrator = WatchSyncOrchestrator(
            transport: transport,
            paths: paths,
            engine: engine,
            water: withWater ? water : nil
        )
    }

    /// The launch: the engine, then the start paths, then the water state.
    func launch() async {
        await engine.restore()
        await paths.restore()
        await water.restore()
    }

    /// "Tap at t": a stored tap with an explicit instant.
    @discardableResult
    func tap(_ change: WatchGlassChange, _ instant: String) async throws -> WatchObservationRecord {
        try await engine.logWaterGlass(change, loggedAt: at(instant))
    }

    /// The `observations_up` envelopes handed to the transport by a sync.
    var sentTaps: [[String: Any]] {
        transport.sent.filter { $0["type"] as? String == "observations_up" }
    }

    /// The `observations_up` envelopes the engine emitted when each tap was
    /// stored.
    var emittedTaps: [[String: Any]] {
        emitted.filter { $0["type"] as? String == "observations_up" }
    }

    func waterRowIds() async -> [String] {
        await store.readAll().water.map(\.recordId)
    }
}

final class WatchWaterSyncTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-water-sync-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    // MARK: - S-94b-11 (sync half) the receipt is lost and the tap is delivered again

    func testS94b11ASyncResendsTheTapThenTheAnswerSettlesIt() async throws {
        let x = WaterWrist()
        await x.launch()
        _ = await x.water.applyWaterDown(try waterFrame("2026-11-01T08:00:00Z", glasses: 2, ids: []))

        let stored = await x.water.press(.add)
        XCTAssertTrue(stored)
        XCTAssertEqual(x.water.glasses, 3)
        let firstEmission = try XCTUnwrap(x.emittedTaps.first)
        XCTAssertEqual(firstEmission["messageId"] as? String, "msg-w-1")

        // No receipt arrived: the next sync hands the same envelope over again.
        await x.orchestrator.sync()
        XCTAssertEqual(x.sentTaps.count, 1, "S-94b-11 the sync re-sends the one unreceipted tap")
        XCTAssertEqual(
            x.sentTaps.first as NSDictionary?,
            firstEmission as NSDictionary,
            "S-94b-11 the re-sent envelope is identical to the first emission, msg-w-1 included"
        )
        XCTAssertEqual(x.transport.requestedWantsWater, [true], "S-94b-11 the sync asks for the count")

        // The answer: the receipt and the frame, both through the orchestrator.
        let receiptApplied = try await x.orchestrator.receive(try receipt(["w-1"]))
        XCTAssertTrue(receiptApplied)
        let frameApplied = try await x.orchestrator.receive(
            try waterFrame("2026-11-01T09:01:00Z", glasses: 3, ids: ["w-1"])
        )
        XCTAssertTrue(frameApplied, "S-94b-11 the orchestrator routes the frame to the water state")
        XCTAssertEqual(x.water.glasses, 3, "S-94b-11 after the answer 3, not 4")
        XCTAssertTrue(x.engine.unconfirmedObservations.isEmpty)
        let rowsAfterAnswer = await x.waterRowIds()

        // The same answer again changes nothing and writes no water row.
        _ = try await x.orchestrator.receive(try receipt(["w-1"]))
        let repeated = try await x.orchestrator.receive(
            try waterFrame("2026-11-01T09:02:00Z", glasses: 3, ids: ["w-1"])
        )
        XCTAssertFalse(repeated, "S-94b-11 the repeated frame is not applied (D-24 (4))")
        let rowsAfterRepeat = await x.waterRowIds()
        XCTAssertEqual(rowsAfterRepeat, rowsAfterAnswer, "S-94b-11 the repeat writes no water row")
        XCTAssertEqual(x.water.glasses, 3)

        // A receipted tap is owed no more: the next sync hands nothing over.
        await x.orchestrator.sync()
        XCTAssertEqual(x.sentTaps.count, 1, "S-94b-11 a receipted tap is not re-sent")
    }

    // MARK: - S-94b-16 (sync half) relaunch with unsent taps

    func testS94b16ARelaunchedWristResendsItsTapsAndAsksForTheCount() async throws {
        let first = WaterWrist(store: FileWatchSessionStore(directory: directory))
        await first.launch()
        _ = await first.water.applyWaterDown(try waterFrame("2026-11-01T08:00:00Z", glasses: 2, ids: []))
        try await first.tap(.add, "2026-11-01T09:00:00Z")
        try await first.tap(.add, "2026-11-01T09:01:00Z")
        let firstEmissions = first.emittedTaps
        XCTAssertEqual(firstEmissions.map { $0["messageId"] as? String }, ["msg-w-1", "msg-w-2"])

        let relaunched = WaterWrist(store: FileWatchSessionStore(directory: directory))
        await relaunched.launch()
        XCTAssertEqual(relaunched.water.glasses, 4, "S-94b-16 the held 2 plus two unsent taps")
        XCTAssertEqual(relaunched.engine.unconfirmedObservations.count, 2)

        await relaunched.orchestrator.sync()

        XCTAssertEqual(
            relaunched.transport.requestedWantsWater,
            [true],
            "S-94b-16 the relaunched wrist asks for the count"
        )
        XCTAssertEqual(
            relaunched.sentTaps.map { $0["messageId"] as? String },
            ["msg-w-1", "msg-w-2"],
            "S-94b-16 the relaunched wrist re-sends under the first launch's message ids"
        )
        XCTAssertEqual(
            relaunched.sentTaps.map { $0 as NSDictionary },
            firstEmissions.map { $0 as NSDictionary },
            "S-94b-16 the re-sent envelopes equal the first launch's"
        )
    }

    // MARK: - S-94b-17 the wrist asks for the count

    func testS94b17EverySyncOfAWristWithAWaterStateAsksForTheCount() async throws {
        let x = WaterWrist()
        await x.launch()

        await x.orchestrator.sync()
        await x.orchestrator.catchUp(reachable: true)

        XCTAssertEqual(
            x.transport.requestedWantsWater,
            [true, true],
            "S-94b-17 a manual sync and a catch-up both ask for the count"
        )

        let without = WaterWrist(withWater: false)
        await without.launch()
        await without.orchestrator.sync()
        XCTAssertEqual(
            without.transport.requestedWantsWater,
            [false],
            "S-94b-17 a wrist without a water state does not ask"
        )
    }

    func testS94b17TheRequestFrameMatchesTheContractRows() throws {
        XCTAssertEqual(
            WatchTransportRequest.routinesFrame(since: nil, wantsWater: true) as NSDictionary,
            try transportRequest("routinesWater"),
            "S-94b-17 a wrist that asks sends exactly the routinesWater row"
        )
        XCTAssertEqual(
            WatchTransportRequest.routinesFrame(since: nil) as NSDictionary,
            try transportRequest("routines"),
            "S-94b-17 a wrist that does not ask omits the key rather than sending false"
        )
        XCTAssertEqual(
            WatchTransportRequest.routinesFrame(since: nil, wantsWater: false) as NSDictionary,
            try transportRequest("routines"),
            "S-94b-17 wantsWater false is omitted, never sent"
        )
        XCTAssertEqual(
            WatchTransportRequest.routinesFrame(since: nil, holdsBests: true, wantsWater: true) as NSDictionary,
            ["request": "routines", "holdsBests": true, "wantsWater": true] as NSDictionary,
            "S-94b-17 the two keys travel together"
        )
    }

    func testS94b17TheBridgeCarriesTheKeyOnlyForAWristThatAsks() async throws {
        // Over the real bridge, a wrist built with a water state puts the
        // routinesWater row on the wire as its first frame.
        let x = WaterWrist()
        let session = FakeWatchConnectivitySession()
        let bridge = WatchConnectivityBridge(session: session)
        let asking = WatchSyncOrchestrator(
            transport: bridge,
            paths: x.paths,
            engine: x.engine,
            water: x.water
        )
        await x.launch()
        await asking.sync()
        XCTAssertEqual(
            session.sent.first as NSDictionary?,
            try transportRequest("routinesWater"),
            "S-94b-17 the bridge sends wantsWater: true for a wrist that asks"
        )

        // The app's harness builds its orchestrator without water: its first
        // frame is the pre-94b request, byte for byte (I-9).
        let harness = WatchBridgeHarness()
        await harness.launch()
        await harness.orchestrator.sync()
        XCTAssertNil(
            harness.session.sent.first?["wantsWater"],
            "S-94b-17 a wrist without a water state sends no wantsWater"
        )
        XCTAssertEqual(
            harness.session.sent.first as NSDictionary?,
            try transportRequest("routines"),
            "S-94b-17 a wrist without a water state sends the routines row unchanged"
        )
    }

    // MARK: - S-94b-18 the frame is routed and closes a sync like any reply

    func testS94b18TheFrameIsRoutedToTheWaterState() async throws {
        let x = WaterWrist()
        await x.launch()
        let applied = try await x.orchestrator.receive(try Fixtures.json("fixtures/valid/water_down.json"))
        XCTAssertTrue(applied, "S-94b-18 a wrist with a water state applies the frame")
        XCTAssertEqual(x.water.glasses, 3, "S-94b-18 base 3 from the fixture")
        let rows = await x.waterRowIds()
        XCTAssertEqual(rows.count, 1)

        let without = WaterWrist(withWater: false)
        await without.launch()
        let ignored = try await without.orchestrator.receive(
            try Fixtures.json("fixtures/valid/water_down.json")
        )
        XCTAssertFalse(ignored, "S-94b-18 a wrist without a water state has no use for the frame")
        let noRows = await without.waterRowIds()
        XCTAssertTrue(noRows.isEmpty, "S-94b-18 nothing is stored without a water state")
    }

    func testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply() {
        XCTAssertTrue(WatchSyncProgressCopy.replyTypes.contains("water_down"))

        let t0 = at("2026-11-01T09:00:00Z")
        var progress = WatchSyncProgress(clock: { t0 })
        progress.begin(at: t0)
        progress.noteArrival(type: "routines_down", at: t0.addingTimeInterval(1))
        progress.noteArrival(type: "water_down", at: t0.addingTimeInterval(2.5))

        XCTAssertTrue(
            progress.isActive(at: t0.addingTimeInterval(4)),
            "S-94b-18 the water frame is the newest reply, so the sync is still running"
        )
        XCTAssertFalse(
            progress.isActive(at: t0.addingTimeInterval(4.6)),
            "S-94b-18 quiet after the water frame: the sync is finished"
        )

        // S-94b-18a (plan 96 D-46): the straggler lands after the quiet end
        // and inside the cap, so only `noteArrival`'s guard keeps it out.
        progress.noteArrival(type: "water_down", at: t0.addingTimeInterval(5))
        XCTAssertFalse(
            progress.isActive(at: t0.addingTimeInterval(5)),
            "S-94b-18a a water frame after a tap never revives a finished sync"
        )
        XCTAssertFalse(progress.isActive(at: t0.addingTimeInterval(6)))
    }

    // MARK: - S-94b-19 unsent taps count in the waiting line (Q1, D-30)

    func testS94b19UnsentTapsCountInTheWaitingLine() async throws {
        let x = WaterWrist()
        // A rest window the wrist stored and the phone has not acknowledged.
        _ = await x.store.append(
            .observation(
                WatchObservationRecord(
                    recordId: "rest-1",
                    sessionId: "w9",
                    recordedAt: x.clock.now,
                    kind: WatchObservationKind.rest,
                    payload: ["entryId": "rest-1", "eventId": "rest-1", "kind": WatchObservationKind.rest]
                )
            )
        )
        await x.launch()
        XCTAssertEqual(x.engine.unconfirmedObservations.count, 1, "S-94b-19 the rest window is unconfirmed")

        try await x.engine.logWaterGlass(.add)
        try await x.engine.logWaterGlass(.remove)

        XCTAssertEqual(
            deriveSyncNotice(
                pending: x.engine.unconfirmedObservations,
                reachability: .unreachable,
                now: x.clock.now
            ),
            "2 entries waiting for your phone",
            "S-94b-19 each unsent tap is one entry; the rest window is not counted"
        )

        try await x.engine.applyMessage(try receipt(["w-1"]))
        XCTAssertEqual(
            deriveSyncNotice(
                pending: x.engine.unconfirmedObservations,
                reachability: .unreachable,
                now: x.clock.now
            ),
            "1 entry waiting for your phone",
            "S-94b-19 a receipt takes its tap out of the line"
        )

        XCTAssertNil(
            deriveSyncNotice(
                pending: x.engine.unconfirmedObservations,
                reachability: .reachable,
                now: x.clock.now
            ),
            "S-94b-19 a reachable phone inside the grace says nothing"
        )
    }

    // MARK: - S-94b-20 a press while the phone is out of reach

    func testS94b20APressWhileThePhoneIsOutOfReach() async throws {
        let x = WaterWrist(isPhoneReachable: false)
        await x.launch()
        _ = await x.water.applyWaterDown(try waterFrame("2026-11-01T08:00:00Z", glasses: 2, ids: []))

        let stored = await x.water.press(.add)

        XCTAssertTrue(stored)
        XCTAssertEqual(x.water.glasses, 3, "S-94b-20 the count moves at once")
        XCTAssertEqual(x.emittedTaps.count, 1, "S-94b-20 one emission")
        XCTAssertEqual(x.engine.unconfirmedObservations.count, 1)

        await x.orchestrator.sync()
        XCTAssertEqual(
            x.sentTaps.map { $0["messageId"] as? String },
            ["msg-w-1"],
            "S-94b-20 the sync still hands the tap over"
        )
        XCTAssertEqual(x.transport.requestedWantsWater, [true])
        XCTAssertEqual(x.water.glasses, 3)
    }
}
