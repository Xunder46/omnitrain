//
//  SyncProtocolValidator.swift
//  WatchSessionEngine
//
//  Watch↔phone sync protocol conformance validator — the Swift half of the
//  reference implementation in `lib/core/sync_protocol/message_validator.dart`.
//
//  The protocol's schemas are the contract, and the fixtures in
//  `watch/sync_protocol/fixtures/` are how either watch client proves it speaks
//  them. This is a faithful port of the Dart validator — same dialect, same
//  rejection codes, same wording — so the fixture register can be run against
//  the native implementation and the two platforms are held to one standard
//  rather than two.
//
//  Schema documents are supplied by the caller, keyed the way `$ref` addresses
//  them: relative to `watch/sync_protocol/schemas/`. The validator itself does
//  no file access.
//

import Foundation

/// Machine-facing rejection codes. Documented one by one in PROTOCOL.md.
public enum SyncRejectionCode {
    public static let unsupportedProtocolVersion = "unsupported_protocol_version"
    public static let unknownMessageType = "unknown_message_type"
    public static let missingSchema = "missing_schema"
    public static let unresolvableReference = "unresolvable_reference"
    public static let missingRequiredField = "missing_required_field"
    public static let unexpectedField = "unexpected_field"
    public static let invalidType = "invalid_type"
    public static let invalidEnumValue = "invalid_enum_value"
    public static let invalidConstValue = "invalid_const_value"
    public static let constraintViolation = "constraint_violation"
    public static let noMatchingVariant = "no_matching_variant"
    public static let semanticViolation = "semantic_violation"
}

/// A single reason a message did not conform.
public struct SyncProtocolRejection: Equatable, CustomStringConvertible {
    public let code: String
    public let path: String
    public let message: String

    public var description: String { "\(code) at \(path): \(message)" }
}

public final class SyncProtocolValidator {
    public static let protocolVersion = 1

    public static let messageTypes = [
        "routines_down",
        "foods_down",
        "preferences_down",
        "exercise_push",
        "structure_change",
        "observations_up",
        "receipt",
        "session_lifecycle",
        "session_snapshot",
        "timer_state",
    ]

    public static let timerKinds = ["rest", "round", "hold", "elapsed"]

    /// Entry kinds that are not logged against a slot: a nutrition quick-log,
    /// and the two session-scoped kinds, which describe the whole session.
    private static let slotlessKinds: Set<String> = [
        "nutrition_quick_log",
        "effort_rating",
        "session_end",
    ]

    /// The entry kinds each capture field may travel on, in the order the
    /// semantic layer reports them. The wrist computes these values for the
    /// entries they describe and no other, so a field anywhere else is a
    /// sender defect (PROTOCOL.md, "Session capture").
    private static let captureFieldKinds: [(field: String, kinds: [String])] = [
        ("steps", ["timed"]),
        ("distanceSource", ["timed"]),
        ("avgHeartRateBpm", ["timed", "round", "hold", "session_end"]),
        ("maxHeartRateBpm", ["timed", "round", "hold", "session_end"]),
        ("pausedMs", ["round"]),
        ("setBlockHeartRates", ["session_end"]),
        ("rating", ["effort_rating"]),
        ("status", ["session_end"]),
        ("modality", ["session_end"]),
    ]

    /// Root of every message path, as a constant so `$` never needs escaping.
    private static let root = "$"

    private let documents: [String: [String: Any]]

    public init(schemaDocuments: [String: [String: Any]]) {
        documents = schemaDocuments
    }

    public func hasSchema(for messageType: String) -> Bool {
        documents[schemaPath(for: messageType)] != nil
    }

