//
//  WatchEnergyLiveTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-11-09-135-watch-calories-on-phone-plan/` — the wrist
//  sends `energy_live`: scenarios S-13511, S-13512, S-13513, S-13514 and
//  S-13516. The phone's receiver half is the crew-builder-app P2's.
//

import XCTest

@testable import WatchSessionEngine

final class WatchEnergyLiveTests: XCTestCase {

    /// A fixed instant, never the wall clock: 1_793_016_000 epoch seconds,
    /// far from `testInstant()` so no session row shares it.
    private let t = Date(timeIntervalSince1970: 1_793_016_000)

    private func energyLiveFrames(_ harness: Harness) -> [[String: Any]] {
        harness.emitted.filter { $0["type"] as? String == "energy_live" }
    }

    private func kcal(_ frame: [String: Any]) -> Double? {
        (frame["payload"] as? [String: Any])?["activeEnergyKcal"] as? Double
    }

    // MARK: - S-13511 the emitter's cadence

    func testS13511TheCadenceIsFirstThenHalfAKilocalorieInFiveSecondsThenAFall() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])

        engine.announceEnergy(kilocalories: 10, at: t)
        engine.announceEnergy(kilocalories: 10.2, at: t.addingTimeInterval(1))
        engine.announceEnergy(kilocalories: 10.6, at: t.addingTimeInterval(2))
        engine.announceEnergy(kilocalories: 11.0, at: t.addingTimeInterval(6))
        engine.announceEnergy(kilocalories: 4.0, at: t.addingTimeInterval(7))
        engine.announceEnergy(kilocalories: .nan, at: t.addingTimeInterval(20))
        engine.announceEnergy(kilocalories: -1, at: t.addingTimeInterval(21))

        XCTAssertEqual(
            energyLiveFrames(harness).map(kcal),
            [10.0, 11.0, 4.0],
            "S-13511 first; nothing for 10.2 and 10.6 (not 0.5 in 5 s); a rise of "
                + "1.0 in 6 s; a fall at once; neither NaN nor a negative"
        )
        for frame in energyLiveFrames(harness) {
            XCTAssertEqual(
                Harness.validator().validateEnvelope(frame),
                [],
                "S-13511 every emitted frame conforms: \(frame)"
            )
        }
    }

    func testS13511BARepeatedIdenticalTotalIsNotSentAgain() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])

        engine.announceEnergy(kilocalories: 10, at: t)
        engine.announceEnergy(kilocalories: 10, at: t.addingTimeInterval(30))

        XCTAssertEqual(
            energyLiveFrames(harness).map(kcal),
            [10.0],
            "S-13511 the same total thirty seconds later is no news"
        )
    }

    func testS13511CANewSessionStartsItsOwnCadence() async throws {
        // The shared harness pins one session id, so this engine mints its own.
        let recorder = EmitRecorder()
        var nextId = "s-energy-a"
        let engine = WatchSessionEngine(
            store: InMemoryWatchSessionStore(),
            onEmit: { recorder.append($0) },
            validator: Harness.validator(),
            clock: { self.t },
            sessionIdFactory: { nextId }
        )
        await engine.restore()
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        engine.announceEnergy(kilocalories: 10, at: t)
        _ = await engine.finishSession()

        nextId = "s-energy-b"
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        engine.announceEnergy(kilocalories: 10.1, at: t.addingTimeInterval(1))

        let frames = recorder.frames.filter { $0["type"] as? String == "energy_live" }
        XCTAssertEqual(
            frames.map(kcal),
            [10.0, 10.1],
            "S-13511 the first reading of a NEW session id goes out whatever "
                + "the last session announced (the cadence is per session id)"
        )
        XCTAssertEqual(
            frames.map { $0["sessionId"] as? String },
            ["s-energy-a", "s-energy-b"],
            "S-13511 each frame names its own session"
        )
    }

    // MARK: - S-13512 no live session, nothing sent

    func testS13512WithNoSessionEnergyIsAnnouncedIntoNothing() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()

        engine.announceEnergy(kilocalories: 10, at: t)

        XCTAssertTrue(
            energyLiveFrames(harness).isEmpty,
            "S-13512 no session to name, no frame"
        )
    }

    func testS13512AEndedSessionCarriesNoMoreEnergyFrames() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        _ = await engine.finishSession()

        engine.announceEnergy(kilocalories: 10, at: t)

        XCTAssertTrue(
            energyLiveFrames(harness).isEmpty,
            "S-13512 a completed session sends nothing"
        )
    }

    // MARK: - S-13513 the frame's shape

    func testS13513TheFirstFrameNamesTheSessionAndTheInstant() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let live = await engine.createSession(
            modality: "resistance_lifting",
            exercises: [exercise("sx-bench")]
        )
        harness.clearEmitted()

        engine.announceEnergy(kilocalories: 10, at: t)

        let frames = energyLiveFrames(harness)
        XCTAssertEqual(frames.count, 1, "S-13513 exactly one frame")
        let frame = try XCTUnwrap(frames.first, "S-13513 the frame")
        XCTAssertEqual(frame["type"] as? String, "energy_live", "S-13513 the type")
        XCTAssertEqual(frame["origin"] as? String, "watch", "S-13513 the origin")
        XCTAssertEqual(frame["sessionId"] as? String, live.sessionId, "S-13513 the session")
        XCTAssertEqual(
            frame["messageId"] as? String,
            "msg-energy-\(live.sessionId)-\(Int((t.timeIntervalSince1970 * 1000).rounded()))",
            "S-13513 the delivery key derives from the session and the instant"
        )
        XCTAssertEqual(frame["sentAt"] as? String, utcIso(t), "S-13513 sentAt is the instant")

        let payload = try XCTUnwrap(frame["payload"] as? [String: Any], "S-13513 the payload")
        XCTAssertEqual(
            Set(payload.keys),
            Set(["activeEnergyKcal", "at"]),
            "S-13513 the payload is closed"
        )
        XCTAssertEqual(payload["activeEnergyKcal"] as? Double, 10.0, "S-13513 the value")
        XCTAssertEqual(payload["at"] as? String, utcIso(t), "S-13513 the payload's instant")
    }

    // MARK: - S-13514 the recorder announces what it records

    func testS13514TheRecorderStoresAndAnnouncesEachCount() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let live = await engine.createSession(modality: "resistance_lifting", exercises: [exercise("sx-bench")])
        let source = YieldingSensorSource()
        let recorder = WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)

        harness.clearEmitted()

        await recorder.start(live)
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
        XCTAssertEqual(
            rows.map(\.value),
            [30.0, 75.5],
            "S-13514 the two counts are stored against the session, as 134c2 S-13476 asserts"
        )
        XCTAssertEqual(
            energyLiveFrames(harness).map(kcal),
            [30.0, 75.5],
            "S-13514 each count that is stored is announced too, first regardless"
        )
    }

    // MARK: - S-13516 never durable

    func testS13516EnergyLiveIsNeverDurable() {
        var frame: [String: Any] = [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-energy-s-1-1000000000000",
            "sessionId": "s-1",
            "type": "energy_live",
            "origin": "watch",
            "sentAt": utcIso(t),
            "payload": ["activeEnergyKcal": 10.0, "at": utcIso(t)],
        ]

        XCTAssertFalse(
            WatchConnectivityBridge.isDurable(frame),
            "S-13516 live only: a refused sendMessage is reported and dropped"
        )

        frame["type"] = "timer_state"
        XCTAssertFalse(
            WatchConnectivityBridge.isDurable(frame),
            "S-13516 the mutable guard default still holds"
        )
    }
}
