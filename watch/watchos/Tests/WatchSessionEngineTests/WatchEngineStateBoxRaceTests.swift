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
//  Phase 4 (slice 2): the session mirror (`current`) and the row mirror
//  (`sessionRows`) move into `WatchEngineSessionState`, and
//  `appliedChangeIds`/`newestSnapshotAt` follow; these two tests are the stress
//  evidence that the lock they take holds under the shipping writer mix.
//
//  Scenario mapping:
//    S-16201 two announcing callers with eight readers  → `testS16201...`
//    S-16202 two simultaneous announcements of one total → `testS16202...`
//    S-16203 the mirror under restore + taps             → `testS16203...`
//    S-16204 the full writer mix against every accessor  → `testS16204...`
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

/// What the reader threads saw that no copy of the engine's state may show.
///
/// The readers run outside XCTest's own thread, so a failed assertion cannot be
/// raised from there; each reader records the violation and the test asserts on
/// the collected list once the window closes.
final class CoherenceNotes {
    private let lock = NSLock()
    private var notes: [String] = []

    func note(_ note: String) {
        lock.lock()
        defer { lock.unlock() }
        notes.append(note)
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return notes
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

    // MARK: - S-16203 the mirror under restore and taps

    /// S-16203: `restore()` (which fills the mirror from storage) and
    /// `advanceExercise()` (which appends a row and moves the mirror) are the two
    /// narrowest writers of `current`/`sessionRows`, and they are the pair 159
    /// §5 could not make TSan report. Eight reader threads copy the mirror and
    /// its projections for the window.
    ///
    /// **What this test can and cannot prove.** TSan does not instrument the
    /// torn-copy refcount damage these two values cause, so this test was green
    /// at HEAD before the box and green after it: it proves no regression and
    /// exercises the lock, not that unboxed state would fail. The justification
    /// for the box is by construction (159 §6, D-16202) — every access is one
    /// `NSLock` acquisition and no accessor awaits.
    ///
    /// The row count **can** fall between two of one reader's samples, and that
    /// is today's behaviour, which the box preserves (D-16203): `restore()`'s
    /// `readAll` snapshot can predate a tap's append, and the fill replaces the
    /// mirror with that older list. What no reader may ever see is a mirror with
    /// no rows at all while a session is held, or a copy that is not one whole
    /// row of this session.
    func testS16203MirrorSurvivesRestoreAndTaps() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(
            modality: "strength",
            exercises: [exercise("sx-bench"), exercise("sx-row")]
        )
        let notes = CoherenceNotes()
        let deadline = Date().addingTimeInterval(Self.window)

        let readers = startCoherenceReaders(engine, until: deadline, notes: notes)
        let writerDeadline = deadline

        let restores = Task.detached { () -> Int in
            var rounds = 0
            while Date() < writerDeadline {
                await engine.restore()
                rounds += 1
            }
            return rounds
        }

        let taps = Task.detached { () -> Int in
            var rounds = 0
            while Date() < writerDeadline {
                _ = await engine.advanceExercise()
                rounds += 1
            }
            return rounds
        }

        await awaitGroup(readers)
        let restoreRounds = await restores.value
        let tapRounds = await taps.value

        XCTAssertGreaterThan(restoreRounds, 10, "S-16203 the restore writer looped many rounds")
        XCTAssertGreaterThan(tapRounds, 10, "S-16203 the tap writer looped many rounds")
        XCTAssertEqual(notes.all, [], "S-16203 no reader saw a torn or shrinking mirror")
        XCTAssertEqual(
            engine.session?.sessionId,
            Self.sessionId,
            "S-16203 the mirror still names the session at window end"
        )
        XCTAssertEqual(
            engine.session?.status,
            WatchSessionStatus.active,
            "S-16203 neither writer ended the session"
        )
    }

    /// Eight reader threads over the mirror and its projections, recording any
    /// copy that is not a whole row of this session and any row count that went
    /// backwards within one reader's own sequence.
    private func startCoherenceReaders(
        _ engine: WatchSessionEngine,
        until deadline: Date,
        notes: CoherenceNotes
    ) -> DispatchGroup {
        let group = DispatchGroup()

        for _ in 0..<Self.readers {
            group.enter()
            DispatchQueue.global().async {
                while Date() < deadline {
                    if let row = engine.session {
                        if row.sessionId != Self.sessionId {
                            notes.note("session copy named \(row.sessionId)")
                        }
                        if row.status == WatchSessionStatus.active,
                           row.currentExerciseIndex >= row.exercises.count {
                            notes.note("active session at index \(row.currentExerciseIndex) of \(row.exercises.count)")
                        }
                    }
                    _ = engine.currentExercise
                    _ = engine.entries
                    if let snapshot = engine.sessionSnapshot(),
                       snapshot["sessionId"] as? String != Self.sessionId {
                        notes.note("snapshot named \(snapshot["sessionId"] as? String ?? "nil")")
                    }
                    let rowCount = engine.sessionRowCountForTesting
                    if rowCount < 1 {
                        notes.note("the mirror held \(rowCount) rows while a session was held")
                    }
                }
                group.leave()
            }
        }
        return group
    }

