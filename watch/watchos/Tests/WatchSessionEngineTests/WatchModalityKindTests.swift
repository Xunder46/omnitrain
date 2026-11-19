//
//  WatchModalityKindTests.swift
//  WatchSessionEngineTests
//
//  Plan 206 — the slots the watch creates under a modality declare that
//  modality's effort kind, like the phone's own adds do: the modality start's
//  pick (S-20601, S-20602), a Free workout's slot declares nothing (S-20603),
//  an exercise added to a live modality session declares the modality's kind
//  (S-20604), the screen and the rest labels read the same declared kind
//  (S-20605), the mapping table itself (S-20607), a routine's own slots keep
//  their declared kinds against the Focus (S-20608), and a modality pick over
//  a held session with no modality declares the tapped kind (S-20609).
//
//  `docs/plans/2026-11-15-206-wrist-logging-follows-modality-plan/2026-11-15-206-wrist-logging-follows-modality-plan.md`
//

import XCTest

@testable import WatchSessionEngine

/// A catalog exercise built to the test's own capabilities, unlike any default:
/// the values that decide a kind come from the test, not the fixture's habits.
private func exercise(
    _ id: String,
    _ name: String,
    capabilities: [String],
    roundDurationSecs: Int? = nil
) -> WatchCatalogExercise {
    WatchCatalogExercise(
        exerciseId: id,
        name: name,
        capabilities: capabilities,
        roundDurationSecs: roundDurationSecs
    )
}

/// One observation record for a slot, of `kind`, at a distinct instant — the
/// shape `WatchRestLabelsTests` feeds `deriveRestLabels`.
private func timedEntry(_ slot: String, _ n: Int) -> WatchObservationRecord {
    WatchObservationRecord(
        recordId: "r-\(slot)-timed-\(n)",
        sessionId: "s-watch-1",
        recordedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)),
        kind: "timed",
        payload: [
            "entryId": "e-\(slot)-timed-\(n)",
            "eventId": "e-\(slot)-timed-\(n)",
            "kind": "timed",
            "sessionExerciseId": slot,
            "exerciseId": "ex-\(slot)",
        ]
    )
}

final class WatchModalityKindTests: XCTestCase {

    // MARK: - S-20601 the modality start's pick declares the modality's kind

    func testS20601ACardioPickWithSetsAndTimeDeclaresTimed() async throws {
        let harness = try await WatchModalityStartFixture.wrist()
        let run = exercise(
            "ex-run-walk",
            "Run Walk",
            capabilities: ["sets", "reps", "time"]
        )

        let session = await harness.paths.startModalityWorkout("cardio_endurance", with: run)

        XCTAssertEqual(
            session.exercises.first?["effortKind"] as? String,
            WatchEffortKind.timed,
            "S-20601 the pick's slot declares the Cardio modality's kind, which `sets` would have won"
        )
        XCTAssertEqual(
            harness.surface.effortKind,
            WatchEffortKind.timed,
            "S-20601 the logging surface renders the declared kind"
        )
    }

    // MARK: - S-20602 every modality declares its own kind

    func testS20602EveryModalityDeclaresItsOwnKind() async throws {
        // resistance_lifting over a hold exercise: `set`, not the hold the
        // capabilities would resolve.
        let resistance = try await WatchModalityStartFixture.wrist()
        let hold = exercise(
            "ex-wall-sit",
            "Wall Sit",
            capabilities: ["hold", "time"]
        )
        let resistanceSession = await harnessStart(resistance, "resistance_lifting", hold)
        XCTAssertEqual(
            resistanceSession.exercises.first?["effortKind"] as? String,
            WatchEffortKind.set,
            "S-20602 Resistance declares `set` even for a hold exercise"
        )
        XCTAssertEqual(resistance.surface.effortKind, WatchEffortKind.set)

        // isometric_stretching over a reps exercise: `drill`.
        let isometric = try await WatchModalityStartFixture.wrist()
        let lift = exercise(
            "ex-isometric-lift",
            "Isometric Lift",
            capabilities: ["reps", "sets", "load"]
        )
        let isometricSession = await harnessStart(isometric, "isometric_stretching", lift)
        XCTAssertEqual(
            isometricSession.exercises.first?["effortKind"] as? String,
            WatchEffortKind.drill,
            "S-20602 Isometric declares `drill` even for a reps exercise"
        )
        XCTAssertEqual(isometric.surface.effortKind, WatchEffortKind.drill)

        // sports over a rounds exercise: `round`, and the slot carries the
        // catalog's own length.
        let sports = try await WatchModalityStartFixture.wrist()
        let rally = exercise(
            "ex-rally",
            "Rally Drill",
            capabilities: ["time", "rounds"],
            roundDurationSecs: 247
        )
        let sportsSession = await harnessStart(sports, "sports", rally)
        XCTAssertEqual(
            sportsSession.exercises.first?["effortKind"] as? String,
            WatchEffortKind.round,
            "S-20602 Sports declares `round`"
        )
        XCTAssertEqual(
            sportsSession.exercises.first?[WatchCatalogExercise.roundDurationKey] as? Int,
            247,
            "S-20602 the round slot carries the catalog exercise's own length"
        )
        XCTAssertEqual(sports.surface.effortKind, WatchEffortKind.round)
    }

