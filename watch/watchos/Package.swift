// swift-tools-version: 5.9
//
// Watch session engine — the watchOS (native) half of
// `.github/agents/plans/2026-07-13-06-a1-watch-session-engine-plan.md`.
//
// Deliberately a plain Swift package rather than an Xcode project: the engine,
// its append-only store, its timer math, and the protocol conformance suite are
// platform-independent, so they build and run today — `swift test` — with no
// watch app target standing in the way. The Xcode watch target depends on this
// package and adds only the UI and the transport.
//
// Behaviour parity with the Wear OS implementation in `lib/watch/session/` is
// the contract; the shared JSON fixtures in `watch/sync_protocol/fixtures/`
// are what proves it, and this suite walks the same register the Dart suite
// does.

import PackageDescription

let package = Package(
    name: "WatchSessionEngine",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WatchSessionEngine"),
        .testTarget(
            name: "WatchSessionEngineTests",
            dependencies: ["WatchSessionEngine"]
        ),
    ]
)