    // MARK: - S-16204 the full writer mix against every accessor

    /// S-16204: the shipping writer mix — taps, phone frames, `restore()`, and
    /// the sensor pair — all live at once, against every read accessor the
    /// wrist's screens and prompts use.
    ///
    /// **What this test can and cannot prove.** As S-16203: green at HEAD and
    /// green after the box, because TSan cannot see the damage these values
    /// cause. It is the regression guard, not the justification.
    ///
    /// Nothing here asserts that every logged set survived: `restore()`'s fill
    /// replaces the projection mid-window, which is today's behaviour (D-16203).
    func testS16204FullWriterMixSurvivesAllAccessors() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(
            modality: "strength",
            exercises: [exercise("sx-bench"), exercise("sx-row")]
        )
        let clock = TestClock(testInstant())
        let notes = CoherenceNotes()
        let deadline = Date().addingTimeInterval(Self.window)

        let readers = startFullAccessorReaders(engine, until: deadline, notes: notes)

        let taps = Task.detached { () -> Int in
            var rounds = 0
            while Date() < deadline {
                _ = await engine.advanceExercise()
                _ = try? await engine.appendObservation(
                    setEvent(clock, entryId: "e-tap-\(rounds)")
                )
                rounds += 1
            }
            return rounds
        }

        let frames = Task.detached { () -> Int in
            var rounds = 0
            while Date() < deadline {
                _ = try? await engine.applyMessage(
                    Self.structureChange(
                        changeId: "chg-mix-\(rounds)",
                        changes: [
                            [
                                "kind": "add_exercise",
                                "exercise": exercise("sx-push-\(rounds)"),
                            ]
                        ]
                    )
                )
                rounds += 1
            }
            return rounds
        }

        let restores = Task.detached { () -> Int in
            var rounds = 0
            while Date() < deadline {
                await engine.restore()
                rounds += 1
            }
            return rounds
        }

        let sensors = Task.detached { () -> Int in
            var rounds = 0
            while Date() < deadline {
                let instant = testInstant().addingTimeInterval(Double(rounds) / 1_000)
                await engine.appendSensorSample(
                    kind: WatchSensorKind.activeEnergy,
                    value: Double(rounds) * 0.5,
                    recordedAt: instant
                )
                engine.announceEnergy(kilocalories: Double(rounds) * 0.5, at: instant)
                rounds += 1
            }
            return rounds
        }

        await awaitGroup(readers)
        let tapRounds = await taps.value
        let frameRounds = await frames.value
        let restoreRounds = await restores.value
        let sensorRounds = await sensors.value

        XCTAssertGreaterThan(tapRounds, 10, "S-16204 the tap writer looped many rounds")
        XCTAssertGreaterThan(frameRounds, 10, "S-16204 the frame writer looped many rounds")
        XCTAssertGreaterThan(restoreRounds, 10, "S-16204 the restore writer looped many rounds")
        XCTAssertGreaterThan(sensorRounds, 10, "S-16204 the sensor writer looped many rounds")
        XCTAssertEqual(notes.all, [], "S-16204 no reader saw a torn mirror")
        XCTAssertEqual(
            engine.session?.sessionId,
            Self.sessionId,
            "S-16204 the mirror still names the session at window end"
        )
    }

    /// Eight reader threads over every accessor the wrist reads while a workout
    /// runs.
    private func startFullAccessorReaders(
        _ engine: WatchSessionEngine,
        until deadline: Date,
        notes: CoherenceNotes
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
                    _ = engine.pendingObservations()
                    _ = engine.unconfirmedObservations
                    _ = engine.nutritionLog
                    _ = engine.waterLog
                    _ = engine.hasEffortRating(Self.sessionId)
                    if let row = engine.session, row.sessionId != Self.sessionId {
                        notes.note("session copy named \(row.sessionId)")
                    }
                }
                group.leave()
            }
        }
        return group
    }

    /// A conformant `structure_change` from the phone (the shape plan 150's
    /// S-15031 uses): an `add_exercise` that applies.
    private static func structureChange(
        changeId: String,
        changes: [[String: Any]]
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-\(changeId)",
            "sessionId": Self.sessionId,
            "type": "structure_change",
            "origin": "phone",
            "sentAt": utcIso(testInstant()),
            "payload": ["changeId": changeId, "changes": changes],
        ]
    }
}
