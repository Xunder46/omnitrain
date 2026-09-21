//
//  WatchSensorRecordingTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `.github/agents/plans/2026-07-13-11-d-watch-sensor-recording-plan.md` — the
//  same scenarios the Flutter client proves in
//  `test/watch_sensor_recording_test.dart`, run against the Swift sensor layer.
//
//  Scenario mapping:
//    S-001 strength session does not activate GPS          → `testS001...`
//    S-002 distance session activates GPS, logs distance    → `testS002...`
//    S-003 live heart rate                                  → `testS003...`
//    S-004 GPS-derived distance leaves the watch            → `testS004...`
//    S-005 force-kill leaves no stuck platform workout      → `testS005...`
//    S-006 permission denial degrades gracefully            → `testS006...`
//    S-007 unmapped modality falls back to a generic type   → `testS007...`
//    S-008 GPS activation derives from capabilities         → `testS008...`
//
//  Both suites read `watch/contract/watch_sensor_contract.json`: the sample
//  kinds, the modality → platform workout type table, and the capability
//  profile the GPS decision is derived from.
//

import XCTest

@testable import WatchSessionEngine

/// The sensor hardware, with the permissions the user granted and two streams
/// the test drives. Every subscription is counted, so "was the radio woken for
/// work that has no distance" is an assertion rather than an assumption.
final class FakeSensorSource: WatchSensorSource {
    var heartRateGrant: WatchSensorPermission = .granted
    var locationGrant: WatchSensorPermission = .granted

    private(set) var heartRateSubscriptions = 0
    private(set) var locationSubscriptions = 0

    private var beats: AsyncStream<Double>.Continuation?
    private var fixes: AsyncStream<WatchLocationFix>.Continuation?

    func heartRatePermission() async -> WatchSensorPermission { heartRateGrant }
    func locationPermission() async -> WatchSensorPermission { locationGrant }

    func heartRate() -> AsyncStream<Double> {
        heartRateSubscriptions += 1
        return AsyncStream { beats = $0 }
    }

    func location() -> AsyncStream<WatchLocationFix> {
        locationSubscriptions += 1
        return AsyncStream { fixes = $0 }
    }

    func beat(_ beatsPerMinute: Double) { beats?.yield(beatsPerMinute) }
    func fix(_ cumulativeMetres: Double) { fixes?.yield(WatchLocationFix(distanceMeters: cumulativeMetres)) }

    func close() {
        beats?.finish()
        fixes?.finish()
    }
}

/// The health store, as the watch sees it: sessions it started, and whatever a
/// previous process left in progress.
final class FakePlatformStore: WatchPlatformWorkoutStore {
    private(set) var begun: [String] = []
    private(set) var ended: [String] = []

    /// What the health store reports as still running — the shape a kill leaves
    /// behind.
    var inProgress: [String] = []

    func begin(_ activityType: String) async {
        begun.append(activityType)
        inProgress.append(activityType)
    }

    func end() async {
        if !inProgress.isEmpty { ended.append(inProgress.removeFirst()) }
    }

    func inProgressActivityTypes() async -> [String] { inProgress }
}

/// Waits for `condition` to hold, up to a second: a stream-delivered sample is
/// observed rather than raced.
func eventually(
    _ condition: @escaping () async -> Bool,
    _ message: String = "condition never became true",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail(message, file: file, line: line)
}

final class WatchSensorRecordingTests: XCTestCase {

