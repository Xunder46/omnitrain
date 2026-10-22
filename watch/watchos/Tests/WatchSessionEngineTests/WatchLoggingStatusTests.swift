//
//  WatchLoggingStatusTests.swift
//  WatchSessionEngineTests
//
//  S-7511 to S-7514 of
//  `docs/plans/2026-10-21-51a-wrist-crown-and-layout-plan/2026-10-21-51a-wrist-crown-and-layout-plan.md`
//  — the shared − / + stepper steps the armed row by its own step and nothing
//  else (D-3), the header's one status line joins the set caption and the
//  sensor readout (D-4), and the view renders exactly that pair (D-5).
//

import XCTest

@testable import WatchSessionEngine

final class WatchLoggingStatusTests: XCTestCase {

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

    /// A file of the watch package's engine module, read from the repository
    /// root, with every comment-only line blanked out (the line count is kept).
    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries so line indexes stay true. A trailing `//` comment on a code
    /// line is blanked too, so prose there can neither satisfy a guard nor trip
    /// one.
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - S-7511 the stepper steps the armed row by its own step

    @MainActor
    func testS7511StepArmedStepsTheArmedRowByItsOwnStep() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(harness)

        let repStep = field(model, WatchMetricKey.reps).step
        let weightStep = field(model, WatchMetricKey.weight).step
        let reps = field(model, WatchMetricKey.reps).value
        let weight = field(model, WatchMetricKey.weight).value

