//
//  WatchPagerModelTests.swift
//  WatchSessionEngineTests
//
//  S-6601 to S-6608 of
//  `docs/plans/2026-10-20-46b-wrist-swipe-pager-plan/2026-10-20-46b-wrist-swipe-pager-plan.md`
//  (decisions D-1, D-2): the wrist's swipe pager over one `WatchMenuState` —
//  the rows it reads on every access, the one jump a settled page makes, the
//  lock that refuses a swipe during an effort, and the pages that are gone by
//  the time the swipe settles.
//
//  The pager's rules are held here rather than in the watchOS-only view, so the
//  desktop toolchain can assert them: the view that mounts a `TabView` over this
//  model is compiled only by the watch app target.
//
//  The harness below is a private copy of `WatchMenuHarness`
//  (`WatchMenuTests.swift`) with one addition: the engine's `onEmit` capture,
//  because S-6602 counts the `exercise_advanced` lifecycles a settle emits. Its
//  fixture A is the same three-slot ladder, current index 1 (Bench Press).
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// One slot of the pager fixture ladder.
private func pagerSlot(
    _ id: String,
    _ name: String,
    capabilities: [String] = ["reps", "sets", "load"]
) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": name,
        "capabilities": capabilities,
    ]
}

/// One stored observation of the pager fixture.
private func pagerEntry(
    _ entryId: String,
    slot: String,
    at loggedAt: String
) -> StoredWatchRecord {
    .observation(
        WatchObservationRecord(
            recordId: entryId,
            sessionId: "s-pager",
            recordedAt: instant(loggedAt),
            kind: WatchObservationKind.set,
            payload: [
                "entryId": entryId,
                "eventId": entryId,
                "kind": WatchObservationKind.set,
                "loggedAt": loggedAt,
                "sessionExerciseId": slot,
                "exerciseId": "ex-\(slot)",
                "reps": 5,
                "loadKg": 80,
            ]
        )
    )
}

/// The phone's `session_lifecycle` for an advance, as the phone builds it.
private func pagerAdvance(
    sessionId: String,
    messageId: String,
    index: Int,
    at time: String
) -> [String: Any] {
    [
        "protocolVersion": SyncProtocolValidator.protocolVersion,
        "messageId": messageId,
        "sessionId": sessionId,
        "type": "session_lifecycle",
        "origin": "phone",
        "sentAt": time,
        "payload": [
            "state": WatchLifecycleState.exerciseAdvanced,
            "at": time,
            "exerciseIndex": index,
        ] as [String: Any],
    ]
}

/// The phone's `structure_change` removing `slotId` from the ladder.
private func pagerRemoval(
    sessionId: String,
    changeId: String,
    removing slotId: String,
    at time: String
) -> [String: Any] {
    [
        "protocolVersion": SyncProtocolValidator.protocolVersion,
        "messageId": "msg-\(changeId)",
        "sessionId": sessionId,
        "type": "structure_change",
        "origin": "phone",
        "sentAt": time,
        "payload": [
            "changeId": changeId,
            "changes": [["kind": "remove_exercise", "sessionExerciseId": slotId]],
        ] as [String: Any],
    ]
}

/// A wrist with its engine, start paths, the phone's preferences, the rating
/// state and the menu over them — `WatchMenuHarness` plus the emitted frames
/// (S-6602). One store, so a fixture and an action see the same rows.
final class PagerHarness {
    let clock: TestClock
    let store: WatchSessionStore
    let sessionId = "s-pager"

    /// Everything the engine emitted, in order.
    private(set) var emitted: [[String: Any]] = []

    private(set) var engine: WatchSessionEngine!
    private(set) var paths: WatchSessionStartPaths!
    private(set) var preferences: WatchPhonePreferences!
    private(set) var rating: WatchEffortRatingState!
    private(set) var menu: WatchMenuState!

    init(store: WatchSessionStore = InMemoryWatchSessionStore()) {
        clock = TestClock(instant("2026-09-02T07:15:00Z"))
        self.store = store
    }

