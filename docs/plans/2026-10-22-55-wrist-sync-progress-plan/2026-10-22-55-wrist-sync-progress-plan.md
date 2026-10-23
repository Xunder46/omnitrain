# Feature: 55 — the watch shows a spinner while it is syncing

> Status: SEEDED 2026-10-22 (governor), not planned yet. Owner: watch testing round 2026-10-22 item 5, in chat ("Can the syncing process have a progress spinner or something until it finishes"). Series: PR 3 of 3 (53 food, 54 effort follow before). Base commit: `.work/2026-10-22-55/base.txt`. Working branch: the one checked out; never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 55 |
|---|---|---|
| Press Sync on the watch's start screen | nothing visible until the routines/foods/exercises arrive (or never) | the Sync button turns into a spinner with "Syncing…" at once, and goes back to Sync when the phone's answer has arrived and gone quiet (or after a cap) |
| The wrist catches up by itself when it wakes beside a reachable phone | silent | the same spinner shows while that catch-up runs |
| The phone is out of reach | the Sync button is already hidden (`phoneStatus.offersSync`) | unchanged: no spinner is started when there is nothing to wait for |

## What "finished" means (the sync's replies arrive after the request returns)

`WatchSyncOrchestrator.sync` (`watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift` ~l.84) awaits only the sends; the phone's answer (`preferences_down`, `routines_down`, `foods_down`, `exercises_down` batches, `session_snapshot`) arrives later through `receive` (~l.168). So "finished" cannot be read from the request: it is derived from the arrivals.

## Decision Ledger

- D-1 A pure type `WatchSyncProgress` (new file in `WatchSessionEngine`, platform-independent, injected clock) answers `isActive(at:)`. `begin(at:)` starts it; `noteArrival(type:at:)` records the newest arrival of a sync reply type (`preferences_down`, `routines_down`, `foods_down`, `exercises_down`, `session_snapshot`). Active from `begin` until BOTH: a `routines_down` has arrived since `begin`, AND `quietSeconds` (2.0) have passed since the newest arrival; or until `capSeconds` (20.0) after `begin`, whichever is first. `begin` while already active restarts nothing (the running one continues). Constants live in a copy enum like `WatchSyncNoticeCopy` (`WatchSyncNotice.swift`).
- D-2 `WatchAppHost` (`ios/OmniTrain Watch App/ContentView.swift`) owns one `WatchSyncProgress`. `requestSync()` (~l.227) calls `begin` first; the catch-up path (`catchUpOnActivation`, ~l.262, i.e. `orchestrator.catchUp(reachable:)`) calls `begin` only when it will run (`phoneReachability == .reachable`); every message that reaches `orchestrator.receive` is noted by its `type`. The host publishes `isSyncing` so the start screen re-renders; because activity ends by the clock, the view re-evaluates on a timer while active (a `TimelineView(.periodic(...))` or a host-owned task that bumps `revision` at the end; the planner chooses).
- D-3 `WatchStartView` (`WatchStartView.swift`, Sync button ~l.141) takes `isSyncing: Bool = false`: while true the button is replaced by a non-tappable row with a `ProgressView()` and the text "Syncing…" (a copy constant); while false it is the existing Sync button. A second tap cannot start a second sync. The "waiting for your phone" notice (51d) and the phone-status hint are unchanged.
- D-4 No change to the protocol, the phone, or the Dart twin. The logging surface is unchanged (it has no Sync button).

## Readers listed

- `WatchStartView.init` call sites (host `ContentView.swift` ~l.309, tests/previews: grep `WatchStartView(`); `WatchStartPaths` and the tests that read the Sync button text (grep `syncLabel`, `offersSync`, `WatchPhoneStatus`).
- `WatchNutritionWiringSourceTests.swift` reads `WatchStartView.swift` and `ContentView.swift` as text (S-7201/S-7205): a guard that names the Sync button line may need updating (list it).
- Scenario ids S-8501..S-8510 to be checked free by the builder.

## Core scenarios

