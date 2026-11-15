//
//  WatchWorkoutStoreSourceTests.swift
//  WatchSessionEngineTests
//
//  The source guard for the app target's real platform workout store: the
//  name → workout type map it carries is the shared contract's, and nothing else.
//
//  Plans: `docs/plans/2026-10-10-19c-watch-keep-alive-plan/2026-10-10-19c-watch-keep-alive-plan.md`,
//  scenario S-1509 and decision D-1509, and
//  `docs/plans/2026-11-14-168-health-walk-type-and-relaunch-plan/2026-11-14-168-health-walk-type-and-relaunch-plan.md`,
//  scenario S-16809 and decisions D-16804, D-16805 (the save outcome and a
//  held-session discard are noted, and walking/running distance is collected and
//  shared).
//
//  The app target has no test target, and `HKWorkoutActivityType` does not exist
//  on macOS where `swift test` runs, so the store itself cannot be executed here.
//  What can be held off-device is the one thing drift would break: the set of
//  names the mapping answers to, and that anything unnamed still lands on the
//  generic type. The on-device behaviour is the owner's check (S-1506).
//

import Foundation
import XCTest

final class WatchWorkoutStoreSourceTests: XCTestCase {

    /// The app target's store, from the repository root.
    private func storeSource() throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/HealthKitWorkoutStore.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The distinct `watchos` names the shared contract carries: the union of
    /// the modality table's, the distance table's and the generic type's
    /// (D-4, S-10506).
    private func contractActivityNames() throws -> Set<String> {
        let contract = try Fixtures.sensorContract()
        let types = try XCTUnwrap(
            contract["activityTypes"] as? [String: [String: String]],
            "the contract carries the modality → platform type table"
        )
        let distanceTypes = try XCTUnwrap(
            contract["distanceActivityTypes"] as? [String: [String: String]],
            "the contract carries the distance exercise → platform type table"
        )
        let generic = try XCTUnwrap(
            contract["genericActivityType"] as? [String: String],
            "the contract carries the generic platform type"
        )
        var names = Set(
            (Array(types.values) + Array(distanceTypes.values)).compactMap { $0["watchos"] }
        )
        if let genericName = generic["watchos"] { names.insert(genericName) }
        XCTAssertFalse(names.isEmpty, "a contract with no names proves nothing")
        return names
    }

