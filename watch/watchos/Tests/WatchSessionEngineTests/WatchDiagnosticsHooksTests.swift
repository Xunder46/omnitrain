//
//  WatchDiagnosticsHooksTests.swift
//  WatchSessionEngineTests
//
//  Plan 142 P2 — the diagnostics hooks in the bridge, the engine and the
//  platform workout (D-14206, D-14207, D-14208), scenarios S-14206..S-14211.
//  The hooks are observation only: S-14211 holds that the send outcomes, the
//  reported errors and the engine state are the same with no log, with a log
//  over a directory that cannot be created, and with a working log.
//

import XCTest

@testable import WatchSessionEngine

private struct SendRefused: Error, CustomStringConvertible {
    let description = "the platform refused the frame"
}

// Internal, not private: the log records the error's NSError domain, and a
// private type's domain carries an un-pinnable "(unknown context at $…)".
struct HandlerFailed: Error, CustomStringConvertible {
    let description = "handler refused the frame"
}

/// The health store as a script, over the seam `WatchPlatformWorkout` holds
/// (the `WatchContinueRecoveredWorkoutTests` idiom).
private final class ScriptedPlatformWorkoutStore: WatchPlatformWorkoutStore {
    private let lock = NSLock()
    private var log: [String] = []
    private var stranded: [String]
    private var savings: [Bool] = []
    private var begunTypes: [String] = []
    private var begunOutdoors: [Bool] = []

    /// The name an adopting store hands back, or nil when it cannot adopt.
    let adopts: String?

    init(inProgress: [String] = [], adopts: String? = nil) {
        self.stranded = inProgress
        self.adopts = adopts
    }

    var calls: [String] { withState { log } }
    var endSavings: [Bool] { withState { savings } }
    var begun: [String] { withState { begunTypes } }

    func begin(_ activityType: String) async {
        withState { log.append("begin") }
    }

    func begin(_ activityType: String, outdoors: Bool) async {
        withState {
            log.append("begin")
            begunTypes.append(activityType)
            begunOutdoors.append(outdoors)
        }
    }

    func end() async {
        withState { log.append("end") }
    }

    func end(saving: Bool) async {
        withState {
            log.append("end")
            savings.append(saving)
            if !stranded.isEmpty { stranded.removeFirst() }
        }
    }

    func inProgressActivityTypes() async -> [String] {
        withState {
            log.append("inProgressActivityTypes")
            return stranded
        }
    }

    func adoptInProgress() async -> String? {
        withState {
            log.append("adoptInProgress")
            return adopts
        }
    }

