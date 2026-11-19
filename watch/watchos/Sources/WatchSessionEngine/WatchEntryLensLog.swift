//
//  WatchEntryLensLog.swift
//  WatchSessionEngine
//
//  The entry projection lens and the acknowledged ids, behind a lock each.
//
//  Plan `docs/plans/2026-11-12-150-watch-crash-fix-plan/2026-11-12-150-watch-crash-fix-plan.md`,
//  task G. Both were plain state with the shape tasks A and F removed from the
//  row lists: written by the phone's delivery task (a `structure_change`'s lens
//  entries, a receipt's ids) and by `pruneConfirmed`, read by `entries` and the
//  effort-rating prompt on whatever thread the caller is on. `entries` folds the
//  lens in on every read, so a write landing half-way through it tore a `Set`
//  and crashed the watch inside `projectedEntries` (S-15032).
//
//  Every access takes the lock and only the dictionary or set operation is
//  inside it: a store append stays outside, so no lock is ever held across an
//  `await`.
//

import Foundation

/// The lens `entries` folds over the stored rows: what the phone corrected,
/// what it deleted, and which corrections replace a row outright.
final class WatchEntryLensLog {
    private let lock = NSLock()
    private var corrections: [String: [String: Any]] = [:]
    private var deleted: Set<String> = []
    private var replaced: Set<String> = []

    /// The lens as it stood when the lock was taken. One acquisition for all
    /// three parts, because a projection folded over a lens that moved between
    /// parts is the read that crashed.
    func snapshot() -> (
        corrections: [String: [String: Any]],
        deleted: Set<String>,
        replaced: Set<String>
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (corrections, deleted, replaced)
    }

    func correction(_ entryId: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return corrections[entryId]
    }

    var correctionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return corrections.count
    }

    /// The ids the phone deleted, in a stable order so a row carrying the lens
    /// is written the same way however the set was built.
    func hiddenIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return deleted.sorted()
    }

    /// Folds `correction` into `entryId`'s — a `correct_entry`, or a snapshot
    /// entry restating the row the wrist holds.
    func merge(_ entryId: String, with correction: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        corrections[entryId] = (corrections[entryId] ?? [:])
            .merging(correction) { _, corrected in corrected }
        replaced.remove(entryId)
    }

    /// `entryId` is a different entry wearing a reused id (D-113.3): the
    /// correction is the whole entry, not a fold into the held one.
    func restate(_ entryId: String, with correction: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        corrections[entryId] = correction
        replaced.insert(entryId)
    }

    /// Hides `entryId` — a `delete_entry`. A deleted entry's correction is gone
    /// with it, or the id would come back corrected when the phone shows it
    /// again.
    func hide(_ entryId: String) {
        lock.lock()
        defer { lock.unlock() }
        corrections.removeValue(forKey: entryId)
        replaced.remove(entryId)
        deleted.insert(entryId)
    }

    /// Shows `entryId` again — a snapshot entry outranks the tombstone (D-113.2).
    func show(_ entryId: String) {
        lock.lock()
        defer { lock.unlock() }
        deleted.remove(entryId)
    }

    /// Fills the lens with what storage holds, as `restore` does.
    func fill(hidden: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        deleted = hidden
    }

    /// The ids whose rows a prune dropped: their lens goes with them (D-52).
    func prune(_ entryIds: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        for entryId in entryIds {
            corrections.removeValue(forKey: entryId)
            replaced.remove(entryId)
            deleted.remove(entryId)
        }
    }
}

/// The observation ids the phone has acknowledged, kept across a prune so the
/// wrist still knows it holds one.
final class WatchAcknowledgementLog {
    private let lock = NSLock()
    private var ids: Set<String> = []

    func contains(_ entryId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(entryId)
    }

    func acknowledge(_ entryIds: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        ids.formUnion(entryIds)
    }

    /// Fills the log with what storage holds, as `restore` does.
    func fill(with acknowledged: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        ids = acknowledged
    }
}
