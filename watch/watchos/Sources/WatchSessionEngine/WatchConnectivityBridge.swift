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
//     and no queue here: a frame leaves when the orchestrator syncs or the
//     engine hands over something it owes, and at no other time.
//  2. **A frame the radio cannot carry is reported and dropped** (D-4, D-6). No
//     second delivery path — the next `sync()` re-sends what is owed from
//     storage.
//

import Foundation

/// What the bridge needs from the platform's watch API — `WCSession` in the app
/// target, a fake in tests.
///
/// Deliberately four members and no more: everything else the bridge does
/// (building frames, checking them, reporting failures) would otherwise be
/// written once per platform. The real `WCSession` conformance belongs to the
/// app target and is compiled only where `WatchConnectivity` exists, which is
/// what lets this package compile and its tests run on macOS.
public protocol WatchConnectivitySession: AnyObject {
    /// Whether the phone can be reached right now.
    var isPhoneReachable: Bool { get }

    /// Hands the phone one frame. Throws when the platform refuses it.
    func send(_ frame: [String: Any]) throws

    /// Hands every frame the phone sends to `handler`, for as long as the
    /// session lives. Called once, before the app starts receiving.
    func onReceive(_ handler: @escaping ([String: Any]) async -> Void)

    /// Hands every reachability change to `handler`. Called once.
    func onReachabilityChange(_ handler: @escaping (Bool) -> Void)
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
    /// the wrist has never synced.
    public static func routinesFrame(since: Date?) -> [String: Any] {
        var frame: [String: Any] = ["request": routines]
        if let since { frame["since"] = utcIso(since) }
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
    /// the caller reports it and the next sync re-sends what is owed.
    private let onFailure: ((Error) -> Void)?

    /// Who the bridge hands arriving frames to. Set by the host before the app
    /// starts receiving; a frame that arrives first is dropped rather than
    /// buffered, because the next sync is what brings the wrist up to date.
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
    public func onIncoming(_ handler: @escaping ([String: Any]) async throws -> Void) {
        inbound = handler
    }

    /// Hands every reachability change to `handler`. The host decides what an
    /// unknown, a reachable and an unreachable phone each mean (D-8).
    public func onReachabilityChange(_ handler: @escaping (Bool) -> Void) {
        reachabilityHandler = handler
    }

    public func requestRoutines(since: Date?) async {
        await send(WatchTransportRequest.routinesFrame(since: since))
    }

    public func requestSnapshot() async {
        await send(WatchTransportRequest.snapshotFrame())
    }

    /// Hands the phone one frame the wrist owes it.
    ///
    /// The frame is checked first: a value the radio cannot carry fails the
    /// whole message, so it is reported through the failure hook and never
    /// reaches the session (D-4). A send the session itself refuses is reported
    /// the same way, and nothing is queued (D-6).
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
            report(error)
        }
    }

    /// Hands one arriving frame to the inbound handler, if there is one.
    ///
    /// A handler that throws has already refused the message whole (I-4); the
    /// throw is reported here so the caller of the arrival does not have to
    /// carry it.
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
