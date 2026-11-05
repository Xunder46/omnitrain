//
//  WatchPersonalBests.swift
//  WatchSessionEngine
//
//  The phone's standing bests, as `bests_down` last brought them, and the
//  verdict a set logged on the wrist gets against them.
//
//  Plan: `docs/plans/2026-10-27-87b-wrist-new-pr-detection-and-banner-plan/`,
//  D-1 to D-5, D-11, D-15 and D-16. 87a put the numbers on the wrist; this is
//  the half that decides whether a set beat them.
//
//  Two things are compared, and only their larger matters (D-2):
//
//  * the frame — the phone's copy of each exercise's standing best, the newest
//    `generatedAt` winning, a tie going to the copy received later (D-5); and
//  * the wrist's own best — the best of the sets the wrist itself logged, which
//    the frame may not carry yet. It is the dedup device: the same set logged
//    twice, before or after a relaunch, never beats itself (acceptance 3).
//
//  `max` is idempotent, so an own set the frame already counts changes nothing
//  and no clearing logic exists. A wrist that never received a frame gives no
//  verdict at all (D-3), so its very first sets are silent rather than
//  celebrated.
//
//  Cost is bounded by the plan's budget: the arriving frame is parsed once when
//  it arrives (D-10), memory holds at most the frame's 300 entries plus one
//  entry per exercise the wrist logged (D-12), and a frame whose entries the
//  wrist already holds writes nothing (D-11). Nothing here reads history per
//  log: detection is two dictionary lookups and one multiplication.
//

import Foundation

/// The owner of the phone's standing bests on the wrist.
///
/// The class is reached from the main-actor log path and from the async
/// `receive` path and is not actor-isolated, so its in-memory state is guarded
/// by a lock. Nothing awaits while the lock is held: the verdict and the fold
/// are computed in one critical section, the store is written outside it.
public final class WatchPersonalBests {
    private let store: WatchSessionStore
    private let validator: SyncProtocolValidator?
    private let clock: () -> Date

    private let stateLock = NSLock()

    /// The frame the wrist holds, parsed once when it arrived, or nil when no
    /// frame ever did (D-3, D-10). A held `bests: []` frame is an empty
    /// dictionary, not nil: then every first set of an exercise is a record.
    private var frame: [String: (e1rmKg: Double, repsBest: Int)]?

    /// When the held frame was generated. The frame's own `generatedAt`, not
    /// the row's `recordedAt`: an older copy that arrives late is dropped.
    private var frameGeneratedAt: Date?

    /// The wrist's own best per exercise, per axis: the sets it logged, and the
    /// phone sets its snapshots brought it (D-15, D-16). One entry per
    /// exercise, never a per-set list (D-12).
    private var own: [String: (e1rm: Double, reps: Int)] = [:]

    public init(
        store: WatchSessionStore,
        validator: SyncProtocolValidator? = nil,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.validator = validator
        self.clock = clock
    }

    /// Whether a frame is held at all. Without one there is no verdict (D-3) —
    /// the wrist says nothing rather than celebrating a first-ever set it
    /// cannot confirm.
    public var hasFrame: Bool {
        stateLock.withLock { frame != nil }
    }

    /// Reads the held frame back out of storage and rebuilds the own bests from
    /// the observations still there. Call on launch.
    ///
    /// The rebuild is one pass over the stored observations, confirmed or not
    /// and snapshot-applied phone entries included (D-16): a wrist log must not
    /// celebrate below a set the wrist already knows, and a relaunch is exactly
    /// when the frame may lag behind what the wrist has logged.
    public func restore() async {
        let contents = await store.readAll()
        let newest = contents.bests.max {
            ($0.generatedAt, $0.sequence) < ($1.generatedAt, $1.sequence)
        }
        let parsed = newest.flatMap { Self.parseBests($0.entries) }
        let ownBests = Self.rebuildOwnBests(from: contents.observations)

        stateLock.withLock {
            frame = parsed
            frameGeneratedAt = parsed == nil ? nil : newest?.generatedAt
            own = ownBests
        }
    }

