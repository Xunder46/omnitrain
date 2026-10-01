// swift-tools-version: 5.9
//
// Watch session engine — the watchOS (native) half of
// `docs/plans/2026-07-13-06-a1-watch-session-engine-plan.md`.
//
// Deliberately a plain Swift package rather than an Xcode project: the engine,
// its append-only store, its timer math, and the protocol conformance suite are
// platform-independent, so they build and run today — `swift test` — with no
// watch app target standing in the way. The SwiftUI logging view ships here too,
// behind `#if os(watchOS)` so `swift test` still compiles; the Xcode watch
// target depends on this package and adds the app entry point and the transport.
//
// Behaviour parity with the Wear OS implementation in `lib/watch/session/` is
// the contract; the shared JSON fixtures in `watch/sync_protocol/fixtures/`
// are what proves it, and this suite walks the same register the Dart suite
// does.

import PackageDescription

let package = Package(
    name: "WatchSessionEngine",
    // watchOS is declared so the watch app target can link this library; the
    // macOS platform is what keeps `swift test` runnable without a watch target
    // (see `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
    // Phase 7 step 0).
    platforms: [.macOS(.v13), .watchOS(.v9)],
    // The library the Xcode watch target links. Without a declared product the
    // package has nothing consumable from outside it — `swift test` still passes,
    // because the test target reaches the source target directly, but Xcode
    // refuses to add the package at all.
    products: [
        .library(name: "WatchSessionEngine", targets: ["WatchSessionEngine"]),
    ],
    targets: [
        .target(name: "WatchSessionEngine"),
        .testTarget(
            name: "WatchSessionEngineTests",
            dependencies: ["WatchSessionEngine"]
        ),
    ]
)
