//
//  WatchWorkoutSummaryTests.swift
//  WatchSessionEngineTests
//
//  S-9601 to S-9607 of
//  `docs/plans/2026-10-23-66a-wrist-workout-summary-and-skip-plan/
//  2026-10-23-66a-wrist-workout-summary-and-skip-plan.md`: the numbers the
//  wrist's end-of-workout summary shows (D-1), and the state that owes it to
//  a workout this process saw end (D-2).
//
//  The harness is the rating tests' shape: one engine over an in-memory
//  store, session ids handed out from a queue, and a clock the test drives.
//

import Combine
import XCTest

@testable import WatchSessionEngine

/// A wrist with its engine over one store and a controllable clock, without
/// the rating state the `RatingHarness` carries.
final class SummaryHarness {
    let clock: TestClock
    let store: WatchSessionStore
    private(set) var engine: WatchSessionEngine!

    private var sessionIds: [String]
    private var recordIds = 0

    init(sessionIds: [String], store: WatchSessionStore = InMemoryWatchSessionStore()) {
        clock = TestClock(testInstant())
        self.sessionIds = sessionIds
        self.store = store
    }

    func launch() async -> SummaryHarness {
        engine = WatchSessionEngine(
            store: store,
            onEmit: { _ in },
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
        await engine.restore()
        return self
    }

    func start(at time: String) async -> WatchSessionRecord {
        clock.now = instant(time)
        return await engine.createSession(modality: nil, exercises: [exercise("sx-bench")])
    }

    func logSet(_ entryId: String, at time: String) async throws {
        clock.now = instant(time)
        _ = try await engine.appendObservation(setEvent(clock, entryId: entryId))
    }

    /// A schema-conformant `timed` observation over the bench slot, the way
    /// the timed surface logs one: the window it spanned, not a value row.
    func logTimed(
        _ entryId: String,
        at time: String,
        from start: String,
        to end: String
    ) async throws {
        clock.now = instant(time)
        _ = try await engine.appendObservation([
            "entryId": entryId,
            "eventId": entryId,
            "kind": "timed",
            "loggedAt": utcIso(clock.now),
            "sessionExerciseId": "sx-bench",
            "exerciseId": "ex-sx-bench",
            "startedAt": utcIso(instant(start)),
            "endedAt": utcIso(instant(end)),
        ])
    }

    func finish(at time: String) async -> WatchSessionRecord {
        clock.now = instant(time)
        return await engine.finishSession()
    }
}

final class WatchWorkoutSummaryTests: XCTestCase {

    /// A summary built by hand, for the arithmetic the rows show.
    private func summary(
        startedAt: Date,
        endedAt: Date,
        effortCount: Int,
        allSets: Bool,
        averageBpm: Int?
    ) -> WatchWorkoutSummary {
        WatchWorkoutSummary(
            sessionId: "s-sum",
            startedAt: startedAt,
            endedAt: endedAt,
            effortCount: effortCount,
            allSets: allSets,
            averageBpm: averageBpm
        )
    }

    /// A workout seen active, one set logged, finished — the shape most
    /// scenarios start from.
    private func finishedWorkout(
        _ sessionIds: [String] = ["s-sum-1"]
    ) async throws -> (wrist: SummaryHarness, summary: WatchWorkoutSummaryState) {
        let wrist = await SummaryHarness(sessionIds: sessionIds).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        return (wrist, summary)
    }

    // MARK: - S-9601 the duration text

    func testS9601DurationTextReadsMinutesUnderAnHourAndHoursFromOne() {
        XCTAssertEqual(WatchWorkoutSummary.durationText(0), "0:00")
        XCTAssertEqual(WatchWorkoutSummary.durationText(59), "0:59")
        XCTAssertEqual(WatchWorkoutSummary.durationText(754), "12:34")
        XCTAssertEqual(WatchWorkoutSummary.durationText(3599), "59:59")
        XCTAssertEqual(WatchWorkoutSummary.durationText(3600), "1:00:00")
        XCTAssertEqual(WatchWorkoutSummary.durationText(3725), "1:02:05")
        XCTAssertEqual(WatchWorkoutSummary.durationText(-5), "0:00")
    }

    // MARK: - S-9602 the rows

