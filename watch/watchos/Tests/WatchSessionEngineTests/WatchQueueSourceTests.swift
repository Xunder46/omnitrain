//
//  WatchQueueSourceTests.swift
//  WatchSessionEngineTests
//
//  Source guards for the wrist app's radio: the OS queue behind a refused
//  durable frame, and the queued transfer the phone sends back.
//
//  Plan: `docs/plans/2026-10-21-47b-wrist-queues-durable-frames-plan/2026-10-21-47b-wrist-queues-durable-frames-plan.md`,
//  scenario S-6708 (decision D-3); and
//  `docs/plans/2026-10-24-69-watch-queues-workout-state-plan/2026-10-24-69-watch-queues-workout-state-plan.md`,
//  scenario S-9915 (decisions D-8 and D-10).
//
//  The app target has no test target and `WCSession` does not exist on macOS
//  where `swift test` runs, so the radio's platform half cannot be executed.
//  What can be held off-device is what drift would break: the queue path, the
//  dedupe by `messageId`, the durable-frame rule taken from the package, and the
//  delegate callback that receives a queued transfer. On-device delivery is the
//  owner's check.
//
//  Every guard reads a file's text with its comment lines removed, so a sentence
//  of prose can neither satisfy a guard nor trip one.
//

import Foundation
import XCTest

final class WatchQueueSourceTests: XCTestCase {

    // MARK: - Reading the app target

    /// The radio, read from the repository root, with every comment-only line
    /// blanked out (the line count is kept).
    private func source() throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift")
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

    /// How many times `needle` occurs in `source`.
    private func occurrences(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    /// The brace-balanced body of `func <name>(`, from its opening brace to its
    /// closing one, or nil when the function is not there.
    private func functionBody(named name: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("func \(name)(") }) else {
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
            if started && depth == 0 { break }
        }
        return started ? body.joined(separator: "\n") : nil
    }

    // MARK: - The queue

    /// The seam's new member exists and hands the frame to the OS queue.
    func testS6708TheRadioQueuesThroughOneTransferCall() throws {
        let source = try source()

        XCTAssertTrue(source.contains("func queue("))
        XCTAssertTrue(source.contains("transferUserInfo("))
    }

    /// A transfer still outstanding for the same `messageId` is not queued
    /// again: a sync that re-sends an owed set must not pile up copies.
    func testS6708AnOutstandingTransferForTheSameMessageIsNotQueuedAgain() throws {
        let source = try source()

        XCTAssertTrue(source.contains("outstandingUserInfoTransfers"))
        XCTAssertTrue(source.contains("\"messageId\""))
    }

    // MARK: - Receiving a queued transfer

    /// The phone's queued receipt arrives through the delegate callback, not
    /// only through `didReceiveMessage`.
    func testS6708AQueuedTransferArrivesThroughTheDelegate() throws {
        XCTAssertTrue(try source().contains("didReceiveUserInfo"))
    }

    // MARK: - Which frames may be queued

    /// The durable rule is the package's, so the app target cannot drift from
    /// what `swift test` holds on macOS.
    func testS6708TheDurableRuleIsThePackageOne() throws {
        XCTAssertTrue(try source().contains("WatchConnectivityBridge.isDurable("))
    }

    /// One queue path and no second: a refused send is queued in one place.
    func testS6708ThereIsExactlyOneTransferCall() throws {
        XCTAssertEqual(occurrences(of: "transferUserInfo(", in: try source()), 1)
    }

    // MARK: - The package rule (plan 69, S-9915)

    /// The late refusal goes through the package's replacement rule, not the
    /// radio's own queue: only the newest copy of a durable frame waits.
    func testS9915TheLateRefusalUsesThePackagesRule() throws {
        let source = try source()

        XCTAssertTrue(source.contains("WatchConnectivityBridge.queueNewest(frame, on: self)"))
        XCTAssertFalse(source.contains("try self.queue(frame)"))

        let send = try XCTUnwrap(functionBody(named: "send", in: source))
        let sendMessageLine = send.range(of: "sendMessage(")
        let queueNewestLine = send.range(of: "queueNewest")
        XCTAssertNotNil(sendMessageLine)
        XCTAssertNotNil(queueNewestLine)
        if let sendMessageLine, let queueNewestLine {
            XCTAssertLessThan(sendMessageLine.lowerBound, queueNewestLine.lowerBound)
        }

        XCTAssertEqual(occurrences(of: "transferUserInfo(", in: source), 1)
    }

    /// The radio lists and cancels what the OS holds, but only when the session
    /// is up: a session that is not activated lists nothing and cancels 0.
    func testS9915TheRadioListsAndCancelsOnlyWhenActivated() throws {
        let source = try source()

        XCTAssertTrue(source.contains("func outstandingTransfers("))
        XCTAssertTrue(source.contains("func cancelTransfers(messageIds:"))
        XCTAssertTrue(source.contains("outstandingUserInfoTransfers"))
        XCTAssertTrue(source.contains(".cancel()"))

        let list = try XCTUnwrap(functionBody(named: "outstandingTransfers", in: source))
        XCTAssertTrue(list.contains("activationState == .activated"))

        let cancel = try XCTUnwrap(functionBody(named: "cancelTransfers", in: source))
        XCTAssertTrue(cancel.contains("activationState == .activated"))
        XCTAssertTrue(cancel.contains("transfer.userInfo[\"messageId\"] as? String"))
    }
}
