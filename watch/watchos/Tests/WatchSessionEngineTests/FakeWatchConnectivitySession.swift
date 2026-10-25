//
//  FakeWatchConnectivitySession.swift
//  WatchSessionEngineTests
//
//  The platform's watch API, faked: it records what the bridge asked it to send
//  and lets a test deliver a frame or a reachability change by hand.
//
//  Plan: `docs/plans/2026-10-04-14-watch-shell-bridge-plan/2026-10-04-14-watch-shell-bridge-plan.md`,
//  D-1. The real `WCSession` conformance lives in the app target and is compiled
//  only where `WatchConnectivity` exists, which is what lets the bridge be
//  exercised here on macOS.
//

import Foundation

@testable import WatchSessionEngine

final class FakeWatchConnectivitySession: WatchConnectivitySession {
    /// Every frame the bridge handed over, in order. A frame the bridge refused
    /// never appears here.
    private(set) var sent: [[String: Any]] = []

    /// Every frame the bridge handed to the OS queue, in order. A frame the
    /// radio took never appears here.
    private(set) var queued: [[String: Any]] = []

    /// What the platform answers `send` with, when a test wants a send to fail.
    var sendError: Error?

    /// What the platform answers `queue` with, when a test wants a hand-over to
    /// the OS queue to fail.
    var queueError: Error?

    var isPhoneReachable: Bool

    /// What the OS still holds, in its order (oldest first). `queue` appends here too, but the fake does
    /// NOT dedupe by message id (the package does, plan 69 D-5).
    private(set) var outstanding: [[String: Any]] = []

    /// The ids of every cancel call, one array per call, in order.
    private(set) var cancels: [[String]] = []

    /// How many times `outstandingTransfers()` has been entered. A test that wants a deterministic race
    /// window sets `onListEntered` to wait inside it.
    private(set) var listCalls = 0

    /// Called inside `outstandingTransfers()` after the call was counted (S-9914's race window). Default nil.
    var onListEntered: (() -> Void)?

    /// When true the fake behaves like a session that is not activated: it lists nothing, cancels 0, and `queue` throws `NotActivated`.
    var notActivated = false

    private let lock = NSLock()

    private var receiveHandler: (([String: Any]) async -> Void)?
    private var reachabilityHandler: ((Bool) -> Void)?

    init(isPhoneReachable: Bool = false) {
        self.isPhoneReachable = isPhoneReachable
    }

    func send(_ frame: [String: Any]) throws {
        if let sendError { throw sendError }
        sent.append(frame)
    }

    func queue(_ frame: [String: Any]) throws {
        lock.lock()
        defer { lock.unlock() }
        if notActivated { throw FakeNotActivated() }
        if let queueError { throw queueError }
        queued.append(frame)
        outstanding.append(frame)
    }

    /// Empties both records, for a test that wants to look only at what follows.
    func clearSent() {
        lock.lock()
        defer { lock.unlock() }
        sent.removeAll()
        queued.removeAll()
        outstanding.removeAll()
        cancels.removeAll()
    }

    func onReceive(_ handler: @escaping ([String: Any]) async -> Void) {
        receiveHandler = handler
    }

    func onReachabilityChange(_ handler: @escaping (Bool) -> Void) {
        reachabilityHandler = handler
    }

    /// The phone sending a frame, as the platform would deliver it.
    func deliver(_ frame: [String: Any]) async {
        await receiveHandler?(frame)
    }

    /// The radio reporting a reachability change.
    func reportReachable(_ reachable: Bool) {
        isPhoneReachable = reachable
        reachabilityHandler?(reachable)
    }

    /// Puts frames in the OS queue without going through `queue`, as a previous app run would have left them.
    func seedOutstanding(_ frames: [[String: Any]]) {
        lock.lock()
        outstanding.append(contentsOf: frames)
        lock.unlock()
    }

    func outstandingTransfers() -> [[String: Any]] {
        lock.lock()
        listCalls += 1
        let snapshot = notActivated ? [] : outstanding
        let hook = onListEntered
        lock.unlock()
        hook?()
        return snapshot
    }

    func cancelTransfers(messageIds: [String]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if notActivated { return 0 }
        cancels.append(messageIds)
        let before = outstanding.count
        outstanding.removeAll { ($0["messageId"] as? String).map(messageIds.contains) ?? false }
        return before - outstanding.count
    }
}

/// The error `queue` throws when the fake is told the session is not activated.
struct FakeNotActivated: Error {}
