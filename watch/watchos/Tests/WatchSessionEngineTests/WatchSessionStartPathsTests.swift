//
//  WatchSessionStartPathsTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `.github/agents/plans/2026-07-13-08-b-watch-session-start-paths-plan.md` —
//  the same scenarios the Dart suite proves in
//  `test/watch_session_start_test.dart`, run against the Swift start paths.
//
//  Two sources are read from the repository rather than restated here: the
//  protocol schemas/fixtures (so "conformant" is the schema's verdict) and
//  `watch/contract/watch_start_paths_contract.json`, the values the Wear OS
//  suite is held to as well. A rule that changes on one platform therefore fails
//  the other's tests.
//
//  "Phone offline" is simulated by giving the watch nothing but its own
//  storage: every offline claim is checked by rebuilding the watch over the same
//  store with no transport in sight.
//

import XCTest

@testable import WatchSessionEngine

/// A transport that records what it was asked for and never invents a reply:
/// the reply arrives through `receive`, exactly as a real one would.
final class RecordingTransport: WatchSyncTransport {
    var isPhoneReachable: Bool
    private(set) var requested: [Date?] = []

    /// What the watch handed over: observations, timers, and snapshots.
    private(set) var sent: [[String: Any]] = []

    /// How many times the watch asked for a session snapshot.
    private(set) var snapshotRequests = 0

    init(isPhoneReachable: Bool = false) {
        self.isPhoneReachable = isPhoneReachable
    }

    func requestRoutines(since: Date?) async {
        requested.append(since)
    }

    func requestSnapshot() async {
        snapshotRequests += 1
    }

    func send(_ envelope: [String: Any]) async {
        sent.append(envelope)
    }
}

/// A watch: one engine, its start paths, and the orchestrator that keeps them
/// fed. Rebuilt over the same store to simulate a relaunch.
final class WatchStartHarness {
    let clock: TestClock
    let store: WatchSessionStore
    let sessionId: String
    let transport = RecordingTransport()
    private(set) var emitted: [[String: Any]] = []
    private var ids = 0

    private(set) var engine: WatchSessionEngine!
    private(set) var paths: WatchSessionStartPaths!
    private(set) var preferences: WatchPhonePreferences!
    private(set) var orchestrator: WatchSyncOrchestrator!

    init(store: WatchSessionStore = InMemoryWatchSessionStore(), sessionId: String = "s-watch-1") {
        self.clock = TestClock(testInstant())
        self.store = store
        self.sessionId = sessionId
        build()
    }

    /// A watch that has restored: engine first, then the start paths, exactly as
    /// a launch would.
    @discardableResult
    func launch() async -> WatchStartHarness {
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
        orchestrator = WatchSyncOrchestrator(
            transport: transport,
            paths: paths,
            engine: engine,
            preferences: preferences
        )
    }

    /// The value screen the wrist would show for the exercise the session is on.
    var surface: WatchLoggingState {
        WatchLoggingState(engine: engine, clock: clock.call)
    }

    /// Every message of `type` the watch emitted, in order.
    func emitted(_ type: String) -> [[String: Any]] {
        emitted.filter { $0["type"] as? String == type }
    }

    /// What the phone sent, applied the way a launch would: through the
    /// orchestrator, so routing is exercised rather than bypassed.
    @discardableResult
    func receive(_ envelope: [String: Any]) async throws -> Bool {
        try await orchestrator.receive(envelope)
    }
}

private enum StartFixtureError: Error {
    case malformed(String)
}

private func startContract() throws -> [String: Any] {
    let url = Fixtures.repositoryRoot
        .appendingPathComponent("watch/contract/watch_start_paths_contract.json")
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw StartFixtureError.malformed("watch_start_paths_contract.json")
    }
    return object
}

private func object(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else {
        throw StartFixtureError.malformed("expected an object, found \(String(describing: value))")
    }
    return value
}

private func objects(_ value: Any?) throws -> [[String: Any]] {
    guard let value = value as? [[String: Any]] else {
        throw StartFixtureError.malformed("expected an array of objects")
    }
    return value
}

private func strings(_ value: Any?) throws -> [String] {
    guard let value = value as? [String] else {
        throw StartFixtureError.malformed("expected an array of strings")
    }
    return value
}

