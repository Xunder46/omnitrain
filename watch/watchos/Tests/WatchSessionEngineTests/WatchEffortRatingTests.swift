//
//  WatchEffortRatingTests.swift
//  WatchSessionEngineTests
//
//  S-211 to S-220 of
//  `.github/agents/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`: the
//  wrist's End, the effort-rating prompt it may owe, and the one answer the
//  prompt records (D-113, D-114, D-116 – D-119). Plus the two things the plan
//  asks to be structural: the copy and scale are the shared contract's, and
//  nothing in the rating's state or views offers a way out but an answer.
//
//  A kill is simulated as the watch experiences it: new objects built over the
//  same storage and restored.
//

import XCTest

@testable import WatchSessionEngine

/// The phone's `preferences_down`, as the phone builds it (A-22's id shape).
func preferencesDown(_ asks: Bool, generatedAt: String, messageId: String? = nil) -> [String: Any] {
    [
        "protocolVersion": SyncProtocolValidator.protocolVersion,
        "messageId": messageId ?? "msg-preferences-\(generatedAt)-\(asks ? "on" : "off")",
        "type": "preferences_down",
        "origin": "phone",
        "sentAt": generatedAt,
        "payload": ["generatedAt": generatedAt, "effortRatingPrompt": asks],
    ]
}

/// An instant from its wire form.
func instant(_ text: String) -> Date {
    (try? parseUtcIso(text)) ?? Date(timeIntervalSince1970: 0)
}

/// A wrist with its engine, the phone's preferences and the rating state, all
/// over one store. `launch()` builds them afresh and restores them, which is
/// also how a relaunch after a kill is simulated.
final class RatingHarness {
    let clock: TestClock
    let store = InMemoryWatchSessionStore()

    /// Everything every engine built over this store emitted, in order.
    private(set) var emitted: [[String: Any]] = []

    private var sessionIds: [String]
    private var recordIds = 0

    private(set) var engine: WatchSessionEngine!
    private(set) var preferences: WatchPhonePreferences!
    private(set) var rating: WatchEffortRatingState!

    init(sessionIds: [String] = ["s-r-1"]) {
        clock = TestClock(instant("2026-09-25T09:00:00Z"))
        self.sessionIds = sessionIds
    }

    @discardableResult
    func launch() async -> RatingHarness {
        engine = WatchSessionEngine(
            store: store,
            onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
            validator: Harness.validator(),
            clock: clock.call,
            idFactory: { [weak self] in
                guard let self else { return UUID().uuidString }
                self.recordIds += 1
                return "rec-\(self.recordIds)"
            },
            sessionIdFactory: { [weak self] in
                guard let self, !self.sessionIds.isEmpty else { return UUID().uuidString }
                return self.sessionIds.removeFirst()
            }
        )
        preferences = WatchPhonePreferences(store: store, validator: Harness.validator(), clock: clock.call)
        rating = WatchEffortRatingState(engine: engine, store: store, preferences: preferences, clock: clock.call)

        await engine.restore()
        await preferences.restore()
        await rating.restore()
        return self
    }

    /// The phone's setting arriving at a wrist sync.
    func sync(_ asks: Bool, generatedAt: String, messageId: String? = nil) async {
        _ = await preferences.applyPreferencesDown(
            preferencesDown(asks, generatedAt: generatedAt, messageId: messageId)
        )
    }

    func start(at time: String) async {
        clock.now = instant(time)
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
    }

    func logSet(_ entryId: String, at time: String) async throws {
        clock.now = instant(time)
        _ = try await engine.appendObservation(setEvent(clock, entryId: entryId))
    }

    func end(at time: String) async {
        clock.now = instant(time)
        await rating.end()
    }

    /// A session started, one set logged, and ended on the wrist.
    func loggedSession(start: String, set entryId: String, logged: String, end: String) async throws {
        await self.start(at: start)
        try await logSet(entryId, at: logged)
        await self.end(at: end)
    }

    /// The observation events the wrist emitted, of `kind`.
    func events(_ kind: String) -> [[String: Any]] {
        emitted
            .filter { $0["type"] as? String == "observations_up" }
            .compactMap { ((($0["payload"] as? [String: Any])?["events"]) as? [[String: Any]])?.first }
            .filter { $0["kind"] as? String == kind }
    }

