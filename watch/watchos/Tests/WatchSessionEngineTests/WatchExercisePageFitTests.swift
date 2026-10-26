//
//  WatchExercisePageFitTests.swift
//  WatchSessionEngineTests
//
//  Plan 70 — the wrist's exercise page fits a 40 mm watch: the heart-rate
//  refusal leaves the exercise pages (S-10001), the header clears the menu
//  button and the notices read on one line (S-10003, S-10004), the summary
//  says why there is no heart rate (S-10005), and the wiring is the text the
//  targets are made of (S-10006).
//
//  Plan: `docs/plans/2026-10-24-70-wrist-run-page-fits-40mm-plan/
//  2026-10-24-70-wrist-run-page-fits-40mm-plan.md`.
//
//  The views compile only under xcodebuild, so the view guards read the
//  sources with their comment lines stripped, the way
//  `WatchHealthAccessWiringSourceTests` does.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchExercisePageFitTests: XCTestCase {

    private var harness: Harness!
    private var source: FakeSensorSource!

    override func setUp() {
        super.setUp()
        harness = Harness()
        source = FakeSensorSource()
    }

    override func tearDown() {
        source.close()
        super.tearDown()
    }

    private func makeRecorder(for engine: WatchSessionEngine) -> WatchSensorRecorder {
        WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)
    }

    private func session(
        _ engine: WatchSessionEngine,
        modality: String?,
        exercises: [[String: Any]]
    ) async -> WatchSessionRecord {
        await engine.createSession(modality: modality, exercises: exercises)
    }

    private func liftSlot(_ slot: String) -> [String: Any] {
        [
            "sessionExerciseId": slot,
            "exerciseId": "ex-\(slot)",
            "name": slot,
            "capabilities": ["reps", "sets", "load"],
        ]
    }

    private func runSlot(_ slot: String) -> [String: Any] {
        [
            "sessionExerciseId": slot,
            "exerciseId": "ex-\(slot)",
            "name": slot,
            "capabilities": ["time", "distance"],
        ]
    }

    // MARK: - Source readers (copied from WatchHealthAccessWiringSourceTests.swift)

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

    // MARK: - S-10001 heart-rate refusal no longer produces an exercise-page notice

    func testS10001ADeniedHeartRateAloneAddsNoNotice() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting", exercises: [liftSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.heartRateGrant = .denied
        await recorder.start(live)
        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )

        XCTAssertEqual(
            surface.sensorNotices,
            [],
            "S-10001(a) a refused heart rate is said on the Start screen and the summary, not on an exercise page"
        )
    }

    func testS10001BothRefusalsOnADistanceExerciseReadTheDistanceLineAlone() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "cardio_endurance", exercises: [runSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.heartRateGrant = .denied
        source.locationGrant = .denied
        await recorder.start(live)
        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )

        XCTAssertEqual(
            surface.sensorNotices,
            [WatchSensorNoticeCopy.noDistance],
            "S-10001(b) on a distance exercise the distance line is the only one"
        )
    }

    func testS10001BothRefusalsOnALiftAddNoNotice() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "resistance_lifting", exercises: [liftSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.heartRateGrant = .denied
        source.locationGrant = .denied
        await recorder.start(live)
        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )

        XCTAssertEqual(
            surface.sensorNotices,
            [],
            "S-10001(c) a lift covers neither distance nor a notice"
        )
    }

    func testS10001ADeniedLocationOnADistanceExerciseStillReadsTheDistanceLine() async throws {
        let engine = await harness.runningEngine()
        let live = await session(engine, modality: "cardio_endurance", exercises: [runSlot("sx-1")])
        let recorder = makeRecorder(for: engine)

        source.heartRateGrant = .granted
        source.locationGrant = .denied
        await recorder.start(live)
        let surface = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            sensors: recorder
        )

        XCTAssertEqual(
            surface.sensorNotices,
            [WatchSensorNoticeCopy.noDistance],
            "S-10001(d) the distance line survives the heart-rate line's departure"
        )
    }

    // MARK: - S-10003 the header clears the menu button

    func testS10003TheHeaderRowStopsShortOfTheMenuButton() throws {
        let source = try engineSource("WatchLoggingView.swift")

        XCTAssertTrue(
            source.contains("private static let menuClearance = 40.0"),
            "S-10003 the wearer stops seeing the counter sit under the menu button: the row has no width to stop short of it"
        )

        let rowStart = try XCTUnwrap(
            source.range(of: "HStack(spacing: 4) {"),
            "S-10003 the header has no name row to pad"
        )
        let trailing = try XCTUnwrap(
            source.range(of: ".padding(.trailing, Self.menuClearance)"),
            "S-10003 the wearer stops seeing the counter sit under the menu button: the row never stops short of it"
        )
        let top = try XCTUnwrap(
            source.range(of: ".padding(.top, Self.titleClearance)"),
            "S-10003 the header's name row lost its top clearance"
        )

        XCTAssertGreaterThan(
            trailing.lowerBound, rowStart.lowerBound,
            "S-10003 the trailing clearance is not on the header's name row"
        )
        XCTAssertLessThan(
            trailing.lowerBound, top.lowerBound,
            "S-10003 the trailing clearance must come before the top clearance on the name row"
        )
    }

    // MARK: - S-10004 the notices read on one line

    func testS10004TheNoticeRowsHoldOneLine() throws {
        let source = try engineSource("WatchLoggingView.swift")

        let forEachStart = try XCTUnwrap(
            source.range(of: "ForEach(model.sensorNotices, id: \\.self) { notice in"),
            "S-10004 the logging surface stays silent about a sensor that cannot read"
        )
        // Slice from the ForEach to the end of the header's rows: the
        // `.padding(.top, 2)` after the VStack closes them.
        let blockEnd = try XCTUnwrap(
            source.range(of: ".padding(.top, 2)", options: .backwards),
            "S-10004 the header's rows have no end to slice at"
        )
        let block = String(source[forEachStart.lowerBound..<blockEnd.lowerBound])

        XCTAssertTrue(
            block.contains("Text(notice)"),
            "S-10004 the notice rows render an empty Text, so the user watches an empty field without knowing why"
        )
        XCTAssertTrue(
            block.contains(".lineLimit(1)"),
            "S-10004 the wearer stops seeing the notice fit: it still wraps to two lines"
        )
        XCTAssertNil(
            block.range(of: ".lineLimit(2)"),
            "S-10004 the wearer stops seeing the notice fit: a two-line limit is still in the block"
        )
    }

    // MARK: - S-10005 the summary's line, one test per arm

    private func summary(averageBpm: Int?) -> WatchWorkoutSummary {
        WatchWorkoutSummary(
            sessionId: "s-1",
            startedAt: testInstant(),
            endedAt: testInstant().addingTimeInterval(600),
            effortCount: 3,
            allSets: true,
            averageBpm: averageBpm
        )
    }

    func testS10005NoAverageAndHealthOffReadsTheHeartRateLine() {
        XCTAssertEqual(
            summary(averageBpm: nil).heartRateNote(healthOff: true),
            WatchSensorNoticeCopy.noHeartRate,
            "S-10005 the wearer stops learning why no heart rate is on the summary"
        )
    }

    func testS10005NoAverageAndHealthAllowedReadsNothing() {
        XCTAssertNil(
            summary(averageBpm: nil).heartRateNote(healthOff: false),
            "S-10005 the wearer with access allowed is told access is off"
        )
    }

    func testS10005AnAverageAndHealthOffReadsNothing() {
        XCTAssertNil(
            summary(averageBpm: 137).heartRateNote(healthOff: true),
            "S-10005 the wearer with a recorded average is told there was none"
        )
    }

    func testS10005AnAverageAndHealthAllowedReadsNothing() {
        XCTAssertNil(
            summary(averageBpm: 137).heartRateNote(healthOff: false),
            "S-10005 the wearer with an average and access allowed is told otherwise"
        )
    }

    // MARK: - S-10006 the summary view and the shell carry the line

    func testS10006TheSummaryViewCarriesTheHeartRateLine() throws {
        let view = try engineSource("WatchWorkoutSummaryView.swift")

        XCTAssertTrue(
            view.contains("public let healthOff: Bool"),
            "S-10006 the summary view is never told whether Health access is off, so the line cannot be conditional"
        )
        XCTAssertTrue(
            view.contains("self.healthOff = healthOff"),
            "S-10006 the init no longer stores the access state, so the view always reads a default"
        )
        XCTAssertTrue(
            view.contains("summary.heartRateNote(healthOff: healthOff)"),
            "S-10006 the view never asks the summary for the line, so it never shows"
        )
        XCTAssertTrue(
            view.contains("Text(note)"),
            "S-10006 the line is asked for but never rendered, so the wearer sees nothing"
        )
    }

    func testS10006TheShellPassesTheAccessStateToTheSummary() throws {
        let content = try appSource("ContentView.swift")

        let healthOff = try XCTUnwrap(
            content.range(of: "healthOff: host.healthAccess == .off"),
            "S-10006 the shell never tells the summary whether Health access is off, so the line cannot be conditional"
        )
        let summaryCall = try XCTUnwrap(
            content.range(of: "WatchWorkoutSummaryView(summary: pending"),
            "S-10006 the shell never shows the summary at all"
        )
        XCTAssertGreaterThan(
            healthOff.lowerBound, summaryCall.lowerBound,
            "S-10006 the access state is passed somewhere other than the summary's call"
        )
    }
}
