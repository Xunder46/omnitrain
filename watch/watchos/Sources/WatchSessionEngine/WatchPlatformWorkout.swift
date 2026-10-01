//
//  WatchPlatformWorkout.swift
//  WatchSessionEngine
//
//  The platform workout session: the watch telling the operating system that
//  training is happening. Mirrors `lib/watch/sensors/watch_platform_workout.dart`.
//
//  Plan: `docs/plans/2026-07-13-11-d-watch-sensor-recording-plan.md`,
//  scenarios S-001, S-002, S-005, S-007 and S-008.
//
//  Registering the session with the platform's health service is what unlocks
//  the rest: live heart rate, correct calorie and activity attribution in the
//  store, and — most importantly — the runtime priority that keeps a workout app
//  alive while the wrist is down. It is also why a session that ends must end its
//  workout: a workout left "in progress" by a kill is a lie the health store
//  keeps telling until something closes it.
//
//  The activity type table is shared with the Flutter client
//  (`watch/contract/watch_sensor_contract.json`), so both wrists register the
//  same thing.
//

import Foundation

/// The activity type one modality registers as, in each platform's own
/// vocabulary.
///
/// Two fields rather than one string, because the two platforms have never
/// agreed on a name for anything: watchOS speaks `HKWorkoutActivityType` and
/// Wear OS speaks Health Connect's `EXERCISE_TYPE_*`.
public struct WatchActivityType: Equatable {
    /// The `HKWorkoutActivityType` case, lower-camel.
    public let watchOs: String

    /// The Health Connect exercise type, lower-snake.
    public let wear: String

    public init(watchOs: String, wear: String) {
        self.watchOs = watchOs
        self.wear = wear
    }
}

/// The modality → platform workout type table.
///
/// Every seeded modality is named, including the older ones the phone's own
/// catalog no longer offers: a user's session started months ago still has to
/// open a workout of the right kind if it is replayed.
public enum WatchActivityTypes {
    /// What an unmapped modality registers as. A workout with the wrong type is
    /// a workout the user can correct; no workout at all loses the session, the
    /// runtime priority, and the heart-rate stream with it (S-007).
    public static let generic = WatchActivityType(
        watchOs: "other",
        wear: "exercise_type_other_workout"
    )

    public static let byModality: [String: WatchActivityType] = [
        "cardio_endurance": WatchActivityType(
            watchOs: "running",
            wear: "exercise_type_running"
        ),
        "resistance_lifting": WatchActivityType(
            watchOs: "traditionalStrengthTraining",
            wear: "exercise_type_strength_training"
        ),
        "isometric_stretching": WatchActivityType(
            watchOs: "flexibility",
            wear: "exercise_type_flexibility"
        ),
        "sports": generic,
        "strength_resistance": WatchActivityType(
            watchOs: "traditionalStrengthTraining",
            wear: "exercise_type_strength_training"
        ),
        "skill_technique": generic,
        "conditioning_mixed": WatchActivityType(
            watchOs: "crossTraining",
            wear: "exercise_type_cross_training"
        ),
        "mobility_flexibility": WatchActivityType(
            watchOs: "flexibility",
            wear: "exercise_type_flexibility"
        ),
        "recovery_rehab": WatchActivityType(
            watchOs: "flexibility",
            wear: "exercise_type_flexibility"
        ),
        "competition_match": generic,
    ]

    public static func forModality(_ modality: String?) -> WatchActivityType {
        guard let modality else { return generic }
        return byModality[modality] ?? generic
    }
}

/// Whether a session's modality calls for GPS.
///
/// The answer is read from the modality's capability profile and never from its
/// name: a lift and a run are told apart by what they can measure, so a modality
/// added tomorrow is handled without touching this file, and one that merely
/// *sounds* like distance work does not wake the radio (S-008).
///
/// The profile mirrors `ModalityConfig`, the phone's own owner of it, and the
/// suite checks it against the shared contract — so a change on either client
/// fails on both.
public enum WatchGpsPolicy {
    public static let distanceCapability = "distance"

    /// Primary plus secondary capabilities, per modality — the ones the modality
    /// *offers*. A capability it rules out (anti-capability) is absent here,
    /// which is the whole point.
    public static let capabilitiesByModality: [String: [String]] = [
        "cardio_endurance": ["time", "distance", "rounds"],
        "resistance_lifting": ["reps", "sets", "load", "time"],
        "isometric_stretching": ["hold", "time", "sets"],
        "sports": ["time", "rounds", "distance"],
        // The older modalities the catalog no longer offers: no distance, so no
        // GPS, and a generic workout type if one is ever replayed.
        "strength_resistance": ["reps", "sets", "load"],
        "skill_technique": ["time", "rounds"],
        "conditioning_mixed": ["time", "rounds", "load"],
        "mobility_flexibility": ["hold", "time"],
        "recovery_rehab": ["hold", "time"],
        "competition_match": ["time", "rounds"],
    ]

    /// True when `modality` can cover distance — as a capability it carries, not
    /// as one it rules out. Free training has no profile, so it never records
    /// GPS: the user picks the exercise after the session starts, too late to
    /// decide, and the distance row stays theirs to fill.
    public static func isRequired(_ modality: String?) -> Bool {
        guard let modality, let capabilities = capabilitiesByModality[modality] else {
            return false
        }
        return capabilities.contains(distanceCapability)
    }
}

/// The health service's own view of workouts: the OS-level surface, which is the
/// part that cannot be tested off-device.
///
/// Deliberately three calls and no state. The watch holds one workout at a time —
/// that is what the platform grants — so `end` needs no identifier, and
/// `inProgressActivityTypes` exists for exactly one purpose: finding out what a
/// previous process left running.
public protocol WatchPlatformWorkoutStore {
    func begin(_ activityType: String) async

    func end() async

    /// The activity types the health store still reports as in progress, oldest
    /// first. Anything here belongs to a process that is gone.
    func inProgressActivityTypes() async -> [String]
}

/// The watch's platform workout, over whatever store the platform provides.
public final class WatchPlatformWorkout {
    private let store: WatchPlatformWorkoutStore

    /// The workout currently registered, or nil when the watch has none open.
    public private(set) var running: WatchActivityType?

    public init(store: WatchPlatformWorkoutStore) {
        self.store = store
    }

    /// Registers `session`'s modality as a platform workout and returns what it
    /// was registered as.
    ///
    /// Starting a session while one is already open ends the old workout first:
    /// the platform grants one at a time, and a dangling one is exactly the
    /// stuck state recovery exists to clear.
    @discardableResult
    public func start(_ session: WatchSessionRecord) async -> WatchActivityType {
        if running != nil { await end() }

        let activityType = WatchActivityTypes.forModality(session.modality)
        await store.begin(activityType.watchOs)
        running = activityType
        return activityType
    }

    /// Closes the workout the watch opened, if any.
    public func end() async {
        guard running != nil else { return }
        await store.end()
        running = nil
    }

    /// Ends whatever the health store still reports as in progress and returns
    /// the activity types it closed.
    ///
    /// Run at launch. A kill cannot be caught, so the only reliable moment to
    /// notice an orphaned workout is the next start — and the honest thing to do
    /// with one is end it: the session it belonged to is already over as far as
    /// this process is concerned, and its logged entries are in storage
    /// regardless of whether the workout was open (S-005).
    @discardableResult
    public func recoverInProgress() async -> [String] {
        let stranded = await store.inProgressActivityTypes()
        var ended: [String] = []

        for activityType in stranded {
            await store.end()
            ended.append(activityType)
        }

        running = nil
        return ended
    }
}