    /// The rejections for `envelope`, or an empty array when the receiver
    /// carries no schema set to judge with or the message conforms.
    ///
    /// A receiver that ships without the schemas cannot tell a conformant
    /// message from a malformed one, and a receiver that cannot read is not a
    /// receiver that should refuse. Every entry point gates incoming messages
    /// through here so none of them can answer that question differently.
    public static func incomingRejections(
        _ validator: SyncProtocolValidator?,
        _ envelope: [String: Any]
    ) -> [SyncProtocolRejection] {
        guard let validator else { return [] }

        let version = envelope["protocolVersion"]
        if (version as? NSNumber)?.intValue != protocolVersion {
            return [
                SyncProtocolRejection(
                    code: SyncRejectionCode.unsupportedProtocolVersion,
                    path: "$.protocolVersion",
                    message: "unsupported protocol version; the payload was not read"
                )
            ]
        }

        return validator.validateEnvelope(envelope)
    }

    /// Returns an empty array when `message` conforms to protocol v1.
    public func validateEnvelope(_ message: [String: Any]) -> [SyncProtocolRejection] {
        guard let type = message["type"] as? String,
              Self.messageTypes.contains(type)
        else {
            return [
                SyncProtocolRejection(
                    code: SyncRejectionCode.unknownMessageType,
                    path: "\(Self.root).type",
                    message: "\(describe(message["type"])) is not one of "
                        + jsonInline(Self.messageTypes)
                )
            ]
        }

        guard let schema = documents[schemaPath(for: type)] else {
            return [
                SyncProtocolRejection(
                    code: SyncRejectionCode.missingSchema,
                    path: "\(Self.root).type",
                    message: "no schema document for message type \(type)"
                )
            ]
        }

        let schemaRejections = validate(
            message,
            schema: schema,
            path: Self.root,
            document: schema
        )
        if !schemaRejections.isEmpty { return schemaRejections }

        // Shape is proven from here on, so the semantic layer may read the
        // payload without guards.
        return semanticRejections(message)
    }

    private func schemaPath(for messageType: String) -> String {
        "messages/\(messageType).schema.json"
    }

    // MARK: - Semantic layer — rules JSON Schema cannot express

    private func semanticRejections(_ message: [String: Any]) -> [SyncProtocolRejection] {
        let payload = message["payload"] as? [String: Any] ?? [:]
        switch message["type"] as? String {
        case "timer_state":
            let timers = payload["timers"] as? [String: Any] ?? [:]
            return timerKindRejections(timers) + restLengthRejections(timers)
        case "session_snapshot":
            let timers = payload["timers"] as? [String: Any] ?? [:]
            return snapshotRejections(payload) + restLengthRejections(timers)
        case "observations_up":
            return duplicateEventRejections(payload)
                + captureRejections(
                    payload["events"] as? [Any] ?? [],
                    path: "\(Self.root).payload.events"
                )
                + restWindowRejections(payload["events"] as? [Any] ?? [])
        case "receipt":
            return duplicateAcknowledgementRejections(payload)
        case "routines_down":
            return fallbackCoverageRejections(payload)
        default:
            return []
        }
    }

    /// A timer must declare the kind it is filed under.
    private func timerKindRejections(_ timers: [String: Any]) -> [SyncProtocolRejection] {
        var rejections: [SyncProtocolRejection] = []
        for kind in Self.timerKinds {
            guard let timer = timers[kind] as? [String: Any],
                  (timer["kind"] as? String) != kind
            else { continue }
            rejections.append(
                rejection(
                    SyncRejectionCode.semanticViolation,
                    "\(Self.root).payload.timers.\(kind).kind",
                    "timer '\(kind)' declares kind \(describe(timer["kind"]))"
                )
            )
        }
        return rejections
    }

    /// The one timer that never carries a planned length is the rest: rest is a
    /// count-up (`docs/global_conventions.md`, rest rule). A `timer_state` and
    /// a `session_snapshot` both carry `timers`, so both are held to this rule
    /// and a rest with a plan is never adopted into the wrist's own row
    /// (D-164, D-169).
    private func restLengthRejections(_ timers: [String: Any]) -> [SyncProtocolRejection] {
        guard let rest = timers["rest"] as? [String: Any],
              rest["plannedDurationMs"] != nil
        else { return [] }
        return [
            rejection(
                SyncRejectionCode.semanticViolation,
                "\(Self.root).payload.timers.rest.plannedDurationMs",
                "a rest has no planned length: rest is a count-up "
                    + "(docs/global_conventions.md, rest rule)"
            )
        ]
    }

