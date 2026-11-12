//
//  WatchEndedIsFinalTests.swift
//  WatchSessionEngineTests
//
//  Plan 146, PR 2: "a finished workout is final", proved against the Swift
//  engine. The Dart twin in `lib/watch/session/watch_session_engine.dart`
//  landed the same rules in PR 1; every test here names the scenario it
//  replays, and the shared reconciliation fixtures are walked by
//  `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`.
//
//  D-14601: an ended session stays ended, and the first ending is final.
//  D-14602: the wrist's own Finish or Discard on an ended session changes
//  nothing. D-14603/D-14604: an end stops every timer and a late frame cannot
//  restart one. D-14605/D-14606: a late snapshot of another, ended session
//  merges its entries and nothing else, under the entry id.
//

import XCTest

@testable import WatchSessionEngine

final class WatchEndedIsFinalTests: XCTestCase {

    // MARK: - Frames

    private func setEntry(
        _ entryId: String,
        at date: Date,
        slot: String = "sx-bench",
        eventId: String? = nil
    ) -> [String: Any] {
        [
            "entryId": entryId,
            "eventId": eventId ?? entryId,
            "kind": "set",
            "loggedAt": utcIso(date),
            "sessionExerciseId": slot,
            "exerciseId": "ex-\(slot)",
            "reps": 5,
            "loadKg": 80,
        ]
    }

