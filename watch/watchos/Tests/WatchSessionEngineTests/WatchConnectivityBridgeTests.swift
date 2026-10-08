//
//  WatchConnectivityBridgeTests.swift
//  WatchSessionEngineTests
//
//  S-102 to S-111, S-112 and S-113 of
//  `docs/plans/2026-10-04-14-watch-shell-bridge-plan/2026-10-04-14-watch-shell-bridge-plan.md`,
//  and D-10's picker rows: the wrist's radio, exercised against a fake session.
//
//  Two sources are read from the repository rather than restated here: the
//  protocol fixtures and schemas (so "conformant" is the schema's verdict) and
//  `watch/contract/watch_start_paths_contract.json`, which the Dart suite is
//  held to as well. A request frame that changes on one platform therefore fails
//  the other's tests.
//
//  The bridge is the only thing under test: the orchestrator, the start paths and
//  the engine are the real ones, so what a frame carries is what the wrist would
//  really send.
//

import XCTest

@testable import WatchSessionEngine

/// A wrist with a radio: the start harness's objects, plus the bridge over a
/// fake session and the failure hook a host would report through.
final class WatchBridgeHarness {
    let clock: TestClock
    let store: WatchSessionStore
    let sessionId: String
    let session: FakeWatchConnectivitySession
    private(set) var failures: [Error] = []
    private(set) var emitted: [[String: Any]] = []
    private var ids = 0

    private(set) var engine: WatchSessionEngine!
    private(set) var paths: WatchSessionStartPaths!
    private(set) var preferences: WatchPhonePreferences!
    private(set) var bridge: WatchConnectivityBridge!
    private(set) var orchestrator: WatchSyncOrchestrator!

    init(
        store: WatchSessionStore = InMemoryWatchSessionStore(),
        sessionId: String = "s-watch-1",
        isPhoneReachable: Bool = false
    ) {
        self.clock = TestClock(testInstant())
        self.store = store
        self.sessionId = sessionId
        self.session = FakeWatchConnectivitySession(isPhoneReachable: isPhoneReachable)
        build()
    }

    /// A wrist that has restored: engine first, then the start paths, exactly as
    /// a launch would.
    @discardableResult
    func launch() async -> WatchBridgeHarness {
        build()
        await engine.restore()
        await paths.restore()
        await preferences.restore()
        return self
    }

    private func build() {
        engine = WatchSessionEngine(
            store: store,
            onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.ids += 1
                return "rec-\(self.ids)"
            },
            sessionIdFactory: { [weak self] in self?.sessionId ?? "s-watch-1" }
        )
        paths = WatchSessionStartPaths(
            engine: engine,
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.ids += 1
                return "cat-\(self.ids)"
            }
        )
        preferences = WatchPhonePreferences(
            store: store,
            validator: Harness.validator(),
            clock: clock.call
        )
        bridge = WatchConnectivityBridge(
            session: session,
            onFailure: { [weak self] error in self?.failures.append(error) }
        )
        orchestrator = WatchSyncOrchestrator(
            transport: bridge,
            paths: paths,
            engine: engine,
            preferences: preferences
        )
        bridge.onIncoming { [weak self] frame in
            guard let self else { return }
            _ = try await self.orchestrator.receive(frame)
        }
    }

    /// What the phone sent, applied the way a launch would: through the bridge,
    /// so the arrival path is exercised rather than bypassed.
    func deliver(_ frame: [String: Any]) async {
        await session.deliver(frame)
    }

    /// Every frame the bridge handed the session, of `type`.
    func sent(_ type: String) -> [[String: Any]] {
        session.sent.filter { $0["type"] as? String == type }
    }

    /// Every message of `type` the engine emitted, in order.
    func emitted(_ type: String) -> [[String: Any]] {
        emitted.filter { $0["type"] as? String == type }
    }
}

private enum BridgeFixtureError: Error {
    case malformed(String)
}

private func bridgeContract() throws -> [String: Any] {
    let url = Fixtures.repositoryRoot
        .appendingPathComponent("watch/contract/watch_start_paths_contract.json")
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BridgeFixtureError.malformed("watch_start_paths_contract.json")
    }
    return object
}

private func bridgeObject(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else {
        throw BridgeFixtureError.malformed("expected an object, found \(String(describing: value))")
    }
    return value
}

private func bridgeObjects(_ value: Any?) throws -> [[String: Any]] {
    guard let value = value as? [[String: Any]] else {
        throw BridgeFixtureError.malformed("expected an array of objects")
    }
    return value
}

