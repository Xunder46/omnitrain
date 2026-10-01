# Feature: Distance Unit Preference & UnitFormatter

## Overview
Add distance unit preference support to the existing settings state and introduce a shared unit-formatting utility for weight and distance conversions. Phase 1 established the persisted state and formatting foundation; Phase 2 wires those preferences into the existing settings screen with measurement controls and placeholder training/account sections.

## Requirements
- Add persisted distance unit preference to SettingsState using the existing WorkoutRepository preference pattern.
- Normalize accepted distance values to `km` or `miles`, defaulting to `km`.
- Create a pure static UnitFormatter utility as the single source of truth for weight and distance display labels and conversions.
- Preserve existing appTheme and preferredWeightUnit behavior.
- Add a MEASUREMENTS section to the settings screen before the existing APPEARANCE section.
- Add a TRAINING section before APPEARANCE and an ACCOUNT section after APPEARANCE.
- Preserve the existing AppBar, scaffold, and APPEARANCE implementation unchanged.
- Use OmniSurface, manual row layouts, and the established dark instrument-panel visual language.

## Acceptance Criteria
- [x] SettingsState exposes preferredDistanceUnit with getter, setter, and persistence under the key `preferred_distance_unit`
- [x] Default distance unit is `km`; invalid or legacy values normalize to `km`
- [x] UnitFormatter exists in the core utils layer and is stateless/static-only
- [x] Weight labels return `kg`/`lbs` and uppercase `KG`/`LBS` correctly
- [x] Weight formatting and canonical conversion behave correctly for both `kg` and `lbs`
- [x] Distance labels return `km`/`mi` and uppercase `KM`/`MI` correctly
- [x] Distance formatting and canonical conversion behave correctly for both `km` and `miles`
- [x] Settings screen section order is MEASUREMENTS, TRAINING, APPEARANCE, ACCOUNT
- [x] MEASUREMENTS contains weight and distance segmented toggles with live preview updates via the existing ListenableBuilder
- [x] TRAINING rows show the specified placeholder SnackBars on tap
- [x] ACCOUNT contains Sign In, Export Data, and non-interactive Version rows
- [x] Existing APPEARANCE section, AppBar, and scaffold remain visually and structurally unchanged
- [x] All interactive rows maintain the specified spacing, minimum touch targets, and rounded-rectangle treatment
- [x] UnitFormatter is the sole source of rendered unit labels across session, routine, summary, and profile flows
- [x] Switching weight preference to lbs updates inline editors, previous-set banners, summary tiles, PR copy, and profile measurements immediately without restart
- [x] Switching distance preference to miles updates timed previous-set distance displays immediately without restart
- [x] Profile measurement entry for `unit-kg` values round-trips through display conversion while storing canonical kg in state/repository
- [x] Measurement history charts plot and label display-unit values rather than raw canonical kg values
- [x] No display-facing code path outside UnitFormatter emits hardcoded weight or distance unit strings except explicit nullable fallback guards

## Scenarios
- Fresh install with no saved distance preference defaults to `km`
- Existing saved preference values such as `mile`, `mi`, or invalid strings normalize safely to `km` or `miles` per the implementation rule
- Formatting hides decimals for whole numbers and shows one decimal place otherwise, matching the app’s current display pattern
- Inline editors and future screens can consume uppercase labels without generating their own unit strings
- Tapping `kg` or `lbs` immediately updates the weight preview sample without a screen reload
- Tapping `km` or `mi` immediately updates the distance preview sample without a screen reload
- Placeholder training and account rows provide feedback with the exact specified SnackBar copy
- Completing a set or timed block shows the previous-set banner in the active display unit without any screen-specific unit formatting logic
- Session summary best-weight and PR callouts display the preferred weight unit consistently with the rest of the app
- Profile body weight and lean mass show converted display values while remaining stored canonically as kilograms
- Re-opening the profile measurement log sheet after saving a lbs entry shows the correctly reconverted display value
- The measurement history chart line, y-axis bounds, and selected-entry label stay aligned to the current display unit

## Iteration 1
## Analysis
The request is tightly scoped to shared state and utility groundwork for a broader unit-preference feature. No schema changes, repository contract changes, or screen work are required. This makes it a direct Developer handoff.

## Questions (if any)
1. None. The scope and acceptance criteria are explicit.

## Implementation Plan

