//
//  WatchSessionEngineTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `.github/agents/plans/2026-07-13-06-a1-watch-session-engine-plan.md` —
//  the same scenarios the Dart suite proves in
//  `test/watch_session_engine_test.dart`, run against the Swift engine.
//
//  Process death is simulated the way the watch experiences it: a brand-new
//  engine is constructed over the same storage and asked to restore. Anything
//  the engine failed to persist is lost by construction.
//

import XCTest

@testable import WatchSessionEngine

/// Deterministic clock: the engine reads time only through its injected clock,
/// which is what lets these tests assert wall-clock derivation instead of
/// counters.
final class TestClock {
    var now: Date

    init(_ now: Date) { self.now = now }

    func advance(_ seconds: Double) { now = now.addingTimeInterval(seconds) }

    func call() -> Date { now }
}

final class Harness {
    let clock: TestClock
    let store: WatchSessionStore
    let sessionId: String
    private(set) var emitted: [[String: Any]] = []
    private var ids = 0

    init(store: WatchSessionStore = InMemoryWatchSessionStore(), sessionId: String = "s-watch-1") {
        self.clock = TestClock(testInstant())
        self.store = store
        self.sessionId = sessionId
    }

    /// A fresh engine over the same storage — a relaunch, not a hand-over.
    func newEngine() -> WatchSessionEngine {
        WatchSessionEngine(
            store: store,
            onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
            validator: Self.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.ids += 1
                return "rec-\(self.ids)"
            },
            sessionIdFactory: { [weak self] in self?.sessionId ?? "s-watch-1" }
        )
    }

    /// An engine that has already restored, i.e. one that is running.
    func runningEngine(_ engine: WatchSessionEngine? = nil) async -> WatchSessionEngine {
        let live = engine ?? newEngine()
        await live.restore()
        return live
    }

    static func validator() -> SyncProtocolValidator {
        SyncProtocolValidator(
            schemaDocuments: (try? Fixtures.schemaDocuments()) ?? [:]
        )
    }
}

func exercise(_ slot: String) -> [String: Any] {
    [
        "sessionExerciseId": slot,
        "exerciseId": "ex-\(slot)",
        "name": slot,
        "capabilities": ["reps", "sets", "load"],
    ]
}

/// A fixed instant, built from components so the test never depends on a
/// hand-computed epoch: 2026-07-13T06:00:00Z.
func testInstant() -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 7
    components.day = 13
    components.hour = 6
    components.timeZone = TimeZone(secondsFromGMT: 0)
    return Calendar(identifier: .gregorian).date(from: components)!
}

/// A schema-conformant `set` observation, the way the watch's logging surfaces
/// will hand it to the engine.
func setEvent(_ clock: TestClock, entryId: String, slot: String = "sx-bench") -> [String: Any] {
    [
        "entryId": entryId,
        "eventId": entryId,
        "kind": "set",
        "loggedAt": utcIso(clock.now),
        "sessionExerciseId": slot,
        "exerciseId": "ex-\(slot)",
        "reps": 5,
        "loadKg": 80,
    ]
}

final class WatchSessionEngineTests: XCTestCase {

    // MARK: - S-001 force-kill restores an in-progress session

