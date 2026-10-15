//
//  WatchWorkoutCoordinatorTests.swift
//  WatchSessionEngineTests
//
//  The native watchOS half of
//  `docs/plans/2026-10-10-19c-watch-keep-alive-plan/2026-10-10-19c-watch-keep-alive-plan.md`
//  — the workout follows the session: at most one platform workout is open at a
//  time, one begin and one end per session however often the surface refreshes,
//  and a leftover from a previous process is closed before a session opens
//  another.
//
//  Scenario mapping:
//    S-1500 opens for an active session          → `testS1500...`
//    S-1501 idempotent across refreshes          → `testS1501...`
//    S-1502 closes when the session ends         → `testS1502...`
//    S-1503 relaunch ends the stranded workout   → `testS1503...`
//    S-1504 a different session replaces the one → `testS1504...`
//    S-1505 denial is not failure                → `testS1505...`
//    S-1507 a launch with nothing to do          → `testS1507...`
//    S-1508 two racing refreshes open one        → `testS1508...`
//    S-1510 a killed workout with no session     → `testS1510...`
//
//  Nothing here touches the platform's health service: `ScriptedPlatformStore`
//  is the seam the coordinator is asserted through, so the whole file runs on
//  macOS beside `swift test`.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// The health store as a script: what it holds open, what it refuses, and every
/// call in the order it arrived.
///
/// A call is recorded on entry and again on exit, and any period with two calls
/// in flight is remembered as `overlapped` — which is what turns "the serial
/// tail never races a begin against an end" into an assertion. `suspendNextBegin`
/// parks the next begin on a continuation the test holds, so two refreshes can be
/// made to overlap on purpose.
///
/// Declared here, not beside `FakePlatformStore`
/// (`WatchSensorRecordingTests.swift`): that fake is shared with another suite
/// and is closed to subclassing.
final class ScriptedPlatformStore: WatchPlatformWorkoutStore {
    /// Everything the fake remembers, behind one lock: two refreshes can be made
    /// to overlap (S-1508), so the test and the coordinator do reach it together.
    private struct State {
        var stranded: [String]
        var begins: [String] = []
        var ends = 0
        var log: [String] = []
        var inFlight = 0
        var raced = false
        var suspend = false
        var gate: CheckedContinuation<Void, Never>?

        /// Records a call on entry; two in flight at once is a race.
        mutating func enter(_ call: String) {
            if inFlight > 0 { raced = true }
            inFlight += 1
            log.append(call)
        }

        mutating func settle() { inFlight -= 1 }
    }

    private let lock = NSLock()
    private var state: State

    /// Whether a begin is answered with nothing, as a refused or unavailable
    /// health permission is (S-1505).
    let deniesBegins: Bool

    init(inProgress: [String] = [], deniesBegins: Bool = false) {
        self.state = State(stranded: inProgress)
        self.deniesBegins = deniesBegins
    }

    /// What the health store reports as still in progress.
    var inProgress: [String] { withState { $0.stranded } }

    /// Every activity type a begin asked for, in order.
    var begun: [String] { withState { $0.begins } }

    /// How many ends reached the store.
    var ended: Int { withState { $0.ends } }

    /// Every call, in the order it arrived: `begin(<name>)`, `end`,
    /// `inProgressActivityTypes`.
    var calls: [String] { withState { $0.log } }

    /// Whether two calls were ever in flight at the same time.
    var overlapped: Bool { withState { $0.raced } }

    /// Whether a begin is parked on the gate right now. S-1508 waits for this
    /// before it releases the gate: a parked continuation is only safe to
    /// resume once it has been stored.
    var beginIsParked: Bool { withState { $0.gate != nil } }

    /// Parks the next begin until `resumeBegin()`.
    var suspendNextBegin: Bool {
        get { withState { $0.suspend } }
        set { withState { $0.suspend = newValue } }
    }

    /// Releases a begin parked by `suspendNextBegin`.
    func resumeBegin() {
        let parked = withState { state -> CheckedContinuation<Void, Never>? in
            let gate = state.gate
            state.gate = nil
            return gate
        }
        parked?.resume()
    }

    func begin(_ activityType: String) async {
        let parked = withState { state -> Bool in
            state.enter("begin(\(activityType))")
            state.begins.append(activityType)
            let suspend = state.suspend
            state.suspend = false
            return suspend
        }

        if parked {
            await withCheckedContinuation { continuation in
                withState { $0.gate = continuation }
            }
        }

        if !deniesBegins {
            withState { $0.stranded.append(activityType) }
        }

        withState { $0.settle() }
    }

    func end() async {
        withState { state in
            state.enter("end")
            state.ends += 1
            if !state.stranded.isEmpty { state.stranded.removeFirst() }
            state.settle()
        }
    }

    func inProgressActivityTypes() async -> [String] {
        withState { state in
            state.enter("inProgressActivityTypes")
            let reported = state.stranded
            state.settle()
            return reported
        }
    }

    private func withState<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}

