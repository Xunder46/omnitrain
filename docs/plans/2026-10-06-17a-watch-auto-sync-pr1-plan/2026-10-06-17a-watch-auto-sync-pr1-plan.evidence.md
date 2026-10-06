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
| 2 | gateway `test test/watch_session_engine_test.dart test/watch_logging_timers_test.dart` | 42 passed, 0 failed | S-77 / S-78 / S-79 / S-81 |
| 2 | gateway `test test/watch_session_projection_test.dart` | 29 passed, 0 failed | S-40's premise updated — why, in the Phase 2 section |
| 2 | gateway `test` (full) | 3990 passed, ~1 skipped, 0 failed | baseline 3979 (~1 skipped) + 11 new Dart tests |
| 2 | gateway `swift-test` | 315 passed, 0 failed | baseline 302 + 13 new Swift tests |
| 2 | gateway `lint` | 196 issues, 0 errors | same count as baseline; none in a touched file |
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

## Phase 2 — wrist acceptance rules (S-77 / S-78 / S-79 / S-81)

The same rules in both engines: D-78 (a snapshot naming another session is refused whole while the
wrist runs its own), D-79 (a session-scoped phone frame may only name the session the wrist holds),
D-80 (a countdown belongs to whoever started it). Step 10 (`PROTOCOL.md`) is the governor's: the
session-switch bullet, the timer-state paragraph and the version history were amended to state all
three, each citing tests that exist by name.

Both engines enforce the refusal **before** anything is stored or emitted, and before the wrist's
session-end bookkeeping runs — that ordering is what mutation (e) below pins.

### Mutations — Dart engine (`lib/watch/session/watch_session_engine.dart`)

| # | Original line | Mutant | Red | Green |
|---|---|---|---|---|
| M1 | `if (held != null &&` (`_applySnapshot`, the D-78 refusal) | `if (false && held != null &&` | `--plain-name S-77`: `1 failed` — `S-77 a snapshot for another session changes nothing and says nothing` → `Expected: false / Actual: <true>` … `the phone is in its own session`; both counter-cases (`once the wrist has finished`, `a wrist with an empty ladder reserves nothing`) stayed green | restored → 42 passed, 0 failed |
| M2 | `if (!_guardSession(envelope)) return false;` in `_applyLifecycle` | `if (false) return false;` | `--plain-name S-78`: `2 failed` — `a lifecycle for another session concerns nobody here` and `an advanced position for another session moves nothing`, both `Expected: false / Actual: <true>` … `D-79`; the timer-state, structure-change and exercise-push S-78 tests stayed green (their guards live in other methods, untouched by the mutant) | restored → 42 passed, 0 failed |
| M3 | `return authoritative && _senderWroteTimer(kind)` (`_timerActionFor`) | `return authoritative` | `--plain-name S-79`: `1 failed` — `S-79 a snapshot leaves the wrist's countdown running and stops the phone's own` → `Expected: 'af14f1c1-…' Actual: 'tms-snap-msg-1-rest'` … `the wrist started it, so the phone is not speaking about it`; `S-79 a kind named null is still cleared` stayed green | restored → 42 passed, 0 failed |

Each original was restored exactly; `git-diff --stat -- lib/watch/session/watch_session_engine.dart`
reports the same 58 changed lines (47 insertions, 11 deletions) before and after the three mutants.

### Mutations — Swift engine (`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`)

| # | Mutant | Red | Green |
|---|---|---|---|
| a | the D-78 refusal removed from the snapshot path | both S-77 refusal tests red (9 assertion failures in total: stored rows, echoed messages and held position all moved); the two counter-case tests green | 315 passed, 0 failed after restore |
| c | the D-79 guard removed from `applyLifecycle` | exactly `testS78ALifecycleForAnotherSessionConcernsNobodyHere` and `testS78AnAdvancedPositionForAnotherSessionMovesNothing` red | as above |
| d | the unnamed-kind branch in `adoptTimers` back to `\|\| authoritative` | exactly `testS79ASnapshotLeavesTheWristsCountdownRunningAndStopsThePhones` red (3 failures); `testS79AKindNamedNullIsStillCleared` green | as above |
| e | the refusal moved **after** `captureSessionEnd` | `testS77ARefusedSnapshotDoesNotEndASessionTheWristCreatedEarlier` → `XCTAssertEqual failed: ("1") is not equal to ("0") - a refused snapshot captures no end…` → `Executed 1 test, with 1 failure (0 unexpected)` | as above |

Mutation (e) is invisible unless the wrist holds a **foreign-named session it created itself and has
not ended**: `engine.observations` filters by the held session's id (`WatchSessionEngine.swift:129`),
so an end appended for the *other* session cannot be seen through the accessor. The test therefore
compares `harness.store.readAll().observations.count` across the refused frame. The plan's own S-77
fixture (a wrist mid-workout on a session the phone created) cannot tell this mutant apart — its
session is phone-sourced, so `captureSessionEnd` declines it anyway.