    /// The session lifecycle messages the wrist emitted, in `state`.
    func lifecycles(_ state: String) -> [[String: Any]] {
        emitted
            .filter { $0["type"] as? String == "session_lifecycle" }
            .filter { ($0["payload"] as? [String: Any])?["state"] as? String == state }
    }

    func phoneLifecycle(_ state: String, sessionId: String, at time: String) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-phone-\(state)-\(time)",
            "sessionId": sessionId,
            "type": "session_lifecycle",
            "origin": "phone",
            "sentAt": time,
            "payload": ["state": state, "at": time],
        ]
    }
}

final class WatchEffortRatingTests: XCTestCase {

    // MARK: - S-211 prompt owed and answered

    func testS211AnEndThatOwesARatingAsksForItAndRecordsOneAnswer() async throws {
        let wrist = await RatingHarness().launch()
        await wrist.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        await wrist.start(at: "2026-09-25T10:00:00Z")
        try await wrist.logSet("e-1", at: "2026-09-25T10:05:00Z")
        XCTAssertTrue(wrist.rating.canEnd, "S-211 a running session can be ended")

        await wrist.end(at: "2026-09-25T10:10:00Z")

        XCTAssertEqual(wrist.lifecycles("completed").count, 1, "S-211 exactly one completion is emitted")
        XCTAssertEqual(wrist.events("session_end").count, 1, "S-211 exactly one session end is emitted")
        XCTAssertEqual(wrist.rating.owedSessionIds, ["s-r-1"], "S-211 a prompt is owed for s-r-1")
        XCTAssertFalse(wrist.rating.canEnd, "S-211 the session is over")

        let contract = try Fixtures.effortRatingContract()
        let scale = try XCTUnwrap(contract["scale"] as? [String: Any])
        let labels = try XCTUnwrap(contract["labels"] as? [String: String])
        XCTAssertEqual(wrist.rating.title, contract["title"] as? String, "S-211 the contract's question")
        XCTAssertEqual(
            wrist.rating.scale,
            Array(try XCTUnwrap(scale["min"] as? Int)...(try XCTUnwrap(scale["max"] as? Int))),
            "S-211 the contract's scale"
        )
        XCTAssertEqual(wrist.rating.lowestLabel, labels["1"], "S-211 the contract's label at 1")
        XCTAssertEqual(wrist.rating.highestLabel, labels["5"], "S-211 the contract's label at 5")

        XCTAssertNil(wrist.rating.selected, "S-211 nothing is preselected")
        XCTAssertFalse(wrist.rating.canConfirm, "S-211 Confirm is disabled while nothing is selected")
        let unanswered = try await wrist.rating.confirm()
        XCTAssertNil(unanswered, "S-211 a confirm with nothing selected records nothing")
        XCTAssertTrue(wrist.events("effort_rating").isEmpty, "S-211")

        wrist.clock.now = instant("2026-09-25T10:10:20Z")
        wrist.rating.select(4)
        XCTAssertTrue(wrist.rating.canConfirm, "S-211 a number is selected")
        try await wrist.rating.confirm()

        let ratings = wrist.events("effort_rating")
        XCTAssertEqual(ratings.count, 1, "S-211 exactly one effort_rating")
        let answer = try XCTUnwrap(ratings.first)
        XCTAssertEqual(answer["entryId"] as? String, "rating-s-r-1", "S-211")
        XCTAssertEqual(answer["eventId"] as? String, "rating-s-r-1", "S-211")
        XCTAssertEqual(answer["rating"] as? Int, 4, "S-211")
        XCTAssertEqual(answer["loggedAt"] as? String, "2026-09-25T10:10:20.000Z", "S-211 the confirm instant")
        XCTAssertFalse(wrist.rating.isPromptOwed, "S-211 the prompt is no longer owed")
        XCTAssertNil(wrist.rating.selected, "S-211")
    }

    // MARK: - S-212 / S-213 not owed

