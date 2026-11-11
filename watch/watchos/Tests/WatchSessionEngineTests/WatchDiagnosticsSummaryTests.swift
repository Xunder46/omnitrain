//
//  WatchDiagnosticsSummaryTests.swift
//  WatchSessionEngineTests
//
//  Plan 142 — scenario S-14212 for `WatchDiagnosticsSummary`: the headline
//  sentences and the newest-40 lines built from a fixed event list, read in
//  a fixed time zone (GMT) so no test depends on the runner's clock or zone.
//

import XCTest

@testable import WatchSessionEngine

final class WatchDiagnosticsSummaryTests: XCTestCase {
    private let gmt = TimeZone(secondsFromGMT: 0)!

    /// A fixed instant in the test's own time zone, built from components:
    /// 2026-07-13 at `hour:minute:second` GMT.
    private func at(hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 13
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = gmt
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func summary(_ events: [WatchDiagnosticsEvent]) -> WatchDiagnosticsSummary {
        WatchDiagnosticsSummary(events: events, timeZone: gmt)
    }

    /// S-14212 no launch anywhere: no start has been recorded.
    func testS14212NoLaunchMeansNoStartRecordedYet() {
        let made = summary([
            WatchDiagnosticsEvent(at: at(hour: 6), kind: "scene", detail: "active"),
        ])
        XCTAssertEqual(made.headline, ["No start recorded yet."], "S-14212 the empty headline")
    }

    /// S-14212 a first launch alone: the start time and nothing before it.
    func testS14212AFirstLaunchAloneSaysStartedAndFirstRunRecorded() {
        let made = summary([
            WatchDiagnosticsEvent(at: at(hour: 6), kind: "launch"),
        ])
        XCTAssertEqual(
            made.headline, ["Started 06:00", "First run recorded."], "S-14212 the first-run headline"
        )
    }

    /// S-14212 a previous run that ended in the background, then a launch the
    /// system restarted: the restart is named and the background is last seen.
    func testS14212ARestartedRunNamesTheBackgroundSceneFromThePreviousRun() {
        let made = summary([
            WatchDiagnosticsEvent(at: at(hour: 5, minute: 52), kind: "scene", detail: "background"),
            WatchDiagnosticsEvent(at: at(hour: 6, minute: 4), kind: "launch"),
            WatchDiagnosticsEvent(at: at(hour: 6, minute: 5), kind: "recovery_relaunch"),
        ])
        XCTAssertEqual(
            made.headline,
            [
                "Started 06:04 — restarted by the system",
                "Before that: last seen in the background at 05:52",
            ],
            "S-14212 the restarted headline"
        )
    }

    /// S-14212 the same shape with an active scene and with a workout_begin:
    /// the phrase follows the kind and detail.
    func testS14212ThePhrasesFollowTheKindAndDetailOfThePreviousRun() {
        let active = summary([
            WatchDiagnosticsEvent(at: at(hour: 5, minute: 52), kind: "scene", detail: "active"),
            WatchDiagnosticsEvent(at: at(hour: 6, minute: 4), kind: "launch"),
        ])
        XCTAssertEqual(
            active.headline,
            ["Started 06:04", "Before that: last seen on screen at 05:52"],
            "S-14212 the active scene reads on screen"
        )

        let workout = summary([
            WatchDiagnosticsEvent(at: at(hour: 5, minute: 52), kind: "workout_begin"),
            WatchDiagnosticsEvent(at: at(hour: 6, minute: 4), kind: "launch"),
        ])
        XCTAssertEqual(
            workout.headline,
            ["Started 06:04", "Before that: last seen workout_begin at 05:52"],
            "S-14212 an unnamed kind reads as itself"
        )
    }

    /// S-14212 sixty events: exactly 40 lines, newest first.
    func testS14212SixtyEventsGiveTheNewestFortyLinesNewestFirst() {
        var events = [WatchDiagnosticsEvent(at: at(hour: 6), kind: "launch", detail: "previous=none")]
        for index in 1...59 {
            events.append(WatchDiagnosticsEvent(
                at: at(hour: 6, minute: 0, second: index), kind: "frame_sent", detail: "d\(index)"
            ))
        }
        let made = summary(events)

        XCTAssertEqual(made.lines.count, 40, "S-14212 exactly the newest forty")
        XCTAssertEqual(
            made.lines.first, "06:00:59 frame_sent d59", "S-14212 the first line is the newest event"
        )
        XCTAssertEqual(
            made.lines.last, "06:00:20 frame_sent d20", "S-14212 the last line is the oldest kept"
        )
        XCTAssertEqual(
            made.headline, ["Started 06:00", "First run recorded."],
            "S-14212 the launch is kept out of the cut lines"
        )
    }

    /// S-14212 an inactive previous scene reads as dimmed.
    func testS14212AnInactivePreviousSceneReadsAsDimmed() {
        let made = summary([
            WatchDiagnosticsEvent(at: at(hour: 5, minute: 52), kind: "scene", detail: "inactive"),
            WatchDiagnosticsEvent(at: at(hour: 6, minute: 4), kind: "launch"),
        ])
        XCTAssertEqual(
            made.headline,
            ["Started 06:04", "Before that: last seen dimmed at 05:52"],
            "S-14212 the inactive scene reads dimmed"
        )
    }

    /// S-14212 a line names the time, kind, detail and the session's first
    /// four characters.
    func testS14212ALineNamesTimeKindDetailAndSessionPrefix() {
        let made = summary([
            WatchDiagnosticsEvent(
                at: at(hour: 6, minute: 4, second: 11),
                kind: "frame_sent", session: "s-watch-1", detail: "live"
            ),
        ])
        XCTAssertEqual(
            made.lines, ["06:04:11 frame_sent live s:s-wa"], "S-14212 the whole line shape"
        )
    }
}
