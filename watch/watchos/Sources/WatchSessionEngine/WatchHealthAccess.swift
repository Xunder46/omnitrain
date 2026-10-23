//
//  WatchHealthAccess.swift
//  WatchSessionEngine
//
//  What the wrist knows about Health access before a workout, and the copy the
//  surfaces show when it is off.
//
//  Plan: `docs/plans/2026-10-23-59-health-and-location-access-plan/2026-10-23-59-health-and-location-access-plan.md`,
//  decisions D-2 and D-3, scenarios S-8904..S-8907.
//

import Foundation

/// What the wrist knows about Health access before a workout (plan 59, D-3).
public enum WatchHealthAccess: Equatable {
    case unknown, allowed, off, unavailable

    /// The workout-share permission is what the wrist can read; Apple does not
    /// say whether a read permission (heart rate) was refused.
    public static func answer(available: Bool, granted: Bool) -> WatchHealthAccess {
        guard available else { return .unavailable }
        return granted ? .allowed : .off
    }
}

public enum WatchHealthAccessCopy {
    public static let offLine = "Health access is off. Turn it on in Health on your iPhone."
}

public enum WatchSensorNoticeCopy {
    public static let noHeartRate = "No heart rate, Health access is off"
    public static let noDistance = "No distance, Location access is off"
}
