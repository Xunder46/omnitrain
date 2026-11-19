//
//  WatchActiveEnergyTests.swift
//  WatchSessionEngineTests
//
//  S-13470 to S-13476 of
//  `docs/plans/2026-11-09-134c2-watch-measures-energy-plan/` — the wrist
//  stores the platform's cumulative active energy the way it stores steps,
//  and the session's total rides the `session_end` as `activeEnergyKcal`.
//

import XCTest

@testable import WatchSessionEngine

final class WatchActiveEnergyTests: XCTestCase {

    // MARK: - helpers

    private func at(_ text: String) -> Date {
        (try? parseUtcIso(text)) ?? Date(timeIntervalSince1970: 0)
    }

    private func energySample(
        _ value: Double,
        _ recordedAt: String,
        sequence: Int = 0
    ) -> WatchSensorSampleRecord {
        WatchSensorSampleRecord(
            recordId: "sen-energy-\(recordedAt)-\(sequence)",
            sessionId: "s-sum",
            recordedAt: at(recordedAt),
            kind: WatchSensorKind.activeEnergy,
            value: value,
            sequence: sequence
        )
    }

    /// A wrist-created session, started when the test's clock is at `startedAt`.
    private func wristSession(_ harness: Harness, startedAt: String) async -> WatchSessionEngine {
        harness.clock.now = at(startedAt)
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        return engine
    }

    private func sessionEnd(_ engine: WatchSessionEngine) -> [String: Any]? {
        engine.observations.first { $0.kind == WatchObservationKind.sessionEnd }?.payload
    }

    // MARK: - S-13470 the total of a cumulative counter

    func testS13470TheTotalIsTheLastCumulativeValueRoundedToOneDecimal() {
        let kcal = WatchSensorSummaries.activeEnergy(
            [
                energySample(12.34, "2026-11-09T10:02:00Z"),
                energySample(55.5, "2026-11-09T10:05:00Z", sequence: 1),
                energySample(120.04, "2026-11-09T10:08:00Z", sequence: 2),
            ],
            from: at("2026-11-09T10:00:00Z"),
            through: at("2026-11-09T10:30:00Z")
        )

        XCTAssertEqual(kcal, 120.0, "S-13470 12.34 → 55.5 → 120.04 is one counter climbing")
    }

    // MARK: - S-13471 the chain rules

    func testS13471AChainThatStartedBeforeTheWindowCountsOnlyWhatCameAfterIt() {
        let kcal = WatchSensorSummaries.activeEnergy(
            [
                energySample(100.0, "2026-11-09T09:50:00Z"),
                energySample(160.0, "2026-11-09T10:05:00Z", sequence: 1),
            ],
            from: at("2026-11-09T10:00:00Z"),
            through: at("2026-11-09T10:30:00Z")
        )

        XCTAssertEqual(kcal, 60.0, "S-13471 the 100 before the window is the chain's starting point")
    }

    func testS13471ASmallerValueIsARestartAndIsItselfTheEnergySinceIt() {
        let kcal = WatchSensorSummaries.activeEnergy(
            [
                energySample(100.0, "2026-11-09T10:05:00Z"),
                energySample(40.0, "2026-11-09T10:10:00Z", sequence: 1),
            ],
            from: at("2026-11-09T10:00:00Z"),
            through: at("2026-11-09T10:30:00Z")
        )

        XCTAssertEqual(kcal, 140.0, "S-13471 the restart: 100 of the first run plus 40 of the second")
    }

    func testS13471InvalidValuesAreIgnored() {
        let kcal = WatchSensorSummaries.activeEnergy(
            [
                energySample(.nan, "2026-11-09T10:05:00Z"),
                energySample(-3.0, "2026-11-09T10:06:00Z", sequence: 1),
                energySample(50.0, "2026-11-09T10:10:00Z", sequence: 2),
            ],
            from: at("2026-11-09T10:00:00Z"),
            through: at("2026-11-09T10:30:00Z")
        )

        XCTAssertEqual(kcal, 50.0, "S-13471 a non-number and a negative count are not readings")
    }

    func testS13471ANegativeCountBeforeTheWindowIsNotTheChainStart() {
        let kcal = WatchSensorSummaries.activeEnergy(
            [
                energySample(-3.0, "2026-11-09T09:55:00Z"),
                energySample(10.0, "2026-11-09T10:05:00Z", sequence: 1),
            ],
            from: at("2026-11-09T10:00:00Z"),
            through: at("2026-11-09T10:30:00Z")
        )

        XCTAssertEqual(
            kcal, 10.0,
            "S-13471 a negative count before the window is no reading: the chain starts at zero"
        )
    }

