//
//  WatchPhoneEntriesTests.swift
//  WatchSessionEngineTests
//
//  S-32, S-35, S-38 and S-41 of
//  `docs/plans/2026-10-05-15d-watch-session-sync-pr3-plan/2026-10-05-15d-watch-session-sync-pr3-plan.md`
//  on the native watchOS side — the same scenarios the Dart suite proves in
//  `test/watch_session_projection_test.dart`, run against the Swift engine so
//  both watch clients reconcile a phone's entries identically.
//
//  What the register pins: a snapshot that names a session the wrist does not
//  hold is adopted, and the entries it carries are stored under their own ids,
//  once each however often the answer is re-delivered (S-32, S-38); an id the
//  wrist already holds is *re-stated* — the answer's payload is what the wrist
//  shows, while the stored observation row is left alone, so the log stays
//  append-only and the set neither doubles nor has its first value rewritten
//  (S-35, D-35); and an answer carrying no phone entries neither drops nor
//  doubles the wrist's own set (S-41).
//
//  S-145 of
//  `docs/plans/2026-10-07-17d-watch-auto-sync-pr4-plan/2026-10-07-17d-watch-auto-sync-pr4-plan.md`
//  is here too: the phone's `timed`, `hold` and `round` entries are the wrist's
//  own — stored once each, and counted by the logging surface's tallies.
//

import XCTest

@testable import WatchSessionEngine

final class WatchPhoneEntriesTests: XCTestCase {

    // MARK: - S-38 / S-32 a snapshot the wrist does not hold