    /// The labels of the file's `case "<name>":` arms. Only the name mapping uses
    /// string labels: the reverse mapping switches on the enum, so a second
    /// string table cannot hide in it.
    private func mappedNames(in source: String) throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: "case \"([A-Za-z]+)\":")
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(
            pattern.matches(in: source, range: range).compactMap { match -> String? in
                guard let label = Range(match.range(at: 1), in: source) else { return nil }
                return String(source[label])
            }
        )
    }

    /// Whether a `default:` arm names `.other` — the fallback an unmapped name
    /// takes (D-1509).
    private func hasDefaultNamingOther(in source: String) -> Bool {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        for (index, line) in lines.enumerated() where line.hasPrefix("default:") {
            let window = lines[index..<min(index + 3, lines.count)].joined(separator: "\n")
            if window.contains(".other") { return true }
        }
        return false
    }

    // MARK: - S-16809 helpers

    private func hostSource() throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/ContentView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The source with every comment line emptied and every trailing comment cut,
    /// so prose can neither satisfy a guard nor trip one.
    private func strippingComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// One declaration's own text: from the line that opens it to the line its
    /// braces balance again, so a statement in a neighbouring function cannot
    /// satisfy a guard about this one.
    private func body(of declaration: String, in source: String) throws -> String {
        let lines = strippingComments(source)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let start = try XCTUnwrap(
            lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(declaration) },
            "the store declares `\(declaration)`"
        )
        var depth = 0
        var opened = false
        var collected: [String] = []
        for line in lines[start...] {
            collected.append(line)
            for character in line {
                if character == "{" { depth += 1; opened = true }
                if character == "}" { depth -= 1 }
            }
            if opened && depth == 0 { return collected.joined(separator: "\n") }
        }
        XCTFail("`\(declaration)` never balances its braces")
        return collected.joined(separator: "\n")
    }

    /// The text between two markers of one body, exclusive of both.
    private func slice(in text: String, from start: String, to end: String) throws -> String {
        let from = try XCTUnwrap(text.range(of: start), "the body carries `\(start)`")
        let rest = text[from.upperBound...]
        let to = try XCTUnwrap(rest.range(of: end), "the body carries `\(end)`")
        return String(rest[..<to.lowerBound])
    }

    /// `text` with every run of whitespace removed, so a statement a formatter
    /// wrapped over four lines still reads as one.
    private func squeezing(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined()
    }

    // MARK: - S-16809 (D-16804) the save outcome and the held discard are recorded

    func testS16809TheStoreNotesTheSaveOutcomeAndTheHeldDiscard() throws {
        let source = try storeSource()
        let end = try body(of: "func end(saving: Bool) async", in: source)
        let begin = try body(of: "func begin(_ activityType: String, outdoors: Bool) async", in: source)

        // The failure that used to vanish: `finishWorkout()`'s empty catch.
        let saving = try slice(in: end, from: "if saving {", to: "} else {")
        XCTAssertTrue(
            squeezing(saving).contains("finishWorkout()"),
            "S-16809 the saving branch is the one that finishes the workout"
        )
        XCTAssertTrue(
            saving.contains(#""workout_saved""#),
            "S-16809 a finished workout is noted as saved, so a walk that reached Health says so"
        )
        XCTAssertTrue(
            saving.contains(#""workout_save_failed""#),
            "S-16809 a thrown save is noted, so a walk that never reached Health says so too"
        )

        // The statement that destroyed the first 25 minutes of the owner's walk:
        // `begin`'s replace rule ended the adopted session without a word.
        let discard = try slice(in: begin, from: "if let held = session {", to: "await end(saving: false)")
        XCTAssertTrue(
            discard.contains(#""workout_end""#) && discard.contains("discarded_held "),
            "S-16809 the session a second begin ends is noted as discarded before it is ended"
        )

        // The log reaches the store from the host that builds it.
        let view = strippingComments(try hostSource())
        XCTAssertTrue(
            view.contains(
                [
                    "let healthStore = HealthKitWorkoutStore(",
                    "            location: WatchTrackedLocation(source: CoreLocationRawSource()),",
                    "            diagnostics: diagnostics",
                    "        )",
                ].joined(separator: "\n")
            ),
            "S-16809 the one diagnostics log is handed to the health store"
        )
    }

    // MARK: - S-16809 (D-16805) distance is collected and shared

    func testS16809TheStoreCollectsAndSharesDistance() throws {
        let source = try storeSource()
        let begin = squeezing(
            try body(of: "func begin(_ activityType: String, outdoors: Bool) async", in: source)
        )

        XCTAssertTrue(
            begin.contains("enableCollection(for:HKQuantityType(.distanceWalkingRunning),predicate:nil)"),
            "S-16809 the builder is told to collect walking and running distance, so a "
                + "walk Health agrees with exists carries its distance"
        )

        let authorization = try body(of: "private func resolveAuthorization() async -> Bool",
                                     in: source)
        let shared = try slice(in: authorization, from: "toShare:", to: "read:")
        XCTAssertTrue(
            squeezing(shared).contains("HKQuantityType(.distanceWalkingRunning)"),
            "S-16809 the distance type is shared, or the workout cannot save it"
        )
        // A type the request does not read is a collection that never produces a
        // sample (D-2103), so the enabled type is asked for on both sides.
        let read = try slice(in: authorization, from: "read:",
                             to: "HKSeriesType.workoutRoute()]")
        XCTAssertTrue(
            squeezing(read).contains("HKQuantityType(.distanceWalkingRunning)"),
            "S-16809 the distance type is read, or `enableCollection` collects nothing"
        )
    }

    func testS1509TheStoreMapsEveryContractActivityName() throws {
        let contract = try contractActivityNames()
        let source = try storeSource()

        XCTAssertEqual(
            try mappedNames(in: source),
            contract,
            "the store's name map has to be the shared contract's, exactly: a "
                + "typo, an added name or a dropped one is drift the guard exists "
                + "to catch (D-1509)"
        )
        XCTAssertTrue(
            hasDefaultNamingOther(in: source),
            "an unmapped name has to land on the generic `.other` type: a workout "
                + "with the wrong type is correctable, no workout at all is not"
        )
    }
}