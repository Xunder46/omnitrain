# Evidence — Stats PR 3d (a late watch entry survives Discard)

> Companion to `2026-10-02-03d-stats-pr3d-late-watch-entry-plan.md`. Executors write here; the plan stays clean. Review findings go to `2026-10-02-03d-stats-pr3d-late-watch-entry-plan.review.md`.

## 1. Baselines (Step 0b)

Captured by the planner on 2026-10-02 with `.github/copilot/scripts/macos/gateway.sh`, on `develop`, before any change.

| Command | Final line (verbatim) | Exit |
|---|---|---|
| `gateway.sh lint` | `196 issues found. (ran in 3.0s)` | 1 (info-level only; **0 errors**) |
| `gateway.sh test` | `01:18 +3227 ~1: All tests passed!` | 0 |

These match the brief's expected baselines exactly (`196 issues found.` with 0 errors; `+3227 ~1: All tests passed!`). The lint exit code is 1 because the analyzer reports info-level lints; the error count is 0, and "no new issue" in every Done Criteria means the count stays at 196 with 0 errors.

**Executor (Phase 1, 2026-10-02, `develop`, HEAD `c25617a9`):** re-ran both before any change.

| Command | Final line (verbatim) | Exit |
|---|---|---|
| `gateway.sh lint` | `196 issues found. (ran in 3.1s)` | 1 (info-level only; **0 errors**) |
| `gateway.sh test` | `01:18 +3250 ~1: All tests passed!` | 0 |

The lint line matches the planner's exactly. The test line **differs**: the planner recorded `+3227 ~1`, the executor observed `+3250 ~1` — 23 more passing tests on the same commit. The plan's Executor block predicted `+3227 ~1`; the observed baseline is `+3250 ~1`, and every delta below is measured against the observed figure. The lint count is unchanged at 196 with 0 errors, so "no new issue" still means 196.

**Post-change lint (after the Phase 1 test file was added and formatted):** `196 issues found. (ran in 2.3s)` — identical count, no new issue.

## 2. Red → green table

Filled in by the executor. Phase 1 ends red by design; Phase 3 turns it green.

| Scenario | Test name | Phase 1 (red) | Phase 3 (green) |
|---|---|---|---|
| S-1401 | a late wrist set survives Discard, and the user's own set does not | FAIL (expected) | PASS |
| S-1402 | a late entry that creates a new effort brings its instance and its summary | FAIL (expected) | PASS |
| S-1403 | a late entry the user deleted during edit mode returns | PASS (expected) | PASS |
| S-1404 | a late entry the user edited returns as the wrist sent it | FAIL (expected) | PASS |
| S-1405 | two late entries both return | FAIL (expected) | PASS |
| S-1406 | a second sync after Discard duplicates nothing | FAIL (expected) | PASS |
| S-1407 | Discard with no structural change is a no-op | PASS (expected) | PASS |
| S-1408 | Save keeps the late entry and the user's edits | PASS (expected) | PASS |
| S-1409 | a deletion applied before edit mode stays deleted | PASS (expected) | PASS |
| S-1410 | a late phone correction and a late phone deletion are recovered too | FAIL (expected) | PASS |
| S-1412 | `clearWatchInboxApplied` behaves identically on both stores | FAIL (compile: method absent) | PASS |
| S-1413 | a session with no late entry is untouched by the recovery | PASS (expected) | PASS |
| S-1414 | a snapshot taken with no watermark recovers nothing | PASS (expected) | PASS |

Paste the Phase 1 run's final lines and the per-test failure list here, then the Phase 3 run's final lines.

### Phase 1 run (Step 0c) — `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart`

Final line, verbatim:

```
00:00 +12 -12: Some tests failed.
```

24 test cases (12 scenarios × 2 stores). The split is exactly the one the phase requires: 12 failures = the six listed scenarios on both stores; 12 passes = the other six on both stores.

**Failing (12) — 6 scenarios × {Mock, Hive}:**

| Scenario | Test name | Store | Observed failure |
|---|---|---|---|
| S-1401 | a late wrist set survives Discard, and the user's own set does not | Mock, Hive | `Expected: <3> Actual: <2>` — the wrist's three sets |
| S-1402 | a late entry that creates a new effort brings its instance and its summary | Mock, Hive | `Expected: [...] unordered Actual: ['effort-s-cap-1-sx-bjj-ex-bjj-round', 'effort-s-cap-1-sx-bench-ex-bench-set'] Which: has too few elements (2 < 3)` — the late run effort is back |
| S-1404 | a late entry the user edited returns as the wrist sent it | Mock, Hive | `Expected: [5, 80.0] Actual: [null, null]` — the late set reads the wrist's reps, not the user's 12 |
| S-1405 | two late entries both return | Mock, Hive | `Expected: <3> Actual: <2>` — the wrist's three sets are back |
| S-1406 | a second sync after Discard duplicates nothing | Mock, Hive | `Expected: <3> Actual: <2>` — the wrist's three sets, once each |
| S-1410 | a late phone correction and a late phone deletion are recovered too | Mock, Hive | `Expected: [9, 80.0] Actual: [5, 80.0]` — A: the corrected reps are re-imported, not undone |

