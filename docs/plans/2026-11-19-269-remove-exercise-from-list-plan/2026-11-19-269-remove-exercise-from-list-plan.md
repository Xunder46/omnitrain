# Plan 269 — Remove a whole exercise from the live list

Review item 38, first part (owner list: "Live session: no reorder; an exercise is removed only by deleting its sets. ... Suggested: add drag-to-reorder and a 'Remove exercise' action on the live list, and allow dragging between blocks in the editor."). This plan is the Remove action only; reorder (plan 270) and the editor's drag between blocks (plan 271) are separate.
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

Each exercise tile on the live workout list (and in Edit Session, and inside blocks) has a `⋮` menu with `Remove exercise`. It asks `Remove Exercise?` (Cancel / Remove). Remove takes the whole exercise and everything logged for it out of the workout, stops its timers, cancels a running rest's pings, and reloads the list. Cancel keeps everything.

Acceptance: S-26901, S-26902 green and red without the change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26901 | Reuse `WorkoutState.removeExerciseFromSession` and the clean-up of the existing delete-the-last-set path (in-progress keys, logged keys, edit buffer, open-rest pings, reload). | `workout_session_screen.dart` last-entry delete |
| D-26902 | New `_dropTimerStateForEffort(effortId)` stops every ticker and forgets every per-entry key of the effort (timers, elapsed, alerts, targets, pending transitions). | `workout_session_timer_mixin.dart` |
| D-26903 | In Edit Session the removal marks the screen as structurally changed, so Back still asks and restores the snapshot like any other structural edit. | `_hasStructuralChanges` |

## Scenarios

S-26901 open the tile menu, Remove exercise: the dialog shows; Cancel keeps the exercise and its sets. S-26902 confirm: the exercise leaves the list, its efforts and observations are gone, the other exercise stays.

## Input-reality checklist

1. Writers: `removeExerciseFromSession` (cascades rests). 2. Lifecycle: a wrist-linked session behaves as the existing last-set removal does. 3. Settings: none. 4. Time: a running timer on the exercise stops. 5. Cost: none. 6. Words: `Exercise options`, `Remove exercise`, `Remove Exercise?` (owner to read). 7. Competition: a watch set arriving for a removed exercise follows the existing late-entry rules.

## Docs delta

`docs/modality_based_exercise_ui.md`: one bullet in the List View section.

## Open items

1. (owner) Reorder (plan 270) and the editor's drag between blocks (plan 271) are next.
