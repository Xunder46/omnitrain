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

    /// The platform workout, following the session's life. One coordinator for
    /// the life of the app (D-1504, D-1508): it remembers the session it opened
    /// the workout for, so a refresh never opens a second one for the same
    /// session.
    let workout: WatchWorkoutCoordinator

    /// The sensors follow the session (D-2106): one coordinator for the life of
    /// the app, over the recorder reading the store's own feed. It runs a
    /// subscription exactly while a session is active, so the readings the
    /// logging surface shows belong to the session on screen.
    let sensors: WatchSensorCoordinator

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
        // The health store is built once and shared (D-2106): it owns the
        // workout builder and the sensor feed, so the workout coordinator and
        // the sensors read one authorization outcome, not two. Its location
        // adapter is built here, on the main actor, over a `CLLocationManager`
        // that only calls back on the thread that created it (D-2303, D-2305).
        let healthStore = HealthKitWorkoutStore(
            location: WatchTrackedLocation(source: CoreLocationRawSource())
        )
        let recorder = WatchSensorRecorder(engine: engine, source: healthStore.sensorSource)
        // The units are read from the phone's preferences at every use, so a
        // sync that changes them reaches the logging screens without a relaunch.
        let logging = WatchLoggingState(engine: engine, sensors: recorder, unitsSource: { preferences.units })
        let rating = WatchEffortRatingState(
            engine: engine,
            store: store,
            preferences: preferences
        )
        let workout = WatchWorkoutCoordinator(
            platform: WatchPlatformWorkout(store: healthStore)
        )
        let sensors = WatchSensorCoordinator(recorder: recorder)

        self.engine = engine
        self.paths = paths
        self.preferences = preferences
        self.logging = logging
        self.rating = rating
        self.workout = workout
        self.sensors = sensors
        self.orchestrator = orchestrator
        self.forwarder = forwarder
        self.healthStore = healthStore

        // Every arrival is routed by the orchestrator, then the surface re-reads.
        // A message the wrist refuses is reported through the bridge's failure
        // hook, so the throw is not swallowed here.
        bridge.onIncoming { [weak self] frame in
            guard let self else { return }
            _ = try await self.orchestrator.receive(frame)
            // The receive path runs off the main actor (the radio's handler is
            // `@concurrent`); the counter the views watch is bumped on it.
            await MainActor.run { self.revision += 1 }
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

        // Every session change the surfaces see also settles the platform
        // workout (D-1504) and then the sensors (D-2106): the workout first, so
        // by the time a subscription starts the builder, the permission outcome
        // and the feed exist. The subscription's first emission is the empty
        // session before `restore()`, which the lifecycle rule answers with
        // `.none`, so it is left as it is.
        $revision
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    await self.workout.refresh(self.engine.session)
                    await self.sensors.refresh(self.engine.session)
                }
            }
            .store(in: &cancellables)
    }

    /// The one health store, made in `init` and kept: the sensors, the workout
    /// coordinator and the activation refresh all read this one object, so the
    /// wrist has one authorization outcome and one builder (D-2106, D-3108).
    /// Declared after `init` so the construction inside it stays the first
    /// `HealthKitWorkoutStore(` in this file, which is what the source scan
    /// `testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst` reads.
    private let healthStore: HealthKitWorkoutStore

    /// Reads whatever the wrist already holds, in the order the surfaces need it:
    /// the engine first (its session, the rows it logged and their timers) so a
    /// relaunch mid-session comes back before anything is asked of it, then the
    /// routines, the phone's settings as the last `preferences_down` left them,
    /// and any rating the wrist's own End still owes. The routines, the settings
    /// and the rating are empty on a fresh install, because all three only arrive
    /// when the user asks the phone for them.
    func restore() async {
        // A stranded workout must end before a restored session can open one.
        await workout.recoverInProgress()
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

    /// Reads the workout's newest beat when the app becomes active (D-3108,
    /// D-3113). HealthKit delivers a beat through the builder's callback, which
    /// a suspended app can miss while the wrist is down; the raise that makes
    /// the app active again is therefore also the moment to re-read.
    func refreshHeartRate() {
        healthStore.refreshHeartRate()
    }
}

struct ContentView: View {
    @ObservedObject var host: WatchAppHost

    /// The app's own lifecycle, so a wrist raised beside its phone catches up
    /// without the user pressing Sync (D-183).
    @Environment(\.scenePhase) private var scenePhase

    /// Whether the session menu sheet is up (D-1100, D-3114). Either surface's
    /// list button opens it — the root hosts the one sheet both share.
    @State private var showingMenu = false

