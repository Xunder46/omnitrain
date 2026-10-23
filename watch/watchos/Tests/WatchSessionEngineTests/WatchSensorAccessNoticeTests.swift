//
//  WatchSensorAccessNoticeTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-10-23-59-health-and-location-access-plan/2026-10-23-59-health-and-location-access-plan.md`
//  — a refused Health or Location permission is remembered by the recorder and
//  turned into a short notice line by the logging state, instead of being
//  swallowed.
//
//  Scenario mapping:
//    S-8901 the recorder remembers the heart-rate answer   → `testS8901...`
//    S-8902 stop returns both answers to nil               → `testS8902...`
//    S-8903 location is asked only where distance is possible → `testS8903...`
//    S-8904 the state's heart-rate notice                  → `testS8904...`
//    S-8905 the distance notice follows the current exercise → `testS8905...`
//    S-8906 no sensors, or an unavailable permission, says nothing → `testS8906...`
//    S-8907 WatchHealthAccess.answer and the Start line's copy → `testS8907...`
//

import XCTest

@testable import WatchSessionEngine

final class WatchSensorAccessNoticeTests: XCTestCase {

    private var harness: Harness!
    private var source: FakeSensorSource!

    override func setUp() {
        super.setUp()
        harness = Harness()
        source = FakeSensorSource()
    }

    override func tearDown() {
        source.close()
        super.tearDown()
    }

