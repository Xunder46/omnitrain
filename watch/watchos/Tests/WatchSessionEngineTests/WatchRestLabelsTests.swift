//
//  WatchRestLabelsTests.swift
//  WatchSessionEngineTests
//
//  Plan 51b (the rest screen says what you just did and what comes next),
//  scenarios S-7601..S-7608 and S-7610 of
//  `docs/plans/2026-10-21-51b-wrist-rest-now-next-plan/2026-10-21-51b-wrist-rest-now-next-plan.md`
//  against the pure function, and S-7609 through the real engine and
//  `WatchLoggingState`.
//

import XCTest

@testable import WatchSessionEngine

final class WatchRestLabelsTests: XCTestCase {

    // MARK: - S-7601 the planned set counts the logged sets

    func testS7601APlannedSetCountsTheLoggedSets() {
        let first = deriveRestLabels(
            sessionExercises: [slot("b1", "Bench", planned: 4)],
            entries: entries("b1", 3),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(first.now, "Bench · Set 3 done", "S-7601 the three logged sets are the count")
        XCTAssertEqual(first.next, "Next: Set 4 of 4", "S-7601 the plan of four says which set is next")

        let second = deriveRestLabels(
            sessionExercises: [slot("b1", "Bench", planned: 3)],
            entries: entries("b1", 2),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(second.now, "Bench · Set 2 done")
        XCTAssertEqual(second.next, "Next: Set 3 of 3")
    }

    // MARK: - S-7602 the plan done names the later exercise

    func testS7602ACompletePlanNamesTheLaterExercise() {
        let ladder = [slot("b1", "Bench", planned: 3), slot("s1", "Squat", planned: 2)]

        let first = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("b1", 3),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(
            first.next,
            "Next: Squat · Set 1 of 2",
            "S-7602 the later exercise's own plan names its first set"
        )

        let second = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("b1", 3) + entries("s1", 1),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(
            second.next,
            "Next: Squat · Set 2 of 2",
            "S-7602 the later exercise's own logged set is the count"
        )
    }

    // MARK: - S-7603 the search goes forward first, then from the top

    func testS7603TheForwardSearchWinsThenTheBackwardOne() {
        // (a) the current exercise is done, and both a later and an earlier one
        // are unfinished: the later one is named.
        let three = [
            slot("a1", "A", planned: 2),
            slot("b1", "B", planned: 3),
            slot("c1", "C", planned: 2),
        ]
        let forward = deriveRestLabels(
            sessionExercises: three,
            entries: entries("b1", 3),
            currentIndex: 1,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(forward.now, "B · Set 3 done")
        XCTAssertEqual(
            forward.next,
            "Next: C · Set 1 of 2",
            "S-7603 the later unfinished exercise wins over the earlier one"
        )

        // (b) the current exercise is done and last in the ladder, and only an
        // earlier one is unfinished: the search wraps to the top.
        let two = [slot("a1", "A", planned: 2), slot("b1", "B", planned: 3)]
        let backward = deriveRestLabels(
            sessionExercises: two,
            entries: entries("b1", 3),
            currentIndex: 1,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(
            backward.next,
            "Next: A · Set 1 of 2",
            "S-7603 the earlier unfinished exercise is named when the search wraps"
        )
    }

    // MARK: - S-7604 everything done

    func testS7604EverythingDoneSaysNothingPlannedNext() {
        let labels = deriveRestLabels(
            sessionExercises: [slot("b1", "Bench", planned: 3)],
            entries: entries("b1", 3),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(labels.now, "Bench · Set 3 done")
        XCTAssertEqual(labels.next, WatchRestLabelCopy.nothingNext, "S-7604 the copy's own words")
        XCTAssertEqual(labels.next, "Nothing planned next", "S-7604 the literal the screen shows")
    }

    // MARK: - S-7605 a free set with no plan

    func testS7605AFreeSetCountsPastThePlan() {
        let labels = deriveRestLabels(
            sessionExercises: [slot("b1", "Bench")],
            entries: entries("b1", 4),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(labels.now, "Bench · Set 4 done", "S-7605 the free set's own count")
        XCTAssertEqual(labels.next, "Next: Set 5", "S-7605 no plan, so no 'of N'")
    }

    // MARK: - S-7606 a rest after a jump to an unlogged exercise

    func testS7606AJumpedToExerciseWithNothingLogged() {
        let planned = deriveRestLabels(
            sessionExercises: [slot("b1", "Bench", planned: 3)],
            entries: [],
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(planned.now, "Bench", "S-7606 no set logged, so the name alone")
        XCTAssertEqual(planned.next, "Next: Set 1 of 3", "S-7606 the plan's first set")

        let free = deriveRestLabels(
            sessionExercises: [slot("b1", "Bench")],
            entries: [],
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(free.now, "Bench")
        XCTAssertEqual(free.next, "Next: Set 1", "S-7606 no plan, so no 'of N'")
    }

    // MARK: - S-7607 a round effort names the next period

    func testS7607ARoundEffortNamesTheNextPeriod() {
        let ladder = [
            slot("b1", "Bench", effortKind: WatchEffortKind.round),
            slot("s1", "Squat"),
        ]
        let rounds = entries("b1", 1, kind: WatchObservationKind.round)

        let withRound = deriveRestLabels(
            sessionExercises: ladder,
            entries: rounds,
            currentIndex: 0,
            effortKind: WatchEffortKind.round,
            nextRound: "Period 2"
        )
        XCTAssertEqual(withRound.now, "Bench", "S-7607 a round is no numbered set")
        XCTAssertEqual(withRound.next, "Next: Period 2", "S-7607 the modality's own word")

        let fallsThrough = deriveRestLabels(
            sessionExercises: ladder,
            entries: rounds,
            currentIndex: 0,
            effortKind: WatchEffortKind.round,
            nextRound: nil
        )
        XCTAssertEqual(
            fallsThrough.next,
            "Next: Squat",
            "S-7607 without a next period the exercise search stands in"
        )
    }

    // MARK: - S-7608 a timed effort names the next exercise with work

    func testS7608ATimedEffortNamesTheNextExerciseWithWork() {
        let ladder = [
            slot("b1", "Bench", effortKind: WatchEffortKind.timed),
            slot("s1", "Squat"),
        ]
        let timed = entries("b1", 1, kind: WatchObservationKind.timed)

        let withLater = deriveRestLabels(
            sessionExercises: ladder,
            entries: timed,
            currentIndex: 0,
            effortKind: WatchEffortKind.timed,
            nextRound: nil
        )
        XCTAssertEqual(withLater.now, "Bench", "S-7608 a timed effort is no numbered set")
        XCTAssertEqual(withLater.next, "Next: Squat", "S-7608 the later unlogged exercise")

        let alone = deriveRestLabels(
            sessionExercises: [slot("b1", "Bench", effortKind: WatchEffortKind.timed)],
            entries: timed,
            currentIndex: 0,
            effortKind: WatchEffortKind.timed,
            nextRound: nil
        )
        XCTAssertEqual(
            alone.next,
            WatchRestLabelCopy.nothingNext,
            "S-7608 no other slot, so nothing is planned next"
        )
    }

    // MARK: - S-7603c a plan exactly logged is skipped

    func testS7603cAnExerciseWithItsPlanExactlyLoggedIsSkipped() {
        let ladder = [slot("a1", "A", planned: 2), slot("b1", "B", planned: 3)]
        let labels = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("a1", 2) + entries("b1", 3),
            currentIndex: 1,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(labels.now, "B · Set 3 done")
        XCTAssertEqual(
            labels.next,
            WatchRestLabelCopy.nothingNext,
            "S-7603c A's plan is logged exactly, so it is done and not named"
        )
    }

    // MARK: - S-7611 only set entries count as sets

    func testS7611OnlySetEntriesCountAsSets() {
        let labels = deriveRestLabels(
            sessionExercises: [slot("b1", "Bench", planned: 3)],
            entries: entries("b1", 2) + [entry("b1", kind: "timed", 2)],
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(
            labels.now,
            "Bench · Set 2 done",
            "S-7611 the timed entry is not a set, so the count is two"
        )
        XCTAssertEqual(labels.next, "Next: Set 3 of 3")
    }

    // MARK: - S-7609 through the engine: the phone's set counts

    func testS7609ThroughTheEngineThePhonesSetCounts() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            snapshot(
                messageId: "msg-rest-1",
                exercises: [slot(plannedSets: plannedRows)],
                entries: [
                    setEntry("entry-sx-bench-0", reps: 10, loadKg: 40, loggedAt: "2026-10-15T17:00:00Z")
                ]
            )
        )

        let state = WatchLoggingState(engine: engine, clock: harness.clock.call)

        XCTAssertEqual(
            state.restLabels.now,
            "Bench Press · Set 1 done",
            "S-7609 the phone's entry is a set the wrist holds"
        )
        XCTAssertEqual(state.restLabels.next, "Next: Set 2 of 3")

        harness.clock.advance(120)
        try await state.log()

        XCTAssertEqual(state.restLabels.now, "Bench Press · Set 2 done", "S-7609 the wrist's own set joins")
        XCTAssertEqual(state.restLabels.next, "Next: Set 3 of 3")
    }

    // MARK: - S-7610 the view reads the labels

    func testS7610TheRestViewReadsTheLabels() throws {
        let source = try engineSource("WatchRestView.swift")
        XCTAssertTrue(source.contains("state.restLabels"), "S-7610 the view reads state.restLabels")
        XCTAssertTrue(source.contains("labels.now"), "S-7610 the name line is labels.now")
        XCTAssertTrue(source.contains("labels.next"), "S-7610 the next line is labels.next")
        XCTAssertTrue(source.contains("nextButton"), "S-7610 the Next button stays")
        XCTAssertTrue(
            source.contains("WatchRestSurfaceCopy.restCaption"),
            "S-7610 the Rest caption stays"
        )
        XCTAssertFalse(
            source.contains("exerciseName"),
            "S-7610 the view no longer reads exerciseName"
        )
    }

    // MARK: - Helpers (the pure function's fixtures)

    /// One valid slot of the ladder, as the pure function reads it.
    private func slot(
        _ id: String,
        _ name: String,
        planned: Int = 0,
        effortKind: String? = nil
    ) -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": name,
            "capabilities": ["sets", "reps", "load"],
        ]
        if planned > 0 {
            slot["plannedSets"] = Array(
                repeating: ["reps": 10, "loadKg": 40] as [String: Any],
                count: planned
            )
        }
        if let effortKind { slot["effortKind"] = effortKind }
        return slot
    }

    /// One observation record for a slot, of `kind`, at a distinct instant.
    private func entry(_ slot: String, kind: String = "set", _ n: Int) -> WatchObservationRecord {
        WatchObservationRecord(
            recordId: "r-\(slot)-\(kind)-\(n)",
            sessionId: "s-rest",
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)),
            kind: kind,
            payload: [
                "entryId": "e-\(slot)-\(kind)-\(n)",
                "eventId": "e-\(slot)-\(kind)-\(n)",
                "kind": kind,
                "sessionExerciseId": slot,
                "exerciseId": "ex-\(slot)",
            ]
        )
    }

    /// `count` observations of `kind` for a slot, newest last.
    private func entries(
        _ slot: String,
        _ count: Int,
        kind: String = "set"
    ) -> [WatchObservationRecord] {
        (0..<count).map { entry(slot, kind: kind, $0) }
    }

    // MARK: - Helpers (the engine's fixtures, as WatchPlannedSetsTests arranges them)

    /// Fixture P: the three rows a phone session with three sets of bench holds.
    private var plannedRows: [[String: Any]] {
        [
            ["reps": 10, "loadKg": 40],
            ["reps": 10, "loadKg": 40],
            ["reps": 8, "loadKg": 42.5],
        ]
    }

    private func slot(
        _ id: String = "sx-bench",
        capabilities: [String] = ["sets", "reps", "load"],
        effortKind: String? = nil,
        plannedSets: [[String: Any]]? = nil
    ) -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": id,
            "exerciseId": "ex-bench",
            "name": "Bench Press",
            "capabilities": capabilities,
        ]
        if let effortKind { slot["effortKind"] = effortKind }
        if let plannedSets { slot["plannedSets"] = plannedSets }
        return slot
    }

    private func setEntry(
        _ entryId: String,
        reps: Int,
        loadKg: Double,
        loggedAt: String
    ) -> [String: Any] {
        [
            "entryId": entryId,
            "eventId": entryId,
            "kind": "set",
            "loggedAt": loggedAt,
            "sessionExerciseId": "sx-bench",
            "exerciseId": "ex-bench",
            "reps": reps,
            "loadKg": loadKg,
        ]
    }

    private func snapshot(
        messageId: String,
        revision: Int = 1,
        exercises: [[String: Any]],
        entries: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": messageId,
            "sessionId": "s-planned",
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-10-15T18:00:00Z",
            "payload": [
                "sessionId": "s-planned",
                "revision": revision,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 0,
                "exercises": exercises,
                "entries": entries,
                "timers": [String: Any](),
            ] as [String: Any],
        ]
    }

    // MARK: - Helpers (the source guard, as WatchCrownUnitTests reads views)

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
}
