//
//  WatchHostHopSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the app target's host hop: the radio's incoming handler
//  runs off the main actor, so the counter the views watch has to be bumped on
//  it.
//
//  Plan: `docs/plans/2026-10-20-46c-engine-serialisation-plan/2026-10-20-46c-engine-serialisation-plan.md`,
//  scenario S-6507 (decision D-4).
//
//  The app target has no test target and SwiftUI does not exist on macOS where
//  `swift test` runs, so the host cannot be executed here. What can be held
//  off-device is what drift would break: that the arrival path hops to the main
//  actor before touching `revision`, and that the reachability path — which
//  already runs on it — was left alone.
//
//  Every guard reads the file's text with its comment lines removed, so a
//  sentence of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchHostHopSourceTests: XCTestCase {

    // MARK: - Reading the app target

    /// The app target's host, read from the repository root, with every
    /// comment-only line blanked out (the line count is kept).
    private func source(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    private func viewSource() throws -> String { try source("ContentView.swift") }

    /// Blanks every line whose trimmed text starts with `//`, keeping the line
    /// boundaries so line indexes stay true. A trailing `//` comment on a code
    /// line is blanked too, so prose there can neither satisfy a guard nor trip
    /// one; the guarded file keeps no `//` inside a string literal.
    private func strippingCommentLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { return "" }
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - Matching helpers

    /// The lines of `source`.
    private func sourceLines(_ source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// The brace-balanced body of the first line containing `needle`, from its
    /// opening brace to its closing one, or nil when that line is not there.
    private func braceBody(ofLineContaining needle: String, in source: String) -> String? {
        let allLines = sourceLines(source)
        guard let start = allLines.firstIndex(where: { $0.contains(needle) }) else {
            return nil
        }

        var depth = 0
        var started = false
        var body: [String] = []
        for line in allLines[start...] {
            for character in line {
                if character == "{" {
                    depth += 1
                    started = true
                } else if character == "}" {
                    depth -= 1
                }
            }
            if started { body.append(line) }
            if started && depth == 0 { break }
        }
        return started ? body.joined(separator: "\n") : nil
    }

    /// A line of `source` whose trimmed text is exactly `text`: the statement,
    /// not one that merely contains it (the hopped form contains the bare one).
    private func hasStatement(_ text: String, in source: String) -> Bool {
        sourceLines(source).contains { $0.trimmingCharacters(in: .whitespaces) == text }
    }

    // MARK: - S-6507: the arrival path hops to the main actor

    /// The radio's handler is `@concurrent`, so the arrival path runs off the
    /// main actor. `revision` is `@Published` on a `@MainActor` class, so the
    /// bump has to be hopped: a direct one is a data race the compiler would
    /// only catch as an isolation error, not as the race it is.
    func testS6507TheIncomingHandlerBumpsRevisionOnTheMainActor() throws {
        let view = try viewSource()
        let incoming = try XCTUnwrap(
            braceBody(ofLineContaining: "bridge.onIncoming", in: view),
            "the host routes the radio's arrivals (D-4, S-6507)"
        )

        XCTAssertTrue(
            incoming.contains("await MainActor.run { self.revision += 1 }"),
            "the arrival handler runs off the main actor, so its bump is hopped "
                + "through `MainActor.run` (D-4)"
        )
        XCTAssertFalse(
            hasStatement("self.revision += 1", in: incoming),
            "a bare bump inside the arrival handler is the race the hop removes, "
                + "and a `contains` match would accept it: the statement form is "
                + "what is looked for (D-4)"
        )
    }

    // MARK: - S-6507: the reachability path is not hopped

    /// The reachability handler already runs on the main actor — the bridge
    /// delivers it there — so its bump stays direct. Hopping it would be a
    /// second change the scenario does not ask for, and it would hide the
    /// difference the arrival hop is for.
    func testS6507TheReachabilityHandlerStillBumpsRevisionDirectly() throws {
        let view = try viewSource()
        let reachability = try XCTUnwrap(
            braceBody(ofLineContaining: "bridge.onReachabilityChange", in: view),
            "the host maps the radio's reachability answers (D-8, S-6507)"
        )

        XCTAssertTrue(
            hasStatement("self.revision += 1", in: reachability),
            "the reachability handler runs on the main actor, so its bump stays "
                + "direct (S-6507)"
        )
    }
}
