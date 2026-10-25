//
//  WatchConnectivityBridge.swift
//  WatchSessionEngine
//
//  The wrist's radio: the `WatchSyncTransport` the orchestrator asks, over a
//  `WatchConnectivitySession` that the app target supplies and the tests fake.
//
//  Plan: `docs/plans/2026-10-04-14-watch-shell-bridge-plan/2026-10-04-14-watch-shell-bridge-plan.md`,
//  D-1 to D-7. Mirrors `lib/core/platform/watch_transport.dart`.
//
//  Two rules shape it:
//
//  1. **Nothing is sent unless the watch asked** (D-16, I-1). There is no timer
//     here and no queue of its own: a frame leaves when the orchestrator syncs
//     or the engine hands over something it owes, and at no other time. What the
//     wrist owes the phone for good it hands to the platform's own queue (D-1).
//  2. **A durable frame the radio cannot carry is queued — a set the wrist
//     logged, a lifecycle message and the snapshot of a workout that is
//     running — and only the newest copy of a snapshot or a lifecycle waits
//     per workout (plan 69); a timer, a request and an ended workout's
//     snapshot are live state, reported and dropped.** The next `sync()`
//     re-sends what is owed from storage either way.
//
//  Plan: `docs/plans/2026-10-24-69-watch-queues-workout-state-plan/2026-10-24-69-watch-queues-workout-state-plan.md`,
//  D-2 to D-10.
//

import Foundation

/// What the bridge needs from the platform's watch API — `WCSession` in the app
/// target, a fake in tests.
///
/// Deliberately seven members and no more: the bridge's own logic (building
/// frames, checking them, reporting failures, keeping only the newest queued
/// copy) is written once, and a conformer only lists and cancels what the OS
/// holds. The real `WCSession` conformance belongs to the
/// app target and is compiled only where `WatchConnectivity` exists, which is
/// what lets this package compile and its tests run on macOS.
public protocol WatchConnectivitySession: AnyObject {
    /// Whether the phone can be reached right now.
    var isPhoneReachable: Bool { get }

    /// Hands the phone one frame. Throws when the platform refuses it.
    func send(_ frame: [String: Any]) throws

    /// Hands the phone one frame the OS delivers later, when the two meet,
    /// even if this app is asleep by then. Throws when the platform refuses it.
    func queue(_ frame: [String: Any]) throws

    /// The frames the OS still holds for the phone, in the OS's order (oldest first). A session that
    /// cannot list answers an empty list.
    func outstandingTransfers() -> [[String: Any]]

    /// Cancels the outstanding transfers whose `messageId` is in `messageIds` and answers how many were
    /// cancelled. Never throws; a session that cannot cancel answers 0.
    func cancelTransfers(messageIds: [String]) -> Int

    /// Hands every frame the phone sends to `handler`, for as long as the
    /// session lives. Called once, before the app starts receiving.
    func onReceive(_ handler: @escaping ([String: Any]) async -> Void)

    /// Hands every reachability change to `handler`. Called once.
    func onReachabilityChange(_ handler: @escaping (Bool) -> Void)

    /// Opens the radio's inbound gate, so frames that arrived before the app
    /// was ready are handed over now. Called once, after the host has
    /// installed its inbound handler. A session that has no gate answers
    /// nothing (the default below).
    func openInbound()
}

extension WatchConnectivitySession {
    /// Defaults for a conformer that cannot list or cancel: the bridge then queues without withdrawing.
    public func outstandingTransfers() -> [[String: Any]] { [] }
    public func cancelTransfers(messageIds: [String]) -> Int { 0 }

    /// Default for a conformer with no gate: nothing to open.
    public func openInbound() {}
}

/// The requests the bridge carries that are not protocol messages (D-2).
///
/// A request carries no `type` key: that key is what makes a frame a protocol
/// message, so its presence here would make the phone read the request as one.
public enum WatchTransportRequest {
    /// Watch → phone: send the routines, optionally only what changed since.
    public static let routines = "routines"

    /// Either direction: send your session state.
    public static let snapshot = "snapshot"

    /// Watch → phone: send the routines. `since` is omitted, never nulled, when
    /// the wrist has never synced. `exercisesVersion` says which exercise-list
    /// version the wrist holds, and is likewise omitted, never nulled, when it
    /// holds none — so the frames the contract pins while the wrist holds no
    /// list are unchanged (D-3818, S-3820).
    public static func routinesFrame(since: Date?, exercisesVersion: String? = nil) -> [String: Any] {
        var frame: [String: Any] = ["request": routines]
        if let since { frame["since"] = utcIso(since) }
        if let exercisesVersion { frame["exercisesVersion"] = exercisesVersion }
        return frame
    }

