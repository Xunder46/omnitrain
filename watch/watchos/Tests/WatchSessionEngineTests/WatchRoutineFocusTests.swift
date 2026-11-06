//
//  WatchRoutineFocusTests.swift
//  WatchSessionEngineTests
//
//  Plan 125b phase A: the wrist reads a routine's Focus and starts the session
//  with it. Scenarios S-12560, S-12562, S-12568 (after S-12560), S-12569,
//  S-12570, S-12571 and S-12572 of
//  `docs/plans/2026-11-05-125-wrist-routine-focus-modality-plan/2026-11-05-125b-watch-app-plan.md`.
//
//  The Focus table's values are the plan's rows; the Health type, the GPS
//  decision and the round word are read through the production surfaces.
//

import XCTest

@testable import WatchSessionEngine

/// One engine and its start paths over a fresh store, with both id sources
/// injected — the `TokenHarness` shape (`WatchSlotTokenTests.swift`): session
/// ids handed out in order, the start paths' factory counting "alpha-<n>".
/// Validators are left out, exactly as the token tests build the pair, so a
/// scenario exercises the parse and the start paths rather than the schema.
private final class RoutineFocusHarness {
    let clock: TestClock
    let store: WatchSessionStore
    private(set) var emitted: [[String: Any]] = []
    private(set) var engine: WatchSessionEngine!
    private(set) var paths: WatchSessionStartPaths!

    init(
        store: WatchSessionStore = InMemoryWatchSessionStore(),
        sessionIds: [String] = (1...12).map { "s-f\($0)" }
    ) {
        self.clock = TestClock(testInstant())
        self.store = store

        var sessionQueue = sessionIds
        var engineId = 0
        var pathId = 0
        engine = WatchSessionEngine(
            store: store,
            onEmit: { [weak self] envelope in self?.emitted.append(envelope) },
            validator: nil,
            clock: clock.call,
            idFactory: { engineId += 1; return "rec-\(engineId)" },
            sessionIdFactory: { sessionQueue.isEmpty ? "s-extra" : sessionQueue.removeFirst() }
        )
        paths = WatchSessionStartPaths(
            engine: engine,
            store: store,
            validator: nil,
            clock: clock.call,
            idFactory: { pathId += 1; return "alpha-\(pathId)" }
        )
    }

    /// A launch over the same store: a second harness reading what the first
    /// left behind, as a relaunch does.
    @discardableResult
    func relaunched() async -> RoutineFocusHarness {
        let relaunched = RoutineFocusHarness(store: store)
        await relaunched.engine.restore()
        await relaunched.paths.restore()
        return relaunched
    }

    func apply(_ envelope: [String: Any]) async -> WatchCatalogSyncResult {
        await paths.applyRoutinesDown(envelope)
    }

    var surface: WatchLoggingState {
        WatchLoggingState(engine: engine, clock: clock.call)
    }

    func sessionEndPayload() -> [String: Any]? {
        engine.observations.first { $0.kind == WatchObservationKind.sessionEnd }?.payload
    }
}

private func focusRoutine(
    id: String,
    focus: Any?,
    name: String = "Focus Routine",
    efforts: [[String: Any]]
) -> [String: Any] {
    var routine: [String: Any] = [
        "routineId": id,
        "name": name,
        "updatedAt": "2026-07-12T09:00:00Z",
        "segments": [
            [
                "segmentId": "seg-main",
                "name": "Main",
                "efforts": efforts,
            ]
        ],
    ]
    if let focus { routine["focusModality"] = focus }
    return routine
}

private func effort(
    _ effortId: String,
    exercise: String,
    name: String,
    kind: String,
    capabilities: [String]
) -> [String: Any] {
    [
        "effortId": effortId,
        "exerciseId": exercise,
        "exerciseName": name,
        "effortKind": kind,
        "capabilities": capabilities,
        "targets": [String: Any](),
    ]
}

private let twoEfforts: [[String: Any]] = [
    effort("eff-bench", exercise: "ex-bench", name: "Bench", kind: "set", capabilities: ["sets"]),
    effort("eff-plank", exercise: "ex-plank", name: "Plank", kind: "drill", capabilities: ["hold", "time"]),
]

/// The contract's own `routines_down` shape, plus the `focusModality` key this
/// plan's routine carries (`watch/contract/watch_start_paths_contract.json`,
/// `fallback.routinesDown`).
private func routinesDown(_ routines: [[String: Any]]) -> [String: Any] {
    [
        "protocolVersion": SyncProtocolValidator.protocolVersion,
        "messageId": "msg-routines-focus-1",
        "type": "routines_down",
        "origin": "phone",
        "sentAt": "2026-07-13T17:00:00Z",
        "payload": [
            "generatedAt": "2026-07-13T17:00:00Z",
            "routines": routines,
            "fallbackExercises": [
                [
                    "exerciseId": "ex-bench",
                    "name": "Bench",
                    "capabilities": ["sets", "reps", "load"],
                ],
                [
                    "exerciseId": "ex-plank",
                    "name": "Plank",
                    "capabilities": ["hold", "time"],
                ],
                [
                    "exerciseId": "ex-squat",
                    "name": "Squat",
                    "capabilities": ["reps", "sets", "load"],
                ],
            ],
        ] as [String: Any],
    ]
}

