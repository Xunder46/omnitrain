//
//  WatchPagerSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the wrist's swipe pager: the shell mounts it, the view
//  mounts one logger with a swipe between exercises, and the Crown stays on
//  the logging surface.
//
//  Plan: `docs/plans/2026-10-20-46b-wrist-swipe-pager-plan/2026-10-20-46b-wrist-swipe-pager-plan.md`,
//  scenarios S-6610, S-6611 and S-6612 (decisions D-3, D-5, D-6); plan 79
//  (`docs/plans/2026-10-26-79-wrist-swipe-and-rest-next-plan/2026-10-26-79-wrist-swipe-and-rest-next-plan.md`)
//  rewrites S-6611 and adds S-9111: no page-turn, so no `TabView` and no
//  preview card — one logger, and a swipe that switches at once.
//
//  The pager's rules are held by `WatchPagerModelTests`; what is left is the
//  shape of the watchOS-only view, which `swift test` cannot compile. What can
//  be held off-device is what drift would break: the shell's one mount, the
//  one logger with its swipe and no page-turn, the locked page's drag, and the
//  absence of a second Crown binding — the Crown belongs to the logging
//  surface, and a pager that captured it would take the value stepping away.
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

    // MARK: - S-6611: no TabView, and the locked drag

    func testS6611ThePagerIsNoTabViewAndStillAnswersADragWhenLocked() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")

        XCTAssertFalse(
            source.contains("TabView("),
            "plan 79 D-1: the pager mounts one logger, not a TabView of pages"
        )
        XCTAssertFalse(
            source.contains(".tabViewStyle"),
            "there is no paged TabView left, so no tab view style either"
        )
        XCTAssertEqual(
            occurrences(of: "DragGesture(minimumDistance: 24)", in: source), 2,
            "exactly two drags: the swipe between exercises and the locked branch"
        )
        XCTAssertTrue(
            source.contains("let across = abs(value.translation.width)"),
            "the locked branch keeps its own width reading, so it is not lost"
        )
    }

    // MARK: - S-9111: one logger with a swipe

    func testS9111ThePagerIsOneLoggerWithASwipe() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")

        XCTAssertFalse(
            source.contains("WatchExercisePreviewPage"),
            "plan 79 D-1: the preview card between exercises is gone"
        )
        XCTAssertTrue(
            source.contains(".id("),
            "plan 79 D-5: the shown logger is rebuilt per exercise through its slot id"
        )
        XCTAssertGreaterThanOrEqual(
            occurrences(of: "DragGesture(minimumDistance: 24)", in: source), 2,
            "the swipe between exercises and the locked branch both drag"
        )
        XCTAssertTrue(
            source.contains("pager.neighbourIndex(of: selection, towardsNext:"),
            "plan 79 D-2: the swipe asks the model which page it reaches"
        )
        XCTAssertTrue(
            source.contains("state.focusSlotId = pager.focusSlotId(for: target)"),
            "plan 52 D-5: the focus names the page the user reached before the engine has moved"
        )
        XCTAssertTrue(
            source.contains("withAnimation(Self.slideAnimation) { selection = target }"),
            "plan 85 D-3: the selection moves to the page the user reached, animated"
        )
        XCTAssertTrue(
            source.contains(".onChange(of: selection)"),
            "the settled selection lands through land(on:)"
        )
        XCTAssertTrue(
            source.contains("play(.click)"),
            "plan 79 D-4: a swipe that moves gives a click"
        )
        XCTAssertTrue(
            source.contains("pager.neighbourIndex(of: selection, towardsNext: across < 0)"),
            "plan 79 D-3: a finger moving left (negative width) goes to the NEXT exercise"
        )
        XCTAssertTrue(
            source.contains("guard abs(across) > 24, abs(across) > abs(value.translation.height),"),
            "plan 79 D-3: only a mostly horizontal drag longer than 24 points switches exercise"
        )
        XCTAssertFalse(
            source.contains("digitalCrownRotation"),
            "the Crown belongs to WatchLoggingView; the pager must not bind it"
        )
        XCTAssertFalse(
            source.contains(".focusable"),
            "the pager must not take focus, or the Crown's value stepping goes with it"
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
