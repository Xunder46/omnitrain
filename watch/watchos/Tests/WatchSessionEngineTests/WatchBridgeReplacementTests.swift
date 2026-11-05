//
//  WatchBridgeReplacementTests.swift
//  WatchSessionEngineTests
//
//  S-9903 to S-9908, S-9910 to S-9914 and S-9916 of
//  `docs/plans/2026-10-24-69-watch-queues-workout-state-plan/2026-10-24-69-watch-queues-workout-state-plan.md`,
//  D-3 to D-8: only the newest copy of a workout's snapshot or lifecycle waits
//  in the OS queue, a stale copy never replaces a newer one, entries are never
//  withdrawn, live sends clear older waiting copies, and two hand-overs at once
//  leave one copy.
//
//  Scenario map:
//  - S-9903  only the newest snapshot of a workout waits
//  - S-9904  same messageId, newer content (near-twin) — A fake, B harness
//  - S-9905  a stale copy handed over late — A no replace, B equal stamp replaces
//  - S-9906  40 exercises added while apart leave one snapshot
//  - S-9907  25 exercise moves while apart leave the newest one
//  - S-9908  the end waits and withdraws the workout's live state — A/B/C
//  - S-9910  entries are never withdrawn; timers and requests never wait
//  - S-9911  a live send clears older waiting copies — A/B/C
//  - S-9912  waiting is not delivered
//  - S-9913  failures — A queue refusal, B not activated
//  - S-9914  two hand-overs at once leave one copy
//  - S-9916  copies left by an earlier run are matched
//
//  The harness is `WatchConnectivityBridgeTests`'s, so the frames under test are
//  the ones the engine and the start paths really build.
//

import XCTest

@testable import WatchSessionEngine

/// What the platform's radio answers with. A type of its own, so a test can say
/// which of the two refusals was reported.
private struct RefusedByRadio: Error {}

/// What the platform's queue answers with.
private struct RefusedByQueue: Error {}

/// Collects what the bridge reported, from a closure that must not capture a
/// local variable.
private final class FailureBox {
    private(set) var failures: [Error] = []

    func append(_ error: Error) { failures.append(error) }
}

final class WatchBridgeReplacementTests: XCTestCase {

    // MARK: - Fixtures

    private func at(_ seconds: Int) -> String {
        utcIso(testInstant().addingTimeInterval(Double(seconds)))
    }

    private func snap(
        _ session: String,
        _ id: String,
        _ t: Int,
        status: String = "active",
        entries: [String] = []
    ) -> [String: Any] {
        [
            "type": "session_snapshot",
            "messageId": id,
            "sessionId": session,
            "sentAt": at(t),
            "payload": [
                "sessionId": session,
                "status": status,
                "entries": entries.map { ["entryId": $0] },
            ],
        ]
    }

    private func lc(_ session: String, _ state: String, _ id: String, _ t: Int) -> [String: Any] {
        [
            "type": "session_lifecycle",
            "messageId": id,
            "sessionId": session,
            "sentAt": at(t),
            "payload": ["state": state, "at": at(t)],
        ]
    }

    private func obs(_ session: String, _ id: String) -> [String: Any] {
        [
            "type": "observations_up",
            "messageId": id,
            "sessionId": session,
            "sentAt": at(0),
            "payload": ["events": []],
        ]
    }

    private func ids(_ frames: [[String: Any]]) -> [String] {
        frames.compactMap { $0["messageId"] as? String }
    }

    /// A bridge over a fake whose radio refuses everything: the "apart" shape
    /// the queue tests use.
    private func apartBridge() -> (FakeWatchConnectivitySession, WatchConnectivityBridge, FailureBox) {
        let session = FakeWatchConnectivitySession()
        session.sendError = RefusedByRadio()
        let box = FailureBox()
        let bridge = WatchConnectivityBridge(
            session: session,
            onFailure: { box.append($0) }
        )
        return (session, bridge, box)
    }

    /// Lets two callers be inside `outstandingTransfers()` together (S-9914's race window).
    private final class RaceGate: @unchecked Sendable {
        private let condition = NSCondition()
        private var entered = 0

