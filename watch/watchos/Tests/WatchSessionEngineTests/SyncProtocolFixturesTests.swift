//
//  SyncProtocolFixturesTests.swift
//  WatchSessionEngineTests
//
//  S-007 of `.github/agents/plans/2026-07-13-06-a1-watch-session-engine-plan.md`:
//  the native watch client is held to the same conformance register the Dart
//  client is, by running the shared JSON fixtures through the Swift validator
//  and through the engine's emission pipeline.
//
//  Scope: `manifest.json`'s valid and invalid registers. The reconciliation
//  fixtures are replayed by the phone's reference implementation in
//  `test/sync_protocol_fixtures_test.dart` — structural reconciliation is the
//  receiver's job, delivered for the watch by the live-session items.
//

import XCTest

@testable import WatchSessionEngine

final class SyncProtocolFixturesTests: XCTestCase {

    private let validator = SyncProtocolValidator(
        schemaDocuments: (try? Fixtures.schemaDocuments()) ?? [:]
    )

    func testEveryValidFixtureConforms() throws {
        let entries = try Fixtures.entries("valid")
        XCTAssertFalse(entries.isEmpty)

        for entry in entries {
            let path = try XCTUnwrap(entry["path"] as? String)
            let type = try XCTUnwrap(entry["type"] as? String)

            XCTAssertTrue(
                validator.hasSchema(for: type),
                "no schema document for message type \(type)"
            )

            let rejections = validator.validateEnvelope(try Fixtures.json("fixtures/\(path)"))
            XCTAssertTrue(rejections.isEmpty, "\(path) was rejected: \(rejections)")
        }
    }

    func testEveryInvalidFixtureIsRejectedAsStated() throws {
        let entries = try Fixtures.entries("invalid")
        XCTAssertFalse(entries.isEmpty)

        for entry in entries {
            let path = try XCTUnwrap(entry["path"] as? String)
            let expectedCode = try XCTUnwrap(entry["expectedCode"] as? String)
            let expectedReason = try XCTUnwrap(entry["expectedReasonContains"] as? String)

            let rejections = validator.validateEnvelope(try Fixtures.json("fixtures/\(path)"))

            XCTAssertFalse(rejections.isEmpty, "\(path) must not conform")
            XCTAssertTrue(
                rejections.map(\.code).contains(expectedCode),
                "\(path): expected code \(expectedCode), got \(rejections.map(\.code))"
            )
            XCTAssertTrue(
                rejections.map(\.message).joined(separator: " | ").contains(expectedReason),
                "\(path): no rejection explains \(expectedReason)"
            )
        }
    }

    func testEveryValidObservationsEventFlowsThroughTheEmissionPipeline() async throws {
        let entries = try Fixtures.entries("valid").filter {
            $0["type"] as? String == "observations_up"
        }
        XCTAssertFalse(entries.isEmpty)

        for entry in entries {
            let path = try XCTUnwrap(entry["path"] as? String)
            let fixture = try Fixtures.json("fixtures/\(path)")
            let events = (fixture["payload"] as? [String: Any])?["events"] as? [[String: Any]] ?? []
            XCTAssertFalse(events.isEmpty)

            let harness = Harness()
            let engine = await harness.runningEngine()
            _ = await engine.createSession(modality: nil)

            for event in events {
                try await engine.appendObservation(event)
            }

            // The session start announces itself too; the events are what this
            // test counts.
            let emitted = harness.emitted.filter { $0["type"] as? String == "observations_up" }
            XCTAssertEqual(emitted.count, events.count)
            for envelope in emitted {
                let rejections = validator.validateEnvelope(envelope)
                XCTAssertTrue(
                    rejections.isEmpty,
                    "\(path) produced a non-conformant envelope: \(rejections)"
                )
            }
        }
    }

    func testEveryInvalidObservationsEventIsRejectedBeforePersisting() async throws {
        let entries = try Fixtures.entries("invalid").filter {
            $0["type"] as? String == "observations_up"
        }
        XCTAssertFalse(entries.isEmpty)

        for entry in entries {
            let path = try XCTUnwrap(entry["path"] as? String)
            let expectedCode = try XCTUnwrap(entry["expectedCode"] as? String)
            let expectedReason = try XCTUnwrap(entry["expectedReasonContains"] as? String)
            let fixture = try Fixtures.json("fixtures/\(path)")
            let events = (fixture["payload"] as? [String: Any])?["events"] as? [[String: Any]] ?? []

            let harness = Harness()
            let engine = await harness.runningEngine()
            _ = await engine.createSession(modality: nil)

            for event in events {
                do {
                    try await engine.appendObservation(event)
                    XCTFail("\(path) must not reach storage")
                } catch let rejection as WatchEmissionRejected {
                    XCTAssertTrue(rejection.rejections.map(\.code).contains(expectedCode))
                    XCTAssertTrue(
                        rejection.rejections.map(\.message).joined(separator: " | ")
                            .contains(expectedReason)
                    )
                }
            }

            let stored = await harness.store.readAll()
            XCTAssertTrue(stored.observations.isEmpty)
            XCTAssertTrue(
                harness.emitted.filter { $0["type"] as? String == "observations_up" }.isEmpty,
                "a refused event is never emitted"
            )
        }
    }

    func testEmittedTimerMessagesCarryTimestampsAndPauseBookkeepingOnly() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-row")])

        for kind in WatchTimerKind.all {
            _ = try await engine.startTimer(kind)
            _ = await engine.pauseTimer()
            _ = await engine.resumeTimer()
        }

        let timerMessages = harness.emitted.filter { $0["type"] as? String == "timer_state" }
        XCTAssertEqual(timerMessages.count, WatchTimerKind.all.count * 3)

        for envelope in timerMessages {
            XCTAssertTrue(validator.validateEnvelope(envelope).isEmpty)
            let timers = (envelope["payload"] as? [String: Any])?["timers"] as? [String: Any] ?? [:]
            for timer in timers.values {
                let fields = (timer as? [String: Any]).map { Array($0.keys) } ?? []
                XCTAssertFalse(
                    fields.contains("remainingMs") || fields.contains("remainingSeconds"),
                    "timers travel as timestamps; a receiver derives remaining time "
                        + "from its own clock"
                )
            }
        }
    }
}
