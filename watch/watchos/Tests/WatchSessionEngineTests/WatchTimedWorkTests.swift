//
//  WatchTimedWorkTests.swift
//  WatchSessionEngineTests
//
//  S-1300 to S-1306 and the guards S-1310 to S-1312 of
//  `docs/plans/2026-10-09-21-watch-timed-work-plan/2026-10-09-21-watch-timed-work-plan.md`:
//  the work clock (one Start button that turns into Log) and the surface state
//  that reads it, proved on the desktop toolchain without a watch target.
//
//  Every instant below is derived from the injected clock and the stored timer
//  rows, never from a ticker: the screen-off case is the same case as the
//  on-screen one. Fixtures are the register's: `sx-run` (`time`, `distance`),
//  `sx-plank` (`hold`, `time`) and a `rounds` slot, on the shared
//  `Harness`/`TestClock`.
//

import XCTest

@testable import WatchSessionEngine

final class WatchTimedWorkTests: XCTestCase {

    private func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)!
    }

    private func slot(_ id: String, capabilities: [String]) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
    }

    private func surface(
        _ harness: Harness,
        engine: WatchSessionEngine,
        roundPresetMs: Int? = nil
    ) -> WatchLoggingState {
        WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            roundPresetMs: roundPresetMs
        )
    }

    /// The event the surface logged last, with the schema's verdict on the frame
    /// that carried it.
    private func loggedEvent(
        _ harness: Harness
    ) throws -> (event: [String: Any], rejections: [SyncProtocolRejection]) {
        let envelope = try XCTUnwrap(
            harness.emitted.last(where: { $0["type"] as? String == "observations_up" })
        )
        let events = (envelope["payload"] as? [String: Any])?["events"] as? [[String: Any]]
        return (try XCTUnwrap(events?.first), Harness.validator().validateEnvelope(envelope))
    }

    /// Every observation event the wrist emitted, oldest first.
    private func emittedEvents(_ harness: Harness) -> [[String: Any]] {
        harness.emitted
            .filter { $0["type"] as? String == "observations_up" }
            .flatMap { (($0["payload"] as? [String: Any])?["events"] as? [[String: Any]]) ?? [] }
    }

    private func phoneFrame(
        _ type: String,
        sessionId: String,
        messageId: String,
        sentAt: String,
        payload: [String: Any]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": type,
            "origin": "phone",
            "sentAt": sentAt,
            "payload": payload,
        ]
    }

    private func runningTimer(_ kind: String, startedAt: String) -> [String: Any] {
        [
            "kind": kind,
            "state": WatchTimerState.running,
            "startedAt": startedAt,
            "plannedDurationMs": 60_000,
        ]
    }

    // MARK: - S-1300 cardio Start → Log

    func testS1300TimedWorkIsLoggedAsTheWindowFromStartToLog() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let surface = surface(harness, engine: engine)

        let startedAt = harness.clock.now
        await surface.startWork()
        harness.clock.advance(754) // 10:12:34
        let loggedAt = harness.clock.now
        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["kind"] as? String, "timed")
        XCTAssertEqual(logged.event["startedAt"] as? String, utcIso(startedAt))
        XCTAssertEqual(logged.event["endedAt"] as? String, utcIso(loggedAt))
        XCTAssertNil(
            logged.event["distanceMeters"],
            "no distance is dialled and nothing was measured, so none is saved"
        )
        XCTAssertTrue(surface.fields.isEmpty, "a timed effort has no value rows")
        XCTAssertEqual(engine.timerFor(WatchTimerKind.elapsed)?.state, WatchTimerState.stopped)
        XCTAssertEqual(engine.timerFor(WatchTimerKind.elapsed)?.stoppedAt, loggedAt)
    }

    // MARK: - S-1301 Log before Start

    func testS1301LogBeforeStartStoresNothing() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let surface = surface(harness, engine: engine)

        let before = engine.entries.count
        harness.clearEmitted()
        do {
            try await surface.log()
            XCTFail("Log before Start must store nothing")
        } catch is WatchRecordError {
            // Expected: there is nothing to log yet.
        }
        XCTAssertEqual(engine.entries.count, before, "the refused log appended no entry")
        XCTAssertTrue(harness.emitted.isEmpty, "the refused log emitted no frame")

        await surface.startWork()
        await surface.startWork()
        let clocks = engine.timerRows(WatchTimerKind.elapsed)
        XCTAssertEqual(clocks.count, 1, "a second Start does not stack a second clock")
        XCTAssertEqual(clocks.first?.state, WatchTimerState.running)
    }

    // MARK: - S-1302 drill keeps Extra load

    func testS1302ADrillKeepsItsExtraLoadRow() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "isometric_stretching",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )
        let surface = surface(harness, engine: engine)

        XCTAssertEqual(surface.effortKind, WatchEffortKind.drill)
        XCTAssertEqual(surface.fields.map(\.metricKey), [WatchMetricKey.extraWeight])

        surface.adjust(WatchMetricKey.extraWeight, detents: -4)
        await surface.startWork()
        harness.clock.advance(60)
        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["kind"] as? String, "hold")
        XCTAssertEqual(
            logged.event["startedAt"] as? String,
            utcIso(harness.clock.now.addingTimeInterval(-60))
        )
        XCTAssertEqual(logged.event["endedAt"] as? String, utcIso(harness.clock.now))
        XCTAssertEqual(logged.event["extraLoadKg"] as? Double, -10)
    }

    // MARK: - S-1303 a period is a countdown and Log is not +round

    @MainActor
    func testS1303APeriodCountsDownAndLogIsNotARoundButton() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-bjj", capabilities: ["time", "rounds"])]
        )
        let surface = surface(harness, engine: engine)
        let model = WatchLoggingModel(state: surface, haptics: RecordingHaptics())

        XCTAssertEqual(surface.effortKind, WatchEffortKind.round)
        XCTAssertTrue(surface.fields.isEmpty, "a period has no rounds or length row")
        XCTAssertEqual(surface.workRemainingSeconds(), 180, "before Start a period shows its preset")
        XCTAssertEqual(model.primaryTitle, "Start", "a period that is not running offers Start")
        XCTAssertEqual(model.workReadout, "3:00", "the preset is what a period shows before Start")

        let startedAt = harness.clock.now
        await surface.startWork()
        let countdown = try XCTUnwrap(engine.timerFor(WatchTimerKind.round))
        XCTAssertEqual(countdown.plannedDurationMs, 180_000, "the wrist's own preset (D-1303)")
        XCTAssertEqual(countdown.startedAt, startedAt)

        harness.clock.advance(90)
        XCTAssertEqual(surface.workRemainingSeconds(), 90, "the period counts down")
        XCTAssertEqual(model.primaryTitle, "Log", "a running period's button is Log")
        XCTAssertEqual(model.workReadout, "1:30", "a period's readout counts down")

        try await surface.log()
        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["kind"] as? String, "round")
        XCTAssertEqual(logged.event["roundNumber"] as? Int, 1)
        XCTAssertEqual(logged.event["startedAt"] as? String, utcIso(startedAt))
        XCTAssertEqual(logged.event["endedAt"] as? String, utcIso(harness.clock.now))

        let stopped = try XCTUnwrap(engine.timerFor(WatchTimerKind.round))
        XCTAssertEqual(stopped.state, WatchTimerState.stopped, "Log stops the period's clock")
        XCTAssertEqual(stopped.stoppedAt, harness.clock.now)
        XCTAssertFalse(surface.isWorkRunning)

        // No follow-on countdown: polling the whole stretch the user would have
        // waited is owed nothing, and no new countdown row exists.
        let haptics = WatchTimerHaptics(engine)
        var milestones: [WatchTimerMilestone] = []
        for second in 0...600 {
            milestones += haptics.poll(now: startedAt.addingTimeInterval(Double(second)))
        }
        XCTAssertTrue(milestones.isEmpty, "a logged period starts nothing")
        XCTAssertTrue(
            engine.timerRows(WatchTimerKind.rest).isEmpty,
            "timed work starts no rest of its own (D-1306)"
        )
        XCTAssertEqual(
            stopped.startedAt,
            startedAt,
            "no new countdown row exists: the newest row is still the one Start wrote"
        )

        // The next period is the user's own Start, numbered 2.
        await surface.startWork()
        harness.clock.advance(10)
        try await surface.log()
        XCTAssertEqual(try loggedEvent(harness).event["roundNumber"] as? Int, 2)
    }

    // MARK: - D-1307 the period line

    @MainActor
    func testS1303ThePeriodLineNamesTheNextPeriodInTheModalitysOwnWord() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-bjj", capabilities: ["time", "rounds"])]
        )
        let periodSurface = surface(harness, engine: engine)
        let model = WatchLoggingModel(state: periodSurface, haptics: RecordingHaptics())

        XCTAssertEqual(model.periodLine, "Period 1", "the first period is what Start will record")

        await model.startWork()
        harness.clock.advance(30)
        await model.log()

        XCTAssertEqual(
            model.periodLine,
            "Period 2",
            "one period logged: the line names the next in the modality's own word, singular (D-1307)"
        )

        let other = Harness()
        let otherEngine = await other.runningEngine()
        _ = await otherEngine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let timed = WatchLoggingModel(
            state: surface(other, engine: otherEngine),
            haptics: RecordingHaptics()
        )
        XCTAssertNil(timed.periodLine, "a timed slot has no periods to name")
    }

    // MARK: - S-1304 a late Log on a period

    func testS1304ALateLogOnAPeriodEndsWhereTheCountdownDid() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-bjj", capabilities: ["time", "rounds"])]
        )
        let surface = surface(harness, engine: engine)

        let startedAt = harness.clock.now
        await surface.startWork()
        harness.clock.advance(300) // 10:05:00 — two minutes past the countdown
        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["startedAt"] as? String, utcIso(startedAt))
        XCTAssertEqual(
            logged.event["endedAt"] as? String,
            utcIso(startedAt.addingTimeInterval(180)),
            "the period ended when its countdown did, not when the user looked down"
        )

        let haptics = WatchTimerHaptics(engine)
        var milestones: [WatchTimerMilestone] = []
        for second in 0...360 {
            milestones += haptics.poll(now: startedAt.addingTimeInterval(Double(second)))
        }
        XCTAssertEqual(
            milestones,
            [WatchTimerMilestone(kind: WatchTimerKind.round, at: startedAt.addingTimeInterval(180))],
            "exactly one milestone, at the instant the countdown reached zero"
        )
    }

    // MARK: - S-1305 Start ends a rest

    func testS1305StartEndsARunningRest() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: [
                slot("sx-bench", capabilities: ["reps", "sets", "load"]),
                slot("sx-run", capabilities: ["time", "distance"]),
            ]
        )
        let surface = surface(harness, engine: engine)

        let set = try await surface.log()
        let restStartedAt = harness.clock.now

        _ = await engine.selectExercise(slotId: "sx-run")
        harness.clock.advance(40)
        let startInstant = harness.clock.now
        await surface.startWork()

        let rest = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(rest.state, WatchTimerState.stopped)
        XCTAssertEqual(rest.stoppedAt, startInstant, "the rest ends at the Start instant")

        let restEvent = try XCTUnwrap(
            emittedEvents(harness).last { $0["kind"] as? String == "rest" }
        )
        XCTAssertEqual(restEvent["startedAt"] as? String, utcIso(restStartedAt))
        XCTAssertEqual(restEvent["endedAt"] as? String, utcIso(startInstant))
        XCTAssertEqual(restEvent["afterEntryId"] as? String, set.entryId)

        XCTAssertEqual(engine.timerFor(WatchTimerKind.elapsed)?.startedAt, startInstant)
    }

    // MARK: - S-1306 derived, not counted

    func testS1306TheClockIsTheStoredTimers() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        await surface(harness, engine: engine).startWork()

        harness.clock.advance(180)
        let relaunched = surface(harness, engine: engine)
        XCTAssertTrue(relaunched.isWorkRunning)
        XCTAssertEqual(relaunched.workElapsedSeconds(), 180)

        _ = await engine.stopTimer(kind: WatchTimerKind.elapsed)
        XCTAssertFalse(relaunched.isWorkRunning, "a stopped timer reports not running")
        XCTAssertEqual(relaunched.workElapsedSeconds(), 0)
    }

    // MARK: - S-1310 a phone snapshot cannot stop the wrist's work clock

    func testS1310APhoneSnapshotLeavesTheWristsWorkClockRunning() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        let ladder = [
            slot("sx-run", capabilities: ["time", "distance"]),
            slot("sx-bjj", capabilities: ["time", "rounds"]),
        ]
        _ = await engine.createSession(modality: "cardio_endurance", exercises: ladder)

        // The phone's own countdown: its row id derives from the message that
        // named it, which is what marks it as the sender's (D-80).
        _ = try await engine.applyMessage(
            phoneFrame(
                "timer_state",
                sessionId: harness.sessionId,
                messageId: "m-phone",
                sentAt: "2026-07-13T09:59:50Z",
                payload: [
                    "timers": [
                        WatchTimerKind.round: runningTimer(
                            WatchTimerKind.round,
                            startedAt: "2026-07-13T09:59:50Z"
                        )
                    ]
                ]
            )
        )

        await surface(harness, engine: engine).startWork()
        let elapsedId = try XCTUnwrap(engine.timerFor(WatchTimerKind.elapsed)?.recordId)

        harness.clock.advance(30)
        _ = try await engine.applyMessage(
            phoneFrame(
                "session_snapshot",
                sessionId: harness.sessionId,
                messageId: "snap-1",
                sentAt: "2026-07-13T10:00:30Z",
                payload: [
                    "sessionId": harness.sessionId,
                    "revision": 1,
                    "status": WatchSessionStatus.active,
                    "currentExerciseIndex": 1,
                    "exercises": ladder,
                    "entries": [[String: Any]](),
                    "timers": [String: Any](),
                ]
            )
        )

        let elapsed = try XCTUnwrap(engine.timerFor(WatchTimerKind.elapsed))
        XCTAssertEqual(
            elapsed.recordId,
            elapsedId,
            "the wrist started it, so the phone is not speaking about it"
        )
        XCTAssertEqual(elapsed.state, WatchTimerState.running)
        XCTAssertNil(elapsed.stoppedAt)

        let round = try XCTUnwrap(engine.timerFor(WatchTimerKind.round))
        XCTAssertEqual(round.state, WatchTimerState.stopped, "the phone's own row is the one stopped")
        XCTAssertEqual(round.stoppedAt, instant("2026-07-13T10:00:30Z"))
    }

    // MARK: - S-1311 Finish leaves the work clock running and takes the readout

    func testS1311FinishLeavesTheWorkClockRunningAndTakesTheReadout() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let surface = surface(harness, engine: engine)
        let startedAt = harness.clock.now
        await surface.startWork()

        harness.clock.advance(300) // 10:05:00
        let endedAt = harness.clock.now

        let preferences = WatchPhonePreferences(
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call
        )
        let menu = WatchMenuState(
            engine: engine,
            paths: WatchSessionStartPaths(
                engine: engine,
                store: harness.store,
                validator: Harness.validator(),
                clock: harness.clock.call
            ),
            rating: WatchEffortRatingState(
                engine: engine,
                store: harness.store,
                preferences: preferences,
                clock: harness.clock.call
            )
        )
        await menu.finish()

        XCTAssertFalse(surface.canLog)
        XCTAssertTrue(surface.fields.isEmpty)
        XCTAssertNil(surface.workTimer, "no readout outlives the session")
        XCTAssertFalse(surface.isWorkRunning)

        let end = try XCTUnwrap(
            engine.entries.last { $0.kind == WatchObservationKind.sessionEnd }
        )
        XCTAssertEqual(end.payload["startedAt"] as? String, utcIso(startedAt))
        XCTAssertEqual(end.payload["endedAt"] as? String, utcIso(endedAt))

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.elapsed)?.state,
            WatchTimerState.running,
            "a Finish stops only the rest; the work row survives in storage (D-1309)"
        )
    }

    // MARK: - S-1312 the clock is the storage, not the screen

    @MainActor
    func testS1312ARelaunchKeepsTheButtonOnLog() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let startedAt = harness.clock.now
        await surface(harness, engine: engine).startWork()

        harness.clock.advance(180) // 10:03:00

        // A relaunch: new objects, same engine and storage.
        let relaunched = await harness.runningEngine(harness.newEngine())
        let state = surface(harness, engine: relaunched)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())

        XCTAssertTrue(state.isWorkRunning)
        XCTAssertEqual(state.workElapsedSeconds(), 180)
        XCTAssertEqual(model.primaryTitle, "Log", "a running effort shows Log, not Start")
        XCTAssertEqual(model.workReadout, "3:00")

        try await state.log()
        let logged = try loggedEvent(harness)
        XCTAssertEqual(logged.event["startedAt"] as? String, utcIso(startedAt))
        XCTAssertEqual(logged.event["endedAt"] as? String, utcIso(harness.clock.now))
    }
}
