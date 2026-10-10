//
//  WatchSensorSourceSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the app target's live sensor side and its host wiring.
//
//  Plan: `docs/plans/2026-10-10-19d-watch-heart-rate-and-steps-plan/2026-10-10-19d-watch-heart-rate-and-steps-plan.md`,
//  scenarios S-3109, S-3110, S-3114 and S-3116 (decisions D-2103, D-2104,
//  D-2105, D-2106, D-2113).
//
//  The app target has no test target and `HKLiveWorkoutBuilder` does not exist on
//  macOS where `swift test` runs, so the feed and the host cannot be executed
//  here. What can be held off-device is what drift would break: the feed's shape
//  and its one-authorization rule, the store's read set, the host's build order,
//  and that the workout is refreshed before the sensors. The on-device behaviour
//  is the owner's check.
//
//  Every guard reads a file's text with its comment lines removed, so a sentence
//  of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchSensorSourceSourceTests: XCTestCase {

    // MARK: - Reading the app target

    /// A file of the app target, read from the repository root, with every
    /// comment-only line blanked out (the line count is kept).
    private func source(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    private func feedSource() throws -> String { try source("HealthKitSensorFeed.swift") }

    private func storeSource() throws -> String { try source("HealthKitWorkoutStore.swift") }

    private func viewSource() throws -> String { try source("ContentView.swift") }

    // MARK: - Matching helpers

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries so line indexes stay true. A trailing `//` comment on a code
    /// line is blanked too, so prose there can neither satisfy a guard nor trip
    /// one; none of the three guarded files keeps a `//` inside a string
    /// literal (checked 2026-10-10).
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// The number of the first line containing `needle`, or nil.
    private func lineIndex(of needle: String, in source: String) -> Int? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.firstIndex { $0.contains(needle) }
    }

    /// The brace-balanced body of `func <name>(`, from its opening brace to its
    /// closing one, or nil when the function is not there. `return` is not
    /// required: a one-expression body is exactly the shape the short probes use.
    private func functionBody(named name: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("func \(name)(") }) else {
            return nil
        }

        var depth = 0
        var started = false
        var body: [String] = []
        for line in lines[start...] {
            for character in line {
                if character == "{" {
                    depth += 1
                    started = true
                } else if character == "}" {
                    depth -= 1
                }
            }
            if started { body.append(line) }
            if started && depth == 0 { break }
        }
        return started ? body.joined(separator: "\n") : nil
    }

    /// The parenthesised argument text of the first call to `needle`, braces and
    /// parens balanced, or nil when the call is not there.
    private func arguments(of needle: String, in source: String) -> String? {
        guard let call = source.range(of: needle) else { return nil }

        var depth = 0
        var started = false
        var collected = ""
        for character in source[call.upperBound...] {
            if character == "(" {
                depth += 1
                started = true
                if depth == 1 { continue }
            } else if character == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            if started { collected.append(character) }
        }
        return started ? collected : nil
    }

    /// The `$revision` subscription, from its declaration to its `store(in:)`.
    private func revisionSink(in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.contains("$revision") }) else {
            return nil
        }

        var collected: [String] = []
        for line in lines[start...] {
            collected.append(String(line))
            if line.contains(".store(in:") { break }
        }
        return collected.joined(separator: "\n")
    }

    // MARK: - S-3109: the feed is the real source and the store asks for both reads

    func testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes() throws {
        let feed = try feedSource()

        XCTAssertTrue(
            feed.contains("WatchSensorSource"),
            "the feed has to be the package's `WatchSensorSource`, not a lookalike (D-2103)"
        )
        XCTAssertTrue(
            feed.contains("HKLiveWorkoutBuilderDelegate"),
            "the feed is fed by the builder's delegate callbacks (D-2103)"
        )
        XCTAssertTrue(
            feed.contains("HKQuantityType(.heartRate)"),
            "the feed reduces heart rate samples and nothing else (D-2103)"
        )
        XCTAssertTrue(
            feed.contains("HKQuantityType(.stepCount)"),
            "the feed reduces step samples and nothing else (D-2103)"
        )
        XCTAssertFalse(
            feed.contains("import CoreLocation"),
            "GPS, distance and route stay out of this scope (D-2100)"
        )

        let locationBody = try XCTUnwrap(
            functionBody(named: "locationPermission", in: feed),
            "the feed has to answer the location probe (D-2104)"
        )
        XCTAssertTrue(
            locationBody.contains(".unavailable"),
            "the location probe answers `.unavailable`: nothing here measures a route (D-2100)"
        )
        XCTAssertFalse(
            locationBody.contains(".granted"),
            "the location probe never claims a permission it does not use (D-2100)"
        )

        let store = try storeSource()
        let request = try XCTUnwrap(
            arguments(of: "requestAuthorization", in: store),
            "the store asks for authorization in one request (D-1503)"
        )
        let readParts = request.components(separatedBy: "read:")
        XCTAssertEqual(
            readParts.count,
            2,
            "the request carries exactly one read list (D-2105)"
        )
        let readList = readParts[1]
        XCTAssertTrue(
            readList.contains("HKQuantityType(.heartRate)"),
            "a read left out of the one request is a stream that never produces "
                + "anything: the builder's statistics only carry what was asked for (D-2103, D-2105)"
        )
        XCTAssertTrue(
            readList.contains("HKQuantityType(.stepCount)"),
            "both read types belong in the same request, so the user sees one "
                + "prompt (D-2105)"
        )
    }

    // MARK: - S-3110: the host wires the sensors and refreshes the workout first

    func testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst() throws {
        let view = try viewSource()

        XCTAssertTrue(
            view.contains("WatchLoggingState(engine: engine, sensors:"),
            "the logging surface reads the live sensors, so the host hands it the "
                + "recorder it built (D-2106)"
        )
        XCTAssertTrue(
            view.contains("WatchSensorCoordinator("),
            "the host follows the session with a sensor coordinator (D-2106)"
        )

        let sink = try XCTUnwrap(
            revisionSink(in: view),
            "the host has a `$revision` subscription that settles the session's "
                + "platform work (D-2106)"
        )
        let workoutLine = try XCTUnwrap(
            lineIndex(of: "self.workout.refresh(", in: sink),
            "the sink refreshes the workout (D-2106)"
        )
        let sensorsLine = try XCTUnwrap(
            lineIndex(of: "self.sensors.refresh(", in: sink),
            "the sink refreshes the sensors (D-2106)"
        )
        XCTAssertLessThan(
            workoutLine,
            sensorsLine,
            "the workout is refreshed first: by the time a subscription starts, the "
                + "builder, the permission outcome and the feed exist (D-2106)"
        )
    }

    // MARK: - S-3114: the feed never opens a prompt of its own

    func testS3114TheFeedNeverPromptsAndAnswersUnavailableWithoutHealthData() throws {
        let feed = try feedSource()

        XCTAssertFalse(
            feed.contains("requestAuthorization"),
            "the feed reports the store's one authorization outcome and never "
                + "opens a second prompt (D-2104)"
        )

        let lines = feed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let probeLines = lines.enumerated().filter {
            $0.element.contains("HKHealthStore.isHealthDataAvailable()")
        }
        XCTAssertFalse(
            probeLines.isEmpty,
            "the probes ask the platform whether there is health data at all (D-2104)"
        )
        for (index, _) in probeLines {
            let window = lines[index..<min(index + 3, lines.count)].joined(separator: "\n")
            XCTAssertTrue(
                window.contains(".unavailable"),
                "no health data answers `.unavailable`, the first branch of "
                    + "D-2104's rule, on line \(index + 1)"
            )
        }
    }

    // MARK: - S-3116: the feed is nonisolated, so HealthKit may call it off the main actor

    func testS3116TheFeedIsDeclaredNonisolated() throws {
        let feed = try feedSource()
        let lines = feed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let declaration = try XCTUnwrap(
            lines.first { $0.contains("HealthKitSensorFeed") && $0.contains("class") },
            "the feed's declaration has to be in the file (D-2103)"
        )
        XCTAssertTrue(
            declaration.contains("nonisolated"),
            "the target's default isolation is the main actor, and HealthKit calls "
                + "the delegate off it: the class has to say `nonisolated` (D-2113)"
        )
        XCTAssertTrue(
            declaration.contains("final class HealthKitSensorFeed"),
            "the declaration is `nonisolated final class HealthKitSensorFeed` (D-2113)"
        )
    }
}
