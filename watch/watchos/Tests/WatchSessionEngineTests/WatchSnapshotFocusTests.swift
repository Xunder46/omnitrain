//
//  WatchSnapshotFocusTests.swift
//  WatchSessionEngineTests
//
//  P1 of
//  `docs/plans/2026-11-05-125-wrist-routine-focus-modality-plan/2026-11-05-125d-snapshot-focus-plan.md`:
//  a session started on the phone carries its Focus to the wrist — the
//  `session_snapshot` gains an optional `modality`, and `applySnapshotExclusive`
//  stamps it only the first time it hears of the session.
//
//  Scenario mapping:
//    S-12592 first hearing stamps the known key, nothing else → `testS12592…`
//    S-12593 the Health type, the outdoor flag and the round word → `testS12593…`
//    S-12594 the empty Free workout and the one with exercises → `testS12594…`
//    S-12595 never override, never null, never a late stamp → `testS12595…`
//    S-12596 the Focus survives a relaunch and a keyless snapshot → `testS12596…`
//    S-12597 old phone, old watch, a malformed key → `testS12597…`
//    S-12598 a followed session's end carries the Focus and validates → `testS12598…`
//
//  S-12590/S-12591 are walked through the fixtures by `SyncProtocolFixturesTests`.
//

import XCTest

@testable import WatchSessionEngine

/// Reads as "the `modality` key is absent from the payload" for `focusSnapshot`.
/// Passing `NSNull()` explicitly means "the key is present, carrying null".
private enum FocusKeyAbsent {
    case absent
}

private func strengthSlot(_ id: String) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": id,
        "capabilities": ["sets", "reps", "load"],
    ]
}

private func holdSlot(_ id: String) -> [String: Any] {
    [
        "sessionExerciseId": id,
        "exerciseId": "ex-\(id)",
        "name": id,
        "capabilities": ["hold", "time"],
    ]
}

private let threeStrength = [strengthSlot("sx-1"), strengthSlot("sx-2"), strengthSlot("sx-3")]
private let twoHolds = [holdSlot("sx-hold-1"), holdSlot("sx-hold-2")]

/// One `session_snapshot` from the phone, with an optional `modality` key.
private func focusSnapshot(
    messageId: String,
    sessionId: String,
    sentAt: String,
    modality: Any? = FocusKeyAbsent.absent,
    status: String = WatchSessionStatus.active,
    revision: Int = 7,
    exercises: [[String: Any]] = threeStrength
) -> [String: Any] {
    var payload: [String: Any] = [
        "sessionId": sessionId,
        "revision": revision,
        "status": status,
        "currentExerciseIndex": 0,
        "exercises": exercises,
        "entries": [[String: Any]](),
        "timers": [String: Any](),
    ]
    if !(modality is FocusKeyAbsent) { payload["modality"] = modality }
    return [
        "protocolVersion": SyncProtocolValidator.protocolVersion,
        "messageId": messageId,
        "sessionId": sessionId,
        "type": "session_snapshot",
        "origin": "phone",
        "sentAt": sentAt,
        "payload": payload as [String: Any],
    ]
}

private let focusTable: [(key: String, health: String, gps: Bool, word: String)] = [
    ("isometric_stretching", "flexibility", false, "Rounds"),
    ("resistance_lifting", "traditionalStrengthTraining", false, "Rounds"),
    ("cardio_endurance", "running", true, "Intervals"),
    ("sports", "other", true, "Periods"),
    ("conditioning_mixed", "crossTraining", false, "Rounds"),
]

final class WatchSnapshotFocusTests: XCTestCase {

    // MARK: - Helpers

    /// A fresh engine over the same store, the shipped watch's shape: no
    /// validator, so a frame the schema would refuse is applied whole and the
    /// value the wrist cannot use still lands as a nil modality.
    private func engineWithoutValidator(_ harness: Harness) async -> WatchSessionEngine {
        let engine = WatchSessionEngine(store: harness.store, clock: harness.clock.call)
        await engine.restore()
        return engine
    }

