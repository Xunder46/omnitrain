//
//  WatchWorkoutSummaryWiringSourceTests.swift
//  WatchSessionEngineTests
//
//  The wrist's Skip button and end-of-workout summary, wired into the app
//  shell (plan 66a, S-9620).
//
//  Plan:
//  `docs/plans/2026-10-23-66a-wrist-workout-summary-and-skip-plan/2026-10-23-66a-wrist-workout-summary-and-skip-plan.md`.
//
//  The views compile only under xcodebuild, so what `swift test` holds is the
//  text the wiring is made of, read with the comment lines stripped the way
//  `WatchPhoneProblemWiringSourceTests` does.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchWorkoutSummaryWiringSourceTests: XCTestCase {

    // MARK: - Source readers (copied from WatchPhoneProblemWiringSourceTests.swift)

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

    // MARK: - S-9620: the wiring is the text the two targets are made of

    func testS9620TheShellShowsTheSummaryBetweenTheQuestionAndTheRest() throws {
        let content = try appSource("ContentView.swift")

        XCTAssertTrue(
            content.contains("} else if let pending = host.summary.pending {"),
            "S-9620 the wearer stops seeing the workout-done summary: the shell never shows it"
        )
        XCTAssertTrue(
            content.contains(
                "WatchWorkoutSummaryView(summary: pending, onDone: { host.summary.dismissPending() })"
            ),
            "S-9620 the wearer stops seeing Done take the summary away and return to the start screen"
        )
        let note = try XCTUnwrap(
            content.range(of: "self.summary.note(self.engine.session)"),
            "S-9620 the wearer stops seeing the summary built at all: the host never tells the state about a session change"
        )
        let refresh = try XCTUnwrap(
            content.range(of: "await self.workout.refresh(self.engine.session)"),
            "S-9620 the wearer stops seeing an average heart rate: the sensors stop before the summary reads the readings"
        )
        XCTAssertLessThan(
            note.lowerBound, refresh.lowerBound,
            "S-9620 the wearer stops seeing an average heart rate: the summary must read the "
                + "readings before the workout refresh stops the sensors"
        )
        XCTAssertTrue(
            content.contains("let summary = WatchWorkoutSummaryState(engine: engine)"),
            "S-9620 the wearer stops seeing the summary: the host never builds its state"
        )
        XCTAssertTrue(
            content.contains("self.summary = summary"),
            "S-9620 the wearer stops seeing the summary: the host builds the state and drops it"
        )
        XCTAssertTrue(
            content.contains("summary.objectWillChange"),
            "S-9620 the wearer stops seeing the summary appear or give way: the shell never re-reads when the state changes"
        )
    }

    func testS9620TheQuestionCarriesTheSkipUnderConfirm() throws {
        let view = try engineSource("WatchEffortRatingView.swift")

        XCTAssertTrue(
            view.contains("Button(WatchEffortRatingCopy.skipLabel) { state.skipPrompt() }"),
            "S-9620 the wearer stops seeing a way out of the question that records nothing"
        )
        // The body only: the `confirmButton` and `skipButton` declarations
        // live below it, so an order check over the whole file would stay
        // green with the Skip gone from the stack.
        let bodyStart = try XCTUnwrap(
            view.range(of: "public var body: some View {"),
            "S-9620 the rating view has no body to wire"
        )
        let bodyEnd = try XCTUnwrap(
            view.range(of: "private func scaleButton"),
            "S-9620 the rating view's body has no end to slice at"
        )
        let body = String(view[bodyStart.lowerBound..<bodyEnd.lowerBound])
        XCTAssertNotNil(
            body.range(of: "confirmButton\\s+skipButton", options: .regularExpression),
            "S-9620 the wrist's effort question no longer shows a Skip under Confirm"
        )
    }

    func testS9620TheSummaryViewRendersTheRowsAndDone() throws {
        let view = try engineSource("WatchWorkoutSummaryView.swift")

        XCTAssertTrue(
            view.contains("WatchWorkoutSummaryCopy.title"),
            "S-9620 the wearer stops seeing the summary's title line"
        )
        XCTAssertTrue(
            view.contains("Text(row.label)"),
            "S-9620 the wearer stops seeing what each row is (Time, Sets or Efforts, Avg HR)"
        )
        XCTAssertTrue(
            view.contains("Text(row.value)"),
            "S-9620 the wearer stops seeing each row's number"
        )
        XCTAssertTrue(
            view.contains("Button(WatchWorkoutSummaryCopy.done, action: onDone)"),
            "S-9620 the wearer stops seeing the Done button that leaves the summary"
        )
    }
}
