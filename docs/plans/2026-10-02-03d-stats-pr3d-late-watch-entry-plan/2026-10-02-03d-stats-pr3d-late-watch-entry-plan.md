# Feature: Stats PR 3d — a late watch entry survives Discard

> **Status:** READY (planner) — no code yet.
> **Next handoff:** @developer (Phase 1).
> **Series:** `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` — the row "O-17 PR", which this round calls **3d**. This plan does not edit that index; the 3d status line lives here.
> **Source of scope:** PR 2 Open Item **O-17** in `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md` — the only data-loss bug the owner asked to fix before the release.
> **Base:** `develop`, working tree at PR 3c DONE. No branch step: work directly on `develop`.
> **Depends on:** nothing unmerged. The watch capture (PR 2) and the distance source (PR 3b) are in.
> **Evidence:** `2026-10-02-03d-stats-pr3d-late-watch-entry-plan.evidence.md` (same folder). Review findings go to `.review.md`; neither belongs in this file.
> **Binding conventions:** `docs/global_conventions.md`, plus `docs/README.md` → `docs/watch_session_capture.md`, `docs/data_models.md`, `docs/db_integration.md`, `docs/modality_based_exercise_ui.md`, `docs/state_management/workout_state.md`, `docs/state_management/services_and_utils.md`, `docs/documentation_standard.md`. Budget: `.github/agents/pr_scope_budget.md`.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 353 (measured 2026-10-02 by reading this file back) | 500 | 800 |
| Phases | 4 | >3 | >5 |
| Tracks | 1 (`lib/`) | >1 | — |
| Ledger decisions | 12 (D-801…D-812) | >20 | — |
| Scenarios | 14 (S-1401…S-1414) | >30 | — |
| Predicted production lines | ~230 | — | ~1,500 |

**Verdict:** under budget on every axis. One bug, one mechanism, one track. The four phases are the mandated red test, the data layer, the mechanism, and the docs — not four features.

## What this PR does

A wrist session is open on the phone in **Edit Session**. A late watch entry for that session arrives; the importer materialises it into history and stamps it applied. The user then taps **Discard** (Back without Save). Today `restoreSessionSnapshot` replaces the snapshotted exercises' rows wholesale from a snapshot taken *before* the late entry arrived, so the entry's rows vanish — and the wrist re-sends nothing, because the entry is already marked applied. A set the user logged on the wrist is silently lost.

After this PR: **Discard throws away the user's own edits but never a watch entry that arrived while the screen was open.** The late wrist set is in the session; the user's own added or edited rows are gone exactly as before.

**Out of scope:** anything in `watch/`; the sync protocol; the PR (personal record) logic and its parity tests; any schema change; Save's behaviour; the import itself (`WatchSessionImporter` is not modified).

## Decision Ledger — PR 3d

Immutable once written; a change is a new superseding entry. `D-801…D-812` are unused elsewhere in `docs/plans/`.

**D-801 — The watermark is the set of applied inbox entry ids, read before the rows.** The snapshot carries `watchEntryIdsAppliedAtSnapshot`: the `entryId` of every inbox row of the session whose `appliedAtMs != null`, read from the repository at the moment the snapshot is taken. It is a `Set<String>?`; **null means the caller recorded no watermark, and null means no recovery** (D-803). The read happens *before* the screen's `loadSessionData()` call, so the watermark can only be a subset of what the snapshot's rows reflect — never a superset.

**D-802 — The late set is every applied row the watermark does not name.** At restore, `late = {applied rows of the session} ∖ watermark`. One rule, no origin or kind filter: a late wrist entry, a late phone correction and a late phone deletion are all recovered the same way. A row applied *after* the watermark read but *before* the row load is in the snapshot's rows and not in the watermark, so it is un-marked and re-imported — the re-import is idempotent (D-806), so this is harmless and is the safe direction to err in.

**D-803 — No watermark, no recovery.** When `watchEntryIdsAppliedAtSnapshot == null` the restore behaves exactly as it does today. This is what keeps the three existing `snapshotSessionState()` call sites compiling and behaving unchanged, and it is the reason the field is nullable rather than defaulting to the empty set.

**D-804 — Recovery is un-marking in storage, then one ordinary import pass.** The recovery (a) clears `appliedAtMs` on exactly the late rows, then (b) runs the inbox's normal settle for that session, which is the ordinary `WatchSessionImporter.apply` pass. Nothing else is written by the recovery: no row is created, deleted or edited by the recovery itself. The importer re-materialises the late entries, re-stamps them applied, and fires the history-changed callback.

**D-805 — The recovery runs inside the restore, after the row replacement and before the reload.** `restoreSessionSnapshot` calls the recovery after its delete/re-create loops and its summary re-create, and before its final `loadSessionData()`. Running it earlier would let the restore's own delete loops remove the rows the recovery had just re-created; running it later would leave the screen showing the pre-recovery rows.

**D-806 — The re-import is idempotent and duplicates nothing.** The importer keys every row it writes by id and stages put-if-absent, so a second pass over the same staged rows writes the same rows with the same ids. A second sync after Discard, and a wrist re-send after Discard, both leave the session with the same rows. The re-import also re-sends a receipt for the recovered entries; a duplicate receipt is accepted (the wrist treats a re-send as an unacknowledged entry, and a second acknowledgement is harmless).

**D-807 — The late entry returns as the wrist sent it.** Discard undoes the user's edits to the late entry along with every other edit: the wrist's values, and the source the wrist's distance arrived with, are what the session holds after Discard. A late entry the user *deleted* during edit mode also returns, because Discard undoes that deletion like any other edit.

**D-808 — A deletion made before edit mode stays deleted.** The watermark is read at snapshot time, so a phone deletion staged and applied *before* the user entered edit mode is in the watermark and is never un-marked. Its tombstone keeps the entry out of history, exactly as D-136 requires. Only rows applied after the watermark are recovered.

