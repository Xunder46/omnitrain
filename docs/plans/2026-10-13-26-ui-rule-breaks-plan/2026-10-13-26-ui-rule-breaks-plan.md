# 26 · Fix the UI rule breaks and guard them

Status 2026-10-13: Reviewed (APPROVE WITH FIXES, fixed in fix round 1), proved, verified. Final: flutter test +4467 ~1, analyze 181.

Parent: `docs/plans/2026-10-12-25-ui-standards-refresh-plan/` (survey, evidence, owner decisions). Base `6d17994`.
Owner approved 2026-10-13 ("go on all recommended"). Source sheets: `.../25-.../survey/s1`, `s3`, `s6`, `s7`, `s9`.

## Goal and acceptance

Eight places where the app breaks a written, unambiguous UI rule are fixed, and an automatic check fails if any of
them comes back. What the user sees afterwards:

1. Every dialog button is a slightly-rounded rectangle (8 buttons were default pills).
2. The modality picker dialog follows the theme (no fixed near-black / blue) and its Cancel is a text button.
3. Session block cards and routine segment cards use the shared card look (3 hand-built cards).
4. Records page: "Recent PRs" is a normal section label above its card (`RECENT PRS`). Calendar day list: the three
   group labels are normal section labels (`COMPLETED`, `PLANNED`, `IN PROGRESS`).
5. Delete icons on calendar session rows, period rows and the live session list follow the theme's error colour.
6. Calendar-month arrows, Settings close, delete icons, and 12 other icon-only buttons have a tooltip (screen-reader label).
7. Onboarding "Get Started" text, the coach-mark card, the Routines home tile grey and the session summary divider
   follow the theme.
8. `flutter test` green; `flutter analyze` issue count not above the baseline (195, 0 errors).

Out of scope (each has its own plan): snackbars (27), empty states (28), unsaved guards and delete confirms (29),
ratchet tests beyond these rules and process rules (30), docs (25). Routine Save/Cancel row stays (D7: documented
exception). Period highlight colour from the user's chosen hex stays (user data).

## Decision Ledger