`WatchSyncProgressTests.swift` (new; clock injected):
- S-8501 never begun: inactive. After `begin` at t=0: active.
- S-8502 `routines_down` at t=1, nothing else: active until t=3.0, inactive at 3.0 (quiet window 2 s measured from the newest arrival).
- S-8503 `routines_down` t=1 then `exercises_down` batches at t=2.5 and t=4: active until 6.0.
- S-8504 no arrival at all: active until the cap, inactive at t=20.0 exactly.
- S-8505 only `foods_down` arrives (no `routines_down`): stays active until the cap.
- S-8506 `begin` again while active changes nothing; `begin` after it ended starts a fresh one (arrivals before the new `begin` do not count).
- S-8507 an arrival of another type (`timer_state`, `receipt`) neither ends nor extends it.
Source guards in `WatchNutritionWiringSourceTests.swift` or a new `WatchSyncProgressWiringTests.swift`:
- S-8508 `ContentView.swift`: `requestSync` begins the progress before awaiting the orchestrator; `receive` arrivals are noted; the catch-up begins only under `.reachable`.
- S-8509 `WatchStartView.swift`: an `isSyncing` parameter exists, a `ProgressView` is in the file, the Sync button is not shown while syncing.

## Phases

- P1 `developer` — Swift: `WatchSyncProgress` + copy + S-8501..S-8507. Done: `swift test`.
- P2 `developer` — view and host wiring: D-2, D-3 and S-8508, S-8509. `xcodebuild` is the governor's. Done: `swift test`.
- P3 `developer` — docs (`docs/state_management/watch_surface_wrist.md`, the start-screen doc section) and plan Progress.
- Governor after P3: full `swift test`, `xcodebuild`, `flutter analyze`, docs tests, `prove-red`, review, commit per phase.

## Owner checks (owner)

- (owner) Press Sync on the watch: a spinner with "Syncing…" shows, then the button returns once the lists have arrived; raise the wrist beside the phone and see the same spinner during the automatic catch-up.

## Scope budget

About 80 production lines (Swift only), about 200 of test. One track, three phases.

---

# Planner expansion (2026-10-23, conductor-v2)

Everything above this line is the governor's seed, kept verbatim. Everything below is the planner's
expansion. Every file:symbol the seed cites was read and verified — see the evidence file for the
table; all actual line numbers sit within the seed's "~" tolerance (largest drift: `sync` is at
`WatchSyncOrchestrator.swift:94`, seed said ~l.84).

## Appended decisions (Ledger continues; D-5..D-7 are derived from D-1/D-2 and vetoable)

- D-5 Exact semantics of `WatchSyncProgress` (refines D-1, derived). A `struct` in the new
  `WatchSyncProgress.swift` with an injected clock `clock: () -> Date` (default `{ Date() }`);
  `begin()`, `noteArrival(type:at:)` and `isActive()` all read the clock, so tests advance it by
  hand (the `WatchSyncNoticeTests` pattern). Boundary math, pinned:
  - never begun → inactive; otherwise inactive when `now >= beganAt + capSeconds` (S-8504: inactive
    at t=20.0 exactly);
  - else, when a `routines_down` has arrived since `begin` and a newest reply arrival exists:
    inactive when `now >= newestArrival + quietSeconds` (S-8502: inactive at t=3.0 exactly);
    active otherwise. No arrival at all → active until the cap.
  - `begin()` while `isActive()` is true is a no-op (the running one continues); otherwise it resets
    `beganAt` and forgets every recorded arrival, so arrivals before a fresh `begin` never count
    (S-8506).
  - `noteArrival(type:at:)` records only the five reply types (`preferences_down`, `routines_down`,
    `foods_down`, `exercises_down`, `session_snapshot`); any other type is ignored (S-8507). Any
    later reply arrival overwrites the newest, whichever type it is; `routines_down` additionally
    sets the routines-arrived flag, in any arrival order (S-8510).