    /// A rest is a window between two instants, so one that does not end after
    /// it starts is nothing to write: the wrist never builds one (D-166) and
    /// the phone drops such a row (S-323). An unparseable instant adds nothing
    /// here — the schema's `type` rule already reports it.
    private func restWindowRejections(_ events: [Any]) -> [SyncProtocolRejection] {
        var rejections: [SyncProtocolRejection] = []
        for (index, event) in events.enumerated() {
            guard let record = event as? [String: Any],
                  (record["kind"] as? String) == "rest",
                  let startedAt = try? parseUtcIso(record["startedAt"]),
                  let endedAt = try? parseUtcIso(record["endedAt"]),
                  endedAt <= startedAt
            else { continue }
            rejections.append(
                rejection(
                    SyncRejectionCode.semanticViolation,
                    "\(Self.root).payload.events[\(index)].endedAt",
                    "a rest must end after it starts: "
                        + "endedAt \(record["endedAt"] ?? "") is not after startedAt "
                        + "\(record["startedAt"] ?? "")"
                )
            )
        }
        return rejections
    }

    /// Position stays inside the exercise list, slots are unique, and workout
    /// entries name the slot they were logged against.
    private func snapshotRejections(_ payload: [String: Any]) -> [SyncProtocolRejection] {
        let exercises = payload["exercises"] as? [Any] ?? []
        let index = (payload["currentExerciseIndex"] as? NSNumber)?.intValue ?? 0

        var rejections: [SyncProtocolRejection] = []
        if exercises.isEmpty ? index != 0 : index >= exercises.count {
            rejections.append(
                rejection(
                    SyncRejectionCode.semanticViolation,
                    "\(Self.root).payload.currentExerciseIndex",
                    "currentExerciseIndex \(index) is out of range for "
                        + "\(exercises.count) exercises"
                )
            )
        }

        let entries = payload["entries"] as? [Any] ?? []
        rejections += duplicateSlotRejections(exercises)
        rejections += entryIdentityRejections(entries)
        rejections += captureRejections(entries, path: "\(Self.root).payload.entries")
        return rejections
    }

    /// A slot id addresses an exercise for the life of the session, so a
    /// snapshot that reuses one is ambiguous. The same `exerciseId` in two slots
    /// is legitimate and not reported.
    private func duplicateSlotRejections(_ exercises: [Any]) -> [SyncProtocolRejection] {
        var seen = Set<String>()
        var duplicates: [String] = []
        for exercise in exercises {
            guard let slotId = (exercise as? [String: Any])?["sessionExerciseId"] as? String
            else { continue }
            if !seen.insert(slotId).inserted { duplicates.append(slotId) }
        }
        guard !duplicates.isEmpty else { return [] }

        return [
            rejection(
                SyncRejectionCode.semanticViolation,
                "\(Self.root).payload.exercises",
                "every sessionExerciseId MUST be unique within a session; "
                    + "repeated \(duplicates.joined(separator: ", "))"
            )
        ]
    }

    /// A workout entry has to say both which exercise it recorded and which slot
    /// it logged in; a nutrition quick-log, an effort rating, and a session end
    /// are not tied to a slot at all.
    private func entryIdentityRejections(_ entries: [Any]) -> [SyncProtocolRejection] {
        var withoutIdentity: [String] = []
        for entry in entries {
            guard let record = entry as? [String: Any] else { continue }
            if Self.slotlessKinds.contains(record["kind"] as? String ?? "") { continue }
            if record["exerciseId"] == nil || record["sessionExerciseId"] == nil {
                withoutIdentity.append(record["entryId"] as? String ?? "?")
            }
        }
        guard !withoutIdentity.isEmpty else { return [] }

        return [
            rejection(
                SyncRejectionCode.semanticViolation,
                "\(Self.root).payload.entries",
                "a workout entry must name the exercise it logged and the slot "
                    + "it logged it in; missing on \(withoutIdentity.joined(separator: ", "))"
            )
        ]
    }

