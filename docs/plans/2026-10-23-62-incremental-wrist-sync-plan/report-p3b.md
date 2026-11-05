# Report: plan 62, phase P3b — docs for D-8 (no spinner on an incremental raise) (crew-docs-keeper)

## Edits

1. `docs/state_management/watch_surface_wrist.md` — the "A sync is finished by its replies, not by the request." paragraph: the catch-up clause now reads "only when the phone is reachable and only when the wrist holds no routines catalog yet (plan 62: … the Sync button always opens the window)", and `…testS9221AnIncrementalCatchUpOpensNoWindow` joined its "Verified by" list.
2. `docs/watch-app-setup-and-qa.md` — QA step 23: added that a raise with nothing changed shows no syncing spinner, that a fresh install (nothing synced yet) still shows it and that tapping Sync shows it; the spinner gating is now named as held by `WatchSyncProgressWiringTests` (`testS8508CatchUpBeginsOnlyWhenReachable`, `testS9221AnIncrementalCatchUpOpensNoWindow`) beside the two existing test citations.
3. `docs/plans/2026-10-23-62-incremental-wrist-sync-plan/2026-10-23-62-incremental-wrist-sync-plan.evidence.md` — new "Fix 2 (D-8) — no spinner on an incremental catch-up" section with the brief's facts (window ends only on `routines_down`, cap 20 s; `paths.syncedAt != nil` gates the automatic catch-ups; first sync and Sync button still spin; the two tests; 874 tests / 0 failures; 5 gate mutants killed; defect found by the lead reading `WatchSyncProgress.swift` before review). The plan's Progress line gained "Fix 2 (D-8) done 2026-10-23; docs P3b done."

## Checks run

None (brief says: run NO test). Both named tests were read, not run: `watch/watchos/Tests/WatchSessionEngineTests/WatchSyncProgressWiringTests.swift` lines 166 (`testS8508CatchUpBeginsOnlyWhenReachable`) and 229 (`testS9221AnIncrementalCatchUpOpensNoWindow`); each asserts the exact gated statements in `ContentView.swift` (`if reachable && self.paths.syncedAt == nil { self.beginSyncProgress() }` at the edge, `if reachable && paths.syncedAt == nil { beginSyncProgress() }` in `catchUpOnActivation()`), which were confirmed in the source (lines 232, 367; `requestSync()` line 313 `await orchestrator.sync(reconnect: false)` with `beginSyncProgress()` at 311).

## Open questions

- Step 23 still says "Four checks": the spinner observations ride on the existing raise and Sync checks (the fresh-install spinner is the first-sync state of the raise check), so no fifth check was invented. If the owner wants the fresh-install spinner as its own device step, that is a product/QA decision, not a docs one.

## Governor actions

None.