    /// A wrist that has restored, with the menu over the same objects.
    @discardableResult
    func launch() async -> PagerHarness {
        var ids = 0
        func nextId(_ prefix: String) -> String {
            ids += 1
            return "\(prefix)-\(ids)"
        }

        engine = WatchSessionEngine(
            store: store,
            onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
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

    /// Fixture A: Squat, Bench Press and Row, the session on Bench Press.
    @discardableResult
    func fixtureA() async -> PagerHarness {
        let at = instant("2026-09-02T07:15:00Z")
        _ = await store.append(
            .session(
                WatchSessionRecord(
                    recordId: "pager-row-1",
                    sessionId: sessionId,
                    recordedAt: at,
                    startedAt: at,
                    modality: nil,
                    source: "watch",
                    status: WatchSessionStatus.active,
                    currentExerciseIndex: 1,
                    exercises: [
                        pagerSlot("s1", "Squat"),
                        pagerSlot("s2", "Bench Press"),
                        pagerSlot("s3", "Row"),
                    ]
                )
            )
        )
        _ = await store.append(pagerEntry("e-s1-1", slot: "s1", at: "2026-09-02T07:16:00Z"))
        _ = await store.append(pagerEntry("e-s1-2", slot: "s1", at: "2026-09-02T07:18:00Z"))
        _ = await store.append(pagerEntry("e-s3-1", slot: "s3", at: "2026-09-02T07:20:00Z"))
        await engine.restore()
        return self
    }

    /// Forget the frames the fixture wrote, so a test counts its own act.
    func clearEmitted() { emitted.removeAll() }
}

/// The `exercise_advanced` lifecycles the engine emitted.
private func advancedFrames(_ harness: PagerHarness) -> [[String: Any]] {
    harness.emitted.filter { envelope in
        guard envelope["type"] as? String == "session_lifecycle" else { return false }
        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        return payload["state"] as? String == WatchLifecycleState.exerciseAdvanced
    }
}

/// A three-slot session whose second slot is timed work, with the wrist's own
/// work clock started on it: the lock S-6603 and S-6606 exercise.
@discardableResult
private func startAWorkClock(_ harness: PagerHarness) async -> WatchLoggingState {
    _ = await harness.engine.createSession(
        modality: "cardio_endurance",
        exercises: [
            pagerSlot("p1", "Sprint", capabilities: ["time", "distance"]),
            pagerSlot("p2", "Cycle", capabilities: ["time", "distance"]),
            pagerSlot("p3", "Rower"),
        ]
    )
    _ = await harness.engine.selectExercise(slotId: "p2")
    let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)
    await surface.startWork()
    return surface
}

@MainActor
final class WatchPagerModelTests: XCTestCase {

    // MARK: - S-6601 the rows and the counter, read fresh

    func testS6601TheModelReadsTheLadderAndThePositionOnEveryAccess() async throws {
        let harness = await PagerHarness().launch()
        await harness.fixtureA()
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)

        XCTAssertEqual(
            model.rows.map(\.name),
            ["Squat", "Bench Press", "Row"],
            "S-6601 the pages are the ladder's rows, in its own order"
        )
        XCTAssertEqual(model.pageCount, 3, "S-6601 three slots, three pages")
        XCTAssertEqual(model.currentIndex, 1, "S-6601 the fixture sits on Bench Press")
        XCTAssertEqual(model.pageLabel, "2/3", "S-6601 the counter names the page, not the index")

        _ = await harness.engine.selectExercise(slotId: "s3")

        XCTAssertEqual(model.currentIndex, 2, "S-6601 a jump made after the first read is in the next read")
        XCTAssertEqual(model.pageLabel, "3/3", "S-6601 and the counter follows it")
        XCTAssertEqual(model.rows.map(\.name), ["Squat", "Bench Press", "Row"], "S-6601 the ladder itself did not move")
    }

    // MARK: - S-6602 the settle

    func testS6602ASettledPageMovesTheSessionOnceAndEmitsOneFrame() async throws {
        let harness = await PagerHarness().launch()
        await harness.fixtureA()
        harness.clearEmitted()
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)

