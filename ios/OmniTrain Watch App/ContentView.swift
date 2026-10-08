//
//  ContentView.swift
//  OmniTrain Watch App
//
//  The wrist's home surface, wired to the real start paths from the
//  `WatchSessionEngine` package.
//

import Combine
import SwiftUI
import WatchSessionEngine

/// Owns the engine, its store, its start paths and its radio for the life of the
/// app.
///
/// The store is an append-only file in the app's Application Support directory,
/// so what the wrist logged survives a relaunch. The radio below is real, so a
/// sync and a push do arrive.
@MainActor
final class WatchAppHost: ObservableObject {
    let engine: WatchSessionEngine
    let paths: WatchSessionStartPaths
    let preferences: WatchPhonePreferences

    /// The logging surface's state, and the End/effort-rating state. One of each
    /// for the life of the app (D-30): the logging state derives the current
    /// exercise live from the engine, so one instance follows the session, the
    /// picker and the phone's own pushes.
    let logging: WatchLoggingState
    let rating: WatchEffortRatingState

    /// Bumped whenever `paths` changes underneath us. `WatchSessionStartPaths` is
    /// a plain class that publishes nothing, so without this SwiftUI would never
    /// re-read it — and a restore that loaded routines would leave the surface
    /// still showing an empty list.
    @Published private(set) var revision = 0

    /// What the radio last said about the phone. Unknown until it says anything
    /// (D-8): a launch that has asked nothing must not claim the phone is out of
    /// reach, which is what a flag starting `false` would say.
    @Published private(set) var phoneReachability = WatchPhoneReachability.unknown

    private let orchestrator: WatchSyncOrchestrator

    /// The engine's sink holds this weakly, so the app has to hold it: without
    /// the host, every frame the wrist produces is dropped (D-21).
    private let forwarder: WatchEmitForwarder

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Build order matters (D-21): store, the radio, the sink over the radio,
        // then the engine that hands its emissions to that sink. The package's
        // own harnesses record emissions in a separate array and never hand them
        // to a bridge, so theirs is not the order to copy.
        let storeDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watch-session", isDirectory: true)
        let store = FileWatchSessionStore(directory: storeDirectory)
        let session = OmniTrainWatchConnectivity(onSendFailure: reportWatchRadioFailure)
        let bridge = WatchConnectivityBridge(session: session, onFailure: reportWatchRadioFailure)
        let forwarder = WatchEmitForwarder(transport: bridge, onFailure: reportWatchRadioFailure)
        let engine = WatchSessionEngine(store: store, onEmit: forwarder.sink)
        let paths = WatchSessionStartPaths(engine: engine, store: store)
        let preferences = WatchPhonePreferences(store: store)
        let orchestrator = WatchSyncOrchestrator(
            transport: bridge,
            paths: paths,
            engine: engine,
            preferences: preferences
        )
        let logging = WatchLoggingState(engine: engine)
        let rating = WatchEffortRatingState(
            engine: engine,
            store: store,
            preferences: preferences
        )

        self.engine = engine
        self.paths = paths
        self.preferences = preferences
        self.logging = logging
        self.rating = rating
        self.orchestrator = orchestrator
        self.forwarder = forwarder

        // Every arrival is routed by the orchestrator, then the surface re-reads.
        // A message the wrist refuses is reported through the bridge's failure
        // hook, so the throw is not swallowed here.
        bridge.onIncoming { [weak self] frame in
            guard let self else { return }
            _ = try await self.orchestrator.receive(frame)
            self.revision += 1
        }

        // The radio's answers, mapped to the three-state value the surface reads
        // (D-8). The first one arrives from activation, which is why a wrist that
        // launched beside its phone still learns that it did.
        bridge.onReachabilityChange { [weak self] reachable in
            guard let self else { return }
            self.phoneReachability = WatchPhoneReachability.observed(reachable: reachable)
            self.revision += 1
            // The phone back in reach catches the wrist up by itself (D-96). Not
            // awaited, so the handler is never blocked; the gate and the in-flight
            // guard live in `catchUp`, not here.
            Task { await self.orchestrator.catchUp(reachable: reachable) }
        }

