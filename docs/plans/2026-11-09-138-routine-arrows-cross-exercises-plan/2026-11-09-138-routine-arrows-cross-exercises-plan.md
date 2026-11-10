# Plan 138 — routine editor: the Previous / Next arrows cross exercises

Slug `2026-11-09-138-routine-arrows-cross-exercises`. Branch `claude_develop` (the working branch; never switched).
Base commit `b78112ef2f99d2bdaf450c889cbe4b7c53d7d80d`. Series: **138 (this plan, "PR A")** = arrows only.
**PR B (separate plan, not here)** = going back from an exercise returns to that exercise in the list, in the routine
editor and the live session. No scroll code is touched by this plan.

## Goal and acceptance

Owner report (2026-11-09): in the routine editor the Previous / Next arrows only walk the sets of one exercise; to reach
the next exercise the owner has to go back to the list and tap it. The live session already walks across exercises.

What the user sees after this plan (routine editor, exercise detail view):

1. **Next** on the last set of an exercise opens the next exercise on its **first set**. It never adds a set.
2. **Previous** on the first set of an exercise opens the previous exercise on its **last set**.
3. **Next** is dimmed and does nothing on the last set of the last exercise; **Previous** is dimmed and does nothing on
   the first set of the first exercise.
4. "Next exercise" means the next one in the order the list shows: block by block, top to bottom, including after the
   blocks or exercises were reordered.
5. Nothing else changes: the header, the set bar, the tooltips (`Previous Set`, `Next Set`), the list view and its
   scroll position behave exactly as today.

Acceptance: S-4514..S-4518 pass (Mock harness, the routine editor has no Hive path in these tests); the existing
S-4512 stays green unchanged; `flutter analyze` count not above baseline; invariant grep clean;
`test/ui_standards_contract_test.dart` and `test/docs_indexing_contract_test.dart` pass; the routine screen test files
pass; every guard arm proven by a mutation the lead observed.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `_nextSet` on the last set of effort *i* (when *i* is not the last effort) calls the existing `_openDetail(i + 1)`, which sets `_currentExerciseIndex`, `_currentSet = 1` and keeps the detail view. | `routine_setup_screen.dart:775` `_openDetail`, `:1425` `_nextSet`, S-4514 |
| D-2 | `_previousSet` on set 1 of effort *i* > 0 moves to effort *i - 1* with `_currentSet` = that effort's set count, read with `_getSetCount(previous, widget.routineState.getEffortTargets(previous.id))`. | `:1202` `_getSetCount`, S-4515 |
| D-3 | The enabled flags move into `_buildSetControls`: Previous enabled iff `_currentSet > 1 || _currentExerciseIndex > 0`; Next enabled iff `_currentSet < totalEntries || _currentExerciseIndex < currentEfforts.length - 1`. The `onPressed` is null exactly when the arrow is disabled. | `:1400-1418`, S-4516 |
| D-4 | Next never adds a set. The only adder stays `_addSet` (the `+` in the sets control). | S-4517 |
| D-5 | Order: the detail index is an index into `routineState.currentEfforts`, which sorts segments by `orderIndex` then each segment's efforts by `orderIndex`; the list renders `currentSegments` and `getEffortsForSegment` whose data is loaded sorted (Mock and Hive) and re-indexed by every add / reorder. So both orders agree; no new ordering code. A test pins it across two blocks and after `reorderSegments`. | `lib/state/routine/routine_state.dart:983-997`, `:547-565`, `:628-650`; `hive_workout_repository.dart:2116,2155`; S-4518 |
| D-6 | No per-exercise widget state exists in the detail view (only `_currentExerciseIndex`, `_currentSet`, list scroll controller), so moving from exercise to exercise without passing through the list loses nothing. Row widgets are keyed `'<effortId>-<set>-...'`, so an in-flight edit on the previous exercise is discarded the same way a set change discards it today. | `routine_setup_screen.dart:63-80`, `:1384` |
| D-7 | Tooltips stay `Previous Set` / `Next Set` (copy is a product matter, the tests find the arrows by them). Owner may want `Next` as on the live screen; flagged in the report. | live screen: `workout_session_detail_view.dart:663,681` |

## Scenarios

