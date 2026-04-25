# Feature: Settings Account Removal

## Overview
Remove the non-functional Account section from the Settings screen before TestFlight. This is a removal-only cleanup pass: eliminate the Sign In and Export Data rows, remove the now-empty Account card/header, and keep the Version value visible as a low-emphasis footer at the bottom of the screen.

Fast-track note: this change introduces no new user-facing flow, no schema changes, and no new state methods. It can go directly to @developer without a DBA phase.

## Requirements
- Remove the Sign In row entirely from Settings, including its subtitle, icon, chevron, tap handler, and any navigation or snackbar target tied only to that row.
- Remove the Export Data row entirely from Settings, including its subtitle, icon, trailing icon, tap handler, and any dead references tied only to that row.
- Remove the Account section container and the ACCOUNT header once the rows are deleted.
- Relocate the Version display so it remains visible at the bottom of Settings as plain, low-emphasis footer text.
- Leave Measurements, Training, and Appearance sections unchanged in behavior and ordering.
- Remove or update tests that explicitly assert the old Account section, Sign In row, Export Data row, or Account snackbar behavior.
- Clean up any dead imports, icon references, constants, or handlers left behind by the removed rows.

## Acceptance Criteria
- [ ] The Sign In row no longer appears anywhere in Settings.
- [ ] The Export Data row no longer appears anywhere in Settings.
- [ ] The Account section card and ACCOUNT header are fully removed.
- [ ] The Version text remains visible as a plain footer element below the Appearance section, outside any card and without tappable-row affordances.
- [ ] Settings shows exactly three retained section cards in order: Measurements, Training, Appearance; then the Version footer.
- [ ] Measurements behavior is unchanged.
- [ ] Training behavior is unchanged, with Equipment and Modality Defaults still present.
- [ ] Appearance behavior is unchanged.
- [ ] No dead handlers, orphan references, or unused imports remain for Sign In or Export Data.
- [ ] Widget tests no longer reference the removed Account structure and verify the new footer placement.
- [ ] Relevant tests pass after the cleanup.

## Scenarios
- Open Settings and confirm the visible cards are Measurements, Training, and Appearance only.
- Scroll to the bottom of Settings and confirm the version number is visible as small footer text, not in a card and not interactive.
- Tap Equipment and confirm its existing placeholder snackbar still appears.
- Tap Modality Defaults and confirm its existing placeholder snackbar still appears.
- Confirm there is no Sign In or Export Data entry anywhere on the screen.

## Iteration 1
### Analysis
Current implementation places an ACCOUNT placeholder section in [lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart) containing Sign In, Export Data, and Version. Existing tests in [test/screen_widget_test.dart](test/screen_widget_test.dart) and [test/interaction_flow_test.dart](test/interaction_flow_test.dart) explicitly assert the Account section and Sign In snackbar behavior.

### DB Changes
- None required.
- No repository, persistence, or schema work is expected for this pass.

### Backend Changes
- None required.

### Frontend Changes (@developer)
1. [ ] Update [lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart) to remove the entire ACCOUNT placeholder section.
2. [ ] Delete the Sign In row definition and its placeholder snackbar usage.
3. [ ] Delete the Export Data row definition and its placeholder snackbar usage.
4. [ ] Re-home the version value as small, muted footer text at the bottom of the Settings list after the Appearance section.
5. [ ] Keep existing spacing visually balanced without adding new cards or sections.
6. [ ] Remove any no-longer-used icon references or local helpers only if they become unused after the row deletions.

### Test/Validation Steps (@developer)
1. [ ] Update [test/screen_widget_test.dart](test/screen_widget_test.dart) so it verifies the retained section order and the presence of the footer-style version text instead of ACCOUNT.
2. [ ] Update or remove the Account-specific portion of [test/interaction_flow_test.dart](test/interaction_flow_test.dart), preserving checks for still-supported Settings interactions only.
3. [ ] Run the focused widget test files covering Settings.
4. [ ] Run the broader relevant regression test set if the focused tests expose shared layout issues.

