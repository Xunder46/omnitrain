//
//  WatchPagerSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the wrist's swipe pager: the shell mounts it, the view
//  mounts one paged `TabView`, and the Crown stays on the logging surface.
//
//  Plan: `docs/plans/2026-10-20-46b-wrist-swipe-pager-plan/2026-10-20-46b-wrist-swipe-pager-plan.md`,
//  scenarios S-6610, S-6611 and S-6612 (decisions D-3, D-5, D-6).
//
//  The pager's rules are held by `WatchPagerModelTests`; what is left is the
//  shape of the watchOS-only view, which `swift test` cannot compile. What can
//  be held off-device is what drift would break: the shell's one mount, the
//  single `TabView` with no dots, the locked page's drag, and the absence of a
//  second Crown binding — the Crown belongs to the logging surface, and a pager
//  that captured it would take the value stepping away.
//
//  Every guard reads a file's text with its comment lines removed, so a sentence
//  of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchPagerSourceTests: XCTestCase {

    // MARK: - Reading the two targets

    /// A file of the app target, read from the repository root, with every
    /// comment-only line blanked out (the line count is kept).
    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// A file of the watch package's engine module, read the same way.
    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
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

    // MARK: - S-6610: the shell mounts the pager

    func testS6610TheLoggingSurfaceMountsThePagerAndNotTheBareView() throws {
        let source = try appSource("ContentView.swift")
        let surface = try XCTUnwrap(
            propertyBody(named: "loggingSurface", in: source),
            "ContentView has no loggingSurface property"
        )

        XCTAssertTrue(
            surface.contains("WatchLoggingPagerView("),
            "the logging surface should mount WatchLoggingPagerView"
        )
        XCTAssertFalse(
            surface.contains("WatchLoggingView("),
            "the logging surface should not mount the bare WatchLoggingView"
        )
    }

    // MARK: - S-6611: one paged TabView and the locked drag

    func testS6611ThePagerIsOneTabViewWithoutDotsAndAnswersADragWhenLocked() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")

        XCTAssertTrue(
            source.contains(".tabViewStyle(.page(indexDisplayMode: .never))"),
            "the paged TabView should carry no dots: the page label is the counter"
        )
        XCTAssertEqual(
            occurrences(of: "TabView(", in: source), 1,
            "the pager should mount exactly one TabView"
        )
        XCTAssertTrue(
            source.contains("DragGesture("),
            "the locked single page should answer a drag"
        )
    }

    // MARK: - S-6612: the Crown stays on the logging surface

    func testS6612ThePagerTakesNoCrownAndNoFocus() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")

        XCTAssertFalse(
            source.contains("digitalCrownRotation"),
            "the Crown belongs to WatchLoggingView; the pager must not bind it"
        )
        XCTAssertFalse(
            source.contains(".focusable"),
            "the pager must not take focus, or the Crown's value stepping goes with it"
        )
    }
}