    func testS001RestoresEntriesPositionAndWallClockTimer() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [exercise("sx-bench"), exercise("sx-plank")]
        )

        for entryId in ["e-1", "e-2", "e-3"] {
            try await engine.appendObservation(setEvent(harness.clock, entryId: entryId))
            harness.clock.advance(120)
        }
        _ = try await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 180_000)

        // Killed 30 s into the rest timer; relaunched two minutes later.
        harness.clock.advance(30)
        _ = await engine.advanceExercise()
        harness.clock.advance(120)

        let relaunched = await harness.runningEngine()

        let session = try XCTUnwrap(relaunched.session)
        XCTAssertEqual(session.currentExerciseIndex, 1)
        XCTAssertEqual(session.status, WatchSessionStatus.active)
        XCTAssertEqual(relaunched.observations.map(\.entryId), ["e-1", "e-2", "e-3"])
        XCTAssertEqual(relaunched.observations[0].payload["reps"] as? Int, 5)

        let rest = try XCTUnwrap(relaunched.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(rest.state, WatchTimerState.running)
        XCTAssertEqual(
            remainingMs(rest, now: harness.clock.now),
            180_000 - 150_000,
            "remaining time derives from startedAt and the current clock, "
                + "never from a counter frozen at kill time"
        )
    }

    func testS001PausedTimerRestoresPausedWithRemainingTimeHeld() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-plank")])

        _ = try await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 120_000)
        harness.clock.advance(20)
        _ = await engine.pauseTimer()

        let relaunched = await harness.runningEngine()
        let rest = try XCTUnwrap(relaunched.timerFor(WatchTimerKind.rest))

        XCTAssertEqual(rest.state, WatchTimerState.paused)
        XCTAssertEqual(remainingMs(rest, now: harness.clock.now), 120_000 - 20_000)
    }

    func testS001RestoringOverAnUntouchedStoreYieldsNoSession() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        XCTAssertNil(engine.session)
        XCTAssertTrue(engine.observations.isEmpty)
        XCTAssertNil(engine.timerFor(WatchTimerKind.rest))
    }

    // MARK: - S-002 reboot restores the session identically

    func testS002ASecondProcessRestoresTheSameSession() async throws {
        let first = Harness()
        let firstEngine = await first.runningEngine()
        _ = await firstEngine.createSession(
            modality: "cardio_endurance",
            exercises: [exercise("sx-row")]
        )
        try await firstEngine.appendObservation(setEvent(first.clock, entryId: "e-1"))
        _ = try await firstEngine.startTimer(WatchTimerKind.elapsed, plannedDurationMs: 600_000)
        first.clock.advance(240)

        // Reboot: the in-memory store stands in for the device's storage, and a
        // brand-new engine is the freshly launched process.
        let second = Harness(store: first.store, sessionId: first.sessionId)
        second.clock.now = first.clock.now
        let relaunched = await second.runningEngine()

        let session = try XCTUnwrap(relaunched.session)
        XCTAssertEqual(session.modality, "cardio_endurance")
        XCTAssertEqual(session.startedAt, first.clock.now.addingTimeInterval(-240))
        XCTAssertEqual(relaunched.observations.map(\.entryId), ["e-1"])
        XCTAssertEqual(
            remainingMs(try XCTUnwrap(relaunched.timerFor(WatchTimerKind.elapsed)),
                        now: second.clock.now),
            600_000 - 240_000
        )
    }

    // MARK: - S-003 logging with the phone unreachable delivers exactly once

    func testS003EveryEntryIsPersistedAndReplayedWithTheSameIdentity() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])

        for entryId in ["e-1", "e-2", "e-3"] {
            try await engine.appendObservation(setEvent(harness.clock, entryId: entryId))
            harness.clock.advance(60)
        }

        // A session start announces itself; the three entries follow it.
        XCTAssertEqual(
            harness.emitted.map { $0["type"] as? String },
            ["session_lifecycle", "observations_up", "observations_up", "observations_up"]
        )

        // Killed before anything left the watch: the replay rebuilds the same
        // events from persisted rows rather than inventing new ones.
        let logged = harness.emitted.filter { $0["type"] as? String == "observations_up" }
        let relaunched = await harness.runningEngine()
        let replay = relaunched.pendingObservations()
        XCTAssertEqual(
            replay.map { $0["messageId"] as? String },
            logged.map { $0["messageId"] as? String }
        )

        let validator = Harness.validator()
        for envelope in harness.emitted + replay {
            XCTAssertTrue(validator.validateEnvelope(envelope).isEmpty)
        }

        let eventIds = Set(
            replay.compactMap { envelope -> String? in
                ((envelope["payload"] as? [String: Any])?["events"] as? [[String: Any]])?
                    .first?["eventId"] as? String
            }
        )
        XCTAssertEqual(eventIds, ["e-1", "e-2", "e-3"])
    }

    // MARK: - S-004 append-only enforcement at the storage API

    func testS004NoMutatingOperationExistsAnywhereInTheModule() throws {
        // Exactly five names are deliberate. `pruneConfirmed` and
        // `pruneSensorSamples` are the two ways anything leaves the store, and
        // each is gated on having nothing left to lose: confirmed observations
        // for the first, and for the second a session that is over whose numbers
        // the phone has already recorded in full. A third prune, or a wider
        // gate, has to be added here on purpose.
        let allowed: Set<String> = [
            "append",
            "readAll",
            "pruneConfirmed",
            "pruneSensorSamples",
        ]
        let verbs = "update|delete|remove|replace|edit|overwrite|write|clear"
            + "|purge|wipe|reset|drop|truncate|erase|forget|modify|mutate|destroy|set"
        let mutating = try NSRegularExpression(
            pattern: "^ {4}(?:public |private |internal |fileprivate |open |static "
                + "|override |mutating )*func _?(\(verbs))",
            options: [.anchorsMatchLines]
        )
        let declaration = try NSRegularExpression(
            pattern: "^ {4}((?:public |private |internal |fileprivate |open |static "
                + "|override |mutating )*)func (\\w+)",
            options: [.anchorsMatchLines]
        )

        let files = try FileManager.default
            .contentsOfDirectory(at: Fixtures.sourcesRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)

            XCTAssertTrue(
                mutating.firstMatch(in: source, range: range) == nil,
                "\(file.lastPathComponent) declares a mutating operation. Synced "
                    + "entities are append-only: nothing may be named for a mutation."
            )

            guard file.lastPathComponent.hasSuffix("Store.swift") else { continue }

            // Every store — the protocol and each implementation — is pinned to
            // the same public surface, so a method added to any of them is a
            // mutation entry point the append-only rule forbids. A declaration
            // with no modifier is a protocol requirement, i.e. public API.
            let exposed = Set(
                declaration.matches(in: source, range: range).compactMap { match -> String? in
                    guard let modifiersRange = Range(match.range(at: 1), in: source),
                          let nameRange = Range(match.range(at: 2), in: source)
                    else { return nil }
                    let name = String(source[nameRange])
                    let modifiers = String(source[modifiersRange])
                    guard !["init", "deinit"].contains(name),
                          modifiers.isEmpty || modifiers.contains("public")
                    else { return nil }
                    return name
                }
            )
            XCTAssertEqual(
                exposed,
                allowed,
                "\(file.lastPathComponent) exposes \(exposed.sorted()). The store "
                    + "contract is exactly \(allowed.sorted()) — anything else is "
                    + "a mutation entry point the append-only rule forbids"
            )
        }

        let engineSource = try String(
            contentsOf: Fixtures.sourcesRoot.appendingPathComponent("WatchSessionEngine.swift"),
            encoding: .utf8
        )
        let storeCall = try NSRegularExpression(pattern: "(?<![\\w])store\\.(\\w+)")
        let engineRange = NSRange(engineSource.startIndex..<engineSource.endIndex, in: engineSource)
        let calls = Set(
            storeCall.matches(in: engineSource, range: engineRange).compactMap { match -> String? in
                guard let captured = Range(match.range(at: 1), in: engineSource) else { return nil }
                return String(engineSource[captured])
            }
        )
        XCTAssertTrue(
            calls.subtracting(allowed).isEmpty,
            "the engine reaches for a store method outside the append-only contract: \(calls.sorted())"
        )
    }

    // MARK: - S-005 / S-006 retention

    func testS005UnconfirmedEntriesAreNeverPruned() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])

        for entryId in ["e-1", "e-2", "e-3", "e-4", "e-5"] {
            try await engine.appendObservation(setEvent(harness.clock, entryId: entryId))
        }
        _ = await engine.confirmObservations(["e-1", "e-2"])

        let pruned = await engine.pruneConfirmed()
        let stored = await harness.store.readAll()

        XCTAssertEqual(Set(pruned), ["e-1", "e-2"])
        XCTAssertEqual(engine.observations.map(\.entryId), ["e-3", "e-4", "e-5"])
        XCTAssertEqual(engine.pendingObservations().count, 3)
        XCTAssertEqual(stored.observations.map(\.entryId), ["e-3", "e-4", "e-5"])
    }

    func testS006ConfirmedEntriesMayBePruned() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))

        _ = await engine.confirmObservations(["e-1"])
        XCTAssertEqual(
            engine.observations[0].confirmedAt,
            harness.clock.now,
            "confirmation is durable: the watch must remember what it may drop "
                + "across a relaunch"
        )

        let relaunched = await harness.runningEngine()
        let pruned = await relaunched.pruneConfirmed()

        XCTAssertEqual(pruned, ["e-1"])
        XCTAssertTrue(relaunched.observations.isEmpty)
    }

    // MARK: - Timer derivation

    func testTimerMathFollowsTheClockAcrossEveryState() throws {
        let start = testInstant()
        func timer(
            pausedAt: Date? = nil,
            stoppedAt: Date? = nil,
            accumulatedPauseMs: Int = 0,
            plannedDurationMs: Int? = nil
        ) -> WatchTimerRecord {
            WatchTimerRecord(
                recordId: "t-1",
                sessionId: "s-1",
                recordedAt: start,
                kind: WatchTimerKind.rest,
                startedAt: start,
                pausedAt: pausedAt,
                stoppedAt: stoppedAt,
                accumulatedPauseMs: accumulatedPauseMs,
                plannedDurationMs: plannedDurationMs
            )
        }

        let running = timer(plannedDurationMs: 180_000)
        XCTAssertEqual(activeElapsedMs(running, now: start.addingTimeInterval(45)), 45_000)
        XCTAssertEqual(remainingMs(running, now: start.addingTimeInterval(45)), 135_000)
        XCTAssertEqual(
            remainingMs(running, now: start.addingTimeInterval(1_800)),
            0,
            "a finished timer reads zero, never a negative remainder"
        )

        let paused = timer(pausedAt: start.addingTimeInterval(30), plannedDurationMs: 180_000)
        XCTAssertEqual(
            remainingMs(paused, now: start.addingTimeInterval(3_600)),
            150_000,
            "pause freezes the remaining time"
        )

        let resumed = timer(accumulatedPauseMs: 45_000, plannedDurationMs: 180_000)
        XCTAssertEqual(
            activeElapsedMs(resumed, now: start.addingTimeInterval(120)),
            75_000,
            "paused time is accounted for, not counted as work"
        )

        let stopped = timer(stoppedAt: start.addingTimeInterval(10), plannedDurationMs: 180_000)
        XCTAssertEqual(
            remainingMs(stopped, now: start.addingTimeInterval(7_200)),
            170_000,
            "a stopped timer stops moving"
        )

        XCTAssertNil(remainingMs(timer(), now: start.addingTimeInterval(300)))
    }

    func testPauseAndResumeAccumulateThePauseWithoutTouchingStartedAt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-row")])

        let startedAt = harness.clock.now
        _ = try await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 120_000)
        harness.clock.advance(30)
        _ = await engine.pauseTimer()
        harness.clock.advance(40)
        _ = await engine.resumeTimer()
        harness.clock.advance(20)

        let rest = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(rest.startedAt, startedAt)
        XCTAssertEqual(rest.accumulatedPauseMs, 40_000)
        XCTAssertEqual(rest.state, WatchTimerState.running)
        XCTAssertEqual(remainingMs(rest, now: harness.clock.now), 120_000 - 50_000)
    }

    func testAdvancingPastTheLastExerciseStaysOnIt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: [exercise("sx-bench"), exercise("sx-row")]
        )

        _ = await engine.advanceExercise()
        _ = await engine.advanceExercise()
        XCTAssertEqual(engine.session?.currentExerciseIndex, 1)

        _ = await engine.finishSession()
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed)
    }

    // MARK: - Close paths

    func testAbandoningASessionKeepsWhatWasAlreadyLogged() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        for entryId in ["e-1", "e-2"] {
            _ = try await engine.appendObservation(setEvent(harness.clock, entryId: entryId))
        }

        _ = await engine.abandonSession()
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.abandoned)

        let relaunched = await harness.runningEngine()
        XCTAssertEqual(relaunched.session?.status, WatchSessionStatus.abandoned)
        XCTAssertEqual(
            relaunched.observations.map(\.entryId),
            ["e-1", "e-2", "end-s-watch-1"],
            "giving up on the session does not discard work already logged, and "
                + "the session's end records that it was abandoned (D-120)"
        )
    }

    // MARK: - D-120 a session the wrist created ends exactly once

    private func sessionEnd(_ engine: WatchSessionEngine) -> [String: Any]? {
        engine.observations.first { $0.kind == WatchObservationKind.sessionEnd }?.payload
    }

    private func lifecycle(_ state: String, at: String, messageId: String) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": "s-watch-1",
            "type": "session_lifecycle",
            "origin": "phone",
            "sentAt": at,
            "payload": ["state": state, "at": at],
        ]
    }

    func testTheWristsEndIsStoredAndSentBeforeTheSessionIsMarkedComplete() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        let startedAt = harness.clock.now
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))
        harness.clock.advance(600)

        _ = await engine.finishSession()

        let end = try XCTUnwrap(sessionEnd(engine), "D-120 the wrist's End appends the session's end")
        XCTAssertEqual(end["entryId"] as? String, "end-s-watch-1")
        XCTAssertEqual(end["eventId"] as? String, "end-s-watch-1")
        XCTAssertEqual(end["status"] as? String, WatchSessionStatus.completed)
        XCTAssertEqual(end["startedAt"] as? String, utcIso(startedAt))
        XCTAssertEqual(end["endedAt"] as? String, utcIso(harness.clock.now), "D-120 the wrist's clock at End")
        XCTAssertEqual(end["loggedAt"] as? String, utcIso(harness.clock.now))
        XCTAssertEqual(end["modality"] as? String, "resistance_lifting", "D-120 the session's modality, when it has one")
        XCTAssertNil(end["avgHeartRateBpm"], "no reading, no pair — never a zero")

        XCTAssertEqual(
            harness.emitted.suffix(2).map { $0["type"] as? String },
            ["observations_up", "session_lifecycle"],
            "D-120 the end goes before the row that completes the session"
        )
        let stored = await harness.store.readAll()
        let endRow = try XCTUnwrap(stored.observations.first { $0.entryId == "end-s-watch-1" })
        let completedRow = try XCTUnwrap(stored.sessions.last)
        XCTAssertEqual(completedRow.status, WatchSessionStatus.completed)
        XCTAssertLessThan(endRow.sequence, completedRow.sequence, "D-120 stored before anything else for the session")
        for envelope in harness.emitted {
            XCTAssertTrue(Harness.validator().validateEnvelope(envelope).isEmpty)
        }
    }

    func testAbandoningEndsTheSessionAsAbandoned() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])

        _ = await engine.abandonSession()

        XCTAssertEqual(sessionEnd(engine)?["status"] as? String, WatchSessionStatus.abandoned, "D-120")
        XCTAssertNil(sessionEnd(engine)?["modality"], "D-120 a session with no modality says none")
    }

    func testThePhonesLifecycleEndsAWristSessionAtTheMomentItNames() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        harness.clock.advance(900)

        _ = try await engine.applyMessage(
            lifecycle(WatchLifecycleState.abandoned, at: "2026-07-13T06:10:00Z", messageId: "msg-life-1")
        )
        _ = try await engine.applyMessage(
            lifecycle(WatchLifecycleState.completed, at: "2026-07-13T06:12:00Z", messageId: "msg-life-2")
        )

        let ends = engine.observations.filter { $0.kind == WatchObservationKind.sessionEnd }
        XCTAssertEqual(ends.count, 1, "D-120 the first terminal transition ends it; the second does not")
        XCTAssertEqual(ends.first?.payload["status"] as? String, WatchSessionStatus.abandoned)
        XCTAssertEqual(ends.first?.payload["endedAt"] as? String, "2026-07-13T06:10:00.000Z", "D-120 the payload's `at`")
        XCTAssertEqual(
            ends.first?.payload["loggedAt"] as? String,
            utcIso(harness.clock.now),
            "D-120 appended on the wrist's own clock"
        )
    }

    func testThePhonesSnapshotEndsAWristSessionOnceAtItsSentAt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let snapshot: [String: Any] = [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-snap-end",
            "sessionId": "s-watch-1",
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-07-13T06:30:00Z",
            "payload": [
                "sessionId": "s-watch-1",
                "revision": 0,
                "status": WatchSessionStatus.completed,
                "currentExerciseIndex": 0,
                "exercises": [exercise("sx-bench")],
                "entries": [[String: Any]](),
                "timers": [String: Any](),
            ] as [String: Any],
        ]

        _ = try await engine.applyMessage(snapshot)
        _ = try await engine.applyMessage(snapshot)

        let ends = engine.observations.filter { $0.kind == WatchObservationKind.sessionEnd }
        XCTAssertEqual(ends.count, 1, "D-120 one end, however often the phone says so")
        XCTAssertEqual(ends.first?.payload["endedAt"] as? String, "2026-07-13T06:30:00.000Z", "D-120 the snapshot's sentAt")
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed)
    }

    func testAReopenedSessionThatEndsAgainKeepsItsFirstEnd() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))
        _ = await engine.finishSession()
        let first = try XCTUnwrap(sessionEnd(engine))

        harness.clock.advance(60)
        _ = try await engine.applyMessage(
            lifecycle(WatchLifecycleState.started, at: "2026-07-13T06:01:00Z", messageId: "msg-reopen")
        )
        harness.clock.advance(60)
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-2"))
        _ = await engine.finishSession()

        let ends = engine.observations.filter { $0.kind == WatchObservationKind.sessionEnd }
        XCTAssertEqual(ends.count, 1, "D-120 a reopened session gets no second end")
        XCTAssertEqual(ends.first?.payload["endedAt"] as? String, first["endedAt"] as? String)
    }

    func testAnEndThePhoneAcknowledgedIsNeverAppendedAgainAfterAPrune() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = await engine.finishSession()
        _ = await engine.confirmObservations(["end-s-watch-1"])
        _ = await engine.pruneConfirmed()

        let relaunched = await harness.runningEngine()
        _ = try await relaunched.applyMessage(
            lifecycle(WatchLifecycleState.started, at: "2026-07-13T06:05:00Z", messageId: "msg-reopen")
        )
        _ = await relaunched.finishSession()

        XCTAssertNil(sessionEnd(relaunched), "D-120 the session had its end; a receipt outlives the row it names")
        XCTAssertTrue(relaunched.pendingObservations().isEmpty)
    }

    func testASessionTheWristJoinedEndsWithNoEnd() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage([
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-join",
            "sessionId": "s-phone",
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-07-13T06:00:00Z",
            "payload": [
                "sessionId": "s-phone",
                "revision": 0,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 0,
                "exercises": [exercise("sx-bench")],
                "entries": [[String: Any]](),
                "timers": [String: Any](),
            ] as [String: Any],
        ])

        _ = await engine.finishSession()

        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed)
        XCTAssertNil(sessionEnd(engine), "D-120 a session the wrist joined from the phone gets none")
    }

    // MARK: - S-240 resend across sessions

    func testS240EveryUnacknowledgedObservationOfEverySessionIsResentInStoreOrder() async throws {
        let harness = Harness()
        var sessionIds = ["s-a", "s-b"]
        var recordIds = 0
        let engine = WatchSessionEngine(
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call,
            idFactory: {
                recordIds += 1
                return "rec-\(recordIds)"
            },
            sessionIdFactory: { sessionIds.removeFirst() }
        )
        await engine.restore()

        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-a1"))
        harness.clock.advance(60)
        _ = await engine.finishSession() // ended with the phone out of reach
        harness.clock.advance(3600)
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-b1"))

        func owed(_ envelopes: [[String: Any]]) -> [String] {
            envelopes.compactMap {
                (($0["payload"] as? [String: Any])?["events"] as? [[String: Any]])?.first?["entryId"] as? String
            }
        }
        let pending = engine.pendingObservations()
        XCTAssertEqual(
            owed(pending),
            ["e-a1", "end-s-a", "e-b1"],
            "S-240 session A's events, then B's, in the order they were stored"
        )
        XCTAssertEqual(pending.map { $0["sessionId"] as? String }, ["s-a", "s-a", "s-b"], "S-240")
        for envelope in pending {
            XCTAssertTrue(Harness.validator().validateEnvelope(envelope).isEmpty, "S-240")
        }

        _ = try await engine.applyMessage([
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-receipt-a",
            "type": "receipt",
            "origin": "phone",
            "sentAt": utcIso(harness.clock.now),
            "payload": ["entryIds": ["e-a1", "end-s-a"]],
        ])

        XCTAssertEqual(owed(engine.pendingObservations()), ["e-b1"], "S-240 a receipt for A's ids removes them")
    }

    func testAStoppedTimerFreezesTheTimeItHadReached() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-row")])

        _ = try await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 180_000)
        harness.clock.advance(45)
        _ = await engine.stopTimer()

        let stopped = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(stopped.state, WatchTimerState.stopped)
        XCTAssertEqual(remainingMs(stopped, now: harness.clock.now), 135_000)

        // Killed ten minutes after the stop: the readout derives from the stored
        // stop instant, so it must not have kept counting.
        harness.clock.advance(600)
        let relaunched = await harness.runningEngine()
        let restored = try XCTUnwrap(relaunched.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(restored.state, WatchTimerState.stopped)
        XCTAssertEqual(remainingMs(restored, now: harness.clock.now), 135_000)
    }
}
