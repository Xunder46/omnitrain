//
//  WatchSensorSampleRaceTests.swift
//  WatchSessionEngineTests
//
//  Plan `docs/plans/2026-11-12-150-watch-crash-fix-plan/2026-11-12-150-watch-crash-fix-plan.md`,
//  scenario S-15001: the raw sensor readings are written from the platform
//  calls' threads while the logging screen reads them on the main thread.
//
//  Scenario mapping:
//    S-15001 concurrent appends and reads          → `testS15001...`
//

import Foundation
import XCTest

@testable import WatchSessionEngine

/// The in-memory store behind the package's own async mutex.
///
/// S-15001 appends from many tasks at once, and a store that is not serialised
/// would race on its own rows — hiding the list race the test is about. An
/// actor will not do: actor methods are reentrant across an `await`, so the
/// rows would still be reached concurrently.
final class SerialSessionStore: WatchSessionStore {
    private let mutex = WatchAsyncMutex()
    private let inner = InMemoryWatchSessionStore()

    func append(_ record: StoredWatchRecord) async -> StoredWatchRecord {
        await mutex.exclusive { await inner.append(record) }
    }

    func readAll() async -> WatchStoreContents {
        await mutex.exclusive { await inner.readAll() }
    }

    func pruneConfirmed() async -> [String] {
        await mutex.exclusive { await inner.pruneConfirmed() }
    }

    func pruneSensorSamples(_ sessionIds: [String]) async -> [String] {
        await mutex.exclusive { await inner.pruneSensorSamples(sessionIds) }
    }

    func pruneExerciseBatches(keepingVersion: String) async -> [String] {
        await mutex.exclusive {
            await inner.pruneExerciseBatches(keepingVersion: keepingVersion)
        }
    }

    func pruneBests(keepingRecordId: String) async -> [String] {
        await mutex.exclusive {
            await inner.pruneBests(keepingRecordId: keepingRecordId)
        }
    }

    func pruneWater(keepingRecordId: String) async -> [String] {
        await mutex.exclusive {
            await inner.pruneWater(keepingRecordId: keepingRecordId)
        }
    }

    func pruneWaterTaps(loggedBefore cutoff: Date) async -> [String] {
        await mutex.exclusive { await inner.pruneWaterTaps(loggedBefore: cutoff) }
    }
}

final class WatchSensorSampleRaceTests: XCTestCase {

    /// S-15001: many appends racing reads trap on a plain array (the device's
    /// SIGABRT) and lose or duplicate rows. With the log's one lock, every
    /// distinct reading is held exactly once and no read ever faults.
    func testS15001ConcurrentAppendsAndReadsAreSafe() async {
        let harness = Harness(store: SerialSessionStore())
        let engine = await harness.runningEngine()
        _ = await engine.createSession(modality: "cardio_endurance")

        let writers = 8
        let perWriter = 250
        let readers = 4
        let start = testInstant()
        let expected = writers * perWriter

        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<writers {
                group.addTask {
                    for index in 0..<perWriter {
                        // One reading per millisecond: the record id is derived
                        // from kind and instant, so each is a distinct row.
                        let instant = start.addingTimeInterval(
                            Double(writer * perWriter + index) / 1_000
                        )
                        await engine.appendSensorSample(
                            kind: WatchSensorKind.heartRate,
                            value: Double(writer * perWriter + index),
                            recordedAt: instant
                        )
                    }
                }
            }
            for _ in 0..<readers {
                group.addTask {
                    for _ in 0..<2_000 {
                        _ = engine.sensorSamples.count
                        _ = engine.newestSensorSamples().count
                        await Task.yield()
                    }
                }
            }
        }

        let samples = engine.sensorSamples
        XCTAssertEqual(samples.count, expected, "every distinct reading is held exactly once")
        XCTAssertEqual(
            Set(samples.map(\.recordId)).count,
            expected,
            "and no racing append stored a reading twice"
        )
    }
}