    /// Either direction: send your session state.
    public static func snapshotFrame() -> [String: Any] {
        ["request": snapshot]
    }
}

/// The wrist's transport over a `WatchConnectivitySession`.
public final class WatchConnectivityBridge: WatchSyncTransport {
    private let session: WatchConnectivitySession

    /// A frame the radio could not carry does not take the wrist down with it:
    /// the caller reports it and the next sync re-sends what is owed. A frame
    /// that is durable and refused goes to the OS queue instead (D-2).
    private let onFailure: ((Error) -> Void)?

    /// Who the bridge hands arriving frames to. Set by the host before the app
    /// starts receiving; a frame that arrives first waits in the radio's gate
    /// (plan 73) and is handed over when `onIncoming` opens it. The guard here
    /// stays as defence only.
    private var inbound: (([String: Any]) async throws -> Void)?

    private var reachabilityHandler: ((Bool) -> Void)?

    public init(
        session: WatchConnectivitySession,
        onFailure: ((Error) -> Void)? = nil
    ) {
        self.session = session
        self.onFailure = onFailure

        session.onReceive { [weak self] frame in
            await self?.deliver(frame)
        }
        session.onReachabilityChange { [weak self] reachable in
            self?.reachabilityHandler?(reachable)
        }
    }

    /// Whether the phone can be reached right now — the platform's answer, read
    /// through the seam rather than cached here.
    public var isPhoneReachable: Bool { session.isPhoneReachable }

    /// Hands every arriving frame to `handler`, unmodified (D-7). The phone
    /// already sent property-list values; re-encoding them here would only be a
    /// chance to lose one.
    ///
    /// The handler is stored first, then the radio's gate is opened: the first
    /// frame the gate hands over already finds its handler here (plan 73 D-3).
    public func onIncoming(_ handler: @escaping ([String: Any]) async throws -> Void) {
        inbound = handler
        session.openInbound()
    }

    /// Hands every reachability change to `handler`. The host decides what an
    /// unknown, a reachable and an unreachable phone each mean (D-8).
    public func onReachabilityChange(_ handler: @escaping (Bool) -> Void) {
        reachabilityHandler = handler
    }

    public func requestRoutines(since: Date?, exercisesVersion: String?) async {
        await send(
            WatchTransportRequest.routinesFrame(since: since, exercisesVersion: exercisesVersion)
        )
    }

    public func requestSnapshot() async {
        await send(WatchTransportRequest.snapshotFrame())
    }

    /// Hands the phone one frame the wrist owes it.
    ///
    /// The frame is checked first: a value the radio cannot carry fails the
    /// whole message, so it is reported through the failure hook and never
    /// reaches the session (D-4). A send the session itself refuses is queued
    /// when the frame is durable (D-2), and reported otherwise. A durable frame
    /// that went out live withdraws the older copies still waiting (D-6).
    public func send(_ envelope: [String: Any]) async {
        let frame: [String: Any]
        do {
            frame = try PropertyListFrames.plistSafe(envelope)
        } catch {
            report(error)
            return
        }

        do {
            try session.send(frame)
        } catch {
            guard Self.isDurable(frame) else {
                report(error)
                return
            }
            do {
                try Self.queueNewest(frame, on: session)
            } catch {
                report(error)
            }
            return
        }
        // The frame went out live: a copy of it still waiting in the OS queue is now older news (D-6).
        if Self.isDurable(frame) { Self.withdrawSuperseded(by: frame, on: session) }
    }

    /// The frames the wrist may hand the OS to deliver later when the radio refuses them (plan 69 D-2):
    /// a set it logged, every lifecycle message, and the snapshot of a workout that is still running. A
    /// timer, a request, a receipt and the snapshot of an ended workout are live state that would arrive
    /// wrong, so they are reported and dropped.
    public static func isDurable(_ frame: [String: Any]) -> Bool {
        switch frame["type"] as? String {
        case "observations_up", "session_lifecycle":
            return true
        case "session_snapshot":
            return (frame["payload"] as? [String: Any])?["status"] as? String == "active"
        default:
            return false
        }
    }

    // MARK: - Only the newest copy waits (plan 69 D-3…D-8)

    /// One lock for every path that lists, withdraws and queues, so two hand-overs at once cannot both
    /// keep a copy (D-7). Static on purpose: the app target's late-refusal path calls `queueNewest` too.
    private static let queueLock = NSLock()

