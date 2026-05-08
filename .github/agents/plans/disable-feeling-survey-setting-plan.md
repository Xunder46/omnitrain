# Feature: Disable Feeling Survey Setting

## Overview
Add a setting to the Settings page that allows users to disable the "How did it feel?" post-workout survey sheet that automatically appears after finishing a workout.

## Requirements
- A toggle in Settings that controls whether the feeling survey is shown after a session
- Default on (survey appears as before)
- Persisted across app restarts

## Acceptance Criteria
- [x] Setting persists across restarts (stored as preference string)
- [x] Default is `true` (survey shows as before unless user opts out)
- [x] When toggled off, finishing a workout goes straight to summary screen with no sheet
- [x] Toggle is visible on the Settings page with a clear label and subtitle
- [x] No impact on existing `sessionFeeling` data or fields

## Scenarios
N/A — no new state classes or screens required.

## Iteration 1

### DB Changes
None. Uses existing `setPreferenceString` / `getPreferenceString` pattern.

### Backend Changes
- Add `_showFeelingSurveyKey`, backing field, getter, setter, and load logic to `SettingsState`

### Frontend Changes
- Add `_WorkoutSection` widget to `settings_screen.dart` with a toggle row
- Guard `_showFeelingSheet()` in `session_summary_screen.dart`

### Implementation Steps

#### Phase 1: State Layer
1. [x] Add `static const String _showFeelingSurveyKey = 'show_feeling_survey';` to `SettingsState`
2. [x] Add `bool _showFeelingSurvey = true;` backing field and `bool get showFeelingSurvey` getter
3. [x] Add `setShowFeelingSurvey(bool value)` async method — stores `value.toString()` via `setPreferenceString`, calls `notifyListeners()`
4. [x] Load in `_loadFromPrefs()`: read the key, parse as bool (`== 'true'`), default `true`

#### Phase 2: Settings UI
5. [x] Add `_WorkoutSection` widget in `settings_screen.dart` following the same `OmniSurface` + `_SectionHeader` + `_SettingsRow` pattern
6. [x] Row: label `'Feeling Survey'`, subtitle `'Ask how the workout felt after finishing'`, trailing = `Switch` bound to `settingsState.showFeelingSurvey`
7. [x] Insert section between SOUNDS & ALERTS and APPEARANCE in the `ListView`

#### Phase 3: Session Summary Guard
8. [x] In `_showFeelingSheet()` in `session_summary_screen.dart`, add guard at the top: `if (!widget.settingsState.showFeelingSurvey) return;`

## Progress
- [x] Add `showFeelingSurvey` to SettingsState
- [x] Add `_WorkoutSection` to settings_screen.dart
- [x] Guard `_showFeelingSheet` with the setting

### Phase 2 Complete ✓
Implementation done. All focused Phase 0 tests green. Ready for Code Reviewer.

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->