/// The phone's answer to a session-less wrist's catch-up: its own
/// `session_snapshot`, carrying the session and the entries it asserts (S-186).
private func bridgeSnapshotFrame(
    sessionId: String,
    messageId: String,
    exercises: [[String: Any]],
    entries: [[String: Any]] = [],
    revision: Int = 4
) -> [String: Any] {
    [
        "protocolVersion": SyncProtocolValidator.protocolVersion,
        "messageId": messageId,
        "sessionId": sessionId,
        "type": "session_snapshot",
        "origin": "phone",
        "sentAt": "2026-07-13T06:30:00Z",
        "payload": [
            "sessionId": sessionId,
            "revision": revision,
            "status": WatchSessionStatus.active,
            "currentExerciseIndex": 0,
            "exercises": exercises,
            "entries": entries,
            "timers": [String: Any](),
        ] as [String: Any],
    ]
}

/// A value the radio cannot carry: not a property-list type at all.
private struct NotAPlistValue {
    let text = "nope"
}

final class WatchConnectivityBridgeTests: XCTestCase {

    // MARK: - S-102 a first sync asks for routines with no `since`

    func testS102FirstSyncAsksForRoutinesWithNoSince() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        XCTAssertNil(harness.paths.syncedAt)
        await harness.orchestrator.sync()

        let expected = try bridgeObject(try bridgeContract()["transportRequests"])
        let routines = try bridgeObject(expected["routines"])

