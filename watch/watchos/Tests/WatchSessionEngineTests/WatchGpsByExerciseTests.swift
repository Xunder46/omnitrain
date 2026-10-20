//
//  WatchGpsByExerciseTests.swift
//  WatchSessionEngineTests
//
//  Phase 1A of
//  `docs/plans/2026-10-18-40-watch-gps-by-exercise-plan/2026-10-18-40-watch-gps-by-exercise-plan.md`:
//  for a session that carries no modality — free training, or one started from a
//  routine — what decides whether the wrist records GPS is the exercise the user
//  is on, not a profile the session does not have.
//
//  Scenario mapping:
//    S-4800 a walk in a free workout starts GPS                 → `testS4800...`
//    S-4801 a lift never starts GPS and never asks              → `testS4801...`
//    S-4802 GPS starts when the user reaches the walk           → `testS4802...`
//    S-4803 the latch across the exercises                      → `testS4803...`
//    S-4804 refused once is not asked again                     → `testS4804...`
//    S-4805 idempotent across refreshes                         → `testS4805...`
//    S-4806 a distance modality still starts GPS                → `testS4806...`
//    S-4807 the workout is registered outdoors by the first exercise → `testS4807...`
//    S-4808 a late start still logs the right metres            → `testS4808...`
//    S-4809 the contract cases (Swift)                          → `testS4809...`
//    S-4811 a phone snapshot moves the user onto a walk         → `testS4811...`
//    S-4812 a slot with no `capabilities` key is no GPS work    → `testS4812...`
//    S-4813 a routine that begins with a run                    → `testS4813...`,
//           and its GPS half                                   → `testS4813b...`
//    S-4814 two sessions in a row                               → `testS4814...`
//    S-4815 `.unavailable` is answered once, like denied        → `testS4815...`
//
//  `watch/contract/watch_sensor_contract.json` is read rather than restated, so
//  the capability rule is the same on both watch clients. The sensor layer
//  behind the workout is `WatchSensorRecordingTests`': this file adds the cases
//  where the session's modality was never the decider.
//

import XCTest

@testable import WatchSessionEngine

/// `FakeSensorSource` is shared and closed to subclassing, so this wrapper is
/// the counting seam: every call forwards to the fake, and the location probe
/// is counted here rather than assumed.
final class CountingSensorSource: WatchSensorSource {
    private let inner = FakeSensorSource()

    /// How often the location permission was asked about — the read S-4812
    /// holds at zero for work that has no distance.
    private(set) var locationPermissionReads = 0

    var locationSubscriptions: Int { inner.locationSubscriptions }

    /// The answer the fake gives, so a test can refuse the probe.
    var locationGrant: WatchSensorPermission {
        get { inner.locationGrant }
        set { inner.locationGrant = newValue }
    }

    func fix(_ cumulativeMetres: Double) { inner.fix(cumulativeMetres) }

    func heartRatePermission() async -> WatchSensorPermission { await inner.heartRatePermission() }

    func locationPermission() async -> WatchSensorPermission {
        locationPermissionReads += 1
        return await inner.locationPermission()
    }

    func stepsPermission() async -> WatchSensorPermission { await inner.stepsPermission() }

    func heartRate() -> AsyncStream<Double> { inner.heartRate() }

    func location() -> AsyncStream<WatchLocationFix> { inner.location() }

    func steps() -> AsyncStream<Double> { inner.steps() }

    func close() { inner.close() }
}

/// An outdoor-aware store recording the pair it was given, so the activity name
/// and the outdoors answer are one recorded call rather than two that could
/// drift apart.
final class RecordingGpsOutdoorStore: WatchPlatformWorkoutStore {
    private(set) var begins: [(activityType: String, outdoors: Bool)] = []

    func begin(_ activityType: String, outdoors: Bool) async {
        begins.append((activityType, outdoors))
    }

    func end() async {}

    func inProgressActivityTypes() async -> [String] { [] }
}

final class WatchGpsByExerciseTests: XCTestCase {

    private var source: CountingSensorSource!
    private var harness: Harness!

    override func setUp() {
        super.setUp()
        source = CountingSensorSource()
        harness = Harness()
    }

    override func tearDown() {
        source.close()
        super.tearDown()
    }

    /// One protocol slot carrying `capabilities`.
    private func slot(_ capabilities: [String]) -> [String: Any] {
        [
            "sessionExerciseId": "sx-1",
            "exerciseId": "ex-1",
            "name": "sx-1",
            "capabilities": capabilities,
        ]
    }

