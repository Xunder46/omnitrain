//
//  WatchSessionStore.swift
//  WatchSessionEngine
//
//  The storage contract the watch session engine depends on. Mirrors
//  `lib/watch/session/watch_session_store.dart`.
//
//  Append-only by construction (PROTOCOL.md, authority rule 1): a store offers
//  no update, no delete and no remove. `append` is the only way anything enters,
//  and there are exactly six ways anything leaves it — all of them prunes,
//  each gated on nothing left to lose: `pruneConfirmed` drops observations the
//  phone has acknowledged, `pruneSensorSamples` drops the raw sensor log of a
//  session the phone has recorded in full, `pruneExerciseBatches` drops the
//  stored exercise batches of every list version but the one that just became
//  active, `pruneBests` drops the bests frames the wrist has replaced with the
//  copy it holds as newest, `pruneWater` does the same for the water frames,
//  and `pruneWaterTaps` drops the water taps the phone has acknowledged that
//  are too old for any count to read.
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

    /// The readings the platform sensors produced, oldest first. A reading has
    /// no receipt of its own — the phone has no field for one — so what gates it
    /// is its session: `pruneSensorSamples` drops a session's readings once the
    /// session is over and the phone holds what was computed from them, or once
    /// the session is too old to still be owed (D-15602).
    public let sensorSamples: [WatchSensorSampleRecord]

    /// The reference data the phone sent down, oldest first. The newest row is
    /// the catalog that applies.
    public let routineCatalogs: [WatchRoutineCatalogRecord]

    /// The planned sessions the phone sent down, oldest first. The newest row
    /// is the list that applies (plan 129).
    public let plannedCatalogs: [WatchPlannedCatalogRecord]

    /// The food lists the phone sent down, oldest first. The newest row is the
    /// list that applies.
    public let foodCatalogs: [WatchFoodCatalogRecord]

    /// The phone's preferences as each `preferences_down` brought them, oldest
    /// first. The newest by `generatedAt` is the one that applies.
    public let preferences: [WatchPreferencesRecord]

    /// The effort-rating prompts the wrist's End has owed, oldest first. A
    /// session's prompt is answered by its rating, never by another row.
    public let ratingPrompts: [WatchRatingPromptRecord]

    /// The exercise-list batches the phone sent down, oldest first, across
    /// every version. A version is complete once its batches are all here and
    /// all but the active version's are then pruned (D-3813, D-3814).
    public let exerciseBatches: [WatchExerciseBatchRecord]

    /// The standing bests each `bests_down` brought, oldest first. The newest
    /// by `generatedAt` is the copy that applies, and the others are pruned
    /// once it is written (D-11, D-17).
    public let bests: [WatchBestsRecord]

    /// The water counts each `water_down` brought, oldest first. The newest by
    /// `generatedAt` is the frame the wrist holds, and the others are pruned
    /// once it is written (plan 95 D-23, D-24).
    public let water: [WatchWaterRecord]

    public init(
        sessions: [WatchSessionRecord] = [],
        observations: [WatchObservationRecord] = [],
        timers: [WatchTimerRecord] = [],
        confirmations: [WatchConfirmationRecord] = [],
        sensorSamples: [WatchSensorSampleRecord] = [],
        routineCatalogs: [WatchRoutineCatalogRecord] = [],
        plannedCatalogs: [WatchPlannedCatalogRecord] = [],
        foodCatalogs: [WatchFoodCatalogRecord] = [],
        preferences: [WatchPreferencesRecord] = [],
        ratingPrompts: [WatchRatingPromptRecord] = [],
        exerciseBatches: [WatchExerciseBatchRecord] = [],
        bests: [WatchBestsRecord] = [],
        water: [WatchWaterRecord] = []
    ) {
        self.sessions = sessions
        self.observations = observations
        self.timers = timers
        self.confirmations = confirmations
        self.sensorSamples = sensorSamples
        self.routineCatalogs = routineCatalogs
        self.plannedCatalogs = plannedCatalogs
        self.foodCatalogs = foodCatalogs
        self.preferences = preferences
        self.ratingPrompts = ratingPrompts
        self.exerciseBatches = exerciseBatches
        self.bests = bests
        self.water = water
    }

    public var isEmpty: Bool {
        sessions.isEmpty && observations.isEmpty && timers.isEmpty
            && confirmations.isEmpty && sensorSamples.isEmpty
            && routineCatalogs.isEmpty && plannedCatalogs.isEmpty && foodCatalogs.isEmpty
            && preferences.isEmpty && ratingPrompts.isEmpty
            && exerciseBatches.isEmpty && bests.isEmpty && water.isEmpty
    }

    /// The same contents with `samples` as the readings — what merging the main
    /// file's rows with the side files' rows builds. Internal on purpose: it is a
    /// value helper, not store API (the S-004 scan pins the store's public
    /// surface).
    internal func withSensorSamples(_ samples: [WatchSensorSampleRecord]) -> WatchStoreContents {
        WatchStoreContents(
            sessions: sessions,
            observations: observations,
            timers: timers,
            confirmations: confirmations,
            sensorSamples: samples,
            routineCatalogs: routineCatalogs,
            plannedCatalogs: plannedCatalogs,
            foodCatalogs: foodCatalogs,
            preferences: preferences,
            ratingPrompts: ratingPrompts,
            exerciseBatches: exerciseBatches,
            bests: bests,
            water: water
        )
    }
}


