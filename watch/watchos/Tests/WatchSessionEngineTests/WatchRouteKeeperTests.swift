//
//  WatchRouteKeeperTests.swift
//  WatchSessionEngineTests
//
//  Phase 1, run B of
//  `docs/plans/2026-10-24-68-run-route-map-plan/2026-10-24-68-run-route-map-plan.md`:
//  the rules for which GPS points enter a Health route, and when the route is
//  kept.
//
//  Scenario mapping:
//    S-9801  an outdoor run records, batches and saves   → `testS9801`
//    S-9803  the accuracy gate                           → `testS9803`
//    S-9804  duplicates and out-of-order                 → `testS9804`
//    S-9805  nothing before the workout began            → `testS9805`
//    S-9806  teleport (speed gate), arm a                → `testS9806a`
//    S-9806  teleport (speed gate), arm b                → `testS9806b`
//    S-9807  treadmill / standing in place, arm a        → `testS9807a`
//    S-9807  treadmill / standing in place, arm b        → `testS9807b`
//    S-9807  treadmill / standing in place, arm c        → `testS9807c`
//    S-9808  no GPS fix at all                           → `testS9808`
//    S-9809  one fix only                                → `testS9809`
//    S-9810  location revoked mid-run (keeper arm)       → `testS9810`
//    S-9811  pause / GPS gap                             → `testS9811`
//    S-9812  very long run                               → `testS9812`
//    S-9813  closed keeper refuses; reopen starts fresh  → `testS9813`
//    S-9814  activation matrix (Q1)                      → `testS9814`
//
//  The arithmetic is the plan's own: at 52° N one second of the fixture's
//  0.00006° of latitude is 6.672 m, so the S-9801 spread is 73.4 m and the
//  S-9807 treadmill spread stays under the 50 m floor. Every number asserted
//  here is a count of accepted fixes, a batch size, a timestamp or a verdict —
//  never a distance the production code does not itself compute.
//

import XCTest

@testable import WatchSessionEngine

