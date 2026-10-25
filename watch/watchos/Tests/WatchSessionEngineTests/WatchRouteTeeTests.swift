//
//  WatchRouteTeeTests.swift
//  WatchSessionEngineTests
//
//  Phase 1, run C of
//  `docs/plans/2026-10-24-68-run-route-map-plan/2026-10-24-68-run-route-map-plan.md`:
//  the raw-fix tee on `WatchTrackedLocation` — the route keeper's one observer.
//
//  Scenario mapping:
//    S-9815 the tee sees fresh raw fixes, adds no subscription → `testS9815...`
//    S-9816 rich fields pass through unchanged                 → `testS9816...`
//    S-9810 tee arm: 30 fixes, observer sees all, stream ends  → `testS9810...`
//
//  Fixtures use 0.00001° of latitude = 1.112 m at 52° N; longitude 4.0 and
//  accuracy 5 throughout. The clock is pinned, never the wall clock.
//

import XCTest

@testable import WatchSessionEngine

private final class FixBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [WatchRawFix] = []
    func add(_ fix: WatchRawFix) { lock.lock(); items.append(fix); lock.unlock() }
    var all: [WatchRawFix] { lock.lock(); defer { lock.unlock() }; return items }
}

private final class DistanceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [WatchLocationFix] = []
    private var finished = false
    func add(_ fix: WatchLocationFix) { lock.lock(); items.append(fix); lock.unlock() }
    func done() { lock.lock(); finished = true; lock.unlock() }
    var all: [WatchLocationFix] { lock.lock(); defer { lock.unlock() }; return items }
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
}

final class WatchRouteTeeTests: XCTestCase {

    /// The pinned instant every fixture is stamped from: the freshness gate's
    /// `oldest` is C − 10 s, read once per `fixes()` call.
    private let c = Date(timeIntervalSince1970: 1_800_000_000)

    private func fix(
        _ latitude: Double,
        at seconds: Double,
        altitude: Double? = nil,
        verticalAccuracy: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil
    ) -> WatchRawFix {
        WatchRawFix(
            latitude: latitude,
            longitude: 4.0,
            horizontalAccuracyMeters: 5,
            timestamp: c.addingTimeInterval(seconds),
            altitudeMeters: altitude,
            verticalAccuracyMeters: verticalAccuracy,
            speedMetersPerSecond: speed,
            courseDegrees: course
        )
    }

    /// Consumes the distance stream in the background, collecting what it
    /// yields and when it finishes; the test waits through `eventually`, never
    /// an unbounded await.
    private func collect(_ stream: AsyncStream<WatchLocationFix>) -> DistanceBox {
        let box = DistanceBox()
        Task {
            for await fix in stream { box.add(fix) }
            box.done()
        }
        return box
    }

    // MARK: - S-9815 the tee sees fresh raw fixes, adds no subscription

    func testS9815aTheObserverSeesFreshRawFixesAndTheDistanceIsUnchanged() async throws {
        let raw = ScriptedRawFixSource()
        let tracked = WatchTrackedLocation(source: raw, clock: { self.c })
        let box = FixBox()

        tracked.observeFixes { box.add($0) }
        let distances = collect(tracked.fixes())
        await eventually { raw.subscriptions == 1 }

        raw.fix(fix(52.0, at: -11)) // stale: older than the 10 s gate
        raw.fix(fix(52.0, at: 0)) // f1: the tracker's origin
        raw.fix(fix(52.000009, at: 1)) // f2: 1.0 m from f1, under the floor
        raw.fix(fix(52.00009, at: 2)) // f3: 10.0 m from f1, 5 m/s
        raw.close()

        await eventually({ distances.isFinished }, "a closed raw stream finishes the distance stream")

        XCTAssertEqual(box.all.count, 3, "the stale fix never reaches the observer")
        XCTAssertEqual(box.all.first?.timestamp, c.addingTimeInterval(0))
        XCTAssertEqual(box.all.dropFirst(0).first?.latitude, 52.0)
        XCTAssertEqual(box.all.dropFirst(1).first?.latitude, 52.000009)
        XCTAssertEqual(box.all.dropFirst(2).first?.latitude, 52.00009)
        XCTAssertEqual(box.all.last?.timestamp, c.addingTimeInterval(2))

        let values = distances.all
        XCTAssertEqual(values.count, 1, "only f3 adds something: f1 is the origin, f2 is under the floor")
        XCTAssertEqual(
            try XCTUnwrap(values.first).distanceMeters,
            10.007,
            accuracy: 0.05,
            "f3 is measured from f1, the tracker's reference"
        )
        XCTAssertEqual(raw.subscriptions, 1, "the observer adds no subscription")
    }

