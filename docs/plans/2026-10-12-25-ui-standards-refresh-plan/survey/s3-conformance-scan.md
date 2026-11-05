# S3 · Whole-app conformance scan (grep, read-only) · 2026-10-12

Scope scanned: `lib/features/**` and `lib/widgets/**` (67 + 34 dart files). Exclusions per brief
(`lib/core/constants/omni_theme.dart`, `lib/mock/`, `lib/watch/`) were outside the scanned roots anyway.
All counts are ripgrep match counts on disk today; "per folder" sums the brief's screen folders plus the
shared `lib/widgets/**` folders. Verdicts use the common sheet's kinds; rules cited are from
`docs/design_system.md` (read this run, lines quoted in the verdict lines).

---

## 1 · Raw colours

**1a. `Color(0x` — search `Color\(0x` in lib/features+lib/widgets → 7 matches / 5 files.**
- lib/features/calendar/calendar_screen.dart:483: `return Color(0xFF000000 | value).withOpacity(0.14);`
- lib/features/session/workout_session_global_timer.dart:694: `child: Container(color: const Color(0xBF000000)),`
- lib/features/session/workout_session_global_timer.dart:808: `color: const Color(0xFF1A1A2E),`
- lib/features/onboarding/onboarding_screen.dart:327: `const Color(0xFF060B14),`
- lib/widgets/cards/energy_tile.dart:340: `color: Color(0x4D000000), // black @ 30%`
- lib/widgets/pickers/modality_picker_dialog.dart:22: `color: Color(0xFF1a1a1a),`
Per folder: session 3, calendar 1, onboarding 1, widgets/cards 1, widgets/pickers 1.
Verdict: **BREAKS-RULE** — design_system.md "Values live in `lib/core/constants/omni_theme.dart` and
nowhere else" (Color System → Theme Roster) and Color Usage Rule 7 (modality accents from
`modality_colors.dart` only; `modality_picker_dialog.dart:22,90` hardcodes `Color(0xFF1a1a1a)`/`Colors.blue`).

**1b. `Colors.` — search `Colors\.` → 327 matches / 61 files; of those `Colors.transparent` = 78, so
non-transparent ≈ 249.** Per folder (incl. transparent): nutrition/widgets 72, stats/widgets 37,
session 31, stats 29, exercise 26, onboarding 17, calendar 16, home 15 (+home/widgets 9),
widgets/pickers 12, settings 10, widgets/layout 9, widgets/cards 9, profile 7, widgets/session 7,
widgets/chart 5, nutrition 4, period 3, widgets/common 3, profile/widgets 3 (+3 small dirs omitted by rg).
Examples (non-transparent):
- lib/widgets/pickers/modality_picker_dialog.dart:90: `color: isSelected ? Colors.blue : Colors.grey[700]!,`
- lib/features/session/workout_session_list_view.dart:234: `const Icon(Icons.delete, size: 18, color: Colors.red),`
- lib/features/period/period_list_screen.dart:236: `color: Colors.redAccent,`
- lib/features/calendar/day_session_list_screen.dart:522: `color: Colors.redAccent,`
- lib/widgets/common/interactive_logo.dart:89: `style: TextStyle(color: Colors.white, fontSize: 12),`
- lib/features/session/workout_session_global_timer.dart:834: `foregroundColor: Colors.black87,`
Verdict: **BREAKS-RULE** for the hue-bearing ones (red/redAccent destructive tints, blue/grey in the
modality picker — Color Usage Rule 7 and "Never hardcode button colours"); black/white opacity tints
are arguably sanctioned by Color Usage Rule 4 ("White text with opacity levels creates hierarchy") —
counted INCONSISTENT there because the rule names white text, not white/black fills and borders.

**1c. `.withOpacity(` / `.withValues(` — search → 165 matches / 37 files.** Per folder: routine 32,
session 30, calendar 18, exercise 14, profile/widgets 12, home 10, period 8, widgets/layout 7,
widgets/pickers 7, settings 7, widgets/cards 7, nutrition/widgets 5, profile 5, widgets/session 5,
stats 3, stats/widgets 2, routine/widgets 2, onboarding 1, splash 1, widgets/logo 1.
Most are alpha variants of theme tokens (`theme.colorScheme.onSurface.withOpacity(0.45)`), e.g.
- lib/features/session/workout_session_global_timer.dart:219: `color: theme.colorScheme.onSurface.withOpacity(0.45),`
- lib/features/routine/routine_setup_screen.dart:234: `color: theme.colorScheme.onSurface.withOpacity(0.65),`
- lib/features/calendar/calendar_screen.dart:470: `return Colors.grey.withOpacity(0.08);` (raw)
- lib/features/session/session_summary_screen.dart:555: `border: Border.all(color: Colors.white.withOpacity(0.06)),` (raw)
Verdict: **INCONSISTENT** — alpha-on-token is the dominant idiom and no doc forbids it, but raw-colour
alphas (calendar:470, session_summary:555, energy_tile:188-191) sit next to it with no rule naming
which is allowed. Note: repo mixes deprecated `withOpacity` and newer `withValues` with no stated rule.

