//
//  WatchRestIsCountUpTests.swift
//  WatchSessionEngineTests
//
//  The wrist's rest is a count-up (D-160): nothing on the native side names a
//  preset rest length, and nothing starts a rest timer with a planned duration.
//  Its Dart twin is `test/rest_is_count_up_contract_test.dart`, which scans
//  these same sources, the wrist's Dart tree and the shared message contract.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchRestIsCountUpTests: XCTestCase {

    /// The rule, in the words a failing scan repeats. It is the wording of
    /// `docs/global_conventions.md`, "Rest rule: rest is a count-up".
    private let rule = """
    Rest is a count-up from the moment a set is logged to the moment the next \
    set starts. There is no preset rest length, no rest countdown and no \
    end-of-rest alarm on any device. The one allowed rest cue is the rest ping. \
    See docs/global_conventions.md, "Rest rule: \
    rest is a count-up", and \
    docs/plans/2026-10-08-18b-watch-rest-count-up-plan, D-160 and D-164. Do not \
    add a preset rest length or a rest countdown; if you think the product \
    needs one, ask the owner.
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
