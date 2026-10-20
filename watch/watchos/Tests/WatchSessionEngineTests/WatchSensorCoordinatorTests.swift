//
//  WatchSensorCoordinatorTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-10-10-19d-watch-heart-rate-and-steps-plan/2026-10-10-19d-watch-heart-rate-and-steps-plan.md`
//  — the sensors follow the session: one subscription per active session, a
//  change of session id is a stop then a start, every non-active status stops
//  them, and a refusal is asked about once per session rather than once per
//  refresh.
//
//  Scenario mapping:
//    S-3100 start                            → `testS3100...`
//    S-3101 end                              → `testS3101...`
//    S-3102 a replaced session               → `testS3102...`
//    S-3103 idempotent across refreshes      → `testS3103...`
//    S-3104 refused probe                    → `testS3104...`
//    S-3105 the serial tail                  → `testS3105...`
//    S-3106 relaunch onto a live session     → `testS3106...`
//    S-3107 the session end carries the pair → `testS3107...`
//    S-3108 the live label                   → `testS3108...`
//    S-3111 the tail while a start is parked → `testS3111...`
//    S-3112 the refusal is asked once        → `testS3112...`
//    S-3113 one kind granted, one refused    → `testS3113...`
//    S-3115 a timed entry's step total       → `testS3115...`
//
//  The seam a test can park is the source: `WatchSensorCoordinator` takes the
//  concrete `WatchSensorRecorder`, so parking a permission probe parks the
//  recorder inside `start`, which is the same effect (D-2109). `FakeSensorSource`
//  (`WatchSensorRecordingTests.swift`) is shared and closed to subclassing, so
//  `CountingSource` and `GatedSource` are declared here.
//
//  Nothing here touches HealthKit or a device: the whole file runs on macOS
//  beside `swift test`.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// Hardware that refuses every probe and counts how often it was asked.
///
/// S-3104 and S-3112 assert the count, not the answer: the session id is
/// recorded before the source is asked, so a refusal is asked about once per
/// session however often the surface refreshes. Declared here, not beside
/// `FakeSensorSource`: that fake is shared with another suite and is closed to
/// subclassing.
final class CountingSource: WatchSensorSource {
    private(set) var heartRateProbes = 0
    private(set) var locationProbes = 0
    private(set) var stepsProbes = 0

    private(set) var heartRateSubscriptions = 0
    private(set) var locationSubscriptions = 0
    private(set) var stepsSubscriptions = 0

    func heartRatePermission() async -> WatchSensorPermission {
        heartRateProbes += 1
        return .denied
    }

    func locationPermission() async -> WatchSensorPermission {
        locationProbes += 1
        return .denied
    }

    func stepsPermission() async -> WatchSensorPermission {
        stepsProbes += 1
        return .denied
    }

    func heartRate() -> AsyncStream<Double> {
        heartRateSubscriptions += 1
        return AsyncStream { _ in }
    }

    func location() -> AsyncStream<WatchLocationFix> {
        locationSubscriptions += 1
        return AsyncStream { _ in }
    }

    func steps() -> AsyncStream<Double> {
        stepsSubscriptions += 1
        return AsyncStream { _ in }
    }
}

/// Hardware whose next permission probe parks on a continuation the test holds,
/// with every call recorded so "the calls landed in order and never overlapped"
/// is an assertion rather than an assumption.
///
/// Which probe parks is whichever the recorder reaches first — the heart-rate
/// probe, since `WatchSensorRecorder.start` asks for the beat before the count —
/// and the gate is armed for one probe only, so the probes that follow are
/// answered at once.
final class GatedSource: WatchSensorSource {
    private struct State {
        var armed = false
        var gate: CheckedContinuation<Void, Never>?

        var heartRateProbes = 0
        var stepsProbes = 0
        var heartRateSubscriptions = 0
        var stepsSubscriptions = 0
        var beats: AsyncStream<Double>.Continuation?

        var inFlight = 0
        var raced = false

        /// Records a call on entry; two in flight at once is an overlap.
        mutating func enter() {
            if inFlight > 0 { raced = true }
            inFlight += 1
        }

        mutating func settle() { inFlight -= 1 }

        /// Consumes the arm, so only the next probe parks.
        mutating func takesGate() -> Bool {
            let armed = self.armed
            self.armed = false
            return armed
        }
    }