**D-809 — Save is unchanged.** `_saveEditChanges` does not call the recovery and does not read the watermark. A late entry is already in history when Save runs, and Save keeps it.

**D-810 — No schema change.** `app_watch_inbox_entry.applied_at_ms` already exists and is already nullable. The recovery writes `null` into it. `scripts/sqlite_schema.sql`, `lib/data/models/models.dart` and `test/db_seed_test.dart` are untouched, and `currentDataVersion` is unchanged.

**D-811 — The recovery is a capability of the inbox, handed in by constructor.** `WatchSessionInbox` implements a second narrow interface beside `WatchSessionRatings`, and `createWatchSync` returns it in `WatchSyncGraph`. `WorkoutState` takes it as an optional constructor parameter and passes it to `SessionCore`. A screen never receives it, and no state object reaches into the importer directly.

**D-812 — The re-import lays the session out the importer's way.** The recovered entry lands where the importer's canonical placement puts it, which may differ from where the user's own edits had left the exercise. The plan does not pin a second ordering rule; the importer's order is the order.

### Decisions this plan consumes but does not define

| Decision | Source | What it binds here |
|---|---|---|
| Applied inbox rows are tombstones that keep deleted history deleted | D-136, `docs/data_models.md` ("Applied once, never deleted") | D-808 — the watermark is what keeps a pre-edit deletion deleted |
| The inbox is put-if-absent and no history delete cascades into it | D-132, `docs/db_integration.md` | D-804 — the recovery unsets a stamp; it never deletes a row |
| The import is idempotent and independent of arrival order | `docs/watch_session_capture.md` Invariants | D-806 |
| A distance's source survives an Edit Session snapshot and restore | `docs/distance_source.md`, `S-821` | D-807 — the recovered entry brings its own source |
| Hive and Mock agree value for value | `docs/global_conventions.md` | Phase 2's parity test |
| The snapshot does not carry rest records | `docs/rest_tracking.md` | Unchanged; the recovery carries no rest record either |

## Feature invariants that bite in this PR

- **Repository parity.** `clearWatchInboxApplied` is a new `WorkoutRepository` method with a Hive and a Mock implementation, and the parity suite runs one body against both. Mock must mirror Hive value for value, including the skip rules.
- **No schema change, no stored field.** The column exists; the recovery writes `null` into it. `scripts/sqlite_schema.sql` and `test/db_seed_test.dart` are untouched.
- **The importer is not modified.** `lib/core/services/watch_session_importer.dart` is not in any phase's Predicted Files. The fix is un-marking plus a normal pass, not a new importer mode.
- **PR parity tests are read-only.** `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` are not edited.
- **The three existing `snapshotSessionState()` call sites keep compiling and behaving unchanged** — `test/session_summary_distance_test.dart` and the two in `test/watch_session_edit_restore_summaries_test.dart` pass no watermark, so they get `null` and no recovery (D-803).
- **Docs describe what exists.** A doc sentence may not name a type, file, constant or test that does not exist, and every behaviour sentence names the test that asserts it.

## Requirements

1. A snapshot that records which inbox entries were already applied when it was taken, without breaking the callers that do not record one.
2. A repository method that unsets the applied stamp on named inbox rows, on both stores, skipping unknown ids and rows that are not applied.
3. A recovery capability on the inbox that un-marks the late rows and runs one ordinary import pass.
4. The restore calling that recovery at the one safe point, and the screen reading the watermark at the one safe point.
5. Constructor wiring from `createWatchSync` through `WorkoutState` to `SessionCore`, with the bootstrap order in `lib/main.dart` corrected.
6. A red test first, on both repositories, covering every case the brief enumerates.
7. The docs the change invalidates.

## Acceptance Criteria → scenarios

| # | Criterion | Scenario |
|---|---|---|
| A1 | A late wrist set that arrives while the screen is open is in the session after Discard | S-1401 |
| A2 | The user's own added set is gone after Discard, as before | S-1401 |
| A3 | A late entry that creates a new effort, its instance and its summary all return | S-1402 |
| A4 | A late entry the user deleted during edit mode returns | S-1403 |
| A5 | A late entry the user edited returns as the wrist sent it | S-1404 |
| A6 | Two late entries both return | S-1405 |
| A7 | A second sync after Discard duplicates nothing | S-1406 |
| A8 | A wrist re-send after Discard duplicates nothing | S-1406 |
| A9 | Discard with no structural change is a no-op and loses nothing | S-1407 |
| A10 | Save keeps the late entry and the user's edits | S-1408 |
| A11 | A deletion applied before edit mode stays deleted | S-1409 |
| A12 | A late phone correction and a late phone deletion are recovered too | S-1410 |
| A13 | Hive and Mock reach the same rows | S-1412; the probe runs every scenario on both stores with identical expectations |
| A14 | A session with no late entry is untouched by the recovery | S-1413 |
| A15 | A snapshot taken with no watermark recovers nothing | S-1414 |
| A16 | The screen itself reads the watermark before the rows | S-1415 |

## Scenarios

Fixtures are exact: every entity class involved is named, including the adversarial twins. `_capId` is the capture contract's session (`watch/contract/watch_capture_contract.json`), whose bench effort is `e-set1..e-set3` at 5 × 80 kg, plus `e-run` and `e-r1..e-r3`. "The screen's edit entry" means `loadHistoricalSession` → `loadSessionData` → `snapshotSessionState` (the order `test/watch_session_edit_restore_summaries_test.dart` uses). "A late entry arrives" means `inbox.receive(observationsUp(_capId, [entry]))` followed by the settle the inbox runs, which is what the transport does in the app.