| Id | Decision |
|----|----------|
| D-26.1 | Destructive icon colour = `Theme.of(context).colorScheme.error` (what `ConfirmationDialog` already uses). No new theme value, so the palette contract tests are untouched. |
| D-26.2 | Dialog button shape = `RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius))` via `ButtonStyle(shape: WidgetStateProperty.all(...))` exactly as `lib/widgets/dialogs/confirmation_dialog.dart:155-166`. |
| D-26.3 | Cards: `OmniSurface` with `padding: const EdgeInsets.all(12)` (they had 12) wrapped in `Padding` for the old margin. Drop the translucent 0.7 fill and the elevation: that is the point. |
| D-26.4 | Section labels: `OmniCardHeader(title: ...)` above an `OmniSurface`/list, uppercase titles (D6: uppercase for screen-level sections). |
| D-26.5 | Guards are source-scan tests (`test/ui_standards_contract_test.dart`) over `lib/` (excluding `lib/watch/`), using a helper that finds a constructor call by balancing parentheses and skips comments. Exceptions live in `test/support/ui_standards_allowlist.dart`, each with a reason string; the list may only shrink. |
| D-26.6 | Raw colour rule: `Color(0x...)` literals and hue-bearing `Colors.<name>` (red, redAccent, blue, grey, green, orange, amber, ...) are banned outside the allowlist and `lib/app.dart` (the ColorScheme role mapping). `Colors.white`/`Colors.black`/`Colors.transparent` stay allowed but their per-file counts are a ratchet (may not rise above today's). |
| D-26.7 | Allowlisted on purpose: scrims (`workout_session_global_timer.dart` two `0xBF000000`), shadow (`energy_tile.dart` `0x4D000000`), user-chosen period highlight (`calendar_screen.dart` `Color(0xFF000000 | value)`), `lib/core/constants/omni_theme.dart`, `modality_colors.dart`, the `_colorPalette` of period colours in `create_period_screen.dart` (user-pickable swatches). |
| D-26.8 | Tooltip text = a plain verb phrase from the icon and its context ('Previous month', 'Next month', 'Close', 'Back', 'Delete period', 'Delete session', 'Delete exercise', 'Clear search', ...). Builder reads each site and picks; list them in the report for QA. |

## Scenarios (every one is red at the base commit)

- S-2601 Button shape scan: every `TextButton|FilledButton|OutlinedButton|ElevatedButton(.icon)` constructor in `lib/`
  contains `shape`. Red at base: `calendar/day_session_list_screen.dart` 737, 746, 759, 768; `nutrition/add_food_screen.dart` 968, 1732;
  `widgets/pickers/metric_chooser_dialog.dart` 44, 109 (8 sites).
- S-2602 `ModalityPickerDialog` pumped: no `OutlinedButton` in the dialog; the Cancel button is a `TextButton` whose
  style resolves a `RoundedRectangleBorder`. Red at base (`modality_picker_dialog.dart:40` is an `OutlinedButton`).
- S-2603 No raw `Card(` in `lib/features` or `lib/widgets`. Red at base: `session/workout_session_list_view.dart:161`,
  `routine/routine_setup_screen.dart:354` and `:1113`.
- S-2604 Colour scan (D-26.6). Red at base: `widgets/pickers/modality_picker_dialog.dart:22,90,94,99,117,125`,
  `features/session/workout_session_global_timer.dart:808`, `features/onboarding/onboarding_screen.dart:327`,
  `core/constants/home_tiles.dart:102`, `calendar/day_session_list_screen.dart:522`, `period/period_list_screen.dart:236`,
  `session/workout_session_list_view.dart:234`, `calendar/calendar_screen.dart:470`.
- S-2605 `RecentPRList` pumped with one PR: one `OmniCardHeader` titled `RECENT PRS` is found above the card; no raw
  `Text('Recent PRs')` inside the card. `DaySessionListScreen` pumped with a completed, a planned and an in-progress
  session: three `OmniCardHeader`s `COMPLETED`, `PLANNED`, `IN PROGRESS`. Red at base: no `OmniCardHeader` there.
- S-2606 Icon-only button scan: every `IconButton(` has `tooltip:` (or is inside `Semantics`). Red at base (18 sites):
  calendar_screen 273, 285; day_session_list 514, 520, 714; exercise_library 117; exercise_picker 231; maintenance_placeholder 24;
  period_list 234; routine_setup 389, 399; session_overview 267; session_summary 601; workout_session_list_view 986;
  settings 525, 620; records_and_trends 154; `lib/widgets/layout/omni_back_header.dart` 46.
- S-2607 Colour ratchet: `Colors.white` and `Colors.black` counts per file do not exceed the recorded baseline
  (written into the allowlist file by the builder from a grep today; red only if a count is raised, so the prover
  proves it with a mutation, not a base run).

## Phases (serial: same files)

| Phase | Agent | Scope | Items |
|-------|-------|-------|-------|
| 1 | crew-builder-app | `lib/features/**`, `lib/widgets/**`, `test/**` | scan helper + contract test file (tests first); S-2601 8 buttons; S-2602 picker + chooser; S-2603 cards; S-2605 two header changes |
| 2 | crew-builder-app | same | S-2604 colours; delete icons; S-2606 18 tooltips; S-2607 baseline in allowlist; report the QA list |
| 3 | crew-prover | `test/**` | prove S-2601..S-2606 at base; list mutations for S-2607 |
| 4 | crew-reviewer + governor | read-only | review; governor verifies full suite and analyze |

Predicted production diff: about 200 lines changed in about 20 files. Predicted existing-test fallout: tests that find the
text `Recent PRs`, `Completed`, `Planned`, `In Progress`, or a `Card` widget in the session list / routine setup. Builders
list these first (grep `test/`) and update only those strings/finders, and report them.

## Code pointers (current lines)

- Dialog button pattern to copy: `lib/widgets/dialogs/confirmation_dialog.dart:155-166`.
- Cards: `workout_session_list_view.dart:161` `return Card(color: tileColors.surface.withOpacity(0.7), elevation: 2, margin: const EdgeInsets.fromLTRB(16, 0, 16, 16), shape: ...(12)`; `routine_setup_screen.dart:354` margin `bottom: 16`; `:1113` margin `bottom: 12`, child `InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12)`: keep the InkWell, set its radius to `OmniTheme.surfaceBorderRadius`.
- `OmniSurface({child, padding, showShadow})` has no margin: `lib/widgets/layout/omni_surface.dart`.
- `OmniCardHeader({title, actions, padding})`: `lib/widgets/layout/omni_card_header.dart`.
- Recent PRs: `lib/features/stats/widgets/recent_pr_list.dart:33-41`. Day list: `class _SectionHeader` at `day_session_list_screen.dart:406-421`, used at 130, 147, 173.
- Delete red: `day_session_list_screen.dart:522`, `period_list_screen.dart:236`, `workout_session_list_view.dart:234`.
