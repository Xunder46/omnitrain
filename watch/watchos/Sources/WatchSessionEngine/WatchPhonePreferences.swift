//
//  WatchPhonePreferences.swift
//  WatchSessionEngine
//
//  The phone's settings the wrist honours, as `preferences_down` last brought
//  them. Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
//  D-113 and D-114.
//
//  Reference data, like the routines and the food list: the wrist learns it when
//  it syncs, keeps every copy it accepts, and reads the newest. Sync is the
//  wrist's to start, so a setting changed on the phone arrives at the wrist's
//  next sync and not before. Today the message carries three settings: whether a
//  session the wrist ends asks for the session effort rating, how often a rest
//  pings, and the theme accent the wrist wears.
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

    /// How often a rest pings, in whole seconds; 0 is Off. The phone's one
    /// setting for this, carried on every copy (D-242).
    public let restPingSeconds: Int

    /// The phone's theme accent as `#RRGGBB`, or nil when the phone had none to
    /// send (D-3709). Read through `WatchAccent.usable(hex:)`: a wrist wears an
    /// accent only when this parses and clears the contrast floor.
    public let accentColorHex: String?

    public init(
        recordId: String,
        recordedAt: Date,
        generatedAt: Date,
        effortRatingPrompt: Bool,
        restPingSeconds: Int = 0,
        accentColorHex: String? = nil,
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = ""
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.effortRatingPrompt = effortRatingPrompt
        self.restPingSeconds = restPingSeconds
        self.accentColorHex = accentColorHex
    }

    public func withSequence(_ sequence: Int) -> WatchPreferencesRecord {
        WatchPreferencesRecord(
            recordId: recordId,
            recordedAt: recordedAt,
            generatedAt: generatedAt,
            effortRatingPrompt: effortRatingPrompt,
            restPingSeconds: restPingSeconds,
            accentColorHex: accentColorHex,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "recordType": StoredWatchRecord.preferencesType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "generatedAt": utcIso(generatedAt),
            "effortRatingPrompt": effortRatingPrompt,
            "restPingSeconds": restPingSeconds,
        ]
        // A copy the phone sent no accent on writes no key, so a wrist that
        // reads it back keeps its default look instead of an earlier accent.
        if let accentColorHex {
            json["accentColorHex"] = accentColorHex
        }
        return json
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchPreferencesRecord {
        WatchPreferencesRecord(
            recordId: try requiredString(json, "recordId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            generatedAt: try parseUtcIso(json["generatedAt"]),
            effortRatingPrompt: (json["effortRatingPrompt"] as? Bool) ?? false,
            // A row written before the wrist knew this setting carries no key,
            // and reads as Off (D-242).
            restPingSeconds: (json["restPingSeconds"] as? NSNumber)?.intValue ?? 0,
            // A row written before the wrist knew the accent carries no key,
            // and a key that is not a string reads as no accent (D-3709).
            accentColorHex: json["accentColorHex"] as? String,
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

    /// How often a rest pings, in seconds, as the copy that applies carries it.
    /// A wrist that has never heard from the phone reads 0, which is Off: it
    /// does not invent a rest ping (S-242).
    public var restPingSeconds: Int {
        current?.restPingSeconds ?? 0
    }

    /// The phone's theme accent, `#RRGGBB`, as the copy that applies carries it
    /// — nil when that copy carries none, and so nil for a wrist that has never
    /// heard from the phone. Render it through `WatchAccent.usable(hex:)` rather
    /// than trusting it (D-3704).
    public var accentColorHex: String? {
        current?.accentColorHex
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
              let asks = payload["effortRatingPrompt"] as? Bool,
              let restPingSeconds = wholeSeconds(payload["restPingSeconds"])
        else { return WatchCatalogSyncResult(applied: false, rejections: []) }

        if let current, generatedAt < current.generatedAt {
            return WatchCatalogSyncResult(applied: false, rejections: [])
        }

        // The accent is optional, so it is read rather than demanded. A copy
        // without the key — and a key that is not a string, which the payload's
        // closed shape and pattern made the validator refuse first — reads as no
        // accent: the wrist stores the absence and keeps its default look
        // instead of the accent the previous copy carried (D-3704).
        let accentColorHex = payload["accentColorHex"] as? String

        let recordId = "prefs-\(messageId)"
        let stored = await store.append(
            .preferences(
                WatchPreferencesRecord(
                    recordId: recordId,
                    recordedAt: clock(),
                    generatedAt: generatedAt,
                    effortRatingPrompt: asks,
                    restPingSeconds: restPingSeconds,
                    accentColorHex: accentColorHex
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

/// A payload's field as a non-negative whole number of seconds, or nil for
/// anything else — an absent key, a boolean, a negative, and a JSON `90.0`,
/// which the phone's validator refuses as an integer too (F-10). A copy that
/// does not carry a readable interval is refused rather than read as Off
/// (D-242).
private func wholeSeconds(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber,
          !isBoolean(number),
          !CFNumberIsFloatType(number),
          number.intValue >= 0
    else { return nil }
    return number.intValue
}