    /// Both engines the wrist's rows are checked on: the package engine with
    /// the schemas' validator and one built without any.
    private func bothEngines(
        _ sessionId: String
    ) async -> [(title: String, harness: Harness, engine: WatchSessionEngine)] {
        let validated = Harness()
        let plain = Harness()
        return [
            ("validator", validated, await validated.runningEngine()),
            ("no validator", plain, await engineWithoutValidator(plain)),
        ]
    }

    /// A coordinator over a scripted store, with the platform handed back so a
    /// test can read what the watch has open (copied from
    /// `WatchWorkoutTypeFromExercisesTests`).
    private func makeCoordinator(
        _ store: ScriptedPlatformStore
    ) -> (coordinator: WatchWorkoutCoordinator, platform: WatchPlatformWorkout) {
        let platform = WatchPlatformWorkout(store: store)
        return (WatchWorkoutCoordinator(platform: platform), platform)
    }

    /// A coordinator over the recording store, so an assertion carries the
    /// begin's `outdoors` beside its activity type.
    private func makeOutdoorCoordinator(
        _ store: RecordingGpsOutdoorStore
    ) -> WatchWorkoutCoordinator {
        WatchWorkoutCoordinator(platform: WatchPlatformWorkout(store: store))
    }

    // MARK: - S-12592 one known key stamps one session

    private func assertStamps(_ key: String) async throws {
        for engineCase in await bothEngines("s-focus-\(key)") {
            let applied = try await engineCase.engine.applyMessage(
                focusSnapshot(
                    messageId: "msg-focus-\(key)",
                    sessionId: "s-focus-\(key)",
                    sentAt: "2026-07-13T06:30:00Z",
                    modality: key
                )
            )
            let session = try XCTUnwrap(engineCase.engine.session, "(\(key)) the row is stored")
            XCTAssertEqual(
                applied, true,
                "(\(key)) the snapshot applied on the \(engineCase.title) engine"
            )
            XCTAssertEqual(
                session.modality, key,
                "(\(key)) stamps the session on the \(engineCase.title) engine"
            )
        }
    }

    func testS12592AStretchingKeyStampsTheSession() async throws {
        try await assertStamps("isometric_stretching")
    }

    func testS12592AResistanceKeyStampsTheSession() async throws {
        try await assertStamps("resistance_lifting")
    }

    func testS12592ACardioKeyStampsTheSession() async throws {
        try await assertStamps("cardio_endurance")
    }

    func testS12592ASportsKeyStampsTheSession() async throws {
        try await assertStamps("sports")
    }

    func testS12592AConditioningKeyStampsTheSession() async throws {
        try await assertStamps("conditioning_mixed")
    }

    /// A well-typed value the wrist has no row for is applied and stamps nil,
    /// on both engines. (`""` is refused on the validating engine — a schema
    /// `minLength: 1` bound — so it is asserted in its own test below.)
    private func assertKeylessStampsNothing(_ value: String, name: String) async throws {
        for engineCase in await bothEngines("s-bad-\(value.replacingOccurrences(of: " ", with: "_"))") {
            let applied = try await engineCase.engine.applyMessage(
                focusSnapshot(
                    messageId: "msg-bad-\(value)",
                    sessionId: engineCase.harness.sessionId,
                    sentAt: "2026-07-13T06:30:00Z",
                    modality: value
                )
            )
            XCTAssertEqual(
                applied, true,
                "(\(name)) the snapshot applied on the \(engineCase.title) engine"
            )
            XCTAssertNil(
                engineCase.engine.session?.modality,
                "(\(name)) stamps nothing on the \(engineCase.title) engine"
            )
        }
    }

    func testS12592ADisplayNameStampsNothing() async throws {
        try await assertKeylessStampsNothing("Stretching", name: "display name")
    }

    func testS12592AnUpperCaseKeyStampsNothing() async throws {
        try await assertKeylessStampsNothing("ISOMETRIC_STRETCHING", name: "upper case")
    }

    func testS12592ALeadingSpaceKeyStampsNothing() async throws {
        try await assertKeylessStampsNothing(" cardio_endurance", name: "padded")
    }