### S-1401: a late wrist set survives Discard, and the user's own set does not
- **Fixture:** the capture contract's `full` case **minus `e-set3`**, imported, so the bench effort holds 2 sets. The screen is in edit mode: `loadHistoricalSession(_capId)`, `loadSessionData()`, `snapshotSessionState()` (watermark = the applied ids at that moment, which do not include `e-set3`).
- **Trigger:** `e-set3` arrives late (`inbox.receive(observationsUp(_capId, [eSet3]))`), then the user adds a set (`addEntry('e-bench')` + `loadSessionData()`, faithful to `_addSet`), then Discard (`restoreSessionSnapshot(snapshot)`).
- **Flow:** the restore replaces the bench rows from the snapshot (2 sets), then the recovery un-marks `e-set3` and runs one import pass, which re-materialises it.
- **Expected outcome:** the bench effort holds **3** sets — the wrist's `e-set3` and the two imported ones — and the user's added set is gone. The third set's values are the wrist's (5 reps, 80 kg).
- **Edge case of:** none. This is the PR 2 probe, as a test.

### S-1402: a late entry that creates a new effort brings its instance and its summary
- **Fixture:** the capture contract's `full` case **minus `e-run`**, imported, so no run effort exists. Edit mode entered as in S-1401.
- **Trigger:** `e-run` arrives late, then the user adds a set to the bench effort, then Discard.
- **Flow:** the restore removes the run effort (it is not in the snapshot), then the recovery re-imports it.
- **Expected outcome:** the run effort is back with its `TimedInstance` and with the `SensorSummary` the wrist measured for it; the bench effort holds the wrist's sets and not the user's added one.
- **Edge case of:** S-1401 — the case where the late entry is a whole new effort rather than a row on an existing one.

### S-1403: a late entry the user deleted during edit mode returns
- **Fixture:** S-1401's fixture, with `e-set3` already arrived and applied **before** edit mode is entered, so the bench effort holds 3 sets and the watermark names `e-set3`.
- **Trigger:** the user deletes the third set during edit mode, then Discard.
- **Flow:** the restore replaces the rows from the snapshot (3 sets), and the recovery finds no late row (`e-set3` is in the watermark), so it does nothing.
- **Expected outcome:** the bench effort holds 3 sets — the user's deletion is undone, exactly as any other edit is undone by Discard.
- **Edge case of:** S-1401. This is the adversarial twin of S-1409: the same entry, deleted on the other side of the watermark.

### S-1404: a late entry the user edited returns as the wrist sent it
- **Fixture:** S-1401's fixture, with `e-set3` arrived late and applied.
- **Trigger:** the user edits the late set's reps to 12 during edit mode, then Discard.
- **Flow:** the restore replaces the rows from the snapshot, then the recovery re-imports `e-set3` from its staged payload.
- **Expected outcome:** the third set reads the wrist's 5 reps and 80 kg, not the user's 12. The user's edit is discarded like every other edit (D-807).
- **Edge case of:** S-1401.

### S-1405: two late entries both return
- **Fixture:** the capture contract's `full` case **minus `e-set3` and `e-r3`**, imported. Edit mode entered as in S-1401.
- **Trigger:** `e-set3` and `e-r3` both arrive late, then the user adds a set, then Discard.
- **Flow:** the recovery un-marks both and runs one pass, which re-materialises both.
- **Expected outcome:** the bench effort holds 3 sets and the round effort holds 3 rounds; the user's added set is gone.
- **Edge case of:** S-1401.

### S-1406: a second sync after Discard duplicates nothing
- **Fixture:** S-1401's fixture, after Discard.
- **Trigger:** the wrist re-sends `e-set3` (`inbox.receive(observationsUp(_capId, [eSet3]))` again), and separately a full settle runs for the session.
- **Flow:** the re-send is refused put-if-absent (the row is staged), and the settle's pass finds the entry already applied.
- **Expected outcome:** the bench effort still holds exactly 3 sets, with the same row ids as before the re-send. No row is duplicated, and no second effort appears.
- **Edge case of:** S-1401 — idempotence (D-806).

### S-1407: Discard with no structural change is a no-op
- **Fixture:** S-1401's fixture, with `e-set3` arrived late and applied, and **no** user edit made.
- **Trigger:** Discard.
- **Flow:** `_discardEditChanges` restores only when `_hasStructuralChanges` is true, so the restore does not run at all.
- **Expected outcome:** the bench effort holds 3 sets. The late entry was never at risk, and the recovery never runs.
- **Edge case of:** S-1401 — the case the bug does not reach, kept as a guard against a fix that makes Discard destructive where it was not.

### S-1408: Save keeps the late entry and the user's edits
- **Fixture:** S-1401's fixture, with `e-set3` arrived late and applied, and the user's added set present.
- **Trigger:** Save (`_saveEditChanges`).
- **Flow:** Save writes the user's edits and calls no recovery.
- **Expected outcome:** the bench effort holds 4 sets — the wrist's 3 and the user's added one. Nothing is un-marked and no import pass runs.
- **Edge case of:** S-1401 — the other exit from edit mode.

### S-1409: a deletion applied before edit mode stays deleted
- **Fixture:** the capture contract's `full` case imported, then the phone's deletion of `e-set3` staged and applied **before** edit mode is entered, so the bench effort holds 2 sets and the watermark names the deletion's entry id.
- **Trigger:** the user adds a set, then Discard.
- **Flow:** the restore replaces the rows from the snapshot (2 sets), and the recovery finds no late row — the deletion is in the watermark.
- **Expected outcome:** the bench effort holds 2 sets. The deleted set does not come back, and a later wrist re-send of `e-set3` still does not bring it back (D-136, D-808).
- **Edge case of:** S-1403 — the adversarial twin that a "un-mark everything applied" fix would break.

### S-1410: a late phone correction and a late phone deletion are recovered too
- **Fixture A:** the capture contract's `full` case imported, edit mode entered. A phone correction of `e-set2`'s reps is staged and applied **after** the watermark.
- **Expected outcome A:** after the user adds a set and Discards, `e-set2` reads the corrected reps — the correction is re-imported like any late entry.
- **Fixture B:** the same, with a phone deletion of `e-set3` staged and applied after the watermark.
- **Expected outcome B:** after Discard, `e-set3` is gone from the bench effort — the late deletion is re-applied, so the session holds 2 sets.
- **Edge case of:** S-1401 — the origin and kind filter is deliberately absent (D-802).

