//
//  WatchRestPingWiringSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for plan 61's rest-ping rewiring: the host asks the ping on
//  its own scheduler, and the rest view only shows the clock, dimmed or lit.
//
//  Plan: `docs/plans/2026-10-23-61-wrist-down-rest-pings-plan/2026-10-23-61-wrist-down-rest-pings-plan.md`,
//  scenario S-9109.
//
//  The app target has no test target and SwiftUI does not exist on macOS where
//  `swift test` runs, so the wiring cannot be executed here. What can be held
//  off-device is what drift would break: the exact statements in the view and
//  in the host, read with every comment line blanked out so a sentence of prose
//  can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchRestPingWiringSourceTests: XCTestCase {

    // MARK: - S-9109 the view shows the clock only, the host asks the ping

    func testS9109TheRestViewShowsTheDimmedClockAndAsksNoPing() throws {
        let source = try engineSource("WatchRestView.swift")
        XCTAssertTrue(
            source.contains("@Environment(\\.isLuminanceReduced) private var dimmed"),
            "S-9109 the rest view reads the dimmed display from the environment"
        )
        XCTAssertTrue(
            source.contains(
                "TimelineView(.periodic(from: state.restStartedAt ?? Date(), by: dimmed ? 60 : 1)) { _ in"
            ),
            "S-9109 the timeline ticks every second lit and once a minute dimmed, anchored on the rest's own start"
        )
        XCTAssertTrue(
            source.contains("? WatchLoggingState.dimmedRestClock(seconds: seconds)"),
            "S-9109 dimmed, the clock shows whole minutes"
        )
        XCTAssertTrue(
            source.contains(": WatchLoggingState.clock(Double(seconds))"),
            "S-9109 lit, the clock keeps the m:ss count-up"
        )
        XCTAssertTrue(
            source.contains("Text(elapsed)"),
            "S-9109 the clock still renders through the elapsed chain S-8621 reads"
        )
        let elapsedBody = try slice(from: "private var elapsed: String {", to: "\n    }\n", in: source)
        let collapsed = elapsedBody.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        XCTAssertTrue(
            collapsed.contains(
                "return dimmed ? WatchLoggingState.dimmedRestClock(seconds: seconds) : WatchLoggingState.clock(Double(seconds))"
            ),
            "S-9109 the elapsed chain picks the dimmed clock on the dimmed branch and the lit clock on the lit branch"
        )
        XCTAssertFalse(
            collapsed.contains("!dimmed"),
            "S-9109 the dimmed branch is not inverted"
        )
        XCTAssertFalse(
            source.contains("pingIfOwed"),
            "S-9109 the view no longer asks whether a ping is owed"
        )
        XCTAssertFalse(
            source.contains("isOwed"),
            "S-9109 the ping rule's question left the view with the tick"
        )
        XCTAssertFalse(
            source.contains("playRestPing"),
            "S-9109 the view no longer plays the ping itself"
        )
        XCTAssertFalse(
            source.contains("restPingSeconds"),
            "S-9109 the phone's interval is no longer a view parameter"
        )
        XCTAssertFalse(
            source.contains("WatchRestPing()"),
            "S-9109 the view no longer holds the ping rule's state"
        )
    }

    func testS9109TheHostOwnsTheSchedulerAndArmsItOnEveryRestChange() throws {
        let source = try appSource("ContentView.swift")
        XCTAssertTrue(
            source.contains(
                "let restPings = WatchRestPingScheduler(state: logging, interval: { preferences.restPingSeconds }, haptics: WristHaptics())"
            ),
            "S-9109 the host builds the scheduler over the logging state and the phone's interval"
        )
        XCTAssertTrue(
            source.contains("self.restPings = restPings"),
            "S-9109 the host keeps the scheduler for the app's life"
        )

        let sink = try slice(from: "$revision", to: ".store(in: &cancellables)", in: source)
        let armIndex = sink.range(of: "self.restPings.arm()")
        let refreshIndex = sink.range(of: "await self.workout.refresh")
        XCTAssertNotNil(armIndex, "S-9109 the $revision sink arms the scheduler")
        XCTAssertNotNil(refreshIndex, "S-9109 the $revision sink still refreshes the workout")
        if let armIndex, let refreshIndex {
            XCTAssertTrue(
                armIndex.lowerBound < refreshIndex.lowerBound,
                "S-9109 the arm runs before the awaits in the sink's task"
            )
        }

        let catchUp = try functionBody(of: "func catchUpOnActivation()", in: source)
        let catchUpArm = catchUp.range(of: "restPings.arm()")
        let reachable = catchUp.range(of: "let reachable")
        XCTAssertNotNil(catchUpArm, "S-9109 activation arms the scheduler")
        XCTAssertNotNil(reachable, "S-9109 activation still reads the reachability")
        if let catchUpArm, let reachable {
            XCTAssertTrue(
                catchUpArm.lowerBound < reachable.lowerBound,
                "S-9109 the arm is the first statement of catchUpOnActivation"
            )
        }

        let restCall = try slice(from: "WatchRestView(", to: "onNext:", in: source)
        XCTAssertTrue(
            restCall.contains("state: host.logging,"),
            "S-9109 the rest view still binds to the logging state"
        )
        XCTAssertFalse(
            restCall.contains("restPingSeconds"),
            "S-9109 the rest view call passes no ping interval"
        )
    }

    // MARK: - Helpers (the source guard, as WatchRestSurfaceTests reads views)

    /// A file of the watch package's engine module, read from the repository
    /// root, with every comment-only line blanked out (the line count is kept).
    private func engineSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// The app target's host, read from the repository root, with every
    /// comment-only line blanked out (the line count is kept).
    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
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

    /// The text from the first occurrence of `from` up to (not including) the
    /// first occurrence of `to` after it.
    private func slice(from: String, to: String, in source: String) throws -> String {
        guard let start = source.range(of: from) else {
            XCTFail("S-9109 \(from) not found in the source")
            return ""
        }
        guard let end = source.range(of: to, range: start.upperBound..<source.endIndex) else {
            XCTFail("S-9109 \(to) not found after \(from) in the source")
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    /// The body of the function whose signature line contains `signature`: from
    /// that line to the next line that is exactly `    }` (four spaces, brace).
    private func functionBody(of signature: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let index = lines.firstIndex(where: { $0.contains(signature) }) else {
            XCTFail("S-9109 \(signature) not found in the source")
            return ""
        }
        var body: [String] = [String(lines[index])]
        for line in lines[(index + 1)...] {
            if line == "    }" { break }
            body.append(String(line))
        }
        return body.joined(separator: "\n")
    }
}