**Passing (12) — 6 scenarios × {Mock, Hive}:** S-1403, S-1407, S-1408, S-1409, S-1413, S-1414. These assert behaviour the bug does not break, so they are green before the fix and must stay green after it.

S-1412 is Phase 2's; it is not in this file and is not counted here. Cross-store parity is asserted inside every scenario above, which runs on both stores with identical absolute expectations.

### Full suite after Phase 1 — `gateway.sh test`

Final line, verbatim:

```
01:20 +3262 ~1 -12: Some tests failed.
```

`+3262` = the observed baseline `+3250` plus the 24 new cases minus the 12 that fail by design. The only failing tests in the whole suite are the twelve above; every other test that passed at baseline still passes.

## 3. Inverse-edit mutations (Phase 3)

All three on tracked files, all reverted after, all recorded with their red run.

| # | Mutation | File | Test that must fail | Observed |
|---|---|---|---|---|
| M1 | Drop the watermark filter in the inbox's recovery (un-mark every applied row) | `lib/state/watch/watch_session_inbox.dart` | S-1409 | RED — S-1410 fails on both stores (`Expected: <2> Actual: <3>`, "the late deletion is re-applied"); S-1409 itself stays green because its re-send is a no-op. Reverted; stat back to `56 ++++ 55+ 1-`. |
| M2 | Remove the `clearWatchInboxApplied` call, or the `appliedAtMs != null` filter in it | `lib/state/watch/watch_session_inbox.dart` / `lib/data/repositories/hive_workout_repository.dart` | S-1401 | RED — S-1401 fails on both stores (`Expected: <3> Actual: <2>`, "the wrist's three sets — the late entry survives Discard"); 12 failures total. Reverted; stat back to `56 ++++ 55+ 1-`. |
| M3 | Move the recovery call in `restoreSessionSnapshot` to before the delete loops | `lib/state/workout/session_core_lifecycle.dart` | S-1401 | RED — S-1401 fails on both stores (`Expected: <3> Actual: <2>`); 12 failures total. Reverted; stat back to `33 ++++ 32+ 1-`. |

M1 is the mutation that proves the watermark is load-bearing: without it, a set the wrist deleted before edit mode is resurrected, which is the D-136 violation the design exists to avoid.

## 4. Doc-claim → test table (Phase 4)

Every behaviour sentence this PR adds to a doc, the file it is in, and the test that asserts it. Every row names a test that exists and passes; each S-id was opened in the test file and found (not taken from earlier evidence). The tests were run together in one command: `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart test/watch_capture_repository_parity_test.dart test/db_seed_test.dart` → `00:01 +69: All tests passed!`.

| Doc | Claim added | Test that asserts it | S-id found in the test |
|---|---|---|---|
| `docs/watch_session_capture.md` (Structure row) | `WatchLateEntryRecovery` is the inbox capability `SessionCore.restoreSessionSnapshot` calls on Discard; `createWatchSync` returns it in `WatchSyncGraph` and `lib/main.dart` hands it to `WorkoutState` | `test/watch_session_edit_restore_late_entry_test.dart` (S-1401) | yes — line 333 |
| `docs/watch_session_capture.md` (Rationale) | The restore un-marks exactly the late entry and runs one ordinary import pass; the un-mark is durable and the pass re-stamps it applied | `test/watch_session_edit_restore_late_entry_test.dart` (S-1401, S-1406) | yes — lines 333, 603 |
| `docs/watch_session_capture.md` (Invariant) | A wrist entry that arrived while an Edit Session was open survives Discard; no watermark recovers nothing; no late entry is untouched | `test/watch_session_edit_restore_late_entry_test.dart` (S-1401 to S-1410, S-1413, S-1414) | yes — lines 333–885 |
| `docs/data_models.md` | An applied stamp is unset when an Edit Session Discard has to recover an entry that arrived after the snapshot | `test/watch_session_edit_restore_late_entry_test.dart` (S-1401), `test/watch_capture_repository_parity_test.dart` (S-1412) | yes — lines 333, 524 |
| `docs/db_integration.md` | One write unsets an applied stamp; an unknown id and an unapplied row are skipped; nothing is created or deleted; the schema is unchanged | `test/watch_capture_repository_parity_test.dart` (S-1412), `test/db_seed_test.dart` | yes — line 524 |
| `docs/modality_based_exercise_ui.md` | Discard throws away the user's own edits but never a wrist entry that arrived while the screen was open | `test/watch_session_edit_restore_late_entry_test.dart` (S-1401 to S-1410) | yes — lines 333–885 |
| `docs/state_management/services_and_utils.md` | `WatchSyncGraph` carries a second handle, `WatchLateEntryRecovery`; `main.dart` hands it to `WorkoutState`, which passes it to the session core's restore | `test/watch_session_edit_restore_late_entry_test.dart` (S-1401 to S-1410) | yes — lines 333–885 |
| `docs/state_management/workout_state.md` | `WorkoutState` takes the optional recovery; a null handle leaves the restore as before; `lib/main.dart` builds `WorkoutState` after `createWatchSync` and `ExerciseLibraryState` after both | `test/watch_session_edit_restore_late_entry_test.dart` (S-1401 to S-1410, S-1414) | yes — lines 333–885 |