### Implementation Steps
1. [ ] Remove obsolete Account UI from the Settings list.
2. [ ] Add the non-interactive version footer below the retained sections.
3. [ ] Clean test expectations for removed rows/section.
4. [ ] Verify no analyzer warnings or unused imports remain.
5. [ ] Verify the Settings screen still scrolls and renders correctly on the retained sections.

## Progress
- [x] Remove Account section UI from Settings screen.
- [x] Relocate version text to footer.
- [x] Clean obsolete handlers/references.
- [x] Update Account-related widget tests.
- [x] Run relevant verification tests.

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Iteration 2 — TestFlight Finalization (April 20, 2026)
### Analysis
The previous pass removed Account (Sign In, Export Data). This pass removes Training (Equipment, Modality Defaults), renames Measurements → Preferences, adds a Start of Week preference row, and wires the start-of-week value through the calendar and any week-based UI.

No new DB tables are needed. The preference follows the same `setPreferenceString` / `getPreferenceString` pattern already used for weight unit and distance unit. All changes are confined to the state, settings UI, calendar, session summary mini-calendar, and tests.

### DB Changes
None. Preference is stored via the existing `WorkoutRepository.setPreferenceString` / `getPreferenceString` API.

### Backend / State Changes
1. [ ] Add `_preferredStartOfWeekKey = 'preferred_start_of_week'` constant to `SettingsState`.
2. [ ] Add `String _startOfWeek = 'monday'` field (default: Monday).
3. [ ] Add `String get startOfWeek => _startOfWeek` getter.
4. [ ] Add `Future<void> setStartOfWeek(String value) async` — normalises to `'sunday'` or `'monday'`, persists, notifies.
5. [ ] Load `_startOfWeek` in `_loadFromPrefs()`, defaulting to `'monday'`.

### Frontend Changes
#### Settings screen (`lib/features/settings/settings_screen.dart`)
6. [ ] Remove `_PlaceholderSection` for TRAINING and its two rows (Equipment, Modality Defaults) — including the `const SizedBox(height: 24)` spacer that precedes it.
7. [ ] Remove the now-dead `_showPlaceholderSnackBar` function.
8. [ ] Remove the now-dead `_PlaceholderSection` class.
9. [ ] Remove the now-dead `_SettingsRowData` class (only used by `_PlaceholderSection`).
10. [ ] Rename the `_MeasurementsSection` section header label from `'MEASUREMENTS'` to `'PREFERENCES'`.
11. [ ] Add a divider and a new **Start of Week** `_SettingsRow` at the bottom of `_MeasurementsSection`, below the preview block. Use a `_SegmentedToggle` with options `['sunday', 'monday']` (labels `'Sun'` / `'Mon'`), `groupValue: settingsState.startOfWeek`, `onChanged: settingsState.setStartOfWeek`.

#### Date utility (`lib/core/utils/date_utils.dart`)
12. [ ] Add `startOfWeek` parameter (default `'monday'`) to `buildMonthGrid`. For `'sunday'`: `leadingBlanks = firstOfMonth.weekday % 7` (Sun=7 maps to 0, Mon=1 maps to 1…). For `'monday'` (existing): `(firstOfMonth.weekday - 1) % 7`.

