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
    /// The ids `rows` holds, so an append is a lookup rather than a scan of
    /// every entry ever stored (D-15604). Exact: `append`, `prune` and `fill`
    /// are its only writers; `map` keeps each row's id.
    private var ids: Set<String> = []
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
        guard !ids.contains(row.recordId) else { return }
        rows.append(row)
        ids.insert(row.recordId)
    }

    func contains(where predicate: (WatchObservationRecord) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rows.contains(where: predicate)
    }

    /// The rows whose ids are in `ids` are gone — the store dropped them.
    func prune(_ prunedIds: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        rows.removeAll { prunedIds.contains($0.recordId) }
        ids = Set(rows.map(\.recordId))
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
        ids = Set(stored.map(\.recordId))
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
    /// The ids `rows` holds, so an append is a lookup rather than a scan
    /// (D-15604).
    private var ids: Set<String> = []

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
        guard !ids.contains(row.recordId) else { return }
        rows.append(row)
        ids.insert(row.recordId)
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
        ids = Set(stored.map(\.recordId))
    }
}

/// One in-flight write of an entry. A second copy waits until the first copy's
/// row is in `WatchObservationLog`, then re-reads it instead of storing again
/// (F-7, D-14606).
///
/// The flag and the waiter list live behind `lock` (D-15401): a waiter arriving
/// while the claim is being finished must either see `finished` or be in
/// `waiters` before the finish drains it, or it is never resumed. The lock is
/// never held across an `await`, and the resume happens after it is released.
final class EntryClaim {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var finished = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func finish() {
        lock.lock()
        finished = true
        let resuming = waiters
        waiters.removeAll()
        lock.unlock()
        for waiter in resuming { waiter.resume() }
    }
}
