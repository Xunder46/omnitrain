import Foundation

/// Hands frames to one handler one at a time, in the order they were offered
/// (plan 63 D-4). `enqueue` may be called from any thread; the order of its
/// calls is the order of handling, so a caller that is itself serial (the
/// radio's delegate queue) gets its arrival order.
public final class WatchInboundLane: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [[String: Any]] = []
    private var running = false
    private let handler: @Sendable ([String: Any]) async -> Void

    public init(handler: @escaping @Sendable ([String: Any]) async -> Void) {
        self.handler = handler
    }

    public func enqueue(_ frame: [String: Any]) {
        lock.lock()
        waiting.append(frame)
        let start = !running
        running = true
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