    private let lock = NSLock()
    private var state = State()

    /// Whether a probe is parked on the gate right now. A parked continuation
    /// is only safe to resume once it has been stored, so a test waits for this.
    var gateIsParked: Bool { withState { $0.gate != nil } }

    var heartRateProbes: Int { withState { $0.heartRateProbes } }
    var stepsProbes: Int { withState { $0.stepsProbes } }
    var heartRateSubscriptions: Int { withState { $0.heartRateSubscriptions } }
    var stepsSubscriptions: Int { withState { $0.stepsSubscriptions } }

    /// Whether two source calls were ever in flight at the same time.
    var overlapped: Bool { withState { $0.raced } }

    /// Parks the next permission probe until `release()`.
    func armGate() { withState { $0.armed = true } }

    /// Releases a probe parked by `armGate()`.
    func release() {
        let parked = withState { state -> CheckedContinuation<Void, Never>? in
            let gate = state.gate
            state.gate = nil
            return gate
        }
        parked?.resume()
    }

    func heartRatePermission() async -> WatchSensorPermission {
        let parked = withState { state -> Bool in
            state.enter()
            state.heartRateProbes += 1
            return state.takesGate()
        }

        if parked {
            await withCheckedContinuation { continuation in
                withState { $0.gate = continuation }
            }
        }

        withState { $0.settle() }
        return .granted
    }

    func locationPermission() async -> WatchSensorPermission { .denied }

    func stepsPermission() async -> WatchSensorPermission {
        let parked = withState { state -> Bool in
            state.enter()
            state.stepsProbes += 1
            return state.takesGate()
        }

        if parked {
            await withCheckedContinuation { continuation in
                withState { $0.gate = continuation }
            }
        }

        withState { $0.settle() }
        return .granted
    }

    func heartRate() -> AsyncStream<Double> {
        withState { $0.heartRateSubscriptions += 1 }
        return AsyncStream { continuation in
            withState { $0.beats = continuation }
        }
    }

    func steps() -> AsyncStream<Double> {
        withState { $0.stepsSubscriptions += 1 }
        return AsyncStream { _ in }
    }

    /// `locationPermission()` answers `.denied`, so the recorder never reaches
    /// here; the stream exists because the protocol requires it.
    func location() -> AsyncStream<WatchLocationFix> {
        AsyncStream { _ in }
    }

    func beat(_ beatsPerMinute: Double) {
        withState { $0.beats }?.yield(beatsPerMinute)
    }

    private func withState<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}

/// The heart-rate rows the engine holds for the session it is on.
private func heartRateRows(_ engine: WatchSessionEngine) -> [WatchSensorSampleRecord] {
    engine.sensorSamples.filter { $0.kind == WatchSensorKind.heartRate }
}

/// The steps rows the engine holds for the session it is on.
private func stepRows(_ engine: WatchSessionEngine) -> [WatchSensorSampleRecord] {
    engine.sensorSamples.filter { $0.kind == WatchSensorKind.steps }
}

final class WatchSensorCoordinatorTests: XCTestCase {

    /// A coordinator over a fresh recorder, with the recorder handed back so a
    /// test can read the live readout off it.
    private func makeCoordinator(
        _ engine: WatchSessionEngine,
        _ harness: Harness,
        _ source: WatchSensorSource
    ) -> (coordinator: WatchSensorCoordinator, recorder: WatchSensorRecorder) {
        let recorder = WatchSensorRecorder(
            engine: engine,
            source: source,
            clock: harness.clock.call
        )
        return (WatchSensorCoordinator(recorder: recorder), recorder)
    }

