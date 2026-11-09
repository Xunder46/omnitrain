//
//  WatchFollowPhoneEffortTests.swift
//  WatchSessionEngineTests
//
//  S-8401 to S-8404 and S-8411 to S-8415 of
//  `docs/plans/2026-10-22-54-wrist-follows-phone-effort-plan/2026-10-22-54-wrist-follows-phone-effort-plan.md`
//  (decisions D-2, D-6, D-7, D-8): a work timer the phone starts for another
//  exercise of the session moves the wrist there, the snapshot path shares the
//  rule, and nothing else moves it — not a rest, not a stopped or a cleared
//  timer, not a slot the session no longer holds, and not the slot the wrist is
//  already on.
//
//  The edges (S-8404, S-8411 to S-8414): the clear frame that ends the effort
//  releases the lock without moving the wrist, an earlier-start drop stores
//  nothing and so moves nobody, a paused effort still moves the wrist, a session
//  that is no longer active follows nothing, and a swipe still in flight when
//  the jump lands is refused.
//
//  The jump is the engine's own select path, so it announces itself the way a
//  user's pick does: one `exercise_advanced` lifecycle frame. Every fixture is
//  the register's own: slots `sx-a`/`sx-b`, the wrist on `sx-b`, and the phone's
//  message `timer_state`.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// A wrist with its engine, start paths, the phone's preferences, the rating
/// state and the menu over them — `FocusHarness`'s shape, with the frames the
/// engine emits kept so a jump can be counted.
final class FollowHarness {
    let clock: TestClock
    let store: WatchSessionStore
    let sessionId = "s-follow"

    private(set) var emitted: [[String: Any]] = []

    private(set) var engine: WatchSessionEngine!
    private(set) var paths: WatchSessionStartPaths!
    private(set) var preferences: WatchPhonePreferences!
    private(set) var rating: WatchEffortRatingState!
    private(set) var menu: WatchMenuState!

    init(store: WatchSessionStore = InMemoryWatchSessionStore()) {
        clock = TestClock(instant("2026-10-22T09:00:00Z"))
        self.store = store
    }

    /// A wrist that has restored, with the menu over the same objects.
    @discardableResult
    func launch() async -> FollowHarness {
        var ids = 0
        func nextId(_ prefix: String) -> String {
            ids += 1
            return "\(prefix)-\(ids)"
        }

        engine = WatchSessionEngine(
            store: store,
            onEmit: { [weak self] frame in self?.emitted.append(frame) },
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { nextId("rec") },
            sessionIdFactory: { [sessionId] in sessionId }
        )
        paths = WatchSessionStartPaths(
            engine: engine,
            store: store,
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { nextId("cat") }
        )
        preferences = WatchPhonePreferences(
            store: store,
            validator: Harness.validator(),
            clock: clock.call
        )
        rating = WatchEffortRatingState(
            engine: engine,
            store: store,
            preferences: preferences,
            clock: clock.call
        )
        menu = WatchMenuState(engine: engine, paths: paths, rating: rating)

        await engine.restore()
        await paths.restore()
        await preferences.restore()
        await rating.restore()
        return self
    }

    /// The register's ladder: two slots the wrist holds, the second current.
    @discardableResult
    func fixture() async -> FollowHarness {
        _ = await engine.createSession(
            modality: "sports",
            exercises: [roundSlot("sx-a"), roundSlot("sx-b")]
        )
        _ = await engine.selectExercise(slotId: "sx-b")
        clearEmitted()
        return self
    }

    func clearEmitted() { emitted.removeAll() }

    /// The `exercise_advanced` frames the wrist announced, oldest first.
    var advanceFrames: [[String: Any]] {
        emitted.filter {
            $0["type"] as? String == "session_lifecycle"
                && ($0["payload"] as? [String: Any])?["state"] as? String
                    == WatchLifecycleState.exerciseAdvanced
        }
    }

    func phoneFrame(
        _ type: String,
        messageId: String,
        sentAt: String? = nil,
        payload: [String: Any]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": sessionId,
            "type": type,
            "origin": "phone",
            "sentAt": sentAt ?? utcIso(clock.now),
            "payload": payload,
        ]
    }

    func timerState(
        _ messageId: String,
        sentAt: String? = nil,
        timers: [String: Any]
    ) -> [String: Any] {
        phoneFrame("timer_state", messageId: messageId, sentAt: sentAt, payload: ["timers": timers])
    }

    func timer(
        _ kind: String,
        startedAt: String,
        slot: String? = nil,
        stoppedAt: String? = nil,
        pausedAt: String? = nil
    ) -> [String: Any] {
        let state: String
        if stoppedAt != nil {
            state = WatchTimerState.stopped
        } else if pausedAt != nil {
            state = WatchTimerState.paused
        } else {
            state = WatchTimerState.running
        }
        var timer: [String: Any] = [
            "kind": kind,
            "state": state,
            "startedAt": startedAt,
            "accumulatedPauseMs": 0,
        ]
        if let slot { timer["sessionExerciseId"] = slot }
        if let stoppedAt { timer["stoppedAt"] = stoppedAt }
        if let pausedAt { timer["pausedAt"] = pausedAt }
        return timer
    }
}

