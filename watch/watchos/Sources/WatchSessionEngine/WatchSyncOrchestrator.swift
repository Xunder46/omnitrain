//
//  WatchSyncOrchestrator.swift
//  WatchSessionEngine
//
//  Proactive routine sync: what keeps the wrist's routines and fallback list
//  current without the user asking. Mirrors
//  `lib/watch/start/watch_sync_orchestrator.dart`.
//
//  Plan: `.github/agents/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`.
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
}

public final class WatchSyncOrchestrator {
    private let transport: WatchSyncTransport
    private let paths: WatchSessionStartPaths
    private let engine: WatchSessionEngine

    public init(
        transport: WatchSyncTransport,
        paths: WatchSessionStartPaths,
        engine: WatchSessionEngine
    ) {
        self.transport = transport
        self.paths = paths
        self.engine = engine
    }

    /// Pulls the routines: everything on a first connect, what changed after one.
    ///
    /// Call on connect and on reconnect. It never throws: a watch that cannot
    /// reach the phone keeps the routines it has, which is the whole point of
    /// syncing proactively.
    public func sync(reconnect: Bool = false) async {
        paths.phoneReachable = transport.isPhoneReachable
        await transport.requestRoutines(since: reconnect ? paths.syncedAt : nil)
    }

    /// Routes an arriving message to whoever owns it.
    ///
    /// Returns what the message changed, or false when the watch has no use for
    /// it — a conformant message for another item's surface, say. A message the
    /// watch cannot read throws, and nothing is applied: a peer speaking another
    /// protocol version must not half-edit a live session.
    @discardableResult
    public func receive(_ envelope: [String: Any]) async throws -> Bool {
        switch envelope["type"] as? String {
        case "routines_down":
            return await paths.applyRoutinesDown(envelope).applied
        case "exercise_push":
            _ = try await engine.applyExercisePush(envelope)
            return true
        default:
            return false
        }
    }
}