    func testS38TheWristAdoptsASessionItDoesNotHold() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        XCTAssertNil(engine.session)

        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-adopt-1",
                sessionId: "s-phone",
                revision: 4,
                entries: [entry("e-adopted-1", at: "2026-07-13T06:00:00Z", loadKg: 60)]
            )
        )

        XCTAssertEqual(engine.session?.sessionId, "s-phone", "S-38 the wrist takes the session it was sent")
        XCTAssertEqual(
            engine.entries.map(\.entryId),
            ["e-adopted-1"],
            "S-38 the entry the phone logged is in the wrist's log"
        )
        XCTAssertEqual(
            engine.observations.filter { $0.sessionId == "s-phone" }.count,
            1,
            "S-38 stored, so the adopted entry survives a relaunch"
        )
    }

    func testS32TheSameAnswerAgainAndAFreshAnswerStoreOneRowPerId() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let first = snapshot(
            messageId: "msg-answer-1",
            sessionId: "s-phone",
            revision: 4,
            entries: [entry("e-bench-0", at: "2026-07-13T06:00:00Z", loadKg: 60)]
        )

        _ = try await engine.applyMessage(first)
        _ = try await engine.applyMessage(first)
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-answer-2",
                sessionId: "s-phone",
                revision: 5,
                entries: [
                    entry("e-bench-0", at: "2026-07-13T06:00:00Z", loadKg: 60),
                    entry("e-bench-1", at: "2026-07-13T06:05:00Z", loadKg: 62.5),
                ]
            )
        )

        XCTAssertEqual(
            engine.entries.map(\.entryId),
            ["e-bench-0", "e-bench-1"],
            "S-32 the answer twice over doubles nothing: one row per entry id"
        )
        XCTAssertEqual(
            engine.observations.filter { $0.sessionId == "s-phone" }.count,
            2,
            "S-32 the store holds the phone's two entries, not four"
        )
    }

    // MARK: - S-35 a held id is re-stated, not resaved

    /// The phone keeps the first value it stored for an id it holds, so the two
    /// stacks diverge on an edited set: the wrist shows the phone's newest
    /// value, the phone its own. The divergence is the point of D-35, not a
    /// defect — but the wrist's stored row is still the one it first wrote.
    func testS35AReStatementShowsThePhonesNewValueAndLeavesTheRow() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-restate-1",
                sessionId: "s-watch-1",
                revision: 4,
                entries: [entry("e-bench-0", at: "2026-07-13T06:00:00Z", loadKg: 60)]
            )
        )

        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-restate-2",
                sessionId: "s-watch-1",
                revision: 5,
                entries: [entry("e-bench-0", at: "2026-07-13T06:00:00Z", loadKg: 65)]
            )
        )

        XCTAssertEqual(
            engine.entries.count,
            1,
            "S-35 the wrist holds the id, so the answer re-states it: no second row"
        )
        XCTAssertEqual(
            engine.entries.first?.payload["loadKg"] as? Double,
            65,
            "S-35 the wrist shows the weight the phone has now"
        )

        let rows = engine.observations.filter { $0.recordId == "e-bench-0" }
        XCTAssertEqual(rows.count, 1, "S-35 the store is append-only: exactly one row")
        XCTAssertEqual(
            rows.first?.payload["loadKg"] as? Double,
            60,
            "S-35 a re-statement never rewrites the stored observation"
        )
        XCTAssertNotNil(rows.first?.confirmedAt, "S-35 the snapshot is still the receipt for what it carries")
        XCTAssertTrue(engine.pendingObservations().isEmpty, "S-35 nothing is owed: the phone has the entry")
    }

    /// The wrist already holds the id when the phone's *second* edit arrives,
    /// so this is the case a fold order that let the earlier correction win
    /// would get wrong: the newest snapshot has to be the authoritative one.
    func testASecondEditWinsOverTheFirst() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        for (revision, loadKg) in [(4, 60.0), (5, 65.0), (6, 70.0)] {
            _ = try await engine.applyMessage(
                snapshot(
                    messageId: "msg-second-edit-\(revision)",
                    sessionId: "s-watch-1",
                    revision: revision,
                    entries: [entry("e-bench-0", at: "2026-07-13T06:00:00Z", loadKg: loadKg)]
                )
            )
        }

        XCTAssertEqual(
            engine.entries.first?.payload["loadKg"] as? Double,
            70,
            "S-35/D-35 the newest snapshot is authoritative: a set edited twice (60 -> 65 -> 70) shows 70, not the first correction"
        )

        let rows = engine.observations.filter { $0.recordId == "e-bench-0" }
        XCTAssertEqual(rows.count, 1, "S-35 one row per id however many times the phone re-states it")
        XCTAssertEqual(
            rows.first?.payload["loadKg"] as? Double,
            60,
            "S-35 the second re-statement still never rewrites the stored observation"
        )
    }

    func testS35AReStatementOfADeletedIdStaysDeleted() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-deleted-1",
                sessionId: "s-watch-1",
                revision: 4,
                entries: [entry("e-bench-0", at: "2026-07-13T06:00:00Z", loadKg: 60)]
            )
        )
        _ = try await engine.applyMessage(
            structureChange(
                changeId: "chg-delete-1",
                changes: [["kind": "delete_entry", "entryId": "e-bench-0"]]
            )
        )
        XCTAssertTrue(engine.entries.isEmpty, "S-35 an entry the phone deleted is gone")

        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-deleted-2",
                sessionId: "s-watch-1",
                revision: 6,
                entries: [entry("e-bench-0", at: "2026-07-13T06:00:00Z", loadKg: 65)]
            )
        )

        XCTAssertTrue(
            engine.entries.isEmpty,
            "S-35 a deleted id is dropped before a correction is read, so re-stating it revives nothing"
        )
    }

    // MARK: - S-41 the wrist's own set faces an answer with no entries

    func testS41AWristLoggedSetSurvivesAnAnswerWithNoEntries() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-wrist-1"))

        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-no-entries",
                sessionId: "s-watch-1",
                revision: 4,
                exercises: [exercise("sx-bench")],
                entries: []
            )
        )

        XCTAssertEqual(
            engine.observations.filter { $0.recordId == "e-wrist-1" }.count,
            1,
            "S-41 the wrist's own set is neither dropped nor doubled by an answer with no entries"
        )
        XCTAssertEqual(engine.entries.map(\.entryId), ["e-wrist-1"], "S-41 it is still the wrist's log")
        XCTAssertEqual(
            engine.entries.first?.payload["loadKg"] as? Int,
            80,
            "S-41 the wrist's own set is shown as it was logged"
        )
        XCTAssertEqual(
            engine.pendingObservations().count,
            1,
            "S-41 an answer that names no entry confirms none: the wrist's set is still owed"
        )

        _ = await engine.confirmObservations(["e-wrist-1"])

        XCTAssertNotNil(
            engine.observations.first { $0.recordId == "e-wrist-1" }?.confirmedAt,
            "S-41 the receipt that names it is what confirms it"
        )
        XCTAssertTrue(engine.pendingObservations().isEmpty, "S-41")
    }

    // MARK: - the reconciliation fixture, on the Swift side

    /// The same fixture the Dart suite replays in `test/live_mirroring_test.dart`.
    /// Its second answer re-carries `entry-slot-bench-0` with the values the
    /// wrist already shows, so what this pins is the shape of a re-statement
    /// (one row, the answer's copy) rather than the divergence an edit produces;
    /// `testS35AReStatementShowsThePhonesNewValueAndLeavesTheRow` pins that.
    func testTheMergeFixturesHeldIdIsReStatedOnce() async throws {
        let fixture = try Fixtures.json("fixtures/reconciliation/phone_entries_merge.json")
        let snapshotMessage = try XCTUnwrap(fixture["snapshot"] as? [String: Any])
        let stream = try XCTUnwrap(fixture["stream"] as? [[String: Any]])
        let expected = try XCTUnwrap(fixture["expected"] as? [String: Any])

        let harness = Harness()
        let engine = await harness.runningEngine()
        try await engine.applyMessage(snapshotMessage)
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

        let carried = try XCTUnwrap(expected["entries"] as? [[String: Any]])
        XCTAssertEqual(
            engine.entries.map(\.entryId),
            carried.compactMap { $0["entryId"] as? String },
            "S-32 the wrist's log is the phone's, and the wrist's own observation is still in it"
        )
        XCTAssertEqual(
            engine.observations.filter { $0.recordId == "entry-slot-bench-0" }.count,
            1,
            "S-35 the answer re-carried a held id: one row, not two"
        )
    }

    // MARK: - S-145 a phone entry of any kind is the wrist's own

    /// The phone sends a `timed`, a `hold` and a `round` over three slots. The
    /// wrist stores each under its own id — not only the sets — and the logging
    /// surface reads them back as work it did: the round's number is spent, and
    /// the hold's own window and added load are what the wrist's next hold
    /// repeats.
    func testS145APhoneEntryOfEveryKindIsTheWristsOwn() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let frame = phoneEntriesSnapshot(
            messageId: "msg-kinds-1",
            revision: 7,
            currentExerciseIndex: 2
        )
        XCTAssertTrue(
            Harness.validator().validateEnvelope(frame).isEmpty,
            "\(Harness.validator().validateEnvelope(frame))"
        )

        _ = try await engine.applyMessage(frame)
        _ = try await engine.applyMessage(frame)

        XCTAssertEqual(
            Set(engine.entries.map(\.entryId)),
            ["entry-sx-ride-0", "entry-sx-plank-0", "entry-sx-burpee-0"],
            "S-145 every kind the phone logged is in the wrist's log"
        )
        XCTAssertEqual(
            engine.entries.count,
            3,
            "S-145 …once each: the same frame twice over doubles nothing"
        )
        XCTAssertEqual(
            engine.entries.first { $0.entryId == "entry-sx-plank-0" }?
                .payload["extraLoadKg"] as? Double,
            12,
            "S-145 the hold keeps the phone's added load"
        )
        XCTAssertEqual(
            engine.entries.first { $0.entryId == "entry-sx-burpee-0" }?
                .payload["roundNumber"] as? Int,
            1,
            "S-145 and the round its number"
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.effortKind, WatchEffortKind.round, "S-145 the round slot is shown")
        XCTAssertEqual(
            surface.nextRoundNumber,
            2,
            "S-145 the phone's round 1 is counted: the wrist's next round is 2"
        )

        // One frame later the wrist is on the hold slot: what the phone logged
        // for it is what the surface's next hold carries.
        _ = try await engine.applyMessage(
            phoneEntriesSnapshot(
                messageId: "msg-kinds-2",
                revision: 8,
                currentExerciseIndex: 1
            )
        )

        XCTAssertEqual(surface.effortKind, WatchEffortKind.drill, "S-145 the hold slot is shown")
        XCTAssertEqual(
            engine.entries.count,
            3,
            "S-145 a second frame carrying the same three ids adds no fourth row"
        )
        let phoneHold = try XCTUnwrap(
            engine.entries.first { $0.entryId == "entry-sx-plank-0" }
        )
        XCTAssertEqual(
            phoneHold.payload["startedAt"] as? String,
            "2026-07-13T06:00:00Z",
            "S-145 the phone's hold is the minute from 06:00 the wrist carries"
        )
        XCTAssertEqual(
            phoneHold.payload["endedAt"] as? String,
            "2026-07-13T06:01:00Z",
            "S-145 …to 06:01"
        )
        XCTAssertEqual(
            value(surface, WatchMetricKey.extraWeight),
            12,
            "S-145 and the phone's added load with it"
        )

        // The wrist's own hold, started and logged over the same minute, is the
        // same window: a phone entry of every kind is the wrist's own.
        await surface.startWork()
        harness.clock.advance(60)
        let wristHold = try await surface.log().payload

        XCTAssertEqual(wristHold["kind"] as? String, "hold")
        XCTAssertEqual(wristHold["startedAt"] as? String, "2026-07-13T06:00:00.000Z")
        XCTAssertEqual(wristHold["endedAt"] as? String, "2026-07-13T06:01:00.000Z")
        XCTAssertEqual(wristHold["extraLoadKg"] as? Double, 12)
        XCTAssertEqual(
            engine.entries.count,
            4,
            "S-145 the wrist's own hold is one more row, once"
        )
    }

    private func value(_ surface: WatchLoggingState, _ metricKey: String) -> Double? {
        surface.fields.first(where: { $0.metricKey == metricKey })?.value
    }

    // MARK: - Helpers

    private func slot(_ id: String, capabilities: [String]) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
    }

    /// A phone frame carrying one entry of every kind the sync carries, over
    /// three slots, with its position selectable so a surface can be read at
    /// each of them.
    private func phoneEntriesSnapshot(
        messageId: String,
        revision: Int,
        currentExerciseIndex: Int
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": "s-kinds",
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-07-13T06:30:00Z",
            "payload": [
                "sessionId": "s-kinds",
                "revision": revision,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": currentExerciseIndex,
                "exercises": [
                    slot("sx-ride", capabilities: ["time", "distance"]),
                    slot("sx-plank", capabilities: ["hold", "time"]),
                    slot("sx-burpee", capabilities: ["rounds", "time"]),
                ],
                "entries": [
                    [
                        "entryId": "entry-sx-ride-0",
                        "eventId": "entry-sx-ride-0",
                        "kind": "timed",
                        "loggedAt": "2026-07-13T06:20:00Z",
                        "sessionExerciseId": "sx-ride",
                        "exerciseId": "ex-sx-ride",
                        "startedAt": "2026-07-13T06:10:00Z",
                        "endedAt": "2026-07-13T06:20:00Z",
                        "distanceMeters": 2_000.0,
                    ],
                    [
                        "entryId": "entry-sx-plank-0",
                        "eventId": "entry-sx-plank-0",
                        "kind": "hold",
                        "loggedAt": "2026-07-13T06:01:00Z",
                        "sessionExerciseId": "sx-plank",
                        "exerciseId": "ex-sx-plank",
                        "startedAt": "2026-07-13T06:00:00Z",
                        "endedAt": "2026-07-13T06:01:00Z",
                        "extraLoadKg": 12.0,
                    ],
                    [
                        "entryId": "entry-sx-burpee-0",
                        "eventId": "entry-sx-burpee-0",
                        "kind": "round",
                        "loggedAt": "2026-07-13T06:08:00Z",
                        "sessionExerciseId": "sx-burpee",
                        "exerciseId": "ex-sx-burpee",
                        "startedAt": "2026-07-13T06:05:00Z",
                        "endedAt": "2026-07-13T06:08:00Z",
                        "roundNumber": 1,
                        "pausedMs": 5_000,
                    ],
                ],
                "timers": [String: Any](),
            ] as [String: Any],
        ]
    }

    private func entry(_ entryId: String, at loggedAt: String, loadKg: Double) -> [String: Any] {
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

    private func snapshot(
        messageId: String,
        sessionId: String,
        revision: Int,
        exercises: [[String: Any]]? = nil,
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
                "exercises": exercises ?? [exercise("sx-bench")],
                "entries": entries,
                "timers": [String: Any](),
            ] as [String: Any],
        ]
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
}
