# Plan 266 — A failed save says so

Review item 36 (owner list: "Saves that report success when storage fails: routine ('saved successfully'), daily target (silent), period (Save stays disabled). Suggested: on a failed save, stay on the screen, show 'Could not save. Try again.' and re-enable Save.").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

When the storage write fails, the routine editor, the Daily Targets form and the training period form each stay open with the user's input intact, show `Could not save. Try again.`, and leave Save usable. The routine form no longer says "Routine saved successfully", the target form no longer closes and its failed write no longer blanks the target on screen, and the period form's Save no longer stays disabled.

Acceptance: S-26601..S-26603 green and red without the change; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26601 | `RoutineState.saveRoutine`, `NutritionState.saveNutritionTarget(ForDate)` return `Future<bool>`; false on a failed write. A failed target write keeps the previous target (it used to set it to null). | state files |
| D-26602 | `PeriodState.createPeriod`/`updatePeriod` catch a failed write and return false (validation still returns false first); the form shows the message and clears `_isSaving`. | `period_state.dart`, `create_period_screen.dart` |
| D-26603 | The three screens show `OmniMessage.error(context, 'Could not save. Try again.')` and return without popping. | screens |

## Scenarios

S-26601 routine with an exercise, `createTemplate` throws: message, still on screen, nothing stored, then a retry saves and closes. S-26602 target 2000 stored, `saveNutritionTargetForDate` throws on a new 2500: message, still on screen, `nutritionTarget` still 2000, then a retry saves 2500. S-26603 period edit, `updatePeriod` throws: message, Save enabled, retry closes.

## Input-reality checklist

1. Writers: the three saves only. 2. Lifecycle: the unsaved-changes dialog's Save uses the same path. 3. Settings: none. 4. Time: none. 5. Cost: none. 6. Words: `Could not save. Try again.` (owner's wording). 7. Competition: the error message covers the bottom Save for a few seconds (as other messages do).

## Docs delta

`docs/global_conventions.md`: one rule row.

## Open items

1. (owner) Other saves (exercise editor, profile, measurements, food form) were not part of this item and were not checked.
