//
//  WatchPersonalRecordBannerTests.swift
//  WatchSessionEngineTests
//
//  Phase 3 of
//  `docs/plans/2026-10-27-87b-wrist-new-pr-detection-and-banner-plan/`: the log
//  path asks the holder whether the set beat the standing best, the surface
//  plays one cue (the record's, not the logged one), and the banner's window is
//  read off the injected clock.
//
//  Fixture F is the plan's frame — bench-press 116.6667 (100 x 5), push-up 12
//  reps, squat absent — and every number below is derived from it.
//
//  What these tests pin: a record plays only the record tap (S-87b-9,
//  S-87b-21), the window is visible a tenth of a second short of four seconds
//  and gone exactly at four (S-87b-10), a second record restarts it, a phone set
//  the snapshot brought fires nothing (S-87b-8), and a hold or a timed effort is
//  never a claim (S-87b-7).
//

import XCTest

@testable import WatchSessionEngine

/// 116.66666666666667 — 100 x 5 as the phone computes it, in the phone's own
/// operation order.
private let benchHeldEstimate = 100 * (1 + 5 / 30.0)

private func bestsFrame(
    _ entries: [[String: Any]],
    generatedAt: String = "2026-10-27T09:00:00Z",
    messageId: String = "msg-f-1"
) -> [String: Any] {
    [
        "protocolVersion": 1,
        "messageId": messageId,
        "type": "bests_down",
        "origin": "phone",
        "sentAt": "2026-10-27T09:00:00Z",
        "payload": [
            "generatedAt": generatedAt,
            "bests": entries,
        ],
    ]
}

/// Fixture F: bench-press 116.6667, push-up 12 reps, squat absent.
private func fixtureF() -> [String: Any] {
    bestsFrame([
        ["exerciseId": "ex-bench", "e1rmKg": benchHeldEstimate],
        ["exerciseId": "ex-push-up", "repsBest": 12],
    ])
}

final class WatchPersonalRecordBannerTests: XCTestCase {

    // MARK: - Harness

    private func slot(
        _ sessionExerciseId: String,
        exerciseId: String,
        capabilities: [String] = ["sets", "reps", "load"],
        effortKind: String? = nil,
        plannedSets: [[String: Any]]? = nil
    ) -> [String: Any] {
        var slot: [String: Any] = [
            "sessionExerciseId": sessionExerciseId,
            "exerciseId": exerciseId,
            "name": exerciseId,
            "capabilities": capabilities,
        ]
        if let effortKind { slot["effortKind"] = effortKind }
        if let plannedSets { slot["plannedSets"] = plannedSets }
        return slot
    }

    private func holder(_ harness: Harness) -> WatchPersonalBests {
        WatchPersonalBests(
            store: harness.store,
            validator: Harness.validator(),
            clock: harness.clock.call
        )
    }

