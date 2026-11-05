//
//  WatchWater.swift
//  WatchSessionEngine
//
//  The day's glasses of water on the wrist: the phone's count as the newest
//  `water_down` brought it, plus the wrist's own taps the phone has not
//  counted yet.
//
//  Plan: `docs/plans/2026-11-01-95-watch-water-bar-plan/`, D-24 to D-27 and
//  D-35; the counting rule is plan 94 D-7
//  (`docs/plans/2026-11-01-94-watch-water-logging-plan/`).
//
//  The phone owns the day's water. The wrist sends taps, never a total, and
//  stores no count: the number shown is computed on every read from the held
//  frame and the stored taps, so a relaunch, a receipt or a local midnight
//  never leaves a stale number behind (I-6). A launch drops the taps the phone
//  confirmed long before any local today began (plan 96
//  `docs/plans/2026-11-01-96-watch-water-follow-up-plan/`, D-43).
//

import Combine
import Foundation

/// The wrist's limits on water taps.
public enum WatchWaterLimits {
    /// How many taps the wrist stores per local day (plan 95 D-26). Equal to
    /// `appliedTapIds.maxItems` in `water_down.schema.json` and to the phone's
    /// `kWatchWaterTapsPerDay`: the phone lists at most that many taps for a
    /// day, so a wrist that never taps past it has every receipted tap listed.
    /// `WatchWaterStateTests.testS94b15TapsPastTheCap` reads the schema.
    public static let tapsPerDay = 500

    /// How long a tap the phone confirmed is kept; a launch drops the older
    /// ones (plan 96 D-43). The count reads only taps of local today, and a
    /// local day in any zone contains now and lasts at most 25 h, so a tap
    /// logged before now − 25 h is unreadable by every count in every zone. The
    /// retention adds at least a day of margin (it must be ≥ 49 h); this one
    /// lets a launch clock run up to 47 h fast without dropping a tap a count
    /// can read. Plain instant arithmetic, so a zone change cannot move it.
    /// `WatchWaterPruneTests.testS94c10TheRetentionOutlastsTheLongestLocalDayByADay`.
    public static let confirmedTapRetention: TimeInterval = 72 * 3600
}

/// The owner of the water count on the wrist.
///
/// Reached from the main-actor press path and from the async `receive` path
/// and not actor-isolated, so the held frame is guarded by a lock (the
/// `WatchPersonalBests` pattern), and the frame applies and presses run one at
/// a time through an async gate, so two frames cannot both pass the "newer"
/// check, and two presses cannot both pass the cap.
public final class WatchWaterState {
    /// The held frame, as parsed when it arrived.
    private struct HeldFrame {
        var generatedAt: Date
        let day: String
        let glasses: Int
        let appliedTapIds: [String]
    }

    private let engine: WatchSessionEngine
    private let store: WatchSessionStore
    private let validator: SyncProtocolValidator?
    private let clock: () -> Date
    private let calendar: Calendar

    /// Plan 96 D-45: where a read takes the stored taps from, and how it reads
    /// a tap's `loggedAt`. Not public: the host builds the state with the
    /// defaults, and tests count reads and parses through these.
    private let tapLog: () -> [WatchObservationRecord]
    private let parseLoggedAt: (Any?) throws -> Date

    private let stateLock = NSLock()
    private let gate = WatchAsyncMutex()

    /// The newest frame, or nil before the first one. Its `generatedAt` can
    /// run ahead of the stored row's: a repeat of the held content advances it
    /// in memory without writing (D-24 step 4).
    private var held: HeldFrame?

    /// Fires after `restore()`, after an applied frame and after a stored tap;
    /// never for a refused, dropped or unchanged frame, nor a press that
    /// stored nothing (D-24, D-27).
    public var onWaterChanged: (() -> Void)?

    public convenience init(
        engine: WatchSessionEngine,
        store: WatchSessionStore,
        validator: SyncProtocolValidator? = nil,
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.init(
            engine: engine,
            store: store,
            validator: validator,
            clock: clock,
            calendar: calendar,
            tapLog: { engine.waterLog },
            parseLoggedAt: parseUtcIso
        )
    }

    init(
        engine: WatchSessionEngine,
        store: WatchSessionStore,
        validator: SyncProtocolValidator?,
        clock: @escaping () -> Date,
        calendar: Calendar,
        tapLog: @escaping () -> [WatchObservationRecord],
        parseLoggedAt: @escaping (Any?) throws -> Date
    ) {
        self.engine = engine
        self.store = store
        self.validator = validator
        self.clock = clock
        self.calendar = calendar
        self.tapLog = tapLog
        self.parseLoggedAt = parseLoggedAt
    }

    // MARK: - The frame