    /// Applies a `bests_down` frame.
    ///
    /// A frame the watch cannot read is refused whole, with nothing stored and
    /// the previous copy still deciding (D-5). A frame older than the held one
    /// is understood and dropped. A frame carrying the entries the wrist
    /// already holds writes nothing and parses nothing further (D-11). Anything
    /// else is stored — a frame stamped the same moment as the held one
    /// included, so the later-received of the two decides (D-5) — and the copy
    /// it just wrote becomes the one held, with every other frame pruned away
    /// (D-11, D-17).
    public func applyBestsDown(_ envelope: [String: Any]) async -> WatchCatalogSyncResult {
        let rejections = SyncProtocolValidator.incomingRejections(validator, envelope)
        if !rejections.isEmpty {
            return WatchCatalogSyncResult(applied: false, rejections: rejections)
        }

        guard envelope["type"] as? String == "bests_down",
              let messageId = envelope["messageId"] as? String,
              let payload = envelope["payload"] as? [String: Any],
              let generatedAt = try? parseUtcIso(payload["generatedAt"]),
              let rawBests = payload["bests"] as? [[String: Any]],
              let parsed = Self.parseBests(rawBests)
        else { return WatchCatalogSyncResult(applied: false, rejections: []) }

        let older: Bool = stateLock.withLock {
            guard let frameGeneratedAt else { return false }
            return generatedAt < frameGeneratedAt
        }
        if older { return WatchCatalogSyncResult(applied: false, rejections: []) }

        let unchanged: Bool = stateLock.withLock {
            guard let frame else { return false }
            return Self.sameFrame(frame, parsed)
        }
        if unchanged { return WatchCatalogSyncResult(applied: false, rejections: []) }

        let stored = await store.append(
            .bests(
                WatchBestsRecord(
                    recordId: "bests-\(messageId)",
                    recordedAt: clock(),
                    generatedAt: generatedAt,
                    entries: rawBests
                )
            )
        )
        guard case .bests(let row) = stored else {
            return WatchCatalogSyncResult(applied: false, rejections: [])
        }

        stateLock.withLock {
            frame = parsed
            frameGeneratedAt = generatedAt
        }

        _ = await store.pruneBests(keepingRecordId: row.recordId)

        return WatchCatalogSyncResult(applied: true, rejections: [])
    }

    /// Whether the set the wrist just logged beat the best it knows, and the
    /// fold of that set into the own bests.
    ///
    /// Only an effort of kind `set` with reps >= 1 is a claim (D-1); anything
    /// else — a hold with extra load, a timed effort, a round — returns false
    /// and changes nothing. A set with a load is measured on the weight axis,
    /// `loadKg * (1 + reps / 30.0)` in the phone's own operation order, so an
    /// equal set compares equal bit for bit; a set without one — or with a
    /// negative one, the band assist — is measured on the reps axis, exactly as
    /// the phone's toast does (D-1).
    ///
    /// The verdict is read before the fold, and the set is folded in either
    /// way: the own best is what stops the same set celebrating twice, whether
    /// or not a frame is held and whether or not this set was a record (D-15).
    /// Only a held frame grants a verdict at all (D-3).
    public func noteLogged(
        kind: String,
        exerciseId: String,
        reps: Int,
        loadKg: Double?
    ) -> Bool {
        guard kind == WatchObservationKind.set, !exerciseId.isEmpty, reps >= 1 else {
            return false
        }
        return stateLock.withLock {
            let record = beatsStandingBest(exerciseId: exerciseId, reps: reps, loadKg: loadKg)
            Self.fold(exerciseId: exerciseId, reps: reps, loadKg: loadKg, into: &own)
            return record
        }
    }

    /// The verdict against `max(held frame's best, own best)`, strict `>` per
    /// axis, a missing axis counting as zero (D-1, D-2). Called with the lock
    /// held and before the set is folded in.
    private func beatsStandingBest(exerciseId: String, reps: Int, loadKg: Double?) -> Bool {
        guard let frame else { return false }
        let held = frame[exerciseId]
        let mine = own[exerciseId]

        if let loadKg, loadKg > 0 {
            let estimate = Self.estimateOneRepMax(loadKg: loadKg, reps: reps)
            let best = max(held?.e1rmKg ?? 0, mine?.e1rm ?? 0)
            return estimate > best
        }

        let best = max(held?.repsBest ?? 0, mine?.reps ?? 0)
        return reps > best
    }
}

// MARK: - The pieces both the live path and the rebuild use

extension WatchPersonalBests {
    /// Epley, in the phone's operation order (`StatsProgressService.epley1RM`):
    /// `weight * (1 + reps / 30.0)`. The order is the point — a set equal to
    /// the frame's must compare equal to it bit for bit.
    private static func estimateOneRepMax(loadKg: Double, reps: Int) -> Double {
        loadKg * (1 + Double(reps) / 30.0)
    }