    /// The logging surface over a session the caller shaped, with the holder
    /// wired in (or nil, for a watch that has none) and the recorder it plays
    /// into.
    @MainActor
    private func surface(
        _ harness: Harness,
        exercises: [[String: Any]],
        bests: WatchPersonalBests?
    ) async -> (
        engine: WatchSessionEngine,
        state: WatchLoggingState,
        model: WatchLoggingModel,
        haptics: RecordingHaptics
    ) {
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: nil, exercises: exercises)
        let haptics = RecordingHaptics()
        let state = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            personalBests: bests
        )
        let model = WatchLoggingModel(state: state, haptics: haptics)
        return (engine, state, model, haptics)
    }

    /// The bench surface whose planned rows are exactly the sets a case logs, so
    /// the payload is the case's own numbers rather than dialled ones.
    @MainActor
    private func benchSurface(
        _ harness: Harness,
        bests: WatchPersonalBests?,
        plannedSets: [[String: Any]] = [["reps": 6, "loadKg": 100]]
    ) async -> (
        engine: WatchSessionEngine,
        state: WatchLoggingState,
        model: WatchLoggingModel,
        haptics: RecordingHaptics
    ) {
        await surface(
            harness,
            exercises: [slot("sx-bench", exerciseId: "ex-bench", plannedSets: plannedSets)],
            bests: bests
        )
    }

    /// A phone snapshot carrying one entry, the way the existing snapshot tests
    /// build one: the phone's own entry id, the session the wrist holds.
    private func phoneSnapshot(
        exercises: [[String: Any]],
        entries: [[String: Any]],
        sessionId: String = "s-watch-1"
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-phone-set-1",
            "sessionId": sessionId,
            "type": "session_snapshot",
            "origin": "phone",
            "sentAt": "2026-07-13T06:30:00Z",
            "payload": [
                "sessionId": sessionId,
                "revision": 4,
                "status": WatchSessionStatus.active,
                "currentExerciseIndex": 0,
                "exercises": exercises,
                "entries": entries,
                "timers": [String: Any](),
            ] as [String: Any],
        ]
    }

    private func phoneSet(_ entryId: String, reps: Int, loadKg: Double) -> [String: Any] {
        [
            "entryId": entryId,
            "eventId": entryId,
            "kind": WatchObservationKind.set,
            "loggedAt": "2026-07-13T06:05:00Z",
            "sessionExerciseId": "sx-bench",
            "exerciseId": "ex-bench",
            "reps": reps,
            "loadKg": loadKg,
        ]
    }

    // MARK: - S-87b-9 the tap a log is owed

    @MainActor
    func testS87b9ARecordLogPlaysTheRecordTapAndNotTheLoggedOne() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        let (engine, state, model, haptics) = await benchSurface(harness, bests: bests)

        await model.log()

        XCTAssertEqual(haptics.personalRecords, 1, "S-87b-9 a record plays one record tap")
        XCTAssertEqual(haptics.logged, 0, "S-87b-9 …and not the logged tap")
        XCTAssertTrue(
            state.lastLogWasPersonalRecord,
            "S-87b-9 the state reports the verdict of the log just made"
        )
        XCTAssertEqual(engine.observations.count, 1, "S-87b-9 the set is stored as any other")
    }

    @MainActor
    func testS87b9ANonRecordLogPlaysTheLoggedTapOnly() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        // 100 x 5 is exactly the held 116.6667: a set that merely equals the
        // best is not a record (strict `>`).
        let (_, state, model, haptics) = await benchSurface(
            harness,
            bests: bests,
            plannedSets: [["reps": 5, "loadKg": 100]]
        )

        await model.log()

        XCTAssertEqual(haptics.personalRecords, 0, "S-87b-9 an equal set plays no record tap")
        XCTAssertEqual(haptics.logged, 1, "S-87b-9 it plays the ordinary logged tap")
        XCTAssertFalse(state.lastLogWasPersonalRecord)
    }

    @MainActor
    func testS87b9ARefusedLogPlaysNeitherTap() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        let engine = await harness.runningEngine()
        let haptics = RecordingHaptics()
        let state = WatchLoggingState(
            engine: engine,
            clock: harness.clock.call,
            personalBests: bests
        )
        let model = WatchLoggingModel(state: state, haptics: haptics)

        await model.primaryAction()
        await model.log()

        XCTAssertEqual(haptics.personalRecords, 0, "S-87b-9 nothing to log plays no record tap")
        XCTAssertEqual(haptics.logged, 0, "S-87b-9 …and no logged tap either")
        XCTAssertNil(state.personalRecordBannerUntil, "S-87b-9 a refused log raises no banner")
    }

    @MainActor
    func testS87b9AWatchWithNoHolderPlaysTheLoggedTapForABeatingSet() async throws {
        let harness = Harness()
        // The set would be a record against Fixture F, but this watch has no
        // holder: without one there is no verdict at all (D-3).
        let (_, state, model, haptics) = await benchSurface(harness, bests: nil)

        await model.log()

        XCTAssertEqual(haptics.personalRecords, 0, "S-87b-9 a holderless watch plays no record tap")
        XCTAssertEqual(haptics.logged, 1, "S-87b-9 it plays the logged tap")
        XCTAssertFalse(state.lastLogWasPersonalRecord)
        XCTAssertNil(state.personalRecordBannerUntil)
    }

    // MARK: - S-87b-21 one cue, never two

    @MainActor
    func testS87b21EachLogPlaysExactlyOneTap() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        // A record (100 x 6 is 120.0), then a set that only equals the held best.
        let (_, _, model, haptics) = await benchSurface(
            harness,
            bests: bests,
            plannedSets: [["reps": 6, "loadKg": 100], ["reps": 5, "loadKg": 100]]
        )

        await model.primaryAction()
        XCTAssertEqual(haptics.personalRecords, 1, "S-87b-21 the record log plays the record tap")
        XCTAssertEqual(haptics.logged, 0, "S-87b-21 and never both")

        harness.clock.advance(120)
        await model.log()
        XCTAssertEqual(haptics.personalRecords, 1, "S-87b-21 the second log adds no record tap")
        XCTAssertEqual(haptics.logged, 1, "S-87b-21 it plays the logged tap")
        XCTAssertFalse(
            model.state.lastLogWasPersonalRecord,
            "S-87b-9 a non-record log clears the verdict the record log left"
        )
        XCTAssertEqual(
            haptics.personalRecords + haptics.logged,
            2,
            "S-87b-21 two logs, two taps: the two cues never stack"
        )
    }

    // MARK: - S-87b-10 the banner window

    @MainActor
    func testS87b10TheBannerIsVisibleUntilTheWindowEnds() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        let (_, state, model, _) = await benchSurface(harness, bests: bests)
        let t0 = harness.clock.now

        await model.log()

        let until = try XCTUnwrap(state.personalRecordBannerUntil, "S-87b-10 a record raises the banner")
        XCTAssertEqual(
            until.timeIntervalSince(t0),
            WatchPersonalRecordCopy.bannerSeconds,
            "S-87b-10 the window is the copy's own number"
        )
        XCTAssertTrue(
            state.isPersonalRecordBannerVisible(at: t0.addingTimeInterval(3.9)),
            "S-87b-10 visible a tenth of a second before the window ends"
        )
        XCTAssertFalse(
            state.isPersonalRecordBannerVisible(at: t0.addingTimeInterval(4.0)),
            "S-87b-10 gone exactly at the window's end"
        )
    }

    @MainActor
    func testS87b10ASecondRecordRestartsTheWindow() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        // 100 x 6 is a record (120.0); 100 x 7 beats it again (123.3333).
        let (engine, state, model, haptics) = await benchSurface(
            harness,
            bests: bests,
            plannedSets: [["reps": 6, "loadKg": 100], ["reps": 7, "loadKg": 100]]
        )
        let t0 = harness.clock.now

        await model.log()
        XCTAssertTrue(state.isResting, "S-87b-10 the rest the set starts still runs under the banner")

        harness.clock.advance(2)
        await model.log()

        XCTAssertEqual(
            engine.observations.filter { $0.kind == WatchObservationKind.set }.count,
            2,
            "S-87b-10 logging under the banner still stores the set"
        )
        XCTAssertEqual(haptics.personalRecords, 2, "S-87b-10 the second record plays its own tap")
        let until = try XCTUnwrap(state.personalRecordBannerUntil)
        XCTAssertEqual(
            until.timeIntervalSince(t0),
            6.0,
            "S-87b-10 the second record moves the end to t0 + 2 + the window"
        )
        XCTAssertTrue(
            state.isPersonalRecordBannerVisible(at: t0.addingTimeInterval(5.9)),
            "S-87b-10 the restarted window is still up a tenth of a second short"
        )
        XCTAssertFalse(
            state.isPersonalRecordBannerVisible(at: t0.addingTimeInterval(6.0)),
            "S-87b-10 and gone at its own end"
        )
    }

    @MainActor
    func testS87b10ANonRecordLogLeavesTheWindowAlone() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        let (_, state, model, _) = await benchSurface(
            harness,
            bests: bests,
            plannedSets: [["reps": 6, "loadKg": 100], ["reps": 5, "loadKg": 100]]
        )
        let t0 = harness.clock.now

        await model.log()
        let until = try XCTUnwrap(state.personalRecordBannerUntil)

        harness.clock.advance(1)
        await model.log()

        XCTAssertEqual(
            state.personalRecordBannerUntil,
            until,
            "S-87b-10 a non-record log neither clears the banner nor extends it"
        )
        XCTAssertTrue(state.isPersonalRecordBannerVisible(at: t0.addingTimeInterval(3.9)))
    }

    // MARK: - S-87b-8 a phone set never fires the wrist's banner

    @MainActor
    func testS87b8ASnapshotSetRaisesNoBannerAndNoTap() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        let exercises = [
            slot("sx-bench", exerciseId: "ex-bench", plannedSets: [["reps": 6, "loadKg": 100]])
        ]
        let (engine, state, model, haptics) = await surface(harness, exercises: exercises, bests: bests)

        _ = try await engine.applyMessage(
            phoneSnapshot(
                exercises: exercises,
                entries: [phoneSet("entry-phone-1", reps: 5, loadKg: 200)]
            )
        )

        XCTAssertNil(
            state.personalRecordBannerUntil,
            "S-87b-8 a set the phone mirrored in raises no banner"
        )
        XCTAssertFalse(state.lastLogWasPersonalRecord, "S-87b-8 and no verdict is claimed")
        XCTAssertEqual(haptics.personalRecords, 0, "S-87b-8 …and no record tap plays")
        XCTAssertEqual(haptics.logged, 0, "S-87b-8 …nor a logged one: nothing was logged here")

        // The wrist's own next set still compares against Fixture F and the
        // wrist's own bests, which hold nothing yet: the snapshot set enters the
        // comparison only through the launch rebuild (D-16, S-87b-18). So within
        // one run 100 x 6 (120.0) beats the frame's 116.6667 and is announced —
        // the known limit the plan states, not a defect this phase closes.
        await model.log()
        XCTAssertEqual(
            haptics.personalRecords,
            1,
            "S-87b-8 the wrist's own beating set is still a record in the same run"
        )
        XCTAssertEqual(haptics.logged, 0)
    }

    // MARK: - S-87b-7 only a set is a claim

    @MainActor
    func testS87b7ATimedEffortNeverRaisesTheBanner() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        let (_, state, model, haptics) = await surface(
            harness,
            exercises: [slot("sx-run", exerciseId: "ex-run", capabilities: ["time", "distance"])],
            bests: bests
        )

        await model.primaryAction()
        harness.clock.advance(60)
        await model.primaryAction()

        XCTAssertEqual(haptics.logged, 1, "S-87b-7 the timed effort is logged with the ordinary tap")
        XCTAssertEqual(haptics.personalRecords, 0, "S-87b-7 …and never the record tap")
        XCTAssertFalse(state.lastLogWasPersonalRecord)
        XCTAssertNil(state.personalRecordBannerUntil)
    }

    @MainActor
    func testS87b7AHoldNeverRaisesTheBanner() async throws {
        let harness = Harness()
        let bests = holder(harness)
        _ = await bests.applyBestsDown(fixtureF())
        let (_, state, model, haptics) = await surface(
            harness,
            exercises: [slot("sx-plank", exerciseId: "ex-plank", capabilities: ["time", "hold"])],
            bests: bests
        )

        await model.primaryAction()
        harness.clock.advance(30)
        await model.primaryAction()

        XCTAssertEqual(haptics.logged, 1, "S-87b-7 a hold is logged with the ordinary tap")
        XCTAssertEqual(haptics.personalRecords, 0, "S-87b-7 …and never the record tap, load or not")
        XCTAssertFalse(state.lastLogWasPersonalRecord)
        XCTAssertNil(state.personalRecordBannerUntil)
    }
}