    /// The fields the wrist computes from its own readings, held to the rules
    /// the schema cannot state: each travels only on the kinds it describes,
    /// the heart-rate pair travels whole and in order, a round's pause fits
    /// inside its window, and a session end names each set block once.
    /// `observations_up` events and snapshot entries are the same entries, so
    /// both are held to it.
    private func captureRejections(_ entries: [Any], path: String) -> [SyncProtocolRejection] {
        var rejections: [SyncProtocolRejection] = []
        for (index, entry) in entries.enumerated() {
            guard let record = entry as? [String: Any] else { continue }
            let at = "\(path)[\(index)]"
            let kind = record["kind"] as? String ?? ""
            let entryId = record["entryId"] as? String ?? "?"

            for (field, kinds) in Self.captureFieldKinds
            where record[field] != nil && !kinds.contains(kind) {
                rejections.append(
                    rejection(
                        SyncRejectionCode.semanticViolation,
                        "\(at).\(field)",
                        "\(field) is carried only by \(kinds.joined(separator: ", ")) entries; "
                            + "\(entryId) is a \(kind) entry"
                    )
                )
            }

            rejections += heartRatePairRejections(record, path: at, where: entryId)
            rejections += distanceSourceRejections(record, path: at, entryId: entryId)
            rejections += pauseWindowRejections(record, path: at, entryId: entryId)
            rejections += blockHeartRateRejections(record, path: at, entryId: entryId)
        }
        return rejections
    }

    /// A source describes a distance, so one without the other says nothing
    /// about where a value came from that is not there.
    private func distanceSourceRejections(
        _ record: [String: Any],
        path: String,
        entryId: String
    ) -> [SyncProtocolRejection] {
        guard record["distanceSource"] != nil, record["distanceMeters"] == nil else { return [] }
        return [
            rejection(
                SyncRejectionCode.semanticViolation,
                "\(path).distanceSource",
                "distanceSource travels with distanceMeters; "
                    + "\(entryId) carries no distanceMeters"
            )
        ]
    }

    /// An average and a maximum describe the same readings, so one without the
    /// other is half a measurement, and an average above its maximum is not
    /// one.
    private func heartRatePairRejections(
        _ record: [String: Any],
        path: String,
        where subject: String
    ) -> [SyncProtocolRejection] {
        let average = numericValue(record["avgHeartRateBpm"])
        let maximum = numericValue(record["maxHeartRateBpm"])
        if record["avgHeartRateBpm"] == nil && record["maxHeartRateBpm"] == nil { return [] }
        guard let average, let maximum else {
            let present = record["avgHeartRateBpm"] == nil ? "maxHeartRateBpm" : "avgHeartRateBpm"
            return [
                rejection(
                    SyncRejectionCode.semanticViolation,
                    path,
                    "avgHeartRateBpm and maxHeartRateBpm travel together; "
                        + "\(subject) carries only \(present)"
                )
            ]
        }
        guard average > maximum else { return [] }
        return [
            rejection(
                SyncRejectionCode.semanticViolation,
                "\(path).avgHeartRateBpm",
                "avgHeartRateBpm must not exceed maxHeartRateBpm, but does on \(subject)"
            )
        ]
    }

