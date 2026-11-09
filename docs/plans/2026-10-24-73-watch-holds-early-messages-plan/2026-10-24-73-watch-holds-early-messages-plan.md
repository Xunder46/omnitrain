# Feature: 73 — a message that reaches the watch while its app is still starting waits instead of being dropped

> Status: Iteration 1 active. Owner answers: none needed (no behaviour a user chooses). One track: watch client (`watch/watchos/`, `ios/OmniTrain Watch App/`).
> Next handoff: `crew-builder-watch` (Phase 1).
> Base: `c1b1c5f0` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Binding: `docs/global_conventions.md`; `.github/copilot/pr-scope-budget.md`.

## Overview

| What you do | Now | After 73 |
|---|---|---|
| The phone queued a workout message (plan 67a) while the watch app was closed; you open the watch app | The message can reach the app a moment before it is ready and is thrown away, so the watch shows the old state until the next sync | The message waits and is handled, in order, as soon as the app is ready |
| Any other message that arrives during launch (a snapshot, a rest, an exercise push) | same loss | same fix |

Code facts (read 2026-10-24, all by the scouts and re-read by the lead):
- The radio object `OmniTrainWatchConnectivity` (`ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`) hands every arrival to a `WatchInboundLane` (plan 63) whose closure is `{ [weak self] frame in await self?.receiveHandler?(frame) }` (l.50, a `lazy var`). A frame drained while `receiveHandler` is nil is dropped.
- `receiveHandler` is installed by `WatchConnectivityBridge.init` (`session.onReceive`, WatchConnectivityBridge.swift l.124). `WatchConnectivityBridge.deliver` (l.316) drops a frame while `inbound` is nil; `inbound` is installed by `bridge.onIncoming(...)`, called from `WatchAppHost.init` (`ContentView.swift` l.208). `OmniTrainWatchConnectivity.init` calls `session.activate()` (l.82) before any of this, so the OS may deliver queued transfers in the gap.
- Before plan 63 `deliver` hopped to the main actor, which incidentally deferred frames past `WatchAppHost.init`. The lane has no such deferral.

## Decision Ledger