private func slotIds(_ session: WatchSessionRecord) -> [String] {
    session.exercises.compactMap { $0["sessionExerciseId"] as? String }
}

private func routineSlots(_ routine: WatchRoutine) -> [String] {
    routine.slots.compactMap { $0["sessionExerciseId"] as? String }
}

/// A push at `index`, carrying the contract's own slot so the only thing that
/// varies between cases is the position.
private func push(at index: Int) throws -> [String: Any] {
    let push = try object(try startContract()["exercisePush"])
    var envelope = try object(push["envelope"])
    var payload = try object(envelope["payload"])

    envelope["messageId"] = "msg-push-at-\(index)"
    payload["insertAtIndex"] = index
    envelope["payload"] = payload
    return envelope
}

/// The contract's message plus a second routine, so the routine list is
/// exercised with more than one entry. The added routine reuses an exercise the
/// contract's fallback list already covers, which is what keeps the message
/// conformant — the protocol rejects a `routines_down` that names an exercise
/// the watch could not log with the phone off.
private func twoRoutineMessage(_ effort: WatchRoutineEffort) throws -> [String: Any] {
    let fallback = try object(try startContract()["fallback"])
    let sent = try object(fallback["routinesDown"])
    var payload = try object(sent["payload"])
    let routines = try objects(payload["routines"])

    payload["generatedAt"] = "2026-07-13T18:30:00Z"
    payload["routines"] = routines + [
        [
            "routineId": "routine-pull-day",
            "name": "Pull Day",
            "updatedAt": "2026-07-13T18:30:00Z",
            "segments": [
                [
                    "segmentId": "seg-pull",
                    "name": "Pull",
                    "efforts": [effort.toJson()],
                ]
            ],
        ]
    ]

    var message = sent
    message["messageId"] = "msg-routines-second"
    message["sentAt"] = "2026-07-13T18:30:00Z"
    message["payload"] = payload
    return message
}

/// The effort kind the logging surface resolves for `capabilities`, asked of a
/// watch of its own so a slot can be probed without moving the session under
/// test off the exercise the user is on.
private func effortKind(
    capabilities: [String],
    clock: @escaping () -> Date
) async -> String {
    let engine = WatchSessionEngine(store: InMemoryWatchSessionStore(), clock: clock)
    _ = await engine.createSession(
        modality: nil,
        exercises: [[
            "sessionExerciseId": "sx-probe",
            "exerciseId": "ex-probe",
            "name": "Probe",
            "capabilities": capabilities,
        ]]
    )
    return WatchLoggingState(engine: engine, clock: clock).effortKind
}

final class WatchSessionStartPathsTests: XCTestCase {

    private func firstMessage() throws -> [String: Any] {
        let fallback = try object(try startContract()["fallback"])
        return try object(fallback["routinesDown"])
    }

    // MARK: - S-003 fallback list derivation

    func testS003FallbackListUnionsRecentsAndRoutineExercisesInContractOrder() throws {
        let fallback = try object(try startContract()["fallback"])
        let sent = try WatchRoutinesDown(envelope: try object(fallback["routinesDown"]))

        let derived = deriveFallbackExercises(
            recents: try objects(fallback["recents"]).map(WatchCatalogExercise.init(json:)),
            syncedFallback: sent.fallbackExercises,
            routines: sent.routines
        )

        XCTAssertEqual(derived.map(\.exerciseId), try strings(fallback["expected"]))
        XCTAssertEqual(Set(derived.map(\.exerciseId)).count, derived.count)
    }

    func testS003RoutineReferencedExercisesKeepRoutineOrder() throws {
        let fallback = try object(try startContract()["fallback"])
        let sent = try WatchRoutinesDown(envelope: try object(fallback["routinesDown"]))

        XCTAssertEqual(
            sent.routines.flatMap(\.referencedExercises).map(\.exerciseId),
            try strings(fallback["routineOrder"])
        )
    }