    func testS9815bWithoutAnObserverTheDistanceStreamIsTheSame() async throws {
        let raw = ScriptedRawFixSource()
        let tracked = WatchTrackedLocation(source: raw, clock: { self.c })

        let distances = collect(tracked.fixes())
        await eventually { raw.subscriptions == 1 }

        raw.fix(fix(52.0, at: -11))
        raw.fix(fix(52.0, at: 0))
        raw.fix(fix(52.000009, at: 1))
        raw.fix(fix(52.00009, at: 2))
        raw.close()

        await eventually({ distances.isFinished }, "a closed raw stream finishes the distance stream")

        let values = distances.all
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(values.first).distanceMeters,
            10.007,
            accuracy: 0.05
        )
        XCTAssertEqual(raw.subscriptions, 1)
    }

    func testS9815cStillOneSubscriptionPerFixesCall() async throws {
        let raw = ScriptedRawFixSource()
        let tracked = WatchTrackedLocation(source: raw, clock: { self.c })
        let box = FixBox()

        tracked.observeFixes { box.add($0) }

        let first = tracked.fixes()
        await eventually { raw.subscriptions == 1 }
        let second = tracked.fixes()
        await eventually { raw.subscriptions == 2 }

        XCTAssertEqual(raw.subscriptions, 2, "each call is its own effort, observer or not")
        XCTAssertEqual(box.all.count, 0, "nothing was fed, so the observer saw nothing")
        // Both streams stay alive until here: dropping one early would cancel
        // its raw subscription and race the count above.
        _ = (first, second)
    }

    // MARK: - S-9816 rich fields pass through unchanged

    func testS9816aRichFieldsReachTheObserverAsGiven() async throws {
        let raw = ScriptedRawFixSource()
        let tracked = WatchTrackedLocation(source: raw, clock: { self.c })
        let box = FixBox()

        tracked.observeFixes { box.add($0) }
        let distances = collect(tracked.fixes())
        await eventually { raw.subscriptions == 1 }

        let sent = WatchRawFix(
            latitude: 52.0,
            longitude: 4.0,
            horizontalAccuracyMeters: 5,
            timestamp: c,
            altitudeMeters: 12.5,
            verticalAccuracyMeters: 3,
            speedMetersPerSecond: 3.3,
            courseDegrees: 90
        )
        raw.fix(sent)
        raw.close()

        await eventually({ distances.isFinished }, "a closed raw stream finishes the distance stream")
        await eventually { box.all.count == 1 }

        let received = try XCTUnwrap(box.all.first)
        XCTAssertEqual(received.altitudeMeters, 12.5)
        XCTAssertEqual(received.verticalAccuracyMeters, 3)
        XCTAssertEqual(received.speedMetersPerSecond, 3.3)
        XCTAssertEqual(received.courseDegrees, 90)
        XCTAssertEqual(received, sent)
        XCTAssertEqual(distances.all.count, 0, "the origin yields no distance")
    }

    func testS9816bTheOldInitLeavesTheRichFieldsNil() async throws {
        let raw = ScriptedRawFixSource()
        let tracked = WatchTrackedLocation(source: raw, clock: { self.c })
        let box = FixBox()

        tracked.observeFixes { box.add($0) }
        let distances = collect(tracked.fixes())
        await eventually { raw.subscriptions == 1 }

        let sent = WatchRawFix(
            latitude: 52.0,
            longitude: 4.0,
            horizontalAccuracyMeters: 5,
            timestamp: c
        )
        raw.fix(sent)
        raw.close()

        await eventually({ distances.isFinished }, "a closed raw stream finishes the distance stream")
        await eventually { box.all.count == 1 }

        let received = try XCTUnwrap(box.all.first)
        XCTAssertNil(received.altitudeMeters)
        XCTAssertNil(received.verticalAccuracyMeters)
        XCTAssertNil(received.speedMetersPerSecond)
        XCTAssertNil(received.courseDegrees)
        XCTAssertEqual(received, sent)
    }

    // MARK: - S-9810 tee arm: location revoked mid-run

    func testS9810TheTeeObserverSeesAllThirtyFixesAndTheStreamFinishes() async throws {
        let raw = ScriptedRawFixSource()
        let tracked = WatchTrackedLocation(source: raw, clock: { self.c })
        let box = FixBox()

        tracked.observeFixes { box.add($0) }
        let distances = collect(tracked.fixes())
        await eventually { raw.subscriptions == 1 }

        for i in 0..<30 {
            raw.fix(fix(52.0 + Double(i) * 0.00006, at: Double(i)))
        }
        raw.close()

        await eventually({ distances.isFinished }, "a closed raw stream finishes the distance stream")

        XCTAssertEqual(box.all.count, 30, "the observer saw every fresh fix, in order")
        for (i, seen) in box.all.enumerated() {
            XCTAssertEqual(seen.latitude, 52.0 + Double(i) * 0.00006, "fix \(i) out of order")
            XCTAssertEqual(seen.timestamp, c.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(distances.all.count, 29, "the origin yields nothing; the other 29 add")
    }
}
