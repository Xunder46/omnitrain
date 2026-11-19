//
//  WatchSnapshotWristModalityTests.swift
//  WatchSessionEngineTests
//
//  P1 of
//  `docs/plans/2026-11-15-204-wrist-names-its-modality-plan/2026-11-15-204-wrist-names-its-modality-plan.md`:
//  the wrist's own `session_snapshot` names the session's modality when the
//  row holds one — never null, never empty — so a workout started on the watch
//  from the Cardio button is picked up by the phone as Cardio (with plan 203,
//  which has the phone read the key).
//
//  Scenario mapping:
//    S-20401 a session with a modality names it in its snapshot → `testS20401…`
//    S-20402 a free session names no modality → `testS20402…`
//    S-20403 the other keys and the schema are unchanged → `testS20403…`
//    S-20404 the wrist echoes the modality it was told and keeps it → `testS20404…`
//    S-20406 the modality survives a relaunch → `testS20406…`
//

import XCTest

@testable import WatchSessionEngine

/// Reads as "the `modality` key is absent from the payload" for `focusSnapshot`.
private enum ModalityKeyAbsent {
    case absent
}

final class WatchSnapshotWristModalityTests: XCTestCase {

    // MARK: - Helpers

    private func slot(_ id: String, capabilities: [String]) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
    }

    /// One `session_snapshot` from the phone, with an optional `modality` key
    /// (copied from `WatchSnapshotFocusTests`).
    private func focusSnapshot(
        messageId: String,
        sessionId: String,
        sentAt: String,
        modality: Any? = ModalityKeyAbsent.absent,
        status: String = WatchSessionStatus.active,
        revision: Int = 7,
        exercises: [[String: Any]]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "revision": revision,
            "status": status,
            "currentExerciseIndex": 0,
            "exercises": exercises,
            "entries": [[String: Any]](),
            "timers": [String: Any](),
        ]
        if !(modality is ModalityKeyAbsent) { payload["modality"] = modality }
        return [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": sentAt,
            "payload": payload as [String: Any],
        ]
    }

    /// The snapshot's payload, the part D-20401 touches.
    private func payload(of envelope: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(envelope["payload"] as? [String: Any], "the snapshot carries a payload")
    }

    // MARK: - S-20401 a session with a modality names it

    func testS20401ASessionWithAModalityNamesItInItsSnapshot() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )

        let envelope = try XCTUnwrap(engine.sessionSnapshot(), "the session snapshots")
        let payload = try payload(of: envelope)
        XCTAssertEqual(
            payload["modality"] as? String,
            "cardio_endurance",
            "the wrist's snapshot names the session's modality (D-20401)"
        )
    }

    // MARK: - S-20402 a free session names no modality

    func testS20402AFreeSessionNamesNoModality() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: [slot("sx-bench", capabilities: ["sets", "reps", "load"])]
        )

        let envelope = try XCTUnwrap(engine.sessionSnapshot(), "the session snapshots")
        let payload = try payload(of: envelope)
        XCTAssertFalse(
            payload.keys.contains("modality"),
            "a free session's snapshot has no modality key at all (S-20402)"
        )
    }

    // MARK: - S-20403 the other keys and the schema are unchanged

    func testS20403TheOtherKeysAndTheSchemaAreUnchanged() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let named = try XCTUnwrap(engine.sessionSnapshot(), "the session snapshots")
        let namedPayload = try payload(of: named)
        XCTAssertEqual(
            Set(namedPayload.keys),
            Set(["sessionId", "revision", "status", "currentExerciseIndex", "exercises", "entries", "timers", "modality"]),
            "the named payload's key set is the seven old keys plus modality (S-20403)"
        )
        XCTAssertEqual(
            Harness.validator().validateEnvelope(named),
            [],
            "the named snapshot still conforms to the schema (S-20403)"
        )

        // A second harness: a live session holds the start slot, so the free
        // case needs its own engine, not a second start on the same one.
        let freeHarness = Harness()
        let freeEngine = await freeHarness.runningEngine()
        _ = await freeEngine.createSession(
            modality: nil,
            exercises: [slot("sx-bench", capabilities: ["sets", "reps", "load"])]
        )
        let freeSnapshot = try XCTUnwrap(freeEngine.sessionSnapshot(), "the session snapshots")
        let freePayload = try payload(of: freeSnapshot)
        XCTAssertEqual(
            Set(freePayload.keys),
            Set(["sessionId", "revision", "status", "currentExerciseIndex", "exercises", "entries", "timers"]),
            "the free payload's key set is the seven old keys, no modality (S-20403)"
        )
        XCTAssertEqual(
            Harness.validator().validateEnvelope(freeSnapshot),
            [],
            "the free snapshot still conforms to the schema (S-20403)"
        )
    }

    // MARK: - S-20404 the wrist echoes the modality it was told and keeps it

    func testS20404TheWristEchoesTheModalityItWasToldAndKeepsIt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        let first = focusSnapshot(
            messageId: "msg-p204-first",
            sessionId: "s-watch-1",
            sentAt: "2026-07-13T06:30:00Z",
            modality: "sports",
            exercises: [slot("sx-court", capabilities: ["time"])]
        )
        let applied = try await engine.applyMessage(first)
        XCTAssertEqual(applied, true, "the first-hearing snapshot applies")
        XCTAssertEqual(
            try payload(of: XCTUnwrap(engine.sessionSnapshot())).first(where: { $0.key == "modality" })?.value as? String,
            "sports",
            "the wrist's own snapshot echoes the modality it was told (D-20401)"
        )

        // A LATER phone snapshot naming a different modality is ignored: the
        // wrist keeps what it first heard (D-12591).
        let later = focusSnapshot(
            messageId: "msg-p204-second",
            sessionId: "s-watch-1",
            sentAt: "2026-07-13T06:31:00Z",
            modality: "cardio_endurance",
            exercises: [slot("sx-court", capabilities: ["time"])]
        )
        _ = try await engine.applyMessage(later)
        XCTAssertEqual(
            try payload(of: XCTUnwrap(engine.sessionSnapshot())).first(where: { $0.key == "modality" })?.value as? String,
            "sports",
            "a later phone snapshot does not change the wrist's modality (S-20404)"
        )
    }

    // MARK: - S-20406 the modality survives a relaunch

    func testS20406TheModalitySurvivesARelaunch() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "isometric_stretching",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        // A relaunch: new objects, same engine and storage.
        let relaunched = await harness.runningEngine(harness.newEngine())
        let envelope = try XCTUnwrap(relaunched.sessionSnapshot(), "the session snapshots")
        XCTAssertEqual(
            try payload(of: envelope)["modality"] as? String,
            "isometric_stretching",
            "the restored session still names its modality (S-20406)"
        )
    }
}