## 2 · Hard-coded text styling

Search `fontSize:|fontWeight:|TextStyle\(` → 176 matches / 58 files. Per folder: nutrition/widgets 25,
session 17, exercise 14, routine 13, nutrition 12, profile 12, settings 11, widgets/session 10,
stats/widgets 9, calendar 9, period 6, stats 6, onboarding 6, home 4, profile/widgets 4,
widgets/pickers 4, widgets/chart 3, widgets/cards 2, widgets/layout 2, home/widgets 2 (+4 dirs omitted).
Examples:
- lib/features/profile/profile_screen.dart (12 matches in file; e.g. title styles via `textTheme.titleMedium?.copyWith`)
- lib/features/settings/settings_screen.dart:520-521: `style: theme.textTheme.titleMedium?.copyWith(\n  fontWeight: FontWeight.w600,`
- lib/widgets/common/interactive_logo.dart:89: `style: TextStyle(color: Colors.white, fontSize: 12),`
- lib/features/onboarding/onboarding_screen.dart (6; step-label chrome, D-10 exception covers the step label)
- lib/features/nutrition/widgets/nutrition_trend_card.dart (7)
- lib/features/calendar/calendar_screen.dart:281: `style: Theme.of(context).textTheme.titleMedium,` (theme-derived, OK)
Verdict: **INCONSISTENT** — most styling derives from `theme.textTheme` (allowed; the doc's typography
table governs letter-spacing tiers, not sizes), but raw `TextStyle(fontSize: …)` exists
(interactive_logo.dart:89) and no doc rule names a written ban to cite. The D-1 OmniCardHeader rule
("raw `Text` widgets above outlined cards are not permitted", design_system.md § Section/Card Headers)
is enforced by `test/header_standardization_test.dart` — not re-verified per-screen here (not checked).

## 3 · Buttons

- Material button constructors (`FilledButton|OutlinedButton|TextButton|ElevatedButton|IconButton` with `(`):
  **96 constructor sites / 40 files** (broader token count incl. `.icon`/`.styleFrom` forms: 155 / 41).
  `ElevatedButton`: **0** — the deprecated variant is fully gone.
- `shape:` → 108 / 45 files (includes non-button shapes: containers, input borders), so a precise
  "N of 96 set shape" was **not established**; spot checks show dialog buttons consistently set
  `RoundedRectangleBorder(OmniTheme.buttonUtilityRadius)` (workout_session_screen.dart:1620-1630,
  profile_screen.dart:652-662, routine_setup_screen.dart:834-836).
- `InkWell|GestureDetector` → 78 / 33 files; per folder: session 17, widgets/session 11,
  nutrition/widgets 10, profile(+widgets) 12, routine 6, settings 3, home(+widgets) 4, calendar 2,
  stats/widgets 2, widgets/cards 2, widgets/common 2, widgets/pickers 2, nutrition 2, period 2, stats 1.
- Shared button widgets: `lib/widgets/buttons/` contains only `.gitkeep` — **no shared button widget
  exists**. The shared pieces are `OmniBottomCTA` (primary bottom CTA, 15 constructor sites / 11 files:
  create_period, period_list, day_session_list, session_summary, session_list, my_routines,
  nutrition_target, add_food ×4, exercise_editor + the widget itself) and `OmniCardHeader`/`OmniBackHeader`.
Verdict: **BREAKS-RULE (partial, not fully counted)** — design_system.md Shape Rule (MANDATORY):
"Every `FilledButton`, `OutlinedButton`, or `TextButton` MUST explicitly set `shape`." Spot checks pass;
a per-site audit was not done (would need file-by-file reading, out of grep scope). Guard:
`test/screen_widget_test.dart:126-129` asserts a shape on one button; `test/widgets/confirmation_dialog_test.dart:143-147,724-728`
covers the dialog. No repo-wide shape sweep test found: searched `shape|StadiumBorder` in test/ —
only per-widget assertions, none iterate all buttons.

## 4 · Dialogs, sheets, snackbars

