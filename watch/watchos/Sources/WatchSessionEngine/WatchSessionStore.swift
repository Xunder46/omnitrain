//
//  WatchSessionStore.swift
//  WatchSessionEngine
//
//  The storage contract the watch session engine depends on. Mirrors
//  `lib/watch/session/watch_session_store.dart`.
//
//  Append-only by construction (PROTOCOL.md, authority rule 1): a store offers
//  no update, no delete and no remove. `append` is the only way anything enters
//  and `pruneConfirmed` the only way anything leaves — and it may only drop
//  what the phone has already acknowledged.
//
//  `WatchSessionEngineTests` (S-004) fails the build if a mutating method is
//  declared anywhere in this module or if the engine reaches for a store method
//  outside this set.
//

import Foundation

/// Everything the store holds, in append order.
public struct WatchStoreContents {
    public let sessions: [WatchSessionRecord]
    public let observations: [WatchObservationRecord]
    public let timers: [WatchTimerRecord]
    public let confirmations: [WatchConfirmationRecord]

    /// The reference data the phone sent down, oldest first. The newest row is
    /// the catalog that applies.
    public let routineCatalogs: [WatchRoutineCatalogRecord]

    public init(
        sessions: [WatchSessionRecord] = [],
        observations: [WatchObservationRecord] = [],
        timers: [WatchTimerRecord] = [],
        confirmations: [WatchConfirmationRecord] = [],
        routineCatalogs: [WatchRoutineCatalogRecord] = []
    ) {
        self.sessions = sessions
        self.observations = observations
        self.timers = timers
        self.confirmations = confirmations
        self.routineCatalogs = routineCatalogs
    }

    public var isEmpty: Bool {
        sessions.isEmpty && observations.isEmpty && timers.isEmpty
            && confirmations.isEmpty && routineCatalogs.isEmpty
    }
}

public protocol WatchSessionStore {
    /// Writes `record`, assigning its append-order sequence. Appending a record
    /// whose id is already stored is a no-op that returns the stored row.
    func append(_ record: StoredWatchRecord) async -> StoredWatchRecord

    /// Every row, in append order, with confirmations folded into observations.
    func readAll() async -> WatchStoreContents

    /// Drops confirmed observations, returning the record ids that were
    /// dropped. Unconfirmed observations are retained indefinitely.
    func pruneConfirmed() async -> [String]
}

/// Folds confirmations into observations as their `confirmedAt` receipt.
///
/// Read-time derivation rather than a write: the observation row is never
/// rewritten, and a confirmation is itself just another append.
public func applyConfirmations(
    _ observations: [WatchObservationRecord],
    _ confirmations: [WatchConfirmationRecord]
) -> [WatchObservationRecord] {
    guard !confirmations.isEmpty else { return observations }

    var receipts: [String: Date] = [:]
    for confirmation in confirmations {
        for observationId in confirmation.observationIds {
            if let existing = receipts[observationId], confirmation.confirmedAt <= existing {
                continue
            }
            receipts[observationId] = confirmation.confirmedAt
        }
    }

    return observations.map { observation in
        guard let confirmedAt = receipts[observation.recordId] else {
            return observation
        }
        return observation.withConfirmation(confirmedAt)
    }
}

/// In-memory store for tests and desktop runs: the same append-only contract
/// without touching a disk.
public final class InMemoryWatchSessionStore: WatchSessionStore {
    private var rows: [StoredWatchRecord] = []
    private var sequence = 0

    public init() {}

    public func append(_ record: StoredWatchRecord) async -> StoredWatchRecord {
        for row in rows
        where row.recordId == record.recordId && row.recordType == record.recordType {
            return row
        }

        sequence += 1
        let stored = record.withSequence(sequence)
        rows.append(stored)
        return stored
    }

    public func readAll() async -> WatchStoreContents {
        var sessions: [WatchSessionRecord] = []
        var observations: [WatchObservationRecord] = []
        var timers: [WatchTimerRecord] = []
        var confirmations: [WatchConfirmationRecord] = []
        var routineCatalogs: [WatchRoutineCatalogRecord] = []

        for row in rows {
            switch row {
            case .session(let value): sessions.append(value)
            case .observation(let value): observations.append(value)
            case .timer(let value): timers.append(value)
            case .confirmation(let value): confirmations.append(value)
            case .routineCatalog(let value): routineCatalogs.append(value)
            }
        }

        return WatchStoreContents(
            sessions: sessions,
            observations: applyConfirmations(observations, confirmations),
            timers: timers,
            confirmations: confirmations,
            routineCatalogs: routineCatalogs
        )
    }

    public func pruneConfirmed() async -> [String] {
        let contents = await readAll()
        let confirmed = contents.observations
            .filter { $0.confirmedAt != nil }
            .map(\.recordId)
        let dropped = Set(confirmed)
        rows.removeAll { row in
            if case .observation(let value) = row { return dropped.contains(value.recordId) }
            return false
        }
        return confirmed
    }
}
