# 25 · Evidence (survey, 2026-10-12)

Nine read-only scouts (GLM 5.3 flash), sheets in `survey/`. Governor read all nine and re-checked claims against
the code. Findings page published to the owner as a private artifact (plain language).

## Scouts

| Sheet | Covers | Findings (raw) |
|-------|--------|----------------|
| s1 | every rule in `design_system.md` and the UI rules in `global_conventions.md` | 28 |
| s2 | widget catalog vs `lib/widgets` | 11 |
| s3 | grep scan of all screens (colours, buttons, dialogs, labels, keyboard, empty states) | 9 verdicts |
| s4, s5 | UI rules decided in ~75 past plans | 12 + ~9 |
| s6 | session / exercise / routine | 15 + matrix |
| s7 | home / calendar / profile / settings / onboarding / startup | ~17 + matrix |
| s8 | nutrition | 14 + matrix |
| s9 | stats / records / signals | 10 + matrix |

Cost and time: each scout 3-9 min, 0.5-0.9M input tokens (mostly cached). All nine finished; no run stopped.

## Governor verification (observed in the code, 2026-10-12)

Held: raw bottom-sheet calls (scout 15, observed 16); error snackbars (scout "30+", observed 71 raw `SnackBar(` outside
`lib/widgets`, so the scout undercounted); no `snackBarTheme`/`bottomSheetTheme` anywhere; resume dialog class gone;
`pressedScale = 0.9` vs doc 0.96; four `TextButton`s with no style (`add_food_screen.dart`, `metric_chooser_dialog.dart`);
`ModalityPickerDialog` Cancel is an `OutlinedButton` inside a dialog; delete icons fixed `Colors.redAccent`
(`day_session_list_screen.dart`, `period_list_screen.dart`); `RecentPRList` title is a raw `Text`; calendar month arrows
and Settings close button have no tooltip; profile snackbar prints `$e`; `CreatePeriodScreen` has no `PopScope`;
`EditFoodScreen` has no bottom CTA; `SessionOverviewScreen` is built by no `lib/` code (only `test/session_screen_build_phase_notify_test.dart`).

**Wrong, dropped:** s5 reported `train-screen-non-scrolling-layout` Phase 2 and `timer-start-on-exercise-select` as
unbuilt. Both are built (`home_screen.dart` rows with uniform gap; `resetSessionTimerStart` in
`session_core_lifecycle.dart:64`, called at `workout_session_screen.dart:1593`); only the plans' progress boxes were
never ticked. s1 line numbers into `design_system.md` are off by about 11 lines: re-derive before editing.

Not verified: text-scale overflow and tap-target sizes (nobody ran the app); s6 did not search `test/` for guards, so
its "none found" lines mean `lib/` only.

## Stale statements (docs to correct in phase 2a)

- `widget_catalog.md` ("Note on resume dialog"), `navigation_and_screens.md` (Active Session Resume), `releases/2026-05-plan-review.md` line ~25 (history, leave): silent restore, no prompt.
- `widget_catalog/session_widgets.md` ModalityPickerDialog: four modalities, no General.
- `modality_based_exercise_ui.md`: no FAB (inline add bar); InlineMetricEditor is tap-only, not drag.
- `session_summary.md` layout table: date and modality chip are on the first card.
- `exercise_ranking.md` lines ~47-49: Recommended / Other partition exists (threshold in `modality_config.dart`).
- `rolling_sessions.md`: quoted source comment gone.
- `exercise_info_and_notes.md`: bilateral exercises show the logging note instead of the empty text.
- `app_philosophy.md` §8 (hub snap points) and §11 (onboarding seeds defaults: it does not).
- `calendar_periods.md`: day list has an In Progress group; streak slot relabels to BEST RUN, flame from 3 days.
- `navigation_and_screens.md`: placeholder screen contradiction; `StartupPreparingScreen` missing from the inventory; target control is a labelled button.
- `docs-audit-2026-07-26.md` §8.1: only one hub exists (frozen record: add a dated note, do not rewrite).
- `nutrition.md` (Add Food is three tabs), `widget_catalog/nutrition_widgets.md` (`_GroupsTab`, New Category / Uncategorized, amount auto-commit, name and notes not select-all, Edit Food has no CTA).
- `design_system.md`: press scale; "Active Border"; cyan-means-interactive vs the six themes; "deprecated widgets are stubs"; "values live only in omni_theme" (the ColorScheme mapping in `lib/app.dart` holds about 104 literals); header table omits Records & Trends and Exercise Progress.
- `widget_catalog`: four undocumented pieces (`ConfirmationDialog`, `OverheadPressIcon`, `chart_primitives.dart`, `edge_aware_date_label.dart`).

## Never written (phase 2b, each with its existing test)

Keyboard dismissal and capitalisation (`keyboard_dismissal_test`, `capitalization_defaults_test`); hub hidden at rest
(`home_logo_hub_open_test`); bilateral note (`exercise_info_sheet_bilateral_test`); coach-mark anchoring
(`exercise_detail_coach_mark_positioning_test`); block-header plus (`screen_widget_test`); library vs picker info
button (`pr8_exercise_library_test`); grams vs count amount (no named test found); thumbnail ring (`nutrition_test`);
screen transition style (`omni_route_test`); weight step 0.5 (no test found); neutral chip / LOGGED label (plan only);
Foods I Eat empty message (`nutrition_test`); streak flame (no test); change-colour rule (no test).

## Written rules with no test (phase 4 candidates, owner approval needed)

Button shape; 48 dp targets; element labels; colours from theme (call sites); shared card; bottom CTA;
reduced motion; no text shadow / no bounce; text-scale (plan `typography-text-scale-audit` phases 4-5 never done);
dialog backdrop floor (plan `theme-system-overhaul`, dropped from code).

## Doc off standard (phase 2c)

`design_system.md`: Spacing and Layout table, Depth and Shadow table, Interaction and Animation table, button tables,
large-screen column constants, outline-role alphas and ratios, home-tile opacities, letter-spacing values,
accessibility ratios and dp, header-contract style values, the splash-screen story, PR/S-id annotations, survey counts.
`widget_catalog/*`: column-cap numbers, animation durations, crop-sheet geometry, tile sizes, regex, dispose delay,
FoodForm field list and prop table. `theme_and_settings.md`: copied enum and token table (already self-flagged).

## Unresolved and noticed (not part of this plan)

Dead code: `SessionOverviewScreen` (tests only), `MaintenancePlaceholderScreen`; unused `onEditTap` on
`CalorieRingCard`; stale comment at `lib/core/models/signals.dart:60`; two note debounces (600 ms vs 500 ms); different
one-point message in Exercise Progress vs the shared helper.