- `showDialog(`/`showModalBottomSheet(`/`showGeneralDialog(`/`showDatePicker(`/`showTimePicker(` →
  **8 call sites** (2 more matches are doc comments in the primer sheets):
  - spinner dialogs: workout_session_edit_mode.dart:145, session_summary_screen.dart:364, 391
    (`barrierDismissible: false`, `Center(child: CircularProgressIndicator())`)
  - bottom sheets: workout_session_global_timer.dart:126, 304
  - date picker: create_period_screen.dart:269 (`showDatePicker`)
  - `showTimePicker`: **0** (searched, not found).
- `AlertDialog(` → 12 sites: shared helpers confirmation_dialog.dart:150,215, metric_chooser_dialog.dart:38,
  duration_entry_dialog.dart:29, metric_crown_widget.dart:165; raw in screens: workout_session_screen.dart:1615,
  add_food_screen.dart:961,1691, exercise_library_detail_screen.dart:309, routine_setup_screen.dart:832,
  profile_screen.dart:644,1291. The raw screen ones are text-entry dialogs (rename/edit), not
  confirmations; they hand-set the utility shape per the Dialog Buttons rule.
- `ConfirmationDialog.` → 24 call sites / 15 files (the shared two-tier confirmation component).
- `SnackBar`/`ScaffoldMessenger` → 106 matches / 16 files, all raw `ScaffoldMessenger.of(context).showSnackBar(...)`;
  PR toasts go through the shared `PRToast.buildPRSnackBar`/`buildRepPRSnackBar` (widgets/session/pr_toast.dart:81,121).
  No shared snackbar helper exists (searched `showSnack|ScaffoldMessenger` — only PRToast centralises styling).
Verdict: **INCONSISTENT** — confirmations are centralised (rule + guard exist:
`test/widgets/confirmation_dialog_test.dart`), but text-entry dialogs and snackbars are built inline in
~10 screens with no doc saying whether that is allowed; error snackbars repeat
`SnackBar(content: Text('Failed to …: $e'))` verbatim in 8+ files.

## 5 · Raw navigation

Search `\bNavigator\.push|MaterialPageRoute|PageRouteBuilder` in lib/features+lib/widgets →
**0 code sites**; only 2 doc-comment mentions (avatar_crop_sheet.dart:74, profile_screen.dart:621,
both explaining they deliberately avoid the raw form). All routing goes through `OmniNavigator`
(55 call sites / 23 files; helpers live in `lib/core/navigation/omni_navigator.dart` — confirmed exists).
Verdict: **NO-RULE (clean)** — consistent, and global_conventions.md is referenced by design_system.md
for the navigation contract; I did not re-read global_conventions.md this run (not checked).

## 6 · Fixed sizes / text-scale overflow

- `SizedBox(height:/width: >100)` or `Container(height: >100)` → **1**:
  lib/features/session/session_summary_screen.dart (1 match; fixed tall block in the summary).
- `textScaler|textScaleFactor` → 6 matches / 3 files: maintenance_tile.dart:1, energy_tile.dart:1,
  home_screen.dart:4 (clamping/reading scaler). No other screen handles text scaling.
- `maxLines:` → ~80 / 30 files; `overflow:` → ~66 / 26 files. Pairing per-Text not done by grep
  (not established); `OmniCardHeader` enforces `maxLines: 1, overflow: ellipsis` for card headers.
Verdict: **NO-GUARD** — design_system.md Accessibility Requirement 6 ("text sizes must be legible…")
and the 48dp rule exist, but only 3 widgets touch `textScaler` and no test named in the docs pins
large-text behaviour per screen: searched `textScaler|textScaleFactor` in lib and `textScale` ideas
in test/ — not run against test/ (not checked).

## 7 · Accessibility

- `Semantics(|semanticLabel|tooltip:` → 22 files with matches. `tooltip:` → 21 sites / 13 files
  (workout_session_detail_view ×2, confirmation_dialog, workout_session_list_view, my_routines,
  routine_setup ×2, session_summary, food_form ×2, water_tracker ×2, add_food ×2, nutrition_screen ×2,
  stats_screen ×2, exercise_picker, signals_layer).
- Icon-only `IconButton(` → 36 sites / 21 files; icon-only buttons **without** `tooltip:` found at:
  - lib/features/session/session_overview_screen.dart:267 (delete exercise, no tooltip)
  - lib/features/calendar/calendar_screen.dart:273,285 (chevron_left/right month paging)
  - lib/features/period/period_list_screen.dart:234 (delete period, `Colors.redAccent`, no tooltip)
  - lib/features/settings/settings_screen.dart:525 (close button, no tooltip)
  - plus unverified-by-read sites: workout_session_list_view.dart:986, records_and_trends_screen.dart:154,
    day_session_list_screen.dart:514,520,714, exercise_picker_screen.dart:231, exercise_library_screen.dart:117,
    add_food_screen.dart:420, session_summary_screen.dart:601, my_routines_screen.dart:467 area, stats_screen.dart:252.