final class WatchWorkoutCoordinatorTests: XCTestCase {

    /// A coordinator over a scripted store, with the platform handed back so a
    /// test can read what the watch has open.
    private func makeCoordinator(
        _ store: ScriptedPlatformStore
    ) -> (coordinator: WatchWorkoutCoordinator, platform: WatchPlatformWorkout) {
        let platform = WatchPlatformWorkout(store: store)
        return (WatchWorkoutCoordinator(platform: platform), platform)
    }

    /// An active session of `modality`, on a fresh restored engine.
    private func activeSession(
        _ harness: Harness,
        modality: String? = "sports"
    ) async -> WatchSessionRecord {
        let engine = await harness.runningEngine()
        return await engine.createSession(modality: modality)
    }

    /// Spins the executor until `condition` holds — a poll to a bound, never a
    /// wall-clock threshold — so an overlapping refresh (S-1508) is observed
    /// where it actually is. The bound turns a stuck call into a failure rather
    /// than a hang.
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

    func testS1500OpensForAnActiveSession() async throws {
        let harness = Harness()
        let session = await activeSession(harness)

        XCTAssertEqual(
            WatchWorkoutLifecycle.action(session: session, running: nil),
            WatchWorkoutAction.start,
            "an active session with nothing running is a start"
        )
        XCTAssertEqual(
            WatchWorkoutLifecycle.action(session: session, running: WatchActivityTypes.generic),
            WatchWorkoutAction.none,
            "an active session with its workout already open is nothing to do"
        )
        XCTAssertEqual(
            WatchWorkoutLifecycle.action(session: nil, running: WatchActivityTypes.generic),
            WatchWorkoutAction.end,
            "a workout nobody's session owns is an end"
        )

        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)
        await coordinator.refresh(session)