    func testS13471TheWindowStartExcludesCountsBeforeIt() {
        let kcal = WatchSensorSummaries.activeEnergy(
            [
                energySample(50.0, "2026-11-09T09:45:00Z"),
                energySample(100.0, "2026-11-09T09:55:00Z", sequence: 1),
                energySample(160.0, "2026-11-09T10:05:00Z", sequence: 2),
            ],
            from: at("2026-11-09T10:00:00Z"),
            through: at("2026-11-09T10:30:00Z")
        )

        XCTAssertEqual(
            kcal, 60.0,
            "S-13471 only the last count before the window starts the chain: 160 − 100"
        )
    }

    // MARK: - S-13472 a zero total is never sent

    func testS13472NoSampleInsideTheWindowIsNoTotal() {
        let kcal = WatchSensorSummaries.activeEnergy(
            [energySample(30.0, "2026-11-09T09:50:00Z")],
            from: at("2026-11-09T10:00:00Z"),
            through: at("2026-11-09T10:30:00Z")
        )

        XCTAssertNil(kcal, "S-13472 the 09:50 count lies before the window")
    }

    func testS13472AMeasuredZeroIsNotSent() {
        let kcal = WatchSensorSummaries.activeEnergy(
            [energySample(0.0, "2026-11-09T10:05:00Z")],
            from: at("2026-11-09T10:00:00Z"),
            through: at("2026-11-09T10:30:00Z")
        )

        XCTAssertNil(kcal, "S-13472 a zero total is never sent")
    }

    func testS13472ATotalThatRoundsToZeroIsNotSent() {
        let kcal = WatchSensorSummaries.activeEnergy(
            [energySample(0.04, "2026-11-09T10:05:00Z")],
            from: at("2026-11-09T10:00:00Z"),
            through: at("2026-11-09T10:30:00Z")
        )

        XCTAssertNil(kcal, "S-13472 0.04 rounds to 0.0 and is never sent")
    }

    // MARK: - S-13473 the wrist's own end

    func testS13473AWristEndedSessionCarriesItsEnergyTotalAndValidates() async throws {
        let harness = Harness()
        let engine = await wristSession(harness, startedAt: "2026-11-09T10:00:00Z")
        await engine.appendSensorSample(
            kind: WatchSensorKind.activeEnergy,
            value: 40.0,
            recordedAt: at("2026-11-09T10:05:00Z")
        )
        await engine.appendSensorSample(
            kind: WatchSensorKind.activeEnergy,
            value: 95.5,
            recordedAt: at("2026-11-09T10:10:00Z")
        )

        harness.clock.now = at("2026-11-09T10:12:00Z")
        _ = await engine.abandonSession()

        let end = try XCTUnwrap(sessionEnd(engine), "S-13473 the end the wrist emitted")
        XCTAssertEqual(end["entryId"] as? String, "end-s-watch-1")
        XCTAssertEqual(end["status"] as? String, "abandoned")
        XCTAssertEqual(numericValue(end["activeEnergyKcal"]), 95.5, "S-13473 the last cumulative count")
        XCTAssertNil(end["followed"], "S-13473 a wrist-created end has no followed key")

        let envelopes = engine.pendingObservations()
        XCTAssertFalse(envelopes.isEmpty, "S-13473 the end is owed to the phone")
        for envelope in envelopes {
            XCTAssertTrue(
                Harness.validator().validateEnvelope(envelope).isEmpty,
                "S-13473 the protocol takes the energy key: \(Harness.validator().validateEnvelope(envelope))"
            )
        }
    }

    // MARK: - S-13474 nothing measured, nothing sent

    func testS13474ASessionWithNoEnergySampleSendsNoEnergyKey() async throws {
        let harness = Harness()
        let engine = await wristSession(harness, startedAt: "2026-11-09T10:00:00Z")

        harness.clock.now = at("2026-11-09T10:12:00Z")
        _ = await engine.abandonSession()

        let end = try XCTUnwrap(sessionEnd(engine))
        XCTAssertNil(end["activeEnergyKcal"], "S-13474 no measurement, and never a zero")
    }

    // MARK: - S-13475 the followed end

    func testS13475AFollowedSessionCarriesBothItsMarkAndItsEnergyTotal() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        harness.clock.now = at("2026-07-13T06:00:00Z")
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
        await engine.appendSensorSample(
            kind: WatchSensorKind.activeEnergy,
            value: 40.0,
            recordedAt: at("2026-07-13T06:05:00Z")
        )
        await engine.appendSensorSample(
            kind: WatchSensorKind.activeEnergy,
            value: 88.0,
            recordedAt: at("2026-07-13T06:08:00Z")
        )

