//
//  WatchEffortDistanceTests.swift
//  WatchSessionEngineTests
//
//  Phase 1B of
//  `docs/plans/2026-10-10-19e-watch-distance-tracking-plan/2026-10-10-19e-watch-distance-tracking-plan.md`:
//  a timed effort logs the metres its own window covered, with the source the
//  number came from, and nothing else (D-2205, D-2206).
//
//  Scenario mapping:
//    S-3208 an effort carries its own metres                → `testS3208...`
//    S-3209 metres before Start are not the effort's        → `testS3209...`
//    S-3210 the source travels, and only with a distance    → `testS3210...`
//    S-3211 a window with no movement carries nothing       → `testS3211...`
//    S-3212 a relaunch changes nothing                      → `testS3212...`
//    S-3214 the Start boundary is inclusive                 → `testS3214...`
//    S-3215 the newest qualifying sample wins               → `testS3215...`
//    S-3216 the settled `distance` sample is not the effort's → `testS3216...`
//    S-3217 the Log boundary is inclusive                   → `testS3217...`
//    S-3219 a hold logged while measuring carries nothing   → `testS3219...`
//    S-3221 a restarted total inside the window             → `testS3221...`
//
//  Every fix is stamped with the clock reading when it arrives, and two samples
//  of one kind on one instant are one stored row (D-2211): each fixture advances
//  the clock to the instant it means, yields the fix, awaits the store, and only
//  then advances again.
//

import XCTest

@testable import WatchSessionEngine

