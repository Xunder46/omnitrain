//
//  WatchSensorRecordingTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-07-13-11-d-watch-sensor-recording-plan.md` — the
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
    var stepsGrant: WatchSensorPermission = .granted

    private(set) var heartRateSubscriptions = 0
    private(set) var locationSubscriptions = 0
    private(set) var stepsSubscriptions = 0

    /// Whether the steps stream has ended — cancelled by its consumer, or
    /// closed by the test.
    private(set) var stepsStreamEnded = false

    private var beats: AsyncStream<Double>.Continuation?
    private var fixes: AsyncStream<WatchLocationFix>.Continuation?
    private var counts: AsyncStream<Double>.Continuation?

    func heartRatePermission() async -> WatchSensorPermission { heartRateGrant }
    func locationPermission() async -> WatchSensorPermission { locationGrant }
    func stepsPermission() async -> WatchSensorPermission { stepsGrant }

    func heartRate() -> AsyncStream<Double> {
        heartRateSubscriptions += 1
        return AsyncStream { beats = $0 }
    }

    func location() -> AsyncStream<WatchLocationFix> {
        locationSubscriptions += 1
        return AsyncStream { fixes = $0 }
    }

    func steps() -> AsyncStream<Double> {
        stepsSubscriptions += 1
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.stepsStreamEnded = true }
            counts = continuation
        }
    }

    func beat(_ beatsPerMinute: Double) { beats?.yield(beatsPerMinute) }
    func fix(_ cumulativeMetres: Double) { fixes?.yield(WatchLocationFix(distanceMeters: cumulativeMetres)) }
    func count(_ cumulativeSteps: Double) { counts?.yield(cumulativeSteps) }

    func close() {
        beats?.finish()
        fixes?.finish()
        counts?.finish()
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

class WatchSensorRecordingTests: XCTestCase {

    /// The steps permission every test in this class starts with. S-239 runs
    /// the whole class a second time with it denied
    /// (`WatchSensorRecordingStepsDeniedTests`): steps are a sensor of their
    /// own, and nothing the other sensors do may depend on them.
    class var stepsGrant: WatchSensorPermission { .granted }

    private var harness: Harness!
    private var source: FakeSensorSource!
    private var health: FakePlatformStore!
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        harness = Harness()
        source = FakeSensorSource()
        source.stepsGrant = Self.stepsGrant
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

        let state = WatchLoggingState(
            engine: engine,
            clock: clock.call,
            sensors: sensors.recorder
        )
        // Timed work is its own clock: Start opens the window the log closes
        // 1200 s later, where the old dial left it empty.
        await state.startWork()
        clock.advance(1200)
        let logged = try await state.log()

        XCTAssertEqual(logged.payload["distanceMeters"] as? Double, 3000)
    }

    func testS004WithoutAFixTheTimedSurfaceOffersNoDistanceRow() async throws {
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
        XCTAssertFalse(state.isMeasuringDistance, "no fix, so nothing is measured")
        XCTAssertTrue(
            state.fields.isEmpty,
            "a timed surface has no rows: the distance is neither measured nor the user's to dial"
        )
        state.adjust(WatchMetricKey.distance, detents: 15)

        await state.startWork()
        clock.advance(1200)
        let logged = try await state.log()

        XCTAssertNil(
            logged.payload["distanceMeters"],
            "with nothing measured the observation carries no distance"
        )
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
        // The session's end carries what was computed from the log, so its
        // receipt is the last thing the log waits for (D-129).
        _ = await engine.confirmObservations([WatchSessionCapture.sessionEndId(harness.sessionId)])

        let released = await engine.pruneSettledSensorSamples()

        XCTAssertEqual(released.count, 1)
        XCTAssertTrue(engine.sensorSamples.isEmpty)
        XCTAssertEqual(engine.observations.count, 2, "e-1 and the session's end (D-120) are untouched")
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
        // The end is acknowledged, so the entry is the only thing still owed.
        _ = await engine.confirmObservations([WatchSessionCapture.sessionEndId(harness.sessionId)])

        let released = await engine.pruneSettledSensorSamples()

        XCTAssertTrue(released.isEmpty)
        XCTAssertEqual(engine.sensorSamples.count, 1)
    }

    // MARK: - S-237 summaries before the prune

    /// F-CAP `full` replayed through End, with the wrist's rating appended as
    /// the prompt appends it.
    private func capturedSession() async throws -> CaptureReplay {
        let replay = try CaptureReplay("full")
        try await replay.run(stoppingBefore: ["answer"])
        let ratingId = WatchSessionCapture.effortRatingId(replay.sessionId)
        _ = try await replay.engine.appendObservation([
            "entryId": ratingId,
            "eventId": ratingId,
            "kind": WatchObservationKind.effortRating,
            "loggedAt": "2026-09-25T10:55:20.000Z",
            "rating": 4,
        ])
        return replay
    }

    func testS237TheLogIsReleasedOnlyOnceTheSessionEndIsAcknowledged() async throws {
        let replay = try await capturedSession()
        let engine = replay.engine!
        let samples = engine.sensorSamples.count
        XCTAssertGreaterThan(samples, 0, "S-237 F-CAP full records heart rate and steps")

        _ = await engine.confirmObservations(
            [
                "e-run", "e-r1", "e-r2", "e-r3", "e-set1", "e-set2", "e-set3",
                "rec-15-rest", "rec-17-rest", "rec-19-rest",
            ]
        )
        let afterEntries = await engine.pruneSettledSensorSamples()
        XCTAssertEqual(afterEntries, [], "S-237 every effort acknowledged, the end not yet: nothing released")

        _ = await engine.confirmObservations(["rating-s-cap-1"])
        let afterRating = await engine.pruneSettledSensorSamples()
        XCTAssertEqual(afterRating, [], "S-237 the rating acknowledged, the end not yet: still nothing released")
        XCTAssertEqual(engine.sensorSamples.count, samples, "S-237")

        _ = await engine.confirmObservations(["end-s-cap-1"])
        let afterEnd = await engine.pruneSettledSensorSamples()
        XCTAssertEqual(afterEnd.count, samples, "S-237 the end acknowledged: every reading of the session is released")
        XCTAssertTrue(engine.sensorSamples.isEmpty, "S-237")
    }

    func testS237AnEndAcknowledgedAndPrunedStillReleasesTheLog() async throws {
        let replay = try await capturedSession()
        let engine = replay.engine!
        let samples = engine.sensorSamples.count
        _ = await engine.confirmObservations(engine.observations.map(\.entryId))

        // The prunes may run in either order: the end's receipt outlives it.
        _ = await engine.pruneConfirmed()
        await replay.relaunch()
        let released = await replay.engine.pruneSettledSensorSamples()

        XCTAssertEqual(released.count, samples, "S-237 an acknowledged end still counts after it was pruned")
    }

    func testS237ACompletedWristSessionWithNoEndIsNeverReleased() async throws {
        // Seeded the way a store written before session ends existed looks: a
        // session the wrist created, completed, every entry acknowledged, and
        // no end at all.
        let store = InMemoryWatchSessionStore()
        let startedAt = testInstant()
        for (id, status) in [("row-1", WatchSessionStatus.active), ("row-2", WatchSessionStatus.completed)] {
            _ = await store.append(
                .session(
                    WatchSessionRecord(
                        recordId: id,
                        sessionId: "s-legacy",
                        recordedAt: startedAt,
                        startedAt: startedAt,
                        modality: nil,
                        source: "watch",
                        status: status,
                        currentExerciseIndex: 0
                    )
                )
            )
        }
        _ = await store.append(
            .sensorSample(
                WatchSensorSampleRecord(
                    recordId: "sen-legacy",
                    sessionId: "s-legacy",
                    recordedAt: startedAt,
                    kind: WatchSensorKind.heartRate,
                    value: 120
                )
            )
        )

        let engine = await Harness(store: store).runningEngine()
        let released = await engine.pruneSettledSensorSamples()

        XCTAssertEqual(released, [], "S-237 no end, so no summary the phone holds: the readings stay")
        let stored = await store.readAll()
        XCTAssertEqual(stored.sensorSamples.count, 1, "S-237")
        XCTAssertTrue(stored.observations.isEmpty, "a launch does not invent an end for it")
    }

    func testS237ASessionTheWristJoinedOwesNoEnd() async throws {
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage([
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-join",
            "sessionId": "s-phone",
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-07-13T06:00:00Z",
            "payload": [
                "sessionId": "s-phone",
                "revision": 0,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 0,
                "exercises": [exercise("sx-bench")],
                "entries": [[String: Any]](),
                "timers": [String: Any](),
            ] as [String: Any],
        ])
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 110)
        _ = await engine.finishSession()

        let released = await engine.pruneSettledSensorSamples()

        XCTAssertTrue(engine.observations.isEmpty, "S-237 a joined session gets no end (D-120)")
        XCTAssertEqual(released.count, 1, "S-237 so nothing but today's gates holds its log")
    }

    // MARK: - S-239 steps change nothing else

    /// What one scripted run shows the user and asks of the platform.
    private struct Observed: Equatable {
        let heartRate: Double?
        let distance: Double?
        let heartRateSubscriptions: Int
        let locationSubscriptions: Int
        let begun: [String]
        let ended: [String]
        let emitted: Int
        let steps: [Double]
    }

    /// Starts a distance session, feeds every sensor, and stops — on a fresh
    /// watch whose steps permission is `stepsGrant`.
    private func observedRun(stepsGrant: WatchSensorPermission) async throws -> Observed {
        let harness = Harness()
        let source = FakeSensorSource()
        source.stepsGrant = stepsGrant
        let health = FakePlatformStore()
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let sensors = WatchSessionSensors(
            platform: WatchPlatformWorkout(store: health),
            recorder: WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)
        )

        await sensors.start(live)
        source.count(40)
        if stepsGrant == .granted {
            await eventually(
                { engine.sensorSamples.contains { $0.kind == WatchSensorKind.steps } },
                "S-239 with permission, the count reaches storage"
            )
        }
        source.beat(131)
        await eventually { sensors.recorder.readings.heartRate == 131 }
        source.fix(900)
        await eventually { sensors.recorder.readings.distanceMeters == 900 }
        harness.clock.advance(60)
        await sensors.stop()
        defer { source.close() }

        return Observed(
            heartRate: sensors.recorder.readings.heartRate,
            distance: sensors.recorder.readings.distanceMeters,
            heartRateSubscriptions: source.heartRateSubscriptions,
            locationSubscriptions: source.locationSubscriptions,
            begun: health.begun,
            ended: health.ended,
            emitted: harness.emitted.count,
            steps: engine.sensorSamples.filter { $0.kind == WatchSensorKind.steps }.map(\.value)
        )
    }

    func testS239StepsPermissionChangesNothingButTheStepsRecorded() async throws {
        let granted = try await observedRun(stepsGrant: .granted)
        let denied = try await observedRun(stepsGrant: .denied)

        XCTAssertEqual(granted.steps, [40], "S-239 with permission, the count is stored")
        XCTAssertEqual(denied.steps, [], "S-239 without it, nothing is")
        XCTAssertEqual(granted.heartRate, denied.heartRate, "S-239 the heart-rate readout is identical")
        XCTAssertEqual(granted.distance, denied.distance, "S-239 the distance readout is identical")
        XCTAssertEqual(granted.heartRateSubscriptions, denied.heartRateSubscriptions, "S-239")
        XCTAssertEqual(
            granted.locationSubscriptions,
            denied.locationSubscriptions,
            "S-239 the GPS subscription decision is identical"
        )
        XCTAssertEqual(granted.begun, denied.begun, "S-239 the platform workout begins identically")
        XCTAssertEqual(granted.ended, denied.ended, "S-239 and ends identically")
        XCTAssertEqual(
            granted.emitted,
            denied.emitted,
            "S-239 a stored count adds nothing to the outbound stream"
        )
    }

    func testS239StoppingEndsTheStepsSubscription() async throws {
        source.stepsGrant = .granted
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting")
        let sensors = sensors(for: engine)

        await sensors.start(live)
        XCTAssertEqual(source.stepsSubscriptions, 1, "S-239 steps are counted whatever the modality")
        source.count(12)
        await eventually { engine.sensorSamples.contains { $0.kind == WatchSensorKind.steps } }

        await sensors.stop()
        await eventually({ self.source.stepsStreamEnded }, "S-239 stop cancels the steps subscription")
    }

    func testS239EveryStreamReachesTheEngineOneReadingAtATime() async throws {
        let store = ContendedWatchSessionStore()
        let harness = Harness(store: store)
        source.stepsGrant = .granted
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let recorder = WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)
        await recorder.start(live)

        for second in 1...5 {
            harness.clock.advance(1)
            // Three sensors delivering at once, as a run's do.
            source.beat(Double(100 + second))
            source.count(Double(second * 10))
            source.fix(Double(second * 100))
            await eventually { engine.sensorSamples.count == second * 3 }
        }

        let contended = await store.contended
        XCTAssertEqual(
            contended,
            0,
            "S-239 a second always-on sensor must not make two writers: every reading waits for the one before it"
        )
        await recorder.stop()
    }

    func testS239AppendingAStepCountEmitsNothing() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "resistance_lifting")
        let before = harness.emitted.count

        await engine.appendSensorSample(kind: WatchSensorKind.steps, value: 250)
        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 101)

        XCTAssertEqual(engine.sensorSamples.count, 2)
        XCTAssertEqual(harness.emitted.count, before, "S-239 raw readings, steps included, never leave the wrist")
    }

    // MARK: - Sensor wiring

    func testStartingASessionClosesTheWorkoutTheLastOneLeftOpen() async throws {
        let engine = await harness.runningEngine()
        let sensors = sensors(for: engine)

        await sensors.start(await session(engine, modality: "resistance_lifting"))
        // D-177 refuses a second start over a live session, so the first closes here.
        _ = await engine.finishSession()
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
        // Two frames, not one: D-91 has the start send its lifecycle and then the
        // snapshot the phone adopts the session from.
        XCTAssertEqual(harness.emitted.count, 2, "starting a session tells the phone")

        await engine.appendSensorSample(kind: WatchSensorKind.heartRate, value: 132)

        XCTAssertEqual(engine.sensorSamples.count, 1)
        XCTAssertEqual(
            harness.emitted.count,
            2,
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

    func testAMeasuredDistanceIsWhatTheObservationCarries() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "cardio_endurance", capabilities: ["time", "distance"])
        let sensors = sensors(for: engine)
        await sensors.start(try XCTUnwrap(engine.session))
        source.fix(3200)
        await eventually { sensors.recorder.readings.distanceMeters == 3200 }

        let state = WatchLoggingState(engine: engine, clock: clock.call, sensors: sensors.recorder)

        XCTAssertTrue(state.isMeasuringDistance, "the fix is being kept")
        XCTAssertTrue(
            state.fields.isEmpty,
            "a timed surface has no distance row, so there is no dial for a measurement to outrank"
        )
        state.adjust(WatchMetricKey.distance, detents: 15)

        await state.startWork()
        clock.advance(1200)
        let logged = try await state.log()

        XCTAssertEqual(
            logged.payload["distanceMeters"] as? Double,
            3200,
            "the phone receives the measured total, not a number the user added to it"
        )
    }
}

