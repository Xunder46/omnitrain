//
//  WatchMetricStepping.swift
//  WatchSessionEngine
//
//  Metric stepping for the watch logging surfaces. Mirrors
//  `lib/watch/logging/watch_metric_stepping.dart` value for value, so a crown
//  turn means the same thing on the native client as it does on the Flutter
//  one — which is what the plan's parity criterion asks for.
//
//  Values are canonical (reps, kilograms, seconds, metres) and converted for
//  display through the same conversion constants `UnitFormatter` uses on the
//  phone side.
//

import Foundation

/// The metric keys a logging surface can edit, matching the phone's
/// `MetricIds.keyToMetricId` vocabulary.
public enum WatchMetricKey {
    public static let reps = "reps"
    public static let weight = "weight"
    public static let duration = "duration"
    public static let distance = "distance"
    public static let rounds = "rounds"
    public static let roundDuration = "round-duration"
    public static let extraWeight = "extra-weight"

    /// Extra load is a hold's companion metric: the phone's `EffortDefaults`
    /// gives a drill duration plus optional extra weight.
    public static let all = [reps, weight, duration, distance, rounds, roundDuration, extraWeight]
}

/// The units a logging surface is set to. Weight and distance are the two
/// preferences that change what a detent means.
public struct WatchUnitPreferences: Equatable {
    public let weightUnit: String
    public let distanceUnit: String

    public init(weightUnit: String = "kg", distanceUnit: String = "km") {
        self.weightUnit = weightUnit
        self.distanceUnit = distanceUnit
    }

    public var isPounds: Bool { weightUnit.lowercased().trimmingCharacters(in: .whitespaces) == "lbs" }
    public var isMiles: Bool {
        let unit = distanceUnit.lowercased().trimmingCharacters(in: .whitespaces)
        return unit == "miles" || unit == "mile" || unit == "mi"
    }
}

/// What one rotary detent does, per metric.
public enum WatchMetricStepping {
    /// Points of crown travel that count as one detent on every wrist surface.
    /// A Digital Crown detent and a Wear OS rotary notch both arrive as a scroll
    /// or a drag, and the Flutter surface accumulates against the same number.
    public static let pointsPerDetent: Double = 32

    /// Load moves in the saved increment: 2.5 kg, or the 5 lb plate the user
    /// thinks in — converted once here, so the display reads exactly 5 lb.
    public static let kilogramsPerDetent = 2.5
    public static let poundsPerDetent = 5.0

    /// Duration moves in five-second steps, the granularity the phone uses for
    /// timed and held work.
    public static let secondsPerDetent = 5.0

    /// Distance moves in a tenth of the display unit.
    public static let tenthsOfDistanceUnitPerDetent = 0.1

    /// Counts move by one.
    public static let countPerDetent = 1.0

    /// The lowest canonical load the wire carries, in kilograms — a band or
    /// partner assist. Mirrors `envelope.schema.json` `$defs.entry.loadKg` and
    /// the phone's `WireLimits.minLoadKg` (D-58/D-59); a value below it is
    /// refused by the schema, so the dial must not produce one.
    public static let minimumLoadKg: Double = -200

    /// Mirrors `UnitFormatter`'s conversion constants.
    public static let kilogramsPerPound = 2.20462
    public static let kilometresPerMile = 0.621371

    /// Canonical kilograms for a weight expressed in `unit` — the mirror of
    /// `UnitFormatter.toKilograms`.
    public static func toKilograms(_ value: Double, unit: String) -> Double {
        unit.lowercased().trimmingCharacters(in: .whitespaces) == "lbs"
            ? value / kilogramsPerPound
            : value
    }

    /// Canonical kilograms as the display value for `unit` — the mirror of
    /// `UnitFormatter.fromKilograms`.
    public static func fromKilograms(_ kilograms: Double, unit: String) -> Double {
        unit.lowercased().trimmingCharacters(in: .whitespaces) == "lbs"
            ? kilograms * kilogramsPerPound
            : kilograms
    }

    /// Metres in one display unit of distance — the mirror of
    /// `UnitFormatter.metresPerUnit`.
    public static func metresPerUnit(_ unit: String) -> Double {
        let normalized = unit.lowercased().trimmingCharacters(in: .whitespaces)
        let isMiles = normalized == "miles" || normalized == "mile" || normalized == "mi"
        return isMiles ? 1000 / kilometresPerMile : 1000
    }

    /// The canonical change one detent applies to `metricKey`.
    public static func step(
        for metricKey: String,
        units: WatchUnitPreferences = WatchUnitPreferences()
    ) -> Double {
        switch metricKey {
        case WatchMetricKey.reps, WatchMetricKey.rounds:
            return countPerDetent
        case WatchMetricKey.weight, WatchMetricKey.extraWeight:
            return toKilograms(
                units.isPounds ? poundsPerDetent : kilogramsPerDetent,
                unit: units.isPounds ? "lbs" : "kg"
            )
        case WatchMetricKey.duration, WatchMetricKey.roundDuration:
            return secondsPerDetent
        case WatchMetricKey.distance:
            return tenthsOfDistanceUnitPerDetent * metresPerUnit(units.distanceUnit)
        default:
            return 0
        }
    }

    /// `value` after `detents` rotations of the crown — positive is clockwise.
    public static func adjust(
        _ value: Double,
        metricKey: String,
        detents: Double,
        units: WatchUnitPreferences = WatchUnitPreferences()
    ) -> Double {
        clamp(quantize(value + detents * step(for: metricKey, units: units)), metricKey: metricKey)
    }

    /// Holds `value` inside the range the metric's own semantics allow: counts
    /// start at one, load is floored at the wire's own `-200 kg` (band assist,
    /// D-58/D-62), distance never goes negative, and extra load is signed
    /// because negative is band assist.
    public static func clamp(_ value: Double, metricKey: String) -> Double {
        switch metricKey {
        case WatchMetricKey.reps, WatchMetricKey.rounds:
            return value < countPerDetent ? countPerDetent : value
        case WatchMetricKey.extraWeight:
            return value
        case WatchMetricKey.weight:
            return value < minimumLoadKg ? minimumLoadKg : value
        case WatchMetricKey.duration, WatchMetricKey.distance,
             WatchMetricKey.roundDuration:
            return value < 0 ? 0 : value
        default:
            return value
        }
    }

    /// Keeps repeated stepping from leaving float dust behind: a tenth of a
    /// millimetre of precision is not a value anyone entered.
    private static func quantize(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}
