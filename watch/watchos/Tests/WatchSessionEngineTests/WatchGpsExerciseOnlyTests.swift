//
//  WatchGpsExerciseOnlyTests.swift
//  WatchSessionEngineTests
//
//  Phase P1b of
//  `docs/plans/2026-11-15-205-gps-by-exercise-plan/2026-11-15-205-gps-by-exercise-plan.md`:
//  the scenarios where "GPS follows the exercise, never the modality" is
//  pinned — a Sports or Cardio session whose exercise carries no distance asks
//  for no location, no outdoor registration and no radio, and a Cardio session
//  on a timed exercise starts location late, when the user reaches one that
//  does carry distance.
//
//  Scenario mapping:
//    S-20501 Boxing under Sports is indoor                    → `testS20501...`
//    S-20502 a walk under Cardio is outdoor                   → `testS20502...`
//    S-20503 a stationary bike under Cardio stays GPS         → `testS20503...`
//    S-20504 a Cardio-focus routine of squats asks for no GPS → `testS20504...`
//    S-20505 a Sports exercise without distance is indoor     → `testS20505...`
//    S-20506 a free workout decides by the exercise, as before→ `testS20506...`
//    S-20507 jump rope under Cardio, then the run starts late → `testS20507...`
//
//  Fixtures are copied from `WatchOutdoorWorkoutTests` (the recording outdoor
//  store) and `WatchGpsByExerciseTests` (the counting source seam, the slot
//  builder, the S-4802 move-and-notify pattern). Production code is read, not
//  edited: the modality arm is gone, and these tests hold the new answers.
//

import XCTest

@testable import WatchSessionEngine

final class WatchGpsExerciseOnlyTests: XCTestCase {

    /// An outdoor-aware store recording the pair it was given, so the activity
    /// name and the outdoors answer are one recorded call rather than two that
    /// could drift apart. (From `WatchOutdoorWorkoutTests`, nested here so the
    /// two test files own their own fixtures.)
    private final class RecordingOutdoorPlatformStore: WatchPlatformWorkoutStore {
        private(set) var begins: [(activityType: String, outdoors: Bool)] = []

        func begin(_ activityType: String, outdoors: Bool) async {
            begins.append((activityType, outdoors))
        }

        func end() async {}

        func inProgressActivityTypes() async -> [String] { [] }
    }

    /// The counting seam over the shared fake: `locationSubscriptions` is what
    /// "the radio was woken" means here. (From `WatchGpsByExerciseTests`.)
    private final class CountingSensorSource: WatchSensorSource {
        private let inner = FakeSensorSource()

        var locationSubscriptions: Int { inner.locationSubscriptions }

        func fix(_ cumulativeMetres: Double) { inner.fix(cumulativeMetres) }

        func heartRatePermission() async -> WatchSensorPermission {
            await inner.heartRatePermission()
        }

        func locationPermission() async -> WatchSensorPermission {
            await inner.locationPermission()
        }

        func stepsPermission() async -> WatchSensorPermission {
            await inner.stepsPermission()
        }

        func heartRate() -> AsyncStream<Double> { inner.heartRate() }

        func location() -> AsyncStream<WatchLocationFix> { inner.location() }

        func steps() -> AsyncStream<Double> { inner.steps() }

        func close() { inner.close() }
    }

    // MARK: - fixtures

    /// One named slot carrying `capabilities`, with exercise ids unlike any
    /// default so an id collision cannot be mistaken for a pass.
    private func slot(
        _ id: String,
        _ name: String,
        _ capabilities: [String]
    ) -> [String: Any] {
        [
            "sessionExerciseId": id,
            "exerciseId": "ex-g205-\(id)",
            "name": name,
            "capabilities": capabilities,
        ]
    }

    private func boxingSlot() -> [String: Any] {
        slot("sx-g205-boxing", "Heavy Bag Rounds", ["time", "rounds"])
    }

    private func walkSlot() -> [String: Any] {
        slot("sx-g205-walk", "Brisk Walk", ["time", "distance"])
    }

    private func bikeSlot() -> [String: Any] {
        slot("sx-g205-bike", "Stationary Bike", ["time", "distance"])
    }

    private func soccerSlot() -> [String: Any] {
        slot("sx-g205-soccer", "Soccer Match", ["time", "rounds"])
    }

    private func jumpRopeSlot() -> [String: Any] {
        slot("sx-g205-rope", "Jump Rope", ["time"])
    }

    private func runSlot() -> [String: Any] {
        slot("sx-g205-run", "Running", ["time", "distance"])
    }

    private func squatSlot() -> [String: Any] {
        slot("sx-g205-squat", "Squat", ["reps", "sets", "load"])
    }