    func testS212WithTheSettingOffTheEndOwesNothing() async throws {
        let wrist = await RatingHarness().launch()
        await wrist.sync(false, generatedAt: "2026-09-25T09:00:00Z")
        try await wrist.loggedSession(
            start: "2026-09-25T10:00:00Z",
            set: "e-1",
            logged: "2026-09-25T10:05:00Z",
            end: "2026-09-25T10:10:00Z"
        )

        XCTAssertFalse(wrist.rating.isPromptOwed, "S-212 the phone's setting is off")
        XCTAssertTrue(wrist.events("effort_rating").isEmpty, "S-212 no effort_rating")
        XCTAssertEqual(wrist.events("session_end").count, 1, "S-212 the session end is sent regardless")
    }

    func testS213AWristThatNeverSyncedDoesNotAsk() async throws {
        let wrist = await RatingHarness().launch()
        XCTAssertNil(wrist.preferences.current)
        try await wrist.loggedSession(
            start: "2026-09-25T10:00:00Z",
            set: "e-1",
            logged: "2026-09-25T10:05:00Z",
            end: "2026-09-25T10:10:00Z"
        )

        XCTAssertFalse(wrist.rating.isPromptOwed, "S-213 no preferences record: the setting is unknown, so no prompt")
        XCTAssertEqual(wrist.events("session_end").count, 1, "S-213")
    }

    // MARK: - S-214 the setting arrives at sync and the newest copy rules

    func testS214TheSettingArrivesAtSyncAndIsHonouredFromThenOn() async throws {
        let wrist = await RatingHarness(sessionIds: ["s-a", "s-b", "s-c"]).launch()

        await wrist.sync(false, generatedAt: "2026-09-25T09:00:00Z")
        try await wrist.loggedSession(
            start: "2026-09-25T10:00:00Z", set: "e-a", logged: "2026-09-25T10:05:00Z", end: "2026-09-25T10:10:00Z"
        )
        XCTAssertEqual(wrist.rating.owedSessionIds, [], "S-214 A: the setting was off")

        await wrist.sync(true, generatedAt: "2026-09-25T09:30:00Z")
        try await wrist.loggedSession(
            start: "2026-09-25T11:00:00Z", set: "e-b", logged: "2026-09-25T11:05:00Z", end: "2026-09-25T11:10:00Z"
        )
        XCTAssertEqual(wrist.rating.owedSessionIds, ["s-b"], "S-214 B: the newer copy turned it on")

        // The first copy's setting and stamp, delivered late under its own id —
        // a byte-identical redelivery would be a store no-op (A-22), so this is
        // the copy the newest-wins rule exists for.
        await wrist.sync(false, generatedAt: "2026-09-25T09:00:00Z", messageId: "msg-preferences-late-copy")
        try await wrist.loggedSession(
            start: "2026-09-25T12:00:00Z", set: "e-c", logged: "2026-09-25T12:05:00Z", end: "2026-09-25T12:10:00Z"
        )
        XCTAssertEqual(
            wrist.rating.owedSessionIds,
            ["s-c", "s-b"],
            "S-214 C: a stale copy arriving late changes nothing; owed prompts come most recent first"
        )
    }

    // MARK: - S-215 kill during the prompt

    func testS215AKillDuringThePromptAsksAgainAndRecordsOneAnswer() async throws {
        let wrist = await RatingHarness().launch()
        await wrist.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        try await wrist.loggedSession(
            start: "2026-09-25T10:00:00Z", set: "e-1", logged: "2026-09-25T10:05:00Z", end: "2026-09-25T10:10:00Z"
        )
        XCTAssertEqual(wrist.rating.owedSessionIds, ["s-r-1"])

        // Killed with the prompt up: a new process over the same storage.
        await wrist.launch()
        XCTAssertEqual(
            wrist.rating.owedSessionIds,
            ["s-r-1"],
            "S-215 the prompt was stored at End, so the relaunch still owes it"
        )

        wrist.clock.now = instant("2026-09-25T10:12:00Z")
        wrist.rating.select(2)
        try await wrist.rating.confirm()

        XCTAssertEqual(wrist.events("effort_rating").map { $0["rating"] as? Int }, [2], "S-215 exactly one rating, 2")
        let stored = await wrist.store.readAll()
        XCTAssertEqual(
            stored.observations.filter { $0.kind == WatchObservationKind.effortRating }.count,
            1,
            "S-215 exactly one effort_rating is stored"
        )
        XCTAssertEqual(wrist.lifecycles("completed").count, 1, "S-215 across both processes, one completion")
        XCTAssertFalse(wrist.rating.isPromptOwed, "S-215")
    }

