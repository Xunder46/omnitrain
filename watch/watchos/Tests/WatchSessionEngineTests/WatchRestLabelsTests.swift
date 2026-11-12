//
//  WatchRestLabelsTests.swift
//  WatchSessionEngineTests
//
//  Plan 51b (the rest screen says what you just did and what comes next),
//  scenarios S-7601..S-7608 and S-7610 of
//  `docs/plans/2026-10-21-51b-wrist-rest-now-next-plan/2026-10-21-51b-wrist-rest-now-next-plan.md`
//  against the pure function, and S-7609 through the real engine and
//  `WatchLoggingState`. Plan 79 (D-6) adds S-9101..S-9107: the slot id the
//  announced exercise's line carries.
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

    // MARK: - S-14920 the wrist counts each kind against its own plan

    /// S-14920's fixture: A "Plank" plans 3 holds, B "Wall Sit" plans 2, and C is
    /// a planned set. Neither drill declares a kind: they resolve to a drill from
    /// their capabilities, as a phone-projected slot does (D-14910).
    private var plannedHoldLadder: [[String: Any]] {
        [
            slot("A", "Plank", capabilities: ["hold", "time"], plannedEfforts: 3),
            slot("B", "Wall Sit", capabilities: ["hold", "time"], plannedEfforts: 2),
            slot("C", "Bench", planned: 2),
        ]
    }

    func testS14920APlannedHoldStaysUntilItsPlanThenNamesTheNext() {
        let first = deriveRestLabels(
            sessionExercises: plannedHoldLadder,
            entries: entries("A", 1, kind: WatchObservationKind.hold),
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(first.now, "Plank", "S-14920 a hold is no numbered set")
        XCTAssertEqual(first.next, "Next: Hold 2 of 3", "S-14920 the plan's next hold")
        XCTAssertNil(first.nextSlotId, "S-14920 the plan is not met, so Next stays")

        let second = deriveRestLabels(
            sessionExercises: plannedHoldLadder,
            entries: entries("A", 2, kind: WatchObservationKind.hold),
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(second.next, "Next: Hold 3 of 3", "S-14920 the last hold of the plan")
        XCTAssertNil(second.nextSlotId)

        let third = deriveRestLabels(
            sessionExercises: plannedHoldLadder,
            entries: entries("A", 3, kind: WatchObservationKind.hold),
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(third.now, "Plank", "S-14920 the name alone is the now line")
        XCTAssertEqual(
            third.next,
            "Next: Wall Sit · Hold 1 of 2",
            "S-14920 the plan met, the line names the next not-done exercise with its own count"
        )
        XCTAssertEqual(third.nextSlotId, "B", "S-14920 and the id Next moves to")
    }

    // MARK: - S-14921 a planned round moves on when its plan is met

    func testS14921APlannedRoundStaysWithItsCountAndMovesWhenMet() {
        let ladder = [
            slot("A", "Sports Drill", effortKind: WatchEffortKind.round, plannedEfforts: 3),
            slot("B", "Bench", planned: 2),
        ]

        let first = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("A", 1, kind: WatchObservationKind.round),
            currentIndex: 0,
            effortKind: WatchEffortKind.round,
            nextRound: nil,
            roundNoun: "Period"
        )
        XCTAssertEqual(
            first.next,
            "Next: Period 2 of 3",
            "S-14921 a planned round is not today's unbounded period line"
        )
        XCTAssertNil(first.nextSlotId, "S-14921 the plan is not met, so the round stays")

        let second = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("A", 2, kind: WatchObservationKind.round),
            currentIndex: 0,
            effortKind: WatchEffortKind.round,
            nextRound: nil,
            roundNoun: "Period"
        )
        XCTAssertEqual(second.next, "Next: Period 3 of 3", "S-14921 the last period of the plan")
        XCTAssertNil(second.nextSlotId)

        let third = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("A", 3, kind: WatchObservationKind.round),
            currentIndex: 0,
            effortKind: WatchEffortKind.round,
            nextRound: nil,
            roundNoun: "Period"
        )
        XCTAssertEqual(
            third.next,
            "Next: Bench · Set 1 of 2",
            "S-14921 the plan met, the planned round moves on like every other kind"
        )
        XCTAssertEqual(third.nextSlotId, "B")
    }

    // MARK: - S-14922 a planned timed effort counts its intervals

    func testS14922APlannedTimedEffortStaysWithItsIntervalCount() {
        let ladder = [
            slot("A", "Row Intervals", effortKind: WatchEffortKind.timed, plannedEfforts: 3),
            slot("B", "Plank", capabilities: ["hold", "time"], plannedEfforts: 1),
        ]

        let first = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("A", 1, kind: WatchObservationKind.timed),
            currentIndex: 0,
            effortKind: WatchEffortKind.timed,
            nextRound: nil
        )
        XCTAssertEqual(first.next, "Next: Interval 2 of 3", "S-14922 a timed kind's own word")
        XCTAssertNil(first.nextSlotId)

        let second = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("A", 2, kind: WatchObservationKind.timed),
            currentIndex: 0,
            effortKind: WatchEffortKind.timed,
            nextRound: nil
        )
        XCTAssertEqual(second.next, "Next: Interval 3 of 3")
        XCTAssertNil(second.nextSlotId)

        let third = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("A", 3, kind: WatchObservationKind.timed),
            currentIndex: 0,
            effortKind: WatchEffortKind.timed,
            nextRound: nil
        )
        XCTAssertEqual(
            third.next,
            "Next: Plank · Hold 1 of 1",
            "S-14922 the later planned hold is announced with its own count"
        )
        XCTAssertEqual(third.nextSlotId, "B")
    }

    // MARK: - S-14923 the mirrored ignore gates

    func testS14923ASetSlotIgnoresPlannedEfforts() {
        // A hand-built slot carrying both keys: the phone never sends both
        // (D-14901), and the set rule alone must apply.
        var both = slot("A", "Bench", planned: 2)
        both["plannedEfforts"] = 3

        let labels = deriveRestLabels(
            sessionExercises: [both],
            entries: entries("A", 1),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(labels.now, "Bench · Set 1 done")
        XCTAssertEqual(
            labels.next,
            "Next: Set 2 of 2",
            "S-14923 plannedEfforts never becomes a set slot's count"
        )
        XCTAssertNil(labels.nextSlotId, "S-14923 the set rule keeps the exercise")
    }

    func testS14923ADrillSlotIgnoresPlannedSets() {
        let ladder = [
            slot(
                "A", "Plank", planned: 2,
                capabilities: ["hold", "time"]
            ),
            slot("B", "Wall Sit", capabilities: ["hold", "time"]),
        ]
        let labels = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("A", 1, kind: WatchObservationKind.hold),
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(
            labels.next,
            "Next: Wall Sit",
            "S-14923 a drill reads no plannedSets: its one hold is done and the line moves"
        )
        XCTAssertEqual(labels.nextSlotId, "B")
        XCTAssertFalse(labels.next.contains("Set"), "S-14923 a non-set slot never reads Set")
    }

    // MARK: - S-14924 a fourth hold is accepted

    func testS14924AFourthHoldIsAcceptedAndNeverReadsPastItsPlan() {
        let labels = deriveRestLabels(
            sessionExercises: plannedHoldLadder,
            entries: entries("A", 4, kind: WatchObservationKind.hold),
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(labels.now, "Plank")
        XCTAssertEqual(
            labels.next,
            "Next: Wall Sit · Hold 1 of 2",
            "S-14924 4 is at least the plan of 3, so the line moves on"
        )
        XCTAssertEqual(labels.nextSlotId, "B")
        XCTAssertFalse(labels.next.contains("4 of 3"), "S-14924 no count ever prints past its plan")
    }

    // MARK: - S-14925 out-of-order counting keys on the slot id

    func testS14925OutOfOrderCountingKeysOnTheSlotId() {
        let ladder = [
            slot("A", "Alpha", capabilities: ["hold", "time"], plannedEfforts: 2),
            slot("B", "Bravo", capabilities: ["hold", "time"], plannedEfforts: 2),
            slot("C", "Charlie", capabilities: ["hold", "time"], plannedEfforts: 2),
        ]
        // C logged first, then A: C's hold must not complete A's plan.
        let outOfOrder = entries("C", 1, kind: WatchObservationKind.hold)
            + entries("A", 1, kind: WatchObservationKind.hold)

        let onA = deriveRestLabels(
            sessionExercises: ladder,
            entries: outOfOrder,
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(onA.next, "Next: Hold 2 of 2", "S-14925 A's own count is one hold")
        XCTAssertNil(onA.nextSlotId)

        let aDone = entries("C", 1, kind: WatchObservationKind.hold)
            + entries("A", 2, kind: WatchObservationKind.hold)
        let afterA = deriveRestLabels(
            sessionExercises: ladder,
            entries: aDone,
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(
            afterA.next,
            "Next: Bravo · Hold 1 of 2",
            "S-14925 B's own logged count is zero, so k is 1"
        )
        XCTAssertEqual(afterA.nextSlotId, "B")

        let bDone = aDone + entries("B", 2, kind: WatchObservationKind.hold)
        let onB = deriveRestLabels(
            sessionExercises: ladder,
            entries: bDone,
            currentIndex: 1,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(
            onB.next,
            "Next: Charlie · Hold 2 of 2",
            "S-14925 C's own entry is the count the line shows"
        )
        XCTAssertEqual(onB.nextSlotId, "C")
    }

    // MARK: - S-14926 no planned amount keeps today's rule

    func testS14926NoPlannedAmountKeepsTodaysRule() {
        let ladder = [
            slot("A", "Plank", capabilities: ["hold", "time"]),
            slot("B", "Squat"),
        ]

        let holdDone = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("A", 1, kind: WatchObservationKind.hold),
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(holdDone.now, "Plank")
        XCTAssertEqual(
            holdDone.next,
            "Next: Squat",
            "S-14926 an unplanned hold is done after one effort, so the line moves"
        )
        XCTAssertEqual(holdDone.nextSlotId, "B")

        let freeSet = deriveRestLabels(
            sessionExercises: ladder,
            entries: entries("A", 1, kind: WatchObservationKind.hold) + entries("B", 1),
            currentIndex: 1,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(freeSet.now, "Squat · Set 1 done")
        XCTAssertEqual(freeSet.next, "Next: Set 2", "S-14926 an unplanned set keeps the bare stay line")
        XCTAssertNil(freeSet.nextSlotId)
    }

    // MARK: - S-14928 a plan of one is the one-effort rule

    func testS14928APlanOfOneBehavesAsTheOneEffortRule() {
        let planned = [
            slot("A1", "Plank", capabilities: ["hold", "time"], plannedEfforts: 1),
            slot("B1", "Wall Sit", capabilities: ["hold", "time"]),
        ]
        let unplanned = [
            slot("A1", "Plank", capabilities: ["hold", "time"]),
            slot("B1", "Wall Sit", capabilities: ["hold", "time"]),
        ]
        let oneHold = entries("A1", 1, kind: WatchObservationKind.hold)

        let withPlan = deriveRestLabels(
            sessionExercises: planned,
            entries: oneHold,
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        let withoutPlan = deriveRestLabels(
            sessionExercises: unplanned,
            entries: oneHold,
            currentIndex: 0,
            effortKind: WatchEffortKind.drill,
            nextRound: nil
        )
        XCTAssertEqual(
            withPlan,
            withoutPlan,
            "S-14928 a plan of one is the one-effort rule in effect"
        )
        XCTAssertEqual(withPlan.next, "Next: Wall Sit")
        XCTAssertEqual(withPlan.nextSlotId, "B1")
    }

    // MARK: - S-9101 the announced exercise carries its slot id (plan 79, D-6)

    /// The plan's fixture ladder: A "Squat" planned 2, B "Bench" planned 3,
    /// C "Row" planned 0 (S-9101..S-9107).
    private func restLadder(aPlanned: Int = 2) -> [[String: Any]] {
        [
            slot("A", "Squat", planned: aPlanned),
            slot("B", "Bench", planned: 3),
            slot("C", "Row"),
        ]
    }

    func testS9101TheAnnouncedExerciseCarriesItsSlotId() {
        let labels = deriveRestLabels(
            sessionExercises: restLadder(),
            entries: entries("A", 2),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(labels.now, "Squat · Set 2 done")
        XCTAssertEqual(labels.next, "Next: Bench · Set 1 of 3", "S-9101 the line names B's first set")
        XCTAssertEqual(labels.nextSlotId, "B", "S-9101 the id the menu's jump accepts rides with it")
    }

    // MARK: - S-9102 a set count carries no slot id

    func testS9102ASetCountCarriesNoSlotId() {
        let labels = deriveRestLabels(
            sessionExercises: restLadder(),
            entries: entries("A", 1),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(labels.next, "Next: Set 2 of 2", "S-9102 the line is this exercise's own set count")
        XCTAssertNil(labels.nextSlotId, "S-9102 a set count names no exercise to open")
    }

    // MARK: - S-9103 a planless set count carries no slot id

    func testS9103ASetCountWithoutAPlanCarriesNoSlotId() {
        let labels = deriveRestLabels(
            sessionExercises: restLadder(aPlanned: 0),
            entries: entries("A", 3),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(labels.next, "Next: Set 4", "S-9103 no plan, so no 'of N'")
        XCTAssertNil(labels.nextSlotId, "S-9103 a planless count names no exercise")
    }

    // MARK: - S-9104 nothing planned carries no slot id

    func testS9104NothingPlannedCarriesNoSlotId() {
        let labels = deriveRestLabels(
            sessionExercises: restLadder(),
            entries: entries("A", 2) + entries("B", 3) + entries("C", 1),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(labels.next, WatchRestLabelCopy.nothingNext, "S-9104 the whole ladder is done")
        XCTAssertNil(labels.nextSlotId, "S-9104 and nothing is announced")
    }

    // MARK: - S-9105 a period carries no slot id

    func testS9105APeriodCarriesNoSlotId() {
        let labels = deriveRestLabels(
            sessionExercises: restLadder(),
            entries: entries("A", 1, kind: WatchObservationKind.round),
            currentIndex: 0,
            effortKind: WatchEffortKind.round,
            nextRound: "Period 2"
        )
        XCTAssertEqual(labels.next, "Next: Period 2", "S-9105 the modality's own word")
        XCTAssertNil(labels.nextSlotId, "S-9105 a period is not an exercise to open")
    }

    // MARK: - S-9106 a timed effort announces the exercise, and the wrap holds

    func testS9106ATimedEffortAnnouncesTheExerciseAndTheWrapHolds() {
        let timed = entries("A", 1, kind: WatchObservationKind.timed)

        let forward = deriveRestLabels(
            sessionExercises: restLadder(),
            entries: timed,
            currentIndex: 0,
            effortKind: WatchEffortKind.timed,
            nextRound: nil
        )
        XCTAssertEqual(forward.next, "Next: Bench · Set 1 of 3", "S-9106 the later unlogged exercise")
        XCTAssertEqual(forward.nextSlotId, "B", "S-9106 the timed effort announces B all the same")

        let wrap = deriveRestLabels(
            sessionExercises: restLadder(),
            entries: timed + entries("C", 1, kind: WatchObservationKind.timed),
            currentIndex: 2,
            effortKind: WatchEffortKind.timed,
            nextRound: nil
        )
        XCTAssertEqual(wrap.next, "Next: Squat · Set 1 of 2", "S-9106 the search wraps to the top")
        XCTAssertEqual(wrap.nextSlotId, "A", "S-9106 and the wrap carries the id too")
    }

    // MARK: - S-9107 a slot without its own id announces the catalog slot id

    func testS9107ASlotWithoutItsOwnIdAnnouncesTheCatalogSlotId() throws {
        var bare = slot("B", "Bench", planned: 3)
        bare.removeValue(forKey: "sessionExerciseId")
        let exercise = try XCTUnwrap(
            WatchCatalogExercise(slot: bare),
            "S-9107 the slot is still a valid exercise"
        )

        let labels = deriveRestLabels(
            sessionExercises: [slot("A", "Squat", planned: 2), bare],
            entries: entries("A", 2),
            currentIndex: 0,
            effortKind: WatchEffortKind.set,
            nextRound: nil
        )
        XCTAssertEqual(labels.next, "Next: Bench · Set 1 of 3", "S-9107 the line reads as always")
        XCTAssertEqual(
            labels.nextSlotId,
            exercise.slotId,
            "S-9107 the announced id is the catalog slot id the menu's jump accepts"
        )
        XCTAssertEqual(
            exercise.slotId,
            "sx-ex-B",
            "S-9107 the derived id, the slot carrying no sessionExerciseId of its own"
        )
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
        effortKind: String? = nil,
        capabilities: [String] = ["sets", "reps", "load"],
        plannedEfforts: Int? = nil
    ) -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": id,
            "exerciseId": "ex-\(id)",
            "name": name,
            "capabilities": capabilities,
        ]
        if planned > 0 {
            slot["plannedSets"] = Array(
                repeating: ["reps": 10, "loadKg": 40] as [String: Any],
                count: planned
            )
        }
        if let effortKind { slot["effortKind"] = effortKind }
        if let plannedEfforts { slot["plannedEfforts"] = plannedEfforts }
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
