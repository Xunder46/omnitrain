# Review: 38g importer positional rests · P1, P3 · 80928669 + 38a-38f..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: 4945 passed / 0 failed / 1 skipped (`02:46 +4945 ~1: All tests passed!`, full suite via gateway `test`, exit 0)
Diff vs Predicted Files: conforms — the 38g-named files are all in `git-diff --stat 80928669` (`lib/core/services/watch_session_importer.dart`, `lib/core/utils/entry_rows.dart`, `lib/state/workout/timer_manager.dart`, `test/watch_session_merge_test.dart`, `test/entry_rows_test.dart`, `docs/rest_tracking.md`, `docs/watch_session_sync.md`). The working tree also carries the unrelated uncommitted 38a–38f work, which this review does not judge. `test/helpers/ui_standards_allowlist.dart` is NOT in the diff — no allowlist entry added, no ratchet raised.

## Findings
1. [Minor] docs/rest_tracking.md:~88–93 — actor attribution. The new section says the importer re-keys the effort's rests when the phone user deletes a watch-logged set through the live mirror. In the screen flow the phone's own delete runs first: `WorkoutSessionScreen._deleteSetAt` → `workoutState.deleteEntry` → `SessionCore.deleteEntry` (`lib/state/workout/session_core_entry.dart:648–688`) deletes the group rows and re-keys via `TimerManager.rekeyEntryRestsAfterDelete` BEFORE the auto-push stages `delete_entry`; the import pass then finds the rows gone (`rows.indexOf(entry)` → null, importer:776–806) and skips the re-key. The importer's loop re-keys only when the deleted set's rows are still in the store (deletion staged without the phone-side delete having removed them — the S-4505 fixture shape). Observable outcome is identical in every traced flow (exactly one re-key, by the shared pure rule), so this is a maintainer-facing imprecision, not a behaviour bug. Fix: one clause — "or the phone's own delete has already re-keyed them; the importer re-keys only when the rows are still in the store". Guard: none needed (doc-only).
2. [Minor, pre-existing, not production-reachable] lib/core/services/watch_session_importer.dart:776–806 — the plain `_placeEntries` removal path does not re-key rests. Traced: a wrist-only effort with rests {1,2,3}, a staged `delete_entry` whose rows are still in the store, and no phone-side `SessionCore.deleteEntry` → rows renumber to {0,1}, stale rest 3 is orphaned; a later appended set's rest report at position+1=3 hits the stale closed rest and is dropped, and the new set reads as logged with the deleted set's stamps. Not reachable in production: staging happens at send time AFTER `SessionCore.deleteEntry` has removed the rows (importer then skips via `indexOf` null), and the mirror's `deleteEntry` (`lib/state/workout/live_session_mirror_state.dart:484`) has no lib/ callers (only its internal wrappers and a debug main). Pre-existing before 38g (the uncommitted 38f work predates the 80928669 base, so the old inline loop is not diffable); 38g does not make it false. No fix required in this plan; record for a future pass if a staging path ever appears that deletes rows without the phone-side delete.

No Blocker or Major findings. The `_positionOf` kindSet guard mutation (survives, per the lead's mutation log) is unproven; my trace says the fallback `return index` is unreachable for sets in the delete loop (rows exist ⇒ the number's group exists in fresh `setGroups`) and correct in the rows-gone edge (post-hole list index = new position), so I do not raise it.

## Answers to the brief's five questions
Q1 — Is the `_positionOf` fallback (`return index`, importer:926–936) reachable for kindSet, and is it right?
Not reachable in any path that matters. New-entry block: `_createEntry` writes rows at `entryIndex: index`, so the group exists. Unfinished path: `unfinishedPlaceOf` only returns indexes whose stamped rows exist. Delete loop: `indexOf` non-null implies rows exist ⇒ the number's group exists in fresh `setGroups` (grouping verified at `lib/core/utils/entry_rows.dart:158–170`). Rows gone ⇒ `indexOf` null ⇒ position null ⇒ the entry is skipped. In the residual edge (rows deleted without staging, entry still in `now`), the fallback returns the post-hole list index, which IS the correct new position. No defect.

Q2 — Can a stale position be written, or a rest be re-keyed twice?
No. Deleted entries get no `_placed` record, so their rest reports are dropped (`placed == null`). Surviving entries' positions are computed after the delete loop from fresh rows. No double re-key: the screen flow's `SessionCore.deleteEntry` already removed rows and re-keyed, and the importer then skips (`indexOf` null); the importer re-keys only when rows remain (wrist-side/staged delete with rows present). `_Pass` is instantiated fresh per import run (importer:202, :271), so `_placed` never goes stale across passes.

Q3 — Does the re-key interact badly with `rested` (importer:812) or with two deletions in one pass?
No. `rested` is computed after the delete loop from fresh `getEntryRests`, so it reads the re-keyed rests. Two deletions: each iteration reads fresh rests AND fresh groups; the second entry's position is computed while its own rows are still present. Traced groups {0,1,2,3} with rests {1,2,3,4}, deleting numbers 1 then 2 → final rests {1,2}, correct.

Q4 — Does `EntryRows.restsAfterDelete` + `TimerManager.rekeyEntryRestsAfterDelete` lose any behaviour of the old inline loop?
No observable behaviour lost: null/empty early return, sorted output (S-4512), open/paused preserved (S-4508 test asserts it), id shape `rest-$effortId-${entryIndex-1}`, cache-first persist in TimerManager, never-notifies — all present and green (S-4301..S-4304 pass in the full run). The old inline loop is not diffable (uncommitted 38f work predates the base), so this answer rests on the new tests' assertions, which cover each listed property.

Q5 — Do the docs' claims hold?
Yes, with the one Minor imprecision in Finding 1. Every named test and constant exists (verified by reading this run): S-4301..S-4304 and S-4318 in `test/entry_delete_rests_test.dart:83–177`; group `Logger polish — deleting a logged set (S-4310, S-4319..S-4321)` at `test/logger_shell_screen_test.dart:1090` with test `S-4319: an edit-mode delete that is Saved keeps the new rest indexes` at :1179; `SessionEditSnapshot.entryRests` at `lib/state/workout/session_edit_snapshot.dart:76`, filled by `snapshotSessionState` (`session_core_lifecycle.dart:298`) and restored (`:341`, `:374–376`); `EntryRows.loggedSetNumbersOf` exists. `watch_session_sync.md` claims match the code.

## Assumption Log rulings
- A-1 (timed/hold/round have no number/position split; ruling pending at review): RATIFY. The code matches the assumption — only `kindSet` entries get a translated position (`_positionOf` importer:926–936); timed/hold/round wrist deletions leave rests untouched, which the plan records explicitly under "Not changed" / D-4. No evidence against.

## Scenario coverage
S-4501 → test/watch_session_merge_test.dart · S-4501 test (group at :2639) | covered
S-4502 → test/watch_session_merge_test.dart · S-4502a/S-4502b | covered
S-4503 → test/watch_session_merge_test.dart · S-4503 | covered
S-4504 → test/watch_session_merge_test.dart · S-4504 | covered
S-4505 → test/watch_session_merge_test.dart · S-4505 | covered
S-4506 → test/watch_session_merge_test.dart · S-4506 | covered
S-4507 → test/watch_session_merge_test.dart · S-4507 | covered
S-4508 → test/entry_rows_test.dart · group at :132–227 (+ S-4512 ordering) | covered
Extras beyond the plan (good, not findings): S-4509 (retry), S-4510 (delete after hole), S-4511 (two sets one message) in the merge group; S-4512 (ordering) in entry_rows_test.