    // MARK: - S-216 / S-217 the phone ended it

    func testS216ThePhonesLifecycleEndingItOwesNoPrompt() async throws {
        let wrist = await RatingHarness(sessionIds: ["s-r-2"]).launch()
        await wrist.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        await wrist.start(at: "2026-09-25T10:00:00Z")
        try await wrist.logSet("e-1", at: "2026-09-25T10:05:00Z")

        wrist.clock.now = instant("2026-09-25T10:21:00Z")
        _ = try await wrist.engine.applyMessage(
            wrist.phoneLifecycle("completed", sessionId: "s-r-2", at: "2026-09-25T10:20:00Z")
        )

        XCTAssertFalse(wrist.rating.isPromptOwed, "S-216 a completion from the phone never owes a prompt")
        XCTAssertFalse(wrist.rating.canEnd, "S-216 there is nothing left for the wrist's End")
        let end = try XCTUnwrap(wrist.events("session_end").first, "S-216 the session end is still sent")
        XCTAssertEqual(end["endedAt"] as? String, "2026-09-25T10:20:00.000Z", "S-216 the lifecycle's `at`")
        XCTAssertTrue(wrist.events("effort_rating").isEmpty, "S-216 no effort_rating")
    }

    func testS217ThePhonesSnapshotEndingItOwesNoPromptAndOneEnd() async throws {
        let wrist = await RatingHarness(sessionIds: ["s-r-3"]).launch()
        await wrist.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        await wrist.start(at: "2026-09-25T10:00:00Z")
        try await wrist.logSet("e-1", at: "2026-09-25T10:05:00Z")
        let logged = try XCTUnwrap(wrist.engine.entries.first?.payload)
        let snapshot: [String: Any] = [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-phone-snap-end",
            "sessionId": "s-r-3",
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-09-25T10:30:00Z",
            "payload": [
                "sessionId": "s-r-3",
                "revision": 0,
                "status": WatchSessionStatus.completed,
                "currentExerciseIndex": 0,
                "exercises": [exercise("sx-bench")],
                "entries": [logged],
                "timers": [String: Any](),
            ] as [String: Any],
        ]

        wrist.clock.now = instant("2026-09-25T10:31:00Z")
        _ = try await wrist.engine.applyMessage(snapshot)
        _ = try await wrist.engine.applyMessage(snapshot)

        XCTAssertFalse(wrist.rating.isPromptOwed, "S-217 a completion from the phone never owes a prompt")
        let ends = wrist.events("session_end")
        XCTAssertEqual(ends.count, 1, "S-217 exactly one session end, though the snapshot came twice")
        XCTAssertEqual(ends.first?["endedAt"] as? String, "2026-09-25T10:30:00.000Z", "S-217 the snapshot's sentAt")
    }

    // MARK: - S-218 the wrist never changes a rating

    func testS218TheWristNeverChangesARating() async throws {
        let wrist = await RatingHarness().launch()
        await wrist.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        try await wrist.loggedSession(
            start: "2026-09-25T10:00:00Z", set: "e-1", logged: "2026-09-25T10:05:00Z", end: "2026-09-25T10:10:00Z"
        )
        wrist.rating.select(4)
        try await wrist.rating.confirm()

        wrist.rating.select(5)
        XCTAssertFalse(wrist.rating.canConfirm, "S-218 nothing is owed any more")
        let second = try await wrist.rating.confirm()
        XCTAssertNil(second, "S-218 a second confirm records nothing")
        let direct = try await wrist.engine.recordEffortRating(5, sessionId: "s-r-1")
        XCTAssertNil(direct, "S-218 nor does the engine's own append path")

        wrist.clock.now = instant("2026-09-25T10:15:00Z")
        _ = try await wrist.engine.applyMessage(
            wrist.phoneLifecycle("started", sessionId: "s-r-1", at: "2026-09-25T10:15:00Z")
        )
        try await wrist.logSet("e-2", at: "2026-09-25T10:16:00Z")
        await wrist.end(at: "2026-09-25T10:20:00Z")

        XCTAssertEqual(wrist.events("effort_rating").map { $0["rating"] as? Int }, [4], "S-218 no new effort_rating")
        XCTAssertEqual(wrist.events("session_end").count, 1, "S-218 no second session end")
        XCTAssertFalse(wrist.rating.isPromptOwed, "S-218 no prompt owed")
    }

