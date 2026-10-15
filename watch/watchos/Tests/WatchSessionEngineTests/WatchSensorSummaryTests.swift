//
//  WatchSensorSummaryTests.swift
//  WatchSessionEngineTests
//
//  S-231 to S-236 and S-238 of
//  `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`: the
//  heart-rate, steps and pause values the wrist computes from its own readings
//  (D-121 to D-126), read off the events it emits when F-CAP
//  (`watch/contract/watch_capture_contract.json`) is replayed through it, plus
//  the boundary cases of the arithmetic itself.
//

import XCTest

@testable import WatchSessionEngine

final class WatchSensorSummaryTests: XCTestCase {

    /// F-CAP `full`, replayed up to the wrist's End.
    private func fullCase() async throws -> CaptureReplay {
        let replay = try CaptureReplay("full")
        try await replay.run(stoppingBefore: ["answer"])
        return replay
    }

    private func at(_ text: String) -> Date {
        (try? parseUtcIso(text)) ?? Date(timeIntervalSince1970: 0)
    }

    private func sample(
        _ kind: String,
        _ value: Double,
        _ recordedAt: String,
        sequence: Int = 0
    ) -> WatchSensorSampleRecord {
        WatchSensorSampleRecord(
            recordId: "sen-\(kind)-\(recordedAt)",
            sessionId: "s-sum",
            recordedAt: at(recordedAt),
            kind: kind,
            value: value,
            sequence: sequence
        )
    }

