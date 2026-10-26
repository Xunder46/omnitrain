//
//  WatchDistanceTracker.swift
//  WatchSessionEngine
//
//  The wrist's own distance: raw location fixes in, a monotonic total out.
//
//  Plan: `docs/plans/2026-10-10-19e-watch-distance-tracking-plan/2026-10-10-19e-watch-distance-tracking-plan.md`,
//  scenarios S-3200…S-3205 (D-2201, D-2202).
//
//  One rule shapes this type: a fix is either accepted or ignored, never
//  corrected. A wrist watch reports positions it cannot honour — an 80 m
//  accuracy in a doorway, a 5 km hop between two cell towers, the same instant
//  twice — and the honest answer is to leave the total where it was. The total
//  therefore never decreases, and every gate below is a reason to add nothing.
//
//  The numbers are tuning values, not promises: the owner's on-wrist run is the
//  calibration. They are named here so the tests and the QA step talk about the
//  same constants.
//

import Foundation

/// One location fix as the platform hands it over, before any judgement.
///
/// The platform's own cumulative distance is deliberately not carried: the
/// wrist computes it, so a fix is raw input and never a running total already
/// decided elsewhere.
public struct WatchRawFix: Equatable {
    public let latitude: Double
    public let longitude: Double

    /// Metres: how wrong the platform thinks this fix may be. Zero is a perfect
    /// fix, and the floor it sets for movement scales with it.
    public let horizontalAccuracyMeters: Double

    public let timestamp: Date

    /// Metres above sea level, as the platform gave it; nil when the source does not say.
    public let altitudeMeters: Double?
    /// Vertical accuracy in metres; a negative value means the altitude is not valid (platform convention, passed through).
    public let verticalAccuracyMeters: Double?
    /// Metres per second; negative means invalid (passed through).
    public let speedMetersPerSecond: Double?
    /// Degrees from true north; negative means invalid (passed through).
    public let courseDegrees: Double?

    public init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double,
        timestamp: Date,
        altitudeMeters: Double? = nil,
        verticalAccuracyMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        courseDegrees: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.timestamp = timestamp
        self.altitudeMeters = altitudeMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.courseDegrees = courseDegrees
    }
}

/// Turns raw fixes into the one number a training session needs: metres covered
/// so far.
public struct WatchDistanceTracker {
    /// A fix the platform is less sure of than this is refused outright.
    public static let maxAccuracyMeters = 30.0

    /// Metres per second above which a step is a jump, not a person: a sprinting
    /// cyclist manages about 12 m/s, so 20 leaves room without accepting a
    /// tower handover.
    public static let maxSpeedMetersPerSecond = 20.0

    /// The least a wrist has to move before it counts. A still wrist drifts a
    /// metre or two, and without a floor a two-hour session accumulates hours of
    /// standing still.
    public static let movementFloorMeters = 2.0

    /// The mean radius the great-circle step is measured over.
    public static let earthRadiusMeters = 6_371_008.8

    /// Metres covered since the tracker was made. Only ever grows.
    public private(set) var totalMeters: Double = 0

    /// The last fix that was accepted — what the next one is measured from.
    private var reference: WatchRawFix?

    public init() {}

    /// Takes one raw fix, and returns the new total when the fix added to it.
    ///
    /// Returns nil when the fix adds nothing: it is the origin, the platform is
    /// unsure of it, it is not newer than the last accepted one, it arrived too
    /// fast to be a person, or the wrist did not move far enough for the reading
    /// to mean anything.
    public mutating func accept(_ fix: WatchRawFix) -> WatchLocationFix? {
        guard fix.latitude.isFinite,
              fix.longitude.isFinite,
              fix.horizontalAccuracyMeters.isFinite,
              fix.horizontalAccuracyMeters >= 0,
              fix.horizontalAccuracyMeters <= Self.maxAccuracyMeters
        else { return nil }

        guard let last = reference else {
            reference = fix
            return nil
        }

        let elapsed = fix.timestamp.timeIntervalSince(last.timestamp)
        guard elapsed > 0 else { return nil }

        let distance = Self.meters(from: last, to: fix)
        guard distance / elapsed <= Self.maxSpeedMetersPerSecond else { return nil }

        // The floor scales with the fix's own accuracy: a metre of drift on a
        // 10 m fix is noise, while a slow creep of 2.2 m on a 3 m fix is real.
        guard distance >= max(Self.movementFloorMeters, 0.5 * fix.horizontalAccuracyMeters)
        else { return nil }

        totalMeters += distance
        reference = fix
        return WatchLocationFix(distanceMeters: totalMeters)
    }

    /// Great-circle metres between two fixes (haversine). The route keeper
    /// (plan 68) reuses this one formula; there is no second one.
    static func meters(from origin: WatchRawFix, to fix: WatchRawFix) -> Double {
        let radians = Double.pi / 180
        let latitude1 = origin.latitude * radians
        let latitude2 = fix.latitude * radians
        let deltaLatitude = latitude2 - latitude1
        let deltaLongitude = (fix.longitude - origin.longitude) * radians

        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)

        return 2 * earthRadiusMeters * asin(min(1, sqrt(a)))
    }
}
