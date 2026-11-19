//
//  WatchPagerSlideSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for plan 85's slide: the pager's logger sits in a `ZStack`
//  whose `.id` change is an insertion the swipe animates — from the swiped
//  side, with the focus named and the side written before the animated change,
//  and with Reduce Motion fading instead of sliding.
//
//  Plan: `docs/plans/2026-10-26-85-wrist-swipe-slide-plan/2026-10-26-85-wrist-swipe-slide-plan.md`,
//  scenarios S-15401, S-15402, S-15403 and S-15408 (decisions D-1..D-4, D-7,
//  D-8).
//
//  The slide itself is watchOS-only view code that `swift test` cannot
//  compile; what is held off-device is the shape the drift would break: the
//  slide constant, the wrapped animated write, the single `withAnimation`, and
//  the Reduce Motion ternary with its identity removal.
//
//  Every guard reads a file's text with its comment lines removed, so a
//  sentence of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchPagerSlideSourceTests: XCTestCase {

    // MARK: - Reading the engine module

    /// A file of the watch package's engine module, read from the repository
    /// root, with every comment-only line blanked out (the line count is kept).
    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.sourcesRoot
            .appendingPathComponent(name)
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries so line indexes stay true. A trailing `//` comment on a code
    /// line is blanked too, so prose there can neither satisfy a guard nor trip
    /// one.
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// The brace-balanced body of the property `var <name>:`, from its opening
    /// brace to its closing one, or nil when the property is not there.
    private func propertyBody(named name: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("var \(name):") }) else {
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
            if started, depth == 0 { return body.joined(separator: "\n") }
        }
        return nil
    }

    /// How many times `needle` occurs in `source`.
    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    // MARK: - S-15401: the slide is short, and shorter than the notice

    func testS15401TheSlideIsShorterThanTheLockedNotice() {
        XCTAssertEqual(
            WatchPagerCopy.slideSeconds, 0.2, accuracy: 0.0001,
            "S-15401 the slide is about a fifth of a second"
        )
        XCTAssertGreaterThan(
            WatchPagerCopy.slideSeconds, 0,
            "S-15401 a slide of no time is no slide"
        )
        XCTAssertLessThan(
            WatchPagerCopy.slideSeconds, WatchPagerCopy.noticeSeconds,
            "S-15401 a slide is shorter than the locked notice"
        )
    }

    // MARK: - S-15402: the logger slides in from the swiped side

    func testS15402ThePagedLoggerSlidesInFromTheSwipedSide() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")
        let paged = try XCTUnwrap(
            propertyBody(named: "paged", in: source),
            "S-15402 the pager's paged branch is where the logger lives"
        )

        let zstack = try XCTUnwrap(
            paged.range(of: "ZStack {"),
            "S-15402 plan 85 D-1: the logger sits in a ZStack, so the `.id` change is an insertion"
        )
        let logger = try XCTUnwrap(
            paged.range(of: "WatchLoggingView("),
            "S-15402 the paged branch still mounts the one logger"
        )
        XCTAssertLessThan(
            zstack.lowerBound, logger.lowerBound,
            "S-15402 the ZStack encloses the logger, and the gesture and `.onChange` live on it"
        )

        XCTAssertTrue(
            paged.contains(".transition(.asymmetric(insertion:"),
            "S-15402 plan 85 D-2: the insertion is an asymmetric transition"
        )
        XCTAssertTrue(
            paged.contains("removal: .identity))"),
            "S-15402 plan 85 D-5: the leaving logger is discarded at once, never repainted"
        )

        let focus = try XCTUnwrap(
            paged.range(of: "state.focusSlotId = pager.focusSlotId(for: target)"),
            "S-15402 the swipe names the focus synchronously"
        )
        let side = try XCTUnwrap(
            paged.range(of: "slideFromTrailing = across < 0"),
            "S-15402 plan 85 D-2: the side the logger enters from is written in the gesture"
        )
        let animated = try XCTUnwrap(
            paged.range(of: "withAnimation("),
            "S-15402 plan 85 D-3: the swipe's selection change is animated"
        )
        XCTAssertLessThan(
            side.lowerBound, animated.lowerBound,
            "S-15402 the side is written BEFORE the animated change, or the edge is stale"
        )
        XCTAssertLessThan(
            focus.lowerBound, animated.lowerBound,
            "S-15402 plan 52 D-5: the focus names the page before the engine moves"
        )
        XCTAssertTrue(
            paged.contains("withAnimation(Self.slideAnimation) { selection = target }"),
            "S-15402 plan 85 D-3: `withAnimation` encloses exactly the selection write"
        )

        XCTAssertTrue(
            source.contains("accessibilityReduceMotion"),
            "S-15402 plan 85 D-8: Reduce Motion is read"
        )
        XCTAssertTrue(
            paged.contains(".clipped()"),
            "S-15402 plan 85 D-4: the entering page cannot draw outside the screen frame"
        )
    }

    // MARK: - S-15403: only the user's own swipe is animated

    func testS15403OnlyTheUsersSwipeIsAnimated() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")
        let paged = try XCTUnwrap(
            propertyBody(named: "paged", in: source),
            "S-15403 the pager's paged branch is where the swipe lives"
        )

        XCTAssertEqual(
            occurrences(of: "withAnimation(", in: source), 1,
            "S-15403 a phone push never slides: `followEngine()` and `land(on:)` assign with no animation"
        )
        XCTAssertTrue(
            paged.contains("withAnimation("),
            "S-15403 the one animated write is the swipe's own"
        )
    }

    // MARK: - S-15408: Reduce Motion fades instead of sliding

    func testS15408ReduceMotionFadesInsteadOfSliding() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")

        // The whole insertion branch, exactly as written: the ternary inside
        // the `.asymmetric(insertion:` block, and `removal: .identity)` outside
        // it — the Reduce Motion branch keeps the identity removal (plan 85
        // D-8), so the leaving logger is never repainted in either state.
        let insertionBlock =
            ".transition(.asymmetric(insertion:\n" +
            "                reduceMotion\n" +
            "                    ? .opacity\n" +
            "                    : .move(edge: slideFromTrailing ? .trailing : .leading)\n" +
            "                        .combined(with: .opacity),\n" +
            "                removal: .identity))"
        XCTAssertTrue(
            source.contains(insertionBlock),
            "S-15408 plan 85 D-8: Reduce Motion swaps only the insertion to `.opacity`; the removal stays `.identity`"
        )
    }
}