        let moved = await model.land(on: 2)

        XCTAssertTrue(moved, "S-6602 a free session takes the page")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 2, "S-6602 the session is on Row")
        XCTAssertEqual(harness.engine.currentExercise?["sessionExerciseId"] as? String, "s3")
        XCTAssertEqual(advancedFrames(harness).count, 1, "S-6602 one settled page is one select, one frame")
        let payload = (advancedFrames(harness).last?["payload"] as? [String: Any]) ?? [:]
        XCTAssertEqual(payload["exerciseIndex"] as? Int, 2, "S-6602 the frame names the page it landed on")

        let again = await model.land(on: 2)

        XCTAssertTrue(again, "S-6602 a page that is already current settles true")
        XCTAssertEqual(advancedFrames(harness).count, 1, "S-6602 and emits nothing more")
        XCTAssertEqual(model.currentIndex, 2)
    }

    /// The same-index arm on its own: the model never asks the engine for a
    /// position it already holds.
    func testS6602TheSameIndexArmSelectsNothing() async throws {
        let harness = await PagerHarness().launch()
        await harness.fixtureA()
        harness.clearEmitted()
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)
        let revisionBefore = harness.engine.session?.revision

        let settled = await model.land(on: 1)

        XCTAssertTrue(settled, "S-6602 the page the session is already on lands true")
        XCTAssertEqual(harness.emitted.count, 0, "S-6602 no frame for a page that was already current")
        XCTAssertEqual(harness.engine.session?.revision, revisionBefore, "S-6602 and no structure change either")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 1)
    }

    // MARK: - S-6603 the lock arm

    func testS6603ASwipeDuringAWorkClockIsRefusedAndRaisesTheNotice() async throws {
        let harness = await PagerHarness().launch()
        await startAWorkClock(harness)
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.elapsed)?.state,
            WatchTimerState.running,
            "S-6603 the fixture is running an elapsed work clock, so the lock case is the one exercised"
        )
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)
        let now = harness.clock.call()
        XCTAssertFalse(model.noticeVisible(at: now), "S-6603 no notice before any swipe")
        XCTAssertTrue(model.isLocked, "S-6603 and the menu is locked")

        let settled = await model.land(on: 0)

        XCTAssertFalse(settled, "S-6603 a locked session refuses the page")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 1, "S-6603 the session stays on the effort")
        XCTAssertEqual(harness.engine.currentExercise?["sessionExerciseId"] as? String, "p2")
        XCTAssertTrue(model.noticeVisible(at: harness.clock.call()), "S-6603 the refused swipe raises the notice")
        XCTAssertTrue(
            model.noticeVisible(at: now.addingTimeInterval(1.4)),
            "S-6603 the notice is still up at 1.4 s"
        )
        XCTAssertFalse(
            model.noticeVisible(at: now.addingTimeInterval(WatchPagerCopy.noticeSeconds)),
            "S-6603 exactly noticeSeconds later it has expired"
        )
        XCTAssertEqual(
            WatchPagerCopy.lockedNotice,
            "An effort is running",
            "S-6603 the notice uses the menu's own words"
        )
    }

    // MARK: - S-6604 the out-of-range arm

    func testS6604APageOutsideTheRowsChangesNothing() async throws {
        let harness = await PagerHarness().launch()
        await harness.fixtureA()
        harness.clearEmitted()
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)

        let before = await model.land(on: -1)
        let past = await model.land(on: 3)

        XCTAssertFalse(before, "S-6604 there is no page before the first")
        XCTAssertFalse(past, "S-6604 there is no page after the last")
        XCTAssertEqual(model.currentIndex, 1, "S-6604 the session did not move")
        XCTAssertEqual(model.pageLabel, "2/3")
        XCTAssertEqual(harness.emitted.count, 0, "S-6604 nothing was selected, so nothing was announced")
        XCTAssertFalse(
            model.noticeVisible(at: harness.clock.call()),
            "S-6604 a page that does not exist is not a locked swipe"
        )
    }

    // MARK: - S-6605 a rest is not work

    func testS6605ARunningRestLeavesThePagerFree() async throws {
        let harness = await PagerHarness().launch()
        await harness.fixtureA()
        _ = try await harness.engine.startTimer(WatchTimerKind.rest)
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.running,
            "S-6605 the fixture is resting, so the rest case is the one exercised"
        )
        XCTAssertFalse(harness.menu.isLocked, "S-6605 a rest is not work, so the menu is free")
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)

        let settled = await model.land(on: 0)

        XCTAssertTrue(settled, "S-6605 a running rest does not refuse the page")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 0, "S-6605 the session moves to Squat")
        XCTAssertEqual(model.currentIndex, 0)
    }

    // MARK: - S-6606 when the pager is shown

    func testS6606ThePagerShowsOnlyForSeveralExercisesAndAnUnlockedMenu() async throws {
        let harness = await PagerHarness().launch()
        await harness.fixtureA()
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)

        XCTAssertTrue(model.showsPager, "S-6606 three pages on a free session")
        XCTAssertEqual(model.pageLabel, "2/3")

        let single = await PagerHarness().launch()
        _ = await single.engine.createSession(
            modality: nil,
            exercises: [pagerSlot("only", "Deadlift")]
        )
        let onePage = WatchPagerModel(menu: single.menu, clock: single.clock.call)
        XCTAssertEqual(onePage.pageCount, 1, "S-6606 one exercise is one page")
        XCTAssertFalse(onePage.showsPager, "S-6606 and there is nothing to page through")
        XCTAssertNil(onePage.pageLabel, "S-6606 a session of one says no counter at all")

        let locked = await PagerHarness().launch()
        await startAWorkClock(locked)
        let lockedModel = WatchPagerModel(menu: locked.menu, clock: locked.clock.call)
        XCTAssertFalse(lockedModel.showsPager, "S-6606 a running effort hides the pager")
    }

    // MARK: - S-6607 the phone moves the position

    func testS6607APhoneSideAdvanceIsVisibleOnTheNextRead() async throws {
        let harness = await PagerHarness().launch()
        await harness.fixtureA()
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)
        XCTAssertEqual(model.currentIndex, 1)

        let applied = try await harness.engine.applyMessage(
            pagerAdvance(
                sessionId: harness.sessionId,
                messageId: "msg-pager-advance-1",
                index: 0,
                at: "2026-09-02T07:30:00Z"
            )
        )

        XCTAssertTrue(applied, "S-6607 the phone's lifecycle is about this session")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 0)
        XCTAssertEqual(model.currentIndex, 0, "S-6607 the model reads the position the phone set")
        XCTAssertEqual(model.pageLabel, "1/3")
    }

    // MARK: - S-6608 the page the phone removed

    func testS6608SettlingOnAPageThePhoneRemovedChangesNothing() async throws {
        let harness = await PagerHarness().launch()
        await harness.fixtureA()
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)
        XCTAssertEqual(model.pageCount, 3)

        let applied = try await harness.engine.applyMessage(
            pagerRemoval(
                sessionId: harness.sessionId,
                changeId: "chg-pager-remove-row-1",
                removing: "s3",
                at: "2026-09-02T07:31:00Z"
            )
        )

        XCTAssertTrue(applied, "S-6608 the change really applied, so the refusal below is not a refused frame's")
        XCTAssertEqual(model.pageCount, 2, "S-6608 the last page is gone before the swipe settles")
        XCTAssertEqual(model.currentIndex, 1, "S-6608 the user is still on Bench Press")

        let settled = await model.land(on: 2)

        XCTAssertFalse(settled, "S-6608 the page the swipe was heading for no longer exists")
        XCTAssertEqual(model.currentIndex, 1, "S-6608 the session did not move")
        XCTAssertEqual(harness.engine.session?.currentExerciseIndex, 1)
        XCTAssertEqual(model.pageLabel, "2/2", "S-6608 the counter reads the ladder that is left")
    }
}