    /// A session on `slot`, started at `startedAt`, on an engine whose clock
    /// the test drives.
    private func session(
        _ harness: Harness,
        startedAt: String,
        slot: [String: Any]
    ) async -> WatchSessionEngine {
        harness.clock.now = at(startedAt)
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [slot])
        return engine
    }

    // MARK: - S-231 the run

    func testS231TheRunCarriesItsHeartRateAndStepTotalAndNoPause() async throws {
        let run = try await fullCase().event("e-run")

        XCTAssertEqual(numericValue(run["avgHeartRateBpm"]), 140, "S-231 120, 140 and 160 are in the window")
        XCTAssertEqual(numericValue(run["maxHeartRateBpm"]), 160, "S-231 the largest reading in the window")
        XCTAssertEqual(
            numericValue(run["steps"]),
            3200,
            "S-231 the chain 0 → 800 → 1600 → 3200; the 3300 at 10:30 is outside the window"
        )
        XCTAssertNil(run["pausedMs"], "S-231 a timed entry carries no pause")
    }

    // MARK: - S-232 the rounds

    func testS232EachRoundIsSummarisedOverItsOwnActiveWindow() async throws {
        let replay = try await fullCase()
        let first = try replay.event("e-r1")
        let second = try replay.event("e-r2")
        let third = try replay.event("e-r3")

        XCTAssertEqual(numericValue(first["avgHeartRateBpm"]), 160, "S-232 e-r1: 150 and 170")
        XCTAssertEqual(numericValue(first["maxHeartRateBpm"]), 170, "S-232 e-r1")
        XCTAssertNil(first["pausedMs"], "S-232 e-r1 ran on no countdown, so it was never paused")

        XCTAssertEqual(
            numericValue(second["avgHeartRateBpm"]),
            165,
            "S-232 e-r2: 150 and 180 — the 100 at 10:33 lies in the pause [10:32, 10:34), "
                + "and counting it would give 143.33"
        )
        XCTAssertEqual(numericValue(second["maxHeartRateBpm"]), 180, "S-232 e-r2")
        XCTAssertEqual(numericValue(second["pausedMs"]), 120_000, "S-232 e-r2 was paused for two minutes")

        XCTAssertEqual(
            numericValue(third["avgHeartRateBpm"]),
            155,
            "S-232 e-r3: 145 at its start (inclusive) and 165; the 175 at 10:42:08 is after its end"
        )
        XCTAssertEqual(numericValue(third["maxHeartRateBpm"]), 165, "S-232 e-r3")
        XCTAssertNil(third["pausedMs"], "S-232 e-r3 was never paused")

        for round in [first, second, third] {
            XCTAssertNil(
                round["steps"],
                "S-232 no round carries steps, though the 10:30 count lies inside e-r1's and e-r2's windows"
            )
        }
    }

    // MARK: - S-233 the set block

    func testS233TheSessionEndCarriesTheSetBlockAndTheSetsCarryNothing() async throws {
        let replay = try await fullCase()
        let end = try replay.event("end-s-cap-1")
        let blocks = try XCTUnwrap(end["setBlockHeartRates"] as? [[String: Any]], "S-233 no set blocks")

        XCTAssertEqual(blocks.count, 1, "S-233 one slot and exercise was set-logged")
        let block = try XCTUnwrap(blocks.first)
        XCTAssertEqual(block["sessionExerciseId"] as? String, "sx-bench", "S-233")
        XCTAssertEqual(block["exerciseId"] as? String, "ex-bench", "S-233")
        XCTAssertEqual(
            block["startedAt"] as? String,
            "2026-09-25T10:42:10.000Z",
            "S-233 the span starts at the last effort before the first set: e-r3"
        )
        XCTAssertEqual(block["endedAt"] as? String, "2026-09-25T10:51:00.000Z", "S-233 the last set")
        XCTAssertEqual(
            numericValue(block["avgHeartRateBpm"]),
            130,
            "S-233 110, 130 and 150; the 175 at 10:42:08 is before the span and the 0 is ignored"
        )
        XCTAssertEqual(numericValue(block["maxHeartRateBpm"]), 150, "S-233")

        for entryId in ["e-set1", "e-set2", "e-set3"] {
            let set = try replay.event(entryId)
            XCTAssertNil(set["avgHeartRateBpm"], "S-233 a set never carries heart rate")
            XCTAssertNil(set["maxHeartRateBpm"], "S-233 a set never carries heart rate")
        }
    }

    // MARK: - S-234 the session

    func testS234TheSessionEndCoversTheWholeSession() async throws {
        let end = try await fullCase().event("end-s-cap-1")

        XCTAssertEqual(end["status"] as? String, "completed", "S-234")
        XCTAssertEqual(end["startedAt"] as? String, "2026-09-25T10:00:00.000Z", "S-234 the session's start")
        XCTAssertEqual(end["endedAt"] as? String, "2026-09-25T10:55:00.000Z", "S-234 the wrist's End")
        XCTAssertEqual(
            numericValue(end["avgHeartRateBpm"]),
            143,
            "S-234 fifteen positive readings summing to 2145; a round's pause is not a session pause"
        )
        XCTAssertEqual(numericValue(end["maxHeartRateBpm"]), 180, "S-234")
        XCTAssertNil(end["modality"], "S-234 a wrist session carries no modality today (F-7)")
    }

    func testS234APhoneEndedSessionIsSummarisedUpToWhenThePhoneEndedIt() async throws {
        let harness = Harness()
        let engine = await session(harness, startedAt: "2026-09-25T10:00:00Z", slot: exercise("sx-bench"))
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 130, recordedAt: at("2026-09-25T10:18:00Z"))
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 200, recordedAt: at("2026-09-25T10:22:00Z"))

        harness.clock.now = at("2026-09-25T10:25:00Z")
        _ = try await engine.applyMessage([
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-phone-ends",
            "sessionId": harness.sessionId,
            "type": "session_lifecycle",
            "origin": "phone",
            "sentAt": "2026-09-25T10:25:00Z",
            "payload": ["state": "completed", "at": "2026-09-25T10:20:00Z"],
        ])

        let end = try XCTUnwrap(
            engine.observations.first { $0.kind == WatchObservationKind.sessionEnd }?.payload,
            "S-234 the phone's completion ends the wrist's session"
        )
        XCTAssertEqual(end["endedAt"] as? String, "2026-09-25T10:20:00.000Z", "S-234 the lifecycle's own `at`")
        XCTAssertEqual(end["loggedAt"] as? String, "2026-09-25T10:25:00.000Z", "S-234 when the wrist appended it")
        XCTAssertEqual(numericValue(end["avgHeartRateBpm"]), 130, "S-234 the 200 at 10:22 is after the end")
        XCTAssertEqual(numericValue(end["maxHeartRateBpm"]), 130, "S-234")
    }

    // MARK: - S-235 nothing measured, nothing sent

    func testS235WithTheSensorsDeniedNoEventCarriesASummary() async throws {
        let replay = try CaptureReplay("no-sensors")
        try await replay.run(stoppingBefore: ["answer"])

        let summaryFields = ["avgHeartRateBpm", "maxHeartRateBpm", "steps", "setBlockHeartRates"]
        XCTAssertFalse(replay.emittedEvents.isEmpty, "S-235 the session was logged")
        for event in replay.emittedEvents {
            for field in summaryFields {
                XCTAssertNil(
                    event[field],
                    "S-235 \(event["entryId"] as? String ?? "?") carries \(field) with nothing measured"
                )
            }
        }
        XCTAssertEqual(
            numericValue(try replay.event("e-r2")["pausedMs"]),
            120_000,
            "S-235 a round's pause is the countdown's, not a sensor's"
        )
    }

    func testS235HeartRateWithoutAStepCountSendsNoStepTotal() async throws {
        let harness = Harness()
        let engine = await session(
            harness,
            startedAt: "2026-09-25T10:00:00Z",
            slot: ["sessionExerciseId": "sx-run", "exerciseId": "ex-run", "name": "Run", "capabilities": ["time", "distance"]]
        )
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 140, recordedAt: at("2026-09-25T10:05:00Z"))

        // The window is the work clock's, not a dialled length: Start at the
        // instant the old dial implied (10:10 minus 120 detents of 5 s), and
        // the log instant is unchanged.
        harness.clock.now = at("2026-09-25T10:04:00Z")
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)
        await surface.startWork()
        harness.clock.now = at("2026-09-25T10:10:00Z")
        let run = try await surface.log().payload

        XCTAssertEqual(numericValue(run["avgHeartRateBpm"]), 140, "S-235 the heart rate was measured")
        XCTAssertNil(run["steps"], "S-235 no count was sampled, so there is no step total — not a zero")
    }

    func testS235AStepCountThatDidNotMoveIsAMeasuredZero() async throws {
        let harness = Harness()
        let engine = await session(
            harness,
            startedAt: "2026-09-25T10:00:00Z",
            slot: ["sessionExerciseId": "sx-run", "exerciseId": "ex-run", "name": "Run", "capabilities": ["time", "distance"]]
        )
        await engine.appendSensorSample(kind: WatchSensorKind.steps, value: 500, recordedAt: at("2026-09-25T10:01:00Z"))
        await engine.appendSensorSample(kind: WatchSensorKind.steps, value: 500, recordedAt: at("2026-09-25T10:08:00Z"))

        // Start opens the same 8-minute window from 10:02 the dial used to.
        harness.clock.now = at("2026-09-25T10:02:00Z")
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)
        await surface.startWork()
        harness.clock.now = at("2026-09-25T10:10:00Z")
        let run = try await surface.log().payload

        XCTAssertEqual(
            numericValue(run["steps"]),
            0,
            "S-235 the only count in the window equals the baseline before it: a measured zero is sent"
        )
        XCTAssertNil(run["avgHeartRateBpm"], "S-235 no heart rate was measured")
    }

    // MARK: - S-236 a hold

    func testS236AHoldIsSummarisedOverItsOwnWindow() async throws {
        let harness = Harness()
        let engine = await session(
            harness,
            startedAt: "2026-09-25T10:55:00Z",
            slot: ["sessionExerciseId": "sx-plank", "exerciseId": "ex-plank", "name": "Plank", "capabilities": ["time", "hold"]]
        )
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 125, recordedAt: at("2026-09-25T11:00:30Z"))
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 135, recordedAt: at("2026-09-25T11:01:00Z"))
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 200, recordedAt: at("2026-09-25T11:01:30Z"))

        // The hold's own clock: Start at 11:00, the window's opening instant
        // the 12-detent dial used to imply, and Log at the same 11:01.
        harness.clock.now = at("2026-09-25T11:00:00Z")
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)
        XCTAssertEqual(surface.effortKind, WatchEffortKind.drill)
        await surface.startWork()
        harness.clock.now = at("2026-09-25T11:01:00Z")
        let hold = try await surface.log().payload

        XCTAssertEqual(hold["kind"] as? String, "hold")
        XCTAssertEqual(hold["startedAt"] as? String, "2026-09-25T11:00:00.000Z")
        XCTAssertEqual(numericValue(hold["avgHeartRateBpm"]), 130, "S-236 125 and 135 (its end, inclusive)")
        XCTAssertEqual(numericValue(hold["maxHeartRateBpm"]), 135, "S-236 the 200 at 11:01:30 is after the hold")
        XCTAssertNil(hold["steps"], "S-236 a hold carries no steps")
    }

    // MARK: - S-238 never rewritten

    func testS238ALateReadingNeverRewritesWhatWasSent() async throws {
        let replay = try await fullCase()
        await replay.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: 200,
            recordedAt: at("2026-09-25T10:19:59Z")
        )

        await replay.relaunch()
        let pending = replay.engine.pendingObservations().compactMap {
            (($0["payload"] as? [String: Any])?["events"] as? [[String: Any]])?.first
        }

        let run = try XCTUnwrap(pending.first { $0["entryId"] as? String == "e-run" })
        XCTAssertEqual(numericValue(run["avgHeartRateBpm"]), 140, "S-238 e-run is re-sent as it was logged")
        XCTAssertEqual(numericValue(run["maxHeartRateBpm"]), 160, "S-238 the 200 at 10:19:59 arrived too late")

        let end = try XCTUnwrap(pending.first { $0["entryId"] as? String == "end-s-cap-1" })
        XCTAssertEqual(numericValue(end["avgHeartRateBpm"]), 143, "S-238 the session end is not recomputed")
        XCTAssertEqual(numericValue(end["maxHeartRateBpm"]), 180, "S-238 the session end is not recomputed")
        XCTAssertEqual(
            pending.filter { $0["kind"] as? String == WatchObservationKind.sessionEnd }.count,
            1,
            "S-238 one session end, however many launches"
        )
    }

    // MARK: - Pauses are half-open (D-122 b, c)

    func testAPauseExcludesTheInstantItBeganButNotTheInstantItEnded() {
        let samples = [
            sample(WatchSensorKind.heartRate, 100, "2026-09-25T10:00:00Z"),
            sample(WatchSensorKind.heartRate, 250, "2026-09-25T10:01:00Z"),
            sample(WatchSensorKind.heartRate, 300, "2026-09-25T10:02:00Z"),
        ]
        let pause = WatchPauseInterval(start: at("2026-09-25T10:01:00Z"), end: at("2026-09-25T10:02:00Z"))

        let pair = WatchSensorSummaries.heartRate(
            samples,
            from: at("2026-09-25T10:00:00Z"),
            through: at("2026-09-25T10:03:00Z"),
            excluding: [pause]
        )

        XCTAssertEqual(
            pair,
            WatchHeartRateSummary(averageBpm: 200, maximumBpm: 300),
            "D-122 b: the pause's first instant is paused, the instant it resumed is not"
        )
    }

    func testAPauseReadFromTheTimersRowsEndsWhereThatTimerRanAgain() {
        let startedAt = at("2026-09-25T10:30:00Z")
        func row(
            _ id: String,
            _ sequence: Int,
            recordedAt: String,
            startedAt: Date = startedAt,
            pausedAt: String? = nil,
            stoppedAt: String? = nil
        ) -> WatchTimerRecord {
            WatchTimerRecord(
                recordId: id,
                sessionId: "s-sum",
                recordedAt: at(recordedAt),
                kind: WatchTimerKind.round,
                startedAt: startedAt,
                pausedAt: pausedAt.map(at),
                stoppedAt: stoppedAt.map(at),
                plannedDurationMs: 300_000,
                sequence: sequence
            )
        }
        let windowEnd = at("2026-09-25T10:40:00Z")

        let resumed = WatchSensorSummaries.pauses(
            of: [
                row("t-1", 1, recordedAt: "2026-09-25T10:30:00Z"),
                row("t-2", 2, recordedAt: "2026-09-25T10:32:00Z", pausedAt: "2026-09-25T10:32:00Z"),
                row("t-3", 3, recordedAt: "2026-09-25T10:34:00Z"),
                // Another timer altogether: a different start.
                row("t-4", 4, recordedAt: "2026-09-25T10:35:00Z",
                    startedAt: at("2026-09-25T10:35:00Z"), pausedAt: "2026-09-25T10:35:00Z"),
            ],
            startedAt: startedAt,
            windowEnd: windowEnd
        )
        XCTAssertEqual(
            resumed,
            [WatchPauseInterval(start: at("2026-09-25T10:32:00Z"), end: at("2026-09-25T10:34:00Z"))],
            "D-122 c: the pause ends at the first later row of that timer without a pause"
        )

        let stopped = WatchSensorSummaries.pauses(
            of: [
                row("t-1", 1, recordedAt: "2026-09-25T10:30:00Z"),
                row("t-2", 2, recordedAt: "2026-09-25T10:33:00Z",
                    pausedAt: "2026-09-25T10:33:00Z", stoppedAt: "2026-09-25T10:36:00Z"),
            ],
            startedAt: startedAt,
            windowEnd: windowEnd
        )
        XCTAssertEqual(
            stopped,
            [WatchPauseInterval(start: at("2026-09-25T10:33:00Z"), end: at("2026-09-25T10:36:00Z"))],
            "D-122 c: a pause that never resumed ends where its timer stopped"
        )

        let open = WatchSensorSummaries.pauses(
            of: [
                row("t-1", 1, recordedAt: "2026-09-25T10:30:00Z"),
                row("t-2", 2, recordedAt: "2026-09-25T10:38:00Z", pausedAt: "2026-09-25T10:38:00Z"),
            ],
            startedAt: startedAt,
            windowEnd: windowEnd
        )
        XCTAssertEqual(
            open,
            [WatchPauseInterval(start: at("2026-09-25T10:38:00Z"), end: windowEnd)],
            "D-122 c: a pause still open runs to the window's end"
        )
    }

    // MARK: - A round's pause on the wire (D-126)

    func testARoundsPauseCountsOnlyWhatFallsInsideItsWindow() {
        let startedAt = at("2026-09-25T10:30:00Z")
        func countdown(accumulatedMs: Int, pausedAt: String?) -> WatchTimerRecord {
            WatchTimerRecord(
                recordId: "t-round",
                sessionId: "s-sum",
                recordedAt: startedAt,
                kind: WatchTimerKind.round,
                startedAt: startedAt,
                pausedAt: pausedAt.map(at),
                accumulatedPauseMs: accumulatedMs,
                plannedDurationMs: 300_000
            )
        }

        XCTAssertEqual(
            WatchSensorSummaries.pausedMs(
                countdown(accumulatedMs: 60_000, pausedAt: "2026-09-25T10:33:00Z"),
                windowStart: startedAt,
                windowEnd: at("2026-09-25T10:34:00Z")
            ),
            120_000,
            "D-126: the accumulated pause plus the pause still open at the window's end"
        )
        XCTAssertEqual(
            WatchSensorSummaries.pausedMs(
                countdown(accumulatedMs: 60_000, pausedAt: "2026-09-25T10:40:00Z"),
                windowStart: startedAt,
                windowEnd: at("2026-09-25T10:36:00Z")
            ),
            60_000,
            "a countdown paused after it had run out paused nothing the round contains"
        )
        XCTAssertEqual(
            WatchSensorSummaries.pausedMs(
                countdown(accumulatedMs: 400_000, pausedAt: nil),
                windowStart: startedAt,
                windowEnd: at("2026-09-25T10:35:00Z")
            ),
            300_000,
            "never longer than the window: the protocol refuses a longer pause, and a refused event is a refused log"
        )
    }

    // MARK: - Glitches never make an event unsendable

    func testAReadingBelowOneBeatPerMinuteIsNotAHeartRate() {
        let window = (at("2026-09-25T10:00:00Z"), at("2026-09-25T10:10:00Z"))
        let glitches = [
            sample(WatchSensorKind.heartRate, 0, "2026-09-25T10:01:00Z"),
            sample(WatchSensorKind.heartRate, 0.5, "2026-09-25T10:02:00Z"),
            sample(WatchSensorKind.heartRate, -40, "2026-09-25T10:03:00Z"),
            sample(WatchSensorKind.heartRate, .nan, "2026-09-25T10:04:00Z"),
        ]

        XCTAssertNil(
            WatchSensorSummaries.heartRate(glitches, from: window.0, through: window.1),
            "the protocol's minimum is 1 bpm: a pair built from these could not be sent"
        )
        XCTAssertEqual(
            WatchSensorSummaries.heartRate(
                glitches + [sample(WatchSensorKind.heartRate, 120, "2026-09-25T10:05:00Z")],
                from: window.0,
                through: window.1
            ),
            WatchHeartRateSummary(averageBpm: 120, maximumBpm: 120)
        )
    }

    func testAnAverageOfEqualReadingsNeverExceedsItsMaximum() throws {
        // Three readings of 60.2 sum, in binary floating point, to a mean of
        // 60.20000000000001 — past the maximum it is the mean of.
        let readings = (0..<3).map {
            sample(WatchSensorKind.heartRate, 60.2, "2026-09-25T10:0\($0):00Z", sequence: $0)
        }
        let pair = try XCTUnwrap(
            WatchSensorSummaries.heartRate(
                readings,
                from: at("2026-09-25T10:00:00Z"),
                through: at("2026-09-25T10:10:00Z")
            )
        )

        XCTAssertLessThanOrEqual(
            pair.averageBpm,
            pair.maximumBpm,
            "the validator refuses an average above its maximum, and a refused event is a refused log"
        )
        XCTAssertEqual(pair.averageBpm, 60.2, "the mean of equal readings is the reading")
    }

    func testAStepCounterThatRestartedAddsItsNewCount() {
        let counts = [
            sample(WatchSensorKind.steps, 1000, "2026-09-25T09:59:00Z", sequence: 1),
            sample(WatchSensorKind.steps, 1200, "2026-09-25T10:01:00Z", sequence: 2),
            sample(WatchSensorKind.steps, 300, "2026-09-25T10:02:00Z", sequence: 3),
            sample(WatchSensorKind.steps, 500, "2026-09-25T10:03:00Z", sequence: 4),
            sample(WatchSensorKind.steps, -20, "2026-09-25T10:04:00Z", sequence: 5),
        ]

        XCTAssertEqual(
            WatchSensorSummaries.steps(
                counts,
                from: at("2026-09-25T10:00:00Z"),
                through: at("2026-09-25T10:05:00Z")
            ),
            700,
            "D-125: 1000 → 1200 adds 200, the restart adds 300, 300 → 500 adds 200; a negative count is not a count"
        )
    }

    // MARK: - Set blocks (D-123)

    func testSetBlocksAreSpannedFromTheEffortBeforeTheirFirstSet() {
        func set(_ id: String, _ slot: String, _ loggedAt: String) -> [String: Any] {
            ["entryId": id, "kind": "set", "loggedAt": loggedAt, "sessionExerciseId": slot, "exerciseId": "ex-\(slot)"]
        }
        let entries: [[String: Any]] = [
            set("e-a1", "sx-a", "2026-09-25T10:05:00.000Z"),
            set("e-b1", "sx-b", "2026-09-25T10:06:00.000Z"),
            set("e-a2", "sx-a", "2026-09-25T10:07:00.000Z"),
            set("e-b2", "sx-b", "2026-09-25T10:08:00.000Z"),
            ["entryId": "rating-x", "kind": "effort_rating", "loggedAt": "2026-09-25T10:04:00.000Z", "rating": 3],
        ]

        let spans = WatchSensorSummaries.blockSpans(entries, sessionStartedAt: at("2026-09-25T10:00:00Z"))

        XCTAssertEqual(
            spans,
            [
                WatchSetBlockSpan(
                    sessionExerciseId: "sx-a",
                    exerciseId: "ex-sx-a",
                    startedAt: at("2026-09-25T10:00:00Z"),
                    endedAt: at("2026-09-25T10:07:00Z")
                ),
                WatchSetBlockSpan(
                    sessionExerciseId: "sx-b",
                    exerciseId: "ex-sx-b",
                    startedAt: at("2026-09-25T10:05:00Z"),
                    endedAt: at("2026-09-25T10:08:00Z")
                ),
            ],
            "D-123: nothing before the first block, so it starts with the session; a superset's blocks overlap; "
                + "a session-scoped entry is not an effort"
        )
    }
}
