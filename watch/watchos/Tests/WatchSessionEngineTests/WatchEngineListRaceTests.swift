//
//  WatchEngineListRaceTests.swift
//  WatchSessionEngineTests
//
//  Plan `docs/plans/2026-11-12-150-watch-crash-fix-plan/2026-11-12-150-watch-crash-fix-plan.md`,
//  task F: the engine's other in-memory lists have the same shape as the sensor
//  log Task A fixed — written from the async entry points (a phone frame's
//  delivery task, a logging tap, a sensor stream) while the wrist's screens read
//  them on the main thread.
//
//  Scenario mapping:
//    S-15021 observation list, concurrent appends and reads   → `testS15021...`
//    S-15022 timer list, concurrent starts/stops and reads     → `testS15022...`
//    S-15023 session mirror and correction lens                → `testS15023...`
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// An emit sink the concurrent writers can share. `Harness`'s own recorder is a
/// plain array, so a race there would report the test's sink instead of the
/// engine's state.
final class LockedFrameSink {
    private let lock = NSLock()
    private var stored: [[String: Any]] = []

    func append(_ frame: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(frame)
    }

    var frames: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

final class WatchEngineListRaceTests: XCTestCase {

    /// An engine over the serialised store with an emit sink that can take
    /// writes from many tasks. Every id is minted per call, so the writers never
    /// share an id by accident.
    private func raceEngine(_ sink: LockedFrameSink) -> WatchSessionEngine {
        WatchSessionEngine(
            store: SerialSessionStore(),
            onEmit: { sink.append($0) },
            validator: Harness.validator(),
            clock: { testInstant() },
            idFactory: { UUID().uuidString },
            sessionIdFactory: { "s-race" }
        )
    }

    /// S-15021: many logging tasks append while the logging surfaces read the
    /// lists. A plain array traps or loses rows under that; with one lock every
    /// logged set is held exactly once and no read faults.
    func testS15021ObservationListSurvivesConcurrentWritersAndReaders() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(modality: "strength", exercises: [exercise("sx-bench")])
        let clock = TestClock(testInstant())

        let writers = 3
        let perWriter = 60
        let readers = 3
        let expected = writers * perWriter

        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<writers {
                group.addTask {
                    for index in 0..<perWriter {
                        _ = try? await engine.appendObservation(
                            setEvent(clock, entryId: "e-\(writer)-\(index)")
                        )
                    }
                }
            }
            for _ in 0..<readers {
                group.addTask {
                    for _ in 0..<400 {
                        _ = engine.observations
                        _ = engine.entries
                        _ = engine.pendingObservations()
                        _ = engine.unconfirmedObservations
                        _ = engine.nutritionLog
                        _ = engine.waterLog
                        await Task.yield()
                    }
                }
            }
        }

        let stored = engine.observations
        XCTAssertEqual(stored.count, expected, "S-15021 every logged set is held exactly once")
        XCTAssertEqual(
            Set(stored.map(\.recordId)).count,
            expected,
            "S-15021 and no racing append doubled a row"
        )
    }

    /// S-15022: the timer list is appended by the logging taps and by phone
    /// frames while `timerFor`/`timerRows` read it. Every start and stop is held
    /// once and the newest row the readout sees is the last one written.
    func testS15022TimerListSurvivesConcurrentWritersAndReaders() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(modality: "strength", exercises: [exercise("sx-bench")])

        let rounds = 60
        let readers = 3

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for _ in 0..<rounds {
                    _ = try? await engine.startTimer(WatchTimerKind.rest)
                    _ = await engine.stopTimer(kind: WatchTimerKind.rest)
                }
            }
            for _ in 0..<readers {
                group.addTask {
                    for _ in 0..<400 {
                        _ = engine.timerFor(WatchTimerKind.rest)
                        _ = engine.timerRows(WatchTimerKind.rest)
                        _ = engine.sessionSnapshot()
                        await Task.yield()
                    }
                }
            }
        }

        XCTAssertEqual(
            engine.timerRows(WatchTimerKind.rest).count,
            rounds * 2,
            "S-15022 every start and stop is held exactly once"
        )
        XCTAssertEqual(
            engine.timerFor(WatchTimerKind.rest)?.state,
            WatchTimerState.stopped,
            "S-15022 the newest stored timer is the one the readout sees"
        )
    }

    /// S-15023: the session mirror, the row list retention reads, and the
    /// deletion lens are written by transitions and phone frames while the
    /// screens read `session`/`entries`. The session stays readable and the
    /// tombstone still hides its entry once the writers are done.
    func testS15023SessionMirrorAndCorrectionLensSurviveConcurrentWritersAndReaders() async {
        let sink = LockedFrameSink()
        let engine = raceEngine(sink)
        await engine.restore()
        _ = await engine.createSession(
            modality: "strength",
            exercises: [exercise("sx-bench"), exercise("sx-row")]
        )

        let deleted = "e-gone"
        let advances = 80
        let changes = 40
        let readers = 3

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for _ in 0..<advances {
                    _ = await engine.advanceExercise()
                }
            }
            group.addTask {
                for index in 0..<changes {
                    _ = try? await engine.applyMessage(
                        self.deleteEntryFrame(
                            sessionId: "s-race",
                            changeId: "chg-race-\(index)",
                            entryId: deleted
                        )
                    )
                }
            }
            for _ in 0..<readers {
                group.addTask {
                    for _ in 0..<400 {
                        _ = engine.session
                        _ = engine.currentExercise
                        _ = engine.sessionSnapshot()
                        _ = engine.entries
                        _ = engine.hasEffortRating(deleted)
                        _ = engine.sensorSamples
                        await Task.yield()
                    }
                }
            }
        }

        let session = engine.session
        XCTAssertEqual(session?.sessionId, "s-race", "S-15023 the mirror still answers its session")
        XCTAssertEqual(
            session?.status,
            WatchSessionStatus.active,
            "S-15023 a transition never left the session unreadable"
        )
        XCTAssertFalse(
            engine.entries.contains { $0.entryId == deleted },
            "S-15023 the deletion lens still hides the id the phone deleted"
        )
    }

    private func deleteEntryFrame(
        sessionId: String,
        changeId: String,
        entryId: String
    ) -> [String: Any] {
        [
            "protocolVersion": SyncProtocolValidator.protocolVersion,
            "messageId": "msg-\(changeId)",
            "sessionId": sessionId,
            "type": "structure_change",
            "origin": "phone",
            "sentAt": utcIso(testInstant()),
            "payload": [
                "changeId": changeId,
                "changes": [["kind": "delete_entry", "entryId": entryId]],
            ],
        ]
    }
}