    private func ending(
        _ sessionId: String,
        messageId: String,
        state: String,
        at: Date,
        sentAt: Date? = nil
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "session_lifecycle",
            "origin": "phone",
            "sentAt": utcIso(sentAt ?? at),
            "payload": ["state": state, "at": utcIso(at)],
        ]
    }

    private func snapshot(
        _ sessionId: String,
        messageId: String,
        sentAt: Date,
        status: String,
        exercises: [[String: Any]],
        index: Int = 0,
        revision: Int = 1,
        entries: [[String: Any]] = [],
        timers: [String: Any] = [:]
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
                "revision": revision,
                "status": status,
                "currentExerciseIndex": index,
                "exercises": exercises,
                "entries": entries,
                "timers": timers,
            ] as [String: Any],
        ]
    }

    private func phoneTimers(
        _ sessionId: String,
        messageId: String,
        sentAt: Date,
        timers: [String: Any]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "timer_state",
            "origin": "phone",
            "sentAt": utcIso(sentAt),
            "payload": ["timers": timers],
        ]
    }

    // MARK: - Helpers

    private func sessionRows(_ harness: Harness) async -> [WatchSessionRecord] {
        await harness.store.readAll().sessions
    }

    private func sessionEnds(_ engine: WatchSessionEngine) -> [WatchObservationRecord] {
        engine.observations.filter { $0.kind == WatchObservationKind.sessionEnd }
    }

    /// Every observation the store holds, whatever session it belongs to —
    /// `engine.observations` shows only the current session's, and a late
    /// snapshot's entries are stored under the session it named.
    private func storeRows(_ harness: Harness) async -> [WatchObservationRecord] {
        await harness.store.readAll().observations
    }

    private func heldRows(_ engine: WatchSessionEngine, entryId: String) -> [WatchObservationRecord] {
        engine.observations.filter {
            $0.recordId == entryId || $0.payload["entryId"] as? String == entryId
        }
    }

    private func storedRows(_ harness: Harness, entryId: String) async -> [WatchObservationRecord] {
        await storeRows(harness).filter {
            $0.recordId == entryId || $0.payload["entryId"] as? String == entryId
        }
    }

    private func settledSession(_ harness: Harness) async -> (WatchSessionEngine, Date) {
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        return (engine, harness.clock.now)
    }

    // MARK: - D-14602: the wrist cannot end what has already ended

    func testS14605AnAbandonedSessionIsNeverReportedCompleted() async throws {
        let harness = Harness()
        let (engine, _) = await settledSession(harness)

        _ = await engine.abandonSession()
        let rowsAfterDiscard = await sessionRows(harness).count
        let end = try XCTUnwrap(sessionEnds(engine).first)
        let endedAt = try XCTUnwrap(end.payload["endedAt"] as? String)
        harness.clock.advance(120)

        let returned = await engine.finishSession()

        XCTAssertEqual(
            returned.status,
            WatchSessionStatus.abandoned,
            "an auto-finish cannot upgrade a discard (S-14605)"
        )
        XCTAssertEqual(returned.recordId, engine.session?.recordId, "the ending row comes back")
        let rowsAfterFinish = await sessionRows(harness).count
        XCTAssertEqual(
            rowsAfterFinish,
            rowsAfterDiscard,
            "no row is appended for a session that already ended"
        )
        XCTAssertEqual(sessionEnds(engine).count, 1, "one session end, ever")
        XCTAssertEqual(
            sessionEnds(engine).first?.payload["endedAt"] as? String,
            endedAt,
            "the end keeps the instant it happened"
        )
    }

    // MARK: - D-14601: an ended session stays ended

    func testS14601AStaleStartedCannotReopenAFinishedWorkout() async throws {
        let harness = Harness()
        let (engine, t0) = await settledSession(harness)
        _ = await engine.finishSession()
        let rowsBefore = await sessionRows(harness).count

        let applied = try await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-stale-started", state: WatchLifecycleState.started, at: t0.addingTimeInterval(60))
        )

        XCTAssertFalse(applied, "a stale start for an ended session is refused whole")
        XCTAssertEqual(
            engine.session?.status,
            WatchSessionStatus.completed,
            "active never beats terminal, whatever the order"
        )
        let staleRows = await sessionRows(harness).count
        XCTAssertEqual(staleRows, rowsBefore, "no row, no end")
        XCTAssertEqual(sessionEnds(engine).count, 1, "the end stands")
    }

    func testS14601AnEarlierEndingReplacesTheHeldOneAndALaterOneLoses() async throws {
        let harness = Harness()
        let (engine, t0) = await settledSession(harness)

        let later = t0.addingTimeInterval(60)
        let firstEnding = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-late-end", state: WatchLifecycleState.completed, at: later)
        )) ?? false
        XCTAssertTrue(firstEnding, "the first ending the phone reports applies")
        XCTAssertEqual(engine.session?.recordedAt, later, "the row records the instant it claims")

        let earlier = t0.addingTimeInterval(30)
        let earlierEnding = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-early-end", state: WatchLifecycleState.completed, at: earlier)
        )) ?? false
        XCTAssertTrue(earlierEnding, "an earlier ending is the moment the workout actually finished")
        XCTAssertEqual(engine.session?.recordedAt, earlier)
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed)

        harness.clock.advance(200)
        let laterEnding = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-later-end", state: WatchLifecycleState.completed, at: t0.addingTimeInterval(90))
        )) ?? true
        XCTAssertFalse(laterEnding, "a later ending loses to the held one")
        XCTAssertEqual(engine.session?.recordedAt, earlier, "the earlier ending stands")
        XCTAssertEqual(sessionEnds(engine).count, 1, "a session has one end, whatever ends it")
    }

    func testS14601ACompletionOutranksADiscardWhateverTheInstantsSay() async throws {
        let harness = Harness()
        let (engine, t0) = await settledSession(harness)

        let discarded = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-discard", state: WatchLifecycleState.abandoned, at: t0.addingTimeInterval(60))
        )) ?? false
        XCTAssertTrue(discarded)
        let finished = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-finish", state: WatchLifecycleState.completed, at: t0.addingTimeInterval(61))
        )) ?? false
        XCTAssertTrue(finished, "a completion outranks a held discard: a finished workout is never deleted")
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed)

        let other = Harness()
        let (otherEngine, otherT0) = await settledSession(other)
        let otherFinished = (try? await otherEngine.applyMessage(
            ending("s-watch-1", messageId: "msg-finish", state: WatchLifecycleState.completed, at: otherT0.addingTimeInterval(60))
        )) ?? false
        XCTAssertTrue(otherFinished)
        let otherDiscarded = (try? await otherEngine.applyMessage(
            ending("s-watch-1", messageId: "msg-discard", state: WatchLifecycleState.abandoned, at: otherT0.addingTimeInterval(61))
        )) ?? true
        XCTAssertFalse(otherDiscarded, "a discard cannot delete a completion, however much later it lands")
        XCTAssertEqual(otherEngine.session?.status, WatchSessionStatus.completed)
    }

    func testS14601ATiedEndingResolvesOnTheSmallerMessageId() async throws {
        let harness = Harness()
        let (engine, t0) = await settledSession(harness)
        let instant = t0.addingTimeInterval(60)
        let rowsBefore = await sessionRows(harness).count

        let heldZ = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-z", state: WatchLifecycleState.completed, at: instant)
        )) ?? false
        XCTAssertTrue(heldZ)
        let tiedA = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-a", state: WatchLifecycleState.completed, at: instant)
        )) ?? false
        XCTAssertTrue(tiedA, "the tie-break applies the smaller message id, so both sides keep the same ending")
        let afterBoth = await sessionRows(harness).count
        XCTAssertEqual(
            afterBoth,
            rowsBefore + 2,
            "both endings were written"
        )

        let repeated = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-a", state: WatchLifecycleState.completed, at: instant)
        )) ?? false
        XCTAssertTrue(repeated, "the same end delivered again is applied, not refused")
        let afterRepeat = await sessionRows(harness).count
        XCTAssertEqual(
            afterRepeat,
            rowsBefore + 2,
            "a repeat writes nothing"
        )
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed)

        // The replaced ending is now the held one, so the next tied frame is
        // compared against `msg-a` and loses: the pair converges on one ending
        // whichever order the two arrived in.
        XCTAssertEqual(engine.session?.recordId, "life-msg-a")
        _ = try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-m", state: WatchLifecycleState.completed, at: instant)
        )
        XCTAssertEqual(
            engine.session?.recordId,
            "life-msg-a",
            "a tied ending that loses the message-id order replaces nothing"
        )
        let afterLosingTie = await sessionRows(harness).count
        XCTAssertEqual(afterLosingTie, rowsBefore + 2, "and writes no row")
    }

    // MARK: - D-14603 / D-14604: an end stops every timer, and a late frame cannot start one

    func testS14603AnEndStopsEveryTimerOfTheSession() async throws {
        let harness = Harness()
        let (engine, t0) = await settledSession(harness)
        _ = try await engine.startTimer(WatchTimerKind.round, sessionExerciseId: "sx-bench")
        _ = try await engine.startTimer(WatchTimerKind.rest)
        harness.clearEmitted()

        let endedAt = t0.addingTimeInterval(60)
        let ended = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-end", state: WatchLifecycleState.abandoned, at: endedAt)
        )) ?? false
        XCTAssertTrue(ended)

        XCTAssertEqual(engine.timerFor(WatchTimerKind.round)?.state, WatchTimerState.stopped)
        XCTAssertEqual(engine.timerFor(WatchTimerKind.rest)?.state, WatchTimerState.stopped)
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.round)?.recordId,
            "tms-msg-end-round",
            "the stop is written under the id of the message that named it"
        )
        XCTAssertEqual(engine.timerFor(WatchTimerKind.rest)?.recordId, "tms-msg-end-rest")

        let timerRows = engine.timerRows(WatchTimerKind.round).count
            + engine.timerRows(WatchTimerKind.rest).count
        let redelivered = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-end", state: WatchLifecycleState.abandoned, at: endedAt)
        )) ?? false
        XCTAssertTrue(redelivered, "a redelivered end is applied, not refused")
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.round).count + engine.timerRows(WatchTimerKind.rest).count,
            timerRows,
            "a redelivered end stops nothing a second time"
        )

        harness.clearEmitted()
        let rowsBeforeStart = engine.timerRows(WatchTimerKind.round).count
            + engine.timerRows(WatchTimerKind.rest).count
        let started = try await engine.startTimer(WatchTimerKind.round, sessionExerciseId: "sx-bench")
        XCTAssertEqual(
            started.recordId,
            "tms-msg-end-round",
            "the answer is the stop the end wrote, never a new timer"
        )
        XCTAssertNotNil(started.stoppedAt, "and it is stopped")
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.round).count + engine.timerRows(WatchTimerKind.rest).count,
            rowsBeforeStart,
            "the timer store is untouched"
        )
        XCTAssertTrue(harness.emitted.isEmpty, "no timer_state for a workout that is over")

        let rowsBefore = rowsBeforeStart
        let restarted = (try? await engine.applyMessage(
            phoneTimers(
                "s-watch-1",
                messageId: "msg-phone-round",
                sentAt: endedAt.addingTimeInterval(30),
                timers: [
                    WatchTimerKind.round: [
                        "kind": WatchTimerKind.round,
                        "state": "running",
                        "startedAt": utcIso(endedAt.addingTimeInterval(30)),
                        "accumulatedPauseMs": 0,
                    ] as [String: Any],
                ]
            )
        )) ?? true
        XCTAssertFalse(restarted, "a running timer a phone still reports cannot restart one")
        XCTAssertEqual(engine.timerFor(WatchTimerKind.round)?.state, WatchTimerState.stopped)
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.round).count + engine.timerRows(WatchTimerKind.rest).count,
            rowsBefore,
            "the late timer_state changed nothing"
        )
    }

    // MARK: - D-14605 / D-14606: a late snapshot merges only its entries

    func testS14607ALateSnapshotMergesOnlyItsEntries() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let t0 = harness.clock.now
        let foreign = "s-other"

        let followed = (try? await engine.applyMessage(
            snapshot(
                foreign,
                messageId: "msg-foreign-end",
                sentAt: t0,
                status: WatchSessionStatus.completed,
                exercises: [exercise("sx-bench")],
                entries: [setEntry("e-a1", at: t0.addingTimeInterval(-60))]
            )
        )) ?? false
        XCTAssertTrue(followed, "the phone's finished workout is followed")
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let held = try XCTUnwrap(engine.session)
        XCTAssertEqual(held.sessionId, "s-watch-1")

        let late = t0.addingTimeInterval(180)
        let merged = (try? await engine.applyMessage(
            snapshot(
                foreign,
                messageId: "msg-foreign-late",
                sentAt: late,
                status: WatchSessionStatus.active,
                exercises: [exercise("sx-bench"), exercise("sx-squat")],
                index: 1,
                revision: 9,
                entries: [setEntry("e-a2", at: late.addingTimeInterval(-30))]
            )
        )) ?? false
        XCTAssertTrue(merged)

        XCTAssertEqual(engine.session?.sessionId, "s-watch-1", "the wrist stays on its own workout")
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.active)
        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-bench"],
            "no structure is taken from a snapshot of another, ended session"
        )
        XCTAssertEqual(engine.session?.currentExerciseIndex, held.currentExerciseIndex)
        XCTAssertEqual(engine.session?.revision, held.revision)
        let lateRows = await storedRows(harness, entryId: "e-a2")
        XCTAssertEqual(lateRows.count, 1, "the entries are the news it carries")
        XCTAssertTrue(
            engine.unconfirmedObservations.contains { $0.entryId == "e-a2" },
            "a late snapshot is no receipt: nothing is confirmed"
        )
        let ends = await storeRows(harness)
        XCTAssertEqual(
            ends.filter {
                $0.kind == WatchObservationKind.sessionEnd
                    && $0.sessionId == "s-watch-1"
            }.count,
            0,
            "the wrist's own workout was not ended by it"
        )

        _ = try await engine.applyMessage(
            snapshot(
                foreign,
                messageId: "msg-foreign-late",
                sentAt: late,
                status: WatchSessionStatus.active,
                exercises: [exercise("sx-bench"), exercise("sx-squat")],
                index: 1,
                revision: 9,
                entries: [setEntry("e-a2", at: late.addingTimeInterval(-30))]
            )
        )
        let rowsAfterMerge = await storedRows(harness, entryId: "e-a2")
        XCTAssertEqual(
            rowsAfterMerge.count,
            1,
            "union by entry id: a re-stated set is not doubled"
        )
    }

    func testS14606AnEntryTheWristLoggedUnderItsEventIdIsTheOneTheSnapshotNames() async throws {
        let harness = Harness()
        let (engine, t0) = await settledSession(harness)
        var event = setEntry("e-1", at: t0)
        event["eventId"] = "evt-9"
        _ = try await engine.appendObservation(event)
        XCTAssertEqual(heldRows(engine, entryId: "e-1").count, 1, "the fixture holds one row")
        XCTAssertEqual(engine.observations.last?.recordId, "evt-9", "written under its event id")

        _ = try await engine.applyMessage(
            snapshot(
                "s-watch-1",
                messageId: "msg-own-snapshot",
                sentAt: t0.addingTimeInterval(60),
                status: WatchSessionStatus.active,
                exercises: [exercise("sx-bench")],
                entries: [setEntry("e-1", at: t0)]
            )
        )

        XCTAssertEqual(
            heldRows(engine, entryId: "e-1").count,
            1,
            "the entry id is the identity, whatever id the row was written with (D-14606)"
        )
    }

    // MARK: - F-7: a burst of copies of one entry stores it once

    func testS14606ABurstOfCopiesOfOneEntryStoresItOnce() async throws {
        let harness = Harness()
        let store = GatedObservationStore()
        let engine = WatchSessionEngine(
            store: store,
            onEmit: { _ in },
            validator: Harness.validator(),
            clock: harness.clock.call,
            idFactory: { "rec-gated" },
            sessionIdFactory: { "s-watch-1" }
        )
        await engine.restore()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let t0 = harness.clock.now

        async let logged = engine.appendObservation(setEntry("e-race", at: t0))
        await waitUntilParked(store)
        let racing = Task {
            _ = try? await engine.applyMessage(
                snapshot(
                    "s-watch-1",
                    messageId: "msg-race",
                    sentAt: t0.addingTimeInterval(1),
                    status: WatchSessionStatus.active,
                    exercises: [exercise("sx-bench")],
                    entries: [setEntry("e-race", at: t0)]
                )
            )
        }
        // Bounded yields, no clock: let the second copy run as far as it can
        // while the first copy's append is still in flight.
        for _ in 0 ..< 200 {
            if store.appendCalls >= 2 { break }
            await Task.yield()
        }
        let callsWhileParked = store.appendCalls
        await store.gate.open()
        _ = try await logged
        await racing.value

        XCTAssertEqual(
            callsWhileParked,
            1,
            "the second copy waits for the first copy's row instead of appending again"
        )
        XCTAssertEqual(
            heldRows(engine, entryId: "e-race").count,
            1,
            "two copies in flight are one entry, stored once"
        )
    }

    private func waitUntilParked(_ store: GatedObservationStore) async {
        for _ in 0 ..< 10_000 {
            if await store.gate.isParked { return }
            await Task.yield()
        }
        XCTFail("the gated store never parked the first observation append")
    }

    // MARK: - D-14601: the snapshot half

    func testS14601AnActiveSnapshotKeepsTheHeldEndingButTakesItsStructure() async throws {
        let harness = Harness()
        let (engine, t0) = await settledSession(harness)
        let ended = (try? await engine.applyMessage(
            ending("s-watch-1", messageId: "msg-end", state: WatchLifecycleState.abandoned, at: t0.addingTimeInterval(60))
        )) ?? false
        XCTAssertTrue(ended)

        let applied = (try? await engine.applyMessage(
            snapshot(
                "s-watch-1",
                messageId: "msg-active-snap",
                sentAt: t0.addingTimeInterval(120),
                status: WatchSessionStatus.active,
                exercises: [exercise("sx-bench"), exercise("sx-squat")],
                index: 1,
                revision: 4
            )
        )) ?? false
        XCTAssertTrue(applied)

        XCTAssertEqual(engine.session?.status, WatchSessionStatus.abandoned, "the end stands")
        XCTAssertEqual(
            engine.session?.recordedAt,
            t0.addingTimeInterval(60),
            "the ending keeps its own instant"
        )
        XCTAssertEqual(engine.session?.revision, 4, "the snapshot's structure is taken")
        XCTAssertEqual(engine.session?.currentExerciseIndex, 1)
        XCTAssertEqual(
            engine.session?.exercises.compactMap { $0["sessionExerciseId"] as? String },
            ["sx-bench", "sx-squat"]
        )
        XCTAssertEqual(sessionEnds(engine).count, 1, "and no second end is written")
    }

    func testS14601ALaterTerminalSnapshotDoesNotReplaceTheHeldEnding() async throws {
        let harness = Harness()
        let (engine, t0) = await settledSession(harness)
        let firstApplied = (try? await engine.applyMessage(
            snapshot(
                "s-watch-1",
                messageId: "msg-late-end",
                sentAt: t0.addingTimeInterval(60),
                status: WatchSessionStatus.completed,
                exercises: [exercise("sx-bench")]
            )
        )) ?? false
        XCTAssertTrue(firstApplied)
        XCTAssertEqual(engine.session?.recordedAt, t0.addingTimeInterval(60))

        let laterApplied = (try? await engine.applyMessage(
            snapshot(
                "s-watch-1",
                messageId: "msg-later-end",
                sentAt: t0.addingTimeInterval(90),
                status: WatchSessionStatus.abandoned,
                exercises: [exercise("sx-bench")]
            )
        )) ?? false
        XCTAssertTrue(laterApplied, "the frame is applied, its ending is not")
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed, "the finished workout stays finished")
        XCTAssertEqual(engine.session?.recordedAt, t0.addingTimeInterval(60), "and keeps its own instant")
        XCTAssertEqual(sessionEnds(engine).count, 1, "no second end is written")

        // Plan 63 D-1 still governs an out-of-order frame: a snapshot older than
        // the newest one applied changes nothing at all, so an earlier ending
        // reaches the wrist through the lifecycle path, not a stale snapshot.
        let earlierApplied = (try? await engine.applyMessage(
            snapshot(
                "s-watch-1",
                messageId: "msg-early-end",
                sentAt: t0.addingTimeInterval(30),
                status: WatchSessionStatus.abandoned,
                exercises: [exercise("sx-bench")]
            )
        )) ?? true
        XCTAssertFalse(earlierApplied, "a stale snapshot is refused whole")
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed)
        XCTAssertEqual(engine.session?.recordedAt, t0.addingTimeInterval(60))
    }
}