### S-1412: `clearWatchInboxApplied` behaves identically on both stores
- **Fixture:** three staged inbox rows, two applied and one not; plus an id that was never staged.
- **Trigger:** `clearWatchInboxApplied([appliedA, appliedB, neverStaged])`.
- **Flow:** the method unsets the stamp on the applied rows, skips the unapplied row and the unknown id, and creates nothing.
- **Expected outcome:** on both stores, `appliedA` and `appliedB` read back with `appliedAtMs == null`, the unapplied row is unchanged, `getWatchInboxEntry(neverStaged)` is still null, and the rows survive a restart with the same values. The session's unapplied-end list is unchanged.
- **Edge case of:** none — the repository half of the cross-store parity that the probe asserts scenario by scenario.

### S-1413: a session with no late entry is untouched by the recovery
- **Fixture:** the capture contract's `full` case imported, edit mode entered, no late entry.
- **Trigger:** the user adds a set, then Discard.
- **Flow:** the recovery runs (the watermark is non-null) and finds no late row, so it returns without writing.
- **Expected outcome:** the bench effort holds the wrist's 3 sets and the user's added set is gone. No inbox row's `appliedAtMs` changed, and no import pass ran.
- **Edge case of:** S-1401 — the empty state.

### S-1414: a snapshot taken with no watermark recovers nothing
- **Fixture:** S-1401's fixture, but the snapshot is taken with `snapshotSessionState()` and no watermark argument.
- **Trigger:** `e-set3` arrives late, the user adds a set, then Discard.
- **Flow:** the restore sees a null watermark and skips the recovery (D-803).
- **Expected outcome:** the bench effort holds 2 sets — the pre-fix behaviour, deliberately preserved for callers that record no watermark. This is the guard that the nullable field is not silently treated as "the empty set".
- **Edge case of:** S-1401.

### S-1415: the screen's own watermark capture
- **Fixture:** the capture contract's `full` case **minus `e-set3`**, imported into a Mock store. The real `WorkoutSessionScreen` is mounted with `editMode: true` and the real `WatchSessionInbox` as the `WorkoutState`'s recovery handle; the two exercise coach marks are pre-marked seen so neither overlay absorbs the taps.
- **Trigger:** the screen enters edit mode (it reads the watermark and takes the snapshot), `e-set3` arrives late, the state reloads, the user opens the bench and adds a set through the screen, then Discard through the screen's own Back → "Unsaved changes" → Discard path.
- **Flow:** the screen's own `_loadExercises` reads `appliedWatchEntryIds()` before `loadSessionData()` and passes it to `snapshotSessionState()`; Discard runs `restoreSessionSnapshot`, which replaces the bench rows from the snapshot and then re-applies the late entry.
- **Expected outcome:** the bench effort holds **3** sets — the wrist's `e-set3` and the two imported ones — and the third set reads the wrist's 5 reps and 80 kg. The test fails if the screen stops reading the watermark (the restore then leaves 2 sets).
- **Edge case of:** S-1401 — the same recovery, but driven through the screen's own capture rather than the state layer's.

### Executor block — read before Step 0

- **Step 0a.** Read `docs/global_conventions.md`, then this plan in full, then O-17 in `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md` (search `O-17`) and the F-1 fix precedent in the same file (search `F-1`).
- **Step 0b.** Record the baselines by running `gateway.sh lint` and `gateway.sh test` and quoting their **final lines verbatim** into the evidence file. Expected: `196 issues found.` with 0 errors, and `+3227 ~1: All tests passed!`. If yours differ, quote yours and say so.
- **Step 0c.** Red run. Write the phase's test file **before** the code it tests, run `gateway.sh test <that file>`, and paste the failure (a compile error for a missing API counts) into the evidence file. A test that has never failed proves nothing.
- **Rules.** Work on `develop`. Never commit, stage, merge, push or branch. The only shell command is `gateway.sh` (`list`, `lint`, `test [paths]`, `format <paths>`, `pub-get`, `git-status`, `git-diff`, `git-log`, `git-show`). No new dependency. `edit` needs an exact `old_str`. `flutter analyze` must stay at "none new" — never relax it. A test that seeds the Hive harness must seed it in `setUp`, never inside a `testWidgets` body (that hangs the suite); prefer plain `test()` for state-layer tests. Write evidence to the `.evidence.md` file, never into this plan; log every judgement call in the Assumption Log below, at most 3 lines each.
- **Doc checklist for every phase.** Search `docs/` and `test/` for each name you add (`watchEntryIdsAppliedAtSnapshot`, `appliedWatchEntryIds`, `clearWatchInboxApplied`, `WatchLateEntryRecovery`, `recoverEntriesAppliedSince`, `lateEntryRecovery`) and list every hit's file in the evidence file. Every behaviour sentence a doc gains must name the test that asserts it. Name constants, never restate their values. No hex, no sizes, no line numbers, no roadmap phrasing.
- **Inverse-edit mutations (all three required, all on tracked files, all reverted after).** M1: drop the watermark filter in the inbox's recovery (un-mark every applied row) — S-1410 must fail (S-1409 stays green: re-applying every applied row also re-applies the pre-edit deletion). M2: remove the `clearWatchInboxApplied` call (or the `appliedAtMs != null` filter in it) — S-1401 must fail. M3: move the recovery call in `restoreSessionSnapshot` to before the delete loops — S-1401 must fail, because the restore deletes the recovered rows again. Record all three red runs in the evidence file.

### Phase 1: the failing probe, on both repositories (@developer)

