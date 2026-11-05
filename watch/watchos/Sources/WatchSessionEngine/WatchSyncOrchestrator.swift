//
//  WatchSyncOrchestrator.swift
//  WatchSessionEngine
//
//  Proactive routine sync: what keeps the wrist's routines and fallback list
//  current without the user asking. Mirrors
//  `lib/watch/start/watch_sync_orchestrator.dart`.
//
//  Plan: `docs/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`.
//  Carrying the messages is a separate item; this is the orchestrator that
//  decides *when* they are asked for and where an arriving one goes.
//
//  Two rules shape it:
//
//  1. **Sync happens in the background, not at session start.** A user who taps
//     "Start" is never waiting on a radio, and a phone that is out of reach
//     cannot make a routine unstartable.
//  2. **Incremental where the protocol allows it.** The first request asks for
//     everything; later ones say what the watch already has, so the phone can
//     send what changed rather than the whole set.
//
//  A wrist that shows the day's water count asks for it on every request and
//  routes the phone's `water_down` to its water state
//  (`docs/plans/2026-11-01-95-watch-water-bar-plan/`, D-28, D-29).
//

import Foundation

/// What the orchestrator needs from whatever carries messages between the two
/// devices (WatchConnectivity today, anything that replaces it later).
public protocol WatchSyncTransport: AnyObject {
    /// Whether the phone can be reached right now.
    var isPhoneReachable: Bool { get }

    /// Asks the phone for `routines_down`, optionally for everything newer than
    /// `since`, and tells it which exercise-list version the wrist already
    /// holds (`exercisesVersion`, nil when it holds none) so the phone can send
    /// only what changed. `holdsBests` says whether the wrist holds a bests
    /// frame, so the phone can skip a frame that has not changed (87c, D-7).
    /// `wantsWater` asks for the day's water count as well (plan 95 D-28).
    /// The reply arrives through `WatchSyncOrchestrator.receive` — this call
    /// carries no payload of its own.
    func requestRoutines(
        since: Date?,
        exercisesVersion: String?,
        holdsBests: Bool,
        wantsWater: Bool
    ) async

    /// Asks the phone for a `session_snapshot`. The reply arrives through
    /// `WatchSyncOrchestrator.receive`, exactly as a `routines_down` reply does.
    func requestSnapshot() async

    /// Hands the phone one message the watch owes it — an observation, a timer,
    /// a lifecycle change, or the watch's own session snapshot.
    func send(_ envelope: [String: Any]) async
}

public final class WatchSyncOrchestrator {
    private let transport: WatchSyncTransport
    private let paths: WatchSessionStartPaths
    private let engine: WatchSessionEngine

    /// The quick-log surface's synced food list, when the app hosts one. A
    /// watch without the surface has nothing to do with a `foods_down`.
    private let nutrition: WatchNutritionState?

    /// The phone's preferences, when the app keeps them. A watch without them
    /// has nothing to do with a `preferences_down`.
    private let preferences: WatchPhonePreferences?

    /// The phone's standing bests, when the app keeps them. A watch without
    /// them has nothing to do with a `bests_down`, and announces nothing about
    /// a record (D-3).
    private let bests: WatchPersonalBests?

    /// The day's water count, when the app shows one. A watch without it does
    /// not ask for the count and has nothing to do with a `water_down`, so its
    /// requests are the ones it sent before water existed (plan 95 D-28, I-9).
    private let water: WatchWaterState?

    /// Whether a catch-up is running. The class is not main-actor isolated, so
    /// the flag is protected by a lock: the test-and-set in `catchUp` has no
    /// suspension point between the check and the set, so two triggers can never
    /// both pass it.
    private let catchUpLock = NSLock()
    private var catchUpInFlight = false

    public init(
        transport: WatchSyncTransport,
        paths: WatchSessionStartPaths,
        engine: WatchSessionEngine,
        nutrition: WatchNutritionState? = nil,
        preferences: WatchPhonePreferences? = nil,
        bests: WatchPersonalBests? = nil,
        water: WatchWaterState? = nil
    ) {
        self.transport = transport
        self.paths = paths
        self.engine = engine
        self.nutrition = nutrition
        self.preferences = preferences
        self.bests = bests
        self.water = water
    }