Fixtures are exact. `A` = the library resistance exercise helper `_resistanceExercise(repo)` (already in the test file),
`B`, `C` = two other exercises of the repo (`exercises[1]`, `exercises[2]` distinct from A by id). Targets are written with
the existing `_seedSets(routine, effortId, n)` (reps 10 per set, so the set count is `n`). Header subtitle strings are
`Exercise <i> / <n> · <block name>`. Detail is opened with the existing `_openDetail(tester, routine, exerciseName: ...)`.

| ID | Fixture | Expectation | Fails without the change because |
|---|---|---|---|
| S-4514 | One block `Main Block`; efforts `A` (2 sets), `B` (3 sets). Open detail on A, tap `Next Set` once (Set 2 of 2), tap `Next Set` again. | Header reads `Exercise 2 / 2 · Main Block`; the count line reads `Set 1 of 3`; `find.byKey(ValueKey('$bId-0-reps'))` is found and `ValueKey('$aId-1-reps')` is gone. | Next on the last set does nothing, so the screen stays on `Exercise 1 / 2`. |
| S-4515 | Same routine. Open detail on B (tap B in the list), at `Set 1 of 3` tap `Previous Set`. | Header `Exercise 1 / 2 · Main Block`; count line `Set 2 of 2` (A's LAST set, not set 1); `ValueKey('$aId-1-reps')` found. | Previous is disabled on set 1 and does nothing. |
| S-4516 | Same routine. (a) Open detail on A, set 1: Previous is dimmed (its `InkWell.onTap` is null) and tapping it leaves `Exercise 1 / 2`, `Set 1 of 2`. (b) Walk Next to B's set 3: Next is dimmed (`onTap` null) and tapping it leaves `Exercise 2 / 2`, `Set 3 of 3`. Each arm is its own test. | As stated. (Previous enabled on set 1 of exercise 2 is covered by S-4515; Next enabled on the last set of exercise 1 by S-4514.) | Honest note: the OLD code already passes both end checks (it dims at every last set). These two tests guard the new enable rule from being too wide: a rule that left Previous always enabled on set 1, or Next always enabled on the last set, would run off the ends. They are proven by mutation, not by failing on the old code. |
| S-4517 | Same routine. Walk Next from A set 1 through B set 3 and press Next two more times. | B's set bar keeps exactly 3 segments (`find.byType(SetSegmentBar)` still shows `count: 3`; read the widget's `count`), `routine.routineState.getEffortTargets(bId)` has sets 0..2 only, and A's targets still have sets 0..1 only. | A fix that added a set when Next ran off the end would grow B to 4. |
| S-4518 | Two blocks: `Block One` holds `A` (1 set); `Block Two` holds `B` (2 sets) and `C` (1 set), created with `routineState.addSegment(name: ...)` and `addExerciseToRoutine(exercise, 'set', segmentId: ...)`. (a) Open detail on A (`Exercise 1 / 3 · Block One`), tap Next: `Exercise 2 / 3 · Block Two`, `Set 1 of 2`; Next, Next: `Exercise 3 / 3 · Block Two`, `Set 1 of 1`; the single-set exercise's Next is dimmed. (b) Separate test: same two blocks, then `await routine.routineState.reorderSegments(1, 0)` BEFORE `_openDetail` (move Block Two to the top; `(0, 1)` would be a no-op because `reorderSegments` subtracts 1 when moving down) (Block Two is now first in the list: B, C, then A). Open detail on B: `Exercise 1 / 3 · Block Two`; Next on its last set, Next: `Exercise 2 / 3 · Block Two` (C), Next: `Exercise 3 / 3 · Block One` (A). | The detail walk visits the exercises in the order the list shows them, before and after the reorder. | The old arrows never leave an exercise, so the walk cannot reach the second block at all. |

The lead re-derives every number in this table with a throwaway script before the brief is written (set counts come from
`_seedSets`, `Exercise i / n` from the flattened order).

## Phases

| Phase | Agent | Items (max 8) | Write scope | Parallel |
|---|---|---|---|---|
| P1a | crew-builder-app | 1 `_buildSetControls`, `_previousSet`, `_nextSet` replaced by the exact text in the brief (D-1..D-4). No test, no doc. | `lib/features/routine/routine_setup_screen.dart` | serial, first |
| P1b | crew-builder-app | 1 new group `S-4514..S-4518` in `routine_detail_screen_test.dart` (helper block named in the brief; Mock only); 2 update the scenario map comment at the top of the file | `test/routine_detail_screen_test.dart` | after P1a |
| P2 | crew-docs-keeper | the Docs delta table below; evidence file | `docs/my_routines.md`, this plan's evidence file | after P1b |

