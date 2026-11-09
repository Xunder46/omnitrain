# Review: plan 36c routine adoption · Phases P1/D · e9c5207..working tree

Reviewer: the lead (the crew reviewer was stopped twice by the runner's read-loop guard: once for re-reading `watch_reference_sync.dart` 27 times, once for reading `logged_entry_rows.dart` in 10-line slices 25 times; see `.work/friction.md`). Scope: `lib/state/watch/watch_session_adoption_bridge.dart`, `test/watch_routine_adoption_test.dart`, `docs/watch_session_sync.md`, `docs/my_routines.md`.

Verdict: APPROVE WITH FIXES (all applied)
Counts: blocker 0 · major 1 · minor 3 · tests: flutter `+4723 ~1` before the Hive fix, analyze 182 (= baseline), swift unchanged (592)

## Findings

1. [Major, fixed] `test/watch_routine_adoption_test.dart` ran on the Mock store only (the Hive run then found that the null-set-index tie-break depended on the store's order; fixed with a store-independent rule, S-3653/b/c), while the app persists through Hive and invariant I-7 asks for identical output (the merge tests run every scenario under both). Fix applied (closed fix brief `brief-builder-app-P1-fix-1.md`): the tests run in a `Mock` and a `Hive` group; the lead re-ran the file.
2. [Minor, accepted] `_adopt` writes the session, effort rows and now planned rows one repository call at a time. A failure inside `_createPlannedRows` after `createSession` leaves a session without its planned rows; `consider` reports it through `onFailure` and rethrows, and a later snapshot then finds the row (`existing != null`) and loads it as is. This is the same class of partial write `_adopt` already had (a failing `createEffort`), not a new one; the template reads in `_routineFor` all happen BEFORE the first write.
3. [Minor, accepted by decision] A ladder only partly covered by a template (an effort deleted on the phone after the wrist synced) adopts as a free session; the plan chose that (A5) and the docs say so.
4. [Minor, accepted] `_routineFor` reads every template, segment and effort on each adoption; adoption happens once per wrist-started session, so the cost is a handful of reads even for hundreds of templates.
5. [Doc gap, fixed] The known limits (timed/hold/round efforts get no planned rows; a routine added to an already-open empty wrist session is not planned) were not stated; added as a bullet in `docs/watch_session_sync.md` ("What does not sync" list), naming the test that backs the first half.

## Checked, no finding

- Values: the adoption writes the same numbers the phone's own start writes (`populateSessionFromManifest` → `updateEntryValue` as-is; weights are kilograms), through `LoggedEntryRows.setObservations`, the same row builder `addEntry` uses (reps 10 / load 0.0 defaults, extra-weight row for an exercise without `load` or an unknown one).
- Redelivery and later revisions: `_adopt` runs only when `existing == null` and `_everSeen` is set at its end; S-3647 delivers the same snapshot twice and a later revision and asserts one session, two efforts, three rows.
- S-3642 edits the template (set 2 becomes 5 reps / 45 kg, a third effort joins) before the snapshot is received and asserts the phone's values, the link, and that the wrist's ladder is unchanged.
- Ten mutations (lead): no intent, no title, no link, set count short by one, default reps 0, default load 1, targets read for the wrong id, match on any slot only, load always known, non-set efforts get rows: each fails the guarding tests; files restored byte for byte.
