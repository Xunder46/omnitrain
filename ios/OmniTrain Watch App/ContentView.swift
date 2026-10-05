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
/// One deliberate gap remains: the store is in-memory. The Swift package ships no
/// persistent store, so nothing logged here survives a relaunch yet. The radio
/// below is real, so a sync and a push do arrive.
@MainActor
final class WatchAppHost: ObservableObject {
    let engine: WatchSessionEngine
    let paths: WatchSessionStartPaths
    let preferences: WatchPhonePreferences

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

    init() {
        let store = InMemoryWatchSessionStore()
        let engine = WatchSessionEngine(store: store)
        let paths = WatchSessionStartPaths(engine: engine, store: store)
        let preferences = WatchPhonePreferences(store: store)
        let session = OmniTrainWatchConnectivity(onSendFailure: reportWatchRadioFailure)
        let bridge = WatchConnectivityBridge(session: session, onFailure: reportWatchRadioFailure)
        let orchestrator = WatchSyncOrchestrator(
            transport: bridge,
            paths: paths,
            engine: engine,
            preferences: preferences
        )

        self.engine = engine
        self.paths = paths
        self.preferences = preferences
        self.orchestrator = orchestrator

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
        }
    }

    /// Reads whatever the wrist already holds: the routines, and the phone's
    /// settings as the last `preferences_down` left them. Empty on a fresh
    /// install, because both only arrive when the user asks the phone for them.
    func restore() async {
        await paths.restore()
        await preferences.restore()
        revision += 1
    }

    /// Asks the phone for the routines and the wrist's session state — the one
    /// action that starts a sync, because nothing arrives unless the user asks
    /// (D-16, I-1).
    ///
    /// The first sync asks for everything; a later one says what the wrist
    /// already has, so the phone can answer with what changed.
    func requestSync() async {
        await orchestrator.sync(reconnect: paths.syncedAt != nil)
        revision += 1
    }
}

struct ContentView: View {
    @ObservedObject var host: WatchAppHost

    /// Which session the user is in. The logging surface is not wired in yet, so
    /// what follows a start is the session's own ladder with the current
    /// exercise marked — the state a start path, and a push from the phone, both
    /// have to reach.
    @State private var startedSessionId: String?

    var body: some View {
        Group {
            if startedSessionId != nil, let session = host.engine.session {
                startedPlaceholder(session: session)
            } else {
                WatchStartView(
                    paths: host.paths,
                    onSessionStarted: { record in
                        startedSessionId = record.sessionId
                    },
                    onRequestSync: { Task { await host.requestSync() } },
                    phoneReachability: host.phoneReachability,
                    revision: host.revision
                )
            }
        }
        .task {
            await host.restore()
        }
    }

    private func startedPlaceholder(session: WatchSessionRecord) -> some View {
        VStack(spacing: 4) {
            Text("Session started")
                .font(.headline)
            ForEach(session.exercises.indices, id: \.self) { index in
                let isCurrent = index == session.currentExerciseIndex
                HStack(spacing: 4) {
                    Image(systemName: isCurrent ? "arrowtriangle.right.fill" : "circle.fill")
                        .font(.system(size: 6))
                    Text(session.exercises[index]["name"] as? String ?? "Exercise")
                        .font(.footnote)
                        .lineLimit(1)
                }
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
            }
            Button("Back") {
                startedSessionId = nil
            }
        }
        .padding()
    }
}
