//
//  WatchHandDistanceTests.swift
//  WatchSessionEngineTests
//
//  Plan 65 P1 (`docs/plans/2026-10-23-65-wrist-hand-distance-plan/…`): a timed
//  effort takes a hand-dialled distance when GPS measured nothing.
//
//  Scenario mapping:
//    S-9501 the tile is offered exactly when the exercise counts distance → `testS9501...`
//    S-9502 a dialled distance is logged as "entered"                    → `testS9502...`
//    S-9503 a dialled distance reaches the observation                   → WatchLoggingSurfacesTests
//    S-9504 a measurement outranks a dial                                → `testS9504...`
//    S-9504b a second effort measures its own window, not the session total → `testS9504b...`
//    S-9505 a distance belongs to one effort                             → `testS9505...`
//    S-9506 every arm of the "measured" test                             → `testS9506...`
//    S-9507 a zero or untouched dial sends no distance keys              → `testS9507...`
//    S-9508 the entered event passes the package's own validation        → `testS9508...`
//    S-9509 a hold and a period get no distance tile                     → `testS9509...`
//    S-9510 the dial is read in the phone's unit, sent in metres         → `testS9510...`
//
//  The sensor/GPS sample helper block is copied from `WatchEffortDistanceTests`:
//  it stores `gps` samples with sequence numbers under the injected clock, and
//  every fix is awaited through `eventually` so no test races the store.
//

import XCTest

@testable import WatchSessionEngine

final class WatchHandDistanceTests: XCTestCase {