    /// Folds one logged set into the own bests, on the axis its verdict used:
    /// a loaded set updates the weight axis, everything else the reps axis
    /// (D-15). It never lowers a standing best.
    private static func fold(
        exerciseId: String,
        reps: Int,
        loadKg: Double?,
        into own: inout [String: (e1rm: Double, reps: Int)]
    ) {
        let standing = own[exerciseId] ?? (e1rm: 0, reps: 0)
        if let loadKg, loadKg > 0 {
            own[exerciseId] = (
                e1rm: max(standing.e1rm, estimateOneRepMax(loadKg: loadKg, reps: reps)),
                reps: standing.reps
            )
        } else {
            own[exerciseId] = (
                e1rm: standing.e1rm,
                reps: max(standing.reps, reps)
            )
        }
    }

    /// The own bests rebuilt in one pass over the observations still stored
    /// (D-12, D-16): every `set` with reps >= 1, confirmed or not, folded
    /// through the same function the live path uses.
    private static func rebuildOwnBests(
        from observations: [WatchObservationRecord]
    ) -> [String: (e1rm: Double, reps: Int)] {
        var own: [String: (e1rm: Double, reps: Int)] = [:]
        for observation in observations where observation.kind == WatchObservationKind.set {
            guard let exerciseId = observation.payload["exerciseId"] as? String,
                  !exerciseId.isEmpty,
                  let reps = wholeCount(observation.payload["reps"]),
                  reps >= 1
            else { continue }
            fold(
                exerciseId: exerciseId,
                reps: reps,
                loadKg: loadKilograms(observation.payload["loadKg"]),
                into: &own
            )
        }
        return own
    }

    /// The frame's `bests` array parsed once into the dictionary detection
    /// reads (D-10), or nil for an entry that is not the shape the payload
    /// promises — a frame is refused whole rather than half-understood.
    ///
    /// An entry names a string `exerciseId` and at least one axis: a positive
    /// `e1rmKg` and/or a positive whole `repsBest`. A missing axis reads as
    /// zero, which is what "an exercise absent from the frame" reads as too
    /// (D-1).
    private static func parseBests(
        _ entries: [[String: Any]]
    ) -> [String: (e1rmKg: Double, repsBest: Int)]? {
        var parsed: [String: (e1rmKg: Double, repsBest: Int)] = [:]

        for entry in entries {
            guard let exerciseId = entry["exerciseId"] as? String, !exerciseId.isEmpty else {
                return nil
            }

            var e1rmKg = 0.0
            if let raw = entry["e1rmKg"] {
                guard let estimate = positiveNumber(raw) else { return nil }
                e1rmKg = estimate
            }

            var repsBest = 0
            if let raw = entry["repsBest"] {
                guard let count = positiveWhole(raw) else { return nil }
                repsBest = count
            }

            guard e1rmKg > 0 || repsBest > 0 else { return nil }

            let standing = parsed[exerciseId] ?? (e1rmKg: 0, repsBest: 0)
            parsed[exerciseId] = (
                e1rmKg: max(standing.e1rmKg, e1rmKg),
                repsBest: max(standing.repsBest, repsBest)
            )
        }

        return parsed
    }

    /// Whether two parsed frames carry the same numbers: the D-11 check that
    /// turns a repeated frame into no write at all.
    private static func sameFrame(
        _ lhs: [String: (e1rmKg: Double, repsBest: Int)],
        _ rhs: [String: (e1rmKg: Double, repsBest: Int)]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (exerciseId, left) in lhs {
            guard let right = rhs[exerciseId],
                  left.e1rmKg == right.e1rmKg,
                  left.repsBest == right.repsBest
            else { return false }
        }
        return true
    }

    /// A payload field as a positive finite number, or nil for anything else —
    /// an absent key's neighbour, a boolean, a string, zero and negatives.
    private static func positiveNumber(_ value: Any) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double > 0 else { return nil }
        return double
    }

    /// A payload field as a positive whole number, or nil for anything else,
    /// a JSON `15.0` included — the payload promises an integer.
    private static func positiveWhole(_ value: Any) -> Int? {
        guard let number = value as? NSNumber,
              !isBoolean(number),
              !CFNumberIsFloatType(number),
              number.intValue >= 1
        else { return nil }
        return number.intValue
    }

    /// A stored payload's count as an integer. Lenient on purpose: the rebuild
    /// must not lose a set it logged, so a number it can read is read.
    private static func wholeCount(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return number.intValue
    }

    /// A stored payload's load in kilograms, negative assists included, or nil
    /// when the set carried none (unloaded work sends no load claim, D-61).
    private static func loadKilograms(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return number.doubleValue
    }
}