### Phase 1: Logic/Foundation (@developer)
1. [ ] Update [lib/state/settings/settings_state.dart](lib/state/settings/settings_state.dart) to add the new private constant, backing field, public getter, and async setter for preferred distance unit.
2. [ ] Keep normalization logic string-based and aligned with the existing weight-unit implementation style.
3. [ ] Extend the preference-loading path in [lib/state/settings/settings_state.dart](lib/state/settings/settings_state.dart) so saved distance values load on initialize and safely fall back to `km`.
4. [ ] Create [lib/core/utils/unit_formatter.dart](lib/core/utils/unit_formatter.dart) as a pure static utility with no instance state.
5. [ ] Implement the requested weight helpers: conversion, lowercase label, uppercase label, formatted value with label, formatted numeric value without label, and canonical conversion back to kilograms.
6. [ ] Implement the requested distance helpers: conversion, lowercase label, uppercase label, formatted value with label, formatted numeric value without label, and canonical conversion back to kilometers.
7. [ ] Use the specified constants: $1\ \text{kg} = 2.20462\ \text{lbs}$ and $1\ \text{km} = 0.621371\ \text{mi}$.
8. [ ] Match the existing number-formatting rule from the session summary flow, while allowing the explicit decimals argument to override the default formatting behavior.
9. [ ] Verify no screen files were changed and run the relevant tests for settings and utility behavior.

### DB Changes
- None. Continue using WorkoutRepository string preferences as-is.

### Backend Changes
- None. No repository method or schema updates are required.

### Frontend Changes
- None in this phase. Do not touch screen files.

### Files Affected
- [lib/state/settings/settings_state.dart](lib/state/settings/settings_state.dart)
- [test/settings_state_test.dart](test/settings_state_test.dart) if targeted validation is added or updated
- [test/utils_test.dart](test/utils_test.dart) or another focused utility test file if formatter coverage is added

## Progress
- [x] Add preferredDistanceUnit to SettingsState
- [x] Create UnitFormatter utility
- [x] Verify relevant tests pass
- [x] Confirm zero screen-file changes

## Doc Updates
- No update required for this scoped state/utility phase.

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Iteration 2
## Analysis
This is a UI-only follow-up to the existing unit-preference foundation. No new schema, repository, or state methods are needed because the screen already receives SettingsState and the formatting utility is in place. The work should be a direct Developer handoff and also qualifies for the fast-track path because there is no new user-data model or storage contract.

## Questions (if any)
1. None. The requested section order, row copy, and visual specs are explicit.

## Implementation Plan

### Phase 2: Settings Screen UI (@developer)
1. [ ] Update [lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart) only; do not modify the existing AppBar, scaffold, or APPEARANCE tile grid.
2. [ ] Insert a new MEASUREMENTS OmniSurface before APPEARANCE with two manual rows for Weight and Distance using the shared row spacing and typography spec.
3. [ ] Build a reusable segmented toggle widget/helper inside the screen file or as a local private widget using dark background, $8$ radius outer shell, $6$ radius active pill, minimum $52$ dp option width, and $36$ dp height.
4. [ ] Bind the weight toggle to SettingsState.preferredWeightUnit and SettingsState.setPreferredWeightUnit(...).
5. [ ] Bind the distance toggle to SettingsState.preferredDistanceUnit and SettingsState.setPreferredDistanceUnit(...), mapping the displayed `mi` option to the persisted miles preference cleanly.
6. [ ] Add the PREVIEW inset box below the toggle rows using the specified icons and UnitFormatter examples: $100.0$ for weight and $5.0$ for distance.
7. [ ] Insert a TRAINING OmniSurface below MEASUREMENTS and above APPEARANCE with manual InkWell rows for Equipment and Modality Defaults, each showing the exact placeholder SnackBar message.
8. [ ] Insert an ACCOUNT OmniSurface below APPEARANCE with Sign In, Export Data, and non-interactive Version rows using the exact specified copy and icons.
9. [ ] Keep section spacing at $24$ dp and add $40$ dp breathing room at the bottom of the ListView.
10. [ ] Verify that touch targets stay at or above $48$ dp and that no ListTile or StadiumBorder usage is introduced.
11. [ ] Run the relevant widget tests or targeted Flutter test command to confirm the screen still builds and that no regressions were introduced.

### DB Changes
- None.

### Backend Changes
- None.

### Frontend Changes
- Extend the existing settings screen UI with measurements and placeholder panels while preserving the completed appearance section exactly as-is.

### Files Affected
- [lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart)
- [test/widget_test.dart](test/widget_test.dart) or a more targeted settings screen test if validation coverage is added

