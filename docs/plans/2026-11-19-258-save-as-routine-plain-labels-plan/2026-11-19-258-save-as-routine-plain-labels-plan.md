# Plan 258 — Save as Routine uses plain labels and keeps you on the summary

Review item 29 (owner list: "Summary: Save as Routine shows 'set / timed / drill' and closes the summary. Suggested: show the plain labels the routine editor uses ('Reps & Sets', 'Time', 'Hold Time', 'Rounds') and stay on the summary after saving.").
Phone only. No wire, watch, storage or schema change.

## Goal and acceptance

In the workout summary's overflow menu, **Save as Routine** opens a sheet that lists the exercises.

- Each exercise line's second row reads the plain label of how it is tracked, not the stored word: `Reps & Sets` (was `set`), `Time` (was `timed`), `Hold Time` (was `drill`), `Rounds` (was `round`).
- Tapping **Save** saves the routine, closes the sheet, shows `Routine saved` and STAYS on the summary. Before this change Save also finished the workout and closed the summary (as if Done had been tapped). Done still finishes the workout and closes the summary as before.

Acceptance: S-25801..S-25804 green, the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set; Docs delta applied.

## What the user sees

- Finish a workout, open the overflow menu, Save as Routine: the exercises read `Reps & Sets` / `Hold Time`... Tap Save: a `Routine saved` message and the summary is still there; tap Done to leave.
- To SEE it: finish any workout and open Save as Routine from the summary.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25801 | `ModalityDisplay.effortKindLabel(String effortKind)`: `set` -> `Reps & Sets`, `timed` -> `Time`, `drill` -> `Hold Time`, `round` -> `Rounds`, anything else the raw string. | `modality_display.dart`, `routine_setup_screen.dart:1218` (the editor's `Track by ...` wording) |
| D-25802 | The Save-as-Routine sheet's exercise subtitle shows `ModalityDisplay.effortKindLabel(exercise.effortKind)`. | `session_summary_screen.dart:649` |
| D-25803 | The sheet's Save handler keeps its order (save the routine, reload routines, `if (!mounted) return`, close the sheet) and then shows `OmniMessage.show(this.context, 'Routine saved')` instead of calling `_finishAndSaveSession()`. Done (`_finishAndSaveSession`) is unchanged. | `session_summary_screen.dart:680-698,794` |

## Scenarios

Fixtures. The summary screen pump of `test/capitalization_defaults_test.dart` (the test at line ~267 opens the overflow menu and taps `Save as Routine`: copy its pump and routine/state setup) with a finished workout holding a set exercise, plus a hold exercise (`effortKindOverride: 'drill'`), an interval (`'timed'`) and a round exercise (`'round'`) so every kind appears; Mock repository.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25801 | open Save as Routine | the four exercise lines read `Reps & Sets`, `Hold Time`, `Time`, `Rounds`; none reads `set`, `drill`, `timed` or `round` | raw kinds shown |
| S-25802 | `ModalityDisplay.effortKindLabel` for the four kinds and an unknown kind | the four labels; the unknown kind comes back unchanged | no helper |
| S-25803 | tap Save with a name | `routineState.routines` holds a routine with that name; `Routine saved` is shown; the sheet is closed; the summary screen is still on screen (`find.byType(SessionSummaryScreen)`) and `find.text('Done')` is found | Save also finished the workout and closed the summary |
| S-25804 | after S-25803 tap Done | the workout is finished and the summary is gone (the screen pops to the first route) | control: Done still finishes |

## Input-reality checklist

1. Writers: routines are written by `saveRoutineFromDraft` (unchanged). Units: none.
2. Lifecycle: saving twice from the same summary makes two routines (as before: not changed).
3. Settings: none.
4. Time: none.
5. Cost: none.
6. Words: new copy `Routine saved`; the four labels (owner to read).
7. Competition: the note field's pending write and Done: unchanged (`_flushNote` runs in Done).

## Phases

1. **P1 builder-app**, scope `lib/core/constants/modality_display.dart`, `lib/features/session/session_summary_screen.dart`: D-25801..D-25803 (exact code in the brief). No full suite.
2. **P2 builder-app** (after P1), scope `test/save_as_routine_labels_test.dart` (new): S-25801..S-25804.
3. **P3 lead**: readers (`capitalization_defaults_test`, `header_standardization_test`, summary tests), full suite, analyze, mutation pass, docs, reviewer.

## Mutation list (lead)

(a) the raw kind shown (S-25801); (b) one label wrong (S-25801/S-25802); (c) Save still calls `_finishAndSaveSession` (S-25803); (d) no `Routine saved` message (S-25803); (e) Done no longer finishes (S-25804); (f) the unknown kind mapped to a label (S-25802).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/session_summary.md` | MODIFIED | additions and removals — before it is persisted through `saveRoutineFromDraft`. | additions and removals — before it is persisted through `saveRoutineFromDraft`. Each exercise line names how it is tracked in plain words (`Reps & Sets`, `Time`, `Hold Time`, `Rounds`), and Save keeps the summary open with a `Routine saved` message (plan 258, `test/save_as_routine_labels_test.dart`). | S-25801, S-25803 |

## Open items

1. (owner) Save as Routine no longer finishes the workout: tap Done afterwards (the summary stays so the note and rating can still be set).