- D-6 The re-render mechanism (D-2 left the choice to the planner; derived, vetoable). The host
  publishes a dedicated `@Published private(set) var isSyncing` and drives it with a host-owned
  ticker task, not a `TimelineView`: `beginSyncProgress()` (one host helper) sets `isSyncing = true`
  at once, then starts (or restarts) a `Task` that, while `syncProgress.isActive(at: Date())`, sleeps
  0.5 s and re-assigns `isSyncing` from a fresh evaluation; when the evaluation is false it assigns
  false once and exits. Chosen over `TimelineView(.periodic(...))` because the ticker runs only
  while a sync is plausibly unfinished (no steady-state battery cost on the wrist) and because it
  bumps only `isSyncing`, never `revision` — the `$revision` sink in the host's `init` refreshes the
  workout coordinator and the sensors, and a 0.5 s tick must not spam it (guarded by S-8512).
  Arrivals need no ticker: `bridge.onIncoming` already bumps `revision`, and the view reads
  `host.isSyncing` at render.
- D-7 Copy homes (derived). The words "Syncing…" live in `WatchStartSurfaceCopy.syncingLabel`
  (`WatchStartPaths.swift`, beside `syncLabel` at l.37) — the start surface's copy home, testable on
  the desktop toolchain. Deliberately NOT added to
  `watch/contract/watch_start_paths_contract.json`: D-4 forbids a contract change, and the type
  already has the precedent of `unreachableLabel`, which is kept out of the contract for the same
  reason. The timing constants `quietSeconds` (2.0) and `capSeconds` (20.0) live in a
  `WatchSyncProgressCopy` enum in the new `WatchSyncProgress.swift`, mirroring `WatchSyncNoticeCopy`
  (`WatchSyncNotice.swift`).

## Existing-Functionality Impact

| Touched surface | What already reads it (grep that found it) | Effect | Guarded by |
|---|---|---|---|
| `WatchStartView.init` (`WatchStartView.swift` ~l.114) | `WatchStartView(` — the only code call site is `ContentView.swift:319` (the rest are docs/plans prose) | new `isSyncing: Bool = false` parameter, defaulted, so no call site breaks | S-8509 |
| `WatchStartView.body` Sync button block (`WatchStartView.swift:141-144`) | `WatchNutritionWiringSourceTests.testS7205LogFoodSitsRightUnderFreeWorkout` greps the `Self.syncLabel` line (`WatchNutritionWiringSourceTests.swift:276`); `WatchConnectivityBridgeTests.testS111…` greps `WatchPhoneStatusHint(status: phoneStatus)` in the same file | the button moves into the `else` branch of the new `isSyncing` split; the `Button(Self.syncLabel, action: onRequestSync)` line survives, so both guards keep passing — the reviewer re-runs both | S-8509, S-8511 |
| `WatchAppHost.requestSync` (`ContentView.swift:238`) | the Sync button's `onRequestSync` closure (`ContentView.swift:322`) | gains `beginSyncProgress()` before the `await`; no signature change | S-8508 |
| Catch-up call sites: `bridge.onReachabilityChange` (`ContentView.swift:166`) and `catchUpOnActivation` (`ContentView.swift:256`) | the scenePhase `.onChange` (~l.370) and the bridge handler itself | each gains a begin gated on the phone being `.reachable`, before `orchestrator.catchUp`; the in-flight guard inside `catchUp` is untouched | S-8508 |
| `bridge.onIncoming` (`ContentView.swift:155`) | every arriving frame | gains a `noteArrival` beside the existing `revision` bump; the `receive` routing is untouched | S-8508 |
| `WatchStartSurfaceCopy` (`WatchStartPaths.swift:29`) | `WatchSessionStartPathsTests` (l.536) and `testTheContractLabelsMatchWatchStartSurfaceCopy` (`WatchConnectivityBridgeTests`) | a new constant is additive; the contract file is not touched (D-4) | S-8509 + the existing tests |
| The host's `$revision` sink (`ContentView.swift`, `init`) | the workout/sensors refresh it drives | the ticker must never bump `revision`, or the refresh runs every 0.5 s during a sync | S-8512 |
| The Dart twin (`lib/watch/start/watch_start_screen.dart:57,80`) | grep `syncLabel|offersSync|WatchStartView` in `lib/` → this file only; it owns its own `syncLabel` constant | unaffected: D-4 forbids a Dart change, and the Dart start screen is a separate surface with its own copy | D-4 |
| `watch/contract/watch_start_paths_contract.json:344` | grep `syncLabel` in `watch/contract/` → this one value | unaffected: no contract change (D-4, D-7) | D-4 |

