//
//  WatchRestIsCountUpTests.swift
//  WatchSessionEngineTests
//
//  The wrist's rest is a count-up (D-160): nothing on the native side names a
//  preset rest length, and nothing starts a rest timer with a planned duration.
//  The Dart twin of this rule (`test/rest_is_count_up_contract_test.dart`)
//  lands in a later phase of the same plan; until then this scan is the Swift
//  half.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchRestIsCountUpTests: XCTestCase {

    /// The rule, in the words a failing scan repeats.
    private let rule = """
    Rest is a count-up from the moment a set is logged to the next set; there \
    is no preset rest length, no rest countdown and no rest alarm on any \
    device. See docs/global_conventions.md (rest rule) and \
    docs/plans/2026-10-08-18b-watch-rest-count-up-plan, D-160.
    """

    /// Every `.swift` file under `watch/watchos/Sources`.
    private func sourceFiles() throws -> [URL] {
        let root = Fixtures.repositoryRoot.appendingPathComponent("watch/watchos/Sources")
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let file = walker?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            files.append(file)
        }
        return files
    }

    func testS166NoSwiftSourceNamesAPresetRestLength() throws {
        var offenders: [String] = []

        for file in try sourceFiles() {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains("restSeconds") {
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }

        XCTAssertTrue(offenders.isEmpty, "\(rule) Offending sites: \(offenders)")
    }

    func testS166NoSwiftSourceStartsARestWithAPlannedDuration() throws {
        var offenders: [String] = []

        for file in try sourceFiles() {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for (index, line) in lines.enumerated() where line.contains("WatchTimerKind.rest") {
                let window = lines[index..<min(index + 3, lines.count)]
                    .joined(separator: "\n")
                if window.contains("plannedDurationMs") {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, "\(rule) Offending sites: \(offenders)")
    }
}