    private func withState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class WatchDiagnosticsHooksTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-diagnostics-hooks-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    /// A log over a directory that cannot be created: a regular file sits where
    /// the parent directory should be (the S-14204 idiom), cleaned up on exit.
    private func unwritableLog() -> WatchDiagnosticsLog {
        let block = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "watch-diagnostics-hooks-block-\(UUID().uuidString)", isDirectory: false
            )
        _ = FileManager.default.createFile(atPath: block.path, contents: Data())
        addTeardownBlock { try? FileManager.default.removeItem(at: block) }
        return WatchDiagnosticsLog(directory: block.appendingPathComponent("sub"))
    }

    // MARK: - S-14206 the bridge records what happened to each sent frame

    func testS14206SendOutcomesAreRecordedFrameSent() async {
        let clock = TestClock(testInstant())
        let log = WatchDiagnosticsLog(directory: directory, clock: clock.call)
        let session = FakeWatchConnectivitySession()
        let bridge = WatchConnectivityBridge(session: session, diagnostics: log)

        await bridge.send(["type": "timer_state", "sessionId": "s-1", "payload": ["timers": [:]]])
        let live = log.events().filter { $0.kind == "frame_sent" }
        XCTAssertEqual(live.count, 1, "S-14206 exactly the live frame's line")
        XCTAssertEqual(live.first?.detail, "timer_state live")
        XCTAssertEqual(live.first?.session, "s-1")

        session.sendError = SendRefused()
        await bridge.send([
            "type": "observations_up", "sessionId": "s-2", "payload": ["events": []],
        ])
        let queued = log.events().filter { $0.kind == "frame_sent" }
        XCTAssertEqual(queued.count, 2, "S-14206 the durable frame's queued line follows")
        XCTAssertEqual(queued.last?.detail, "observations_up queued")
        XCTAssertEqual(queued.last?.session, "s-2")

        await bridge.send(["type": "timer_state", "sessionId": "s-3", "payload": ["timers": [:]]])
        let failed = log.events().filter { $0.kind == "frame_sent" }
        XCTAssertEqual(failed.count, 3, "S-14206 the non-durable frame's failed line follows")
        XCTAssertEqual(
            failed.last?.detail, "timer_state failed: the platform refused the frame"
        )
        XCTAssertEqual(failed.last?.session, "s-3")

        session.sendError = nil
        await bridge.send(["type": "timer_state", "sessionId": "s-4", "payload": NSNull()])
        let notSent = log.events().filter { $0.kind == "frame_not_sent" }
        XCTAssertEqual(notSent.count, 1, "S-14206 a frame the radio cannot carry is frame_not_sent")
        XCTAssertEqual(notSent.first?.session, "s-4")
        XCTAssertTrue(
            notSent.first?.detail?.hasPrefix("timer_state ") ?? false,
            "S-14206 the detail names the frame, got \(notSent.first?.detail ?? "nil")"
        )
    }

    // MARK: - S-14207 the chatty energy_live is coalesced to one line a minute

    func testS14207LiveEnergyLiveIsCoalescedToOneLineAMinute() async {
        let clock = TestClock(testInstant())
        let log = WatchDiagnosticsLog(directory: directory, clock: clock.call)
        let session = FakeWatchConnectivitySession()
        let bridge = WatchConnectivityBridge(session: session, diagnostics: log)

        func energyFrame(_ sessionId: String) -> [String: Any] {
            [
                "type": "energy_live",
                "sessionId": sessionId,
                "payload": ["activeEnergyKcal": 12, "at": utcIso(clock.now)],
            ]
        }

        for index in 1...30 {
            await bridge.send(energyFrame("s-e\(index)"))
            clock.advance(0.5)
        }
        let coalesced = log.events().filter { $0.kind == "frame_sent" }
        XCTAssertEqual(coalesced.count, 1, "S-14207 thirty sends, one line")
        XCTAssertEqual(coalesced.first?.detail, "energy_live live x1")
        XCTAssertEqual(session.sent.count, 30, "S-14207 the frames all went out")

        clock.advance(61)
        await bridge.send(energyFrame("s-e31"))
        let after = log.events().filter { $0.kind == "frame_sent" }
        XCTAssertEqual(after.count, 2, "S-14207 a minute later the held count lands")
        XCTAssertEqual(after.last?.detail, "energy_live live x30")
    }

    /// S-14207 the arriving side of the chatty energy_live coalesces too: one
    /// line a minute, and a non-chatty type in the same window is on its own.
    func testS14207LiveEnergyLiveArrivingIsCoalescedToo() async {
        let clock = TestClock(testInstant())
        let log = WatchDiagnosticsLog(directory: directory, clock: clock.call)
        let session = FakeWatchConnectivitySession()
        let bridge = WatchConnectivityBridge(session: session, diagnostics: log)
        await bridge.onIncoming { _ in }

        func energyFrame(_ sessionId: String) -> [String: Any] {
            [
                "type": "energy_live",
                "sessionId": sessionId,
                "payload": ["activeEnergyKcal": 12, "at": utcIso(clock.now)],
            ]
        }

        for index in 1...30 {
            await session.deliver(energyFrame("s-r\(index)"))
            clock.advance(0.5)
        }

        await session.deliver(["type": "session_lifecycle", "sessionId": "s-l1", "payload": ["status": "active"]])
        await session.deliver(["type": "session_lifecycle", "sessionId": "s-l2", "payload": ["status": "active"]])

        clock.advance(61)
        await session.deliver(energyFrame("s-r31"))

        let received = log.events().filter {
            $0.kind == "frame_received" && $0.detail?.hasPrefix("energy_live") == true
        }
        XCTAssertEqual(received.count, 2, "S-14207 thirty arrivals held to two lines")
        XCTAssertEqual(
            received.map(\.detail), ["energy_live x1", "energy_live x30"],
            "S-14207 the arriving frames' coalesced counts"
        )
        let lifecycle = log.events().filter {
            $0.kind == "frame_received" && $0.detail == "session_lifecycle"
        }
        XCTAssertEqual(
            lifecycle.count, 2,
            "S-14207 a non-chatty type in the same window is recorded on its own"
        )
    }

    func testS14207AFailedEnergyLiveIsNotCoalesced() async {
        let clock = TestClock(testInstant())
        let log = WatchDiagnosticsLog(directory: directory, clock: clock.call)
        let session = FakeWatchConnectivitySession()
        session.sendError = SendRefused()
        let bridge = WatchConnectivityBridge(session: session, diagnostics: log)

        func energyFrame(_ sessionId: String) -> [String: Any] {
            [
                "type": "energy_live",
                "sessionId": sessionId,
                "payload": ["activeEnergyKcal": 12, "at": utcIso(clock.now)],
            ]
        }

        await bridge.send(energyFrame("s-f1"))
        clock.advance(0.5)
        await bridge.send(energyFrame("s-f2"))

        let failed = log.events().filter { $0.kind == "frame_sent" }
        XCTAssertEqual(failed.count, 2, "S-14207 a non-live outcome is recorded on its own line")
        XCTAssertEqual(
            failed.map(\.detail),
            [
                "energy_live failed: the platform refused the frame",
                "energy_live failed: the platform refused the frame",
            ]
        )
    }

    // MARK: - S-14208 the bridge records an arriving frame and a handler failure

    func testS14208ADeliveredFrameIsRecordedAndItsHandlerFailureToo() async {
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        let session = FakeWatchConnectivitySession()
        var reported: [String] = []
        let bridge = WatchConnectivityBridge(
            session: session,
            onFailure: { reported.append(String(describing: $0)) },
            diagnostics: log
        )
        await bridge.onIncoming { _ in }

        let frame: [String: Any] = [
            "type": "session_snapshot", "sessionId": "s-9", "payload": ["status": "active"],
        ]
        await session.deliver(frame)

        let received = log.events().filter { $0.kind == "frame_received" }
        XCTAssertEqual(received.count, 1, "S-14208 the arrival is recorded")
        XCTAssertEqual(received.first?.detail, "session_snapshot")
        XCTAssertEqual(received.first?.session, "s-9")
        XCTAssertEqual(reported.count, 0, "S-14208 an accepting handler reports nothing")

        await bridge.onIncoming { _ in throw HandlerFailed() }
        await session.deliver(frame)

        let receivedAfterThrow = log.events().filter { $0.kind == "frame_received" }
        let failures = log.events().filter { $0.kind == "frame_handler_failed" }
        XCTAssertEqual(failures.count, 1, "S-14208 the handler's throw is recorded")
        XCTAssertEqual(
            failures.first?.detail,
            "session_snapshot WatchSessionEngineTests.HandlerFailed 1",
            "S-14208 the detail is the error's domain and code (D-14211), got \(failures.first?.detail ?? "nil")"
        )
        XCTAssertEqual(failures.first?.session, "s-9")
        XCTAssertEqual(receivedAfterThrow.count, 2, "S-14208 the second arrival is recorded too")
        XCTAssertEqual(reported, ["handler refused the frame"], "S-14208 the throw is still reported")
    }

    // MARK: - S-14209 the engine records what its validator refused

    func testS14209ARefusedIncomingFrameIsRecordedFrameRejectedOnce() async throws {
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        let engine = WatchSessionEngine(
            store: InMemoryWatchSessionStore(),
            validator: Harness.validator(),
            clock: TestClock(testInstant()).call,
            diagnostics: log
        )
        await engine.restore()
        let before = await engine.storedSession()

        let refused: [String: Any] = [
            "protocolVersion": 2,
            "type": "observations_up",
            "sessionId": "s-phone",
            "payload": ["events": []],
        ]
        do {
            _ = try await engine.applyMessage(refused)
            XCTFail("a frame the watch cannot read is refused")
        } catch let rejected as WatchEmissionRejected {
            XCTAssertEqual(
                rejected.rejections.map(\.code), ["unsupported_protocol_version"],
                "S-14209 the same rejection the unhooked engine throws"
            )
        }

        let events = log.events().filter { $0.kind == "frame_rejected" }
        XCTAssertEqual(events.count, 1, "S-14209 exactly one frame_rejected")
        XCTAssertEqual(events.first?.session, "s-phone")
        XCTAssertTrue(
            events.first?.detail?.hasPrefix("observations_up unsupported_protocol_version") ?? false,
            "S-14209 the detail names the type and the rejection, got \(events.first?.detail ?? "nil")"
        )
        let afterSession = await engine.storedSession()?.sessionId
        XCTAssertEqual(afterSession, before?.sessionId, "S-14209 nothing changed")
    }

    func testS14209ARefusedOwnFrameIsRecordedFrameNotSent() async {
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        // A validator with no schema documents refuses every frame whole, so the
        // engine's own lifecycle and snapshot are refused at the emit side.
        let engine = WatchSessionEngine(
            store: InMemoryWatchSessionStore(),
            validator: SyncProtocolValidator(schemaDocuments: [:]),
            clock: TestClock(testInstant()).call,
            diagnostics: log
        )
        await engine.restore()
        let session = await engine.createSession(modality: nil)

        XCTAssertNotNil(session, "S-14209 the session still exists")
        let notSent = log.events().filter { $0.kind == "frame_not_sent" }
        XCTAssertEqual(notSent.count, 2, "S-14209 the lifecycle and the snapshot are both refused")
        XCTAssertEqual(
            notSent.compactMap { $0.detail?.split(separator: " ").first.map(String.init) },
            ["session_lifecycle", "session_snapshot"],
            "S-14209 the refused frames' types, in order"
        )
    }

    // MARK: - S-14216A the log never records a value the user typed (D-14211)

    /// S-14216A an incoming frame refused by a numeric bound: the recorded
    /// detail names the code and the path only — never the value the user
    /// typed, never the schema's `found` wording. The engine still refuses.
    func testS14216ARefusedIncomingFrameNeverRecordsThePayloadValue() async throws {
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        let engine = WatchSessionEngine(
            store: InMemoryWatchSessionStore(),
            validator: Harness.validator(),
            clock: TestClock(testInstant()).call,
            diagnostics: log
        )
        await engine.restore()
        let before = await engine.storedSession()

        // The shape of `fixtures/invalid/observations_up_rating_out_of_range.json`,
        // with the value inflated far past the schema's bound of 5
        // (envelope.schema.json's rating.maximum).
        let refused: [String: Any] = [
            "protocolVersion": 1,
            "messageId": "msg-obs-rating-14216",
            "sessionId": "s-phone",
            "type": "observations_up",
            "origin": "watch",
            "sentAt": "2026-09-25T10:55:20Z",
            "payload": ["events": [[
                "eventId": "evt-rating-14216",
                "entryId": "e-rating-14216",
                "kind": "effort_rating",
                "loggedAt": "2026-09-25T10:55:20Z",
                "rating": 97531,
            ]]],
        ]
        do {
            _ = try await engine.applyMessage(refused)
            XCTFail("a frame over the schema's bound is refused")
        } catch let rejected as WatchEmissionRejected {
            XCTAssertEqual(
                rejected.rejections.first?.code, "constraint_violation",
                "S-14216A the bound is the refusal, got \(rejected.rejections)"
            )
            let events = log.events().filter { $0.kind == "frame_rejected" }
            XCTAssertEqual(events.count, 1, "S-14216A exactly one frame_rejected")
            XCTAssertEqual(events.first?.session, "s-phone")
            let detail = try XCTUnwrap(events.first?.detail, "S-14216A the refusal was recorded")
            XCTAssertTrue(
                detail.contains("constraint_violation at "),
                "S-14216A the detail names the code, got \(detail)"
            )
            XCTAssertTrue(
                detail.contains(try XCTUnwrap(rejected.rejections.first?.path)),
                "S-14216A the detail names the path, got \(detail)"
            )
            XCTAssertFalse(
                detail.contains("97531"),
                "S-14216A the value the user typed is never recorded, got \(detail)"
            )
            XCTAssertFalse(
                detail.contains("found"),
                "S-14216A the schema's wording is not recorded, got \(detail)"
            )
        }

        let afterSession = await engine.storedSession()?.sessionId
        XCTAssertEqual(afterSession, before?.sessionId, "S-14216A nothing changed")
    }

    /// S-14216A a handler whose throw is itself a refusal: the recorded detail
    /// is the type and the rejections' codes and paths only.
    func testS14216AHandlerThatThrowsARefusalRecordsCodesAndPathsOnly() async {
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        let session = FakeWatchConnectivitySession()
        let bridge = WatchConnectivityBridge(session: session, diagnostics: log)
        await bridge.onIncoming { _ in
            throw WatchEmissionRejected(
                message: "expected at most 5, found 97531",
                rejections: [SyncProtocolRejection(
                    code: "constraint_violation",
                    path: "payload.entries[0].rating",
                    message: "expected at most 5, found 97531"
                )]
            )
        }

        await session.deliver([
            "type": "session_snapshot", "sessionId": "s-14216", "payload": ["status": "active"],
        ])

        let failures = log.events().filter { $0.kind == "frame_handler_failed" }
        XCTAssertEqual(failures.count, 1, "S-14216A the handler's refusal is recorded once")
        XCTAssertEqual(
            failures.first?.detail,
            "session_snapshot constraint_violation at payload.entries[0].rating",
            "S-14216A the codes and paths only, got \(failures.first?.detail ?? "nil")"
        )
        XCTAssertFalse(
            failures.first?.detail?.contains("97531") ?? true,
            "S-14216A the refused value is never recorded"
        )
        XCTAssertFalse(
            failures.first?.detail?.contains("found") ?? true,
            "S-14216A the schema's wording is not recorded"
        )
    }

    // MARK: - S-14210 the platform workout records its life

    func testS14210ThePlatformWorkoutRecordsItsLife() async throws {
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: "sports")

        let store = ScriptedPlatformWorkoutStore()
        let platform = WatchPlatformWorkout(store: store, diagnostics: log)
        _ = await platform.start(session)
        XCTAssertEqual(store.begun, ["other"], "S-14210 sports registers as the generic type")

        await platform.end(saving: true)
        XCTAssertEqual(store.endSavings, [true], "S-14210 the end reached the store saving")

        let adopting = ScriptedPlatformWorkoutStore(adopts: "running")
        let adopted = WatchPlatformWorkout(store: adopting, diagnostics: log)
        let continued = await adopted.continueInProgress()
        XCTAssertTrue(continued, "S-14210 an adopting store continues the workout")
        XCTAssertNotNil(adopted.running, "S-14210 the adopted workout is the one running")

        let stranded = ScriptedPlatformWorkoutStore(inProgress: ["walking"])
        let recovering = WatchPlatformWorkout(store: stranded, diagnostics: log)
        let ended = await recovering.recoverInProgress(saving: false)
        XCTAssertEqual(ended, ["walking"], "S-14210 the stranded workout was recovered")
        XCTAssertEqual(stranded.endSavings, [false], "S-14210 discarded")

        let events = log.events()
        XCTAssertEqual(
            events.map(\.kind),
            ["workout_begin", "workout_end", "workout_adopted", "workout_recovered"],
            "S-14210 the four hook events, in order"
        )
        XCTAssertEqual(events[0].session, harness.sessionId, "S-14210 the begin names the session")
        XCTAssertEqual(events[0].detail, "other", "S-14210 the begin names the workout type")
        XCTAssertEqual(events[1].detail, "saving", "S-14210 the end says saving")
        XCTAssertEqual(events[2].detail, "running", "S-14210 the adoption names the workout")
        XCTAssertEqual(
            events[3].detail, "walking discarded", "S-14210 the recovery names type and outcome"
        )
    }

    // MARK: - S-14211 observation only: the hooks change nothing

    private struct SendOutcome {
        var sent: [[String: Any]]
        var queued: [[String: Any]]
        var reported: [String]
    }

    /// The S-14206 send fixtures over one bridge, with whatever log it was given.
    private func runSendFixtures(diagnostics: WatchDiagnosticsLog?) async -> SendOutcome {
        let session = FakeWatchConnectivitySession()
        var reported: [String] = []
        let bridge = WatchConnectivityBridge(
            session: session,
            onFailure: { reported.append(String(describing: $0)) },
            diagnostics: diagnostics
        )

        await bridge.send(["type": "timer_state", "sessionId": "s-1", "payload": ["timers": [:]]])
        session.sendError = SendRefused()
        await bridge.send([
            "type": "observations_up", "sessionId": "s-2", "payload": ["events": []],
        ])
        await bridge.send(["type": "timer_state", "sessionId": "s-3", "payload": ["timers": [:]]])
        session.sendError = nil
        await bridge.send(["type": "timer_state", "sessionId": "s-4", "payload": NSNull()])

        return SendOutcome(sent: session.sent, queued: session.queued, reported: reported)
    }

    /// The S-14209 incoming fixture over one engine, with whatever log it was
    /// given: the refusal and the state it left.
    private struct EngineOutcome {
        var reportedError: String?
        var sessionIdBefore: String?
        var sessionIdAfter: String?
    }

    private func runEngineFixture(diagnostics: WatchDiagnosticsLog?) async throws -> EngineOutcome {
        let engine = WatchSessionEngine(
            store: InMemoryWatchSessionStore(),
            validator: Harness.validator(),
            clock: TestClock(testInstant()).call,
            diagnostics: diagnostics
        )
        await engine.restore()
        let before = await engine.storedSession()?.sessionId
        var reportedError: String?
        do {
            _ = try await engine.applyMessage([
                "protocolVersion": 2,
                "type": "observations_up",
                "sessionId": "s-phone",
                "payload": ["events": []],
            ])
            XCTFail("the frame is refused with or without a log")
        } catch {
            reportedError = String(describing: error)
        }
        let after = await engine.storedSession()?.sessionId
        return EngineOutcome(
            reportedError: reportedError, sessionIdBefore: before, sessionIdAfter: after
        )
    }

    func testS14211TheHooksChangeNothingAboutWhatHappens() async throws {
        let bare = await runSendFixtures(diagnostics: nil)
        let unwritable = await runSendFixtures(diagnostics: unwritableLog())
        let working = await runSendFixtures(
            diagnostics: WatchDiagnosticsLog(directory: directory, clock: { Date() })
        )

        for outcome in [("unwritable", unwritable), ("working", working)] {
            XCTAssertEqual(
                outcome.1.sent.map(NSDictionary.init) == bare.sent.map(NSDictionary.init), true,
                "S-14211 the \(outcome.0) log's sends are the bare run's sends"
            )
            XCTAssertEqual(
                outcome.1.queued.map(NSDictionary.init) == bare.queued.map(NSDictionary.init), true,
                "S-14211 the \(outcome.0) log's queues are the bare run's queues"
            )
            XCTAssertEqual(
                outcome.1.reported == bare.reported, true,
                "S-14211 the \(outcome.0) log's reported errors are the bare run's"
            )
        }
        XCTAssertEqual(bare.sent.count, 1, "S-14211 only the first frame went out live")
        XCTAssertEqual(bare.queued.count, 1, "S-14211 only the durable frame was queued")
        XCTAssertEqual(bare.reported.count, 2, "S-14211 two failures were reported")
        XCTAssertFalse(bare.reported.isEmpty, "S-14211 the fixtures do exercise the failure paths")

        let bareEngine = try await runEngineFixture(diagnostics: nil)
        let unwritableEngine = try await runEngineFixture(diagnostics: unwritableLog())
        let workingEngine = try await runEngineFixture(
            diagnostics: WatchDiagnosticsLog(directory: directory, clock: { Date() })
        )
        for outcome in [("unwritable", unwritableEngine), ("working", workingEngine)] {
            XCTAssertEqual(
                outcome.1.reportedError, bareEngine.reportedError,
                "S-14211 the \(outcome.0) log's thrown error is the bare run's"
            )
            XCTAssertEqual(
                outcome.1.sessionIdBefore, bareEngine.sessionIdBefore,
                "S-14211 the \(outcome.0) log's session before is the bare run's"
            )
            XCTAssertEqual(
                outcome.1.sessionIdAfter, bareEngine.sessionIdAfter,
                "S-14211 the \(outcome.0) log's session after is the bare run's"
            )
        }
        XCTAssertNotNil(bareEngine.reportedError, "S-14211 the engine fixture still refuses")
        XCTAssertNil(bareEngine.sessionIdBefore, "S-14211 no session existed")
        XCTAssertNil(bareEngine.sessionIdAfter, "S-14211 and a refused frame created none")
    }
}
