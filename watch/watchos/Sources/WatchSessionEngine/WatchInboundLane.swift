import Foundation

/// Hands frames to one handler one at a time, in the order they were offered
/// (plan 63 D-4). `enqueue` may be called from any thread; the order of its
/// calls is the order of handling, so a caller that is itself serial (the
/// radio's delegate queue) gets its arrival order.
public final class WatchInboundLane: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [[String: Any]] = []
    private var running = false
    private var opened = true
    private let handler: @Sendable ([String: Any]) async -> Void

    public init(startsOpen: Bool = true, handler: @escaping @Sendable ([String: Any]) async -> Void) {
        self.opened = startsOpen
        self.handler = handler
    }

    /// Opens a lane built with `startsOpen: false`: the frames it held are
    /// drained in offer order, and frames offered after this call queue behind
    /// them. Idempotent, and safe from any thread.
    public func open() {
        lock.lock()
        opened = true
        let start = !running && !waiting.isEmpty
        if start { running = true }
        lock.unlock()
        guard start else { return }
        Task { await self.drain() }
    }

    public func enqueue(_ frame: [String: Any]) {
        lock.lock()
        waiting.append(frame)
        let start = opened && !running
        if start { running = true }
        lock.unlock()
        guard start else { return }
        Task { await self.drain() }
    }

    private func drain() async {
        while let frame = next() {
            await handler(frame)
        }
    }

    private func next() -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard let first = waiting.first else {
            running = false
            return nil
        }
        waiting = Array(waiting[1...])
        return first
    }
}