    private func makeRecorder(for engine: WatchSessionEngine) -> WatchSensorRecorder {
        WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)
    }

    private func session(
        _ engine: WatchSessionEngine,
        modality: String?,
        exercises: [[String: Any]]
    ) async -> WatchSessionRecord {
        await engine.createSession(modality: modality, exercises: exercises)
    }

    private func liftSlot(_ slot: String) -> [String: Any] {
        [
            "sessionExerciseId": slot,
            "exerciseId": "ex-\(slot)",
            "name": slot,
            "capabilities": ["reps", "sets", "load"],
        ]
    }

    private func runSlot(_ slot: String) -> [String: Any] {
        [
            "sessionExerciseId": slot,
            "exerciseId": "ex-\(slot)",
            "name": slot,
            "capabilities": ["time", "distance"],
        ]
    }

    // MARK: - S-8901 the recorder remembers what the platform answered

    func testS8901HeartRateAccessIsNilBeforeStartAndTheAnswerAfter() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting", exercises: [liftSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        XCTAssertNil(recorder.heartRateAccess, "S-8901 before start nothing has been asked")

        source.heartRateGrant = .denied
        await recorder.start(live)
        XCTAssertEqual(recorder.heartRateAccess, .denied, "S-8901 a refusal is remembered")

        let grantedRecorder = makeRecorder(for: engine)
        source.heartRateGrant = .granted
        await grantedRecorder.start(live)
        XCTAssertEqual(grantedRecorder.heartRateAccess, .granted, "S-8901 an allowance is remembered")
    }

    // MARK: - S-8902 stop clears both answers

    func testS8902StopReturnsBothAccessesToNil() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "cardio_endurance", exercises: [runSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.heartRateGrant = .denied
        source.locationGrant = .denied
        await recorder.start(live)
        XCTAssertEqual(recorder.heartRateAccess, .denied)
        XCTAssertEqual(recorder.locationAccess, .denied)

        await recorder.stop()
        XCTAssertNil(recorder.heartRateAccess, "S-8902 stop clears the heart-rate answer")
        XCTAssertNil(recorder.locationAccess, "S-8902 stop clears the location answer")
    }

    // MARK: - S-8903 location is asked only for work that can cover distance

    func testS8903ADeniedLocationOnADistanceSessionIsRemembered() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "cardio_endurance", exercises: [runSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.locationGrant = .denied
        await recorder.start(live)

        XCTAssertEqual(recorder.locationAccess, .denied, "S-8903 a distance session asks, and remembers")
    }

    func testS8903ALiftSessionNeverAsksSoTheAnswerStaysNil() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting", exercises: [liftSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.locationGrant = .denied
        await recorder.start(live)

        XCTAssertNil(recorder.locationAccess, "S-8903 a lift never asks, so nothing is remembered")
    }

    // MARK: - S-8904 the state's heart-rate notice

    func testS8904ADeniedHeartRateBecomesTheNoticeLine() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting", exercises: [liftSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.heartRateGrant = .denied
        await recorder.start(live)
        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )

        XCTAssertEqual(
            surface.sensorNotices,
            [WatchSensorNoticeCopy.noHeartRate],
            "S-8904 a refused heart rate is one line, heart rate first"
        )
    }

    func testS8904AGrantedHeartRateSaysNothing() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting", exercises: [liftSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.heartRateGrant = .granted
        await recorder.start(live)
        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )

        XCTAssertEqual(surface.sensorNotices, [], "S-8904 an allowance adds no line")
    }

    func testS8904TheHeartRateNoticeTextIsExact() {
        XCTAssertEqual(
            WatchSensorNoticeCopy.noHeartRate,
            "No heart rate, Health access is off"
        )
    }

    // MARK: - S-8905 the distance notice follows the current exercise

    func testS8905TheDistanceNoticeShowsOnTheRunAndNotOnTheLift() async throws {
        let engine = await harness.runningEngine()
        let live = await session(
            engine,
            modality: nil,
            exercises: [runSlot("sx-run"), liftSlot("sx-lift")]
        )
        let recorder = makeRecorder(for: engine)

        source.locationGrant = .denied
        await recorder.start(live)
        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )

        XCTAssertTrue(
            surface.sensorNotices.contains(WatchSensorNoticeCopy.noDistance),
            "S-8905 on the run the refused location is a line"
        )

        _ = await engine.selectExercise(slotId: "sx-lift")
        XCTAssertNil(
            surface.sensorNotices.first(where: { $0 == WatchSensorNoticeCopy.noDistance }),
            "S-8905 on the lift the distance line is gone"
        )
    }

    func testS8905BothRefusalsReadHeartRateFirstThenDistance() async throws {
        let engine = await harness.runningEngine()
        let live = await session(
            engine,
            modality: nil,
            exercises: [runSlot("sx-run"), liftSlot("sx-lift")]
        )
        let recorder = makeRecorder(for: engine)

        source.heartRateGrant = .denied
        source.locationGrant = .denied
        await recorder.start(live)
        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )

        XCTAssertEqual(
            surface.sensorNotices,
            [WatchSensorNoticeCopy.noHeartRate, WatchSensorNoticeCopy.noDistance],
            "S-8905 both lines, heart rate first"
        )
    }

    func testS8905TheDistanceNoticeTextIsExact() {
        XCTAssertEqual(
            WatchSensorNoticeCopy.noDistance,
            "No distance, Location access is off"
        )
    }

    // MARK: - S-8906 what says nothing

    func testS8906NoSensorsMeansNoNotices() async throws {
        let engine = await harness.runningEngine()
        _ = await session(engine, modality: "resistance_lifting", exercises: [liftSlot("sx-1")])
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.sensorNotices, [], "S-8906 a view with no sensors says nothing")
    }

    func testS8906AnUnavailablePermissionSaysNothing() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting", exercises: [liftSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.heartRateGrant = .unavailable
        await recorder.start(live)
        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )

        XCTAssertEqual(
            surface.sensorNotices,
            [],
            "S-8906 hardware that cannot give the sensor is not a refusal"
        )
    }

    // MARK: - S-8907 the pre-workout answer and its copy

    func testS8907TheAnswerFollowsAvailabilityAndGrant() {
        XCTAssertEqual(WatchHealthAccess.answer(available: false, granted: false), .unavailable)
        XCTAssertEqual(WatchHealthAccess.answer(available: false, granted: true), .unavailable)
        XCTAssertEqual(WatchHealthAccess.answer(available: true, granted: true), .allowed)
        XCTAssertEqual(WatchHealthAccess.answer(available: true, granted: false), .off)
    }

    func testS8907TheStartScreenLineTextIsExact() {
        XCTAssertEqual(
            WatchHealthAccessCopy.offLine,
            "Health access is off. Turn it on in Health on your iPhone."
        )
    }
}
