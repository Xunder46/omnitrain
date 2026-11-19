//
//  WatchEngineSessionStateRaceTests.swift
//  WatchSessionEngineTests
//
//  Plan `docs/plans/2026-11-12-150-watch-crash-fix-plan/2026-11-12-150-watch-crash-fix-plan.md`,
//  task G: the strong stress test for the engine state that is still plain — the
//  session mirror (`current`), the row mirror (`sessionRows`), the
//  correction/deletion lens, the acknowledgement set and the energy marks.
//
//  Thread layout, read off the shipping call sites (evidence file, "Task G"):
//
//    main actor (SwiftUI taps)  createSession, advanceExercise, appendObservation,
//                               startTimer/stopTimer, every screen read
//    radio receive path         applyMessage — `ContentView`'s frame handler hops
//                               off the main actor before `orchestrator.receive`
//    sensor stream tasks        appendSensorSample, announceEnergy — `WatchSensorRecorder`
//                               `consume`'s `Task {}` and `WatchSensorWrites` are
//                               non-isolated, so they run off the main actor
//
//  S-15023's readers ran between writes inside one task group, so the accesses
//  never overlapped and TSan found nothing. Here the readers are real GCD
//  threads and every writer is its own task, all live at once for the whole
//  window; the writers loop for as long as the readers do (hundreds of rounds,
//  not ten), so the overlap is continuous rather than sampled.
//
//  Scenario mapping:
//    S-15031 the session mirror under taps and phone frames  → `testS15031...`
//    S-15032 the correction/deletion lens under phone frames → `testS15032...`
//    S-15033 the sensor task's reads of the mirror           → `testS15033...`
//    S-15034 the acknowledgement set under receipts          → `testS15034...`
//

import Foundation
import XCTest

@testable import WatchSessionEngine

final class WatchEngineSessionStateRaceTests: XCTestCase {

    private static let sessionId = "s-race"

    /// How long every reader and writer runs. Long enough for thousands of
    /// overlapping accesses at TSan's slower pace, short enough that four
    /// scenarios stay a few seconds.
    private static let window: TimeInterval = 1.5

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

