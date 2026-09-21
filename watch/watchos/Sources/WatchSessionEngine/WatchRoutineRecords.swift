//
//  WatchRoutineRecords.swift
//  WatchSessionEngine
//
//  The reference data a `routines_down` message carries, and the row the watch
//  keeps it in. Mirrors `lib/watch/session/watch_records.dart` (the row) and
//  `lib/watch/start/watch_routine_catalog.dart` (the view the start paths read
//  it through), so the two watch clients hold and reason about the same data.
//
//  The full catalog never reaches the watch: what comes down is the user's
//  routines and the fallback exercise list that covers them. Nothing here is
//  the watch's own data — routines are the phone's to own and the wrist's to
//  read (PROTOCOL.md, authority rule 2).
//

import Foundation

/// A catalog exercise: what it is, not where it sits in a session.
public struct WatchCatalogExercise: Equatable {
    public let exerciseId: String
    public let name: String

    /// The capability flags the effort kind and the metric rows are derived from.
    public let capabilities: [String]

    public init(exerciseId: String, name: String, capabilities: [String]) {
        self.exerciseId = exerciseId
        self.name = name
        self.capabilities = capabilities
    }

    public init(json: [String: Any]) throws {
        self.init(
            exerciseId: try requiredString(json, "exerciseId"),
            name: try requiredString(json, "name"),
            capabilities: (json["capabilities"] as? [String]) ?? []
        )
    }

    /// The exercise a session slot holds, or nil when the slot is malformed.
    public init?(slot: [String: Any]) {
        guard let exerciseId = slot["exerciseId"] as? String,
              let name = slot["name"] as? String
        else { return nil }
        self.init(
            exerciseId: exerciseId,
            name: name,
            capabilities: (slot["capabilities"] as? [String]) ?? []
        )
    }

    /// The slot id this exercise takes when the user picks it for a session.
    /// Distinct from the ids the phone chooses, which is what lets a pushed
    /// exercise and a picked one of the same kind sit side by side.
    public var slotId: String { "sx-\(exerciseId)" }

    /// This exercise as a protocol `sessionExercise` slot.
    public func toSlot(sessionExerciseId: String? = nil) -> [String: Any] {
        [
            "sessionExerciseId": sessionExerciseId ?? slotId,
            "exerciseId": exerciseId,
            "name": name,
            "capabilities": capabilities,
        ]
    }

    public func toJson() -> [String: Any] {
        ["exerciseId": exerciseId, "name": name, "capabilities": capabilities]
    }
}

/// One planned effort inside a routine segment: what to do and how much of it.
public struct WatchRoutineEffort {
    public let effortId: String
    public let exerciseId: String
    public let exerciseName: String
    public let effortKind: String
    public let capabilities: [String]
    public let targets: [String: Any]

    public init(
        effortId: String,
        exerciseId: String,
        exerciseName: String,
        effortKind: String,
        capabilities: [String],
        targets: [String: Any] = [:]
    ) {
        self.effortId = effortId
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.effortKind = effortKind
        self.capabilities = capabilities
        self.targets = targets
    }

    public init(json: [String: Any]) throws {
        self.init(
            effortId: try requiredString(json, "effortId"),
            exerciseId: try requiredString(json, "exerciseId"),
            exerciseName: try requiredString(json, "exerciseName"),
            effortKind: try requiredString(json, "effortKind"),
            capabilities: (json["capabilities"] as? [String]) ?? [],
            targets: (json["targets"] as? [String: Any]) ?? [:]
        )
    }

    /// The slot this effort becomes when the routine is started. Keyed by
    /// effort, so a routine that benches in two segments yields two slots.
    public var slot: [String: Any] {
        catalogExercise.toSlot(sessionExerciseId: "sx-\(effortId)")
    }

    /// This effort as a catalog exercise, for the fallback list.
    public var catalogExercise: WatchCatalogExercise {
        WatchCatalogExercise(
            exerciseId: exerciseId,
            name: exerciseName,
            capabilities: capabilities
        )
    }

    public func toJson() -> [String: Any] {
        [
            "effortId": effortId,
            "exerciseId": exerciseId,
            "exerciseName": exerciseName,
            "effortKind": effortKind,
            "capabilities": capabilities,
            "targets": targets,
        ]
    }
}

/// One segment of a routine: a named run of efforts.
public struct WatchRoutineSegment {
    public let segmentId: String
    public let name: String
    public let efforts: [WatchRoutineEffort]

    public init(segmentId: String, name: String, efforts: [WatchRoutineEffort]) {
        self.segmentId = segmentId
        self.name = name
        self.efforts = efforts
    }

    public init(json: [String: Any]) throws {
        self.init(
            segmentId: try requiredString(json, "segmentId"),
            name: try requiredString(json, "name"),
            efforts: try ((json["efforts"] as? [[String: Any]]) ?? []).map(WatchRoutineEffort.init(json:))
        )
    }

    public func toJson() -> [String: Any] {
        ["segmentId": segmentId, "name": name, "efforts": efforts.map { $0.toJson() }]
    }
}

/// A reusable workout template, as the phone sent it.
public struct WatchRoutine {
    public let routineId: String
    public let name: String

    /// When the phone last edited it. The cache is replaced wholesale, so this
    /// is what tells the user which version they are looking at.
    public let updatedAt: Date

    public let segments: [WatchRoutineSegment]

