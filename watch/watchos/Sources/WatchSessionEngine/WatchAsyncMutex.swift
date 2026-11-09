//
//  WatchAsyncMutex.swift
//  WatchSessionEngine
//
//  A first-in-first-out, non-reentrant async mutex. The engine's session-row
//  writers run their whole body inside `exclusive`, so a read of the session,
//  the awaited store append and the write of the session cannot interleave with
//  another writer (D-1, S-6506).
//
//  Do not call `exclusive` from inside a body that is itself inside the same
//  mutex: the mutex is not reentrant and the inner call would wait forever.
//

import Foundation

final class WatchAsyncMutex {
    private let lock = NSLock()
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// How many bodies are queued behind the running one. For tests.
    var queued: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    /// Runs `body` alone: bodies start in the order they asked, and the next
    /// one starts only when the running one has finished.
    func exclusive<T>(_ body: () async -> T) async -> T {
        await acquire()
        let result = await body()
        release()
        return result
    }

    private func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if held {
                waiters.append(continuation)
                lock.unlock()
            } else {
                held = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    private func release() {
        lock.lock()
        if waiters.isEmpty {
            held = false
            lock.unlock()
        } else {
            let next = waiters[0]
            waiters = Array(waiters[1...])
            lock.unlock()
            next.resume()
        }
    }
}