    var body: some View {
        Group {
            if host.rating.isPromptOwed {
                owedRating
            } else if host.logging.isResting {
                // D-161: while a rest runs, the rest surface replaces logging —
                // an owed rating still wins above, and the rest is ended by
                // Next (or by logging the next set) below.
                //
                // D-3102: the rest screen carries the same list button, so the
                // menu is one tap away mid-rest; the sheet it opens is the one
                // the root hosts, so a rest ending under it does not close it.
                NavigationStack {
                    WatchRestView(
                        state: host.logging,
                        restPingSeconds: { host.preferences.restPingSeconds },
                        onNext: { host.noteSurfaceChange() }
                    )
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showingMenu = true
                                } label: {
                                    Image(systemName: "list.bullet")
                                }
                            }
                        }
                }
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
        // D-3704: the accent rides the preferences the root already observes, so
        // a Sync that changes the theme re-runs this body and the environment
        // value with it. Read here, at render, like `restPingSeconds`.
        .environment(\.watchAccent, WatchAccent.usable(hex: host.preferences.accentColorHex))
        // D-3114: one sheet, on the root, so the rest↔logging switch and a rest
        // ending underneath it both leave it alone.
        .menuSheet(host, menu: menuState, isPresented: $showingMenu)
        .task {
            await host.restore()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                host.catchUpOnActivation()
                // D-3108: the wrist coming back up is also a read of the
                // builder, since the callback it missed cannot be replayed.
                host.refreshHeartRate()
            }
        }
        // D-3114: with no session behind it the menu has nothing to show, so the
        // sheet closes itself rather than being pulled down by the logging
        // surface going away (an ended session).
        .onChange(of: host.engine.session?.status) { _, status in
            if status != WatchSessionStatus.active { showingMenu = false }
        }
        // D-3114: the owed question outranks every surface, so the sheet closes
        // rather than sitting over it. The host bumps `revision` when the rating
        // changes (`rating.objectWillChange` above), so the body re-runs and this
        // comparison sees the new value.
        .onChange(of: host.rating.isPromptOwed) { _, owed in
            if owed { showingMenu = false }
        }
    }

    /// D-24's first surface: the owed question, alone. The view carries no other
    /// control, so an answer is the only way past it (R-3).
    private var owedRating: some View {
        WatchEffortRatingView(state: host.rating)
    }

    /// The session menu's one construction site (`menuState`), read by both the
    /// pager and the menu sheet (D-3114). Every access constructs a plain
    /// wrapper over the same engine, paths and rating, so the instances are
    /// equivalent: the pager pages the ladder through it, and the sheet hosts it.
    private var menuState: WatchMenuState {
        WatchMenuState(engine: host.engine, paths: host.paths, rating: host.rating)
    }

    /// D-24's second surface: logging, with the session menu one tap away behind
    /// its list button — the ladder's exercises with their logged counts to jump
    /// to, then Add Exercise — the phone's whole list, A to Z, whose pick is
    /// appended at the end (D-3607, D-3608) — then Finish (D-25, D-1100,
    /// D-1200).
    ///
    /// The branch only shows this while the session is active and holds an
    /// exercise. A Free workout starts with none, so the start surface and its
    /// picker stay up until the first exercise lands — picking one gives the
    /// session its slot and the body switches here on the host's nudge.
    ///
    /// Swiping pages the session's exercises (plan 46b); the menu button stays
    /// in the toolbar either way.
    private var loggingSurface: some View {
        NavigationStack {
            WatchLoggingPagerView(
                menu: menuState,
                state: host.logging,
                revision: host.revision,
                onSurfaceChange: { host.noteSurfaceChange() }
            )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingMenu = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }
                }
        }
    }
}

/// D-3114's one sheet, applied to the root: neither the rest↔logging switch nor
/// a rest ending underneath it can tear the menu down, and the shell's one
/// `WatchMenuState` is handed to it rather than built beside it.
private extension View {
    /// The session menu, opened by the list button either surface carries.
    func menuSheet(
        _ host: WatchAppHost,
        menu: WatchMenuState,
        isPresented: Binding<Bool>
    ) -> some View {
        sheet(isPresented: isPresented) {
            WatchMenuView(
                state: menu,
                revision: host.revision,
                onClose: {
                    isPresented.wrappedValue = false
                    host.noteSurfaceChange()
                },
                onFinish: {
                    isPresented.wrappedValue = false
                    host.noteSurfaceChange()
                }
            )
        }
    }
}