    /// A recorder over this test's counting source, on the harness clock.
    private func makeRecorder(
        _ engine: WatchSessionEngine,
        _ source: CountingSensorSource,
        _ harness: Harness
    ) -> WatchSensorRecorder {
        WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)
    }

    // MARK: - S-20501 Boxing under Sports is indoor

    func testS20501BoxingUnderSportsIsIndoor() async {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "sports",
            exercises: [boxingSlot()]
        )
        let source = CountingSensorSource()
        defer { source.close() }

        XCTAssertFalse(
            WatchGpsPolicy.isRequired(session),
            "S-20501: the modality alone is no longer GPS work (plan 205)"
        )

        let store = RecordingOutdoorPlatformStore()
        await WatchPlatformWorkout(store: store).start(session)
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [false],
            "S-20501: the workout is registered as indoor work"
        )
        XCTAssertEqual(
            store.begins.map(\.activityType),
            ["other"],
            "S-20501: the Health type is unchanged (D-20505)"
        )

        let recorder = makeRecorder(engine, source, harness)
        await recorder.start(session)
        XCTAssertEqual(
            source.locationSubscriptions,
            0,
            "S-20501: the recorder on a boxing round opens no location feed"
        )
    }

    // MARK: - S-20502 a walk under Cardio is outdoor

    func testS20502AWalkUnderCardioIsOutdoor() async {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [walkSlot()]
        )
        let source = CountingSensorSource()
        defer { source.close() }

        XCTAssertTrue(
            WatchGpsPolicy.isRequired(session),
            "S-20502: the walk carries distance, so the exercise asks for GPS"
        )

        let store = RecordingOutdoorPlatformStore()
        await WatchPlatformWorkout(store: store).start(session)
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [true],
            "S-20502: the workout is registered as outdoor work"
        )

        let recorder = makeRecorder(engine, source, harness)
        await recorder.start(session)
        XCTAssertEqual(
            source.locationSubscriptions,
            1,
            "S-20502: the permission is granted in the fake, so the radio wakes"
        )
    }

    // MARK: - S-20503 a stationary bike under Cardio stays GPS

    func testS20503AStationaryBikeUnderCardioStaysGpsUntilAnIndoorFlagExists() async {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [bikeSlot()]
        )
        let source = CountingSensorSource()
        defer { source.close() }

        // The accepted consequence of plan 205 (owner, 2026-11-15): the bike
        // carries `distance`, so it is GPS work today. A later per-exercise
        // indoor marker changes this knowingly.
        XCTAssertTrue(
            WatchGpsPolicy.isRequired(session),
            "S-20503: the exercise's capabilities decide, even for indoor work"
        )

        let store = RecordingOutdoorPlatformStore()
        await WatchPlatformWorkout(store: store).start(session)
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [true],
            "S-20503: the outdoor flag follows the capabilities today"
        )
    }

    // MARK: - S-20505 a Sports exercise without distance is indoor

    func testS20505ASportsExerciseWithoutDistanceIsIndoor() async {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "sports",
            exercises: [soccerSlot()]
        )
        let source = CountingSensorSource()
        defer { source.close() }

        XCTAssertFalse(
            WatchGpsPolicy.isRequired(session),
            "S-20505: a match's capabilities cover no distance"
        )

        let store = RecordingOutdoorPlatformStore()
        await WatchPlatformWorkout(store: store).start(session)
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [false],
            "S-20505: the workout is registered as indoor work"
        )

        let recorder = makeRecorder(engine, source, harness)
        await recorder.start(session)
        XCTAssertEqual(
            source.locationSubscriptions,
            0,
            "S-20505: no location subscription for a match"
        )
    }

    // MARK: - S-20507 jump rope under Cardio, then the run starts location late

    func testS20507CardioOnJumpRopeThenTheRunStartsLocationLate() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let live = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [jumpRopeSlot(), runSlot()]
        )
        let source = CountingSensorSource()
        defer { source.close() }

        let store = RecordingOutdoorPlatformStore()
        await WatchPlatformWorkout(store: store).start(live)
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [false],
            "S-20507: the flag is fixed at begin by the first exercise (D-20502)"
        )

        let recorder = makeRecorder(engine, source, harness)
        await recorder.start(live)
        XCTAssertEqual(
            source.locationSubscriptions,
            0,
            "S-20507: jump rope carries no distance, so the radio stays off"
        )

        // The S-4802 move: the user reaches the run, and the recorder is told
        // the session changed.
        await engine.selectExercise(slotId: "sx-g205-run")
        let moved = try XCTUnwrap(engine.session)
        await recorder.sessionChanged(moved)

        XCTAssertEqual(
            source.locationSubscriptions,
            1,
            "S-20507: the run starts location late, with no modality help"
        )
        XCTAssertTrue(recorder.isMeasuringDistance)

        XCTAssertEqual(
            store.begins.count,
            1,
            "S-20507: the platform workout was never restarted by the move"
        )
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [false],
            "S-20507: and the outdoors flag it was given never changes (D-20502)"
        )
    }

    // MARK: - S-20506 a free workout decides by the exercise, as before

    func testS20506AFreeWorkoutDecidesByTheExerciseExactlyAsBefore() async {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: nil)

        XCTAssertFalse(
            WatchGpsPolicy.isRequired(live),
            "S-20506: no exercise yet, so nothing asks for GPS"
        )

        let picked = await engine.insertExercise(runSlot(), moveTo: true)
        XCTAssertTrue(
            WatchGpsPolicy.isRequired(picked),
            "S-20506: the run the user picked carries distance, so it asks"
        )
    }

    // MARK: - S-20504 a Cardio-focus routine of squats asks for no GPS

    func testS20504ACardioFocusRoutineOfSquatsAsksForNoGps() async {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [squatSlot()]
        )
        let source = CountingSensorSource()
        defer { source.close() }

        XCTAssertFalse(
            WatchGpsPolicy.isRequired(session),
            "S-20504: the squat covers no distance, so no GPS is asked"
        )

        XCTAssertEqual(
            WatchActivityTypes.forSession(session)?.watchOs,
            "running",
            "S-20504: the Health type is unchanged (D-20505)"
        )
    }
}
