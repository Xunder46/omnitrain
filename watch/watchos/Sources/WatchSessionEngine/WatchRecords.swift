//
//  WatchRecords.swift
//  WatchSessionEngine
//
//  Records the watch appends to its own storage. Mirrors
//  `lib/watch/session/watch_records.dart` field for field, so the two watch
//  implementations store and emit the same data.
//
//  The watch store is append-only (PROTOCOL.md, authority rule 1): a record is
//  written once and never rewritten, and the newest record for a key wins when
//  state is reduced from the log. Position and timer state therefore advance by
//  appending, and there is no update path to forget to avoid.
//

import Foundation

public enum WatchSessionStatus {
    public static let active = "active"
    public static let completed = "completed"
    public static let abandoned = "abandoned"
}

public enum WatchTimerKind {
    public static let rest = "rest"
    public static let round = "round"
    public static let hold = "hold"
    public static let elapsed = "elapsed"

    public static let all = [rest, round, hold, elapsed]
}

/// Derived timer states, matching the protocol's `timer.state` enum.
public enum WatchTimerState {
    public static let running = "running"
    public static let paused = "paused"
    public static let stopped = "stopped"
}

/// Session lifecycle states, matching `session_lifecycle.payload.state`. The
/// watch emits these as the session moves; the phone's mirror follows them.
public enum WatchLifecycleState {
    public static let started = "started"
    public static let exerciseAdvanced = "exercise_advanced"
    public static let completed = "completed"
    public static let abandoned = "abandoned"
}

/// The `kind` an observation carries, matching `observations_up`'s event enum
/// (PROTOCOL.md, "Message families").
public enum WatchObservationKind {
    public static let set = "set"
    public static let timed = "timed"
    public static let round = "round"
    public static let hold = "hold"

    /// A food the user quick-logged. Not tied to a session slot: it names a
    /// food and a portion, and nothing else.
    public static let nutritionQuickLog = "nutrition_quick_log"

    /// The session effort rating the wrist asks for when its End completes a
    /// session. Session-scoped: it names no slot and no exercise, and a session
    /// carries at most one (`WatchSessionCapture.effortRatingId`).
    public static let effortRating = "effort_rating"

    /// How and when a session the wrist created ended, with the heart-rate
    /// summaries computed for it. Session-scoped, and one per such session
    /// (`WatchSessionCapture.sessionEndId`).
    public static let sessionEnd = "session_end"

    /// The window between two efforts, hung on the entry it followed. It
    /// records no work in a slot, so it is not an effort: it never joins
    /// `efforts`, and the set block's span and the effort debt do not see it.
    public static let rest = "rest"

    public static let all = [
        set, timed, round, hold, nutritionQuickLog, effortRating, sessionEnd, rest,
    ]

    /// The kinds that record work done in a slot — what "an effort entry" means
    /// to a set block's span and to whether an effort rating is owed.
    public static let efforts = [set, timed, round, hold]
}

/// The ids of the two session-scoped observations. Derived from the session
/// rather than minted, so appending one twice is a store no-op and "does this
/// session have one" is a lookup (PROTOCOL.md, "Session capture").
public enum WatchSessionCapture {
    public static func sessionEndId(_ sessionId: String) -> String { "end-\(sessionId)" }

    public static func effortRatingId(_ sessionId: String) -> String { "rating-\(sessionId)" }
}

/// The session id a nutrition quick-log carries when the wrist has no session
/// to put it in.
///
/// `observations_up` requires a non-empty `sessionId`, and the quick-log
/// surface is reachable with no workout running — eating is not a training
/// event. A log taken outside a session therefore names the day's nutrition
/// log rather than inventing a training session; a log taken while a session is
/// running rides that session instead, so it is part of the workout's story.
public enum WatchNutritionSession {
    public static let prefix = "nutrition-"

    /// The id standalone quick-logs logged at `loggedAt` carry, in UTC.
    public static func idFor(_ loggedAt: Date) -> String {
        let utc = UTC.calendar.dateComponents([.year, .month, .day], from: loggedAt)
        let month = String(format: "%02d", utc.month ?? 1)
        let day = String(format: "%02d", utc.day ?? 1)
        return "\(prefix)\(utc.year ?? 0)-\(month)-\(day)"
    }
}