    /// A round cannot have been paused for longer than it lasted.
    private func pauseWindowRejections(
        _ record: [String: Any],
        path: String,
        entryId: String
    ) -> [SyncProtocolRejection] {
        guard let pausedMs = numericValue(record["pausedMs"]),
              let startedAt = try? parseUtcIso(record["startedAt"]),
              let endedAt = try? parseUtcIso(record["endedAt"])
        else { return [] }

        // Whole milliseconds, as the wire writes them: the rounding absorbs the
        // binary noise a `Date` difference carries.
        let windowMs = (endedAt.timeIntervalSince(startedAt) * 1000).rounded()
        guard pausedMs > windowMs else { return [] }
        return [
            rejection(
                SyncRejectionCode.semanticViolation,
                "\(path).pausedMs",
                "pausedMs must not exceed the time between startedAt and endedAt, "
                    + "but does on \(entryId)"
            )
        ]
    }

    /// A set block is every set logged for one slot and exercise, so a session
    /// end names each block once, and each block's pair is a measurement.
    private func blockHeartRateRejections(
        _ record: [String: Any],
        path: String,
        entryId: String
    ) -> [SyncProtocolRejection] {
        guard let blocks = record["setBlockHeartRates"] as? [Any] else { return [] }

        var rejections: [SyncProtocolRejection] = []
        var seen = Set<String>()
        var repeated: [String] = []
        for (index, item) in blocks.enumerated() {
            guard let block = item as? [String: Any] else { continue }
            let key = "\(block["sessionExerciseId"] as? String ?? "?")/"
                + "\(block["exerciseId"] as? String ?? "?")"
            if !seen.insert(key).inserted { repeated.append(key) }
            rejections += heartRatePairRejections(
                block,
                path: "\(path).setBlockHeartRates[\(index)]",
                where: "\(entryId) set block \(key)"
            )
        }
        if !repeated.isEmpty {
            rejections.append(
                rejection(
                    SyncRejectionCode.semanticViolation,
                    "\(path).setBlockHeartRates",
                    "a set block may appear once per sessionExerciseId and "
                        + "exerciseId pair; repeated \(repeated.joined(separator: ", ")) on \(entryId)"
                )
            )
        }
        return rejections
    }

    /// One eventId may appear once per message — the idempotency key has to mean
    /// something inside a batch too.
    private func duplicateEventRejections(_ payload: [String: Any]) -> [SyncProtocolRejection] {
        var seen = Set<String>()
        var duplicates: [String] = []
        for event in payload["events"] as? [Any] ?? [] {
            guard let eventId = (event as? [String: Any])?["eventId"] as? String
            else { continue }
            if !seen.insert(eventId).inserted { duplicates.append(eventId) }
        }
        guard !duplicates.isEmpty else { return [] }

        return [
            rejection(
                SyncRejectionCode.semanticViolation,
                "\(Self.root).payload.events",
                "the same eventId appears twice: \(duplicates.joined(separator: ", "))"
            )
        ]
    }

    /// One entry may be acknowledged once per receipt — the same id twice says
    /// nothing more the second time, and a sender that does it is confused about
    /// what it holds.
    private func duplicateAcknowledgementRejections(_ payload: [String: Any]) -> [SyncProtocolRejection] {
        var seen = Set<String>()
        var duplicates: [String] = []
        for entryId in payload["entryIds"] as? [Any] ?? [] {
            guard let entryId = entryId as? String else { continue }
            if !seen.insert(entryId).inserted { duplicates.append(entryId) }
        }
        guard !duplicates.isEmpty else { return [] }

        return [
            rejection(
                SyncRejectionCode.semanticViolation,
                "\(Self.root).payload.entryIds",
                "the same entryId appears twice: \(duplicates.joined(separator: ", "))"
            )
        ]
    }

