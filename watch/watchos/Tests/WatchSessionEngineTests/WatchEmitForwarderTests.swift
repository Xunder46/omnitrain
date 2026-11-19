//
//  WatchEmitForwarderTests.swift
//  WatchSessionEngineTests
//
//  S-20 (frames leave the wrist in the order they were produced) and S-26 (a
//  refused frame is reported once and dropped, never queued).
//

import XCTest
@testable import WatchSessionEngine

/// Frames the forwarder handed over and the failures it reported, recorded from
/// the forwarding task so the test can read them once `drain()` returns.
final class ForwarderRecorder {
    private let lock = NSLock()
    private var recordedFrames: [[String: Any]] = []
    private var recordedFailures: [Error] = []

    func record(_ frame: [String: Any]) {
        lock.lock()
        recordedFrames.append(frame)
        lock.unlock()
    }

    func record(_ error: Error) {
        lock.lock()
        recordedFailures.append(error)
        lock.unlock()
    }

    var frames: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedFrames
    }

    var failures: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return recordedFailures
    }

    var ids: [String] { frames.compactMap { $0["id"] as? String } }

    var types: [String] { frames.compactMap { $0["type"] as? String } }

    /// The kind of the first event in each `observations_up` frame, in send order.
    var eventKinds: [String] {
        frames.compactMap { frame in
            guard frame["type"] as? String == "observations_up" else { return nil }
            let payload = frame["payload"] as? [String: Any]
            let events = payload?["events"] as? [[String: Any]]
            return events?.first?["kind"] as? String
        }
    }

    /// The state of each `session_lifecycle` frame, in send order.
    var lifecycleStates: [String] {
        frames.compactMap { frame in
            guard frame["type"] as? String == "session_lifecycle" else { return nil }
            return (frame["payload"] as? [String: Any])?["state"] as? String
        }
    }
}

private enum ForwarderTestError: Error {
    case refused
}

final class WatchEmitForwarderTests: XCTestCase {
    // MARK: - S-020 frames leave in emission order

    func testFramesAreHandedOverInEmissionOrderWhenTheFirstSendIsSlow() async throws {
        let recorder = ForwarderRecorder()
        let forwarder = WatchEmitForwarder(
            send: { frame in
                if frame["id"] as? String == "first" {
                    // The second frame is enqueued while this one is in flight.
                    try await Task.sleep(nanoseconds: 40_000_000)
                }
                recorder.record(frame)
            },
            onFailure: { error in XCTFail("no frame should be refused: \(error)") }
        )

        forwarder.sink(["id": "first"])
        forwarder.sink(["id": "second"])
        await forwarder.drain()

        XCTAssertEqual(recorder.ids, ["first", "second"])
    }

    func testTheEnginesEmissionsReachTheSinkInOrder() async throws {
        let recorder = ForwarderRecorder()
        let forwarder = WatchEmitForwarder(
            send: { recorder.record($0) },
            onFailure: { error in XCTFail("no frame should be refused: \(error)") }
        )

        let harness = Harness()
        var recordIds = 0
        let engine = WatchSessionEngine(
            store: harness.store,
            onEmit: forwarder.sink,
            validator: Harness.validator(),
            clock: harness.clock.call,
            idFactory: {
                recordIds += 1
                return "rec-\(recordIds)"
            },
            sessionIdFactory: { harness.sessionId }
        )
        await engine.restore()
        _ = await engine.createSession(modality: nil, exercises: [exercise("sx-free")])

        let surface = WatchLoggingState(engine: engine, clock: harness.clock.call)
        try await surface.log()
        _ = await engine.finishSession()
        await forwarder.drain()

        // The rest timer the log started rides between the set and the session
        // end: its start and its stop each send a `timer_state`. The start's own
        // snapshot (D-91) follows the lifecycle frame the start already sent and
        // is enqueued behind it like any other frame. The clock never advances
        // here, so the rest's window is empty and no `rest` observation travels
        // (D-220) — the two frames are the rest's start and its stop.
        let expectedFrames = [
            "session_lifecycle",
            "session_snapshot",
            "observations_up",
            "timer_state",
            "timer_state",
            "observations_up",
            "session_lifecycle",
        ]
        XCTAssertEqual(recorder.types.count, expectedFrames.count)
        for (index, type) in expectedFrames.enumerated() {
            let sent = index < recorder.types.count ? recorder.types[index] : "<missing>"
            XCTAssertEqual(sent, type, "frame \(index) of the session's emissions")
        }
        XCTAssertEqual(recorder.eventKinds, ["set", "session_end"])
        XCTAssertEqual(recorder.lifecycleStates, ["started", "completed"])
    }

