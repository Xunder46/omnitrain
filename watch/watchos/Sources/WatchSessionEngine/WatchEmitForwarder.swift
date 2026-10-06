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

import Foundation

/// Turns the engine's `WatchMessageSink` into sends over a `WatchSyncTransport`.
public final class WatchEmitForwarder {
    /// Hands one frame over. Throwing means this frame is refused; it is
    /// reported and dropped, never retried.
    private let send: ([String: Any]) async throws -> Void

    /// Where a refused frame is reported — the same kind of hook the bridge uses.
    private let onFailure: (Error) -> Void

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
        onFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.send = { await transport.send($0) }
        self.onFailure = onFailure
    }

    /// The seam the transport init wraps: a sender that can refuse a frame, so
    /// the failure path is expressible without a transport whose `send` throws.
    init(
        send: @escaping ([String: Any]) async throws -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.send = send
        self.onFailure = onFailure
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
        let next = Task {
            await previous?.value
            do {
                try await send(envelope)
            } catch {
                onFailure(error)
            }
        }
        tail = next
        lock.unlock()
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