    /// Every exercise a routine references must be in the fallback list, or the
    /// watch can hold a routine it cannot log.
    private func fallbackCoverageRejections(_ payload: [String: Any]) -> [SyncProtocolRejection] {
        let listed = Set(
            (payload["fallbackExercises"] as? [Any] ?? [])
                .compactMap { ($0 as? [String: Any])?["exerciseId"] as? String }
        )

        var missing: [String] = []
        for routine in payload["routines"] as? [Any] ?? [] {
            let segments = (routine as? [String: Any])?["segments"] as? [Any] ?? []
            for segment in segments {
                let efforts = (segment as? [String: Any])?["efforts"] as? [Any] ?? []
                for effort in efforts {
                    guard let exerciseId = (effort as? [String: Any])?["exerciseId"] as? String
                    else { continue }
                    if !listed.contains(exerciseId) && !missing.contains(exerciseId) {
                        missing.append(exerciseId)
                    }
                }
            }
        }
        guard !missing.isEmpty else { return [] }

        return [
            rejection(
                SyncRejectionCode.semanticViolation,
                "\(Self.root).payload.fallbackExercises",
                "every exercise a routine references must be listed in "
                    + "fallbackExercises; missing \(missing.joined(separator: ", "))"
            )
        ]
    }

    // MARK: - Schema layer

    private func validate(
        _ value: Any?,
        schema: [String: Any],
        path: String,
        document: [String: Any]
    ) -> [SyncProtocolRejection] {
        if let reference = schema["$ref"] as? String {
            guard let resolved = resolve(reference, document: document) else {
                return [
                    rejection(
                        SyncRejectionCode.unresolvableReference,
                        path,
                        "the reference \(reference) cannot be resolved"
                    )
                ]
            }
            return validate(
                value,
                schema: resolved.schema,
                path: path,
                document: resolved.document
            )
        }

        if let expected = schema["type"] as? String, !matchesType(value, expected) {
            return [
                rejection(
                    SyncRejectionCode.invalidType,
                    path,
                    "expected \(expected), found \(describe(value))"
                )
            ]
        }

        var rejections: [SyncProtocolRejection] = []

        if let constant = schema["const"], !deepEquals(value, constant) {
            rejections.append(
                rejection(
                    SyncRejectionCode.invalidConstValue,
                    path,
                    "expected \(describe(constant)), found \(describe(value))"
                )
            )
        }

        if let allowed = schema["enum"] as? [Any],
           !allowed.contains(where: { deepEquals(value, $0) }) {
            rejections.append(
                rejection(
                    SyncRejectionCode.invalidEnumValue,
                    path,
                    "\(describe(value)) is not one of \(jsonInline(allowed))"
                )
            )
        }

        if let object = value as? [String: Any] {
            rejections += validateObject(object, schema: schema, path: path, document: document)
        } else if let array = value as? [Any] {
            rejections += validateArray(array, schema: schema, path: path, document: document)
        } else if let string = value as? String {
            rejections += validateString(string, schema: schema, path: path)
        } else if let number = numericValue(value) {
            rejections += validateNumber(number, schema: schema, path: path)
        }

        // Combinators run last so a value that is simply the wrong shape reports
        // that first, instead of a wall of branch failures.
        rejections += validateAllOf(
            value,
            branches: schema["allOf"],
            path: path,
            document: document
        )
        rejections += validateOneOf(
            value,
            branches: schema["oneOf"],
            path: path,
            document: document
        )

        return rejections
    }

    private func validateObject(
        _ object: [String: Any],
        schema: [String: Any],
        path: String,
        document: [String: Any]
    ) -> [SyncProtocolRejection] {
        var rejections: [SyncProtocolRejection] = []

        if let required = schema["required"] as? [String] {
            for name in required where object[name] == nil {
                rejections.append(
                    rejection(
                        SyncRejectionCode.missingRequiredField,
                        "\(path).\(name)",
                        "required field \"\(name)\" is missing"
                    )
                )
            }
        }

        guard let properties = schema["properties"] as? [String: Any] else {
            return rejections
        }

        for (name, childSchema) in properties {
            guard let child = childSchema as? [String: Any],
                  let value = object[name]
            else { continue }
            rejections += validate(
                value,
                schema: child,
                path: "\(path).\(name)",
                document: document
            )
        }

        if let additional = schema["additionalProperties"] as? Bool, additional == false {
            for key in object.keys where properties[key] == nil {
                rejections.append(
                    rejection(
                        SyncRejectionCode.unexpectedField,
                        "\(path).\(key)",
                        "field \"\(key)\" is not defined by the schema"
                    )
                )
            }
        }

        return rejections
    }

