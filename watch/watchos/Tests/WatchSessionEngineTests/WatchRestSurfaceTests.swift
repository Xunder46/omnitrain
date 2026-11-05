//
//  WatchRestSurfaceTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of the wrist's rest surface. Plan:
//  `docs/plans/2026-10-08-18b-watch-rest-count-up-plan.md`, scenarios S-161,
//  S-162 and S-163 (D-160, D-161, D-162), proved the same way the Flutter twin
//  proves them in `test/watch_rest_surface_test.dart`.
//
//  A rest is a count-up with no length, and its elapsed is derived from the
//  persisted row at the instant it is read: every case below moves a clock,
//  never a ticker, which is what makes the screen-off case the same case as the
//  on-screen one.
//

import XCTest

@testable import WatchSessionEngine

final class WatchRestSurfaceTests: XCTestCase {

    private func restingState(
        _ harness: Harness,
        engine: WatchSessionEngine
    ) -> WatchLoggingState {
        WatchLoggingState(engine: engine, clock: harness.clock.call)
    }

    /// A running session on a set-kind effort, and the logging state over it.
    private func runningBench(_ harness: Harness) async -> WatchSessionEngine {
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        return engine
    }

    // MARK: - S-161 a rest counts up and survives the screen turning off

    func testS161TheRestElapsedCountsUpAndSurvivesARelaunch() async throws {
        let harness = Harness()
        let engine = await runningBench(harness)
        let state = restingState(harness, engine: engine)

        try await state.log()
        XCTAssertTrue(state.isResting, "logging a set starts the rest surface")
        XCTAssertEqual(state.restElapsedSeconds(), 0, "the rest starts at 0:00")

        harness.clock.advance(7)
        XCTAssertEqual(
            state.restElapsedSeconds(),
            7,
            "seven seconds later the rest shows 0:07 — a count-up, not a countdown"
        )

        // Four minutes with the screen off, then a relaunch over the same store:
        // nothing ticked in memory, so the stored row is the whole account of it.
        harness.clock.advance(233)
        let relaunched = await harness.runningEngine(harness.newEngine())
        let restored = restingState(harness, engine: relaunched)

        XCTAssertTrue(restored.isResting, "the restore keeps the running rest")
        XCTAssertEqual(
            restored.restElapsedSeconds(),
            240,
            "the elapsed is derived from the row, not from a ticker that stopped"
        )
    }

    // MARK: - S-162 Next ends the rest at the tap instant

