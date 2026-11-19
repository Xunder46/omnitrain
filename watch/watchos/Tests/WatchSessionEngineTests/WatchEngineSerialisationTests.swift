//
//  WatchEngineSerialisationTests.swift
//  WatchSessionEngineTests
//
//  S-6501 to S-6505 of
//  `docs/plans/2026-10-20-46c-engine-serialisation-plan/2026-10-20-46c-engine-serialisation-plan.md`
//  — the engine's five session-row writers run one at a time (D-2): a phone
//  message and the wrist's own change both land, each built from the row the
//  one before it wrote.
//
//  Every case pauses one writer inside its store append (`SuspendingStore`,
//  `WatchEffortRatingTests.swift`), lets the competing writer start, and then
//  releases the append. Bounded `Task.yield` polls only; no test reads a clock.
//

import XCTest

@testable import WatchSessionEngine

final class WatchEngineSerialisationTests: XCTestCase {

    private let sentAt = "2026-10-20T21:00:00Z"

    /// Bounded poll: never an unbounded wait on the store.
    private func spin(until condition: () -> Bool, limit: Int = 100_000) async -> Bool {
        var spins = 0
        while !condition() && spins < limit {
            await Task.yield()
            spins += 1
        }
        return condition()
    }

    /// An engine whose store can be armed, holding a wrist-started session of
    /// `slots` at index 0.
    private func fixture(
        slots: [String] = ["sx-a", "sx-b"]
    ) async -> (engine: WatchSessionEngine, store: SuspendingStore, sessionId: String) {
        let store = SuspendingStore()
        let engine = WatchSessionEngine(store: store)
        let started = await engine.createSession(
            modality: "resistance_lifting",
            exercises: slots.map(exercise)
        )
        return (engine, store, started.sessionId)
    }