    public init(routineId: String, name: String, updatedAt: Date, segments: [WatchRoutineSegment]) {
        self.routineId = routineId
        self.name = name
        self.updatedAt = updatedAt
        self.segments = segments
    }

    public init(json: [String: Any]) throws {
        self.init(
            routineId: try requiredString(json, "routineId"),
            name: try requiredString(json, "name"),
            updatedAt: try parseUtcIso(json["updatedAt"]),
            segments: try ((json["segments"] as? [[String: Any]]) ?? []).map(WatchRoutineSegment.init(json:))
        )
    }

    /// Every effort in the routine, in the order the session will run them.
    public var efforts: [WatchRoutineEffort] { segments.flatMap(\.efforts) }

    /// The session slots starting this routine creates, in order.
    public var slots: [[String: Any]] { efforts.map(\.slot) }

    /// The catalog exercises this routine cannot run without, in routine order,
    /// deduplicated. Every one of them must be in the fallback list, or the
    /// watch would hold a routine it cannot log offline.
    public var referencedExercises: [WatchCatalogExercise] {
        var seen = Set<String>()
        return efforts.compactMap { effort in
            seen.insert(effort.exerciseId).inserted ? effort.catalogExercise : nil
        }
    }

    public func toJson() -> [String: Any] {
        [
            "routineId": routineId,
            "name": name,
            "updatedAt": utcIso(updatedAt),
            "segments": segments.map { $0.toJson() },
        ]
    }
}

/// A parsed `routines_down` payload: the routines, the fallback list, and when
/// the phone generated them.
public struct WatchRoutinesDown {
    public let generatedAt: Date
    public let routines: [WatchRoutine]
    public let fallbackExercises: [WatchCatalogExercise]

    public init(
        generatedAt: Date,
        routines: [WatchRoutine],
        fallbackExercises: [WatchCatalogExercise]
    ) {
        self.generatedAt = generatedAt
        self.routines = routines
        self.fallbackExercises = fallbackExercises
    }

    /// Reads the payload out of an envelope the validator has already approved.
    public init(envelope: [String: Any]) throws {
        let payload = (envelope["payload"] as? [String: Any]) ?? [:]
        self.init(
            generatedAt: try parseUtcIso(payload["generatedAt"]),
            routines: try ((payload["routines"] as? [[String: Any]]) ?? []).map(WatchRoutine.init(json:)),
            fallbackExercises: try ((payload["fallbackExercises"] as? [[String: Any]]) ?? [])
                .map(WatchCatalogExercise.init(json:))
        )
    }

    /// The same view, read back out of the row the watch stored.
    public init(catalog: WatchRoutineCatalogRecord) throws {
        self.init(
            generatedAt: catalog.generatedAt,
            routines: try catalog.routines.map(WatchRoutine.init(json:)),
            fallbackExercises: try catalog.fallbackExercises.map(WatchCatalogExercise.init(json:))
        )
    }

    /// The row that stores this message, so a relaunch holds the same routines
    /// without the phone.
    public func toRecord(recordId: String, recordedAt: Date) -> WatchRoutineCatalogRecord {
        WatchRoutineCatalogRecord(
            recordId: recordId,
            recordedAt: recordedAt,
            generatedAt: generatedAt,
            routines: routines.map { $0.toJson() },
            fallbackExercises: fallbackExercises.map { $0.toJson() }
        )
    }
}

// MARK: - The stored row

/// The reference data the phone sends down: the user's routines and the fallback
/// exercise list the wrist may log without reaching the phone.
///
/// A catalog row carries no session, which is why its `sessionId` is empty — it
/// belongs to the watch, not to any one workout. Like every other row it is
/// append-only: a sync writes a new catalog and the newest one wins, so the
/// version the user had before a sync is still readable afterwards.
///
/// What the wrist itself used recently is *not* stored here: it is derived from
/// the sessions the watch already kept, which is one less thing that can drift.
public struct WatchRoutineCatalogRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int

    /// When the phone generated this view of the routines. A message older than
    /// the cached one is not a newer truth, so it is ignored.
    public let generatedAt: Date

    /// The routines as `routines_down` carried them: routine → segments →
    /// efforts → per-metric targets.
    public let routines: [[String: Any]]

    /// The phone's fallback exercise list, in the phone's order.
    public let fallbackExercises: [[String: Any]]

    public init(
        recordId: String,
        recordedAt: Date,
        generatedAt: Date,
        routines: [[String: Any]] = [],
        fallbackExercises: [[String: Any]] = [],
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = ""
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.routines = routines
        self.fallbackExercises = fallbackExercises
    }

    public func withSequence(_ sequence: Int) -> WatchRoutineCatalogRecord {
        WatchRoutineCatalogRecord(
            recordId: recordId,
            recordedAt: recordedAt,
            generatedAt: generatedAt,
            routines: routines,
            fallbackExercises: fallbackExercises,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.routineCatalogType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "generatedAt": utcIso(generatedAt),
            "routines": routines,
            "fallbackExercises": fallbackExercises,
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchRoutineCatalogRecord {
        WatchRoutineCatalogRecord(
            recordId: try requiredString(json, "recordId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            generatedAt: try parseUtcIso(json["generatedAt"]),
            routines: (json["routines"] as? [[String: Any]]) ?? [],
            fallbackExercises: (json["fallbackExercises"] as? [[String: Any]]) ?? [],
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}