final class WatchEffortDistanceTests: XCTestCase {

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
        _ recorder: WatchSensorRecorder
    ) -> WatchLoggingState {
        WatchLoggingState(engine: engine, clock: clock.call, sensors: recorder)
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

    // MARK: - S-3208 an effort carries its own metres

    func testS3208AnEffortCarriesItsOwnWindowsMetres() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        clock.advance(600)
        source.fix(3000)
        await eventually { recorder.readings.distanceMeters == 3000 }
        clock.advance(600)
        let first = try await state.log()

        XCTAssertEqual(first.payload["distanceMeters"] as? Double, 3000)

        clock.advance(300)
        await state.startWork()
        clock.advance(500)
        source.fix(4500)
        await eventually { recorder.readings.distanceMeters == 4500 }
        clock.advance(100)
        let second = try await state.log()

        XCTAssertEqual(
            second.payload["distanceMeters"] as? Double,
            1500,
            "the second effort's window is 4500 − 3000, not the session's newest total (D-2205)"
        )
    }

    // MARK: - S-3209 metres before Start are not the effort's

    func testS3209MetresBeforeStartAreNotTheEfforts() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        source.fix(800)
        await eventually { recorder.readings.distanceMeters == 800 }

        clock.advance(600)
        await state.startWork()
        clock.advance(600)
        source.fix(2800)
        await eventually { recorder.readings.distanceMeters == 2800 }
        clock.advance(600)
        let logged = try await state.log()

        XCTAssertEqual(
            logged.payload["distanceMeters"] as? Double,
            2000,
            "the 800 m covered before Start belongs to the session, not to this effort"
        )
    }

    // MARK: - S-3210 the source travels

    func testS3210TheSourceTravelsAndOnlyBesideADistance() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        clock.advance(600)
        source.fix(3000)
        await eventually { recorder.readings.distanceMeters == 3000 }
        clock.advance(600)
        let logged = try await state.log()
        let captured = try loggedEvent()

        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, 3000)
        XCTAssertEqual(
            logged.payload["distanceSource"] as? String,
            "gps",
            "a measured distance says where it came from (D-2206)"
        )
        XCTAssertEqual(captured.event["distanceSource"] as? String, "gps")
        XCTAssertTrue(
            captured.rejections.isEmpty,
            "a measured timed entry the phone's validator accepts: \(captured.rejections)"
        )

        // With no new fix the window moved nothing: neither the distance nor its
        // source is written — never the source alone (D-2206).
        clock.advance(100)
        await state.startWork()
        clock.advance(100)
        let bare = try await state.log()

        XCTAssertNil(bare.payload["distanceMeters"])
        XCTAssertNil(bare.payload["distanceSource"])
    }

    // MARK: - S-3211 a window with no movement

    func testS3211AWindowThatMovedNothingCarriesNoDistance() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        source.fix(3000)
        await eventually { recorder.readings.distanceMeters == 3000 }

        clock.advance(300)
        await state.startWork()
        clock.advance(1200)
        let logged = try await state.log()

        XCTAssertNil(
            logged.payload["distanceMeters"],
            "the fix predates Start, so end − start is 0"
        )
        XCTAssertNil(logged.payload["distanceSource"])
        XCTAssertEqual(state.effortKind, WatchEffortKind.timed)
        XCTAssertEqual(logged.payload["kind"] as? String, "timed")
        XCTAssertEqual(engine.observations.count, 1, "the effort is logged regardless")
    }

    // MARK: - S-3212 a relaunch changes nothing

    func testS3212ARelaunchedStateLogsTheSameWindow() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        clock.advance(600)
        source.fix(3000)
        await eventually { recorder.readings.distanceMeters == 3000 }

        // A kill and a relaunch: a fresh engine over the same storage, and a
        // state rebuilt on it before the effort is logged.
        let restarted = await harness.runningEngine()
        clock.advance(600)
        let rebuilt = surface(restarted, recorder)
        let logged = try await rebuilt.log()

        XCTAssertEqual(
            logged.payload["distanceMeters"] as? Double,
            3000,
            "the rule reads stored samples and timestamps, not memory (D-2205)"
        )
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "gps")
    }

    // MARK: - S-3214 the Start boundary is inclusive

    func testS3214ASampleExactlyAtStartCountsAsBeforeIt() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        source.fix(800)
        await eventually { recorder.readings.distanceMeters == 800 }

        // The sample's `recordedAt` is equal to the clock's start.
        await state.startWork()
        clock.advance(60)
        source.fix(2800)
        await eventually { recorder.readings.distanceMeters == 2800 }
        clock.advance(1140)
        let logged = try await state.log()

        XCTAssertEqual(
            logged.payload["distanceMeters"] as? Double,
            2000,
            "a sample at or before Start is inside the window"
        )
    }

    // MARK: - S-3215 the newest qualifying sample wins

    func testS3215TheNewestQualifyingSampleWinsNotTheLargestNorTheFirst() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        source.fix(400)
        await eventually { recorder.readings.distanceMeters == 400 }
        clock.advance(10)
        source.fix(1200)
        await eventually { recorder.readings.distanceMeters == 1200 }
        clock.advance(10)
        source.fix(900)
        await eventually { recorder.readings.distanceMeters == 900 }

        clock.advance(10)
        await state.startWork()
        clock.advance(10)
        let flat = try await state.log()

        XCTAssertNil(
            flat.payload["distanceMeters"],
            "the newest qualifying sample is 900 at Start and 900 at Log: 0, not 1200 − 400"
        )

        clock.advance(10)
        await state.startWork()
        clock.advance(5)
        source.fix(1500)
        await eventually { recorder.readings.distanceMeters == 1500 }
        clock.advance(5)
        let climbed = try await state.log()

        XCTAssertEqual(
            climbed.payload["distanceMeters"] as? Double,
            600,
            "1500 − the newest qualifying sample at Start, 900"
        )
    }

    // MARK: - S-3216 the settled distance sample is not read

    func testS3216ASettledDistanceSampleIsNotTheEffortsDistance() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        clock.advance(600)
        source.fix(3000)
        await eventually { recorder.readings.distanceMeters == 3000 }
        clock.advance(600)
        let first = try await state.log()
        XCTAssertEqual(first.payload["distanceMeters"] as? Double, 3000)

        // Stopping settles the session total as a `distance` sample, and the
        // wrist starts measuring again for the next effort.
        await recorder.stop()
        await recorder.start(live)
        XCTAssertTrue(recorder.isMeasuringDistance)

        clock.advance(100)
        await state.startWork()

        // A stored `distance` sample inside the second effort's window, appended
        // directly rather than through the recorder: the rule under test is "the
        // settled `distance` kind is never read", and routing the sample through
        // the recorder would conflate it with whatever the recorder itself
        // writes. Without the `distance` kind the window is 3000 − 3000 = 0; a
        // rule that also read it would see 5000 − 3000 = 2000.
        await engine.appendSensorSample(
            kind: WatchSensorKind.distance,
            value: 5000,
            recordedAt: clock.call().addingTimeInterval(50)
        )

        clock.advance(100)
        let second = try await state.log()

        XCTAssertNil(
            second.payload["distanceMeters"],
            "the newest samples are `distance` rows (3000 settled, 5000 in-window), and neither is read"
        )
        XCTAssertNil(second.payload["distanceSource"])
    }

    // MARK: - S-3217 the Log boundary is inclusive

    func testS3217AFixStampedAtTheLogInstantCounts() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        await state.startWork()
        clock.advance(1200)
        source.fix(2000)
        await eventually { recorder.readings.distanceMeters == 2000 }
        let logged = try await state.log()

        XCTAssertEqual(
            logged.payload["distanceMeters"] as? Double,
            2000,
            "the fix at the log instant is the wrist's total at that instant"
        )
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "gps")
    }

    // MARK: - S-3221 a restarted total inside the window

    func testS3221ARestartedTotalInsideTheWindowIsTheMetresSinceTheRestart() async throws {
        let engine = await harness.runningEngine()
        let live = await cardio(engine)
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)

        source.fix(3000)
        await eventually { recorder.readings.distanceMeters == 3000 }

        clock.advance(60)
        await state.startWork()
        clock.advance(60)
        // The location subscription restarted: the fresh total starts below
        // the one the baseline carries.
        source.fix(111)
        await eventually { recorder.readings.distanceMeters == 111 }
        clock.advance(60)
        source.fix(311)
        await eventually { recorder.readings.distanceMeters == 311 }
        clock.advance(60)
        let logged = try await state.log()

        XCTAssertEqual(
            logged.payload["distanceMeters"] as? Double,
            311,
            "111 m since the restart plus 200 m after it, not 311 − 3000 clamped to 0 (D-2215)"
        )
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "gps")
    }

    // MARK: - S-3219 a hold carries nothing

    func testS3219AHoldLoggedWhileMeasuringCarriesNoDistance() async throws {
        let engine = await harness.runningEngine()
        let live = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [[
                "sessionExerciseId": "sx-plank",
                "exerciseId": "ex-plank",
                "name": "Plank",
                "capabilities": ["hold", "time"],
            ]]
        )
        let recorder = await measuring(engine, live)
        let state = surface(engine, recorder)
        XCTAssertEqual(state.effortKind, WatchEffortKind.drill)

        await state.startWork()
        clock.advance(600)
        source.fix(3000)
        await eventually { recorder.readings.distanceMeters == 3000 }
        clock.advance(600)
        let logged = try await state.log()

        XCTAssertTrue(recorder.isMeasuringDistance, "the wrist was keeping the distance")
        XCTAssertNil(logged.payload["distanceMeters"], "a hold is not a distance effort")
        XCTAssertNil(logged.payload["distanceSource"])
        XCTAssertTrue(try loggedEvent().rejections.isEmpty)
    }
}
