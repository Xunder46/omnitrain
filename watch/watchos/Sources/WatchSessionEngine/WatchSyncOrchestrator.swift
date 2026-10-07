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

import Foundation

/// What the orchestrator needs from whatever carries messages between the two
/// devices (WatchConnectivity today, anything that replaces it later).
public protocol WatchSyncTransport: AnyObject {
    /// Whether the phone can be reached right now.
    var isPhoneReachable: Bool { get }

    /// Asks the phone for `routines_down`, optionally for everything newer than
    /// `since`. The reply arrives through `WatchSyncOrchestrator.receive` — this
    /// call carries no payload of its own.
    func requestRoutines(since: Date?) async

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
        preferences: WatchPhonePreferences? = nil
    ) {
        self.transport = transport
        self.paths = paths
        self.engine = engine
        self.nutrition = nutrition
        self.preferences = preferences
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
        await transport.requestRoutines(since: reconnect ? paths.syncedAt : nil)

        for message in engine.pendingObservations() {
            await transport.send(message)
        }

        if engine.session == nil {
            await transport.requestSnapshot()
        } else {
            await answerSnapshotRequest()
        }
    }

    /// Catches the wrist up with the phone when the radio reports the phone back
    /// in reach, without the user pressing Sync (D-96).
    ///
    /// Two gates, both here rather than in the shell: the phone must be
    /// `reachable` **and** the wrist must hold a session. A wrist with no session
    /// keeps the old behaviour — routines, settings and the first fetch still
    /// wait for the Sync button — so nothing is pulled for a reason the user did
    /// not ask for. A trigger that arrives while one is already running is
    /// dropped: never queued, never cancelling the running one.
    public func catchUp(reachable: Bool) async {
        guard reachable, engine.session != nil else { return }

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
        case "foods_down":
            guard let nutrition else { return false }
            return await nutrition.applyFoodsDown(envelope).applied
        case "preferences_down":
            // Reference data, gated like the routines and the food list: a copy
            // the watch cannot read is refused with nothing stored (D-113).
            guard let preferences else { return false }
            return await preferences.applyPreferencesDown(envelope).applied
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