    private static let terminalStates: Set<String> = ["completed", "abandoned"]

    /// Queues a frame the radio refused, after withdrawing the waiting copies it replaces. A copy with a
    /// LATER `sentAt` is newer than the frame: the frame is then not queued and nothing is withdrawn (D-4,
    /// not a failure). A frame that already waits under its own message id is not queued again (D-5),
    /// except a snapshot, whose id does not change with its content. Throws only what the queue throws.
    public static func queueNewest(
        _ frame: [String: Any],
        on session: WatchConnectivitySession
    ) throws {
        queueLock.lock()
        defer { queueLock.unlock() }
        let held = session.outstandingTransfers()
        let own = frame["messageId"] as? String
        if frame["type"] as? String != "session_snapshot",
           let own,
           held.contains(where: { ($0["messageId"] as? String) == own }) {
            return
        }
        let found = superseded(by: frame, in: held)
        if found.newerExists { return }
        if !found.olderIds.isEmpty { _ = session.cancelTransfers(messageIds: found.olderIds) }
        try session.queue(frame)
    }

    /// After a frame went out live: cancels the waiting copies it replaces, never a newer one (D-6).
    static func withdrawSuperseded(
        by frame: [String: Any],
        on session: WatchConnectivitySession
    ) {
        guard let type = frame["type"] as? String,
              type == "session_snapshot" || type == "session_lifecycle"
        else { return }
        queueLock.lock()
        defer { queueLock.unlock() }
        let found = superseded(by: frame, in: session.outstandingTransfers())
        if !found.olderIds.isEmpty { _ = session.cancelTransfers(messageIds: found.olderIds) }
    }

    private struct Superseded {
        var olderIds: [String] = []
        var newerExists = false
    }

    /// The waiting copies `frame` replaces (D-3), split by the wrist's own `sentAt` (D-4). A snapshot
    /// replaces the snapshots of its session; a non-terminal lifecycle the non-terminal lifecycles of its
    /// session; a terminal lifecycle (completed, abandoned) both of those and is never stale. A logged set,
    /// a terminal lifecycle and another session's frame are never replaced. A copy without a string
    /// `messageId` or `type` is never touched. An unreadable `sentAt` counts as oldest on a waiting copy
    /// and as newest on the frame.
    private static func superseded(
        by frame: [String: Any],
        in held: [[String: Any]]
    ) -> Superseded {
        var result = Superseded()
        guard let type = frame["type"] as? String,
              type == "session_snapshot" || type == "session_lifecycle",
              let sessionId = frame["sessionId"] as? String
        else { return result }
        let terminal = type == "session_lifecycle" && isTerminal(frame)
        let own = frame["messageId"] as? String
        let sent = sentAt(of: frame, missing: .distantFuture)
        for copy in held {
            guard copy["sessionId"] as? String == sessionId,
                  let copyId = copy["messageId"] as? String,
                  let copyType = copy["type"] as? String
            else { continue }
            let replaced: Bool
            switch (type, copyType) {
            case ("session_snapshot", "session_snapshot"): replaced = true
            case ("session_lifecycle", "session_snapshot"): replaced = terminal
            case ("session_lifecycle", "session_lifecycle"): replaced = !isTerminal(copy)
            default: replaced = false
            }
            guard replaced else { continue }
            if copyId == own && type != "session_snapshot" { continue }
            if !terminal && sentAt(of: copy, missing: .distantPast) > sent {
                result.newerExists = true
            } else {
                result.olderIds.append(copyId)
            }
        }
        return result
    }

    private static func isTerminal(_ frame: [String: Any]) -> Bool {
        guard let state = (frame["payload"] as? [String: Any])?["state"] as? String else {
            return false
        }
        return terminalStates.contains(state)
    }

    private static func sentAt(of frame: [String: Any], missing: Date) -> Date {
        (try? parseUtcIso(frame["sentAt"])) ?? missing
    }

    /// Hands one arriving frame to the inbound handler, if there is one.
    ///
    /// A handler that throws has already refused the message whole (I-4); the
    /// throw is reported here so the caller of the arrival does not have to
    /// carry it. The radio's gate (plan 73) holds a frame that arrived before
    /// `onIncoming`, so this guard is unreachable in the wired app; it stays
    /// for a session without a gate.
    private func deliver(_ frame: [String: Any]) async {
        guard let inbound else { return }
        do {
            try await inbound(frame)
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        onFailure?(error)
    }
}