    // MARK: - S-026 a refused frame is reported once and dropped

    func testEveryRefusedFrameIsReportedOnceAndDropped() async throws {
        let recorder = ForwarderRecorder()
        let forwarder = WatchEmitForwarder(
            send: { _ in throw ForwarderTestError.refused },
            onFailure: { recorder.record($0) }
        )

        forwarder.sink(["id": "a"])
        forwarder.sink(["id": "b"])
        await forwarder.drain()

        XCTAssertEqual(recorder.failures.count, 2, "each refused frame is reported exactly once")
        XCTAssertTrue(recorder.frames.isEmpty, "a refused frame is never handed over")
    }

    func testARefusedFrameLeavesNothingQueuedBehindIt() async throws {
        let recorder = ForwarderRecorder()
        let forwarder = WatchEmitForwarder(
            send: { frame in
                guard frame["id"] as? String != "refused" else { throw ForwarderTestError.refused }
                recorder.record(frame)
            },
            onFailure: { recorder.record($0) }
        )

        forwarder.sink(["id": "refused"])
        forwarder.sink(["id": "accepted"])
        await forwarder.drain()

        XCTAssertEqual(recorder.failures.count, 1)
        XCTAssertEqual(recorder.ids, ["accepted"], "the refused frame is dropped, not queued")
        XCTAssertEqual(recorder.frames.count, 1, "it is not re-sent after the failure")
    }

    func testASlowRefusalDoesNotDisturbTheOrderOfTheFramesBehindIt() async throws {
        let recorder = ForwarderRecorder()
        let forwarder = WatchEmitForwarder(
            send: { frame in
                if frame["id"] as? String == "refused" {
                    try await Task.sleep(nanoseconds: 40_000_000)
                    throw ForwarderTestError.refused
                }
                recorder.record(frame)
            },
            onFailure: { recorder.record($0) }
        )

        forwarder.sink(["id": "refused"])
        forwarder.sink(["id": "next"])
        await forwarder.drain()

        XCTAssertEqual(recorder.failures.count, 1)
        XCTAssertEqual(recorder.ids, ["next"])
    }

    // MARK: - S-112 a hung send cannot wedge the chain

    func testS112AHungSendCannotWedgeTheQueue() async throws {
        let recorder = ForwarderRecorder()
        let forwarder = WatchEmitForwarder(
            send: { frame in
                if frame["id"] as? String == "hung" {
                    // Never returns within the bound. The bound, not the send, is
                    // what moves the chain on (D-98).
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    return
                }
                recorder.record(frame)
            },
            onFailure: { recorder.record($0) },
            sendTimeout: 0.05
        )

        forwarder.sink(["id": "hung"])
        forwarder.sink(["id": "next"])

        // The bound is a real clock, so poll to a deadline rather than assuming
        // a fixed duration.
        let deadline = Date().addingTimeInterval(2)
        while recorder.ids != ["next"] && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await forwarder.drain()

        XCTAssertEqual(recorder.ids, ["next"], "the frame behind a wedged send still leaves")
        XCTAssertEqual(recorder.failures.count, 1, "the wedged send is reported exactly once")
        XCTAssertEqual(recorder.frames.count, 1, "and nothing is retried")
    }
}