1. [x] Create `test/watch_session_edit_restore_late_entry_test.dart`, modelled on `test/watch_session_edit_restore_summaries_test.dart`: the `_PathProviderChannel` stand-in, a `_MockStore` and a `_HiveStore` harness, per-store groups, plain `test()`, Hive seeding in `setUp`. Use `test/helpers/watch_capture_import_harness.dart` (`captureEvents`, `observationsUp`, `seedCaptureCatalog`, `CaptureTransport`, `importedEfforts`, `importedRows`, `expectCaptureImport`) and the `full` case of `watch/contract/watch_capture_contract.json`.
2. [x] Write the probe as S-1401, exactly as the PR 2 probe ran it: import `full` minus `e-set3`; `loadHistoricalSession` + `loadSessionData` + `snapshotSessionState`; deliver `e-set3` through the inbox; `addEntry('e-bench')` + `loadSessionData()`; `restoreSessionSnapshot(snapshot)`; assert the bench effort holds 3 sets.
3. [x] Write S-1402 (a late entry that creates a new effort, with its instance and its summary), S-1403, S-1404, S-1405, S-1406, S-1407, S-1408, S-1409, S-1410, S-1413 and S-1414 in the same file, each as its own `test()` with the S-id in the name.
4. [x] Run `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart` and paste the failure into the evidence file. **This phase ends red by design.** S-1401, S-1402, S-1404, S-1405, S-1406 and S-1410 must fail; S-1403, S-1407, S-1408, S-1409, S-1413 and S-1414 must already pass (they assert behaviour the bug does not break). Record which failed and which passed, with the counts.

**Done Criteria:** `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart` runs and reports the expected split — the six listed tests failing, the six listed tests passing — with the output pasted into the evidence file. `gateway.sh lint` reports no new issue. **This phase is not green and must not be made green here.**
**Predicted Files:** `test/watch_session_edit_restore_late_entry_test.dart` (new), the evidence file.
**Phase 1 verification notes (Conductor, pending):** added at verification.

### Phase 2: the data layer (@dba)

1. [x] Add `final Set<String>? watchEntryIdsAppliedAtSnapshot;` to `SessionEditSnapshot` in `lib/core/models/session_edit_snapshot.dart` as an optional named constructor parameter defaulting to `null` (D-801, D-803). The eight existing required fields keep their order and their required-ness, so the three existing call sites compile unchanged. Document the field in the class's doc comment: what it is, that null means no recovery, and that it is read before the rows.
2. [x] Add `Future<void> clearWatchInboxApplied(Iterable<String> entryIds)` to `WorkoutRepository` in `lib/data/repositories/workout_repository.dart`, beside the other watch-inbox methods. Its doc comment states the contract: unset `appliedAtMs` on the named rows of the inbox; skip an id that names no row; skip a row whose `appliedAtMs` is already null; create nothing; delete nothing; touch no other row.
3. [x] Implement it in `lib/data/repositories/hive_workout_repository.dart`, following the shape of `markWatchInboxEntriesApplied` in the same file: read the box, for each id read the row, skip when absent or already unapplied, write `{...staged.toMap(), 'applied_at_ms': null}`. One write per changed row; no batch API.
4. [x] Implement it in `lib/data/repositories/mock_workout_repository.dart`, following the shape of `markWatchInboxEntriesApplied` in the same file, over the in-memory map. The two implementations must agree value for value, including the skip rules.
5. [x] Add S-1412 to `test/watch_capture_repository_parity_test.dart` in the `D-132 watch session inbox` group, so it runs once per repository through the existing `_Harness`. Use the file's own `_wristRow` helper. Assert: the two applied rows read back with `appliedAtMs == null` after a restart, the unapplied row is unchanged, the unknown id is still absent, and `getWatchSessionIdsWithUnappliedEnd()` is unchanged.
6. [x] Add the new method to the `_script`/`_dump` parity sequence in the same file so the "Hive and Mock store the same rows" group covers it: unset one applied row's stamp in the script and let the row-by-row `toMap()` comparison prove the two stores agree.
7. [x] Edit `docs/db_integration.md`'s "Watch Capture Storage" section: add the one write that unsets an applied stamp to the invariants, naming `test/watch_capture_repository_parity_test.dart` and the S-id. State that nothing deletes an inbox row and that the schema is unchanged.
8. [x] Edit `docs/data_models.md`'s `WatchInboxEntry` invariants: the "Applied once, never deleted" entry gains the one exception — an applied stamp is unset when an Edit Session Discard has to recover an entry that arrived after the snapshot — naming the test.

**Done Criteria:** `gateway.sh lint` reports no new issue (compare with Step 0b); `gateway.sh test test/watch_capture_repository_parity_test.dart` passes on both harnesses; `gateway.sh test test/db_seed_test.dart` passes unchanged; `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart` still shows the Phase 1 split (the data layer alone does not fix the bug); `gateway.sh git-status` shows no file outside Predicted Files.
**Predicted Files:** `lib/core/models/session_edit_snapshot.dart`, `lib/data/repositories/workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`, `test/watch_capture_repository_parity_test.dart`, `docs/db_integration.md`, `docs/data_models.md`, the evidence file.
**Phase 2 verification notes (Conductor, pending):** added at verification.

### Phase 3: the mechanism (@developer)