    private func validateArray(
        _ array: [Any],
        schema: [String: Any],
        path: String,
        document: [String: Any]
    ) -> [SyncProtocolRejection] {
        var rejections: [SyncProtocolRejection] = []

        if let minItems = (schema["minItems"] as? NSNumber)?.intValue,
           array.count < minItems {
            rejections.append(
                constraint(path, "expected at least \(minItems) items, found \(array.count)")
            )
        }

        if let items = schema["items"] as? [String: Any] {
            for (index, value) in array.enumerated() {
                rejections += validate(
                    value,
                    schema: items,
                    path: "\(path)[\(index)]",
                    document: document
                )
            }
        }

        return rejections
    }

    private func validateString(
        _ value: String,
        schema: [String: Any],
        path: String
    ) -> [SyncProtocolRejection] {
        var rejections: [SyncProtocolRejection] = []

        if let minLength = (schema["minLength"] as? NSNumber)?.intValue,
           value.count < minLength {
            rejections.append(
                constraint(
                    path,
                    "expected at least \(minLength) characters, found \(value.count)"
                )
            )
        }

        if let pattern = schema["pattern"] as? String,
           !matches(pattern, value) {
            rejections.append(
                constraint(path, "\(describe(value)) does not match the required pattern")
            )
        }

        return rejections
    }

    private func validateNumber(
        _ value: Double,
        schema: [String: Any],
        path: String
    ) -> [SyncProtocolRejection] {
        var rejections: [SyncProtocolRejection] = []

        if let minimum = numericValue(schema["minimum"]), value < minimum {
            rejections.append(
                constraint(path, "expected at least \(trim(minimum)), found \(trim(value))")
            )
        }

        if let maximum = numericValue(schema["maximum"]), value > maximum {
            rejections.append(
                constraint(path, "expected at most \(trim(maximum)), found \(trim(value))")
            )
        }

        return rejections
    }

    private func validateAllOf(
        _ value: Any?,
        branches: Any?,
        path: String,
        document: [String: Any]
    ) -> [SyncProtocolRejection] {
        guard let branches = branches as? [Any] else { return [] }
        return branches.flatMap { branch -> [SyncProtocolRejection] in
            guard let schema = branch as? [String: Any] else { return [] }
            return validate(value, schema: schema, path: path, document: document)
        }
    }

    private func validateOneOf(
        _ value: Any?,
        branches: Any?,
        path: String,
        document: [String: Any]
    ) -> [SyncProtocolRejection] {
        guard let branches = branches as? [Any] else { return [] }

        var matches = 0
        var failures: [[SyncProtocolRejection]] = []
        for branch in branches {
            guard let schema = branch as? [String: Any] else { continue }
            let branchRejections = validate(
                value,
                schema: schema,
                path: path,
                document: document
            )
            if branchRejections.isEmpty {
                matches += 1
            } else {
                failures.append(branchRejections)
            }
        }
        if matches == 1 { return [] }

        let firstFailure = failures.first?.first
        let mismatch = firstFailure.map { " (first mismatch: \($0.message))" } ?? ""
        var rejections = [
            rejection(
                SyncRejectionCode.noMatchingVariant,
                path,
                "value matches \(matches) of \(branches.count) allowed shapes\(mismatch)"
            )
        ]

        // When nothing matched, the branch failures are the useful part: they
        // say which field was wrong, not just that the shape was.
        if matches == 0 {
            for failure in failures { rejections += failure }
        }

        return rejections
    }

    // MARK: - Reference resolution

