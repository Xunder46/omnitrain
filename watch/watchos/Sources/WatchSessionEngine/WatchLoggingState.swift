//
//  WatchLoggingState.swift
//  WatchSessionEngine
//
//  The value screen's state: the effort the session is on, the values the user
//  has dialled in, and the observation that comes out of confirming them.
//  Mirrors `lib/watch/logging/watch_logging_state.dart` behaviour for
//  behaviour, so both watch clients log the same event from the same taps.
//
//  Everything the view shows is derived — from the slot the engine is on, the
//  observations already logged against it, and the timers it is running. The
//  only thing held in memory is an edit the user has made but not yet
//  confirmed, which is not data yet: a kill mid-turn costs a turn, never an
//  entry. The event this builds is the protocol's `observations_up` event
//  verbatim, so confirming goes straight to the engine's `appendObservation`
//  with nothing translated in between.
//

import Foundation

/// What the views fall back on before the phone's prescription arrives.
public enum WatchLoggingDefaults {
    /// Length of the rest countdown after a set. A routine's per-effort rest
    /// supersedes it once the prescription reaches the watch.
    public static let restSeconds = 90

    /// Mirrors `WorkoutConstants.defaultRoundDurationSecs`.
    public static let roundDurationSeconds = 180
}

/// The effort kinds a value screen can be, in the protocol's vocabulary. A hold
/// is a `drill` to the data layer and a `hold` on the wire.
public enum WatchEffortKind {
    public static let set = "set"
    public static let timed = "timed"
    public static let round = "round"
    public static let drill = "drill"

    /// The `observations_up` event a surface of this kind emits.
    public static func eventKind(_ effortKind: String) -> String {
        effortKind == drill ? "hold" : effortKind
    }
}

/// One adjustable value on a logging surface. `value` is canonical — the unit
/// the protocol and the store speak — while `displayValue` is what the wrist
/// prints, already converted through the mirrored `UnitFormatter` constants.
public struct WatchMetricField: Equatable {
    public let metricKey: String

    /// The phone's word for it, so the wrist never invents a synonym.
    public let label: String

    public let value: Double
    public let displayValue: String

    /// Canonical change per rotary detent.
    public let step: Double

    public let unitLabel: String

    public init(
        metricKey: String,
        label: String,
        value: Double,
        displayValue: String,
        step: Double,
        unitLabel: String
    ) {
        self.metricKey = metricKey
        self.label = label
        self.value = value
        self.displayValue = displayValue
        self.step = step
        self.unitLabel = unitLabel
    }
}

/// The value screen for the effort the session is currently on.
public final class WatchLoggingState {
    public let engine: WatchSessionEngine

    /// The saved unit preferences the wrist reads in.
    public let units: WatchUnitPreferences

    /// Rest countdown length after a set, in seconds.
    public let restSeconds: Int

    private let clock: () -> Date
    private let newId: () -> String

    /// Values the user has dialled in but not confirmed, by metric key. Cleared
    /// on confirm, at which point the values come back from the logged
    /// observation (for a set) or start fresh (for measured work).
    private var dialled: [String: Double] = [:]

    /// Which capability decides the effort kind, in the order that matters: an
    /// isometric exercise usually carries `time` as well, and it is still a
    /// hold. Mirrors `ModalityConfig.effortKindFromMetric`.
    private static let kindPrecedence = ["hold", "rounds", "reps", "sets", "load", "time", "distance"]

    /// The metrics each effort kind calls for, in the order the wrist reads
    /// them. Mirrors `EffortDefaults`' primary and secondary metrics.
    private static let metricKeysByKind: [String: [String]] = [
        WatchEffortKind.set: [WatchMetricKey.reps, WatchMetricKey.weight],
        WatchEffortKind.timed: [WatchMetricKey.duration, WatchMetricKey.distance],
        WatchEffortKind.round: [WatchMetricKey.rounds, WatchMetricKey.roundDuration],
        WatchEffortKind.drill: [WatchMetricKey.duration, WatchMetricKey.extraWeight],
    ]

    /// The starting values `EffortDefaults.getDefaultTargets` prescribes.
    private static let targetsByKind: [String: [String: Double]] = [
        WatchEffortKind.set: [WatchMetricKey.reps: 10, WatchMetricKey.weight: 0],
        WatchEffortKind.timed: [WatchMetricKey.duration: 0, WatchMetricKey.distance: 0],
        WatchEffortKind.round: [
            WatchMetricKey.rounds: 1,
            WatchMetricKey.roundDuration: Double(WatchLoggingDefaults.roundDurationSeconds),
        ],
        WatchEffortKind.drill: [WatchMetricKey.duration: 0, WatchMetricKey.extraWeight: 0],
    ]

