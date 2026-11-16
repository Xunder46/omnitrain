//
//  WatchModalityStartTests.swift
//  WatchSessionEngineTests
//
//  Plan 176 — the modality grid's start paths, on the governor's amended design:
//  a tap remembers the modality and creates nothing (S-17604), the pick creates
//  one session carrying that modality and the exercise (S-17605), and closing
//  the picker leaves nothing behind (S-17606). D-17608 and D-17609 supersede the
//  empty-session design.
//
//  `docs/plans/2026-11-15-176-watch-modality-start-grid-plan/2026-11-15-176-watch-modality-start-grid-plan.md`
//

import XCTest

@testable import WatchSessionEngine

/// The grid's fixture: a wrist that has synced the protocol's `routines_down`,
/// optionally with a Brisk Walk the phone named `walking` appended to its
/// fallback list (the plan 168 fixture shape) — the exercise S-17607's walking
/// case is about.
enum WatchModalityStartFixture {
    static let briskWalkId = "ex-brisk-walk"

    static func wrist(briskWalk: Bool = false) async throws -> WatchStartHarness {
        let harness = WatchStartHarness()
        await harness.launch()
        var message = try Fixtures.json("fixtures/valid/routines_down.json")
        if briskWalk {
            var payload = try XCTUnwrap(message["payload"] as? [String: Any])
            var fallback = try XCTUnwrap(payload["fallbackExercises"] as? [[String: Any]])
            fallback.append([
                "exerciseId": briskWalkId,
                "name": "Brisk Walk",
                "capabilities": ["time", "distance"],
                "healthActivity": "walking",
            ])
            payload["fallbackExercises"] = fallback
            message["payload"] = payload
        }
        _ = try await harness.receive(message)
        return harness
    }

    static func exercise(_ exerciseId: String, of harness: WatchStartHarness) throws -> WatchCatalogExercise {
        try XCTUnwrap(
            harness.paths.fallbackExercises.first { $0.exerciseId == exerciseId },
            "the synced fallback list carries \(exerciseId)"
        )
    }
}

final class WatchModalityStartTests: XCTestCase {
    private func object(_ value: Any?) throws -> [String: Any] {
        try XCTUnwrap(value as? [String: Any])
    }

    private func sessionRows(_ harness: WatchStartHarness) async -> [WatchSessionRecord] {
        await harness.store.readAll().sessions
    }

    // MARK: - S-17604 a tap remembers the modality and creates nothing

    func testS17604ATapRemembersItsModalityAndCreatesNothing() async throws {
        for cell in WatchModalityStart.cells {
            let harness = try await WatchModalityStartFixture.wrist()

            harness.paths.beginModalityStart(cell.key)

            XCTAssertEqual(
                harness.paths.pendingModalityStart,
                cell.key,
                "S-17604 the picker now collects \(cell.label)'s first exercise"
            )
            XCTAssertNil(
                harness.engine.session,
                "S-17604 \(cell.label)'s tap starts no session (D-17608)"
            )
            let rows = await sessionRows(harness)
            XCTAssertTrue(rows.isEmpty, "S-17604 and appends no row")
            XCTAssertTrue(
                harness.emitted.isEmpty,
                "S-17604 and sends the phone nothing: no frame at all"
            )
        }
    }

    func testS17604FourTapsInARowLeaveNoTrace() async throws {
        let harness = try await WatchModalityStartFixture.wrist()

        for cell in WatchModalityStart.cells {
            harness.paths.beginModalityStart(cell.key)
        }

        XCTAssertEqual(
            harness.paths.pendingModalityStart,
            WatchModalityStart.cells.last?.key,
            "S-17604 the last cell tapped is the one the picker collects for"
        )
        XCTAssertNil(harness.engine.session, "S-17604 four taps, no session")
        let rows = await sessionRows(harness)
        XCTAssertTrue(rows.isEmpty, "S-17604 four taps, no row")
        XCTAssertTrue(harness.emitted.isEmpty, "S-17604 four taps, no frame")
    }

    // MARK: - S-17608 the start-mode picker lists what the Free workout's did