    /// One named slot carrying `capabilities` — the ladder fixtures need ids a
    /// pick can name.
    private func slot(
        _ id: String,
        _ name: String,
        _ capabilities: [String]
    ) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": name,
            "capabilities": capabilities,
        ]
    }

    private func walkSlot(_ id: String = "sx-walk") -> [String: Any] {
        slot(id, "Walking", ["time", "distance"])
    }

    private func liftSlot(_ id: String = "sx-bench") -> [String: Any] {
        slot(id, "Bench", ["reps", "sets", "load"])
    }

    /// A recorder over this test's counting source, on the harness clock.
    private func makeRecorder(_ engine: WatchSessionEngine) -> WatchSensorRecorder {
        WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)
    }

    private func gpsSamples(_ engine: WatchSessionEngine) -> [WatchSensorSampleRecord] {
        engine.sensorSamples.filter { $0.kind == WatchSensorKind.gps }
    }

    /// One `start` of a session on a watch of its own, over the recording store.
    ///
    /// `capabilities` nil means a session with no slots at all — what free
    /// training starts as, before the user picks anything.
    private func assertStart(
        modality: String?,
        capabilities: [String]?,
        activityType: String,
        outdoors: Bool,
        _ label: String
    ) async {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let live: WatchSessionRecord
        if let capabilities {
            live = await engine.createSession(modality: modality, exercises: [slot(capabilities)])
        } else {
            live = await engine.createSession(modality: modality)
        }

        let store = RecordingGpsOutdoorStore()
        await WatchPlatformWorkout(store: store).start(live)

        XCTAssertEqual(
            store.begins.map(\.activityType),
            [activityType],
            "\(label): the type is the modality's own, or the generic one"
        )
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [outdoors],
            "\(label): outdoors follows a capability, never a name (S-4807)"
        )
    }

    // MARK: - S-4807 the workout is registered outdoors by the first exercise

    func testS4807TheWorkoutIsRegisteredOutdoorsByTheExerciseTheUserIsOn() async {
        await assertStart(
            modality: nil,
            capabilities: ["time", "distance"],
            activityType: "other",
            outdoors: true,
            "a free workout on a distance exercise"
        )
        await assertStart(
            modality: nil,
            capabilities: ["reps", "sets", "load"],
            activityType: "other",
            outdoors: false,
            "a free workout on a lift"
        )
        await assertStart(
            modality: nil,
            capabilities: nil,
            activityType: "other",
            outdoors: false,
            "a free workout before the first pick"
        )
        await assertStart(
            modality: "resistance_lifting",
            capabilities: ["reps", "sets", "load"],
            activityType: "traditionalStrengthTraining",
            outdoors: false,
            "a lift on a lift's own modality"
        )
    }

    // MARK: - S-4809 the contract cases

    func testS4809TheContractCasesDecideCoverage() throws {
        let cases = try XCTUnwrap(
            try Fixtures.sensorContract()["exerciseGpsCases"] as? [[String: Any]]
        )
        XCTAssertEqual(cases.count, 7, "the contract seeds seven cases (D-4804)")

        for entry in cases {
            let capabilities = try XCTUnwrap(entry["capabilities"] as? [String])
            let gps = try XCTUnwrap(entry["gps"] as? Bool)
            XCTAssertEqual(
                WatchGpsPolicy.coversDistance(capabilities),
                gps,
                "\(capabilities) covers distance: \(gps)"
            )
        }
    }

    // MARK: - S-4812 a slot with no `capabilities` key is no GPS work

    func testS4812ASlotWithNoCapabilitiesKeyIsNoGpsWork() async {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let live = await engine.createSession(
            modality: nil,
            exercises: [[
                "sessionExerciseId": "sx-1",
                "exerciseId": "ex-1",
                "name": "sx-1",
            ]]
        )

        XCTAssertFalse(
            WatchGpsPolicy.isRequired(live),
            "a slot that declares no capabilities is no GPS work"
        )

        let recorder = WatchSensorRecorder(
            engine: engine,
            source: source,
            clock: harness.clock.call
        )
        let sensors = WatchSessionSensors(
            platform: WatchPlatformWorkout(store: FakePlatformStore()),
            recorder: recorder
        )
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        await sensors.start(live)
        for _ in 0..<3 { await coordinator.refresh(live) }

        XCTAssertEqual(source.locationSubscriptions, 0, "no location subscription is made")
        XCTAssertEqual(
            source.locationPermissionReads,
            0,
            "and the permission is never asked about"
        )
    }

    // MARK: - S-4813 the first exercise decides, not the routine's name

    func testS4813ARoutineThatBeginsWithARunIsOutdoorWork() async throws {
        let harness = WatchStartHarness()
        let result = await harness.paths.applyRoutinesDown(try routinesDownBeginningWithARun())
        XCTAssertTrue(result.applied, "the contract's edited routine survives the validator")

        let live = try await harness.paths.startFromRoutine("routine-push-a")
        XCTAssertEqual(
            live.currentExercise?["capabilities"] as? [String],
            ["time", "distance"],
            "the session begins on the routine's first effort"
        )

        let store = RecordingGpsOutdoorStore()
        await WatchPlatformWorkout(store: store).start(live)

        XCTAssertEqual(store.begins.map(\.activityType), ["other"])
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [true],
            "the exercise the routine starts on is what makes the work outdoors (S-4813)"
        )
    }

    // MARK: - S-4800 a walk in a free workout starts GPS

    func testS4800AWalkInAFreeWorkoutStartsGps() async {
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: nil, exercises: [walkSlot()])
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        await coordinator.refresh(live)

        XCTAssertEqual(
            source.locationSubscriptions,
            1,
            "the exercise the user is on carries distance, so the radio is woken"
        )
        XCTAssertTrue(recorder.isMeasuringDistance)

        source.fix(300)
        await eventually { recorder.readings.distanceMeters == 300 }
    }

    // MARK: - S-4801 a lift never starts GPS and never asks

    func testS4801ALiftNeverStartsGpsAndNeverAsks() async {
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: nil, exercises: [liftSlot()])
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        for _ in 0..<3 { await coordinator.refresh(live) }

        XCTAssertEqual(source.locationSubscriptions, 0, "a lift has no distance to measure")
        XCTAssertFalse(recorder.isMeasuringDistance)
        XCTAssertEqual(
            source.locationPermissionReads,
            0,
            "and the user is never asked for a radio the work will not use"
        )
    }

    // MARK: - S-4802 GPS starts when the user reaches the walk

    func testS4802GpsStartsWhenTheUserReachesTheWalk() async {
        let engine = await harness.runningEngine()
        let live = await engine.createSession(
            modality: nil,
            exercises: [liftSlot(), walkSlot("sx-run")]
        )
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        await coordinator.refresh(live)
        XCTAssertEqual(source.locationSubscriptions, 0, "the session begins on a lift")

        await engine.selectExercise(slotId: "sx-run")
        await coordinator.refresh(engine.session)

        XCTAssertEqual(
            source.locationSubscriptions,
            1,
            "the refresh after the move follows the exercise the user reached"
        )
        XCTAssertTrue(recorder.isMeasuringDistance)
    }

    // MARK: - S-4803 the latch

    func testS4803TheFeedStaysOnWhenTheUserMovesBackToALift() async throws {
        let engine = await harness.runningEngine()
        let live = await engine.createSession(
            modality: nil,
            exercises: [liftSlot(), walkSlot("sx-run")]
        )
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        await coordinator.refresh(live)
        await engine.selectExercise(slotId: "sx-run")
        await coordinator.refresh(engine.session)
        XCTAssertEqual(source.locationSubscriptions, 1)

        source.fix(400)
        await eventually { recorder.readings.distanceMeters == 400 }

        await engine.selectExercise(slotId: "sx-bench")
        await coordinator.refresh(engine.session)

        XCTAssertTrue(
            recorder.isMeasuringDistance,
            "a latch: moving back to a lift does not stop the feed (S-4803)"
        )
        XCTAssertEqual(source.locationSubscriptions, 1, "and does not subscribe again")

        // Two samples of one kind on one instant are one stored row (D-2211),
        // so the clock moves to the instant the second fix means.
        harness.clock.advance(1)
        source.fix(900)
        await eventually {
            recorder.readings.distanceMeters == 900
        }

        await recorder.stop()

        let settled = engine.sensorSamples.filter { $0.kind == WatchSensorKind.distance }
        XCTAssertEqual(settled.count, 1, "one settled total is written")
        XCTAssertEqual(settled.first?.value, 900, "the cumulative total, not the lift's window")
        XCTAssertFalse(recorder.isMeasuringDistance)
    }

    // MARK: - S-4804 refused once is not asked again

    func testS4804ARefusedSessionIsAskedAboutOnceAndANewOneAgain() async {
        source.locationGrant = .denied
        let engine = await harness.runningEngine()
        let first = await engine.createSession(modality: nil, exercises: [walkSlot()])
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        for _ in 0..<3 { await coordinator.refresh(first) }

        XCTAssertEqual(
            source.locationPermissionReads,
            1,
            "a refused session asks exactly once"
        )
        XCTAssertEqual(source.locationSubscriptions, 0)
        XCTAssertTrue(gpsSamples(engine).isEmpty, "and nothing is recorded")

        let ended = await engine.finishSession()
        await coordinator.refresh(ended)

        let second = await engine.createSession(
            modality: nil,
            exercises: [walkSlot("sx-walk-2")]
        )
        await coordinator.refresh(second)

        XCTAssertEqual(
            source.locationPermissionReads,
            2,
            "the refusal is not carried into the next session"
        )
        XCTAssertEqual(source.locationSubscriptions, 0, "and the answer is still no")
    }

    // MARK: - S-4805 idempotent across refreshes

    func testS4805AGrantedWalkSubscribesOnceHoweverOftenTheSensorsRefresh() async {
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: nil, exercises: [walkSlot()])
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        for _ in 0..<5 { await coordinator.refresh(live) }

        XCTAssertEqual(source.locationSubscriptions, 1)
        XCTAssertTrue(recorder.isMeasuringDistance)
    }

    // MARK: - S-4806 a distance modality still starts GPS with no exercise

    func testS4806ADistanceModalityStartsWithNoExerciseAtAll() async {
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: "cardio_endurance")
        let recorder = makeRecorder(engine)

        await recorder.start(live)

        XCTAssertEqual(
            source.locationSubscriptions,
            1,
            "the old modality rule is intact (S-4806)"
        )
        XCTAssertTrue(recorder.isMeasuringDistance)
    }

    // MARK: - S-4808 a late start still logs the right metres

    func testS4808ALateStartStillLogsTheEffortsMetres() async throws {
        let engine = await harness.runningEngine()
        let clock = harness.clock

        // t0 is the user's Start; the session is already running on nothing.
        let live = await engine.createSession(modality: nil)
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)
        await coordinator.refresh(live)
        XCTAssertEqual(source.locationSubscriptions, 0, "free training before the first pick")

        // t0 − 90 s: the user adds a walk, and the feed starts.
        clock.advance(90)
        await engine.insertExercise(walkSlot(), moveTo: true)
        await coordinator.refresh(engine.session)
        XCTAssertEqual(source.locationSubscriptions, 1)

        let state = WatchLoggingState(engine: engine, clock: clock.call, sensors: recorder)

        // t0 − 30 s: metres covered before Start, which are not this effort's.
        clock.advance(60)
        source.fix(250)
        await eventually { recorder.readings.distanceMeters == 250 }

        // t0: the user starts the effort.
        clock.advance(30)
        await state.startWork()

        // t0 + 300 s: a fix inside the effort's window.
        clock.advance(300)
        source.fix(1050)
        await eventually { recorder.readings.distanceMeters == 1050 }

        // t0 + 600 s: Log.
        clock.advance(300)
        let logged = try await state.log()

        XCTAssertEqual(
            logged.payload["distanceMeters"] as? Double,
            800,
            "1050 − 250: only the metres between Start and Log (D-2205)"
        )
        XCTAssertEqual(logged.payload["distanceSource"] as? String, "gps")
    }

    // MARK: - S-4811 a phone snapshot moves the user onto a walk

    func testS4811APhoneSnapshotMovesTheUserOntoAWalk() async throws {
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: nil, exercises: [liftSlot()])
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        await coordinator.refresh(live)
        XCTAssertEqual(source.locationSubscriptions, 0, "the wrist is on a lift")

        var snapshot = try Fixtures.json("fixtures/valid/session_snapshot.json")
        snapshot["sessionId"] = live.sessionId
        var payload = try XCTUnwrap(snapshot["payload"] as? [String: Any])
        payload["sessionId"] = live.sessionId
        payload["revision"] = 7
        payload["currentExerciseIndex"] = 0
        payload["exercises"] = [walkSlot()]
        payload["entries"] = [[String: Any]]()
        payload["timers"] = [String: Any]()
        snapshot["payload"] = payload

        let applied = try await engine.applyMessage(snapshot)
        XCTAssertTrue(applied, "the phone's snapshot is about this session")

        await coordinator.refresh(engine.session)

        XCTAssertEqual(
            source.locationSubscriptions,
            1,
            "the refresh after the snapshot follows the exercise the phone moved to"
        )
        XCTAssertTrue(recorder.isMeasuringDistance)
    }

    // MARK: - S-4814 two sessions in a row

    func testS4814ASecondSessionMeasuresAgain() async {
        let engine = await harness.runningEngine()
        let first = await engine.createSession(modality: nil, exercises: [walkSlot()])
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        await coordinator.refresh(first)
        XCTAssertEqual(source.locationSubscriptions, 1)
        XCTAssertEqual(source.locationPermissionReads, 1)

        let ended = await engine.finishSession()
        await coordinator.refresh(ended)

        let second = await engine.createSession(
            modality: nil,
            exercises: [walkSlot("sx-walk-2")]
        )
        await coordinator.refresh(second)

        XCTAssertEqual(
            source.locationSubscriptions,
            2,
            "stop() reset the latch, so the next session subscribes again"
        )
        XCTAssertEqual(
            source.locationPermissionReads,
            2,
            "and reset the refusal, so the next session asks again"
        )
        XCTAssertTrue(recorder.isMeasuringDistance)
    }

    // MARK: - S-4815 `.unavailable` is answered once, like denied

    func testS4815UnavailableIsAnsweredOnceLikeDenied() async {
        source.locationGrant = .unavailable
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: nil, exercises: [walkSlot()])
        let recorder = makeRecorder(engine)
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        for _ in 0..<3 { await coordinator.refresh(live) }

        XCTAssertEqual(
            source.locationPermissionReads,
            1,
            "hardware that is not there is an answer, not a question to repeat"
        )
        XCTAssertEqual(source.locationSubscriptions, 0)
        XCTAssertTrue(gpsSamples(engine).isEmpty)
    }

    // MARK: - S-4813 the GPS half: a routine that begins with a run

    func testS4813bTheRoutineStartsGpsWhenItsFirstExerciseCarriesDistance() async throws {
        let start = WatchStartHarness()
        let result = await start.paths.applyRoutinesDown(try routinesDownBeginningWithARun())
        XCTAssertTrue(result.applied)

        let live = try await start.paths.startFromRoutine("routine-push-a")
        let recorder = WatchSensorRecorder(
            engine: start.engine,
            source: source,
            clock: start.clock.call
        )
        let coordinator = WatchSensorCoordinator(recorder: recorder)

        await coordinator.refresh(start.engine.session)

        XCTAssertEqual(
            source.locationSubscriptions,
            1,
            "a routine whose first effort is a run records distance (S-4813b)"
        )
        XCTAssertTrue(recorder.isMeasuringDistance)
        XCTAssertEqual(
            (live.currentExercise?["capabilities"] as? [String])?.contains("distance"),
            true
        )
    }
}

