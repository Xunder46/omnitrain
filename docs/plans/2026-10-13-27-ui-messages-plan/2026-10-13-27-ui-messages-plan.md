# 27 · One look for messages, plain wording, honest load failures

Status 2026-10-13: Built, proved (mutations by the governor), reviewed together with 28 and 29; fixes done (exercise editor copy, profile and session load failure text). Final: flutter test +4467 ~1, analyze 181.

Parent: `docs/plans/2026-10-12-25-ui-standards-refresh-plan/` (owner decision D1 = A, 2026-10-13). Starts after plan 26 is verified.
Sources: survey sheets s2 F5, s3 section 4, s7 I1, s8 F11, s9 F5-F6.

## Goal and acceptance

What the user sees afterwards:

1. Every small pop-up message at the bottom of a screen (46 places in 16 files) looks the same: theme surface colour, theme text
   colour, the same corner shape as dialog buttons, same duration. Placement is unchanged (default bottom bar).
2. A failed action says what failed and what to do, never the technical error text. 13 places print `$e` today ("Failed to save
   entry: Exception: ..."). Afterwards: "Could not save the entry. Try again."
3. If Stats, Records & Trends or Exercise Progress fail to load, the screen says "Could not load your stats. Try again." with a
   "Try again" button that reloads; today it looks like "no data".
4. The PR celebration toast is unchanged (it keeps its own look; named exception).
5. `flutter test` green; analyze not above 195 issues.

Out of scope: wording of non-error messages (kept verbatim); empty states (28); the home Foods I Eat screen (no load failure today).

## Decision Ledger

| Id | Decision |
|----|----------|
| D-27.1 | New `lib/widgets/feedback/omni_message.dart`: `OmniMessage.show(BuildContext, String text, {SnackBarAction? action, Duration? duration})` for info and `OmniMessage.error(BuildContext, String text)` for failures (adds a leading `Icons.error_outline` in `colorScheme.error`). Both call `ScaffoldMessenger.of(context).showSnackBar` with default (fixed) behaviour so placement does not change. Colours from `Theme.of(context).colorScheme` (`surface`, `onSurface`); shape `RoundedRectangleBorder(OmniTheme.buttonUtilityRadius)`. Never takes an exception object. |
| D-27.2 | Error copy rule: "Could not <verb> <thing>. Try again." (first words may follow the existing phrase, e.g. "Failed to add exercise: $e" becomes "Could not add the exercise. Try again."). The exception object may be passed to `debugPrint` only. Non-error messages keep their text verbatim. |
| D-27.3 | `PRToast` keeps raw `SnackBar` construction (celebration look, D-9..D-12 of its own plan). Sites that show a PRToast snackbar stay on `ScaffoldMessenger...showSnackBar(PRToast.build...)`; the scan allows exactly that argument. |
| D-27.4 | Load failure: each of the three Stats-area screens gets a `_loadFailed` flag set in the existing `catch (_)`; when set it renders a centred message (`Could not load your stats.` / `Could not load your records.` / `Could not load this exercise.`) and a `FilledButton` "Try again" (shape per D-26.2 button rule, `OmniTheme.buttonBorderRadius`) that clears the flag, sets loading, and re-runs the existing load method. |
| D-27.5 | Scan guard in `test/ui_standards_contract_test.dart` (helper from plan 26): no `SnackBar(` constructor and no `showSnackBar(` call outside `lib/widgets/feedback/omni_message.dart`, `lib/widgets/session/pr_toast.dart`, and calls whose argument starts with `PRToast.`; and no `$` interpolation of `e`, `error`, `ex` or `err` inside an `OmniMessage.` call. |

## Scenarios (red at base)

- S-2701 `OmniMessage.show` / `.error` pumped under a `Scaffold` with a light and a dark theme: the SnackBar's background is
  `colorScheme.surface`, text colour `onSurface`, shape is a `RoundedRectangleBorder`; `.error` shows an error icon; `.show` does not.
  (No such class at base: compile red.)
- S-2702 Scan: no raw SnackBar/showSnackBar outside the allowed files. Red at base: the 16 files listed by
  `grep -rln "SnackBar(" lib` (add_food_screen 21 sites, food_form 9, workout_session_screen 7, routine_setup 7, exercise_library_detail 7,
  timer mixin 4, my_routines 3, profile 3, day_session_list 3, session_summary 2, and 6 files with one).
- S-2703 Scan: no exception interpolation in message text. Red at base: day_session_list_screen.dart:306, profile_screen.dart:1013 and :1099,
  my_routines_screen.dart:265, measurement_history_chart_sheet.dart:487, add_food_screen.dart:307, session_overview_screen.dart:124,
  workout_session_screen.dart:1550/1561/1584, avatar_crop_sheet.dart:220, food_form.dart:370, workout_session_finish.dart:108.
- S-2704 Stats, Records & Trends and Exercise Progress with a repository whose read throws: text `Could not load ...` and a
  `Try again` button are found; the empty-state text ("No sessions yet", "No history for this exercise") is not. Tapping `Try again`
  with the repository healthy again shows the normal content. Red at base: the empty state shows.

## Phases (serial, same test files)

| Phase | Agent | Scope | Items |
|-------|-------|-------|-------|
| 1 | crew-builder-app | `lib/widgets/feedback/**`, `lib/features/stats/**`, `test/**` | helper + S-2701; S-2704 for the 3 screens |
| 2 | crew-builder-app | `lib/features/nutrition/**`, `test/**` | migrate `add_food_screen.dart` (21) and `food_form.dart` (9) |
| 3 | crew-builder-app | `lib/features/session/**`, `test/**` | migrate `workout_session_screen.dart` 7, `workout_session_timer_mixin.dart` 4, `session_summary_screen.dart` 2, `workout_session_finish.dart` 1, `session_overview_screen.dart` 1 |
| 4 | crew-builder-app | `lib/features/{routine,exercise,profile,calendar}/**`, `test/**` | `my_routines` 3, `routine_setup` 7, `exercise_library_detail` 7, `exercise_editor` 1, `profile_screen` 3, `day_session_list` 3, `measurement_history_chart_sheet` 1, `avatar_crop_sheet` 1 |
| 5 | crew-builder-app | `test/**` | S-2702, S-2703 scan groups; then prover, reviewer |

Predicted production diff about 350 lines changed in 18 files. Predicted existing-test fallout: tests that find the old message strings
containing `$e`-style text, and tests that find a `SnackBar` widget by type (still works). Builders grep `test/` for each changed string first.
