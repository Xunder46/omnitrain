# Plan 255 — The active-session list shows how far each exercise is

Review item 19 (owner list: "Active-session list shows no progress. Suggested: '2 of 3 sets' and a done mark.").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

On the live workout's exercise list (the screen before you open an exercise), every reps-and-sets exercise says how many of its sets are logged, and an exercise whose sets are all logged carries a done mark.

- A `set` exercise reads `0 of 3 sets` before anything is logged, `2 of 3 sets` after two logged sets, `3 of 3 sets` when all are logged (singular: `1 of 1 set`). Before this change it read `3 sets`.
- A hold exercise (`drill` effort) reads `1 of 3 holds` the same way.
- When every entry of a set or hold exercise is logged (and there is at least one), a check mark sits at the right end of the tile (semantic label `Done`).
- Editing a finished workout (edit mode) keeps the old `3 sets` text and shows no mark (progress means nothing there).
- Interval (`timed`) and round exercises are unchanged (their subtitle already shows time or round count).
- "Logged" is the app's own rule (`_isSetLogged`): a set counts when it went through Log Set (a rest exists for the next entry), a hold when its timer finished.

Acceptance: S-25501..S-25507 green, the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; existing tests that read the old `N sets` subtitle updated; no new red in the full suite against the base failing set; Docs delta applied.

## What the user sees

- Start a 3-set bench press: the list tile says `0 of 3 sets`. Log a set: back on the list it says `1 of 3 sets`; after the third a check mark appears.
- To SEE it: start a workout, add a set exercise, log a set, go back to the list.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25501 | `_buildExerciseSubtitle` for `set` returns `'$logged of ${entries.length} set${entries.length != 1 ? 's' : ''}'` and for `drill` `'$logged of ${entries.length} hold${...}'`, where `logged` counts the entries `_isSetLogged(effortId, i, effortKind)` says are logged; in edit mode (`widget.editMode`) and when there are no entries both keep the old text. `timed` and `round` are untouched. | `workout_session_list_view.dart:121-160`, `workout_session_screen.dart:824-840` |
| D-25502 | New helper `_exerciseProgressDone(exercise)` (true for `set`/`drill` with at least one entry, all logged, not edit mode). `_buildExerciseTileCard` gets `trailing: done ? Icon(Icons.check_circle, key: Key('exercise_tile_done_<effortId>'), color: <the theme's primary>, semanticLabel: 'Done') : null` on its `ListTile`. | `workout_session_list_view.dart:174-210` |
| D-25503 | The list already rebuilds when the workout state changes (entries, rests) because it reads `getEntryRests` through `_isSetLogged` the same way the detail view does; no new listener. | `workout_session_screen.dart` |

## Scenarios