## Progress
- [x] Extend UnitFormatter with uppercase and numeric-only helpers needed by session and routine inline displays
- [x] Remove remaining hardcoded weight strings from session summary rendering
- [x] Wire WorkoutSessionScreen previous-set and inline editor labels to SettingsState through UnitFormatter
- [x] Pass SettingsState through MyRoutinesScreen into RoutineSetupScreen and replace routine-specific hardcoded unit labels
- [x] Wire ProfileScreen, measurement log sheet, and history chart through UnitFormatter for `unit-kg` values
- [x] Run focused tests and a display-string audit for remaining hardcoded unit output paths

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Iteration 3
## Analysis
Phase 3 is the app-wide wiring pass that applies the already-established settings preferences and UnitFormatter foundation to every remaining weight and distance display/input path. There are no schema, repository, or persistence-contract changes required; this is a focused Developer handoff spanning session UI, routine UI, summary copy, and profile measurement presentation.

## Questions (if any)
1. None. The requested scope, method-level replacements, and acceptance criteria are explicit.

## Implementation Plan

### Phase 3: App-wide Unit Preference Wiring (@developer)
1. [ ] Update [lib/core/utils/unit_formatter.dart](lib/core/utils/unit_formatter.dart) only by extending the existing static API surface; reuse the current conversion methods and keep all display labels centralized there.
2. [ ] Patch [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart) so best-weight subtitles and PR achievement strings format through UnitFormatter instead of concatenating raw weight labels.
3. [ ] Update [lib/features/session/workout_session_screen.dart](lib/features/session/workout_session_screen.dart) to source uppercase inline-editor labels from the existing preferred-unit getter and to rebuild all previous-set banner strings through UnitFormatter for set, timed, and drill effort kinds.
4. [ ] Keep nullable SettingsState handling safe in the workout screen: prefer passing a non-null settings object where already available, but allow minimal fallback formatting only when the widget truly lacks settings.
5. [ ] Add an optional settingsState dependency to [lib/features/routine/my_routines_screen.dart](lib/features/routine/my_routines_screen.dart) and thread it through both create and edit navigation paths into [lib/features/routine/routine_setup_screen.dart](lib/features/routine/routine_setup_screen.dart).
6. [ ] Replace all remaining routine inline-editor and previous-set display labels with UnitFormatter-backed labels, including the extra-weight editor labels for timed and drill flows.
7. [ ] Add a required settingsState dependency to [lib/features/profile/profile_screen.dart](lib/features/profile/profile_screen.dart) and pass it into the profile measurement row, log sheet, and chart sheet paths from the existing home-screen launch point.
8. [ ] In the profile measurement list and chart flows, treat only `unit-kg` entries as conversion-aware: display via UnitFormatter, prefill edited values in the preferred unit, and convert back to canonical kilograms before saving.
9. [ ] Update [lib/features/profile/widgets/measurement_history_chart_sheet.dart](lib/features/profile/widgets/measurement_history_chart_sheet.dart) so plotted values, y-axis ranges, and selected-entry labels use display units for `unit-kg` definitions while leaving cm and percent entries untouched.
10. [ ] Run targeted Flutter tests covering settings, session summary, profile measurements, and interaction flows, then perform a workspace search to confirm there are no display-facing raw unit literals remaining outside UnitFormatter and the explicit fallback exceptions.

### DB Changes
- None.

### Backend Changes
- None. Canonical storage remains kg for weight and km for distance.

### Frontend Changes
- Session summary strings, workout session banners/editors, routine setup banners/editors, and profile measurement UI all become live consumers of SettingsState through UnitFormatter.

### Files Affected
- [lib/core/utils/unit_formatter.dart](lib/core/utils/unit_formatter.dart)
- [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart)
- [lib/features/session/workout_session_screen.dart](lib/features/session/workout_session_screen.dart)
- [lib/features/routine/my_routines_screen.dart](lib/features/routine/my_routines_screen.dart)
- [lib/features/routine/routine_setup_screen.dart](lib/features/routine/routine_setup_screen.dart)
- [lib/features/profile/profile_screen.dart](lib/features/profile/profile_screen.dart)
- [lib/features/profile/widgets/measurement_history_chart_sheet.dart](lib/features/profile/widgets/measurement_history_chart_sheet.dart)
- [lib/features/home/home_screen.dart](lib/features/home/home_screen.dart)
- Targeted tests in [test](test)

### Notes
- UnitFormatter remains the single source of truth for user-visible weight and distance labels.
- Raw unit strings remain acceptable only for persistence keys, model IDs such as `unit-kg`, and internal SettingsState comparisons.
- This phase touches live UI behavior and should be validated on web after the focused test run.

### Phase 3 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback
### Review Follow-up Complete ✓
- Remaining hardcoded settings toggle labels were moved behind UnitFormatter-backed helpers.
- Focused widget coverage was added for preferred-unit workout/routine behavior.
- Supporting agent docs were refreshed to match the current SettingsState and SettingsScreen wiring.

### Review Status
- Approved after follow-up verification.