Predicted production code: about 30 lines in one file. Plan budget respected (one track, 2 phases of code, under 200
lines of plan).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/my_routines.md` | MODIFIED | the Previous Set / Next Set arrow row is unchanged | Next on the last set opens the next exercise | S-4514 |
| `docs/my_routines.md` | ADDED | - | Previous on the first set opens the previous exercise on its last set | S-4515 |
| `docs/my_routines.md` | ADDED | - | dimmed on the last set of the last exercise | S-4516 |
| `docs/my_routines.md` | ADDED | - | never adds a set | S-4517 |
| `docs/my_routines.md` | ADDED | - | same order as the list | S-4518 |

Stale-term sweep run 2026-11-09: `grep -rIn "Previous Set\|Next Set\|set arrows\|arrow row\|S-4512" docs | grep -v "docs/plans\|docs/history\|docs/releases"`
returned only `docs/my_routines.md:383-385`. The S-4512 sentence's test name (`...stop at the ends`) stays true for a
one-exercise routine and keeps its name.

## Input-reality checklist

- Writers and units: no stored value is read beyond the template targets the screen already reads (`getEffortTargets`); set counts come from target rows (`_getSetCount`), written by the routine builder, the importer of a routine and the Mock/Hive repositories.
- Lifecycle: an exercise added, removed or reordered while the detail is open: `_removeExercise` already clamps `_currentExerciseIndex`; the new code reads `currentEfforts` fresh on each tap and guards the index. A routine with one exercise: both arms stay as today (S-4512).
- Settings changing while open: none read.
- Time edges: none.
- Load cost: one `getEffortTargets` read for the previous effort on a Previous tap; none on build beyond a `currentEfforts` length read.
- Wording: tooltips unchanged (D-7). Docs sentence in `docs/my_routines.md:383`.
- Slot competition: none.

## Progress

- [x] P1a production (builder run, 19 requests, diff identical to the brief)
- [x] P1b tests (builder run, 7 tests) + 1 lead-written test (Previous walk, closes mutants M8/M9)
- [x] P2 docs (`docs/my_routines.md` Set arrows paragraph; lead rewrapped two markers split across lines)
- [x] Verify: analyze 24 notices in the file before and after; `routine_detail_screen_test.dart` +25 green; ui standards + docs indexing contract tests green; invariant grep clean; plan-lint after clean
- [x] Prove: 10 mutants, 8 killed first time, M8 and M9 survived and were killed after the added test; original restored byte-identical (cmp)
- [x] Review: lead read the diff (no reviewer run: one file, 38 lines, exact brief text)
- [ ] Full suite green in one run: NOT achieved (see Assumption Log)

## Assumption Log

- Plan written by the lead without an architect run: the change is one screen and the seed carries exact code and fixtures.
- Scope guard applied by inspection (one file, ~30 lines of code, 2 code phases); the `pr-scope-guard` skill is not needed under the hard limits.
- Branch is `claude_develop`, not `develop` (the working branch of this series; the lead never switches branches).
- The shared tree has another session's crew runs live (plans 135/136 area); this plan's scopes do not overlap theirs, and the full suite is run only when no other builder run is live.
- Commits: not authorised for this unit; the owner commits.
- (owner) Device check: open a routine with two or more exercises, open the first exercise's detail, press Next past its last set (lands on exercise 2, set 1), press Previous on set 1 (back on exercise 1's last set); the arrows dim at the very first and very last set.
- Full suite (2026-11-09, shared tree, another session's tests running at the same time): run 1 `+7315 ~2 -1`, run 2 `+7303 ~2 -13`. Every failure was in `timer_digits_hours_test.dart` (S-4702, a real-clock header) or the `pre_release_gate_*` files (`PathNotFoundException` on their temp copy of the repo). Each of those files passes alone: timer digits `+7`, ios artifact `+12`, notification and build `+8`, upload destination `+8`. None touches the routine editor. A single clean full run is still owed once no other session is running tests.
- The Previous-walk test (`Previous walks back block by block, landing on last sets`) was written by the lead after the mutation pass showed that a two-exercise fixture cannot tell "previous exercise" from "first exercise" or "previous set count" from "current set count".
- Equivalent-by-design: `_previousSet`'s own index guard and `_nextSet`'s own end guard are unreachable while the arrows are dimmed (the dimming flag gates them). They are kept as defence in depth and are not separately tested.
