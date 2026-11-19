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
//  The rows are grouped by session (plan 156, D-15605): a readout asks for one
//  workout's readings every second, so a read of one session never touches
//  another workout's rows, and the newest row of each kind is cached beside
//  them on append instead of being found by a scan.
//

import Foundation

final class WatchSensorSampleLog {
    private let lock = NSLock()
    /// The rows grouped by the session that produced them, in arrival order
    /// within a session (D-15605): a one-second readout asks for one workout's
    /// readings, and visiting every workout's rows per tick made the readout's
    /// cost grow with everything ever stored.
    private var rowsBySession: [String: [WatchSensorSampleRecord]] = [:]
    /// The newest row of each kind per session, maintained on append. The
    /// greatest `sequence` wins; on an equal `sequence` the row already held
    /// keeps its place, which is the rule `newestSensorSamples()` applied when
    /// it scanned the whole log.
    private var newestBySession: [String: [String: WatchSensorSampleRecord]] = [:]
    /// How many rows of each kind a session holds, so a consumer can tell a new
    /// reading from a re-read without walking the rows (the pace window's cache
    /// key, S-15606).
    private var countsBySessionKind: [String: [String: Int]] = [:]
    /// The ids the log holds, so an append is a lookup rather than a scan of
    /// every reading ever stored (D-15604). Exact: `append`, `prune` and `fill`
    /// are its only writers.
    private var ids: Set<String> = []

    /// How many stored rows the per-session reads have returned so far — the
    /// count S-15606 bounds a tick's cost by, instead of wall time. Read-only
    /// and internal: no production behaviour depends on it.
    var rowsVisitedForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return rowsRead
    }

    private var rowsRead = 0

    /// One session's rows, in the order they arrived. The copy belongs to the
    /// caller, so scanning it needs no lock.
    func samples(forSession sessionId: String) -> [WatchSensorSampleRecord] {
        lock.lock()
        defer { lock.unlock() }
        let rows = rowsBySession[sessionId] ?? []
        rowsRead += rows.count
        return rows
    }

    /// One session's newest row per kind. The copy belongs to the caller.
    func newest(forSession sessionId: String) -> [String: WatchSensorSampleRecord] {
        lock.lock()
        defer { lock.unlock() }
        let newest = newestBySession[sessionId] ?? [:]
        rowsRead += newest.count
        return newest
    }

    /// How many of `kind` the session holds, without visiting a row.
    func count(forSession sessionId: String, kind: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return countsBySessionKind[sessionId]?[kind] ?? 0
    }

    /// Whether the log holds any reading for `sessionId`.
    func contains(sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !(rowsBySession[sessionId] ?? []).isEmpty
    }

    /// Adds `row` unless its id is already held. The store treats the same
    /// reading twice as one row; the list must agree, and doing the check here
    /// is what closes the read-then-write window a caller's own `contains`
    /// would leave open.
    func append(_ row: WatchSensorSampleRecord) {
        lock.lock()
        defer { lock.unlock() }
        guard !ids.contains(row.recordId) else { return }
        ids.insert(row.recordId)
        index(row)
    }

    func prune(where predicate: (WatchSensorSampleRecord) -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        rebuild(keeping: rowsBySession.values.flatMap { $0 }.filter { !predicate($0) })
    }

    /// Fills the log with what storage holds, as `restore` does.
    func fill(with stored: [WatchSensorSampleRecord]) {
        lock.lock()
        defer { lock.unlock() }
        rebuild(keeping: stored)
    }

    /// Adds `row` to the per-session views. The caller holds the lock.
    private func index(_ row: WatchSensorSampleRecord) {
        rowsBySession[row.sessionId, default: []].append(row)
        if let existing = newestBySession[row.sessionId]?[row.kind],
           existing.sequence >= row.sequence {
            // A tie keeps the row already held, as the whole-log reduction did.
        } else {
            newestBySession[row.sessionId, default: [:]][row.kind] = row
        }
        countsBySessionKind[row.sessionId, default: [:]][row.kind, default: 0] += 1
    }

    /// Replaces the log with `stored`, rebuilding every per-session view. The
    /// caller holds the lock.
    private func rebuild(keeping stored: [WatchSensorSampleRecord]) {
        ids = Set(stored.map(\.recordId))
        rowsBySession = [:]
        newestBySession = [:]
        countsBySessionKind = [:]
        for row in stored {
            index(row)
        }
    }
}
