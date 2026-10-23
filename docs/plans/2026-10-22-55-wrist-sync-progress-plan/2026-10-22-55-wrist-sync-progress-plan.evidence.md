# Evidence — plan 55 (the watch shows a spinner while it is syncing)

Implementers append here: baselines, suite outputs, red→green tables, footprints.
The plan holds one-line results only.

## Baselines (planner, 2026-10-23)

- Base commit: `39915055bc99f0ca1153d35e35771d2e83333d4c` (`.work/2026-10-22-55/base.txt`).
- `swift test --package-path watch/watchos` (gateway `swift-test`, run 2026-10-23 00:03:33):
  **756 tests, 0 failures** (2.697 s). Full log: `.work/gateway/swift-test-20261023-000332-7988.log`.
- `flutter analyze` / `flutter test`: not run by the planner (no Dart file changes; the governor runs
  them after P3). Plan 53 is mid-build in the same tree — its uncommitted files are not this plan's
  baseline.

## Seed citation verification (planner, 2026-10-23)

Every file:symbol the seed cites was read at the base commit:

| Seed cite | Found at | Verdict |
|---|---|---|
| `WatchSyncOrchestrator.sync` ~l.84 | `WatchSyncOrchestrator.swift:94` | within "~" |
| `receive` ~l.168 | `WatchSyncOrchestrator.swift:161` | within "~" |
| `requestSync()` ~l.227 | `ContentView.swift:238` | within "~" |
| `catchUpOnActivation` ~l.262 | `ContentView.swift:256` | within "~" |
| `WatchStartView(` call site ~l.309 | `ContentView.swift:319` (only code call site; grep) | within "~" |
| Sync button ~l.141 | `WatchStartView.swift:141-144` | exact |
| `WatchSyncNoticeCopy` (`WatchSyncNotice.swift`) | exists, `graceSeconds = 90` | exact |
| `WatchNutritionWiringSourceTests` reads both files as text (S-7201/S-7205) | confirmed; S-7205 greps the `Self.syncLabel` line at `WatchNutritionWiringSourceTests.swift:276` | exact |
| `offersSync` / `WatchPhoneStatus` | `WatchStartPaths.swift:81,106` | exact |

## Red→green tables (implementers fill)

### P1 — `WatchSyncProgressTests.swift`

Red proofs by mutation (the type does not exist at `HEAD`, so `prove-red` cannot compile the test
file there; the brief allows mutations instead). Each mutation was applied alone to
`WatchSyncProgress.swift`, run with `gateway.sh swift-test --filter WatchSyncProgressTests/testS85xx`,
then restored to the exact original line and the class re-run green.

| Scenario | Red against (stub/mutation) | Red run | Green run |
|---|---|---|---|
| S-8501 | `isActive(at:)` `guard let beganAt else { return true }` | `XCTAssertFalse failed - S-8501 a sync that never began is not running` (l.27), 1 failure | green |
| S-8502 | quiet window measured from `beganAt` instead of `newestReplyAt` | `XCTAssertTrue failed - S-8502 a tenth before the quiet window closes` (l.47), 1 failure | green |
| S-8503 | newest reply never replaced: `newestReplyAt = newestReplyAt ?? now` (ends on the first reply) | `S-8503 three seconds in, still running — the first reply did not end it` (l.69) + `S-8503 a tenth before the newest batch goes quiet` (l.78), 2 failures | green |
| S-8504 | cap line replaced by `_ = beganAt` (no cap) | `XCTAssertFalse failed - S-8504 inactive at the cap exactly` (l.95), 1 failure | green |
| S-8505 | routines gate dropped: `guard let newestReplyAt else` (any reply satisfies it) | `S-8505 two seconds after a foods reply alone…` (l.111) + `S-8505 still running just before the cap` (l.117), 2 failures | green |
| S-8506 (a) | `begin` always resets: the `guard !isActive(at: now)` line removed | `S-8506 begin while running did not restart the window (it would run until 3.5)` (l.136), 1 failure | green |
| S-8506 (b) | `routinesArrived = false` removed from `begin` (keeps the earlier sync's routines flag) | `S-8506 the earlier routines reply does not finish the fresh sync` (l.148) + `S-8506 a reply alone does not finish it…` (l.154), 2 failures | green |
| S-8507 | reply-type filter removed from `noteArrival` (notes every type) | `S-8507 the quiet window runs from the routines reply at 1.0, not the later timer state` (l.183), 1 failure | green |
| S-8510 | a `routines_down` only counts as the newest when it arrives first | `S-8510 a tenth before the newest reply goes quiet` (l.203), 1 failure | green |

Two notes for the reviewer:

- S-8506 was strengthened after the first red round: with the fresh `begin` at t=3 and no reply
  afterwards, dropping only `newestReplyAt = nil` was **not** observable (the routines reset already
  kept the sync active), so the fixture now sends an `exercises_down` at t=4 and the green run above
  is the strengthened test. Dropping `newestReplyAt = nil` alone is behaviourally equivalent while
  `routinesArrived` is reset — recorded, not claimed as proven.
- Not covered by any register scenario (A-6 in the plan): `noteArrival` ignores an arrival while the
  sync is not running. A mutation removing `isActive(at: now)` from that guard therefore stays green.


### P2 — `WatchSyncProgressWiringTests.swift`

| Scenario | Red against (mutation) | Red run | Green run |
|---|---|---|---|
| S-8508 | `beginSyncProgress()` after the `await` in `requestSync` | — | — |
| S-8509 | `isSyncing` without default / no `ProgressView` | — | — |
| S-8511 | spinner row outside the `onRequestSync` gate | — | — |
| S-8512 | ticker bumps `revision` / never exits | — | — |

## Suite counts (implementers paste)

| Phase | Check | Result |
|---|---|---|
| baseline | gateway `swift-test` | 756 tests, 0 failures (2026-10-23 00:03:33, commit `3991505`) |
| P1 baseline at `HEAD` | derived: the tree now holds plans 53 and 54 (commit `d0101e0d`), which added 14 tests | **770** tests before P1; `git-status` shows only the two new P1 files |
| P1 | gateway `swift-test --filter WatchSyncProgressTests` | 8 tests, 0 failures (2026-10-23 01:38:19) |
| P1 | gateway `swift-test` (full) | **778 tests, 0 failures** (2026-10-23 01:39:14; log `.work/gateway/swift-test-20261023-013914-5166.log`) |
| P2 | gateway `swift-test` | — |
| P3 | governor full `flutter test` (docs tests) | — |

P1 is Swift-only: `gateway.sh lint` (`flutter analyze`) and
`test/ui_standards_contract_test.dart` were not run because no Dart, UI or test-Dart file changed;
the `hive_workout_repository` grep invariant is likewise unaffected (no `lib/` file changed).

## Notes for the reviewer

- Pre-existing guards that read the touched files and must stay green: `testS7205LogFoodSitsRightUnderFreeWorkout`
  (`WatchNutritionWiringSourceTests.swift:276`, greps the `Self.syncLabel` line) and `testS111…`
  (`WatchConnectivityBridgeTests`, greps `WatchPhoneStatusHint(status: phoneStatus)` in
  `WatchStartView.swift`).
- After P1 the type has no production reader (dead until P2) — expected, not a finding at the P1
  checkpoint.
- Assumption Log entries A-1..A-4 (plan file) are the planner's derived interpretations, offered for
  veto before P2.