/// What the phone echoes back for one of the wrist's own sessions, with no
/// modality key anywhere — the snapshot's shape
/// (`watch/sync_protocol/fixtures/valid/session_snapshot.json`).
private func snapshotMessage(sessionId: String, exercises: [[String: Any]]) -> [String: Any] {
    [
        "protocolVersion": SyncProtocolValidator.protocolVersion,
        "messageId": "msg-snapshot-focus-1",
        "sessionId": sessionId,
        "type": "session_snapshot",
        "origin": "phone",
        "sentAt": "2026-07-13T06:21:00Z",
        "payload": [
            "sessionId": sessionId,
            "revision": 7,
            "status": WatchSessionStatus.active,
            "currentExerciseIndex": 0,
            "exercises": exercises,
            "entries": [[String: Any]](),
            "timers": [String: Any](),
        ] as [String: Any],
    ]
}

final class WatchRoutineFocusTests: XCTestCase {

    // MARK: - S-12560 the Focus table

    func testS12560RoutineFocusCarriesTheTableToTheSession() async throws {
        let rows: [(focus: String, health: String, gps: Bool, word: String)] = [
            ("isometric_stretching", "flexibility", false, "Rounds"),
            ("resistance_lifting", "traditionalStrengthTraining", false, "Rounds"),
            ("cardio_endurance", "running", true, "Intervals"),
            ("sports", "other", true, "Periods"),
            ("conditioning_mixed", "crossTraining", false, "Rounds"),
        ]

        for row in rows {
            let harness = RoutineFocusHarness()
            let result = await harness.apply(
                routinesDown([
                    focusRoutine(id: "routine-focus-1", focus: row.focus, efforts: twoEfforts)
                ])
            )
            XCTAssertEqual(result.applied, true, "row \(row.focus): the list applied")

            let session = try await harness.paths.startFromRoutine("routine-focus-1")

            XCTAssertEqual(
                session.modality, row.focus,
                "row \(row.focus): the session starts with the routine's Focus"
            )
            XCTAssertEqual(
                WatchActivityTypes.forSession(session)?.watchOs,
                row.health,
                "row \(row.focus): the Health type the table names"
            )
            XCTAssertEqual(
                WatchGpsPolicy.isRequired(session),
                row.gps,
                "row \(row.focus): the GPS the table names"
            )
            XCTAssertEqual(
                harness.surface.roundsLabel,
                row.word,
                "row \(row.focus): the round word the table names"
            )
            XCTAssertEqual(
                harness.emitted.map { $0["type"] as? String },
                ["session_lifecycle", "session_snapshot"],
                "row \(row.focus): a start emits the same frames as before, and no new message type"
            )
        }
    }

    // MARK: - S-12562 the session_end carries the Focus

    func testS12562TheSessionEndCarriesTheFocus() async throws {
        let harness = RoutineFocusHarness()
        _ = await harness.apply(
            routinesDown([
                focusRoutine(
                    id: "routine-stretch",
                    focus: "isometric_stretching",
                    efforts: [
                        effort("eff-plank", exercise: "ex-plank", name: "Plank", kind: "drill", capabilities: ["hold", "time"])
                    ]
                )
            ])
        )
        _ = try await harness.paths.startFromRoutine("routine-stretch")

        await harness.surface.startWork()
        harness.clock.advance(60)
        _ = try await harness.surface.log()
        _ = await harness.engine.finishSession()

        let end = try XCTUnwrap(
            harness.sessionEndPayload(),
            "the wrist's End appends the session's end"
        )
        XCTAssertEqual(
            end["modality"] as? String, "isometric_stretching",
            "the end carries the Focus the session started with"
        )
    }

    // MARK: - S-12568 the phone's snapshot does not undo it

    func testS12568PhoneSnapshotWithNoModalityKeepsTheFocus() async throws {
        let harness = RoutineFocusHarness()
        _ = await harness.apply(
            routinesDown([
                focusRoutine(
                    id: "routine-stretch",
                    focus: "isometric_stretching",
                    efforts: [
                        effort("eff-plank", exercise: "ex-plank", name: "Plank", kind: "drill", capabilities: ["hold", "time"])
                    ]
                )
            ])
        )
        let session = try await harness.paths.startFromRoutine("routine-stretch")

        let applied = try await harness.engine.applyMessage(
            snapshotMessage(sessionId: session.sessionId, exercises: session.exercises)
        )
        XCTAssertEqual(applied, true, "the phone's echo applied")

        XCTAssertEqual(
            harness.engine.session?.modality, "isometric_stretching",
            "a snapshot with no modality key leaves the Focus alone"
        )

        _ = await harness.engine.finishSession()
        let end = try XCTUnwrap(
            harness.sessionEndPayload()
        )
        XCTAssertEqual(
            end["modality"] as? String, "isometric_stretching",
            "a later End still emits the Focus"
        )
    }

