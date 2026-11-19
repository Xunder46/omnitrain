# Plan 224 — A session with nothing done adds nothing to the Training Mix

Series: second Stats review (Fable, 2026-11-17) open item 2, second half, after plans 179 and 221. Phone only (`lib/core`), one builder run, then docs. Status: BUILT, reviewed (APPROVE WITH FIXES, fixed), verified, COMMITTED.

## Goal and acceptance

The Training Mix gives a session's whole length to Resistance when nothing in it was measured. Probed on the current code: a workout whose only exercise is a never-started round, a never-started run, or a lift with nothing logged each contributes its full length to Resistance, so bag work never started reads Resistance 100%. Plan 179 already made a no-sets session with some measured time share its length across what it measured; this closes the remaining case. After this change a session with no set that holds anything and no measured time contributes no time to the Mix.

Acceptance: S-22401..S-22404 green, the ones marked "fails without" red at the base commit; the Mix readers (`training_load_test`, `mix_layer_*`, `stats_mix_*`, `signals_*` that seed sessions) green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- A workout where nothing was done (a never-started run or bag round, or a lift emptied of its sets) no longer shows up as Resistance time on the Mix bar. If it was the only workout in the window the Mix shows its "no time yet" state for the window. The workout still counts as a session in the totals.
- Everything with real work in it reads as before: a logged set, a finished timed or round interval.
- To SEE it: add a run to a workout, never start it, finish (the app asks to discard when nothing at all is logged, so add a lift with one logged set too, then look at the bar: Resistance only for that lift's session share).

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `sessionTimeByModality` (`lib/core/models/training_load.dart:205`) gets `bool hasEfforts = false`; after the plan-179 branch, `if (!hasSets && hasEfforts) return const {};` i.e. a non-rolling session that holds efforts but no set with a row and no measured time contributes nothing (a rolling session returns earlier, unchanged). A session with NO effort at all keeps the old remainder rule: the app never stores one (an empty workout is discarded), but ~100 existing fixtures seed rated sessions without efforts and pin that figure (found by the builder's first run). | `training_load.dart:216-234` |
| D-2 | The service passes `hasEfforts: _hasAnyEffort(history, session)` (a new private helper: any effort of any kind on the session). `_hasSetEffort` (`stats_progress_service.dart:~999`) counts a set effort only when it holds at least one stored row (`history.observationsOf(effort.id).isNotEmpty`): a lift emptied by the end of a watch-linked workout (plan 218) is not "has sets". | `stats_progress_service.dart:999-1008` |
| D-3 | The session still counts in `windowSessionCount` and the all-time totals (the split only decides Mix time). | `stats_progress_service.dart:795-806` |
| D-4 | Wording unchanged. | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22401 | Pure: `sessionTimeByModality(durationSecs: 2400, isRolling: false, measuredSecs: {}, dominantSection: ExerciseSection.sports, hasSets: false, hasEfforts: true)`. | empty map. | the base returns `{resistance: 2400}` |
| S-22402 | Pure neighbours: `hasSets: true` and no measured time → `{resistance: 2400}`; `hasSets: false` with `{cardio: 600}` → `{cardio: 2400}` (plan 179); rolling with no measured → empty (unchanged); `hasSets: false, hasEfforts: false`, no measured → `{resistance: 2400}` (the old rule, `mix_no_sets_pure_test` S-20006). | as listed. | passes with and without the change on purpose: pins the neighbouring rules (mutation: the new branch ignores `hasSets`) |
| S-22403 | Service (Mock): a completed session whose only exercise is a never-started round (the probe fixture: `createNewSession(modality: 'sports')`, `addExerciseToSession(effortKindOverride: 'round')`, a 1.1 s wait, `endSession`). `sessionTimeBySectionFor(id)`. Then a session with a finished round instance. | empty; the second gives `sports` the whole duration. | the base gives Resistance the whole duration to the first |
| S-22404 | Service (Mock): a lift with nothing typed, ended with `endSession(writeToHealth: false)` → empty; a lift with one logged set (100 x 3, rest at 1), `endSession()` → `resistance` only. | as listed. | the base gives the emptied lift Resistance time (D-2) |

## Input-reality checklist

1. Writers and units: none; a read-side rule, durations in seconds as today.
2. Lifecycle: applies on every load.
3. Settings: none.
4. Time: a session with a zero duration already contributed nothing.
5. Cost: one `isNotEmpty` per set effort.
6. Words: none.
7. Readers: every reader of `sessionTimeByModality`/`sessionTimeBySectionFor`/`computeMixLayer` (the energy estimate for Free Training, signals that read Mix time, the strip).

## Phases

1. **P1 builder-app**, scope `lib/core/models/training_load.dart`, `lib/core/services/stats_progress_service.dart`, `test/mix_session_with_nothing_done_test.dart` (new): the exact code in the brief and S-22401..S-22404. No full suite.
2. **P2 lead**: docs, mutation pass, review, full suite.

## Readers

`test/training_load_test.dart`, `test/stats_mix_*`, `test/mix_layer_*`, `test/signals_*` tests that seed a session with a set effort and no observations, `test/active_energy_*` (the Free Training estimate reads `sessionTimeBySectionFor`). A test whose fixture is a set effort with no stored rows and expects Resistance time is reported (file, name), not edited.

## Mutation list (lead)

(a) the new branch is removed; (b) the new branch ignores `hasSets`; (e) the new branch ignores `hasEfforts`; (c) `_hasSetEffort` counts an effort with no rows; (d) the new branch also empties a rolling session.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/training_load.md` | MODIFIED | A session with no measured time is unchanged. | A session that holds efforts but no set with a stored row | S-22401, S-22403 |

Stale-term sweep (`grep -rIn "no measured time\|remainder" docs`): `training_load.md:65-72`.

## Open items

1. (owner) Device check: a workout of only a never-started round, then the Mix bar.
2. A watch-linked workout with nothing logged still counts as a completed workout in the totals (plan 220 open item 2).

3. (review) Skip-marked-only sets still count as sets for the Mix (the skip marker is a stored reps row): same as before this plan; owner may want them to count as nothing (same question as plan 220 open item 3).
4. (review, wording) A window whose only session is nothing-done shows NO Mix card (the payload is null when the window holds a session with zero time), not an empty-state line; the device check should look for an absent card.

## Predicted files

`training_load.dart` (+4), `stats_progress_service.dart` (+3), one new test file, one doc.

## Progress

- [x] Seeded and probed (all three cases give Resistance 1.0 on a 1 s workout)
- [x] P1 build + fix 1 (narrower rule after ~100 fixtures with no efforts went red)
- [x] Docs, mutation pass (5 mutants killed), review (1 major doc bullet, fixed)

## Assumption Log

- 2026-11-17: base commit `9e1e5a65` on `claude_develop`; other sessions' files (plan 223, watch Swift, plan 208, gallery test) are outside this plan.
- 2026-11-17: scenario ids S-224xx: none found. The rule (nothing done adds nothing) follows the owner's plan 179 choice, "share by what you did".

## Feedback

- 2026-11-17: the first build (nothing done = no efforts or only empty ones) turned ~100 older fixtures red (rated sessions seeded without any effort); the rule was narrowed to sessions that hold efforts (`hasEfforts`).