        // End and the answer both change which surface the shell shows, and
        // neither goes through a host `@Published`. SwiftUI's `objectWillChange`
        // announces a change *before* it is made, so the nudge is deferred a
        // turn: by then the session has finished and the prompt is owed (D-24).
        rating.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.revision += 1 }
            }
            .store(in: &cancellables)
    }

    /// Reads whatever the wrist already holds, in the order the surfaces need it:
    /// the engine first (its session, the rows it logged and their timers) so a
    /// relaunch mid-session comes back before anything is asked of it, then the
    /// routines, the phone's settings as the last `preferences_down` left them,
    /// and any rating the wrist's own End still owes. The routines, the settings
    /// and the rating are empty on a fresh install, because all three only arrive
    /// when the user asks the phone for them.
    func restore() async {
        await engine.restore()
        await paths.restore()
        await preferences.restore()
        await rating.restore()
        revision += 1
    }

    /// Asks the phone for the routines and the wrist's session state — the Sync
    /// button's own action, for what is not automatic: the first fetch on a fresh
    /// watch, the routines and the settings, and a manual retry. A session the
    /// wrist is running keeps itself in step with the phone without it, by its own
    /// announcements and its reachability catch-up (D-96).
    ///
    /// The first sync asks for everything; a later one says what the wrist
    /// already has, so the phone can answer with what changed.
    func requestSync() async {
        await orchestrator.sync(reconnect: paths.syncedAt != nil)
        revision += 1
    }

    /// Tells the surfaces to re-read after a change the host did not make itself:
    /// a session started from a routine or the picker, and an exercise picked on
    /// the logging surface. Arrivals and rating-state changes already bump
    /// `revision` on their own.
    func noteSurfaceChange() {
        revision += 1
    }

    /// Catches the wrist up whenever the app becomes active (D-183), with what
    /// the radio last observed: the same trigger the reachability edge uses, so
    /// a wrist that woke beside a reachable phone converges without the Sync
    /// button. Not awaited, so the handler is never blocked; the gate and the
    /// in-flight guard live in `catchUp`.
    func catchUpOnActivation() {
        Task { await orchestrator.catchUp(reachable: phoneReachability == .reachable) }
    }
}

struct ContentView: View {
    @ObservedObject var host: WatchAppHost

    /// The app's own lifecycle, so a wrist raised beside its phone catches up
    /// without the user pressing Sync (D-183).
    @Environment(\.scenePhase) private var scenePhase

    /// The exercise picker on the logging surface. The start surface keeps its
    /// own sheet for the empty Free workout; this one moves between exercises and
    /// adds new ones (R-1, S-30).
    @State private var pickingExercise = false

    var body: some View {
        Group {
            if host.rating.isPromptOwed {
                owedRating
            } else if let session = host.engine.session,
                      session.status == WatchSessionStatus.active,
                      !session.exercises.isEmpty {
                loggingSurface
            } else {
                WatchStartView(
                    paths: host.paths,
                    onSessionStarted: { _ in host.noteSurfaceChange() },
                    onRequestSync: { Task { await host.requestSync() } },
                    phoneReachability: host.phoneReachability,
                    revision: host.revision
                )
            }
        }
        .task {
            await host.restore()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { host.catchUpOnActivation() }
        }
    }

    /// D-24's first surface: the owed question, alone. The view carries no other
    /// control, so an answer is the only way past it (R-3).
    private var owedRating: some View {
        WatchEffortRatingView(state: host.rating)
    }

    /// D-24's second surface: logging, with the picker one tap away and the
    /// package's own End on the same screen (D-25, R-1).
    ///
    /// The branch only shows this while the session is active and holds an
    /// exercise. A Free workout starts with none, so the start surface and its
    /// picker stay up until the first exercise lands — picking one gives the
    /// session its slot and the body switches here on the host's nudge.
    private var loggingSurface: some View {
        NavigationStack {
            WatchLoggingView(state: host.logging)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        WatchEndSessionView(state: host.rating)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            pickingExercise = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }
                }
                .sheet(isPresented: $pickingExercise) {
                    WatchExercisePickerView(
                        paths: host.paths,
                        revision: host.revision
                    ) { _ in
                        pickingExercise = false
                        host.noteSurfaceChange()
                    }
                }
        }
        // The picker is a presentation, not the screen: a session that ends
        // underneath it must not leave it owed when the surface comes back.
        .onDisappear { pickingExercise = false }
    }
}
