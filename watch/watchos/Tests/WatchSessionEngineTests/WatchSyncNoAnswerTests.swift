//
//  WatchSyncNoAnswerTests.swift
//  WatchSessionEngineTests
//
//  S-9001 to S-9003 of
//  `docs/plans/2026-10-23-60-failed-start-and-phone-link-notices-plan/2026-10-23-60-failed-start-and-phone-link-notices-plan.md`
//  — the wrist's "the phone never answered" derivation, the three Start-screen
//  sentences, and the unknown-routine start path. The window is driven by an
//  injected clock, so every boundary is asserted exactly rather than waited for.
//

import XCTest

@testable import WatchSessionEngine

final class WatchSyncNoAnswerTests: XCTestCase {

    private func makeClock() -> TestClock {
        TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    }

    // MARK: - Fixture readers (copied from WatchCancelEmptyFreeWorkoutTests.swift,
    // whose helpers are private to that file)

    private enum StartFixtureError: Error {
        case malformed(String)
    }

    private func startContract() throws -> [String: Any] {
        let url = Fixtures.repositoryRoot
            .appendingPathComponent("watch/contract/watch_start_paths_contract.json")
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StartFixtureError.malformed("watch_start_paths_contract.json")
        }
        return object
    }

    private func object(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else {
            throw StartFixtureError.malformed("expected an object, found \(String(describing: value))")
        }
        return value
    }

    private func firstMessage() throws -> [String: Any] {
        let fallback = try object(try startContract()["fallback"])
        return try object(fallback["routinesDown"])
    }

    // MARK: - S-9001: a sync that began, is over, and never got its routines

    func testS9001aNeverBeganIsFalse() {
        let clock = makeClock()
        let progress = WatchSyncProgress(clock: clock.call)

        XCTAssertFalse(
            progress.endedWithoutAnswer(at: clock.call()),
            "S-9001a a sync that never began cannot have ended without an answer"
        )
    }

    func testS9001bFiveSecondsInIsStillRunningSoFalse() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin(at: clock.call())

        clock.advance(5)
        XCTAssertFalse(
            progress.endedWithoutAnswer(at: clock.call()),
            "S-9001b five seconds in the sync is still running, not ended"
        )
    }

    func testS9001cCapWithNoArrivalsIsTrue() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin(at: clock.call())

        clock.advance(20)
        XCTAssertTrue(
            progress.endedWithoutAnswer(at: clock.call()),
            "S-9001c only the cap ends a sync that got no routines_down, so twenty seconds of silence is the phone never answering"
        )
    }

    func testS9001dRoutinesArrivedIsAnsweredSoFalse() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin(at: clock.call())

        clock.advance(1)
        progress.noteArrival(type: "routines_down", at: clock.call())

        clock.advance(3)
        XCTAssertFalse(
            progress.endedWithoutAnswer(at: clock.call()),
            "S-9001d the routines the sync asked for arrived, so it was answered"
        )
    }

    func testS9001eOnlyPreferencesArrivedIsStillUnanswered() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin(at: clock.call())

        clock.advance(1)
        progress.noteArrival(type: "preferences_down", at: clock.call())

        clock.advance(19)
        XCTAssertTrue(
            progress.endedWithoutAnswer(at: clock.call()),
            "S-9001e an arrival that is not the routines does not answer the sync: at the cap it is still ended without an answer"
        )
    }

    func testS9001fNewBeginAfterCapIsRunningAgainSoFalseThenTrueAtItsCap() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin(at: clock.call())
        clock.advance(20)
        XCTAssertTrue(progress.endedWithoutAnswer(at: clock.call()), "S-9001f precondition: the first sync ended unanswered")

        progress.begin(at: clock.call())
        XCTAssertFalse(
            progress.endedWithoutAnswer(at: clock.call()),
            "S-9001f a fresh begin forgets the earlier window: the new sync is running at once"
        )

        clock.advance(20)
        XCTAssertTrue(
            progress.endedWithoutAnswer(at: clock.call()),
            "S-9001f the new sync runs its own window and ends unanswered at its cap"
        )
    }

    func testS9001gArrivalAfterTheCapDoesNotTurnTrueIntoFalse() {
        let clock = makeClock()
        var progress = WatchSyncProgress(clock: clock.call)
        progress.begin(at: clock.call())
        clock.advance(20)
        XCTAssertTrue(progress.endedWithoutAnswer(at: clock.call()), "S-9001g precondition: ended unanswered at the cap")

        progress.noteArrival(type: "routines_down", at: clock.call())
        XCTAssertTrue(
            progress.endedWithoutAnswer(at: clock.call()),
            "S-9001g noteArrival refuses arrivals once the sync is over, so a late reply cannot flip it"
        )
    }

    // MARK: - S-9002: the three Start-screen sentences

    func testS9002RoutineMissingLabelIsExactlyThePlannedSentence() {
        XCTAssertEqual(
            WatchStartSurfaceCopy.routineMissingLabel,
            "That routine is no longer on the watch. Tap Sync.",
            "S-9002 the vanished-routine sentence is exactly the planned text"
        )
    }

    func testS9002SyncNoAnswerLabelIsExactlyThePlannedSentence() {
        XCTAssertEqual(
            WatchStartSurfaceCopy.syncNoAnswerLabel,
            "No answer from your phone. Open OmniTrain on it and try again.",
            "S-9002 the no-answer sentence is exactly the planned text"
        )
    }

    func testS9002LinkUnavailableLabelIsExactlyThePlannedSentence() {
        XCTAssertEqual(
            WatchStartSurfaceCopy.linkUnavailableLabel,
            "Phone link unavailable. Restart the watch app.",
            "S-9002 the link-unavailable sentence is exactly the planned text"
        )
    }

    // MARK: - S-9003: starting a routine the watch no longer holds

    func testS9003UnknownRoutineThrowsAndLeavesTheSessionUnchanged() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        _ = try await harness.receive(try firstMessage())

        let before = harness.engine.session?.sessionId
        var thrown: Error?
        do {
            _ = try await harness.paths.startFromRoutine("not-there")
        } catch {
            thrown = error
        }
        let error = try XCTUnwrap(thrown, "S-9003 starting a routine the watch does not hold must throw")
        guard case WatchStartPathError.unknownRoutine(let routineId) = error else {
            XCTFail("S-9003 expected unknownRoutine, got \(error)")
            return
        }
        XCTAssertEqual(routineId, "not-there", "S-9003 the error names the routine that was not there")
        XCTAssertEqual(
            harness.engine.session?.sessionId,
            before,
            "S-9003 the failed start leaves the session exactly as it was (nil before is fine)"
        )
    }
}