    /// Brings the watch up to date with the phone: the routines, and then the
    /// session state the two devices do not share yet.
    ///
    /// Call on connect and on reconnect. It never throws: a watch that cannot
    /// reach the phone keeps the routines it has, which is the whole point of
    /// syncing proactively.
    ///
    /// The watch re-sends every observation the phone has not acknowledged —
    /// rebuilt from storage rather than from a queue, so a relaunch re-sends the
    /// same identifiers and the phone deduplicates them (S-003). It asks for a
    /// snapshot when it has no session to converge on (joining a phone session),
    /// and hands over its own when it has one, which is the exchange the
    /// protocol asks of both devices on connect.
    public func sync(reconnect: Bool = false) async {
        paths.phoneReachable = transport.isPhoneReachable
        await transport.requestRoutines(
            since: reconnect ? paths.syncedAt : nil,
            exercisesVersion: paths.exercisesVersion,
            // The wrist's own copy is the truth about "holds" (87c, D-7): a
            // wrist with no frame asks for one, and one that holds says so.
            holdsBests: bests?.hasFrame ?? false,
            // A wrist that shows the water count asks for it on every sync,
            // manual or catch-up; one that does not never asks (plan 95 D-28).
            wantsWater: water != nil
        )

        for message in engine.pendingObservations() {
            await transport.send(message)
        }

        // D-199: the rating observation above must reach the phone before the
        // replay, so the copy ends with the wrist's rating already in it.
        if paths.phoneReachable { engine.replaySessionEnd() }

        if engine.session == nil {
            await transport.requestSnapshot()
        } else {
            await answerSnapshotRequest()
        }
    }

    /// Catches the wrist up with the phone when it becomes the active app and
    /// the radio reports the phone in reach, without the user pressing Sync
    /// (D-96, D-183).
    ///
    /// One gate, here rather than in the shell: the phone must be `reachable`.
    /// The wrist's own session no longer matters — a wrist with no session asks
    /// the phone for its current workout and for the routines (D-183), so the
    /// workout the wrist should be in appears after its own was discarded. A
    /// trigger that arrives while one is already running is dropped: never
    /// queued, never cancelling the running one; the next trigger after it
    /// completes runs a fresh catch-up.
    public func catchUp(reachable: Bool) async {
        guard reachable else { return }

        let alreadyRunning = catchUpLock.withLock { () -> Bool in
            if catchUpInFlight { return true }
            catchUpInFlight = true
            return false
        }
        guard !alreadyRunning else { return }

        defer { catchUpLock.withLock { catchUpInFlight = false } }

        await sync(reconnect: paths.syncedAt != nil)
    }

    /// Answers a snapshot request from the phone with the watch's live session.
    ///
    /// A watch with nothing logged has nothing authoritative to report, so the
    /// request goes unanswered rather than answered with an empty session.
    public func answerSnapshotRequest() async {
        guard let snapshot = engine.sessionSnapshot() else { return }
        await transport.send(snapshot)
    }

    /// Routes an arriving message to whoever owns it.
    ///
    /// Returns what the message changed, or false when the watch has no use for
    /// it — a conformant message for another item's surface, say, or reference
    /// data already older than the cached catalog. A message the watch cannot
    /// read is refused whole, nothing is applied, and the phone is answered with
    /// the watch's snapshot so it converges from what the wrist actually holds
    /// (PROTOCOL.md, "Versioning policy"). The refusal is still reported,
    /// because a caller needs to know its session was not advanced.
    @discardableResult
    public func receive(_ envelope: [String: Any]) async throws -> Bool {
        switch envelope["type"] as? String {
        case "routines_down":
            return await paths.applyRoutinesDown(envelope).applied
        case "exercises_down":
            return await paths.applyExercisesDown(envelope).stored
        case "foods_down":
            guard let nutrition else { return false }
            return await nutrition.applyFoodsDown(envelope).applied
        case "preferences_down":
            // Reference data, gated like the routines and the food list: a copy
            // the watch cannot read is refused with nothing stored (D-113).
            guard let preferences else { return false }
            return await preferences.applyPreferencesDown(envelope).applied
        case "bests_down":
            // The phone's standing bests, gated the same way: a frame the watch
            // cannot read is refused with nothing stored and the copy it holds
            // still deciding (D-5).
            guard let bests else { return false }
            return await bests.applyBestsDown(envelope).applied
        case "water_down":
            // The phone's water count for its today, gated the same way: a
            // frame the watch cannot read is refused with nothing stored and
            // the frame it holds still counting (plan 95 D-24, D-29).
            guard let water else { return false }
            return await water.applyWaterDown(envelope).applied
        case "exercise_push", "session_snapshot", "structure_change",
             "session_lifecycle", "timer_state", "observations_up",
             "receipt":
            do {
                return try await engine.applyMessage(envelope)
            } catch {
                await answerSnapshotRequest()
                throw error
            }
        default:
            return false
        }
    }
}
