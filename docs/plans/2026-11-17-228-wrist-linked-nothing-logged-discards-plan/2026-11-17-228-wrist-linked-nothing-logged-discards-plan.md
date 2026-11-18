# Plan 228 — A watch-linked workout with nothing logged is discarded too

Series: Stats pre-launch review, owner rule 2026-11-17: "anything not logged is ignored". Plan 220 made Finish on a nothing-logged workout ask `Discard Workout?` and discard, but left out any workout the watch took part in. Phone only (`lib/state/workout`), one builder run, then docs. Status: BUILT, mutation-checked (12 mutants killed; four activity kinds needed an extra test), docs applied; full suite pending.

## Goal and acceptance

Finish on a workout the watch is running, when nothing was logged on the phone or the wrist, asks `Discard Workout?` and discards it, exactly like a phone-only workout. Today `finishWouldSaveNothing` (`session_core_lifecycle.dart:216`) answers false whenever the wrist runs the session or any wrist row is staged, so the workout is saved empty and counts in the totals and Consistency.

Acceptance: S-22801..S-22806 green, the ones marked "fails without" red at the base commit; readers green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Start a workout on the wrist, log nothing, press Finish on the phone: `Discard Workout?` (nothing was logged, it won't be saved), Cancel or Discard. Discard removes it, the same as the Discard button in the header does today for a wrist workout.
- Wrist sets already logged (even not yet shown on the phone) keep the normal `Finish Workout?` dialog: the phone first lets the watch's pending sets land, then decides.
- Phone-only workouts: unchanged.
- To SEE it: with the watch paired, start a workout on the wrist, add an exercise, log nothing, press Finish on the phone.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `finishWouldSaveNothing` decides behind the inbox's queued import passes: it runs its check inside `_afterPendingWristImports` when the seam is set (the same seam `endSession` uses, plan 218), so a wrist set whose row is written before its rest is read after both. The result is carried out of the callback in a local. | `session_core_lifecycle.dart:11-43`, `workout_state.dart:66-70` |
| D-2 | The `_wristRunsSession` clause is removed: a wrist that runs the session and has logged nothing is not a reason to save it. | `session_core_lifecycle.dart:220` |
| D-3 | The staged-row check counts only wrist ACTIVITY rows: `kindSet`, `kindTimed`, `kindRound`, `kindHold` (origin watch). A staged `rest`, `effort_rating` or `session_end` row alone is not work. | `models.dart:2818-2840` |
| D-4 | The discard path is the existing one (`discardCurrentSession`): the importer already consumes rows that name a deleted session and never recreates it (D-136, D-14), and the wrist is told by the same path the header Discard button uses. A wrist set that arrives after a discard is dropped; accepted (the wrist logged nothing when the user pressed Finish). | `watch_session_importer.dart:224-233,314-317` |
| D-5 | The dialog (`workout_session_finish.dart:10-45`) does not change. | plan 220 |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22801 | State test, both harnesses: `wristRunsSession` returns true, one lift added, nothing logged, no staged row. | `finishWouldSaveNothing()` true. | the base answers false for a wrist-run session |
| S-22802 | Same, with a staged watch `set` row for the session. | false. | passes both ways on purpose (mutation: the staged check removed) |
| S-22803 | Same as S-22801 but a staged watch `session_end` row and an `effort_rating` row only. | true. | the base answers false for any staged watch row |
| S-22804 | `afterPendingWristImports` seam stub that first writes a logged set (values + a rest at position + 1 through the state, as the importer does) and then runs the action; the wrist runs the session. | false (the set landed before the decision). | a decision taken before the queue reads true (mutation: the check bypasses the seam) |
| S-22805 | Wrist runs the session and one lift has a logged set (rest at 1). | false. | passes both ways on purpose (mutation: always true) |
| S-22806 | Screen test, Mock only: `WorkoutSessionScreen` over a wrist-run session with a lift and nothing logged; tap Finish Workout. | `Discard Workout?` is shown (key `session-finish-nothing-confirm` found), confirming removes the session and pops. | the base shows `Finish Workout?` |

## Input-reality checklist

1. Writers and units: the wrist writes set rows then rests through the importer (plan 218); D-1 reads after the queue. No new writer.
2. Lifecycle: the decision runs once per Finish tap; Cancel leaves the workout live and the wrist running. A wrist set arriving between the dialog opening and Discard is lost (D-4).
3. Settings: none.
4. Time: none.
5. Load cost: one extra read of staged rows (already read today).
6. Words: unchanged.
7. Slot competition: none.

## Phases

1. **P1 builder-app**, scope `lib/state/workout/session_core_lifecycle.dart`, `test/finish_nothing_logged_discards_test.dart` (extend S-22001), `test/finish_wrist_nothing_logged_discards_test.dart` (new, S-22801..S-22806). No full suite.
2. **P2 lead**: docs, mutation pass, full suite.

## Readers

`grep -rln "finishWouldSaveNothing\|wristRunsSession" test`: plan 220's tests and the wrist-linked finish tests (`wrist_linked_finish_drops_planned_sets_test`, `wrist_linked_end_late_sets_test`, `watch_session_*`). A reader that pins "a wrist workout is never discarded" is reported, not edited.

## Mutation list (lead)

(a) wrist clause back; (b) staged check back to any watch row; (c) staged check removed; (d) decision bypasses the queue; (e) always false; (f) always true.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/session_summary.md` | MODIFIED | `and no watch involvement asks` | `a workout the watch runs with nothing logged is discarded the same way` | S-22801, S-22804 |
| `docs/modality_based_exercise_ui.md` | MODIFIED | `instead of being finished (plan 220; see` | `a workout the watch runs included` | S-22806 |
| `docs/watch_session_sync.md` | ADDED | - | `Finish on a workout with nothing logged discards it, the watch's workout` | S-22804 |

Stale-term sweep: `grep -rIn "never discarded\|took part in\|Discard Workout" docs` outside plans/history/releases; each hit is a row.

## Open items

1. (owner) With a paired watch: start on the wrist, log nothing, Finish on the phone: `Discard Workout?`; and a wrist set logged just before Finish still keeps the normal dialog.
2. A wrist set that arrives after the discard is dropped (D-4).

## Predicted files

`session_core_lifecycle.dart` (+15), two test files, two to three docs.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass
- [x] Full suite (+7866 ~4 green, analyze 181)

## Assumption Log

- 2026-11-17: base commit recorded when the build starts; other sessions' files (plans 223/225/208, watch Swift, gallery test) are outside this plan.
- 2026-11-17: ids S-228xx: none found yet (grep before building).

## Feedback

(none yet)
