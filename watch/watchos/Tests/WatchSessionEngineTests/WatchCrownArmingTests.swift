//
//  WatchCrownArmingTests.swift
//  WatchSessionEngineTests
//
//  S-6401 to S-6406 and S-6408 of
//  `docs/plans/2026-10-20-46a-wrist-logging-basics-plan/2026-10-20-46a-wrist-logging-basics-plan.md`
//  — one Crown binding per surface (D-1): the surface arms one row, remembers a
//  single absolute crown position across an arming change, and drops the
//  travel that was still short of a detent when another row is armed.
//
//  A measured row is a reading rather than a value the user dials (S-004), so
//  the Crown may never step it; the surface falls back to the first open row.
//

import Combine
import XCTest

@testable import WatchSessionEngine

final class WatchCrownArmingTests: XCTestCase {

    private func slot(
        _ id: String,
        capabilities: [String],
        roundDurationSecs: Int? = nil
    ) -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
        if let roundDurationSecs {
            slot[WatchCatalogExercise.roundDurationKey] = roundDurationSecs
        }
        return slot
    }

    @MainActor
    private func field(_ model: WatchLoggingModel, _ metricKey: String) -> WatchMetricField {
        model.state.fields.first { $0.metricKey == metricKey }!
    }

    /// The bench set every crown case starts from: reps 10, load 0.
    @MainActor
    private func benchModel(
        _ harness: Harness,
        exercises: [[String: Any]]? = nil
    ) async -> (engine: WatchSessionEngine, model: WatchLoggingModel) {
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: exercises ?? [exercise("sx-bench")]
        )
        let model = WatchLoggingModel(
            state: WatchLoggingState(engine: engine, clock: harness.clock.call),
            haptics: RecordingHaptics()
        )
        return (engine, model)
    }

    // MARK: - S-6401 the fresh surface arms its first row

    @MainActor
    func testS6401AFreshSurfaceArmsTheFirstRow() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(harness)

        XCTAssertEqual(model.armedMetricKey, WatchMetricKey.reps)
        var reps = field(model, WatchMetricKey.reps).value
        XCTAssertEqual(reps, 10)

        let weight = field(model, WatchMetricKey.weight).value
        model.turn(to: WatchLoggingModel.pointsPerDetent)

        reps = field(model, WatchMetricKey.reps).value
        XCTAssertEqual(reps, 11, "one detent steps the armed row by its own step")
        XCTAssertEqual(field(model, WatchMetricKey.weight).value, weight)
    }

    // MARK: - S-6402 arming another row moves the crown there

    @MainActor
    func testS6402ArmingTheWeightRowStepsOnlyTheWeight() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(harness)

        let repStep = field(model, WatchMetricKey.reps).step
        let weightStep = field(model, WatchMetricKey.weight).fineStep
        let reps = field(model, WatchMetricKey.reps).value
        let weight = field(model, WatchMetricKey.weight).value

        model.arm(WatchMetricKey.weight)
        XCTAssertEqual(model.armedMetricKey, WatchMetricKey.weight)

        model.turn(to: WatchLoggingModel.pointsPerDetent)

        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            weight + weightStep,
            "the weight moves by its own increment"
        )
        XCTAssertEqual(
            field(model, WatchMetricKey.reps).value,
            reps,
            "the row that is not armed does not move (its step is \(repStep))"
        )
    }

    // MARK: - S-6403 the crown position is continuous across arming

    @MainActor
    func testS6403ArmingDoesNotStepByTheDistanceAlreadyTravelled() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(harness)

        let weightStep = field(model, WatchMetricKey.weight).fineStep
        let weight = field(model, WatchMetricKey.weight).value

        model.turn(to: WatchLoggingModel.pointsPerDetent)
        XCTAssertEqual(field(model, WatchMetricKey.reps).value, 11)

        model.arm(WatchMetricKey.weight)
        model.turn(to: 2 * WatchLoggingModel.pointsPerDetent)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            weight + weightStep,
            "one detent of travel since arming is one step, not two"
        )

        model.turn(to: WatchLoggingModel.pointsPerDetent)
        XCTAssertEqual(field(model, WatchMetricKey.weight).value, weight)
    }

    // MARK: - S-6404 the carry is dropped when another row is armed

    @MainActor
    func testS6404ArmingDropsTheTravelThatWasShortOfADetent() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(harness)

        let weightStep = field(model, WatchMetricKey.weight).fineStep
        let weight = field(model, WatchMetricKey.weight).value

        model.turn(to: WatchLoggingModel.pointsPerDetent / 2)
        XCTAssertEqual(field(model, WatchMetricKey.reps).value, 10, "half a detent is no step")

        model.arm(WatchMetricKey.weight)
        model.turn(to: WatchLoggingModel.pointsPerDetent)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            weight,
            "the half detent aimed at reps did not finish on the weight"
        )

        model.turn(to: 3 * WatchLoggingModel.pointsPerDetent / 2)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            weight + weightStep,
            "the carry built after arming does finish a detent"
        )
    }

    // MARK: - S-6405 a measured row cannot be armed

    @MainActor
    func testS6405AMeasuredRowIsNeverArmedAndCrownTravelWithoutRowsDoesNothing() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let recorder = WatchSensorRecorder(
            engine: engine,
            source: source,
            clock: harness.clock.call
        )
        await recorder.start(session)

        let state = WatchLoggingState(engine: engine, clock: harness.clock.call, sensors: recorder)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())

        // plan 65: the timed surface of a distance exercise offers one Distance
        // row that is dialled until GPS measures this effort, so the
        // never-armed case is the measured one: samples inside the window.
        await state.startWork()
        harness.clock.advance(60)
        source.fix(400)
        await eventually { recorder.readings.distanceMeters == 400 }

        XCTAssertTrue(state.isMeasuringDistance, "a sensor is keeping the distance")
        let distance = try XCTUnwrap(
            state.fields.first { $0.metricKey == WatchMetricKey.distance },
            "the timed surface of a distance exercise offers one Distance row"
        )
        XCTAssertTrue(distance.isMeasured, "samples in the window make the row measured")
        XCTAssertNil(model.armedMetricKey, "a measured row is never armed")

        model.arm(WatchMetricKey.distance)
        XCTAssertNil(model.armedMetricKey, "the measured row is not one the crown may drive")

        model.turn(to: 2 * WatchLoggingModel.pointsPerDetent)
        XCTAssertNil(model.armedMetricKey, "a turn with nothing armed stays that way")
        XCTAssertEqual(
            state.fields.first { $0.metricKey == WatchMetricKey.distance }?.value,
            400,
            "and changes no value: nothing crashed"
        )
        source.close()
    }

    // MARK: - S-6406 changing exercise re-checks what may be armed

    @MainActor
    func testS6406AnArmedRowIsReCheckedWhenTheExerciseChanges() async throws {
        let harness = Harness()
        let (engine, model) = await benchModel(
            harness,
            exercises: [
                slot("sx-bench", capabilities: ["reps", "sets", "load"]),
                slot("sx-plank", capabilities: ["time", "hold"]),
            ]
        )

        XCTAssertNotNil(
            model.state.fields.first { $0.metricKey == WatchMetricKey.weight },
            "the bench carries a load row"
        )
        model.arm(WatchMetricKey.weight)
        XCTAssertEqual(model.armedMetricKey, WatchMetricKey.weight)

        await engine.selectExercise(slotId: "sx-plank")
        XCTAssertNil(
            model.state.fields.first { $0.metricKey == WatchMetricKey.weight },
            "a hold has no set-weight row, only its extra weight"
        )
        XCTAssertEqual(
            model.armedMetricKey,
            WatchMetricKey.extraWeight,
            "the weight is no longer a row, so the first open row is armed"
        )

        await engine.selectExercise(slotId: "sx-bench")
        XCTAssertEqual(model.armedMetricKey, WatchMetricKey.weight, "the choice survived the detour")
    }

    // MARK: - S-6408 arming republishes the model

    @MainActor
    func testS6408ArmingAnOpenRowNotifiesTheViewAndARefusedArmDoesNot() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(harness)

        var notifications = 0
        var cancellables: Set<AnyCancellable> = []
        model.objectWillChange
            .sink { _ in notifications += 1 }
            .store(in: &cancellables)

        model.arm(WatchMetricKey.weight)
        XCTAssertEqual(model.armedMetricKey, WatchMetricKey.weight)
        XCTAssertEqual(notifications, 1, "arming an open row republishes so the outline can move")

        model.arm("no-such-metric")
        XCTAssertEqual(model.armedMetricKey, WatchMetricKey.weight, "a key that is not a row changes nothing")
        XCTAssertEqual(notifications, 1, "and says nothing: there is nothing for the view to redraw")

        let cardioHarness = Harness()
        let cardioEngine = await cardioHarness.runningEngine()
        _ = await cardioEngine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        // plan 65: arming the distance row now succeeds before Start, so the
        // refusal that still exists is a metric the exercise does not carry.
        let cardio = WatchLoggingModel(
            state: WatchLoggingState(engine: cardioEngine, clock: cardioHarness.clock.call),
            haptics: RecordingHaptics()
        )

        var cardioNotifications = 0
        cardio.objectWillChange
            .sink { _ in cardioNotifications += 1 }
            .store(in: &cancellables)

        cardio.arm(WatchMetricKey.reps)
        XCTAssertEqual(
            cardio.armedMetricKey,
            WatchMetricKey.distance,
            "a metric the exercise does not carry is not a row: the armed row stays"
        )
        XCTAssertEqual(cardioNotifications, 0, "an arm that is refused publishes nothing")

        withExtendedLifetime(cancellables) {}
    }
}
