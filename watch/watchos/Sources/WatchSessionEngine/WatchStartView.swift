//
//  WatchStartView.swift
//  WatchSessionEngine
//
//  The native watchOS start surface: a synced routine, or a free workout.
//  Native half of
//  `docs/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`.
//
//  Another deliberate choice of the same kind `Package.swift` makes: the engine,
//  the store, the start paths and the fallback derivation are
//  platform-independent, so they build and test today with `swift test`. The view
//  is the one part that cannot be — SwiftUI lists and their presentation are
//  watchOS-only here — so it is compiled only into a watch target. What it
//  renders is the behaviour the tests cover.
//
//  Everything on this surface is already on the watch. The routine list is read
//  from local storage, so it renders with the phone off, in airplane mode, or
//  before the wrist has ever seen a radio — which is the point of syncing
//  proactively rather than at session start.
//

#if os(watchOS)

import SwiftUI

/// "The full catalog is a phone away" — shown only while the phone can actually
/// be reached, because it is a promise about a radio.
public struct WatchSearchOnPhoneHint: View {
    public static let label = "Search on phone"

    public init() {}

    public var body: some View {
        Label(Self.label, systemImage: "iphone")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// "The phone is not there" — said only once the radio has observed it
/// unreachable (D-8), so a cold start says nothing rather than something it has
/// not learned.
public struct WatchPhoneUnreachableHint: View {
    public static let label = WatchStartSurfaceCopy.unreachableLabel

    public init() {}

    public var body: some View {
        Label(Self.label, systemImage: "iphone.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// Where a session begins on the wrist, and what the user is handed when it
/// does: the session to log against, never a screen to find.
public struct WatchStartView: View {
    private let paths: WatchSessionStartPaths
    private let onSessionStarted: (WatchSessionRecord) -> Void

    /// Opens the quick-log surface. Nil leaves the button off the screen.
    ///
    /// Nutrition logging is independent of training sessions, so this sits on the
    /// home surface rather than behind a workout (S-006).
    private let onOpenNutrition: (() -> Void)?

    /// Asks the phone for the routines. Nil leaves the button off the screen —
    /// the app owns the transport, not this view.
    private let onRequestSync: (() -> Void)?

    /// What the radio last said about the phone. Unknown until the host has
    /// observed something, which is what keeps a cold start from claiming the
    /// phone is unreachable before anyone asked (D-8).
    private let phoneReachability: WatchPhoneReachability

    /// Bumped by the host on every arrival. The paths are a plain class that
    /// publishes nothing, so this is the value whose change re-runs the picker's
    /// body and makes it re-read the session it is showing.
    private let revision: Int

    /// Wrist-scale inset. The phone's spacing tokens are sized for a full-width
    /// screen; this surface carries its own value rather than scaling one down.
    private static let surfaceInset = 4.0

    /// The home surface's way into the quick-log, which is reachable with no
    /// workout running.
    public static let logFoodLabel = "Log food"

    /// The user's explicit action — recovering a device that was out of reach
    /// and refreshing the routine list.
    public static let syncLabel = WatchStartSurfaceCopy.syncLabel

    @State private var pickingExercise = false

    public init(
        paths: WatchSessionStartPaths,
        onSessionStarted: @escaping (WatchSessionRecord) -> Void,
        onOpenNutrition: (() -> Void)? = nil,
        onRequestSync: (() -> Void)? = nil,
        phoneReachability: WatchPhoneReachability = .unknown,
        revision: Int = 0
    ) {
        self.paths = paths
        self.onSessionStarted = onSessionStarted
        self.onOpenNutrition = onOpenNutrition
        self.onRequestSync = onRequestSync
        self.phoneReachability = phoneReachability
        self.revision = revision
    }

    /// What this surface says about the phone, from the one rule that decides it
    /// (D-8, D-9).
    private var phoneStatus: WatchPhoneStatus {
        WatchPhoneStatus(reachability: phoneReachability)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Self.surfaceInset) {
                if paths.routines.isEmpty {
                    Text("No routines yet. Sync with your phone to get them.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                } else {
                    ForEach(paths.routines, id: \.routineId) { routine in
                        Button(routine.name) {
                            Task { await start(routine) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Button("Free workout") {
                    Task { await startFreeWorkout() }
                }
                .buttonStyle(.bordered)

                if let onRequestSync, phoneStatus.offersSync {
                    Button(Self.syncLabel, action: onRequestSync)
                        .buttonStyle(.bordered)
                }

                // D-8: said only once the radio has observed it.
                if phoneStatus.sentence != nil { WatchPhoneUnreachableHint() }

                if let onOpenNutrition {
                    Button(Self.logFoodLabel, action: onOpenNutrition)
                        .buttonStyle(.bordered)
                }

                if paths.phoneReachable { WatchSearchOnPhoneHint() }
            }
            .padding(Self.surfaceInset)
        }
        .sheet(isPresented: $pickingExercise) {
            WatchExercisePickerView(paths: paths, revision: revision) { session in
                pickingExercise = false
                onSessionStarted(session)
            }
        }
    }

    /// Path 1: the routine's template becomes the session, and the first
    /// exercise is what the logging surface shows.
    private func start(_ routine: WatchRoutine) async {
        guard let session = try? await paths.startFromRoutine(routine.routineId) else { return }
        onSessionStarted(session)
    }

    /// Path 2: an empty session, then the picker — the fallback list, or
    /// whatever the phone pushes for the search the wrist cannot do itself.
    private func startFreeWorkout() async {
        _ = await paths.startFreeWorkout()
        pickingExercise = true
    }
}

/// The exercise picker for a free workout: what the session already holds, then
/// what the wrist can add to it.
///
/// The full catalog deliberately never reaches the wrist, so this is not a
/// search screen — it is a short list of what the watch knows it can log. An
/// exercise the phone pushed into the live session appears here as the session's
/// own row, so it is selectable rather than merely present; an exercise already
/// on the ladder is offered once, as the row that moves the user to it, and not
/// again as one that would add a second copy. When the phone is reachable, the
/// screen says where the rest lives and waits for the push.
public struct WatchExercisePickerView: View {
    private let paths: WatchSessionStartPaths

    /// Bumped by the host on every arrival. The rows come from a plain class that
    /// publishes nothing, so a push that lands while the picker is open shows up
    /// only because this value changed and the body ran again.
    private let revision: Int

    private let onExerciseAdded: (WatchSessionRecord) -> Void

    public init(
        paths: WatchSessionStartPaths,
        revision: Int = 0,
        onExerciseAdded: @escaping (WatchSessionRecord) -> Void
    ) {
        self.paths = paths
        self.revision = revision
        self.onExerciseAdded = onExerciseAdded
    }

    public var body: some View {
        let rows = paths.pickerRows

        return ScrollView {
            VStack(spacing: 4) {
                if rows.isEmpty {
                    Text("No exercises yet. Search on the phone and send one over.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                } else {
                    ForEach(rows, id: \.id) { row in
                        if row.isInSession {
                            Button(row.name) {
                                Task { await select(row) }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(row.name) {
                                Task { await select(row) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if paths.phoneReachable { WatchSearchOnPhoneHint() }
            }
            .padding(4)
        }
    }

    /// A row the session holds moves the user to it; one it does not appends a
    /// slot. Either way the session is what the screen is handed next.
    private func select(_ row: WatchExercisePickerRow) async {
        guard let session = await paths.selectExercise(row) else { return }
        onExerciseAdded(session)
    }
}

#endif