        XCTAssertEqual(store.begun, ["other"], "sports registers as the table's generic type")
        XCTAssertEqual(store.ended, 0, "nothing was open to close")
        XCTAssertEqual(platform.running?.watchOs, "other", "and the watch holds it")
    }

    func testS1501IdempotentAcrossFiveRefreshes() async throws {
        let harness = Harness()
        let session = await activeSession(harness)
        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)

        for _ in 0..<5 {
            await coordinator.refresh(session)
        }

        XCTAssertEqual(store.begun.count, 1, "one begin, however often the surface refreshes")
        XCTAssertEqual(store.ended, 0, "and the workout it opened stays open")
        XCTAssertEqual(platform.running?.watchOs, "other")
    }

    func testS1502ClosesWhenTheSessionEnds() async throws {
        // Completed.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let store = ScriptedPlatformStore()
            let (coordinator, platform) = makeCoordinator(store)

            await coordinator.refresh(await engine.createSession(modality: "sports"))
            let completed = await engine.finishSession()

            XCTAssertEqual(
                WatchWorkoutLifecycle.action(session: completed, running: platform.running),
                WatchWorkoutAction.end,
                "a completed session closes its workout"
            )
            await coordinator.refresh(completed)
            XCTAssertEqual(store.ended, 1)

            await coordinator.refresh(completed)
            XCTAssertEqual(store.ended, 1, "a second refresh adds nothing")
            XCTAssertNil(platform.running)
        }

        // Abandoned.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let store = ScriptedPlatformStore()
            let (coordinator, platform) = makeCoordinator(store)

            await coordinator.refresh(await engine.createSession(modality: "sports"))
            let abandoned = await engine.abandonSession()

            XCTAssertEqual(
                WatchWorkoutLifecycle.action(session: abandoned, running: platform.running),
                WatchWorkoutAction.end,
                "an abandoned session closes its workout"
            )
            await coordinator.refresh(abandoned)
            XCTAssertEqual(store.ended, 1)

            await coordinator.refresh(abandoned)
            XCTAssertEqual(store.ended, 1, "a second refresh adds nothing")
            XCTAssertNil(platform.running)
        }

        // Gone.
        do {
            let harness = Harness()
            let engine = await harness.runningEngine()
            let store = ScriptedPlatformStore()
            let (coordinator, platform) = makeCoordinator(store)

            await coordinator.refresh(await engine.createSession(modality: "sports"))

            XCTAssertEqual(
                WatchWorkoutLifecycle.action(session: nil, running: platform.running),
                WatchWorkoutAction.end,
                "a session that is gone closes its workout"
            )
            await coordinator.refresh(nil)
            XCTAssertEqual(store.ended, 1)

            await coordinator.refresh(nil)
            XCTAssertEqual(store.ended, 1, "a second refresh adds nothing")
            XCTAssertNil(platform.running)
        }
    }

    func testS1507ALaunchWithNothingToDo() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        XCTAssertNil(engine.session, "a first install has no session at all")

        let store = ScriptedPlatformStore()
        let (coordinator, _) = makeCoordinator(store)

        await coordinator.recoverInProgress()
        await coordinator.refresh(engine.session)

        XCTAssertEqual(store.calls, ["inProgressActivityTypes"], "one question, no begin, no end")
        XCTAssertEqual(
            store.calls.filter { $0 == "inProgressActivityTypes" }.count,
            1,
            "and the no-op refresh does not ask the health store a second time"
        )
    }

    func testS1503RelaunchEndsTheStrandedWorkoutThenOpensTheSessions() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: "cardio_endurance")

        // A previous process was killed with a workout still open.
        let store = ScriptedPlatformStore(inProgress: ["flexibility"])
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.recoverInProgress()
        await coordinator.refresh(session)

        XCTAssertEqual(
            store.calls,
            ["inProgressActivityTypes", "end", "begin(running)"],
            "the stranded workout is closed before the session opens its own"
        )
        XCTAssertEqual(platform.running?.watchOs, "running", "and the session's workout is the one left open")
    }

    func testS1510AKilledWorkoutWithNoSessionToReplaceIt() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        XCTAssertNil(engine.session, "the session was ended before the process was killed")

        let store = ScriptedPlatformStore(inProgress: ["flexibility"])
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.recoverInProgress()
        await coordinator.refresh(engine.session)

        XCTAssertEqual(
            store.calls,
            ["inProgressActivityTypes", "end"],
            "the stranded workout is closed and there is no session to open another"
        )
        XCTAssertNil(platform.running, "nothing is left open")

        await coordinator.recoverInProgress()
        XCTAssertEqual(store.ended, 1, "the second recovery finds nothing stranded and adds no end")
    }

    func testS1504ADifferentSessionReplacesTheRunningOne() async throws {
        let harnessA = Harness()
        let engineA = await harnessA.runningEngine()
        let sessionA = await engineA.createSession(modality: "sports")

        let store = ScriptedPlatformStore()
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.refresh(sessionA)
        XCTAssertEqual(store.begun, ["other"], "A's workout is open")

        // The phone's reset: a new session with an id of its own.
        let harnessB = Harness(sessionId: "s-watch-2")
        let engineB = await harnessB.runningEngine()
        let sessionB = await engineB.createSession(modality: "cardio_endurance")
        XCTAssertNotEqual(sessionA.sessionId, sessionB.sessionId, "the replacement is a different session")

        await engineA.abandonSession()
        await coordinator.refresh(sessionB)

        XCTAssertEqual(store.ended, 1, "A's workout is closed exactly once")
        XCTAssertEqual(store.begun, ["other", "running"], "and exactly one new begin opens B's")
        XCTAssertEqual(
            store.calls,
            ["begin(other)", "end", "begin(running)"],
            "the new begin never precedes the end: two workouts are never open at once"
        )
        XCTAssertFalse(store.overlapped, "and the end never raced the begin")
        XCTAssertEqual(platform.running?.watchOs, "running", "B's is the one left open")
    }

    func testS1505DenialIsNotFailure() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: "sports")

        // A refused or unavailable health permission: a begin is answered with
        // nothing at all.
        let store = ScriptedPlatformStore(deniesBegins: true)
        let (coordinator, platform) = makeCoordinator(store)

        await coordinator.refresh(session)
        XCTAssertEqual(store.begun, ["other"], "the store was asked once")
        XCTAssertEqual(store.ended, 0, "and nothing was open to close")
        XCTAssertEqual(platform.running?.watchOs, "other", "the registration is recorded however the store answered")

        await coordinator.refresh(session)
        await coordinator.refresh(session)
        XCTAssertEqual(store.begun.count, 1, "a refusal is not retried while the same session is live")

        try await engine.appendObservation(setEvent(harness.clock, entryId: "e-1"))
        XCTAssertEqual(
            engine.pendingObservations().count,
            1,
            "logging a set afterwards stores the observation as usual"
        )
    }

    func testS1508TwoRacingRefreshesOpenOneWorkout() async throws {
        let harness = Harness()
        let engine = await harness.runningEngine()
        let session = await engine.createSession(modality: "cardio_endurance")

        let store = ScriptedPlatformStore()
        store.suspendNextBegin = true
        let (coordinator, platform) = makeCoordinator(store)

        let first = Task { await coordinator.refresh(session) }
        await yieldUntil({ store.beginIsParked }, "the first refresh parks inside the store's begin")

        let second = Task { await coordinator.refresh(session) }
        await Task.yield()

        XCTAssertEqual(
            store.calls,
            ["begin(running)"],
            "the parked begin is the only call while the second refresh waits its turn"
        )
        XCTAssertEqual(store.ended, 0)
        XCTAssertFalse(store.overlapped, "nothing else reached the store while the begin was in flight")

        store.resumeBegin()
        await first.value
        await second.value

        XCTAssertEqual(store.calls, ["begin(running)"], "one begin, however the two refreshes interleaved")
        XCTAssertEqual(store.ended, 0, "and no end for the workout that just opened")
        XCTAssertFalse(store.overlapped, "no two store calls ever overlapped")
        XCTAssertEqual(platform.running?.watchOs, "running", "the workout the first refresh opened stays open")
    }
}
