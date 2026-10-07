//
//  WatchSessionEngineTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-07-13-06-a1-watch-session-engine-plan.md` —
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

    /// Forget what has been emitted so far, so a test asserts its own frame and
    /// not the session setup's.
    func clearEmitted() { emitted.removeAll() }

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

        // A session start announces itself — the lifecycle frame, then the
        // snapshot carrying the ladder (D-91) — and the three entries follow both.
        XCTAssertEqual(
            harness.emitted.map { $0["type"] as? String },
            [
                "session_lifecycle", "session_snapshot",
                "observations_up", "observations_up", "observations_up",
            ]
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

    // MARK: - S-48 / G3 a pruned row takes its lens with it

    func testS48APrunedRowTakesItsCorrectionWithIt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])

        for entryId in ["e-1", "e-2", "e-3"] {
            try await engine.appendObservation(setEvent(harness.clock, entryId: entryId))
        }
        _ = try await engine.applyMessage(
            structureChangeMessage(
                changeId: "chg-correct-1",
                changes: [
                    ["kind": "correct_entry", "entryId": "e-1", "correction": ["loadKg": 70.0]]
                ]
            )
        )
        XCTAssertEqual(
            engine.entries.first { $0.entryId == "e-1" }?.payload["loadKg"] as? Double,
            70,
            "S-48 the phone's correction is what the wrist shows"
        )
        _ = await engine.confirmObservations(["e-1", "e-2"])

        let pruned = await engine.pruneConfirmed()
        XCTAssertEqual(Set(pruned), ["e-1", "e-2"], "S-48 the confirmed rows are the ones dropped")

        _ = try await engine.applyMessage(
            snapshotMessage(
                messageId: "msg-resend-1",
                sessionId: harness.sessionId,
                revision: 7,
                entries: [entryMap("e-1", at: utcIso(testInstant()), loadKg: 60)]
            )
        )

        XCTAssertEqual(
            engine.entries.map(\.entryId),
            ["e-1", "e-3"],
            "S-48 the re-carried id is a fresh row again, and the unconfirmed entry is untouched"
        )
        XCTAssertEqual(
            engine.entries.first { $0.entryId == "e-1" }?.payload["loadKg"] as? Double,
            60,
            "S-48/G3 a pruned row takes its correction with it: the fresh row shows what was delivered, not 70"
        )
    }

    func testS48APrunedRowTakesItsDeletionMarkerWithIt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))

        _ = try await engine.applyMessage(
            structureChangeMessage(
                changeId: "chg-delete-1",
                changes: [["kind": "delete_entry", "entryId": "e-1"]]
            )
        )
        XCTAssertTrue(engine.entries.isEmpty, "S-48 the phone's deletion hides the entry")

        _ = await engine.confirmObservations(["e-1"])
        let pruned = await engine.pruneConfirmed()
        XCTAssertEqual(pruned, ["e-1"], "S-48 the deleted row is still a stored row, so a prune drops it")

        _ = try await engine.applyMessage(
            snapshotMessage(
                messageId: "msg-resend-2",
                sessionId: harness.sessionId,
                revision: 8,
                entries: [entryMap("e-1", at: utcIso(testInstant()), loadKg: 60)]
            )
        )

        XCTAssertEqual(
            engine.entries.map(\.entryId),
            ["e-1"],
            "S-48/G3 the deletion marker went with the pruned row, so a re-carried id is shown again"
        )
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

    /// A phone entry, as a snapshot carries it.
    private func entryMap(_ entryId: String, at loggedAt: String, loadKg: Double) -> [String: Any] {
        [
            "entryId": entryId,
            "eventId": entryId,
            "kind": "set",
            "loggedAt": loggedAt,
            "sessionExerciseId": "sx-bench",
            "exerciseId": "ex-sx-bench",
            "reps": 8,
            "loadKg": loadKg,
        ]
    }

    /// One `session_snapshot` from the phone, over the wrist's own session.
    private func snapshotMessage(
        messageId: String,
        sessionId: String,
        revision: Int,
        entries: [[String: Any]]
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
                "exercises": [exercise("sx-bench")],
                "entries": entries,
                "timers": [String: Any](),
            ] as [String: Any],
        ]
    }

    /// One `structure_change` from the phone, over the wrist's own session.
    private func structureChangeMessage(
        changeId: String,
        changes: [[String: Any]]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-\(changeId)",
            "sessionId": "s-watch-1",
            "type": "structure_change",
            "origin": "phone",
            "sentAt": "2026-07-13T06:30:00Z",
            "payload": ["changeId": changeId, "changes": changes],
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

    // MARK: - S-77/S-78 the wrist's session-acceptance rules

    /// A phone frame about whichever session the caller names — S-77 and S-78
    /// are both about a frame the wrist must refuse.
    private func phoneFrame(
        _ type: String,
        sessionId: String,
        messageId: String,
        payload: [String: Any]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": type,
            "origin": "phone",
            "sentAt": "2026-07-13T06:30:00Z",
            "payload": payload,
        ]
    }

    private func snapshotFrame(
        _ sessionId: String,
        messageId: String,
        status: String = WatchSessionStatus.active,
        exercises: [[String: Any]],
        entries: [[String: Any]] = [],
        timers: [String: Any] = [:]
    ) -> [String: Any] {
        phoneFrame("session_snapshot", sessionId: sessionId, messageId: messageId, payload: [
            "sessionId": sessionId,
            "revision": 1,
            "status": status,
            "currentExerciseIndex": 0,
            "exercises": exercises,
            "entries": entries,
            "timers": timers,
        ])
    }

    private func lifecycleFrame(
        _ sessionId: String,
        messageId: String,
        state: String,
        exerciseIndex: Int? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = ["state": state, "at": "2026-07-13T06:30:00Z"]
        if let exerciseIndex { payload["exerciseIndex"] = exerciseIndex }
        return phoneFrame("session_lifecycle", sessionId: sessionId, messageId: messageId, payload: payload)
    }

    private func timerStateFrame(
        _ sessionId: String,
        messageId: String,
        timers: [String: Any]
    ) -> [String: Any] {
        phoneFrame("timer_state", sessionId: sessionId, messageId: messageId, payload: ["timers": timers])
    }

    private func structureChangeFrame(
        _ sessionId: String,
        changeId: String,
        changes: [[String: Any]]
    ) -> [String: Any] {
        phoneFrame(
            "structure_change",
            sessionId: sessionId,
            messageId: "msg-\(changeId)",
            payload: ["changeId": changeId, "changes": changes]
        )
    }

    private func exercisePushFrame(
        _ sessionId: String,
        messageId: String,
        slot: String
    ) -> [String: Any] {
        phoneFrame("exercise_push", sessionId: sessionId, messageId: messageId, payload: [
            "exercise": exercise(slot),
            "insertAtIndex": 1,
        ])
    }

    private func timerJson(_ kind: String, startedAt: String, plannedDurationMs: Int = 60_000) -> [String: Any] {
        [
            "kind": kind,
            "state": WatchTimerState.running,
            "startedAt": startedAt,
            "plannedDurationMs": plannedDurationMs,
        ]
    }

    /// The wrist mid-workout, holding its own `s-2` — the fixture S-77 and S-78
    /// are measured against. Holding nothing would prove nothing.
    private func wristMidWorkout() async -> (Harness, WatchSessionEngine) {
        let harness = Harness(sessionId: "s-2")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-9")])
        _ = try? await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 90_000)
        harness.clearEmitted()
        return (harness, engine)
    }

    /// Applies one frame the wrist must refuse, and asserts it left `s-2` exactly
    /// as it was: nothing applied, nothing stored, nothing emitted.
    private func assertRefused(
        _ frame: [String: Any],
        _ engine: WatchSessionEngine,
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let before = await harness.store.readAll()

        let applied = try await engine.applyMessage(frame)

        XCTAssertFalse(applied, "D-79", file: file, line: line)
        XCTAssertEqual(engine.session?.sessionId, "s-2", file: file, line: line)
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.active, file: file, line: line)
        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-9"],
            "a frame naming another session is about another session",
            file: file,
            line: line
        )
        XCTAssertEqual(engine.session?.currentExerciseIndex, 0, file: file, line: line)
        let after = await harness.store.readAll()
        XCTAssertEqual(after.sessions.count, before.sessions.count, file: file, line: line)
        XCTAssertEqual(after.timers.count, before.timers.count, file: file, line: line)
        XCTAssertTrue(harness.emitted.isEmpty, file: file, line: line)
    }

    func testS77AForeignSnapshotChangesNothingAndSaysNothing() async throws {
        let (harness, engine) = await wristMidWorkout()

        let applied = try await engine.applyMessage(
            snapshotFrame(
                "s-1",
                messageId: "msg-p-1",
                exercises: [exercise("sx-1"), exercise("sx-2")],
                entries: [entryMap("e-p1", at: "2026-07-13T06:30:00Z", loadKg: 80)]
            )
        )

        XCTAssertFalse(applied, "the phone is in its own session")
        XCTAssertEqual(engine.session?.sessionId, "s-2")
        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-9"],
            "the wrist is mid-workout; the phone's ladder is not its"
        )
        XCTAssertFalse(
            engine.observations.contains { $0.entryId == "e-p1" },
            "a foreign snapshot brings no entries with it"
        )
        let stored = await harness.store.readAll()
        XCTAssertEqual(stored.sessions.count, 1, "a refused snapshot writes no row of its own")
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.running,
            "a refused frame is no reason for the wrist to stop anything"
        )
        XCTAssertTrue(harness.emitted.isEmpty, "no receipt, no answer, no lifecycle — nothing at all")
    }

    /// The refusal runs ahead of the snapshot's end capture, so a frame the wrist
    /// refuses cannot end a session the wrist created earlier (D-78).
    func testS77ARefusedSnapshotDoesNotEndASessionTheWristCreatedEarlier() async throws {
        let harness = Harness(sessionId: "s-1")
        let engine = await harness.runningEngine()
        // The wrist's own session, still empty: the phone's workout takes over
        // (the empty-ladder counter-case), which is how the wrist comes to hold a
        // session of the phone's while the row it created is still open.
        _ = await engine.createSession(modality: nil, exercises: [])
        _ = try await engine.applyMessage(
            snapshotFrame("s-2", messageId: "msg-p-2", exercises: [exercise("sx-2")])
        )
        XCTAssertEqual(engine.session?.sessionId, "s-2")
        XCTAssertTrue(engine.observations.isEmpty)
        let before = await harness.store.readAll()

        let applied = try await engine.applyMessage(
            snapshotFrame(
                "s-1",
                messageId: "msg-p-1",
                status: WatchSessionStatus.completed,
                exercises: [exercise("sx-1")]
            )
        )

        XCTAssertFalse(applied, "s-2 is running, so s-1 is not the wrist's business")
        XCTAssertEqual(engine.session?.sessionId, "s-2")
        let after = await harness.store.readAll()
        XCTAssertEqual(
            after.observations.count,
            before.observations.count,
            "a refused snapshot captures no end for the session it names"
        )
    }

    func testS77TheSameSnapshotAppliesOnceTheWristHasFinished() async throws {
        let harness = Harness(sessionId: "s-2")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-9")])
        _ = await engine.finishSession()
        harness.clearEmitted()

        let applied = try await engine.applyMessage(
            snapshotFrame("s-1", messageId: "msg-p-1", exercises: [exercise("sx-1"), exercise("sx-2")])
        )

        XCTAssertTrue(applied, "the phone's next workout is the ordinary case")
        XCTAssertEqual(engine.session?.sessionId, "s-1")
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.active)
        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-1", "sx-2"]
        )
    }

    func testS77AWristWithAnEmptyLadderReservesNothing() async throws {
        let harness = Harness(sessionId: "s-2")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil)

        let applied = try await engine.applyMessage(
            snapshotFrame("s-1", messageId: "msg-p-1", exercises: [exercise("sx-1")])
        )

        XCTAssertTrue(applied, "no exercise to interrupt means nothing to refuse")
        XCTAssertEqual(engine.session?.sessionId, "s-1")
    }

    func testS78ALifecycleForAnotherSessionConcernsNobodyHere() async throws {
        let (harness, engine) = await wristMidWorkout()

        try await assertRefused(
            lifecycleFrame("s-1", messageId: "msg-life-1", state: WatchLifecycleState.completed),
            engine,
            harness
        )
    }

    func testS78AnAdvancedPositionForAnotherSessionMovesNothing() async throws {
        let (harness, engine) = await wristMidWorkout()

        try await assertRefused(
            lifecycleFrame(
                "s-1",
                messageId: "msg-life-2",
                state: WatchLifecycleState.exerciseAdvanced,
                exerciseIndex: 0
            ),
            engine,
            harness
        )
    }

    func testS78TimerStateForAnotherSessionAdoptsNoTimer() async throws {
        let (harness, engine) = await wristMidWorkout()

        try await assertRefused(
            timerStateFrame(
                "s-1",
                messageId: "msg-timers-1",
                timers: ["rest": timerJson(WatchTimerKind.rest, startedAt: "2026-07-13T06:29:50Z")]
            ),
            engine,
            harness
        )

        XCTAssertTrue(
            engine.timerFor(WatchTimerKind.rest)?.recordId.hasPrefix("rec-") == true,
            "the wrist keeps its own row"
        )
    }

    func testS78AStructureChangeForAnotherSessionWritesNoRow() async throws {
        let (harness, engine) = await wristMidWorkout()

        try await assertRefused(
            structureChangeFrame(
                "s-1",
                changeId: "chg-foreign-1",
                changes: [["kind": "remove_exercise", "sessionExerciseId": "sx-9"]]
            ),
            engine,
            harness
        )
    }

    func testS78AnExercisePushForAnotherSessionLandsNowhere() async throws {
        let (harness, engine) = await wristMidWorkout()

        try await assertRefused(
            exercisePushFrame("s-1", messageId: "msg-push-1", slot: "sx-10"),
            engine,
            harness
        )
    }

    func testS81AReDeliveredSnapshotLeavesTheStoreAsItWas() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        let snapshot = snapshotFrame(
            "s-watch-1",
            messageId: "msg-replayed-1",
            exercises: [exercise("sx-bench")],
            entries: [entryMap("e-p1", at: "2026-07-13T06:30:00Z", loadKg: 80)],
            timers: ["rest": timerJson(WatchTimerKind.rest, startedAt: "2026-07-13T06:20:00Z")]
        )

        _ = try await engine.applyMessage(snapshot)
        let once = await harness.store.readAll()

        _ = try await engine.applyMessage(snapshot)
        let twice = await harness.store.readAll()

        XCTAssertEqual(
            twice.sessions.map(\.recordId),
            once.sessions.map(\.recordId),
            "the same message mints no second row id"
        )
        XCTAssertEqual(twice.timers.map(\.recordId), once.timers.map(\.recordId))
        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-bench"]
        )
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.active)
    }

    // MARK: - S-100/S-101/S-104 the wrist announces its own structure (D-91, D-101)

    /// The `session_snapshot` frames the wrist emitted from its own sink, in
    /// order — the frames the phone's adoption reads.
    private func wristSnapshots(_ harness: Harness) -> [[String: Any]] {
        harness.emitted.filter { $0["type"] as? String == "session_snapshot" }
    }

    private func snapshotPayload(_ frame: [String: Any]) -> [String: Any] {
        (frame["payload"] as? [String: Any]) ?? [:]
    }

    /// The `sessionExerciseId`s a snapshot's ladder carries, in order.
    private func snapshotLadder(_ frame: [String: Any]) -> [String] {
        (snapshotPayload(frame)["exercises"] as? [[String: Any]] ?? [])
            .compactMap { $0["sessionExerciseId"] as? String }
    }

    private func snapshotRevision(_ frame: [String: Any]) -> Int? {
        snapshotPayload(frame)["revision"] as? Int
    }

    func testS100AWristStartSendsItsLifecycleThenItsOwnSnapshot() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [exercise("sx-a"), exercise("sx-b")]
        )

        XCTAssertEqual(
            harness.emitted.map { $0["type"] as? String },
            ["session_lifecycle", "session_snapshot"],
            "D-91 the frame the start already sent keeps its place and the snapshot follows it, one each"
        )

        let lifecycle = try XCTUnwrap(harness.emitted.first)
        let snapshot = try XCTUnwrap(harness.emitted.last)
        XCTAssertEqual(lifecycle["sessionId"] as? String, "s-watch-1")
        XCTAssertEqual(snapshot["sessionId"] as? String, "s-watch-1")
        XCTAssertNotEqual(
            lifecycle["messageId"] as? String,
            snapshot["messageId"] as? String,
            "two announcements, two identities: each is re-deliverable on its own"
        )
        XCTAssertEqual(snapshotLadder(snapshot), ["sx-a", "sx-b"], "the ladder the phone adopts")
        XCTAssertEqual(snapshotPayload(snapshot)["status"] as? String, WatchSessionStatus.active)
        XCTAssertEqual(snapshotPayload(snapshot)["currentExerciseIndex"] as? Int, 0)
        XCTAssertEqual(snapshotRevision(snapshot), engine.session?.revision)
        XCTAssertTrue(
            Harness.validator().validateEnvelope(snapshot).isEmpty,
            "a telling this build could not send would be dropped, so what the sink got is a frame the protocol accepts"
        )
    }

    func testS101AWristAddedExerciseArrivesAsASecondSnapshotWithAMovedRevision() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        // S-101's fixture: a free session started with no exercise at all, then
        // the user's own pick.
        _ = await engine.createSession(modality: nil, exercises: [])
        let first = try XCTUnwrap(wristSnapshots(harness).first, "the free start announces itself")
        XCTAssertEqual(snapshotLadder(first).count, 0, "the ladder the wrist started with, empty")
        let before = try XCTUnwrap(snapshotRevision(first))

        _ = await engine.insertExercise(exercise("sx-c"), moveTo: true)

        let snapshots = wristSnapshots(harness)
        XCTAssertEqual(snapshots.count, 2, "the wrist's own add is announced once, and nothing else is")
        let second = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(snapshotLadder(second), ["sx-c"])
        XCTAssertEqual(
            snapshotPayload(second)["currentExerciseIndex"] as? Int,
            0,
            "the user's own add moves the session onto the exercise they just added"
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(snapshotRevision(second)),
            before,
            "D-101 a wrist-originated structural change moves the revision"
        )
        XCTAssertEqual(
            snapshotRevision(second),
            engine.session?.revision,
            "the snapshot carries the number the row holds"
        )
        XCTAssertTrue(Harness.validator().validateEnvelope(second).isEmpty)
    }

    func testS104AStructureChangeFromThePhoneIsNeverAnnouncedBack() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [exercise("sx-a"), exercise("sx-b")]
        )
        harness.clearEmitted()

        _ = try await engine.applyMessage(
            structureChangeFrame(
                "s-watch-1",
                changeId: "chg-phone-1",
                changes: [["kind": "remove_exercise", "sessionExerciseId": "sx-b"]]
            )
        )

        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-a"],
            "the change really applied, so the silence below is not a refused frame's"
        )
        XCTAssertTrue(
            harness.emitted.isEmpty,
            "D-91 the phone is the structure authority: a change it wrote is not announced back at it"
        )
    }

    func testS104AnExercisePushFromThePhoneIsNeverAnnouncedBack() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-a")])
        harness.clearEmitted()

        _ = try await engine.applyMessage(
            exercisePushFrame("s-watch-1", messageId: "msg-push-1", slot: "sx-c")
        )

        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-a", "sx-c"],
            "the push landed and left the user where they were"
        )
        XCTAssertTrue(
            harness.emitted.isEmpty,
            "D-91 an `exercise_push` applies with `announce: false`: the phone wrote it, so the phone hears nothing"
        )
    }

    func testS104ASnapshotFromThePhoneIsNeverAnsweredWithTheWristsOwn() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-a")])
        harness.clearEmitted()

        _ = try await engine.applyMessage(
            snapshotFrame(
                "s-watch-1",
                messageId: "msg-snap-1",
                exercises: [exercise("sx-a"), exercise("sx-b")]
            )
        )

        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-a", "sx-b"],
            "the snapshot applied"
        )
        XCTAssertTrue(
            harness.emitted.isEmpty,
            "D-91 a snapshot is answered with silence: answering it would be a snapshot the phone did not ask for"
        )
    }
}
