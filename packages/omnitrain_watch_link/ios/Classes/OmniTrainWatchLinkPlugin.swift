import Flutter
import UIKit
import WatchConnectivity

/// The phone's WatchConnectivity link (plan 47a). One WCSession delegate that:
/// buffers every event until Dart listens (a cold background launch delivers
/// transfers before the app is ready), acknowledges every message by replying,
/// answers `sendMessage` only when the watch has replied, deduplicates queued
/// transfers by `messageId`, lists and cancels outstanding transfers, and
/// reports reachability and pairing changes.
public class OmniTrainWatchLinkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, WCSessionDelegate {
    private static let bufferCap = 500
    /// Held for the life of the app: WCSession keeps its delegate weakly.
    private static var shared: OmniTrainWatchLinkPlugin?

    private var sink: FlutterEventSink?
    private var pending: [[String: Any]] = []
    private var session: WCSession?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = OmniTrainWatchLinkPlugin()
        shared = instance
        let methods = FlutterMethodChannel(
            name: "omnitrain/watch_link/methods",
            binaryMessenger: registrar.messenger()
        )
        let events = FlutterEventChannel(
            name: "omnitrain/watch_link/events",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methods)
        events.setStreamHandler(instance)
        instance.activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let current = WCSession.default
        current.delegate = self
        current.activate()
        session = current
    }

    // MARK: - Methods

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "status":
            result(statusMap())
        case "sendMessage":
            sendMessage(call.arguments, result: result)
        case "transferUserInfo":
            transferUserInfo(call.arguments, result: result)
        case "outstandingTransfers":
            outstandingTransfers(result: result)
        case "cancelTransfers":
            cancelTransfers(call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func statusMap() -> [String: Any] {
        guard let current = session else {
            return [
                "supported": false, "paired": false, "appInstalled": false,
                "activated": false, "reachable": false,
            ]
        }
        return [
            "supported": true,
            "paired": current.isPaired,
            "appInstalled": current.isWatchAppInstalled,
            "activated": current.activationState == .activated,
            "reachable": current.isReachable,
        ]
    }

    private func failure(_ code: String, _ message: String? = nil) -> FlutterError {
        FlutterError(code: code, message: message, details: nil)
    }

    private func sendMessage(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let current = session else { return result(failure("not_supported")) }
        guard current.activationState == .activated else { return result(failure("not_activated")) }
        guard current.isReachable else { return result(failure("not_reachable")) }
        guard let frame = arguments as? [String: Any] else {
            return result(failure("send_failed", "the frame is not a dictionary"))
        }
        current.sendMessage(
            frame,
            replyHandler: { _ in
                DispatchQueue.main.async { result(nil) }
            },
            errorHandler: { error in
                DispatchQueue.main.async {
                    result(
                        FlutterError(
                            code: "send_failed",
                            message: error.localizedDescription,
                            details: nil
                        )
                    )
                }
            }
        )
    }

    private func transferUserInfo(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let current = session else { return result(failure("not_supported")) }
        guard current.activationState == .activated else { return result(failure("not_activated")) }
        guard let frame = arguments as? [String: Any] else {
            return result(failure("send_failed", "the frame is not a dictionary"))
        }
        if let messageId = frame["messageId"] as? String,
           current.outstandingUserInfoTransfers.contains(where: {
               ($0.userInfo["messageId"] as? String) == messageId
           }) {
            NSLog("OmniTrainWatchLink: transfer already_queued type=%@", Self.frameType(frame))
            return result("already_queued")
        }
        current.transferUserInfo(frame)
        NSLog("OmniTrainWatchLink: transfer queued type=%@", Self.frameType(frame))
        result("queued")
    }

    /// The transfers the OS still holds, read from each one's `userInfo` (the frame itself).
    /// An entry without a string `messageId` is skipped. `changeId` sits in the frame's `payload`.
    private func outstandingTransfers(result: @escaping FlutterResult) {
        guard let current = session else { return result(failure("not_supported")) }
        guard current.activationState == .activated else { return result(failure("not_activated")) }
        var entries: [[String: Any]] = []
        for transfer in current.outstandingUserInfoTransfers {
            let info = transfer.userInfo
            guard let messageId = info["messageId"] as? String else { continue }
            var entry: [String: Any] = [
                "messageId": messageId,
                "type": (info["type"] as? String) ?? "",
            ]
            if let sessionId = info["sessionId"] as? String { entry["sessionId"] = sessionId }
            if let payload = info["payload"] as? [String: Any],
               let changeId = payload["changeId"] as? String {
                entry["changeId"] = changeId
            }
            entries.append(entry)
        }
        result(entries)
    }

    /// Cancels the outstanding transfers whose `messageId` is in `messageIds`; answers how many.
    /// An empty list is answered 0 without touching the session.
    private func cancelTransfers(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let ids = (arguments as? [String: Any])?["messageIds"] as? [String], !ids.isEmpty else {
            return result(0)
        }
        guard let current = session else { return result(failure("not_supported")) }
        guard current.activationState == .activated else { return result(failure("not_activated")) }
        let wanted = Set(ids)
        var cancelled = 0
        for transfer in current.outstandingUserInfoTransfers {
            guard let messageId = transfer.userInfo["messageId"] as? String,
                  wanted.contains(messageId) else { continue }
            transfer.cancel()
            cancelled += 1
        }
        NSLog("OmniTrainWatchLink: cancelled %d transfers", cancelled)
        result(cancelled)
    }

    // MARK: - Events

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sink = events
        let waiting = pending
        pending = []
        for event in waiting { events(event) }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    private func emit(_ event: [String: Any]) {
        DispatchQueue.main.async {
            NSLog("OmniTrainWatchLink: %@", Self.describe(event))
            if let sink = self.sink {
                sink(event)
                return
            }
            self.pending.append(event)
            if self.pending.count > Self.bufferCap {
                self.pending.removeFirst(self.pending.count - Self.bufferCap)
            }
        }
    }

    private func emitState(_ current: WCSession) {
        var event = statusMap()
        event["kind"] = "state"
        emit(event)
    }

    private static func frameType(_ frame: [String: Any]) -> String {
        (frame["type"] as? String) ?? (frame["request"] as? String) ?? "unknown"
    }

    private static func describe(_ event: [String: Any]) -> String {
        let kind = (event["kind"] as? String) ?? "?"
        if let frame = event["frame"] as? [String: Any] {
            return "\(kind) type=\(frameType(frame))"
        }
        if let reachable = event["reachable"] as? Bool {
            return "\(kind) reachable=\(reachable)"
        }
        return kind
    }

    // MARK: - WCSessionDelegate

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        emitState(session)
        emit(["kind": "reachability", "reachable": session.isReachable])
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        emit(["kind": "reachability", "reachable": session.isReachable])
    }

    public func sessionWatchStateDidChange(_ session: WCSession) {
        emitState(session)
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        emit(["kind": "message", "frame": message])
    }

    public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        replyHandler([:])
        emit(["kind": "message", "frame": message])
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        emit(["kind": "userInfo", "frame": userInfo])
    }
}
