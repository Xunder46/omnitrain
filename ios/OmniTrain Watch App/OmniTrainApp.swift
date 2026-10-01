//
//  OmniTrainApp.swift
//  OmniTrain Watch App
//
//  The watch app's entry point. Everything it renders comes from the
//  `WatchSessionEngine` package in `watch/watchos/` — this target owns only the
//  app lifecycle and, eventually, the transport.
//
//  Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
//  Phase 7.
//

import SwiftUI

@main
struct OmniTrain_Watch_AppApp: App {
    @StateObject private var host = WatchAppHost()

    var body: some Scene {
        WindowGroup {
            ContentView(host: host)
        }
    }
}
