//
//  WatchMenuEndRunningEffortTests.swift
//  WatchSessionEngineTests
//
//  S-20107 to S-20110 of
//  `docs/plans/2026-11-15-201-watch-flow-fixes-plan/2026-11-15-201-watch-flow-fixes-plan.md`
//  (decision D-20104): the menu's End over the logging surface. An End while an
//  effort clock runs logs that effort first and finishes the session — the
//  status is `completed`, never `abandoned` — while an End on nothing to save
//  still discards: a set-kind exercise has no clock, another slot's phone clock
//  is not this exercise's running effort, and a timed slot whose clock was
//  never started has nothing to log.
//
//  The fixture is `WatchTimedWorkTests`' own S-1311 pattern: the shared
//  `Harness`/`TestClock`, the `sx-run` register slot, and the logging surface
//  handed to `WatchMenuState` as its `logging:`.
//

import XCTest

@testable import WatchSessionEngine

final class WatchMenuEndRunningEffortTests: XCTestCase {

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
        engine: WatchSessionEngine
    ) -> WatchLoggingState {
        WatchLoggingState(
            engine: engine,
            clock: harness.clock.call
        )
    }

    /// A timer object the phone names in a `timer_state`, with the slot when the
    /// case has one.
    private func phoneTimer(
        _ kind: String,
        startedAt: String,
        sessionExerciseId: String? = nil
    ) -> [String: Any] {
        var timer: [String: Any] = [
            "kind": kind,
            "state": WatchTimerState.running,
            "startedAt": startedAt,
            "accumulatedPauseMs": 0,
        ]
        if let sessionExerciseId { timer["sessionExerciseId"] = sessionExerciseId }
        return timer
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

    /// The menu over the session, with the logging surface End reads.
    private func menu(
        _ harness: Harness,
        engine: WatchSessionEngine,
        logging: WatchLoggingState
    ) -> WatchMenuState {
        let preferences = WatchPhonePreferences(
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call
        )
        return WatchMenuState(
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
            ),
            logging: logging
        )
    }

    // MARK: - S-20107 End logs a running effort, then finishes

    func testS20107EndWithARunningEffortLogsItThenFinishes() async throws {
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

        harness.clock.advance(433) // 10:07:13 — unlike every default in the plan
        let endInstant = harness.clock.now

        let menu = menu(harness, engine: engine, logging: surface)
        XCTAssertTrue(menu.hasRunningEffort, "S-20107 a started clock is a running effort")
        XCTAssertFalse(menu.hasLoggedEfforts, "S-20107 nothing is logged yet")
        XCTAssertTrue(menu.hasWorkToSave, "S-20107 the running effort is work to save")

        await menu.finish()

        let timed = engine.entries.filter { $0.kind == WatchObservationKind.timed }
        XCTAssertEqual(timed.count, 1, "S-20107 exactly one timed entry is stored")
        let payload = try XCTUnwrap(timed.first?.payload, "S-20107 the timed entry carries a payload")
        XCTAssertEqual(
            payload["startedAt"] as? String,
            utcIso(startedAt),
            "S-20107 the entry opens where the clock started"
        )
        XCTAssertEqual(
            payload["endedAt"] as? String,
            utcIso(endInstant),
            "S-20107 and closes where End ran"
        )
        XCTAssertEqual(
            engine.session?.status,
            WatchSessionStatus.completed,
            "S-20107 the session finishes, not discards"
        )
    }

    // MARK: - S-20108 a set with nothing logged still discards

    func testS20108ASetExerciseWithNothingLoggedStillDiscards() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-bench", capabilities: ["reps", "sets", "load"])]
        )
        let surface = surface(harness, engine: engine)
        let menu = menu(harness, engine: engine, logging: surface)

        XCTAssertFalse(menu.hasRunningEffort, "S-20108 a set has no clock to run")
        XCTAssertFalse(menu.hasWorkToSave, "S-20108 an untouched set is nothing to save")

        await menu.finish()

        XCTAssertEqual(
            engine.session?.status,
            WatchSessionStatus.abandoned,
            "S-20108 an empty End still discards (S-17109's pin)"
        )
    }

    // MARK: - S-20109 another exercise's phone clock is not this exercise's running effort

    func testS20109AnotherExercisesPhoneClockIsNotThisExercisesRunningEffort() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [
                slot("sx-run", capabilities: ["time", "distance"]),
                slot("sx-bench", capabilities: ["reps", "sets", "load"]),
            ]
        )
        let surface = surface(harness, engine: engine)

        // The phone's clock for `sx-run` arrives while the wrist is on `sx-run`
        // (the S-6004 frame), so it is adopted and stored; the wrist then sits
        // on the set, and the clock stays `sx-run`'s.
        harness.clock.advance(10)
        let phoneStartedAt = harness.clock.now
        _ = try await engine.applyMessage(
            phoneFrame(
                "timer_state",
                sessionId: harness.sessionId,
                messageId: "m-20109",
                sentAt: utcIso(phoneStartedAt),
                payload: [
                    "timers": [
                        WatchTimerKind.elapsed: phoneTimer(
                            WatchTimerKind.elapsed,
                            startedAt: utcIso(phoneStartedAt),
                            sessionExerciseId: "sx-run"
                        )
                    ]
                ]
            )
        )
        await engine.selectExercise(slotId: "sx-bench")

        XCTAssertEqual(
            engine.currentExercise?["sessionExerciseId"] as? String,
            "sx-bench",
            "S-20109 the fixture has the wrist on the set"
        )
        let menu = menu(harness, engine: engine, logging: surface)
        XCTAssertFalse(
            menu.hasRunningEffort,
            "S-20109 the phone's clock for sx-run is not this exercise's running effort"
        )
        XCTAssertFalse(menu.hasWorkToSave, "S-20109 a borrowed clock is nothing to save")

        await menu.finish()

        XCTAssertEqual(
            engine.session?.status,
            WatchSessionStatus.abandoned,
            "S-20109 the session still discards"
        )
    }

    // MARK: - S-20110 a timed exercise whose clock was never started still discards

    func testS20110ATimedExerciseWhoseClockWasNeverStartedStillDiscards() async throws {
        let harness = Harness()
        harness.clock.now = instant("2026-07-13T10:00:00Z")
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let surface = surface(harness, engine: engine)
        let menu = menu(harness, engine: engine, logging: surface)

        XCTAssertFalse(menu.hasRunningEffort, "S-20110 a clock never started runs nothing")
        XCTAssertFalse(menu.hasWorkToSave, "S-20110 an unstarted clock is nothing to save")

        await menu.finish()

        XCTAssertEqual(
            engine.session?.status,
            WatchSessionStatus.abandoned,
            "S-20110 the session discards"
        )
        XCTAssertFalse(
            engine.entries.contains { $0.kind == WatchObservationKind.timed },
            "S-20110 no timed entry is stored"
        )
    }
}
