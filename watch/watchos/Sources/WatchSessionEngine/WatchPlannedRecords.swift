//
//  WatchPlannedRecords.swift
//  WatchSessionEngine
//
//  The wrist's stored planned sessions and the `planned_down` message that
//  carries them. Mirrors `WatchRoutineRecords.swift` field for field: the same
//  parse gate, the same catalog row, the same newest-wins rule — the plans'
//  `generatedAt` competes only inside their own store, never with the routine
//  catalog's (plan 129, D-8961, D-8966).
//

import Foundation

/// One planned session row as `planned_down` carried it (D-8961): what to call
/// it, when it is scheduled, and where it came from. The phone derived the name
/// (the plan's own title, else its routine template's name, else the modality
/// label, else "Free Training") — the wrist only reads it.
public struct WatchPlannedSession {
    public let plannedSessionId: String
    public let name: String
    public let scheduledDateMs: Int
    public let routineTemplateId: String?
    public let modality: String?
    public let createdAtMs: Int
    public let updatedAtMs: Int

    public init(
        plannedSessionId: String,
        name: String,
        scheduledDateMs: Int,
        routineTemplateId: String? = nil,
        modality: String? = nil,
        createdAtMs: Int,
        updatedAtMs: Int
    ) {
        self.plannedSessionId = plannedSessionId
        self.name = name
        self.scheduledDateMs = scheduledDateMs
        self.routineTemplateId = routineTemplateId
        self.modality = modality
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
    }

    /// Reads one plan out of the payload the validator has already approved.
    /// The optional ids travel only when the phone knows them; their absence is
    /// the free plan's shape, not an error.
    public init(json: [String: Any]) throws {
        self.init(
            plannedSessionId: try requiredString(json, "plannedSessionId"),
            name: try requiredString(json, "name"),
            scheduledDateMs: try requiredInt(json, "scheduledDateMs"),
            routineTemplateId: json["routineTemplateId"] as? String,
            modality: json["modality"] as? String,
            createdAtMs: try requiredInt(json, "createdAtMs"),
            updatedAtMs: try requiredInt(json, "updatedAtMs")
        )
    }
}

/// A parsed `planned_down` payload: the plans the phone still counts as planned
/// and when it generated the view.
public struct WatchPlannedDown {
    public let generatedAt: Date
    public let plans: [WatchPlannedSession]

    public init(generatedAt: Date, plans: [WatchPlannedSession]) {
        self.generatedAt = generatedAt
        self.plans = plans
    }

    /// Reads the payload out of an envelope the validator has already approved.
    public init(envelope: [String: Any]) throws {
        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        self.init(
            generatedAt: try parseUtcIso(payload["generatedAt"]),
            plans: try ((payload["plans"] as? [[String: Any]]) ?? []).map(WatchPlannedSession.init(json:))
        )
    }

    /// The same view, read back out of the row the watch stored.
    public init(catalog: WatchPlannedCatalogRecord) throws {
        self.init(
            generatedAt: catalog.generatedAt,
            plans: try catalog.plans.map(WatchPlannedSession.init(json:))
        )
    }

    /// The row that stores this message, so a relaunch holds the same plans
    /// without the phone.
    public func toRecord(recordId: String, recordedAt: Date) -> WatchPlannedCatalogRecord {
        let planDictionaries: [[String: Any]] = plans.map { plan in
            var planDictionary: [String: Any] = [
                "plannedSessionId": plan.plannedSessionId,
                "name": plan.name,
                "scheduledDateMs": plan.scheduledDateMs,
                "createdAtMs": plan.createdAtMs,
                "updatedAtMs": plan.updatedAtMs,
            ]
            if let routineTemplateId = plan.routineTemplateId {
                planDictionary["routineTemplateId"] = routineTemplateId
            }
            if let modality = plan.modality {
                planDictionary["modality"] = modality
            }
            return planDictionary
        }
        return WatchPlannedCatalogRecord(
            recordId: recordId,
            recordedAt: recordedAt,
            generatedAt: generatedAt,
            plans: planDictionaries
        )
    }
}

// MARK: - The stored row

/// The planned sessions the phone sends down, as the day-list keeps them. Like
/// the routine catalog row it carries no session — its `sessionId` is empty —
/// and it is append-only: a sync writes a new row and the newest one wins, so
/// the list the user had before a sync is still readable afterwards.
public struct WatchPlannedCatalogRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int

    /// When the phone generated this view of the plans. A message older than
    /// the cached one is not a newer truth, so it is ignored.
    public let generatedAt: Date

    /// The plans as `planned_down` carried them, in the phone's order.
    public let plans: [[String: Any]]

    public init(
        recordId: String,
        recordedAt: Date,
        generatedAt: Date,
        plans: [[String: Any]] = [],
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = ""
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.plans = plans
    }

    public func withSequence(_ sequence: Int) -> WatchPlannedCatalogRecord {
        WatchPlannedCatalogRecord(
            recordId: recordId,
            recordedAt: recordedAt,
            generatedAt: generatedAt,
            plans: plans,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.plannedCatalogType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "generatedAt": utcIso(generatedAt),
            "plans": plans,
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchPlannedCatalogRecord {
        WatchPlannedCatalogRecord(
            recordId: try requiredString(json, "recordId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            generatedAt: try parseUtcIso(json["generatedAt"]),
            plans: (json["plans"] as? [[String: Any]]) ?? [],
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}

private func requiredInt(_ json: [String: Any], _ key: String) throws -> Int {
    guard let number = json[key] as? NSNumber else {
        throw WatchRecordError.malformed("field \"\(key)\" is missing")
    }
    return number.intValue
}