    /// Drops the confirmed taps older than `confirmedTapRetention` (plan 96
    /// D-43), then reads the held frame back out of storage: the row with the
    /// greatest (`generatedAt`, `sequence`). Call on launch, after the engine's
    /// own restore (the count folds the engine's stored taps). The tap prune
    /// runs here only, once per launch, never on the radio path.
    public func restore() async {
        await gate.exclusive {
            let cutoff = clock().addingTimeInterval(-WatchWaterLimits.confirmedTapRetention)
            _ = await engine.pruneWaterTaps(loggedBefore: cutoff)
            let rows = await store.readAll().water
            let newest = rows.max {
                ($0.generatedAt, $0.sequence) < ($1.generatedAt, $1.sequence)
            }
            let frame = newest.map {
                HeldFrame(
                    generatedAt: $0.generatedAt,
                    day: $0.day,
                    glasses: $0.glasses,
                    appliedTapIds: $0.appliedTapIds
                )
            }
            stateLock.withLock { held = frame }
        }
        onWaterChanged?()
    }

    /// Applies a `water_down` frame (D-24).
    ///
    /// In order: a frame the validator refuses stores nothing; a frame the
    /// wrist cannot read stores nothing; a frame older than the held one is
    /// dropped; a frame carrying the held content again writes nothing and
    /// only moves the held `generatedAt` forward. Anything else is stored —
    /// a tie in `generatedAt` with different content included, so the later
    /// received decides — held, and every other frame row is pruned (I-8).
    public func applyWaterDown(_ envelope: [String: Any]) async -> WatchCatalogSyncResult {
        let rejections = SyncProtocolValidator.incomingRejections(validator, envelope)
        if !rejections.isEmpty {
            return WatchCatalogSyncResult(applied: false, rejections: rejections)
        }

        guard envelope["type"] as? String == "water_down",
              let messageId = envelope["messageId"] as? String,
              let payload = envelope["payload"] as? [String: Any],
              let generatedAt = try? parseUtcIso(payload["generatedAt"]),
              let day = payload["day"] as? String,
              let glasses = Self.wholeGlasses(payload["glasses"]),
              let appliedTapIds = payload["appliedTapIds"] as? [String]
        else { return WatchCatalogSyncResult(applied: false, rejections: []) }

        let applied: Bool = await gate.exclusive {
            enum Verdict { case older, unchanged, newer }
            let verdict: Verdict = stateLock.withLock {
                guard let current = held else { return .newer }
                if generatedAt < current.generatedAt { return .older }
                if current.day == day,
                   current.glasses == glasses,
                   current.appliedTapIds == appliedTapIds {
                    held?.generatedAt = generatedAt
                    return .unchanged
                }
                return .newer
            }
            guard verdict == .newer else { return false }

            let stored = await store.append(
                .water(
                    WatchWaterRecord(
                        recordId: "water-\(messageId)",
                        recordedAt: clock(),
                        generatedAt: generatedAt,
                        day: day,
                        glasses: glasses,
                        appliedTapIds: appliedTapIds
                    )
                )
            )
            guard case .water(let row) = stored else { return false }

            stateLock.withLock {
                held = HeldFrame(
                    generatedAt: generatedAt,
                    day: day,
                    glasses: glasses,
                    appliedTapIds: appliedTapIds
                )
            }
            _ = await store.pruneWater(keepingRecordId: row.recordId)
            return true
        }

        if applied { onWaterChanged?() }
        return WatchCatalogSyncResult(applied: applied, rejections: [])
    }

    // MARK: - The count

    /// The count and both buttons' rules, from one clock read and one read of
    /// the stored taps (plan 96 D-40). Computed on every read, never cached:
    /// a cache would need to hear of every receipt, minute and zone change.
    public var snapshot: WatchWaterSnapshot {
        let now = clock()
        let frame = stateLock.withLock { held }
        let taps = todaysTaps(now)
        let listed = Set(frame?.appliedTapIds ?? [])
        var count = frame?.day == localDay(now) ? frame?.glasses ?? 0 : 0
        for tap in taps where !listed.contains(tap.id) {
            switch tap.change {
            case .add: count += 1
            case .remove: count = max(0, count - 1)
            }
        }
        let canAdd = taps.count < WatchWaterLimits.tapsPerDay
        return WatchWaterSnapshot(
            glasses: count,
            canAdd: canAdd,
            canRemove: canAdd && count > 0,
            spokenCount: WatchWaterCopy.spokenCount(count)
        )
    }

    /// The glasses shown (D-25, plan 94 D-7): the held frame's count when its
    /// day is the wrist's local today, else 0; then the wrist's taps of local
    /// today that the frame does not list — confirmed or not, because only the
    /// frame's list takes a tap out — folded in `loggedAt` order, ties by
    /// store order: add +1, remove −1 but never below 0.
    public var glasses: Int { snapshot.glasses }

    /// Whether a plus stores a tap: today's own taps are under the cap (D-27).
    public var canAdd: Bool { snapshot.canAdd }

    /// Whether a minus stores a tap: the count is above 0 and the cap is not
    /// reached (D-27).
    public var canRemove: Bool { snapshot.canRemove }

    // MARK: - The presses

    /// One press of plus or minus: stores one tap, logged at this state's
    /// clock, and returns whether it did. A press whose button's rule is false
    /// stores nothing, emits nothing and returns false (D-27).
    @discardableResult
    public func press(_ change: WatchGlassChange) async -> Bool {
        let stored: Bool = await gate.exclusive {
            let current = snapshot
            let allowed: Bool
            switch change {
            case .add: allowed = current.canAdd
            case .remove: allowed = current.canRemove
            }
            guard allowed else { return false }
            guard let tap = try? await engine.logWaterGlass(change, loggedAt: clock()) else {
                return false
            }
            return engine.waterLog.contains { $0.recordId == tap.recordId }
        }
        if stored { onWaterChanged?() }
        return stored
    }

