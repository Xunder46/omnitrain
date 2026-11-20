//
//  WatchTimerReadoptionTests.swift
//  WatchSessionEngineTests
//
//  Plan 202 — a phone frame never restarts a timer interval the wrist already
//  ran:
//  `docs/plans/2026-11-15-202-watch-timer-readoption-plan/2026-11-15-202-watch-timer-readoption-plan.md`.
//
//  The fixture and the frame-building helpers are the S-6005 ones from
//  `WatchLoggingTimersTests.swift` (a session with a hold slot, a phone
//  `timer_state` envelope, `engine.timerFor(WatchTimerKind.hold)`), copied here
//  so the plan's own scenarios stand alone. Every incoming frame carries a
//  DIFFERENT message id — the new row id is what made the bug.
//

import XCTest

@testable import WatchSessionEngine

final class WatchTimerReadoptionTests: XCTestCase {

    private func slot(
        _ id: String,
        capabilities: [String]
    ) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
    }

    private func phoneFrame(
        _ type: String,
        sessionId: String,
        messageId: String,
        payload: [String: Any]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": type,
            "origin": "phone",
            "sentAt": "2026-07-13T06:00:00Z",
            "payload": payload,
        ]
    }

    /// A timer object the phone names in a `timer_state`, with the slot when
    /// the case has one and an ending when it is a stopped row. `pausedAt` and
    /// `accumulatedPauseMs` carry a pause or a resume; the defaults keep every
    /// call that names neither unchanged.
    private func phoneTimer(
        _ kind: String,
        startedAt: String,
        sessionExerciseId: String? = nil,
        stoppedAt: String? = nil,
        pausedAt: String? = nil,
        accumulatedPauseMs: Int = 0
    ) -> [String: Any] {
        var timer: [String: Any] = [
            "kind": kind,
            "state": stoppedAt == nil
                ? (pausedAt == nil ? WatchTimerState.running : WatchTimerState.paused)
                : WatchTimerState.stopped,
            "startedAt": startedAt,
            "accumulatedPauseMs": accumulatedPauseMs,
        ]
        if let stoppedAt { timer["stoppedAt"] = stoppedAt }
        if let pausedAt { timer["pausedAt"] = pausedAt }
        if let sessionExerciseId { timer["sessionExerciseId"] = sessionExerciseId }
        return timer
    }

    /// A phone `session_snapshot` frame — the S-9311 builder in
    /// `WatchStaleSnapshotTests.swift`, with the `timers` map the timer cases
    /// need. `sentAt` must be later than any snapshot applied before it.
    private func phoneSnapshot(
        sessionId: String,
        messageId: String,
        sentAt: String,
        exercises: [[String: Any]],
        timers: [String: Any] = [String: Any]()
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
                "entries": [[String: Any]](),
                "timers": timers,
            ],
        ]
    }

    /// S-20201: the phone names a hold running at T (m1); the wrist adopts it
    /// and stops it 20 s in; a second `timer_state` (m2, a different message id)
    /// still names the same hold running at T. The wrist's stopped copy wins:
    /// nothing is stored, nothing reopens (D-20202, D-20204).
    func testS20201AStoppedHoldIsNotRestartedByALaterFrameNamingTheSameInterval() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(37)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20201-a", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )
        _ = await engine.stopTimer(kind: WatchTimerKind.hold, at: startedAt.addingTimeInterval(20))
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.stopped,
            "the wrist's own stop ended the hold"
        )
        let holdRows = engine.timerRows(WatchTimerKind.hold).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20201-b", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.stopped,
            "a frame naming an interval the wrist already ran is ignored (D-20202)"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.hold).count,
            holdRows,
            "the stale frame stores no hold row (D-20204)"
        )
    }

    /// S-20203: continuing S-20201's fixture, a `timer_state` names the hold
    /// running at T+60 s — a genuinely new interval for the same slot — and it
    /// is adopted as today: a new running row with its own start.
    func testS20203ARealSecondIntervalAfterAStopIsAdopted() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(37)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20203-a", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )
        _ = await engine.stopTimer(kind: WatchTimerKind.hold, at: startedAt.addingTimeInterval(20))
        let holdRows = engine.timerRows(WatchTimerKind.hold).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20203-b", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt.addingTimeInterval(60)),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.running,
            "a genuinely new interval is adopted"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.startedAt,
            startedAt.addingTimeInterval(60),
            "the new interval's own start is the one kept (D-20201)"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.hold).count,
            holdRows + 1,
            "the new interval is a row of its own"
        )
    }

    /// S-20202: S-20201's stale frame as a phone `session_snapshot` instead —
    /// the snapshot path reaches the same adoption, so a snapshot that names
    /// the stopped hold running again stores nothing and reopens nothing
    /// (D-20202, D-20204).
    func testS20202ASnapshotNamingTheStoppedHoldDoesNotReopenIt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(53)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20202-a", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )
        _ = await engine.stopTimer(kind: WatchTimerKind.hold, at: startedAt.addingTimeInterval(20))
        let holdRows = engine.timerRows(WatchTimerKind.hold).count

        let applied = try await engine.applyMessage(
            phoneSnapshot(
                sessionId: harness.sessionId,
                messageId: "m-20202-b",
                sentAt: "2026-07-13T06:10:00Z",
                exercises: engine.session?.exercises ?? [],
                timers: [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            )
        )
        XCTAssertTrue(applied, "S-20202 the snapshot itself applies")

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.stopped,
            "S-20202 the snapshot naming the stopped hold running does not reopen it"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.hold).count,
            holdRows,
            "S-20202 the snapshot stores no hold row for the interval the wrist already ran"
        )
    }

    /// S-20204: the wrist is on `sx-wall`; the phone names a live hold for
    /// `sx-plank` and the wrist follows it (the move is allowed), then stops
    /// the hold and moves back. A second frame naming the same `sx-plank`
    /// interval is ignored, so it neither moves the wrist again nor reopens
    /// the hold (D-20202, D-20204).
    func testS20204AStaleHoldForAnotherExerciseDoesNotMoveTheWrist() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [
                slot("sx-plank", capabilities: ["hold", "time"]),
                slot("sx-wall", capabilities: ["hold", "time"]),
            ]
        )
        _ = await engine.selectExercise(slotId: "sx-wall")

        harness.clock.advance(53)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20204-a", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )
        let afterTheFirstAdoption = engine.session?.currentExerciseIndex
        _ = await engine.stopTimer(kind: WatchTimerKind.hold, at: startedAt.addingTimeInterval(20))
        _ = await engine.selectExercise(slotId: "sx-wall")
        let indexBefore = engine.session?.currentExerciseIndex
        let holdRows = engine.timerRows(WatchTimerKind.hold).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20204-b", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )

        XCTAssertEqual(
            afterTheFirstAdoption,
            0,
            "S-20204 the live frame for sx-plank is what moved the wrist to it"
        )
        XCTAssertEqual(
            engine.session?.currentExerciseIndex,
            indexBefore,
            "S-20204 the stale frame for sx-plank does not move the wrist off sx-wall"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.stopped,
            "S-20204 the stopped hold is not reopened"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.hold).count,
            holdRows,
            "S-20204 the stale frame stores no hold row"
        )
    }

    /// S-20205: the phone names a rest running at T in a `timer_state`, then
    /// the same rest in a `session_snapshot` under a new id. The wrist holds
    /// one rest row with one unchanged id, and the ping memory belongs to that
    /// id: the same boundary pings once, not once per frame that named the
    /// rest (D-20203, D-20204).
    func testS20205ARestAdoptedTwiceKeepsOneRowAndTheSamePingMemory() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(41)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20205-a", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: utcIso(startedAt))
                ]
            ])
        )
        let recordIdBefore = engine.timerFor(WatchTimerKind.rest)?.recordId

        _ = try await engine.applyMessage(
            phoneSnapshot(
                sessionId: harness.sessionId,
                messageId: "m-20205-b",
                sentAt: "2026-07-13T06:10:00Z",
                exercises: engine.session?.exercises ?? [],
                timers: [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: utcIso(startedAt))
                ]
            )
        )

        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            1,
            "S-20205 the snapshot names the rest the wrist already holds, so there is one rest row"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.recordId,
            recordIdBefore,
            "S-20205 the held rest row keeps its own id"
        )

        let restId = try XCTUnwrap(
            engine.timerFor(WatchTimerKind.rest)?.recordId,
            "S-20205 the wrist holds the rest row whose id the ping is keyed on"
        )
        let ping = WatchRestPing()
        XCTAssertTrue(
            ping.isOwed(restId: restId, elapsed: 31, interval: 30),
            "S-20205 the held rest row pings at its first boundary"
        )
        XCTAssertFalse(
            ping.isOwed(restId: restId, elapsed: 31, interval: 30),
            "S-20205 the same boundary does not ping again while the row id is unchanged"
        )
    }

    /// S-20209: the wrist ended the rest the phone named; a snapshot still
    /// naming that rest running at T changes nothing (D-20203, D-20204).
    func testS20209ARestTheWristEndedIsNotReopenedByASnapshot() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(41)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20209-a", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: utcIso(startedAt))
                ]
            ])
        )
        _ = await engine.stopTimer(kind: WatchTimerKind.rest, at: startedAt.addingTimeInterval(10))
        let restRows = engine.timerRows(WatchTimerKind.rest).count

        _ = try await engine.applyMessage(
            phoneSnapshot(
                sessionId: harness.sessionId,
                messageId: "m-20209-b",
                sentAt: "2026-07-13T06:10:00Z",
                exercises: engine.session?.exercises ?? [],
                timers: [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: utcIso(startedAt))
                ]
            )
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.stopped,
            "S-20209 the rest the wrist ended is not reopened by the snapshot"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            restRows,
            "S-20209 the snapshot stores no rest row"
        )
    }

    /// S-20210: a rest the wrist holds running at T, then a phone rest that
    /// starts at T+30 s — a genuinely later rest, so it supersedes the wrist's
    /// own (D-20203's later start wins, S-336).
    func testS20210ALaterPhoneRestStillSupersedesTheWristsRest() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(41)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20210-a", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: utcIso(startedAt))
                ]
            ])
        )
        let restRows = engine.timerRows(WatchTimerKind.rest).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20210-b", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(
                        WatchTimerKind.rest,
                        startedAt: utcIso(startedAt.addingTimeInterval(30))
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.startedAt,
            startedAt.addingTimeInterval(30),
            "S-20210 the phone's later rest is the newest rest the wrist holds"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.running,
            "S-20210 the later rest is running"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            restRows + 1,
            "S-20210 the later rest is a row of its own"
        )
    }

    /// S-20211: a rest the wrist holds at T; an incoming rest at T+0.4 s is
    /// the same interval inside the one-second tolerance and is ignored, while
    /// one at T+2 s is a real new interval and is adopted (D-20203).
    func testS20211TheToleranceIsOneSecond() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(41)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20211-a", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: utcIso(startedAt))
                ]
            ])
        )
        let restRows = engine.timerRows(WatchTimerKind.rest).count

        let nearStart = utcIso(startedAt.addingTimeInterval(0.4))
        XCTAssertEqual(
            try parseUtcIso(nearStart).timeIntervalSince(startedAt),
            0.4,
            accuracy: 0.001,
            "S-20211 utcIso round trips the 0.4 s offset at millisecond precision"
        )
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20211-b", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: nearStart)
                ]
            ])
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            restRows,
            "S-20211 a rest 0.4 s later is the same interval and stores no row"
        )

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20211-c", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(
                        WatchTimerKind.rest,
                        startedAt: utcIso(startedAt.addingTimeInterval(2))
                    )
                ]
            ])
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.startedAt,
            startedAt.addingTimeInterval(2),
            "S-20211 a rest 2 s later is a new interval and is adopted"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            restRows + 1,
            "S-20211 the new interval is a row of its own"
        )
    }

    /// S-20206: a hold the wrist holds running at T, then a frame naming the
    /// same hold with `stoppedAt` set — a stop always applies (D-20202).
    func testS20206AStopFrameStillStopsTheHold() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(53)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20206-a", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )
        let holdRows = engine.timerRows(WatchTimerKind.hold).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20206-b", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank",
                        stoppedAt: utcIso(startedAt.addingTimeInterval(5))
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.stopped,
            "S-20206 the stop frame stops the hold"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.stoppedAt,
            startedAt.addingTimeInterval(5),
            "S-20206 the stop's own instant is the one kept"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.hold).count,
            holdRows + 1,
            "S-20206 the stop is a row of its own"
        )
    }

    /// S-20212: a rest the wrist holds paused at T, then the phone's resume of
    /// the same rest — `pausedAt` nil, `accumulatedPauseMs` 5000 — is a
    /// different pause shape, so it is adopted (D-20203's exact-repeat rule
    /// does not swallow a resume).
    func testS20212AResumeOfTheSameRestIsStillAdopted() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(41)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20212-a", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(
                        WatchTimerKind.rest,
                        startedAt: utcIso(startedAt),
                        pausedAt: utcIso(startedAt.addingTimeInterval(10))
                    )
                ]
            ])
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.paused,
            "S-20212 the fixture holds the rest paused"
        )
        let restRows = engine.timerRows(WatchTimerKind.rest).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20212-b", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(
                        WatchTimerKind.rest,
                        startedAt: utcIso(startedAt),
                        accumulatedPauseMs: 5000
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.running,
            "S-20212 the resume adopts a running rest row"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.accumulatedPauseMs,
            5000,
            "S-20212 the resume carries its own accumulated pause"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            restRows + 1,
            "S-20212 the resume is a row of its own"
        )
    }

    /// S-20208: the source guard — inside `adoptTimer`, the plan-202 guard runs
    /// before the store append and before the jump target is asked for, and the
    /// helper's tolerance is the one-second comparison (D-20204).
    func testS20208TheGuardRunsBeforeTheStoreAppendAndTheJump() throws {
        let lines = sourceLines(
            try engineSource("watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift")
        )
        let adopt = try functionBody("private func adoptTimer(", in: lines)
        let ran = try functionBody("private func ranInterval(", in: lines)

        XCTAssertEqual(
            adopt.filter { $0.trimmingCharacters(in: .whitespaces) == "if stoppedAt == nil," }.count,
            1,
            "S-20208 the guard's own condition stands in adoptTimer once"
        )
        let call = try XCTUnwrap(
            adopt.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "ranInterval(" },
            "S-20208 adoptTimer calls ranInterval"
        )
        let append = try XCTUnwrap(
            adopt.firstIndex { $0.contains("store.append(") },
            "S-20208 adoptTimer appends to the store"
        )
        let jump = try XCTUnwrap(
            adopt.firstIndex { $0.contains("jumpTarget(") },
            "S-20208 adoptTimer asks for a jump target"
        )
        XCTAssertLessThan(
            call,
            append,
            "S-20208 the guard runs before the store append (D-20204)"
        )
        XCTAssertLessThan(
            call,
            jump,
            "S-20208 the guard runs before the jump target (D-20204)"
        )
        XCTAssertTrue(
            ran.contains {
                $0.trimmingCharacters(in: .whitespaces)
                    == "abs(held.startedAt.timeIntervalSince(startedAt)) < 1.0"
            },
            "S-20208 the helper's tolerance is one second"
        )
    }

    /// S-20213: the wrist's stopped hold of `sx-plank` names its own slot, so a
    /// stopped hold of ANOTHER slot never blocks a frame for a different slot.
    /// A frame naming a hold running at the same T for `sx-wall` is adopted
    /// (the guard's slot comparison is what makes the difference).
    func testS20213AStoppedHoldOfAnotherExerciseDoesNotBlockANewInterval() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [
                slot("sx-plank", capabilities: ["hold", "time"]),
                slot("sx-wall", capabilities: ["hold", "time"]),
            ]
        )

        harness.clock.advance(67)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20213-a", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )
        _ = await engine.stopTimer(kind: WatchTimerKind.hold, at: startedAt.addingTimeInterval(20))
        let holdRows = engine.timerRows(WatchTimerKind.hold).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20213-b", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-wall"
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.sessionExerciseId,
            "sx-wall",
            "S-20213 the newest hold row is the frame's own slot"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.running,
            "S-20213 a hold for another slot is not the interval the wrist ran"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.hold).count,
            holdRows + 1,
            "S-20213 the sx-wall hold is a row of its own"
        )
    }

    /// S-20214: a rest repeat the wrist already holds is only ignored when the
    /// pause shape repeats too: the same rest at T, still running with
    /// `pausedAt` nil but a new `accumulatedPauseMs` of 3000, is adopted. A
    /// third frame identical to the second is then ignored.
    func testS20214ARestThatDiffersOnlyByItsAccumulatedPauseIsAdopted() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(29)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20214-a", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: utcIso(startedAt))
                ]
            ])
        )
        let restRows = engine.timerRows(WatchTimerKind.rest).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20214-b", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(
                        WatchTimerKind.rest,
                        startedAt: utcIso(startedAt),
                        accumulatedPauseMs: 3000
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.accumulatedPauseMs,
            3000,
            "S-20214 the rest's own accumulated pause is the one kept"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.running,
            "S-20214 the new pause shape is a running rest row"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            restRows + 1,
            "S-20214 a rest differing only by its accumulated pause is a row of its own"
        )

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20214-c", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(
                        WatchTimerKind.rest,
                        startedAt: utcIso(startedAt),
                        accumulatedPauseMs: 3000
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            restRows + 1,
            "S-20214 an exact repeat of the rest the wrist holds stores no row"
        )
    }

    /// S-20215: a stop frame (`stoppedAt` set) for a rest the wrist holds
    /// running at the same T is never swallowed by the repeat guard — a stop
    /// always applies (S-20206's rest twin).
    func testS20215ARestStopFrameStopsAnIdenticalRunningRest() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(67)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20215-a", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: utcIso(startedAt))
                ]
            ])
        )
        let restRows = engine.timerRows(WatchTimerKind.rest).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20215-b", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(
                        WatchTimerKind.rest,
                        startedAt: utcIso(startedAt),
                        stoppedAt: utcIso(startedAt.addingTimeInterval(40))
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.stopped,
            "S-20215 the stop frame stops the rest the wrist holds running"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.stoppedAt,
            startedAt.addingTimeInterval(40),
            "S-20215 the stop's own instant is the one kept"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            restRows + 1,
            "S-20215 the stop is a row of its own"
        )
    }

    /// S-27606: the phone cannot send `{rest: null}` — iOS refuses a message
    /// holding a null — so a clear travels as a stopped timer with no slot and
    /// no pause fields, started and stopped at the frame's own instant, which is
    /// later than the timer it ends (`wireSafeFrame`). It stops a running rest
    /// and a running hold alike.
    func testS27606APhoneClearSentAsAStoppedTimerStopsARunningRestAndHold() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(67)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-27606-a", payload: [
                "timers": [
                    WatchTimerKind.rest: phoneTimer(WatchTimerKind.rest, startedAt: utcIso(startedAt)),
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    ),
                ]
            ])
        )
        XCTAssertNotEqual(engine.timerFor(WatchTimerKind.rest)?.state, WatchTimerState.stopped)
        XCTAssertNotEqual(engine.timerFor(WatchTimerKind.hold)?.state, WatchTimerState.stopped)

        let clearedAt = utcIso(startedAt.addingTimeInterval(30))
        func clear(_ kind: String) -> [String: Any] {
            ["kind": kind, "state": "stopped", "startedAt": clearedAt, "stoppedAt": clearedAt]
        }
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-27606-b", payload: [
                "timers": [
                    WatchTimerKind.rest: clear(WatchTimerKind.rest),
                    WatchTimerKind.hold: clear(WatchTimerKind.hold),
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.stopped,
            "S-27606 the clear stops the running rest"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.stopped,
            "S-27606 the clear stops the running hold"
        )
    }

    /// S-20216: the wrist holds a hold running at T; a frame names the same
    /// hold at T paused (`pausedAt` set) — a running row the wrist holds never
    /// blocks a pause of the same interval, because the pause shape differs.
    func testS20216APauseOfARunningHoldIsAdopted() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )

        harness.clock.advance(29)
        let startedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20216-a", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank"
                    )
                ]
            ])
        )
        let holdRows = engine.timerRows(WatchTimerKind.hold).count

        _ = try await engine.applyMessage(
            phoneFrame("timer_state", sessionId: harness.sessionId, messageId: "m-20216-b", payload: [
                "timers": [
                    WatchTimerKind.hold: phoneTimer(
                        WatchTimerKind.hold,
                        startedAt: utcIso(startedAt),
                        sessionExerciseId: "sx-plank",
                        pausedAt: utcIso(startedAt.addingTimeInterval(15))
                    )
                ]
            ])
        )

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.paused,
            "S-20216 the pause of the running hold is adopted"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.pausedAt,
            startedAt.addingTimeInterval(15),
            "S-20216 the pause's own instant is the one kept"
        )
        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.hold).count,
            holdRows + 1,
            "S-20216 the pause is a row of its own"
        )
    }
}