        XCTAssertEqual(harness.session.sent.first as NSDictionary?, routines as NSDictionary)
        XCTAssertNil(harness.session.sent.first?["since"])
        XCTAssertNil(harness.session.sent.first?["type"])
        XCTAssertEqual(harness.session.sent.count, 2)
    }

    // MARK: - S-103 a later sync carries `since`

    func testS103LaterSyncCarriesSince() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        // The phone's routines arrive, which is what gives the wrist an instant
        // to ask from.
        let routinesDown = try Fixtures.json("fixtures/valid/routines_down.json")
        await harness.deliver(routinesDown)
        let syncedAt = try XCTUnwrap(harness.paths.syncedAt)

        harness.session.clearSent()
        await harness.orchestrator.sync(reconnect: true)

        let expected = try bridgeObject(try bridgeContract()["transportRequests"])
        let routinesSince = try bridgeObject(expected["routinesSince"])

        XCTAssertEqual(harness.session.sent.first as NSDictionary?, routinesSince as NSDictionary)
        XCTAssertEqual(
            harness.session.sent.first?["since"] as? String,
            utcIso(syncedAt)
        )
        XCTAssertEqual(harness.session.sent.count, 2)
    }

    // MARK: - S-104 a sync with no session asks for a snapshot

    func testS104SyncWithNoSessionAsksForASnapshot() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        await harness.orchestrator.sync()

        let expected = try bridgeObject(try bridgeContract()["transportRequests"])
        let snapshot = try bridgeObject(expected["snapshot"])

        XCTAssertEqual(harness.session.sent.count, 2)
        XCTAssertEqual(harness.session.sent.last as NSDictionary?, snapshot as NSDictionary)
        XCTAssertEqual(harness.session.sent.first?["request"] as? String, "routines")
    }

    // MARK: - S-105 a sync fills the routine list and the preference

    func testS105SyncFillsTheRoutineListAndThePreference() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        await harness.deliver(try Fixtures.json("fixtures/valid/preferences_down.json"))
        await harness.deliver(try Fixtures.json("fixtures/valid/routines_down.json"))

        let routinesDown = try Fixtures.json("fixtures/valid/routines_down.json")
        let payload = try bridgeObject(routinesDown["payload"])
        let routines = try bridgeObjects(payload["routines"])

        XCTAssertEqual(harness.paths.routines.count, routines.count)
        XCTAssertEqual(
            harness.paths.routines.first?.routineId,
            routines.first?["routineId"] as? String
        )
        XCTAssertEqual(harness.preferences.asksForEffortRating, false)
        XCTAssertNotNil(harness.preferences.current)
    }

    // MARK: - S-106 a phone with no routines still sends its preference

    func testS106APhoneWithNoRoutinesStillSendsItsPreference() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        await harness.deliver(try Fixtures.json("fixtures/valid/preferences_down.json"))

        XCTAssertTrue(harness.paths.routines.isEmpty)
        XCTAssertEqual(harness.preferences.asksForEffortRating, false)
        XCTAssertNotNil(harness.preferences.current)

        // The wrist now knows the setting instead of guessing it: before the
        // message it had no copy at all.
        let fresh = WatchBridgeHarness()
        await fresh.launch()
        XCTAssertNil(fresh.preferences.current)

        // The empty state still tells the user sync is theirs to start.
        let view = try String(
            contentsOf: Fixtures.sourcesRoot.appendingPathComponent("WatchStartView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(view.contains("No routines yet. Sync with your phone to get them."))
    }

    // MARK: - S-107 a synced routine starts on the wrist

    func testS107ASyncedRoutineStartsOnTheWrist() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        let contract = try bridgeContract()
        let fallback = try bridgeObject(contract["fallback"])
        await harness.deliver(try bridgeObject(fallback["routinesDown"]))

        let routineSession = try bridgeObject(contract["routineSession"])
        let routineId = try XCTUnwrap(routineSession["routineId"] as? String)
        let expectedSlots = try bridgeObjects(routineSession["expectedSlots"])

        XCTAssertEqual(harness.paths.routines.map(\.routineId), [routineId])

        let session = try await harness.paths.startFromRoutine(routineId)
        XCTAssertEqual(session.exercises as NSArray, expectedSlots as NSArray)
    }

    // MARK: - S-112 the frames the wrist sends survive the plist round trip

    func testS112TheFramesTheWristSendsSurviveThePlistRoundTrip() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        _ = await harness.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await harness.engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))
        try await harness.engine.startTimer(WatchTimerKind.rest)
        _ = await harness.engine.pauseTimer(kind: WatchTimerKind.rest)
        await harness.engine.insertExercise(exercise("sx-pushed"))

        let observation = try XCTUnwrap(harness.engine.pendingObservations().first)
        let timer = try XCTUnwrap(harness.emitted("timer_state").last)
        let snapshot = try XCTUnwrap(harness.engine.sessionSnapshot())

        for frame in [observation, timer, snapshot] {
            await harness.bridge.send(frame)
        }

        XCTAssertTrue(harness.failures.isEmpty)
        XCTAssertEqual(harness.session.sent.count, 3)
        XCTAssertEqual(harness.session.sent[0] as NSDictionary, observation as NSDictionary)
        XCTAssertEqual(harness.session.sent[1] as NSDictionary, timer as NSDictionary)
        XCTAssertEqual(harness.session.sent[2] as NSDictionary, snapshot as NSDictionary)

        // Every integer is an integer and every timestamp a string.
        let events = try bridgeObjects(try bridgeObject(observation["payload"])["events"])
        XCTAssertTrue(events.first?["reps"] is Int)
        XCTAssertTrue(events.first?["loggedAt"] is String)

        // The pushed slot is in the snapshot, and the timer frame carries the
        // wire form of the timer rather than the stored row.
        let snapshotPayload = try bridgeObject(snapshot["payload"])
        let slots = try bridgeObjects(snapshotPayload["exercises"])
        XCTAssertEqual(slots.count, 2)
        let timers = try bridgeObject(try bridgeObject(timer["payload"])["timers"])
        let rest = try bridgeObject(timers[WatchTimerKind.rest])
        XCTAssertEqual(rest["state"] as? String, WatchTimerState.paused)
        XCTAssertNil(rest["plannedDurationMs"])

        // The stored row is the one that carries a null; the wire frame omits it.
        let all = await harness.store.readAll()
        let stored = try XCTUnwrap(all.timers.last)
        XCTAssertTrue(stored.toJson()["plannedDurationMs"] is NSNull)
        XCTAssertNil(stored.toTimerJson()["plannedDurationMs"])
    }

    // MARK: - S-113 a frame that cannot be represented is reported

    func testS113AFrameThatCannotBeRepresentedIsReported() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        let nulled: [String: Any] = ["request": "snapshot", "payload": ["value": NSNull()]]
        let custom: [String: Any] = ["request": "snapshot", "payload": ["value": NotAPlistValue()]]
        let binary: [String: Any] = ["request": "snapshot", "payload": ["value": Data([0x01])]]

        for frame in [nulled, custom, binary] {
            await harness.bridge.send(frame)
        }

        XCTAssertTrue(harness.session.sent.isEmpty)
        XCTAssertEqual(harness.failures.count, 3)
        for failure in harness.failures {
            XCTAssertTrue(failure is PropertyListFrameError)
        }

        // The report names where the offending value sits.
        XCTAssertEqual(
            (harness.failures.first as? PropertyListFrameError)?.description,
            "payload.value is not a property-list value"
        )

        // Nothing was queued: the next good frame goes out on its own.
        await harness.bridge.requestSnapshot()
        XCTAssertEqual(harness.session.sent.count, 1)
        XCTAssertEqual(harness.session.sent.first?["request"] as? String, "snapshot")
    }

    // MARK: - D-5 a number is never coerced

    func testD5NumbersAreNeverCoerced() throws {
        let frame: [String: Any] = [
            "one": NSNumber(value: 1),
            "zero": NSNumber(value: 0),
            "int": 5,
            "double": 5.5,
            "flag": true,
            "list": [NSNumber(value: 1), 0, 5, 5.5, true] as [Any],
            "nested": ["one": NSNumber(value: 1), "flag": true] as [String: Any],
        ]

        let safe = try PropertyListFrames.plistSafe(frame)

        /// The type code `NSNumber` reports: `"c"` for a `Bool`, `"d"` for a
        /// `Double`, a numeric code for an integer.
        func typeCode(_ value: Any?) throws -> String {
            let number = try XCTUnwrap(value as? NSNumber)
            return String(cString: number.objCType)
        }

        // An `NSNumber` wrapping 0 or 1 is an integer, not the `Bool` its
        // bridge would report.
        let one = try typeCode(safe["one"])
        let zero = try typeCode(safe["zero"])
        let int = try typeCode(safe["int"])
        let double = try typeCode(safe["double"])
        let flag = try typeCode(safe["flag"])
        XCTAssertNotEqual(one, "c")
        XCTAssertNotEqual(zero, "c")
        XCTAssertNotEqual(int, "c")
        XCTAssertEqual(double, "d")
        XCTAssertEqual(flag, "c")

        let list = try XCTUnwrap(safe["list"] as? [Any])
        let listOne = try typeCode(list[0])
        let listZero = try typeCode(list[1])
        let listInt = try typeCode(list[2])
        let listDouble = try typeCode(list[3])
        let listFlag = try typeCode(list[4])
        XCTAssertNotEqual(listOne, "c")
        XCTAssertNotEqual(listZero, "c")
        XCTAssertNotEqual(listInt, "c")
        XCTAssertEqual(listDouble, "d")
        XCTAssertEqual(listFlag, "c")

        let nested = try XCTUnwrap(safe["nested"] as? [String: Any])
        let nestedOne = try typeCode(nested["one"])
        let nestedFlag = try typeCode(nested["flag"])
        XCTAssertNotEqual(nestedOne, "c")
        XCTAssertEqual(nestedFlag, "c")
    }

    // MARK: - A send the platform refuses is reported, and nothing is queued

    func testASendThePlatformRefusesIsReported() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        harness.session.sendError = BridgeFixtureError.malformed("the radio refused it")
        await harness.bridge.requestSnapshot()

        XCTAssertTrue(harness.session.sent.isEmpty)
        XCTAssertEqual(harness.failures.count, 1)

        harness.session.sendError = nil
        await harness.bridge.requestSnapshot()
        XCTAssertEqual(harness.session.sent.count, 1)
    }

    // MARK: - S-206 a refused frame is reported once, and the row stays owed

    func testS206ARefusedFrameIsReportedOnceAndTheRowStaysOwed() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        _ = await harness.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await harness.engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))

        let observation = try XCTUnwrap(harness.engine.pendingObservations().first)
        let messageId = try XCTUnwrap(observation["messageId"] as? String)

        harness.session.sendError = BridgeFixtureError.malformed("the radio refused it")
        await harness.bridge.send(observation)

        // The wrist never claims the frame went out, and says so once.
        XCTAssertTrue(harness.session.sent.isEmpty)
        XCTAssertEqual(harness.failures.count, 1, "a refusal is reported, once")

        // The refused frame is still owed: it is not treated as delivered, so a
        // later send can carry it again (D-196).
        XCTAssertEqual(
            harness.engine.pendingObservations().compactMap { $0["messageId"] as? String },
            [messageId]
        )
        let pruned = await harness.engine.pruneConfirmed()
        XCTAssertTrue(
            pruned.isEmpty,
            "nothing is confirmed, so the phone's receipt has not arrived"
        )
        XCTAssertEqual(
            harness.engine.pendingObservations().compactMap { $0["messageId"] as? String },
            [messageId],
            "the row survives the sweep that drops confirmed ones"
        )

        // Once the radio takes it, the frame is out.
        harness.session.sendError = nil
        await harness.bridge.send(observation)
        XCTAssertEqual(harness.session.sent.count, 1)
        XCTAssertEqual(harness.failures.count, 1)
    }

    // MARK: - Reachability is read from the seam

    func testReachabilityIsReadFromTheSeam() async throws {
        let harness = WatchBridgeHarness(isPhoneReachable: true)
        await harness.launch()

        XCTAssertTrue(harness.bridge.isPhoneReachable)

        var observed: [Bool] = []
        harness.bridge.onReachabilityChange { observed.append($0) }
        harness.session.reportReachable(false)

        XCTAssertFalse(harness.bridge.isPhoneReachable)
        XCTAssertEqual(observed, [false])
    }

    // MARK: - S-111 the surface says the phone is unreachable only once observed

    func testS111TheSurfaceSaysUnreachableOnlyAfterObservingIt() throws {
        // A cold start has asked the radio nothing, so there is nothing honest
        // to say (D-8) — the state a flag starting `false` would misreport as
        // "unreachable".
        XCTAssertNil(WatchPhoneStatus(reachability: .unknown).sentence)

        // The radio's two answers are the two observed states.
        XCTAssertEqual(WatchPhoneReachability.observed(reachable: false), .unreachable)
        XCTAssertEqual(WatchPhoneReachability.observed(reachable: true), .reachable)

        XCTAssertEqual(
            WatchPhoneStatus(reachability: .unreachable).sentence,
            WatchStartSurfaceCopy.unreachableLabel
        )
        XCTAssertNil(WatchPhoneStatus(reachability: .reachable).sentence)

        // The Sync button is offered in all three (D-9).
        for reachability in [WatchPhoneReachability.unknown, .reachable, .unreachable] {
            XCTAssertTrue(WatchPhoneStatus(reachability: reachability).offersSync)
        }

        XCTAssertEqual(WatchStartSurfaceCopy.unreachableLabel, "Phone not reachable")

        // The surface says it through that one constant, and carries no
        // no-automatic-sync hint any more (S-82).
        let view = try String(
            contentsOf: Fixtures.sourcesRoot.appendingPathComponent("WatchStartView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(view.contains("WatchStartSurfaceCopy.unreachableLabel"))
        XCTAssertFalse(view.contains("WatchNoAutomaticSyncHint"))
    }

    // MARK: - the two contract labels still match the package's copy

    func testTheContractLabelsMatchWatchStartSurfaceCopy() throws {
        let surface = try bridgeObject(try bridgeContract()["startSurface"])

        XCTAssertEqual(surface["syncLabel"] as? String, WatchStartSurfaceCopy.syncLabel)

        // The removed no-automatic-sync line is gone from the contract, not
        // renamed (S-82).
        XCTAssertNil(surface["noAutoSyncLabel"])

        // The unreachable sentence is deliberately not a contract value: the
        // Wear OS client reads the same file and has no transport, so it has no
        // reachability to say it about. It moves into the contract with that
        // client's transport.
        XCTAssertNil(surface["unreachableLabel"])
    }

    // MARK: - I-1 the bridge never sends unsolicited

    func testBridgeSendsNothingUntilAsked() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        await harness.deliver(try Fixtures.json("fixtures/valid/preferences_down.json"))
        await harness.deliver(try Fixtures.json("fixtures/valid/routines_down.json"))

        XCTAssertTrue(harness.session.sent.isEmpty)
        XCTAssertFalse(harness.paths.routines.isEmpty)

        await harness.orchestrator.sync()
        XCTAssertFalse(harness.session.sent.isEmpty)
        XCTAssertEqual(harness.session.sent.first?["request"] as? String, "routines")
    }

    // MARK: - S-108 a push into an open free workout lands

    func testS108APushIntoAnOpenFreeWorkoutLands() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        let edit = try bridgeObject(try bridgeContract()["routineEdit"])
        await harness.deliver(try bridgeObject(edit["routinesDown"]))
        let push = try bridgeObject(try bridgeContract()["exercisePush"])
        let pushedSlotId = try XCTUnwrap(push["pushedSlotId"] as? String)

        _ = await harness.paths.startFreeWorkout()
        await harness.deliver(try bridgeObject(push["envelope"]))

        let session = try XCTUnwrap(harness.engine.session)
        XCTAssertEqual(
            session.exercises.compactMap { $0["sessionExerciseId"] as? String },
            [pushedSlotId]
        )
        XCTAssertEqual(session.currentExerciseIndex, 0)
        XCTAssertEqual(
            harness.engine.currentExercise?["sessionExerciseId"] as? String,
            pushedSlotId,
            "the pushed exercise is the one the wrist is on"
        )

        // Visible and selectable, not merely present: the picker's rows carry the
        // session's own slot first, and offer the exercise once.
        let rows = harness.paths.pickerRows
        XCTAssertEqual(rows.first?.id, pushedSlotId)
        XCTAssertEqual(rows.first?.isInSession, true)
        XCTAssertEqual(rows.filter { $0.exerciseId == "ex-front-squat" }.count, 1)
        XCTAssertTrue(rows.contains { $0.exerciseId == "ex-barbell-bench-press" })
    }

    // MARK: - S-109 a re-delivered push does not duplicate the slot

    func testS109AReDeliveredPushDoesNotDuplicateTheSlot() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        let push = try bridgeObject(try bridgeContract()["exercisePush"])

        _ = await harness.paths.startFreeWorkout()
        await harness.deliver(try bridgeObject(push["envelope"]))
        let after = try XCTUnwrap(harness.engine.session)
        await harness.deliver(try bridgeObject(push["envelope"]))

        XCTAssertEqual(harness.engine.session?.exercises.count, 1)
        XCTAssertEqual(
            harness.engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            after.exercises.compactMap { $0["sessionExerciseId"] as? String }
        )
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, after.currentExerciseIndex)
    }

    // MARK: - S-110 a push with no live session changes nothing

    func testS110APushWithNoLiveSessionChangesNothing() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        let push = try bridgeObject(try bridgeContract()["exercisePush"])

        XCTAssertNil(harness.engine.session)

        // Through the radio, the way the phone's push really arrives: a readable
        // push with nowhere to land is read and dropped rather than trapping.
        await harness.deliver(try bridgeObject(push["envelope"]))
        XCTAssertNil(harness.engine.session, "D-12: no session is created for it")
        XCTAssertTrue(harness.failures.isEmpty, "a readable push with nowhere to go is not a refusal")

        let applied = try await harness.orchestrator.receive(try bridgeObject(push["envelope"]))
        XCTAssertFalse(applied, "D-12: the result reports not applied")

        let stored = await harness.store.readAll()
        XCTAssertTrue(stored.sessions.isEmpty, "D-12: nothing is stored")

        // The next sync still converges from what the wrist holds (S-104).
        await harness.orchestrator.sync()
        XCTAssertEqual(harness.session.sent.last?["request"] as? String, "snapshot")
    }

    // MARK: - D-10 the picker's rows

    func testPickerRowsListTheSessionFirstAndNeverTwice() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        let edit = try bridgeObject(try bridgeContract()["routineEdit"])
        await harness.deliver(try bridgeObject(edit["routinesDown"]))
        let bench = try XCTUnwrap(
            harness.paths.fallbackExercises.first { $0.exerciseId == "ex-barbell-bench-press" }
        )
        let plank = try XCTUnwrap(
            harness.paths.fallbackExercises.first { $0.exerciseId == "ex-plank" }
        )

        _ = await harness.paths.startFreeWorkout()
        _ = await harness.paths.addExerciseToSession(bench)
        let session = await harness.paths.addExerciseToSession(plank)
        XCTAssertEqual(session.currentExerciseIndex, 1)

        let rows = harness.paths.pickerRows
        XCTAssertEqual(rows.prefix(2).map(\.name), ["Barbell Bench Press", "Plank"])
        XCTAssertEqual(rows.filter { $0.isInSession }.count, 2, "the session's slots come first")
        XCTAssertEqual(rows.filter { $0.exerciseId == "ex-barbell-bench-press" }.count, 1)
        XCTAssertEqual(rows.filter { $0.exerciseId == "ex-plank" }.count, 1)
        XCTAssertEqual(rows.map(\.id).count, Set(rows.map(\.id)).count, "every row is keyed uniquely")

        // What follows is the fallback list, in its order, minus what the ladder
        // already shows — including the exercise only the routine edit knows.
        XCTAssertEqual(
            rows.dropFirst(2).map(\.exerciseId),
            harness.paths.fallbackExercises
                .map(\.exerciseId)
                .filter { !["ex-barbell-bench-press", "ex-plank"].contains($0) }
        )
        XCTAssertTrue(rows.contains { $0.exerciseId == "ex-front-squat" })

        // Picking a session row moves the session to that exercise, and says so
        // the way a `+1` advance does.
        let picked = await harness.paths.selectExercise(rows[0])
        XCTAssertEqual(picked?.currentExerciseIndex, 0)
        XCTAssertEqual(harness.engine.currentExercise?["sessionExerciseId"] as? String, bench.slotId)

        let payload = try bridgeObject(harness.emitted("session_lifecycle").last?["payload"])
        XCTAssertEqual(payload["state"] as? String, "exercise_advanced")
        XCTAssertEqual(payload["exerciseIndex"] as? Int, 0)

        // A row whose slot the session no longer holds changes nothing.
        let stale = WatchExercisePickerRow.inSession(slotId: "sx-gone", exercise: bench)
        let refused = await harness.paths.selectExercise(stale)
        XCTAssertNil(refused)
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 0)
    }

    func testPickerRowsFallBackToTheFallbackListWhileTheSessionIsEmpty() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        let edit = try bridgeObject(try bridgeContract()["routineEdit"])
        await harness.deliver(try bridgeObject(edit["routinesDown"]))

        _ = await harness.paths.startFreeWorkout()
        let rows = harness.paths.pickerRows

        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { !$0.isInSession })
        XCTAssertEqual(rows.map(\.exerciseId), harness.paths.fallbackExercises.map(\.exerciseId))
        XCTAssertEqual(rows.map(\.exerciseId).count, Set(rows.map(\.exerciseId)).count)

        // Picking an offered exercise appends it, exactly as the add path does.
        let added = await harness.paths.selectExercise(rows[0])
        XCTAssertEqual(added?.exercises.count, 1)
        XCTAssertEqual(added?.exercises.first?["exerciseId"] as? String, rows[0].exerciseId)
        XCTAssertEqual(added?.currentExerciseIndex, 0)
    }

    // MARK: - S-107/S-186 the wrist's activation catch-up (D-96, D-183)

    func testS107TheWristCatchesUpOnAReachabilityEdgeOnce() async throws {
        let harness = Harness(sessionId: "s-watch-1")
        let engine = await harness.runningEngine()
        let paths = WatchSessionStartPaths(
            engine: engine,
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call,
            idFactory: { "cat-1" }
        )
        let transport = GatedTransport()
        let orchestrator = WatchSyncOrchestrator(transport: transport, paths: paths, engine: engine)

        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = try await engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))
        _ = try await engine.appendObservation(setEvent(harness.clock, entryId: "e-2"))
        XCTAssertEqual(engine.pendingObservations().count, 2, "two owed entries")

        // The first catch-up starts a sync and suspends inside the transport.
        let first = Task { await orchestrator.catchUp(reachable: true) }
        let deadline = Date().addingTimeInterval(2)
        while !transport.gateEntered && Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(transport.gateEntered, "the first sync must reach the transport")

        // A second notification with the same value, while the first is still in
        // flight, is dropped: never queued, never cancelling the running one.
        await orchestrator.catchUp(reachable: true)
        XCTAssertEqual(transport.requested.count, 1, "exactly one sync ran")
        XCTAssertTrue(transport.sent.isEmpty, "and no send overlapped it")

        transport.release()
        await first.value

        let entryIds = transport.sent.flatMap { frame -> [String] in
            guard frame["type"] as? String == "observations_up" else { return [] }
            let events = (frame["payload"] as? [String: Any])?["events"] as? [[String: Any]] ?? []
            return events.compactMap { $0["entryId"] as? String }
        }
        XCTAssertEqual(entryIds, ["e-1", "e-2"], "the owed entries left exactly once")
        XCTAssertEqual(
            transport.sent.filter { $0["type"] as? String == "session_snapshot" }.count,
            1,
            "the wrist holding a session offers its own snapshot"
        )
        XCTAssertEqual(engine.session?.sessionId, "s-watch-1", "the wrist's session is unchanged")

        // A later reachability edge runs again.
        await orchestrator.catchUp(reachable: true)
        XCTAssertEqual(transport.requested.count, 2, "a later trigger is not dropped")

        // An unreachable radio starts nothing.
        await orchestrator.catchUp(reachable: false)
        XCTAssertEqual(transport.requested.count, 2, "an unreachable phone starts no sync")
    }

    /// S-186, the Swift half (was `testS108AWristWithNoSessionDoesNotSyncOnItsOwn`
    /// before D-183). A wrist holding nothing is exactly the one that must ask:
    /// the phone may hold the session it should be in, so a reachable activation
    /// carries a routines request and a snapshot request and installs the answer.
    func testS186AWristWithNoSessionAsksAtItsNextActivation() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        XCTAssertNil(harness.engine.session, "the wrist holds no session")
        XCTAssertTrue(harness.engine.pendingObservations().isEmpty, "and owes nothing")

        await harness.orchestrator.catchUp(reachable: true)

        let routinesRequest = try XCTUnwrap(
            harness.transport.requested.first,
            "the wrist asks for routines at its activation"
        )
        XCTAssertNil(routinesRequest, "and the first pass asks for everything")
        XCTAssertEqual(harness.transport.snapshotRequests, 1, "and for the phone's session")
        XCTAssertTrue(harness.transport.sent.isEmpty, "nothing else leaves the wrist")
        XCTAssertTrue(harness.paths.routines.isEmpty, "the routines surface is still empty")
        XCTAssertNil(harness.preferences.current, "and so is the settings surface")

        let answer = bridgeSnapshotFrame(
            sessionId: "p1",
            messageId: "msg-p1-1",
            exercises: [exercise("u-squat"), exercise("u-press")],
            entries: [
                setEvent(harness.clock, entryId: "e-u-squat-1", slot: "u-squat"),
                setEvent(harness.clock, entryId: "e-u-squat-2", slot: "u-squat"),
                setEvent(harness.clock, entryId: "e-u-press-1", slot: "u-press"),
            ]
        )
        let installed = try await harness.receive(answer)
        XCTAssertTrue(installed, "the phone's answer is applied")

        let session = try XCTUnwrap(harness.engine.session)
        XCTAssertEqual(session.sessionId, "p1")
        XCTAssertEqual(session.status, WatchSessionStatus.active)
        XCTAssertEqual(
            session.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["u-squat", "u-press"]
        )
        // Same instant for all three, so the projection's order is not the
        // subject here — the entries it holds are.
        XCTAssertEqual(
            Set(harness.engine.entries.compactMap { $0.payload["entryId"] as? String }),
            ["e-u-squat-1", "e-u-squat-2", "e-u-press-1"],
            "the ladder the phone asserts arrives whole"
        )
    }

    /// S-187, the Swift half: an activation with the phone out of reach carries
    /// nothing and throws nothing; the reachability edge that follows does work.
    func testS187AnUnreachableActivationIsANoOpAndTheEdgeDoesTheWork() async throws {
        let harness = WatchStartHarness()
        await harness.launch()

        await harness.orchestrator.catchUp(reachable: false)

        XCTAssertTrue(harness.transport.requested.isEmpty, "an unreachable phone is not asked")
        XCTAssertEqual(harness.transport.snapshotRequests, 0)
        XCTAssertTrue(harness.transport.sent.isEmpty, "and nothing leaves the wrist")
        XCTAssertNil(harness.engine.session, "the wrist still holds nothing")

        await harness.orchestrator.catchUp(reachable: true)

        XCTAssertEqual(harness.transport.requested.count, 1, "the edge runs the catch-up")
        XCTAssertEqual(harness.transport.snapshotRequests, 1)

        let answer = bridgeSnapshotFrame(
            sessionId: "p1",
            messageId: "msg-p1-2",
            exercises: [exercise("u-squat"), exercise("u-press")]
        )
        let installed = try await harness.receive(answer)
        XCTAssertTrue(installed)
        XCTAssertEqual(harness.engine.session?.sessionId, "p1")
    }

    /// S-188, the Swift half: a burst of triggers from one wake runs one sync —
    /// the rest are dropped, never queued — and the next trigger after that sync
    /// completes runs a fresh catch-up.
    func testS188AnActivationBurstIsDroppedAndTheLaterTriggerRuns() async throws {
        let harness = Harness(sessionId: "s-watch-1")
        let engine = await harness.runningEngine()
        let paths = WatchSessionStartPaths(
            engine: engine,
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call,
            idFactory: { "cat-1" }
        )
        let transport = GatedRequestTransport()
        let orchestrator = WatchSyncOrchestrator(transport: transport, paths: paths, engine: engine)
        XCTAssertNil(engine.session, "a wrist with no session is the burst's case")

        let first = Task { await orchestrator.catchUp(reachable: true) }
        let deadline = Date().addingTimeInterval(2)
        while !transport.gateEntered && Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(transport.gateEntered, "the first catch-up must reach the transport")

        await orchestrator.catchUp(reachable: true)
        await orchestrator.catchUp(reachable: true)
        XCTAssertTrue(transport.requested.isEmpty, "the triggers in flight are dropped")

        transport.release()
        await first.value

        XCTAssertEqual(transport.requested.count, 1, "the burst ran one sync, not three")
        XCTAssertEqual(transport.snapshotRequests, 1, "and asked once for the phone's session")

        await orchestrator.catchUp(reachable: true)
        XCTAssertEqual(transport.requested.count, 2, "a later trigger is not dropped")
        XCTAssertEqual(transport.snapshotRequests, 2, "and runs a fresh pass")
    }
}