## Appended scenarios

### S-8510: reply batches arrive in any order
- Fixture: pure `WatchSyncProgress`, clock at t=0; `begin()` at t=0; `exercises_down` noted at t=1;
  `routines_down` noted at t=3.
- Trigger: `isActive()` queries around the quiet boundary.
- Flow: pure type, no view.
- Expected outcome: active at t=4.9; inactive at t=5.0 (quiet 2 s measured from the newest reply,
  t=3 — the routines gate does not care which reply came first).
- Edge case of: S-8503.

### S-8511: no transport, no spinner
- Fixture: the source of `WatchStartView.swift` (comment-stripped, the `WatchNutritionWiringSourceTests`
  pattern); conceptually a host whose `onRequestSync` is nil.
- Trigger: a render with `isSyncing` true.
- Flow: source guard.
- Expected outcome: no spinner row and no Sync button — the spinner row sits inside the same
  `if let onRequestSync, phoneStatus.offersSync` gate as the button, so a watch without a transport
  never shows either.
- Edge case of: S-8509.

### S-8512: the spinner ends by the clock, not by an arrival
- Fixture: the source of `ContentView.swift` (comment-stripped).
- Trigger: a sync whose replies never arrive (the S-8504 case, in the host).
- Flow: source guard.
- Expected outcome: the host re-evaluates `isSyncing` on a bounded tick while a sync is plausibly
  unfinished and stops when it ends; the tick assigns `isSyncing` only and never bumps `revision`
  (the `$revision` sink must not be ticked).
- Edge case of: S-8504, S-8508.

## Expanded phases

### P1 (@developer) — the pure type, its copy, and S-8501..S-8507 + S-8510

1. [x] Create `watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift` — `enum
  WatchSyncProgressCopy` (`quietSeconds = 2.0`, `capSeconds = 20.0`) and `struct WatchSyncProgress`
  per D-1, D-5, D-7: injected `clock: () -> Date` defaulting to `{ Date() }`; `begin()`,
  `noteArrival(type:at:)`, `isActive()`; the five reply types; the boundary math, the
  begin-no-op-while-active rule and the begin-resets rule exactly as D-5 pins them —
  `WatchSyncProgress` · `begin`, `noteArrival`, `isActive`
2. [x] Create `watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressTests.swift` — one test
   per scenario, clock advanced by hand (fixed base date + explicit offsets, the
   `WatchSyncNoticeTests` pattern): S-8501, S-8502, S-8503, S-8504, S-8505, S-8506, S-8507, S-8510 —
   `WatchSyncProgressTests` · one `testS85xx…` per scenario
3. [x] Prove each new test red against the stub it names, then green against the real type (record
   the red→green table in the evidence file). The mutation that turns each red:
   - S-8501: a stub whose `isActive` returns true before any `begin`.
   - S-8502: a stub measuring the quiet window from `begin` instead of the newest arrival (it would
     go inactive at t=2.0).
   - S-8503: a stub that ends on the *first* reply arrival instead of the newest (inactive at t=3.0
     instead of t=6.0).
   - S-8504: a stub with no cap (active forever when nothing arrives).
   - S-8505: a stub that lets any reply arrival satisfy the routines gate (would end at t=3.0 on a
     `foods_down` alone).
   - S-8506: a stub whose `begin` always resets (a second `begin` while active would restart the
     window), and one that keeps arrivals across a fresh `begin`.
   - S-8507: a stub that notes every type (a `timer_state` at t=2.5 would extend the window).
   - S-8510: a stub that requires `routines_down` to be the first reply.
