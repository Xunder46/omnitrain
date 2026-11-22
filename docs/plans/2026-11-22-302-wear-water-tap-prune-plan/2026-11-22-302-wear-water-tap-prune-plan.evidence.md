
# Plan 302 evidence

Base commit `af1c676f` (plan 300). The tree was shared with another session (the food-category repair) that had uncommitted edits in `lib/core/constants/data_version.dart` and `lib/data/repositories/*`; every check and the commit were scoped to this plan's own paths. Windows PC: the full suite is red in the baseline.

## Builds

- P1: `crew-builder-watch`, run `20261122-181512`, 1.4 min, no denial, no stop. Five files, as briefed (+90 lines).
- Lead: `dart format` on the five files reflowed four unrelated spots in `watch_session_engine.dart` (a `when` clause, two assignments, a set literal); the engine was restored from git and the one new method re-inserted by script, so its diff is the 18 added lines only. Never format a whole existing file: format only a new file, or restore the reflow.

## Checks (observed)

- `flutter test test/watch_water_prune_test.dart`: `+9: All tests passed!` (S-30201..S-30203 under the in-memory store and Hive, S-30204, S-30205, S-30206).
- The existing water tests (`watch_water_state_test`, `watch_water_engine_test`, `watch_water_store_test`, the water wiring and bar tests) ran in the mutation pass as the regression set and pass.
- `flutter analyze` (whole repo): `174 issues found.` (baseline 174, 0 errors) after a test double that implements the store directly (`watch_dialled_per_exercise_test.dart`) got the new member: the first whole-repo run reported 1 error and 175 issues, which is how that implementer was found (the seed grep for `implements WatchSessionStore` was run on `lib` only, not `test`).

## Mutation pass (lead; in place, backup outside the tree, restored and compared after each)

14 mutants: the receipt gate removed; the age not strict; the age direction reversed; the kind filter removed; a non-string time dropped; an unreadable time dropped; Hive deleting nothing; the in-memory store keeping the rows; the engine keeping the taps in memory; the retention shortened to 24 h; restore not pruning; the cutoff sign flipped; and two on the engine's lens trim. **12 of 14 killed.** The two survivors are the engine's projection-lens trim (`_entryCorrections` and `_deletedEntryIds` removal for a dropped tap): they mirror `pruneConfirmed`, and no message the phone sends names a water tap's entry id (corrections and deletions are for workout entries), so there is no observable difference today; named, not closed.

