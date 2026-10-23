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

    /// The food quick-log's state: the synced food list, the food and portion the
    /// user has picked, and the observation a confirm makes. One for the life of
    /// the app (D-1), so the start screen's sheet and the session menu's row read
    /// the list the phone last sent and the recent order the wrist's own logs
    /// give.
    let nutrition: WatchNutritionState

    /// The quick-log's one model, built beside its state so the crown, the
    /// selection and the state's change observer live as long as the app: the
    /// start screen's sheet and the session menu's row both present this model
    /// (D-6, D-10).
    let nutritionModel: WatchNutritionModel

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

    /// Whether a sync is plausibly unfinished, so the start screen shows the
    /// spinner instead of the Sync button (plan 55, D-2, D-6). Published, so the
    /// surface re-reads it; nothing else in the host observes it, which is why
    /// the tick below assigns this and never `revision`.
    @Published private(set) var isSyncing = false

    /// Whether Health access is on, asked when the start screen first shows (plan 59, D-6).
    @Published private(set) var healthAccess = WatchHealthAccess.unknown

    /// Whether the last manual Sync ended with no answer from the phone (plan 60, D-4).
    @Published private(set) var syncNoAnswer = false

    /// Whether the radio could not come up at all (plan 60, D-4).
    @Published private(set) var linkUnavailable = false

    /// Set by a manual Sync only, so an automatic catch-up never raises the
    /// no-answer line.
    private var manualSyncPending = false

    /// The window the spinner follows (D-1, D-5): begun by a sync request or a
    /// catch-up that will run, ended by the replies going quiet or by the cap.
    /// Touched on the main actor only — the host's own isolation — so the tick
    /// and the radio handlers cannot race each other through it.
    private var syncProgress = WatchSyncProgress()

    /// The bounded tick that ends the spinner when no reply ever comes (D-6).
    /// A begin while one is still running replaces it, so two ticks never race
    /// to write `isSyncing`.
    private var syncProgressTicker: Task<Void, Never>?

    /// How often the tick re-reads the window (D-6): fine enough that the Sync
    /// button is back as the quiet window ends, coarse enough to cost nothing on
    /// a wrist.
    private static let syncProgressTickNanoseconds: UInt64 = 500_000_000

    /// The line the wrist shows when entries are waiting for the phone (plan 51d
    /// D-3), read at render: the views re-run on `revision`, which every receipt
    /// and every reachability change bumps.
    var syncNotice: String? {
        deriveSyncNotice(
            pending: engine.unconfirmedObservations,
            reachability: phoneReachability,
            now: Date()
        )
    }

    /// The one phone-link problem the Start screen shows: the link that cannot
    /// start outranks a Sync that got no answer (plan 60, D-4).
    var phoneProblem: String? {
        if linkUnavailable { return WatchStartSurfaceCopy.linkUnavailableLabel }
        if syncNoAnswer { return WatchStartSurfaceCopy.syncNoAnswerLabel }
        return nil
    }

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
        // The quick-log is built over the same engine and store (D-1): its foods
        // arrive on the orchestrator's `foods_down`, and its log is the engine's
        // own `logNutrition`, so it is the same event the start screen takes.
        let nutrition = WatchNutritionState(engine: engine, store: store)
        // One model for the app's life (D-6): a model built per body evaluation
        // would reset the crown and drop the state's change observer, so a
        // foods_down would leave an open surface showing the old numbers.
        let nutritionModel = WatchNutritionModel(state: nutrition)
        let orchestrator = WatchSyncOrchestrator(
            transport: bridge,
            paths: paths,
            engine: engine,
            nutrition: nutrition,
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
        self.nutrition = nutrition
        self.nutritionModel = nutritionModel
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
            // Plan 55 (D-2, A-3): the phone spoke, so the wait may end. Noted
            // before the receive, so a frame the wrist refuses still counts and a
            // throw cannot skip it. `syncProgress` is main-actor state and this
            // handler is not, so the note is hopped like the bump below.
            let type = frame["type"] as? String ?? ""
            await MainActor.run {
                self.syncProgress.noteArrival(type: type, at: Date())
                if WatchSyncProgressCopy.replyTypes.contains(type) { self.syncNoAnswer = false }
            }
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
            // guard live in `catchUp`, not here — and so does the spinner, which
            // only a reachable phone has anything to wait for (plan 55, A-4).
            if reachable { self.beginSyncProgress() }
            Task { await self.orchestrator.catchUp(reachable: reachable) }
        }
        // The radio that cannot come up at all is its own line, not a
        // reachability answer (plan 60, D-5).
        session.onLinkProblem { [weak self] problem in self?.linkUnavailable = problem }

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
    /// quick-log's synced food list, then the routines, the phone's settings as the
    /// last `preferences_down` left them, and any rating the wrist's own End still
    /// owes. The routines, the settings and the rating are empty on a fresh
    /// install, because all three only arrive when the user asks the phone for
    /// them.
    func restore() async {
        // A stranded workout must end before a restored session can open one.
        await workout.recoverInProgress()
        await engine.restore()
        await nutrition.restore()
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
    ///
    /// The spinner starts before the request is awaited (plan 55, D-2): the
    /// orchestrator's `sync` returns once the frames are sent, and the answer
    /// arrives afterwards.
    func requestSync() async {
        syncNoAnswer = false
        manualSyncPending = true
        beginSyncProgress()
        await orchestrator.sync(reconnect: paths.syncedAt != nil)
        revision += 1
    }

    /// Starts the spinner, opens a sync window, and starts the tick that closes
    /// it (plan 55, D-2, D-6). The window's arithmetic is `WatchSyncProgress`'s;
    /// nothing observes a struct, so the tick re-reads it while a sync is
    /// plausibly unfinished and then exits.
    ///
    /// The tick assigns `isSyncing` alone: bumping `revision` here would put the
    /// workout and sensor refresh on a half-second cycle for the length of every
    /// sync (S-8512).
    private func beginSyncProgress() {
        syncProgress.begin()
        isSyncing = true
        syncProgressTicker?.cancel()
        syncProgressTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.syncProgressTickNanoseconds)
                guard let self, !Task.isCancelled else { return }
                if self.syncProgress.isActive(at: Date()) {
                    self.isSyncing = true
                } else {
                    self.isSyncing = false
                    if self.manualSyncPending {
                        self.manualSyncPending = false
                        self.syncNoAnswer = self.syncProgress.endedWithoutAnswer(at: Date())
                    }
                    return
                }
            }
        }
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
        let reachable = phoneReachability == .reachable
        // Nothing to wait for when the phone is out of reach, and `catchUp` does
        // nothing then either, so no spinner is started (plan 55, A-4).
        if reachable { beginSyncProgress() }
        Task { await orchestrator.catchUp(reachable: reachable) }
    }

    /// Reads the workout's newest beat when the app becomes active (D-3108,
    /// D-3113). HealthKit delivers a beat through the builder's callback, which
    /// a suspended app can miss while the wrist is down; the raise that makes
    /// the app active again is therefore also the moment to re-read.
    func refreshHeartRate() {
        healthStore.refreshHeartRate()
    }

    /// Asks for Health access before any workout: called when the start screen
    /// shows. The system raises its sheet once; every later call answers at once.
    func askHealthAccess() async {
        healthAccess = await healthStore.requestAccess()
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

    /// Whether the food quick-log sheet is up (D-2). The start screen's Log food
    /// button opens it; the sheet is the root's, so a session starting or a rest
    /// ending underneath it does not replace it.
    @State private var showingFood = false

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
                                        .accessibilityLabel("Exercises")
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
                    onFreeWorkoutCancelled: { host.noteSurfaceChange() },
                    onOpenNutrition: { showingFood = true },
                    onRequestSync: { Task { await host.requestSync() } },
                    phoneReachability: host.phoneReachability,
                    revision: host.revision,
                    syncNotice: host.syncNotice,
                    isSyncing: host.isSyncing,
                    healthAccess: host.healthAccess,
                    phoneProblem: host.phoneProblem
                )
                .task { await host.askHealthAccess() }
            }
        }
        // D-3704: the accent rides the preferences the root already observes, so
        // a Sync that changes the theme re-runs this body and the environment
        // value with it. Read here, at render, like `restPingSeconds`.
        // With no usable phone accent the wrist wears the phone's default theme (plan 56, D-1).
        .environment(\.watchAccent, WatchAccent.worn(hex: host.preferences.accentColorHex))
        // D-3114: one sheet, on the root, so the rest↔logging switch and a rest
        // ending underneath it both leave it alone.
        .menuSheet(host, menu: menuState, isPresented: $showingMenu)
        // D-2: the start screen's way into the quick-log. Its own sheet, on the
        // root, so the surface is the one the phone's foods landed in.
        .sheet(isPresented: $showingFood) {
            NavigationStack {
                WatchNutritionView(model: host.nutritionModel)
            }
        }
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
                                .accessibilityLabel("Exercises")
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
                nutritionModel: host.nutritionModel,
                syncNotice: host.syncNotice,
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
