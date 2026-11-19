//
//  WatchSensorPaceTests.swift
//  WatchSessionEngineTests
//
//  The logging header's pace: one window for its time and its distance, and a
//  pace that never outgrows a clock (plan 150, Task D, D-15007 and D-15008).
//
//  Scenario mapping:
//    S-15007 a counter restart pairs the new run's metres with its own time
//    S-15008 a pace slower than the ceiling is "standing still" and is absent
//    S-15010 the ceiling is exclusive; just inside it the minutes stay below 60
//
//  The 5:00 /km case lives where it was written,
//  `WatchSensorRecordingTests.testS003TheLoggingSurfaceShowsTheLiveHeartRate
//  AndDistance`, and stays green: a pace's window starts at its first fix, and
//  the surface's clock has advanced from it (S-15009).
//

import XCTest

@testable import WatchSessionEngine

final class WatchSensorPaceTests: XCTestCase {
    private var harness: Harness!
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        harness = Harness()
        clock = harness.clock
    }

    /// A running session that can cover distance, at the harness's clock.
    private func distanceSession(_ engine: WatchSessionEngine) async -> WatchSessionRecord {
        await engine.createSession(
            modality: "cardio_endurance",
            exercises: [[
                "sessionExerciseId": "sx-run",
                "exerciseId": "ex-run",
                "name": "sx-run",
                "capabilities": ["time", "distance"],
            ]]
        )
    }

    /// The logging surface over `engine`, reading miles or kilometres as the
    /// phone asked, with the live readings wired as on the wrist.
    private func state(
        _ engine: WatchSessionEngine,
        unit: String
    ) -> WatchLoggingState {
        WatchLoggingState(
            engine: engine,
            clock: clock.call,
            units: WatchUnitPreferences(weightUnit: "kg", distanceUnit: unit),
            sensors: WatchSensorRecorder(
                engine: engine,
                source: FakeSensorSource(),
                clock: clock.call
            )
        )
    }

    // MARK: - S-15007 a restart's metres are timed by the restart's own window

    /// The owner's walk after two relaunches: the counter restarts, so the
    /// header's 0.1 mi is the new run's metres while the session itself is 21
    /// minutes old. The pace is 0.1 mi in two minutes — 20:00 /mi — not the
    /// session's whole clock divided by the new run's distance (which read
    /// `6:38:33 /mi` on the wrist).
    func testS15007ARestartedCounterIsPacedOverItsOwnRun() async throws {
        let startedAt = clock.now
        let engine = await harness.runningEngine()
        _ = await distanceSession(engine)

        // The first run: half a mile over five minutes, then the workout
        // restarts under the already-running session.
        await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 0, recordedAt: startedAt)
        await engine.appendSensorSample(
            kind: WatchSensorKind.gps,
            value: 800,
            recordedAt: startedAt.addingTimeInterval(300)
        )
        let restart = startedAt.addingTimeInterval(1260)
        await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 0, recordedAt: restart)
        await engine.appendSensorSample(
            kind: WatchSensorKind.gps,
            value: 160.9344,
            recordedAt: restart.addingTimeInterval(120)
        )
        clock.advance(1380)

        let labels = state(engine, unit: "mi").sensorLabels

        XCTAssertEqual(labels.distance, "0.1", "S-15007 the header's distance is the new run's total")
        XCTAssertEqual(
            labels.pace,
            "20:00 /mi",
            "S-15007 0.1 mi in the two minutes since the restart, not the session's 23"
        )
        XCTAssertEqual(
            labels.pace?.filter { $0 == ":" }.count,
            1,
            "S-15007 a pace is minutes and seconds; it never grows an hours field"
        )
    }

    // MARK: - S-15008 standing still is no pace at all

    /// A watch left open on a walk that stopped moving: 160 m over two hours is
    /// 45,375 s/km, past the ceiling, and the line is simply absent — the
    /// convention for an unavailable pace.
    func testS15008APacePastTheCeilingIsAbsent() async throws {
        let startedAt = clock.now
        let engine = await harness.runningEngine()
        _ = await distanceSession(engine)

        await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 100, recordedAt: startedAt)
        await engine.appendSensorSample(
            kind: WatchSensorKind.gps,
            value: 160,
            recordedAt: startedAt.addingTimeInterval(7260)
        )
        clock.advance(7260)

        let labels = state(engine, unit: "km").sensorLabels

        XCTAssertEqual(labels.distance, "0.2", "S-15008 the distance itself is honest")
        XCTAssertNil(labels.pace, "S-15008 standing still has no pace to show")
    }

    // MARK: - S-15010 the ceiling's boundary and the pace's shape

    /// Exactly 60 minutes a kilometre is the ceiling, and the ceiling is
    /// exclusive: the formatter can never print `60:00`, let alone an hours
    /// field. A second inside it prints `59:59`.
    func testS15010TheCeilingIsExclusiveAndTheMinutesStayBelowSixty() async throws {
        let startedAt = clock.now
        let engine = await harness.runningEngine()
        _ = await distanceSession(engine)

        await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 0, recordedAt: startedAt)
        await engine.appendSensorSample(
            kind: WatchSensorKind.gps,
            value: 1000,
            recordedAt: startedAt.addingTimeInterval(1)
        )

        clock.advance(3600)
        XCTAssertNil(
            state(engine, unit: "km").paceLabel,
            "S-15010 exactly one hour a kilometre is the ceiling, and the ceiling is not a pace"
        )

        clock.advance(-1)
        XCTAssertEqual(
            state(engine, unit: "km").paceLabel,
            "59:59 /km",
            "S-15010 a second inside the ceiling still prints, and prints no hours field"
        )
    }
}
