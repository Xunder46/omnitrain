//
//  WatchTimerCueTests.swift
//  WatchSessionEngineTests
//
//  S-15105 to S-15107 of
//  `docs/plans/2026-10-26-82-wrist-health-failure-and-haptics-plan/2026-10-26-82-wrist-health-failure-and-haptics-plan.md`
//  — the cue table for the countdown taps (D-7), and the source guards on the
//  two `#if os(watchOS)` files that carry the taps (D-7, D-8), which `swift
//  test` does not compile.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchTimerCueTests: XCTestCase {

    // MARK: - Source readers (copied from WatchHealthAccessWiringSourceTests.swift,
    // whose helpers are private to that file)

    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.sourcesRoot.appendingPathComponent(name)
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

    /// The brace-balanced block that opens at the first `{` after `marker`.
    private func block(after marker: String, in source: String) throws -> String {
        let markerRange = try XCTUnwrap(source.range(of: marker), "no \(marker) in source")
        let open = try XCTUnwrap(
            source.range(of: "{", range: markerRange.upperBound..<source.endIndex),
            "no block after \(marker)"
        )
        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[open.lowerBound...index])
                }
            }
            index = source.index(after: index)
        }
        XCTFail("unbalanced braces after \(marker)")
        return ""
    }

    /// The block's own lines, trimmed, empties dropped: the exact statements
    /// and braces, in order.
    private func statements(_ block: String) -> [String] {
        block.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - S-15105 the cue table

    func testS15105TheCueTableMapsEachCountdownKindAndNothingElse() {
        XCTAssertEqual(WatchTimerHaptics.cue(for: "round"), .roundEnd)
        XCTAssertEqual(WatchTimerHaptics.cue(for: "hold"), .holdEnd)
        XCTAssertEqual(WatchTimerHaptics.cue(for: "elapsed"), .targetReached)
        XCTAssertNil(WatchTimerHaptics.cue(for: "rest"), "a rest is a count-up, owed no tap")
        XCTAssertNil(WatchTimerHaptics.cue(for: "bogus"), "an unknown kind is owed no tap")
        XCTAssertEqual(
            Set<WatchHapticCue>([.roundEnd, .holdEnd, .targetReached]).count,
            3,
            "the three cues are pairwise distinct"
        )
    }

    // MARK: - the optional switch the view's play(_:) uses

    /// `WristHaptics.play(_:)` switches over the optional cue directly, in a
    /// file only the Xcode build compiles; this twin pins that the pattern
    /// compiles and maps the way the source guard below reads it.
    private func mapped(_ cue: WatchHapticCue?) -> String {
        switch cue {
        case .roundEnd: return "notification"
        case .holdEnd: return "stop"
        case .targetReached: return "retry"
        case nil: return "notification"
        }
    }

    func testTheOptionalSwitchTheViewUsesMapsEachCue() {
        XCTAssertEqual(mapped(WatchTimerHaptics.cue(for: "round")), "notification")
        XCTAssertEqual(mapped(WatchTimerHaptics.cue(for: "hold")), "stop")
        XCTAssertEqual(mapped(WatchTimerHaptics.cue(for: "elapsed")), "retry")
        XCTAssertEqual(mapped(WatchTimerHaptics.cue(for: "rest")), "notification")
        XCTAssertEqual(mapped(WatchTimerHaptics.cue(for: "bogus")), "notification")
    }

    // MARK: - S-15106 the wrist maps each cue and the finish tap

    func testS15106WristHapticsMapsEachCueAndTheFinishTap() throws {
        let source = try engineSource("WatchLoggingView.swift")

        let play = try block(
            after: "public func play(_ milestone: WatchTimerMilestone)",
            in: source
        )
        XCTAssertEqual(
            statements(play),
            [
                "{",
                "switch WatchTimerHaptics.cue(for: milestone.kind) {",
                "case .roundEnd:",
                "WKInterfaceDevice.current().play(.notification)",
                "case .holdEnd:",
                "WKInterfaceDevice.current().play(.stop)",
                "case .targetReached:",
                "WKInterfaceDevice.current().play(.retry)",
                "case nil:",
                "WKInterfaceDevice.current().play(.notification)",
                "}",
                "}",
            ],
            "each countdown kind gets its own tap, and an unknown kind keeps the old alert"
        )

        let finished = try block(after: "public func playFinished()", in: source)
        XCTAssertEqual(
            statements(finished),
            ["{", "WKInterfaceDevice.current().play(.success)", "}"],
            "the Finish tap is the success tap"
        )
    }

    // MARK: - S-15107 the menu plays the tap on Finish, never on Cancel

    func testS15107TheMenuFinishesWithTheTapAndNeverOnCancel() throws {
        let source = try engineSource("WatchMenuView.swift")

        let initMarker = try XCTUnwrap(source.range(of: "public init("), "no init")
        let initOpen = try XCTUnwrap(
            source.range(of: "{", range: initMarker.upperBound..<source.endIndex)
        )
        let initParameters = String(source[initMarker.upperBound..<initOpen.lowerBound])
        XCTAssertTrue(
            initParameters.contains("haptics: WatchHaptics = WristHaptics()"),
            "the menu takes the wrist's haptics, defaulting to the device"
        )
        XCTAssertTrue(
            source.contains("private let haptics: WatchHaptics"),
            "the haptics are stored, not built per body run"
        )
        XCTAssertTrue(
            source.contains("self.haptics = haptics"),
            "the handed-over haptics are the ones stored"
        )

        let finish = try block(after: "Button(WatchMenuCopy.confirmFinish)", in: source)
        XCTAssertEqual(
            statements(finish),
            [
                "{",
                "Task {",
                "haptics.playFinished()",
                "await state.finish()",
                "onFinish()",
                "}",
                "}",
            ],
            "the Finish tap is the first statement, before the rating state's end"
        )

        let cancelLine = try XCTUnwrap(
            source.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.contains("confirmCancel") },
            "no Cancel line"
        )
        XCTAssertEqual(
            cancelLine,
            "Button(WatchMenuCopy.confirmCancel, role: .cancel) {}",
            "the Cancel line is the empty action, untouched"
        )
        XCTAssertFalse(cancelLine.contains("playFinished"), "Cancel plays no tap")
    }
}
