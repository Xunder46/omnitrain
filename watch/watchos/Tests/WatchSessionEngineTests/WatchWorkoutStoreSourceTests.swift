//
//  WatchWorkoutStoreSourceTests.swift
//  WatchSessionEngineTests
//
//  The source guard for the app target's real platform workout store: the
//  name → workout type map it carries is the shared contract's, and nothing else.
//
//  Plan: `docs/plans/2026-10-10-19c-watch-keep-alive-plan/2026-10-10-19c-watch-keep-alive-plan.md`,
//  scenario S-1509 and decision D-1509.
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

    /// The distinct `watchos` names the shared contract carries.
    private func contractActivityNames() throws -> Set<String> {
        let contract = try Fixtures.sensorContract()
        let types = try XCTUnwrap(
            contract["activityTypes"] as? [String: [String: String]],
            "the contract carries the modality → platform type table"
        )
        let names = Set(types.values.compactMap { $0["watchos"] })
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