    /// Reader threads in the shape of the main actor's screens: every accessor
    /// the logging surface, the summary and the effort-rating prompt read.
    private func startReaders(
        _ engine: WatchSessionEngine,
        until deadline: Date,
        reading: @escaping (WatchSessionEngine) -> Void
    ) -> DispatchGroup {
        let group = DispatchGroup()

        for _ in 0..<3 {
            group.enter()
            DispatchQueue.global().async {
                while Date() < deadline {
                    reading(engine)
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

    private func writerDeadline() -> Date {
        Date().addingTimeInterval(Self.window)
    }
    // MARK: - S-15031 the session mirror

    /// S-15031: the wrist's own taps (one serial writer, like the main actor) and
    /// the phone's frames (their own task) both rewrite `current` and
    /// `sessionRows` while the screens read `session`, `currentExercise`,
    /// `entries` and `sessionSnapshot()`.
    func testS15031SessionMirrorSurvivesConcurrentReadersAndWriters() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(
            modality: "strength",
            exercises: [exercise("sx-bench"), exercise("sx-row")]
        )
        let clock = TestClock(testInstant())
        let deadline = writerDeadline()

        let readers = startReaders(engine, until: deadline) { engine in
            _ = engine.session
            _ = engine.currentExercise
            _ = engine.sessionSnapshot()
            _ = engine.entries
        }

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
                        changeId: "chg-mirror-\(rounds)",
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

        await awaitGroup(readers)
        let tapRounds = await taps.value
        let frameRounds = await frames.value

        XCTAssertGreaterThan(tapRounds, 10, "S-15031 the taps looped many rounds, not ten")
        XCTAssertGreaterThan(frameRounds, 10, "S-15031 the frames looped many rounds, not ten")
        XCTAssertEqual(engine.session?.sessionId, Self.sessionId, "S-15031 the mirror still answers")
        XCTAssertEqual(
            engine.session?.status,
            WatchSessionStatus.active,
            "S-15031 neither writer left the session unreadable"
        )
        XCTAssertEqual(
            engine.entries.filter { $0.entryId.hasPrefix("e-tap-") }.count,
            tapRounds,
            "S-15031 every logged set survived the concurrent frame writer"
        )
    }

    // MARK: - S-15032 the correction and deletion lens

    /// S-15032: the phone's frames correct and delete entries (their own task)
    /// while the screens project `entries` and re-read the pending lists. The
    /// projection folds the lens in on every read, so a write half-way through
    /// it is the crash the lens would cause.
    func testS15032CorrectionLensSurvivesConcurrentFramesAndProjections() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(
            modality: "strength",
            exercises: [exercise("sx-bench")]
        )
        let clock = TestClock(testInstant())
        let logged = 40
        for index in 0..<logged {
            _ = try? await engine.appendObservation(
                setEvent(clock, entryId: "e-lens-\(index)")
            )
        }
        let deadline = writerDeadline()

        let readers = startReaders(engine, until: deadline) { engine in
            _ = engine.entries
            _ = engine.pendingObservations()
            _ = engine.unconfirmedObservations
            _ = engine.sessionSnapshot()
        }

        let deletes = Task.detached { () -> Int in
            var rounds = 0
            while Date() < deadline {
                let entryId = "e-lens-\(rounds % logged)"
                _ = try? await engine.applyMessage(
                    Self.structureChange(
                        changeId: "chg-lens-\(rounds)",
                        changes: [
                            ["kind": "correct_entry", "entryId": entryId, "correction": ["reps": 6]],
                            ["kind": "delete_entry", "entryId": entryId],
                        ]
                    )
                )
                rounds += 1
            }
            return rounds
        }

        await awaitGroup(readers)
        let rounds = await deletes.value

        XCTAssertGreaterThan(rounds, 10, "S-15032 the lens writer looped many rounds")
        XCTAssertEqual(engine.session?.sessionId, Self.sessionId, "S-15032 the mirror still answers")
        XCTAssertTrue(
            engine.entries.allSatisfy { !$0.entryId.hasPrefix("e-lens-") },
            "S-15032 every id the phone deleted stayed deleted"
        )
    }

    // MARK: - S-15033 the sensor task's reads of the mirror

    /// S-15033: the sensor stream's tasks — `recordEnergy`'s
    /// `appendSensorSample` then `announceEnergy`, off the main actor — read
    /// `current` and the sensor log while the wrist's taps rewrite the mirror
    /// and the logging screen reads the readings.
    func testS15033SensorTaskReadsRaceTheSessionMirror() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(
            modality: "cardio_endurance",
            exercises: [exercise("sx-run")]
        )

        let deadline = writerDeadline()

        let readers = startReaders(engine, until: deadline) { engine in
            _ = engine.sensorSamples
            _ = engine.newestSensorSamples()
            _ = engine.session
            _ = engine.currentExercise
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

        let taps = Task.detached { () -> Int in
            var rounds = 0
            while Date() < deadline {
                _ = await engine.advanceExercise()
                rounds += 1
            }
            return rounds
        }

        await awaitGroup(readers)
        let rounds = await sensors.value
        let tapRounds = await taps.value

        XCTAssertGreaterThan(rounds, 10, "S-15033 the sensor task looped many rounds")
        XCTAssertGreaterThan(tapRounds, 10, "S-15033 the tap writer looped many rounds")
        XCTAssertEqual(
            engine.sensorSamples.filter { $0.kind == WatchSensorKind.activeEnergy }.count,
            rounds,
            "S-15033 every reading the sensor task stored is held exactly once"
        )
        XCTAssertEqual(engine.session?.sessionId, Self.sessionId, "S-15033 the mirror still answers")
    }

    // MARK: - S-15034 the acknowledgement set

    /// S-15034: a receipt (the phone's frame, off the main actor) confirms
    /// entries while the effort-rating prompt and the pending lists read the
    /// same set. The set is what answers both after a prune, so a torn read is
    /// the prompt asking for a rating the wrist already recorded.
    func testS15034AcknowledgementSetSurvivesConcurrentReceiptsAndReads() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(
            modality: "strength",
            exercises: [exercise("sx-bench")]
        )
        let clock = TestClock(testInstant())
        let logged = 60
        let entryIds = (0..<logged).map { "e-ack-\($0)" }
        for entryId in entryIds {
            _ = try? await engine.appendObservation(setEvent(clock, entryId: entryId))
        }
        let ids = entryIds
        let deadline = writerDeadline()

        let readers = startReaders(engine, until: deadline) { engine in
            _ = engine.hasEffortRating(Self.sessionId)
            _ = engine.pendingObservations()
            _ = engine.unconfirmedObservations
        }

        let receipts = Task.detached { () -> Int in
            var rounds = 0
            while Date() < deadline {
                _ = await engine.confirmObservations(ids)
                rounds += 1
            }
            return rounds
        }

        await awaitGroup(readers)
        let rounds = await receipts.value

        XCTAssertGreaterThan(rounds, 10, "S-15034 the receipt writer looped many rounds")
        XCTAssertTrue(
            engine.pendingObservations().isEmpty,
            "S-15034 every acknowledged entry is still acknowledged"
        )
        XCTAssertEqual(engine.session?.sessionId, Self.sessionId, "S-15034 the mirror still answers")
    }

    // MARK: - Frames

    /// A conformant `structure_change` from the phone, the shape
    /// `WatchLiveMirroringTests` replays.
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
