//
//  WatchPortionCrownTests.swift
//  WatchSessionEngineTests
//
//  S-8611 to S-8616 of
//  `docs/plans/2026-10-23-56-wrist-quick-fixes-plan/2026-10-23-56-wrist-quick-fixes-plan.md`
//  — the food portion's Crown arithmetic (D-4): positive Crown movement raises
//  the portion, the direction that raises a value on the logging screen, and
//  travel short of one detent is carried to the next event rather than rounding
//  the portion off its step. The model's `turn(to:)` is watchOS-only, so it is
//  held by one source guard.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchPortionCrownTests: XCTestCase {

    // MARK: - S-8611 / S-8612 one detent, either way (a sign-flip mutant fails both)

    func testS8611OneDetentUpIsOnePositiveDetent() {
        let step = WatchPortionCrown.turn(from: 0, to: 1)
        XCTAssertEqual(step.detents, 1, "a detent up raises the portion")
        XCTAssertEqual(step.position, 0, accuracy: 1e-9, "the consumed detent is handed back")
    }

    func testS8612OneDetentDownIsOneNegativeDetent() {
        let step = WatchPortionCrown.turn(from: 0, to: -1)
        XCTAssertEqual(step.detents, -1, "a detent down lowers the portion")
        XCTAssertEqual(step.position, 0, accuracy: 1e-9, "the consumed detent is handed back")
    }

    // MARK: - S-8613 to S-8615 travel short of a detent is carried, not rounded off

    func testS8613TravelShortOfOneDetentMovesNothing() {
        let step = WatchPortionCrown.turn(from: 0, to: 0.4)
        XCTAssertEqual(step.detents, 0, "less than a detent is no step")
        XCTAssertEqual(step.position, 0.4, accuracy: 1e-9, "the travel is carried to the next event")
    }

    func testS8614CarriedTravelJoinsTheNextEvent() {
        let step = WatchPortionCrown.turn(from: 0.4, to: 1.4)
        XCTAssertEqual(step.detents, 1, "the carried travel completes one detent")
        XCTAssertEqual(step.position, 0.4, accuracy: 1e-9, "the consumed detent is handed back")
    }

    func testS8615WholeDetentsHandTheCrownBackNearZero() {
        let step = WatchPortionCrown.turn(from: 0, to: 3)
        XCTAssertEqual(step.detents, 3)
        XCTAssertEqual(step.position, 0, accuracy: 1e-9, "the Crown never reaches the end of its range")
    }

    // MARK: - S-8616 the model turns through the helper

    /// The watchOS-only model reads its source: the body of `turn(to:)` calls
    /// the shared helper and steps the portion by its detents, and the leading
    /// minus that turned the Crown backwards is gone.
    func testS8616TheModelTurnsThroughTheHelper() throws {
        let source = try engineSource("WatchNutritionView.swift")
        let body = try XCTUnwrap(
            body(ofFunctionContaining: "func turn(to points: Double)", in: source),
            "WatchNutritionModel.turn(to:) exists"
        )

        XCTAssertTrue(
            body.contains("WatchPortionCrown.turn(from: crownPosition, to: points)"),
            "the sign and detent math lives in the shared helper"
        )
        XCTAssertTrue(
            body.contains("state.stepPortion(step.detents)"),
            "the whole detents step the portion"
        )
        XCTAssertTrue(
            body.contains("crownPosition = step.position"),
            "the consumed detent is handed back to the Crown"
        )
        XCTAssertFalse(
            body.contains("stepPortion(-"),
            "the leading minus that turned the Crown backwards is gone"
        )
        XCTAssertFalse(
            body.contains("-("),
            "the leading minus that turned the Crown backwards is gone"
        )
    }
}

private extension WatchPortionCrownTests {

    /// A file of the watch package's engine module, read from the repository
    /// root, with every comment-only line blanked out (the line count is kept).
    func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries so line indexes stay true. A trailing `//` comment on a code
    /// line is blanked too, so prose there can neither satisfy a guard nor trip
    /// one.
    func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// The text of the first function whose line contains `needle`, from that
    /// line to the closing brace at the function's own indent.
    func body(ofFunctionContaining needle: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else {
            return nil
        }
        let indent = lines[start].prefix(while: { $0 == " " }).count

        var collected: [String] = []
        for line in lines[start...] {
            collected.append(line)
            let lineIndent = line.prefix(while: { $0 == " " }).count
            if line.trimmingCharacters(in: .whitespaces) == "}", lineIndent == indent {
                break
            }
        }
        return collected.joined(separator: "\n")
    }
}
