//
//  WatchLiveMirroringTests.swift
//  WatchSessionEngineTests
//
//  S-002 to S-007 of
//  `docs/plans/2026-07-13-09-c1-live-session-mirroring-plan.md` on the
//  native watchOS side — the same reconciliation fixtures the Dart suite
//  replays in `test/live_mirroring_test.dart`, run through the Swift engine so
//  the two watch clients converge identically.
//
//  What the register pins for a watch: structure, status, position, revision,
//  and timers converge on `expected`; the entries are the session's log, with
//  the phone's corrections folded in and deletions dropped. A message the watch
//  cannot read is refused whole and answered with a snapshot, which is what
//  keeps a protocol mismatch from half-editing a live session.
//

import XCTest

@testable import WatchSessionEngine

final class WatchLiveMirroringTests: XCTestCase {

    // MARK: - S-007 the register, driven through the engine

    func testEveryReconciliationFixtureConverges() async throws {
        let scenarios = try Fixtures.entries("scenarios")
        XCTAssertFalse(scenarios.isEmpty)

        var replayed = 0
        for entry in scenarios {
            let path = try XCTUnwrap(entry["path"] as? String)
            let fixture = try Fixtures.json("fixtures/\(path)")
            guard let snapshot = fixture["snapshot"] as? [String: Any],
                  let stream = fixture["stream"] as? [[String: Any]],
                  let expected = fixture["expected"] as? [String: Any]
            else { continue } // version_mismatch carries cases instead

            replayed += 1
            let harness = Harness()
            let engine = await harness.runningEngine()
            try await engine.applyMessage(snapshot)

            for message in stream {
                if message["type"] as? String == "observations_up" {
                    let payload = message["payload"] as? [String: Any] ?? [:]
                    for event in payload["events"] as? [[String: Any]] ?? [] {
                        _ = try await engine.appendObservation(event)
                    }
                } else {
                    _ = try await engine.applyMessage(message)
                }
            }

            try assertConverged(engine, expected: expected, path: path)
        }
        XCTAssertGreaterThan(replayed, 0, "the register must have replayable fixtures")
    }

    func testReplayingTheStreamTwiceConvergesIdentically() async throws {
        let fixture = try Fixtures.json("fixtures/reconciliation/snapshot_then_events.json")
        let snapshot = try XCTUnwrap(fixture["snapshot"] as? [String: Any])
        let stream = try XCTUnwrap(fixture["stream"] as? [[String: Any]])
        let expected = try XCTUnwrap(fixture["expected"] as? [String: Any])

        let once = await Harness().runningEngine()
        try await replay(once, snapshot: snapshot, stream: stream)
        let twice = await Harness().runningEngine()
        try await replay(twice, snapshot: snapshot, stream: stream + stream)

        try assertConverged(once, expected: expected, path: "applied once")
        try assertConverged(twice, expected: expected, path: "applied twice")
    }

    // MARK: - S-002 a phone structure change reaches the watch

