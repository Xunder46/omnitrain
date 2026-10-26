//
//  WatchHealthActivityContractTests.swift
//  WatchSessionEngineTests
//
//  S-10507 — the `distanceActivityTypes` section of
//  `watch/contract/watch_sensor_contract.json`: exactly the five Health kinds
//  a distance exercise can record as, each row naming both platforms, and no
//  `activityTypes` row changed by the new section.
//
//  Plan: `docs/plans/2026-10-24-75-health-type-per-exercise-plan/`.
//

import XCTest

final class WatchHealthActivityContractTests: XCTestCase {
    func testS10507DistanceActivityTypesHasExactlyTheFiveKinds() throws {
        let contract = try Fixtures.sensorContract()
        let types = try XCTUnwrap(
            contract["distanceActivityTypes"] as? [String: [String: String]]
        )

        XCTAssertEqual(
            Set(types.keys),
            ["running", "cycling", "rowing", "walking", "hiking"]
        )
    }

    func testS10507EveryRowNamesItsOwnWatchOsType() throws {
        let contract = try Fixtures.sensorContract()
        let types = try XCTUnwrap(
            contract["distanceActivityTypes"] as? [String: [String: String]]
        )

        for (kind, mapped) in types {
            XCTAssertEqual(mapped["watchos"], kind, "\(kind) row drifts from its key")
        }
    }

    func testS10507TheWearNamesAreTheFourNewKindsPlusRunning() throws {
        let contract = try Fixtures.sensorContract()
        let types = try XCTUnwrap(
            contract["distanceActivityTypes"] as? [String: [String: String]]
        )

        XCTAssertEqual(types["cycling"]?["wear"], "exercise_type_biking")
        XCTAssertEqual(types["rowing"]?["wear"], "exercise_type_rowing")
        XCTAssertEqual(types["walking"]?["wear"], "exercise_type_walking")
        XCTAssertEqual(types["hiking"]?["wear"], "exercise_type_hiking")
        XCTAssertEqual(types["running"]?["wear"], "exercise_type_running")
    }

    func testS10507ActivityTypesRowsAreUnchanged() throws {
        let contract = try Fixtures.sensorContract()
        let types = try XCTUnwrap(
            contract["activityTypes"] as? [String: [String: String]]
        )
        let cardio = try XCTUnwrap(types["cardio_endurance"])

        XCTAssertEqual(cardio["watchos"], "running")
        XCTAssertEqual(cardio["wear"], "exercise_type_running")
    }
}
