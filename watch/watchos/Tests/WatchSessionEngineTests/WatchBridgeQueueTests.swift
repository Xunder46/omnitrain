//
//  WatchBridgeQueueTests.swift
//  WatchSessionEngineTests
//
//  S-6701 to S-6707 of
//  `docs/plans/2026-10-21-47b-wrist-queues-durable-frames-plan/2026-10-21-47b-wrist-queues-durable-frames-plan.md`,
//  D-1 and D-2: what the wrist owes the phone for good goes to the OS queue when
//  the radio refuses it, and every other frame is still reported and dropped.
//
//  The harness is `WatchConnectivityBridgeTests`'s, so the frames under test are
//  the ones the engine and the start paths really build.
//

import XCTest

@testable import WatchSessionEngine

/// What the platform's radio answers with. A type of its own, so a test can say
/// which of the two refusals was reported.
private enum SendFixtureError: Error {
    case refusedByTheRadio
}

/// What the platform's queue answers with.
private enum QueueFixtureError: Error {
    case refusedByTheQueue
}

final class WatchBridgeQueueTests: XCTestCase {

    /// A wrist with one logged set the phone has not confirmed: the frame an
    /// unreachable catch-up hands over.
    private func owedObservation(
        _ harness: WatchBridgeHarness,
        entryId: String = "q-1"
    ) async throws -> [String: Any] {
        _ = await harness.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await harness.engine.appendObservation(setEvent(harness.clock, entryId: entryId))
        return try XCTUnwrap(
            harness.engine.pendingObservations().first,
            "a logged set is owed"
        )
    }

    // MARK: - S-6701 a refused observation is queued, not dropped

    func testS6701ARefusedObservationIsQueued() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        let observation = try await owedObservation(harness)
        let messageId = try XCTUnwrap(observation["messageId"] as? String)

        harness.session.sendError = SendFixtureError.refusedByTheRadio
        await harness.bridge.send(observation)