/// A store that parks the first observation append until the test opens the
/// gate, so two copies of one entry are provably in flight at the same time.
final class GatedObservationStore: WatchSessionStore {
    let base = InMemoryWatchSessionStore()
    let gate = ObservationGate()
    private(set) var appendCalls = 0

    func append(_ record: StoredWatchRecord) async -> StoredWatchRecord {
        if case .observation = record {
            appendCalls += 1
            if appendCalls == 1 { await gate.park() }
        }
        return await base.append(record)
    }

    func readAll() async -> WatchStoreContents { await base.readAll() }
    func pruneConfirmed() async -> [String] { await base.pruneConfirmed() }
    func pruneSensorSamples(_ sessionIds: [String]) async -> [String] {
        await base.pruneSensorSamples(sessionIds)
    }
    func pruneExerciseBatches(keepingVersion: String) async -> [String] {
        await base.pruneExerciseBatches(keepingVersion: keepingVersion)
    }
    func pruneBests(keepingRecordId: String) async -> [String] {
        await base.pruneBests(keepingRecordId: keepingRecordId)
    }
    func pruneWater(keepingRecordId: String) async -> [String] {
        await base.pruneWater(keepingRecordId: keepingRecordId)
    }
    func pruneWaterTaps(loggedBefore cutoff: Date) async -> [String] {
        await base.pruneWaterTaps(loggedBefore: cutoff)
    }
}

/// One gate: `park()` suspends until `open()`, and `isParked` lets the test
/// wait for the suspension without a wall-clock sleep.
actor ObservationGate {
    private(set) var isParked = false
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func park() async {
        isParked = true
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}