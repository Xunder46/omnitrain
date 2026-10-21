//
//  WatchAsyncMutexTests.swift
//  WatchSessionEngineTests
//
//  Phase P1 of
//  `docs/plans/2026-10-20-46c-engine-serialisation-plan/2026-10-20-46c-engine-serialisation-plan.md`:
//  the async mutex the engine's session-row writers share (D-1).
//
//  Scenario mapping:
//    S-6506 three bodies run one at a time, in arrival order, and the lock is
//           free again after the last one                 → `testS6506...`
//           case A: a parked body blocks the two behind it
//           case B: the lock is free after the last body
//           case C: a body that suspends holds the lock
//           A body is only ever begun after the test has seen it queue, so the
//           arrival order is fixed rather than hoped for. Every wait is bounded
//           by `waitUntil`'s 500 yields; no test reads a clock.
//

import XCTest

@testable import WatchSessionEngine

/// Yields until `condition` holds, up to 500 times. The bound is what turns a
/// mutex that never wakes a waiter into a failed assertion instead of a hung
/// suite.
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

/// What the bodies saw: how many ran at once, the order they began and every
/// begin/end event in sequence.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var runningCount = 0
    private var peak = 0
    private var enteredOrder: [Int] = []
    private var departed: [Int] = []
    private var eventLog: [String] = []

    var running: Int {
        lock.lock()
        defer { lock.unlock() }
        return runningCount
    }

    var maxRunning: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    /// The ids of the bodies, in the order they began.
    var order: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return enteredOrder
    }

    /// The ids of the bodies, in the order they finished.
    var finished: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return departed
    }

    /// `"enter 1"`, `"leave 1"`, in sequence.
    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return eventLog
    }

    func enter(_ id: Int) {
        lock.lock()
        runningCount += 1
        if runningCount > peak { peak = runningCount }
        enteredOrder.append(id)
        eventLog.append("enter \(id)")
        lock.unlock()
    }

    func leave(_ id: Int) {
        lock.lock()
        runningCount -= 1
        departed.append(id)
        eventLog.append("leave \(id)")
        lock.unlock()
    }
}

/// A suspension the test releases by hand, so a body parks inside the mutex for
/// as long as the test needs and no longer.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        opened = true
        let parked = continuation
        continuation = nil
        lock.unlock()
        parked?.resume()
    }
}

final class WatchAsyncMutexTests: XCTestCase {

    /// S-6506, case A. Body 0 parks; bodies 1 and 2 queue behind it in that
    /// order; releasing body 0 runs them one after another in arrival order.
    func testS6506ParkedBodyHoldsTheOnesBehindItInOrder() async {
        let mutex = WatchAsyncMutex()
        let recorder = Recorder()
        let gate = Gate()

        let first = Task {
            await mutex.exclusive {
                recorder.enter(0)
                await gate.wait()
                recorder.leave(0)
                return 0
            }
        }
        let body0Entered = await waitUntil { recorder.running == 1 }
        XCTAssertTrue(body0Entered, "body 0 entered")

        let second = Task {
            await mutex.exclusive {
                recorder.enter(1)
                await Task.yield()
                recorder.leave(1)
                return 1
            }
        }
        let body1Queued = await waitUntil { mutex.queued == 1 }
        XCTAssertTrue(body1Queued, "body 1 queued")

        let third = Task {
            await mutex.exclusive {
                recorder.enter(2)
                await Task.yield()
                recorder.leave(2)
                return 2
            }
        }
        let body2Queued = await waitUntil { mutex.queued == 2 }
        XCTAssertTrue(body2Queued, "body 2 queued")

        gate.open()

        let allDone = await waitUntil { recorder.finished.count == 3 }
        XCTAssertTrue(allDone, "all three bodies finished")
        if allDone {
            _ = await first.value
            _ = await second.value
            _ = await third.value
        }

        XCTAssertEqual(recorder.order, [0, 1, 2], "bodies began in arrival order")
        XCTAssertEqual(recorder.maxRunning, 1, "never two bodies at once")
        let events = recorder.events
        if let body0Left = events.firstIndex(of: "leave 0"),
           let body1Entered = events.firstIndex(of: "enter 1") {
            XCTAssertLessThan(body0Left, body1Entered, "body 1 began only after body 0 finished")
        } else {
            XCTFail("expected body 0 to finish and body 1 to begin, saw \(events)")
        }
    }

    /// S-6506, case B. After the last body the lock is free again: a fresh call
    /// runs to completion with nothing else to release it.
    func testS6506LockIsFreeAfterTheLastBody() async {
        let mutex = WatchAsyncMutex()
        let recorder = Recorder()

        let only = await mutex.exclusive { recorder.enter(9); recorder.leave(9); return 7 }
        XCTAssertEqual(only, 7, "the body's own answer comes back")
        XCTAssertEqual(mutex.queued, 0, "nothing is waiting")
        XCTAssertEqual(recorder.maxRunning, 1)

        let again = await mutex.exclusive { 7 }
        XCTAssertEqual(again, 7, "a second call is not held up by the first")
        XCTAssertEqual(mutex.queued, 0)
    }

    /// S-6506, case C. A body that suspends in the middle still holds the lock:
    /// the next body waits through every suspension, not just until the first.
    func testS6506SuspendingBodyHoldsTheLock() async {
        let mutex = WatchAsyncMutex()
        let recorder = Recorder()

        let first = Task {
            await mutex.exclusive {
                recorder.enter(0)
                var spins = 0
                while mutex.queued == 0 && spins < 500 {
                    spins += 1
                    await Task.yield()
                }
                await Task.yield()
                await Task.yield()
                await Task.yield()
                recorder.leave(0)
                return 0
            }
        }
        let body0Entered = await waitUntil { recorder.running == 1 }
        XCTAssertTrue(body0Entered, "body 0 entered")

        let second = Task {
            await mutex.exclusive {
                recorder.enter(1)
                recorder.leave(1)
                return 1
            }
        }
        let body1Queued = await waitUntil { mutex.queued == 1 }
        XCTAssertTrue(body1Queued, "body 1 queued")

        let allDone = await waitUntil { recorder.finished.count == 2 }
        XCTAssertTrue(allDone, "both bodies finished")
        if allDone {
            _ = await first.value
            _ = await second.value
        }

        XCTAssertEqual(recorder.order, [0, 1], "body 1 began after body 0")
        XCTAssertEqual(recorder.maxRunning, 1, "the suspensions did not let body 1 in")
        let events = recorder.events
        if let body0Left = events.firstIndex(of: "leave 0"),
           let body1Entered = events.firstIndex(of: "enter 1") {
            XCTAssertLessThan(body0Left, body1Entered, "body 1 began only after body 0 finished")
        } else {
            XCTFail("expected body 0 to finish and body 1 to begin, saw \(events)")
        }
    }
}
