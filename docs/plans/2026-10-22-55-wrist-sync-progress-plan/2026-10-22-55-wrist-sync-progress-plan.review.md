# Review: plan 55 — the watch shows a spinner while syncing

Reviewer: code-reviewer (Copilot CLI). Base: d0101e0d3b2974ee2217c47a81da06f0fe71c805. P1+P2 committed, P3 docs in the working tree.

## Findings

(appended as found)

## Scope

Layers in scope: watch package (`WatchSessionEngine` sources + tests), the watch app host (`ios/OmniTrain Watch App/ContentView.swift`), docs.
Layers skipped: Dart models/persistence/state/features/core (no `lib/` file changed), UI standards scans (no Dart UI or allowlist file in the diff).

Diff vs Predicted Files: conforms — the 10 changed files are exactly the plan's "Files Affected" plus the plan and evidence files themselves. No out-of-bounds file, no unfinished predicted file.

Test run: `gateway.sh swift-test` → **784 tests, 0 failures** (log `.work/gateway/swift-test-20261023-015600-20475.log`). `testS7205LogFoodSitsRightUnderFreeWorkout`, `testS111TheSurfaceSaysConnectedOrUnreachableOnlyAfterObservingIt` and both `testS6507` host-hop guards ran and passed in the same run (log l.141-142, 466-469, 841-842).

Red proof spot-check: `gateway.sh prove-red d0101e0d swift-test --filter WatchSyncProgressWiringTests -- <wiring test file>` → 6 tests, 12 failures at the base, each for the reason it guards (log `.work/gateway/swift-test-20261023-015540-19999.log`). P1's type does not exist at the base, so `prove-red` cannot compile there; the evidence file's mutation table (9 mutations, each red then green) covers S-8501..S-8510 and was accepted in its place.

### Findings

1. minor | `watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift:100` | Brief check (a), long-batch case: with `routines_down` at t=1 and `exercises_down` batches more than 2 s apart (t=2.5, t=4, t=6.5…), the window ends at newest+2 s (t=6.0) while batches are still arriving, and the A-6 activity gate makes `noteArrival` ignore every later batch, so the spinner never revives — it can end too early, but it can never fail to end (the 20 s cap bounds every path). This is the pinned D-1/D-5 semantics (S-8503 covers only gaps under 2 s), not a deviation; no change requested — owner to confirm a >2 s inter-batch gap is acceptable on real hardware. | @owner
2. minor | `watch/watchos/Sources/WatchSessionEngine/WatchSyncProgress.swift:83` | Brief check (a), early-`routines_down` case: a `routines_down` that arrives before the window opens does not count (`begin` forgets all earlier arrivals, S-8506), so if the phone does not re-send `routines_down` for the catch-up the spinner runs to the full 20 s cap and then ends — bounded, never stuck; correct per the plan. | @owner
3. minor | `docs/watch_session_sync.md:291` | Incomplete (4d): the catch-up section is silent on the spinner the catch-up now shows; it says nothing false ("without the user pressing anything" still holds). Remedy: one clause pointing at the wrist doc's new paragraph, or accept the wrist doc as the spinner's home. | @developer (P3 follow-up)

No blocker, no major. Critical count: 0.

### Brief checks

- (a) Walked both cases — see findings 1 and 2. The spinner can end too early (long batch gaps); it can never fail to end (cap).
- (b) Host threading: `WatchAppHost` is `@MainActor` (ContentView.swift:19-20); `onIncoming` notes the arrival inside `MainActor.run` before `receive`; the `onReachabilityChange` closure is a non-Sendable closure formed in the `@MainActor` init and so inherits the isolation (same pattern as its pre-existing direct `revision += 1`, guarded by `testS6507TheReachabilityHandlerStillBumpsRevisionDirectly`); the ticker `Task` inherits `@MainActor`, is cancelled and replaced on every `beginSyncProgress`, and assigns `isSyncing` only — never `revision` (guarded by S-8512). PASS.
- (c) All three begin sites wired: `requestSync` (before the `await`), `onReachabilityChange` (`if reachable`), `catchUpOnActivation` (`if reachable`, same condition `catchUp` gets). Reachable-edge flapping: the second `begin` is a no-op while the window is active (`begin(at:)` guards on `isActive`), so a running window is not restarted; only a begin after it ended opens a fresh one. PASS.
- (d) The spinner row sits inside the `if let onRequestSync, phoneStatus.offersSync` gate (WatchStartView.swift:147-163; guarded by S-8511). S-7205 and S-111 pass in the full run. PASS.
- (e) Other builders/readers: the only code call site of `WatchStartView(` is `ContentView.swift:386`, updated with `isSyncing: host.isSyncing`; the Dart twin (`lib/watch/start/watch_start_screen.dart`) owns its own `syncLabel` and is deliberately untouched (D-4); `watch/contract/watch_start_paths_contract.json` is untouched (D-7, A-1). No inconsistency left.
- (5) Test names base vs tree: the diff touches no existing test file — zero removed or renamed; 14 new tests in two new files (8 + 6).

### Assumption Log adjudication

- A-1, A-2, A-3, A-4: RATIFY (each verified against the shipped code; promote A-1 and A-2 to numbered decisions — they bind future surface work).
- A-5 (both `begin`/`begin(at:)` pairs): RATIFY — one line each, both used (tests use the clock form, the host the `at:` form).
- A-6 (`noteArrival` gated on activity): RATIFY — consistent with D-5's "straggler must not revive"; note it is the mechanism behind finding 1's no-revive behaviour.
- A-7 (`let type` before the `MainActor.run` hop): RATIFY — correct strict-concurrency reasoning, behaviour identical.
- A-8 (tick interval host-side): RATIFY — P2 may not edit P1's file; the constant is guarded by S-8512.

### DOC FALSIFICATION

DOC FALSIFICATION: ✅ PASS (2 updated: watch_surface_wrist.md, README.md — every symbol and test name they cite exists) + 1 incomplete (finding 3).

### DOC STANDARD

DOC STANDARD: ✅ PASS — the new paragraph names constants, not values (§3.4), points at the 13 S-85xx tests instead of restating behaviour, and adds no walkthrough, inventory, roadmap or unshipped note.

### Verdict

No blocker or major finding; the three minors are owner confirmations and one optional doc clause.

VERDICT: APPROVE
