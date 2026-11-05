//
//  WatchStaleSnapshotTests.swift
//  WatchSessionEngineTests
//
//  S-9311 to S-9314 of
//  `docs/plans/2026-10-23-63-message-order-plan/2026-10-23-63-message-order-plan.md`
//  — a snapshot older than the newest one applied is refused whole (plan 63
//  D-1, D-6): no entry comes back, no tombstone is cleared, and the rule
//  survives a relaunch because the stamp is rebuilt from the stored `snap-`
//  rows.
//
//  T1 = T2 - 1 ms, a value unlike the fixtures' whole-second stamps.
//

import XCTest

@testable import WatchSessionEngine

final class WatchStaleSnapshotTests: XCTestCase {

    /// The newer stamp, T2.
    private let t2 = "2026-07-13T06:30:00Z"
    /// T1 = T2 - 1 ms.
    private let t1 = "2026-07-13T06:29:59.999Z"

    private func snapshot(
        _ sessionId: String,
        messageId: String,
        sentAt: String,
        exercises: [[String: Any]],
        entries: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": sentAt,
            "payload": [
                "sessionId": sessionId,
                "revision": 1,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 0,
                "exercises": exercises,
                "entries": entries,
                "timers": [String: Any](),
            ] as [String: Any],
        ]
    }

    private func entryMap(_ entryId: String, at loggedAt: String) -> [String: Any] {
        [
            "entryId": entryId,
            "eventId": entryId,
            "kind": "set",
            "loggedAt": loggedAt,
            "sessionExerciseId": "sx-bench",
            "exerciseId": "ex-sx-bench",
            "reps": 8,
            "loadKg": 60,
        ]
    }

    private func structureChange(
        _ sessionId: String,
        changeId: String,
        changes: [[String: Any]]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-\(changeId)",
            "sessionId": sessionId,
            "type": "structure_change",
            "origin": "phone",
            "sentAt": t2,
            "payload": ["changeId": changeId, "changes": changes],
        ]
    }

    // MARK: - S-9311 the older snapshot is refused whole

    func testS9311AnOlderSnapshotIsRefusedAndChangesNothing() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        let newer = snapshot(
            harness.sessionId,
            messageId: "msg-p2-s9311-a",
            sentAt: t2,
            exercises: [exercise("sx-bench"), exercise("sx-row")],
            entries: [entryMap("e-1", at: t2)]
        )
        let older = snapshot(
            harness.sessionId,
            messageId: "msg-p2-s9311-b",
            sentAt: t1,
            exercises: [exercise("sx-bench")]
        )

        let appliedNewer = try await engine.applyMessage(newer)
        XCTAssertTrue(appliedNewer, "S-9311 the newer snapshot applied")
        let appliedOlder = try await engine.applyMessage(older)
        XCTAssertFalse(
            appliedOlder,
            "S-9311 the older snapshot is refused whole"
        )

        let session = try XCTUnwrap(engine.session)
        XCTAssertEqual(
            session.exercises.count,
            2,
            "S-9311 the session still shows the newer snapshot's exercises"
        )
        XCTAssertEqual(
            engine.entries.map(\.entryId),
            ["e-1"],
            "S-9311 the newer snapshot's entry is still the one held"
        )
    }

    // MARK: - S-9312 one test per arm

    func testS9312ASnapshotWithTheEqualStampApplies() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        let first = try await engine.applyMessage(
            snapshot(harness.sessionId, messageId: "msg-p2-s9312-eq-a", sentAt: t2, exercises: [exercise("sx-bench")])
        )
        XCTAssertTrue(first, "S-9312 the first snapshot applied")
        let second = try await engine.applyMessage(
            snapshot(harness.sessionId, messageId: "msg-p2-s9312-eq-b", sentAt: t2, exercises: [exercise("sx-bench"), exercise("sx-row")])
        )
        XCTAssertTrue(
            second,
            "S-9312 a snapshot with the equal stamp is not stale: it applies"
        )
    }

    func testS9312ALaterSnapshotApplies() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        let first = try await engine.applyMessage(
            snapshot(harness.sessionId, messageId: "msg-p2-s9312-later-a", sentAt: t2, exercises: [exercise("sx-bench")])
        )
        XCTAssertTrue(first, "S-9312 the first snapshot applied")
        let second = try await engine.applyMessage(
            snapshot(harness.sessionId, messageId: "msg-p2-s9312-later-b", sentAt: "2026-07-13T06:30:00.001Z", exercises: [exercise("sx-bench"), exercise("sx-row")])
        )
        XCTAssertTrue(
            second,
            "S-9312 a later snapshot applies"
        )
    }

    func testS9312AnOlderSnapshotOfAnotherWorkoutIsRefusedToo() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        let applied = try await engine.applyMessage(
            snapshot(harness.sessionId, messageId: "msg-p2-s9312-other-a", sentAt: t2, exercises: [exercise("sx-bench")])
        )
        XCTAssertTrue(applied, "S-9312 the newer snapshot applied")
        // The held session ends, so the D-78 foreign-session guard is out of
        // the way: what refuses the next frame is the stale rule alone.
        _ = await engine.finishSession()

        let refused = try await engine.applyMessage(
            snapshot("s-other-workout", messageId: "msg-p2-s9312-other-b", sentAt: t1, exercises: [exercise("sx-row")])
        )
        XCTAssertFalse(
            refused,
            "S-9312 an older snapshot of another workout is refused too"
        )
    }

    func testS9312ARefusedSnapshotStoresNoRow() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        let applied = try await engine.applyMessage(
            snapshot(harness.sessionId, messageId: "msg-p2-s9312-row-a", sentAt: t2, exercises: [exercise("sx-bench")])
        )
        XCTAssertTrue(applied, "S-9312 the newer snapshot applied")
        let rowsBefore = await harness.store.readAll().sessions.count

        let refused = try await engine.applyMessage(
            snapshot(harness.sessionId, messageId: "msg-p2-s9312-row-b", sentAt: t1, exercises: [exercise("sx-bench")])
        )
        XCTAssertFalse(
            refused,
            "S-9312 the older snapshot is refused"
        )
        let rowsAfter = await harness.store.readAll().sessions.count
        XCTAssertEqual(
            rowsAfter,
            rowsBefore,
            "S-9312 the refused snapshot stored no session row"
        )
    }

    // MARK: - S-9313 the rule survives a relaunch

    func testS9313ARestoredEngineRefusesTheOlderSnapshotToo() async throws {
        let harness = Harness()
        let first = await harness.runningEngine()

        let applied = try await first.applyMessage(
            snapshot(harness.sessionId, messageId: "msg-p2-s9313-a", sentAt: t2, exercises: [exercise("sx-bench"), exercise("sx-row")])
        )
        XCTAssertTrue(applied, "S-9313 the newer snapshot applied")

        // A relaunch: a brand-new engine over the same storage.
        let relaunched = await harness.runningEngine()
        let refused = try await relaunched.applyMessage(
            snapshot(harness.sessionId, messageId: "msg-p2-s9313-b", sentAt: t1, exercises: [exercise("sx-bench")])
        )
        XCTAssertFalse(
            refused,
            "S-9313 the stamp is rebuilt from the snap- rows, so the restored "
                + "engine refuses the older snapshot too"
        )
        XCTAssertEqual(
            relaunched.session?.exercises.count,
            2,
            "S-9313 the newer snapshot's state is what the wrist still holds"
        )
    }

    // MARK: - S-9314 a stale snapshot does not un-hide a deleted entry

    func testS9314AStaleSnapshotDoesNotUnHideADeletedEntry() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        let applied = try await engine.applyMessage(
            snapshot(
                harness.sessionId,
                messageId: "msg-p2-s9314-a",
                sentAt: t2,
                exercises: [exercise("sx-bench")],
                entries: [entryMap("e-1", at: t2)]
            )
        )
        XCTAssertTrue(applied, "S-9314 the newer snapshot applied, carrying e1")
        _ = try await engine.applyMessage(
            structureChange(
                harness.sessionId,
                changeId: "chg-p2-s9314-del",
                changes: [["kind": "delete_entry", "entryId": "e-1"]]
            )
        )
        XCTAssertTrue(engine.entries.isEmpty, "S-9314 the phone's deletion hides the entry")

        let refused = try await engine.applyMessage(
            snapshot(
                harness.sessionId,
                messageId: "msg-p2-s9314-b",
                sentAt: t1,
                exercises: [exercise("sx-bench")],
                entries: [entryMap("e-1", at: t2)]
            )
        )
        XCTAssertFalse(
            refused,
            "S-9314 the stale snapshot that names e1 is refused"
        )
        XCTAssertTrue(
            engine.entries.isEmpty,
            "S-9314 the deleted entry stays hidden: the stale snapshot brought nothing back"
        )
        XCTAssertEqual(
            engine.session?.deletedEntryIds,
            ["e-1"],
            "S-9314 the tombstone was not cleared"
        )
    }
}