    func testS17608TheStartModePickerOffersTheWholeListTheFreeWorkoutOffered() async throws {
        let startMode = try await WatchModalityStartFixture.wrist()
        startMode.paths.beginModalityStart("cardio_endurance")
        let offered = startMode.paths.availablePickerExercises.map(\.exerciseId)

        let free = try await WatchModalityStartFixture.wrist()
        _ = await free.paths.startFreeWorkout()
        let freeOffered = free.paths.availablePickerExercises.map(\.exerciseId)

        XCTAssertEqual(
            offered,
            freeOffered,
            "S-17608 the grid's picker offers exactly the list the Free workout's picker offered"
        )
        XCTAssertEqual(
            offered,
            ["ex-barbell-bench-press", "ex-goblet-squat", "ex-plank"],
            "S-17608 the whole synced fallback list, A to Z — no modality filters it"
        )
        XCTAssertTrue(
            startMode.paths.pickerRows.allSatisfy { !$0.isInSession },
            "S-17608 and nothing is on the ladder yet: the tap created no session"
        )
    }

    // MARK: - S-17605 the pick creates one session with the modality and the exercise

    func testS17605ThePickCreatesOneSessionWithTheModalityAndTheExercise() async throws {
        let harness = try await WatchModalityStartFixture.wrist()
        let plank = try WatchModalityStartFixture.exercise("ex-plank", of: harness)
        harness.paths.beginModalityStart("resistance_lifting")

        let session = await harness.paths.startModalityWorkout("resistance_lifting", with: plank)

        XCTAssertEqual(session.status, WatchSessionStatus.active, "S-17605 the pick starts a live session")
        XCTAssertEqual(
            session.modality,
            "resistance_lifting",
            "S-17605 the tapped modality is the session's own"
        )
        XCTAssertEqual(session.source, "watch", "S-17605 the wrist starts its own session")
        XCTAssertEqual(session.exercises.count, 1, "S-17605 one session, holding the one exercise picked")
        XCTAssertEqual(session.exercises.first?["exerciseId"] as? String, "ex-plank")
        XCTAssertEqual(
            session.currentExerciseIndex,
            0,
            "S-17605 choosing is a request to do it, so the session is on the pick"
        )
        let slotId = try XCTUnwrap(session.exercises.first?["sessionExerciseId"] as? String)
        XCTAssertTrue(
            slotId.hasPrefix("sx-ex-plank~"),
            "S-17605 the slot carries the session token the other starts mint (plan 81 D-1): \(slotId)"
        )
        XCTAssertNil(harness.paths.pendingModalityStart, "S-17605 the pick ends the start mode")

        let rows = await sessionRows(harness)
        XCTAssertEqual(rows.count, 1, "S-17605 one session row, not an empty one plus a filled one")

        let lifecycle = harness.emitted("session_lifecycle")
        XCTAssertEqual(lifecycle.count, 1, "S-17605 one started lifecycle, as any start sends")
        let payload = try object(lifecycle.first?["payload"])
        XCTAssertEqual(payload["state"] as? String, "started")
        XCTAssertEqual(lifecycle.first?["sessionId"] as? String, session.sessionId)
        let snapshots = harness.emitted("session_snapshot")
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertTrue(
            Harness.validator().validateEnvelope(snapshots[0]).isEmpty,
            "S-17605 the announcement is a frame the phone can read"
        )
        let snapshot = try object(snapshots[0]["payload"])
        XCTAssertEqual(
            (snapshot["exercises"] as? [[String: Any]])?.count,
            1,
            "S-17605 the phone hears a session that already holds its first exercise"
        )
    }

    func testS17605TheSessionCarriesTheExercisesNamedHealthKind() async throws {
        let harness = try await WatchModalityStartFixture.wrist(briskWalk: true)
        let walk = try WatchModalityStartFixture.exercise(
            WatchModalityStartFixture.briskWalkId,
            of: harness
        )

        let session = await harness.paths.startModalityWorkout("cardio_endurance", with: walk)

        XCTAssertEqual(
            session.exercises.first?["healthActivity"] as? String,
            "walking",
            "S-17605 the slot carries the Health kind the phone named, which is what types the workout"
        )
        XCTAssertEqual(session.modality, "cardio_endurance", "S-17605 the modality rides alongside it")
    }

