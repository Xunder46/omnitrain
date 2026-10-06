//
//  WatchLoggingSurfacesTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`
//  — the same scenarios the Flutter client proves in
//  `test/watch_logging_surfaces_test.dart`, run against the Swift logging
//  state.
//
//  Scenario mapping:
//    S-001 log a set (reps + load)                       → `testS001...`
//    S-002 log timed work (duration, optional distance)  → `testS002...`
//    S-003 log a round                                   → `testS003...`
//    S-004 log a hold / drill                            → `testS004...`
//    S-006 manual distance entry without GPS             → `testS006...`
//    S-007 metric stepping                               → WatchLoggingTimersTests
//    S-008 terminology parity with the phone             → `testS008...`
//    S-062 zero still means "no load claim"              → `testS062...`
//    S-063 the assist carries to the next set            → `testS063...`
//    S-064 a leading minus renders in the user's unit    → `testS064...`
//
//  Every event asserted here is validated against the shared protocol schemas
//  read from the repository — the same documents the phone's validator and the
//  Flutter suite use — so "identical in shape to a phone-logged equivalent" is
//  the schema's verdict, not this file's opinion.
//

import XCTest

@testable import WatchSessionEngine

final class WatchLoggingSurfacesTests: XCTestCase {

    /// A slot carrying the capabilities the surface derives its effort kind
    /// from. The shared `exercise(_:)` helper is weighted for the engine tests
    /// (reps/sets/load); a logging surface needs to vary them.
    private func slot(
        _ id: String,
        capabilities: [String] = ["reps", "sets", "load"]
    ) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
    }

    /// The event the surface logged last, plus the schema's verdict on the
    /// message that carried it. Timer messages are skipped: an effort kind that
    /// starts a countdown emits one of those too.
    private func loggedEvent(
        _ harness: Harness
    ) throws -> (event: [String: Any], rejections: [SyncProtocolRejection]) {
        let envelope = try XCTUnwrap(
            harness.emitted.last(where: { $0["type"] as? String == "observations_up" })
        )
        XCTAssertEqual(envelope["origin"] as? String, "watch")

        let events = (envelope["payload"] as? [String: Any])?["events"] as? [[String: Any]]
        let event = try XCTUnwrap(events?.first)
        return (event, Harness.validator().validateEnvelope(envelope))
    }

    private func value(_ state: WatchLoggingState, _ metricKey: String) -> Double? {
        state.fields.first(where: { $0.metricKey == metricKey })?.value
    }

    private func field(_ state: WatchLoggingState, _ metricKey: String) -> WatchMetricField {
        state.fields.first(where: { $0.metricKey == metricKey })!
    }

    // MARK: - S-001 log a set (reps + load)

    func testS001RotaryValuesAreLoggedAsAProtocolSetObservation() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-bench")]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        // The whole logging interaction: turn the crown, confirm. Load starts at
        // the effort-kind default (0 kg) and is dialled up in 2.5 kg detents.
        surface.adjust(WatchMetricKey.reps, detents: 2)
        surface.adjust(WatchMetricKey.weight, detents: 33)
        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["kind"] as? String, "set")
        XCTAssertEqual(logged.event["reps"] as? Int, 12)
        XCTAssertEqual(logged.event["loadKg"] as? Double, 82.5)
        XCTAssertEqual(logged.event["sessionExerciseId"] as? String, "sx-bench")
        XCTAssertEqual(logged.event["exerciseId"] as? String, "ex-sx-bench")
        XCTAssertEqual(logged.event["loggedAt"] as? String, utcIso(harness.clock.now))
        XCTAssertEqual(logged.event["eventId"] as? String, logged.event["entryId"] as? String)
    }

    func testS001TheNextSetCarriesOverTheValuesJustLogged() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-bench")]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        surface.adjust(WatchMetricKey.reps, detents: 2)
        surface.adjust(WatchMetricKey.weight, detents: 33)
        try await surface.log()

        XCTAssertEqual(value(surface, WatchMetricKey.reps), 12)
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 82.5)
    }

    func testS001ABodyweightSetCarriesNoLoadAtAll() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-pushup", capabilities: ["reps", "sets"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.fields.map(\.metricKey), [WatchMetricKey.reps])
        XCTAssertEqual(value(surface, WatchMetricKey.reps), 10)

        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertNil(logged.event["loadKg"])
    }

    // MARK: - S-062 zero still means "no load claim"

    func testS062AnAssistedLoadIsEmittedWithItsSign() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-assisted")]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        // Eight detents down from the 0 kg default: a 20 kg band assist.
        surface.adjust(WatchMetricKey.weight, detents: -8)
        XCTAssertEqual(value(surface, WatchMetricKey.weight), -20)

        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["loadKg"] as? Double, -20)
    }

    func testS062AnUntouchedLoadDialSendsNoLoadKg() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-bench")]
        )

        try await WatchLoggingState(engine: engine, clock: harness.clock.call).log()

        XCTAssertNil(try loggedEvent(harness).event["loadKg"])
    }

    func testS062ADrillSendsItsExtraLoadAndNeverALoadKg() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "isometric_stretching",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        surface.adjust(WatchMetricKey.extraWeight, detents: -4)
        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["extraLoadKg"] as? Double, -10)
        XCTAssertNil(logged.event["loadKg"])
    }

    // MARK: - S-063 the assist carries to the next set

    func testS063TheNextSetCarriesTheAssist() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-assisted")]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        surface.adjust(WatchMetricKey.weight, detents: -8)
        try await surface.log()

        // The carry-over reads the stored `loadKg` back, sign and all; it must
        // not fall back to zero.
        XCTAssertEqual(value(surface, WatchMetricKey.weight), -20)
    }

    // MARK: - S-064 a leading minus renders in the user's unit

    func testS064ANegativeLoadPrintsALeadingMinusInKgAndLbs() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-assisted")]
        )
        let kg = WatchLoggingState(engine: engine, clock: harness.clock.call)
        kg.adjust(WatchMetricKey.weight, detents: -8)
        XCTAssertEqual(field(kg, WatchMetricKey.weight).displayValue, "-20.0")
        XCTAssertEqual(field(kg, WatchMetricKey.weight).unitLabel, "kg")

        let pounds = WatchUnitPreferences(weightUnit: "lbs")
        let lbs = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            units: pounds
        )
        let step = WatchMetricStepping.step(for: WatchMetricKey.weight, units: pounds)
        // Dial to exactly -20 kg, so the same load prints in the saved unit.
        lbs.adjust(WatchMetricKey.weight, detents: -20 / step)
        XCTAssertEqual(value(lbs, WatchMetricKey.weight), -20)
        XCTAssertEqual(field(lbs, WatchMetricKey.weight).displayValue, "-44.1")
        XCTAssertEqual(field(lbs, WatchMetricKey.weight).unitLabel, "lbs")
    }

    func testS064AZeroLoadNeverPrintsASignedZero() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [slot("sx-assisted")]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        // A fractional detent that rounds to zero must not leave a "-0.0"
        // behind: zero is zero.
        surface.adjust(WatchMetricKey.weight, detents: -0.0001)
        XCTAssertEqual(field(surface, WatchMetricKey.weight).displayValue, "0.0")
    }

    // MARK: - S-002 log timed work (duration, optional distance)

    func testS002DurationIsLoggedAsTheWindowThatEndedAtTheLog() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.effortKind, WatchEffortKind.timed)
        surface.adjust(WatchMetricKey.duration, detents: 60)
        XCTAssertEqual(value(surface, WatchMetricKey.duration), 300)

        harness.clock.advance(360)
        let loggedAt = harness.clock.now
        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["kind"] as? String, "timed")
        XCTAssertEqual(
            logged.event["startedAt"] as? String,
            utcIso(loggedAt.addingTimeInterval(-300))
        )
        XCTAssertEqual(logged.event["endedAt"] as? String, utcIso(loggedAt))
    }

    func testS002TheNextEffortPresentsAFreshDuration() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        surface.adjust(WatchMetricKey.duration, detents: 60)
        surface.adjust(WatchMetricKey.distance, detents: 5)
        try await surface.log()

        XCTAssertEqual(value(surface, WatchMetricKey.duration), 0)
        XCTAssertEqual(value(surface, WatchMetricKey.distance), 0)
    }

    func testS002AnExerciseThatCannotCoverDistanceOffersNoDistance() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-row", capabilities: ["time"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.fields.map(\.metricKey), [WatchMetricKey.duration])
    }

    // MARK: - S-003 log a round

    func testS003TheRoundCarriesTheTerminologyThePhoneUses() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-period", capabilities: ["time", "rounds"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.effortKind, WatchEffortKind.round)
        XCTAssertEqual(surface.roundsLabel, "Periods")
    }

    func testS003LoggingARoundNumbersItAndStartsTheNextCountdown() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-period", capabilities: ["time", "rounds"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.nextRoundNumber, 1)
        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["kind"] as? String, "round")
        XCTAssertEqual(logged.event["roundNumber"] as? Int, 1)

        XCTAssertEqual(surface.nextRoundNumber, 2)
        let countdown = try XCTUnwrap(engine.timerFor(WatchTimerKind.round))
        XCTAssertEqual(countdown.plannedDurationMs, 180_000)
    }

    func testS003ARoundThatRanItsCountdownEndsWhereTheCountdownDid() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "sports",
            exercises: [slot("sx-period", capabilities: ["time", "rounds"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        try await surface.log()
        let countdown = try XCTUnwrap(engine.timerFor(WatchTimerKind.round))
        let roundEnd = try XCTUnwrap(completionInstant(countdown))

        // The user looks down twenty seconds after the round is over.
        harness.clock.advance(200)
        try await surface.log()

        let second = try loggedEvent(harness).event
        XCTAssertEqual(second["roundNumber"] as? Int, 2)
        XCTAssertEqual(
            second["endedAt"] as? String,
            utcIso(roundEnd),
            "the round ended when its countdown did, not when it was seen"
        )
        XCTAssertEqual(
            second["startedAt"] as? String,
            utcIso(countdown.startedAt),
            "round two is the countdown's own window"
        )
    }

    // MARK: - S-004 log a hold / drill

    func testS004HoldDurationAndExtraLoadAreLoggedTogether() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "isometric_stretching",
            exercises: [slot("sx-plank", capabilities: ["hold", "time"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.effortKind, WatchEffortKind.drill)
        surface.adjust(WatchMetricKey.duration, detents: 12)
        surface.adjust(WatchMetricKey.extraWeight, detents: -4)

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

    // MARK: - S-006 manual distance entry without GPS

    func testS006AManualDistanceReachesTheObservationWithNoFixNeeded() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-ride", capabilities: ["time", "distance"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        surface.adjust(WatchMetricKey.duration, detents: 120)
        surface.adjust(WatchMetricKey.distance, detents: 4)
        try await surface.log()

        let logged = try loggedEvent(harness)
        XCTAssertTrue(logged.rejections.isEmpty, "\(logged.rejections)")
        XCTAssertEqual(logged.event["distanceMeters"] as? Double, 400)
    }

    // MARK: - S-008 terminology parity with the phone

    func testS008EveryModalityKeepsThePhonesRoundTermOnTheWrist() async throws {
        // The shared contract carries the phone's `ModalityDisplay.getRoundsLabel`
        // output, and the Flutter suite asserts its own helper against the same
        // entries. Two clients, one vocabulary.
        let labels = try XCTUnwrap(
            (try Fixtures.loggingContract())["roundsLabels"] as? [[String: Any]]
        )
        XCTAssertFalse(labels.isEmpty)

        for entry in labels {
            let modality = entry["modality"] as? String
            let term = try XCTUnwrap(entry["label"] as? String)
            let harness = Harness()
            let engine = await harness.runningEngine()
            _ = await engine.createSession(
                modality: modality,
                exercises: [slot("sx-round", capabilities: ["time", "rounds"])]
            )
            let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

            XCTAssertEqual(
                surface.roundsLabel,
                term,
                "\(modality ?? "free training") must read the same on the wrist"
            )
        }
    }

    func testTheFirstCapabilityPresentDecidesTheEffortKind() async throws {
        let contract = try Fixtures.loggingContract()
        let precedence = try XCTUnwrap(contract["capabilityPrecedence"] as? [String])
        let kinds = try XCTUnwrap(contract["effortKindByMetric"] as? [String: String])

        // Each capability in turn, leading a slot that carries every one after
        // it: the leading capability is the one that must win.
        for start in precedence.indices {
            let capabilities = Array(precedence[start...])
            let harness = Harness()
            let engine = await harness.runningEngine()
            _ = await engine.createSession(
                modality: "resistance_lifting",
                exercises: [slot("sx-\(start)", capabilities: capabilities)]
            )
            let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

            XCTAssertEqual(
                surface.effortKind,
                kinds[precedence[start]],
                "\(capabilities) should be led by \(precedence[start])"
            )
        }
    }

    func testS008FreeTrainingFallsBackToASetSurface() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: [slot("sx-free", capabilities: ["reps", "load"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.effortKind, WatchEffortKind.set)
        XCTAssertEqual(surface.roundsLabel, "Rounds")
    }

    // MARK: - Surfaces refuse what they cannot log

    func testNoSessionMeansNothingToLog() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertFalse(surface.canLog)
        XCTAssertTrue(surface.fields.isEmpty)
        do {
            try await surface.log()
            XCTFail("a surface with no exercise must not log")
        } catch is WatchRecordError {
            // Expected: nothing to log against.
        }
    }

    // MARK: - S-029 nothing logs into a session that is over

    func testS029AnEndedSessionCannotBeLoggedInto() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: [slot("sx-free", capabilities: ["reps", "load"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        try await surface.log()
        _ = await engine.finishSession()
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed)

        // The count after the end includes the `session_end` row the engine
        // appends; the refused log must add nothing to it.
        let afterEnd = engine.observations.count

        XCTAssertFalse(surface.canLog, "a finished session is not a surface to log into")
        XCTAssertTrue(surface.fields.isEmpty)

        do {
            try await surface.log()
            XCTFail("logging into a finished session must throw")
        } catch is WatchRecordError {
            // Expected: the session is over, so there is nothing to log against.
        }
        XCTAssertEqual(
            engine.observations.count,
            afterEnd,
            "the refused log appended no observation row"
        )
    }

    // MARK: - S-29a the phone's own end closes the wrist's surface

    func testS029aAPhoneCompletionClosesTheLoggingSurface() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: [slot("sx-free", capabilities: ["reps", "load"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        try await surface.log()
        let sessionId = try XCTUnwrap(engine.session?.sessionId)

        harness.clock.advance(60)
        _ = try await engine.applyMessage(
            phoneLifecycle("completed", sessionId: sessionId, at: "2026-07-13T06:01:00Z")
        )
        XCTAssertEqual(engine.session?.status, WatchSessionStatus.completed)

        // The count after the end includes the `session_end` row the engine
        // appends; the refused log must add nothing to it.
        let afterEnd = engine.observations.count

        XCTAssertFalse(
            surface.canLog,
            "S-29a a session the phone ended is not a surface to log into"
        )
        XCTAssertTrue(surface.fields.isEmpty)

        do {
            try await surface.log()
            XCTFail("logging into a phone-ended session must throw")
        } catch is WatchRecordError {
            // Expected: the session is over, so there is nothing to log against.
        }
        XCTAssertEqual(
            engine.observations.count,
            afterEnd,
            "the refused log appended no observation row"
        )
    }

    // MARK: - Shared fixtures

    func testEveryValidObservationsEventIsReproducedByTheSurfaceShape() async throws {
        // The surface's own output must sit in the same shape as the fixture
        // the phone's validator accepts: same field names, same value types.
        let fixture = try Fixtures.json("fixtures/valid/observations_up_distance_and_load.json")
        let events = (fixture["payload"] as? [String: Any])?["events"] as? [[String: Any]] ?? []
        XCTAssertFalse(events.isEmpty)

        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-ride", capabilities: ["time", "distance"])]
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)
        surface.adjust(WatchMetricKey.duration, detents: 120)
        surface.adjust(WatchMetricKey.distance, detents: 24)
        try await surface.log()

        let logged = try loggedEvent(harness)
        let fixtureTimed = try XCTUnwrap(
            events.first(where: { $0["kind"] as? String == "timed" })
        )
        XCTAssertEqual(
            Set(logged.event.keys),
            Set(fixtureTimed.keys),
            "the surface emits the fixture's field set, no more and no less"
        )
    }
}