1. [x] Add `Future<Set<String>> appliedWatchEntryIds()` to `SessionCore` in `lib/state/workout/session_core_lifecycle.dart`: read `getWatchInboxEntriesForSession(currentSession.id)` and return the `entryId` of every row whose `appliedAtMs != null`. Return an empty set when there is no current session. Add the delegating method to `WorkoutState` in `lib/state/workout/workout_state.dart` beside `snapshotSessionState`.
2. [x] Change `SessionCore.snapshotSessionState` to take `{Set<String>? watchEntryIdsAppliedAtSnapshot}` and pass it into the `SessionEditSnapshot` (D-801). `WorkoutState.snapshotSessionState` takes and forwards the same parameter. The parameter is optional, so the three existing call sites are unchanged.
3. [x] In `lib/features/session/workout_session_screen.dart`, inside the existing `if (widget.editMode && _editSnapshot == null)` guard at the top of `_loadExercises()`, read the watermark **before** the `loadSessionData()` call and hold it; assign the snapshot with it at the existing snapshot site. The read must precede the row load (D-801): a row applied in the window between the two is in the snapshot's rows and not in the watermark, which is the safe direction.
4. [x] Add `WatchLateEntryRecovery` to `lib/state/watch/watch_session_inbox.dart` beside `WatchSessionRatings`: `Future<void> recoverEntriesAppliedSince(String watchSessionId, Set<String> appliedAtSnapshot)`. `WatchSessionInbox` implements both. The implementation reads the session's inbox rows, computes `late` as the applied rows whose id is not in `appliedAtSnapshot` (D-802), returns without writing when `late` is empty, otherwise calls `clearWatchInboxApplied(late)` and then the inbox's own settle for that session (D-804). It writes nothing else.
5. [x] Add `final WatchLateEntryRecovery? lateEntryRecovery;` to `WatchSyncGraph` in `lib/state/watch/watch_sync_wiring.dart` and set it to the inbox in `createWatchSync`'s return (D-811). Only one construction site exists; tests read only `.mirror`.
6. [x] Add `final WatchLateEntryRecovery? watchLateEntryRecovery;` to `WorkoutState`'s constructor as an optional named parameter defaulting to `null`, and pass it to `SessionCore`'s constructor. `SessionCore` holds it and calls it from `restoreSessionSnapshot` (next step). A null recovery means the restore behaves exactly as today.
7. [x] In `SessionCore.restoreSessionSnapshot`, after the delete/re-create loops and the summary re-create, and **before** the final `loadSessionData()`, call the recovery when `snapshot.watchEntryIdsAppliedAtSnapshot != null` and the recovery is non-null, with `(snapshot.sessionId, snapshot.watchEntryIdsAppliedAtSnapshot!)` (D-805). Await it.
8. [x] Reorder `lib/main.dart`'s bootstrap: construct `WorkoutState` **after** the `createWatchSync` block, passing `watchLateEntryRecovery: watchSync?.lateEntryRecovery`, and construct `exerciseLibraryState` after both. Everything else keeps its relative order. `createWatchSync` needs `calendarState.refresh`, `nutritionState` and `foodLibraryState`, which are defined after `workoutState` today, so the reorder is required rather than optional.
9. [x] Run `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart` and confirm the Phase 1 split is now **all green**. Paste the counts into the evidence file.
10. [x] Run the three inverse-edit mutations (M1, M2, M3 in the Executor block) one at a time, each reverted before the next, and paste each red run into the evidence file.
11. [x] Edit `docs/watch_session_capture.md`: a Structure row for the recovery handle, a new Invariant ("a watch entry that arrived while an Edit Session was open survives Discard"), and the Discard rule in the Rationale. Name the test and the S-ids.
12. [x] Edit `docs/modality_based_exercise_ui.md`'s Edit Mode section: the user-visible Discard rule — Discard throws away the user's own edits but never a watch entry that arrived while the screen was open. Name the test.
13. [x] Edit `docs/state_management/services_and_utils.md`'s `createWatchSync` section: `WatchSyncGraph` now carries a second handle, `WatchLateEntryRecovery`, and say what it is for. Name the test.
14. [x] Edit `docs/state_management/workout_state.md`'s `WorkoutState` construction-order block: the constructor now takes the optional recovery, and `lib/main.dart` builds `WorkoutState` after the watch graph. Name the test.

**Done Criteria:** `gateway.sh lint` reports no new issue; `gateway.sh test test/watch_session_edit_restore_late_entry_test.dart` passes in full; `gateway.sh test test/watch_session_edit_restore_summaries_test.dart test/session_summary_distance_test.dart test/watch_capture_repository_parity_test.dart test/watch_session_import_test.dart test/watch_capture_contract_test.dart` passes; `gateway.sh test` passes in full with the count grown only by the tests this PR adds; all three mutation red runs are in the evidence file; `gateway.sh git-status` shows no file outside Predicted Files.
**Predicted Files:** `lib/state/workout/session_core_lifecycle.dart`, `lib/state/workout/session_core.dart`, `lib/state/workout/workout_state.dart`, `lib/state/watch/watch_session_inbox.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/features/session/workout_session_screen.dart`, `lib/main.dart`, `test/watch_session_edit_restore_late_entry_test.dart`, `docs/watch_session_capture.md`, `docs/modality_based_exercise_ui.md`, `docs/state_management/services_and_utils.md`, `docs/state_management/workout_state.md`, the evidence file.
**Phase 3 verification notes (Conductor, pending):** added at verification.

### Phase 4: the residue sweep and the doc-claim table (@developer)

1. [x] Grep `lib/` and `test/` for every name this PR added (`watchEntryIdsAppliedAtSnapshot`, `appliedWatchEntryIds`, `clearWatchInboxApplied`, `WatchLateEntryRecovery`, `recoverEntriesAppliedSince`, `lateEntryRecovery`) and list every hit's file in the evidence file. Every hit must be a file in this PR's Predicted Files or a test that asserts the new behaviour. A hit in a file this PR did not touch is a finding.
2. [x] Prove no reader of the old behaviour remains: grep for `snapshotSessionState()` with no argument in `lib/` and confirm the only call site is the screen's, which now passes the watermark. The three test call sites are deliberately argument-free (D-803) and are listed as such.
3. [x] Confirm `lib/core/services/watch_session_importer.dart` is unmodified (`gateway.sh git-status`), and that `scripts/sqlite_schema.sql`, `lib/data/models/models.dart` and `test/db_seed_test.dart` are unmodified (D-810).
4. [x] Build the doc-claim → test table in the evidence file: every behaviour sentence this PR added to a doc, the file it is in, and the test that asserts it. Every row must name a test that exists and passes.
5. [x] Re-read each edited doc section and confirm it names no type, file, constant or test that does not exist, and that it carries no line number, hex value or roadmap phrasing.
6. [x] Confirm `docs/README.md` needs no new row (no new doc) and that no doc exceeds 64 KiB (`gateway.sh test test/docs_indexing_contract_test.dart`).

