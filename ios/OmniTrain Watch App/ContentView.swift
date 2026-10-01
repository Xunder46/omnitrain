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

/// Owns the engine, its store and its start paths for the life of the app.
///
/// Two deliberate gaps, both of which the shipping plan closes later:
///
/// - The store is in-memory. The Swift package ships no persistent store, so
///   nothing logged here survives a relaunch yet.
/// - There is no transport, which is why `onRequestSync` is nil below. The sync
///   button stays off the surface until something can actually answer it —
///   a button that asks a phone nobody is listening to would be a lie.
@MainActor
final class WatchAppHost: ObservableObject {
    let engine: WatchSessionEngine
    let paths: WatchSessionStartPaths

    /// Bumped whenever `paths` changes underneath us. `WatchSessionStartPaths` is
    /// a plain class that publishes nothing, so without this SwiftUI would never
    /// re-read it — and a restore that loaded routines would leave the surface
    /// still showing an empty list.
    @Published private(set) var revision = 0

    init() {
        let store = InMemoryWatchSessionStore()
        let engine = WatchSessionEngine(store: store)
        self.engine = engine
        self.paths = WatchSessionStartPaths(engine: engine, store: store)
    }

    /// Reads whatever the wrist already holds. Empty on a fresh install, because
    /// routines only arrive when the user asks the phone for them.
    func restore() async {
        await paths.restore()
        revision += 1
    }
}

struct ContentView: View {
    @ObservedObject var host: WatchAppHost

    /// Set when a session starts. A placeholder until the logging surface is
    /// wired in — proving the start path fires is the point of this step.
    @State private var startedSessionId: String?

    var body: some View {
        Group {
            if let sessionId = startedSessionId {
                startedPlaceholder(sessionId: sessionId)
            } else {
                WatchStartView(
                    paths: host.paths,
                    onSessionStarted: { record in
                        startedSessionId = record.sessionId
                    }
                )
            }
        }
        .task {
            await host.restore()
        }
    }

    private func startedPlaceholder(sessionId: String) -> some View {
        VStack(spacing: 4) {
            Text("Session started")
                .font(.headline)
            Text(sessionId)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Back") {
                startedSessionId = nil
            }
        }
        .padding()
    }
}