    /// The modality start each fresh harness runs, so a modality's kind is
    /// decided alone in its own session.
    private func harnessStart(
        _ harness: WatchStartHarness,
        _ modality: String,
        _ exercise: WatchCatalogExercise
    ) async -> WatchSessionRecord {
        await harness.paths.startModalityWorkout(modality, with: exercise)
    }

    // MARK: - S-20603 a Free workout's slot declares nothing

    func testS20603AFreeSessionSlotDeclaresNothing() async throws {
        let harness = WatchStartHarness()
        await harness.launch()
        let add = exercise(
            "ex-plank-variant",
            "Plank Variant",
            capabilities: ["sets", "time"]
        )
        _ = await harness.engine.createSession(modality: nil, exercises: [])

        let session = await harness.paths.addExerciseToEnd(add)

        XCTAssertNil(
            session.exercises.first?["effortKind"],
            "S-20603 a Free workout's slot carries no effortKind key at all"
        )
        XCTAssertEqual(
            harness.surface.effortKind,
            WatchEffortKind.set,
            "S-20603 the surface still resolves the slot from its capabilities"
        )
    }

    // MARK: - S-20604 an exercise added to a modality session declares the modality's kind

    func testS20604AnExerciseAddedToAModalitySessionDeclaresTheModalitysKind() async throws {
        let harness = try await WatchModalityStartFixture.wrist()
        let first = exercise(
            "ex-interval-run",
            "Interval Run",
            capabilities: ["sets", "reps", "time"]
        )
        let added = exercise(
            "ex-heavy-lift",
            "Heavy Lift",
            capabilities: ["reps", "sets", "load"]
        )
        _ = await harness.paths.startModalityWorkout("cardio_endurance", with: first)

        let endAdded = await harness.paths.addExerciseToEnd(added)
        let moveToAdded = await harness.paths.addExerciseToSession(added)

        XCTAssertEqual(
            endAdded.exercises[1]["effortKind"] as? String,
            WatchEffortKind.timed,
            "S-20604 Add Exercise declares the session's modality's kind, which `reps` would have won"
        )
        XCTAssertEqual(
            moveToAdded.exercises[2]["effortKind"] as? String,
            WatchEffortKind.timed,
            "S-20604 a pick over the started workout declares the modality's kind too"
        )
    }

    // MARK: - S-20605 the screen and the rest labels read the same declared kind

    func testS20605TheRestLabelsAndTheScreenReadTheSameDeclaredKind() async throws {
        let harness = try await WatchModalityStartFixture.wrist()
        let first = exercise(
            "ex-interval-run",
            "Interval Run",
            capabilities: ["sets", "reps", "time"]
        )
        let second = exercise(
            "ex-heavy-lift",
            "Heavy Lift",
            capabilities: ["reps", "sets", "load"]
        )
        _ = await harness.paths.startModalityWorkout("cardio_endurance", with: first)
        let both = await harness.paths.addExerciseToEnd(second)

        let slotIds = both.exercises.compactMap { $0["sessionExerciseId"] as? String }
        XCTAssertEqual(slotIds.count, 2, "S-20605 the session holds the picked and the added slot")

        for (index, slotId) in slotIds.enumerated() {
            _ = await harness.engine.selectExercise(slotId: slotId)
            XCTAssertEqual(
                harness.surface.effortKind,
                WatchEffortKind.timed,
                "S-20605 slot \(index) renders the declared kind, not its capabilities"
            )
        }

        // The declared kind is what the rest labels read — `RestLabelSlot.kind`
        // is private to the source, so the label is the observable. A plan is
        // what makes the kind word render at all: the phone sends
        // `plannedEfforts` for a non-set kind, and without the declared kind
        // these capabilities would speak "Set 1 of 2".
        let planned = both.exercises.map { slot -> [String: Any] in
            var slot = slot
            slot["plannedEfforts"] = 2
            return slot
        }

        // The picked slot, one logged timed effort against its plan of two.
        let here = deriveRestLabels(
            sessionExercises: planned,
            entries: [timedEntry(slotIds[0], 1)],
            currentIndex: 0,
            effortKind: WatchEffortKind.timed,
            nextRound: nil
        )
        XCTAssertEqual(
            here.next,
            "Next set: Interval 2 of 2",
            "S-20605 the picked slot's rest line counts the declared timed kind"
        )

        // The added slot: its capabilities alone would speak "Set 1 of 2".
        let next = deriveRestLabels(
            sessionExercises: planned,
            entries: [timedEntry(slotIds[0], 1)],
            currentIndex: 1,
            effortKind: WatchEffortKind.timed,
            nextRound: nil
        )
        XCTAssertEqual(
            next.next,
            "Next set: Interval 1 of 2",
            "S-20605 the added slot speaks the declared timed kind's word"
        )
    }