        func pass() {
            condition.lock()
            entered += 1
            condition.broadcast()
            let deadline = Date().addingTimeInterval(0.2)
            while entered < 2 && condition.wait(until: deadline) {}
            condition.unlock()
        }
    }

    // MARK: - S-9903 only the newest snapshot of a workout waits

    func testS9903OnlyTheNewestSnapshotOfAWorkoutWaits() async throws {
        let (session, bridge, box) = apartBridge()
        session.seedOutstanding([
            snap("s-1", "mA", 1),
            snap("s-2", "mB", 1),
            obs("s-1", "mO"),
            lc("s-1", "started", "mL", 0),
            ["foo": 1],
            ["messageId": "x"],
        ])

        await bridge.send(snap("s-1", "mC", 2))

        XCTAssertEqual(
            session.cancels,
            [["mA"]],
            "S-9903 only the older snapshot of the same workout is withdrawn"
        )
        XCTAssertEqual(
            ids(session.outstanding),
            ["mB", "mO", "mL", "x", "mC"],
            "S-9903 every other waiting frame keeps its place, the new snapshot joins"
        )
        XCTAssertEqual(
            session.outstanding.count,
            6,
            "S-9903 the frame without a messageId is still held, it is just never named"
        )
        XCTAssertTrue(box.failures.isEmpty, "S-9903 a hand-over to the queue is not a refusal")
    }

    // MARK: - S-9904 same messageId, newer content (near-twin)

    func testS9904ASameMessageIdNewerContentReplacesTheOlderCopy() async throws {
        let (session, bridge, box) = apartBridge()
        session.seedOutstanding([snap("s-1", "mA", 1)])

        await bridge.send(snap("s-1", "mA", 2, entries: ["e-1"]))

        XCTAssertEqual(
            session.cancels,
            [["mA"]],
            "S-9904A a snapshot replaces the waiting copy under its own id too"
        )
        XCTAssertEqual(session.outstanding.count, 1, "S-9904A exactly one copy waits")
        XCTAssertEqual(ids(session.outstanding), ["mA"], "S-9904A under the same message id")
        XCTAssertEqual(
            session.outstanding.first?["sentAt"] as? String,
            at(2),
            "S-9904A the newer stamp is the one that waits"
        )
        let entries = (session.outstanding.first?["payload"] as? [String: Any])?["entries"]
            as? [[String: Any]]
        XCTAssertEqual(
            entries?.count,
            1,
            "S-9904A the newer content is the one that waits"
        )
        XCTAssertEqual(
            entries?.first?["entryId"] as? String,
            "e-1",
            "S-9904A the newer content is the one that waits"
        )
        XCTAssertTrue(box.failures.isEmpty)
    }

    func testS9904BTheEngineRebuildsTheSnapshotWithTheSameId() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        _ = await harness.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        harness.session.sendError = RefusedByRadio()

        let first = try XCTUnwrap(
            harness.emitted("session_snapshot").first,
            "starting a session announces it with a snapshot"
        )
        let firstId = try XCTUnwrap(first["messageId"] as? String)
        await harness.bridge.send(first)