private enum UTC {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

/// What a sensor sample measures, and in which unit.
///
/// The watch stores raw readings; nothing here is derived analytics, and the
/// kinds are the vocabulary both watch clients agreed on
/// (`watch/contract/watch_sensor_contract.json`).
public enum WatchSensorKind {
    /// Beats per minute, at the instant the sample was taken.
    public static let heartRate = "hr"

    /// Cumulative metres covered since the session started, as the GPS fix saw
    /// it. Each fix supersedes the one before: latest wins.
    public static let gps = "gps"

    /// The session's distance total in metres, written when recording stops and
    /// the measurement is final.
    public static let distance = "distance"

    /// The platform's step count since the platform workout began, cumulative:
    /// each sample supersedes the one before, and a smaller value than its
    /// predecessor means the counter restarted.
    public static let steps = "steps"

    public static let all = [heartRate, gps, distance, steps]
}

/// A UTC timestamp in the protocol's wire shape: `YYYY-MM-DDTHH:MM:SS(.sss)Z`.
public func utcIso(_ instant: Date) -> String {
    isoWithFractionalSeconds.string(from: instant)
}

private let isoWithFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let isoWithoutFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

public func parseUtcIso(_ value: Any?) throws -> Date {
    guard let text = value as? String else {
        throw WatchRecordError.malformed("expected a timestamp, found \(value ?? "nil")")
    }
    if let parsed = isoWithFractionalSeconds.date(from: text) { return parsed }
    if let parsed = isoWithoutFractionalSeconds.date(from: text) { return parsed }
    throw WatchRecordError.malformed("not an ISO-8601 UTC instant: \(text)")
}

public func parseOptionalUtcIso(_ value: Any?) throws -> Date? {
    guard let value, !(value is NSNull) else { return nil }
    return try parseUtcIso(value)
}

public enum WatchRecordError: Error {
    case malformed(String)
    case unknownRecordType(String)
}

// MARK: - Session

/// One version of a session's state. The newest row for a session id *is* the
/// session; a state change appends rather than updates.
public struct WatchSessionRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int
    public let startedAt: Date
    public let modality: String?
    public let source: String
    public let status: String
    public let currentExerciseIndex: Int
    public let exercises: [[String: Any]]

    /// The phone's structure counter — bumped by one per applied structure
    /// change, so the two devices can tell at a glance whether they are looking
    /// at the same session shape. Zero until a snapshot says otherwise.
    public let revision: Int

    /// The entry ids the phone deleted, as the newest row knows them: the
    /// durable half of the deletion lens (plan D-113), so a relaunch rebuilds
    /// it from storage instead of forgetting it. Ids the newest snapshot
    /// carries are not in it — an entry the phone still sends exists.
    public let deletedEntryIds: [String]

    public init(
        recordId: String,
        sessionId: String,
        recordedAt: Date,
        startedAt: Date,
        modality: String?,
        source: String,
        status: String,
        currentExerciseIndex: Int,
        exercises: [[String: Any]] = [],
        revision: Int = 0,
        deletedEntryIds: [String] = [],
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = sessionId
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.startedAt = startedAt
        self.modality = modality
        self.source = source
        self.status = status
        self.currentExerciseIndex = currentExerciseIndex
        self.exercises = exercises
        self.revision = revision
        self.deletedEntryIds = deletedEntryIds
    }

    public var currentExercise: [String: Any]? {
        guard !exercises.isEmpty else { return nil }
        return exercises[min(max(currentExerciseIndex, 0), exercises.count - 1)]
    }