    // MARK: - Days and taps

    private struct Tap {
        let id: String
        let change: WatchGlassChange
        let loggedAt: Date
        let sequence: Int
        let position: Int
    }

    /// The wrist's own taps whose `loggedAt` falls on the local day of `now`,
    /// in fold order: `loggedAt`, then store sequence, then store position.
    /// Only a tap stored under a session id local today can carry is parsed
    /// (plan 96 D-41); the rest of the history is skipped unread.
    private func todaysTaps(_ now: Date) -> [Tap] {
        let candidates = sessionIds(on: now)
        return tapLog().enumerated().compactMap { position, record -> Tap? in
            if let candidates, !candidates.contains(record.sessionId) { return nil }
            guard let raw = record.payload["glassChange"] as? String,
                  let change = WatchGlassChange(rawValue: raw),
                  let loggedAt = try? parseLoggedAt(record.payload["loggedAt"]),
                  calendar.isDate(loggedAt, inSameDayAs: now)
            else { return nil }
            return Tap(
                id: record.entryId,
                change: change,
                loggedAt: loggedAt,
                sequence: record.sequence,
                position: position
            )
        }
        .sorted { ($0.loggedAt, $0.sequence, $0.position) < ($1.loggedAt, $1.sequence, $1.position) }
    }

    /// The session ids a tap of local today can be stored under: a tap is
    /// stored under `WatchNutritionSession.idFor(loggedAt)`, its UTC date
    /// (D-22), so these are the UTC dates local today touches — at most three,
    /// since a local day lasts at most 25 h. Nil when the calendar gives no
    /// interval for the day: then every tap is read, as before plan 96.
    private func sessionIds(on now: Date) -> Set<String>? {
        guard let day = calendar.dateInterval(of: .day, for: now) else { return nil }
        var ids: Set<String> = []
        var instant = day.start
        while instant < day.end {
            ids.insert(WatchNutritionSession.idFor(instant))
            // The next UTC midnight: Unix time has no leap seconds.
            let utcDay = (instant.timeIntervalSince1970 / Self.secondsPerDay).rounded(.down)
            instant = Date(timeIntervalSince1970: (utcDay + 1) * Self.secondsPerDay)
        }
        return ids
    }

    private static let secondsPerDay: TimeInterval = 86_400

    /// The zero-padded `YYYY-MM-DD` of `instant` in the injected calendar —
    /// the form a frame's `day` is written in.
    private func localDay(_ instant: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A payload's whole, non-negative glass count, or nil for anything else
    /// — an absent key, a string, a boolean, a fraction or a negative.
    private static func wholeGlasses(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              !isBoolean(number),
              !CFNumberIsFloatType(number),
              number.intValue >= 0
        else { return nil }
        return number.intValue
    }
}

/// One read of the water bar (plan 96 D-40): the count, both buttons' rules
/// and the count as spoken, all from the same instant and the same taps.
public struct WatchWaterSnapshot: Equatable {
    public let glasses: Int
    public let canAdd: Bool
    public let canRemove: Bool
    public let spokenCount: String

    public init(glasses: Int, canAdd: Bool, canRemove: Bool, spokenCount: String) {
        self.glasses = glasses
        self.canAdd = canAdd
        self.canRemove = canRemove
        self.spokenCount = spokenCount
    }
}

/// What VoiceOver says about the water bar (plan 95 D-33), worded after the
/// phone's own tooltips. Platform-independent so `swift test` holds the words.
public enum WatchWaterCopy {
    public static let addLabel = "Add one glass"
    public static let removeLabel = "Remove one glass"
    /// The middle of the bar — the drop and the number — is one element.
    public static let countLabel = "Water"

    /// The count as spoken: "1 glass", otherwise "N glasses".
    public static func spokenCount(_ glasses: Int) -> String {
        glasses == 1 ? "1 glass" : "\(glasses) glasses"
    }
}

/// The water bar's observable wrapper (plan 95 D-35): every read goes to the
/// state, which computes the snapshot afresh, and every change the state
/// announces — a stored tap, an applied frame, a restore — is handed to
/// SwiftUI on the main queue, since the state can announce it from the
/// radio's thread. Outside any `#if`, so `swift test` covers it.
public final class WatchWaterModel: ObservableObject {
    public let state: WatchWaterState

    public init(state: WatchWaterState) {
        self.state = state
        state.onWaterChanged = { [weak self] in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    /// The count, both buttons' rules and the spoken count, read once per
    /// redraw (plan 96 D-42): the only read the bar makes.
    public var snapshot: WatchWaterSnapshot { state.snapshot }

    /// One press of plus or minus; true when a tap was stored, which is when
    /// the bar plays its click (D-32).
    @discardableResult
    public func press(_ change: WatchGlassChange) async -> Bool {
        await state.press(change)
    }
}