    func testS162NextEndsTheRestAtTheTapInstant() async throws {
        let harness = Harness()
        let engine = await runningBench(harness)
        let state = restingState(harness, engine: engine)

        try await state.log()
        harness.clock.advance(30)
        XCTAssertEqual(state.restElapsedSeconds(), 30)

        await state.endRest()

        XCTAssertFalse(state.isResting, "Next ends the rest, so the shell returns to logging")
        XCTAssertNil(state.restElapsedSeconds())
        let rest = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest))
        XCTAssertEqual(rest.stoppedAt, harness.clock.now, "the tap instant is the rest's end")
        XCTAssertEqual(
            activeElapsedMs(rest, now: harness.clock.now.addingTimeInterval(40)),
            30_000,
            "a stopped timer keeps the time it had reached"
        )
    }

    // MARK: - S-163 logging ends a running rest first

    func testS163LoggingEndsARunningRestFirst() async throws {
        let harness = Harness()
        let engine = await runningBench(harness)
        let state = restingState(harness, engine: engine)

        try await state.log()             // set #1, rest #1 starts
        harness.clock.advance(30)
        await state.endRest()             // Next ends rest #1

        harness.clock.advance(40)         // 10:01:10
        try await state.log()             // set #2, rest #2 starts
        let rest2StartedAt = try XCTUnwrap(
            engine.timerFor(WatchTimerKind.rest)?.startedAt
        )

        harness.clock.advance(50)         // 10:02:00
        try await state.log()             // set #3, ends rest #2 first, starts rest #3

        let stoppedRest2 = engine.timerRows(WatchTimerKind.rest)
            .first { $0.startedAt == rest2StartedAt && $0.stoppedAt != nil }
        XCTAssertEqual(
            try XCTUnwrap(stoppedRest2).stoppedAt,
            harness.clock.now,
            "logging the next set ends the running rest at that log's instant"
        )
        let newest = try XCTUnwrap(engine.timerFor(WatchTimerKind.rest))
        XCTAssertNil(newest.stoppedAt, "the follow-on rest starts and is running")
        XCTAssertNotEqual(newest.startedAt, rest2StartedAt)
        XCTAssertEqual(
            Set(engine.timerRows(WatchTimerKind.rest).map(\.startedAt)).count,
            3,
            "three rests were started, one per logged set"
        )
        XCTAssertEqual(
            engine.entries.count,
            5,
            "three sets, plus the two rests their logs ended (D-219): the third rest is still running"
        )
    }

    // MARK: - the rest surface shows nothing once the session is not live

    func testARestLeftOverFromAFinishedSessionIsNotResting() async throws {
        let harness = Harness()
        let engine = await runningBench(harness)
        let state = restingState(harness, engine: engine)

        try await state.log()
        XCTAssertTrue(state.isResting)

        _ = await engine.finishSession()

        XCTAssertFalse(state.isResting, "a finished session has no rest surface")
        XCTAssertNil(state.restElapsedSeconds())
    }

    // MARK: - S-332/S-336 the surface's own Next emits the rest it ends

    /// A phone's `timer_state` carrying a running rest the wrist did not start.
    private func phoneRestFrame(
        _ sessionId: String,
        messageId: String,
        sentAt: Date,
        startedAt: Date
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": "timer_state",
            "origin": "phone",
            "sentAt": utcIso(sentAt),
            "payload": [
                "timers": [
                    "rest": [
                        "kind": WatchTimerKind.rest,
                        "state": WatchTimerState.running,
                        "startedAt": utcIso(startedAt),
                    ],
                ],
            ],
        ]
    }

    func testS332NextEmitsTheRestItEndsExactlyOnce() async throws {
        let harness = Harness()
        let engine = await runningBench(harness)
        let state = restingState(harness, engine: engine)
        let t0 = harness.clock.now

        let logged = try await state.log()
        harness.clock.advance(70)
        await state.endRest()
        await state.endRest()

        let rests = emittedRests(harness)
        XCTAssertEqual(rests.count, 1, "Next ends one rest once")
        assertRest(
            try XCTUnwrap(rests.first),
            startedAt: t0,
            endedAt: t0.addingTimeInterval(70),
            afterEntryId: logged.entryId
        )
        XCTAssertFalse(state.isResting, "and the shell is back to logging")
    }

    func testS336NextEndsARestThePhoneStartedAndTheWristStillReportsIt() async throws {
        let harness = Harness()
        let engine = await runningBench(harness)
        let state = restingState(harness, engine: engine)
        let t0 = harness.clock.now
        let logged = try await state.log()
        let sessionId = try XCTUnwrap(engine.session?.sessionId)

        // The phone's rest, started at T0+8s, arriving at T0+10s.
        harness.clock.advance(10)
        _ = try await engine.applyMessage(
            phoneRestFrame(
                sessionId,
                messageId: "msg-phone-rest",
                sentAt: harness.clock.now,
                startedAt: t0.addingTimeInterval(8)
            )
        )
        harness.clearEmitted()

        harness.clock.advance(30)
        await state.endRest()

        let rests = emittedRests(harness)
        XCTAssertEqual(rests.count, 1, "the wrist ended it, so the wrist reports it")
        assertRest(
            try XCTUnwrap(rests.first),
            startedAt: t0.addingTimeInterval(8),
            endedAt: t0.addingTimeInterval(40),
            afterEntryId: logged.entryId
        )
    }

    // MARK: - S-8621 the rest clock is wrist-scale, like the work readout

    func testS8621TheRestClockMatchesTheWorkReadoutsScale() throws {
        let restSource = try engineSource("WatchRestView.swift")
        let restChain = try modifierChain(of: "Text(elapsed)", in: restSource)
        XCTAssertTrue(
            restChain.contains(".font(.largeTitle)"),
            "S-8621 the rest clock is .largeTitle, the work readout's scale"
        )
        XCTAssertTrue(
            restChain.contains(".monospacedDigit()"),
            "S-8621 the rest clock's digits hold their width as it counts"
        )
        XCTAssertFalse(restChain.contains("title3"), "S-8621 the old .title3 clock is gone")

        let loggingSource = try engineSource("WatchLoggingView.swift")
        let loggingChain = try modifierChain(of: "Text(readout)", in: loggingSource)
        XCTAssertTrue(
            loggingChain.contains(".font(.largeTitle)"),
            "S-8621 the work readout stays .largeTitle, so the two clocks cannot drift"
        )
    }

    // MARK: - Helpers (the source guard, as WatchRestLabelsTests reads views)

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

    /// The modifier chain that follows `call` in `source`: the lines after the
    /// line carrying `call` that start with `.` once trimmed, up to the first
    /// that does not.
    private func modifierChain(of call: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard let index = lines.firstIndex(where: { $0.contains(call) }) else {
            XCTFail("S-8621 \(call) not found in the source")
            return ""
        }
        var chain: [String] = []
        for line in lines[(index + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(".") else { break }
            chain.append(trimmed)
        }
        return chain.joined(separator: "\n")
    }
}
