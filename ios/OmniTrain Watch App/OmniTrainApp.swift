//
//  OmniTrainApp.swift
//  OmniTrain Watch App
//
//  The watch app's entry point. Everything it renders comes from the
//  `WatchSessionEngine` package in `watch/watchos/` — this target owns only the
//  app lifecycle and the transport.
//
//  Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
//  Phase 7.
//

import SwiftUI
import WatchKit

@main
struct OmniTrain_Watch_AppApp: App {
    /// The delegate owns the one host, so the system's workout-recovery
    /// relaunch and the surface reach the same engine and workout (plan 89 D-3).
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(host: delegate.host)
        }
    }
}

/// Answers the system when it relaunches the app to recover a workout a
/// force-quit left running (plan 89 D-3): the stranded workout is ended through
/// the launch's own recovery, so the heart-rate sensor stops without the user
/// opening the app.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let host = WatchAppHost()

    func handleActiveWorkoutRecovery() {
        Task { await host.recoverStrandedWorkout() }
    }
}