    // MARK: - S-219 crown and tap mapping

    func testS219TheCrownAndTheScaleMapToTheseNumbers() async throws {
        let wrist = await RatingHarness().launch()
        await wrist.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        try await wrist.loggedSession(
            start: "2026-09-25T10:00:00Z", set: "e-1", logged: "2026-09-25T10:05:00Z", end: "2026-09-25T10:10:00Z"
        )
        let state = try XCTUnwrap(wrist.rating)
        let detent = WatchMetricStepping.pointsPerDetent

        state.turnCrown(to: -1 * detent)
        XCTAssertNil(state.selected, "S-219 counter-clockwise from nothing picks nothing")
        XCTAssertFalse(state.canConfirm, "S-219 Confirm is disabled before the first selection")

        state.turnCrown(to: 0)
        XCTAssertEqual(state.selected, 1, "S-219 +1 detent from unselected → 1")
        XCTAssertTrue(state.canConfirm, "S-219")

        state.turnCrown(to: 3 * detent)
        XCTAssertEqual(state.selected, 4, "S-219 +3 → 4")

        state.turnCrown(to: 8 * detent)
        XCTAssertEqual(state.selected, 5, "S-219 +5 → 5, clamped")

        state.turnCrown(to: -2 * detent)
        XCTAssertEqual(state.selected, 1, "S-219 −10 → 1, clamped; never back to unselected")
        XCTAssertTrue(state.canConfirm, "S-219 Confirm stays enabled once a number is picked")

        state.turnCrown(to: -1.5 * detent)
        XCTAssertEqual(state.selected, 1, "S-219 half a detent moves nothing")
        state.turnCrown(to: -1 * detent)
        XCTAssertEqual(state.selected, 2, "S-219 the carried half and this one make a detent")

        state.select(3)
        XCTAssertEqual(state.selected, 3, "S-219 tap 3 → 3")
        state.select(6)
        XCTAssertEqual(state.selected, 3, "S-219 a number off the scale is not a choice")
    }

    /// F-7: a continuous crown wraps at the ends of its range, so the device can
    /// report the reading leaving one end and arriving at the other with no
    /// travel in between. That is not a turn. The view asks for a discontinuous
    /// crown, and the state ignores a jump longer than the whole range behind
    /// it — `swift test` cannot build the view, so the rule is proven here.
    func testF7ACrownThatWrappedItsRangeIsNotATurn() async throws {
        let wrist = await RatingHarness().launch()
        await wrist.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        try await wrist.loggedSession(
            start: "2026-09-25T10:00:00Z", set: "e-1", logged: "2026-09-25T10:05:00Z", end: "2026-09-25T10:10:00Z"
        )
        let state = try XCTUnwrap(wrist.rating)
        let detent = WatchMetricStepping.pointsPerDetent
        let end = WatchEffortRatingState.crownRangeDetents * detent

        for step in 1...10 { state.turnCrown(to: Double(step) * detent) }
        XCTAssertEqual(state.selected, 5, "F-7 ten detents clockwise reach 5")

        // A wrap at either end of the scale would be clamped back by the scale
        // itself, so pick a middle number first: the guard, not the clamp, is
        // what holds it (review N3).
        state.select(3)
        state.turnCrown(to: -end)
        XCTAssertEqual(state.selected, 3, "F-7 a wrapped −10 after +10 does not move the picked number")
        state.turnCrown(to: end)
        XCTAssertEqual(state.selected, 3, "F-7 nor a wrapped +10 after −10")

        // The crown did move to the end the wrap reported, so the next turning
        // counts from there: one detent lands on the number below.
        state.turnCrown(to: end - detent)
        XCTAssertEqual(state.selected, 2, "F-7 a turn after a wrap counts from where the crown now is")
    }