public protocol WatchSessionStore {
    /// Writes `record`, assigning its append-order sequence. Appending a record
    /// whose id is already stored is a no-op that returns the stored row.
    func append(_ record: StoredWatchRecord) async -> StoredWatchRecord

    /// Every row, in append order, with confirmations folded into observations.
    ///
    /// Everything stored, including the readings that live in a terminal
    /// session's own side file: `readAll()` is the whole store, not the launch's
    /// part of it.
    func readAll() async -> WatchStoreContents

    /// Everything except the raw readings of a terminal session (D-17301) — the
    /// set a launch decodes.
    ///
    /// A launch needs the readings of the session that is still running: they
    /// are what the live readout and the energy chain read after a kill. An
    /// ended session's readings have no reader at all, so they live in that
    /// session's side file (`watch-samples-<sessionId>.jsonl`) and are not part
    /// of any launch. A store with nothing moved answers this exactly as
    /// `readAll()` does, so this is a narrowing of the same store, never a
    /// different one.
    func readLaunch() async -> WatchStoreContents

    /// Moves `sessionId`'s raw readings out of the launch set, returning the
    /// record ids that moved.
    ///
    /// Called when the session's newest row lands with a terminal status
    /// (D-17305): from then on nothing reads those readings, so they go to the
    /// session's side file and out of the main file. A call for a session with
    /// nothing inline writes nothing and returns nothing (D-15603, D-17303);
    /// `readAll()` still answers every one of them until a prune deletes them.
    func archiveSensorSamples(_ sessionId: String) async -> [String]

    /// Drops confirmed observations, returning the record ids that were
    /// dropped. Unconfirmed observations are retained indefinitely.
    func pruneConfirmed() async -> [String]

    /// Drops the sensor samples of `sessionIds`, returning the record ids that
    /// were dropped.
    ///
    /// The gate is not a receipt — the phone never receives a raw reading — but
    /// the session: the caller only names sessions that are over and whose
    /// entries the phone has recorded in full. A session that is still running
    /// keeps every reading it has taken, which is what makes the live readout
    /// kill-safe.
    func pruneSensorSamples(_ sessionIds: [String]) async -> [String]