    func testS12592AnUnknownKeyStampsNothing() async throws {
        try await assertKeylessStampsNothing("no_such_modality", name: "unknown key")
    }

    /// An empty string trips the schema's `minLength` on a validating receiver
    /// (S-12591 a): the whole snapshot is refused there, and the shipped
    /// watch's validator-less engine still applies it and stamps nothing.
    func testS12592AnEmptyKeyNeverStampsAnything() async throws {
        let validated = Harness()
        let validatedEngine = await validated.runningEngine()
        do {
            _ = try await validatedEngine.applyMessage(
                focusSnapshot(
                    messageId: "msg-bad-empty",
                    sessionId: "s-bad-empty",
                    sentAt: "2026-07-13T06:30:00Z",
                    modality: ""
                )
            )
            XCTFail("the validator refuses an empty modality whole")
        } catch is WatchEmissionRejected {}
        XCTAssertNil(validatedEngine.session?.modality, "a refused snapshot writes nothing")

        let plain = Harness()
        let plainEngine = await engineWithoutValidator(plain)
        let applied = try await plainEngine.applyMessage(
            focusSnapshot(
                messageId: "msg-bad-empty",
                sessionId: "s-bad-empty",
                sentAt: "2026-07-13T06:30:00Z",
                modality: ""
            )
        )
        XCTAssertEqual(applied, true)
        XCTAssertNil(plainEngine.session?.modality, "an empty key stamps nothing")
    }

