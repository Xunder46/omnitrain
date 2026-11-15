//
//  HealthKitWorkoutStore.swift
//  OmniTrain Watch App
//
//  The wrist's real workout registration: `HKWorkoutSession` +
//  `HKLiveWorkoutBuilder` behind the package's `WatchPlatformWorkoutStore` seam.
//
//  Plans: `docs/plans/2026-10-10-19c-watch-keep-alive-plan/2026-10-10-19c-watch-keep-alive-plan.md`
//  (D-1502, D-1503 and D-1509), and
//  `docs/plans/2026-10-10-19d-watch-heart-rate-and-steps-plan/2026-10-10-19d-watch-heart-rate-and-steps-plan.md`
//  (D-2103 to D-2105: this store now reads heart rate and steps, turns its
//  builder into a collecting one, and owns the `HealthKitSensorFeed` that hands
//  those readings to the package), and
//  `docs/plans/2026-10-23-58-health-workout-type-and-calories-plan/2026-10-23-58-health-workout-type-and-calories-plan.md`
//  (D-5: the store also shares and reads active energy, so the workout saves its
//  calories and the Move ring counts them), and
//  `docs/plans/2026-10-24-68-run-route-map-plan/2026-10-24-68-run-route-map-plan.md`
//  (plan 68: the store also records the Health route of an outdoor run through
//  `HealthKitRouteRecorder`; the route never decides the workout's save), and
//  `docs/plans/2026-11-14-168-health-walk-type-and-relaunch-plan/2026-11-14-168-health-walk-type-and-relaunch-plan.md`
//  (plan 168 D-16804, D-16805: the save outcome and a held-session discard are
//  noted in the diagnostics log, and the store collects and shares walking and
//  running distance). Every rule about *when* a workout opens or closes
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

    /// Feeds the Health route of an outdoor run (plan 68); nothing in the session depends on it.
    private let routeRecorder = HealthKitRouteRecorder()

    /// True while the workout held is one recovered from a previous process (D-9).
    private var recoveredSession = false

    /// A recovered workout this store held because it was not live when
    /// `adoptInProgress` reached it (plan 140): its name is answered once, by
    /// `inProgressActivityTypes`, without asking Health a second time.
    private var pendingRecoveryName: String?

    /// Whether the last `begin` failed at the platform (plan 82 D-1). A guard
    /// that returns early because Health is unavailable or access is off is not
    /// a failure, so it is set only in the `catch`.
    var lastBeginFailed = false

    /// The one authorization request this process is allowed, from the moment it
    /// starts until the process ends. The prompt is asked for on the first
    /// session that is about to open a workout and never at launch, so a user
    /// who never trains is never asked (D-1503). Concurrent callers — `begin`
    /// and the feed's closure — await the same task rather than reading a
    /// half-settled answer.
    private var authorization: Task<Bool, Never>?

    /// The location adapter the feed delegates to (D-2304): the app builds it
    /// over the CoreLocation source and this store only hands it along, so the
    /// permission question and the fixes never pass through here.
    private let location: WatchTrackedLocation

    /// Where the workout's outcome is recorded (plan 168 D-16804); nil records
    /// nothing.
    private let diagnostics: WatchDiagnosticsLog?

    /// The live readings of the workout this store opens (D-2103). Built on
    /// first use, over a closure that asks this store for its authorization
    /// outcome: the feed holds no reference back to the store, and the store is
    /// the only thing holding the feed.
    private lazy var sensorFeed = HealthKitSensorFeed(authorization: { [weak self] in
        guard let self else { return false }
        return await self.resolveAuthorization()
    }, location: location)

    /// The sensor seam the package sees. Permission comes from the store's own
    /// resolution, so the feed reports it without asking anyone (D-2104, D-2105).
    var sensorSource: WatchSensorSource { sensorFeed }

    /// The location adapter arrives from the host, which builds it on the main
    /// actor over a `CLLocationManager` that must be created there (D-2303,
    /// D-2305).
    ///
    /// The diagnostics log is the package's own (plan 168 D-16804), so a save
    /// outcome and a held-session discard are visible in the wrist's log rather
    /// than swallowed here.
    init(location: WatchTrackedLocation, diagnostics: WatchDiagnosticsLog?) {
        self.location = location
        self.diagnostics = diagnostics
    }

    /// The store of a host that holds no log: `nil` records nothing, the rule
    /// every optional log in the app follows (plan 142 D-14202).
    convenience init(location: WatchTrackedLocation) {
        self.init(location: location, diagnostics: nil)
    }

    // MARK: - WatchPlatformWorkoutStore

    /// Registers the session's workout, and tells HealthKit whether it is an
    /// outdoor one: a modality that measures distance registers as `.outdoor`,
    /// every other one as before (D-2304).
    func begin(_ activityType: String, outdoors: Bool) async {
        lastBeginFailed = false
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard await resolveAuthorization() else { return }

        // The platform grants one workout at a time; a second begin replaces the
        // first rather than leaving two open, and discards it: its session's end
        // is not known here (plan 89 D-2). Ending a workout this store was still
        // holding loses everything it collected, so the discard is logged
        // (plan 168 D-16804): this is the statement that destroyed the first 25
        // minutes of the owner's walk.
        if let held = session {
            diagnostics?.note(
                "workout_end",
                detail: "discarded_held \(Self.name(for: held.workoutConfiguration.activityType))"
            )
            await end(saving: false)
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: activityType)
        configuration.locationType = outdoors ? .outdoor : .unknown

        do {
            let opened = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let collection = opened.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            // The data source only collects the types it was told to — heart
            // rate, steps and active energy — and the delegate is what turns its
            // callbacks into the package's streams (D-2103, D-2105, D-5).
            dataSource.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)
            dataSource.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
            dataSource.enableCollection(for: HKQuantityType(.activeEnergyBurned), predicate: nil)
            // Walking and running distance, so a walk or run Health agrees with
            // exists carries its distance (plan 168 D-16805).
            dataSource.enableCollection(
                for: HKQuantityType(.distanceWalkingRunning),
                predicate: nil
            )

            collection.dataSource = dataSource
            collection.delegate = sensorFeed
            // The feed reads this builder on its own tick and on activation, so
            // a beat whose callback was missed while the app was suspended still
            // becomes a reading (D-3108, D-3113).
            sensorFeed.refreshHeartRate(from: collection)

            session = opened
            builder = collection

            let startDate = Date()
            opened.startActivity(with: startDate)
            try await collection.beginCollection(at: startDate)

            recoveredSession = false
            openRoute(on: collection, startedAt: startDate)
        } catch {
            // Nothing is left registered: a session that started but whose
            // collection did not is a workout the user cannot see.
            lastBeginFailed = true
            session?.end()
            session = nil
            builder = nil
        }
    }

    /// The indoor answer, for a caller that does not know the modality: it
    /// registers exactly as it did before, through HealthKit's own default
    /// (D-2304).
    func begin(_ activityType: String) async {
        await begin(activityType, outdoors: false)
    }

    /// Opens the route for every workout while route sharing is allowed (plan 76 D-1) and points the location
    /// adapter at the recorder (plan 68 D-2): no second subscription, no permission question. Route sharing is
    /// read here, per workout; the route is kept at close only when it covers 50 m or more.
    private func openRoute(
        on collection: HKLiveWorkoutBuilder,
        startedAt: Date
    ) {
        let sharing = healthStore.authorizationStatus(for: HKSeriesType.workoutRoute()) == .sharingAuthorized
        guard routeRecorder.open(
            on: collection,
            routeSharingAllowed: sharing,
            beganAt: startedAt
        ) else { return }
        location.observeFixes { [routeRecorder] fix in routeRecorder.offer(fix) }
    }

    /// Closes the workout: saved to Health when `saving`, otherwise discarded so
    /// an abandoned or removed session leaves nothing in Fitness (plan 89 D-1).
    /// The sensor stops either way.
    func end(saving: Bool) async {
        // The feed stops reading the builder this store is about to finish,
        // whatever else `end` does: a tick over a closed builder is a stranded
        // reading (D-3113).
        sensorFeed.refreshHeartRate(from: nil)

        guard let openSession = session else { return }
        let openBuilder = builder
        let wasRecovered = recoveredSession
        session = nil
        builder = nil
        recoveredSession = false
        pendingRecoveryName = nil

        // The route closes before the workout does (plan 68 D-6): no point is handed to Health after this.
        let route = routeRecorder.close()
        // A recovered workout's route builder is asked for before the workout is finished (D-9).
        let recoveredRoute = wasRecovered
            ? openBuilder.flatMap { routeRecorder.recoveredBuilder(from: $0) }
            : nil

        openSession.end()

        guard let openBuilder else {
            await routeRecorder.finish(route, workout: nil)
            return
        }
        var saved: HKWorkout?
        if saving {
            let name = Self.name(for: openSession.workoutConfiguration.activityType)
            do {
                try await openBuilder.endCollection(at: Date())
                saved = try await openBuilder.finishWorkout()
                diagnostics?.note("workout_saved", detail: name)
            } catch {
                // The session is already closed, which is the part that matters: a
                // saved workout is a bonus, a workout left open is a lie. The
                // failure is still recorded, so a walk that never reached Health
                // says so (plan 168 D-16804).
                diagnostics?.note("workout_save_failed", detail: name)
            }
        } else {
            // Not saved (plan 89 D-1): the builder and its samples are dropped,
            // and `saved` stays nil, so both routes below are discarded too.
            try? await openBuilder.endCollection(at: Date())
            openBuilder.discardWorkout()
        }
        // The workout is saved first, then the route is finished with it (F-1).
        await routeRecorder.finish(route, workout: saved)
        await routeRecorder.finishRecovered(recoveredRoute, workout: saved)
    }

    /// Reads the workout's newest beat now, through the feed's one gate, so a
    /// beat whose callback arrived while the app was suspended becomes a
    /// reading when the user raises the wrist again (D-3108, D-3113). The
    /// builder is handed over rather than assumed: the feed reads the workout
    /// this store currently holds, and nothing at all once `end` cleared it.
    func refreshHeartRate() {
        sensorFeed.refreshHeartRate(from: builder)
        sensorFeed.refreshActiveEnergy(from: builder)
    }

    func inProgressActivityTypes() async -> [String] {
        if let name = pendingRecoveryName { pendingRecoveryName = nil; return [name] }
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        do {
            guard let recovered = try await healthStore.recoverActiveWorkoutSession() else {
                return []
            }

            // Held, not just reported: the coordinator ends it through `end()`,
            // and that takes the session and its builder.
            session = recovered
            builder = recovered.associatedWorkoutBuilder()
            recoveredSession = true

            return [Self.name(for: recovered.workoutConfiguration.activityType)]
        } catch {
            return []
        }
    }

    /// Takes over the workout a previous process left running so the session
    /// continues it (plan 140): the builder keeps its collected totals, the feed
    /// is pointed at it again, and nothing is saved or restarted. A recovered
    /// workout that is not live (stopped, ended, not started) is held for the
    /// ordinary recovery to close, and nil is answered.
    func adoptInProgress() async -> String? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }

        do {
            guard let recovered = try await healthStore.recoverActiveWorkoutSession() else {
                return nil
            }
            let collection = recovered.associatedWorkoutBuilder()
            let name = Self.name(for: recovered.workoutConfiguration.activityType)

            session = recovered
            builder = collection
            recoveredSession = true

            guard recovered.state == .running || recovered.state == .paused else {
                pendingRecoveryName = name
                return nil
            }

            collection.delegate = sensorFeed
            collection.dataSource?.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
            collection.dataSource?.enableCollection(for: HKQuantityType(.activeEnergyBurned), predicate: nil)
            sensorFeed.refreshHeartRate(from: collection)
            return name
        } catch {
            return nil
        }
    }

    // MARK: - The mapping

    /// The activity type a contract name registers as (D-1509).
    ///
    /// The labels are the distinct `watchos` names across the contract's
    /// `activityTypes` and `distanceActivityTypes` sections in
    /// `watch/contract/watch_sensor_contract.json`, and anything else lands on
    /// the generic type: a workout with the wrong type is one the user can
    /// correct, no workout at all loses the session's runtime priority and its
    /// heart-rate stream with it.
    static func activityType(for name: String) -> HKWorkoutActivityType {
        switch name {
        case "running": return .running
        case "cycling": return .cycling
        case "rowing": return .rowing
        case "walking": return .walking
        case "hiking": return .hiking
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
        case .cycling: return "cycling"
        case .rowing: return "rowing"
        case .walking: return "walking"
        case .hiking: return "hiking"
        case .traditionalStrengthTraining: return "traditionalStrengthTraining"
        case .flexibility: return "flexibility"
        case .crossTraining: return "crossTraining"
        default: return "other"
        }
    }

    // MARK: - Authorization

    /// Asks for Health access when the Start screen first shows and answers what
    /// the wrist can read (plan 59, D-5). It joins the one memoised request, so
    /// the feed's and `begin`'s asks never raise a second sheet; once the user has
    /// answered, the system asks nothing again.
    func requestAccess() async -> WatchHealthAccess {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        return WatchHealthAccess.answer(available: true, granted: await resolveAuthorization())
    }

    /// Asks for permission the first time a workout is about to open, and answers
    /// the same way for the life of the process afterwards (D-1503); the Start
    /// screen now asks first through `requestAccess`, and the first workout open
    /// still asks for a relaunch into a live session. Concurrent
    /// callers share that one in-flight request rather than each reading a
    /// half-settled answer.
    ///
    /// Share the workout type, active energy and walking/running distance, so
    /// the workout saves its calories and its distance (plan 58 D-5, plan 168
    /// D-16805), and the workout route, so an outdoor run saves its map (plan 68
    /// D-7); read heart rate, steps, active energy and that distance. The
    /// builder's statistics only carry the types asked for here, so a read left
    /// out is a stream that never produces anything (D-2103). A refusal, or a
    /// request that cannot be answered, means `begin` does nothing — the session
    /// keeps running without a workout, exactly as it does when the phone denies
    /// a sync.
    private func resolveAuthorization() async -> Bool {
        if let task = authorization { return await task.value }

        let task = Task<Bool, Never> {
            do {
                try await healthStore.requestAuthorization(
                    toShare: [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned),
                              HKQuantityType(.distanceWalkingRunning),
                              HKSeriesType.workoutRoute()],
                    read: [HKQuantityType(.heartRate), HKQuantityType(.stepCount),
                           HKQuantityType(.activeEnergyBurned),
                           HKQuantityType(.distanceWalkingRunning),
                           HKObjectType.workoutType(),
                           HKSeriesType.workoutRoute()]
                )
                return healthStore.authorizationStatus(for: HKObjectType.workoutType())
                    == .sharingAuthorized
            } catch {
                return false
            }
        }
        authorization = task
        return await task.value
    }
}

#endif