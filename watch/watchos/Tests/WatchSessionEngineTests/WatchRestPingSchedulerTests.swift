//
//  WatchRestPingSchedulerTests.swift
//  WatchSessionEngineTests
//
//  Plan 61, P1:
//  `docs/plans/2026-10-23-61-wrist-down-rest-pings-plan/2026-10-23-61-wrist-down-rest-pings-plan.md`,
//  scenarios S-9101..S-9108.
//
//  The scheduler owns the ping now (D-1): the host arms it, it keeps its own
//  clock and wakes just after each boundary of the persisted rest row. The
//  harness is the shared one (`Harness`, `TestClock`, `exercise` in
//  `WatchSessionEngineTests.swift`), driving a real `WatchLoggingState` whose
//  clock the test advances; the sleeper is injected, so no test waits on the
//  real clock.
//

import XCTest

@testable import WatchSessionEngine

@MainActor
final class WatchRestPingSchedulerTests: XCTestCase {

    /// A session with a logged set, so a rest is open at `t0`.
    private func loggedRestFixture() async throws -> (Harness, WatchLoggingState) {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let state = WatchLoggingState(engine: engine, clock: harness.clock.call)
        try await state.log()
        return (harness, state)
    }

    // MARK: - S-9101 the nextWait table

    func testS9101NextWaitTable() throws {
        XCTAssertEqual(
            try XCTUnwrap(WatchRestPingScheduler.nextWait(elapsedMs: 0, interval: 30)),
            30.05, accuracy: 0.0001,
            "S-9101: a rest just opened waits to just after its first boundary"
        )
        XCTAssertEqual(
            try XCTUnwrap(WatchRestPingScheduler.nextWait(elapsedMs: 12345, interval: 30)),
            17.705, accuracy: 0.0001,
            "S-9101: mid-interval waits for what is left of it plus the 50 ms"
        )
        XCTAssertEqual(
            try XCTUnwrap(WatchRestPingScheduler.nextWait(elapsedMs: 29990, interval: 30)),
            0.06, accuracy: 0.0001,
            "S-9101: just before the boundary wakes just after it"
        )
        XCTAssertEqual(
            try XCTUnwrap(WatchRestPingScheduler.nextWait(elapsedMs: 30000, interval: 30)),
            30.05, accuracy: 0.0001,
            "S-9101: exactly on a boundary waits a full interval"
        )
        XCTAssertEqual(
            try XCTUnwrap(WatchRestPingScheduler.nextWait(elapsedMs: 59999, interval: 30)),
            0.051, accuracy: 0.0001,
            "S-9101: one millisecond before the second boundary wakes just after it"
        )
        XCTAssertNil(
            WatchRestPingScheduler.nextWait(elapsedMs: 0, interval: 0),
            "S-9101: the interval Off waits for nothing"
        )
        XCTAssertNil(
            WatchRestPingScheduler.nextWait(elapsedMs: 0, interval: -5),
            "S-9101: a negative interval is Off"
        )
        XCTAssertNil(
            WatchRestPingScheduler.nextWait(elapsedMs: -1, interval: 30),
            "S-9101: a negative elapsed is no rest to wait on"
        )
    }

    // MARK: - S-9102 step() around the first boundary

    func testS9102StepBeforeTheBoundaryPingsNothing() async throws {
        let (harness, state) = try await loggedRestFixture()
        let intervalSeconds = 30
        let haptics = RecordingHaptics()
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { intervalSeconds },
            haptics: haptics,
            sleep: { _ in }
        )

