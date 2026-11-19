//
//  WatchBackgroundModesSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guard for what `swift test` cannot compile: the watch app's Info.plist
//  fragment declares the background modes a workout app that gives haptic
//  feedback needs. Apple's HealthKit guide "Running workout sessions": workout
//  sessions need the Workout processing background mode, and an app that plays
//  audio or gives haptic feedback during the session must also add the Audio
//  background mode. The app's rest pings and timer taps are haptics.
//  Plan `docs/plans/2026-11-15-178-watch-audio-background-mode-plan/2026-11-15-178-watch-audio-background-mode-plan.md`
//  (D-17801, S-17801).
//

import Foundation
import XCTest

final class WatchBackgroundModesSourceTests: XCTestCase {

    private func plist() throws -> [String: Any] {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrainWatchApp-Info.plist")
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - S-17801 (D-17801) the two background modes

    func testS17801TheWatchAppDeclaresWorkoutProcessing() throws {
        let modes = try XCTUnwrap(plist()["WKBackgroundModes"] as? [String])

        XCTAssertTrue(
            modes.contains("workout-processing"),
            "S-17801 the session keeps the app running with the wrist down"
        )
    }

    func testS17801TheWatchAppDeclaresAudioForItsHaptics() throws {
        let modes = try XCTUnwrap(plist()["UIBackgroundModes"] as? [String])

        XCTAssertTrue(
            modes.contains("audio"),
            "S-17801 Apple's guide: an app that gives haptic feedback during a "
                + "workout session must also add the Audio background mode"
        )
    }
}
