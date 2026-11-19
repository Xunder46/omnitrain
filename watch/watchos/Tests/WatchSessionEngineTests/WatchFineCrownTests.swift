//
//  WatchFineCrownTests.swift
//  WatchSessionEngineTests
//
//  S-7901 to S-7905 of
//  `docs/plans/2026-10-21-52-wrist-fine-crown-and-no-landing-flash-plan/2026-10-21-52-wrist-fine-crown-and-no-landing-flash-plan.md`
//  — the Crown is the fine control: one click moves one digit (a kilogram or
//  a pound of load, a second of a length), while the − / + buttons keep the
//  quick step (a plate, five seconds).
//

import XCTest

@testable import WatchSessionEngine

final class WatchFineCrownTests: XCTestCase {

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
        exercises: [[String: Any]]? = nil,
        units: WatchUnitPreferences = WatchUnitPreferences()
    ) async -> (engine: WatchSessionEngine, model: WatchLoggingModel) {
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: exercises ?? [exercise("sx-bench")]
        )
        let model = WatchLoggingModel(
            state: WatchLoggingState(
                engine: engine,
                clock: harness.clock.call,
                units: units
            ),
            haptics: RecordingHaptics()
        )
        return (engine, model)
    }

    // MARK: - S-7901 the fine step table

    func testS7901TheFineStepTable() {
        XCTAssertEqual(WatchMetricStepping.fineStep(for: WatchMetricKey.weight), 1)
        let pounds = WatchUnitPreferences(weightUnit: "lbs")
        XCTAssertEqual(
            WatchMetricStepping.fineStep(for: WatchMetricKey.weight, units: pounds),
            WatchMetricStepping.toKilograms(1, unit: "lbs"),
            accuracy: 0.0001
        )
        XCTAssertEqual(WatchMetricStepping.fineStep(for: WatchMetricKey.extraWeight), 1)
        XCTAssertEqual(WatchMetricStepping.fineStep(for: WatchMetricKey.duration), 1)
        XCTAssertEqual(WatchMetricStepping.fineStep(for: WatchMetricKey.roundDuration), 1)
        XCTAssertEqual(WatchMetricStepping.fineStep(for: WatchMetricKey.reps), 1)
        XCTAssertEqual(WatchMetricStepping.fineStep(for: WatchMetricKey.rounds), 1)
        XCTAssertEqual(
            WatchMetricStepping.fineStep(for: WatchMetricKey.distance),
            WatchMetricStepping.step(for: WatchMetricKey.distance),
            accuracy: 0.0001
        )

        // The quick step the − / + buttons take is untouched.
        XCTAssertEqual(WatchMetricStepping.step(for: WatchMetricKey.weight), 2.5)
        XCTAssertEqual(WatchMetricStepping.step(for: WatchMetricKey.duration), 5)
    }

    // MARK: - S-7902 a Crown click on a weight is one kilogram

    @MainActor
    func testS7902ACrownClickOnAWeightStepsOneKilogram() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(harness)

        model.arm(WatchMetricKey.weight)
        XCTAssertEqual(model.armedMetricKey, WatchMetricKey.weight)

        model.turn(to: 1)
        XCTAssertEqual(field(model, WatchMetricKey.weight).value, 1.0, "one click is one kilogram, not a plate")

        model.turn(to: 3)
        XCTAssertEqual(field(model, WatchMetricKey.weight).value, 3.0, "a value no plate step lands on")

        model.adjust(WatchMetricKey.weight, detents: 1)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            5.5,
            "the − / + button is still the quick plate step"
        )
    }

    // MARK: - S-7903 a Crown click on a length is one second

    @MainActor
    func testS7903ACrownClickOnALengthStepsOneSecond() async throws {
        // A hold is a drill, and a drill's only row is its extra load: the
        // hold's time is the hold clock's, not a dialled number, and timed
        // work reads the clock too — so neither exposes a duration row.
        let holdHarness = Harness()
        let (_, hold) = await benchModel(
            holdHarness,
            exercises: [slot("sx-plank", capabilities: ["time", "hold"])]
        )
        XCTAssertNil(
            hold.state.fields.first { $0.metricKey == WatchMetricKey.duration },
            "a hold's time is its clock, not a dialled row"
        )

        // The dialled length row is a round effort's round length instead.
        let harness = Harness()
        let (_, model) = await benchModel(
            harness,
            exercises: [slot("sx-half", capabilities: ["time", "rounds"], roundDurationSecs: 60)]
        )
        XCTAssertEqual(model.state.effortKind, WatchEffortKind.round)

        model.arm(WatchMetricKey.roundDuration)
        XCTAssertEqual(field(model, WatchMetricKey.roundDuration).value, 60)

        model.turn(to: 1)
        XCTAssertEqual(
            field(model, WatchMetricKey.roundDuration).value,
            61,
            "one Crown click is one second"
        )

        model.adjust(WatchMetricKey.roundDuration, detents: 1)
        XCTAssertEqual(
            field(model, WatchMetricKey.roundDuration).value,
            66,
            "the − / + button is the five-second step"
        )
    }

    // MARK: - S-7904 pounds: a Crown click is one pound

    @MainActor
    func testS7904ACrownClickOnAPoundWeightMovesTheDisplayByOne() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(
            harness,
            units: WatchUnitPreferences(weightUnit: "lbs")
        )

        model.arm(WatchMetricKey.weight)

        model.turn(to: 1)
        XCTAssertEqual(field(model, WatchMetricKey.weight).displayValue, "1.0")

        model.turn(to: 2)
        XCTAssertEqual(field(model, WatchMetricKey.weight).displayValue, "2.0")

        model.adjust(WatchMetricKey.weight, detents: 1)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).displayValue,
            "7.0",
            "the − / + button moves the display by five pounds"
        )
    }

    // MARK: - S-7905 a field without a fine step borrows its step

    func testS7905AFieldWithoutAFineStepBorrowsItsStep() {
        let plain = WatchMetricField(
            metricKey: WatchMetricKey.reps,
            label: "Reps",
            value: 10,
            displayValue: "10",
            step: 1,
            unitLabel: ""
        )
        XCTAssertEqual(plain.fineStep, plain.step)

        let fine = WatchMetricField(
            metricKey: WatchMetricKey.weight,
            label: "Load",
            value: 80,
            displayValue: "80.0",
            step: 2.5,
            unitLabel: "kg",
            fineStep: 0.5
        )
        XCTAssertEqual(fine.fineStep, 0.5)
    }
}