    /// Drops every exercise-batch row whose version is not `keepingVersion`,
    /// returning the record ids that were dropped.
    ///
    /// The gate is the list, not the phone's receipt: the caller names a version
    /// only once every batch of it is stored, i.e. once a complete list is
    /// active, and the batches of every other version are then the ones nothing
    /// reads any more. No other record kind is touched — a routine catalog row
    /// stays where it is.
    func pruneExerciseBatches(keepingVersion: String) async -> [String]

    /// Drops every `bests` row whose record id is not `keepingRecordId`,
    /// returning the record ids that were dropped.
    ///
    /// The gate is the frame, not the phone's receipt: the caller names the one
    /// copy it holds as newest, having just written it, and every other frame
    /// is a copy nothing reads any more (D-11, D-17). A tie in `generatedAt`
    /// still leaves exactly one row, because the caller names the copy it keeps.
    /// A record id that is not stored drops nothing — there is then no newest
    /// copy to keep. No other record kind is touched.
    func pruneBests(keepingRecordId: String) async -> [String]

    /// Drops every `water` row whose record id is not `keepingRecordId`,
    /// returning the record ids that were dropped.
    ///
    /// The gate is `pruneBests`' own: the caller names the one frame it holds
    /// as newest, having just written it, and every other water frame is a
    /// copy nothing reads any more (plan 95 D-23). A record id that is not
    /// stored drops nothing, and a prune that drops nothing writes nothing.
    /// No other record kind is touched — the wrist's taps are observations and
    /// leave only through `pruneWaterTaps` (plan 96 D-43).
    func pruneWater(keepingRecordId: String) async -> [String]

    /// Drops every `water_glass` observation a receipt names whose `loggedAt`
    /// is strictly earlier than `cutoff`, returning the record ids that were
    /// dropped.
    ///
    /// The gate is the receipt plus the age: the phone holds the tap, and the
    /// caller's cutoff lies before the start of any local today, so no count
    /// can still read it (plan 96 D-43, D-44). An unconfirmed tap, a tap whose
    /// `loggedAt` cannot be read, every other kind of row and the confirmation
    /// rows themselves stay. A prune that drops nothing writes nothing.
    func pruneWaterTaps(loggedBefore cutoff: Date) async -> [String]
}

/// The stores that stand behind `WatchSessionStore` without owning its new
/// members — test doubles that forward to a real store — answer them from the
/// members they already have. The two production stores implement both.
public extension WatchSessionStore {
    func readLaunch() async -> WatchStoreContents {
        await readAll()
    }

    func archiveSensorSamples(_ sessionId: String) async -> [String] {
        []
    }
}

/// The session ids whose raw readings are outside the launch set (D-17301): a
/// session whose newest row is terminal — `completed` or `abandoned`. A session
/// with no row is not in this set: it cannot be classified, and unclassified
/// readings are the recovery case.
func settledSensorSessionIds(in rows: [StoredWatchRecord]) -> Set<String> {
    var newest: [String: WatchSessionRecord] = [:]
    for row in rows {
        guard case .session(let value) = row else { continue }
        if let existing = newest[value.sessionId], existing.sequence >= value.sequence {
            continue
        }
        newest[value.sessionId] = value
    }
    return Set(
        newest.values
            .filter {
                $0.status == WatchSessionStatus.completed
                    || $0.status == WatchSessionStatus.abandoned
            }
            .map(\.sessionId)
    )
}

/// `rows`' sample rows that stay in the launch set: every reading except those
/// of `settledSensorSessionIds`. One rule for both stores, so the twin cannot
/// drift from the file store it stands in for (D-17307).
func launchSensorSampleRows(_ rows: [StoredWatchRecord]) -> [StoredWatchRecord] {
    let settled = settledSensorSessionIds(in: rows)
    return rows.filter { row in
        guard case .sensorSample(let value) = row else { return false }
        return !settled.contains(value.sessionId)
    }
}