final class WatchRouteKeeperTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// fix(t, lat, acc): the plan's shorthand. Longitude 4.0.
    private func fix(_ t: Double, _ lat: Double, _ acc: Double = 5) -> WatchRawFix {
        WatchRawFix(latitude: lat, longitude: 4.0, horizontalAccuracyMeters: acc,
                    timestamp: t0.addingTimeInterval(t))
    }

    private func keeper(outdoors: Bool = true, name: String = "running", sharing: Bool = true) -> WatchRouteKeeper {
        let keeper = WatchRouteKeeper()
        keeper.open(outdoors: outdoors, activityName: name, routeSharingAllowed: sharing, beganAt: t0)
        return keeper
    }

    /// The non-empty batches handed out while offering `fixes` in order.
    private func batches(_ keeper: WatchRouteKeeper, _ fixes: [WatchRawFix]) -> [[WatchRawFix]] {
        var out: [[WatchRawFix]] = []
        for item in fixes {
            let batch = keeper.offer(item)
            if !batch.isEmpty { out.append(batch) }
        }
        return out
    }

    private func seconds(_ batch: [WatchRawFix]) -> [Double] {
        batch.map { $0.timestamp.timeIntervalSince(t0) }
    }

    /// 12 fixes of S-9801: fix(i, 52.0 + i*0.00006, 5), i = 0...11.
    private func run12() -> [WatchRawFix] { (0..<12).map { fix(Double($0), 52.0 + Double($0) * 0.00006) } }

    // MARK: S-9801

    func testS9801() {
        let k = keeper()
        let handed = batches(k, run12())
        XCTAssertEqual(handed.count, 1, "S-9801: exactly one batch while offering 12 fixes")
        XCTAssertEqual(seconds(handed[0]), (0...9).map(Double.init), "S-9801: the batch is fixes 0..9")
        XCTAssertEqual(k.acceptedCount, 12, "S-9801: all 12 fixes accepted")
        let end = k.close()
        XCTAssertEqual(seconds(end.remainder), [10.0, 11.0], "S-9801: close hands out fixes 10 and 11")
        XCTAssertEqual(end.verdict, .save, "S-9801: 73.4 m spread saves the route")
    }

    // MARK: S-9803

    func testS9803() {
        let k = keeper()
        let accuracies: [Double] = [-1, 0, 50, 50.01, .nan, 120]
        for (i, acc) in accuracies.enumerated() {
            _ = k.offer(fix(Double(i), 52.0 + Double(i) * 0.00006, acc))
        }
        _ = k.offer(fix(6, 91.0, 5))
        _ = k.offer(fix(7, .nan, 5))
        XCTAssertEqual(k.acceptedCount, 2, "S-9803: only accuracies 0 and 50 accepted")
        let end = k.close()
        XCTAssertEqual(end.verdict, .discard, "S-9803: 6.672 m spread discards")
        XCTAssertEqual(end.remainder.count, 2, "S-9803: the two accepted fixes are the remainder")
    }

    // MARK: S-9804

    func testS9804() {
        let k = keeper()
        _ = k.offer(fix(5, 52.0))
        _ = k.offer(fix(5, 52.00006))
        _ = k.offer(fix(4, 52.00012))
        _ = k.offer(fix(6, 52.00012))
        XCTAssertEqual(k.acceptedCount, 2, "S-9804: the duplicate and the out-of-order fix are refused")
        let end = k.close()
        XCTAssertEqual(seconds(end.remainder), [5.0, 6.0], "S-9804: the accepted fixes are the 1st and the 4th")
    }

    // MARK: S-9805

    func testS9805() {
        let k = keeper()
        _ = k.offer(fix(-1, 52.0))
        _ = k.offer(fix(0, 52.00006))
        XCTAssertEqual(k.acceptedCount, 1, "S-9805: the fix before the workout began is refused")
    }

    // MARK: S-9806

    func testS9806a() {
        let k = keeper()
        _ = k.offer(fix(0, 52.0))
        _ = k.offer(fix(1, 52.0002))
        _ = k.offer(fix(2, 52.00017))
        XCTAssertEqual(k.acceptedCount, 2, "S-9806a: the 22.24 m/s teleport is refused")
        let end = k.close()
        XCTAssertEqual(seconds(end.remainder), [0.0, 2.0], "S-9806a: the rejected fix never became the reference")
    }

    func testS9806b() {
        let k = keeper()
        _ = k.offer(fix(0, 52.0))
        _ = k.offer(fix(1, 52.00017))
        XCTAssertEqual(k.acceptedCount, 2, "S-9806b: 18.90 m/s is under the gate, both accepted")
    }

    // MARK: S-9807

    private func treadmill(_ extra: WatchRawFix?) -> (count: Int, verdict: WatchRouteVerdict) {
        let k = keeper()
        let c = [0.0, 0.0002, 0.0004, 0.0002]
        let fixes = (0..<300).map { fix(Double(2 * $0), 52.0 + c[$0 % 4], 10) }
        var all = fixes
        if let extra { all.append(extra) }
        let handed = batches(k, all)
        XCTAssertEqual(handed.count, 30, "S-9807: 300+ fixes hand out exactly 30 batches")
        let end = k.close()
        return (k.acceptedCount, end.verdict)
    }

    func testS9807a() {
        let result = treadmill(nil)
        XCTAssertEqual(result.count, 300, "S-9807a: all 300 in-place fixes accepted")
        XCTAssertEqual(result.verdict, .discard, "S-9807a: 44.48 m spread discards")
    }

    func testS9807b() {
        let result = treadmill(fix(600, 52.00045, 10))
        XCTAssertEqual(result.count, 301, "S-9807b: the 301st fix is accepted")
        XCTAssertEqual(result.verdict, .save, "S-9807b: 50.038 m spread saves")
    }

    func testS9807c() {
        let result = treadmill(fix(600, 52.00044, 10))
        XCTAssertEqual(result.count, 301, "S-9807c: the 301st fix is accepted")
        XCTAssertEqual(result.verdict, .discard, "S-9807c: 48.926 m spread discards")
    }

    // MARK: S-9808

    func testS9808() {
        let k = keeper()
        let end = k.close()
        XCTAssertTrue(end.remainder.isEmpty, "S-9808: nothing to hand out")
        XCTAssertEqual(end.verdict, .discard, "S-9808: no fix at all discards")
        XCTAssertEqual(k.acceptedCount, 0, "S-9808: nothing accepted")
    }

    // MARK: S-9809

    func testS9809() {
        let k = keeper()
        _ = k.offer(fix(0, 52.0))
        let end = k.close()
        XCTAssertEqual(end.verdict, .discard, "S-9809: one fix only discards")
        XCTAssertEqual(seconds(end.remainder), [0.0], "S-9809: close hands out fix 0")
    }

    // MARK: S-9810

    func testS9810() {
        let k = keeper()
        let fixes = (0..<30).map { fix(Double($0), 52.0 + Double($0) * 0.00006) }
        let handed = batches(k, fixes)
        XCTAssertEqual(handed.count, 3, "S-9810: 30 fixes hand out 3 batches")
        for batch in handed {
            XCTAssertEqual(batch.count, 10, "S-9810: every batch has exactly 10")
        }
        let end = k.close()
        XCTAssertTrue(end.remainder.isEmpty, "S-9810: nothing left at close")
        XCTAssertEqual(end.verdict, .save, "S-9810: 193.5 m spread saves")
    }

    // MARK: S-9811

    func testS9811() {
        let k = keeper()
        var fixes = (0..<60).map { fix(Double($0), 52.0 + Double($0) * 0.00006) }
        fixes.append(fix(359, 52.00354 + 0.0036))
        fixes.append(contentsOf: (0..<59).map { k in
            fix(360.0 + Double(k), 52.00714 + Double(k + 1) * 0.00006)
        })
        let handed = batches(k, fixes)
        XCTAssertEqual(k.acceptedCount, 120, "S-9811: all 120 fixes accepted across the gap")
        XCTAssertEqual(handed.count, 12, "S-9811: 12 batches")
        let end = k.close()
        XCTAssertTrue(end.remainder.isEmpty, "S-9811: nothing left at close")
        XCTAssertEqual(end.verdict, .save, "S-9811: one route, no break")
    }

    // MARK: S-9812

    func testS9812() {
        let k = keeper()
        let fixes = (0..<10_800).map { fix(Double($0), 52.0 + Double($0) * 0.00003) }
        let handed = batches(k, fixes)
        XCTAssertEqual(handed.count, 1_080, "S-9812: exactly 1080 hand-outs")
        for batch in handed {
            XCTAssertEqual(batch.count, 10, "S-9812: every batch has exactly 10")
        }
        XCTAssertEqual(k.acceptedCount, 10_800, "S-9812: all 10800 fixes accepted")
        let end = k.close()
        XCTAssertTrue(end.remainder.isEmpty, "S-9812: nothing left at close")
        XCTAssertEqual(end.verdict, .save, "S-9812: 36024 m spread saves")
    }

    // MARK: S-9813

    func testS9813() {
        let k = keeper()
        _ = batches(k, run12())
        let end = k.close()
        XCTAssertEqual(end.verdict, .save, "S-9813: the S-9801 flow closed with save")
        let refused = k.offer(fix(12, 52.00072))
        XCTAssertTrue(refused.isEmpty, "S-9813: a closed keeper hands out nothing")
        XCTAssertEqual(k.acceptedCount, 12, "S-9813: the post-close fix changed nothing")
        let reopened = k.open(outdoors: true, activityName: "running", routeSharingAllowed: true, beganAt: t0)
        XCTAssertTrue(reopened, "S-9813: reopen records again")
        XCTAssertEqual(k.acceptedCount, 0, "S-9813: reopen starts fresh")
        let after = k.offer(fix(0, 52.0))
        XCTAssertEqual(after.count, 0, "S-9813: one fix is not yet a batch")
        XCTAssertEqual(k.acceptedCount, 1, "S-9813: the earlier timestamp is accepted after reopen")
    }

    // MARK: S-9814

    func testS9814() {
        let denied: [(Bool, String, Bool)] = [
            (false, "running", true),
            (true, "other", true),
            (true, "traditionalStrengthTraining", true),
            (true, "flexibility", true),
            (true, "crossTraining", true),
            (true, "running", false),
        ]
        for (outdoors, name, sharing) in denied {
            let k = keeper(outdoors: outdoors, name: name, sharing: sharing)
            XCTAssertFalse(
                k.open(outdoors: outdoors, activityName: name, routeSharingAllowed: sharing, beganAt: t0),
                "S-9814: open(\(outdoors), \(name), \(sharing)) does not record")
            let handed = batches(k, run12())
            XCTAssertTrue(handed.isEmpty, "S-9814: no batch for open(\(outdoors), \(name), \(sharing))")
            XCTAssertEqual(k.acceptedCount, 0, "S-9814: nothing accepted for open(\(outdoors), \(name), \(sharing))")
            let end = k.close()
            XCTAssertEqual(end.remainder, [], "S-9814: empty remainder for open(\(outdoors), \(name), \(sharing))")
            XCTAssertEqual(end.verdict, .none, "S-9814: verdict none for open(\(outdoors), \(name), \(sharing))")
        }
        let control = keeper()
        XCTAssertTrue(
            control.open(outdoors: true, activityName: "running", routeSharingAllowed: true, beganAt: t0),
            "S-9814: the positive control records")
    }
}