    private var harness: Harness!
    private var source: FakeSensorSource!
    private var health: FakePlatformStore!
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        harness = Harness()
        source = FakeSensorSource()
        health = FakePlatformStore()
        clock = harness.clock
    }

    override func tearDown() {
        source.close()
        super.tearDown()
    }

    private func sensors(for engine: WatchSessionEngine) -> WatchSessionSensors {
        WatchSessionSensors(
            platform: WatchPlatformWorkout(store: health),
            recorder: WatchSensorRecorder(engine: engine, source: source, clock: clock.call)
        )
    }

    private func session(
        _ engine: WatchSessionEngine,
        modality: String?,
        capabilities: [String] = ["reps", "sets", "load"]
    ) async -> WatchSessionRecord {
        await engine.createSession(
            modality: modality,
            exercises: [[
                "sessionExerciseId": "sx-1",
                "exerciseId": "ex-1",
                "name": "sx-1",
                "capabilities": capabilities,
            ]]
        )
    }

    // MARK: - S-001 a strength session leaves the GPS radio alone

    func testS001ThePlatformWorkoutCarriesTheModalitysOwnType() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting")
        let sensors = sensors(for: engine)

        await sensors.start(live)

        XCTAssertEqual(health.begun, ["traditionalStrengthTraining"])
        XCTAssertEqual(health.inProgress, ["traditionalStrengthTraining"])
    }

    func testS001NoLocationSubscriptionIsMadeForWorkWithNoDistance() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting")
        let sensors = sensors(for: engine)

        await sensors.start(live)
        source.fix(500)

        XCTAssertEqual(source.locationSubscriptions, 0)
        XCTAssertFalse(sensors.recorder.isMeasuringDistance)
        XCTAssertTrue(engine.sensorSamples.isEmpty)
    }

    // MARK: - S-002 a distance modality records GPS

    func testS002GpsStartsWithTheSessionAndTheLiveDistanceAdvances() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let sensors = sensors(for: engine)

        await sensors.start(live)
        XCTAssertTrue(sensors.recorder.isMeasuringDistance)
        XCTAssertEqual(source.locationSubscriptions, 1)

        source.fix(400)
        await eventually { sensors.recorder.readings.distanceMeters == 400 }
        clock.advance(1)
        source.fix(1200)
        await eventually { sensors.recorder.readings.distanceMeters == 1200 }
    }

    func testS002StoppingSettlesTheSessionDistanceAtTheMeasuredTotal() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let sensors = sensors(for: engine)

        await sensors.start(live)
        source.fix(400)
        await eventually { sensors.recorder.readings.distanceMeters == 400 }
        clock.advance(1)
        source.fix(2500)
        await eventually { sensors.recorder.readings.distanceMeters == 2500 }
        clock.advance(600)
        await sensors.stop()

        let settled = try XCTUnwrap(engine.sensorSamples.last)
        XCTAssertEqual(settled.kind, WatchSensorKind.distance)
        XCTAssertEqual(settled.value, 2500)
        XCTAssertEqual(settled.sessionId, live.sessionId)
        XCTAssertFalse(sensors.recorder.isMeasuringDistance)
    }

    // MARK: - S-003 live heart rate

    func testS003BeatsAreStoredAgainstTheSessionAsTheyArrive() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting")
        let sensors = sensors(for: engine)

        await sensors.start(live)
        XCTAssertEqual(source.heartRateSubscriptions, 1)

        source.beat(96)
        await eventually { sensors.recorder.readings.heartRate == 96 }
        clock.advance(2)
        source.beat(104)
        await eventually { sensors.recorder.readings.heartRate == 104 }

        let beats = engine.sensorSamples.filter { $0.kind == WatchSensorKind.heartRate }
        XCTAssertEqual(beats.map(\.value), [96, 104])
        XCTAssertEqual(beats.first?.sessionId, live.sessionId)
    }

    func testS003TheLoggingSurfaceShowsTheLiveHeartRateAndDistance() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 128)
        await engine.appendSensorSample(kind: WatchSensorKind.gps, value: 1000)
        clock.advance(300)

        let state = WatchLoggingState(
            engine: engine,
            clock: clock.call,
            sensors: WatchSensorRecorder(engine: engine, source: source, clock: clock.call)
        )

        XCTAssertEqual(state.heartRateLabel, "128")
        XCTAssertEqual(state.liveDistanceLabel, "1.0")
        XCTAssertEqual(state.paceLabel, "5:00 /km")
    }

    // MARK: - S-004 measured distance is what leaves the watch

    func testS004TheLoggedEffortCarriesTheGpsTotal() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let sensors = sensors(for: engine)
        await sensors.start(try XCTUnwrap(engine.session))
        source.fix(3000)
        await eventually { sensors.recorder.readings.distanceMeters == 3000 }
        clock.advance(1200)

        let state = WatchLoggingState(
            engine: engine,
            clock: clock.call,
            sensors: sensors.recorder
        )
        let logged = try await state.log()

        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, 3000)
    }

    func testS004WithoutAFixTheDistanceRowIsTheUsersToFill() async throws {
        source.locationGrant = .denied
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let sensors = sensors(for: engine)
        await sensors.start(try XCTUnwrap(engine.session))

        let state = WatchLoggingState(
            engine: engine,
            clock: clock.call,
            sensors: sensors.recorder
        )
        state.adjust(WatchMetricKey.distance, detents: 15)
        let logged = try await state.log()

        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, 1500)
    }

    // MARK: - S-005 a kill leaves nothing running in the health store

    func testS005TheNextLaunchEndsTheWorkoutTheKillLeftBehind() async throws {
        health.inProgress = ["running"]
        let engine = await harness.runningEngine()
        let sensors = sensors(for: engine)

        let ended = await sensors.recoverInProgress()

        XCTAssertEqual(ended, ["running"])
        XCTAssertTrue(health.inProgress.isEmpty)
    }

    func testS005NothingIsEndedWhenTheLastSessionClosedCleanly() async throws {
        let engine = await harness.runningEngine()
        let sensors = sensors(for: engine)

        let ended = await sensors.recoverInProgress()

        XCTAssertTrue(ended.isEmpty)
        XCTAssertTrue(health.ended.isEmpty)
    }

    // MARK: - S-006 permission denial degrades gracefully

    func testS006DeniedHeartRateSkipsTheSubscriptionAndLoggingCarriesOn() async throws {
        source.heartRateGrant = .denied
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "resistance_lifting")
        let sensors = sensors(for: engine)

        await sensors.start(try XCTUnwrap(engine.session))
        source.beat(110)

        XCTAssertEqual(source.heartRateSubscriptions, 0)
        XCTAssertNil(sensors.recorder.readings.heartRate)

        let state = WatchLoggingState(
            engine: engine,
            clock: clock.call,
            sensors: sensors.recorder
        )
        state.adjust(WatchMetricKey.reps, detents: 7)
        let logged = try await state.log()

        XCTAssertEqual(logged.payload["reps"] as? Int, 17)
        XCTAssertEqual(engine.observations.count, 1)
    }

    func testS006DeniedLocationLeavesTheSessionWithNoDistanceAtAll() async throws {
        source.locationGrant = .denied
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let sensors = sensors(for: engine)

        await sensors.start(try XCTUnwrap(engine.session))

        XCTAssertEqual(source.locationSubscriptions, 0)
        XCTAssertNil(sensors.recorder.readings.distanceMeters)
        XCTAssertTrue(
            engine.sensorSamples.filter { $0.kind == WatchSensorKind.gps }.isEmpty
        )
    }

    func testS006HardwareThatIsNotThereIsNotAFailure() async throws {
        source.heartRateGrant = .unavailable
        source.locationGrant = .unavailable
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let sensors = sensors(for: engine)

        await sensors.start(try XCTUnwrap(engine.session))
        await sensors.stop()

        XCTAssertTrue(engine.sensorSamples.isEmpty)
        XCTAssertEqual(source.heartRateSubscriptions, 0)
        XCTAssertEqual(source.locationSubscriptions, 0)
    }

    // MARK: - S-007 an unmapped modality still produces a workout

    func testS007AnUnknownModalityFallsBackToTheGenericPlatformType() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "not_a_modality")
        let sensors = sensors(for: engine)

        await sensors.start(try XCTUnwrap(engine.session))

        XCTAssertEqual(health.begun, [WatchActivityTypes.generic.watchOs])
    }

    func testS007FreeTrainingFallsBackToo() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: nil)
        let sensors = sensors(for: engine)

        await sensors.start(try XCTUnwrap(engine.session))

        XCTAssertEqual(health.begun, [WatchActivityTypes.generic.watchOs])
    }

    func testS007EveryMappedModalityNamesBothPlatforms() throws {
        let contract = try Fixtures.sensorContract()
        let types = try XCTUnwrap(contract["activityTypes"] as? [String: [String: String]])
        XCTAssertFalse(types.isEmpty)

        for (modality, mapped) in types {
            XCTAssertNotNil(mapped["watchos"], "\(modality) has no watchOS type")
            XCTAssertNotNil(mapped["wear"], "\(modality) has no Wear OS type")
            XCTAssertEqual(WatchActivityTypes.forModality(modality).watchOs, mapped["watchos"])
            XCTAssertEqual(WatchActivityTypes.forModality(modality).wear, mapped["wear"])
        }

        let generic = try XCTUnwrap(contract["genericActivityType"] as? [String: String])
        XCTAssertEqual(WatchActivityTypes.generic.watchOs, generic["watchos"])
        XCTAssertEqual(WatchActivityTypes.generic.wear, generic["wear"])
    }

    // MARK: - S-008 the GPS decision reads capabilities, not names

    func testS008TheGpsDecisionFollowsTheCapabilityProfile() throws {
        let contract = try Fixtures.sensorContract()
        let profiles = try XCTUnwrap(
            contract["modalityCapabilities"] as? [[String: Any]]
        )
        let capability = try XCTUnwrap(contract["gpsCapability"] as? String)
        XCTAssertFalse(profiles.isEmpty)

        for profile in profiles {
            let modality = profile["modality"] as? String
            let capabilities = (profile["capabilities"] as? [String]) ?? []
            XCTAssertEqual(
                WatchGpsPolicy.isRequired(modality),
                capabilities.contains(capability),
                "\(modality ?? "free training") diverged from its capability profile"
            )
        }
    }

    func testS008AModalityThatNamesDistanceButCannotCoverItStaysOff() throws {
        // The isometric profile names distance only to rule it out, so the
        // decision has to read what the modality can do.
        let contract = try Fixtures.sensorContract()
        let profiles = try XCTUnwrap(contract["modalityCapabilities"] as? [[String: Any]])
        let isometric = try XCTUnwrap(
            profiles.first { $0["modality"] as? String == "isometric_stretching" }
        )
        XCTAssertTrue((isometric["capabilities"] as? [String] ?? []).isEmpty == false)
        XCTAssertFalse((isometric["capabilities"] as? [String] ?? []).contains("distance"))

        XCTAssertFalse(WatchGpsPolicy.isRequired("isometric_stretching"))
        XCTAssertFalse(WatchGpsPolicy.isRequired("resistance_lifting"))
    }

    func testS008TheContractsExpectationListIsTheDerivedAnswer() throws {
        let contract = try Fixtures.sensorContract()
        let expected = Set(try XCTUnwrap(contract["gpsModalities"] as? [String]))
        let profiles = try XCTUnwrap(contract["modalityCapabilities"] as? [[String: Any]])
        let derived = Set(
            profiles
                .compactMap { $0["modality"] as? String }
                .filter { WatchGpsPolicy.isRequired($0) }
        )

        XCTAssertEqual(derived, expected)
    }

    // MARK: - Sensor storage

    func testTheSampleKindsAreTheOnesBothClientsAgreedOn() throws {
        let contract = try Fixtures.sensorContract()
        let kinds = try XCTUnwrap(contract["kinds"] as? [String])
        XCTAssertEqual(Set(WatchSensorKind.all), Set(kinds))
    }

    func testASampleSurvivesStorageAndARelaunch() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let stored = await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 121)

        guard case .sensorSample(let decoded) = try StoredWatchRecord.fromJson(stored.toJson()) else {
            return XCTFail("a sensor sample did not survive the store's encoding")
        }
        XCTAssertEqual(decoded.kind, WatchSensorKind.heartRate)
        XCTAssertEqual(decoded.value, 121)
        XCTAssertEqual(decoded.recordId, stored.recordId)

        let restarted = await harness.runningEngine()
        XCTAssertEqual(restarted.sensorSamples.map(\.value), [121])
    }

    func testAppendingTheSameInstantTwiceStoresOneRow() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "resistance_lifting")

        let first = await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 88)
        let again = await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 88)

        XCTAssertEqual(again.recordId, first.recordId)
        XCTAssertEqual(engine.sensorSamples.count, 1)
    }

    func testPruningConfirmedObservationsLeavesSensorRowsAlone() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "resistance_lifting")
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 99)

        let pruned = await engine.pruneConfirmed()

        XCTAssertTrue(pruned.isEmpty)
        XCTAssertEqual(engine.sensorSamples.count, 1)
    }

    func testASettledSessionReleasesItsLogAndARunningOneKeepsIt() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 128)
        _ = await engine.confirmObservations(["e-1"])
        _ = await engine.finishSession()

        let released = await engine.pruneSettledSensorSamples()

        XCTAssertEqual(released.count, 1)
        XCTAssertTrue(engine.sensorSamples.isEmpty)
        XCTAssertEqual(engine.observations.count, 1)
    }

    func testASessionStillRunningNeverLosesItsReadings() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 96)

        let released = await engine.pruneSettledSensorSamples()

        XCTAssertTrue(released.isEmpty)
        XCTAssertEqual(engine.sensorSamples.count, 1)
    }

    func testAnEntryStillOwedToThePhoneHoldsTheLogBack() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 96)
        _ = await engine.finishSession()

        let released = await engine.pruneSettledSensorSamples()

        XCTAssertTrue(released.isEmpty)
        XCTAssertEqual(engine.sensorSamples.count, 1)
    }

    // MARK: - Sensor wiring

    func testStartingASessionClosesTheWorkoutTheLastOneLeftOpen() async throws {
        let engine = await harness.runningEngine()
        let sensors = sensors(for: engine)

        await sensors.start(await session(engine, modality: "resistance_lifting"))
        await sensors.start(await session(engine, modality: nil, capabilities: []))

        XCTAssertEqual(
            health.begun,
            ["traditionalStrengthTraining", WatchActivityTypes.generic.watchOs]
        )
        XCTAssertEqual(
            health.ended,
            ["traditionalStrengthTraining"],
            "the platform grants one workout at a time; a second one started over "
                + "a dangling first is the stuck state recovery exists to clear"
        )
    }

    func testAReadingIsStoredWithoutBeingSentAnywhere() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        XCTAssertEqual(harness.emitted.count, 1, "starting a session tells the phone")

        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 132)

        XCTAssertEqual(engine.sensorSamples.count, 1)
        XCTAssertEqual(
            harness.emitted.count,
            1,
            "a reading adds nothing to the outbound stream: the sync protocol "
                + "carries the logged effort, and the distance in it is the reading "
                + "that survived"
        )
    }

    func testThePaceFloorIsTheOneBothClientsAgreedOn() throws {
        let contract = try Fixtures.sensorContract()
        let floor = try XCTUnwrap(contract["paceMinDistanceMeters"] as? NSNumber)

        XCTAssertEqual(
            WatchSensorPace.minDistanceMeters,
            floor.doubleValue,
            "a pace below the floor is noise from a fix that has barely moved, and "
                + "the two clients have to hide it at the same distance"
        )
    }

    // MARK: - Distance readout

    func testAMeasuredDistanceOutranksTheDial() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let sensors = sensors(for: engine)
        await sensors.start(try XCTUnwrap(engine.session))
        source.fix(3200)
        await eventually { sensors.recorder.readings.distanceMeters == 3200 }

        let state = WatchLoggingState(engine: engine, clock: clock.call, sensors: sensors.recorder)
        let distance = try XCTUnwrap(
            state.fields.first { $0.metricKey == WatchMetricKey.distance }
        )

        XCTAssertTrue(distance.isMeasured)
        state.adjust(WatchMetricKey.distance, detents: 15)
        XCTAssertEqual(
            distance.value,
            3200,
            "a measured row is not a number the user can add to"
        )

        let logged = try await state.log()
        XCTAssertEqual(
            logged.payload["distanceMeters"] as? Double,
            3200,
            "the phone receives the measured total, not the last thing the dial was set to"
        )
    }
}