/// `contents` without the readings a launch does not need (D-17301): the raw
/// readings of every session whose newest row is terminal.
func launchReadingsOnly(_ contents: WatchStoreContents) -> WatchStoreContents {
    let settled = settledSensorSessionIds(in: contents.sessions.map { .session($0) })
    guard !settled.isEmpty else { return contents }

    return contents.withSensorSamples(
        contents.sensorSamples.filter { !settled.contains($0.sessionId) }
    )
}

/// The record ids `pruneWaterTaps(loggedBefore:)` drops from `observations`
/// (confirmations already folded in), in store order: water taps with a
/// receipt and a readable `loggedAt` strictly earlier than `cutoff`. One rule
/// for both stores, so they cannot drift apart.
func confirmedWaterTapIds(
    in observations: [WatchObservationRecord],
    loggedBefore cutoff: Date
) -> [String] {
    observations.compactMap { observation -> String? in
        guard observation.kind == WatchObservationKind.waterGlass,
              observation.confirmedAt != nil,
              let loggedAt = try? parseUtcIso(observation.payload["loggedAt"]),
              loggedAt < cutoff
        else { return nil }
        return observation.recordId
    }
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

    /// The in-memory twin of the file store's lock. A prune the consumer asks
    /// for off its own turn (D-15601) runs beside the caller's next append, and
    /// the file store has always been safe against that; this one has to be too,
    /// or the twin would disagree with the store it stands in for.
    private let lock = NSLock()

    public init() {}

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func append(_ record: StoredWatchRecord) async -> StoredWatchRecord {
        locked { appendLocked(record) }
    }

    private func appendLocked(_ record: StoredWatchRecord) -> StoredWatchRecord {
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
        locked { contentsLocked() }
    }

    public func readLaunch() async -> WatchStoreContents {
        locked { launchReadingsOnly(contentsLocked()) }
    }

    public func archiveSensorSamples(_ sessionId: String) async -> [String] {
        locked { sensorSampleIdsLocked(sessionId) }
    }

    /// Memory keeps a moved session's readings — the on-watch end summary reads
    /// them in the same process — while `readLaunch()` already leaves them out
    /// through the shared rule (A-17303). So the move is a read of their ids.
    private func sensorSampleIdsLocked(_ sessionId: String) -> [String] {
        rows.compactMap { row -> String? in
            guard case .sensorSample(let value) = row, value.sessionId == sessionId else {
                return nil
            }
            return value.recordId
        }
    }

    private func contentsLocked() -> WatchStoreContents {
        var sessions: [WatchSessionRecord] = []
        var observations: [WatchObservationRecord] = []
        var timers: [WatchTimerRecord] = []
        var confirmations: [WatchConfirmationRecord] = []
        var sensorSamples: [WatchSensorSampleRecord] = []
        var routineCatalogs: [WatchRoutineCatalogRecord] = []
        var plannedCatalogs: [WatchPlannedCatalogRecord] = []
        var foodCatalogs: [WatchFoodCatalogRecord] = []
        var preferences: [WatchPreferencesRecord] = []
        var ratingPrompts: [WatchRatingPromptRecord] = []
        var exerciseBatches: [WatchExerciseBatchRecord] = []
        var bests: [WatchBestsRecord] = []
        var water: [WatchWaterRecord] = []

        for row in rows {
            switch row {
            case .session(let value): sessions.append(value)
            case .observation(let value): observations.append(value)
            case .timer(let value): timers.append(value)
            case .sensorSample(let value): sensorSamples.append(value)
            case .confirmation(let value): confirmations.append(value)
            case .routineCatalog(let value): routineCatalogs.append(value)
            case .plannedCatalog(let value): plannedCatalogs.append(value)
            case .foodCatalog(let value): foodCatalogs.append(value)
            case .preferences(let value): preferences.append(value)
            case .ratingPrompt(let value): ratingPrompts.append(value)
            case .exerciseBatch(let value): exerciseBatches.append(value)
            case .bests(let value): bests.append(value)
            case .water(let value): water.append(value)
            }
        }

        return WatchStoreContents(
            sessions: sessions,
            observations: applyConfirmations(observations, confirmations),
            timers: timers,
            confirmations: confirmations,
            sensorSamples: sensorSamples,
            routineCatalogs: routineCatalogs,
            plannedCatalogs: plannedCatalogs,
            foodCatalogs: foodCatalogs,
            preferences: preferences,
            ratingPrompts: ratingPrompts,
            exerciseBatches: exerciseBatches,
            bests: bests,
            water: water
        )
    }

    public func pruneConfirmed() async -> [String] {
        locked { pruneConfirmedLocked() }
    }

    private func pruneConfirmedLocked() -> [String] {
        let contents = contentsLocked()
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

    public func pruneSensorSamples(_ sessionIds: [String]) async -> [String] {
        locked { pruneSensorSamplesLocked(sessionIds) }
    }

    private func pruneSensorSamplesLocked(_ sessionIds: [String]) -> [String] {
        let sessions = Set(sessionIds)
        guard !sessions.isEmpty else { return [] }

        let dropped = rows.compactMap { row -> String? in
            if case .sensorSample(let value) = row,
               sessions.contains(value.sessionId) { return value.recordId }
            return nil
        }
        rows.removeAll { row in
            if case .sensorSample(let value) = row {
                return sessions.contains(value.sessionId)
            }
            return false
        }
        return dropped
    }

    public func pruneExerciseBatches(keepingVersion: String) async -> [String] {
        locked { pruneExerciseBatchesLocked(keepingVersion) }
    }

    private func pruneExerciseBatchesLocked(_ keepingVersion: String) -> [String] {
        let dropped = rows.compactMap { row -> String? in
            if case .exerciseBatch(let value) = row,
               value.catalogVersion != keepingVersion { return value.recordId }
            return nil
        }
        let keep = Set(dropped)
        rows.removeAll { row in
            if case .exerciseBatch(let value) = row {
                return keep.contains(value.recordId)
            }
            return false
        }
        return dropped
    }

    public func pruneBests(keepingRecordId: String) async -> [String] {
        locked { pruneBestsLocked(keepingRecordId) }
    }

    private func pruneBestsLocked(_ keepingRecordId: String) -> [String] {
        let stored = rows.contains { row in
            if case .bests(let value) = row { return value.recordId == keepingRecordId }
            return false
        }
        guard stored else { return [] }

        let dropped = rows.compactMap { row -> String? in
            if case .bests(let value) = row,
               value.recordId != keepingRecordId { return value.recordId }
            return nil
        }
        let drop = Set(dropped)
        rows.removeAll { row in
            if case .bests(let value) = row {
                return drop.contains(value.recordId)
            }
            return false
        }
        return dropped
    }

    public func pruneWater(keepingRecordId: String) async -> [String] {
        locked { pruneWaterLocked(keepingRecordId) }
    }

    private func pruneWaterLocked(_ keepingRecordId: String) -> [String] {
        let stored = rows.contains { row in
            if case .water(let value) = row { return value.recordId == keepingRecordId }
            return false
        }
        guard stored else { return [] }

        let dropped = rows.compactMap { row -> String? in
            if case .water(let value) = row,
               value.recordId != keepingRecordId { return value.recordId }
            return nil
        }
        let drop = Set(dropped)
        rows.removeAll { row in
            if case .water(let value) = row {
                return drop.contains(value.recordId)
            }
            return false
        }
        return dropped
    }

    public func pruneWaterTaps(loggedBefore cutoff: Date) async -> [String] {
        locked { pruneWaterTapsLocked(cutoff) }
    }

    private func pruneWaterTapsLocked(_ cutoff: Date) -> [String] {
        let dropped = confirmedWaterTapIds(in: contentsLocked().observations, loggedBefore: cutoff)
        let drop = Set(dropped)
        rows.removeAll { row in
            if case .observation(let value) = row { return drop.contains(value.recordId) }
            return false
        }
        return dropped
    }
}
