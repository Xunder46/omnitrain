//
//  WatchHealthAccessWiringSourceTests.swift
//  WatchSessionEngineTests
//
//  The Start screen asks for Health access and the surfaces say why a sensor is
//  silent (plan 59, scenario S-8908).
//
//  Plan:
//  `docs/plans/2026-10-23-59-health-and-location-access-plan/2026-10-23-59-health-and-location-access-plan.md`.
//
//  S-8908 reads the targets' sources with their comment lines stripped, the way
//  `WatchCancelEmptyFreeWorkoutTests` does: the views compile only under
//  xcodebuild, so what `swift test` can hold is the text the wiring is made of.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchHealthAccessWiringSourceTests: XCTestCase {

    // MARK: - Source readers (copied from WatchCancelEmptyFreeWorkoutTests.swift,
    // whose helpers are private to that file)

    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        return strippingCommentLines(try String(contentsOf: url, encoding: .utf8))
    }

    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        return strippingCommentLines(try String(contentsOf: url, encoding: .utf8))
    }

    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - S-8908: the store asks, the host wires it, the surfaces say it

    func testS8908StoreHasRequestAccessAnsweringWhatTheWristCanRead() throws {
        let source = try appSource("HealthKitWorkoutStore.swift")
        XCTAssertTrue(
            source.contains("func requestAccess() async -> WatchHealthAccess"),
            "Without it the Start screen never asks for Health access, so the user "
                + "opens a workout and only then meets the permission sheet."
        )
        XCTAssertTrue(
            source.contains("guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }"),
            "Without it a wrist without HealthKit would be told access is off rather "
                + "than that it does not exist, and the user would hunt for a setting "
                + "that cannot help."
        )
        XCTAssertTrue(
            source.contains("await resolveAuthorization()"),
            "Without it the Start screen's ask would raise a second permission sheet "
                + "beside the one the feed and `begin` already share."
        )
    }

    func testS8908HostAsksWhenTheStartScreenShows() throws {
        let source = try appSource("ContentView.swift")
        XCTAssertTrue(
            source.contains("func askHealthAccess() async"),
            "Without it nothing triggers the ask, so the user never sees the "
                + "permission sheet until a workout is already open."
        )
        XCTAssertTrue(
            source.contains("healthAccess = await healthStore.requestAccess()"),
            "Without it the host never learns the answer, so the Start screen cannot "
                + "tell the user that Health access is off."
        )
        XCTAssertTrue(
            source.contains("healthAccess: host.healthAccess"),
            "Without it the Start view is never told the access state, so the user "
                + "stays on a screen that cannot say why no heart rate will appear."
        )
        XCTAssertTrue(
            source.contains(".task { await host.askHealthAccess() }"),
            "Without it the ask never fires when the Start screen shows, so the "
                + "user's first workout opens on an unanswered permission sheet."
        )
    }

    func testS8908StartViewSaysHealthAccessIsOff() throws {
        let source = try engineSource("WatchStartView.swift")
        XCTAssertTrue(
            source.contains("if healthAccess == .off"),
            "Without it the Start screen shows the off line always or never, so the "
                + "user with access off is not told before the first workout."
        )
        XCTAssertTrue(
            source.contains("WatchHealthAccessCopy.offLine"),
            "Without it the user with Health access off sees a silent screen and "
                + "never learns to turn access on in Health on the iPhone."
        )
        XCTAssertTrue(
            source.contains("self.healthAccess = healthAccess"),
            "Without it the init no longer stores the state the host asked for, so the Start "
                + "screen always renders `.unknown` and the user with access off is never told "
                + "before the first workout."
        )
        XCTAssertTrue(
            source.contains("healthAccess: WatchHealthAccess = .unknown"),
            "Without it the parameter vanishes and every caller compiles against a default of "
                + "`.unknown`, so the user with access off is never told before the first workout."
        )
        XCTAssertTrue(
            source.contains("Text(WatchHealthAccessCopy.offLine)"),
            "Without it the off branch renders an empty Text, so the user with Health access off "
                + "sees a silent screen and never learns to turn access on in Health on the iPhone."
        )
    }

    func testS8908LoggingViewShowsSensorNotices() throws {
        let source = try engineSource("WatchLoggingView.swift")
        XCTAssertTrue(
            source.contains("ForEach(model.sensorNotices"),
            "Without it the logging surface stays silent about a sensor that cannot "
                + "read, so the user watches an empty heart rate field without knowing "
                + "Health access is the reason."
        )
        XCTAssertTrue(
            source.contains("Text(notice)"),
            "Without it the ForEach body renders an empty Text, so the user watches an "
                + "empty heart rate field without knowing Health access is the reason."
        )
        let forEach = try XCTUnwrap(
            source.range(of: "ForEach(model.sensorNotices"),
            "Without it the logging surface stays silent about a sensor that cannot read."
        )
        let noticeLine = try XCTUnwrap(
            source.range(of: "Text(notice)"),
            "Without it the sensor notice is rendered somewhere the ForEach never reaches."
        )
        XCTAssertLessThan(
            forEach.lowerBound, noticeLine.lowerBound,
            "Without it the notice renders outside the sensor-notices rows, so the user is "
                + "told something unrelated while the sensor stays silent."
        )
    }
}
