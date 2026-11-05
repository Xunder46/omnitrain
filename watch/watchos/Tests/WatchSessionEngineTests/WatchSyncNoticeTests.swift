//
//  WatchSyncNoticeTests.swift
//  WatchSessionEngineTests
//
//  S-7701 to S-7707 of
//  `docs/plans/2026-10-21-51d-wrist-sync-waiting-notice-plan/2026-10-21-51d-wrist-sync-waiting-notice-plan.md`
//  — the wrist's "waiting for your phone" line: always when the radio says the
//  phone is out of reach, otherwise only once the oldest unacknowledged entry
//  has waited the grace, the count through the engine, and the source guards
//  that keep both views and the shell host wired to it.
//

import XCTest

@testable import WatchSessionEngine

final class WatchSyncNoticeTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ n: Int, age: TimeInterval, kind: String = "set") -> WatchObservationRecord {
        WatchObservationRecord(
            recordId: "r-\(n)",
            sessionId: "s-sync",
            recordedAt: now.addingTimeInterval(-age),
            kind: kind,
            payload: ["entryId": "e-\(n)", "eventId": "e-\(n)", "kind": kind]
        )
    }

    // MARK: - S-7701 no pending -> nil for every reachability

    func testS7701NoPendingIsNilForEveryReachability() {
        for reachability in [WatchPhoneReachability.unreachable, .reachable, .unknown] {
            XCTAssertNil(
                deriveSyncNotice(pending: [], reachability: reachability, now: now),
                "S-7701 nothing waiting says nothing (\(reachability))"
            )
        }
    }

    // MARK: - S-7702 unreachable says it at once, with the count

    func testS7702UnreachableSaysTheCountOfFreshEntries() {
        XCTAssertEqual(
            deriveSyncNotice(pending: [record(1, age: 5)], reachability: .unreachable, now: now),
            "1 entry waiting for your phone",
            "S-7702 one entry, seconds old, out of reach"
        )
        XCTAssertEqual(
            deriveSyncNotice(
                pending: [record(1, age: 5), record(2, age: 6), record(3, age: 7)],
                reachability: .unreachable,
                now: now
            ),
            "3 entries waiting for your phone",
            "S-7702 three entries, seconds old, out of reach"
        )
    }

    // MARK: - S-7703 reachable waits for the grace, counts all pending

    func testS7703ReachableWaitsForTheGraceAndCountsAllPending() {
        XCTAssertNil(
            deriveSyncNotice(
                pending: [record(1, age: 30), record(2, age: 10)],
                reachability: .reachable,
                now: now
            ),
            "S-7703 both entries younger than the grace: no flicker"
        )
        XCTAssertEqual(
            deriveSyncNotice(
                pending: [record(1, age: 120), record(2, age: 10)],
                reachability: .reachable,
                now: now
            ),
            "2 entries waiting for your phone",
            "S-7703 the count is all pending, not only the old one"
        )
    }

    // MARK: - S-7704 unknown gets the same grace as reachable

    func testS7704UnknownGetsTheSameGraceAsReachable() {
        XCTAssertNil(
            deriveSyncNotice(pending: [record(1, age: 10)], reachability: .unknown, now: now),
            "S-7704 a young entry on a not-yet-known phone says nothing"
        )
        XCTAssertEqual(
            deriveSyncNotice(pending: [record(1, age: 200)], reachability: .unknown, now: now),
            "1 entry waiting for your phone",
            "S-7704 an old entry on a not-yet-known phone is named"
        )
    }

    // MARK: - S-7705 the exact boundary shows

    func testS7705TheExactGraceBoundaryShows() {
        XCTAssertEqual(
            deriveSyncNotice(pending: [record(1, age: 90)], reachability: .reachable, now: now),
            "1 entry waiting for your phone",
            "S-7705 exactly the grace shows"
        )
        XCTAssertNil(
            deriveSyncNotice(pending: [record(1, age: 89)], reachability: .reachable, now: now),
            "S-7705 a second short of the grace does not"
        )
        XCTAssertEqual(
            WatchSyncNoticeCopy.graceSeconds,
            90,
            "S-7705 the grace is 90 seconds"
        )
    }

    // MARK: - S-7706 through the engine: the count and the receipt

    @MainActor
    func testS7706TheEngineCountsUnconfirmedAndAReceiptRemovesOne() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(
            modality: nil,
            exercises: [exercise("sx-bench")]
        )

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)
        let first = try await surface.log()
        XCTAssertFalse(first.entryId.isEmpty, "S-7706 the logged set carries its entryId")
        XCTAssertEqual(
            engine.unconfirmedObservations.count,
            1,
            "S-7706 one logged set is one unconfirmed observation"
        )

        harness.clock.advance(120)
        let second = try await surface.log()
        XCTAssertEqual(
            engine.unconfirmedObservations.count,
            3,
            "S-7706 the second log stores its set and the rest window that follows it"
        )
        XCTAssertEqual(
            deriveSyncNotice(
                pending: engine.unconfirmedObservations,
                reachability: .unreachable,
                // .unreachable ignores age
                now: Date()
            ),
            "2 entries waiting for your phone",
            "S-7706 the notice counts the two sets, not the rest window"
        )

        let confirmed = await engine.confirmObservations([first.entryId])
        XCTAssertEqual(confirmed, [first.entryId], "S-7706 the receipt names the entry")
        XCTAssertEqual(
            engine.unconfirmedObservations.count,
            2,
            "S-7706 the receipt removes its entry from the count"
        )
        XCTAssertEqual(
            engine.unconfirmedObservations.first { $0.kind != WatchObservationKind.rest }?.entryId,
            second.entryId,
            "S-7706 the remaining non-rest record is the second set"
        )
    }

    // MARK: - S-7708 rest windows are not counted nor aged

    func testS7708RestWindowsAreNotCounted() {
        XCTAssertNil(
            deriveSyncNotice(
                pending: [record(1, age: 5, kind: "rest")],
                reachability: .unreachable,
                now: now
            ),
            "S-7708 a pending list holding only a rest window says nothing"
        )
        XCTAssertEqual(
            deriveSyncNotice(
                pending: [record(1, age: 5), record(2, age: 5, kind: "rest")],
                reachability: .unreachable,
                now: now
            ),
            "1 entry waiting for your phone",
            "S-7708 the rest window is not counted among the waiting entries"
        )
        XCTAssertNil(
            deriveSyncNotice(
                pending: [record(1, age: 200, kind: "rest"), record(2, age: 10)],
                reachability: .reachable,
                now: now
            ),
            "S-7708 an old rest window alone must not age the notice"
        )
    }

    // MARK: - S-7707 source guards: the views and the shell host

    private func engineSource(_ name: String) throws -> String {
        try source(
            Fixtures.repositoryRoot
                .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
        )
    }

    private func shellSource(_ relativePath: String) throws -> String {
        try source(Fixtures.repositoryRoot.appendingPathComponent(relativePath))
    }

    private func source(_ url: URL) throws -> String {
        strippingCommentLines(try String(contentsOf: url, encoding: .utf8))
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

    func testS7707TheShellHostPassesTheNoticeToBothViews() throws {
        let contentView = try shellSource("ios/OmniTrain Watch App/ContentView.swift")

        let sites = contentView.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("syncNotice: host.syncNotice") }
        XCTAssertEqual(
            sites.count,
            2,
            "S-7707 the host passes the notice to the start view and the menu sheet: \(sites)"
        )
        XCTAssertTrue(
            contentView.contains("deriveSyncNotice("),
            "S-7707 the host derives the notice"
        )
    }

    func testS7707BothViewsDeclareAndShowTheNotice() throws {
        for name in ["WatchStartView.swift", "WatchMenuView.swift"] {
            let source = try engineSource(name)
            XCTAssertTrue(
                source.contains("syncNotice: String? = nil"),
                "S-7707 \(name) declares the notice with a default"
            )
            XCTAssertTrue(
                source.contains("if let syncNotice"),
                "S-7707 \(name) shows the notice"
            )
        }
    }
}
