//
//  WatchEmitForwarder.swift
//  WatchSessionEngine
//
//  The wrist's outbound sink: what turns the engine's synchronous `onEmit`
//  callback into frames handed to the radio as the action that produced them
//  happens.
//
//  Plan: `docs/plans/2026-10-05-15c-watch-session-sync-pr2b-plan/…`, D-21/D-22.
//
//  Two rules shape it:
//
//  1. **The caller never waits on the radio.** The engine calls `onEmit`
//     synchronously from the action the user took — a log, End, a rating — so
//     the sink hands the frame to a task and returns. A wrist that stalls
//     logging because the phone is out of reach is worse than a late frame.
//  2. **Frames leave in the order they were produced.** Each frame is chained
//     behind the one before it — the serial tail `WatchSensorWrites` uses — so a
//     slow first send cannot let the second overtake it.
//
//  A frame the transport refuses is reported through `onFailure` and ends there:
//  it is not queued and not retried, because the row it came from is still owed
//  and the next Sync re-sends it from storage (D-22).
//
//  A send that never completes is bounded the same way: after `sendTimeout` the
//  frame is reported through `onFailure` and the chain moves on, so one wedged
//  radio cannot silence the wrist for the rest of the session (D-98).

import Foundation

/// A send that did not complete inside its bound (D-98). Reported through the
/// forwarder's failure hook like any refusal; the frame is dropped, and the row
/// it came from is re-sent from storage by the next sync.
struct WatchSendTimeout: Error {
    let seconds: TimeInterval
}

/// Resolves a timeout race exactly once, so the loser cannot resume the
/// continuation a second time.
private final class SendRace {
    private let lock = NSLock()
    private var settled = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if settled { return false }
        settled = true
        return true
    }
}

/// Holds the sleeper task of one bounded send so the send can cancel it (F5).
///
/// The send may settle before the sleeper is stored, so a cancel that arrives
/// first is remembered and applied at the store.
private final class SleeperHandle {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelledFirst = false

    func store(_ task: Task<Void, Never>) {
        lock.lock()
        let cancelledFirst = self.cancelledFirst
        if !cancelledFirst { self.task = task }
        lock.unlock()
        if cancelledFirst { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelledFirst = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

/// Turns the engine's `WatchMessageSink` into sends over a `WatchSyncTransport`.
public final class WatchEmitForwarder {
    /// Hands one frame over. Throwing means this frame is refused; it is
    /// reported and dropped, never retried.
    private let send: ([String: Any]) async throws -> Void

    /// Where a refused frame is reported — the same kind of hook the bridge uses.
    private let onFailure: (Error) -> Void

    /// How long one send may run before it is treated as refused (D-98).
    /// Injectable so a test can use a bound it can outlast.
    private let sendTimeout: TimeInterval

    private let lock = NSLock()

    /// The last send enqueued, and every one chained behind it.
    private var tail: Task<Void, Never>?

    /// Over a transport.
    ///
    /// `WatchSyncTransport.send` does not throw — a bridge reports a refusal
    /// through its own failure hook — so the throw path is exercised through the
    /// seam below rather than through the protocol.
    public init(
        transport: WatchSyncTransport,
        onFailure: @escaping (Error) -> Void = { _ in },
        sendTimeout: TimeInterval = 10
    ) {
        self.send = { await transport.send($0) }
        self.onFailure = onFailure
        self.sendTimeout = sendTimeout
    }

    /// The seam the transport init wraps: a sender that can refuse a frame, so
    /// the failure path is expressible without a transport whose `send` throws.
    init(
        send: @escaping ([String: Any]) async throws -> Void,
        onFailure: @escaping (Error) -> Void,
        sendTimeout: TimeInterval = 10
    ) {
        self.send = send
        self.onFailure = onFailure
        self.sendTimeout = sendTimeout
    }

    /// What the engine is given as its `onEmit`.
    public var sink: WatchMessageSink {
        { [weak self] envelope in self?.enqueue(envelope) }
    }

    /// Hands `envelope` to the transport, behind every frame enqueued before it.
    ///
    /// Synchronous and non-blocking: the send runs on its own task, and a
    /// refusal is reported there rather than thrown back into the engine.
    private func enqueue(_ envelope: [String: Any]) {
        lock.lock()
        let previous = tail
        let send = self.send
        let onFailure = self.onFailure
        let timeout = sendTimeout
        let next = Task {
            await previous?.value
            do {
                try await WatchEmitForwarder.bounded(envelope, via: send, within: timeout)
            } catch {
                onFailure(error)
            }
        }
        tail = next
        lock.unlock()
    }

    /// Hands one frame to `send`, failing with `WatchSendTimeout` when it has not
    /// completed within `timeout` seconds (D-98).
    ///
    /// The loser of the race is abandoned rather than awaited: a send that never
    /// returns must not hold the serial chain. The winner cancels the loser's
    /// sleeper, so a settled send leaves no task waiting out the timeout. Nothing
    /// is retried — the row the frame came from is still owed and the next sync
    /// re-sends it from storage.
    static func bounded(
        _ envelope: [String: Any],
        via send: @escaping ([String: Any]) async throws -> Void,
        within timeout: TimeInterval
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let race = SendRace()
            let sleeper = SleeperHandle()
            Task {
                do {
                    try await send(envelope)
                    if race.claim() {
                        sleeper.cancel()
                        continuation.resume()
                    }
                } catch {
                    if race.claim() {
                        sleeper.cancel()
                        continuation.resume(throwing: error)
                    }
                }
            }
            sleeper.store(Task {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return
                }
                if race.claim() { continuation.resume(throwing: WatchSendTimeout(seconds: timeout)) }
            })
        }
    }

    /// The send in flight and everything queued behind it. The app never reads
    /// it; it exists so a test can wait for the wrist to finish handing frames
    /// over before asserting their order.
    var inFlight: Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return tail
    }

    /// Waits until every frame handed to `sink` so far has reached the transport
    /// — or been refused. Test seam, like `inFlight`.
    ///
    /// Not named `settle…`: the module forbids a declaration named for a
    /// mutation, and that name reads as one to the guard
    /// (`testS004NoMutatingOperationExistsAnywhereInTheModule`).
    func drain() async {
        await inFlight?.value
    }
}
