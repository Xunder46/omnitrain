//
//  WatchStartView.swift
//  WatchSessionEngine
//
//  The native watchOS start surface: a synced routine, or a free workout.
//  Native half of
//  `.github/agents/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`.
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

/// Where a session begins on the wrist, and what the user is handed when it
/// does: the session to log against, never a screen to find.
public struct WatchStartView: View {
    private let paths: WatchSessionStartPaths
    private let onSessionStarted: (WatchSessionRecord) -> Void

    /// Wrist-scale inset. The phone's spacing tokens are sized for a full-width
    /// screen; this surface carries its own value rather than scaling one down.
    private static let surfaceInset = 4.0

    @State private var pickingExercise = false

    public init(
        paths: WatchSessionStartPaths,
        onSessionStarted: @escaping (WatchSessionRecord) -> Void
    ) {
        self.paths = paths
        self.onSessionStarted = onSessionStarted
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

                if paths.phoneReachable { WatchSearchOnPhoneHint() }
            }
            .padding(Self.surfaceInset)
        }
        .sheet(isPresented: $pickingExercise) {
            WatchExercisePickerView(paths: paths) { session in
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

/// The exercise picker for a free workout: the fallback list, and nothing else.
///
/// The full catalog deliberately never reaches the wrist, so this is not a
/// search screen — it is a short list of what the watch knows it can log. When
/// the phone is reachable, the screen says where the rest lives and waits for
/// the push.
public struct WatchExercisePickerView: View {
    private let paths: WatchSessionStartPaths
    private let onExerciseAdded: (WatchSessionRecord) -> Void

    public init(
        paths: WatchSessionStartPaths,
        onExerciseAdded: @escaping (WatchSessionRecord) -> Void
    ) {
        self.paths = paths
        self.onExerciseAdded = onExerciseAdded
    }

    public var body: some View {
        let exercises = paths.fallbackExercises

        return ScrollView {
            VStack(spacing: 4) {
                if exercises.isEmpty {
                    Text("No exercises yet. Search on the phone and send one over.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                } else {
                    ForEach(exercises, id: \.exerciseId) { exercise in
                        Button(exercise.name) {
                            Task { await add(exercise) }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if paths.phoneReachable { WatchSearchOnPhoneHint() }
            }
            .padding(4)
        }
    }

    private func add(_ exercise: WatchCatalogExercise) async {
        onExerciseAdded(await paths.addExerciseToSession(exercise))
    }
}

#endif
