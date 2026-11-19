# Plan 232 — Saving an edited workout never turns unstarted rounds into done ones

Series: nutrition/calendar/summary pre-launch review (2026-11-16, third pass), proven item "Edit Session Save Changes marks every never-started round finished and completed at its planned length (1 round/180 s became 3 rounds/540 s with nothing edited)". Owner rule 2026-11-17: what was not logged is ignored, what was logged stays. Phone only (`lib/state/workout/timer_manager.dart`), one builder run, then docs. Status: COMMITTED (built, mutation-checked (4 of 4 killed), docs applied; full suite pending.

## Goal and acceptance

Edit Session's Save runs `normalizeAllRoundsToFinished` (`timer_manager.dart:1657`), which turns EVERY round that is not finished into a finished one at its planned duration. Finish keeps never-started rounds in a workout (they count for nothing), so saving an edit of a note or a rep count invents rounds and minutes that were never done: they show in the summary, the Training Mix and Stats. After this change only rounds that were really started (running or paused) are finished by Save; a round that was never started stays never started.

Acceptance: S-23201..S-23204 green, those marked "fails without" red at the base commit; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Open a finished workout that has rounds nobody started, change anything (a note, a rep), Save: the rounds stay unstarted; the summary's round count and total time do not grow.
- A round that was running or paused when the workout ended is still finished at its planned length on Save, as today.
- To SEE it: finish a workout with a 3-round exercise where you only ran 1 round, open it from the calendar, Edit, change a note, Save; the summary still says 1 round.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `normalizeAllRoundsToFinished` skips a round whose `state == RoundState.notStarted`; `active` and `paused` rounds are still finished at `plannedDurationSecs` (the method's stated purpose: a historical session never keeps a running or paused round). | `timer_manager.dart:1657-1671`, `models.dart:1077` |
| D-2 | The doc comments of `normalizeAllRoundsToFinished`, `WorkoutState.normalizeRoundsToFinished` and the Save step 2 comment (`workout_session_edit_mode.dart:216-218`) say "started" rounds. The edit-mode file's step 2 comment was reworded by the lead after the run (out of the builder's scope). | same |
| D-3 | Timed/drill entries are not touched (the review proved rounds only). | review memory |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-23201 | State test, both harnesses. A finished session with a round exercise of three planned rounds: round 0 finished (e.g. 60 s), rounds 1 and 2 never started. `normalizeRoundsToFinished()`. | rounds 1 and 2 are still `notStarted`; round 0 unchanged. | the base finishes them at the planned duration |
| S-23202 | A round `active` (started) and one `paused`; normalize. | both `finished` at `plannedDurationSecs`. | passes both ways on purpose (mutation: skip every non-finished round) |
| S-23203 | The same fixture; session summary before and after `normalizeRoundsToFinished()`. | the round count and total round time are equal before and after. | the base's summary grows by the invented rounds |
| S-23204 | Reload from the store (a fresh state `loadHistoricalSession`) after normalize. | the unstarted rounds are still `notStarted` in the store (the change is persisted, not only in memory). | the base persists them finished |

## Input-reality checklist

1. Writers and units: only the Save path calls it (`workout_session_edit_mode.dart:219`, plus two tests). Round durations in seconds.
2. Lifecycle: Finish already leaves never-started rounds in place; `persistActiveRounds` stores the running ones before the end, so they are `active`/`paused` at the edit.
3. Settings: none.
4. Time: none.
5. Cost: none.
6. Words: none.
7. Slot competition: none.

## Phases

1. **P1 builder-app**, scope `lib/state/workout/timer_manager.dart`, `lib/state/workout/workout_state.dart` (comment only), `test/edit_save_keeps_unstarted_rounds_test.dart` (new). No full suite.
2. **P2 lead**: docs, mutation pass, full suite.

## Readers

`test/watch_session_edit_restore_late_entry_test.dart` (~715) and `test/watch_session_edit_restore_summaries_test.dart` (~414, ~450) call `normalizeRoundsToFinished`; `grep -rln "setRoundFinished\|normalizeAllRoundsToFinished\|RoundState.notStarted" test`. A reader that pins unstarted rounds finished after Save is reported, not edited.

## Mutation list (lead)

(a) the `notStarted` skip removed; (b) every non-finished round skipped (S-23202); (c) only `active` finished, `paused` skipped.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/session_summary.md` | ADDED | - | a round that was never started stays never started | S-23201, S-23203 |

Stale-term sweep: `grep -rIn "normalizeRoundsToFinished\|Save Changes" docs` outside plans/history/releases found nothing to change.

## Open items

1. (owner) Finish a workout with an unrun round, edit and save: the summary round count does not grow.

## Predicted files

`timer_manager.dart` (+6), `workout_state.dart` (comment), one new test file, one doc.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass
- [x] Full suite (+7910 ~4 green, analyze 181)

## Assumption Log

- 2026-11-17: base commit in `.work/crew/2026-11-17-232/base.txt`; other sessions' files are outside this plan.
- 2026-11-17: ids S-232xx: none found.

## Feedback

(none yet)