**Finding F-4.1 (fixed).** The Rationale sentence originally read "recovers it at its next start". That is false for a late set row: `WatchSessionInbox.resume` settles only sessions whose `session_end` row is unapplied (`getWatchSessionIdsWithUnappliedEnd`), and a late set on an already-ended session is not one of them. The sentence now says "at the next import pass for that session", which is what `WatchSessionImporter.apply` does with the un-marked row. Fixed in `docs/watch_session_capture.md`; no test change.

## 5. Residue sweep (Phase 4)

Grep `lib/` and `test/` for each name this PR added and list every hit's file. Every hit must be a file in the plan's Predicted Files or a test asserting the new behaviour.

| Name | Hits | Verdict |
|---|---|---|
| `watchEntryIdsAppliedAtSnapshot` | `lib/core/models/session_edit_snapshot.dart`, `lib/features/session/workout_session_screen.dart`, `lib/state/workout/workout_state.dart`, `lib/state/workout/session_core_lifecycle.dart`, `test/watch_session_edit_restore_late_entry_test.dart` | all Predicted Files or the probe — no finding |
| `appliedWatchEntryIds` | `lib/features/session/workout_session_screen.dart`, `lib/state/workout/workout_state.dart`, `lib/state/workout/session_core_lifecycle.dart`, `test/watch_session_edit_restore_late_entry_test.dart` | all Predicted Files or the probe — no finding |
| `clearWatchInboxApplied` | `lib/state/watch/watch_session_inbox.dart`, `lib/data/repositories/mock_workout_repository.dart`, `lib/data/repositories/workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`, `test/watch_capture_repository_parity_test.dart` | all Predicted Files or the parity test — no finding |
| `WatchLateEntryRecovery` | `lib/state/watch/watch_sync_wiring.dart`, `lib/state/watch/watch_session_inbox.dart`, `lib/state/workout/workout_state.dart`, `lib/state/workout/session_core.dart`, `test/watch_session_edit_restore_late_entry_test.dart` | all Predicted Files or the probe — no finding |
| `recoverEntriesAppliedSince` | `lib/state/watch/watch_session_inbox.dart`, `lib/state/workout/session_core_lifecycle.dart` | both Predicted Files — no finding |
| `lateEntryRecovery` | `lib/state/watch/watch_sync_wiring.dart`, `lib/state/workout/workout_state.dart`, `lib/state/workout/session_core.dart`, `lib/state/workout/session_core_lifecycle.dart`, `lib/main.dart` | all Predicted Files — no finding |

No hit lands in a file this PR did not touch. `lib/core/services/watch_session_importer.dart` is not among them.

Argument-free `snapshotSessionState()` call sites after this PR:

| File | Line context | Why argument-free |
|---|---|---|
| `lib/features/session/workout_session_screen.dart` | the edit-mode snapshot site (line 491) | **passes the watermark** — `watchEntryIdsAppliedAtSnapshot: watermark`, read at line 425 before `loadSessionData()` at line 432. No finding. |
| `test/session_summary_distance_test.dart` | line 731 | deliberate (D-803) |
| `test/watch_session_edit_restore_summaries_test.dart` | lines 240 and 456 | deliberate (D-803) |

The only `lib/` call site is the screen's, and it passes the watermark. No reader of the old behaviour remains in `lib/`.

## 6. Unmodified-file confirmations (Phase 4)

`gateway.sh git-status` must show none of these as changed. Observed 2026-10-03: the status lists exactly the 18 modified files of this PR plus the untracked probe and the plan folders; none of the files below appears.

