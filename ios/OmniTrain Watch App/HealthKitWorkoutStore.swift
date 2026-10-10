//
//  HealthKitWorkoutStore.swift
//  OmniTrain Watch App
//
//  The wrist's real workout registration: `HKWorkoutSession` +
//  `HKLiveWorkoutBuilder` behind the package's `WatchPlatformWorkoutStore` seam.
//
//  Plan: `docs/plans/2026-10-10-19c-watch-keep-alive-plan/2026-10-10-19c-watch-keep-alive-plan.md`,
//  D-1502, D-1503 and D-1509. Every rule about *when* a workout opens or closes
//  lives in the package, where `swift test` exercises it on macOS
//  (`WatchWorkoutCoordinatorTests`). What is left here is the platform call
//  itself, so this file is the one part of the keep-alive no desktop test can
//  reach: the app target has no test target and `HKWorkoutActivityType` does not
//  exist on macOS. What the off-device suite can hold is the one thing drift
//  would break — the set of activity names this store answers to — and
//  `WatchWorkoutStoreSourceTests.testS1509TheStoreMapsEveryContractActivityName`
//  does exactly that.
//
//  Two rules shape this file:
//
//  1. **It never throws and never leaves a workout open by accident.** Every
//     failure — no health data, a refused permission, a thrown call — is
//     swallowed, and the store ends up with nothing registered. A workout the
//     user did not ask for is worse than none: the session's logging, its
//     timers and its sync never depend on this file (S-1505).
//  2. **The name table is not here.** Which modality registers as which name is
//     `WatchActivityTypes.byModality` in the package; this store only turns a
//     name into a type, so the two clients cannot disagree about a modality.
//

#if os(watchOS)

import Foundation
import HealthKit
import WatchSessionEngine

/// `HKHealthStore`, as the seam `WatchPlatformWorkoutStore` expects.
///
/// One health store for the life of the app, and one workout at a time — that is
/// what the platform grants, so `end()` needs no identifier. The session and its
/// builder are kept because ending a workout takes both, including one recovered
/// from a previous process.
final class HealthKitWorkoutStore: WatchPlatformWorkoutStore {
    private let healthStore = HKHealthStore()

    /// The workout this process opened, or the one it recovered. nil when the
    /// watch has nothing registered.
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Whether the one authorization request this process is allowed has already
    /// happened, and what it decided. The prompt is asked for on the first
    /// session that is about to open a workout and never at launch, so a user
    /// who never trains is never asked (D-1503).
    private var authorizationResolved = false
    private var authorizationGranted = false

    init() {}

    // MARK: - WatchPlatformWorkoutStore

    func begin(_ activityType: String) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard await resolveAuthorization() else { return }

        // The platform grants one workout at a time; a second begin replaces the
        // first rather than leaving two open.
        if session != nil { await end() }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: activityType)
        configuration.locationType = .unknown

        do {
            let opened = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let collection = opened.associatedWorkoutBuilder()
            collection.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            session = opened
            builder = collection

            opened.startActivity(with: Date())
            try await collection.beginCollection(at: Date())
        } catch {
            // Nothing is left registered: a session that started but whose
            // collection did not is a workout the user cannot see.
            session?.end()
            session = nil
            builder = nil
        }
    }

    func end() async {
        guard let openSession = session else { return }
        let openBuilder = builder
        session = nil
        builder = nil

        openSession.end()

        guard let openBuilder else { return }
        do {
            try await openBuilder.endCollection(at: Date())
            _ = try await openBuilder.finishWorkout()
        } catch {
            // The session is already closed, which is the part that matters: a
            // saved workout is a bonus, a workout left open is a lie.
        }
    }

    func inProgressActivityTypes() async -> [String] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        do {
            guard let recovered = try await healthStore.recoverActiveWorkoutSession() else {
                return []
            }

            // Held, not just reported: the coordinator ends it through `end()`,
            // and that takes the session and its builder.
            session = recovered
            builder = recovered.associatedWorkoutBuilder()

            return [Self.name(for: recovered.workoutConfiguration.activityType)]
        } catch {
            return []
        }
    }

    // MARK: - The mapping

    /// The activity type a contract name registers as (D-1509).
    ///
    /// The labels are exactly the distinct `watchos` names in
    /// `watch/contract/watch_sensor_contract.json`, and anything else lands on
    /// the generic type: a workout with the wrong type is one the user can
    /// correct, no workout at all loses the session's runtime priority and its
    /// heart-rate stream with it.
    static func activityType(for name: String) -> HKWorkoutActivityType {
        switch name {
        case "running": return .running
        case "traditionalStrengthTraining": return .traditionalStrengthTraining
        case "flexibility": return .flexibility
        case "crossTraining": return .crossTraining
        case "other": return .other
        default: return .other
        }
    }

    /// The reverse of `activityType(for:)`, for a workout this process did not
    /// open. Switches on the type rather than on names, so the store keeps one
    /// name table and not two.
    static func name(for activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running: return "running"
        case .traditionalStrengthTraining: return "traditionalStrengthTraining"
        case .flexibility: return "flexibility"
        case .crossTraining: return "crossTraining"
        default: return "other"
        }
    }

    // MARK: - Authorization

    /// Asks for permission the first time a workout is about to open, and answers
    /// the same way for the life of the process afterwards (D-1503).
    ///
    /// Share only the workout type; nothing is read. A refusal, or a request that
    /// cannot be answered, means `begin` does nothing — the session keeps running
    /// without a workout, exactly as it does when the phone denies a sync.
    private func resolveAuthorization() async -> Bool {
        if authorizationResolved { return authorizationGranted }
        authorizationResolved = true

        do {
            try await healthStore.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: []
            )
            authorizationGranted =
                healthStore.authorizationStatus(for: HKObjectType.workoutType())
                == .sharingAuthorized
        } catch {
            authorizationGranted = false
        }

        return authorizationGranted
    }
}

#endif