- Tap targets 24–36 px: grep for `SizedBox(width|height: 24-36)` returned 40 hits but inspection of the
  list shows they are **spacing gaps, not tap-target constraints**; a real small-tappable audit was
  **not established** by grep alone.
Verdict: **BREAKS-RULE** — design_system.md Accessibility Requirement 4: "all interactive elements must
have semantic labels" (and rule 2: minimum 48×48 dp). Named offenders above; guard: none found for
icon-button labels — searched `tooltip` in test/ (not run; not checked).

## 8 · Entry fields

- `TextField(|TextFormField(` → 17 files. Per folder: nutrition/widgets (food_form 5, log_food_row 1),
  profile 4, routine 3, session 4, exercise 4, calendar 2, period 2, stats 1, nutrition screens 3.
- `textCapitalization` → 13 files; `keyboardType` → 8 files (+ widgets/session 3, widgets/inputs 3);
  `unfocus|onTapOutside` → 4 files (numeric_field_with_done_bar ×2, add_food ×2, calorie_ring_card ×6,
  macro_donut_chart ×2 — the last two are chart widgets, not fields); `SelectAllOnFocus` → used by
  food_form (11), log_food_row, nutrition_target_screen, and the shared
  `lib/widgets/inputs/select_all_on_focus.dart` + `numeric_field_with_done_bar.dart` (11).
Verdict: **INCONSISTENT** — select-on-focus and the done-bar live in shared inputs used by the
nutrition/profile flows, but plain `TextField(` sites (e.g. rename dialogs in workout_session_screen.dart:1618,
profile_screen.dart:646, routine_setup_screen.dart:838) set `textCapitalization` yet no
`onTapOutside`/unfocus, and no doc states which fields must use the shared inputs.

## 9 · Empty states (distinct user-facing messages, lib/features)

| Message | Screen |
|---|---|
| 'No sessions on this day.' / 'No sessions planned yet.' | calendar/day_session_list_screen.dart:397 |
| 'No Routines Yet' | routine/my_routines_screen.dart:110 |
| 'No exercises in this block yet.' | routine/routine_setup_screen.dart:469 (also session_list_view.dart:249) |
| 'No exercises yet' + 'Add your first exercise to get started' | session/session_overview_screen.dart:191,196 |
| 'No exercises yet' | session/workout_session_list_view.dart:754 |
| 'No information available yet' | session/workout_session_global_timer.dart:286 |
| 'No exercises found' | exercise/exercise_library_screen.dart:329; exercise_picker_screen.dart:446 |
| 'No training periods yet.' | period/period_list_screen.dart:52 |
| 'No history for this exercise' | stats/exercise_progress_screen.dart:410 |
| 'No sessions yet' | stats/stats_screen.dart:432; stats/records_and_trends_screen.dart:355 |
| 'No training in the last N weeks.' | stats/widgets/mix_layer.dart:256 |
| 'No catalog foods available' / 'No matches for "…"' / 'No custom foods yet' | nutrition/add_food_screen.dart:397,436,672 |
| 'No history yet' | profile/widgets/measurement_sparkline.dart:199 |
| 'No entries yet' | profile/widgets/measurement_history_chart_sheet.dart:129 |
| 'No Capabilities' | widgets/pickers/metric_chooser_dialog.dart:39 (dialog title, edge case) |
Nutrition summary card empty states are parameterised (`isEmpty` flags, home/widgets/nutrition_summary_card.dart),
wording lives in the card/energy widgets, not literal strings here.
Verdict: **INCONSISTENT** — 15+ distinct phrasings for "nothing here" across screens; no doc names a
canonical empty-state component or copy pattern (searched docs terms only via design_system.md —
widget_catalog not read this run: not checked).

---

## Summary verdict lines

1. Raw colours: BREAKS-RULE (1a, 1b hue-bearing) / INCONSISTENT (alpha tints).
2. Text styling: INCONSISTENT.
3. Buttons: BREAKS-RULE (shape rule) — per-site audit not completed; no repo-wide guard test found.
4. Dialogs/sheets/snackbars: INCONSISTENT (confirmations centralised; entry dialogs + snackbars raw).
5. Navigation: NO-RULE (clean — 0 raw sites).
6. Fixed sizes / text scale: NO-GUARD.
7. Accessibility: BREAKS-RULE (icon-only buttons without labels; 48dp rule unenforced by tests found).
8. Entry fields: INCONSISTENT.
9. Empty states: INCONSISTENT.

Not checked: widget_catalog.md and global_conventions.md contents; per-site shape audit of all 96 button
constructors; maxLines/overflow pairing per Text; tap-target size audit below 40px; test/ coverage for
tooltip and text-scale rules.