    public init(
        engine: WatchSessionEngine,
        clock: @escaping () -> Date = { Date() },
        idFactory: @escaping () -> String = { UUID().uuidString },
        units: WatchUnitPreferences = WatchUnitPreferences(),
        restSeconds: Int = WatchLoggingDefaults.restSeconds
    ) {
        self.engine = engine
        self.clock = clock
        self.newId = idFactory
        self.units = units
        self.restSeconds = restSeconds
    }

    // MARK: - What the view is showing

    /// Whether there is an exercise in progress to log against.
    public var canLog: Bool { engine.session != nil && slot != nil }

    /// The name of the exercise being logged, when there is one.
    public var exerciseName: String? { slot?["name"] as? String }

    /// The current instant, read through this state's clock, so the view and
    /// the events it logs agree on the time.
    public func now() -> Date { clock() }

    /// The newest timer of `kind`, which is the one that applies.
    public func timer(for kind: String) -> WatchTimerRecord? { engine.timerFor(kind) }

    /// The effort kind the current exercise is, derived from its capabilities —
    /// the same way the phone decides, so the two agree without being told.
    public var effortKind: String {
        for capability in Self.kindPrecedence where capabilities.contains(capability) {
            return Self.effortKindFromMetric(capability)
        }
        return WatchEffortKind.set
    }

    /// Mirrors `ModalityConfig.effortKindFromMetric`.
    private static func effortKindFromMetric(_ metric: String) -> String {
        switch metric {
        case "time", "distance": return WatchEffortKind.timed
        case "hold": return WatchEffortKind.drill
        case "rounds": return WatchEffortKind.round
        default: return WatchEffortKind.set
        }
    }

    /// The word this modality uses for a round, exactly as the phone says it
    /// (S-008). Mirrors `ModalityDisplay.getRoundsLabel`.
    public var roundsLabel: String {
        switch engine.session?.modality {
        case "sports": return "Periods"
        case "cardio_endurance": return "Intervals"
        default: return "Rounds"
        }
    }

    /// The number the next round will carry.
    public var nextRoundNumber: Int {
        var highest = 0
        for observation in observations where observation.payload["kind"] as? String == "round" {
            if let number = observation.payload["roundNumber"] as? Int, number > highest {
                highest = number
            }
        }
        return highest + 1
    }

    /// The adjustable values for the current effort, in the order the wrist
    /// reads them. Empty when there is no exercise to log against.
    public var fields: [WatchMetricField] {
        guard canLog else { return [] }
        return metricKeys.map(field(for:))
    }

    /// The current session's observations for the exercise being shown.
    private var observations: [WatchObservationRecord] {
        guard let slotId = slot?["sessionExerciseId"] as? String else { return [] }
        return engine.observations.filter {
            $0.payload["sessionExerciseId"] as? String == slotId
        }
    }

    private var slot: [String: Any]? { engine.currentExercise }

    private var capabilities: [String] {
        (slot?["capabilities"] as? [String]) ?? []
    }

    /// The metrics the effort kind calls for, minus the ones the exercise
    /// cannot fill: a bodyweight movement has no load row, a run that covers no
    /// distance has no distance row.
    ///
    /// Extra load is the exception: `EffortDefaults` gives a drill its
    /// extra-weight row whether or not the exercise carries `load`, because
    /// band assist is assistance rather than load.
    private var metricKeys: [String] {
        let prescribed = Self.metricKeysByKind[effortKind] ?? []
        return prescribed.filter { metricKey in
            switch capability(for: metricKey) {
            case let capability?: return capabilities.contains(capability)
            case nil: return true
            }
        }
    }

    /// The capability a metric depends on, or nil when it can always be offered.
    private func capability(for metricKey: String) -> String? {
        switch metricKey {
        case WatchMetricKey.weight: return "load"
        case WatchMetricKey.distance: return "distance"
        default: return nil
        }
    }

    private func field(for metricKey: String) -> WatchMetricField {
        let value = dialled[metricKey] ?? initialValue(for: metricKey)
        return WatchMetricField(
            metricKey: metricKey,
            label: label(for: metricKey),
            value: value,
            displayValue: displayValue(for: metricKey, value: value),
            step: WatchMetricStepping.step(for: metricKey, units: units),
            unitLabel: unitLabel(for: metricKey)
        )
    }

