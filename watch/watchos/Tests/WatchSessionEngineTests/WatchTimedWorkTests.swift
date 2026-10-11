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

    /// A round slot: the register's `time`+`rounds` pair, with the phone's own
    /// period length when the case has one.
    private func roundSlot(_ id: String, roundDurationSecs: Int? = nil) -> [String: Any] {
        var slot = slot(id, capabilities: ["time", "rounds"])
        if let roundDurationSecs { slot[WatchCatalogExercise.roundDurationKey] = roundDurationSecs }
        return slot
    }

    /// What a row shows right now, or nil when the surface offers no such row.
    private func fieldValue(_ surface: WatchLoggingState, _ metricKey: String) -> Double? {
        surface.fields.first { $0.metricKey == metricKey }?.value
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
        XCTAssertEqual(
            surface.fields.map(\.metricKey),
            [WatchMetricKey.roundDuration],
            "23a: a period shows its length row before Start, and nothing else"
        )
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
        let rests = engine.timerRows(WatchTimerKind.rest)
        XCTAssertEqual(rests.count, 1, "a logged period starts one rest (D-3501)")
        XCTAssertEqual(
            rests.first?.state,
            WatchTimerState.running,
            "and that rest is running, not a countdown"
        )
        XCTAssertNil(
            rests.first?.plannedDurationMs,
            "the rest is a count-up with no length (D-160)"
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

    // MARK: - S-3403 to S-3409, plan 23a: the Load label and the period length row

    func testS3403AHoldRowIsLabelledLoad() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "isometric_stretching",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )
        let surface = surface(harness, engine: engine)

        let row = try XCTUnwrap(
            surface.fields.first { $0.metricKey == WatchMetricKey.extraWeight }
        )
        XCTAssertEqual(
            row.label,
            "Load",
            "the wire field stays extraLoadKg; the wrist's word is Load (D-3403)"
        )
    }

    func testS3404APeriodShowsItsLengthBeforeStart() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [roundSlot("sx-half", roundDurationSecs: 2400)]
        )
        let surface = surface(harness, engine: engine)

        XCTAssertEqual(surface.effortKind, WatchEffortKind.round)
        XCTAssertEqual(
            surface.fields.map(\.metricKey),
            [WatchMetricKey.roundDuration],
            "a period's only row is its length (D-3404)"
        )
        XCTAssertEqual(fieldValue(surface, WatchMetricKey.roundDuration), 2400, "the phone's own number")
        XCTAssertEqual(surface.workRemainingSeconds(), 2400, "and it is what the countdown would start from")

        let preset = Harness()
        preset.clock.now = instant("2026-07-13T10:00:00Z")
        let presetEngine = await preset.runningEngine()
        _ = await presetEngine.createSession(
            modality: "sports",
            exercises: [roundSlot("sx-bjj")]
        )
        let presetSurface = self.surface(preset, engine: presetEngine)

        XCTAssertEqual(
            fieldValue(presetSurface, WatchMetricKey.roundDuration),
            180,
            "no number on the slot: the wrist's own preset"
        )
    }

    func testS3405TurningTheLengthChangesWhatStartCountsDownFrom() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [roundSlot("sx-bjj")]
        )
        let surface = surface(harness, engine: engine)

        XCTAssertEqual(fieldValue(surface, WatchMetricKey.roundDuration), 180)
        surface.adjust(WatchMetricKey.roundDuration, detents: 3)
        XCTAssertEqual(
            fieldValue(surface, WatchMetricKey.roundDuration),
            180 + 3 * WatchMetricStepping.secondsPerDetent,
            "three detents of five seconds"
        )

        let startedAt = harness.clock.now
        await surface.startWork()
        let countdown = try XCTUnwrap(engine.timerFor(WatchTimerKind.round))
        XCTAssertEqual(
            countdown.plannedDurationMs,
            195_000,
            "Start counts down from the length the user dialled (D-3404)"
        )
        XCTAssertEqual(countdown.startedAt, startedAt)
        XCTAssertEqual(surface.workRemainingSeconds(), 195)
    }

    func testS3406ARunningPeriodHasNoLengthRowAndKeepsTheDialledLength() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [
                roundSlot("sx-half", roundDurationSecs: 2400),
                roundSlot("sx-shift", roundDurationSecs: 600),
            ]
        )
        let surface = surface(harness, engine: engine)

        surface.adjust(WatchMetricKey.roundDuration, detents: 3)
        let dialled = try XCTUnwrap(fieldValue(surface, WatchMetricKey.roundDuration))
        XCTAssertEqual(dialled, 2400 + 3 * WatchMetricStepping.secondsPerDetent)

        await surface.startWork()
        XCTAssertTrue(
            surface.fields.isEmpty,
            "a running period offers no row: its length cannot change mid-countdown (D-3404)"
        )
        XCTAssertEqual(engine.timerFor(WatchTimerKind.round)?.plannedDurationMs, Int(dialled) * 1000)

        harness.clock.advance(60)
        try await surface.log()

        XCTAssertEqual(
            fieldValue(surface, WatchMetricKey.roundDuration),
            dialled,
            "after Log the next period starts from the length the last one used (D-3404)"
        )
        XCTAssertFalse(surface.isWorkRunning)

        await surface.startWork()
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.round)?.plannedDurationMs,
            Int(dialled) * 1000,
            "the same slot's next period counts down from the same length"
        )
        harness.clock.advance(30)
        try await surface.log()

        _ = await engine.selectExercise(slotId: "sx-shift")
        XCTAssertEqual(
            fieldValue(surface, WatchMetricKey.roundDuration),
            600,
            "another slot starts from its own number, never the override (D-3404)"
        )
    }

    func testS3407APeriodLengthNeverFallsBelowOneSecond() async throws {
        XCTAssertEqual(
            WatchMetricStepping.adjust(0, metricKey: WatchMetricKey.roundDuration, detents: -1),
            1,
            "the shortest length the schema accepts (D-3405)"
        )

        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [roundSlot("sx-bjj")]
        )
        let surface = surface(harness, engine: engine)

        surface.adjust(WatchMetricKey.roundDuration, detents: -40)
        XCTAssertEqual(fieldValue(surface, WatchMetricKey.roundDuration), 1)

        await surface.startWork()
        XCTAssertEqual(engine.timerFor(WatchTimerKind.round)?.plannedDurationMs, 1000)
    }

    func testS3408SetsAndTimedWorkKeepTheRowsTheyHad() async throws {
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

        XCTAssertEqual(
            surface.fields.map(\.metricKey),
            [WatchMetricKey.reps, WatchMetricKey.weight],
            "a set shows reps and load and nothing new"
        )

        _ = await engine.selectExercise(slotId: "sx-run")
        XCTAssertTrue(surface.fields.isEmpty, "a timed effort still has no row (D-1305)")
    }

    func testS3409TheRestSurfaceNamesItself() {
        XCTAssertEqual(WatchRestSurfaceCopy.restCaption, "Rest")
    }

    // MARK: - S-3502 to S-3505, plan 23b: every effort starts a rest

    func testS3502ATimedEntryStartAndLogLeavesTheRestRunning() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let surface = surface(harness, engine: engine)

        await surface.startWork()
        harness.clock.advance(754) // 10:12:34
        try await surface.log()

        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.elapsed)?.state,
            WatchTimerState.stopped,
            "Log still ends the timed window's own clock (S-1300)"
        )
        XCTAssertTrue(
            surface.isResting,
            "a logged timed entry starts the rest screen, as a set does (D-3501)"
        )
        XCTAssertEqual(surface.restElapsedSeconds(), 0, "the rest starts at 0:00")

        let rests = engine.timerRows(WatchTimerKind.rest)
        XCTAssertEqual(rests.count, 1, "one rest, the one this log started")
        XCTAssertEqual(rests.first?.state, WatchTimerState.running)
        XCTAssertEqual(rests.first?.startedAt, harness.clock.now)
        XCTAssertNil(rests.first?.plannedDurationMs, "a rest has no length (D-160)")
    }

    func testS3503AHoldStartsARestAfterItsLog() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "isometric_stretching",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )
        let surface = surface(harness, engine: engine)

        await surface.startWork()
        harness.clock.advance(60)
        try await surface.log()

        XCTAssertEqual(surface.effortKind, WatchEffortKind.drill)
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.hold)?.state,
            WatchTimerState.stopped,
            "the hold's own clock is the one Log stops"
        )
        XCTAssertTrue(surface.isResting, "a logged hold starts the rest screen (D-3501)")

        let rests = engine.timerRows(WatchTimerKind.rest)
        XCTAssertEqual(rests.count, 1, "exactly one rest row")
        XCTAssertEqual(rests.first?.state, WatchTimerState.running)
        XCTAssertNil(rests.first?.plannedDurationMs)
    }

    @MainActor
    func testS3503BAPeriodStartsARestAfterItsLog() async throws {
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
        harness.clock.advance(90)
        try await surface.log()

        let stopped = try XCTUnwrap(engine.timerFor(WatchTimerKind.round))
        XCTAssertEqual(stopped.state, WatchTimerState.stopped, "Log stops the period's clock")
        XCTAssertEqual(
            stopped.startedAt,
            startedAt,
            "no new round countdown replaces it (D-1306)"
        )
        XCTAssertTrue(surface.isResting, "a logged period starts the rest screen (D-3501)")

        let rests = engine.timerRows(WatchTimerKind.rest)
        XCTAssertEqual(rests.count, 1, "exactly one rest row")
        XCTAssertEqual(rests.first?.state, WatchTimerState.running)
        XCTAssertNil(
            rests.first?.plannedDurationMs,
            "the rest is a count-up: the period's countdown is not moved onto it"
        )

        // The user's own Start ends the rest and opens period 2 where it left
        // off — no countdown of the app's own (D-1306).
        harness.clock.advance(30)
        let nextStart = harness.clock.now
        await surface.startWork()
        let nextRound = try XCTUnwrap(engine.timerFor(WatchTimerKind.round))
        XCTAssertEqual(nextRound.startedAt, nextStart)
        XCTAssertFalse(surface.isResting, "Start leaves the rest")
    }

    func testS3504StartOfTheNextTimedEffortEndsTheRestItWalksInto() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let surface = surface(harness, engine: engine)

        await surface.startWork()
        harness.clock.advance(300) // 10:05:00
        let first = try await surface.log()
        let restStartedAt = harness.clock.now

        harness.clock.advance(45) // 10:05:45
        let startInstant = harness.clock.now
        await surface.startWork()

        let rest = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(rest.state, WatchTimerState.stopped)
        XCTAssertEqual(rest.stoppedAt, startInstant, "the rest ends at the Start instant (D-1311)")

        let rests = emittedEvents(harness).filter { $0["kind"] as? String == "rest" }
        XCTAssertEqual(rests.count, 1, "one rest observation, the one this Start ended")
        XCTAssertEqual(rests.first?["startedAt"] as? String, utcIso(restStartedAt))
        XCTAssertEqual(rests.first?["endedAt"] as? String, utcIso(startInstant))
        XCTAssertEqual(
            rests.first?["afterEntryId"] as? String,
            first.entryId,
            "the rest hangs on the entry it followed (D-221)"
        )
        XCTAssertFalse(surface.isResting)
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.elapsed)?.startedAt,
            startInstant,
            "the next timed window runs from Start"
        )
    }

    func testS3505EndingTheRestAfterATimedEntryReportsThatEntry() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let surface = surface(harness, engine: engine)

        await surface.startWork()
        harness.clock.advance(240) // 10:04:00
        let timed = try await surface.log()
        let restStartedAt = harness.clock.now

        harness.clock.advance(75)
        let endedAt = harness.clock.now
        await surface.endRest()

        XCTAssertFalse(surface.isResting, "Next ends the rest, so the shell returns to logging")
        let rests = emittedEvents(harness).filter { $0["kind"] as? String == "rest" }
        XCTAssertEqual(rests.count, 1)
        XCTAssertEqual(rests.first?["startedAt"] as? String, utcIso(restStartedAt))
        XCTAssertEqual(rests.first?["endedAt"] as? String, utcIso(endedAt))
        XCTAssertEqual(
            rests.first?["afterEntryId"] as? String,
            timed.entryId,
            "the rest hangs on the timed entry it followed (D-221)"
        )
    }
}
