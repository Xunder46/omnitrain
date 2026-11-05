# Plan 38g — The watch importer reads and writes rests by POSITION

Status: SEEDED by the lead 2026-10-16 (no architect run: one file of logic, scenarios derived by hand and proven red by the builder's first run). NOT STARTED. Base: uncommitted claude_develop tree (38a-38f built) on `80928669`. Not authorised to commit: the owner commits; never push; no branch work.
Follow-up of `docs/plans/2026-10-15-38f-logger-polish-plan/` (D-1, D-11, Assumption Log A-1, review findings 1 and 2). Scenario ids: `S-45xx` (grep clean in `test/`, `docs/`, `watch/`, `lib/` on 2026-10-16).
Hard rules: no data-model change, no repository-interface change, no watch-wire change.

## Goal and acceptance (what the user sees)

After the user deleted a set in the middle of a set exercise on the phone while a watch session is live (the row numbers keep a hole, the positions do not), the watch's later sets and the watch's deletions behave as they do without a hole:

- A1. A set the watch logs lands as the next set and reads as logged (its rest marker sits at its POSITION + 1), exactly one rest marker for it — also when the watch's rest report for it arrives later (that report closes the marker in place and writes no second one).
- A2. A set the watch logs that fills a planned set after the hole reads as logged at that planned set's position; no marker lands on a later set.
- A3. A running rest of a later set is not ended by a watch set that fills an earlier planned set.
- A4. When the phone user deletes a watch-logged set (through the live mirror), the other sets keep the logged / unlogged state they had; the deleted set's rest marker goes with it and the later markers move down one, the same rule as a delete made on the phone's own screen.
- A5. Unchanged: planned-set fill order, the phone's own finished rest wins, redelivery writes nothing, timed / hold / round entries, history imports without a hole, every stored value shape.

## Cause (verified by reading)

Since 38f a rest's `entryIndex` is a POSITION: the rest at `k` marks the set at position `k-1` logged, and a phone delete removes the deleted set's rest and re-keys the later ones (`TimerManager.rekeyEntryRestsAfterDelete`, `lib/state/workout/timer_manager.dart`). Set row ids carry a NUMBER that is never renumbered. The importer (`lib/core/services/watch_session_importer.dart`) still:
- (a) writes the arrival rest at `index + 1` where `index` is the row NUMBER (`_placeAroundUserRows`, the `fills && !rested.contains(index + 1)` block and `rested.add(index + 1)`), and the wrist's rest report at `placed.index + 1` (`_applyRests`, `entryIndex = placed.index + 1`; `_placed` records the number);
- (b) decides whether an earlier rest is still open with `rest.entryIndex > index` (number);
- (c) deletes a deleted wrist set's rows and instance (the "Deleted since they were imported" loop) without touching the rests.
`_plannedSetToFill` is already positional (38f fix 3, S-4334).

## Decision Ledger

- D-1 `_placed` records both numbers: `({String effortId, int index, int position})`. `index` stays what the rows and instances carry (`_createEntry`, `_reindexInstance`); `position` is what a rest is keyed on (+ 1). For a `set` entry position is the 0-based index of the group whose number is `index` among `EntryRows.setGroups(await getEffortObservations(effortId))`, read AFTER the entry's rows exist; for timed / hold / round entries position = index (the phone renumbers their instances on delete, so their index already is a position); in the plain history path (`_placeEntries` main loop) position = index (no user rows means contiguous numbers). Three write sites of `_placed` (grep `_placed\[`), one reader (`_applyRests`).
- D-2 `_applyRests` keys on `placed.position + 1` (entryIndex, id `rest-<effort>-<position+1>` unchanged shape); the arrival-rest block keys on `position + 1` and records `rested.add(position + 1)`; the open-rest closing compares `rest.entryIndex > position`.
- D-3 The wrist-delete loop, for a deleted entry of wire kind `set` only: before its rows are deleted, read its position (the group whose number `rows.indexOf(entry)` names, in a fresh `setGroups` read); when the entry has no own rows of the effort (`ownRowsOf` empty / `indexOf` null) nothing is re-keyed. After its rows are deleted, re-key the effort's rests with the same rule as the phone: new pure function `EntryRows.restsAfterDelete(Iterable<EntryRest> rests, String effortId, int deletedIndex)` in `lib/core/utils/entry_rows.dart` returning null when no rest sits at `deletedIndex + 1` or above, else the kept list (rest at `<= deletedIndex` stay, the rest at `deletedIndex + 1` is dropped, every higher one re-keyed down by one with id `rest-<effortId>-<newIndex>`, sorted by `entryIndex`). `TimerManager.rekeyEntryRestsAfterDelete` is changed to call it (one rule, one place) and keeps its cache-first persist order. The importer persists with `deleteEntryRestsForEffort(effortId)` then `createEntryRest` per kept rest (existing repository methods only) and counts a write (`changed = true`) so the effort is named for refresh. Each deleted entry is handled one at a time in `before` order, each reading fresh groups, so several deletions in one pass stay correct.
- D-4 Timed / hold / round wrist deletions are NOT changed (not in the task; the importer does not renumber their instances after a delete, which is a separate matter: recorded under "Not changed").
- D-5 The re-key also applies in the history path that reaches `_placeAroundUserRows` without `fillPlanned` (the same delete loop). `test/watch_session_import_test.dart` A-51 deletion tests have no rests and must stay green; S-327 / S-337 in the import / merge tests are re-checked by the full run.
- D-6 Tests: new group in `test/watch_session_merge_test.dart` (it already runs every scenario under Mock AND Hive; plain `test()`), the pure rule in `test/entry_rows_test.dart`. Fixtures reuse the file's helpers (`_phone`, `_snapshot`, `_plannedRows`, `_phoneRows`, `_rests`, `_ids`, `_set`, `_rest`, `sortedObservations`, `observationsUp`); the delete is staged with `phone.inbox.stagePhoneChanges` using a `structure_change` envelope carrying `{'kind': 'delete_entry', 'entryId': ...}` (the shape of `_correctionEnvelope`, `watch_session_merge_test.dart`; changeId unique per call).

## Scenarios (exact fixtures; every `fails today` is derived from the code above and PROVEN by the builder's red run)

Common: `phone = await _phone(repository)`; `phone.router.receive(_snapshot())`; effort `sl-1`; stamps `_t1 < _t2 < _t3 < _t4`; `_plannedAt` earlier than all.

- S-4501 (merge, hole, a wrist set appends). Fixture exactly as S-4334: three phone rows (numbers 0,1,2; reps 12/11/10; weights 50/51/52; stamps `_t2/_t3/_t4`), `refreshEfforts(['sl-1'])`, `recordRestStart/End('sl-1', 1..3)`, `phone.state.deleteEntry('sl-1', 1)` → numbers {0,2}, rests {1,2}. Wrist set `sx-1` (reps 8, 42.5, `_t1`) arrives. Expect: rows numbers {0,2,3}; rests exactly [1,2,3]; rest 3 id `rest-sl-1-3`, `restStartMs == _msOf(_t1)`, `restEndMs == null`. Fails today: rests [1,2,4] (the number 3 + 1).
- S-4502 (merge, hole, the wrist's rest report, TWO shapes). Same fixture. (a) the report arrives in a LATER message: `_rest('rx-1', slot:'sl-1', exerciseId:'ex-1', startedAt: _restStart, endedAt: _restEnd, afterEntryId:'sx-1')` — guards the `_placed` entry written for an already-placed entry. (b) the set and its report arrive in ONE message (`observationsUp('s-w1', [set, rest])`) — guards the same-pass write. Expect for both: rests exactly [1,2,3]; rest 3 `restStartMs == _msOf(_restStart)` and `restEndMs == _msOf(_restEnd)`; no rest at 4. Fails today: rests [1,2,4].
- S-4503 (merge, hole, a wrist set FILLS a planned set after the hole). `_plannedRows(count: 4)` (numbers 0..3, no rests); `phone.state.refreshEfforts(['sl-1'])`; `recordRestStart/End('sl-1', 1)` (set at position 0 logged); `phone.state.deleteEntry('sl-1', 1)` → numbers {0,2,3}, rests {1}. Wrist set `sx-1` (reps 8, 42.5, `_t1`) arrives. Expect: it fills number 2 (the first unlogged POSITION is 1): `obs-sl-1-2-reps` holds 8 with stamp `_t1`; numbers still {0,2,3}; number 3 still planned (reps 10, stamp `_plannedAt`); rests exactly [1,2], rest 2 open from `_msOf(_t1)`. Fails today: rests [1,3].
- S-4504 (merge, hole, an open rest of a LATER set is not closed). `_plannedRows(count: 5)` (0..4); `refreshEfforts`; closed phone rest at 1 (`recordRestStart/End('sl-1', 1)`: position 0 logged); `recordRestStart('sl-1', 5)` left OPEN (position 4 logged, running); `deleteEntry('sl-1', 1)` then `deleteEntry('sl-1', 1)` again → numbers {0,3,4}, rests {1 closed, 3 open}. Wrist set `sx-1` arrives and fills number 3 (position 1). Expect: rests exactly [1,2,3]; rest 1 unchanged (closed); rest 2 is the arrival rest (open from `_msOf(_t1)`); rest 3 is STILL open (`restEndMs == null`, its `restStartMs` unchanged). Fails today: the rest at 3 is closed (3 is not above number 3) and the arrival rest lands at 4 (rests [1,3,4]).
- S-4505 (merge, wrist set deleted in the middle keeps the others' state). No hole beforehand. `_plannedRows(count: 3)`; wrist sets `sx-1`, `sx-2`, `sx-3` (reps 8/9/10, 42.5, `_t1/_t2/_t3`) arrive (message ids distinct), each fills the next planned set; then the wrist's rest reports `rx-1` (after `sx-1`, `_restStart`/`_restEnd`) and `rx-2` (after `sx-2`, `_t2 + 1 min` .. `_t2 + 2 min`) arrive: rests {1 closed, 2 closed, 3 open from `_msOf(_t3)`}. Stage `delete_entry sx-2` (`phone.inbox.stagePhoneChanges`). Expect: numbers {0,2}; rests exactly [1,2]; rest 1 unchanged; rest 2 carries the OLD rest 3's stamps (`restStartMs == _msOf(_t3)`, open) and id `rest-sl-1-2`; no rest at 3. Fails today: rests [1,2,3] (the deleted set's rest stays and nothing moves).
- S-4506 (merge, the owner-named mixed case). `_plannedRows(count: 3)`; the phone's own logged state for position 2 only: closed phone rest at 3 (`_phoneRest(repository, effortId:'sl-1', entryIndex: 3, startedAtMs: _msOf(_t3), endedAtMs: _msOf(_t4))`); wrist set `sx-1` (`_t1`) arrives and fills position 0 (rest 1 opened) → positions 0 logged / 1 unlogged / 2 logged, rests {1,3}. Stage `delete_entry sx-1`. Expect: numbers {1,2} (`obs-sl-1-1-*`, `obs-sl-1-2-*` stay planned / the user's, nothing renumbered); rests exactly [2] and its `restStartMs == _msOf(_t3)`; so position 0 (number 1) reads unlogged and position 1 (number 2) reads logged (assert through `EntryRows.loggedSetNumbersOf(EntryRows.setGroups(rows), rests)` == {2}). Fails today: rests [1,3] (position 0 reads logged, position 1 unlogged: one off).
- S-4507 (merge, the only wrist set is deleted: its rest goes, a redelivery changes nothing). `_plannedRows(count: 1)`; `sx-1` arrives (rest 1 open). Stage `delete_entry sx-1`. Expect: no row of number 0 remains of `sx-1`'s stamp and rests exactly [] (the rest at 1 is the deleted set's mark). Stage the SAME delete again (a redelivery): rests still [], no failure (`phone.failures` empty). Fails today: rests [1].
- S-4508 (`EntryRows.restsAfterDelete`, pure; `test/entry_rows_test.dart`). Effort `e`, rests at 1, 2, 3 with `restStartMs` 1000, 2000, 3000 and ids `rest-e-1..3`: delete 0 -> entryIndex [1, 2], startMs [2000, 3000], ids `rest-e-1`, `rest-e-2`; delete 1 -> [1, 2], startMs [1000, 3000]; delete 2 -> [1, 2], startMs [1000, 2000]; delete 3 -> null (no rest at 4 or above). Rests {1}: delete 0 -> empty list (the rest at 1 is the mark); delete 1 -> null. An empty input -> null. A re-keyed rest keeps `restEndMs == null`, `restIsPaused == true` and `restPausedAtMs`. Fails today: the function does not exist (a compile error: the prover's list for this row is mutations only).

## Phases

Parallel: none (one writer scope). Never run the full suite inside a builder run.

- P1 (crew-builder-app) — items:
  1. Report skeleton first at `.work/crew/2026-10-16-38g/report-p1.md`.
  2. `EntryRows.restsAfterDelete` + S-4508 (`lib/core/utils/entry_rows.dart`, `test/entry_rows_test.dart`).
  3. `TimerManager.rekeyEntryRestsAfterDelete` calls it (`lib/state/workout/timer_manager.dart`); `test/entry_delete_rests_test.dart` unchanged and green.
  4. Red tests S-4501..S-4507 in `test/watch_session_merge_test.dart` (ONE new group, touch no existing test); run them alone and report the failing values (all must fail for the stated reason BEFORE step 5).
  5. Importer D-1..D-3 (`lib/core/services/watch_session_importer.dart`); comments: the `_placed` doc ("keyed on that index + 1") becomes position, the loop comment "a rest following one of them is keyed on that index + 1" becomes position.
  6. Run `test/watch_session_merge_test.dart`, `test/watch_session_import_test.dart`, `test/entry_rows_test.dart`, `test/entry_delete_rests_test.dart`, `test/watch_session_edit_restore_late_entry_test.dart`, `test/watch_session_projection_test.dart` (a Done list naming the importer's siblings).
  Write scope: `lib/core/utils/entry_rows.dart`, `lib/core/services/watch_session_importer.dart`, `lib/state/workout/timer_manager.dart`, `test/watch_session_merge_test.dart`, `test/entry_rows_test.dart`, `.work/crew/2026-10-16-38g/**`.
- P2 (crew-prover) — mutations list only (the lead applies them, by script): see "Guards to prove".
- P3 (crew-docs-keeper) — docs: `docs/watch_session_sync.md` (the rest paragraph: rests keyed by position, a wrist delete re-keys), `docs/rest_tracking.md` if it states the importer key, plan evidence; then (crew-reviewer) one review.

## Guards to prove (mutations the lead applies)

M1 `_applyRests`: `placed.position + 1` → `placed.index + 1` (S-4502a/b). M2 arrival rest keyed at `index + 1` (S-4501/4503). M3 `rested.add(position + 1)` → `rested.add(index + 1)`. M4 open-rest closing compares `rest.entryIndex > index` (S-4504). M5 the `_placed` write for already-placed entries (the loop after the new-entry loop) records `position: index` (S-4502a). M6 the same-pass `_placed` write records `position: index` (S-4502b). M7 delete loop: skip the re-key (S-4505/4506). M8 delete loop: re-key from `position + 1`'s wrong neighbour (`deletedIndex` off by one: `position + 1`). M9 delete loop: position read from the number (`rows.indexOf(entry)`) instead of the position (S-4506). M10 `restsAfterDelete`: keep the mark (do not drop the rest at `deletedIndex + 1`). M11 `restsAfterDelete`: do not shift higher rests. M12 `restsAfterDelete`: lose open / paused state on re-key (`copyWith` replaced by a new `EntryRest` without the flags). M13 re-key writes without `deleteEntryRestsForEffort` (leaves stale old ids). M14 the re-key `changed = true` removed (S-4507 / the refresh: the test reads repository rows only; unobservable there — the prover says NOT PROVEN, lead decides). M15 `TimerManager` no longer calls `restsAfterDelete` and keeps its own loop (the pure rule and the manager must agree: `test/entry_delete_rests_test.dart` S-4301..S-4304 stay green either way — equivalent mutation, listed only to be reported unobservable).

## Not changed (recorded)

- Timed / hold / round wrist deletions leave later instances' indexes and rests as they were (D-4); nothing there turns row numbers into positions.
- Rests the wrist's session writes in a history import without a hole keep `position == index`.
- The UI-visible delete of a watch-logged set through the live mirror cancels no scheduled rest ping (the importer has no notification service); a running rest of the deleted set simply disappears from the store.

- `_placeEntries`' plain removal path (no user rows) does not re-key rests; not reachable in production because the phone's own delete has already removed the rows and re-keyed before the delete is staged (review finding 2). Revisit only if a staging path appears that deletes without the phone-side delete.

## Scope budget

One file of logic, one new pure function (~25 lines), ~8 new tests (~330 lines of test), two doc paragraphs. Well under `.github/copilot/pr-scope-budget.md`; no phase over 8 items.

## Progress

- 2026-10-16 seeded by the lead; P1 built by crew-builder-app (red first: 16 cases red under Mock+Hive with the plan's predicted values, then green); lead mutations 19 of 19 red after fix 1 (first pass left M2a, M3, M9, M18 green: fix 1 added S-4509..S-4512, re-run red; M14 and M17 were redundant lines, removed); docs keeper; review APPROVE (0 blocker, 0 major, 2 minor: doc attribution fixed, pre-existing `_placeEntries` removal path recorded below). Not proven: `_positionOf`'s non-set guard (no timed-effort merge harness; reviewer traced it correct). Final: `flutter analyze` 182, 0 errors; full suite `+4927 ~1` all passed.

## Assumption Log

- A-1 (lead) Timed / hold / round efforts have no number/position split (their instances are renumbered by the phone's delete), so only the `set` kind is translated. Ruling at review: pending.

## Feedback

(none yet)