    func testS003StoredListCoversEveryExerciseASyncedRoutineNames() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())

        let referenced = harness.paths.routines
            .flatMap(\.referencedExercises)
            .map(\.exerciseId)
        let offered = Set(harness.paths.fallbackExercises.map(\.exerciseId))

        for exerciseId in referenced {
            XCTAssertTrue(offered.contains(exerciseId), "\(exerciseId) is not offered")
        }
    }

    // MARK: - S-001 start from a routine, phone offline

    func testS001CreatesTheRoutineStructureAndLoadsTheFirstExercise() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        let expected = try objects(try object(try startContract()["routineSession"])["expectedSlots"])

        let session = try await harness.paths.startFromRoutine("routine-push-a")

        XCTAssertEqual(session.status, WatchSessionStatus.active)
        XCTAssertEqual(session.currentExerciseIndex, 0)
        XCTAssertEqual(session.exercises.count, expected.count)
        for (slot, expectedSlot) in zip(session.exercises, expected) {
            XCTAssertEqual(slot["sessionExerciseId"] as? String, expectedSlot["sessionExerciseId"] as? String)
            XCTAssertEqual(slot["exerciseId"] as? String, expectedSlot["exerciseId"] as? String)
            XCTAssertEqual(slot["name"] as? String, expectedSlot["name"] as? String)
            XCTAssertEqual(slot["capabilities"] as? [String], expectedSlot["capabilities"] as? [String])
            // The routine's declared kind travels with the slot (D-6).
            XCTAssertEqual(slot["effortKind"] as? String, expectedSlot["effortKind"] as? String)
        }

        // The first exercise reaches the logging surface as its own effort kind,
        // off the capabilities the routine carried.
        XCTAssertEqual(harness.surface.effortKind, WatchEffortKind.set)
        XCTAssertEqual(harness.surface.exerciseName, "Barbell Bench Press")
    }

    /// D-6: a slot a routine produced renders the kind the routine declared, not
    /// the one its capabilities imply — which is where the two disagree for
    /// `Plank`, stored `timed` on the phone while `hold` wins the shared
    /// precedence.
    func testS004APlankDeclaredTimedRendersAsATimedEffort() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())

        let session = try await harness.paths.startFromRoutine("routine-push-a")
        XCTAssertEqual(session.exercises.count, 3)

        // The routine's second effort is the Plank.
        _ = await harness.engine.advanceExercise()

        XCTAssertEqual(harness.surface.exerciseName, "Plank")
        XCTAssertEqual(harness.surface.effortKind, WatchEffortKind.timed)

        // The capability rule on its own would have produced a hold, which is
        // the divergence this closes.
        let derived = await effortKind(
            capabilities: ["time", "hold"],
            clock: harness.clock.call
        )
        XCTAssertEqual(derived, WatchEffortKind.drill)
    }

    /// S-010: sync is watch-initiated, and the start surface has to say so.
    /// Both clients read the sentence from the contract, so neither can drift.
    func testS010TheStartSurfaceCarriesTheNoAutomaticSyncLabel() throws {
        let surface = try object(try startContract()["startSurface"])

        XCTAssertEqual(
            WatchStartSurfaceCopy.noAutoSyncLabel,
            surface["noAutoSyncLabel"] as? String
        )
        XCTAssertEqual(
            WatchStartSurfaceCopy.syncLabel,
            surface["syncLabel"] as? String
        )
    }

    func testS001ARelaunchWithNoPhoneStillListsAndStartsTheRoutine() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())

        // Gone: engine, start paths, in-memory state. Left: the store.
        await harness.launch()

        XCTAssertEqual(harness.paths.routines.map(\.name), ["Push A"])
        let session = try await harness.paths.startFromRoutine("routine-push-a")
        XCTAssertEqual(session.exercises.count, 3)
        XCTAssertFalse(harness.paths.phoneReachable)
    }

    func testS001TheStartedSessionSurvivesAKillWithItsStructure() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        let started = try await harness.paths.startFromRoutine("routine-push-a")

        harness.clock.advance(12 * 60)
        await harness.launch()

        XCTAssertEqual(harness.engine.session?.sessionId, started.sessionId)
        XCTAssertEqual(harness.engine.session?.startedAt, started.startedAt)
        XCTAssertEqual(slotIds(harness.engine.session!), slotIds(started))
    }

    // MARK: - S-002 free workout, phone offline

    func testS002FreeWorkoutStartsEmptyAndAddsAFallbackExercise() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        let fallback = try object(try startContract()["fallback"])
        let bench = try XCTUnwrap(
            harness.paths.fallbackExercises.first { $0.exerciseId == "ex-barbell-bench-press" }
        )

        let started = await harness.paths.startFreeWorkout()
        XCTAssertTrue(started.exercises.isEmpty)
        XCTAssertNil(started.modality)

        let session = await harness.paths.addExerciseToSession(bench)

        XCTAssertEqual(session.exercises.count, 1)
        XCTAssertEqual(
            session.exercises.first?["sessionExerciseId"] as? String,
            fallback["expectedPickerSlotId"] as? String
        )
        XCTAssertEqual(session.exercises.first?["exerciseId"] as? String, bench.exerciseId)
        XCTAssertEqual(harness.surface.effortKind, WatchEffortKind.set)
        XCTAssertEqual(harness.surface.exerciseName, "Barbell Bench Press")

        try await harness.surface.log()

        let events = harness.emitted("observations_up").flatMap { envelope -> [[String: Any]] in
            let payload = envelope["payload"] as? [String: Any] ?? [:]
            return (payload["events"] as? [[String: Any]]) ?? []
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?["exerciseId"] as? String, "ex-barbell-bench-press")
        XCTAssertTrue(Harness.validator().validateEnvelope(harness.emitted("observations_up")[0]).isEmpty)

        // Persisted, not just emitted: the register's outcome is that the entry
        // survives whatever happens to the app next.
        let stored = await harness.store.readAll()
        XCTAssertEqual(stored.observations.map(\.entryId), [events.first?["entryId"] as? String].compactMap { $0 })
    }

    func testS001ListsEverySyncedRoutineAndStartsAnyOneOfThem() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        let sent = try WatchRoutinesDown(envelope: try firstMessage())

        // A second routine, composed from what the contract already pins so the
        // message stays conformant: its exercise is in the fallback list.
        let pullUp = try XCTUnwrap(
            sent.routines.first?.efforts.last { $0.exerciseId == "ex-pull-up" }
        )
        _ = try await harness.receive(twoRoutineMessage(pullUp))

        XCTAssertEqual(harness.paths.routines.map(\.name), ["Push A", "Pull Day"])

        let session = try await harness.paths.startFromRoutine("routine-pull-day")
        XCTAssertEqual(session.exercises.count, 1)
        XCTAssertEqual(session.exercises.first?["exerciseId"] as? String, "ex-pull-up")
        XCTAssertEqual(harness.surface.exerciseName, "Pull-Up")
    }

    func testS002TheExerciseAddedMidSessionBecomesTheOneBeingLogged() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        let plank = try XCTUnwrap(
            harness.paths.fallbackExercises.first { $0.exerciseId == "ex-plank" }
        )

        _ = await harness.paths.startFreeWorkout()
        let session = await harness.paths.addExerciseToSession(plank)

        XCTAssertEqual(session.currentExerciseIndex, 0)
        XCTAssertEqual(harness.surface.exerciseName, "Plank")
        XCTAssertEqual(harness.surface.effortKind, WatchEffortKind.drill)
    }

    func testS002AFreeWorkoutStartedOfflineIsStillThereAfterARelaunch() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        let started = await harness.paths.startFreeWorkout()

        await harness.launch()

        XCTAssertEqual(harness.engine.session?.sessionId, started.sessionId)
        XCTAssertTrue(harness.engine.session?.exercises.isEmpty ?? false)
    }
    // MARK: - S-006 session-started lifecycle event

    func testS006StartingFromARoutineEmitsOneConformantSessionStartedEvent() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        let expected = try object(try startContract()["sessionStarted"])

        let session = try await harness.paths.startFromRoutine("routine-push-a")

        let lifecycle = harness.emitted("session_lifecycle")
        XCTAssertEqual(lifecycle.count, 1)
        let envelope = try XCTUnwrap(lifecycle.first)
        XCTAssertTrue(Harness.validator().validateEnvelope(envelope).isEmpty)
        XCTAssertEqual(envelope["origin"] as? String, expected["origin"] as? String)
        XCTAssertEqual(envelope["sessionId"] as? String, session.sessionId)
        let payload = try object(envelope["payload"])
        XCTAssertEqual(payload["state"] as? String, expected["state"] as? String)
        XCTAssertEqual(payload["at"] as? String, utcIso(session.startedAt))
    }

    func testS006AFreeWorkoutEmitsTheSameEventAndARelaunchDoesNotReEmitIt() async throws {
        let harness = WatchStartHarness()
        await harness.launch()

        _ = await harness.paths.startFreeWorkout()
        await harness.launch()

        let lifecycle = harness.emitted("session_lifecycle")
        XCTAssertEqual(lifecycle.count, 1, "one per session start")
        let payload = try object(lifecycle.first?["payload"])
        XCTAssertEqual(payload["state"] as? String, "started")
    }

    func testS006AdvancingAndFinishingReportThemselvesAndNothingElse() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = try await harness.paths.startFromRoutine("routine-push-a")

        _ = await harness.engine.advanceExercise()
        _ = await harness.engine.finishSession()

        let payloads = try harness.emitted("session_lifecycle").map { try object($0["payload"]) }
        XCTAssertEqual(
            payloads.map { $0["state"] as? String },
            ["started", "exercise_advanced", "completed"]
        )
        XCTAssertEqual(payloads[1]["exerciseIndex"] as? Int, 1)
        XCTAssertNil(payloads[2]["exerciseIndex"])
        for envelope in harness.emitted("session_lifecycle") {
            XCTAssertTrue(Harness.validator().validateEnvelope(envelope).isEmpty)
        }

        // The advanced event is the one the protocol's fixture pins, field for
        // field — including the index, which no other state may carry.
        let fixture = try object(try Fixtures.json("fixtures/valid/session_lifecycle.json")["payload"])
        XCTAssertEqual(Set(payloads[1].keys), Set(fixture.keys))
        XCTAssertEqual(fixture["state"] as? String, payloads[1]["state"] as? String)
    }

    // MARK: - S-005 phone push adds an exercise to the live session

    func testS005PushInsertsAtTheChosenPositionAndStaysOnTheSameExercise() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = try await harness.paths.startFromRoutine("routine-push-a")
        let push = try object(try startContract()["exercisePush"])

        for _ in 0..<(push["startIndex"] as? Int ?? 0) {
            _ = await harness.engine.advanceExercise()
        }
        let before = harness.engine.currentExercise?["sessionExerciseId"] as? String

        let applied = try await harness.receive(try object(push["envelope"]))
        XCTAssertTrue(applied)

        XCTAssertEqual(slotIds(harness.engine.session!), try strings(push["expectedSlotIds"]))
        XCTAssertEqual(
            harness.engine.currentExercise?["sessionExerciseId"] as? String,
            push["expectedCurrentSlotId"] as? String,
            "the push is not a request to move the user elsewhere"
        )
        XCTAssertEqual(
            harness.engine.currentExercise?["sessionExerciseId"] as? String,
            before,
            "the position follows the exercise, not the index"
        )
    }

    func testS005ThePushedExerciseLogsWithItsOwnEffortKind() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = try await harness.paths.startFromRoutine("routine-push-a")
        let push = try object(try startContract()["exercisePush"])

        _ = try await harness.receive(try object(push["envelope"]))

        // The push lands behind the exercise the user was on, so advancing twice
        // is how a wrist reaches it — and then it has to log as a set.
        let pushedIndex = try XCTUnwrap(
            harness.engine.session?.exercises.firstIndex {
                $0["sessionExerciseId"] as? String == push["pushedSlotId"] as? String
            }
        )
        while (harness.engine.session?.currentExerciseIndex ?? 0) < pushedIndex {
            _ = await harness.engine.advanceExercise()
        }

        XCTAssertEqual(
            harness.engine.currentExercise?["sessionExerciseId"] as? String,
            push["pushedSlotId"] as? String
        )
        XCTAssertEqual(harness.surface.effortKind, WatchEffortKind.set)

        try await harness.surface.log()
        let payload = try object(harness.emitted("observations_up").last?["payload"])
        let events = (payload["events"] as? [[String: Any]]) ?? []
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(
            events.first?["sessionExerciseId"] as? String,
            push["pushedSlotId"] as? String
        )
        XCTAssertEqual(events.first?["exerciseId"] as? String, "ex-front-squat")
    }

    func testS005APushBeforeTheCurrentExerciseLeavesTheUserWhereTheyWere() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = try await harness.paths.startFromRoutine("routine-push-a")

        _ = await harness.engine.advanceExercise()
        _ = await harness.engine.advanceExercise()
        XCTAssertEqual(harness.engine.currentExercise?["sessionExerciseId"] as? String, "sx-eff-pullup")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 2)

        _ = try await harness.receive(push(at: 0))

        XCTAssertEqual(
            slotIds(harness.engine.session!),
            ["sx-push-front-squat", "sx-eff-bench", "sx-eff-plank", "sx-eff-pullup"]
        )
        XCTAssertEqual(
            harness.engine.currentExercise?["sessionExerciseId"] as? String,
            "sx-eff-pullup",
            "inserting earlier in the ladder must not move the user"
        )
        XCTAssertEqual(
            harness.engine.session?.currentExerciseIndex,
            3,
            "the position follows the exercise, so it shifts with it"
        )
    }

    func testS005AReDeliveredPushChangesNothing() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = try await harness.paths.startFromRoutine("routine-push-a")
        let push = try object(try startContract()["exercisePush"])

        _ = try await harness.receive(try object(push["envelope"]))
        let after = try XCTUnwrap(harness.engine.session)
        _ = try await harness.receive(try object(push["envelope"]))

        XCTAssertEqual(slotIds(harness.engine.session!), slotIds(after))
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, after.currentExerciseIndex)
    }

    func testS005ANonConformantPushChangesNothing() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = try await harness.paths.startFromRoutine("routine-push-a")
        let before = try XCTUnwrap(harness.engine.session)
        let invalid = try Fixtures.json("fixtures/invalid/exercise_push_unknown_origin.json")

        do {
            _ = try await harness.receive(invalid)
            XCTFail("a push from a sender the protocol does not define must be refused")
        } catch is WatchEmissionRejected {
            // Expected: nothing was persisted and nothing changed.
        }

        XCTAssertEqual(slotIds(harness.engine.session!), slotIds(before))
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, before.currentExerciseIndex)
    }

    // MARK: - S-004 routine edit propagates

    func testS004ANewerMessageReplacesTheCachedRoutineWithNoUserAction() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        let edit = try object(try startContract()["routineEdit"])

        _ = try await harness.receive(try object(edit["routinesDown"]))

        XCTAssertEqual(harness.paths.routines.count, 1)
        XCTAssertEqual(harness.paths.routines.first?.name, edit["expectedRoutineName"] as? String)
        XCTAssertEqual(
            harness.paths.routines.first.map(routineSlots),
            try strings(edit["expectedSlotIds"])
        )
        let payload = try object(try object(edit["routinesDown"])["payload"])
        XCTAssertEqual(
            harness.paths.syncedAt,
            try parseUtcIso(payload["generatedAt"])
        )
    }

    func testS004AnOlderMessageDoesNotRollTheCacheBack() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        let edit = try object(try startContract()["routineEdit"])
        _ = try await harness.receive(try object(edit["routinesDown"]))

        _ = try await harness.receive(try firstMessage())

        XCTAssertEqual(harness.paths.routines.first?.name, "Push A (deload)")
    }

    func testS004AMessageWhoseFallbackListMissesARoutineExerciseIsRejected() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        let invalid = try Fixtures.json(
            "fixtures/invalid/routines_down_unlisted_fallback_exercise.json"
        )

        let result = await harness.paths.applyRoutinesDown(invalid)

        XCTAssertFalse(result.applied)
        XCTAssertFalse(result.rejections.isEmpty)
        XCTAssertTrue(harness.paths.routines.isEmpty)
    }

    func testS004SyncingAppendsARowAndRewritesNothing() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        let edit = try object(try startContract()["routineEdit"])

        _ = try await harness.receive(try firstMessage())
        _ = try await harness.receive(try object(edit["routinesDown"]))
        let contents = await harness.store.readAll()

        XCTAssertEqual(contents.routineCatalogs.count, 2)
        XCTAssertEqual(
            contents.routineCatalogs.map { $0.routines.first?["name"] as? String },
            ["Push A", "Push A (deload)"],
            "the log keeps both versions; the newest one wins"
        )
    }

    // MARK: - S-007 modality / effort-kind parity with the phone

    func testS007EveryCapabilitySetResolvesTheWayThePhoneResolvesIt() async throws {
        // The native client mirrors the phone's precedence rather than reading
        // it: the contract is what keeps the two in step.
        let expectations: [[String]: String] = [
            ["sets", "reps", "load"]: "set",
            ["time", "hold"]: "drill",
            ["time", "distance"]: "timed",
            ["time", "rounds"]: "round",
            ["load"]: "set",
            ["hold"]: "drill",
        ]
        let cases = try objects(try startContract()["effortKindParity"])

        for example in cases {
            let capabilities = try strings(example["capabilities"])
            XCTAssertEqual(
                expectations[capabilities],
                example["effortKind"] as? String,
                "the contract and the resolver disagree for \(capabilities)"
            )
            let resolved = await effortKind(
                capabilities: capabilities,
                clock: { testInstant() }
            )
            XCTAssertEqual(
                resolved,
                example["effortKind"] as? String,
                "the logging surface disagrees with the contract for \(capabilities)"
            )
        }
    }

    func testS007ARoutineNamedEffortRendersTheKindTheRoutineDeclared() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        let sent = try WatchRoutinesDown(envelope: try firstMessage())
        let session = try await harness.paths.startFromRoutine("routine-push-a")

        // Walk the session the way the user would, asking the real surface what
        // each exercise is.
        var rendered: [String: String] = [:]
        while true {
            if let slot = harness.engine.currentExercise,
               let exerciseId = slot["exerciseId"] as? String {
                rendered[exerciseId] = harness.surface.effortKind
            }
            guard let index = harness.engine.session?.currentExerciseIndex,
                  index < session.exercises.count - 1
            else { break }
            _ = await harness.engine.advanceExercise()
        }

        for effort in sent.routines.flatMap(\.efforts) {
            XCTAssertEqual(
                rendered[effort.exerciseId],
                effort.effortKind,
                "\(effort.exerciseName) renders as the routine declares it"
            )
        }

        // The divergence D-6 closes: `Plank` carries `time` and `hold`, which the
        // capability rule reads as a drill, while the routine the user built
        // declares it `timed`. The routine wins — the wrist renders the surface
        // the phone's own routine sets up, not one inferred from a capability
        // list.
        let plank = try XCTUnwrap(
            sent.routines.flatMap(\.efforts).first { $0.exerciseName == "Plank" }
        )
        XCTAssertEqual(rendered[plank.exerciseId], WatchEffortKind.timed)
        let derived = await effortKind(
            capabilities: plank.capabilities,
            clock: harness.clock.call
        )
        XCTAssertNotEqual(
            derived,
            WatchEffortKind.timed,
            "the capability rule alone would have rendered a hold"
        )
    }

    func testS007APushedExerciseAndARoutineExerciseWithTheSameCapabilitiesAgree() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())
        _ = try await harness.paths.startFromRoutine("routine-push-a")
        let push = try object(try startContract()["exercisePush"])
        _ = try await harness.receive(try object(push["envelope"]))

        let pushed = try XCTUnwrap(
            harness.engine.session?.exercises.first {
                $0["sessionExerciseId"] as? String == push["pushedSlotId"] as? String
            }
        )
        let routineSlot = try XCTUnwrap(harness.engine.session?.exercises.first)
        XCTAssertEqual(pushed["capabilities"] as? [String], routineSlot["capabilities"] as? [String])

        let resolved = await effortKind(
            capabilities: (pushed["capabilities"] as? [String]) ?? [],
            clock: harness.clock.call
        )
        XCTAssertEqual(
            resolved,
            harness.surface.effortKind,
            "same capabilities, same surface, wherever the exercise came from"
        )
    }

    // MARK: - Proactive sync

    func testConnectPullsEverythingAndReconnectAsksOnlyForWhatChanged() async throws {
        let harness = WatchStartHarness()
        await harness.launch()

        await harness.orchestrator.sync()
        XCTAssertEqual(harness.transport.requested.count, 1)
        XCTAssertNil(harness.transport.requested[0])

        _ = try await harness.receive(try firstMessage())
        harness.transport.isPhoneReachable = true
        await harness.orchestrator.sync(reconnect: true)

        XCTAssertEqual(harness.transport.requested.count, 2)
        XCTAssertEqual(
            harness.transport.requested[1],
            harness.paths.syncedAt,
            "the second request carries the catalog it already has"
        )
        XCTAssertTrue(harness.paths.phoneReachable)
    }

    func testAnUnreachablePhoneNeverBlocksTheRoutinesTheWatchAlreadyHas() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())

        harness.transport.isPhoneReachable = false
        await harness.orchestrator.sync()

        XCTAssertFalse(harness.paths.phoneReachable)
        XCTAssertEqual(harness.paths.routines.count, 1)
        XCTAssertFalse(harness.paths.fallbackExercises.isEmpty)
    }

    // MARK: - The phone's preferences (D-113, D-114)

    func testThePhonesPreferencesAreRoutedStoredAndReadBackAfterARelaunch() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        XCTAssertNil(harness.preferences.current, "D-114 nothing is known before the first sync")
        XCTAssertFalse(harness.preferences.asksForEffortRating, "D-114 so the wrist does not ask")

        let applied = try await harness.receive(try Fixtures.json("fixtures/valid/preferences_down.json"))

        XCTAssertTrue(applied, "D-113 the orchestrator routes preferences_down to the preferences")
        XCTAssertEqual(harness.preferences.current?.effortRatingPrompt, false, "D-113")
        XCTAssertTrue(harness.transport.sent.isEmpty, "D-113 reference data is not answered")

        await harness.launch()
        XCTAssertEqual(
            harness.preferences.current?.effortRatingPrompt,
            false,
            "D-113 the setting is stored, so a relaunch still knows it"
        )
    }

    func testAPreferencesDownTheWristCannotReadIsRefusedAndChangesNothing() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(
            preferencesDown(true, generatedAt: "2026-09-25T08:00:00Z", messageId: "msg-prefs-on")
        )

        let applied = try await harness.receive(
            try Fixtures.json("fixtures/invalid/preferences_down_missing_effort_rating_prompt.json")
        )

        // Newer, and readable field by field — but a field the protocol does not
        // define makes it a message the wrist cannot read (the payload is closed).
        var surprise = preferencesDown(false, generatedAt: "2026-09-25T10:00:00Z", messageId: "msg-prefs-surprise")
        surprise["payload"] = [
            "generatedAt": "2026-09-25T10:00:00Z",
            "effortRatingPrompt": false,
            "surprise": true,
        ]
        let surpriseApplied = try await harness.receive(surprise)

        XCTAssertFalse(applied, "D-113 a copy the wrist cannot read is refused")
        XCTAssertFalse(surpriseApplied, "D-113 a copy the wrist cannot read is refused")
        XCTAssertEqual(harness.preferences.current?.effortRatingPrompt, true, "D-113 and changes nothing")
        let stored = await harness.store.readAll()
        XCTAssertEqual(stored.preferences.count, 1, "D-113 nothing of either is stored")
        XCTAssertTrue(harness.transport.sent.isEmpty, "D-113 reference data is not answered")
    }

    func testTheNewestPreferencesApplyAndALaterCopyWinsATie() async throws {
        let harness = WatchStartHarness()
        await harness.launch()

        _ = try await harness.receive(
            preferencesDown(true, generatedAt: "2026-09-25T09:30:00Z", messageId: "msg-prefs-new")
        )
        let older = try await harness.receive(
            preferencesDown(false, generatedAt: "2026-09-25T09:00:00Z", messageId: "msg-prefs-old")
        )
        XCTAssertFalse(older, "D-113 an older copy arriving late never replaces a newer one")
        XCTAssertEqual(harness.preferences.current?.effortRatingPrompt, true, "D-113")

        let tie = try await harness.receive(
            preferencesDown(false, generatedAt: "2026-09-25T09:30:00Z", messageId: "msg-prefs-tie")
        )
        XCTAssertTrue(tie, "D-113 on a tie, the later-received copy applies")
        XCTAssertEqual(harness.preferences.current?.effortRatingPrompt, false, "D-113")
    }
}