    /// A malformed value — not a string — is refused by the validator, so only
    /// the shipped watch's validator-less engine runs them; there the snapshot
    /// applies and stamps nothing.
    private func assertMalformedValueStampsNothing(_ value: Any, name: String) async throws {
        let harness = Harness()
        let engine = await engineWithoutValidator(harness)
        let applied = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-bad-malformed",
                sessionId: harness.sessionId,
                sentAt: "2026-07-13T06:30:00Z",
                modality: value
            )
        )
        XCTAssertEqual(applied, true, "(\(name)) the snapshot applied")
        XCTAssertNil(engine.session?.modality, "(\(name)) stamps nothing")
    }

    func testS12592ANumberStampsNothing() async throws {
        try await assertMalformedValueStampsNothing(NSNumber(value: 12), name: "number")
    }

    func testS12592ANullStampsNothing() async throws {
        try await assertMalformedValueStampsNothing(NSNull(), name: "null")
    }

    func testS12592AnArrayStampsNothing() async throws {
        try await assertMalformedValueStampsNothing(["sports"], name: "array")
    }

    func testS12592AnObjectStampsNothing() async throws {
        try await assertMalformedValueStampsNothing([String: Any](), name: "object")
    }

    func testS12592AKeylessSnapshotStampsNothing() async throws {
        for engineCase in await bothEngines("s-focus") {
            let applied = try await engineCase.engine.applyMessage(
                focusSnapshot(
                    messageId: "msg-keyless",
                    sessionId: engineCase.harness.sessionId,
                    sentAt: "2026-07-13T06:30:00Z"
                )
            )
            XCTAssertEqual(applied, true, "(\(engineCase.title)) the snapshot applied")
            XCTAssertNil(
                engineCase.engine.session?.modality,
                "(\(engineCase.title)) a keyless snapshot stamps nothing"
            )
        }
    }

    // MARK: - S-12593 the table's Health type, GPS and round word

    private func assertFollowsTheTable(_ row: (key: String, health: String, gps: Bool, word: String)) async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-focus-\(row.key)",
                sessionId: "s-focus-\(row.key)",
                sentAt: "2026-07-13T06:30:00Z",
                modality: row.key,
                exercises: threeStrength
            )
        )
        XCTAssertEqual(
            engine.session?.modality, row.key,
            "(\(row.key)) the session carries the Focus the snapshot stamped"
        )

        let store = RecordingGpsOutdoorStore()
        let coordinator = makeOutdoorCoordinator(store)
        await coordinator.refresh(engine.session)
        for _ in 0..<5 { await coordinator.refresh(engine.session) }

        XCTAssertEqual(
            store.begins.map(\.activityType),
            [row.health],
            "(\(row.key)) the Health type the Focus table names"
        )
        XCTAssertEqual(
            store.begins.map(\.outdoors),
            [row.gps],
            "(\(row.key)) the outdoor flag the Focus table names"
        )
        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)
        XCTAssertEqual(surface.roundsLabel, row.word, "(\(row.key)) the round word the table names")
    }

    func testS12593AStretchingFocusOpensFlexibilityHowRounds() async throws {
        try await assertFollowsTheTable(focusTable[0])
    }

    func testS12593AResistanceFocusOpensStrengthHowRounds() async throws {
        try await assertFollowsTheTable(focusTable[1])
    }

    func testS12593ACardioFocusOpensRunningOutdoorsIntervals() async throws {
        try await assertFollowsTheTable(focusTable[2])
    }

    func testS12593ASportsFocusOpensOtherOutdoorsPeriods() async throws {
        try await assertFollowsTheTable(focusTable[3])
    }

    func testS12593AConditioningFocusOpensCrossTrainingHowRounds() async throws {
        try await assertFollowsTheTable(focusTable[4])
    }

    // MARK: - S-12594 the empty Free workout and the one with exercises

    func testS12594aTheFocusReplacesAnEmptyFreeWorkout() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let free = await engine.createSession(modality: nil, exercises: [])
        XCTAssertNil(free.modality, "the wrist's empty Free workout has no modality")

        let store = RecordingGpsOutdoorStore()
        let coordinator = makeOutdoorCoordinator(store)
        await coordinator.refresh(free)
        XCTAssertTrue(store.begins.isEmpty, "an empty Free workout opens no workout yet")

        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-replace",
                sessionId: "s-phone-routine",
                sentAt: "2026-07-13T06:30:00Z",
                modality: "isometric_stretching",
                exercises: twoHolds
            )
        )

        let current = try XCTUnwrap(engine.session, "the phone's session became current")
        XCTAssertEqual(current.sessionId, "s-phone-routine")
        XCTAssertEqual(current.modality, "isometric_stretching")

        await coordinator.refresh(engine.session)
        XCTAssertEqual(
            store.begins.map(\.activityType),
            ["flexibility"],
            "the replaced session's workout once, with the Focus's type"
        )
        XCTAssertEqual(store.begins.map(\.outdoors), [false])

        let stored = await harness.store.readAll()
        let oldRow = try XCTUnwrap(
            stored.sessions.first { $0.sessionId == free.sessionId },
            "the replaced empty session's row is still stored"
        )
        XCTAssertEqual(
            oldRow.status, WatchSessionStatus.active,
            "as the base behaviour gives it: a snapshot for another session does not edit the row it replaces"
        )
    }

    func testS12594bASnapshotForAnotherSessionWithExercisesIsRefusedWhole() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let wrist = await engine.createSession(
            modality: nil,
            exercises: [strengthSlot("sx-free")]
        )

        let store = ScriptedPlatformStore()
        let (coordinator, _) = makeCoordinator(store)
        await coordinator.refresh(engine.session)
        XCTAssertEqual(store.begun, ["traditionalStrengthTraining"], "the workout is open")

        let applied = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-other",
                sessionId: "s-phone-routine",
                sentAt: "2026-07-13T06:30:00Z",
                modality: "isometric_stretching",
                exercises: twoHolds
            )
        )

        XCTAssertEqual(applied, false, "a snapshot for another session is refused while the wrist runs a workout")
        XCTAssertEqual(
            engine.session?.sessionId, wrist.sessionId,
            "the held session is untouched"
        )
        XCTAssertNil(engine.session?.modality, "the Focus never lands on a held session")
        XCTAssertEqual(store.begun.count, 1, "D-78: the open workout is never replaced")
    }

    // MARK: - S-12595 never override, never null, never a late stamp

    func testS12595aDifferentKeyLeavesTheHeldModality() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-first",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:30:00Z",
                modality: "sports"
            )
        )

        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-second",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:31:00Z",
                modality: "isometric_stretching"
            )
        )

        XCTAssertEqual(
            engine.session?.modality, "sports",
            "a held modality keeps its value: never overridden"
        )
    }

    func testS12595bAVoidSessionWithNilKeepsItsNil() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let held = await engine.createSession(
            modality: nil,
            exercises: [strengthSlot("sx-free")]
        )

        let store = ScriptedPlatformStore()
        let (coordinator, _) = makeCoordinator(store)
        await coordinator.refresh(engine.session)
        XCTAssertEqual(store.begun, ["traditionalStrengthTraining"], "the exercises drove the type")

        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-phone",
                sessionId: held.sessionId,
                sentAt: "2026-07-13T06:30:00Z",
                modality: "sports"
            )
        )

        XCTAssertNil(
            engine.session?.modality,
            "a held nil survives a Focus: the stamp is first hearing only"
        )
        XCTAssertEqual(store.begun.count, 1, "the open workout is untouched")

        let source = CountingSensorSource()
        let recorder = WatchSensorRecorder(engine: engine, source: source, clock: harness.clock.call)
        await recorder.sessionChanged(held)
        XCTAssertEqual(
            source.locationPermissionReads, 0,
            "a session with no modality and no distance exercise never asks for location"
        )
        XCTAssertEqual(source.locationSubscriptions, 0, "no location subscription is made")
        source.close()
    }

    func testS12595cKeylessSnapshotKeepsTheHeldModality() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-first",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:30:00Z",
                modality: "sports"
            )
        )

        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-second",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:31:00Z"
            )
        )

        XCTAssertEqual(
            engine.session?.modality, "sports",
            "a converged-state frame never nulls the held modality"
        )
    }

    func testS12595dBadValuesKeepTheHeldModality() async throws {
        let harness = Harness()
        let engine = await engineWithoutValidator(harness)
        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-first",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:30:00Z",
                modality: "sports"
            )
        )

        let second = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-null",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:31:00Z",
                modality: NSNull()
            )
        )
        XCTAssertEqual(second, true)
        XCTAssertEqual(engine.session?.modality, "sports", "null never nulls the held value")

        let third = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-empty",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:32:00Z",
                modality: ""
            )
        )
        XCTAssertEqual(third, true)
        XCTAssertEqual(engine.session?.modality, "sports")

        let fourth = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-number",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:33:00Z",
                modality: NSNumber(value: 7)
            )
        )
        XCTAssertEqual(fourth, true)
        XCTAssertEqual(engine.session?.modality, "sports")
    }

    func testS12595eANewerSnapshotCannotStampALateFocus() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-keyless",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:30:00Z"
            )
        )
        XCTAssertNil(engine.session?.modality, "the first hearing created the row with none")

        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-later",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:31:00Z",
                modality: "sports"
            )
        )

        XCTAssertNil(
            engine.session?.modality,
            "the first hearing already happened: a later snapshot is not one"
        )
    }

    // MARK: - S-12596 the Focus survives a relaunch

    func testS12596TheFocusSurvivesARestoreAndAKeylessSnapshot() async throws {
        let harness = Harness()

        do {
            let engine = await harness.runningEngine()
            _ = try await engine.applyMessage(
                focusSnapshot(
                    messageId: "msg-sports",
                    sessionId: "s-followed",
                    sentAt: "2026-07-13T06:30:00Z",
                    modality: "sports"
                )
            )
        }

        // Relaunch: a new engine over the same store, restored.
        let relaunched = await engineWithoutValidator(harness)
        XCTAssertEqual(
            relaunched.session?.modality, "sports",
            "the restored session kept the Focus its row was created with"
        )

        _ = try await relaunched.applyMessage(
            focusSnapshot(
                messageId: "msg-keyless",
                sessionId: "s-followed",
                sentAt: "2026-07-13T06:31:00Z"
            )
        )
        XCTAssertEqual(
            relaunched.session?.modality, "sports",
            "a keyless snapshot after the restore nulls nothing"
        )

        // A rebuilt coordinator refreshes against the platform whose workout is
        // already open: without the stamp a second begin would be asked for.
        let store = RecordingGpsOutdoorStore()
        let platform = WatchPlatformWorkout(store: store)
        let first = WatchWorkoutCoordinator(platform: platform)
        await first.refresh(relaunched.session)
        XCTAssertEqual(store.begins.count, 1, "the workout opened once")
    }

    // MARK: - S-12597 old phone, old watch, malformed key

    func testS12597aAKeylessSnapshotBehavesAsBefore() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-old-phone",
                sessionId: "s-old-phone",
                sentAt: "2026-07-13T06:30:00Z",
                revision: 7,
                exercises: threeStrength
            )
        )

        XCTAssertNil(engine.session?.modality, "no key, no modality, as before")

        let store = RecordingGpsOutdoorStore()
        let coordinator = makeOutdoorCoordinator(store)
        await coordinator.refresh(engine.session)
        XCTAssertEqual(
            store.begins.map(\.activityType),
            ["traditionalStrengthTraining"],
            "the Health type is the exercises' majority, as before"
        )
        XCTAssertEqual(store.begins.map(\.outdoors), [false])
    }

    func testS12597bAValidatorlessEngineIgnoresAnUnknownFutureKey() async throws {
        let harness = Harness()
        let engine = await engineWithoutValidator(harness)
        var envelope = focusSnapshot(
            messageId: "msg-future",
            sessionId: "s-future",
            sentAt: "2026-07-13T06:30:00Z"
        )
        var payload = (envelope["payload"] as? [String: Any]) ?? [:]
        payload["futureKey"] = NSNumber(value: 1)
        envelope["payload"] = payload

        let applied = try await engine.applyMessage(envelope)

        XCTAssertEqual(applied, true, "the shipped watch (no validator) ignores unknown keys")
        XCTAssertEqual(engine.session?.sessionId, "s-future")
        XCTAssertNil(engine.session?.modality)
    }

    func testS12597cAValidatingReceiverRefusesABadModalityWhole() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let before = await harness.store.readAll().sessions.count

        do {
            _ = try await engine.applyMessage(
                focusSnapshot(
                    messageId: "msg-bad-type",
                    sessionId: "s-bad-type",
                    sentAt: "2026-07-13T06:30:00Z",
                    modality: NSNumber(value: 7)
                )
            )
            XCTFail("the validator refuses a non-string modality whole")
        } catch let rejected as WatchEmissionRejected {
            XCTAssertTrue(
                rejected.rejections.contains {
                    $0.code == "invalid_type" && $0.path == "$.payload.modality"
                },
                "the refusal names invalid_type at $.payload.modality: \(rejected)"
            )
        }
        let after = await harness.store.readAll()
        XCTAssertEqual(
            after.sessions.count,
            before,
            "a refused snapshot writes nothing"
        )
        XCTAssertNil(engine.session, "nothing is made current")
    }

    // MARK: - S-12598 the followed end carries the Focus

    func testS12598AFollowedPhoneSessionSendsItsFocusAndValidates() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        _ = try await engine.applyMessage(
            focusSnapshot(
                messageId: "msg-focus-followed",
                sessionId: "s-phone-followed",
                sentAt: "2026-07-13T06:30:00Z",
                modality: "isometric_stretching"
            )
        )

        _ = await engine.finishSession()

        let end = try XCTUnwrap(
            engine.observations.first {
                $0.kind == WatchObservationKind.sessionEnd
            }?.payload,
            "the followed session's end"
        )
        XCTAssertEqual(end["followed"] as? Bool, true, "the wrist followed the phone's session")
        XCTAssertEqual(
            end["modality"] as? String, "isometric_stretching",
            "the end carries the Focus the snapshot created the row with"
        )

        let validator = Harness.validator()
        let pending = engine.pendingObservations()
        XCTAssertFalse(pending.isEmpty, "the end is owed to the phone")
        for envelope in pending {
            let rejections = validator.validateEnvelope(envelope)
            XCTAssertTrue(
                rejections.isEmpty,
                "the emitted frame conforms: \(rejections)"
            )
        }
    }
}
