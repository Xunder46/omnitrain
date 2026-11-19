//
//  WatchHeaderDistanceTests.swift
//  WatchSessionEngineTests
//
//  The logging header's distance and pace are the Distance field's own figures
//  (plan 150, Task E, D-15011): the owner's walk restarted the platform counter
//  and read `0.1 mi` in the header beside a `0.9 mi` Distance row.
//
//  Scenario mapping:
//    S-15011 the header's distance is the Distance field's own figure
//    S-15012 the header's pace divides that same window's time by its distance
//    S-15013 with no effort window the header keeps the counter's own run
//    S-15014 the unit switch keeps the header and the field the same number
//

import XCTest

@testable import WatchSessionEngine

final class WatchHeaderDistanceTests: XCTestCase {
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

    /// The `sx-run` slot: timed work over a distance the modality can cover, so
    /// the recorder keeps the GPS and the surface offers its Distance row.
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
        _ recorder: WatchSensorRecorder,
        unit: String = "mi"
    ) -> WatchLoggingState {
        WatchLoggingState(
            engine: engine,
            clock: clock.call,
            units: WatchUnitPreferences(weightUnit: "kg", distanceUnit: unit),
            sensors: recorder
        )
    }

    private func distanceField(_ state: WatchLoggingState) throws -> WatchMetricField {
        try XCTUnwrap(
            state.fields.first { $0.metricKey == WatchMetricKey.distance },
            "the timed distance effort shows one Distance row"
        )
    }

    /// The owner's walk: the effort starts, 800 m arrive, the platform's
    /// counter then restarts, and its newest run is the 0.1 mi it measured
    /// since. The effort's own window has covered 800 + 160.9 m in four
    /// minutes, so the field reads 0.6 mi while the counter's newest run reads
    /// 0.1 mi (S-15011).
    private func restartedEffort(
        _ state: WatchLoggingState,
        _ recorder: WatchSensorRecorder
    ) async {
        await state.startWork()
        clock.advance(60)
        source.fix(800)
        await eventually { recorder.readings.distanceMeters == 800 }

        clock.advance(60)
        source.fix(0)
        await eventually { recorder.readings.distanceMeters == 0 }

        clock.advance(120)
        source.fix(160.9344)
        await eventually { recorder.readings.distanceMeters == 160.9344 }
    }

    // MARK: - S-15011 the header prints the Distance field's figure

    /// A kill and a relaunch between the restart and the readout change
    /// nothing: both numbers are read back from the stored samples and the
    /// stored effort window, and they are the same number.
    func testS15011TheHeadersDistanceIsTheDistanceFieldsOwnFigure() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)
        await restartedEffort(state, recorder)

        // The owner's screenshot is taken after the app restarts.
        let restarted = await harness.runningEngine()
        let rebuilt = surface(restarted, recorder)
        let field = try distanceField(rebuilt)
        let labels = rebuilt.sensorLabels

        XCTAssertEqual(
            labels.distance,
            field.displayValue,
            "S-15011 the header's distance is the Distance field's own figure, got "
                + "\"\(labels.distance ?? "nil")\" beside \"\(field.displayValue)\""
        )
        XCTAssertEqual(
            labels.distance,
            "0.6",
            "S-15011 the effort's 960.9 m window, not the counter's newest 0.1 mi run"
        )
    }

    // MARK: - S-15012 the pace divides the same window

    /// Four minutes over the effort's 960.9 m is 6:42 a mile — not 20:00, which
    /// is the counter's newest 0.1 mi run over the two minutes since it
    /// restarted. One colon: a pace never grows an hours field.
    func testS15012ThePaceIsTheSameWindowsTimeOverItsDistance() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)
        await restartedEffort(state, recorder)

        let labels = state.sensorLabels

        XCTAssertEqual(
            labels.pace,
            "6:42 /mi",
            "S-15012 240 s over the window's 0.597 mi, not the restart's own 20:00 /mi"
        )
        XCTAssertEqual(
            labels.pace?.filter { $0 == ":" }.count,
            1,
            "S-15012 minutes and seconds only, got \"\(labels.pace ?? "nil")\""
        )
    }

    // MARK: - S-15013 no effort window keeps the counter's own run

    /// Before Start the effort has no window, so the field is absent and the
    /// header keeps Task D's pairing: the newest counter total over the time
    /// since that counter's run began (S-15007's rule).
    func testS15013WithNoEffortWindowTheHeaderKeepsTheCountersOwnRun() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        source.fix(0)
        await eventually { recorder.readings.distanceMeters == 0 }
        clock.advance(300)
        source.fix(800)
        await eventually { recorder.readings.distanceMeters == 800 }
        clock.advance(960)
        source.fix(0)
        await eventually { recorder.readings.distanceMeters == 0 }
        clock.advance(120)
        source.fix(160.9344)
        await eventually { recorder.readings.distanceMeters == 160.9344 }

        XCTAssertNil(
            state.fields.first { $0.metricKey == WatchMetricKey.distance },
            "S-15013 no Start means no window, so no Distance row"
        )
        XCTAssertEqual(
            state.sensorLabels.distance,
            "0.1",
            "S-15013 the counter's newest run, as before"
        )
        XCTAssertEqual(
            state.sensorLabels.pace,
            "20:00 /mi",
            "S-15013 Task D's pairing, unchanged where there is no effort window"
        )
    }

    // MARK: - S-15014 the unit switch keeps the two numbers equal

    /// The same window in kilometres: 1.0 km at 4:10 /km, still the field's
    /// own figure and still the same number as the header.
    func testS15014TheUnitSwitchKeepsTheHeaderAndTheFieldEqual() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)
        await restartedEffort(state, recorder)

        let miles = state.sensorLabels
        let kilometresState = surface(engine, recorder, unit: "km")
        let kilometres = kilometresState.sensorLabels
        let field = try distanceField(kilometresState)

        XCTAssertEqual(
            miles.distance,
            try distanceField(state).displayValue,
            "S-15014 miles: header and field are one number"
        )
        XCTAssertEqual(
            kilometres.distance,
            field.displayValue,
            "S-15014 kilometres: header and field are one number"
        )
        XCTAssertEqual(kilometres.distance, "1.0", "S-15014 the same window in kilometres")
        XCTAssertEqual(kilometres.pace, "4:10 /km", "S-15014 the same window's time per kilometre")
    }
}
