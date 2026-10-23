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

| Scenario | Red against (stub/mutation) | Red run | Green run |
|---|---|---|---|
| S-8501 | `isActive` true before any `begin` | — | — |
| S-8502 | quiet window measured from `begin` | — | — |
| S-8503 | ends on the first reply, not the newest | — | — |
| S-8504 | no cap | — | — |
| S-8505 | any reply satisfies the routines gate | — | — |
| S-8506 | `begin` always resets / keeps old arrivals | — | — |
| S-8507 | notes every type | — | — |
| S-8510 | requires `routines_down` first | — | — |

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
| baseline | gateway `swift-test` | 756 tests, 0 failures (2026-10-23 00:03:33) |
| P1 | gateway `swift-test` | — |
| P2 | gateway `swift-test` | — |
| P3 | governor full `flutter test` (docs tests) | — |

## Notes for the reviewer

- Pre-existing guards that read the touched files and must stay green: `testS7205LogFoodSitsRightUnderFreeWorkout`
  (`WatchNutritionWiringSourceTests.swift:276`, greps the `Self.syncLabel` line) and `testS111…`
  (`WatchConnectivityBridgeTests`, greps `WatchPhoneStatusHint(status: phoneStatus)` in
  `WatchStartView.swift`).
- After P1 the type has no production reader (dead until P2) — expected, not a finding at the P1
  checkpoint.
- Assumption Log entries A-1..A-4 (plan file) are the planner's derived interpretations, offered for
  veto before P2.
