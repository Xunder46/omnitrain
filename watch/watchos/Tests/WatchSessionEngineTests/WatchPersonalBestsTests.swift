//
//  WatchPersonalBestsTests.swift
//  WatchSessionEngineTests
//
//  Phase 2 of the plan: the holder that decides whether a set logged on the
//  wrist beat the best the phone last sent. Fixture F is the plan's frame — a
//  bench press estimated at 116.6667 kg (100 x 5), a push-up best of 12 reps,
//  and no squat entry at all — and every number below is derived from it rather
//  than restated.
//
//  The tests are plain XCTest on the holder: no UI, no timer, no radio. What
//  they pin is the rule (D-1, strict `>`), the silence without a frame (D-3),
//  the own-best dedup across a relaunch (D-2, D-15, D-16) and the storage
//  discipline (D-11, D-17).
//

import XCTest

@testable import WatchSessionEngine

/// 116.66666666666667 — 100 x 5 as the phone computes it, in the phone's own
/// operation order.
private let benchHeldEstimate = 100 * (1 + 5 / 30.0)

/// 225 lb in kilograms, the number a pounds-denominated phone still sends as
/// `loadKg`.
private let twoTwentyFivePoundsInKilograms = 225.0 * 0.45359237

private func bestsFrame(
    _ entries: [[String: Any]],
    generatedAt: String,
    messageId: String
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
private func fixtureF(
    messageId: String = "msg-f-1",
    generatedAt: String = "2026-10-27T09:00:00Z"
) -> [String: Any] {
    bestsFrame(
        [
            ["exerciseId": "ex-bench", "e1rmKg": benchHeldEstimate],
            ["exerciseId": "ex-push-up", "repsBest": 12],
        ],
        generatedAt: generatedAt,
        messageId: messageId
    )
}

private func bestsStamp(_ text: String) -> Date {
    (try? parseUtcIso(text)) ?? Date(timeIntervalSince1970: 0)
}

/// One `set` observation as the wrist stores it, so the rebuild reads the same
/// shape the log path writes.
private func storedSet(
    _ recordId: String,
    exerciseId: String,
    reps: Int,
    loadKg: Double? = nil,
    at instant: Date = testInstant()
) -> StoredWatchRecord {
    var payload: [String: Any] = [
        "entryId": recordId,
        "eventId": recordId,
        "kind": WatchObservationKind.set,
        "loggedAt": utcIso(instant),
        "sessionExerciseId": "sx-\(exerciseId)",
        "exerciseId": exerciseId,
        "reps": reps,
    ]
    if let loadKg { payload["loadKg"] = loadKg }
    return .observation(
        WatchObservationRecord(
            recordId: recordId,
            sessionId: "s-watch-1",
            recordedAt: instant,
            kind: WatchObservationKind.set,
            payload: payload
        )
    )
}

private func bestsHolder(
    _ store: WatchSessionStore,
    _ clock: TestClock = TestClock(testInstant())
) -> WatchPersonalBests {
    WatchPersonalBests(store: store, validator: Harness.validator(), clock: clock.call)
}

/// An orchestrator over a live engine and its start paths, so routing is the
/// thing under test rather than a bypass.
private func bestsRouter(
    store: WatchSessionStore,
    clock: TestClock,
    bests: WatchPersonalBests?
) -> WatchSyncOrchestrator {
    let engine = WatchSessionEngine(
        store: store,
        onEmit: { _ in },
        validator: Harness.validator(),
        clock: clock.call,
        idFactory: { UUID().uuidString },
        sessionIdFactory: { "s-watch-1" }
    )
    let paths = WatchSessionStartPaths(
        engine: engine,
        store: store,
        validator: Harness.validator(),
        clock: clock.call,
        idFactory: { UUID().uuidString }
    )
    return WatchSyncOrchestrator(
        transport: RecordingTransport(),
        paths: paths,
        engine: engine,
        bests: bests
    )
}

final class WatchPersonalBestsTests: XCTestCase {

    // MARK: - S-87b-1 strict `>`

    func testS87b1AnEqualSetIsNotARecordAndAHeavierOneIs() async {
        let holder = bestsHolder(InMemoryWatchSessionStore())
        let applied = await holder.applyBestsDown(fixtureF())
        XCTAssertTrue(applied.applied, "S-87b-1 the fixture frame is understood")

        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 5, loadKg: 100),
            "S-87b-1 100 x 5 is exactly the held 116.6667, so it is not a record"
        )
        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-1 100 x 6 is 120.0, above the held 116.6667"
        )
    }

    func testS87b1TheWireFixtureCarriesTheSameEstimate() async throws {
        let holder = bestsHolder(InMemoryWatchSessionStore())
        let applied = await holder.applyBestsDown(try Fixtures.json("fixtures/valid/bests_down.json"))
        XCTAssertTrue(applied.applied, "S-87b-1 the protocol's own frame is understood")

        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 5, loadKg: 100),
            "S-87b-1 the frame's 116.66666666666667 is the same estimate this set computes"
        )
        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-1 one rep more beats it"
        )
    }

    // MARK: - S-87b-2 no frame is no verdict

    func testS87b2AWristThatNeverReceivedAFrameSaysNothing() async {
        let store = InMemoryWatchSessionStore()
        let holder = bestsHolder(store)

        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-2 with no frame held a set gets no verdict, however large"
        )
        let contents = await store.readAll()
        XCTAssertTrue(
            contents.bests.isEmpty,
            "S-87b-2 a log writes no bests row: the frame is the phone's to send"
        )
    }

    func testS87b2AHeldEmptyFrameMakesEveryFirstSetARecord() async {
        let holder = bestsHolder(InMemoryWatchSessionStore())
        let applied = await holder.applyBestsDown(
            bestsFrame([], generatedAt: "2026-10-27T09:00:00Z", messageId: "msg-empty-1")
        )
        XCTAssertTrue(applied.applied, "S-87b-2 a held `bests: []` frame is a frame")

        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-anything", reps: 1, loadKg: nil),
            "S-87b-2 with a frame held and nothing in it, a first set is a record"
        )
        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-anything", reps: 1, loadKg: nil),
            "S-87b-2 the same first set twice is not two records"
        )
    }

    // MARK: - S-87b-3 an exercise the frame does not name

    func testS87b3AnExerciseAbsentFromTheFrameIsAFirstEverRecord() async {
        let holder = bestsHolder(InMemoryWatchSessionStore())
        _ = await holder.applyBestsDown(fixtureF())

        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-squat", reps: 5, loadKg: 60),
            "S-87b-3 squat is absent from the frame, so 60 x 5 (70.0) is the first ever"
        )
    }

    // MARK: - S-87b-4 bodyweight work on the reps axis

    func testS87b4BodyweightSetsCompareReps() async {
        let holder = bestsHolder(InMemoryWatchSessionStore())
        _ = await holder.applyBestsDown(fixtureF())

        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-push-up", reps: 13, loadKg: nil),
            "S-87b-4 13 beats the held 12"
        )
        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-push-up", reps: 12, loadKg: nil),
            "S-87b-4 12 does not"
        )
        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-push-up", reps: 13, loadKg: nil),
            "S-87b-4 a second 13 straight after is not a second record"
        )
    }

    // MARK: - S-87b-5 repeats inside one workout

    func testS87b5TheSameSetTwiceIsOneRecordAndAHeavierOneIsTheNext() async {
        let holder = bestsHolder(InMemoryWatchSessionStore())
        _ = await holder.applyBestsDown(fixtureF())

        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-5 100 x 6 (120.0) is the first record"
        )
        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-5 another 100 x 6 is the same set"
        )
        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 7, loadKg: 100),
            "S-87b-5 100 x 7 (123.3333) beats the 120.0 the wrist logged"
        )
    }

    // MARK: - S-87b-6 a set the phone has not received yet

    func testS87b6TheWristsOwnSetSilencesItsRepeatAfterARelaunch() async {
        let store = InMemoryWatchSessionStore()
        let clock = TestClock(testInstant())
        let holder = bestsHolder(store, clock)
        _ = await holder.applyBestsDown(fixtureF())

        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-6 the first 100 x 6 is a record"
        )
        _ = await store.append(storedSet("e-bench-1", exerciseId: "ex-bench", reps: 6, loadKg: 100))

        // Workout A's set is stored and unreceipted; the wrist relaunches.
        let relaunched = bestsHolder(store, clock)
        await relaunched.restore()

        XCTAssertFalse(
            relaunched.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-6 workout B's 100 x 6 is not a record: the wrist already logged it"
        )

        _ = await relaunched.applyBestsDown(
            bestsFrame(
                [["exerciseId": "ex-bench", "e1rmKg": 120.0]],
                generatedAt: "2026-10-27T10:00:00Z",
                messageId: "msg-f-2"
            )
        )
        XCTAssertFalse(
            relaunched.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-6 a frame carrying 120.0 changes nothing for 100 x 6: equal is not above"
        )
    }

    // MARK: - S-87b-7 only `set` efforts

    func testS87b7OnlySetEffortsGetAVerdictOrMoveTheOwnBest() async {
        let holder = bestsHolder(InMemoryWatchSessionStore())
        _ = await holder.applyBestsDown(fixtureF())

        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.hold, exerciseId: "ex-bench", reps: 5, loadKg: 200),
            "S-87b-7 a hold with extra load gets no verdict"
        )
        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.timed, exerciseId: "ex-bench", reps: 5, loadKg: 200),
            "S-87b-7 a timed effort gets no verdict"
        )
        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.round, exerciseId: "ex-bench", reps: 5, loadKg: 200),
            "S-87b-7 a round gets no verdict"
        )
        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 0, loadKg: 100),
            "S-87b-7 a set of no reps is not a claim"
        )
        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "", reps: 5, loadKg: 100),
            "S-87b-7 a set naming no exercise is not a claim"
        )

        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-7 had the hold's 200 kg been folded in, 120.0 would not be a record"
        )
    }

    // MARK: - S-87b-11 storage

    func testS87b11ThreeFramesLeaveOnlyTheNewestAndARestoreReadsIt() async {
        let store = InMemoryWatchSessionStore()
        let clock = TestClock(testInstant())
        let holder = bestsHolder(store, clock)

        for (index, estimate) in [110.0, 113.0, 120.0].enumerated() {
            let applied = await holder.applyBestsDown(
                bestsFrame(
                    [["exerciseId": "ex-bench", "e1rmKg": estimate]],
                    generatedAt: "2026-10-27T0\(index + 1):00:00Z",
                    messageId: "msg-\(index + 1)"
                )
            )
            XCTAssertTrue(applied.applied, "S-87b-11 frame \(index + 1) is understood and applied")
        }

        let contents = await store.readAll()
        XCTAssertEqual(
            contents.bests.map(\.recordId),
            ["bests-msg-3"],
            "S-87b-11 three frames leave one stored row: the newest, older ones pruned"
        )
        XCTAssertEqual(
            contents.bests.first?.generatedAt,
            bestsStamp("2026-10-27T03:00:00Z"),
            "S-87b-11 the row left is the frame with the newest generatedAt"
        )

        let relaunched = bestsHolder(store, clock)
        await relaunched.restore()
        XCTAssertTrue(relaunched.hasFrame, "S-87b-11 the held copy survives a relaunch")
        XCTAssertFalse(
            relaunched.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-11 the restored copy is the 120.0 frame: 100 x 6 equals it"
        )
        XCTAssertTrue(
            relaunched.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 7, loadKg: 100),
            "S-87b-11 123.3333 is above the restored 120.0"
        )
    }

    func testS87b11EqualEntriesTwiceAppendOnce() async {
        let store = InMemoryWatchSessionStore()
        let holder = bestsHolder(store)

        _ = await holder.applyBestsDown(fixtureF())
        let again = await holder.applyBestsDown(fixtureF(messageId: "msg-f-2"))
        let newerButEqual = await holder.applyBestsDown(
            fixtureF(messageId: "msg-f-3", generatedAt: "2026-10-27T11:00:00Z")
        )

        XCTAssertFalse(again.applied, "S-87b-11 the same entries again are nothing to write")
        XCTAssertFalse(
            newerButEqual.applied,
            "S-87b-11 equal entries write nothing even stamped later (D-11)"
        )
        let contents = await store.readAll()
        XCTAssertEqual(
            contents.bests.map(\.recordId),
            ["bests-msg-f-1"],
            "S-87b-11 the one row written is the first frame's, and no second one joined it"
        )
    }

    func testS87b11AnOlderFrameIsUnderstoodAndDropped() async {
        let store = InMemoryWatchSessionStore()
        let holder = bestsHolder(store)
        _ = await holder.applyBestsDown(fixtureF())

        let older = await holder.applyBestsDown(
            bestsFrame(
                [["exerciseId": "ex-bench", "e1rmKg": 200.0]],
                generatedAt: "2026-10-27T08:00:00Z",
                messageId: "msg-older"
            )
        )
        XCTAssertFalse(older.applied, "S-87b-11 a frame older than the held one is dropped")

        let contents = await store.readAll()
        XCTAssertEqual(
            contents.bests.map(\.recordId),
            ["bests-msg-f-1"],
            "S-87b-11 nothing was written for the older frame"
        )
        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-11 the held frame still decides: 120.0 beats 116.6667, not the dropped 200.0"
        )
    }

    // MARK: - S-87b-13 a frame the watch cannot read

    func testS87b13AMalformedFrameIsRefusedWholeAndThePreviousCopyStillDecides() async throws {
        let store = InMemoryWatchSessionStore()
        let holder = bestsHolder(store)
        _ = await holder.applyBestsDown(fixtureF())

        let refused = await holder.applyBestsDown(
            try Fixtures.json("fixtures/invalid/bests_down_zero_e1rm.json")
        )
        XCTAssertFalse(refused.applied, "S-87b-13 the invalid fixture is refused")
        XCTAssertFalse(refused.rejections.isEmpty, "S-87b-13 the refusal names what is wrong")

        let contents = await store.readAll()
        XCTAssertEqual(
            contents.bests.map(\.recordId),
            ["bests-msg-f-1"],
            "S-87b-13 a refused frame stores nothing"
        )
        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-13 the previous copy still decides"
        )
    }

    func testS87b13AnEntryWithNoAxisIsRefusedWithoutAValidator() async {
        let store = InMemoryWatchSessionStore()
        // No validator: the parser itself must refuse an entry nothing can compare.
        let holder = WatchPersonalBests(store: store)

        let refused = await holder.applyBestsDown(
            bestsFrame(
                [["exerciseId": "ex-bench"]],
                generatedAt: "2026-10-27T09:00:00Z",
                messageId: "msg-no-axis"
            )
        )
        XCTAssertFalse(refused.applied, "S-87b-13 an entry with neither axis is refused")
        let contents = await store.readAll()
        XCTAssertTrue(contents.bests.isEmpty, "S-87b-13 and nothing is stored for it")
    }

    // MARK: - S-87b-15 the numbers are kilograms

    func testS87b15DetectionComparesKilogramsWhateverThePhoneDisplays() async {
        let above = bestsHolder(InMemoryWatchSessionStore())
        _ = await above.applyBestsDown(
            bestsFrame(
                [["exerciseId": "ex-bench", "e1rmKg": 119.07]],
                generatedAt: "2026-10-27T09:00:00Z",
                messageId: "msg-above"
            )
        )
        XCTAssertFalse(
            above.noteLogged(
                kind: WatchObservationKind.set,
                exerciseId: "ex-bench",
                reps: 5,
                loadKg: twoTwentyFivePoundsInKilograms
            ),
            "S-87b-15 a 225 lb set is \(twoTwentyFivePoundsInKilograms) kg, estimated 119.068 —"
                + " below 119.07, and nothing like the 262.5 reading 225 as kilograms would give"
        )

        let below = bestsHolder(InMemoryWatchSessionStore())
        _ = await below.applyBestsDown(
            bestsFrame(
                [["exerciseId": "ex-bench", "e1rmKg": 119.0]],
                generatedAt: "2026-10-27T09:00:00Z",
                messageId: "msg-below"
            )
        )
        XCTAssertTrue(
            below.noteLogged(
                kind: WatchObservationKind.set,
                exerciseId: "ex-bench",
                reps: 5,
                loadKg: twoTwentyFivePoundsInKilograms
            ),
            "S-87b-15 the same set is a record above a 119.0 frame"
        )
    }

    // MARK: - S-87b-16 and S-87b-23 assisted sets

    func testS87b16AnAssistedSetWinsOnTheRepsAxis() async {
        let holder = bestsHolder(InMemoryWatchSessionStore())
        _ = await holder.applyBestsDown(
            bestsFrame(
                [["exerciseId": "ex-pull-up", "repsBest": 6]],
                generatedAt: "2026-10-27T09:00:00Z",
                messageId: "msg-assisted"
            )
        )

        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-pull-up", reps: 8, loadKg: -20),
            "S-87b-16 a band-assisted 8 beats the held 6 on the reps axis"
        )
    }

    func testS87b23ASecondIdenticalAssistedSetIsNotARecord() async {
        let holder = bestsHolder(InMemoryWatchSessionStore())
        _ = await holder.applyBestsDown(
            bestsFrame(
                [["exerciseId": "ex-pull-up", "repsBest": 6]],
                generatedAt: "2026-10-27T09:00:00Z",
                messageId: "msg-assisted"
            )
        )

        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-pull-up", reps: 8, loadKg: -20),
            "S-87b-23 the first assisted 8 is a record"
        )
        XCTAssertFalse(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-pull-up", reps: 8, loadKg: -20),
            "S-87b-23 the same assisted set straight after is not"
        )
    }

    // MARK: - S-87b-17 a receipted set still counts

    func testS87b17AReceiptedSetStillSilencesItsRepeatAfterARelaunch() async {
        let store = InMemoryWatchSessionStore()
        let clock = TestClock(testInstant())
        let holder = bestsHolder(store, clock)
        _ = await holder.applyBestsDown(fixtureF())
        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100)
        )

        _ = await store.append(storedSet("e-bench-1", exerciseId: "ex-bench", reps: 6, loadKg: 100))
        _ = await store.append(
            .confirmation(
                WatchConfirmationRecord(
                    recordId: "conf-1",
                    sessionId: "s-watch-1",
                    recordedAt: clock.now,
                    observationIds: ["e-bench-1"]
                )
            )
        )

        let relaunched = bestsHolder(store, clock)
        await relaunched.restore()
        XCTAssertFalse(
            relaunched.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-17 the phone's receipt does not forget the wrist's own set"
        )
    }

    // MARK: - S-87b-18 a phone set the snapshot brought

    func testS87b18ASnapshotBroughtPhoneSetFoldsIntoTheRebuild() async {
        let store = InMemoryWatchSessionStore()
        let clock = TestClock(testInstant())
        // A `session_snapshot` entry: the phone's entryId as the record id, and
        // nothing marking it as the phone's — stored as a plain observation.
        _ = await store.append(storedSet("entry-phone-1", exerciseId: "ex-bench", reps: 5, loadKg: 200))
        _ = await bestsHolder(store, clock).applyBestsDown(fixtureF())

        let relaunched = bestsHolder(store, clock)
        await relaunched.restore()
        XCTAssertFalse(
            relaunched.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-18 the phone's 200 x 5 (233.3333) silences a wrist 100 x 6, frame or no frame"
        )
    }

    // MARK: - routing: `bests_down` reaches the holder

    func testABestsDownFrameReachesTheHolderThroughTheOrchestrator() async throws {
        let store = InMemoryWatchSessionStore()
        let clock = TestClock(testInstant())
        let holder = bestsHolder(store, clock)
        let router = bestsRouter(store: store, clock: clock, bests: holder)

        let applied = try await router.receive(fixtureF())
        XCTAssertTrue(applied, "S-87b-11 the frame is routed to the holder and applied")
        XCTAssertTrue(holder.hasFrame, "S-87b-11 the routed frame is the copy the wrist holds")
        XCTAssertTrue(
            holder.noteLogged(kind: WatchObservationKind.set, exerciseId: "ex-bench", reps: 6, loadKg: 100),
            "S-87b-11 the routed frame is what the next set is measured against"
        )
    }

    func testABestsDownFrameIsRefusedWhenTheWatchKeepsNoHolder() async throws {
        let store = InMemoryWatchSessionStore()
        let router = bestsRouter(store: store, clock: TestClock(testInstant()), bests: nil)

        let applied = try await router.receive(fixtureF())
        XCTAssertFalse(applied, "a watch with no holder has nothing to do with a frame")
        let contents = await store.readAll()
        XCTAssertTrue(contents.bests.isEmpty, "and it stores nothing")
    }
}