#### Calendar screen (`lib/features/calendar/calendar_screen.dart`)
13. [ ] Add `required SettingsState settingsState` parameter to `CalendarScreen`.
14. [ ] Remove the static `_weekLabels` const. Compute labels from `settingsState.startOfWeek`: Sunday-first = `['Sun','Mon','Tue','Wed','Thu','Fri','Sat']`, Monday-first = `['Mon','Tue','Wed','Thu','Fri','Sat','Sun']` (current).
15. [ ] Wrap the `Column` body in a combined listenable on both `calendarState` and `settingsState` so the grid re-renders reactively. (Simplest: wrap inner builder's ListView with a second `ListenableBuilder` on `settingsState`, or use `Listenable.merge`.)
16. [ ] Pass `settingsState.startOfWeek` to `OmniDateUtils.buildMonthGrid`.
17. [ ] Update `_WeekDayRow` to receive the labels list.

#### Home screen (`lib/features/home/home_screen.dart`)
18. [ ] Pass `settingsState: widget.settingsState` to the `CalendarScreen(...)` call inside `_buildMaintenanceGrid`.

#### Session summary screen (`lib/features/session/session_summary_screen.dart`)
19. [ ] In `_buildCalendarGrid`, derive `startOfWeek` from `widget.settingsState?.startOfWeek ?? 'monday'`.
20. [ ] Update the leading-blank calculation: `final leadingBlanks = startOfWeek == 'sunday' ? firstWeekday % 7 : firstWeekday - 1;`
21. [ ] Update `dayNumber` indexing to match the new `leadingBlanks`.
22. [ ] Pass `settingsState: widget.settingsState` to the `CalendarScreen(...)` call opened from this screen (inside `_openCalendarScreen`).

### Test / Validation
23. [ ] In `test/screen_widget_test.dart`, update `'renders retained sections in order with version footer'`:
    - Replace `MEASUREMENTS` finder with `PREFERENCES`.
    - Remove the `TRAINING` finder and `trainingY` ordering assertion.
    - Assert order is `PREFERENCES` before `APPEARANCE`.
    - Optionally assert that the `Start of Week` label is present.
24. [ ] Run `test/screen_widget_test.dart` and `test/settings_state_test.dart` to verify green.
25. [ ] Run the full test suite for regressions.

### Acceptance Criteria
- [ ] Sign In, Export Data, Equipment, Modality Defaults no longer appear in Settings.
- [ ] Account section card + ACCOUNT header: already removed in Iteration 1. ✓
- [ ] Training section card + TRAINING header: fully removed.
- [ ] Measurements section renamed to Preferences; header reads "PREFERENCES".
- [ ] Preferences section contains: Weight row, Distance row, preview block, Start of Week row.
- [ ] Start of Week row label = "Start of Week", subtitle = "First day shown in the calendar".
- [ ] Two-option segmented selector: Sunday / Monday, consistent style with kg/lbs toggle.
- [ ] Only one option selectable at a time.
- [ ] New users default to Monday.
- [ ] Changing selection persists immediately, no confirm step.
- [ ] Calendar screen leftmost day reflects Start of Week preference.
- [ ] Session summary mini-calendar leftmost day reflects Start of Week preference.
- [ ] Changing preference updates visible calendar without app restart.
- [ ] Version label remains plain low-emphasis footer at bottom, not in a card. ✓ (from Iteration 1)
- [ ] Screen order: Preferences card, Appearance card, Version footer.
- [ ] No dead classes, functions, or imports from removed Training section.
- [ ] No tests reference TRAINING or removed rows.

### Files Affected
- `lib/state/settings/settings_state.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/core/utils/date_utils.dart`
- `lib/features/calendar/calendar_screen.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/session/session_summary_screen.dart`
- `test/screen_widget_test.dart`

## Progress
- [x] Remove Account section UI from Settings screen. (Iter 1)
- [x] Relocate version text to footer. (Iter 1)
- [x] Clean obsolete handlers/references. (Iter 1)
- [x] Update Account-related widget tests. (Iter 1)
- [x] Remove Training section UI from Settings screen. (Iter 2)
- [x] Rename Measurements → Preferences section. (Iter 2)
- [x] Add Start of Week preference to SettingsState. (Iter 2)
- [x] Add Start of Week row to Preferences section. (Iter 2)
- [x] Parameterize buildMonthGrid for start-of-week. (Iter 2)
- [x] Wire start-of-week into CalendarScreen. (Iter 2)
- [x] Wire start-of-week into session summary mini-calendar. (Iter 2)
- [x] Update tests. (Iter 2)

## Feedback