    // MARK: - S-20607 the mapping table

    func testS20607ForModalityMapsTheFourKeysAndNothingElse() {
        XCTAssertEqual(WatchEffortKind.forModality("cardio_endurance"), WatchEffortKind.timed, "S-20607")
        XCTAssertEqual(WatchEffortKind.forModality("resistance_lifting"), WatchEffortKind.set, "S-20607")
        XCTAssertEqual(WatchEffortKind.forModality("isometric_stretching"), WatchEffortKind.drill, "S-20607")
        XCTAssertEqual(WatchEffortKind.forModality("sports"), WatchEffortKind.round, "S-20607")

        XCTAssertNil(WatchEffortKind.forModality(nil), "S-20607 no modality, no kind")
        XCTAssertNil(WatchEffortKind.forModality(""), "S-20607 an empty key names nothing")
        XCTAssertNil(WatchEffortKind.forModality("strength_resistance"), "S-20607 an unlisted key")
        XCTAssertNil(WatchEffortKind.forModality("curling"), "S-20607 an unlisted key")
    }

    // MARK: - S-20608 a routine's own slots keep their kinds against the Focus

    /// The protocol's Focus fixture: one routine whose Focus is
    /// `isometric_stretching` and whose own effort declares `timed` — while its
    /// capabilities `["time","hold"]` would resolve a hold, which is the
    /// competition the declared kind has to win.
    private func focusFixture() async throws -> WatchStartHarness {
        let harness = WatchStartHarness()
        await harness.launch()
        var message = try Fixtures.json("fixtures/valid/routines_down_focus_modality.json")
        var payload = try XCTUnwrap(message["payload"] as? [String: Any])
        let storedRoutines = try XCTUnwrap(payload["routines"] as? [[String: Any]])
        var routine = try XCTUnwrap(storedRoutines.first)
        var segments = try XCTUnwrap(routine["segments"] as? [[String: Any]])
        var segment = try XCTUnwrap(segments.first)
        var efforts = try XCTUnwrap(segment["efforts"] as? [[String: Any]])
        var effort = try XCTUnwrap(efforts.first)
        effort["capabilities"] = ["time", "hold"]
        efforts[0] = effort
        segment["efforts"] = efforts
        segments[0] = segment
        routine["segments"] = segments
        var routines = storedRoutines
        routines[0] = routine
        payload["routines"] = routines
        message["payload"] = payload
        _ = try await harness.receive(message)
        return harness
    }

    func testS20608ARoutinesOwnSlotKeepsItsKindAndAnAddedOneTakesTheFocus() async throws {
        let harness = try await focusFixture()
        let added = exercise(
            "ex-heavy-lift",
            "Heavy Lift",
            capabilities: ["reps", "sets", "load"]
        )

        let session = try await harness.paths.startFromRoutine("routine-isometric-a")
        XCTAssertEqual(
            session.modality,
            "isometric_stretching",
            "S-20608 the Focus is the session's modality"
        )
        XCTAssertEqual(
            session.exercises.first?["effortKind"] as? String,
            WatchEffortKind.timed,
            "S-20608 the routine's own slot keeps its declared kind over the Focus's"
        )

        let after = await harness.paths.addExerciseToEnd(added)

        XCTAssertEqual(
            after.exercises.last?["effortKind"] as? String,
            WatchEffortKind.drill,
            "S-20608 the added slot takes the Focus's kind, which `sets` would have won"
        )
    }

    // MARK: - S-20609 a modality pick over a held session with no modality

    func testS20609AModalityPickOverAHeldSessionWithNoModalityDeclaresTheTappedKind() async throws {
        let harness = try await WatchModalityStartFixture.wrist()
        let held = await harness.engine.createSession(modality: nil, exercises: [])
        let pick = exercise(
            "ex-run-walk",
            "Run Walk",
            capabilities: ["sets", "reps", "time"]
        )

        let row = await harness.paths.startModalityWorkout("cardio_endurance", with: pick)

        XCTAssertEqual(row.sessionId, held.sessionId, "S-20609 the held session takes the pick")
        XCTAssertEqual(
            row.exercises.first?["effortKind"] as? String,
            WatchEffortKind.timed,
            "S-20609 the added slot declares the tapped modality's kind (D-20606)"
        )
        XCTAssertNil(
            harness.engine.session?.modality,
            "S-20609 the held session's own modality stays unchanged"
        )
    }
}
