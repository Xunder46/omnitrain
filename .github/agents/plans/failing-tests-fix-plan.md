# Feature: Fix Failing Unit Tests (6 failures)

## Overview
Six tests are failing after recent UI/UX changes. Three categories of failures, all requiring test updates or narrow layout fixes. No schema changes, no new state methods, no new screens.

## Requirements
- All 678 tests should pass
- No behavioral regressions

## Acceptance Criteria
- [x] `flutter test` exits with 0 failures
- [x] S-002, S-003, S-004, S-005 tests correctly reflect the "Start" button behavior
- [x] S-019 test no longer asserts "Previous: —" (empty string is now correct)
- [x] Unsaved dialog test passes with no overflow at 280px viewport

## Analysis

### Root causes confirmed

**Category 1 — S-002, S-003, S-004, S-005 (session_toolbar_rework_test.dart)**
- Tests expect a `FilledButton` labeled "Log Interval" / "Log Round" / "Log Period" / "Log Hold" to appear immediately when a timed/round/drill exercise is added.
- Code changed: `_isTimerEntryNotStarted()` now shows a **"Start"** button first for timer-based exercises (timed, round, drill) that have never been started. The log button only appears after starting.
- **Fix**: Update these 4 tests to expect `FilledButton` with text `'Start'` instead of the specific log labels.

**Category 2 — S-019 (session_toolbar_rework_test.dart)**
- Test expects `find.textContaining('Previous: —')` when set 1 is never logged.
- Code: when `!isPreviousLogged`, `statsText = ''` (empty). No "—" fallback shown. 
- User confirmed: show nothing is the intended behavior.
- **Fix**: Remove/update the `expect(find.textContaining('Previous: —'), findsOneWidget)` assertion. Either assert `findsNothing` or assert the banner is absent.

**Category 3 — Unsaved dialog overflow (unsaved_changes_dialog_test.dart)**
- Test renders the screen at 280×700 logical pixels, navigates to the session detail view, adds a set, then backs out to trigger the "Unsaved changes" dialog.
- `tester.takeException()` catches an 8px right-side overflow.
- The dialog layout itself is unchanged. The overflow originates from `workout_session_detail_view.dart` which was heavily refactored in commit `4283561` ("adjust layout spacing for active session detail and list views"). The detail view is rendered at 280px *before* the dialog appears.
- **Fix**: Identify the element in `workout_session_detail_view.dart` that overflows at 280px (likely a fixed-width widget or a Row with insufficient shrink behavior) and make it flex-safe. Do NOT raise the test viewport — 280px is a real phone width (e.g., certain Android devices at 1x DPR).

## Implementation Plan

### Phase 1: Test Updates (@developer)
**File**: `test/session_toolbar_rework_test.dart`

1. [ ] S-002 (line ~112): Change `expect(find.widgetWithText(FilledButton, 'Log Interval'), findsOneWidget)` → `expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget)`
2. [ ] S-003 (line ~131): Change `expect(find.widgetWithText(FilledButton, 'Log Round'), findsOneWidget)` → `expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget)`
3. [ ] S-004 (line ~150): Change `expect(find.widgetWithText(FilledButton, 'Log Period'), findsOneWidget)` → `expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget)`
4. [ ] S-005 (line ~167): Change `expect(find.widgetWithText(FilledButton, 'Log Hold'), findsOneWidget)` → `expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget)`
5. [ ] S-019 (line ~486): Remove or replace `expect(find.textContaining('Previous: —'), findsOneWidget)` — assert that no "Previous:" banner is shown (use `findsNothing` on `find.textContaining('Previous:')`)

### Phase 2: Layout Fix (@developer)
**File**: `lib/features/session/workout_session_detail_view.dart`

6. [ ] Reproduce the overflow by running only the failing test: `flutter test test/unsaved_changes_dialog_test.dart --name "overflow"`
7. [ ] Identify the overflowing widget. Candidates from the recent spacing commit: fixed-width Rows, non-shrinkable Columns, hardcoded SizedBox widths that don't flex at narrow widths.
8. [ ] Apply a flex-safe fix (e.g., wrap in `Flexible`, use `LayoutBuilder`, or replace fixed widths with `double.infinity` inside `Expanded`).
9. [ ] Verify `flutter test test/unsaved_changes_dialog_test.dart` passes.

### Phase 3: Final validation (@developer)
10. [ ] Run `flutter test` — confirm 0 failures across all 678+ tests.

## Files Affected
- `test/session_toolbar_rework_test.dart` — 5 assertion changes
- `lib/features/session/workout_session_detail_view.dart` — layout flex fix for narrow widths

## Notes
- The "Start" → "Log X" two-step flow for timer exercises is now the canonical UX. Any future tests for timed/round/drill exercises should account for this initial state.
- The "Previous: —" UX was removed. When there is no prior logged set, the previous stats banner should simply be absent. Tests should assert `findsNothing` on that text to guard against regression.
- Fast-track eligible: no new user-facing behavior, no schema changes, no new state methods — skip Conductor and open Developer directly for this one.

## Progress
- [x] S-002 test assertion updated
- [x] S-003 test assertion updated
- [x] S-004 test assertion updated
- [x] S-005 test assertion updated
- [x] S-019 test assertion updated
- [x] Detail view overflow identified and fixed
- [x] All tests pass

## Feedback

### Phase Complete ✓
Logic/UI updates validated. All tests passing.