    private func snapshot(
        sessionId: String,
        messageId: String,
        revision: Int,
        exercises: [[String: Any]],
        currentExerciseIndex: Int = 0
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
                "revision": revision,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": currentExerciseIndex,
                "exercises": exercises,
                "entries": [[String: Any]](),
                "timers": [String: Any](),
            ] as [String: Any],
        ]
    }

    private func structureChange(
        sessionId: String,
        messageId: String,
        changeId: String,
        adding slot: String,
        atIndex index: Int
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "structure_change",
            "origin": "phone",
            "sentAt": sentAt,
            "payload": [
                "changeId": changeId,
                "changes": [
                    ["kind": "add_exercise", "exercise": exercise(slot), "atIndex": index],
                ],
            ] as [String: Any],
        ]
    }

    private func advanceLifecycle(
        sessionId: String,
        messageId: String,
        index: Int
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "session_lifecycle",
            "origin": "phone",
            "sentAt": sentAt,
            "payload": [
                "state": WatchLifecycleState.exerciseAdvanced,
                "at": sentAt,
                "exerciseIndex": index,
            ] as [String: Any],
        ]
    }

    private func slotId(_ session: WatchSessionRecord?) -> String? {
        guard let session, session.currentExerciseIndex < session.exercises.count else { return nil }
        return session.exercises[session.currentExerciseIndex]["sessionExerciseId"] as? String
    }

    // MARK: - S-6501 the phone's snapshot first

    func testS6501ASnapshotFirstAndAPickInFlightBothLand() async throws {
        let (engine, store, sessionId) = await fixture()
        let message = snapshot(
            sessionId: sessionId,
            messageId: "msg-p2-s6501-snapshot",
            revision: 41,
            exercises: [exercise("sx-a"), exercise("sx-b"), exercise("sx-c")]
        )

        store.arm()
        let snapshotTask = Task { try await engine.applyMessage(message) }
        let suspended = await spin(until: { store.suspended })
        guard suspended else {
            XCTFail("S-6501 the snapshot's commit never reached the store")
            return
        }

        let pick = Task { await engine.selectExercise(slotId: "sx-b") }
        _ = await spin(
            until: { (engine.session?.currentExerciseIndex ?? 0) != 0 },
            limit: 1_000
        )
        XCTAssertEqual(
            engine.session?.currentExerciseIndex,
            0,
            "S-6501 the pick waited for the snapshot: neither had landed yet"
        )

        store.resume()
        _ = try await snapshotTask.value
        _ = await pick.value

        let session = try XCTUnwrap(engine.session)
        XCTAssertEqual(session.exercises.count, 3, "S-6501 the phone's exercise landed")
        XCTAssertEqual(slotId(session), "sx-b", "S-6501 and the pick landed on the snapshot's ladder")
    }

    // MARK: - S-6502 the pick first

    func testS6502APickFirstAndASnapshotInFlightBothLand() async throws {
        let (engine, store, sessionId) = await fixture()
        let message = snapshot(
            sessionId: sessionId,
            messageId: "msg-p2-s6502-snapshot",
            revision: 42,
            exercises: [exercise("sx-a"), exercise("sx-b"), exercise("sx-c")]
        )

        store.arm()
        let pick = Task { await engine.selectExercise(slotId: "sx-b") }
        let suspended = await spin(until: { store.suspended })
        guard suspended else {
            XCTFail("S-6502 the pick's commit never reached the store")
            return
        }

        let snapshotTask = Task { try await engine.applyMessage(message) }
        _ = await spin(
            until: { (engine.session?.exercises.count ?? 0) == 3 },
            limit: 1_000
        )

        store.resume()
        _ = await pick.value
        _ = try await snapshotTask.value

        let session = try XCTUnwrap(engine.session)
        XCTAssertEqual(
            session.exercises.count,
            3,
            "S-6502 the snapshot applied after the pick, from the pick's row"
        )
        XCTAssertEqual(session.currentExerciseIndex, 0, "S-6502 the snapshot's own position")
    }

    // MARK: - S-6503 a structure change first

    func testS6503AStructureChangeFirstAndAPickInFlightBothLand() async throws {
        let (engine, store, sessionId) = await fixture()
        let message = structureChange(
            sessionId: sessionId,
            messageId: "msg-p2-s6503-add",
            changeId: "chg-p2-s6503-add",
            adding: "sx-c",
            atIndex: 2
        )

        store.arm()
        let changeTask = Task { try await engine.applyMessage(message) }
        let suspended = await spin(until: { store.suspended })
        guard suspended else {
            XCTFail("S-6503 the structure change's commit never reached the store")
            return
        }

        let pick = Task { await engine.selectExercise(slotId: "sx-b") }
        _ = await spin(
            until: { (engine.session?.currentExerciseIndex ?? 0) != 0 },
            limit: 1_000
        )
        XCTAssertEqual(
            engine.session?.currentExerciseIndex,
            0,
            "S-6503 the pick waited for the structure change"
        )

        store.resume()
        _ = try await changeTask.value
        _ = await pick.value

        let session = try XCTUnwrap(engine.session)
        XCTAssertEqual(session.exercises.count, 3, "S-6503 the structure change landed")
        XCTAssertEqual(slotId(session), "sx-b", "S-6503 and the pick landed on its ladder")
    }

    // MARK: - S-6503 the pick first

    func testS6503APickFirstAndAStructureChangeInFlightBothLand() async throws {
        let (engine, store, sessionId) = await fixture()
        let message = structureChange(
            sessionId: sessionId,
            messageId: "msg-p2-s6503-add-after",
            changeId: "chg-p2-s6503-add-after",
            adding: "sx-c",
            atIndex: 2
        )

        store.arm()
        let pick = Task { await engine.selectExercise(slotId: "sx-b") }
        let suspended = await spin(until: { store.suspended })
        guard suspended else {
            XCTFail("S-6503 the pick's commit never reached the store")
            return
        }

        let changeTask = Task { try await engine.applyMessage(message) }
        _ = await spin(
            until: { (engine.session?.exercises.count ?? 0) == 3 },
            limit: 1_000
        )

        store.resume()
        _ = await pick.value
        _ = try await changeTask.value

        let session = try XCTUnwrap(engine.session)
        XCTAssertEqual(
            session.exercises.count,
            3,
            "S-6503 the structure change applied after the pick, from the pick's row"
        )
        XCTAssertEqual(slotId(session), "sx-b", "S-6503 the pick's position survived the addition")
    }

    // MARK: - S-6504 the lifecycle first

    func testS6504ALifecycleFirstLosesToThePickThatArrivesSecond() async throws {
        let (engine, store, sessionId) = await fixture(slots: ["sx-a", "sx-b", "sx-c"])
        let message = advanceLifecycle(
            sessionId: sessionId,
            messageId: "msg-p2-s6504-advance",
            index: 2
        )

        store.arm()
        let lifecycleTask = Task { try await engine.applyMessage(message) }
        let suspended = await spin(until: { store.suspended })
        guard suspended else {
            XCTFail("S-6504 the lifecycle's commit never reached the store")
            return
        }

        let pick = Task { await engine.selectExercise(slotId: "sx-b") }
        _ = await spin(
            until: { (engine.session?.currentExerciseIndex ?? 0) != 0 },
            limit: 1_000
        )

        store.resume()
        _ = try await lifecycleTask.value
        _ = await pick.value

        let session = try XCTUnwrap(engine.session)
        XCTAssertEqual(
            session.currentExerciseIndex,
            1,
            "S-6504 the pick was applied last, so it decides the position"
        )
        XCTAssertEqual(slotId(session), "sx-b", "S-6504 the pick's exercise")
    }

    // MARK: - S-6504 the pick first

    func testS6504APickFirstLosesToTheLifecycleThatArrivesSecond() async throws {
        let (engine, store, sessionId) = await fixture(slots: ["sx-a", "sx-b", "sx-c"])
        let message = advanceLifecycle(
            sessionId: sessionId,
            messageId: "msg-p2-s6504-advance-after",
            index: 2
        )

        store.arm()
        let pick = Task { await engine.selectExercise(slotId: "sx-b") }
        let suspended = await spin(until: { store.suspended })
        guard suspended else {
            XCTFail("S-6504 the pick's commit never reached the store")
            return
        }

        let lifecycleTask = Task { try await engine.applyMessage(message) }
        _ = await spin(
            until: { (engine.session?.currentExerciseIndex ?? 0) == 2 },
            limit: 1_000
        )

        store.resume()
        _ = await pick.value
        _ = try await lifecycleTask.value

        let session = try XCTUnwrap(engine.session)
        XCTAssertEqual(
            session.currentExerciseIndex,
            2,
            "S-6504 the lifecycle was applied last, so it decides the position"
        )
        XCTAssertEqual(slotId(session), "sx-c", "S-6504 the lifecycle's exercise")
    }

    // MARK: - S-6505 two starts at once

    func testS6505TwoStartsAtOnceProduceOneSession() async throws {
        let store = SuspendingStore()
        let engine = WatchSessionEngine(store: store)

        store.arm()
        let first = Task { await engine.createSession(modality: "sports") }
        let suspended = await spin(until: { store.suspended })
        guard suspended else {
            XCTFail("S-6505 the first start's commit never reached the store")
            return
        }

        let second = Task { await engine.createSession(modality: "sports") }
        _ = await spin(until: { engine.session != nil }, limit: 1_000)

        store.resume()
        let firstSession = await first.value
        let secondSession = await second.value

        XCTAssertEqual(
            firstSession.sessionId,
            secondSession.sessionId,
            "S-6505 the second start found the first one"
        )
        XCTAssertEqual(
            engine.session?.sessionId,
            firstSession.sessionId,
            "S-6505 the held session is the first start's"
        )
        let rows = await store.readAll().sessions
        XCTAssertEqual(rows.count, 1, "S-6505 exactly one session row exists")
    }
}
