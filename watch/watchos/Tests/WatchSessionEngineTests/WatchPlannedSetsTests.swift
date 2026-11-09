//
//  WatchPlannedSetsTests.swift
//  WatchSessionEngineTests
//
//  Plan 36b (routine start sync, PR 2) on the native watchOS side: the phone's
//  `plannedSets` array reaches the logging surface, which starts each set from
//  the planned reps and load of that set and says "Set k of N" in its header.
//
//  Scenario mapping:
//    S-3623 the wrist starts each set from its planned values
//    S-3624 a phone-logged set counts towards k
//    S-3625 no plannedSets / a timed slot / a row without loadKg / without reps
//    S-3626 the planned load shows through the saved unit
//    S-3627 every planned row logged on the phone
//    S-3628 the wrist's own set counts before the phone confirms it
//    S-3631 a slot that declares another kind ignores the key
//    S-3632 a hold ignores the key, on both the wrist's word and the wire's
//
//  Every frame in this file goes through the engine's own schema gate
//  (`Harness.validator()`), so "the phone could send this" is the schema's
//  verdict and not this file's.
//

import XCTest

@testable import WatchSessionEngine

final class WatchPlannedSetsTests: XCTestCase {

    // MARK: - S-3623 the planned values, set by set

    func testS3623TheWristStartsEachSetFromItsPlannedValues() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let frame = snapshot(
            messageId: "msg-planned-1",
            exercises: [slot(plannedSets: plannedRows)]
        )
        XCTAssertTrue(
            Harness.validator().validateEnvelope(frame).isEmpty,
            "\(Harness.validator().validateEnvelope(frame))"
        )
        _ = try await engine.applyMessage(frame)

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            10,
            "S-3623 set 1's planned reps, not the kind's default"
        )
        XCTAssertEqual(
            value(surface, WatchMetricKey.weight),
            40,
            "S-3623 set 1's planned load in kilograms"
        )
        XCTAssertEqual(surface.setCaption, "Set 1 of 3", "S-3623 the header says which set this is")

        // The set the user actually logged: 12 reps at 45 kg, dialled off the
        // planned values and confirmed through the surface's own path.
        surface.adjust(WatchMetricKey.reps, detents: 2)
        surface.adjust(WatchMetricKey.weight, detents: 2)
        let first = try await surface.log()
        XCTAssertEqual(first.payload["reps"] as? Int, 12)
        XCTAssertEqual(first.payload["loadKg"] as? Double, 45)

        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            10,
            "S-3623 set 2's planned reps win over the 12 just logged"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 40, "S-3623 set 2's planned load")
        XCTAssertEqual(surface.setCaption, "Set 2 of 3")

        // Time moves on between sets, so "the set just logged" is the newest one
        // and not whichever row the store happens to order first.
        harness.clock.advance(120)
        try await surface.log()

        XCTAssertEqual(value(surface, WatchMetricKey.reps), 8, "S-3623 set 3's planned reps")
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 42.5, "S-3623 set 3's planned load")
        XCTAssertEqual(surface.setCaption, "Set 3 of 3")

        harness.clock.advance(120)
        try await surface.log()

        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            8,
            "S-3623 past the last planned row the set just logged carries over"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 42.5)
        XCTAssertEqual(
            surface.setCaption,
            "Set 4 of 4",
            "S-3623 an extra set is its own last planned number"
        )
    }

    // MARK: - S-3624 a phone-logged set counts

    func testS3624APhoneLoggedSetCountsTowardsK() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-planned-2",
                exercises: [slot(plannedSets: plannedRows)],
                entries: [
                    setEntry("entry-sx-bench-0", reps: 10, loadKg: 40, loggedAt: "2026-10-15T17:00:00Z")
                ]
            )
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(
            surface.setCaption,
            "Set 2 of 3",
            "S-3624 the set the phone logged is a set the wrist holds"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.reps), 10)
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 40)
    }

    // MARK: - S-3625 what the key does not change

    func testS3625ASlotWithNoPlannedSetsHasNoCaption() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(messageId: "msg-planned-3", exercises: [slot()])
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertNil(surface.setCaption, "S-3625 a free or older-phone slot says nothing")
        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            10,
            "S-3625 and the kind's own default stands"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 0)
    }

    func testS3625ATimedSlotCarryingTheKeyIgnoresIt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-planned-4",
                exercises: [
                    slot(
                        "sx-run",
                        capabilities: ["time"],
                        effortKind: WatchEffortKind.timed,
                        plannedSets: plannedRows
                    )
                ]
            )
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.effortKind, WatchEffortKind.timed)
        XCTAssertNil(surface.setCaption, "S-3625 a timed effort is never a numbered set")
        XCTAssertTrue(surface.fields.isEmpty, "S-3625 …and has no value rows at all")
    }

    func testS3625APlannedRowWithoutALoadShowsZero() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        // One set already held — the phone logged set 1 at 40 kg — so the wrist
        // is on planned row 1, and the last logged load is 40 rather than the
        // kind's 0. A loadKg-less row must still read 0: the chain would say 40.
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-planned-5",
                exercises: [slot(plannedSets: [["reps": 10], ["reps": 10]])],
                entries: [
                    setEntry("entry-sx-bench-0", reps: 10, loadKg: 40, loggedAt: "2026-10-15T17:00:00Z")
                ]
            )
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(
            value(surface, WatchMetricKey.weight),
            0,
            "S-3625 a row that carries no loadKg is a planned zero load, not the 40 just logged"
        )
    }

    func testS3625APlannedRowWithoutRepsFallsBackToTheOldChain() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-planned-6",
                exercises: [slot(plannedSets: [["loadKg": 30]])]
            )
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            10,
            "S-3625 a row that carries no reps leaves the old chain in place"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 30, "S-3625 its load still wins")

        // The chain's other half: with a set already logged, the same reps-less
        // row carries the reps just logged rather than the kind's default 10.
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-planned-6b",
                revision: 2,
                exercises: [slot(plannedSets: [["reps": 7, "loadKg": 30], ["loadKg": 30]])],
                entries: [
                    setEntry("entry-sx-bench-0", reps: 7, loadKg: 30, loggedAt: "2026-10-15T17:00:00Z")
                ]
            )
        )

        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            7,
            "S-3625 a reps-less row shows the reps just logged, not the kind's default"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 30, "S-3625 and its own load still wins")
    }

    // MARK: - S-3626 the saved weight unit

    func testS3626APlannedLoadShowsThroughTheSavedUnit() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-planned-7",
                exercises: [slot(plannedSets: [["reps": 10, "loadKg": 45]])]
            )
        )

        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            units: WatchUnitPreferences(weightUnit: "lbs")
        )
        let weight = try XCTUnwrap(
            surface.fields.first(where: { $0.metricKey == WatchMetricKey.weight })
        )

        XCTAssertEqual(
            weight.value,
            45,
            "S-3626 the planned load is stored in kilograms, whatever unit the wrist reads"
        )
        XCTAssertEqual(
            weight.displayValue,
            String(format: "%.1f", WatchMetricStepping.fromKilograms(45, unit: "lbs")),
            "S-3626 the field prints the pound conversion of the planned 45 kg"
        )
        XCTAssertEqual(weight.unitLabel, "lbs")
    }

    // MARK: - S-3627 every row already logged

    func testS3627AFullyLoggedSlotReadsSetFourOfFour() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-planned-8",
                exercises: [slot(plannedSets: plannedRows)],
                entries: [
                    setEntry("entry-sx-bench-0", reps: 10, loadKg: 40, loggedAt: "2026-10-15T17:00:00Z"),
                    setEntry("entry-sx-bench-1", reps: 10, loadKg: 40, loggedAt: "2026-10-15T17:05:00Z"),
                    setEntry("entry-sx-bench-2", reps: 8, loadKg: 42.5, loggedAt: "2026-10-15T17:10:00Z"),
                ]
            )
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(
            surface.setCaption,
            "Set 4 of 4",
            "S-3627 with every planned row logged the next set is the extra one"
        )
        XCTAssertEqual(
            value(surface, WatchMetricKey.reps),
            8,
            "S-3627 and it carries the set just logged, not planned row 1 again"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 42.5)
    }

    // MARK: - S-3628 the wrist's own set, unconfirmed

    func testS3628AWristLoggedSetCountsBeforeThePhoneConfirms() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(messageId: "msg-planned-9", exercises: [slot(plannedSets: plannedRows)])
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        surface.adjust(WatchMetricKey.reps, detents: 2)
        surface.adjust(WatchMetricKey.weight, detents: 2)
        let logged = try await surface.log()
        XCTAssertEqual(logged.payload["reps"] as? Int, 12)
        XCTAssertEqual(logged.payload["loadKg"] as? Double, 45)

        XCTAssertEqual(
            surface.setCaption,
            "Set 2 of 3",
            "S-3628 the wrist's own set counts before any snapshot carries it back"
        )
        XCTAssertEqual(value(surface, WatchMetricKey.reps), 10)
        XCTAssertEqual(value(surface, WatchMetricKey.weight), 40)
    }

    // MARK: - S-3631 / S-3632 the kind gate

    func testS3631ASlotThatDeclaresAnotherKindIgnoresTheKey() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-planned-10",
                exercises: [
                    slot(
                        capabilities: ["sets", "reps", "load"],
                        effortKind: WatchEffortKind.timed,
                        plannedSets: plannedRows
                    )
                ]
            )
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(
            surface.effortKind,
            WatchEffortKind.timed,
            "S-3631 the routine's declared kind outranks the capabilities"
        )
        XCTAssertNil(surface.setCaption, "S-3631 a declared timed effort is no numbered set")
        XCTAssertTrue(surface.fields.isEmpty)
    }

    func testS3632AHoldSlotIgnoresTheKey() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        // The wrist's own start path: "hold" is the logging surface's word for a
        // drill and is not a wire `effortKind` value, so the slot is built the way
        // a wrist-started session carries its slots.
        _ = await engine.createSession(
            modality: "isometric",
            exercises: [
                slot(
                    capabilities: ["time", "hold"],
                    effortKind: "hold",
                    plannedSets: plannedRows
                )
            ]
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(surface.effortKind, WatchEffortKind.drill)
        XCTAssertNil(surface.setCaption, "S-3632 a hold is no numbered set")
        XCTAssertEqual(
            surface.fields.map(\.metricKey),
            [WatchMetricKey.extraWeight],
            "S-3632 its one row is the added load"
        )
        XCTAssertEqual(
            value(surface, WatchMetricKey.extraWeight),
            0,
            "S-3632 the planned load does not leak into the hold's own row"
        )
    }

    func testS3632ADrillSlotOnTheWireIgnoresTheKey() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        // What a phone snapshot actually carries for a hold: the wire kind is
        // `drill` ("hold" is not a schema value, and is the wrist's own word).
        let frame = snapshot(
            messageId: "msg-planned-11",
            exercises: [
                slot(
                    "sx-plank",
                    capabilities: ["time", "hold"],
                    effortKind: WatchEffortKind.drill,
                    plannedSets: plannedRows
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
            surface.effortKind,
            WatchEffortKind.drill,
            "S-3632 the wire declares the drill kind the wrist calls a hold"
        )
        XCTAssertNil(surface.setCaption, "S-3632 a drill slot is no numbered set")
        // The drill kind's row list is `metricKeysByKind[drill]` = [extraWeight],
        // and every row the drill prescribes is ungated by capability — "load"
        // is not among this slot's capabilities, so anything gated would drop out.
        XCTAssertEqual(
            surface.fields.map(\.metricKey),
            [WatchMetricKey.extraWeight],
            "S-3632 the drill slot shows the extra-weight row only, as a wrist hold does"
        )
        XCTAssertEqual(
            value(surface, WatchMetricKey.extraWeight),
            0,
            "S-3632 and the planned rows do not leak into it"
        )
    }

    // MARK: - Helpers

    /// Fixture P: the three rows a phone session with three sets of bench holds.
    private var plannedRows: [[String: Any]] {
        [
            ["reps": 10, "loadKg": 40],
            ["reps": 10, "loadKg": 40],
            ["reps": 8, "loadKg": 42.5],
        ]
    }

    private func slot(
        _ id: String = "sx-bench",
        capabilities: [String] = ["sets", "reps", "load"],
        effortKind: String? = nil,
        plannedSets: [[String: Any]]? = nil
    ) -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": id,
            "exerciseId": "ex-bench",
            "name": "Bench Press",
            "capabilities": capabilities,
        ]
        if let effortKind { slot["effortKind"] = effortKind }
        if let plannedSets { slot["plannedSets"] = plannedSets }
        return slot
    }

    private func setEntry(
        _ entryId: String,
        reps: Int,
        loadKg: Double,
        loggedAt: String
    ) -> [String: Any] {
        [
            "entryId": entryId,
            "eventId": entryId,
            "kind": "set",
            "loggedAt": loggedAt,
            "sessionExerciseId": "sx-bench",
            "exerciseId": "ex-bench",
            "reps": reps,
            "loadKg": loadKg,
        ]
    }

    private func snapshot(
        messageId: String,
        revision: Int = 1,
        exercises: [[String: Any]],
        entries: [[String: Any]] = []
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
                "revision": revision,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 0,
                "exercises": exercises,
                "entries": entries,
                "timers": [String: Any](),
            ] as [String: Any],
        ]
    }

    private func value(_ surface: WatchLoggingState, _ metricKey: String) -> Double? {
        surface.fields.first(where: { $0.metricKey == metricKey })?.value
    }
}
