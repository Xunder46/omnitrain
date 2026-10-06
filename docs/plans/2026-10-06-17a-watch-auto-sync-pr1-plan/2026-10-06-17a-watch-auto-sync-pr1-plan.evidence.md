# Evidence — watch-auto-sync PR 1 (`17a`)

Plan: `2026-10-06-17a-watch-auto-sync-pr1-plan.md`. Implementers and the reviewer paste real command
output here; the plan holds no evidence.

## Baselines (before this PR, on the branch point)

| Command | Result | Date |
|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` | 3949 passing, ~1 skipped, 0 failures | 2026-10-06 |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues, 0 errors (pre-existing info notices) | 2026-10-06 |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 294 passing, 0 failures | 2026-10-06 |

## Per-phase results

| Phase | Command | Result | Notes |
|---|---|---|---|
| 1 | gateway `test test/watch_session_start_test.dart test/watch_transport_test.dart test/docs_indexing_contract_test.dart` | 64 passed, 0 failed | S-82 |
| 1 | gateway `test` (full) | 3979 passed, ~1 skipped, 0 failed | baseline 3980/~1 minus the one deleted Dart test |
| 1 | gateway `swift-test` | 302 passed, 0 failed | |
| 1 | gateway `lint` | 196 issues, 0 errors | same count as baseline; none in a touched file |
| 2 | | | |
| 3 | | | |

## Phase 1 — the contract amendment and the copy (S-82)

Implemented with two governor changes: A-1 (`watch/sync_protocol/PROTOCOL.md` is not edited — its rules
and cited tests arrive in Phases 2–3) and A-2 (`docs/watch-app-setup-and-qa.md` is not edited — "logging
is automatic" is true only after Phase 3). Phase steps 1 and 9 were therefore skipped by decision; steps
2–8 are done.

Nothing about what syncs changed: only the button's word ("Sync routines" → "Sync"), the removed
"No automatic sync" line, its widget in both stacks, and the fixture both stacks read. The button's
visibility rule (offered only when the app passes an `onRequestSync`) and its action are untouched.

### Mutation — the removed key returns to the fixture

Original line (`watch/contract/watch_start_paths_contract.json`):

```json
  "startSurface": {
    "syncLabel": "Sync"
  },
```

Mutant: put `"noAutoSyncLabel": "No automatic sync",` back as the first key of `startSurface`.

| Stack | Test that goes red | Observed output |
|---|---|---|
| Dart | `test/watch_session_start_test.dart` — `start surfaces › the sync action is offered only when the app can ask` (`:1030`, `expect(surface.containsKey('noAutoSyncLabel'), isFalse)`) | `Expected: false / Actual: <true>` … `The test description was: the sync action is offered only when the app can ask` → `00:00 +0 -1` … `+4 -1: Some tests failed.` |
| Swift | `WatchSessionStartPathsTests.testS082TheStartSurfaceSaysSyncAndCarriesNoAutomaticSyncLabel` (`:365`, `XCTAssertNil(surface["noAutoSyncLabel"])`) | `error: … :365: XCTAssertNil failed: "No automatic sync"` → `Executed 32 tests, with 1 failure (0 unexpected)` |

The exact original was restored afterwards and both suites re-ran green (Dart 64 passed; Swift 302 / 0).

### Residue sweeps (A-3: the deliberate absence guards are the only hits)

| Sweep | Result |
|---|---|
| `noAutoSyncLabel` under `lib/`, `test/`, `watch/` | only the three guards that assert it is gone: Swift `testS082…` + `testTheContractLabelsMatchWatchStartSurfaceCopy`, Dart `the sync action is offered only when the app can ask` |
| `NoAutomaticSyncHint` under `lib/`, `test/`, `watch/` | only the Swift `testS111TheSurfaceSaysUnreachableOnlyAfterObservingIt` view-source guard |
| `Sync routines` under `lib/`, `watch/`, `ios/` | no matches |
| `import .*hive_workout_repository` under `lib/state lib/features lib/widgets lib/core` | no matches |
| `git-diff --stat` | 7 files, +29 / −100; all within the phase's Predicted Files minus `PROTOCOL.md` and the QA doc |

## Red → green (a bug-fix test must fail without its fix)

| Scenario | What was stashed | Failing run | Passing run |
|---|---|---|---|
| S-76 (D-77) | the `projectedSession()` place-keeping change | | |
| S-77 (D-78) | the foreign-snapshot refusal | | |
| S-79 (D-80) | the timer-ownership rule | | |
| S-74 (D-76) | the payload-equality gate | | |

## Residue sweeps

| Sweep | Command | Result |
|---|---|---|
| copy removed from all three sources | grep `noAutoSyncLabel` under `lib/`, `test/`, `watch/` | |
| the hint widget cannot return | grep `NoAutomaticSyncHint` under `lib/`, `test/`, `watch/` | |
| no doc still claims sync is manual | grep (list the terms used) in `docs/` | |
| nothing outside the Predicted Files changed | `.github/copilot/scripts/macos/gateway.sh git-diff develop --name-only` | |

## Historical note (do not edit the old file)

`docs/plans/2026-10-04-14-watch-shell-bridge-plan/…evidence.md:308` records a mutation check "delete
`WatchNoAutomaticSyncHint()` from `WatchStartView.body`". That struct no longer exists after Phase 1;
the row is history.
