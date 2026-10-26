//
//  WatchOutdoorWorkoutTests.swift
//  WatchSessionEngineTests
//
//  Phase 1A of
//  `docs/plans/2026-10-10-19f-watch-gps-feed-plan/2026-10-10-19f-watch-gps-feed-plan.md`:
//  the platform-workout seam learns whether the session is being done outdoors,
//  and old-shape stores keep working through the default.
//
//  Scenario mapping:
//    S-3300 outdoors follows the capability profile        → `testS3300...`
//    S-3301 the default keeps old stores working           → `testS3301...`
//
//  Nothing here touches the platform's health service: the stores declared below
//  are the seam the workout is asserted through, so the file runs on macOS beside
//  `swift test`.
//

import XCTest

@testable import WatchSessionEngine

/// An outdoor-aware store: implements ONLY `begin(_:outdoors:)` and records the
/// pair it was given, so the activity name and the outdoors answer are one
/// recorded call rather than two that could drift apart.
final class RecordingOutdoorPlatformStore: WatchPlatformWorkoutStore {
    private(set) var begins: [(activityType: String, outdoors: Bool)] = []

    func begin(_ activityType: String, outdoors: Bool) async {
        begins.append((activityType, outdoors))
    }

    func end() async {}

    func inProgressActivityTypes() async -> [String] { [] }
}

/// The 19c shape of a store: implements ONLY `begin(_:)`, as `FakePlatformStore`
/// and `ScriptedPlatformStore` do. It conforms because the protocol extension
/// defaults the outdoor-aware requirement.
final class LegacyShapePlatformStore: WatchPlatformWorkoutStore {
    private(set) var begun: [String] = []

    func begin(_ activityType: String) async {
        begun.append(activityType)
    }

    func end() async {}

    func inProgressActivityTypes() async -> [String] { [] }
}

final class WatchOutdoorWorkoutTests: XCTestCase {

    // MARK: - S-3300 outdoors follows the capability profile

    func testS3300OutdoorsFollowsTheCapabilityProfile() async {
        // A distance-capable modality is outdoor work; a modality without the
        // distance capability — and every unmapped one — is not.
        let cases: [(modality: String?, activityType: String, outdoors: Bool)] = [
            ("cardio_endurance", "running", true),
            ("sports", "other", true),
            ("resistance_lifting", "traditionalStrengthTraining", false),
            ("isometric_stretching", "flexibility", false),
            (nil, "other", false),
            ("not_a_modality", "other", false),
        ]

        for expected in cases {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let session = await engine.createSession(modality: expected.modality)
            let store = RecordingOutdoorPlatformStore()
            let platform = WatchPlatformWorkout(store: store)

            await platform.start(session)

            let label = expected.modality ?? "nil"
            XCTAssertEqual(
                store.begins.map { $0.activityType },
                [expected.activityType],
                "\(label) registers as its table's watchOS type"
            )
            XCTAssertEqual(
                store.begins.map { $0.outdoors },
                [expected.outdoors],
                "\(label) tells the store whether the work is outdoors"
            )
            XCTAssertEqual(
                platform.running?.watchOs,
                expected.activityType,
                "and the watch holds the activity it registered"
            )
        }
    }

    // MARK: - S-3301 the default keeps old stores working

    func testS3301TheDefaultKeepsOldShapeStoresWorking() async {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: "cardio_endurance")
        let store = LegacyShapePlatformStore()
        let platform = WatchPlatformWorkout(store: store)

        await platform.start(session)

        XCTAssertEqual(
            store.begun,
            ["running"],
            "the forwarding default reaches an old-shape begin once, with the activity name"
        )
        XCTAssertEqual(platform.running?.watchOs, "running")
    }
}
