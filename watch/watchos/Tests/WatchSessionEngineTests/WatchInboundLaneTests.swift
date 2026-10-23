//
//  WatchInboundLaneTests.swift
//  WatchSessionEngineTests
//
//  S-9310 of
//  `docs/plans/2026-10-23-63-message-order-plan/2026-10-23-63-message-order-plan.md`
//  — the lane hands frames to one handler one at a time, in the order they
//  were offered (plan 63 D-4).
//
//  The first handler is held on a `CheckedContinuation` the test releases, so
//  the queueing and the overlap are observed, never guessed. No test reads a
//  clock.
//

import XCTest

@testable import WatchSessionEngine

/// Records handler starts and ends under a lock, and the most handlers that
/// ever overlapped.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _starts: [Int] = []
    private var _inFlight = 0
    private var _maxInFlight = 0
    private var _finished: [Int] = []

    var starts: [Int] {
        lock.lock(); defer { lock.unlock() }
        return _starts
    }

    var finished: [Int] {
        lock.lock(); defer { lock.unlock() }
        return _finished
    }

    var maxInFlight: Int {
        lock.lock(); defer { lock.unlock() }
        return _maxInFlight
    }

    func begin(_ n: Int) {
        lock.lock()
        _starts.append(n)
        _inFlight += 1
        _maxInFlight = max(_maxInFlight, _inFlight)
        lock.unlock()
    }

    func end(_ n: Int) {
        lock.lock()
        _inFlight -= 1
        _finished.append(n)
        lock.unlock()
    }
}

/// Holds the first handler's continuation until the test opens it.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    /// True once a continuation is held, so the test never opens the gate
    /// before the handler has parked on it.
    var isHeld: Bool {
        lock.lock(); defer { lock.unlock() }
        return continuation != nil
    }

    func hold(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func open() {
        lock.lock()
        let held = continuation
        continuation = nil
        lock.unlock()
        held?.resume()
    }
}

final class WatchInboundLaneTests: XCTestCase {

    /// Bounded poll: never an unbounded wait on the lane.
    private func spin(until condition: () -> Bool, limit: Int = 100_000) async -> Bool {
        var spins = 0
        while !condition() && spins < limit {
            await Task.yield()
            spins += 1
        }
        return condition()
    }

    // MARK: - S-9310 order and no overlap

    func testS9310FramesAreHandledOneAtATimeInOfferOrder() async throws {
        let recorder = Recorder()
        let gate = Gate()
        let lane = WatchInboundLane { frame in
            let n = frame["n"] as! Int
            recorder.begin(n)
            if n == 1 {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    gate.hold(continuation)
                }
            }
            recorder.end(n)
        }

        // All three offered while the first handler is suspended.
        lane.enqueue(["n": 1])
        lane.enqueue(["n": 2])
        lane.enqueue(["n": 3])

        let parked = await spin(until: { recorder.starts == [1] && gate.isHeld })
        guard parked else {
            XCTFail("S-9310 the first handler never parked on the gate")
            gate.open()
            return
        }

        gate.open()
        let drained = await spin(until: { recorder.finished.count == 3 })
        XCTAssertTrue(drained, "S-9310 all three frames were handled")

        XCTAssertEqual(
            recorder.starts,
            [1, 2, 3],
            "S-9310 the handlers started in the order the frames were offered"
        )
        XCTAssertEqual(
            recorder.maxInFlight,
            1,
            "S-9310 no two handlers ever overlapped"
        )
    }

    // MARK: - S-9310 the lane restarts when idle

    func testS9310AFrameEnqueuedAfterTheLaneWentIdleIsStillHandled() async throws {
        let recorder = Recorder()
        let firstDone = expectation(description: "the first frame was handled")
        let lateHandled = expectation(description: "the late frame was handled")
        let lane = WatchInboundLane { frame in
            let n = frame["n"] as! Int
            recorder.begin(n)
            recorder.end(n)
            if n == 1 {
                firstDone.fulfill()
            }
            if n == 2 {
                lateHandled.fulfill()
            }
        }

        lane.enqueue(["n": 1])
        await fulfillment(of: [firstDone], timeout: 5)
        // A real pause separates the two frames, so the lane has gone idle
        // before the next frame is offered.
        try await Task.sleep(nanoseconds: 300_000_000)
        lane.enqueue(["n": 2])

        await fulfillment(of: [lateHandled], timeout: 5)
        XCTAssertEqual(
            recorder.starts,
            [1, 2],
            "S-9310 the late frame was handled after the idle pause"
        )
    }

    func testS9310TwoPausedRoundsAreBothHandledInOrder() async throws {
        let recorder = Recorder()
        let firstDone = expectation(description: "frame 1 was handled")
        let secondDone = expectation(description: "frame 2 was handled")
        let thirdDone = expectation(description: "frame 3 was handled")
        let lane = WatchInboundLane { frame in
            let n = frame["n"] as! Int
            recorder.begin(n)
            recorder.end(n)
            switch n {
            case 1: firstDone.fulfill()
            case 2: secondDone.fulfill()
            default: thirdDone.fulfill()
            }
        }

        lane.enqueue(["n": 1])
        await fulfillment(of: [firstDone], timeout: 5)
        try await Task.sleep(nanoseconds: 300_000_000)
        lane.enqueue(["n": 2])
        await fulfillment(of: [secondDone], timeout: 5)
        try await Task.sleep(nanoseconds: 300_000_000)
        lane.enqueue(["n": 3])
        await fulfillment(of: [thirdDone], timeout: 5)

        XCTAssertEqual(
            recorder.starts,
            [1, 2, 3],
            "S-9310 both paused rounds were handled in offer order"
        )
    }
}