    /// Where a value starts: what was logged last for this exercise, or what
    /// the effort kind prescribes when nothing has been.
    private func initialValue(for metricKey: String) -> Double {
        switch metricKey {
        case WatchMetricKey.rounds:
            return Double(nextRoundNumber)
        case WatchMetricKey.roundDuration:
            guard let planned = engine.timerFor(WatchTimerKind.round)?.plannedDurationMs else {
                return target(for: metricKey)
            }
            return Double(planned) / 1000
        case WatchMetricKey.duration, WatchMetricKey.distance:
            // Measured work starts empty: the next run or ride is timed from
            // zero (S-002). A hold is prescribed rather than measured, so it
            // carries the length of the last one over.
            if effortKind == WatchEffortKind.timed { return 0 }
            return lastLogged(metricKey) ?? target(for: metricKey)
        default:
            return lastLogged(metricKey) ?? target(for: metricKey)
        }
    }

    /// What the previous effort of this kind logged for `metricKey`, or nil
    /// when this is the first.
    private func lastLogged(_ metricKey: String) -> Double? {
        for observation in observations.reversed() {
            guard observation.payload["kind"] as? String == eventKind else { continue }
            if let value = value(in: observation.payload, for: metricKey) { return value }
        }
        return nil
    }

    /// The protocol field `metricKey` lives in, read back as canonical units.
    private func value(in event: [String: Any], for metricKey: String) -> Double? {
        if metricKey == WatchMetricKey.duration { return durationSeconds(in: event) }

        guard let field = protocolField(for: metricKey) else { return nil }
        switch event[field] {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let number as NSNumber: return number.doubleValue
        default: return nil
        }
    }

