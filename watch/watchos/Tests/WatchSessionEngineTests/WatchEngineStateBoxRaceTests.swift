//
//  WatchEngineStateBoxRaceTests.swift
//  WatchSessionEngineTests
//
//  Plan `docs/plans/2026-11-14-162-engine-state-lock-box-plan/2026-11-14-162-engine-state-lock-box-plan.md`,
//  Phase 1 (slice 1): the three energy-announce marks — `energyAnnouncedSession`,
//  `energyAnnouncedKcal`, `energyAnnouncedAt` — are read and written from
//  `announceEnergy`, which the sensor stream calls off the main actor while a
//  second stream task can call it again. 159's TSan attempts proved the race.
//  Slice 1 puts the guard, the envelope, the validator check and the three
//  writes in one synchronous section; this file is its red-then-green evidence.
//
//  Scenario mapping:
//    S-16201 two announcing callers with eight readers  → `testS16201...`
//    S-16202 two simultaneous announcements of one total → `testS16202...`
//
//  Thread layout, as in plan 150's race files: readers on real GCD threads,
//  writers as detached tasks for the whole window, the group waited on without
//  blocking a cooperative-pool thread the writers need.
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// Hands each announcing caller the next round of the shared rising sequence,
/// so a total is announced exactly once across both callers.
///
/// A counter per caller lets the two drifts apart, and a laggard announcing a
/// lower total takes the rule's "the value fell" branch — legitimate behaviour,
/// but it would announce a total twice and make S-16201's distinctness assertion
/// flaky rather than a guard on the engine. This lock is the test's, taken for
/// one increment only: it orders no engine access.
final class AnnouncedRounds {
    private let lock = NSLock()
    private var next = 0

    func nextRound() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let round = next
        next += 1
        return round
    }
}

final class WatchEngineStateBoxRaceTests: XCTestCase {

    private static let sessionId = "s-race"

    /// S-16201's window: long enough for thousands of overlapping announcements
    /// and reads at TSan's pace, short enough to keep the file quick.
    private static let window: TimeInterval = 1.5

    /// Eight readers, the S-zz2 reader set — the shape 159's scratch probe ran.
    private static let readers = 8

    /// An engine over the serialised store, with an emit sink many tasks can
    /// write. A validator, so the section's check is exercised; a fixed clock.
    private func raceEngine(_ sink: LockedFrameSink) -> WatchSessionEngine {
        WatchSessionEngine(
            store: SerialSessionStore(),
            onEmit: { sink.append($0) },
            validator: Harness.validator(),
            clock: { testInstant() },
            idFactory: { UUID().uuidString },
            sessionIdFactory: { Self.sessionId }
        )
    }

    /// The screens' read set, on real GCD threads for the whole window.
    private func startReaders(
        _ engine: WatchSessionEngine,
        until deadline: Date
    ) -> DispatchGroup {
        let group = DispatchGroup()

        for _ in 0..<Self.readers {
            group.enter()
            DispatchQueue.global().async {
                while Date() < deadline {
                    _ = engine.session
                    _ = engine.currentExercise
                    _ = engine.observations
                    _ = engine.sensorSamples
                    _ = engine.newestSensorSamples()
                    _ = engine.timerRows("work")
                    _ = engine.entries
                    _ = engine.sessionSnapshot()
                }
                group.leave()
            }
        }
        return group
    }