    private func resolve(
        _ reference: String,
        document: [String: Any]
    ) -> (schema: [String: Any], document: [String: Any])? {
        let parts = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let documentName = parts.first.map(String.init) ?? ""
        let pointer = parts.count > 1 ? String(parts[1]) : ""

        var target = document
        if !documentName.isEmpty {
            guard let external = documents[documentName] else { return nil }
            target = external
        }

        var node: Any = target
        for token in pointer.split(separator: "/") {
            let key = token.replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            guard let object = node as? [String: Any], let child = object[key] else {
                return nil
            }
            node = child
        }

        guard let schema = node as? [String: Any] else { return nil }
        return (schema, target)
    }

    // MARK: - Primitives

    private func rejection(
        _ code: String,
        _ path: String,
        _ message: String
    ) -> SyncProtocolRejection {
        SyncProtocolRejection(code: code, path: path, message: message)
    }

    private func constraint(_ path: String, _ message: String) -> SyncProtocolRejection {
        rejection(SyncRejectionCode.constraintViolation, path, message)
    }

    private func matches(_ pattern: String, _ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}

/// Whether `value` is a JSON boolean.
///
/// `value is Bool` cannot answer this: every `NSNumber` bridges to `Bool`, so a
/// parsed `1` would pass as `true` and a parsed `true` would pass as `1`. The
/// CoreFoundation type id is the only reliable discriminator.
func isBoolean(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}

/// A JSON number, or nil for anything else — including booleans, which bridge
/// to `NSNumber` and would otherwise pass as 0/1.
func numericValue(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
    return number.doubleValue
}

func matchesType(_ value: Any?, _ expected: String) -> Bool {
    switch expected {
    case "object": return value is [String: Any]
    case "array": return value is [Any]
    case "string": return value is String
    case "integer":
        // A JSON `3200.0` parses to a double, and the Dart validator's
        // `value is int` refuses it. `number == number.rounded()` alone would
        // take it, so a whole-number double would pass on the wrist and be
        // refused by the phone — the two validators must agree on the bytes
        // (F-10).
        guard let number = value as? NSNumber, !isBoolean(number) else { return false }
        return !CFNumberIsFloatType(number)
    case "number": return numericValue(value) != nil
    case "boolean": return isBoolean(value)
    case "null": return value == nil || value is NSNull
    default: return true
    }
}

func deepEquals(_ lhs: Any?, _ rhs: Any?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case (let left as [String: Any], let right as [String: Any]):
        guard left.count == right.count else { return false }
        return left.allSatisfy { key, value in
            guard let other = right[key] else { return false }
            return deepEquals(value, other)
        }
    case (let left as [Any], let right as [Any]):
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { deepEquals($0, $1) }
    case (let left as String, let right as String):
        return left == right
    case (let left as Bool, let right as Bool):
        return left == right
    default:
        guard let left = numericValue(lhs), let right = numericValue(rhs) else {
            return false
        }
        return left == right
    }
}

func describe(_ value: Any?) -> String {
    switch value {
    case nil: return "nothing"
    case is NSNull: return "null"
    case let text as String: return "\"\(text)\""
    case let array as [Any]: return "a list of \(array.count)"
    case let object as [String: Any]: return "an object with \(object.count) fields"
    case let number as NSNumber:
        if isBoolean(number) { return number.boolValue ? "true" : "false" }
        // A float-typed number keeps its fraction, as the Dart validator's
        // `jsonEncode` renders it: a JSON `3200.0` reads back as `3200.0` on
        // both stacks, so a refusal quotes the bytes that arrived (F-10, N6).
        return CFNumberIsFloatType(number)
            ? String(number.doubleValue)
            : trim(number.doubleValue)
    default: return "\(value!)"
    }
}

func jsonInline(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value),
          let text = String(data: data, encoding: .utf8)
    else { return "\(value)" }
    return text
}

/// `1.0` prints as `1`, matching the Dart validator's number rendering.
func trim(_ value: Double) -> String {
    value == value.rounded() && abs(value) < 1e15
        ? String(Int(value))
        : String(value)
}