- **D-1** `WatchInboundLane` gets an optional gate: `init(startsOpen: Bool = true, handler:)` and `public func open()`. A lane that starts closed accepts `enqueue` and keeps the frames in offer order, handles none until `open()`, then drains them in order; frames offered after `open()` queue behind them. `open()` is idempotent and callable from any thread (the lock already guards `waiting`/`running`). A lane built with the default is unchanged. (`WatchInboundLane.swift`)
- **D-2** The seam gets `func openInbound()` on `WatchConnectivitySession` with a default empty implementation in the protocol extension (like `outstandingTransfers`), so fakes that do not care compile unchanged.
- **D-3** `WatchConnectivityBridge.onIncoming` calls `session.openInbound()` after it stores `inbound` (the store happens first, so the first drained frame already finds its handler). It stays a plain (non-async) function. `deliver`'s `guard let inbound else { return }` stays (defence; unreachable once the gate holds).
- **D-4** `OmniTrainWatchConnectivity` builds its lane closed and exactly once, in `init`, right after `super.init()` and BEFORE `session.delegate = self`; `lane` stops being a `lazy var` (a lazy var initialised from a delegate thread races). `openInbound()` calls `lane.open()`. The closure still reads `receiveHandler` at handling time (installed by the bridge's init before `onIncoming` is ever called).
- **D-5** Listeners and their order (the lead's checklist item ah): (1) `OmniTrainWatchConnectivity.init`: lane built closed, delegate set, `activate()`; (2) `WatchConnectivityBridge.init`: `onReceive` installs `receiveHandler`, `onReachabilityChange` installs the reachability handler; (3) `WatchAppHost.init`: `bridge.onIncoming` installs `inbound`, then `openInbound()` opens the gate; (4) reachability handler fires `catchUp`. Nothing else may call `openInbound`. No frame is handled before step (3).
- **D-6** Nothing is persisted: a frame waits only in memory for the few milliseconds of `init`. A process killed in that window loses the frame exactly as before (the OS has already handed it over); the next sync repairs it. Not new, not fixed here.
- **D-7** Out of scope: `didReceiveApplicationContext` (not implemented, never sent); the phone side; protocol/contract (no change).

## Feature Invariants

- Frames are handled one at a time in the order the radio offered them (plan 63 D-4, S-9310).
- A lane built with the default arguments behaves exactly as before.
- No frame is handled before the host has installed `inbound`.

## Scenarios (new ids; grep 2026-10-24: `S-103` unused)

- **S-10301 a closed lane holds, then hands out in order.** Fixture: lane `startsOpen: false` with a recording handler; enqueue frames `["n": 1]`, `["n": 2]`, `["n": 3]`; yield 50 ms; assert nothing handled; call `open()`; wait for 3. Expected: handled `[1, 2, 3]`. Fails today: there is no gate, so frames would be handled (and dropped by a nil handler) immediately.
- **S-10302 frames offered after `open()` queue behind the held ones.** Fixture: as S-10301 but after `open()` immediately enqueue `["n": 4]` while the handler for frame 1 is parked on a continuation; release. Expected: `[1, 2, 3, 4]`, never overlapping (reuse the S-9310 parking helper in `WatchInboundLaneTests.swift`).
- **S-10303 `open()` twice and `open()` on a default lane are harmless.** Fixture: default lane, `open()`, enqueue 1 frame; closed lane `open()` twice then enqueue. Expected: each handled exactly once.
- **S-10304 the bridge opens the gate only after it holds a handler.** Fixture: `FakeWatchConnectivitySession` gains `openInboundCalls` (count) and records, inside `openInbound()`, whether the bridge already had an `inbound` (the test passes a handler to `onIncoming` and, in `openInbound`, delivers a frame through its own receive handler and asserts the handler saw it). Simpler accepted form: the fake counts calls; the test calls `bridge.onIncoming { frames.append($0) }`, asserts `openInboundCalls == 1`, then delivers a frame by hand and asserts it reached the handler. Expected: 1 call; frame handled.
- **S-10305 a frame delivered by the fake BEFORE `onIncoming` is a drop at the bridge, a hold at the radio.** Not testable on macOS for the radio (app target); the bridge arm: deliver a frame to the bridge's receive handler before `onIncoming`; expected: nothing handled and no crash (pins the kept guard).
- **S-10306 source guards (app target; exact statements, not substrings; comment-stripped like S-9315).** `OmniTrainWatchConnectivity.swift` contains `WatchInboundLane(startsOpen: false)`, contains `func openInbound() {` followed within the body by `lane.open()`, does NOT contain `private lazy var lane`, and the lane is built before `session.delegate = self` (the index of `WatchInboundLane(startsOpen: false)` is smaller than the index of `session.delegate = self`). The S-9315 guard in `WatchInboundLaneWiringSourceTests.swift` l.74 currently asserts the substring `WatchInboundLane {`; it is updated to `WatchInboundLane(startsOpen: false)` (reader list: this file only, grep 2026-10-24).
- **S-10307 `ContentView.swift` order.** The host calls `bridge.onIncoming {` before anything can open the gate: since `onIncoming` itself calls `openInbound()` (D-3) the guard is on `WatchConnectivityBridge.swift`: the body of `onIncoming` contains `inbound = handler` before `session.openInbound()` (indices).

## Phase 1: gate in the package, then the app shell (`crew-builder-watch`, one run)

1. [ ] `WatchInboundLane`: D-1 — `watch/watchos/Sources/WatchSessionEngine/WatchInboundLane.swift`.
2. [ ] Seam: D-2 `openInbound()` + default in the extension; bridge `onIncoming`: D-3 — `WatchConnectivityBridge.swift`.
3. [ ] App shell: D-4 — `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`.
4. [ ] `FakeWatchConnectivitySession`: `openInboundCalls` — tests dir.
5. [ ] Tests S-10301..S-10305 in `WatchInboundLaneTests.swift` / `WatchConnectivityBridgeTests.swift`; guards S-10306, S-10307 and the S-9315 update in `WatchInboundLaneWiringSourceTests.swift`.
6. [ ] Report FIRST as a skeleton, then fill it.

**Done**: `swift test --package-path watch/watchos --filter WatchInboundLane`, `--filter WatchConnectivityBridge`, `--filter WatchSessionEngineTests` (the append-only source guard: new function names avoid update/delete/remove/replace/edit/overwrite/write/clear/purge/wipe/reset/drop/truncate/erase/forget/modify/mutate/destroy/set — `open` and `openInbound` are fine), pasted counts. Never run the full `flutter test`; do not run the full Swift suite beyond the filters above (the lead runs it).
**Predicted files**: the six files named above plus the plan's evidence file. Nothing in `lib/`, `docs/` except the plan folder.

## Owner device checks

- (owner) ODC-1 Finish a workout on the phone with the watch app closed, wait a minute, open the watch app: the watch shows the finished state without pressing Sync. (The iOS/watch simulators do not deliver `transferUserInfo`; only a real watch shows this.)

## Progress
- [x] Phase 1

## Assumption Log
- App-target code built with xcodebuild (watchOS Simulator, SE 3 40 mm): BUILD SUCCEEDED. The iOS/watch simulators do not deliver queued transfers: ODC-1 is owner-only.
- Mutants A1..A7 killed (A2, an open() on an empty lane, is equivalent).

## Feedback
