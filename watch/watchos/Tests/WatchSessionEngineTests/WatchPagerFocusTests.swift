//
//  WatchPagerFocusTests.swift
//  WatchSessionEngineTests
//
//  S-7911 to S-7914 of
//  `docs/plans/2026-10-21-52-wrist-fine-crown-and-no-landing-flash-plan/2026-10-21-52-wrist-fine-crown-and-no-landing-flash-plan.md`
//  (decisions D-5, D-6): the focus a settled swipe names before the engine has
//  moved — the logging surface shows the focused slot and logs against it, the
//  pager model answers which slot a page would focus (nil for the engine's own
//  page, an out-of-range index or a locked session), and the watch-only view
//  wires the binding, the page choice, the clears and the counter as the plan
//  says.
//
//  S-7914 (fix round 1): a slot the phone pushed without a
//  `sessionExerciseId` of its own is still focusable, through the id
//  `WatchCatalogExercise(slot:).slotId` derives for it.
//
//  S-7915 and S-7916 (fix round 2): a Start against a focus the engine has not
//  reached is refused, and the view clears a focus its landing left behind.
//
//  The harness below is a copy of `PagerHarness` (`WatchPagerModelTests.swift`).
//  That harness has no `initialIndex`, so the current slot stays where its
//  fixture puts it: index 1, the Bench Press. The plan's "B" — the slot a swipe
//  focuses, a push-up with no `load` — sits at index 0, so its `fields` differ
//  from the bench's.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// One slot of the focus fixture ladder.
private func focusSlot(
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

/// One stored observation of the focus fixture: a set of five, no load.
private func focusEntry(
    _ entryId: String,
    slot: String,
    at loggedAt: String
) -> StoredWatchRecord {
    .observation(
        WatchObservationRecord(
            recordId: entryId,
            sessionId: "s-focus",
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
            ]
        )
    )
}

/// A wrist with its engine, start paths, the phone's preferences, the rating
/// state and the menu over them — `PagerHarness` copied for the focus tests.
/// One store, so a fixture and an action see the same rows.
final class FocusHarness {
    let clock: TestClock
    let store: WatchSessionStore
    let sessionId = "s-focus"

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
    func launch() async -> FocusHarness {
        var ids = 0
        func nextId(_ prefix: String) -> String {
            ids += 1
            return "\(prefix)-\(ids)"
        }

        engine = WatchSessionEngine(
            store: store,
            onEmit: { _ in },
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

    /// The ladder: Push-up (no `load`), Bench Press, Row — the session on the
    /// Bench Press, index 1.
    @discardableResult
    func fixture() async -> FocusHarness {
        let at = instant("2026-09-02T07:15:00Z")
        _ = await store.append(
            .session(
                WatchSessionRecord(
                    recordId: "focus-row-1",
                    sessionId: sessionId,
                    recordedAt: at,
                    startedAt: at,
                    modality: nil,
                    source: "watch",
                    status: WatchSessionStatus.active,
                    currentExerciseIndex: 1,
                    exercises: [
                        focusSlot("s1", "Push-up", capabilities: ["reps", "sets"]),
                        focusSlot("s2", "Bench Press"),
                        focusSlot("s3", "Row"),
                    ]
                )
            )
        )
        _ = await store.append(focusEntry("e-s1-1", slot: "s1", at: "2026-09-02T07:16:00Z"))
        _ = await store.append(focusEntry("e-s3-1", slot: "s3", at: "2026-09-02T07:20:00Z"))
        await engine.restore()
        return self
    }
}

/// A three-slot session whose second slot is timed work, with the wrist's own
/// work clock started on it: the lock S-7912 exercises, arranged as
/// `testS6603ASwipeDuringAWorkClockIsRefusedAndRaisesTheNotice` does.
@discardableResult
private func startAWorkClock(_ harness: FocusHarness) async -> WatchLoggingState {
    _ = await harness.engine.createSession(
        modality: "cardio_endurance",
        exercises: [
            focusSlot("p1", "Sprint", capabilities: ["time", "distance"]),
            focusSlot("p2", "Cycle", capabilities: ["time", "distance"]),
            focusSlot("p3", "Rower"),
        ]
    )
    _ = await harness.engine.selectExercise(slotId: "p2")
    let surface = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)
    await surface.startWork()
    return surface
}

/// How many times `needle` occurs in `source`.
private func occurrences(of needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

@MainActor
final class WatchPagerFocusTests: XCTestCase {

    // MARK: - S-7911 the focus on the logging state

    func testS7911TheFocusShowsTheFocusedExerciseAndLogsAgainstIt() async throws {
        let harness = await FocusHarness().launch()
        await harness.fixture()
        let state = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        XCTAssertNil(state.focusSlotId, "S-7911 no focus before any swipe")
        XCTAssertEqual(
            state.exerciseName,
            "Bench Press",
            "S-7911 nil focus shows the engine's current exercise"
        )
        XCTAssertNotNil(
            state.fields.first { $0.metricKey == WatchMetricKey.weight },
            "S-7911 the bench carries its weight row"
        )

        state.focusSlotId = "s1"

        XCTAssertEqual(
            state.exerciseName,
            "Push-up",
            "S-7911 the focus names the slot the surface shows"
        )
        XCTAssertNil(
            state.fields.first { $0.metricKey == WatchMetricKey.weight },
            "S-7911 the push-up has no load, so no weight row"
        )
        XCTAssertNotNil(
            state.fields.first { $0.metricKey == WatchMetricKey.reps },
            "S-7911 the push-up keeps its reps row"
        )

        let record = try await state.log()

        XCTAssertEqual(
            record.payload["sessionExerciseId"] as? String,
            "s1",
            "S-7911 the entry is stored against the focused slot, not the engine's"
        )

        state.focusSlotId = nil

        XCTAssertEqual(
            state.exerciseName,
            "Bench Press",
            "S-7911 clearing the focus returns to the engine's current exercise"
        )

        state.focusSlotId = "s-nowhere"

        XCTAssertEqual(
            state.exerciseName,
            "Bench Press",
            "S-7911 an id that is not on the ladder falls back, no crash"
        )
    }

    // MARK: - S-7912 which slot a page would focus

    func testS7912ThePagerNamesAFocusOnlyForAnotherLivePage() async throws {
        let harness = await FocusHarness().launch()
        await harness.fixture()
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)
        XCTAssertEqual(model.currentIndex, 1, "S-7912 the fixture sits on Bench Press")

        XCTAssertNil(
            model.focusSlotId(for: 1),
            "S-7912 the engine's own page needs no focus"
        )
        XCTAssertEqual(
            model.focusSlotId(for: 0),
            "s1",
            "S-7912 another page names that row's slot"
        )
        XCTAssertEqual(model.focusSlotId(for: 2), "s3", "S-7912 and so does the third")
        XCTAssertNil(model.focusSlotId(for: -1), "S-7912 no page before the first")
        XCTAssertNil(model.focusSlotId(for: 3), "S-7912 no page after the last")
    }

    func testS7912ALockedSessionFocusesNothing() async throws {
        let harness = await FocusHarness().launch()
        await startAWorkClock(harness)
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.elapsed)?.state,
            WatchTimerState.running,
            "S-7912 the fixture is running an elapsed work clock, so the lock case is the one exercised"
        )
        let model = WatchPagerModel(menu: harness.menu, clock: harness.clock.call)
        XCTAssertTrue(model.isLocked, "S-7912 the menu is locked")
        XCTAssertEqual(model.currentIndex, 1, "S-7912 the session sits on the effort")

