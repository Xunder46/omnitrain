# 29 · Warn before losing typed work; confirm every delete

Status 2026-10-13: Built, proved, reviewed with 27 and 28; New Food photo now counts as unsaved work. Final: flutter test +4467 ~1, analyze 181.

Parent: `docs/plans/2026-10-12-25-ui-standards-refresh-plan/` (owner decisions D3 = A and D4 = A, 2026-10-13). Starts after plan 28 is verified.
Sources: survey sheets s7 N2, s8 F9-F10, s6 F10.

## Goal and acceptance

What the user sees afterwards:

1. Leaving **New Period / Edit Period**, **Daily Calorie Target**, **New Food** and the legacy library edit screen with typed or changed
   values asks "Unsaved changes" (Keep editing / Discard / Save) through the same dialog the routine editor uses. Leaving without
   changes just leaves. Edit Food keeps auto-saving (named exception).
2. Removing a catalog food from your library (trash on a Library tab row) asks first, with the shared destructive dialog; confirming
   removes it and today's log of it as before; cancelling leaves everything.
3. Deleting an empty category asks first with the shared dialog. A non-empty category keeps its own dialog (it needs a destination
   picker); its two buttons get the standard shape. The info-only "Cannot Delete" dialog is unchanged.

Out of scope: routine editor and Edit Session (already guarded); live session (nothing unsaved by design).

## Decision Ledger

| Id | Decision |
|----|----------|
| D-29.1 | Use `ConfirmationDialog.showUnsavedChanges` (`lib/widgets/dialogs/confirmation_dialog.dart:59`) from a `PopScope(canPop: !dirty, onPopInvokedWithResult: ...)` in each screen, exactly like `routine_setup_screen.dart:144-151` and its `_attemptExit` (`:1010-1050`). Copy the pattern; do not invent a new one. "Save" runs the screen's existing save path and pops only on success. |
| D-29.2 | "Dirty" = any controller text differs from its initial value (or, for create screens, any field non-empty/non-default). Compute from the controllers/state the screen already has; no new state classes. The header back button and the system back both go through the same guard. |
| D-29.3 | Delete confirms use `ConfirmationDialog.twoChoice` / `showTwoChoice` with `isDestructive: true` and copy "Remove <name> from your library?" / "Delete category <name>?"; keys `food-remove-cancel`/`food-remove-confirm` and `category-delete-cancel`/`category-delete-confirm`. |
| D-29.4 | `_DeleteGroupDialog` stays bespoke (destination dropdown) but its buttons get the D-26.2 shape. |

## Scenarios (red at base)

- S-2901 CreatePeriodScreen: type a name, system back: dialog "Unsaved changes" found. Keep editing stays on screen; Discard pops and nothing is saved;
  Save with a valid form saves and pops. Untouched form: back pops with no dialog. Red at base: no dialog.
- S-2902 Same four behaviours for NutritionTargetScreen (changed calories field vs initial), `_NewFoodFormScreen` (any field typed),
  `_LegacyLibraryEditScreen` (any changed field).
- S-2903 Library tab, trash on a catalog food: dialog found; cancel leaves the food in the library; confirm removes it and today's log entry.
  Red at base: removed with no dialog.
- S-2904 Empty category delete: dialog found; cancel keeps the category; confirm removes it. Non-empty keeps `_DeleteGroupDialog`.

## Phases (serial)

| Phase | Scope | Items |
|-------|-------|-------|
| 1 | `lib/features/period/**`, `lib/features/nutrition/nutrition_target_screen.dart`, `test/**` | S-2901 and the target screen part of S-2902 |
| 2 | `lib/features/nutrition/add_food_screen.dart`, `test/**` | New Food and legacy edit guards; S-2903; S-2904; dialog shape |
| 3 | prover, reviewer, governor verify | |

Predicted production diff about 220 lines in 3 files. Existing tests that back out of these screens with typed values may now meet the
dialog: builders list them first and update only those.