### Pre-existing test updated: S-40 in `test/watch_session_projection_test.dart`

The plan's Existing-Functionality Impact and the brief's candidate list did **not** name this file; it
went red in the first full-suite run:

```
test/watch_session_projection_test.dart: S-31…S-43 … S-40 two sessions do not share entries [E]
```

(the run is `.work/gateway/test-20261006-183900-14280.log`, line 1331)

It applied a foreign `sess-2` snapshot while the wrist held an active `sess-1` with entries — i.e. it
pinned the wholesale-adoption rule D-78 supersedes, which the brief explicitly permits updating. The
fix is one added `await engine.finishSession();` (plus a comment) after the `sess-1` assertions, which
moves the switch into the D-78 counter-case; **every original assertion is unchanged** and the file
runs 29 passed, 0 failed.

### Final runs on the frozen tree

After every edit (both engines, all test files, `PROTOCOL.md`, the plan and this file):

| Command | Output |
|---|---|
| gateway `test` | `01:40 +3990 ~1: All tests passed!` — 3990 passed, ~1 skipped, 0 failed (exit 0) |
| gateway `swift-test` | `Executed 315 tests, with 0 failures (0 unexpected)` (exit 0) |
| gateway `lint` | `196 issues found. (ran in 1.6s)` — 0 errors; none in a touched file |
| gateway `test test/watch_session_engine_test.dart test/watch_logging_timers_test.dart test/docs_indexing_contract_test.dart` | `+51: All tests passed!` |
| `grep import .*hive_workout_repository` under `lib/state lib/features lib/widgets lib/core` | no matches |
| gateway `git-diff --stat` | 11 files, +1183 / −25: the seven phase files, `PROTOCOL.md` (step 10), the S-40 line, and the plan + this file. **No fixture changed** — the brief's "stop and report if the fixture pins the old rule" case did not arise: `fixtures/reconciliation/session_switch.json` has the receiver holding a **finished** session, which is exactly D-78's counter-case, so it still converges (`WatchLiveMirroringTests.testEveryReconciliationFixtureConverges` is green) |

## Phase 3A — the phone's push (S-70 … S-76, S-80, S-81, S-83, S-84)

The push is one seam, `WatchSessionAutoPush` (`lib/state/watch/watch_session_auto_push.dart`), bound
in `lib/main.dart` beside the adoption bind and reached from `WatchSyncGraph.autoPush`. It listens to
`WorkoutState`, coalesces every notification inside a trailing 250 ms window into at most one frame,
compares the frame's canonical encoding with the last one it sent, and re-baselines after every frame
the phone applies from the wrist (D-82). The end rules read the mirrored session's own repository row,
never the current-session pointer (D-81).

| Command | Output |
|---|---|
| gateway `test test/watch_session_auto_push_test.dart` | `+13: All tests passed!` — 13 passed, 0 failed (exit 0) |
| gateway `test test/watch_session_projection_test.dart` | `+30: All tests passed!` — 30 passed, 0 failed (exit 0) |
| gateway `test test/watch_session_finish_test.dart` | `+8: All tests passed!` — 8 passed, 0 failed (exit 0) |
| gateway `test` (full) | `+4004 ~1: All tests passed!` — 4004 passed, ~1 skipped, 0 failed (exit 0; `.work/gateway/test-20261006-194505-53273.log`, re-run after the doc edits at `.work/gateway/test-20261006-195104-60091.log`, same count) |
| gateway `lint` | `196 issues found. (ran in 2.6s)` — 0 errors, none in a touched file (the first run showed 4 in the new test file: two `unnecessary_import`, two `unused_import`; removed) |
| gateway `swift-test` | `Executed 315 tests, with 0 failures (0 unexpected)` (exit 0; no Swift source changed) |
| gateway `git-diff --name-only` | `lib/main.dart`, `lib/state/watch/live_session_mirror_state.dart`, `lib/state/watch/watch_sync_wiring.dart`, `test/watch_session_finish_test.dart`, `test/watch_session_projection_test.dart`, `watch/sync_protocol/PROTOCOL.md` — all Predicted Files, plus the governor's `PROTOCOL.md` addition; the two new files (`lib/state/watch/watch_session_auto_push.dart`, `test/watch_session_auto_push_test.dart`) are both predicted and untracked |
| `grep import .*hive_workout_repository` under `lib/state lib/features lib/widgets lib/core` | no matches |

Two fixture facts the register did not anticipate and the tests now pin: a logged set writes **two**
observation rows (reps and weight), so counting the phone's entries means filtering
`MetricIds.reps`; and entry numbering is "highest existing group + 1", so with the wrist's two merged
sets in groups 0 and 2 the phone's next set is numbered **3** (S-80 asserts `entry-sx-1-3`).

### Mutations (each applied to source, seen red, restored exactly, re-run green)