/// The value `[[String: Any]]` at `value`, or a fixture error.
private func objects(_ value: Any?) throws -> [[String: Any]] {
    guard let objects = value as? [[String: Any]] else {
        throw Fixtures.FixtureError.malformed("expected an array of objects")
    }
    return objects
}

/// The value `[String: Any]` at `value`, or a fixture error.
private func object(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw Fixtures.FixtureError.malformed("expected an object")
    }
    return object
}

/// The values the wrist and the phone agree on when a session starts.
private func startPathsContract() throws -> [String: Any] {
    let url = Fixtures.repositoryRoot
        .appendingPathComponent("watch/contract/watch_start_paths_contract.json")
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw Fixtures.FixtureError.malformed("watch_start_paths_contract.json")
    }
    return object
}

/// The contract's `routines_down` with its first effort's capabilities set to
/// distance work: the routine still names the exercise the fallback list covers,
/// and only what the user will be doing changes — the phone would send exactly
/// this for a routine whose first effort is a run.
private func routinesDownBeginningWithARun() throws -> [String: Any] {
    let fallback = try object(try startPathsContract()["fallback"])
    var message = try object(fallback["routinesDown"])
    var payload = try object(message["payload"])

    var routines = try objects(payload["routines"])
    var routine = try object(routines[0])
    var segments = try objects(routine["segments"])
    var segment = try object(segments[0])
    var efforts = try objects(segment["efforts"])
    var effort = try object(efforts[0])

    effort["capabilities"] = ["time", "distance"]
    efforts[0] = effort
    segment["efforts"] = efforts
    segments[0] = segment
    routine["segments"] = segments
    routines[0] = routine
    payload["routines"] = routines

    message["messageId"] = "msg-routines-gps-1"
    message["payload"] = payload
    return message
}