    func testS17605EveryCellCreatesItsOwnModalityWithTheSameExercise() async throws {
        for cell in WatchModalityStart.cells {
            let harness = try await WatchModalityStartFixture.wrist()
            let plank = try WatchModalityStartFixture.exercise("ex-plank", of: harness)

            let session = await harness.paths.startModalityWorkout(cell.key, with: plank)

            XCTAssertEqual(
                session.modality,
                cell.key,
                "S-17605 \(cell.label) starts a \(cell.key) session"
            )
            XCTAssertEqual(
                session.exercises.compactMap { $0["exerciseId"] as? String },
                ["ex-plank"],
                "S-17605 \(cell.label) holds the picked exercise"
            )
        }
    }

    // Plan 201, D-20105: a held ACTIVE session takes a pick as one more
    // exercise instead of ignoring it. A session that already holds exercises
    // never shows the Start surface, so this is the paths-level rule a menu
    // pick reaches; the row still answers (one session at a time, D-171) and
    // the held modality stays (D-12591).
    func testS17605ASecondPickReturnsTheHeldSessionAndAddsThePick() async throws {
        let harness = try await WatchModalityStartFixture.wrist()
        let plank = try WatchModalityStartFixture.exercise("ex-plank", of: harness)
        let squat = try WatchModalityStartFixture.exercise("ex-goblet-squat", of: harness)
        let held = await harness.paths.startModalityWorkout("cardio_endurance", with: plank)

        let second = await harness.paths.startModalityWorkout("sports", with: squat)

        XCTAssertEqual(
            second.sessionId,
            held.sessionId,
            "S-17605 one session at a time: the held row answers, whatever starts it (D-171)"
        )
        XCTAssertEqual(
            second.modality,
            "cardio_endurance",
            "S-17605 and the held session keeps the modality it started with (D-12591)"
        )
        XCTAssertEqual(
            second.exercises.compactMap { $0["exerciseId"] as? String },
            ["ex-plank", "ex-goblet-squat"],
            "S-20105 the pick becomes one more exercise of the held session"
        )
        XCTAssertEqual(second.currentExerciseIndex, 1, "S-20105 the session moves to the pick")
    }

    // MARK: - S-17607 the pick's session carries the modality into Health's type

    /// An exercise the phone named no Health kind for: its capabilities decide
    /// nothing on their own, so the modality the grid chose is what types the
    /// workout (D-16803).
    private func unnamedLift() -> WatchCatalogExercise {
        WatchCatalogExercise(
            exerciseId: "ex-unnamed-lift",
            name: "Unnamed Lift",
            capabilities: ["reps", "sets", "load"]
        )
    }

    func testS17607AWalkThePhoneNamedIsAWalkEvenUnderCardio() async throws {
        let harness = try await WatchModalityStartFixture.wrist(briskWalk: true)
        let walk = try WatchModalityStartFixture.exercise(
            WatchModalityStartFixture.briskWalkId,
            of: harness
        )
        let store = ScriptedPlatformStore()
        let coordinator = WatchWorkoutCoordinator(platform: WatchPlatformWorkout(store: store))

        let session = await harness.paths.startModalityWorkout("cardio_endurance", with: walk)
        await coordinator.refresh(session)

        XCTAssertEqual(
            store.begun,
            ["walking"],
            "S-17607 one workout, opened as the kind the exercise's phone named"
        )
    }

    func testS17607AnUnnamedExerciseTakesItsCellsType() async throws {
        let expected = [
            "cardio_endurance": "running",
            "resistance_lifting": "traditionalStrengthTraining",
            "isometric_stretching": "flexibility",
            "sports": "other",
        ]

        for cell in WatchModalityStart.cells {
            let harness = try await WatchModalityStartFixture.wrist()

            let session = await harness.paths.startModalityWorkout(cell.key, with: unnamedLift())

            XCTAssertEqual(
                WatchActivityTypes.forSession(session)?.watchOs,
                expected[cell.key],
                "S-17607 \(cell.label) with an unnamed exercise is the modality's own type"
            )
        }
    }

    // MARK: - S-17606 closing the picker creates nothing