// MARK: - Reading the engine's source text (S-20208's source guard)

/// A repository file read from `Fixtures.repositoryRoot`, with every comment
/// line blanked out — the shape `WatchMenuTests.menuSource` uses, so a sentence
/// of prose can neither satisfy a guard nor trip one.
private func engineSource(_ path: String) throws -> String {
    let url = Fixtures.repositoryRoot.appendingPathComponent(path)
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
            guard let comment = line.range(of: "//") else { return String(line) }
            return String(line[..<comment.lowerBound])
        }
        .joined(separator: "\n")
}

private func sourceLines(_ source: String) -> [String] {
    source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

/// The lines of the first function whose declaration contains `marker`, from
/// the declaration line through the line that closes its body (brace counting).
private func functionBody(_ marker: String, in lines: [String]) throws -> [String] {
    let start = try XCTUnwrap(
        lines.firstIndex { $0.contains(marker) },
        "S-20208 \(marker) is in the engine's source"
    )
    var depth = 0
    var opened = false
    var body: [String] = []
    for line in lines[start...] {
        let opens = line.filter { $0 == "{" }.count
        let closes = line.filter { $0 == "}" }.count
        body.append(line)
        depth += opens - closes
        if opens > 0 { opened = true }
        if opened, depth <= 0 { break }
    }
    return body
}