**Done Criteria:** `gateway.sh test test/docs_indexing_contract_test.dart test/navigation_contract_enforcement_test.dart` passes; `gateway.sh lint` reports no new issue; `gateway.sh test` passes in full; the residue sweep, the doc-claim table and the unmodified-file confirmations are all in the evidence file; `gateway.sh git-status` shows no file outside Predicted Files.
**Predicted Files:** the evidence file only (this phase writes no production or doc file unless a sweep finding requires one, in which case the finding and the fix are both recorded).
**Phase 4 verification notes (Conductor, pending):** added at verification.

### Fix round 1 (review findings 1–6) (@developer)

1. [x] Finding 1: remove S-1411 from the register and re-map A13 to S-1412 plus the probe's per-store coverage; delete the false S-1411 row and the "S-1411 and S-1412 are Phase 2's" line from the evidence file.
2. [x] Finding 2: add S-1415 to the register and its acceptance row (A16); the test lives in `test/watch_session_edit_restore_late_entry_test.dart` and drives the real `WorkoutSessionScreen`; its mutation proof (watermark read → `null`) is in the evidence file.
3. [x] Finding 3 + 4: fold the Discard Rationale sentence into the Invariant that carries the test pointers, and correct "recovers it at the next import pass for that session" to what `WatchSessionInbox.resume`/`_settle` do.
4. [x] Finding 5: widen `docs/watch_session_capture.md`'s scope block to name the restore and the screen.
5. [x] Finding 6: correct the Executor block's M1 text to name S-1410 (S-1409 stays green).

**Done Criteria:** S-1415 green on the Mock store and red under the watermark mutation; `gateway.sh lint` `196 issues found.`; `gateway.sh test test/docs_indexing_contract_test.dart` green; full `gateway.sh test` green.
**Predicted Files:** `test/watch_session_edit_restore_late_entry_test.dart`, `docs/watch_session_capture.md`, this plan, the evidence file.
**Fix round 1 verification notes:** in the evidence file's "Fix round 1" section.

## Governor actions

**None.** This PR deletes, moves and renames nothing. It adds one test file and edits tracked files. `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` stays untouched — another planner owns it in parallel.

## Files Affected (whole PR)

| File | Change |
|---|---|
| `lib/core/models/session_edit_snapshot.dart` | EDIT — the nullable watermark field (D-801, D-803) |
| `lib/data/repositories/workout_repository.dart` | EDIT — `clearWatchInboxApplied` on the interface |
| `lib/data/repositories/hive_workout_repository.dart` | EDIT — its Hive implementation |
| `lib/data/repositories/mock_workout_repository.dart` | EDIT — its Mock implementation |
| `lib/state/workout/session_core_lifecycle.dart` | EDIT — `appliedWatchEntryIds`, the snapshot parameter, the recovery call (D-805) |
| `lib/state/workout/workout_state.dart` | EDIT — the optional recovery parameter and the two delegations |
| `lib/state/watch/watch_session_inbox.dart` | EDIT — `WatchLateEntryRecovery` and its implementation (D-802, D-804) |
| `lib/state/watch/watch_sync_wiring.dart` | EDIT — `WatchSyncGraph.lateEntryRecovery` (D-811) |
| `lib/features/session/workout_session_screen.dart` | EDIT — the watermark read before the row load |
| `lib/main.dart` | EDIT — the bootstrap reorder and the recovery wiring |
| `test/watch_session_edit_restore_late_entry_test.dart` | NEW — the probe and every scenario |
| `test/watch_capture_repository_parity_test.dart` | EDIT — S-1412 and the scripted sequence |
| `docs/watch_session_capture.md` | EDIT — the recovery handle, the invariant, the Discard rule |
| `docs/data_models.md` | EDIT — the applied-stamp exception |
| `docs/db_integration.md` | EDIT — the one write that unsets a stamp |
| `docs/modality_based_exercise_ui.md` | EDIT — the user-visible Discard rule |
| `docs/state_management/services_and_utils.md` | EDIT — the second `WatchSyncGraph` handle |
| `docs/state_management/workout_state.md` | EDIT — the construction-order block |

**Not modified, deliberately:** `lib/core/services/watch_session_importer.dart`, `scripts/sqlite_schema.sql`, `lib/data/models/models.dart`, `test/db_seed_test.dart`, `test/in_session_pr_toast_test.dart`, `test/pr_toast_test.dart`, `watch/`, `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md`.

## Notes

- **Dependency graph.** Phase 1 (red) → Phase 2 (data layer) → Phase 3 (mechanism, green) → Phase 4 (sweep). Phase 2 alone leaves the probe red, which is expected and is asserted in its Done Criteria. Phase 3 is the only phase that turns the probe green. Phase 4 needs Phase 3's diff. Re-ordering Phase 2 before Phase 1 is possible but loses the red evidence the brief requires, so it is not offered.
- **Why the watermark is read before the rows.** The snapshot's rows are read by `loadSessionData()`. If the watermark were read after it, a row applied in between would be in the watermark and in the rows, so it would be neither recovered nor lost — but a row applied *before* the watermark read and *after* the row load cannot happen, so reading first is the only order that cannot miss a row. Reading first can only over-recover, and over-recovery is idempotent (D-806).
- **Why un-marking rather than a new importer mode.** An `apply(..., ignoreApplied:)` parameter would make the 1,477-line importer riskier, and a crash mid-way would lose the entry. Un-marking is durable: the row is staged, so the next pass recovers it even if the app dies between the un-mark and the pass.
- **Why the recovery is not injected into the screen.** Twelve `WorkoutSessionScreen(` construction sites exist; the restore is the one place that knows what was lost, and it already runs inside the state layer.
- **Intermediate state.** After Phase 2 the repository can unset a stamp and nothing calls it. That is expected: Phase 3 is its only caller, and Phase 2's parity test is its reader.
- **The duplicate receipt.** The recovery's import pass re-sends a receipt for the recovered entries. The wrist treats a re-send as an unacknowledged entry, so a second acknowledgement is harmless; suppressing it would mean a second receipt path in the inbox, which is more risk than the duplicate is worth.
- **Cost.** One extra repository read per edit-mode entry (the watermark) and, only when a late entry exists, one un-mark write plus one import pass. The common case — no late entry — costs the read and nothing else.