        harness.clock.now = at("2026-07-13T06:10:00Z")
        _ = try await engine.applyMessage([
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-end-1",
            "sessionId": "s-phone",
            "type": "session_lifecycle",
            "origin": "phone",
            "sentAt": "2026-07-13T06:10:00Z",
            "payload": ["state": WatchLifecycleState.completed, "at": "2026-07-13T06:10:00Z"],
        ])

        let end = try XCTUnwrap(sessionEnd(engine), "S-13475 the followed end")
        XCTAssertEqual(end["followed"] as? Bool, true, "S-13475 the phone started it")
        XCTAssertEqual(numericValue(end["activeEnergyKcal"]), 88.0, "S-13475 the wrist measured it")
    }

    // MARK: - S-13476 the recorder

    func testS13476TheRecorderStoresTheEnergyCountsItIsYielded() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        let source = YieldingSensorSource()
        let recorder = WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)

        await recorder.start(live)
        XCTAssertEqual(source.energySubscriptions, 1, "S-13476 the recorder subscribed")

        harness.clock.advance(300)
        source.energy(30.0)
        await eventually {
            engine.sensorSamples.contains {
                $0.kind == WatchSensorKind.activeEnergy && $0.value == 30.0
            }
        }
        harness.clock.advance(300)
        source.energy(75.5)
        await eventually {
            engine.sensorSamples
                .filter { $0.kind == WatchSensorKind.activeEnergy }.count == 2
        }

        let rows = engine.sensorSamples.filter { $0.kind == WatchSensorKind.activeEnergy }
        XCTAssertEqual(rows.map(\.value), [30.0, 75.5], "S-13476 one row per count, in arrival order")
        XCTAssertEqual(rows.first?.sessionId, live.sessionId, "S-13476 stored against the session")

        await recorder.stop()
        harness.clock.advance(300)
        source.energy(90.0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            engine.sensorSamples.filter { $0.kind == WatchSensorKind.activeEnergy }.map(\.value),
            [30.0, 75.5],
            "S-13476 stopping cancelled the subscription: nothing after it is stored"
        )
    }

    func testS13476ARefusedEnergyPermissionStoresNothing() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        let source = YieldingSensorSource()
        source.energyGrant = .denied
        let recorder = WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)

        await recorder.start(live)
        source.energy(30.0)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(engine.sensorSamples.isEmpty, "S-13476 denial is not failure: nothing is stored")
    }

    func testS13476ASourceWithoutTheNewMembersIsUnavailableAndYieldsNothing() async throws {
        let source = LegacySensorSource()

        let permission = await source.activeEnergyPermission()
        XCTAssertEqual(permission, .unavailable, "S-13476 the default answer")

        var yielded = false
        for await _ in source.activeEnergy() { yielded = true }
        XCTAssertFalse(yielded, "S-13476 the default stream finishes without a value")

        let harness = Harness()
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        let recorder = WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)
        await recorder.start(live)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(
            engine.sensorSamples.filter { $0.kind == WatchSensorKind.activeEnergy }.isEmpty,
            "S-13476 an old source keeps compiling and stores nothing"
        )
    }
}

/// The energy sensor, the way the tests drive it: a permission the test can
/// refuse and a stream the test feeds. The other sensors exist but carry
/// nothing, so only the energy rows appear.
final class YieldingSensorSource: WatchSensorSource {
    var energyGrant: WatchSensorPermission = .granted

    private(set) var energySubscriptions = 0

    private var counts: AsyncStream<Double>.Continuation?

    func heartRatePermission() async -> WatchSensorPermission { .granted }
    func locationPermission() async -> WatchSensorPermission { .granted }
    func stepsPermission() async -> WatchSensorPermission { .granted }

    func heartRate() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func location() -> AsyncStream<WatchLocationFix> { AsyncStream { $0.finish() } }
    func steps() -> AsyncStream<Double> { AsyncStream { $0.finish() } }

    func activeEnergyPermission() async -> WatchSensorPermission { energyGrant }

    func activeEnergy() -> AsyncStream<Double> {
        energySubscriptions += 1
        return AsyncStream { counts = $0 }
    }

    func energy(_ cumulativeKilocalories: Double) { counts?.yield(cumulativeKilocalories) }

    func closeEnergy() { counts?.finish() }
}

/// A source written before energy was a sensor: it implements only the
/// original members and relies on the protocol extension's defaults, which is
/// what S-13476 proves an existing fake can do.
final class LegacySensorSource: WatchSensorSource {
    func heartRatePermission() async -> WatchSensorPermission { .granted }
    func locationPermission() async -> WatchSensorPermission { .granted }
    func stepsPermission() async -> WatchSensorPermission { .granted }

    func heartRate() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func location() -> AsyncStream<WatchLocationFix> { AsyncStream { $0.finish() } }
    func steps() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
}