4. [x] Run `.github/copilot/scripts/macos/gateway.sh swift-test`; paste the pass/fail counts into
   the evidence file.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` —
baseline 756 tests / 0 failures (evidence file); expect 756 + 8 new, 0 failures. No `xcodebuild` —
that is the governor's.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift` (new),
`watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressTests.swift` (new). Nothing else.

### P2 (@developer) — view and host wiring: D-2, D-3, D-6 and S-8508, S-8509, S-8511, S-8512

1. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` — add
   `public static let syncingLabel = "Syncing…"` to `WatchStartSurfaceCopy`, directly after
   `syncLabel` (l.37); do NOT touch `watch/contract/watch_start_paths_contract.json` (D-4, D-7) —
   `WatchStartSurfaceCopy` · `syncingLabel`
2. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` — `WatchStartView.init`
   (~l.114): add `isSyncing: Bool = false` after `syncNotice` and store it. `WatchStartView.body`
   (l.141): replace
   ```swift
                if let onRequestSync, phoneStatus.offersSync {
                    Button(Self.syncLabel, action: onRequestSync)
                        .buttonStyle(.bordered)
                }
   ```
   with the same gate, then inside it `if isSyncing { … ProgressView() +
   Text(WatchStartSurfaceCopy.syncingLabel) … }` (a non-tappable row — no Button, no action) `else {
   Button(Self.syncLabel, action: onRequestSync)… }`. Keep `Self.syncLabel` on its own line so
   S-7205's grep (`WatchNutritionWiringSourceTests.swift:276`) still finds it —
   `WatchStartView` · `init`, `body`
3. [ ] `ios/OmniTrain Watch App/ContentView.swift` — `WatchAppHost`: add `private let syncProgress
   = WatchSyncProgress()` (the default `{ Date() }` clock), `@Published private(set) var isSyncing
   = false`, `private var syncProgressTicker: Task<Void, Never>?`, and one helper
   `beginSyncProgress()` that sets `isSyncing = true`, calls `syncProgress.begin()` and starts (or
   restarts) the ticker task of D-6 (0.5 s tick; assigns `isSyncing` only; exits when
   `isActive(at:)` is false; never bumps `revision`) — `WatchAppHost` · `syncProgress`,
   `isSyncing`, `beginSyncProgress`
4. [ ] `ios/OmniTrain Watch App/ContentView.swift` — `requestSync()` (l.238): call
   `beginSyncProgress()` first, before `await orchestrator.sync(reconnect:…)` —
   `WatchAppHost` · `requestSync`
5. [ ] `ios/OmniTrain Watch App/ContentView.swift` — both catch-up call sites begin under
   `.reachable`, before `orchestrator.catchUp`: in the `bridge.onReachabilityChange` handler
   (l.166-173) gate on the handler's own `reachable`, and in `catchUpOnActivation()` (l.256-258) gate
   on `phoneReachability == .reachable` (the same condition the call already passes) —
   `WatchAppHost` · the `onReachabilityChange` closure, `catchUpOnActivation`
6. [ ] `ios/OmniTrain Watch App/ContentView.swift` — `bridge.onIncoming` (l.155-162): immediately
   after `guard let self`, note the arrival on the main actor (`MainActor.run {
   self.syncProgress.noteArrival(type: frame["type"] as? String ?? "", at: Date()) }`) BEFORE the
   `try await orchestrator.receive(frame)`, so a frame the watch refuses still counts as an arrival
   (the phone spoke; A-3) and a throw cannot skip it — `WatchAppHost` · the `onIncoming` closure