    public func withSequence(_ sequence: Int) -> WatchSessionRecord {
        WatchSessionRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            startedAt: startedAt,
            modality: modality,
            source: source,
            status: status,
            currentExerciseIndex: currentExerciseIndex,
            exercises: exercises,
            revision: revision,
            deletedEntryIds: deletedEntryIds,
            sequence: sequence
        )
    }

    /// The same row carrying `deletedEntryIds` as its deletion lens.
    public func withDeletedEntryIds(_ deletedEntryIds: [String]) -> WatchSessionRecord {
        WatchSessionRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            startedAt: startedAt,
            modality: modality,
            source: source,
            status: status,
            currentExerciseIndex: currentExerciseIndex,
            exercises: exercises,
            revision: revision,
            deletedEntryIds: deletedEntryIds,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.sessionType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "startedAt": utcIso(startedAt),
            "modality": modality ?? NSNull(),
            "source": source,
            "status": status,
            "currentExerciseIndex": currentExerciseIndex,
            "exercises": exercises,
            "revision": revision,
            "deletedEntryIds": deletedEntryIds,
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchSessionRecord {
        WatchSessionRecord(
            recordId: try requiredString(json, "recordId"),
            sessionId: try requiredString(json, "sessionId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            startedAt: try parseUtcIso(json["startedAt"]),
            modality: json["modality"] as? String,
            source: try requiredString(json, "source"),
            status: try requiredString(json, "status"),
            currentExerciseIndex: (json["currentExerciseIndex"] as? NSNumber)?.intValue ?? 0,
            exercises: (json["exercises"] as? [[String: Any]]) ?? [],
            revision: (json["revision"] as? NSNumber)?.intValue ?? 0,
            deletedEntryIds: (json["deletedEntryIds"] as? [String]) ?? [],
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}

// MARK: - Observation

/// One observation the watch logged. The payload is the protocol's
/// `observations_up` event verbatim, so emission needs no reconstruction.
public struct WatchObservationRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int
    public let kind: String
    public let payload: [String: Any]
    public let confirmedAt: Date?

    public init(
        recordId: String,
        sessionId: String,
        recordedAt: Date,
        kind: String,
        payload: [String: Any],
        confirmedAt: Date? = nil,
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = sessionId
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.kind = kind
        self.payload = payload
        self.confirmedAt = confirmedAt
    }

    public var entryId: String { payload["entryId"] as? String ?? "" }

    public var eventId: String { payload["eventId"] as? String ?? "" }

    public func withSequence(_ sequence: Int) -> WatchObservationRecord {
        WatchObservationRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            kind: kind,
            payload: payload,
            confirmedAt: confirmedAt,
            sequence: sequence
        )
    }

    /// The same observation, carrying the phone's receipt.
    public func withConfirmation(_ confirmedAt: Date) -> WatchObservationRecord {
        WatchObservationRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            kind: kind,
            payload: payload,
            confirmedAt: confirmedAt,
            sequence: sequence
        )
    }

    /// The same observation carrying `payload` — how a correction the phone sent
    /// reaches the surface without rewriting the stored row.
    public func withPayload(_ payload: [String: Any]) -> WatchObservationRecord {
        WatchObservationRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            kind: kind,
            payload: payload,
            confirmedAt: confirmedAt,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.observationType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "kind": kind,
            "payload": payload,
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchObservationRecord {
        WatchObservationRecord(
            recordId: try requiredString(json, "recordId"),
            sessionId: try requiredString(json, "sessionId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            kind: try requiredString(json, "kind"),
            payload: (json["payload"] as? [String: Any]) ?? [:],
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}

// MARK: - Timer

/// One version of a timer's state. Timestamps only: remaining time is never
/// stored, because a stored countdown is wrong the moment the watch sleeps.
public struct WatchTimerRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int
    public let kind: String
    public let startedAt: Date
    public let pausedAt: Date?
    public let stoppedAt: Date?
    public let accumulatedPauseMs: Int
    public let plannedDurationMs: Int?

    public init(
        recordId: String,
        sessionId: String,
        recordedAt: Date,
        kind: String,
        startedAt: Date,
        pausedAt: Date? = nil,
        stoppedAt: Date? = nil,
        accumulatedPauseMs: Int = 0,
        plannedDurationMs: Int? = nil,
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = sessionId
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.kind = kind
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.stoppedAt = stoppedAt
        self.accumulatedPauseMs = accumulatedPauseMs
        self.plannedDurationMs = plannedDurationMs
    }

    /// Derived from which timestamps are present.
    public var state: String {
        if stoppedAt != nil { return WatchTimerState.stopped }
        if pausedAt != nil { return WatchTimerState.paused }
        return WatchTimerState.running
    }

    public func withSequence(_ sequence: Int) -> WatchTimerRecord {
        WatchTimerRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            kind: kind,
            startedAt: startedAt,
            pausedAt: pausedAt,
            stoppedAt: stoppedAt,
            accumulatedPauseMs: accumulatedPauseMs,
            plannedDurationMs: plannedDurationMs,
            sequence: sequence
        )
    }

    /// The protocol's `timer` object for this record.
    public func toTimerJson() -> [String: Any] {
        var json: [String: Any] = [
            "kind": kind,
            "state": state,
            "startedAt": utcIso(startedAt),
            "accumulatedPauseMs": accumulatedPauseMs,
        ]
        if let pausedAt { json["pausedAt"] = utcIso(pausedAt) }
        if let stoppedAt { json["stoppedAt"] = utcIso(stoppedAt) }
        // A rest is a count-up (docs/global_conventions.md, rest rule): a row
        // written before that had a length still stores one, and the wire
        // refuses it, so the frame never carries it.
        if kind != "rest", let plannedDurationMs {
            json["plannedDurationMs"] = plannedDurationMs
        }
        return json
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.timerType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "kind": kind,
            "startedAt": utcIso(startedAt),
            "pausedAt": pausedAt.map(utcIso) ?? NSNull(),
            "stoppedAt": stoppedAt.map(utcIso) ?? NSNull(),
            "accumulatedPauseMs": accumulatedPauseMs,
            "plannedDurationMs": plannedDurationMs ?? NSNull(),
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchTimerRecord {
        WatchTimerRecord(
            recordId: try requiredString(json, "recordId"),
            sessionId: try requiredString(json, "sessionId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            kind: try requiredString(json, "kind"),
            startedAt: try parseUtcIso(json["startedAt"]),
            pausedAt: try parseOptionalUtcIso(json["pausedAt"]),
            stoppedAt: try parseOptionalUtcIso(json["stoppedAt"]),
            accumulatedPauseMs: (json["accumulatedPauseMs"] as? NSNumber)?.intValue ?? 0,
            plannedDurationMs: (json["plannedDurationMs"] as? NSNumber)?.intValue,
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}

// MARK: - Confirmation

/// The phone's receipt for observations it has already recorded. Appended
/// rather than written onto the observation row: the watch has to remember what
/// it may drop across a relaunch without rewriting a synced record.
public struct WatchConfirmationRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int
    public let observationIds: [String]

    public init(
        recordId: String,
        sessionId: String,
        recordedAt: Date,
        observationIds: [String],
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = sessionId
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.observationIds = observationIds
    }

    public var confirmedAt: Date { recordedAt }

    public func withSequence(_ sequence: Int) -> WatchConfirmationRecord {
        WatchConfirmationRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            observationIds: observationIds,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.confirmationType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "observationIds": observationIds,
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchConfirmationRecord {
        WatchConfirmationRecord(
            recordId: try requiredString(json, "recordId"),
            sessionId: try requiredString(json, "sessionId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            observationIds: (json["observationIds"] as? [String]) ?? [],
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}

// MARK: - Sensor sample

/// One reading a platform sensor produced during a session.
///
/// Samples are records like any other: appended once, never rewritten, and read
/// back by `WatchSessionEngine.sensorSamples` after a relaunch. A reading is
/// therefore a fact with a timestamp, not a value held in memory — the watch can
/// be killed mid-run and the distance it had measured is still there.
///
/// Nothing here is emitted to the phone as a message of its own. The distance a
/// session covers travels as the `distanceMeters` of the effort that was logged,
/// which is the protocol's own field, so the phone needs no new message type and
/// no second source of truth for how far the user went.
public struct WatchSensorSampleRecord {
    public let recordId: String
    public let sessionId: String
    public let recordedAt: Date
    public let sequence: Int

    /// One of `WatchSensorKind`. `value`'s unit follows from it.
    public let kind: String

    /// Beats per minute, cumulative metres, or the settled total — see
    /// `WatchSensorKind`.
    public let value: Double

    public init(
        recordId: String,
        sessionId: String,
        recordedAt: Date,
        kind: String,
        value: Double,
        sequence: Int = 0
    ) {
        self.recordId = recordId
        self.sessionId = sessionId
        self.recordedAt = recordedAt
        self.kind = kind
        self.value = value
        self.sequence = sequence
    }

    /// The record id for a reading of `kind` taken at `at`.
    ///
    /// Derived rather than random so that a reading delivered twice — a replay,
    /// a duplicate callback from the sensor — is the same row and not a second
    /// one.
    public static func sampleId(sessionId: String, kind: String, at: Date) -> String {
        "sen-\(sessionId)-\(kind)-\(Int((at.timeIntervalSince1970 * 1000).rounded()))"
    }

    public func withSequence(_ sequence: Int) -> WatchSensorSampleRecord {
        WatchSensorSampleRecord(
            recordId: recordId,
            sessionId: sessionId,
            recordedAt: recordedAt,
            kind: kind,
            value: value,
            sequence: sequence
        )
    }

    public func toJson() -> [String: Any] {
        [
            "recordType": StoredWatchRecord.sensorSampleType,
            "recordId": recordId,
            "sessionId": sessionId,
            "recordedAt": utcIso(recordedAt),
            "sequence": sequence,
            "kind": kind,
            "value": value,
        ]
    }

    public static func fromJson(_ json: [String: Any]) throws -> WatchSensorSampleRecord {
        WatchSensorSampleRecord(
            recordId: try requiredString(json, "recordId"),
            sessionId: try requiredString(json, "sessionId"),
            recordedAt: try parseUtcIso(json["recordedAt"]),
            kind: try requiredString(json, "kind"),
            value: (json["value"] as? NSNumber)?.doubleValue ?? 0,
            sequence: (json["sequence"] as? NSNumber)?.intValue ?? 0
        )
    }
}

// MARK: - Stored record
/// What the store accepts and returns. One shape for every family, so the store
/// has exactly one mutation entry point.
public enum StoredWatchRecord {
    public static let sessionType = "session"
    public static let observationType = "observation"
    public static let timerType = "timer"
    public static let sensorSampleType = "sensor_sample"
    public static let confirmationType = "confirmation"
    public static let routineCatalogType = "routine_catalog"
    public static let foodCatalogType = "food_catalog"
    public static let preferencesType = "preferences"
    public static let ratingPromptType = "rating_prompt"

    case session(WatchSessionRecord)
    case observation(WatchObservationRecord)
    case timer(WatchTimerRecord)
    case sensorSample(WatchSensorSampleRecord)
    case confirmation(WatchConfirmationRecord)
    case routineCatalog(WatchRoutineCatalogRecord)
    case foodCatalog(WatchFoodCatalogRecord)
    case preferences(WatchPreferencesRecord)
    case ratingPrompt(WatchRatingPromptRecord)

    public var recordType: String {
        switch self {
        case .session: return Self.sessionType
        case .observation: return Self.observationType
        case .timer: return Self.timerType
        case .sensorSample: return Self.sensorSampleType
        case .confirmation: return Self.confirmationType
        case .routineCatalog: return Self.routineCatalogType
        case .foodCatalog: return Self.foodCatalogType
        case .preferences: return Self.preferencesType
        case .ratingPrompt: return Self.ratingPromptType
        }
    }

    public var recordId: String {
        switch self {
        case .session(let row): return row.recordId
        case .observation(let row): return row.recordId
        case .timer(let row): return row.recordId
        case .sensorSample(let row): return row.recordId
        case .confirmation(let row): return row.recordId
        case .routineCatalog(let row): return row.recordId
        case .foodCatalog(let row): return row.recordId
        case .preferences(let row): return row.recordId
        case .ratingPrompt(let row): return row.recordId
        }
    }

    public var sessionId: String {
        switch self {
        case .session(let row): return row.sessionId
        case .observation(let row): return row.sessionId
        case .timer(let row): return row.sessionId
        case .sensorSample(let row): return row.sessionId
        case .confirmation(let row): return row.sessionId
        case .routineCatalog(let row): return row.sessionId
        case .foodCatalog(let row): return row.sessionId
        case .preferences(let row): return row.sessionId
        case .ratingPrompt(let row): return row.sessionId
        }
    }

    public var recordedAt: Date {
        switch self {
        case .session(let row): return row.recordedAt
        case .observation(let row): return row.recordedAt
        case .timer(let row): return row.recordedAt
        case .sensorSample(let row): return row.recordedAt
        case .confirmation(let row): return row.recordedAt
        case .routineCatalog(let row): return row.recordedAt
        case .foodCatalog(let row): return row.recordedAt
        case .preferences(let row): return row.recordedAt
        case .ratingPrompt(let row): return row.recordedAt
        }
    }

    public var sequence: Int {
        switch self {
        case .session(let row): return row.sequence
        case .observation(let row): return row.sequence
        case .timer(let row): return row.sequence
        case .sensorSample(let row): return row.sequence
        case .confirmation(let row): return row.sequence
        case .routineCatalog(let row): return row.sequence
        case .foodCatalog(let row): return row.sequence
        case .preferences(let row): return row.sequence
        case .ratingPrompt(let row): return row.sequence
        }
    }

    public func withSequence(_ sequence: Int) -> StoredWatchRecord {
        switch self {
        case .session(let row): return .session(row.withSequence(sequence))
        case .observation(let row): return .observation(row.withSequence(sequence))
        case .timer(let row): return .timer(row.withSequence(sequence))
        case .sensorSample(let row): return .sensorSample(row.withSequence(sequence))
        case .confirmation(let row): return .confirmation(row.withSequence(sequence))
        case .routineCatalog(let row): return .routineCatalog(row.withSequence(sequence))
        case .foodCatalog(let row): return .foodCatalog(row.withSequence(sequence))
        case .preferences(let row): return .preferences(row.withSequence(sequence))
        case .ratingPrompt(let row): return .ratingPrompt(row.withSequence(sequence))
        }
    }

    public func toJson() -> [String: Any] {
        switch self {
        case .session(let row): return row.toJson()
        case .observation(let row): return row.toJson()
        case .timer(let row): return row.toJson()
        case .sensorSample(let row): return row.toJson()
        case .confirmation(let row): return row.toJson()
        case .routineCatalog(let row): return row.toJson()
        case .foodCatalog(let row): return row.toJson()
        case .preferences(let row): return row.toJson()
        case .ratingPrompt(let row): return row.toJson()
        }
    }

    public static func fromJson(_ json: [String: Any]) throws -> StoredWatchRecord {
        guard let type = json["recordType"] as? String else {
            throw WatchRecordError.malformed("record has no recordType")
        }
        switch type {
        case sessionType: return .session(try WatchSessionRecord.fromJson(json))
        case observationType: return .observation(try WatchObservationRecord.fromJson(json))
        case timerType: return .timer(try WatchTimerRecord.fromJson(json))
        case sensorSampleType: return .sensorSample(try WatchSensorSampleRecord.fromJson(json))
        case confirmationType: return .confirmation(try WatchConfirmationRecord.fromJson(json))
        case routineCatalogType: return .routineCatalog(try WatchRoutineCatalogRecord.fromJson(json))
        case foodCatalogType: return .foodCatalog(try WatchFoodCatalogRecord.fromJson(json))
        case preferencesType: return .preferences(try WatchPreferencesRecord.fromJson(json))
        case ratingPromptType: return .ratingPrompt(try WatchRatingPromptRecord.fromJson(json))
        default: throw WatchRecordError.unknownRecordType(type)
        }
    }
}

func requiredString(_ json: [String: Any], _ key: String) throws -> String {
    guard let value = json[key] as? String else {
        throw WatchRecordError.malformed("field \"\(key)\" is missing")
    }
    return value
}
