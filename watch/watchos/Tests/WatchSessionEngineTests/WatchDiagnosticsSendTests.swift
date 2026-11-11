//
//  WatchDiagnosticsSendTests.swift
//  WatchSessionEngineTests
//
//  Plan 144 — the scenarios S-14401..S-14403 for sending the watch's
//  diagnostics log to the phone: the log's `snapshotFile`, the send outcome's
//  words, and the source guards for the app target's send path.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchDiagnosticsSendTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-diagnostics-send-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        super.tearDown()
    }

    private var fileURL: URL {
        directory.appendingPathComponent("watch-diagnostics.jsonl")
    }

    private func lines(of url: URL) -> [String] {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: - S-14401 the snapshot

    /// S-14401 a log with 3 events: the snapshot lands in the target directory
    /// under the clock's stamped name, carries the log file's lines, and a new
    /// log over a directory holding it as `watch-diagnostics.jsonl` reads the
    /// same 3 events.
    func testS14401TheSnapshotCarriesTheLogLinesUnderTheStampedName() throws {
        let out = directory.appendingPathComponent("out", isDirectory: true)
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        log.note("launch", detail: "previous=none")
        log.note("scene", detail: "background")
        log.note("frame_sent", session: "s-1", detail: "live")

        let snapshot = log.snapshotFile(into: out)

        XCTAssertNotNil(snapshot, "S-14401 the snapshot exists")
        XCTAssertEqual(
            snapshot?.deletingLastPathComponent().standardizedFileURL.path,
            out.standardizedFileURL.path,
            "S-14401 the snapshot is inside the target directory"
        )
        XCTAssertEqual(
            snapshot?.lastPathComponent, "watch-diagnostics-20260713T060000Z.jsonl",
            "S-14401 the name carries the clock's UTC stamp"
        )
        XCTAssertEqual(
            lines(of: snapshot!), lines(of: fileURL),
            "S-14401 the snapshot's lines equal the log file's lines"
        )

        let received = directory.appendingPathComponent("received", isDirectory: true)
        try FileManager.default.createDirectory(at: received, withIntermediateDirectories: true)
        try Data(contentsOf: snapshot!).write(
            to: received.appendingPathComponent("watch-diagnostics.jsonl")
        )
        let second = WatchDiagnosticsLog(
            directory: received, clock: TestClock(testInstant()).call
        )
        XCTAssertEqual(
            second.events().map(\.kind), ["launch", "scene", "frame_sent"],
            "S-14401 the phone-side log reads the same 3 events"
        )
    }

    /// S-14401 a log with no events: nothing is offered.
    func testS14401AnEmptyLogSnapshotsNothing() {
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)

        XCTAssertNil(
            log.snapshotFile(into: directory.appendingPathComponent("out", isDirectory: true)),
            "S-14401 an empty log offers no file"
        )
    }

    /// S-14401 a target that cannot be created (a read-only parent directory:
    /// on this platform a regular file in the way is replaced by
    /// `createDirectory`, so the read-only parent is the one that fails):
    /// the snapshot answers nil and the log is untouched.
    func testS14401ATargetThatCannotBeCreatedAnswersNil() throws {
        let readonly = directory.appendingPathComponent("readonly", isDirectory: true)
        try FileManager.default.createDirectory(at: readonly, withIntermediateDirectories: true)
        let log = WatchDiagnosticsLog(directory: directory, clock: TestClock(testInstant()).call)
        log.note("launch", detail: "previous=none")

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: readonly.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: readonly.path
            )
        }

        XCTAssertNil(
            log.snapshotFile(into: readonly.appendingPathComponent("out", isDirectory: true)),
            "S-14401 an impossible target answers nil"
        )
        XCTAssertEqual(
            lines(of: fileURL).count, 1,
            "S-14401 the failed copy left the log as it was"
        )
    }

    // MARK: - S-14402 the outcome's words

    /// S-14402 the four outcomes' messages, exactly as the screen shows them.
    func testS14402TheFourOutcomesSayTheWordsTheScreenShows() {
        XCTAssertEqual(
            WatchDiagnosticsSendOutcome.sent.message,
            "Sent. The phone has it when it next wakes.",
            "S-14402 the sent words"
        )
        XCTAssertEqual(
            WatchDiagnosticsSendOutcome.phoneAppMissing.message,
            "Install the OmniTrain app on the phone.",
            "S-14402 the missing-app words"
        )
        XCTAssertEqual(
            WatchDiagnosticsSendOutcome.notReady.message,
            "Phone link not ready.",
            "S-14402 the not-ready words"
        )
        XCTAssertEqual(
            WatchDiagnosticsSendOutcome.failed.message,
            "Could not send.",
            "S-14402 the failed words"
        )
    }

    // MARK: - S-14403 source guards

    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        return strippingCommentLines(try String(contentsOf: url, encoding: .utf8))
    }

    private func packageSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/watchos/Sources/WatchSessionEngine/\(name)")
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

    /// S-14403 the radio answers what the link can do and hands the file to the
    /// system's transfer, never the frame path.
    func testS14403TheRadioSendsTheFileThroughTheSystemsTransfer() throws {
        let radio = try appSource("OmniTrainWatchConnectivity.swift")

        XCTAssertTrue(
            radio.contains("guard session.isCompanionAppInstalled else { return .phoneAppMissing }"),
            "S-14403 a missing companion app is named"
        )
        XCTAssertTrue(
            radio.contains("guard session.activationState == .activated else { return .notReady }"),
            "S-14403 an unactivated session is not ready"
        )
        XCTAssertTrue(
            radio.contains("session.transferFile(url, metadata: [\"kind\": \"diagnostics_log\"])"),
            "S-14403 the file goes through the system's transfer, not the frame path"
        )
    }

    /// S-14403 the host keeps the radio and the sheet hands the snapshot to it.
    func testS14403TheHostWiresTheScreenToTheRadio() throws {
        let view = try appSource("ContentView.swift")

        XCTAssertTrue(
            view.contains("onSend: { url in host.sendDiagnostics(url) }"),
            "S-14403 the sheet hands the snapshot to the host's send"
        )
        XCTAssertTrue(
            view.contains("func sendDiagnostics(_ url: URL) -> WatchDiagnosticsSendOutcome { radio.sendDiagnostics(url) }"),
            "S-14403 the host keeps the radio and forwards the send"
        )
    }

    /// S-14403 the Diagnostics screen offers the send only when the app asks.
    func testS14403TheScreenOffersTheSend() throws {
        let view = try packageSource("WatchDiagnosticsView.swift")

        XCTAssertTrue(
            view.contains("Button(\"Send to phone\") {"),
            "S-14403 the send button is there"
        )
        XCTAssertTrue(
            view.contains("if let onSend {"),
            "S-14403 the button is there only when the app asks for it"
        )
        XCTAssertTrue(
            view.contains("return \"Nothing to send.\""),
            "S-14403 nothing to send says so"
        )
    }
}
