//
//  WatchFollowedSessionEndTests.swift
//  WatchSessionEngineTests
//
//  S-10111 to S-10116 of
//  `docs/plans/2026-10-24-71-followed-session-heart-rate-plan/` (plan 71
//  D-1, D-2, D-3): a session the wrist followed from the phone now gets a
//  `session_end` too, marked `followed: true`, replacing the D-120 negative
//  test the plan retires (`testASessionTheWristJoinedEndsWithNoEnd`).
//

import XCTest

@testable import WatchSessionEngine

final class WatchFollowedSessionEndTests: XCTestCase {

    // MARK: - helpers (copied from the D-120 tests in WatchSessionEngineTests.swift)

    private func sessionEnd(_ engine: WatchSessionEngine) -> [String: Any]? {
        engine.observations.first { $0.kind == WatchObservationKind.sessionEnd }?.payload
    }

    private func sessionEnds(_ engine: WatchSessionEngine) -> [[String: Any]] {
        engine.observations
            .filter { $0.kind == WatchObservationKind.sessionEnd }
            .map(\.payload)
    }

    /// Adopts the phone's session `s-phone` as the wrist's own, the way a
    /// `session_snapshot` from the phone does.
    private func joinPhoneSession(
        _ engine: WatchSessionEngine,
        status: String = WatchSessionStatus.active,
        sentAt: String = "2026-07-13T06:00:00Z",
        messageId: String = "msg-join"
    ) async throws {
        _ = try await engine.applyMessage([
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": "s-phone",
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": sentAt,
            "payload": [
                "sessionId": "s-phone",
                "revision": 0,
                "status": status,
                "currentExerciseIndex": 0,
                "exercises": [exercise("sx-bench")],
                "entries": [[String: Any]](),
                "timers": [String: Any](),
            ] as [String: Any],
        ])
    }