    // MARK: - S-12569 the Focus survives a relaunch

    func testS12569RelaunchKeepsTheRoutineFocusAndTheSessionModality() async throws {
        let harness = RoutineFocusHarness()
        _ = await harness.apply(
            routinesDown([
                focusRoutine(id: "routine-stretch", focus: "isometric_stretching", efforts: twoEfforts)
            ])
        )
        _ = try await harness.paths.startFromRoutine("routine-stretch")

        let relaunched = await harness.relaunched()
        XCTAssertEqual(
            relaunched.paths.routines.first?.focusModality, "isometric_stretching",
            "the catalog row kept the Focus"
        )
        XCTAssertEqual(
            relaunched.paths.routines.first?.startModality, "isometric_stretching",
            "the restored routine still names a modality the wrist knows"
        )
        let json = try XCTUnwrap(relaunched.paths.routines.first?.toJson())
        XCTAssertEqual(json["focusModality"] as? String, "isometric_stretching", "toJson round-trips the key")

        let session = try await relaunched.paths.startFromRoutine("routine-stretch")
        // The wrist is already running the routine: the held session is what a
        // second start returns, and its modality is the Focus.
        XCTAssertEqual(session.modality, "isometric_stretching", "the live session kept the Focus")

        let afterRelaunch = await relaunched.relaunched()
        XCTAssertEqual(
            afterRelaunch.engine.session?.modality, "isometric_stretching",
            "the session's modality survives the relaunch"
        )
    }

    // MARK: - S-12570 an unreadable Focus never types a session, never throws

    func testS12570AdversarialFocusValuesParseTolerantly() async throws {
        let rows: [(label: String, focus: Any?, expected: String?)] = [
            ("empty", "", nil),
            ("display name", "Stretching", "Stretching"),
            ("upper case", "ISOMETRIC_STRETCHING", "ISOMETRIC_STRETCHING"),
            ("leading space", " cardio_endurance", " cardio_endurance"),
            ("number", NSNumber(value: 12), nil),
            ("null", NSNull(), nil),
            ("array", ["sports"], nil),
            ("object", [String: Any](), nil),
        ]

        let harness = RoutineFocusHarness()
        let routines = rows.indices.map { index in
            focusRoutine(id: "routine-case-\(index)", focus: rows[index].focus, efforts: twoEfforts)
        }
        let result = await harness.apply(routinesDown(routines))
        XCTAssertEqual(result.applied, true, "one unreadable Focus drops nothing: the whole list applied")

        for (index, row) in rows.enumerated() {
            let routine = try XCTUnwrap(
                harness.paths.routines.first { $0.routineId == "routine-case-\(index)" },
                "row \(row.label): the routine is in the list"
            )
            XCTAssertEqual(
                routine.focusModality, row.expected,
                "row \(row.label): what the parse keeps of the value"
            )
            XCTAssertNil(routine.startModality, "row \(row.label): no session is typed from it")

            let session = try await harness.paths.startFromRoutine("routine-case-\(index)")
            XCTAssertNil(
                session.modality,
                "row \(row.label): a session started from it carries no modality"
            )
            _ = await harness.engine.finishSession()
        }
    }

    // MARK: - S-12571 the Focus, not the exercises, decides

    func testS12571CardioFocusOverStrengthExercisesStaysRunning() async throws {
        let harness = RoutineFocusHarness()
        _ = await harness.apply(
            routinesDown([
                focusRoutine(
                    id: "routine-cardio",
                    focus: "cardio_endurance",
                    efforts: [
                        effort("eff-squat", exercise: "ex-squat", name: "Squat", kind: "set", capabilities: ["reps", "sets", "load"])
                    ]
                )
            ])
        )
        let session = try await harness.paths.startFromRoutine("routine-cardio")

        XCTAssertEqual(session.modality, "cardio_endurance", "documented consequence: the Focus wins")
        XCTAssertEqual(
            WatchActivityTypes.forSession(session)?.watchOs, "running",
            "documented consequence: a cardio-focus routine of squats registers as Running"
        )
        XCTAssertEqual(WatchGpsPolicy.isRequired(session), true, "documented consequence: GPS asked")
        XCTAssertEqual(harness.surface.roundsLabel, "Intervals", "documented consequence: the round word")
    }

    // MARK: - S-12572 a routines_down with no Focus anywhere

    func testS12572RoutinesDownWithoutTheFieldKeepsTodaySBehaviour() async throws {
        let harness = RoutineFocusHarness()
        let fixture = try Fixtures.json("fixtures/valid/routines_down.json")
        let result = await harness.apply(fixture)
        XCTAssertEqual(result.applied, true, "the old shape applies as it always did")

        let fixtureRoutine = try XCTUnwrap(harness.paths.routines.first, "the fixture's routine applied")
        XCTAssertNil(
            fixtureRoutine.focusModality,
            "a routine with no field parses to no Focus"
        )
        let session = try await harness.paths.startFromRoutine(fixtureRoutine.routineId)
        XCTAssertNil(session.modality, "the session starts with no modality, as before")
    }
}