/// S-239: every sensor scenario above, again, with the user having refused
/// steps. Steps are a sensor of their own — the heart rate, the distance, the
/// GPS decision and the platform workout must not notice the difference.
final class WatchSensorRecordingStepsDeniedTests: WatchSensorRecordingTests {
    override class var stepsGrant: WatchSensorPermission { .denied }
}

/// A store whose appends take a moment, as a disk write does, and that counts
/// every append arriving while another is still in flight — a second writer
/// the engine was not built for. It lets such an append wait its turn, so the
/// count is the finding rather than a crash.
final class ContendedWatchSessionStore: WatchSessionStore {
    private let inner = InMemoryWatchSessionStore()
    private let gate = AppendGate()

    var contended: Int {
        get async { await gate.contended }
    }

    func append(_ record: StoredWatchRecord) async -> StoredWatchRecord {
        await gate.enter()
        try? await Task.sleep(nanoseconds: 2_000_000)
        let stored = await inner.append(record)
        await gate.leave()
        return stored
    }

    func readAll() async -> WatchStoreContents { await inner.readAll() }

    func pruneConfirmed() async -> [String] { await inner.pruneConfirmed() }

    func pruneSensorSamples(_ sessionIds: [String]) async -> [String] {
        await inner.pruneSensorSamples(sessionIds)
    }
}

/// One append at a time, counting the ones that had to wait.
actor AppendGate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var contended = 0

    func enter() async {
        guard busy else {
            busy = true
            return
        }
        contended += 1
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