    /// A timed or held entry's length, which the protocol carries as a window
    /// rather than as a number.
    private func durationSeconds(in event: [String: Any]) -> Double? {
        guard let started = event["startedAt"] as? String,
              let ended = event["endedAt"] as? String,
              let startedAt = parseIso(started),
              let endedAt = parseIso(ended)
        else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    private func parseIso(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: text) { return parsed }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// The starting value `EffortDefaults` prescribes for `metricKey`.
    private func target(for metricKey: String) -> Double {
        Self.targetsByKind[effortKind]?[metricKey] ?? 0
    }

    private func label(for metricKey: String) -> String {
        switch metricKey {
        case WatchMetricKey.reps: return "Reps"
        case WatchMetricKey.weight: return "Load"
        case WatchMetricKey.duration:
            return effortKind == WatchEffortKind.drill ? "Hold Time" : "Duration"
        case WatchMetricKey.distance: return "Distance"
        case WatchMetricKey.rounds: return roundsLabel
        case WatchMetricKey.roundDuration: return "Round length"
        case WatchMetricKey.extraWeight: return "Extra load"
        default: return metricKey
        }
    }

    private func unitLabel(for metricKey: String) -> String {
        switch metricKey {
        case WatchMetricKey.weight, WatchMetricKey.extraWeight:
            return units.isPounds ? "lbs" : "kg"
        case WatchMetricKey.distance:
            return units.isMiles ? "mi" : "km"
        default:
            return ""
        }
    }

    /// The value as the wrist prints it, in the saved unit.
    private func displayValue(for metricKey: String, value: Double) -> String {
        switch metricKey {
        case WatchMetricKey.reps, WatchMetricKey.rounds:
            return String(Int(value.rounded()))
        case WatchMetricKey.duration, WatchMetricKey.roundDuration:
            return Self.clock(value)
        case WatchMetricKey.weight, WatchMetricKey.extraWeight:
            let converted = WatchMetricStepping.fromKilograms(
                value,
                unit: units.isPounds ? "lbs" : "kg"
            )
            return String(format: "%.1f", converted)
        case WatchMetricKey.distance:
            let converted = value / WatchMetricStepping.metresPerUnit(units.distanceUnit)
            return String(format: "%.1f", converted)
        default:
            return String(value)
        }
    }

    /// Mirrors `OmniDateUtils.formatClock`: "m:ss", or "h:mm:ss" past the hour.
    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let remainder = total % 60
        let minutes = total / 60
        if minutes < 60 {
            return "\(minutes):\(String(format: "%02d", remainder))"
        }
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60)):\(String(format: "%02d", remainder))"
    }

    // MARK: - Input

    /// Applies `detents` rotary steps to `metricKey` — positive turns the value
    /// up. An unknown metric, or one the exercise does not carry, does nothing.
    public func adjust(_ metricKey: String, detents: Double) {
        guard let field = fields.first(where: { $0.metricKey == metricKey }) else { return }
        dialled[metricKey] = WatchMetricStepping.adjust(
            field.value,
            metricKey: metricKey,
            detents: detents,
            units: units
        )
    }

    // MARK: - Logging

    /// Confirms the effort: builds the protocol event, hands it to the engine,
    /// and starts whatever countdown the effort kind runs next.
    ///
    /// The event is stored before anything is emitted (the engine's contract),
    /// so a crash between the tap and the phone costs nothing.
    @discardableResult
    public func log(now instant: Date? = nil) async throws -> WatchObservationRecord {
        guard canLog, let slot else {
            throw WatchRecordError.malformed(
                "no exercise is in progress, so there is nothing to log"
            )
        }

        let loggedAt = instant ?? clock()
        let id = newId()
        var event: [String: Any] = [
            "entryId": id,
            "eventId": id,
            "kind": eventKind,
            "loggedAt": utcIso(loggedAt),
            "sessionExerciseId": slot["sessionExerciseId"] as? String ?? "",
            "exerciseId": slot["exerciseId"] as? String ?? "",
        ]
        for (field, value) in metricPayload(loggedAt: loggedAt) {
            event[field] = value
        }

        let stored = try await engine.appendObservation(event)
        dialled.removeAll()
        await startFollowOnTimer()
        return stored
    }

    private var eventKind: String { WatchEffortKind.eventKind(effortKind) }

    /// The metrics of the effort just logged, in the protocol's field names.
    private func metricPayload(loggedAt: Date) -> [String: Any] {
        switch effortKind {
        case WatchEffortKind.round:
            let window = roundWindow(loggedAt: loggedAt)
            return [
                "startedAt": utcIso(window.startedAt),
                "endedAt": utcIso(window.endedAt),
                "roundNumber": Int((value(of: WatchMetricKey.rounds) ?? Double(nextRoundNumber)).rounded()),
            ]
        case WatchEffortKind.set:
            let reps = Int((value(of: WatchMetricKey.reps) ?? 1).rounded())
            var payload: [String: Any] = ["reps": max(1, reps)]
            if let load = value(of: WatchMetricKey.weight), load > 0 { payload["loadKg"] = load }
            return payload
        case WatchEffortKind.timed:
            return windowPayload(loggedAt: loggedAt, coversDistance: true)
        default:
            // A drill: a held window, with the extra load the hold carried.
            var payload = windowPayload(loggedAt: loggedAt, coversDistance: false)
            if let extraLoad = value(of: WatchMetricKey.extraWeight), extraLoad != 0 {
                payload["extraLoadKg"] = extraLoad
            }
            return payload
        }
    }

    private func windowPayload(loggedAt: Date, coversDistance: Bool) -> [String: Any] {
        let duration = value(of: WatchMetricKey.duration) ?? 0
        var payload: [String: Any] = [
            "startedAt": utcIso(loggedAt.addingTimeInterval(-duration)),
            "endedAt": utcIso(loggedAt),
        ]
        if coversDistance, let covered = value(of: WatchMetricKey.distance), covered > 0 {
            payload["distanceMeters"] = covered
        }
        return payload
    }

    /// A round's window. The countdown is the round's clock: while one is
    /// running, the round started with it and — if it reached zero — ended with
    /// it, however long the user took to look down.
    private func roundWindow(loggedAt: Date) -> (startedAt: Date, endedAt: Date) {
        guard let countdown = engine.timerFor(WatchTimerKind.round) else {
            let length = value(of: WatchMetricKey.roundDuration) ?? 0
            return (loggedAt.addingTimeInterval(-length), loggedAt)
        }

        let completed = remainingMs(countdown, now: loggedAt) == 0
        return (
            countdown.startedAt,
            completed ? (completionInstant(countdown) ?? loggedAt) : loggedAt
        )
    }

    private func value(of metricKey: String) -> Double? {
        fields.first(where: { $0.metricKey == metricKey })?.value
    }

    /// The countdown the effort kind runs next: rest after a set, the next
    /// round after a round, nothing after work that is measured rather than
    /// prescribed.
    private func startFollowOnTimer() async {
        switch effortKind {
        case WatchEffortKind.set:
            _ = try? await engine.startTimer(
                WatchTimerKind.rest,
                plannedDurationMs: restSeconds * 1000
            )
        case WatchEffortKind.round:
            let length = value(of: WatchMetricKey.roundDuration) ?? 0
            _ = try? await engine.startTimer(
                WatchTimerKind.round,
                plannedDurationMs: Int((length * 1000).rounded())
            )
        default:
            return
        }
    }

    /// The protocol field a metric key travels in. Values the protocol carries
    /// as a window rather than a field have none.
    private func protocolField(for metricKey: String) -> String? {
        switch metricKey {
        case WatchMetricKey.reps: return "reps"
        case WatchMetricKey.weight: return "loadKg"
        case WatchMetricKey.extraWeight: return "extraLoadKg"
        case WatchMetricKey.distance: return "distanceMeters"
        case WatchMetricKey.rounds: return "roundNumber"
        default: return nil
        }
    }
}