        try await harness.engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))
        harness.clock.advance(60)
        await harness.orchestrator.sync()

        let snapshots = harness.session.outstanding.filter {
            $0["type"] as? String == "session_snapshot"
        }
        XCTAssertEqual(snapshots.count, 1, "S-9904B exactly one snapshot waits")
        XCTAssertEqual(
            snapshots.first?["messageId"] as? String,
            firstId,
            "S-9904B the rebuilt snapshot keeps the near-twin's message id"
        )
        XCTAssertEqual(
            snapshots.first?["sentAt"] as? String,
            utcIso(testInstant().addingTimeInterval(60)),
            "S-9904B the rebuilt snapshot carries the newer stamp"
        )
        let entries = (snapshots.first?["payload"] as? [String: Any])?["entries"] as? [[String: Any]]
        XCTAssertTrue(
            entries?.contains { $0["entryId"] as? String == "e-1" } ?? false,
            "S-9904B the rebuilt snapshot carries the logged set"
        )
    }

    // MARK: - S-9905 a stale copy handed over late (out of order)

    func testS9905AAStaleCopyHandedOverLateIsNotQueued() async throws {
        let (session, bridge, box) = apartBridge()
        session.seedOutstanding([snap("s-1", "mN", 3)])

        await bridge.send(snap("s-1", "mO", 2))

        XCTAssertTrue(session.cancels.isEmpty, "S-9905A a stale copy withdraws nothing")
        XCTAssertEqual(ids(session.outstanding), ["mN"], "S-9905A the newer copy stays")
        XCTAssertTrue(
            session.queued.isEmpty,
            "S-9905A the stale copy is not queued (the seeded N never went through queue)"
        )
        XCTAssertTrue(box.failures.isEmpty, "S-9905A stale is not a failure")
    }

    func testS9905BAnEqualStampReplaces() async throws {
        let (session, bridge, _) = apartBridge()
        session.seedOutstanding([snap("s-1", "mN", 3)])

        await bridge.send(snap("s-1", "mE", 3))

        XCTAssertEqual(session.cancels, [["mN"]], "S-9905B an equal stamp replaces, not `<` but `<=`")
        XCTAssertEqual(ids(session.outstanding), ["mE"], "S-9905B the handed-over copy waits")
    }

    // MARK: - S-9906 40 exercises added while apart (overflow)

    func testS9906FortyExercisesAddedWhileApartLeaveOneSnapshot() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        harness.session.sendError = RefusedByRadio()
        _ = await harness.engine.createSession(modality: nil, exercises: [exercise("sx-0")])

        var handed = 0
        func handOverNew() async {
            let frames = Array(harness.emitted[handed...])
            handed = harness.emitted.count
            for frame in frames { await harness.bridge.send(frame) }
        }
        await handOverNew()

        for i in 1...40 {
            harness.clock.advance(1)
            _ = await harness.engine.insertExercise(exercise("sx-\(i)"))
            await handOverNew()

            let snapshots = harness.session.outstanding.filter {
                $0["type"] as? String == "session_snapshot"
            }
            XCTAssertEqual(
                snapshots.count,
                1,
                "S-9906 after step \(i) exactly one snapshot waits"
            )
        }

        XCTAssertEqual(
            harness.session.cancels.flatMap { $0 }.count,
            40,
            "S-9906 41 snapshots handed over, 40 cancels (no lifecycle is cancelled here)"
        )
        let survivor = try XCTUnwrap(
            harness.session.outstanding.first { $0["type"] as? String == "session_snapshot" },
            "S-9906 a snapshot survives"
        )
        XCTAssertEqual(
            ((survivor["payload"] as? [String: Any])?["exercises"] as? [[String: Any]])?.count,
            41,
            "S-9906 the survivor carries every exercise"
        )
        let lifecycles = harness.session.outstanding.filter {
            $0["type"] as? String == "session_lifecycle"
        }
        XCTAssertEqual(lifecycles.count, 1, "S-9906 exactly one lifecycle waits")
        XCTAssertEqual(
            (lifecycles.first?["payload"] as? [String: Any])?["state"] as? String,
            "started",
            "S-9906 the waiting lifecycle is the start"
        )
    }

    // MARK: - S-9907 25 exercise moves while apart

    func testS9907TwentyFiveMovesWhileApartLeaveTheNewestOne() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        harness.session.sendError = RefusedByRadio()
        _ = await harness.engine.createSession(
            modality: nil,
            exercises: [exercise("sx-a"), exercise("sx-b"), exercise("sx-c")]
        )

        var handed = 0
        func handOverNew() async {
            let frames = Array(harness.emitted[handed...])
            handed = harness.emitted.count
            for frame in frames { await harness.bridge.send(frame) }
        }
        await handOverNew()

        let cycle = ["sx-b", "sx-c", "sx-a"]
        for i in 0..<25 {
            harness.clock.advance(1)
            _ = await harness.engine.selectExercise(slotId: cycle[i % 3])
            await handOverNew()
        }

        let lifecycles = harness.session.outstanding.filter {
            $0["type"] as? String == "session_lifecycle"
        }
        XCTAssertEqual(lifecycles.count, 1, "S-9907 exactly one lifecycle waits")
        let payload = lifecycles.first?["payload"] as? [String: Any]
        XCTAssertEqual(
            payload?["state"] as? String,
            "exercise_advanced",
            "S-9907 the newest move is the one that waits"
        )
        XCTAssertEqual(
            (payload?["exerciseIndex"] as? NSNumber)?.intValue,
            1,
            "S-9907 the 25th pick is sx-b, index 1"
        )
        XCTAssertEqual(
            harness.session.cancels.flatMap { $0 }.count,
            25,
            "S-9907 25 lifecycle cancels: the started one and 24 moves"
        )
        XCTAssertEqual(
            harness.session.outstanding.filter { $0["type"] as? String == "session_snapshot" }.count,
            1,
            "S-9907 the snapshot from the start remains"
        )
    }

    // MARK: - S-9908 the end always waits and withdraws the workout's live state

    private func s9908Seed(_ session: FakeWatchConnectivitySession) {
        session.seedOutstanding([
            lc("s-1", "started", "mS", 0),
            snap("s-1", "mP", 1),
            obs("s-1", "mO1"),
            lc("s-1", "exercise_advanced", "mA", 2),
            lc("s-2", "started", "mS2", 0),
            lc("s-3", "abandoned", "mX", 1),
        ])
    }

    func testS9908AAnEndWaitsAndWithdrawsTheWorkoutsLiveState() async throws {
        let (session, bridge, box) = apartBridge()
        s9908Seed(session)

        await bridge.send(lc("s-1", "completed", "mC", 3))

        XCTAssertEqual(
            session.cancels.map { $0.sorted() },
            [["mA", "mP", "mS"]],
            "S-9908A the end withdraws the workout's snapshot and non-terminal lifecycles"
        )
        XCTAssertEqual(
            ids(session.outstanding),
            ["mO1", "mS2", "mX", "mC"],
            "S-9908A the end itself waits; other sessions' frames and the entry stay"
        )
        XCTAssertTrue(box.failures.isEmpty)
    }

    func testS9908BTheSameEndTwiceIsOneCopy() async throws {
        let (session, bridge, _) = apartBridge()
        s9908Seed(session)
        let end = lc("s-1", "completed", "mC", 3)
        await bridge.send(end)
        let cancelsAfterA = session.cancels

        await bridge.send(end)

        XCTAssertEqual(
            session.cancels,
            cancelsAfterA,
            "S-9908B a replayed end withdraws nothing new"
        )
        XCTAssertEqual(
            ids(session.outstanding).filter { $0 == "mC" }.count,
            1,
            "S-9908B the end waits once"
        )
        XCTAssertEqual(
            session.queued.filter { ($0["messageId"] as? String) == "mC" }.count,
            1,
            "S-9908B the end is not queued again"
        )
    }

    func testS9908CAnotherSessionsEndIsNotWithdrawn() async throws {
        let (session, bridge, _) = apartBridge()
        s9908Seed(session)

        await bridge.send(lc("s-3", "started", "mY", 2))

        XCTAssertTrue(
            ids(session.outstanding).contains("mX"),
            "S-9908C a terminal lifecycle is not withdrawn by a later frame"
        )
        XCTAssertTrue(
            session.queued.contains { ($0["messageId"] as? String) == "mY" },
            "S-9908C the other session's lifecycle is queued"
        )
    }

    // MARK: - S-9910 entries are never withdrawn; timers and requests never wait

    func testS9910EntriesAreNeverWithdrawnAndTimersAndRequestsNeverWait() async throws {
        let (session, bridge, box) = apartBridge()
        session.seedOutstanding([obs("s-1", "mO1")])

        await bridge.send(obs("s-1", "mO2"))
        await bridge.send(snap("s-1", "mP", 1))
        await bridge.send(lc("s-1", "completed", "mC", 2))
        await bridge.send([
            "type": "timer_state",
            "messageId": "t1",
            "sessionId": "s-1",
            "sentAt": at(2),
            "payload": ["state": "running"],
        ])
        await bridge.requestSnapshot()

        let outstandingIds = ids(session.outstanding)
        for id in ["mO1", "mO2"] {
            XCTAssertTrue(outstandingIds.contains(id), "S-9910 \(id) waits")
            XCTAssertFalse(
                session.cancels.flatMap { $0 }.contains(id),
                "S-9910 \(id) is never withdrawn"
            )
        }
        XCTAssertEqual(box.failures.count, 2, "S-9910 the timer and the request are each reported once")
        XCTAssertFalse(
            session.queued.contains { ($0["messageId"] as? String) == "t1" },
            "S-9910 the timer is not queued"
        )
        XCTAssertEqual(
            session.queued.count,
            3,
            "S-9910 only the three durable frames were queued; a request carries no message to queue"
        )
        XCTAssertEqual(
            session.cancels,
            [["mP"]],
            "S-9910 only the snapshot is withdrawn, by the end"
        )
    }

    // MARK: - S-9911 a live send clears older waiting copies

    func testS9911AALiveSendClearsOlderCopies() async throws {
        let session = FakeWatchConnectivitySession()
        let box = FailureBox()
        let bridge = WatchConnectivityBridge(session: session, onFailure: { box.append($0) })
        session.seedOutstanding([
            snap("s-1", "mA", 1),
            lc("s-1", "started", "mS", 0),
            obs("s-1", "mO"),
        ])

        await bridge.send(snap("s-1", "mB", 2))

        XCTAssertEqual(
            session.sent.compactMap { $0["messageId"] as? String },
            ["mB"],
            "S-9911A the live send went out"
        )
        XCTAssertEqual(session.cancels, [["mA"]], "S-9911A the older waiting snapshot is withdrawn")
        XCTAssertTrue(session.queued.isEmpty, "S-9911A nothing is queued behind a live send")
    }

    func testS9911BAFinishedLiveSendWithdrawsTheStartedCopy() async throws {
        let session = FakeWatchConnectivitySession()
        let box = FailureBox()
        let bridge = WatchConnectivityBridge(session: session, onFailure: { box.append($0) })
        session.seedOutstanding([
            snap("s-1", "mA", 1),
            lc("s-1", "started", "mS", 0),
            obs("s-1", "mO"),
        ])
        await bridge.send(snap("s-1", "mB", 2))

        await bridge.send(lc("s-1", "completed", "mC", 3))

        XCTAssertEqual(
            session.cancels,
            [["mA"], ["mS"]],
            "S-9911B the finished end withdraws the started copy"
        )
        XCTAssertEqual(
            ids(session.outstanding),
            ["mO"],
            "S-9911B only the entry still waits"
        )
    }

    func testS9911CAStaleLiveSendLeavesTheNewerCopy() async throws {
        let session = FakeWatchConnectivitySession()
        let box = FailureBox()
        let bridge = WatchConnectivityBridge(session: session, onFailure: { box.append($0) })
        session.seedOutstanding([snap("s-1", "mN", 5)])

        await bridge.send(snap("s-1", "mOld", 4))

        XCTAssertEqual(
            session.sent.compactMap { $0["messageId"] as? String },
            ["mOld"],
            "S-9911C the stale live send still goes out"
        )
        XCTAssertTrue(session.cancels.isEmpty, "S-9911C a stale live send withdraws nothing")
        XCTAssertEqual(ids(session.outstanding), ["mN"], "S-9911C the newer copy stays")
    }

    // MARK: - S-9912 waiting is not delivered

    func testS9912WaitingIsNotDelivered() async throws {
        let harness = WatchBridgeHarness()
        await harness.launch()
        harness.session.sendError = RefusedByRadio()
        _ = await harness.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        try await harness.engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))
        harness.clock.advance(90)
        try await harness.engine.appendObservation(setEvent(harness.clock, entryId: "e-2"))

        await harness.orchestrator.sync()

        XCTAssertEqual(
            harness.engine.unconfirmedObservations.count,
            2,
            "S-9912 two sets are still unconfirmed after an apart sync"
        )
        XCTAssertEqual(
            deriveSyncNotice(
                pending: harness.engine.unconfirmedObservations,
                reachability: .unreachable,
                now: harness.clock.now
            ),
            "2 entries waiting for your phone",
            "S-9912 the notice counts the waiting entries"
        )
        let contents = await harness.store.readAll()
        XCTAssertTrue(
            contents.confirmations.isEmpty,
            "S-9912 an apart sync stores no confirmation row"
        )
    }

    // MARK: - S-9913 failures

    func testS9913AAQueueRefusalAfterTheWithdraw() async throws {
        let (session, bridge, box) = apartBridge()
        session.queueError = RefusedByQueue()
        session.seedOutstanding([snap("s-1", "mA", 1)])

        await bridge.send(snap("s-1", "mB", 2))

        XCTAssertEqual(session.cancels, [["mA"]], "S-9913A the withdraw happened before the refusal")
        XCTAssertFalse(
            ids(session.outstanding).contains("mB"),
            "S-9913A the refused frame is not outstanding"
        )
        XCTAssertEqual(box.failures.count, 1, "S-9913A one refusal, one report")
        XCTAssertTrue(
            box.failures.first is RefusedByQueue,
            "S-9913A the queue's refusal is what is reported"
        )
    }

    func testS9913BNotActivatedListsNothing() async throws {
        let (session, bridge, box) = apartBridge()
        session.seedOutstanding([snap("s-1", "mA", 1)])
        session.notActivated = true

        await bridge.send(snap("s-1", "mB", 2))

        XCTAssertTrue(session.cancels.isEmpty, "S-9913B a session that cannot list cancels nothing")
        XCTAssertEqual(box.failures.count, 1, "S-9913B the refusal is reported")
        XCTAssertFalse(
            ids(session.outstanding).contains("mB"),
            "S-9913B the refused frame is not outstanding"
        )
    }

    // MARK: - S-9914 two hand-overs at once leave one copy

    func testS9914TwoHandOversAtOnceLeaveOneCopy() async throws {
        let (session, bridge, _) = apartBridge()
        let gate = RaceGate()
        session.onListEntered = { gate.pass() }

        async let a: Void = bridge.send(snap("s-1", "m1", 1))
        async let b: Void = bridge.send(snap("s-1", "m2", 2))
        _ = await (a, b)

        let snapshots = session.outstanding.filter {
            $0["type"] as? String == "session_snapshot" && $0["sessionId"] as? String == "s-1"
        }
        XCTAssertEqual(snapshots.count, 1, "S-9914 exactly one copy waits")
        XCTAssertEqual(
            snapshots.first?["messageId"] as? String,
            "m2",
            "S-9914 the newer hand-over is the one that waits"
        )
    }

    // MARK: - S-9916 copies left by an earlier run are matched

    func testS9916CopiesLeftByAnEarlierRunAreMatched() async throws {
        let store = InMemoryWatchSessionStore()
        let first = WatchBridgeHarness(store: store, sessionId: "s-watch-1")
        await first.launch()
        _ = await first.engine.createSession(modality: nil, exercises: [exercise("sx-bench")])

        let harness = WatchBridgeHarness(store: store, sessionId: "s-watch-1")
        harness.session.seedOutstanding([snap("s-watch-1", "mOld", 0)])
        harness.session.sendError = RefusedByRadio()
        await harness.launch()
        harness.clock.advance(30)
        await harness.orchestrator.sync()

        XCTAssertTrue(
            harness.session.cancels.flatMap { $0 }.contains("mOld"),
            "S-9916 the copy left by the earlier run is withdrawn"
        )
        let snapshots = harness.session.outstanding.filter {
            $0["type"] as? String == "session_snapshot"
        }
        XCTAssertEqual(snapshots.count, 1, "S-9916 exactly one snapshot waits")
        XCTAssertEqual(
            snapshots.first?["sentAt"] as? String,
            utcIso(testInstant().addingTimeInterval(30)),
            "S-9916 the fresh snapshot carries the new stamp"
        )
    }
}