        harness.clock.advance(29.9)
        XCTAssertEqual(
            try XCTUnwrap(scheduler.step()),
            0.15, accuracy: 0.0011,
            "S-9102: before the boundary the wait is what is left of the interval plus the 50 ms (the engine's Date-to-ms truncation can cost one millisecond)"
        )
        XCTAssertEqual(haptics.restPings, 0, "S-9102: no ping before the boundary")
        XCTAssertLessThanOrEqual(
            abs((state.restElapsedMilliseconds() ?? 0) - 29900), 1,
            "the millisecond elapsed is what the wait is built from"
        )
        XCTAssertNotNil(state.restStartedAt, "the open rest carries its start")
    }

    func testS9102StepAtTheBoundaryPingsOnce() async throws {
        let (harness, state) = try await loggedRestFixture()
        let intervalSeconds = 30
        let haptics = RecordingHaptics()
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { intervalSeconds },
            haptics: haptics,
            sleep: { _ in }
        )

        harness.clock.advance(30.05)
        XCTAssertEqual(
            try XCTUnwrap(scheduler.step()),
            30.0, accuracy: 0.0011,
            "S-9102: just past the boundary the wait is the next full interval (the engine's Date-to-ms truncation can cost one millisecond)"
        )
        XCTAssertEqual(haptics.restPings, 1, "S-9102: the boundary is owed one ping")
    }

    func testS9102StepAgainAfterTheBoundaryPingsNothingMore() async throws {
        let (harness, state) = try await loggedRestFixture()
        let intervalSeconds = 30
        let haptics = RecordingHaptics()
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { intervalSeconds },
            haptics: haptics,
            sleep: { _ in }
        )

        harness.clock.advance(30.05)
        _ = scheduler.step()
        harness.clock.advance(0.01)
        _ = scheduler.step()
        XCTAssertEqual(
            haptics.restPings, 1,
            "S-9102: one ping per boundary — the tick just after it is not owed another"
        )
    }

    // MARK: - S-9103 a gap is caught up with one ping

    func testS9103StepAfterAGapCatchesUpWithOnePing() async throws {
        let (harness, state) = try await loggedRestFixture()
        let intervalSeconds = 30
        let haptics = RecordingHaptics()
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { intervalSeconds },
            haptics: haptics,
            sleep: { _ in }
        )

        harness.clock.advance(95)
        XCTAssertEqual(
            try XCTUnwrap(scheduler.step()),
            25.05, accuracy: 0.0001,
            "S-9103: after the gap the wait runs to just after the next boundary"
        )
        XCTAssertEqual(
            haptics.restPings, 1,
            "S-9103: the boundaries the gap crossed are caught up with one tap, not three"
        )
    }

    // MARK: - S-9104 the interval Off, and one arriving mid-rest

    func testS9104IntervalOffPingsNothingAndWaitsNothing() async throws {
        let (harness, state) = try await loggedRestFixture()
        let intervalSeconds = 0
        let haptics = RecordingHaptics()
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { intervalSeconds },
            haptics: haptics,
            sleep: { _ in }
        )

        harness.clock.advance(31)
        XCTAssertNil(scheduler.step(), "S-9104: Off, there is no boundary to wait for")
        XCTAssertEqual(haptics.restPings, 0, "S-9104: Off pings nothing")
    }

    func testS9104IntervalArrivingMidRestSyncsOnce() async throws {
        let (harness, state) = try await loggedRestFixture()
        var intervalSeconds = 0
        let haptics = RecordingHaptics()
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { intervalSeconds },
            haptics: haptics,
            sleep: { _ in }
        )

        harness.clock.advance(31)
        XCTAssertNil(scheduler.step(), "S-9104: the ticks before the interval arrives are Off")
        intervalSeconds = 30
        XCTAssertEqual(
            try XCTUnwrap(scheduler.step()),
            29.05, accuracy: 0.0001,
            "S-9104: the sync lands the wait on the next boundary of the new interval"
        )
        XCTAssertEqual(haptics.restPings, 1, "S-9104: a mid-rest sync is heard once")
    }

    // MARK: - S-9105 the wait loop

    func testS9105TheLoopPingsEachBoundaryUntilTheRestEnds() async throws {
        let (harness, state) = try await loggedRestFixture()
        let intervalSeconds = 30
        let haptics = RecordingHaptics()
        var waits: [TimeInterval] = []
        var sleeperCalls = 0
        let clock = harness.clock
        let resting = state
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { intervalSeconds },
            haptics: haptics,
            sleep: { wait in
                waits.append(wait)
                sleeperCalls += 1
                clock.advance(wait)
                if sleeperCalls == 3 {
                    await resting.endRest()
                }
            }
        )

        scheduler.arm()
        await scheduler.finished()

        XCTAssertEqual(haptics.restPings, 2, "S-9105: the loop pings at 30 s and 60 s, then the rest ends")
        XCTAssertEqual(sleeperCalls, 3, "S-9105: the third sleep ends the rest and the loop stops")
        XCTAssertEqual(
            try XCTUnwrap(waits.first),
            30.05, accuracy: 0.0001,
            "S-9105: the first wait runs to just after the first boundary"
        )
        XCTAssertEqual(
            try XCTUnwrap(waits.dropFirst().first),
            30.0, accuracy: 0.0011,
            "S-9105: the second wait is the full interval, woken 50 ms past the boundary (the engine's Date-to-ms truncation can cost one millisecond)"
        )
    }

    // MARK: - S-9106 disarm, and arming twice

    func testS9106DisarmStopsTheLoopBeforeTheSleeperReturns() async throws {
        let (_, state) = try await loggedRestFixture()
        let intervalSeconds = 30
        let haptics = RecordingHaptics()
        var sleeperCalls = 0
        var wokeTest: CheckedContinuation<Void, Never>?
        var releaseSleeper: CheckedContinuation<Void, Never>?
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { intervalSeconds },
            haptics: haptics,
            sleep: { _ in
                sleeperCalls += 1
                wokeTest?.resume()
                wokeTest = nil
                await withCheckedContinuation { releaseSleeper = $0 }
            }
        )

        scheduler.arm()
        // The test suspends here until the sleeper says it is inside, so the
        // disarm below lands while the loop is mid-sleep.
        await withCheckedContinuation { wokeTest = $0 }
        XCTAssertEqual(sleeperCalls, 1, "the loop reached its first sleep")
        XCTAssertNotNil(releaseSleeper, "the sleeper is suspended on the test's gate")

        scheduler.disarm()
        releaseSleeper?.resume()
        await scheduler.finished()
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(sleeperCalls, 1, "S-9106: a disarmed loop sleeps no more")
        XCTAssertEqual(haptics.restPings, 0, "S-9106: a disarmed loop pings no more")
    }

    func testS9106ArmingTwicePingsAsOftenAsArmingOnce() async throws {
        let (harness, state) = try await loggedRestFixture()
        let intervalSeconds = 30
        let haptics = RecordingHaptics()
        var sleeperCalls = 0
        let clock = harness.clock
        let resting = state
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { intervalSeconds },
            haptics: haptics,
            sleep: { wait in
                sleeperCalls += 1
                clock.advance(wait)
                if sleeperCalls == 3 {
                    await resting.endRest()
                }
            }
        )

        scheduler.arm()
        scheduler.arm()
        await scheduler.finished()

        XCTAssertEqual(
            haptics.restPings, 2,
            "S-9106: the first loop is cancelled, so two arms ping exactly as often as one"
        )
        XCTAssertEqual(sleeperCalls, 3, "S-9106: only the second loop's sleeps run")
    }

    // MARK: - S-9107 no rest open

    func testS9107NoRestOpenStepsToNilAndPingsNothing() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let state = WatchLoggingState(engine: engine, clock: harness.clock.call)
        let haptics = RecordingHaptics()
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { 30 },
            haptics: haptics,
            sleep: { _ in }
        )

        harness.clock.advance(95)
        XCTAssertNil(scheduler.step(), "S-9107: a session with no timer has no wait")
        XCTAssertEqual(haptics.restPings, 0, "S-9107: no rest open, no ping")

        try await state.log()
        harness.clock.advance(31)
        await state.endRest()
        harness.clock.advance(31)
        XCTAssertNil(scheduler.step(), "S-9107: a stopped rest row is never evaluated")
        XCTAssertEqual(haptics.restPings, 0, "S-9107: a stopped rest pings nothing")
        XCTAssertNil(state.restStartedAt, "S-9107: a stopped rest has no start to anchor on")
    }

    // MARK: - S-9108 the dimmed rest clock

    func testS9108DimmedRestClockShowsWholeMinutes() {
        XCTAssertEqual(WatchLoggingState.dimmedRestClock(seconds: 0), "0 min", "S-9108")
        XCTAssertEqual(WatchLoggingState.dimmedRestClock(seconds: 59), "0 min", "S-9108")
        XCTAssertEqual(WatchLoggingState.dimmedRestClock(seconds: 60), "1 min", "S-9108")
        XCTAssertEqual(WatchLoggingState.dimmedRestClock(seconds: 185), "3 min", "S-9108")
        XCTAssertEqual(WatchLoggingState.dimmedRestClock(seconds: 3599), "59 min", "S-9108")
        XCTAssertEqual(WatchLoggingState.dimmedRestClock(seconds: -4), "0 min", "S-9108")
        XCTAssertEqual(
            WatchLoggingState.dimmedRestClock(seconds: -75), "0 min",
            "S-9108: a negative elapsed clamps to 0, not to a negative minute count"
        )
        XCTAssertEqual(
            WatchLoggingState.dimmedRestClock(seconds: 3725), "62 min",
            "S-9108: past the hour the whole minutes keep counting up"
        )
    }

    // MARK: - S-9110 a clock that moves between the rule's read and the wait's

    func testS9110AClockThatMovesBetweenReadsStillTapsTheBoundary() async throws {
        // The old step() could skip the boundary when its two clock reads straddled it: the rule saw the whole second before the boundary and the wait slept a full interval past it.
        let t0 = testInstant()
        var ticks = 0
        let clock: () -> Date = {
            ticks += 1
            return t0.addingTimeInterval(0.2 * Double(ticks))
        }
        let engine = WatchSessionEngine(
            store: InMemoryWatchSessionStore(),
            onEmit: { _ in },
            validator: Harness.validator(),
            clock: clock
        )
        await engine.restore()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
        let state = WatchLoggingState(engine: engine, clock: clock)
        try await state.log()

        // Spin the clock so the loop's first read lands in [29.8, 30.0): a
        // second read 0.2 s later then falls past the 30 s boundary.
        let startedAt = try XCTUnwrap(state.restStartedAt)
        while t0.addingTimeInterval(0.2 * Double(ticks)).timeIntervalSince(startedAt) < 29.6 {
            _ = clock()
        }

        let haptics = RecordingHaptics()
        let scheduler = WatchRestPingScheduler(
            state: state,
            interval: { 30 },
            haptics: haptics,
            sleep: { _ in }
        )

        var steps = 0
        while steps < 200 {
            steps += 1
            guard let wait = scheduler.step() else { break }
            if haptics.restPings == 1 { break }
            // The host's sleep, on this clock: spin it forward at least the
            // wait, one 0.2 s tick per call.
            for _ in 0..<Int(ceil(wait / 0.2)) { _ = clock() }
        }

        XCTAssertLessThan(steps, 200, "S-9110: the first tap arrives inside the loop")
        XCTAssertEqual(haptics.restPings, 1, "S-9110: exactly one tap by the first boundary")
        XCTAssertLessThan(
            state.restElapsedMilliseconds() ?? 31_000, 31_000,
            "S-9110: the tap happened at the 30 s boundary, not a full interval later"
        )
    }
}
