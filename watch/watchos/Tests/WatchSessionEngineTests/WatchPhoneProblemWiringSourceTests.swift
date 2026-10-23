//
//  WatchPhoneProblemWiringSourceTests.swift
//  WatchSessionEngineTests
//
//  The Start screen's three new lines: a vanished routine, a Sync that got no
//  answer, and a phone link that cannot come up at all (plan 60, S-9004).
//
//  Plan:
//  `docs/plans/2026-10-23-60-failed-start-and-phone-link-notices-plan/2026-10-23-60-failed-start-and-phone-link-notices-plan.md`.
//
//  The views compile only under xcodebuild, so what `swift test` holds is the
//  text the wiring is made of, read with the comment lines stripped the way
//  `WatchCancelEmptyFreeWorkoutTests` does.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchPhoneProblemWiringSourceTests: XCTestCase {

    // MARK: - Source readers (copied from WatchCancelEmptyFreeWorkoutTests.swift)

    private func appSource(_ name: String) throws -> String {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("ios/OmniTrain Watch App/\(name)")
        return strippingCommentLines(try String(contentsOf: url, encoding: .utf8))
    }

    private func engineSource(_ name: String) throws -> String {
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

    // MARK: - S-9004: the wiring is the text the three targets are made of

    func testS9004TheStartSurfaceSaysWhenARoutineVanished() throws {
        let start = try engineSource("WatchStartView.swift")

        XCTAssertTrue(
            start.contains("routineNotice = WatchStartSurfaceCopy.routineMissingLabel"),
            "S-9004 the user stops seeing a silent tap on a routine that is no longer on the watch"
        )
        XCTAssertTrue(
            start.contains("} catch {"),
            "S-9004 the user stops seeing a failed start swallowed without a word"
        )
        XCTAssertFalse(
            start.contains("try? await paths.startFromRoutine"),
            "S-9004 the user stops seeing the old `try?` that hid the failure"
        )
        XCTAssertEqual(
            start.components(separatedBy: "routineNotice = nil").count - 1,
            2,
            "S-9004 the user stops seeing a stale vanished-routine line: it clears on a new tap "
                + "and on any surface re-read"
        )
        XCTAssertTrue(
            start.contains(".onChange(of: revision)"),
            "S-9004 the user stops seeing the vanished-routine line after a Sync brings the routines"
        )
        XCTAssertTrue(
            start.contains("if let routineNotice {"),
            "S-9004 the user stops seeing nothing said when a tapped routine is gone"
        )
        XCTAssertTrue(
            start.contains("Text(routineNotice)"),
            "S-9004 the user stops seeing the vanished-routine line rendered, even while the "
                + "`if let` survives: the body renders an empty Text instead"
        )
        XCTAssertTrue(
            start.contains("if let phoneProblem {"),
            "S-9004 the user stops seeing nothing said when the phone link has a problem"
        )
        XCTAssertTrue(
            start.contains("Text(phoneProblem)"),
            "S-9004 the user stops seeing the phone-link problem line rendered, even while the "
                + "`if let` survives: the body renders an empty Text instead"
        )
        XCTAssertTrue(
            start.contains("self.phoneProblem = phoneProblem"),
            "S-9004 the user stops seeing the phone-link problem line: the init no longer stores "
                + "what the host passed, so the surface always renders nil"
        )
        XCTAssertTrue(
            start.contains("phoneProblem: String? = nil"),
            "S-9004 the user stops seeing the phone-link problem line: the parameter vanishes and "
                + "every caller compiles against a default of nil"
        )
        let statusHint = try XCTUnwrap(
            start.range(of: "WatchPhoneStatusHint(status: phoneStatus)"),
            "S-9004 the user stops seeing the phone status line the problem line sits under"
        )
        let problemLine = try XCTUnwrap(
            start.range(of: "Text(phoneProblem)"),
            "S-9004 the user stops seeing the phone-link problem line rendered"
        )
        XCTAssertLessThan(
            statusHint.lowerBound, problemLine.lowerBound,
            "S-9004 the user stops seeing the problem line sit under the phone status line: it "
                + "moves above it or off the surface"
        )
        XCTAssertTrue(
            start.contains("Button(Self.syncLabel, action: onRequestSync)"),
            "S-9004 the Sync button keeps its exact text, so the user stops seeing nothing change there"
        )
    }

    func testS9004TheHostRaisesTheNoAnswerAndLinkLines() throws {
        let content = try appSource("ContentView.swift")

        XCTAssertTrue(
            content.contains("manualSyncPending = true"),
            "S-9004 the user stops seeing a no-answer line raised by an automatic catch-up"
        )
        XCTAssertTrue(
            content.contains("self.syncNoAnswer = self.syncProgress.endedWithoutAnswer(at: Date())"),
            "S-9004 the user stops seeing a manual Sync that got no answer end without a word"
        )
        XCTAssertTrue(
            content.contains("self.syncNoAnswer = false"),
            "S-9004 the user stops seeing a stale no-answer line once the phone replies"
        )
        XCTAssertTrue(
            content.contains("session.onLinkProblem"),
            "S-9004 the user stops seeing a radio that cannot come up go unreported"
        )
        XCTAssertTrue(
            content.contains("phoneProblem: host.phoneProblem"),
            "S-9004 the user stops seeing the Start screen without the phone-link line"
        )

        let phoneProblem = try XCTUnwrap(
            content.range(of: "var phoneProblem"),
            "S-9004 the host carries the one phone-link problem"
        )
        let afterPhoneProblem = content[phoneProblem.upperBound...]
        let linkUnavailable = try XCTUnwrap(
            afterPhoneProblem.range(of: "linkUnavailable"),
            "S-9004 the link that cannot start is one of the lines"
        )
        let syncNoAnswer = try XCTUnwrap(
            afterPhoneProblem.range(of: "syncNoAnswer"),
            "S-9004 the no-answer Sync is the other line"
        )
        XCTAssertLessThan(
            linkUnavailable.lowerBound,
            syncNoAnswer.lowerBound,
            "S-9004 the user stops seeing a no-answer line outrank the link that cannot start at all"
        )
    }

    func testS9004TheRadioReportsWhenItCannotComeUp() throws {
        let connectivity = try appSource("OmniTrainWatchConnectivity.swift")

        XCTAssertTrue(
            connectivity.contains("func onLinkProblem("),
            "S-9004 the user stops seeing a link problem the host was never told about"
        )
        XCTAssertTrue(
            connectivity.contains("linkProblem = true"),
            "S-9004 the user stops seeing an unsupported radio look like a working one"
        )
        XCTAssertTrue(
            connectivity.contains("reportLinkProblem(true)"),
            "S-9004 the user stops seeing a failed activation stay silent"
        )
        XCTAssertTrue(
            connectivity.contains("reportLinkProblem(false)"),
            "S-9004 the user stops seeing a link problem outlive a successful activation"
        )
    }
}