## Open Items

- None blocking. The three questions below are decided here with defaults; none blocks Phase 1.

## Progress

| # | Item | Result |
|---|---|---|
| 1 | Plan written (this file) | DONE |
| 2 | Plan line count measured by reading it back | DONE — planner: 353 lines; executor re-measures |
| 3 | Phase 1 — the failing probe, both repositories | DONE — 12 tests, 6 red / 6 green on both stores; `+12 -12` |
| 4 | Phase 2 — the data layer | DONE — `watchEntryIdsAppliedAtSnapshot` on `SessionEditSnapshot`; `clearWatchInboxApplied` on the interface, Hive and Mock; S-1412 added; probe split unchanged (`+12 -12`) |
| 5 | Phase 3 — the mechanism | DONE — probe 24/24 green on both stores; M1/M2/M3 red runs recorded; docs 11-14 edited; lint `196 issues found.`; full suite `+3276 ~1: All tests passed!` |
| 6 | Phase 4 — the residue sweep and the doc-claim table | DONE — sweep clean (no hit outside Predicted Files); doc-claim table 8 rows, every S-id opened and green; F-4.1 fixed in `docs/watch_session_capture.md`; lint `196 issues found.`; contracts `+10`; full suite `+3276 ~1: All tests passed!` |
| 7 | Evidence file baselines recorded (Step 0b) | DONE — lint `196 issues found. (ran in 3.1s)`; test `+3250 ~1: All tests passed!`; HEAD `c25617a9` |
| 8 | Fix round 1 — review findings 1–6 and S-1415 | DONE — S-1415 green and red under the watermark mutation; S-1411 removed from the register and the evidence; docs findings 3–5 applied; lint `196 issues found.`; full suite `+3277 ~1: All tests passed!` |

## Assumption Log

| Phase | Decision | Options considered | Choice and why | Verdict |
|---|---|---|---|---|
| — | (executors append here, at most 3 lines each) | | | |
| 1 | The Phase 1 test file must compile against the **current** public API, because a Dart compile error fails the whole file and would hide the split. | (a) reference the Phase 2/3 names now and accept a compile-error red; (b) express the six reds through the current no-watermark path. | (b). The six reds fail at runtime on the bug itself, which is stronger evidence than a missing symbol; Phase 3 edits the file to pass the watermark. | Accepted |
| 1 | The plan's Executor block predicted a `+3227 ~1` baseline; the observed baseline is `+3250 ~1` on the same commit. | (a) treat the plan's figure as authoritative; (b) quote the observed figure and say so. | (b), per the Executor block's own instruction. All deltas are measured against `+3250 ~1`. | Accepted |
| 2 | The brief requires S-1412 red before the method exists; the method was written first. | (a) paste a post-hoc argument that the test would fail; (b) temporarily remove the three declarations, capture the real compile error, restore them. | (b). The captured failure is the analyzer's own "method isn't defined", and the restored state is what the green run measures. | Accepted |
| 3 | The probe was red because `_enterEditMode` built `WorkoutState` without the recovery handle, not because the mechanism was wrong. | (a) change the mechanism; (b) fix the harness to pass the inbox the test already builds. | (b), per the brief: the mechanism was proven by a debug run; the harness was the defect. Assertions unchanged. | Accepted |
| 3 | S-1414's body was empty (declared but never exercised). | (a) leave it as a compile-only guard; (b) write the full scenario the register specifies. | (b). The register's expected outcome (2 sets after Discard) is the guard that null is not the empty set. | Accepted |
| 4 | The Rationale sentence claimed a stopped phone recovers the un-marked entry "at its next start". | (a) leave it — the common case (a late session_end) does recover at start; (b) correct it to "the next import pass for that session". | (b). `resume` settles only sessions with an unapplied `session_end`, so a late set row is not recovered at start; the corrected sentence is what `apply` does. Doc-only fix, recorded as F-4.1. | Accepted |

## Feedback

Empty. Findings belong in `2026-10-02-03d-stats-pr3d-late-watch-entry-plan.review.md`; the fix checklist goes here.

## Open questions (defaults applied)

Every one of these changes what the user eventually sees, so each is recorded with the default this plan applies. None blocks Phase 1.

1. **The duplicate receipt.** The recovery's import pass re-sends a receipt for the recovered entries. *Default applied:* send it — a second acknowledgement is harmless and suppressing it would add a second receipt path to the inbox (D-806). *Alternative:* suppress receipts for a recovery pass, which needs the importer to know it is a recovery.
2. **The recovered entry's position.** The re-import lays the session out the importer's way, which may move an exercise whose late entry is earlier than the ones already there. *Default applied:* accept the importer's canonical order (D-812) — one ordering rule, not two. *Alternative:* pin the recovered entry to the position the user's edits had left, which needs a second placement rule and a second set of tests.
3. **Four phases or three.** The docs phase could be folded into Phase 3. *Default applied:* keep four — the brief requires the doc-claim table and the residue sweep as their own verifiable surface, and Phase 3 is already the largest phase. *Alternative:* three phases, with the docs and the sweep as Phase 3's last steps.