        model.stepArmed(1)
        XCTAssertEqual(
            field(model, WatchMetricKey.reps).value,
            reps + repStep,
            "the stepper raises the armed reps row by its own step"
        )
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            weight,
            "the row that is not armed does not move"
        )

        model.stepArmed(2)
        XCTAssertEqual(
            field(model, WatchMetricKey.reps).value,
            reps + 3 * repStep,
            "two detents are two more steps"
        )

        model.arm(WatchMetricKey.weight)
        XCTAssertEqual(model.armedMetricKey, WatchMetricKey.weight)

        model.stepArmed(1)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            weight + weightStep,
            "the weight moves by its own increment"
        )
        XCTAssertEqual(
            field(model, WatchMetricKey.reps).value,
            reps + 3 * repStep,
            "the reps stay where the stepper left them"
        )

        model.stepArmed(-1)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            weight,
            "a negative detent steps the weight back down"
        )
    }

    // MARK: - S-7512 the stepper with nothing armable

    @MainActor
    func testS7512StepArmedWithNoRowsChangesNothing() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [slot("sx-run", capabilities: ["time", "distance"])]
        )
        let state = WatchLoggingState(engine: engine, clock: harness.clock.call)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())

        XCTAssertTrue(
            state.fields.isEmpty,
            "the timed kind prescribes no rows at all"
        )
        XCTAssertNil(model.armedMetricKey, "there is no open row to arm")

        model.stepArmed(1)
        model.stepArmed(-1)

        XCTAssertTrue(state.fields.isEmpty, "nothing threw, nothing appeared")
        XCTAssertNil(model.armedMetricKey, "and still nothing is armed")
    }

    @MainActor
    func testS7512StepArmedLeavesASensorKeptValueAlone() async throws {
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
        source.fix(400)
        await eventually { recorder.readings.distanceMeters == 400 }

        let state = WatchLoggingState(engine: engine, clock: harness.clock.call, sensors: recorder)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())

        XCTAssertTrue(state.isMeasuringDistance, "a sensor is keeping the distance")
        XCTAssertTrue(
            state.fields.isEmpty,
            "the measured distance is a reading, not a row the user dials (S-004)"
        )
        XCTAssertNil(model.armedMetricKey, "there is no open row to arm")

        model.stepArmed(1)
        model.stepArmed(-1)

        XCTAssertEqual(
            recorder.readings.distanceMeters,
            400,
            "the measured value is the sensor's, untouched by the stepper"
        )
        source.close()
    }

    // MARK: - S-7513 the status line

    /// Five planned rows, so two logged sets leave the wrist on "Set 3 of 5".
    private var plannedRows: [[String: Any]] {
        [
            ["reps": 10, "loadKg": 40],
            ["reps": 10, "loadKg": 40],
            ["reps": 8, "loadKg": 42.5],
            ["reps": 8, "loadKg": 42.5],
            ["reps": 6, "loadKg": 45],
        ]
    }

    private func plannedSlot(_ id: String = "sx-bench") -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": id,
            "exerciseId": "ex-bench",
            "name": "Bench Press",
            "capabilities": ["sets", "reps", "load"],
        ]
        slot["plannedSets"] = plannedRows
        return slot
    }

    @MainActor
    func testS7513TheStatusLineIsTheCaptionAloneWithoutSensors() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: [plannedSlot()]
        )
        let state = WatchLoggingState(engine: engine, clock: harness.clock.call)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())

        try await state.log()
        harness.clock.advance(120)
        try await state.log()

        XCTAssertEqual(state.setCaption, "Set 3 of 5", "two sets logged of five planned")
        XCTAssertEqual(model.statusLine, "Set 3 of 5", "no sensor reading, so the caption alone")
    }

    @MainActor
    func testS7513TheStatusLineIsNilWithNeitherCaptionNorSensors() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(harness)

        XCTAssertNil(model.state.setCaption, "the bench carries no planned rows")
        XCTAssertNil(model.statusLine, "and no sensor reads anything")
    }

    @MainActor
    func testS7513TheStatusLineJoinsTheCaptionAndTheBeat() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        let engine = await harness.runningEngine()
        var slot = plannedSlot()
        slot["capabilities"] = ["sets", "reps", "load", "distance"]
        let session = await engine.createSession(
            modality: nil,
            exercises: [slot]
        )
        let recorder = WatchSensorRecorder(
            engine: engine,
            source: source,
            clock: harness.clock.call
        )
        await recorder.start(session)
        source.beat(143)
        source.fix(400)
        await eventually { recorder.readings.heartRate == 143 }
        await eventually { recorder.readings.distanceMeters == 400 }

        let state = WatchLoggingState(engine: engine, clock: harness.clock.call, sensors: recorder)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())

        try await state.log()
        harness.clock.advance(120)
        try await state.log()

        XCTAssertEqual(state.sensorLabels.heartRate, "143")
        XCTAssertNotNil(state.sensorLabels.distance, "a distance reading is present")
        let line = try XCTUnwrap(model.statusLine)
        XCTAssertTrue(
            line.contains("143 bpm · "),
            "the beat is followed by the caption's one-space separator, got \"\(line)\""
        )
        XCTAssertFalse(
            line.contains("  "),
            "no part is joined with a double space, got \"\(line)\""
        )
        source.close()
    }

    @MainActor
    func testS7513TheStatusLineIsTheBeatAloneWithoutAPlan() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        let (engine, _) = await benchModel(harness)
        let session = engine.session!
        let recorder = WatchSensorRecorder(
            engine: engine,
            source: source,
            clock: harness.clock.call
        )
        await recorder.start(session)
        source.beat(143)
        await eventually { recorder.readings.heartRate == 143 }

        let state = WatchLoggingState(engine: engine, clock: harness.clock.call, sensors: recorder)
        let model = WatchLoggingModel(state: state, haptics: RecordingHaptics())

        XCTAssertNil(model.state.setCaption, "no planned rows, so no caption")
        XCTAssertEqual(model.statusLine, "143 bpm", "the beat alone carries the line")
        source.close()
    }

    // MARK: - S-7514 the view renders the shared pair and the status line

    func testS7514TheLoggingViewRendersTheSharedStepperAndTheStatusLine() throws {
        let source = try engineSource("WatchLoggingView.swift")

        XCTAssertFalse(
            source.contains(".buttonStyle(.bordered)"),
            "the bordered style's drawn size forced the 36 pt frame to overlap (D-5)"
        )
        XCTAssertEqual(
            source.components(separatedBy: "stepArmed(").count - 1,
            2,
            "the shared − / + pair is the only stepper the view drives"
        )
        XCTAssertTrue(
            source.contains("model.statusLine"),
            "the header renders the model's one status line"
        )
        XCTAssertFalse(
            source.contains("sensorLine"),
            "the sensor line moved into the model (D-4)"
        )
        XCTAssertTrue(
            source.contains("\"Less \\(label)\""),
            "the shared pair's minus label"
        )
        XCTAssertTrue(
            source.contains("\"More \\(label)\""),
            "the shared pair's plus label"
        )
    }
}