    private var harness: Harness!
    private var source: FakeSensorSource!
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        harness = Harness()
        source = FakeSensorSource()
        clock = harness.clock
    }

    override func tearDown() {
        source.close()
        super.tearDown()
    }

    /// The `sx-run` register slot: timed work over a distance the modality can
    /// cover, so the recorder keeps the GPS.
    private static let run: [String: Any] = [
        "sessionExerciseId": "sx-run",
        "exerciseId": "ex-run",
        "name": "Run",
        "capabilities": ["time", "distance"],
    ]

    private func cardio(_ engine: WatchSessionEngine) async -> WatchSessionRecord {
        await engine.createSession(modality: "cardio_endurance", exercises: [Self.run])
    }

    private func measuring(
        _ engine: WatchSessionEngine,
        _ session: WatchSessionRecord
    ) async -> WatchSensorRecorder {
        let recorder = WatchSensorRecorder(engine: engine, source: source, clock: clock.call)
        await recorder.start(session)
        return recorder
    }

    private func surface(
        _ engine: WatchSessionEngine,
        _ recorder: WatchSensorRecorder? = nil
    ) -> WatchLoggingState {
        WatchLoggingState(engine: engine, clock: clock.call, sensors: recorder)
    }

    private func field(_ state: WatchLoggingState, _ metricKey: String) -> WatchMetricField {
        state.fields.first(where: { $0.metricKey == metricKey })!
    }

    /// The event the surface logged last, with the schema's verdict on the frame
    /// that carried it.
    private func loggedEvent() throws -> (event: [String: Any], rejections: [SyncProtocolRejection]) {
        let envelope = try XCTUnwrap(
            harness.emitted.last(where: { $0["type"] as? String == "observations_up" })
        )
        let events = (envelope["payload"] as? [String: Any])?["events"] as? [[String: Any]]
        return (try XCTUnwrap(events?.first), Harness.validator().validateEnvelope(envelope))
    }

    // MARK: - S-9501 the tile is offered exactly when the exercise counts distance

    func testS9501ATimedSurfaceOffersADistanceRowOnlyWhenTheExerciseCoversDistance() async throws {
        let engine = await harness.runningEngine()
        _ = await cardio(engine)
        let state = surface(engine)

        XCTAssertEqual(state.effortKind, WatchEffortKind.timed)
        XCTAssertEqual(state.fields.map(\.metricKey), [WatchMetricKey.distance])
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, 0, "before Start the dial sits at zero")
        XCTAssertFalse(field(state, WatchMetricKey.distance).isMeasured, "nothing is measured before Start")

        // An exercise without the distance capability offers no tile (the old
        // S-002 pins the same rule from the other side). One session at a time,
        // so this one gets its own engine.
        let bareHarness = Harness()
        let bareEngine = await bareHarness.runningEngine()
        _ = await bareEngine.createSession(
            modality: "cardio_endurance",
            exercises: [[
                "sessionExerciseId": "sx-row",
                "exerciseId": "ex-row",
                "name": "Row",
                "capabilities": ["time"],
            ]]
        )
        XCTAssertEqual(surface(bareEngine).fields.map(\.metricKey), [])
    }

    // MARK: - S-9502 a dialled distance is logged as "entered"

    func testS9502ADialledDistanceIsLoggedAsEntered() async throws {
        let engine = await harness.runningEngine()
        _ = await cardio(engine)
        let state = surface(engine)

        await state.startWork()
        clock.advance(120)
        // Three Crown clicks, fine: three tenths of the unit, computed from the
        // stepping rather than hard-coded (and unlike the GPS fixtures' metres).
        state.adjust(WatchMetricKey.distance, detents: 3, fine: true)
        let dialled = 3 * WatchMetricStepping.fineStep(for: WatchMetricKey.distance, units: state.units)
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, dialled)
        XCTAssertEqual(field(state, WatchMetricKey.distance).displayValue, "0.3")
        XCTAssertEqual(field(state, WatchMetricKey.distance).unitLabel, "km")

        let logged = try await state.log()

        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, dialled)
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "entered")
    }

    // MARK: - S-9504 a measurement outranks a dial

    func testS9504AMeasurementOutranksADial() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        // Dial 5 km before anything is measured: the dial is open.
        state.adjust(
            WatchMetricKey.distance,
            detents: 5000 / WatchMetricStepping.step(for: WatchMetricKey.distance, units: state.units)
        )
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, 5000)

        clock.advance(600)
        source.fix(1234)
        await eventually { recorder.readings.distanceMeters == 1234 }

        // The first sample in the window measures the field and locks the dial.
        XCTAssertTrue(field(state, WatchMetricKey.distance).isMeasured)
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, 1234)
        state.adjust(WatchMetricKey.distance, detents: 10)
        XCTAssertEqual(
            field(state, WatchMetricKey.distance).value,
            1234,
            "a dial against a measurement changes nothing"
        )

        clock.advance(600)
        let logged = try await state.log()

        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, 1234)
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "gps")
    }

    // MARK: - S-9504b a second effort measures its own window, not the session total

    /// The governor's mutation pass: `measuredValue(for:)` returning the
    /// recorder's live session total (`readings.distanceMeters`) kept every
    /// test green, because no test ran two efforts in one session. Here the
    /// second effort's window is 200 m while the live readout sits at 700 m.
    func testS9504bASecondEffortMeasuresItsOwnWindowNotTheSessionTotal() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        // Effort 1: 500 m inside its window, logged.
        await state.startWork()
        clock.advance(600)
        source.fix(500)
        await eventually { recorder.readings.distanceMeters == 500 }
        clock.advance(600)
        let first = try await state.log()
        XCTAssertEqual(first.payload["distanceMeters"] as? Double, 500)
        XCTAssertEqual(first.payload["distanceSource"] as? String, "gps")

        // Effort 2, same exercise: the newest sample at or before its Start is
        // the 500 m one, so the window is 700 − 500 = 200 — while the
        // recorder's live readout is the session's 700 m total. The fix is
        // stamped strictly after Start (the clock moves first): a sample at
        // the Start instant would be the baseline, not movement.
        clock.advance(300)
        await state.startWork()
        clock.advance(60)
        source.fix(700)
        await eventually { recorder.readings.distanceMeters == 700 }
        clock.advance(600)

        XCTAssertTrue(field(state, WatchMetricKey.distance).isMeasured)
        XCTAssertEqual(
            field(state, WatchMetricKey.distance).value,
            200,
            "the field shows the effort's own window, not the session total"
        )
        XCTAssertEqual(
            recorder.readings.distanceMeters,
            700,
            "the live readout the mutation read is a different number"
        )

        let second = try await state.log()
        XCTAssertEqual(second.payload["distanceMeters"] as? Double, 200)
        XCTAssertEqual(second.payload["distanceSource"] as? String, "gps")
    }

    // MARK: - S-9505 a distance belongs to one effort

    func testS9505TheNextEffortStartsFromZeroAgain() async throws {
        let engine = await harness.runningEngine()
        _ = await cardio(engine)
        let state = surface(engine)

        await state.startWork()
        clock.advance(120)
        state.adjust(WatchMetricKey.distance, detents: 3)
        let first = try await state.log()
        XCTAssertEqual(first.payload["distanceSource"] as? String, "entered")

        // The same exercise's next effort: the dial is back at zero and nothing
        // is measured.
        clock.advance(60)
        await state.startWork()
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, 0)
        XCTAssertFalse(field(state, WatchMetricKey.distance).isMeasured)

        clock.advance(120)
        let second = try await state.log()

        XCTAssertNil(second.payload["distanceMeters"], "nothing was dialled, so no distance travels")
        XCTAssertNil(second.payload["distanceSource"])
    }

    // MARK: - S-9506 every arm of the "measured" test

    /// (a) The subscription runs but no sample sits in the window: the dial
    /// stays open and the log says "entered".
    func testS9506aASubscriptionWithoutSamplesInTheWindowLeavesTheDialOpen() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        clock.advance(600)
        XCTAssertTrue(recorder.isMeasuringDistance, "the subscription is running")
        XCTAssertFalse(field(state, WatchMetricKey.distance).isMeasured)

        state.adjust(WatchMetricKey.distance, detents: 4)
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, 400)

        clock.advance(600)
        let logged = try await state.log()

        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, 400)
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "entered")
    }

    /// (b) A still watch: the only sample predates Start, so the window covered
    /// nothing and the dial stays open. A stale sample before Start never counts.
    func testS9506bAStillWatchMeasuresNothingAndLeavesTheDialOpen() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        source.fix(800)
        await eventually { recorder.readings.distanceMeters == 800 }

        clock.advance(300)
        await state.startWork()
        clock.advance(1200)
        XCTAssertFalse(field(state, WatchMetricKey.distance).isMeasured)

        state.adjust(WatchMetricKey.distance, detents: 20)
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, 2000)

        let logged = try await state.log()

        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, 2000)
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "entered")
    }

    /// (c) Location access refused: the subscription never runs, the dial stays
    /// open and the log says "entered".
    func testS9506cARefusedLocationLeavesTheDialOpen() async throws {
        source.locationGrant = .denied
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        clock.advance(600)
        XCTAssertFalse(recorder.isMeasuringDistance, "access was refused")
        XCTAssertFalse(field(state, WatchMetricKey.distance).isMeasured)

        state.adjust(WatchMetricKey.distance, detents: 25)
        clock.advance(600)
        let logged = try await state.log()

        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, 2500)
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "entered")
    }

    /// (d) The subscription runs and the window holds movement: the field is
    /// measured and read-only.
    func testS9506dMovementMeasuresTheField() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        clock.advance(600)
        source.fix(700)
        await eventually { recorder.readings.distanceMeters == 700 }

        XCTAssertTrue(field(state, WatchMetricKey.distance).isMeasured)
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, 700)
    }

    /// A sample stamped exactly at the Start instant is the baseline (the
    /// S-3214/S-3217 rule), not movement: the dial stays open.
    func testS9506eASampleExactlyAtStartIsTheBaselineNotMovement() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        // The clock has not moved since Start, so the fix is stamped at the
        // Start instant itself.
        source.fix(800)
        await eventually { recorder.readings.distanceMeters == 800 }

        clock.advance(600)
        XCTAssertFalse(
            field(state, WatchMetricKey.distance).isMeasured,
            "the sample at Start is the baseline; the window covered nothing"
        )
        state.adjust(WatchMetricKey.distance, detents: 2)
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, 200)
    }

    // MARK: - S-9507 a zero or untouched dial sends no distance keys

    func testS9507AZeroOrUntouchedDialSendsNoDistanceKeys() async throws {
        let engine = await harness.runningEngine()
        _ = await cardio(engine)
        let state = surface(engine)

        // Dialled down to zero: a zero is not a distance.
        await state.startWork()
        clock.advance(120)
        state.adjust(WatchMetricKey.distance, detents: -3)
        XCTAssertEqual(field(state, WatchMetricKey.distance).value, 0)
        let zeroed = try await state.log()
        XCTAssertNil(zeroed.payload["distanceMeters"])
        XCTAssertNil(zeroed.payload["distanceSource"])

        // Never touched: the same silence.
        clock.advance(60)
        await state.startWork()
        clock.advance(120)
        let untouched = try await state.log()
        XCTAssertNil(untouched.payload["distanceMeters"])
        XCTAssertNil(untouched.payload["distanceSource"])
    }

    // MARK: - S-9508 the entered event passes the package's own validation

    func testS9508TheEnteredEventPassesThePackageValidation() async throws {
        let engine = await harness.runningEngine()
        _ = await cardio(engine)
        let state = surface(engine)

        await state.startWork()
        clock.advance(120)
        state.adjust(WatchMetricKey.distance, detents: 3, fine: true)
        try await state.log()
        let captured = try loggedEvent()

        XCTAssertEqual(captured.event["kind"] as? String, "timed")
        XCTAssertEqual(captured.event["distanceSource"] as? String, "entered")
        XCTAssertNotNil(
            captured.event["distanceMeters"],
            "the source never travels without its metres (D-2206)"
        )
        XCTAssertTrue(
            captured.rejections.isEmpty,
            "a hand-dialled timed entry the package's validator accepts: \(captured.rejections)"
        )
    }

    // MARK: - S-9509 a hold and a period get no distance tile

    func testS9509AHoldAndAPeriodGetNoDistanceTile() async throws {
        let periodHarness = Harness()
        let periodEngine = await periodHarness.runningEngine()
        _ = await periodEngine.createSession(
            modality: "sports",
            exercises: [[
                "sessionExerciseId": "sx-period",
                "exerciseId": "ex-period",
                "name": "Period",
                "capabilities": ["time", "rounds", "distance"],
            ]]
        )
        XCTAssertEqual(surface(periodEngine).effortKind, WatchEffortKind.round)
        XCTAssertEqual(
            surface(periodEngine).fields.map(\.metricKey),
            [WatchMetricKey.roundDuration],
            "a period's one row is its length, distance capability or not"
        )

        let holdHarness = Harness()
        let holdEngine = await holdHarness.runningEngine()
        _ = await holdEngine.createSession(
            modality: "isometric_stretching",
            exercises: [[
                "sessionExerciseId": "sx-plank",
                "exerciseId": "ex-plank",
                "name": "Plank",
                "capabilities": ["hold", "time", "distance"],
            ]]
        )
        XCTAssertEqual(surface(holdEngine).effortKind, WatchEffortKind.drill)
        XCTAssertEqual(
            surface(holdEngine).fields.map(\.metricKey),
            [WatchMetricKey.extraWeight],
            "a hold's one row is its extra load, distance capability or not"
        )
    }

    // MARK: - S-9510 the dial is read in the phone's unit, sent in metres

    func testS9510TheDialIsReadInThePhonesUnitAndSentInMetres() async throws {
        let engine = await harness.runningEngine()
        _ = await cardio(engine)

        let miles = WatchLoggingState(
            engine: engine,
            clock: clock.call,
            units: WatchUnitPreferences(distanceUnit: "miles")
        )
        await miles.startWork()
        clock.advance(120)
        miles.adjust(WatchMetricKey.distance, detents: 10)
        XCTAssertEqual(field(miles, WatchMetricKey.distance).displayValue, "1.0")
        XCTAssertEqual(field(miles, WatchMetricKey.distance).unitLabel, "mi")
        let dialledMetres = field(miles, WatchMetricKey.distance).value
        XCTAssertEqual(
            dialledMetres,
            1609.344,
            accuracy: 0.001,
            "1.00 mi is 1609.344 m, to the metres field's own rounding"
        )
        let milesLog = try await miles.log()
        XCTAssertEqual(
            milesLog.payload["distanceMeters"] as? Double,
            dialledMetres,
            "the metres travel, not the display unit"
        )
        XCTAssertEqual(milesLog.payload["distanceSource"] as? String, "entered")

        clock.advance(60)
        let kilometres = WatchLoggingState(engine: engine, clock: clock.call)
        await kilometres.startWork()
        clock.advance(120)
        kilometres.adjust(WatchMetricKey.distance, detents: 10)
        XCTAssertEqual(field(kilometres, WatchMetricKey.distance).displayValue, "1.0")
        XCTAssertEqual(field(kilometres, WatchMetricKey.distance).unitLabel, "km")
        let kmLog = try await kilometres.log()
        XCTAssertEqual(kmLog.payload["distanceMeters"] as? Double, 1000)
        XCTAssertEqual(kmLog.payload["distanceSource"] as? String, "entered")
    }
}