    func testStructureChangeAppliesWithoutDisturbingARunningTimer() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [exercise("sx-bench"), exercise("sx-plank"), exercise("sx-squat")]
        )
        _ = try await engine.startTimer(WatchTimerKind.rest, plannedDurationMs: 90_000)
        let rest = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest))

        let applied = try await engine.applyMessage(
            structureChange(
                changeId: "chg-live-1",
                changes: [
                    ["kind": "remove_exercise", "sessionExerciseId": "sx-plank"],
                    ["kind": "reorder_exercises", "order": ["sx-squat", "sx-bench"]],
                ]
            )
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-squat", "sx-bench"]
        )
        XCTAssertEqual(engine.session?.revision, 1)
        XCTAssertEqual(engine.timerFor(WatchTimerKind.rest)?.recordId, rest.recordId)
        XCTAssertEqual(engine.timerFor(WatchTimerKind.rest)?.state, WatchTimerState.running)
    }

    // MARK: - S-003 reconnect after offline logging

    func testPendingObservationsSurviveARelaunchAndClearOnTheSnapshotsReceipt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [exercise("sx-bench")]
        )
        for index in 1...5 {
            _ = try await engine.appendObservation(
                setEvent(harness.clock, entryId: "e-offline-\(index)")
            )
        }

        // A relaunch rebuilds the same five messages from storage.
        let relaunched = await harness.runningEngine(harness.newEngine())
        XCTAssertEqual(relaunched.pendingObservations().count, 5)

        let entryIds = Set(
            relaunched.pendingObservations().compactMap { envelope in
                ((envelope["payload"] as? [String: Any])?["events"] as? [[String: Any]])?
                    .first?["entryId"] as? String
            }
        )
        XCTAssertEqual(entryIds.count, 5)

        // The phone's snapshot is the receipt: the entries it carries are
        // confirmed, so nothing is re-sent and nothing is lost.
        let snapshot = sessionSnapshot(
            sessionId: try XCTUnwrap(relaunched.session?.sessionId),
            revision: 3,
            status: WatchSessionStatus.active,
            currentExerciseIndex: 0,
            exercises: [exercise("sx-bench")],
            entries: relaunched.pendingObservations().compactMap { envelope in
                ((envelope["payload"] as? [String: Any])?["events"] as? [[String: Any]])?.first
            },
            timers: [:]
        )
        _ = try await relaunched.applyMessage(snapshot)

        XCTAssertTrue(relaunched.pendingObservations().isEmpty)
        XCTAssertEqual(relaunched.entries.count, 5)
    }

    // MARK: - S-006 joining an in-progress phone session from the watch

    func testSnapshotPopulatesAWatchWithNoSession() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        XCTAssertNil(engine.session)

        let snapshot = sessionSnapshot(
            sessionId: "s-phone-1",
            revision: 7,
            status: WatchSessionStatus.active,
            currentExerciseIndex: 1,
            exercises: [exercise("sx-bench"), exercise("sx-plank")],
            entries: [
                [
                    "entryId": "e-phone-1",
                    "eventId": "e-phone-1",
                    "kind": "set",
                    "loggedAt": "2026-07-13T06:10:00Z",
                    "sessionExerciseId": "sx-bench",
                    "exerciseId": "ex-sx-bench",
                    "reps": 8,
                    "loadKg": 60,
                ],
            ],
            timers: [
                "rest": [
                    "kind": "rest",
                    "state": "running",
                    "startedAt": "2026-07-13T06:25:00Z",
                    "accumulatedPauseMs": 0,
                    "plannedDurationMs": 90_000,
                ],
            ]
        )

        _ = try await engine.applyMessage(snapshot)

        XCTAssertEqual(engine.session?.sessionId, "s-phone-1")
        XCTAssertEqual(engine.session?.revision, 7)
        XCTAssertEqual(engine.session?.currentExerciseIndex, 1)
        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-bench", "sx-plank"]
        )
        XCTAssertEqual(engine.entries.map(\.entryId), ["e-phone-1"])
        XCTAssertEqual(engine.timerFor(WatchTimerKind.rest)?.state, WatchTimerState.running)
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest).flatMap(completionInstant),
            try XCTUnwrap(parseUtcIso("2026-07-13T06:26:30Z"))
        )
    }

    func testTheWatchesSnapshotCarriesItsSessionForThePhone() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [exercise("sx-bench")]
        )
        _ = try await engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))

        let snapshot = try XCTUnwrap(engine.sessionSnapshot())
        let payload = try XCTUnwrap(snapshot["payload"] as? [String: Any])

        XCTAssertEqual(snapshot["type"] as? String, "session_snapshot")
        XCTAssertEqual(snapshot["origin"] as? String, "watch")
        XCTAssertEqual(payload["sessionId"] as? String, engine.session?.sessionId)
        XCTAssertEqual((payload["entries"] as? [[String: Any]])?.count, 1)
    }

    // MARK: - S-007 a message the watch cannot read

    func testAVersionMismatchIsRefusedAndAnsweredWithASnapshot() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = await harness.engine.createSession(
            modality: "resistance_lifting",
            exercises: [exercise("sx-bench")]
        )
        let before = harness.engine.session

        let fixture = try Fixtures.json("fixtures/reconciliation/version_mismatch.json")
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        let newer = try XCTUnwrap(cases.last?["message"] as? [String: Any])

        do {
            _ = try await harness.orchestrator.receive(newer)
            XCTFail("a v2 message must be refused")
        } catch {
            XCTAssertTrue(error is WatchEmissionRejected)
        }

        XCTAssertEqual(harness.engine.session?.sessionId, before?.sessionId)
        XCTAssertEqual(
            harness.engine.session?.exercises as NSArray?,
            before?.exercises as NSArray?,
            "a refused message must not edit the session"
        )
        XCTAssertEqual(harness.transport.sent.last?["type"] as? String, "session_snapshot")
    }

    func testASnapshotRequestIsAnsweredOnce() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = await harness.engine.createSession(
            modality: "resistance_lifting",
            exercises: [exercise("sx-bench")]
        )

        await harness.orchestrator.answerSnapshotRequest()

        XCTAssertEqual(harness.transport.sent.count, 1)
        XCTAssertEqual(harness.transport.sent.last?["type"] as? String, "session_snapshot")
    }

    /// A watch with nothing logged has nothing authoritative to report, so the
    /// request goes unanswered rather than answered with an empty session.
    func testASessionlessWatchAnswersNothing() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        XCTAssertNil(harness.engine.session)

        await harness.orchestrator.answerSnapshotRequest()

        XCTAssertTrue(harness.transport.sent.isEmpty)
    }

    /// Joining a session asks for the phone's snapshot rather than offering an
    /// empty one of its own.
    func testJoiningAsksForASnapshotRatherThanOfferingOne() async throws {
        let harness = WatchStartHarness()
        await harness.launch()

        await harness.orchestrator.sync(reconnect: true)

        XCTAssertEqual(harness.transport.snapshotRequests, 1)
        XCTAssertTrue(
            harness.transport.sent.allSatisfy { $0["type"] as? String != "session_snapshot" }
        )
    }

    // MARK: - Helpers

    private func replay(
        _ engine: WatchSessionEngine,
        snapshot: [String: Any],
        stream: [[String: Any]]
    ) async throws {
        try await engine.applyMessage(snapshot)
        for message in stream {
            if message["type"] as? String == "observations_up" {
                let payload = message["payload"] as? [String: Any] ?? [:]
                for event in payload["events"] as? [[String: Any]] ?? [] {
                    _ = try await engine.appendObservation(event)
                }
            } else {
                _ = try await engine.applyMessage(message)
            }
        }
    }

    private func assertConverged(
        _ engine: WatchSessionEngine,
        expected: [String: Any],
        path: String
    ) throws {
        let session = try XCTUnwrap(engine.session, "\(path): no session")
        XCTAssertEqual(session.sessionId, expected["sessionId"] as? String, path)
        XCTAssertEqual(session.status, expected["status"] as? String, path)
        XCTAssertEqual(session.revision, expected["revision"] as? Int, path)
        XCTAssertEqual(
            session.currentExerciseIndex,
            expected["currentExerciseIndex"] as? Int,
            path
        )
        XCTAssertEqual(
            session.exercises as NSArray,
            (expected["exercises"] as? [[String: Any]] ?? []) as NSArray,
            path
        )
        XCTAssertEqual(
            engine.entries.map(\.payload) as NSArray,
            (expected["entries"] as? [[String: Any]] ?? []) as NSArray,
            path
        )

        let timers = expected["timers"] as? [String: Any] ?? [:]
        for kind in WatchTimerKind.all {
            guard let expectedTimer = timers[kind] as? [String: Any] else {
                let timer = engine.timerFor(kind)
                XCTAssertTrue(
                    timer == nil || timer?.state == WatchTimerState.stopped,
                    "\(path): \(kind) must not be running when the fixture omits it"
                )
                continue
            }
            let timer = try XCTUnwrap(engine.timerFor(kind), "\(path): \(kind) missing")
            XCTAssertEqual(
                normalisedTimer(timer.toTimerJson()) as NSDictionary,
                normalisedTimer(expectedTimer) as NSDictionary,
                path
            )
        }
    }

    /// Timers compare by instant, not by spelling: the engine writes the
    /// protocol's wire shape with fractional seconds, a fixture may write the
    /// same instant without them.
    private func normalisedTimer(_ timer: [String: Any]) -> [String: Any] {
        var normalised = timer
        for key in ["startedAt", "pausedAt", "stoppedAt"] {
            if let text = timer[key] as? String, let instant = try? parseUtcIso(text) {
                normalised[key] = instant
            }
        }
        return normalised
    }

    private func structureChange(
        changeId: String,
        changes: [[String: Any]],
        sessionId: String = "s-watch-1"
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-\(changeId)",
            "sessionId": sessionId,
            "type": "structure_change",
            "origin": "phone",
            "sentAt": "2026-07-13T06:30:00Z",
            "payload": ["changeId": changeId, "changes": changes],
        ]
    }

    private func sessionSnapshot(
        sessionId: String,
        revision: Int,
        status: String,
        currentExerciseIndex: Int,
        exercises: [[String: Any]],
        entries: [[String: Any]],
        timers: [String: Any]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-snapshot-live",
            "sessionId": sessionId,
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-07-13T06:30:00Z",
            "payload": [
                "sessionId": sessionId,
                "revision": revision,
                "status": status,
                "currentExerciseIndex": currentExerciseIndex,
                "exercises": exercises,
                "entries": entries,
                "timers": timers,
            ],
        ]
    }
}