- `lib/core/services/watch_session_importer.dart` — not in `git-status` ✓
- `scripts/sqlite_schema.sql` — not in `git-status` ✓
- `lib/data/models/models.dart` — not in `git-status` ✓
- `test/db_seed_test.dart` — not in `git-status` ✓
- `test/in_session_pr_toast_test.dart` — not in `git-status` ✓
- `test/pr_toast_test.dart` — not in `git-status` ✓
- anything under `watch/` — not in `git-status` ✓
- `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` — not in `git-status` ✓

**Observation O-4.1 (not fixed, deliberately).** `scripts/sqlite_schema.sql` line 1601 carries the comment `-- NULL = waiting; set once, never cleared`, which the new exception makes stale. The file is deliberately untouched (D-810, and the brief's rule 3 forbids touching it), and `docs/db_integration.md` now carries the corrected statement. Recorded here so the next schema-touching PR can correct the comment.

## 7. Full-suite counts

| Run | Final line | Delta vs baseline |
|---|---|---|
| `gateway.sh test` after Phase 1 | `01:20 +3262 ~1 -12: Some tests failed.` | +12 passing, −12 failing (by design) |
| `gateway.sh test` after Phase 2 | `01:22 +3264 ~1 -12: Some tests failed.` | +2 passing vs Phase 1 (`S-1412` on both stores); −12 unchanged (the probe, by design) |
| `gateway.sh test` after Phase 3 | `01:18 +3276 ~1: All tests passed!` | +12 passing vs Phase 2 (the probe's twelve reds turn green); 0 failing |
| `gateway.sh test` after Phase 4 | `01:24 +3276 ~1: All tests passed!` | unchanged — Phase 4 adds no test; 0 failing. Re-run after the F-4.1 doc fix; the pre-fix run was `01:23 +3276 ~1: All tests passed!`. |
| `gateway.sh lint` after Phase 4 | `196 issues found. (ran in 2.8s)` | unchanged vs the Step 0b baseline (`196 issues found. (ran in 3.1s)`); 0 errors |
| `gateway.sh test test/docs_indexing_contract_test.dart test/navigation_contract_enforcement_test.dart` (Phase 4) | `00:00 +10: All tests passed!` | the two contract suites, green |
| `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart test/watch_capture_repository_parity_test.dart test/db_seed_test.dart` (Phase 4) | `00:01 +69: All tests passed!` | the tests the doc-claim table names, green |

---

## 8. Phase 2 — the data layer (DBA, 2026-10-03)

Steps 1–8 of the plan's Phase 2. The data layer alone does not fix the bug: the probe keeps the Phase 1 split (below).

### 8.1 Red first — S-1412 with the method absent

The test was written first; to reproduce the pre-implementation state the three declarations (`WorkoutRepository`, both implementations) were temporarily removed, the run captured, and the declarations restored.

Command: `gateway.sh test test/watch_capture_repository_parity_test.dart`

Final line, verbatim:

```
00:00 +0 -1: Some tests failed.
```

Failure, verbatim:

```
test/watch_capture_repository_parity_test.dart:559:18: Error: The method 'clearWatchInboxApplied' isn't defined for the type 'WorkoutRepository'.
 - 'WorkoutRepository' is from 'package:omnitrain/data/repositories/workout_repository.dart' ('lib/data/repositories/workout_repository.dart').
Try correcting the name to the name of an existing method, or defining a method named 'clearWatchInboxApplied'.
      await repo.clearWatchInboxApplied(['e-a', 'e-b', 'e-never-staged']);
                 ^^^^^^^^^^^^^^^^^^^^^^
00:00 +0 -1: loading /Users/irinakutsenko/Developer/omnitrain/test/watch_capture_repository_parity_test.dart [E]
  Failed to load "/Users/irinakutsenko/Developer/omnitrain/test/watch_capture_repository_parity_test.dart":
  Compilation failed for testPath=.../test/watch_capture_repository_parity_test.dart: ... Error: The method 'clearWatchInboxApplied' isn't defined for the type 'WorkoutRepository'.
  .
00:00 +0 -1: Some tests failed.
```

### 8.2 Green — parity suite

`gateway.sh test test/watch_capture_repository_parity_test.dart` → `00:00 +36: All tests passed!`

`S-1412` runs once per `_Harness` (Mock and Hive). The suite was `+34` before it. The scripted sequence now calls `clearWatchInboxApplied(['e-run'])`, and the "Hive and Mock store the same rows" group asserts the dumped row is unapplied on both stores, so the row-by-row `toMap()` comparison covers the new write.

### 8.3 The schema contract

`gateway.sh test test/db_seed_test.dart` → `00:00 +9: All tests passed!` (unchanged). `scripts/sqlite_schema.sql`, `lib/data/models/models.dart` and `test/db_seed_test.dart` are untouched (D-810); `applied_at_ms` was already nullable.

### 8.4 The probe keeps the Phase 1 split

`gateway.sh test test/watch_session_edit_restore_late_entry_test.dart` → `00:00 +12 -12: Some tests failed.`

Failing (12): S-1401, S-1402, S-1404, S-1405, S-1406, S-1410 — each on both Mock and Hive. Passing (12): S-1403, S-1407, S-1408, S-1409, S-1413, S-1414 — each on both stores. Identical to Phase 1.

### 8.5 Full suite

`gateway.sh test` → `01:22 +3264 ~1 -12: Some tests failed.`

Phase 1's post-run was `+3262 ~1 -12`; `+3264` is that plus `S-1412` on both stores. The `-12` is the probe's twelve failures and nothing else — no other test in the suite fails.

### 8.6 Lint

`gateway.sh lint` → `196 issues found. (ran in 2.2s)` — the baseline count, 0 errors, no new issue.

### 8.7 Name search (doc checklist)

| Name | Hits |
|---|---|
| `watchEntryIdsAppliedAtSnapshot` | `lib/core/models/session_edit_snapshot.dart`; this plan + evidence |
| `clearWatchInboxApplied` | `lib/data/repositories/workout_repository.dart`, `hive_workout_repository.dart`, `mock_workout_repository.dart`; `test/watch_capture_repository_parity_test.dart`; `docs/data_models.md`; `docs/db_integration.md`; this plan + evidence |
| `appliedWatchEntryIds` | this plan + evidence only (Phase 3) |
| `WatchLateEntryRecovery` | this plan + evidence only (Phase 3) |
| `recoverEntriesAppliedSince` | this plan + evidence only (Phase 3) |
| `lateEntryRecovery` | this plan + evidence only (Phase 3) |

### 8.8 Files changed

`git-status` shows exactly the plan's Phase 2 Predicted Files modified: `lib/core/models/session_edit_snapshot.dart`, `lib/data/repositories/workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`, `test/watch_capture_repository_parity_test.dart`, `docs/db_integration.md`, `docs/data_models.md`. No file outside the Predicted Files was touched.

---

## 9. Phase 3 — the mechanism (Developer, 2026-10-03)

Steps 1–14 of the plan's Phase 3. The mechanism was already on the tree from the previous run; this run fixed the probe harness, ran the mutations, edited the docs, and verified.

### 9.1 The probe harness fix

The probe was red because `_enterEditMode` built `WorkoutState(repository)` with no recovery handle, so the restore skipped the recovery (D-803). The fix passes the `WatchSessionInbox` the test already builds: `_enterEditMode` gained a `WatchLateEntryRecovery? recovery` parameter and constructs `WorkoutState(repository, watchLateEntryRecovery: recovery)`; every call site passes `recovery: session.inbox` (or `a.inbox` / `b.inbox`). S-1414 keeps `watermark: false` and now exercises the full scenario the register specifies (late entry, user's set, Discard → 2 sets). No assertion was weakened. The three unused locals (`label`, `workout`, `snapshot`) are gone — `label` is used by every scenario, and S-1414's body now uses both.

### 9.2 Green — the probe

`gateway.sh test test/watch_session_edit_restore_late_entry_test.dart`

Final line, verbatim:

```
00:00 +24: All tests passed!
```

24/24: 12 scenarios × {Mock, Hive}. The Phase 1 split is gone — S-1401, S-1402, S-1404, S-1405, S-1406 and S-1410 now pass on both stores, and S-1403, S-1407, S-1408, S-1409, S-1413 and S-1414 stay green.

### 9.3 Step 8 sanity — the bootstrap reorder

`lib/main.dart` builds `WorkoutState` after the `createWatchSync` block (line 380, passing `watchLateEntryRecovery: watchSync?.lateEntryRecovery`) and `exerciseLibraryState` after both. `gateway.sh lint` is clean (9.6). Tests that boot the real wiring were run:

`gateway.sh test test/watch_transport_test.dart test/health_platform_test.dart test/startup_failure_screen_test.dart` → `00:03 +58: All tests passed!`

`test/watch_transport_test.dart` calls `createWatchSync` directly (lines 272, 677); `test/health_platform_test.dart` and `test/startup_failure_screen_test.dart` import `package:omnitrain/main.dart`.

### 9.4 The three mutation red runs

Each applied to the tracked file, run, reverted, and the stat confirmed back. No `git stash`/`checkout`/`restore` was used.

**M1 — drop the watermark filter** (`lib/state/watch/watch_session_inbox.dart`; stat before/after `56 ++++ 55+ 1-`). The `late` list became every applied row. `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart`:

```
00:00 +9 -1: PR 3d Mock: ... S-1410 Mock: a late phone correction and a late phone deletion are recovered too [E]
00:00 +20 -2: PR 3d Hive: ... S-1410 Hive: a late phone correction and a late phone deletion are recovered too [E]
00:00 +22 -2: Some tests failed.
```

Failure detail, verbatim:

```
Expected: <2>
    Actual: <3>
  S-1410 Mock B: the late deletion is re-applied
```

S-1409 itself stays green (its re-send is a no-op); the mutation's real damage is S-1410, where a deletion applied before edit mode is resurrected. Reverted; stat back to `56 ++++ 55+ 1-`.

**M2 — remove the `clearWatchInboxApplied` call** (`lib/state/watch/watch_session_inbox.dart`; stat before/after `56 ++++ 55+ 1-`). `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart`:

```
00:00 +0 -1: PR 3d Mock: ... S-1401 Mock: a late wrist set survives Discard and the user's own set does not [E]
00:00 +12 -12: Some tests failed.
```

Failure detail, verbatim:

```
Expected: <3>
    Actual: <2>
  S-1401 Mock: the wrist's three sets — the late entry survives Discard
```

12 failures (the six late-entry scenarios on both stores). Reverted; stat back to `56 ++++ 55+ 1-`.

**M3 — move the recovery call before the delete loops** (`lib/state/workout/session_core_lifecycle.dart`; stat before/after `33 ++++ 32+ 1-`). `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart`:

```
00:00 +0 -1: PR 3d Mock: ... S-1401 Mock: a late wrist set survives Discard and the user's own set does not [E]
00:00 +12 -12: Some tests failed.
```

Failure detail, verbatim:

```
Expected: <3>
    Actual: <2>
  S-1401 Mock: the wrist's three sets — the late entry survives Discard
```

The restore's delete loops remove the rows the recovery had just re-created. Reverted; stat back to `33 ++++ 32+ 1-`. The mutated spot was read back after reverting: the recovery call sits after the summary re-create and before `_exerciseCache`/`loadSessionData()`.

### 9.5 Docs (steps 11–14)

| Doc | Change |
|---|---|
| `docs/watch_session_capture.md` | Structure row for `WatchLateEntryRecovery`; the Discard exception in "Why applied rows are kept"; a new Invariant ("A wrist entry that arrived while an Edit Session was open survives Discard"), naming `test/watch_session_edit_restore_late_entry_test.dart` (S-1401…S-1410, S-1413, S-1414) |
| `docs/modality_based_exercise_ui.md` | Edit Mode: the user-visible Discard rule, naming the same test (S-1401…S-1410) |
| `docs/state_management/services_and_utils.md` | `createWatchSync`: `WatchSyncGraph`'s second handle, `WatchLateEntryRecovery`, naming the same test |
| `docs/state_management/workout_state.md` | Construction-order block: the optional recovery and the `main.dart` order, naming the same test |

No line numbers, hex values or roadmap phrasing. `gateway.sh test test/docs_indexing_contract_test.dart` → `00:00 +9: All tests passed!`.

### 9.6 Lint

`gateway.sh lint` → `196 issues found. (ran in 2.4s)` — the baseline count, 0 errors, no new issue. The pre-existing `use_build_context_synchronously` in `lib/features/session/workout_session_screen.dart` is unchanged (the file's diff is the watermark read only).

### 9.7 Full suite

`gateway.sh test` → `01:18 +3276 ~1: All tests passed!`

`+3276` = the observed baseline `+3250` plus 24 (the probe) plus 2 (`S-1412` on both stores). The count grew only by the tests this PR adds; nothing else changed.

### 9.8 Files changed (Phase 3)

`git-status` shows the Phase 3 Predicted Files modified: `lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/session_core.dart`, `lib/state/workout/workout_state.dart`, `lib/state/watch/watch_session_inbox.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/features/session/workout_session_screen.dart`, `lib/main.dart`, `test/watch_session_edit_restore_late_entry_test.dart`, `docs/watch_session_capture.md`, `docs/modality_based_exercise_ui.md`, `docs/state_management/services_and_utils.md`, `docs/state_management/workout_state.md`. No file outside the Predicted Files was touched.

---

## 10. Phase 4 — the residue sweep and the doc-claim table (Developer, 2026-10-03)

Steps 1–6 of the plan's Phase 4. The phase wrote one doc file (`docs/watch_session_capture.md`, finding F-4.1) and no production file.

### 10.1 Step 1 — the name sweep

Every name this PR added was grepped across `lib/` and `test/`. The full hit table is in section 5. Every hit is a file in the plan's Predicted Files or a test that asserts the new behaviour; no hit lands in a file this PR did not touch. `lib/core/services/watch_session_importer.dart` is not among them.

### 10.2 Step 2 — no reader of the old behaviour remains

`snapshotSessionState` appears in `lib/` at three places: the screen's call site (line 491, which passes `watchEntryIdsAppliedAtSnapshot: watermark`), `WorkoutState`'s delegation (line 105) and `SessionCore`'s definition (line 263). The watermark is read at line 425, before `loadSessionData()` at line 432, so the read precedes the rows (D-801). The three argument-free test call sites are `test/session_summary_distance_test.dart:731` and `test/watch_session_edit_restore_summaries_test.dart:240,456` — deliberate (D-803). No `lib/` reader of the old behaviour remains.

### 10.3 Step 3 — unmodified files

`gateway.sh git-status` lists exactly the 18 modified files of this PR plus the untracked probe and the plan folders. None of the deliberately-unmodified files appears (section 6). One stale comment in `scripts/sqlite_schema.sql` is recorded as O-4.1 and deliberately not fixed.

### 10.4 Step 4 — the doc-claim table

Section 4. Every row names a test that exists and passes; each S-id was opened in the test file and found. The named tests were run together: `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart test/watch_capture_repository_parity_test.dart test/db_seed_test.dart` → `00:01 +69: All tests passed!`.

### 10.5 Step 5 — the doc sentences re-read

Each edited doc section was re-read against the code. Every type, file, constant and test named in the added sentences exists: `clearWatchInboxApplied` (interface, Hive, Mock), `WatchLateEntryRecovery` and `recoverEntriesAppliedSince` (`lib/state/watch/watch_session_inbox.dart`), `SessionCore.restoreSessionSnapshot`'s call (`lib/state/workout/session_core_lifecycle.dart`), `WatchSyncGraph.lateEntryRecovery` and `createWatchSync`'s return (`lib/state/watch/watch_sync_wiring.dart`), `WorkoutState`'s optional parameter and delegation (`lib/state/workout/workout_state.dart`), the `main.dart` order (`createWatchSync` line 364, `WorkoutState` line 380, `ExerciseLibraryState` line 385), `appliedAtMs`/`applied_at_ms` (nullable in `scripts/sqlite_schema.sql`), and the three test files. No added sentence carries a line number, a hex value or roadmap phrasing. No added sentence describes a surface that is not shipped.

**Finding F-4.1 (fixed).** The Rationale sentence in `docs/watch_session_capture.md` claimed a phone that stops between the un-mark and the pass "recovers it at its next start". That is false for a late set row: `WatchSessionInbox.resume` settles only sessions whose `session_end` row is unapplied (`getWatchSessionIdsWithUnappliedEnd`), and a late set on an already-ended session is not one of them. The sentence now says "at the next import pass for that session", which is what `WatchSessionImporter.apply` does with the un-marked row. Doc-only fix; no test change.

### 10.6 Step 6 — README and the size ceiling

No new doc file was added (the only untracked additions are the probe test and the plan folders), so `docs/README.md` needs no new row; it indexes no plan file. `gateway.sh test test/docs_indexing_contract_test.dart test/navigation_contract_enforcement_test.dart` → `00:00 +10: All tests passed!`, which includes the 64 KiB ceiling check.

### 10.7 Commands and results

| Command | Final line |
|---|---|
| `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart test/watch_capture_repository_parity_test.dart test/db_seed_test.dart` | `00:01 +69: All tests passed!` |
| `gateway.sh test test/docs_indexing_contract_test.dart test/navigation_contract_enforcement_test.dart` | `00:00 +10: All tests passed!` (re-run after the F-4.1 doc fix: same) |
| `gateway.sh lint` | `196 issues found. (ran in 2.8s)` (final tree; the pre-fix run was `196 issues found. (ran in 2.3s)`) |
| `gateway.sh test` | `01:24 +3276 ~1: All tests passed!` (re-run after the F-4.1 doc fix; the pre-fix run was `01:23 +3276 ~1: All tests passed!`) |
| `gateway.sh git-status` | the 18 modified files of this PR, the untracked probe, the plan folders — no file outside Predicted Files |

### 10.8 Files changed (Phase 4)

`docs/watch_session_capture.md` (finding F-4.1's fix) and this evidence file. No production file, no test file, no other doc.


---

## Fix round 1 — review findings 1–6

Base for this round: the tree the review read (`c25617a9` + the PR's 18 modified files + the untracked probe). No commit, no staging, no branch.

### F1 — S-1411 removed from the register and the evidence

The scenario had no test (`grep -rn "S-1411" test/` → nothing) and the evidence's red→green row for it was false. The register's `### S-1411` section is deleted, A13 now maps to `S-1412` plus the probe's per-store coverage, S-1412's `Edge case of` is `none`, and the evidence's S-1411 row and the "S-1411 and S-1412 are Phase 2's" sentence are gone. Parity is substantively covered: every scenario in the probe runs on both stores with identical absolute expectations.

### F2 — S-1415, the screen's own watermark capture

`test/watch_session_edit_restore_late_entry_test.dart` gained a `testWidgets` group (`PR 3d Mock: the screen reads the watermark (S-1415)`) that mounts the real `WorkoutSessionScreen` in edit mode with the real `WatchSessionInbox` as the recovery handle, delivers a late set, adds a set through the screen, and discards through the screen's own Back → "Unsaved changes" → Discard path. Register entry and acceptance row A16 added.

Two harness facts the test needed, both recorded because the brief's diagnosis was wrong:

- The failure was **not** a coach-mark overlay absorbing the tap. The two exercise coach marks are pre-marked seen (`markExerciseInfoHintSeen` / `markExerciseNotesHintSeen`) so neither overlay can absorb a tap, but the test still failed with the detail view open and the "Add set" target present.
- The real cause: after a late delivery the `WorkoutState`'s cached observations are stale, so `SessionCore.addEntry` derives `entryNumber` from them, collides with the late row's id, and `createObservation` upserts instead of adding. The test reloads the state (`loadSessionData`) after the late delivery, mirroring the other probe scenarios, so the user's add is a genuine new entry.

**Red → green.**

| Run | Command | Final line |
|---|---|---|
| Red (before the reload) | `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart --plain-name "S-1415"` | `00:00 +0 -1: Some tests failed.` — `Expected: <4> Actual: <3>` at "the user added a set" |
| Green | same | `00:00 +1: All tests passed!` |

**Mutation proof (M4).** `lib/features/session/workout_session_screen.dart`'s watermark read changed from `? await widget.workoutState.appliedWatchEntryIds()` to `? null`, then reverted byte-identically (`gateway.sh git-diff --stat -- lib/features/session/workout_session_screen.dart` → `12 +++++++++++-`, 11 insertions and 1 deletion, before and after).

| Run | Final line |
|---|---|
| Mutated | `00:00 +0 -1: Some tests failed.` — `S-1415 Mock: the real screen recovers a late wrist set on Discard [E]`, `Expected: <3> Actual: <2>` ("the wrist's three sets — the screen read the watermark before the rows") |
| Reverted | `00:00 +1: All tests passed!` |

The mutation is the review's own falsification test: with the screen no longer reading the watermark, the restore leaves 2 sets, so the test fails. The feature's only production wiring is now covered.

### F3 + F4 — the Discard Rationale sentence

`docs/watch_session_capture.md`'s "Why applied rows are kept" no longer carries the unverified durability claim; the sentence ends at "the pass re-stamps it applied". The durability statement moved into the Invariant that already carries the test pointers, corrected to what the code does: the un-mark is durable, so a pass that does not complete leaves the row to the next pass for that session — the wrist re-sending it, or the start-up pass for a session whose end has not been applied (`WatchSessionInbox.resume` settles only `getWatchSessionIdsWithUnappliedEnd`). The Invariant now also names `S-1415`.

### F5 — the scope block

`docs/watch_session_capture.md`'s scope block now names `lib/state/workout/session_core_lifecycle.dart` (the restore) and `lib/features/session/workout_session_screen.dart` (the snapshot capture), so the document's declared scope covers the prose it already carried.

### F6 — the Executor block's M1 expectation

The Executor block now says M1 must make **S-1410** fail, with S-1409 staying green because re-applying every applied row also re-applies the pre-edit deletion. This matches the recorded M1 run.

### Fix round 1 verification

| Command | Final line |
|---|---|
| `gateway.sh lint` | `196 issues found. (ran in 2.5s)` — unchanged from the pre-round `196 issues found.` |
| `gateway.sh test test/docs_indexing_contract_test.dart` | `00:00 +9: All tests passed!` |
| `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart --plain-name "S-1415"` | `00:00 +1: All tests passed!` |
| `gateway.sh test` | `01:23 +3277 ~1: All tests passed!` — the pre-round full suite was `+3276 ~1`, so the count grew by exactly the one test this round adds |

### Fix round 1 files changed

`test/watch_session_edit_restore_late_entry_test.dart` (S-1415 group; the two hint pre-marks; the reload after the late delivery; the two debug prints and their `ignore: avoid_print` lines removed), `docs/watch_session_capture.md` (F3, F4, F5), the plan (F1, F2, F6, the register, A16, Progress row 8, the Fix round 1 phase block), this evidence file. `lib/features/session/workout_session_screen.dart` was mutated and reverted byte-identically — it is not a changed file.
