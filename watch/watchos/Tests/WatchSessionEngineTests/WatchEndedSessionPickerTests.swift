//
//  WatchEndedSessionPickerTests.swift
//  WatchSessionEngineTests
//
//  Plan 225 — a workout the wrist has ended (discarded or finished) is not the
//  live session the exercise picker builds on. After it ends, with or without a
//  relaunch, a modality tile's picker offers no "in this session" rows, ranks by
//  the tile's modality, and a pick starts a new workout; nothing the picker does
//  writes another row to the ended one (D-22501, D-22502).
//
//  `docs/plans/2026-11-17-225-picker-ignores-an-ended-workout-plan/2026-11-17-225-picker-ignores-an-ended-workout-plan.md`
//

import XCTest

@testable import WatchSessionEngine

final class WatchEndedSessionPickerTests: XCTestCase {
    private enum Ending { case discarded, finished }

    private static let ladder = ["ex-barbell-bench-press", "ex-plank"]

    /// A wrist whose newest workout held Bench Press and Plank, was on Plank, and
    /// then ended. `relaunch` rebuilds the engine and the start paths over the
    /// same store, the way the watch app's relaunch does.
    private func endedWorkout(
        _ ending: Ending,
        relaunch: Bool
    ) async throws -> (WatchStartHarness, WatchSessionRecord) {
        let harness = try await WatchModalityStartFixture.wrist()
        _ = await harness.engine.createSession(modality: "resistance_lifting")
        for exerciseId in Self.ladder {
            let exercise = try WatchModalityStartFixture.exercise(exerciseId, of: harness)
            _ = await harness.paths.addExerciseToSession(exercise)
        }
        let ended: WatchSessionRecord
        switch ending {
        case .discarded: ended = await harness.engine.abandonSession()
        case .finished: ended = await harness.engine.finishSession()
        }
        if relaunch { await harness.launch() }
        XCTAssertEqual(
            harness.engine.session?.recordId,
            ended.recordId,
            "precondition: the engine still reports the ended workout as its session"
        )
        return (harness, ended)
    }

    private func endedRows(_ harness: WatchStartHarness) async -> [WatchSessionRecord] {
        await harness.store.readAll().sessions.filter { $0.status != WatchSessionStatus.active }
    }

    private static let cases: [(Ending, Bool, String)] = [
        (.discarded, false, "discarded"),
        (.discarded, true, "discarded, relaunched"),
        (.finished, false, "finished"),
        (.finished, true, "finished, relaunched"),
    ]

    // MARK: - S-22501 the tile's picker offers no rows from the ended workout

    func testS22501ATileStartOffersNoRowsFromAnEndedWorkout() async throws {
        for (ending, relaunch, label) in Self.cases {
            let (harness, _) = try await endedWorkout(ending, relaunch: relaunch)
            harness.paths.beginModalityStart("cardio_endurance")

            XCTAssertTrue(
                harness.paths.pickerRows.allSatisfy { !$0.isInSession },
                "S-22501 [\(label)] the ended workout's exercises are not offered as in-session rows"
            )
            XCTAssertEqual(
                harness.paths.availablePickerExercises.map(\.exerciseId),
                ["ex-barbell-bench-press", "ex-goblet-squat", "ex-plank"],
                "S-22501 [\(label)] the whole synced list is offered, the ended workout's exercises included"
            )
            XCTAssertEqual(
                harness.paths.listModality,
                "cardio_endurance",
                "S-22501 [\(label)] the list ranks by the tile tapped, not by the ended workout's modality"
            )
        }
    }

    // MARK: - S-22502 a pick starts a new workout and leaves the ended one alone

    func testS22502APickOfAnExerciseTheEndedWorkoutHeldStartsANewOne() async throws {
        for (ending, relaunch, label) in Self.cases {
            let (harness, ended) = try await endedWorkout(ending, relaunch: relaunch)
            let endedBefore = await endedRows(harness)
            harness.paths.beginModalityStart("cardio_endurance")
            let bench = try WatchModalityStartFixture.exercise("ex-barbell-bench-press", of: harness)

            let row = await harness.paths.startModalityWorkout("cardio_endurance", with: bench)

            XCTAssertEqual(row.status, WatchSessionStatus.active, "S-22502 [\(label)] a live workout starts")
            XCTAssertNotEqual(row.recordId, ended.recordId, "S-22502 [\(label)] it is a new row")
            XCTAssertEqual(row.modality, "cardio_endurance", "S-22502 [\(label)] carrying the tile's modality")
            XCTAssertEqual(
                row.exercises.compactMap { $0["exerciseId"] as? String },
                ["ex-barbell-bench-press"],
                "S-22502 [\(label)] holding only the pick"
            )
            let endedAfter = await endedRows(harness)
            XCTAssertEqual(
                endedAfter.map(\.recordId),
                endedBefore.map(\.recordId),
                "S-22502 [\(label)] no row is written to the ended workout"
            )
        }
    }

    // MARK: - S-22503 a picker tap aimed at the ended workout writes nothing

    func testS22503SelectingAnEndedWorkoutsSlotWritesNothing() async throws {
        for (ending, relaunch, label) in Self.cases {
            let (harness, ended) = try await endedWorkout(ending, relaunch: relaunch)
            let slot = try XCTUnwrap(ended.exercises.first)
            let slotId = try XCTUnwrap(slot["sessionExerciseId"] as? String)
            let exercise = try XCTUnwrap(WatchCatalogExercise(slot: slot))
            let rowsBefore = await harness.store.readAll().sessions.count
            let framesBefore = harness.emitted.count

            let moved = await harness.paths.selectExercise(.inSession(slotId: slotId, exercise: exercise))
            let added = await harness.paths.selectExercise(.available(exercise))

            XCTAssertNil(moved, "S-22503 [\(label)] an ended workout's slot is not selected")
            XCTAssertNil(added, "S-22503 [\(label)] an ended workout takes no added exercise")
            let rowsAfter = await harness.store.readAll().sessions.count
            XCTAssertEqual(rowsAfter, rowsBefore, "S-22503 [\(label)] no session row is appended")
            XCTAssertEqual(harness.emitted.count, framesBefore, "S-22503 [\(label)] and the phone is sent nothing")
        }
    }
}
