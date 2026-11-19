// A session the wrist has ended never comes back — not the current one, and
// not one the user has moved on from.
//
// Plan: `docs/plans/2026-11-13-151-ended-session-not-current-fix-plan/
// 2026-11-13-151-ended-session-not-current-fix-plan.md`.
// Scenario mapping:
//   S-15101 a snapshot for an ended, non-current session keeps the end
//           → `testS15101...`
//   S-15101 the Phase 4 four-action trace, on this engine
//           → `testS15101TheA1Shape...`
//
// The Dart twin carries the same cases in
// `test/watch_ended_session_not_current_test.dart`; the two engines implement
// one rule, and this file is what keeps the Swift one from drifting from it.

import XCTest
@testable import WatchSessionEngine

final class WatchEndedSessionNotCurrentTests: XCTestCase {
    private func exercise(_ slot: String) -> [String: Any] {
        [
            "sessionExerciseId": slot,
            "exerciseId": "ex-\(slot)",
            "name": slot,
            "capabilities": ["reps", "sets", "load"],
        ]
    }

    private func entry(_ entryId: String, slot: String) -> [String: Any] {
        [
            "entryId": entryId,
            "eventId": entryId,
            "kind": "set",
            "loggedAt": "2026-07-13T11:59:00Z",
            "sessionExerciseId": slot,
            "exerciseId": "ex-\(slot)",
            "reps": 5,
            "loadKg": 80,
        ]
    }

    private func snapshot(
        _ sessionId: String,
        messageId: String,
        sentAt: Date,
        status: String = WatchSessionStatus.active,
        slots: [String] = ["sx-bench"],
        entries: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": utcIso(sentAt),
            "payload": [
                "sessionId": sessionId,
                "revision": 1,
                "status": status,
                "currentExerciseIndex": 0,
                "exercises": slots.map(exercise),
                "entries": entries,
                "timers": [:] as [String: Any],
            ] as [String: Any],
        ]
    }

    private func makeEngine(_ harness: Harness) -> WatchSessionEngine {
        var record = 0
        var session = 0
        return WatchSessionEngine(
            store: harness.store,
            onEmit: { _ in },
            validator: Harness.validator(),
            clock: harness.clock.call,
            idFactory: { record += 1; return "rec-\(record)" },
            sessionIdFactory: { session += 1; return "s-watch-\(session)" }
        )
    }

    private func rows(_ harness: Harness, _ sessionId: String) async -> [WatchSessionRecord] {
        await harness.store.readAll().sessions.filter { $0.sessionId == sessionId }
    }

    /// The Phase 4 four-action trace as the real engine sees it: the wrist
    /// finishes one workout, starts its next with no exercise picked yet, and
    /// the phone's `active` snapshot for the first arrives. The open workout
    /// stays the current one and the finished one stays finished.
    func testS15101TheA1ShapeKeepsTheLiveWorkoutCurrent() async throws {
        let harness = Harness()
        let engine = makeEngine(harness)
        await engine.restore()

        let first = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = await engine.finishSession()
        harness.clock.advance(30)
        let second = await engine.createSession(modality: nil, exercises: [])
        harness.clock.advance(30)

        _ = try await engine.applyMessage(
            snapshot(first.sessionId, messageId: "msg-stale-active", sentAt: harness.clock.now)
        )

        XCTAssertEqual(engine.session?.sessionId, second.sessionId,
                       "the wrist's open workout stays the current one")
        let firstRows = await rows(harness, first.sessionId)
        XCTAssertEqual(firstRows.last?.status, WatchSessionStatus.completed,
                       "a finished workout never reads active again")
    }

    /// Ends session 1, then session 2, so the wrist's current row is another
    /// ended session. The late snapshot for session 1 adds no row.
    func testS15101ALateSnapshotCannotReviveAnEndedSession() async throws {
        let harness = Harness()
        let engine = makeEngine(harness)
        await engine.restore()

        let first = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = await engine.finishSession()
        harness.clock.advance(30)
        let second = await engine.createSession(modality: nil, exercises: [exercise("sx-squat")])
        _ = await engine.finishSession()
        harness.clock.advance(30)

        let before = await rows(harness, first.sessionId)
        _ = try await engine.applyMessage(
            snapshot(first.sessionId, messageId: "msg-s-1-late", sentAt: harness.clock.now,
                     slots: ["sx-bench", "sx-squat"], entries: [entry("e-late-swift", slot: "sx-bench")])
        )

        let after = await rows(harness, first.sessionId)
        XCTAssertEqual(after.count, before.count, "an ended session takes no new row")
        XCTAssertEqual(after.last?.status, WatchSessionStatus.completed)
        XCTAssertEqual(after.last?.exercises.map { $0["sessionExerciseId"] as? String },
                       ["sx-bench"], "an ended session keeps the ladder it ended on")
        XCTAssertNotEqual(engine.session?.sessionId, first.sessionId)
        _ = second
    }

    /// The entries are the only news a frame that names an ended session can
    /// carry (D-14605), and they still merge.
    func testS15101ALateSnapshotForAnEndedSessionStillMergesItsEntries() async throws {
        let harness = Harness()
        let engine = makeEngine(harness)
        await engine.restore()

        let first = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = await engine.finishSession()
        harness.clock.advance(30)
        _ = await engine.createSession(modality: nil, exercises: [])

        _ = try await engine.applyMessage(
            snapshot(first.sessionId, messageId: "msg-s-1-late", sentAt: harness.clock.now,
                     entries: [entry("e-late-swift-2", slot: "sx-bench")])
        )

        let stored = await harness.store.readAll().observations
        XCTAssertTrue(stored.contains { $0.entryId == "e-late-swift-2" },
                      "a set the phone logged is still news worth keeping")
        let firstRows = await rows(harness, first.sessionId)
        XCTAssertEqual(firstRows.last?.status, WatchSessionStatus.completed)
    }

    /// D-78, unchanged: a live workout of the wrist's own refuses a snapshot
    /// for a session it has never stored any row of — no entry, no row.
    func testS15101ALiveWristWorkoutStillRefusesAForeignSnapshot() async throws {
        let harness = Harness()
        let engine = makeEngine(harness)
        await engine.restore()

        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        harness.clock.advance(30)

        let before = await harness.store.readAll()
        _ = try await engine.applyMessage(
            snapshot("s-phone-somewhere-else", messageId: "msg-foreign",
                     sentAt: harness.clock.now,
                     entries: [entry("e-refused-swift", slot: "sx-bench")])
        )

        let after = await harness.store.readAll()
        XCTAssertEqual(after.sessions.count, before.sessions.count)
        XCTAssertFalse(after.observations.contains { $0.entryId == "e-refused-swift" })
    }
}
