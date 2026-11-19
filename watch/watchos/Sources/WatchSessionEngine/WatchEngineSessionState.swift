//
//  WatchEngineSessionState.swift
//  WatchSessionEngine
//
//  The engine's session mirror, its row list, the structure changes it has
//  applied and its snapshot watermark, behind one lock.
//
//  Plan `docs/plans/2026-11-14-162-engine-state-lock-box-plan/2026-11-14-162-engine-state-lock-box-plan.md`,
//  D-16202. `current` and the row list were the two values investigation 159
//  classified as crash-capable by construction: written by the gated writers and
//  by `restore()`, read by every screen and prompt on whatever thread the caller
//  runs on. A torn copy damages refcounts, which TSan does not instrument —
//  three instrumented attempts produced no report, which is not evidence of
//  safety.
//
//  Every access takes the lock and only the memory operation is inside it: no
//  accessor awaits, so the lock is never held across an `await`. Lock order is
//  `mutex -> state lock`, never the reverse (D-16204): the gated writers take
//  this lock only inside synchronous spans, and `restore()` takes only this one.
//

import Foundation

/// The session the watch is on, the rows it holds of every session it has
/// seen — the row list retention reads — the structure changes it has applied
/// and the `sentAt` of the newest snapshot it applied.
final class WatchEngineSessionState {
    private let lock = NSLock()
    private var current: WatchSessionRecord?
    private var heldRows: [WatchSessionRecord] = []
    private var appliedChangeIds: Set<String> = []
    private var newestSnapshotAt: Date?

    /// The session the watch is on, as it stood when the lock was taken.
    func record() -> WatchSessionRecord? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Adds `row` unless its id is already held, and makes it the session the
    /// watch is on — one acquisition, so no reader sees the list grown without
    /// the row that became current.
    ///
    /// A row arrives on whatever thread its writer runs on, and the caller's own
    /// `contains` would leave a read-then-write window two writers can both pass;
    /// the store keeps one row per id and the list must agree.
    @discardableResult
    func mirror(_ row: WatchSessionRecord) -> WatchSessionRecord {
        lock.lock()
        defer { lock.unlock() }
        if !heldRows.contains(where: { $0.recordId == row.recordId }) {
            heldRows.append(row)
        }
        current = row
        return row
    }

    /// The rows as they were when the lock was taken. The copy belongs to the
    /// caller, so scanning it needs no lock.
    func rows() -> [WatchSessionRecord] {
        lock.lock()
        defer { lock.unlock() }
        return heldRows
    }

    /// How many rows the list holds, without copying it.
    var rowCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return heldRows.count
    }

    /// Whether `changeId` is one this watch has not applied yet, recording it as
    /// applied — one acquisition, so two deliveries of the same change cannot
    /// both pass a `contains`-then-`insert` window.
    func firstApply(changeId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return appliedChangeIds.insert(changeId).inserted
    }

    /// The `sentAt` of the newest snapshot applied, or nil when none has been.
    func snapshotWatermark() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return newestSnapshotAt
    }

    /// Raises the snapshot watermark to `sentAt`, never lowering it: a newer
    /// snapshot that landed between this frame's gate and this call has already
    /// moved it on, and an older frame may not move it back.
    func advanceSnapshot(sentAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        newestSnapshotAt = max(newestSnapshotAt ?? sentAt, sentAt)
    }

    /// Fills the list and the session the watch is on with what storage holds, as
    /// `restore` does — one acquisition, so a reader can never see half a
    /// restore.
    ///
    /// `restore()` deliberately takes no mutex (D-16203): a writer's row appended
    /// between its `readAll` and this call is clobbered by the fill, exactly as
    /// the plain assignment it replaces clobbered it.
    func fill(
        rows: [WatchSessionRecord],
        current: WatchSessionRecord?,
        appliedChangeIds: Set<String>,
        newestSnapshotAt: Date?
    ) {
        lock.lock()
        defer { lock.unlock() }
        heldRows = rows
        self.current = current
        self.appliedChangeIds = appliedChangeIds
        self.newestSnapshotAt = newestSnapshotAt
    }
}