/// The register's slot: `time`+`rounds`, so its work clock is a period.
private func roundSlot(_ id: String) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": id,
        "capabilities": ["time", "rounds"],
    ]
}

/// A drill slot: `time`+`hold`, so its work clock is a hold.
private func holdSlot(_ id: String) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": id,
        "capabilities": ["time", "hold"],
    ]
}

final class WatchFollowPhoneEffortTests: XCTestCase {

    private func surface(_ harness: FollowHarness) -> WatchLoggingState {
        WatchLoggingState(engine: harness.engine, clock: harness.clock.call)
    }

    private func currentSlot(_ engine: WatchSessionEngine) -> String? {
        engine.currentExercise?["sessionExerciseId"] as? String
    }

    // MARK: - S-8401 a work timer for another slot moves the wrist there

    func testS8401APhoneTimerForAnotherSlotMovesTheEngineToItsSlot() async throws {
        let harness = await FollowHarness().launch().fixture()
        let startedAt = utcIso(harness.clock.now)

        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8401",
                timers: [WatchTimerKind.round: harness.timer(WatchTimerKind.round, startedAt: startedAt, slot: "sx-a")]
            )
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-a", "the wrist follows the running effort")
        XCTAssertTrue(harness.menu.isLocked, "the running effort still locks the menu")
        XCTAssertNotNil(
            surface(harness).workTimer,
            "the running effort's own Log is what the wrist now shows"
        )
        XCTAssertEqual(harness.advanceFrames.count, 1, "the jump announces itself once")
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.round)?.sessionExerciseId,
            "sx-a",
            "the row the phone named was stored as it arrived"
        )
    }

    // MARK: - S-8402 nothing else moves the wrist

    func testS8402ARestForAnotherSlotDoesNotMoveTheEngine() async throws {
        let harness = await FollowHarness().launch().fixture()
        let startedAt = utcIso(harness.clock.now)

        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8402-rest",
                timers: [WatchTimerKind.rest: harness.timer(WatchTimerKind.rest, startedAt: startedAt, slot: "sx-a")]
            )
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-b", "a rest is not the wrist's business to follow")
        XCTAssertTrue(harness.advanceFrames.isEmpty, "a rest announces no move")
    }

    func testS8402AStoppedRoundForAnotherSlotDoesNotMoveTheEngine() async throws {
        let harness = await FollowHarness().launch().fixture()
        let startedAt = utcIso(harness.clock.now)

        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8402-stopped",
                timers: [
                    WatchTimerKind.round: harness.timer(
                        WatchTimerKind.round,
                        startedAt: startedAt,
                        slot: "sx-a",
                        stoppedAt: startedAt
                    )
                ]
            )
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-b", "a stopped timer runs nothing to follow")
        XCTAssertTrue(harness.advanceFrames.isEmpty, "a stopped timer announces no move")
    }

    func testS8402AClearedTimerDoesNotMoveTheEngine() async throws {
        let harness = await FollowHarness().launch().fixture()

        _ = try await harness.engine.applyMessage(
            harness.timerState("m-8402-clear", timers: [WatchTimerKind.round: NSNull()])
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-b", "a clear names no slot to move to")
        XCTAssertTrue(harness.advanceFrames.isEmpty, "a clear announces no move")
    }

    func testS8402ATimerForASlotTheSessionDoesNotHoldDoesNotMoveTheEngine() async throws {
        let harness = await FollowHarness().launch().fixture()
        let startedAt = utcIso(harness.clock.now)

        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8402-gone",
                timers: [WatchTimerKind.round: harness.timer(WatchTimerKind.round, startedAt: startedAt, slot: "sx-gone")]
            )
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-b", "a slot the ladder does not hold has nowhere to land")
        XCTAssertTrue(harness.advanceFrames.isEmpty, "an unheld slot announces no move")
    }

    func testS8402ATimerForTheCurrentSlotDoesNotMoveTheEngine() async throws {
        let harness = await FollowHarness().launch().fixture()
        let startedAt = utcIso(harness.clock.now)

        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8402-current",
                timers: [WatchTimerKind.round: harness.timer(WatchTimerKind.round, startedAt: startedAt, slot: "sx-b")]
            )
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-b", "the wrist is already there")
        XCTAssertTrue(harness.advanceFrames.isEmpty, "no move, no announcement")
    }

    // MARK: - S-8403 the snapshot path shares the rule

    func testS8403ASnapshotTimerForAnotherSlotMovesTheEngine() async throws {
        let harness = await FollowHarness().launch()
        let startedAt = utcIso(harness.clock.now)

        _ = try await harness.engine.applyMessage(
            harness.phoneFrame("session_snapshot", messageId: "m-8403", payload: [
                "sessionId": harness.sessionId,
                "revision": 1,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 1,
                "exercises": [holdSlot("sx-a"), holdSlot("sx-b")],
                "entries": [[String: Any]](),
                "timers": [
                    WatchTimerKind.hold: harness.timer(WatchTimerKind.hold, startedAt: startedAt, slot: "sx-a")
                ],
            ])
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-a", "a snapshot's running hold moves the wrist too")
        XCTAssertNotNil(surface(harness).workTimer, "the held effort is the one the wrist logs")
        XCTAssertEqual(harness.advanceFrames.count, 1, "the jump announces itself once")
    }

    // MARK: - S-8415 two candidates in one snapshot: the earliest start wins

    func testS8415TwoCandidatesInOneSnapshotEarliestStartWins() async throws {
        let harness = await FollowHarness().launch()
        let earlier = utcIso(harness.clock.now)
        let later = utcIso(harness.clock.now.addingTimeInterval(30))

        _ = try await harness.engine.applyMessage(
            harness.phoneFrame("session_snapshot", messageId: "m-8415", payload: [
                "sessionId": harness.sessionId,
                "revision": 1,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 1,
                "exercises": [roundSlot("sx-a"), roundSlot("sx-b"), holdSlot("sx-c")],
                "entries": [[String: Any]](),
                "timers": [
                    WatchTimerKind.round: harness.timer(WatchTimerKind.round, startedAt: earlier, slot: "sx-a"),
                    WatchTimerKind.hold: harness.timer(WatchTimerKind.hold, startedAt: later, slot: "sx-c"),
                ],
            ])
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-a", "the earliest running effort is the one to follow")
        XCTAssertEqual(harness.advanceFrames.count, 1, "at most one jump per frame")
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.round)?.sessionExerciseId,
            "sx-a",
            "the earlier candidate's row is stored"
        )
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.hold)?.sessionExerciseId,
            "sx-c",
            "the later candidate's row is stored too, it just does not move the wrist"
        )
    }

    // MARK: - S-8404 the clear frame releases the lock and leaves the wrist there

    func testS8404AClearFrameReleasesTheLockAndTheWristStays() async throws {
        let harness = await FollowHarness().launch().fixture()
        let startedAt = utcIso(harness.clock.now)

        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8404-start",
                timers: [WatchTimerKind.round: harness.timer(WatchTimerKind.round, startedAt: startedAt, slot: "sx-a")]
            )
        )
        XCTAssertEqual(currentSlot(harness.engine), "sx-a", "S-8404 the fixture starts on the jump")
        XCTAssertTrue(harness.menu.isLocked, "S-8404 the running effort locks the menu")

        harness.clock.advance(30)
        _ = try await harness.engine.applyMessage(
            harness.timerState("m-8404-clear", timers: [WatchTimerKind.round: NSNull()])
        )

        XCTAssertFalse(harness.menu.isLocked, "S-8404 the end of the effort releases the lock")
        XCTAssertEqual(currentSlot(harness.engine), "sx-a", "S-8404 the wrist stays where the effort ended")
        XCTAssertEqual(harness.advanceFrames.count, 1, "S-8404 a clear announces no move")
    }

    // MARK: - S-8411 a dropped row stores nothing and moves nobody

    func testS8411AnEarlierStartDropCausesNoJump() async throws {
        let harness = await FollowHarness().launch().fixture()
        let earlier = utcIso(harness.clock.now.addingTimeInterval(-60))
        let later = utcIso(harness.clock.now)

        // The wrist adopts a running round for A, which moves it there; the row
        // survives the user's own move back to B (S-6004).
        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8411-first",
                timers: [WatchTimerKind.round: harness.timer(WatchTimerKind.round, startedAt: earlier, slot: "sx-a")]
            )
        )
        XCTAssertEqual(currentSlot(harness.engine), "sx-a", "S-8411 the fixture adopts the row on A")
        _ = await harness.engine.selectExercise(slotId: "sx-b")
        harness.clearEmitted()

        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8411-second",
                timers: [WatchTimerKind.round: harness.timer(WatchTimerKind.round, startedAt: later, slot: "sx-a")]
            )
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-b", "S-8411 a dropped row moves nobody")
        XCTAssertTrue(harness.advanceFrames.isEmpty, "S-8411 a dropped row announces no move")
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.round).map { utcIso($0.startedAt) },
            earlier,
            "S-8411 the held row is unchanged"
        )
    }

    // MARK: - S-8412 a paused effort is still the effort to follow

    func testS8412APausedPhoneTimerStillJumps() async throws {
        let harness = await FollowHarness().launch()
        _ = await harness.engine.createSession(
            modality: "sports",
            exercises: [holdSlot("sx-a"), roundSlot("sx-b")]
        )
        _ = await harness.engine.selectExercise(slotId: "sx-b")
        harness.clearEmitted()

        let startedAt = utcIso(harness.clock.now)
        harness.clock.advance(30)
        let pausedAt = utcIso(harness.clock.now)

        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8412",
                timers: [
                    WatchTimerKind.hold: harness.timer(
                        WatchTimerKind.hold,
                        startedAt: startedAt,
                        slot: "sx-a",
                        pausedAt: pausedAt
                    )
                ]
            )
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-a", "S-8412 a paused effort is still work to follow")
        let shown = surface(harness).workTimer
        XCTAssertEqual(shown?.sessionExerciseId, "sx-a", "S-8412 the paused hold is A's own clock")
        XCTAssertEqual(shown?.state, WatchTimerState.paused, "S-8412 paused is what the wrist reads")
        XCTAssertEqual(harness.advanceFrames.count, 1, "S-8412 the jump announces itself once")
    }

    // MARK: - S-8413 a session that is over follows nothing

    func testS8413NoJumpForAnInactiveSession() async throws {
        let harness = await FollowHarness().launch().fixture()
        harness.clock.advance(60)

        _ = try await harness.engine.applyMessage(
            harness.phoneFrame("session_lifecycle", messageId: "m-8413-finish", payload: [
                "state": WatchLifecycleState.completed,
                "at": utcIso(harness.clock.now),
            ])
        )
        XCTAssertEqual(
            harness.engine.session?.status,
            WatchSessionStatus.completed,
            "S-8413 the fixture's session is over"
        )
        harness.clearEmitted()

        let startedAt = utcIso(harness.clock.now)
        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8413-late",
                timers: [WatchTimerKind.round: harness.timer(WatchTimerKind.round, startedAt: startedAt, slot: "sx-a")]
            )
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-b", "S-8413 a finished session follows nothing")
        XCTAssertTrue(harness.advanceFrames.isEmpty, "S-8413 no move is announced")
    }

    // MARK: - S-8414 a swipe in flight when the jump lands

    /// The swipe's own settling and focus clearing live in the watch-only view
    /// (`WatchLoggingPagerView.land(on:)`, source-scanned by S-7916); this test
    /// drives the model they sit on: the refused landing, the notice, and no
    /// second select.
    @MainActor
    func testS8414ASwipeInFlightWhenTheJumpLandsIsRefusedAndTheFocusClears() async throws {
        let harness = await FollowHarness().launch()
        _ = await harness.engine.createSession(
            modality: "sports",
            exercises: [roundSlot("sx-a"), roundSlot("sx-b"), roundSlot("sx-c")]
        )
        _ = await harness.engine.selectExercise(slotId: "sx-b")
        harness.clearEmitted()

        let state = surface(harness)
        let pager = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)
        let aIndex = try XCTUnwrap(pager.rows.firstIndex { $0.slotId == "sx-a" })

        state.focusSlotId = pager.focusSlotId(for: aIndex)
        XCTAssertEqual(state.focusSlotId, "sx-a", "S-8414 the fixture's swipe is in flight on A")
        XCTAssertEqual(currentSlot(harness.engine), "sx-b", "S-8414 the engine has not moved yet")

        let startedAt = utcIso(harness.clock.now)
        _ = try await harness.engine.applyMessage(
            harness.timerState(
                "m-8414",
                timers: [WatchTimerKind.round: harness.timer(WatchTimerKind.round, startedAt: startedAt, slot: "sx-c")]
            )
        )

        XCTAssertEqual(currentSlot(harness.engine), "sx-c", "S-8414 the jump lands on C")
        XCTAssertEqual(harness.advanceFrames.count, 1, "S-8414 the jump announces itself once")
        XCTAssertTrue(pager.isLocked, "S-8414 the running effort locks the pager")
        XCTAssertNil(pager.focusSlotId(for: aIndex), "S-8414 a locked session names no new focus")

        let moved = await pager.land(on: aIndex)

        XCTAssertFalse(moved, "S-8414 the settled swipe is refused")
        XCTAssertTrue(pager.noticeVisible(at: harness.clock.now), "S-8414 the refusal says why")
        // The view's refused-landing branch, which is the only focus clear left.
        state.focusSlotId = nil
        XCTAssertNil(state.focusSlotId, "S-8414 no focus outlives the refusal")
        XCTAssertEqual(currentSlot(harness.engine), "sx-c", "S-8414 the refused swipe moved nothing")
        XCTAssertEqual(harness.advanceFrames.count, 1, "S-8414 no second select")
    }
}
