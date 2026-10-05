//
//  OmniTrainWatchConnectivity.swift
//  OmniTrain Watch App
//
//  The wrist's real radio: `WCSession` behind the package's
//  `WatchConnectivitySession` seam.
//
//  Plan: `docs/plans/2026-10-04-14-watch-shell-bridge-plan/2026-10-04-14-watch-shell-bridge-plan.md`,
//  D-1 and D-8. Every rule about frames — what they carry, what may not cross,
//  what a refusal means — lives in the package, where `swift test` can exercise
//  it on macOS. What is left here is the platform call and the queue it arrives
//  on, so this file is the one part of the radio no desktop test can reach.
//
//  WCSession delivers on a background queue. The host is a `@MainActor` SwiftUI
//  object, so each callback hops to the main actor before it touches it.
//

#if canImport(WatchConnectivity)

import Foundation
import WatchConnectivity
import WatchSessionEngine

/// The one place a radio failure is reported, for both halves of the radio: a
/// frame the bridge refused, and a send the platform refused.
///
/// Neither is a reason to take the wrist down. Nothing is queued (D-6): what the
/// phone is still owed is re-sent by the next sync, so the failure is reported
/// and dropped.
func reportWatchRadioFailure(_ error: Error) {
    NSLog("OmniTrain watch radio: %@", String(describing: error))
}

/// `WCSession`, as the seam the bridge expects.
///
/// The session is the delegate's owner rather than the reverse: `WCSession`'s
/// `delegate` is weak, so a session nobody holds stops receiving. The bridge
/// holds this object, and the host holds the bridge.
final class OmniTrainWatchConnectivity: NSObject, WatchConnectivitySession {
    private let onSendFailure: (Error) -> Void

    private var receiveHandler: (@concurrent ([String: Any]) async -> Void)?
    private var reachabilityHandler: ((Bool) -> Void)?

    /// What the radio refused, as the failure hook reports it. The bridge's own
    /// failures come from the frame check; these are the platform's.
    enum RadioError: Error, CustomStringConvertible {
        /// Asked to send before the session came up — a launch that beats
        /// `activate()`, not a phone that is out of reach.
        case notActivated

        /// The radio is up and says the phone cannot be reached.
        case phoneNotReachable

        var description: String {
            switch self {
            case .notActivated:
                return "the watch session is not activated yet"
            case .phoneNotReachable:
                return "the phone is not reachable: it is out of range or not in the foreground"
            }
        }
    }

    init(onSendFailure: @escaping (Error) -> Void = { _ in }) {
        self.onSendFailure = onSendFailure
        super.init()

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Whether the phone can be reached right now — read from the platform
    /// rather than cached, because the bridge asks this at sync time.
    var isPhoneReachable: Bool {
        WCSession.isSupported() && WCSession.default.isReachable
    }

    /// Hands the phone one frame, or throws the reason it cannot go.
    ///
    /// `sendMessage` answers asynchronously, so its refusal arrives after this
    /// call returns; it goes to the same failure hook the bridge reports through.
    func send(_ frame: [String: Any]) throws {
        guard WCSession.isSupported() else { throw RadioError.notActivated }

        let session = WCSession.default
        guard session.activationState == .activated else { throw RadioError.notActivated }
        guard session.isReachable else { throw RadioError.phoneNotReachable }

        session.sendMessage(frame, replyHandler: nil) { [weak self] error in
            self?.onSendFailure(error)
        }
    }

    /// Called once by the bridge, before the app starts receiving.
    func onReceive(_ handler: @escaping @concurrent ([String: Any]) async -> Void) {
        receiveHandler = handler
    }

    /// Called once by the bridge.
    ///
    /// A session that is already up has already answered, and the radio only
    /// re-answers on a *change* — so the answer is asked for again here rather
    /// than letting a wrist that launched beside its phone wait for a change
    /// that may never come (D-8). Answering twice costs a rebuild, not a lie.
    func onReachabilityChange(_ handler: @escaping (Bool) -> Void) {
        reachabilityHandler = handler

        if WCSession.isSupported(), WCSession.default.activationState == .activated {
            reportReachability(WCSession.default.isReachable)
        }
    }

    /// Hands one arrival to the bridge, on the main actor.
    ///
    /// A frame that arrives before the bridge has a handler is dropped rather
    /// than buffered (D-6); the next sync is what brings the wrist up to date.
    private func deliver(_ message: [String: Any]) {
        Task { @MainActor in await self.receiveHandler?(message) }
    }

    /// Reports the radio's answer, on the main actor. Every answer is reported,
    /// including one that repeats the last: the host maps it to the same state
    /// and the surface re-reads, which costs nothing and keeps the mapping in
    /// one place.
    private func reportReachability(_ reachable: Bool) {
        Task { @MainActor in self.reachabilityHandler?(reachable) }
    }
}

extension OmniTrainWatchConnectivity: WCSessionDelegate {
    /// The radio is up. Reachability can already be true by now, and a change
    /// callback only fires on a *change*, so the state it starts in is reported
    /// here or a wrist that launched beside its phone would never say so (D-8).
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil, activationState == .activated else { return }
        reportReachability(session.isReachable)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        reportReachability(session.isReachable)
    }

    /// The phone's messages, which it sends without asking for a reply.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    /// The same message, from a sender that does want a reply. Answered with an
    /// empty dictionary so that sender is not left waiting — the wrist's own
    /// answer to anything is the message it sends back, never this.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        deliver(message)
        replyHandler([:])
    }
}

#endif