    // MARK: - S-220 empty session

    func testS220AnEmptySessionOwesNoPrompt() async throws {
        let wrist = await RatingHarness().launch()
        await wrist.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        await wrist.start(at: "2026-09-25T10:00:00Z")
        await wrist.end(at: "2026-09-25T10:10:00Z")

        XCTAssertFalse(wrist.rating.isPromptOwed, "S-220 nothing was logged, so nothing is asked")
        XCTAssertEqual(wrist.events("session_end").count, 1, "S-220")
    }

    func testS220ASessionWhoseOnlySetThePhoneDeletedOwesNoPrompt() async throws {
        let wrist = await RatingHarness().launch()
        await wrist.sync(true, generatedAt: "2026-09-25T09:00:00Z")
        await wrist.start(at: "2026-09-25T10:00:00Z")
        try await wrist.logSet("e-1", at: "2026-09-25T10:05:00Z")
        _ = try await wrist.engine.applyMessage([
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-chg-delete-e-1",
            "sessionId": "s-r-1",
            "type": "structure_change",
            "origin": "phone",
            "sentAt": "2026-09-25T10:06:00Z",
            "payload": [
                "changeId": "chg-delete-e-1",
                "changes": [["kind": "delete_entry", "entryId": "e-1"]],
            ] as [String: Any],
        ])

        await wrist.end(at: "2026-09-25T10:10:00Z")

        XCTAssertFalse(wrist.rating.isPromptOwed, "S-220 the phone deleted the only set, so nothing is asked")
    }

    // MARK: - The contract and the way out

    func testWhetherANeverSyncedWristAsksIsTheContracts() throws {
        let contract = try Fixtures.effortRatingContract()
        XCTAssertEqual(
            WatchEffortRatingCopy.promptBeforeFirstSync,
            contract["promptBeforeFirstSync"] as? Bool,
            "D-114"
        )
        XCTAssertEqual(
            contract["preferencesField"] as? String,
            "effortRatingPrompt",
            "D-113 the field the wrist reads the setting from"
        )
    }

    /// D-118: once shown, the prompt must be answered. A name or a button that
    /// offers another way out is a build failure here, not a review comment.
    func testTheRatingOffersNoWayOutButAnAnswer() throws {
        let banned = ["skip", "dismiss", "cancel", "close", "later", "not now"]
        let declaration = try NSRegularExpression(pattern: "\\b(?:func|var|let|case)\\s+`?(\\w+)")
        let buttonTitle = try NSRegularExpression(pattern: "Button\\(\\s*\"([^\"]*)\"")
        let buttonLabel = try NSRegularExpression(pattern: "label:\\s*\\{\\s*Text\\(\\s*\"([^\"]*)\"")

        func captures(_ pattern: NSRegularExpression, in source: String) -> [String] {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            return pattern.matches(in: source, range: range).compactMap { match in
                Range(match.range(at: 1), in: source).map { String(source[$0]) }
            }
        }

        var labelsSeen = 0
        for file in ["WatchEffortRating.swift", "WatchEffortRatingView.swift"] {
            let source = try String(
                contentsOf: Fixtures.sourcesRoot.appendingPathComponent(file),
                encoding: .utf8
            )
            let names = captures(declaration, in: source)
            let labels = captures(buttonTitle, in: source) + captures(buttonLabel, in: source)
            XCTAssertFalse(names.isEmpty, "\(file): the scan found no declarations — it is not looking")
            labelsSeen += labels.count

            for name in names {
                let spoken = name.lowercased()
                for word in banned where spoken.hasPrefix(word.replacingOccurrences(of: " ", with: "")) {
                    XCTFail("S-211 \(file) declares `\(name)`: the prompt offers no way out but an answer (D-118)")
                }
            }
            for label in labels {
                let spoken = label.lowercased().trimmingCharacters(in: .whitespaces)
                for word in banned where spoken.hasPrefix(word) {
                    XCTFail("S-211 \(file) has a \"\(label)\" button: the prompt offers no way out but an answer (D-118)")
                }
            }
        }
        XCTAssertGreaterThan(labelsSeen, 0, "the scan found no button labels — it is not looking")
    }
}
