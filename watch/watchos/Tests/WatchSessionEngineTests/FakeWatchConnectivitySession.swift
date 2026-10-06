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

    /// What the platform answers `send` with, when a test wants a send to fail.
    var sendError: Error?

    var isPhoneReachable: Bool

    private var receiveHandler: (([String: Any]) async -> Void)?
    private var reachabilityHandler: ((Bool) -> Void)?

    init(isPhoneReachable: Bool = false) {
        self.isPhoneReachable = isPhoneReachable
    }

    func send(_ frame: [String: Any]) throws {
        if let sendError { throw sendError }
        sent.append(frame)
    }

    /// Empties the record, for a test that wants to look only at what follows.
    func clearSent() {
        sent.removeAll()
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
}