    /// Waits for `group` without blocking a cooperative-pool thread the writers
    /// need.
    private func awaitGroup(_ group: DispatchGroup) async {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) { continuation.resume() }
        }
    }

    private func energyLiveFrames(_ sink: LockedFrameSink) -> [[String: Any]] {
        sink.frames.filter { $0["type"] as? String == "energy_live" }
    }

    private func activeEnergy(_ frame: [String: Any]) -> Double? {
        (frame["payload"] as? [String: Any])?["activeEnergyKcal"] as? Double
    }

    // MARK: - S-16201 the marks under two announcing callers

    /// S-16201: two callers announce the same rising sequence — round *r*
    /// announces `Double(r) * 0.5` at `testInstant() + 10 r` — while eight
    /// reader threads copy the screens' accessors. Every announcement reads the
    /// marks, evaluates the rule and writes them, so the two callers race on all
    /// three.
    ///
    /// Under TSan this is red before slice 1: the reports name
    /// `WatchSessionEngine.swift` `announceEnergy` at the mark writes (and the
    /// guard's reads). After slice 1 the section is one synchronous span, so no
    /// report names the marks and this test's own assertions hold: every total
    /// the sink holds was announced once, and every frame conforms.
    ///
    /// No stored sensor reading is made, so `announceEnergy`'s total is the raw
    /// `kilocalories` argument — the no-stored-sample branch of the live total.
    func testS16201EnergyMarksSurviveTwoAnnouncingCallers() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [exercise("sx-run")]
        )
        let start = testInstant()
        let deadline = Date().addingTimeInterval(Self.window)
        let rounds = AnnouncedRounds()

        let readers = startReaders(engine, until: deadline)

        func announcingCaller() -> Task<Int, Never> {
            Task.detached {
                var calls = 0
                while Date() < deadline {
                    let round = rounds.nextRound()
                    engine.announceEnergy(
                        kilocalories: Double(round) * 0.5,
                        at: start.addingTimeInterval(Double(round) * 10)
                    )
                    calls += 1
                }
                return calls
            }
        }

        let first = announcingCaller()
        let second = announcingCaller()

        await awaitGroup(readers)
        let firstCalls = await first.value
        let secondCalls = await second.value

        XCTAssertGreaterThan(firstCalls, 10, "S-16201 the first caller looped many rounds, not ten")
        XCTAssertGreaterThan(secondCalls, 10, "S-16201 the second caller looped many rounds, not ten")

        let frames = energyLiveFrames(sink)
        let totals = frames.compactMap(activeEnergy)
        XCTAssertGreaterThanOrEqual(frames.count, 1, "S-16201 the window announced at least one total")
        XCTAssertEqual(totals.count, frames.count, "S-16201 every frame carries a numeric total")
        XCTAssertEqual(
            Set(totals).count,
            totals.count,
            "S-16201 no total was announced twice across the two callers: \(totals)"
        )
        // The window emits thousands of frames; conformance is the same shape on
        // every one, so the first few are the sample (one validator, not one per
        // frame).
        let validator = Harness.validator()
        for frame in frames.prefix(8) {
            XCTAssertEqual(frame["sessionId"] as? String, Self.sessionId, "S-16201 every frame names the session")
            XCTAssertEqual(
                validator.validateEnvelope(frame),
                [],
                "S-16201 every emitted frame conforms: \(frame)"
            )
        }
        XCTAssertEqual(engine.session?.sessionId, Self.sessionId, "S-16201 the mirror still answers")
    }

    // MARK: - S-16202 one total, two simultaneous announcements

    /// S-16202: two callers announce the same total at the same instant, started
    /// together, with no other writer. The first caller's section records the
    /// marks; the second's compare sees them (same total, rise 0 < 0.5) and
    /// suppresses, so exactly one frame leaves.
    ///
    /// Red-at-HEAD is not guaranteed — the two-callers window is narrow and
    /// probabilistic (S-16201's TSan run is the red evidence); this is the
    /// behaviour pin, green-after required.
    func testS16202TwoSimultaneousAnnouncementsEmitOneFrame() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [exercise("sx-run")]
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    engine.announceEnergy(kilocalories: 12.0, at: testInstant())
                }
            }
        }

        let frames = energyLiveFrames(sink)
        XCTAssertEqual(
            frames.count,
            1,
            "S-16202 two simultaneous announcements of one total emit one frame"
        )
        XCTAssertEqual(
            frames.first.flatMap(activeEnergy),
            12.0,
            "S-16202 the one frame carries the announced total"
        )
    }
}
