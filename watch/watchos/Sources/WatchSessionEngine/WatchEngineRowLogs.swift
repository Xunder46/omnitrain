//
//  WatchEngineRowLogs.swift
//  WatchSessionEngine
//
//  The engine's stored observation and timer rows, behind a lock each.
//
//  Plan `docs/plans/2026-11-12-150-watch-crash-fix-plan/2026-11-12-150-watch-crash-fix-plan.md`,
//  task F. These lists had the shape task A fixed in `WatchSensorSampleLog`: a
//  row arrives on whatever thread its writer runs on — the phone's delivery
//  task, a sensor stream, a logging tap — while a screen reads the list on the
//  main thread. A plain array grown under that reader traps, which is the
//  SIGABRT task A already removed from the sensor log.
//
//  Every access takes the lock and only the array operation is inside it: the
//  store append stays outside, so a slow write never stalls a redraw and no
//  lock is ever held across an `await`.
//

import Foundation

/// The stored observations, with the claims of the writes still in flight.
final class WatchObservationLog {
    private let lock = NSLock()
    private var rows: [WatchObservationRecord] = []
    private var inflight: [String: EntryClaim] = [:]

    /// The rows as they were when the lock was taken. The copy belongs to the
    /// caller, so filtering or scanning it needs no lock.
    func snapshot() -> [WatchObservationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return rows.count
    }

    /// Adds `row` unless its id is already held. The store keeps one row per id;
    /// the list must agree, and doing the check here is what closes the
    /// read-then-write window a caller's own `contains` would leave open.
    func append(_ row: WatchObservationRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard !rows.contains(where: { $0.recordId == row.recordId }) else { return }
        rows.append(row)
    }

    func contains(where predicate: (WatchObservationRecord) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rows.contains(where: predicate)
    }

    /// The rows whose ids are in `ids` are gone — the store dropped them.
    func prune(_ ids: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        rows.removeAll { ids.contains($0.recordId) }
    }

    /// Applies `transform` to every row, as a receipt's stamp does.
    func map(_ transform: (WatchObservationRecord) -> WatchObservationRecord) {
        lock.lock()
        defer { lock.unlock() }
        rows = rows.map(transform)
    }

    /// Fills the log with what storage holds, as `restore` does.
    func fill(with stored: [WatchObservationRecord]) {
        lock.lock()
        defer { lock.unlock() }
        rows = stored
    }

    /// Claims `recordId` for one writer. Nil means this writer now owns it and
    /// must `finishClaim` after storing; a claim means another writer holds the
    /// id and this one waits for its row instead of storing a second one (F-7).
    ///
    /// The claim and the check are one operation under the lock: a burst
    /// delivered without awaiting each frame used to hand two copies of an entry
    /// the same "not held" answer, and both stored it.
    func claim(_ recordId: String) -> EntryClaim? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inflight[recordId] { return existing }
        inflight[recordId] = EntryClaim()
        return nil
    }

    /// Ends the claim and wakes the writers waiting on it.
    func finishClaim(_ recordId: String) {
        lock.lock()
        let claim = inflight.removeValue(forKey: recordId)
        lock.unlock()
        claim?.finish()
    }
}

/// The stored timer rows.
final class WatchTimerLog {
    private let lock = NSLock()
    private var rows: [WatchTimerRecord] = []

    func snapshot() -> [WatchTimerRecord] {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }

    /// Adds `row` unless its id is already held — the store keeps one row per
    /// id, and two writers can reach the list with the same one.
    func append(_ row: WatchTimerRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard !rows.contains(where: { $0.recordId == row.recordId }) else { return }
        rows.append(row)
    }

    func contains(where predicate: (WatchTimerRecord) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rows.contains(where: predicate)
    }

    /// Fills the log with what storage holds, as `restore` does.
    func fill(with stored: [WatchTimerRecord]) {
        lock.lock()
        defer { lock.unlock() }
        rows = stored
    }
}

/// One in-flight write of an entry. A second copy waits until the first copy's
/// row is in `WatchObservationLog`, then re-reads it instead of storing again
/// (F-7, D-14606).
final class EntryClaim {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var finished = false

    func wait() async {
        if finished { return }
        await withCheckedContinuation { continuation in
            if finished {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func finish() {
        finished = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