        XCTAssertTrue(harness.session.sent.isEmpty, "the radio took nothing")
        XCTAssertEqual(harness.session.queued.count, 1, "the OS queue holds it")
        XCTAssertEqual(
            harness.session.queued.first?["messageId"] as? String,
            messageId,
            "the same frame, under the same message id"
        )
        XCTAssertEqual(harness.session.queued.first?["type"] as? String, "observations_up")
        XCTAssertTrue(harness.failures.isEmpty, "a hand-over to the queue is not a refusal")
    }

    // MARK: - S-6702 a refused session end is queued, not dropped

    func testS6702ARefusedSessionEndIsQueued() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        _ = await harness.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        _ = await harness.engine.finishSession()

        let lifecycle = try XCTUnwrap(
            harness.emitted("session_lifecycle").last,
            "ending the session announces it"
        )
        XCTAssertEqual(
            (lifecycle["payload"] as? [String: Any])?["state"] as? String,
            "completed"
        )
        let messageId = try XCTUnwrap(lifecycle["messageId"] as? String)

        harness.session.sendError = SendFixtureError.refusedByTheRadio
        await harness.bridge.send(lifecycle)

        XCTAssertTrue(harness.session.sent.isEmpty, "the radio took nothing")
        XCTAssertEqual(harness.session.queued.count, 1, "the OS queue holds it")
        XCTAssertEqual(harness.session.queued.first?["messageId"] as? String, messageId)
        XCTAssertEqual(harness.session.queued.first?["type"] as? String, "session_lifecycle")
        XCTAssertTrue(harness.failures.isEmpty)
    }

    // MARK: - S-6703 live-only frames are reported and dropped, one test each

    func testS6703ARefusedTimerStateIsReportedAndDropped() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        let timer: [String: Any] = [
            "type": "timer_state",
            "messageId": "m-timer-1",
            "sessionId": "s-watch-1",
            "payload": ["state": "running"],
        ]
        harness.session.sendError = SendFixtureError.refusedByTheRadio
        await harness.bridge.send(timer)

        XCTAssertTrue(harness.session.sent.isEmpty)
        XCTAssertTrue(harness.session.queued.isEmpty, "a timer would arrive stale")
        XCTAssertEqual(harness.failures.count, 1)
    }

    func testS6703ARefusedSessionSnapshotIsReportedAndDropped() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        _ = await harness.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let snapshot = try XCTUnwrap(harness.engine.sessionSnapshot())

        harness.session.sendError = SendFixtureError.refusedByTheRadio
        await harness.bridge.send(snapshot)

        XCTAssertTrue(harness.session.sent.isEmpty)
        XCTAssertTrue(harness.session.queued.isEmpty, "a snapshot would arrive stale")
        XCTAssertEqual(harness.failures.count, 1)
    }

    func testS6703ARefusedRequestIsReportedAndDropped() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()

        harness.session.sendError = SendFixtureError.refusedByTheRadio
        await harness.bridge.requestSnapshot()

        XCTAssertTrue(harness.session.sent.isEmpty)
        XCTAssertTrue(harness.session.queued.isEmpty, "a request carries no message to queue")
        XCTAssertEqual(harness.failures.count, 1)
    }

    // MARK: - S-6704 a queue that refuses is reported once

    func testS6704AQueueRefusalIsReportedOnce() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        let observation = try await owedObservation(harness)

        harness.session.sendError = SendFixtureError.refusedByTheRadio
        harness.session.queueError = QueueFixtureError.refusedByTheQueue
        await harness.bridge.send(observation)

        XCTAssertTrue(harness.session.sent.isEmpty)
        XCTAssertTrue(harness.session.queued.isEmpty)
        XCTAssertEqual(harness.failures.count, 1, "one refusal, one report")
        XCTAssertTrue(
            harness.failures.first is QueueFixtureError,
            "the queue's refusal is what is reported"
        )
    }

    // MARK: - S-6705 a durable frame that sends is never also queued

    func testS6705ADurableFrameThatSendsIsNotAlsoQueued() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        let observation = try await owedObservation(harness)

        await harness.bridge.send(observation)

        XCTAssertEqual(harness.session.sent.count, 1)
        XCTAssertTrue(harness.session.queued.isEmpty, "the OS queue is for refusals only")
        XCTAssertTrue(harness.failures.isEmpty)
    }

    // MARK: - S-6706 durability is exactly the two frames the phone must not lose

    func testS6706OnlyObservationsAndTheEndAreDurable() {
        XCTAssertTrue(WatchConnectivityBridge.isDurable(["type": "observations_up"]))
        XCTAssertTrue(WatchConnectivityBridge.isDurable(["type": "session_lifecycle"]))

        XCTAssertFalse(WatchConnectivityBridge.isDurable(["type": "timer_state"]))
        XCTAssertFalse(WatchConnectivityBridge.isDurable(["type": "session_snapshot"]))
        XCTAssertFalse(WatchConnectivityBridge.isDurable(["type": "receipt"]))
        XCTAssertFalse(
            WatchConnectivityBridge.isDurable(WatchTransportRequest.snapshotFrame()),
            "a request is not a protocol message"
        )
        XCTAssertFalse(WatchConnectivityBridge.isDurable([:]))
    }

    // MARK: - S-6707 an unreachable catch-up queues both logged sets

    func testS6707AnUnreachableCatchUpQueuesBothLoggedSets() async throws {
        let harness = WatchBridgeHarness(isPhoneReachable: false)
        await harness.launch()
        _ = await harness.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await harness.engine.appendObservation(setEvent(harness.clock, entryId: "q-1"))
        harness.clock.advance(90)
        try await harness.engine.appendObservation(setEvent(harness.clock, entryId: "q-2"))

        let messageIds = harness.engine.pendingObservations()
            .compactMap { $0["messageId"] as? String }
        XCTAssertEqual(messageIds.count, 2, "two sets are owed")
        XCTAssertEqual(Set(messageIds).count, 2, "and they are two distinct messages")

        // Apart: the orchestrator hands both over and the radio refuses them.
        harness.session.sendError = SendFixtureError.refusedByTheRadio
        await harness.orchestrator.sync()
        await harness.orchestrator.sync()

        XCTAssertTrue(harness.session.sent.isEmpty, "apart, the radio took nothing")
        let queued = harness.session.queued.compactMap { $0["messageId"] as? String }
        XCTAssertEqual(Set(queued), Set(messageIds), "both sets are queued under their own ids")
        XCTAssertEqual(
            queued.count,
            4,
            "two catch-ups queue both sets again — the fake does not dedupe, the app target does"
        )
        XCTAssertTrue(
            harness.session.queued.allSatisfy { $0["type"] as? String == "observations_up" },
            "only the durable frames reach the queue"
        )
    }
}
