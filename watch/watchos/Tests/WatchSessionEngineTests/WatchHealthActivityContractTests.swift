//
//  WatchHealthActivityContractTests.swift
//  WatchSessionEngineTests
//
//  S-10507 — the `healthActivityTypes` section of
//  `watch/contract/watch_sensor_contract.json`: exactly the Health kinds the
//  phone can name for an exercise, each row naming both platforms, and no
//  `activityTypes` row changed by the section.
//
//  Plan: `docs/plans/2026-10-24-75-health-type-per-exercise-plan/`, renamed
//  and widened to the discipline's kinds by plan 170 (D-17001, D-17006).
//

import XCTest

final class WatchHealthActivityContractTests: XCTestCase {
    /// Every wire kind the contract carries, one per row of plan 170's
    /// discipline table — the Hike/Rucking special case makes `hiking` the
    /// thirty-second.
    private static let kinds: Set<String> = [
        "running", "cycling", "swimming", "rowing", "walking", "hiking",
        "traditionalStrengthTraining", "calisthenics", "isometricHolds", "conditioning",
        "mixedCardio", "preparationAndRecovery", "flexibility", "yoga", "boxing",
        "kickboxing", "martialArts", "tennis", "badminton", "tableTennis", "cricket",
        "hockey", "baseball", "americanFootball", "rugby", "lacrosse", "soccer",
        "basketball", "volleyball", "squash", "golf", "climbing",
    ]

    private func healthActivityTypes() throws -> [String: [String: String]] {
        let contract = try Fixtures.sensorContract()
        return try XCTUnwrap(
            contract["healthActivityTypes"] as? [String: [String: String]],
            "the contract carries the exercise-discipline → platform type table"
        )
    }

    func testS10507HealthActivityTypesHasExactlyTheDisciplineKinds() throws {
        let types = try healthActivityTypes()

        XCTAssertEqual(Set(types.keys), Self.kinds)
    }

    func testS10507EveryRowNamesBothPlatforms() throws {
        let types = try healthActivityTypes()

        for (kind, mapped) in types {
            XCTAssertFalse(
                (mapped["watchos"] ?? "").isEmpty,
                "\(kind) row names its watchOS type"
            )
            XCTAssertFalse(
                (mapped["wear"] ?? "").isEmpty,
                "\(kind) row names its Health Connect type"
            )
        }
    }

    func testS10507TheWearNamesArePinnedPerKind() throws {
        let types = try healthActivityTypes()

        let expected = [
            "running": "exercise_type_running",
            "cycling": "exercise_type_biking",
            "swimming": "exercise_type_swimming",
            "rowing": "exercise_type_rowing",
            "walking": "exercise_type_walking",
            "hiking": "exercise_type_hiking",
            "traditionalStrengthTraining": "exercise_type_strength_training",
            "calisthenics": "exercise_type_calisthenics",
            "isometricHolds": "exercise_type_strength_training",
            "conditioning": "exercise_type_cross_training",
            "mixedCardio": "exercise_type_other_workout",
            "preparationAndRecovery": "exercise_type_other_workout",
            "flexibility": "exercise_type_stretching",
            "yoga": "exercise_type_yoga",
            "boxing": "exercise_type_boxing",
            "kickboxing": "exercise_type_martial_arts",
            "martialArts": "exercise_type_martial_arts",
            "tennis": "exercise_type_tennis",
            "badminton": "exercise_type_badminton",
            "tableTennis": "exercise_type_table_tennis",
            "cricket": "exercise_type_cricket",
            "hockey": "exercise_type_other_workout",
            "baseball": "exercise_type_baseball",
            "americanFootball": "exercise_type_american_football",
            "rugby": "exercise_type_rugby",
            "lacrosse": "exercise_type_other_workout",
            "soccer": "exercise_type_football",
            "basketball": "exercise_type_basketball",
            "volleyball": "exercise_type_volleyball",
            "squash": "exercise_type_squash",
            "golf": "exercise_type_golf",
            "climbing": "exercise_type_rock_climbing",
        ]

        XCTAssertEqual(Set(types.keys), Set(expected.keys), "no kind is left unpinned")
        for (kind, wear) in expected {
            XCTAssertEqual(types[kind]?["wear"], wear, "\(kind) wear row drifts")
        }
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