| # | Mutant | Files it turned red | Restored |
|---|---|---|---|
| a | the payload-equality gate off — `_baseline = encoded;` unconditional | 6: S-70, S-74, S-80, S-81 (replay), S-83, S-84 | yes |
| b | `projectedSession()` back to `projection(null)` (slot 0) | 1: S-76 — `Expected: <2> Actual: <0>` | yes |
| c | `abandoned` keyed on the current-session pointer instead of the mirrored row | 1: S-84 — an `abandoned` lifecycle emitted while browsing history | yes |
| d | `await push.rebaseline()` removed from `onIncoming` | 1: S-80 — 3 snapshots instead of 2 | yes |
| e | the trailing window ignored — `scheduleMicrotask(() => unawaited(flush()))` in `_onChanged` | 4: S-72 (2 lifecycle frames), S-73 (2), S-75 (2 snapshots), S-81 lifecycle ("Too many elements") | yes |

Mutation (e) needed three attempts, and the honest record is that the first two were not mutations of
the observed behaviour. A synchronous `unawaited(flush())` in `_onChanged` composes its payload before
the repository writes are visible and sends **zero** frames — every test reports `Actual: []`, which
is a fixture artifact, not the window's absence. `Timer(Duration.zero, …)` coalesces the whole burst
exactly as the 250 ms window does, so all 13 stayed green. Only the microtask form — one frame per
microtask batch — actually removes the coalescing and is red. The original line
`_window = Timer(_debounce, () => unawaited(flush()));` was restored and the file re-run green.

### The register's place in the plan is taken over by a place-only frame (A-10, A-11)

`projectedSession()` passes `{'payload': {'currentExerciseIndex': …}}`: the projection reads the place
out of `incoming['payload']['currentExerciseIndex']`, and the mirror's own payload carries the
placeholder's `sessionId`, which the D-10 gate rejects — so the literal `_projection?.call(state)`
yields a null session and no push. Mutation (b) is the difference in one line. S-76 sits in
`test/watch_session_projection_test.dart` (A-11); `test/live_mirroring_test.dart` was not changed.

### Red → green (a bug-fix test must fail without its fix)

| Scenario | What was stashed | Failing run | Passing run |
|---|---|---|---|
| S-76 (D-77) | the `projectedSession()` place-keeping change (mutation b) | 1 failed / 29 green (`Expected: <2> Actual: <0>`) | 30 passed, 0 failed |
| S-77 (D-78) | the foreign-snapshot refusal (Dart M1; Swift a) | Dart: `--plain-name S-77` 1 failed / 2 green. Swift: two S-77 tests red, 9 assertions | Dart 42 passed, Swift 315 passed, both 0 failed |
| S-78 (D-79) | the session guard in the lifecycle path (Dart M2; Swift c) | Dart: `--plain-name S-78` 2 failed / 3 green. Swift: 2 tests red | as above |
| S-79 (D-80) | the timer-ownership test (Dart M3; Swift d) | Dart: `--plain-name S-79` 1 failed / 1 green. Swift: 1 test red (3 failures) | as above |
| S-81 (D-78/D-79) | the refusals above are the ones S-81's re-delivery case rides on; no separate mutant — see the Phase 2 section | — | as above |
| S-74 (D-76) | the payload-equality gate (mutation a; also red for S-70, S-80, S-81, S-83, S-84) | 6 failed / 7 green | 13 passed, 0 failed |

## Residue sweeps

| Sweep | Command | Result |
|---|---|---|
| copy removed from all three sources | grep `noAutoSyncLabel` under `lib/`, `test/`, `watch/` | |
| the hint widget cannot return | grep `NoAutomaticSyncHint` under `lib/`, `test/`, `watch/` | |
| no doc still claims sync is manual | grep (list the terms used) in `docs/` | |
| nothing outside the Predicted Files changed | `.github/copilot/scripts/macos/gateway.sh git-diff develop --name-only` | Phase 3A: `lib/main.dart`, `lib/state/watch/live_session_mirror_state.dart`, `lib/state/watch/watch_sync_wiring.dart`, `test/watch_session_finish_test.dart`, `test/watch_session_projection_test.dart` — all predicted — plus `watch/sync_protocol/PROTOCOL.md` (the governor's addition). The two new files are predicted and untracked. `test/live_mirroring_test.dart` is unchanged (A-11) |
| no concrete persistence in state/UI/core | grep `import .*hive_workout_repository` under `lib/state lib/features lib/widgets lib/core` | no matches |
| the refusal can only run first | grep `captureSessionEnd` in `WatchSessionEngine.swift` | 5 hits: the definition (`:1221`), three call sites (`:467` snapshot, `:567` lifecycle, `:950` local end), and the comment at `:457` recording that the snapshot call sits *after* the refusal |

## Historical note (do not edit the old file)

`docs/plans/2026-10-04-14-watch-shell-bridge-plan/…evidence.md:308` records a mutation check "delete
`WatchNoAutomaticSyncHint()` from `WatchStartView.body`". That struct no longer exists after Phase 1;
the row is history.