    func testS17606CancelLeavesNoSessionRowAndNoFrame() async throws {
        let harness = try await WatchModalityStartFixture.wrist()
        harness.paths.beginModalityStart("cardio_endurance")
        let rowsBefore = await sessionRows(harness)
        let framesBefore = harness.emitted

        // What the sheet's dismiss handler does: drop the start mode, then run
        // plan 57's guard, which has no session of the wrist's to give up.
        harness.paths.cancelModalityStart()
        let cancelled = await harness.paths.cancelEmptyFreeWorkout()

        XCTAssertNil(harness.paths.pendingModalityStart, "S-17606 the start mode is dropped")
        XCTAssertFalse(cancelled, "S-17606 there was no empty session to give up (D-17608)")
        XCTAssertNil(harness.engine.session, "S-17606 no session exists to abandon")
        let rowsAfter = await sessionRows(harness)
        XCTAssertEqual(rowsAfter.count, rowsBefore.count, "S-17606 no session row was ever written")
        XCTAssertTrue(rowsAfter.isEmpty)
        XCTAssertEqual(
            harness.emitted.map { $0["type"] as? String },
            framesBefore.map { $0["type"] as? String },
            "S-17606 no frame was emitted: nothing reached the phone"
        )
    }

    func testS17606ChoosingCancelsNothingAndTheSessionSurvives() async throws {
        let harness = try await WatchModalityStartFixture.wrist()
        let plank = try WatchModalityStartFixture.exercise("ex-plank", of: harness)
        harness.paths.beginModalityStart("isometric_stretching")

        let session = await harness.paths.startModalityWorkout("isometric_stretching", with: plank)
        let cancelled = await harness.paths.cancelEmptyFreeWorkout()

        XCTAssertFalse(cancelled, "S-17606 a session holding an exercise is never given up")
        XCTAssertEqual(harness.engine.session?.status, WatchSessionStatus.active)
        XCTAssertEqual(harness.engine.session?.sessionId, session.sessionId)
    }

    // MARK: - S-20112..S-20114 a modality pick over a held session (plan 201, D-20105)

    /// A held ACTIVE session with no exercises and no modality: the session the
    /// engine creates empty, waiting for its first pick.
    private func heldEmptySession() async throws -> (WatchStartHarness, WatchSessionRecord) {
        let harness = try await WatchModalityStartFixture.wrist()
        let held = await harness.engine.createSession(modality: nil, exercises: [])
        return (harness, held)
    }

    func testS20112AModalityPickOverAHeldEmptySessionAddsTheExercise() async throws {
        let (harness, held) = try await heldEmptySession()
        let plank = try WatchModalityStartFixture.exercise("ex-plank", of: harness)
        harness.paths.beginModalityStart("cardio_endurance")

        let row = await harness.paths.startModalityWorkout("cardio_endurance", with: plank)

        XCTAssertEqual(
            row.sessionId,
            held.sessionId,
            "S-20112 the held session receives the pick instead of a new one starting"
        )
        XCTAssertEqual(
            row.exercises.count,
            1,
            "S-20112 the pick becomes the session's one exercise"
        )
        XCTAssertEqual(row.currentExerciseIndex, 0, "S-20112 the session is on the pick")
        XCTAssertNil(harness.paths.pendingModalityStart, "S-20112 the pick ends the start mode")
        XCTAssertEqual(
            harness.engine.session?.sessionId,
            held.sessionId,
            "S-20112 the engine still holds the one session"
        )
    }

    func testS20113AModalityPickOverAnEndedSessionCreatesANewOne() async throws {
        let (harness, held) = try await heldEmptySession()
        _ = await harness.engine.finishSession()
        let plank = try WatchModalityStartFixture.exercise("ex-plank", of: harness)
        harness.paths.beginModalityStart("cardio_endurance")

        let row = await harness.paths.startModalityWorkout("cardio_endurance", with: plank)

        XCTAssertNotEqual(
            row.recordId,
            held.recordId,
            "S-20113 an ended session holds no slot, so the pick starts a new one"
        )
        XCTAssertEqual(
            row.modality,
            "cardio_endurance",
            "S-20113 the S-17605 creation path runs unchanged"
        )
        XCTAssertEqual(row.exercises.count, 1, "S-20113 one session, holding the one exercise")
    }

    func testS20114TheHeldSessionKeepsItsOwnModality() async throws {
        let (harness, held) = try await heldEmptySession()
        XCTAssertNil(held.modality, "S-20114 the held session carries no modality")
        let plank = try WatchModalityStartFixture.exercise("ex-plank", of: harness)
        harness.paths.beginModalityStart("cardio_endurance")

        _ = await harness.paths.startModalityWorkout("cardio_endurance", with: plank)

        XCTAssertNil(
            harness.engine.session?.modality,
            "S-20114 the held session's modality stays nil after the pick (D-12591)"
        )
    }
}
