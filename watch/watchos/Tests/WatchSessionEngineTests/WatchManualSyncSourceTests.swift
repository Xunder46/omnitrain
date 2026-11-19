//
//  WatchManualSyncSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for plan 62's wrist half: the Sync button asks for everything,
//  and the automatic catch-ups keep asking for what changed.
//
//  Plan: `docs/plans/2026-10-23-62-incremental-wrist-sync-plan/2026-10-23-62-incremental-wrist-sync-plan.md`,
//  scenario S-9220 (decision D-5).
//
//  The app target has no test target and SwiftUI does not exist on macOS where
//  `swift test` runs, so the button cannot be tapped here. What can be held
//  off-device is what drift would break: the exact statements in the view and
//  in the orchestrator, read with every comment line blanked out so a sentence
//  of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchManualSyncSourceTests: XCTestCase {

    // MARK: - S-9220 the Sync button omits `since`; the catch-ups keep theirs

    func testS9220TheSyncButtonAsksForEverythingAndTheCatchUpsKeepAskingForWhatChanged() throws {
        let view = try appSource("ContentView.swift")

        let requestSync = try functionSlice(from: "func requestSync() async {", in: view)
        XCTAssertTrue(
            requestSync.contains("await orchestrator.sync(reconnect: false)"),
            "S-9220 the Sync button asks for everything: no `since` reaches the phone"
        )
        XCTAssertFalse(
            requestSync.contains("paths.syncedAt"),
            "S-9220 the Sync button no longer says what the wrist already holds"
        )

        let catchUp = try functionSlice(from: "func catchUpOnActivation() {", in: view)
        XCTAssertTrue(
            catchUp.contains("await orchestrator.catchUp(reachable: reachable)"),
            "S-9220 activation still catches up through the orchestrator's gate"
        )
        XCTAssertFalse(
            catchUp.contains("reconnect: false"),
            "S-9220 the automatic catch-up is not the everything-request; only the Sync button is"
        )

        let orchestrator = try engineSource("WatchSyncOrchestrator.swift")
        let catchUpBody = try functionSlice(
            from: "public func catchUp(reachable: Bool) async {",
            in: orchestrator
        )
        XCTAssertTrue(
            catchUpBody.contains("await sync(reconnect: paths.syncedAt != nil)"),
            "S-9220 the catch-up keeps asking for what changed since the wrist's held stamp"
        )
        let syncBody = try functionSlice(
            from: "public func sync(reconnect: Bool = false) async {",
            in: orchestrator
        )
        XCTAssertTrue(
            syncBody.contains("since: reconnect ? paths.syncedAt : nil,"),
            "S-9220 the request still carries the wrist's stamp when it is a reconnect"
        )
    }

    // MARK: - Helpers (the source guard, as WatchHostHopSourceTests reads the app target)

    /// A file of the app target, read from the repository root, with every
    /// comment-only line blanked out (the line count is kept).
    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        return strippingCommentLines(text)
    }

    /// A file of the watch package's engine module, read from the repository
    /// root, with every comment-only line blanked out (the line count is kept).
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

    /// The text from the first occurrence of `signature` up to (not including)
    /// the next line that is exactly `    }` (four spaces, brace) — the
    /// function's own closing brace, its body sliced whole.
    private func functionSlice(from signature: String, in source: String) throws -> String {
        guard let start = source.range(of: signature) else {
            XCTFail("S-9220 \(signature) not found in the source")
            return ""
        }
        guard let end = source.range(of: "\n    }\n", range: start.upperBound..<source.endIndex) else {
            XCTFail("S-9220 the closing brace after \(signature) not found in the source")
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