    /// An active session of `modality`, on a fresh restored engine.
    private func activeSession(
        _ harness: Harness,
        modality: String? = "resistance_lifting",
        exercises: [[String: Any]] = []
    ) async -> (engine: WatchSessionEngine, session: WatchSessionRecord) {
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: modality, exercises: exercises)
        return (engine, session)
    }

    /// An engine whose sessions mint ids of their own, so a replacement session
    /// is a different session rather than the one the wrist already holds.
    private func numberedEngine(
        _ harness: Harness,
        ids: [String] = ["s-1", "s-2"]
    ) async -> WatchSessionEngine {
        var records = 0
        var sessions = 0
        let engine = WatchSessionEngine(
            store: harness.store,
            onEmit: { _ in },
            validator: Harness.validator(),
            clock: harness.clock.call,
            idFactory: {
                records += 1
                return "rec-\(records)"
            },
            sessionIdFactory: {
                sessions += 1
                return ids[min(sessions - 1, ids.count - 1)]
            }
        )
        await engine.restore()
        return engine
    }

    /// Spins the executor until `condition` holds — a poll to a bound, never a
    /// wall-clock threshold — so a parked probe is observed where it actually
    /// is. The bound turns a stuck call into a failure rather than a hang.
    private func yieldUntil(
        _ condition: () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("timed out waiting until \(message)", file: file, line: line)
    }

    /// A bounded number of scheduler yields — no clock — so work already
    /// delivered to another task is observed without a sleep.
    private func drainYields(_ count: Int = 1_000) async {
        for _ in 0..<count { await Task.yield() }
    }

    /// An instant as the wire spells it.
    private func instant(_ text: String) -> Date {
        (try? parseUtcIso(text)) ?? Date(timeIntervalSince1970: 0)
    }

    /// The named event as it left the wrist, read off the emitted observations.
    private func emittedEvent(_ harness: Harness, kind: String) -> [String: Any]? {
        for envelope in harness.emitted {
            let events = (envelope["payload"] as? [String: Any])?["events"] as? [[String: Any]]
            if let found = events?.first(where: { $0["kind"] as? String == kind }) {
                return found
            }
        }
        return nil
    }

    // MARK: - S-3100 start

    func testS3100StartSubscribesAndTheFirstBeatIsStored() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        let (engine, session) = await activeSession(harness)
        let (coordinator, recorder) = makeCoordinator(engine, harness, source)

        await coordinator.refresh(session)

        XCTAssertEqual(source.heartRateSubscriptions, 1, "the beat is listened to once the session is active")
        XCTAssertEqual(source.stepsSubscriptions, 1, "and so is the count")
        XCTAssertEqual(coordinator.recordingSessionId, session.sessionId, "the session the sensors belong to")

        source.beat(96)
        await eventually { heartRateRows(engine).count == 1 }

        XCTAssertEqual(recorder.readings.heartRate, 96, "the readout is the newest stored beat")
        XCTAssertEqual(heartRateRows(engine).map(\.value), [96])
        XCTAssertEqual(heartRateRows(engine).first?.sessionId, session.sessionId)
    }

    // MARK: - S-3101 end

    func testS3101EndStopsAndClearsTheRecordingSessionId() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        let (engine, session) = await activeSession(harness)
        let (coordinator, _) = makeCoordinator(engine, harness, source)

        await coordinator.refresh(session)
        source.beat(96)
        await eventually { heartRateRows(engine).count == 1 }
        harness.clock.advance(2)

        let completed = await engine.finishSession()
        XCTAssertEqual(completed.status, WatchSessionStatus.completed)

        await coordinator.refresh(completed)
        // The steps stream reports its own termination, and the two are
        // cancelled together — so this is the sign that both consumers are gone.
        await eventually { source.stepsStreamEnded }
        await drainYields()

        source.beat(120)
        await drainYields()

        XCTAssertNil(coordinator.recordingSessionId, "a session that is over records nothing")
        XCTAssertEqual(heartRateRows(engine).map(\.value), [96], "the beat after the end reached nothing")
        XCTAssertEqual(source.heartRateSubscriptions, 1, "and no second subscription was made")
    }

    // MARK: - S-3102 a replaced session

    func testS3102AReplacedSessionStopsOneAndStartsTheOther() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        let engine = await numberedEngine(harness)
        let first = await engine.createSession(modality: "resistance_lifting")
        let (coordinator, _) = makeCoordinator(engine, harness, source)

        await coordinator.refresh(first)
        source.beat(96)
        await eventually { heartRateRows(engine).count == 1 }
        XCTAssertEqual(coordinator.recordingSessionId, "s-1")

        // The phone's reset: the first session is given up and a new one, with
        // an id of its own, takes the slot.
        _ = await engine.abandonSession()
        let second = await engine.createSession(modality: "resistance_lifting")
        XCTAssertNotEqual(first.sessionId, second.sessionId, "the replacement is a different session")

        await coordinator.refresh(second)
        await eventually { source.stepsStreamEnded }

        XCTAssertEqual(coordinator.recordingSessionId, "s-2", "the id follows the new session")
        XCTAssertEqual(source.heartRateSubscriptions, 2, "exactly one stop then one start")
        XCTAssertEqual(source.stepsSubscriptions, 2)

        source.beat(120)
        await eventually { heartRateRows(engine).count == 1 }

        XCTAssertEqual(heartRateRows(engine).map(\.value), [120])
        XCTAssertEqual(heartRateRows(engine).first?.sessionId, "s-2", "the beat is stored against the new session")
    }

    // MARK: - S-3103 idempotent

    func testS3103FiveRefreshesSubscribeOnce() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        let (engine, session) = await activeSession(harness)
        let (coordinator, _) = makeCoordinator(engine, harness, source)

        for _ in 0..<5 {
            await coordinator.refresh(session)
        }

        XCTAssertEqual(source.heartRateSubscriptions, 1, "one subscription, however often the surface refreshes")
        XCTAssertEqual(source.stepsSubscriptions, 1)
        XCTAssertEqual(coordinator.recordingSessionId, session.sessionId)
    }

    // MARK: - S-3104 a refused probe

    func testS3104RefusedProbesAreAskedOnceAndLoggingIsUnaffected() async throws {
        let harness = Harness()
        let source = CountingSource()
        let (engine, session) = await activeSession(
            harness,
            modality: "cardio_endurance",
            exercises: [exercise("sx-bench")]
        )
        let (coordinator, recorder) = makeCoordinator(engine, harness, source)

        await coordinator.refresh(session)
        await coordinator.refresh(session)

        XCTAssertEqual(source.heartRateSubscriptions, 0, "a refused probe subscribes to nothing")
        XCTAssertEqual(source.stepsSubscriptions, 0)
        XCTAssertEqual(source.locationSubscriptions, 0)
        XCTAssertTrue(engine.sensorSamples.isEmpty, "and nothing is measured")
        XCTAssertEqual(source.heartRateProbes, 1, "the refusal is asked about once, not once per refresh")
        XCTAssertEqual(source.stepsProbes, 1)
        XCTAssertEqual(source.locationProbes, 1)
        XCTAssertEqual(coordinator.recordingSessionId, session.sessionId, "the session is still the one recorded")

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call, sensors: recorder)
        XCTAssertNil(surface.heartRateLabel, "no reading, no label")

        let logged = try await surface.log()
        XCTAssertEqual(logged.kind, WatchObservationKind.set, "logging is unaffected")
        XCTAssertTrue(
            engine.observations.contains { $0.recordId == logged.recordId },
            "and the set is stored"
        )
    }

    // MARK: - S-3105 the serial tail

    func testS3105TwoOverlappingRefreshesLandInOrder() async throws {
        let harness = Harness()
        let source = GatedSource()
        let (engine, session) = await activeSession(harness)
        let (coordinator, _) = makeCoordinator(engine, harness, source)

        source.armGate()
        let started = Task { await coordinator.refresh(session) }
        await yieldUntil({ source.gateIsParked }, "the start parks inside the source's probe")

        XCTAssertEqual(
            coordinator.recordingSessionId,
            session.sessionId,
            "the id is recorded before the source is asked, so the start is already this session's"
        )
        XCTAssertEqual(source.heartRateSubscriptions, 0, "the subscription waits for the probe to answer")

        let ended = Task { await coordinator.refresh(nil) }
        await drainYields()

        XCTAssertEqual(
            coordinator.recordingSessionId,
            session.sessionId,
            "the end waits its turn behind the parked start rather than clearing its id mid-flight"
        )
        XCTAssertEqual(source.heartRateProbes, 1, "nothing else reached the source")
        XCTAssertFalse(source.overlapped, "and no two source calls were in flight at once")

        source.release()
        await started.value
        await ended.value

        XCTAssertEqual(source.heartRateSubscriptions, 1, "one start, however the two refreshes interleaved")
        XCTAssertNil(coordinator.recordingSessionId, "the end that waited ran last")
    }

    // MARK: - S-3106 relaunch onto a live session

    func testS3106ARelaunchOntoARestoredActiveSessionStartsSensors() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        let first = await harness.runningEngine()
        _ = await first.createSession(modality: "cardio_endurance", exercises: [exercise("sx-run")])

        // A fresh engine over the same storage — a relaunch, not a hand-over.
        let restored = await harness.runningEngine()
        XCTAssertEqual(restored.session?.status, WatchSessionStatus.active, "the session survived the kill")

        let (coordinator, _) = makeCoordinator(restored, harness, source)
        await coordinator.refresh(restored.session)

        XCTAssertEqual(source.heartRateSubscriptions, 1, "a relaunch starts the sensors again")
        XCTAssertEqual(source.stepsSubscriptions, 1)

        source.beat(120)
        await eventually { heartRateRows(restored).map(\.value) == [120] }
    }

    // MARK: - S-3107 the session end carries the pair

    func testS3107TheSessionEndCarriesTheHeartRateTheSensorsFedIt() async throws {
        // With the sensors recording.
        do {
            let harness = Harness()
            let source = FakeSensorSource()
            let (engine, session) = await activeSession(
                harness,
                modality: "cardio_endurance",
                exercises: [exercise("sx-run")]
            )
            let (coordinator, _) = makeCoordinator(engine, harness, source)
            await coordinator.refresh(session)

            var expected = 0
            for bpm in [120.0, 140, 160] {
                expected += 1
                harness.clock.advance(2)
                source.beat(bpm)
                await eventually { heartRateRows(engine).count == expected }
            }

            _ = await engine.finishSession()

            let end = try XCTUnwrap(
                emittedEvent(harness, kind: WatchObservationKind.sessionEnd),
                "the wrist's end is emitted"
            )
            XCTAssertEqual(numericValue(end["avgHeartRateBpm"]), 140, "the mean of 120, 140 and 160")
            XCTAssertEqual(numericValue(end["maxHeartRateBpm"]), 160, "the largest of them")
        }

        // With nothing measured.
        do {
            let harness = Harness()
            let source = FakeSensorSource()
            let (engine, session) = await activeSession(
                harness,
                modality: "cardio_endurance",
                exercises: [exercise("sx-run")]
            )
            let (coordinator, _) = makeCoordinator(engine, harness, source)
            await coordinator.refresh(session)

            _ = await engine.finishSession()

            let end = try XCTUnwrap(emittedEvent(harness, kind: WatchObservationKind.sessionEnd))
            XCTAssertNil(end["avgHeartRateBpm"], "no reading, no pair — never a zero")
            XCTAssertNil(end["maxHeartRateBpm"])
        }
    }

    // MARK: - S-3108 the live label

    func testS3108TheLiveLabelShowsTheNewestBeat() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        let (engine, session) = await activeSession(
            harness,
            modality: "cardio_endurance",
            exercises: [exercise("sx-run")]
        )
        let (coordinator, recorder) = makeCoordinator(engine, harness, source)
        await coordinator.refresh(session)

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call, sensors: recorder)
        XCTAssertNil(surface.heartRateLabel, "nothing measured yet, so no number")

        source.beat(142)
        await eventually { recorder.readings.heartRate == 142 }

        XCTAssertEqual(surface.heartRateLabel, "142", "the line the view prints beside the unit")
    }

    // MARK: - S-3111 the tail while a start is parked

    func testS3111TheSerialTailHoldsWhileAStartIsParked() async throws {
        let harness = Harness()
        let source = GatedSource()
        let engine = await numberedEngine(harness)
        let first = await engine.createSession(modality: "resistance_lifting")
        let (coordinator, _) = makeCoordinator(engine, harness, source)

        await coordinator.refresh(first)
        source.beat(96)
        await eventually { heartRateRows(engine).count == 1 }

        _ = await engine.abandonSession()
        let second = await engine.createSession(modality: "resistance_lifting")

        source.armGate()
        let replaced = Task { await coordinator.refresh(second) }
        await yieldUntil({ source.gateIsParked }, "the replacement parks inside the source's probe")
        XCTAssertEqual(coordinator.recordingSessionId, "s-2", "the start's id is recorded before it asks")

        // The end of the session arrives while the start is still parked.
        let ended = Task { await coordinator.refresh(nil) }
        await drainYields()

        source.release()
        await replaced.value
        await ended.value

        XCTAssertNil(coordinator.recordingSessionId, "the end ran after the start it waited for")
        XCTAssertEqual(source.heartRateSubscriptions, 2, "the replacement started")

        source.beat(120)
        await drainYields()

        XCTAssertEqual(
            heartRateRows(engine).map(\.value),
            [],
            "the parked start's stream was cancelled by the end that waited for it, so the beat reached nothing"
        )
    }

    // MARK: - S-3112 the refusal is asked once

    func testS3112TheRefusedProbeIsAskedOncePerSession() async throws {
        let harness = Harness()
        let source = CountingSource()
        let (engine, session) = await activeSession(
            harness,
            modality: "cardio_endurance",
            exercises: [exercise("sx-bench")]
        )
        let (coordinator, recorder) = makeCoordinator(engine, harness, source)

        await coordinator.refresh(session)
        await coordinator.refresh(session)

        XCTAssertEqual(source.heartRateSubscriptions, 0)
        XCTAssertEqual(source.stepsSubscriptions, 0)
        XCTAssertEqual(source.heartRateProbes, 1, "dropping the nil guard on the start branch would ask again")
        XCTAssertEqual(source.stepsProbes, 1)
        XCTAssertTrue(engine.sensorSamples.isEmpty)

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call, sensors: recorder)
        XCTAssertNil(surface.heartRateLabel)

        let logged = try await surface.log()
        XCTAssertEqual(logged.kind, WatchObservationKind.set, "a refusal cannot fail a log")
        XCTAssertTrue(
            engine.observations.contains { $0.recordId == logged.recordId },
            "and the set is stored"
        )
    }

    // MARK: - S-3113 one kind granted, the other refused

    func testS3113OneKindGrantedTheOtherRefused() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        source.heartRateGrant = .granted
        source.stepsGrant = .denied
        let (engine, session) = await activeSession(harness)
        let (coordinator, recorder) = makeCoordinator(engine, harness, source)

        await coordinator.refresh(session)
        source.beat(150)
        source.count(300)
        await eventually { heartRateRows(engine).count == 1 }

        XCTAssertEqual(source.heartRateSubscriptions, 1)
        XCTAssertEqual(source.stepsSubscriptions, 0, "the refused kind subscribes to nothing")
        XCTAssertEqual(heartRateRows(engine).map(\.value), [150])
        XCTAssertEqual(heartRateRows(engine).first?.sessionId, session.sessionId)
        XCTAssertTrue(stepRows(engine).isEmpty, "and nothing is counted")

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call, sensors: recorder)
        XCTAssertEqual(surface.heartRateLabel, "150", "the granted kind is what the line shows")
    }

    // MARK: - S-3115 a timed entry's step total

    func testS3115ATimedEntryCarriesTheStepTotalTheRecorderFedIt() async throws {
        let harness = Harness()
        let source = FakeSensorSource()
        harness.clock.now = instant("2026-09-25T10:00:00Z")
        let (engine, session) = await activeSession(
            harness,
            modality: "cardio_endurance",
            exercises: [[
                "sessionExerciseId": "sx-run",
                "exerciseId": "ex-run",
                "name": "Run",
                "capabilities": ["time", "distance"],
            ]]
        )
        let (coordinator, recorder) = makeCoordinator(engine, harness, source)
        await coordinator.refresh(session)

        // A count before the work window is the baseline the chain starts from.
        source.count(500)
        await eventually { stepRows(engine).count == 1 }

        for count in [800.0, 1600, 3200] {
            harness.clock.advance(120)
            source.count(count)
            let expected = stepRows(engine).count + 1
            await eventually { stepRows(engine).count == expected }
        }
        XCTAssertEqual(stepRows(engine).map(\.value), [500, 800, 1600, 3200], "four counts, one per instant")

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call, sensors: recorder)
        harness.clock.now = instant("2026-09-25T10:02:00Z")
        await surface.startWork()
        harness.clock.now = instant("2026-09-25T10:10:00Z")
        let run = try await surface.log()

        XCTAssertEqual(
            numericValue(run.payload["steps"]),
            2700,
            "the chain 500 -> 800 -> 1600 -> 3200: 300 + 800 + 1600 inside the open window"
        )
    }
}