/// A transport whose first send waits for the test to release it, so a second
/// catch-up can arrive while the first sync is still in flight (S-107).
final class GatedTransport: WatchSyncTransport {
    var isPhoneReachable: Bool
    private(set) var requested: [Date?] = []
    private(set) var sent: [[String: Any]] = []
    private(set) var snapshotRequests = 0

    /// True once the gated send has registered its continuation.
    private(set) var gateEntered = false

    private let lock = NSLock()
    private var gateUsed = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(isPhoneReachable: Bool = true) {
        self.isPhoneReachable = isPhoneReachable
    }

    func requestRoutines(since: Date?) async { requested.append(since) }

    func requestSnapshot() async { snapshotRequests += 1 }

    func send(_ envelope: [String: Any]) async {
        let shouldGate = lock.withLock { () -> Bool in
            let gate = !gateUsed
            gateUsed = true
            return gate
        }

        if shouldGate {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.withLock {
                    releaseContinuation = continuation
                    gateEntered = true
                }
            }
        }
        sent.append(envelope)
    }

    /// Lets the gated send finish.
    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let held = releaseContinuation
            releaseContinuation = nil
            return held
        }
        continuation?.resume()
    }
}

/// A transport whose first routines request waits for the test to release it, so
/// a later trigger arrives while a session-less catch-up is in flight (S-188).
/// A wrist with no session has no send to gate, so the gate sits on the request
/// that catch-up makes first.
final class GatedRequestTransport: WatchSyncTransport {
    var isPhoneReachable: Bool
    private(set) var requested: [Date?] = []
    private(set) var sent: [[String: Any]] = []
    private(set) var snapshotRequests = 0

    /// True once the gated request has registered its continuation.
    private(set) var gateEntered = false

    private let lock = NSLock()
    private var gateUsed = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(isPhoneReachable: Bool = true) {
        self.isPhoneReachable = isPhoneReachable
    }

    func requestRoutines(since: Date?) async {
        let shouldGate = lock.withLock { () -> Bool in
            let gate = !gateUsed
            gateUsed = true
            return gate
        }

        if shouldGate {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.withLock {
                    releaseContinuation = continuation
                    gateEntered = true
                }
            }
        }
        requested.append(since)
    }

    func requestSnapshot() async { snapshotRequests += 1 }

    func send(_ envelope: [String: Any]) async { sent.append(envelope) }

    /// Lets the gated request finish.
    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let held = releaseContinuation
            releaseContinuation = nil
            return held
        }
        continuation?.resume()
    }
}
