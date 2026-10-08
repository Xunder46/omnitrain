//
//  SyncProtocolValidatorTests.swift
//  WatchSessionEngineTests
//
//  S-165 of `docs/plans/2026-10-08-18b-watch-rest-count-up-plan.md`: a rest is a
//  count-up, so the wire refuses a rest that carries `plannedDurationMs`
//  (D-164). The valid register's `timer_state` holds the rest without a plan and
//  every other kind with one; `invalid/timer_state_rest_with_planned_duration.json`
//  is the defect.
//

import XCTest

@testable import WatchSessionEngine

final class SyncProtocolValidatorTests: XCTestCase {

    private let validator = SyncProtocolValidator(
        schemaDocuments: (try? Fixtures.schemaDocuments()) ?? [:]
    )

    private func restTimer(of fixture: [String: Any]) -> [String: Any] {
        let payload = fixture["payload"] as? [String: Any] ?? [:]
        let timers = payload["timers"] as? [String: Any] ?? [:]
        return timers["rest"] as? [String: Any] ?? [:]
    }

    func testS165ARestCarriesNoPlannedLengthAndStillConforms() throws {
        let fixture = try Fixtures.json("fixtures/valid/timer_state.json")
        let rest = restTimer(of: fixture)

        XCTAssertEqual(rest["kind"] as? String, "rest")
        XCTAssertNil(
            rest["plannedDurationMs"],
            "a rest is a count-up: it carries no planned length (D-164)"
        )
        XCTAssertTrue(validator.validateEnvelope(fixture).isEmpty)
    }

    func testS165EveryOtherTimerKindKeepsItsPlannedLength() throws {
        var fixture = try Fixtures.json("fixtures/valid/timer_state.json")
        var payload = fixture["payload"] as? [String: Any] ?? [:]
        var timers = payload["timers"] as? [String: Any] ?? [:]
        var round = timers["round"] as? [String: Any] ?? [:]
        round["plannedDurationMs"] = 60_000
        timers["round"] = round
        payload["timers"] = timers
        fixture["payload"] = payload

        XCTAssertTrue(
            validator.validateEnvelope(fixture).isEmpty,
            "the rule refuses a rest plan only; a round keeps its length"
        )
    }

    func testS165ARestWithAPlannedLengthIsRefused() throws {
        let rejections = validator.validateEnvelope(
            try Fixtures.json("fixtures/invalid/timer_state_rest_with_planned_duration.json")
        )

        XCTAssertFalse(
            rejections.isEmpty,
            "a rest with a planned length must not conform"
        )
        XCTAssertTrue(
            rejections.map(\.code).contains(SyncRejectionCode.semanticViolation),
            "expected semantic_violation, got \(rejections.map(\.code))"
        )
        XCTAssertEqual(rejections.first?.path, "$.payload.timers.rest.plannedDurationMs")
        XCTAssertTrue(
            rejections.map(\.message).joined(separator: " | ")
                .contains("a rest has no planned length")
        )
    }

    func testS165AStaleRestPlanNeverReachesTheWire() throws {
        let startedAt = Date(timeIntervalSince1970: 1_784_000_000)
        func row(kind: String, plannedDurationMs: Int?) -> WatchTimerRecord {
            WatchTimerRecord(
                recordId: "t-\(kind)",
                sessionId: "s-1",
                recordedAt: startedAt,
                kind: kind,
                startedAt: startedAt,
                plannedDurationMs: plannedDurationMs
            )
        }

        // A row written before the rest became a count-up still stores a plan…
        let rest = row(kind: WatchTimerKind.rest, plannedDurationMs: 90_000)
        XCTAssertEqual(rest.toJson()["plannedDurationMs"] as? Int, 90_000)
        XCTAssertNil(
            rest.toTimerJson()["plannedDurationMs"],
            "the frame carries no planned length for a rest"
        )

        // …and every other kind still sends the length it was started with.
        let round = row(kind: WatchTimerKind.round, plannedDurationMs: 60_000)
        XCTAssertEqual(round.toTimerJson()["plannedDurationMs"] as? Int, 60_000)

        let envelope: [String: Any] = [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-stale-rest-plan-1",
            "sessionId": "s-1",
            "type": "timer_state",
            "origin": "watch",
            "sentAt": "2026-07-13T17:33:00Z",
            "payload": ["timers": [WatchTimerKind.rest: rest.toTimerJson()]],
        ]
        XCTAssertTrue(
            validator.validateEnvelope(envelope).isEmpty,
            "the wrist's frame for a legacy row must conform"
        )
    }
}