    private func lifecycle(
        _ state: String,
        at: String,
        messageId: String,
        sessionId: String = "s-phone"
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "session_lifecycle",
            "origin": "phone",
            "sentAt": at,
            "payload": ["state": state, "at": at],
        ]
    }

    // MARK: - S-10111 ended by the phone's lifecycle message

    func testS10111APhoneStartedSessionEndedByThePhonesLifecycleGetsOneFollowedEnd() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        try await joinPhoneSession(engine)
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 121)
        harness.clock.advance(60)
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 131)
        harness.clock.advance(60)
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 141)
        harness.clock.advance(480)

        _ = try await engine.applyMessage(
            lifecycle(WatchLifecycleState.completed, at: "2026-07-13T06:10:00Z", messageId: "msg-end-1")
        )

        let ends = sessionEnds(engine)
        XCTAssertEqual(ends.count, 1, "S-10111 one end for the followed session")
        let end = try XCTUnwrap(ends.first)
        XCTAssertEqual(end["entryId"] as? String, "end-s-phone")
        XCTAssertEqual(end["eventId"] as? String, "end-s-phone")
        XCTAssertEqual(end["status"] as? String, WatchSessionStatus.completed)
        XCTAssertEqual(end["followed"] as? Bool, true, "S-10111 the wrist followed the phone's session")
        XCTAssertEqual(end["startedAt"] as? String, utcIso(testInstant()), "S-10111 the phone session's start")
        XCTAssertEqual(
            end["endedAt"] as? String,
            "2026-07-13T06:10:00.000Z",
            "S-10111 the lifecycle's own `at`"
        )
        XCTAssertEqual(numericValue(end["avgHeartRateBpm"]), 131, "S-10111 121, 131 and 141")
        XCTAssertEqual(numericValue(end["maxHeartRateBpm"]), 141, "S-10111 the largest reading")
    }

    // MARK: - S-10112 ended by a phone snapshot

    func testS10112APhoneSnapshotWithACompletedStatusEndsTheFollowedSessionAtTheSentAt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        try await joinPhoneSession(engine)

        try await joinPhoneSession(
            engine,
            status: WatchSessionStatus.completed,
            sentAt: "2026-07-13T06:05:00Z",
            messageId: "msg-snapshot-ends"
        )

        let ends = sessionEnds(engine)
        XCTAssertEqual(ends.count, 1, "S-10112 one end for the followed session")
        let end = try XCTUnwrap(ends.first)
        XCTAssertEqual(end["status"] as? String, WatchSessionStatus.completed)
        XCTAssertEqual(end["followed"] as? Bool, true, "S-10112")
        XCTAssertEqual(
            end["endedAt"] as? String,
            "2026-07-13T06:05:00.000Z",
            "S-10112 the envelope's `sentAt`"
        )
    }

    // MARK: - S-10113 abandoned by the phone

    func testS10113ASessionAbandonedByThePhoneGetsAFollowedAbandonedEnd() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        try await joinPhoneSession(engine)

        _ = try await engine.applyMessage(
            lifecycle(WatchLifecycleState.abandoned, at: "2026-07-13T06:07:00Z", messageId: "msg-discard")
        )

        let ends = sessionEnds(engine)
        XCTAssertEqual(ends.count, 1, "S-10113 one end for the followed session")
        let end = try XCTUnwrap(ends.first)
        XCTAssertEqual(end["status"] as? String, WatchSessionStatus.abandoned)
        XCTAssertEqual(end["followed"] as? Bool, true, "S-10113")
    }

    // MARK: - S-10114 a second terminal message adds no second end

    func testS10114ASecondTerminalMessageDoesNotAddASecondEnd() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        try await joinPhoneSession(engine)

        _ = try await engine.applyMessage(
            lifecycle(WatchLifecycleState.completed, at: "2026-07-13T06:10:00Z", messageId: "msg-end-1")
        )
        _ = try await engine.applyMessage(
            lifecycle(WatchLifecycleState.abandoned, at: "2026-07-13T06:11:00Z", messageId: "msg-end-2")
        )

        let ends = sessionEnds(engine)
        XCTAssertEqual(ends.count, 1, "S-10114 the id is the session's, so no second end")
        XCTAssertEqual(ends.first?["status"] as? String, WatchSessionStatus.completed, "S-10114 the first end keeps its values")
    }

    // MARK: - S-10115 a wrist-created end has no `followed` key

    func testS10115AWristCreatedSessionsEndCarriesNoFollowedKey() async throws {
        let completed = Harness()
        let completedEngine = await completed.runningEngine()
        _ = await completedEngine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = await completedEngine.finishSession()
        let completedEnd = try XCTUnwrap(sessionEnd(completedEngine), "S-10115 the wrist's own end")
        XCTAssertEqual(completedEnd["status"] as? String, WatchSessionStatus.completed)
        XCTAssertNil(completedEnd["followed"], "S-10115 a wrist-created end says nothing about following")

        let abandoned = Harness()
        let abandonedEngine = await abandoned.runningEngine()
        _ = await abandonedEngine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = await abandonedEngine.abandonSession()
        let abandonedEnd = try XCTUnwrap(sessionEnd(abandonedEngine), "S-10115 the wrist's own end")
        XCTAssertEqual(abandonedEnd["status"] as? String, WatchSessionStatus.abandoned)
        XCTAssertNil(abandonedEnd["followed"], "S-10115 a wrist-created end says nothing about following")
    }

    // MARK: - S-10116 pruning

    func testS10116AFollowedSessionWhoseEndIsAcknowledgedReleasesItsLog() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        try await joinPhoneSession(engine)
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 121)
        _ = await engine.finishSession()
        _ = await engine.confirmObservations(["end-s-phone"])

        let released = await engine.pruneSettledSensorSamples()

        XCTAssertEqual(released.count, 1, "S-10116 the end acknowledged, the log is released")
        XCTAssertTrue(engine.sensorSamples.isEmpty, "S-10116")
    }

    func testS10116AFollowedSessionWithNoEndObservationIsPrunedAsBefore() async throws {
        // Seeded the way a store written before this plan looked: a session the
        // wrist followed, completed, no end observation at all.
        let store = InMemoryWatchSessionStore()
        let startedAt = testInstant()
        for (id, status) in [("row-1", WatchSessionStatus.active), ("row-2", WatchSessionStatus.completed)] {
            _ = await store.append(
                .session(
                    WatchSessionRecord(
                        recordId: id,
                        sessionId: "s-legacy-phone",
                        recordedAt: startedAt,
                        startedAt: startedAt,
                        modality: nil,
                        source: "phone",
                        status: status,
                        currentExerciseIndex: 0
                    )
                )
            )
        }
        _ = await store.append(
            .sensorSample(
                WatchSensorSampleRecord(
                    recordId: "sen-legacy-phone",
                    sessionId: "s-legacy-phone",
                    recordedAt: startedAt,
                    kind: WatchSensorKind.heartRate,
                    value: 120
                )
            )
        )

        let engine = await Harness(store: store).runningEngine()
        let released = await engine.pruneSettledSensorSamples()

        XCTAssertEqual(released.count, 1, "S-10116 a followed session owes no end receipt, so nothing extra holds its log")
        let stored = await store.readAll()
        XCTAssertTrue(stored.sensorSamples.isEmpty, "S-10116")
    }
}
