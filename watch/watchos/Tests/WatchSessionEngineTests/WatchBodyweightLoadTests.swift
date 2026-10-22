//
//  WatchBodyweightLoadTests.swift
//  WatchSessionEngineTests
//
//  S-8101 to S-8105 of
//  `docs/plans/2026-10-21-52d-wrist-bodyweight-load-plan/2026-10-21-52d-wrist-bodyweight-load-plan.md`
//  — a set effort offers a weight row whatever the exercise's capabilities say
//  (plan 52d D-1): a push-up dials the added weight, negative an assist, and
//  the value travels to the wire as the set's `loadKg`, absent at zero, exactly
//  as a bench set behaves. A hold keeps only its extra weight and a timed
//  effort keeps no row at all.
//

import XCTest

@testable import WatchSessionEngine

final class WatchBodyweightLoadTests: XCTestCase {

    private func slot(
        _ id: String,
        capabilities: [String],
        plannedSets: [[String: Any]]? = nil
    ) -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": id,
            "capabilities": capabilities,
        ]
        if let plannedSets { slot["plannedSets"] = plannedSets }
        return slot
    }

    @MainActor
    private func field(_ model: WatchLoggingModel, _ metricKey: String) -> WatchMetricField {
        model.state.fields.first { $0.metricKey == metricKey }!
    }

    private func value(_ surface: WatchLoggingState, _ metricKey: String) -> Double? {
        surface.fields.first(where: { $0.metricKey == metricKey })?.value
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

    /// A phone session snapshot over one slot, the frame
    /// `WatchPlannedSetsTests` applies its planned rows through.
    private func snapshot(
        messageId: String,
        exercises: [[String: Any]]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": "s-planned",
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-10-15T18:00:00Z",
            "payload": [
                "sessionId": "s-planned",
                "revision": 1,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 0,
                "exercises": exercises,
                "entries": [[String: Any]](),
                "timers": [String: Any](),
            ] as [String: Any],
        ]
    }

    // MARK: - S-8101 what each effort kind offers

    @MainActor
    func testS8101ASetEffortOffersRepsAndWeightAHoldItsExtraWeightATimedEffortNothing() async throws {
        let harness = Harness()
        let (engine, model) = await benchModel(
            harness,
            exercises: [
                slot("sx-pushup", capabilities: ["reps", "sets"]),
                slot("sx-plank", capabilities: ["time", "hold"]),
                slot("sx-run", capabilities: ["time", "distance"]),
            ]
        )

        XCTAssertEqual(
            model.state.fields.map(\.metricKey),
            [WatchMetricKey.reps, WatchMetricKey.weight],
            "S-8101 a push-up offers the added weight, as on the phone"
        )

        await engine.selectExercise(slotId: "sx-plank")
        XCTAssertEqual(
            model.state.fields.map(\.metricKey),
            [WatchMetricKey.extraWeight],
            "S-8101 a hold keeps only its extra-weight row"
        )

        await engine.selectExercise(slotId: "sx-run")
        XCTAssertTrue(
            model.state.fields.isEmpty,
            "S-8101 a timed effort has no row the user dials"
        )
    }

    // MARK: - S-8102 dial and log

    @MainActor
    func testS8102ADialledWeightIsLoggedAsLoadKgAndAZeroWeightSendsNone() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(
            harness,
            exercises: [slot("sx-pushup", capabilities: ["reps", "sets"])]
        )

        model.arm(WatchMetricKey.weight)
        model.adjust(WatchMetricKey.weight, detents: 4)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            10.0,
            "S-8102 four quick plate steps of 2.5 kg"
        )

        model.adjust(WatchMetricKey.reps, detents: 3)
        let first = try await model.state.log()
        XCTAssertEqual(first.payload["loadKg"] as? Double, 10.0, "S-8102 the dialled added weight")
        XCTAssertEqual(first.payload["reps"] as? Int, 13, "S-8102 the reps as dialled")

        // The carry-over starts the next set at the 10 just logged; this set is
        // left unloaded, so it is dialled back down before the log.
        harness.clock.advance(120)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            10.0,
            "S-8102 the carry-over starts the next set where the last one logged"
        )
        model.adjust(WatchMetricKey.weight, detents: -4)
        XCTAssertEqual(field(model, WatchMetricKey.weight).value, 0)

        let second = try await model.state.log()
        XCTAssertNil(
            second.payload["loadKg"],
            "S-8102 a weight left at 0 is no load claim, as on a bench set"
        )
        XCTAssertEqual(second.payload["reps"] as? Int, 13)
    }

    // MARK: - S-8103 the assist and the wire's floor

    @MainActor
    func testS8103AnAssistTravelsWithItsSignDownToTheWireFloor() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(
            harness,
            exercises: [slot("sx-pushup", capabilities: ["reps", "sets"])]
        )

        model.adjust(WatchMetricKey.weight, detents: -8)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            -20.0,
            "S-8103 eight 2.5 kg detents down from 0: a 20 kg band assist"
        )

        let logged = try await model.state.log()
        XCTAssertEqual(
            logged.payload["loadKg"] as? Double,
            -20.0,
            "S-8103 the assist keeps its sign down to the wire"
        )

        model.adjust(WatchMetricKey.weight, detents: -1000)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            WatchMetricStepping.minimumLoadKg,
            "S-8103 the dial stops at the wire's own floor"
        )
    }

    // MARK: - S-8104 the phone's planned rows

    func testS8104APlannedRowStartsTheWeightTileAtItsOwnLoad() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let frame = snapshot(
            messageId: "msg-bodyweight-1",
            exercises: [
                slot(
                    "sx-pushup",
                    capabilities: ["reps", "sets"],
                    plannedSets: [
                        ["reps": 10, "loadKg": 5.0],
                        ["reps": 10, "loadKg": 7.5],
                    ]
                )
            ]
        )
        XCTAssertTrue(
            Harness.validator().validateEnvelope(frame).isEmpty,
            "\(Harness.validator().validateEnvelope(frame))"
        )
        _ = try await engine.applyMessage(frame)

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(
            value(surface, WatchMetricKey.weight),
            5.0,
            "S-8104 set 1's planned added load, not the kind's 0"
        )
        XCTAssertEqual(surface.setCaption, "Set 1 of 2", "S-8104 the header says which set this is")

        try await surface.log()

        harness.clock.advance(120)
        XCTAssertEqual(
            value(surface, WatchMetricKey.weight),
            7.5,
            "S-8104 set 2 starts at its own planned load, not the set just logged"
        )
        XCTAssertEqual(surface.setCaption, "Set 2 of 2")
    }

    // MARK: - S-8105 the carry-over

    @MainActor
    func testS8105TheNextSetStartsAtTheWeightJustLogged() async throws {
        let harness = Harness()
        let (_, model) = await benchModel(
            harness,
            exercises: [slot("sx-pushup", capabilities: ["reps", "sets"])]
        )

        model.arm(WatchMetricKey.weight)
        model.adjust(WatchMetricKey.weight, detents: 4)
        _ = try await model.state.log()

        harness.clock.advance(120)
        XCTAssertEqual(
            field(model, WatchMetricKey.weight).value,
            10.0,
            "S-8105 the next set starts at the load just logged"
        )
    }
}