        XCTAssertNil(
            model.focusSlotId(for: 0),
            "S-7912 a locked session focuses nothing, not even another live page"
        )
        XCTAssertNil(model.focusSlotId(for: 2), "S-7912 nor the page after")
    }

    // MARK: - S-7913 the view's wiring, read as source

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

    func testS7913ThePagerViewWiresTheFocusThroughItsOwnBinding() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")

        XCTAssertTrue(
            source.contains("TabView(selection: selectionBinding)"),
            "S-7913 the TabView binds the custom selection, not the state var"
        )
        XCTAssertTrue(
            source.contains("state.focusSlotId = pager.focusSlotId(for: newValue)"),
            "S-7913 a settled swipe names the focus synchronously"
        )
        XCTAssertTrue(
            source.contains("if index == selection"),
            "S-7913 the selected page renders the logger, the others the card"
        )
        XCTAssertGreaterThanOrEqual(
            occurrences(of: "state.focusSlotId = nil", in: source),
            2,
            "S-7913 land(on:) clears the focus whether it moved or was refused"
        )
        XCTAssertTrue(
            source.contains("pageLabel: \"\\(index + 1)/\\(pager.pageCount)\""),
            "S-7913 the counter reads the selection's page of the count"
        )
        XCTAssertFalse(
            source.contains("TabView(selection: $selection)"),
            "S-7913 the plain state binding would set no focus"
        )
    }

    // MARK: - S-7914 a focus on a slot that has no id of its own

    /// A slot the phone pushed without a `sessionExerciseId` of its own: only
    /// `exerciseId`, `name` and `capabilities`, so the id anything addresses it
    /// by is the one `WatchCatalogExercise(slot:).slotId` derives —
    /// `"sx-<exerciseId>"`, the same reading `WatchMenu`'s `menuSlotId` makes.
    /// The engine's `createSession(exercises:)` stores the slots as given, so
    /// the ladder can hold such a slot without a snapshot (whose schema requires
    /// the key) and without the engine filling one in.
    func testS7914AFocusNamesASlotThatHasNoIdOfItsOwn() async throws {
        let harness = await FocusHarness().launch()
        _ = await harness.engine.createSession(
            modality: nil,
            exercises: [
                focusSlot("w1", "Bench Press"),
                [
                    "exerciseId": "ex-push",
                    "name": "Push-up",
                    "capabilities": ["reps", "sets"],
                ],
            ]
        )
        let state = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        XCTAssertEqual(
            state.exerciseName,
            "Bench Press",
            "S-7914 no focus shows the engine's current exercise"
        )
        XCTAssertNotNil(
            state.fields.first { $0.metricKey == WatchMetricKey.weight },
            "S-7914 the bench carries its weight row"
        )

        state.focusSlotId = "sx-ex-push"

        XCTAssertEqual(
            state.exerciseName,
            "Push-up",
            "S-7914 the focus reaches a slot through the id its exercise derives"
        )
        XCTAssertNil(
            state.fields.first { $0.metricKey == WatchMetricKey.weight },
            "S-7914 the push-up has no load, so no weight row"
        )
        XCTAssertNotNil(
            state.fields.first { $0.metricKey == WatchMetricKey.reps },
            "S-7914 the push-up keeps its reps row"
        )

        state.focusSlotId = "w1"

        XCTAssertEqual(
            state.exerciseName,
            "Bench Press",
            "S-7914 focusing the first slot returns to it"
        )

        state.focusSlotId = nil

        XCTAssertEqual(
            state.exerciseName,
            "Bench Press",
            "S-7914 clearing the focus returns to the engine's current exercise"
        )
    }

    // MARK: - S-7915 a Start against a focus the engine has not reached

    /// A ladder whose first slot — the engine's current — is a bench and whose
    /// second is timed work: the capabilities resolve to the `timed` kind, so
    /// `startWork()` would start the elapsed clock (S-1300's shape).
    func testS7915StartWorkIsRefusedWhileTheFocusIsAheadOfTheEngine() async throws {
        let harness = await FocusHarness().launch()
        _ = await harness.engine.createSession(
            modality: "cardio_endurance",
            exercises: [
                focusSlot("b1", "Bench Press"),
                focusSlot("t1", "Sprint", capabilities: ["time", "distance"]),
            ]
        )
        let state = WatchLoggingState(engine: harness.engine, clock: harness.clock.call)

        state.focusSlotId = "t1"
        await state.startWork()
        XCTAssertNil(
            harness.engine.timerFor(WatchTimerKind.elapsed),
            "S-7915 a Start against a slot the engine has not reached is refused"
        )

        state.focusSlotId = nil
        _ = await harness.engine.selectExercise(slotId: "t1")
        await state.startWork()
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.elapsed)?.state,
            WatchTimerState.running,
            "S-7915 with no focus and the engine on the timed slot, Start runs the clock"
        )

        _ = await harness.engine.stopTimer(kind: WatchTimerKind.elapsed, at: harness.clock.now)
        state.focusSlotId = "t1"
        await state.startWork()
        XCTAssertEqual(
            harness.engine.timerFor(WatchTimerKind.elapsed)?.state,
            WatchTimerState.running,
            "S-7915 a focus on the engine's own current slot starts as normal"
        )
    }

    // MARK: - S-7916 the view clears a stale focus, read as source

    func testS7916TheViewClearsAStaleFocus() throws {
        let source = try engineSource("WatchLoggingPagerView.swift")

        let landStart = try XCTUnwrap(
            source.range(of: "private func land(on index: Int)"),
            "S-7916 land(on:) is where the early return lives"
        )
        let land = String(source[landStart.lowerBound...])
        let landEnd = try XCTUnwrap(
            land.range(of: "\n    }\n"),
            "S-7916 land(on:) closes"
        )
        let landBody = String(land[..<landEnd.lowerBound])

        let guardRange = try XCTUnwrap(
            landBody.range(of: "guard index != pager.currentIndex else {"),
            "S-7916 the early return is the guard on the engine's own page"
        )
        let guardBody = String(landBody[guardRange.lowerBound...])
        let focus = try XCTUnwrap(
            guardBody.range(of: "state.focusSlotId = nil"),
            "S-7916 the refused landing clears the focus"
        )
        let returnRange = try XCTUnwrap(
            guardBody.range(of: "return"),
            "S-7916 the guard returns"
        )
        XCTAssertLessThan(
            focus.lowerBound, returnRange.lowerBound,
            "S-7916 the focus is cleared before the return"
        )

        let followStart = try XCTUnwrap(
            source.range(of: "private func followEngine()"),
            "S-7916 followEngine() is where a stale focus is dropped"
        )
        let follow = String(source[followStart.lowerBound...])
        XCTAssertTrue(
            follow.contains("if !landing { state.focusSlotId = nil }"),
            "S-7916 a focus left over with no landing in flight is stale and is dropped"
        )
    }
}
