//
//  WatchSensorSampleLog.swift
//  WatchSessionEngine
//
//  The engine's raw sensor readings, behind one lock.
//
//  Plan `docs/plans/2026-11-12-150-watch-crash-fix-plan/2026-11-12-150-watch-crash-fix-plan.md`,
//  task A. A reading arrives on whatever thread the platform delivered it on —
//  the GPS stream, the heart-rate stream — while the logging screen reads the
//  list on the main thread to redraw its distance tile. A plain array grows
//  under that reader and traps (`Array._consumeAndCreateNew`, SIGABRT on the
//  owner's 2026-11-12 outdoor walk).
//
//  Every access therefore takes the lock, and only the array operation is
//  inside it: the store append stays outside, so a slow write never stalls a
//  redraw, and no lock is ever held across an `await`.
//

import Foundation

final class WatchSensorSampleLog {
    private let lock = NSLock()
    private var rows: [WatchSensorSampleRecord] = []

    /// The rows as they were when the lock was taken. The copy belongs to the
    /// caller, so filtering or scanning it needs no lock.
    func snapshot() -> [WatchSensorSampleRecord] {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }

    /// Adds `row` unless its id is already held. The store treats the same
    /// reading twice as one row; the list must agree, and doing the check here
    /// is what closes the read-then-write window a caller's own `contains`
    /// would leave open.
    func append(_ row: WatchSensorSampleRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard !rows.contains(where: { $0.recordId == row.recordId }) else { return }
        rows.append(row)
    }

    func contains(where predicate: (WatchSensorSampleRecord) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rows.contains(where: predicate)
    }

    func prune(where predicate: (WatchSensorSampleRecord) -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        rows.removeAll(where: predicate)
    }

    /// Fills the log with what storage holds, as `restore` does.
    func fill(with stored: [WatchSensorSampleRecord]) {
        lock.lock()
        defer { lock.unlock() }
        rows = stored
    }
}
