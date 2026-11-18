# Plan 227 — A skipped set counts for nothing

Series: Stats pre-launch review, owner rule 2026-11-17: "anything logged is logged and stays, anything not logged is ignored". A set marked skipped was not done. Phone only (`lib/core/services`, `lib/state/workout`), one builder run, then docs. Status: BUILT, mutation-checked (4 of 4 killed), docs applied; full suite pending.

## Goal and acceptance

A set carrying the skip marker (`markSetSkipped`: reps 0, `valueBool` true, the planned weight left in place) is kept in the stored workout but must read as nothing done everywhere a set is counted. Two places still count it: the Training Mix (`_hasSetEffort` only asks for a stored row, so a skip-only lift beside a run gives its leftover minutes to Resistance) and the post-workout summary (`setsCompleted` counts any entry with reps or weight above zero, so a skipped set with its planned weight is a completed set, and its weight can become the "best weight").

Acceptance: S-22701..S-22705 green, the ones marked "fails without" red at the base commit; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- A workout where a lift's only set was skipped no longer gives that lift's share of the time to Resistance in the Training Mix (a run + skipped lift reads Cardio 100, not Cardio + Resistance).
- The post-workout summary counts only sets done: one logged set and one skipped set read `1 set`, and a skipped set's planned weight is never the best weight.
- Nothing else changes: a skipped set is still shown in the session as skipped.
- To SEE it: log a 30 min run, add a lift, skip its only set, finish; open Stats and look at the Mix.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `_hasSetEffort` (`stats_progress_service.dart:1001`) returns true only when a set effort holds at least one entry that is not skip-marked: `EntryRows.setGroups(history.observationsOf(effort.id))` with a group whose `rowFor(MetricIds.reps)?.valueBool` is not true. (After Finish every remaining set row is a logged one or a skip-marked one: plan 157a drops the rest.) | `session_core_lifecycle.dart:141`, `entry_rows.dart:43` |
| D-2 | `_buildSummary` set loop (`session_summary_builder.dart:70`) skips an entry whose `entry['skipped'] == true` before it feeds volume, best weight, e1RM, best reps and `setsCompleted`. | `session_summary_builder.dart:71-117`, `entry_rows.dart:38-43` |
| D-3 | The skip row stays stored; no Finish or import path changes. Plan 157a's "kept, counts for nothing" is now true everywhere. | `session_core_lifecycle.dart:105` |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22701 | Mock service. A session with a finished round (copy the fixture of `test/mix_session_with_nothing_done_test.dart` S-22403 second test) plus a lift whose only set is `markSetSkipped`; ended. | `sessionTimeBySectionFor` has Sports only (the whole duration) and no Resistance. | the skip row makes `_hasSetEffort` true, so the remainder goes to Resistance |
| S-22702 | A session whose only exercise is a lift with one skip-marked set; ended with a ~1.1 s real wait. | `sessionTimeBySectionFor` is empty. | base returns `{resistance: ~1.0}` (measured by probe) |
| S-22703 | A lift with one logged set (reps 5, weight 100, rest at 1) AND one skip-marked set; ended with a wait. | `sessionTimeBySectionFor` has Resistance. | passes both ways on purpose (mutation: skip-marked sets disqualify the effort whenever any exists) |
| S-22704 | Summary builder. A lift with a logged set (reps 5, weight 100) and a second set weight 120 then `markSetSkipped`. | the exercise summary `setsCompleted` 1, session `totalSets` 1. | base counts both (reps 0 but weight 120 > 0): 2 |
| S-22705 | Same fixture. | the exercise's best weight 100 and best e1RM from the 100 kg set only. | base best weight is 120 |

## Input-reality checklist

1. Writers and units: no new writer; reads stored rows. Weight units follow settings; not touched.
2. Lifecycle: a skip-marked set on a still-open session is not in history yet (the Mix reads ended sessions); the summary builder reads the live caches, so the skip must be excluded there too (D-2).
3. Settings changing while open: none.
4. Time: none.
5. Load cost: `EntryRows.setGroups` per set effort in a loop already iterating observations: same order of cost.
6. Words: none.
7. Slot competition: none.

## Phases

1. **P1 builder-app**, scope `lib/core/services/stats_progress_service.dart`, `lib/state/workout/session_summary_builder.dart`, `test/skipped_set_counts_for_nothing_test.dart` (new). No full suite.
2. **P2 lead**: docs (`docs/training_load.md`, the session summary doc), mutation pass, full suite.

## Readers

`grep -rln "markSetSkipped\|skipped" test` and the Mix and summary tests (`mix_*`, `session_summary*`, `stats_progress_service*`). A reader that pins a skipped set as counted is reported, not edited.

## Mutation list (lead)

(a) `_hasSetEffort` back to "any stored row"; (b) `_hasSetEffort` returns false when any skip-marked set exists; (c) summary skip removed; (d) summary skips only the count but not best weight.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/training_load.md` | MODIFIED | `holds a set effort with a stored row` | `with a stored set that was not skipped` | S-22701, S-22702 |
| `docs/training_load.md` | MODIFIED | `holds efforts but no set with a stored row` | `no set that was done` | S-22702 |
| `docs/session_summary.md` | ADDED | - | A set marked skipped was not done | S-22704 |

Stale-term sweep: `grep -rIn "stored row" docs` outside plans/history/releases; each hit is a row.

## Open items

1. The watch-linked workout with nothing logged is plan 228.
2. A bodyweight-only day on a weight-axis lift is plan 157b D-4's rule (noise on the load axis); recommended as is, owner to confirm.

## Predicted files

`stats_progress_service.dart` (+10), `session_summary_builder.dart` (+4), one new test file, two docs.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass
- [x] Full suite (+7866 ~4 green, analyze 181)

## Assumption Log

- 2026-11-17: base commit in `.work/crew/2026-11-17-227/base.txt`; other sessions' files (plans 223/225/208, watch Swift, gallery test) are outside this plan.
- 2026-11-17: ids S-227xx: none found in `test/`, `docs/`.

## Feedback

(none yet)