Fixtures. The logger test harness of `test/exercise_set_last_value_test.dart` (`_buildSessionDeps`, the screen pump; the LIST is what shows after the pump, before `_openSessionDetail`). A set exercise with 3 entries (`workoutState.addEntry` twice more after `addExerciseToSession`); a set counts as logged when `workoutState.recordRestStart(effortId, nextEntryIndex)` exists for the NEXT entry (the rule above): log set `i` by recording a rest at entry `i + 1`. A hold exercise: `addExerciseToSession(exercise, effortKindOverride: 'drill')` with timed instances (look at how `test/state_test.dart` finishes one: `finishTimedEntry(effortId, index)` after starting it).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25501 | set exercise, 3 entries, none logged | tile subtitle `0 of 3 sets`; no `exercise_tile_done_<id>` | the subtitle read `3 sets` |
| S-25502 | two sets logged (rests at entries 1 and 2) | `2 of 3 sets`; no mark | no progress |
| S-25503 | all three logged (rests at 1, 2, and the third set's own rest rule: see the note below) | `3 of 3 sets` and the mark present with semantic label `Done` | no mark |
| S-25504 | one entry, logged | `1 of 1 set` (singular) and the mark | plural/ratio |
| S-25505 | hold exercise with 3 holds, one finished; then all finished | `1 of 3 holds`, no mark; then `3 of 3 holds` and the mark | no hold progress |
| S-25506 | the same set exercise with `editMode: true` | `3 sets`, no mark | edit mode would show progress |
| S-25507 | an interval (`timed`) exercise and a round exercise | their subtitles unchanged (`00:00 total`, the round count text), no mark | guards the untouched kinds |

Note on S-25503: the last set of an exercise is logged when a rest exists at entry `entries.length` (index 3 for three sets): the rule says "logged only if rest was created for the NEXT entry", so the final set only counts once a rest for a non-existent next entry exists; check how the screen's Log Set records it for the last set (`_logSet` creates the rest even after the final set?) and mirror it in the test; if the final set can never satisfy the rule, report that finding instead of changing the rule: it decides whether "3 of 3" and the mark are reachable.

Existing tests that read the old `N sets` subtitle must be found by the readers run and updated.

## Input-reality checklist

1. Writers: rests are written by Log Set (`recordRestStart`), the wrist importer and Edit Session; hold instances by the timer. Units: counts.
2. Lifecycle: deleting a set lowers the total and the count together; adding a set raises the total; a deleted logged set (plan 38f) leaves positional rests: the count follows `_isSetLogged` so it agrees with the detail view's dots.
3. Settings: none.
4. Time: none.
5. Cost: `_isSetLogged` per entry per tile per rebuild: it scans the effort's rests (small lists).
6. Words: `N of M sets`, `N of M holds`, `Done` (owner to read).
7. Competition: the tile's tap target is unchanged; the check sits in the ListTile's trailing slot (the tile has none today); rolling and standard lists share the tile builder.

## Phases

1. **P1 builder-app**, scope `lib/features/session/workout_session_list_view.dart`: D-25501, D-25502 (exact code in the brief). No full suite.
2. **P2 lead**: readers; list the red tests that read the old subtitle.
3. **P3 builder-app**, scope the listed tests plus `test/session_list_progress_test.dart` (new): S-25501..S-25507.
4. **P4 lead**: full suite, analyze, mutation pass, docs, reviewer.

## Readers

`test/screen_widget_test.dart` (the session screen groups), `test/interaction_flow_test.dart`, `test/exercise_set_last_value_test.dart`, `test/session_toolbar_rework_test.dart`, `test/header_standardization_test.dart`, `test/watch_*session*` tests that pump the list, `test/workout_session_*`.

## Mutation list (lead)

(a) the logged count ignored (always 0) (S-25502); (b) the singular rule removed (S-25504); (c) the mark shown when not all logged (S-25502); (d) the mark never shown (S-25503); (e) edit mode not excluded (S-25506); (f) drill kind unchanged (S-25505); (g) `timed` also changed (S-25507); (h) the mark shown for zero entries.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/modality_based_exercise_ui.md` | MODIFIED | **set**: "3 sets" | **set**: "2 of 3 sets" (logged of total; a check mark | S-25501, S-25503 |

The tile's description lives in `docs/modality_based_exercise_ui.md` (list view summary stats), not in the widget catalog: the two lines there (`set`, `drill`) are rewritten by the lead.

## As built

Added after the mutation pass and the review: S-25507b (a fully finished interval shows no mark), S-25508 (an exercise with no entries shows `0 sets` and no mark), S-25509 (a hold that finishes itself while the list is on stage updates its tile, proven with a store whose write is gated: with a fast Mock store the early rebuild already sees the finished hold, so the first version of the test passed without the fix). Production change beyond D-25501/D-25502, from the review: `workout_session_timer_mixin.dart` rebuilds the screen after `finishTimedEntry` resolves (the early `setState` in `_handleEffortTimerExpired` runs before a slow store has finished the write, so the tile kept the old count until the next navigation). The docs row names `docs/modality_based_exercise_ui.md` (where the tile is described), not the widget catalog.

## Open items

1. (owner) Interval (`timed`) and round tiles show no progress or done mark yet.
2. (owner) A set exercise reads `0 of 3 sets` before anything is logged (instead of `3 sets`).