7. [ ] Create `watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressWiringTests.swift` —
   source guards over comment-stripped text (the `WatchNutritionWiringSourceTests` helpers pattern;
   a NEW file, not an edit of `WatchNutritionWiringSourceTests.swift` — plan 53 is mid-build in this
   tree and owns that file): S-8508 (`requestSync` begins before awaiting; arrivals are noted in
   `onIncoming`; both catch-up sites begin only under `.reachable`), S-8509 (`isSyncing` parameter
   with a default exists; a `ProgressView` is in the file; the Sync button is in the `else` branch),
   S-8511 (the spinner row is inside the `onRequestSync` gate), S-8512 (the ticker assigns
   `isSyncing` only, exits when inactive, never bumps `revision`). Red mutations: S-8508 red while
   `beginSyncProgress()` sits after the `await` in `requestSync`; S-8509 red while `isSyncing` has
   no default or no `ProgressView` exists; S-8511 red while the spinner row sits outside the gate;
   S-8512 red while the ticker bumps `revision` or never exits —
   `WatchSyncProgressWiringTests` · one `testS85xx…` per scenario
8. [ ] Run `.github/copilot/scripts/macos/gateway.sh swift-test`; paste the counts into the evidence
   file; confirm the pre-existing `testS7205LogFoodSitsRightUnderFreeWorkout` and `testS111…` guards
   still pass in the same run.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` — expect
P1's count + 4 new, 0 failures, with S-7205 and S-111 green in the same run. `xcodebuild` is the
governor's — never in agent Done Criteria.
**Predicted Files**: `WatchStartPaths.swift`, `WatchStartView.swift`,
`ios/OmniTrain Watch App/ContentView.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressWiringTests.swift` (new). Nothing
else.

### P3 (@developer) — docs and plan Progress

1. [ ] `docs/state_management/watch_surface_wrist.md` — extend "The wrist's start surface, and what
   an arrival does to it" (l.142) with a short paragraph: the Sync button becomes a non-tappable
   spinner row ("Syncing…") while a sync is plausibly unfinished — `WatchSyncProgress` ends it when
   a `routines_down` has arrived and the replies have been quiet 2 s, or at a 20 s cap; the same
   spinner runs for the automatic catch-up; it is clock-driven, so it ends even when no reply ever
   comes. The doc is ~34 KB, inside the 52 KB band — no split needed
2. [ ] `docs/README.md` — extend the `watch_surface_wrist.md` summary clause (l.87) with the sync
   progress spinner, so the index matches the doc
3. [ ] Plan housekeeping: tick the Progress items below with their results, paste the final suite
   counts into the evidence file, and leave the Assumption Log entries for the reviewer's
   adjudication (RATIFY/REVERT)

**Done Criteria**: the doc section and index clause exist; Progress and Assumption Log updated. The
64 KiB doc rule is enforced by `test/docs_indexing_contract_test.dart`, which runs in the governor's
full `flutter test` after P3 — the gateway has no file-size check, so it is not an agent-side Done
Criterion (Open question 3).
**Predicted Files**: `docs/state_management/watch_surface_wrist.md`, `docs/README.md`, this plan
file, the evidence file. Nothing else.

## Files Affected (whole feature)

- `watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift` — new (P1)
- `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` — edit (P2)
- `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` — edit (P2)
- `ios/OmniTrain Watch App/ContentView.swift` — edit (P2)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressTests.swift` — new (P1)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressWiringTests.swift` — new (P2)
- `docs/state_management/watch_surface_wrist.md` — edit (P3)
- `docs/README.md` — edit, one clause (P3)
- this plan + its evidence file — planner/implementers (all phases)

## Notes

- Phase dependency graph: P1 → P2 → P3, strictly. P2 compiles against P1's type; P3 documents P2's
  behaviour. No re-ordering is offered: running P2 first would leave the host wiring red against a
  missing type.
- Intermediate state after P1: `WatchSyncProgress` exists with no production reader — dead code for
  exactly one phase, acceptable and expected; the reviewer should not flag it at the P1 checkpoint.
- Legacy handling: none — no persisted field, table, route or shared constant changes; the only
  state is the host's in-memory progress (D-4).
- The governor's post-P3 list stands as seeded: full `swift test`, `xcodebuild`, `flutter analyze`,
  docs tests, `prove-red`, review, commit per phase.
- The owner check (spinner on press Sync; spinner during the automatic catch-up) needs
  `xcodebuild` + a watch simulator — the governor's, per the seed.

## Progress

- [x] P1 — type + copy + S-8501..S-8507, S-8510 (result: 8 new tests; full `swift-test` 778 tests / 0 failures; each scenario red-proved by mutation — evidence file)
- [ ] P2 — view and host wiring + S-8508, S-8509, S-8511, S-8512 (result: —)
- [ ] P3 — docs and plan Progress (result: —)

## Assumption Log

- A-1 (planner, derived from D-4): "Syncing…" is not a contract value. Options: add it to
  `watch_start_paths_contract.json` or keep it package-side. Chose package-side
  (`WatchStartSurfaceCopy.syncingLabel`) because D-4 forbids a contract change and
  `unreachableLabel` sets the precedent. Vetoable before P2.
- A-2 (planner, fills D-2's open choice): the re-render is a host-owned ticker task, not
  `TimelineView`. Options: periodic `TimelineView` (always ticking, simpler) vs a bounded task
  (ticks only while plausibly active, cannot spam the `$revision` sink). Chose the task (D-6).
  Vetoable before P2.
- A-3 (planner, derived from D-1's "arrivals"): a reply frame the watch refuses still counts as an
  arrival — the phone spoke, so the wait may end. Options: note before `receive` vs only on a
  successful apply. Chose before, so a throw cannot skip the note. Vetoable before P2.
- A-4 (planner, derived from D-2's "the catch-up path"): BOTH catch-up call sites begin the
  progress — the reachability edge (`onReachabilityChange`, l.166) and activation
  (`catchUpOnActivation`, l.256) — not just the named one; they are the same trigger (D-96).
  Vetoable before P2.
- A-5 (P1, resolves D-1 vs D-5's signatures): the type carries both forms — `begin()` / `isActive()`
  read the injected clock (D-5, and what the tests use) and `begin(at:)` / `isActive(at:)` take the
  time explicitly (D-1, and what D-6's host ticker calls). Options: only one pair. Chose both; the
  `at:` overloads are one line each.
- A-6 (P1, beyond D-5): `noteArrival` ignores an arrival while the sync is not running, so a
  straggler reply after it finished cannot revive the window. D-5 pins only the type filter.
  Options: record unconditionally, or gate on activity. Chose the gate; the register has no scenario
  for it, so it is unproven by mutation (evidence file) — flagged for P2's reviewer.

## Open questions

1. Seed line drift, no correction made: every cited symbol was read and exists; actual lines are
   `sync` at `WatchSyncOrchestrator.swift:94` (seed ~l.84), `receive` at l.161 (~l.168),
   `requestSync` at `ContentView.swift:238` (~l.227), `catchUpOnActivation` at l.256 (~l.262), the
   `WatchStartView(` call site at l.319 (~l.309), the Sync button at `WatchStartView.swift:141`
   (exact). All within "~" tolerance; kept as written per the brief.
2. The seed's reader list says "Scenario ids S-8501..S-8510" but defines only S-8501..S-8509. I
   defined S-8510 as the any-order arrival scenario (above). If the governor meant a different
   S-8510, renumber before P1.
3. The gateway has no file-size check, so the 64 KiB doc rule (`test/docs_indexing_contract_test.dart`)
   is verified only in the governor's full `flutter test`; P3's agent-side Done Criteria omits it
   for that reason.
4. The seed offers "WatchNutritionWiringSourceTests.swift or a new WatchSyncProgressWiringTests.swift"
   for the S-8508/S-8509 guards. Chose the new file because plan 53 is mid-build in this tree and
   already owns edits to `WatchNutritionWiringSourceTests.swift` (its S-8311/S-8312/S-8318 guards
   are in it); a separate file avoids colliding with uncommitted work.
5. Shell: no denied command was needed; the only shell use was the gateway (`list`, `swift-test`).