    func testS9602RowsShowTimeSetsAndTheAverageHeartRate() {
        let at = testInstant()
        let rows = summary(
            startedAt: at,
            endedAt: at.addingTimeInterval(754),
            effortCount: 3,
            allSets: true,
            averageBpm: 130
        ).rows
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].label, WatchWorkoutSummaryCopy.time)
        XCTAssertEqual(rows[0].value, "12:34")
        XCTAssertEqual(rows[1].label, WatchWorkoutSummaryCopy.sets)
        XCTAssertEqual(rows[1].value, "3")
        XCTAssertEqual(rows[2].label, WatchWorkoutSummaryCopy.avgHeartRate)
        XCTAssertEqual(rows[2].value, "130 bpm")
    }

    func testS9602AMixOfEffortsIsCountedUnderEffortsNotSets() {
        let at = testInstant()
        let rows = summary(
            startedAt: at,
            endedAt: at.addingTimeInterval(754),
            effortCount: 2,
            allSets: false,
            averageBpm: nil
        ).rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].label, WatchWorkoutSummaryCopy.efforts)
        XCTAssertEqual(rows[1].value, "2")
    }

    func testS9602AWorkoutWithNoHeartRateShowsExactlyTwoRows() {
        let at = testInstant()
        let rows = summary(
            startedAt: at,
            endedAt: at.addingTimeInterval(754),
            effortCount: 3,
            allSets: true,
            averageBpm: nil
        ).rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertFalse(rows.contains { $0.label == WatchWorkoutSummaryCopy.avgHeartRate })
    }

    // MARK: - S-9602 b the label comes from the workout `note` saw, not a guess

    func testS9602bAMixedWorkoutBuildsAnEffortsSummary() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        try await wrist.logTimed(
            "e-2", at: "2026-09-25T10:04:00Z",
            from: "2026-09-25T10:03:00Z", to: "2026-09-25T10:04:00Z"
        )
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        summary.note(wrist.engine.session)

        let pending = try XCTUnwrap(summary.pending, "S-9602 b the mixed workout owes its summary")
        XCTAssertFalse(pending.allSets, "S-9602 b a set and a timed effort are not all sets")
        XCTAssertEqual(pending.effortCount, 2, "S-9602 b both efforts are counted")
        XCTAssertEqual(
            Array(pending.rows.map(\.label).prefix(2)),
            [WatchWorkoutSummaryCopy.time, WatchWorkoutSummaryCopy.efforts],
            "S-9602 b the mixed workout's count is labelled Efforts, not Sets"
        )
    }

    func testS9602bAnAllSetsWorkoutLabelsItsCountSets() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        try await wrist.logSet("e-2", at: "2026-09-25T10:04:00Z")
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        summary.note(wrist.engine.session)

        let pending = try XCTUnwrap(summary.pending, "S-9602 b the all-sets workout owes its summary")
        XCTAssertTrue(pending.allSets, "S-9602 b every effort a set is all sets")
        XCTAssertEqual(pending.rows[1].label, WatchWorkoutSummaryCopy.sets)
    }

    // MARK: - S-9603 note() builds the summary

    func testS9603NoteBuildsTheSummaryForAWorkoutItSawActive() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        let live = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        try await wrist.logSet("e-2", at: "2026-09-25T10:04:00Z")
        _ = try await wrist.engine.logNutrition(foodId: "food-banana", servings: 1)
        let ended = await wrist.finish(at: "2026-09-25T10:12:34Z")
        summary.note(wrist.engine.session)

        let pending = try XCTUnwrap(summary.pending, "S-9603 the finished workout owes its summary")
        XCTAssertEqual(pending.sessionId, live.sessionId)
        XCTAssertEqual(pending.effortCount, 2, "S-9603 the nutrition log is not an effort")
        XCTAssertEqual(pending.startedAt, live.startedAt)
        XCTAssertEqual(pending.endedAt, ended.recordedAt, "S-9603 the end is the completed row's instant")
        XCTAssertEqual(pending.endedAt, wrist.clock.now)
        XCTAssertTrue(pending.allSets)
        XCTAssertEqual(pending.rows[1].label, WatchWorkoutSummaryCopy.sets)
    }

    // MARK: - S-9604 the average heart rate

    func testS9604TheAverageHeartRateCoversOnlyTheWorkoutWindow() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        _ = await wrist.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: 200,
            recordedAt: instant("2026-09-25T09:55:00Z")
        )
        _ = await wrist.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: 120,
            recordedAt: instant("2026-09-25T10:02:00Z")
        )
        _ = await wrist.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: 130,
            recordedAt: instant("2026-09-25T10:04:00Z")
        )
        _ = await wrist.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: 140,
            recordedAt: instant("2026-09-25T10:06:00Z")
        )
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        summary.note(wrist.engine.session)
        XCTAssertEqual(
            summary.pending?.averageBpm,
            130,
            "S-9604 the reading before the start is not the workout's"
        )
    }

    func testS9604TheAverageHeartRateRoundsToTheNearestBeat() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        _ = await wrist.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: 129,
            recordedAt: instant("2026-09-25T10:02:00Z")
        )
        _ = await wrist.engine.appendSensorSample(
            kind: WatchSensorKind.heartRate,
            value: 130,
            recordedAt: instant("2026-09-25T10:04:00Z")
        )
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        summary.note(wrist.engine.session)
        XCTAssertEqual(summary.pending?.averageBpm, 130, "S-9604 129.5 rounds to 130")
    }

    func testS9604AWorkoutWithNoHeartRateCarriesNoAverage() async throws {
        let (wrist, summary) = try await finishedWorkout()
        summary.note(wrist.engine.session)
        let pending = try XCTUnwrap(summary.pending)
        XCTAssertNil(pending.averageBpm, "S-9604 absence is nil, never zero")
        XCTAssertEqual(pending.rows.count, 2)
    }

    // MARK: - S-9605 the gates, one test each

    func testS9605AWorkoutCompletedBeforeThisProcessRanOwesNothing() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1"]).launch()
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        // Built after the end — a relaunch.
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        summary.note(wrist.engine.session)
        XCTAssertNil(summary.pending, "S-9605 a) the summary is for a workout you saw end")
    }

    func testS9605AWorkoutWithNoEffortOwesNothing() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        summary.note(wrist.engine.session)
        XCTAssertNil(summary.pending, "S-9605 b) nothing logged, nothing shown")
    }

    func testS9605AnAbandonedWorkoutOwesNothing() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        wrist.clock.now = instant("2026-09-25T10:12:34Z")
        _ = await wrist.engine.abandonSession()
        summary.note(wrist.engine.session)
        XCTAssertNil(summary.pending, "S-9605 c) an abandoned workout is not a done workout")
    }

    func testS9605ACompletedWorkoutIsSummarisedOnce() async throws {
        let (wrist, summary) = try await finishedWorkout()
        summary.note(wrist.engine.session)
        let first = try XCTUnwrap(summary.pending)
        var publications = 0
        var cancellables: Set<AnyCancellable> = []
        summary.objectWillChange.sink { _ in publications += 1 }.store(in: &cancellables)
        summary.note(wrist.engine.session)
        XCTAssertEqual(publications, 0, "S-9605 d) the same completed row is not summarised again")
        XCTAssertEqual(summary.pending, first)
        withExtendedLifetime(cancellables) {}
    }

    func testS9605ACompletedWorkoutOfAnotherSessionOwesNothing() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1", "s-sum-2"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        // A's completed row is never noted; B starts and ends in its place.
        _ = await wrist.start(at: "2026-09-25T11:00:00Z")
        try await wrist.logSet("e-2", at: "2026-09-25T11:02:00Z")
        _ = await wrist.finish(at: "2026-09-25T11:12:34Z")
        summary.note(wrist.engine.session)
        XCTAssertNil(summary.pending, "S-9605 e) the workout seen active is A, not B")
    }

    func testS9605fANoteForASessionTheEngineIsNotOnBuildsNothing() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1", "s-sum-2"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        let completedA = try XCTUnwrap(wrist.engine.session)
        // B starts on the same engine — the harness's queue gives B its id —
        // and logs its own effort, so a stale note of A would have something
        // to build from if the engine's session were not checked.
        _ = await wrist.start(at: "2026-09-25T11:00:00Z")
        try await wrist.logSet("e-2", at: "2026-09-25T11:02:00Z")
        summary.note(completedA)
        XCTAssertNil(
            summary.pending,
            "S-9605 f) the engine is on B now; A's completed row builds nothing"
        )
    }

    // MARK: - S-9606 a new workout gives way

    func testS9606ANewWorkoutTakesThePendingSummaryAway() async throws {
        let wrist = await SummaryHarness(sessionIds: ["s-sum-1", "s-sum-2"]).launch()
        let summary = WatchWorkoutSummaryState(engine: wrist.engine)
        _ = await wrist.start(at: "2026-09-25T10:00:00Z")
        summary.note(wrist.engine.session)
        try await wrist.logSet("e-1", at: "2026-09-25T10:02:00Z")
        _ = await wrist.finish(at: "2026-09-25T10:12:34Z")
        summary.note(wrist.engine.session)
        XCTAssertNotNil(summary.pending)
        _ = await wrist.start(at: "2026-09-25T11:00:00Z")
        summary.note(wrist.engine.session)
        XCTAssertNil(summary.pending, "S-9606 the new workout gives way")
    }

    // MARK: - S-9607 dismiss and publication

    func testS9607DismissEmptiesThePendingSummaryAndBothChangesArePublished() async throws {
        let (wrist, summary) = try await finishedWorkout()
        let changed = expectation(description: "S-9607 the summary is published on build and on dismiss")
        changed.assertForOverFulfill = false
        changed.expectedFulfillmentCount = 2
        var cancellables: Set<AnyCancellable> = []
        summary.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in changed.fulfill() }
            .store(in: &cancellables)

        summary.note(wrist.engine.session)
        XCTAssertNotNil(summary.pending)
        summary.dismissPending()
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertNil(summary.pending, "S-9607 Done empties the summary")
        withExtendedLifetime(cancellables) {}
    }
}
