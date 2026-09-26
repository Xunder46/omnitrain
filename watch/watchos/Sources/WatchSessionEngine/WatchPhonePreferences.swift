//
//  WatchPhonePreferences.swift
//  WatchSessionEngine
//
//  The phone's settings the wrist honours, as `preferences_down` last brought
//  them. Plan: `.github/agents/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
//  D-113 and D-114.
//
//  Reference data, like the routines and the food list: the wrist learns it when
//  it syncs, keeps every copy it accepts, and reads the newest. Sync is the
//  wrist's to start, so a setting changed on the phone arrives at the wrist's
//  next sync and not before. Today the message carries one setting: whether a
//  session the wrist ends asks for the session effort rating.
//

import Foundation

/// One copy of the phone's preferences, as a `preferences_down` carried it.
///
/// It belongs to no session — its `sessionId` is empty — and, like every other
/// row, it is appended and never rewritten: a newer copy is a newer row, and the
/// one with the latest `generatedAt` applies.
public struct WatchPreferencesRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int

    /// When the phone generated this copy. An older copy that arrives late is
    /// not a newer truth.
    public let generatedAt: Date

    /// Whether a session the wrist ends asks for the session effort rating.
    public let effortRatingPrompt: Bool

    public init(
        recordId: String,
        recordedAt: Date,
        generatedAt: Date,
        effortRatingPrompt: Bool,
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = ""
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.effortRatingPrompt = effortRatingPrompt
    }

    public func withSequence(_ sequence: Int) -> WatchPreferencesRecord {
        WatchPreferencesRecord(
            recordId: recordId,
            recordedAt: recordedAt,
            generatedAt: generatedAt,
            effortRatingPrompt: effortRatingPrompt,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.preferencesType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "generatedAt": utcIso(generatedAt),
            "effortRatingPrompt": effortRatingPrompt,
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchPreferencesRecord {
        WatchPreferencesRecord(
            recordId: try requiredString(json, "recordId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            generatedAt: try parseUtcIso(json["generatedAt"]),
            effortRatingPrompt: (json["effortRatingPrompt"] as? Bool) ?? false,
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}

/// The owner of the phone's preferences on the wrist.
public final class WatchPhonePreferences {
    private let store: WatchSessionStore
    private let validator: SyncProtocolValidator?
    private let clock: () -> Date

    private var copies: [WatchPreferencesRecord] = []

    public init(
        store: WatchSessionStore,
        validator: SyncProtocolValidator? = nil,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.validator = validator
        self.clock = clock
    }

    /// The copy that applies: the latest `generatedAt`, and on a tie the copy
    /// received later. Nil until the phone has sent one.
    public var current: WatchPreferencesRecord? {
        copies.max { ($0.generatedAt, $0.sequence) < ($1.generatedAt, $1.sequence) }
    }

    /// Whether a session the wrist ends asks for the effort rating. A wrist that
    /// has never heard from the phone does not know the setting, so it does not
    /// ask (D-114).
    public var asksForEffortRating: Bool {
        current?.effortRatingPrompt ?? WatchEffortRatingCopy.promptBeforeFirstSync
    }

    /// Reads every accepted copy back out of storage. Call on launch.
    public func restore() async {
        copies = await store.readAll().preferences
    }

    /// Applies a `preferences_down` message.
    ///
    /// A message the watch cannot read is refused with nothing stored. A copy
    /// older than the one that applies is understood and dropped. Anything else
    /// is stored — a copy stamped the same moment as the current one included,
    /// so the later-received of the two applies (D-113).
    public func applyPreferencesDown(_ envelope: [String: Any]) async -> WatchCatalogSyncResult {
        let rejections = SyncProtocolValidator.incomingRejections(validator, envelope)
        if !rejections.isEmpty {
            return WatchCatalogSyncResult(applied: false, rejections: rejections)
        }

        guard envelope["type"] as? String == "preferences_down",
              let messageId = envelope["messageId"] as? String,
              let payload = envelope["payload"] as? [String: Any],
              let generatedAt = try? parseUtcIso(payload["generatedAt"]),
              isBoolean(payload["effortRatingPrompt"]),
              let asks = payload["effortRatingPrompt"] as? Bool
        else { return WatchCatalogSyncResult(applied: false, rejections: []) }

        if let current, generatedAt < current.generatedAt {
            return WatchCatalogSyncResult(applied: false, rejections: [])
        }

        let recordId = "prefs-\(messageId)"
        let stored = await store.append(
            .preferences(
                WatchPreferencesRecord(
                    recordId: recordId,
                    recordedAt: clock(),
                    generatedAt: generatedAt,
                    effortRatingPrompt: asks
                )
            )
        )
        if case .preferences(let row) = stored,
           !copies.contains(where: { $0.recordId == row.recordId }) {
            copies.append(row)
        }

        return WatchCatalogSyncResult(applied: current?.recordId == recordId, rejections: [])
    }
}
