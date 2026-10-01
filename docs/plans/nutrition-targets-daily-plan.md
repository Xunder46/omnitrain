# Feature: Daily Nutrition Targets

## Overview

Extend the nutrition feature to support daily-configurable targets that:
- Roll over each day but allow user edits (forward-looking changes only)
- Preserve historical values (if changed today, only today and future days get new targets)
- Store as 0 (not nullable) when unset; UI hides 0 targets showing "no goal"
- Integrate seamlessly with the existing NutritionState
- Navigate from the nutrition screen (opened via home strip button) to the targets screen

This is a continuation of the nutrition feature, building on the existing NutritionTarget model and NutritionState.

## Clarifying Questions & Answers

1. **Persistence Strategy**: Preserve historical ones, but if changed only future days inherit from today (forward-looking changes only).
   - When a user edits a target, only today and future days inherit the new value; past days retain their original values.

2. **Day Rollover**: They roll over but users can change them if needed.
   - Daily targets are carried forward to the next day; users can modify them on any day independently.

3. **Blank/Null Handling**: Store as 0 (not nullable); 0 = not set. Hide 0 targets in UI (show "no goal").
   - Update NutritionTarget model to use non-nullable doubles (default 0.0).
   - UI displays "no goal" or hides the target line when the value is 0.

4. **Entry Point Navigation**: The nutrition screen that opens via the home screen strip button; the targets screen is the next screen after the nutrition screen (accessed via button/navigation from nutrition screen).
   - Create a new NutritionScreen (if not already present) that displays daily nutrition summary and consumed foods.
   - Add a button/link in NutritionScreen to navigate to NutritionTargetScreen.

5. **Unit Test Scope**: Mock the repository layer; test state reload (unit test, not integration).
   - Write unit tests for NutritionState using MockWorkoutRepository.
   - Test day rollover logic, target changes, and state reload.

6. **Relatedness to Existing Work**: Yes, this is the continuation of the nutrition feature — integrate with existing NutritionState.
   - Extend NutritionState to manage daily-scoped targets.
   - Keep the repository interface stable; all changes are implementation-level.

## Scenarios

### S-001: First Load Today (Targets Unset or From Yesterday)
- Trigger: User opens the nutrition screen for the first time on 2026-06-07
- Precondition: No nutrition targets have been set; or targets from 2026-06-06 exist and should roll over
- Flow: 
  1. User taps the nutrition strip button on home screen
  2. NutritionScreen loads and calls `loadNutritionTargetForDate(2026-06-07_ms)`
  3. If no target exists for 2026-06-07, repository walks backward to find ancestor (2026-06-06)
  4. Ancestor target is returned and displayed
  5. User sees "no goal" or hidden targets if all values are 0
- Expected outcome: Nutrition screen displays rolled-over targets from yesterday (or all "no goal" if none exist). Target fields show latest available values.
- Edge case of: none

### S-002: Edit and Save All Four Target Fields
- Trigger: User navigates to NutritionTargetScreen and fills all four fields
- Precondition: NutritionTargetScreen is open; target values loaded (0 or rolled-over)
- Flow:
  1. User enters: calories=2500, protein=150, carbs=300, fat=80
  2. All four fields are populated (non-zero)
  3. User taps "Save"
  4. NutritionState calls `saveNutritionTargetForDate(2026-06-07_ms, NutritionTarget(...))`
  5. Repository saves for today and forward-propagates unchanged values to future dates
  6. NutritionTargetScreen pops back to NutritionScreen
- Expected outcome: Today's (2026-06-07) target is saved with all four values. Future dates (2026-06-08, 2026-06-09, ...) inherit the new values unless explicitly changed.
- Edge case of: none

### S-003: Clear a Target Field and Save (Store as 0.0)
- Trigger: User opens NutritionTargetScreen with existing targets, clears one field, and saves
- Precondition: NutritionTargetScreen shows target with calories=2500, protein=150, carbs=300, fat=80 (all set)
- Flow:
  1. User clears the "carbs" field (empties it or sets to 0)
  2. Fields now: calories=2500, protein=150, carbs=<empty or 0>, fat=80
  3. User taps "Save"
  4. NutritionState calls `saveNutritionTargetForDate(2026-06-07_ms, NutritionTarget(calories: 2500, protein: 150, carbs: 0.0, fat: 80))`
  5. Repository saves the target with carbs=0.0 (not null)
  6. Back on NutritionScreen, carbs target line is hidden or shows "no goal"
- Expected outcome: Target is saved with carbs=0.0. UI gracefully hides the 0 value (no "NaN", no division errors). Future dates inherit carbs=0.0 unless explicitly changed.
- Edge case of: none

### S-004: Day Rollover Across Midnight (Targets Carry Forward)
- Trigger: Date changes from 2026-06-07 to 2026-06-08 (e.g., user's device time rolls past midnight)
- Precondition: User has set targets for 2026-06-07 (calories=2500, protein=150, carbs=300, fat=80)
- Flow:
  1. User has app open on 2026-06-07 with targets set
  2. System time advances past midnight → 2026-06-08 00:00:00
  3. App detects date change and calls `rolloverToDate(2026-06-08_ms)`
  4. NutritionState (or repository) checks if 2026-06-08 target exists; if not, fetches 2026-06-07's target and propagates
  5. User opens nutrition screen on 2026-06-08
  6. Targets from 2026-06-07 are displayed for 2026-06-08
- Expected outcome: Targets automatically roll over to the new day. User sees the same targets (calories=2500, protein=150, carbs=300, fat=80) on 2026-06-08. No user action required.
- Edge case of: none

### S-005: Display Zero Targets as "No Goal" (Not "0")
- Trigger: User is viewing NutritionScreen with unset targets (0.0 values)
- Precondition: Current target has calories=0, protein=0, carbs=0, fat=0 (all unset)
- Flow:
  1. NutritionScreen loads target with all 0 values
  2. NutritionSummaryCard (or equivalent UI) is rendered
  3. For each macro (calories, protein, carbs, fat) with value 0, UI checks `if (target.value == 0) { display "no goal" or hide row }`
  4. User sees a clean, simple view with "no goal" labels or hidden rows (no "0" numerals)
- Expected outcome: UI displays "no goal" for each 0 target. No empty cells, no division-by-zero errors, no "NaN" or "-Infinity". Layout is clean and intentional.
- Edge case of: none

### S-006: Navigate from Nutrition Screen to Targets Setup and Back
- Trigger: User is on NutritionScreen and taps "Edit Targets" button
- Precondition: NutritionScreen is displayed with today's targets (rolled over or previously set)
- Flow:
  1. User taps "Edit Targets" button on NutritionScreen
  2. App navigates to NutritionTargetScreen
  3. NutritionTargetScreen loads `getTodayTarget()` and populates form fields
  4. User makes edits (e.g., changes calories from 2500 to 2600)
  5. User taps "Save"
  6. Repository saves the change
  7. NutritionTargetScreen pops back to NutritionScreen
  8. NutritionScreen reloads targets and displays updated values
- Expected outcome: Navigation flow is smooth. NutritionScreen displays updated targets after edit. No data loss or refresh errors. Back navigation is clean.
- Edge case of: none

### S-007: Forward-Propagation Rule (Edit Today, Yesterday Unaffected)
- Trigger: User edits targets while yesterday's targets are cached or recently viewed
- Precondition: User previously viewed targets for 2026-06-06 (calories=2000, protein=120, carbs=250, fat=70). Today is 2026-06-07 with rolled-over targets (same values). User opens targets for today and edits.
- Flow:
  1. On 2026-06-07, user opens NutritionTargetScreen
  2. Today's target is loaded (rolled-over from 2026-06-06): calories=2000, protein=120, carbs=250, fat=70
  3. User edits to: calories=2500, protein=150, carbs=300, fat=80
  4. User taps "Save"
  5. NutritionState calls `saveNutritionTargetForDate(2026-06-07_ms, new_target)`
  6. Repository saves for 2026-06-07 and propagates to 2026-06-08, 2026-06-09, etc.
  7. Repository does NOT modify 2026-06-06's target (still calories=2000, protein=120, carbs=250, fat=70)
  8. If user later navigates back to view 2026-06-06, they see original values
- Expected outcome: Past dates (2026-06-06) retain original targets unchanged. Only today (2026-06-07) and future dates inherit the new values. Historical accuracy is preserved.
- Edge case of: S-004 (day rollover couples with forward-propagation rule)

## Architecture & Data Model

### Target Persistence Model (Day-Based Storage)

Currently, NutritionTarget is a single global object (one target set, used everywhere). To support day-based targets with forward-only updates:

1. **Data Model Change**: 
   - Modify NutritionTarget to store non-nullable doubles (default 0.0) instead of nullable.
   - Add a date field (or timestamp) to track which day a target set is for.
   - Consider adding a `createdAtMs` or `dateMs` field to mark the day the target was set.

2. **Repository Interface Extension**:
   - Add `getNutritionTargetForDate(int dateMs)` → returns target for that specific date
   - Add `saveNutritionTargetForDate(int dateMs, NutritionTarget target)` → saves for that date and propagates to future dates
   - Keep legacy `getNutritionTarget()` and `saveNutritionTarget()` for backwards compatibility (operates on "today's" target)

3. **Storage Implementation** (HiveWorkoutRepository & MockWorkoutRepository):
   - Store targets in a map keyed by date (YYYYMMDD string or milliseconds since epoch).
   - When fetching a target for a date, if not found, walk backward to find the most recent ancestor target, then forward-propagate changes.
   - Example storage shape: `{ "20260607": NutritionTarget(...), "20260608": NutritionTarget(...) }`

### State Model (NutritionState Integration)

Extend NutritionState with day-aware operations:

1. **New fields**:
   - `_selectedDate` → current date being viewed (default: today)
   - `_targetsByDate` → cache of target objects fetched/edited

2. **New methods**:
   - `loadNutritionTargetForDate(int dateMs)` → loads target for a specific date
   - `saveNutritionTargetForDate(int dateMs, NutritionTarget target)` → saves and propagates forward
   - `rolloverToDate(int dateMs)` → internal method to handle day transitions
   - `getTodayTarget()` → convenience for current day

3. **Automatic day rollover**:
   - When the app detects a date change (e.g., from 20260606 to 20260607), automatically call rolloverToDate.
   - This can be handled in the app shell or HomeScreen's initState.

### UI Integration (NutritionScreen & Navigation)

1. **NutritionScreen** (new or enhanced):
   - Displays today's consumed nutrition summary.
   - Shows today's targets (0 values displayed as "no goal").
   - Has a button to navigate to NutritionTargetScreen.

2. **NutritionTargetScreen** (existing):
   - Populated with today's target values at load time.
   - Save writes to today's target and propagates forward.
   - Update to store 0 when fields are cleared (not null).

## Implementation Phases

### Phase 1: Data Layer (DBA)

1. [x] **Update NutritionTarget model**:
   - Changed `calories`, `protein`, `carbs`, `fat` from `double?` to `double` (default 0.0)
   - Added optional `dateMs` field (int?)
   - Updated `fromMap()` and `toMap()` to handle date and ensure 0 defaults
   - Added `isUnset` getter to check if all macros are 0

2. [x] **Extend WorkoutRepository interface**:
   - Added `Future<NutritionTarget?> getNutritionTargetForDate(int dateMs);`
   - Added `Future<void> saveNutritionTargetForDate(int dateMs, NutritionTarget target);`
   - Kept `getNutritionTarget()` / `saveNutritionTarget()` for backwards compatibility (delegates to "today")

3. [x] **Implement in HiveWorkoutRepository**:
   - Created Hive box `'nutrition_targets_by_date'` for date-keyed targets
   - Implemented `getNutritionTargetForDate(dateMs)`: walks backward 24h at a time to find ancestor
   - Implemented `saveNutritionTargetForDate(dateMs, target)`: saves and forward-propagates unchanged values
   - Updated legacy methods to call date-aware methods with `_getTodayMs()`

4. [x] **Implement in MockWorkoutRepository**:
   - Added `Map<int, NutritionTarget> _nutritionTargetsByDate` for in-memory storage
   - Mirrored HiveWorkoutRepository logic with same backward-walk and forward-propagation
   - Added `_getTodayMs()` helper for today's midnight timestamp

5. [x] **Update Hive migrations**:
   - Added `_migrateDailyNutritionTargets()` migration
   - Converts legacy nullable fields to non-nullable with 0.0 defaults
   - Creates new `'nutrition_targets_by_date'` box on first install

6. [x] **Update sqlite_schema.sql**:
   - Updated `app_nutrition_target` table with: `id`, `date_ms` (UNIQUE), `calories`, `protein`, `carbs`, `fat` (all REAL NOT NULL DEFAULT 0.0), `created_at_ms`, `updated_at_ms`
   - Added index on `date_ms DESC` for fast date lookups
   - Added comprehensive documentation and forward-propagation rules

### Phase 2: Logic/UI (Developer)

1. [ ] **Extend NutritionState**:
   - Add `_selectedDate` and `_targetsByDate` cache.
   - Implement `loadNutritionTargetForDate(int dateMs)`.
   - Implement `saveNutritionTargetForDate(int dateMs, NutritionTarget target)`.
   - Add internal `_rolloverToDate(int dateMs)` for day transitions.
   - Add `getTodayTarget()` convenience method.
   - Update `loadNutritionTarget()` to call date-aware method with today's date.
   - Update `saveNutritionTarget()` to call date-aware method with today's date.

2. [ ] **Create/enhance NutritionScreen**:
   - Display today's consumed nutrition (if logging exists; stub for now).
   - Show today's targets from NutritionState.
   - Render 0 values as "no goal" (do not show empty cells or division errors).
   - Add button/link to navigate to NutritionTargetScreen.

3. [ ] **Update NutritionTargetScreen**:
   - Load `getTodayTarget()` on init.
   - When saving, call `saveNutritionTargetForDate(today, target)` (which propagates forward).
   - Handle empty fields as 0.0 (not null).
   - Post-save, pop back to NutritionScreen.

4. [ ] **Add day-rollover detection in App shell or HomeScreen**:
   - Check on every app resume or at midnight if the date has changed.
   - If date changed, call `nutritionState.rolloverToDate(newDateMs)`.

5. [ ] **Update NutritionSummaryCard** (if exists):
   - Use NutritionState targets instead of hardcoded values.
   - Display "no goal" for 0 targets.

6. [ ] **Navigation wiring**:
   - Home screen strip button → NutritionScreen.
   - NutritionScreen "Edit Targets" button → NutritionTargetScreen.
   - NutritionTargetScreen back button → NutritionScreen.

### Phase 3: Testing

1. [ ] **Unit tests for NutritionState**:
   - Test `loadNutritionTargetForDate(dateMs)` loads correct target.
   - Test `saveNutritionTargetForDate(dateMs, target)` saves and propagates forward.
   - Test that past dates are unaffected by future edits.
   - Test `getTodayTarget()` returns today's target.
   - Test day-rollover logic (transition from day N to day N+1).
   - Mock MockWorkoutRepository for all tests.

2. [ ] **Widget tests for UI**:
   - Test NutritionScreen renders targets correctly.
   - Test NutritionTargetScreen loads and saves targets.
   - Test that 0 values are displayed as "no goal" (not empty or NaN).
   - Test navigation from NutritionScreen → NutritionTargetScreen.

3. [ ] **Integration/acceptance test**:
   - User sets targets on day N.
   - Day rolls over to N+1.
   - Targets are still present (rolled over).
   - User edits targets on day N+1.
   - Past target (day N) is unchanged; day N+1 and future inherit new values.

## Critical Decisions

1. **Forward-only updates**: When a user edits a target, changes propagate only to today and future dates. Historical values in the past are never modified.

2. **0 = Not Set**: All four fields (calories, protein, carbs, fat) default to 0.0. A value of 0 is treated as "unset" in the UI (shown as "no goal" or hidden).

3. **UI Graceful Degradation**: If a target is 0, the UI does not show it, does not attempt division-by-zero calculations, and does not display "NaN" or errors.

4. **Day Rollover Mechanics**: Targets from day N are automatically copied to day N+1 unless the user has already set different targets for N+1. Day boundaries are defined by wall-clock date (start of day in local timezone, or UTC if specified).

5. **Repository Abstraction**: All date-keyed logic lives in the repository implementation; state and UI only see the public interface.

6. **Backwards Compatibility**: Existing code using `getNutritionTarget()` and `saveNutritionTarget()` continues to work without changes (delegates to "today's" date internally).

## Progress Checklist

- [x] Phase 1 Data Layer (@dba) — Models, repository interface, Hive/Mock implementations, migrations, SQLite schema **Complete**
- [ ] Phase 2 Logic/UI (@developer) — State methods, screens, day rollover, navigation, UI updates
- [ ] Phase 3 Testing (@developer) — Unit tests, widget tests, integration tests

## Next Recommended Handoff

**@dba** — Please proceed with Phase 1 (Data Layer) above.

Focus on:
1. Updating NutritionTarget model to use non-nullable doubles with default 0.0
2. Adding dateMs field for day tracking
3. Extending WorkoutRepository with date-aware methods
4. Implementing both Hive and Mock repositories with forward-propagation logic
5. Preparing SQLite schema for future implementation

Return to Conductor when Phase 1 is complete for review before Phase 2 (@developer) begins.

---

## Feedback (Code Review — @code-reviewer)

**Date**: 2026-06-07
**Verdict**: ❌ **Critical issues block merge.** Phase 1 and Phase 2 implementation are present and architecturally correct, but Phase 3 is incomplete, two existing tests are stale and break the build, and the Buttons rule is violated in both nutrition screens.

### ✅ What matches the plan
- Phase 1 (DBA) is complete: `NutritionTarget` model (`lib/data/models/models.dart:1626`), date-aware repository interface (`workout_repository.dart:394-410`), Hive + Mock implementations with backward-walk + forward-propagation (`hive_workout_repository.dart:680-746`, `mock_workout_repository.dart:1347-1417`), Hive migration (`_migrateDailyNutritionTargets`), and SQLite schema (`scripts/sqlite_schema.sql:1080-1103`).
- Phase 2 (Developer) implementation is present: `NutritionState` (`lib/state/nutrition_state.dart`), `NutritionScreen` (`lib/features/nutrition/nutrition_screen.dart`), `NutritionTargetScreen` (`lib/features/nutrition/nutrition_target_screen.dart`), `NutritionSummaryCard` (`lib/features/nutrition/widgets/nutrition_summary_card.dart`), day-rollover detection in `HomeScreen._checkAndHandleDateRollover` (`lib/features/home/home_screen.dart:146-155`), DI wiring in `main.dart`.

### 🔴 CRITICAL — Must fix before merge

#### C1. Stale tests fail to compile (CI breaker)
**Files**:
- `test/nutrition_test.dart:53, 78, 101` — `NutritionTargetScreen()` and `NutritionSummaryCard()` are now `const` constructors that require `nutritionState`, but the test still calls them as bare const.
- `test/home_nutrition_strip_test.dart:62` — `HomeScreen(...)` now requires `nutritionState`, but the helper still builds it without that arg.

**Fix**: Update both test files to pass `nutritionState: NutritionState(mockRepository)` (or the existing instance) to the relevant constructors.

**Recommend**: @developer

#### C2. Buttons rule violation (Material 3 default `StadiumBorder`)
**Files**:
- `lib/features/nutrition/nutrition_screen.dart:90` — "Edit Targets" `FilledButton` has no `shape:` override.
- `lib/features/nutrition/nutrition_target_screen.dart:240` — "Save" `FilledButton` has no `shape:` override.

Both also wrap the button in `SizedBox(width: double.infinity)` only — missing the `OmniTheme.buttonPrimaryHeight` height token required by the convention.

**Fix**: Apply the standard pattern:
```dart
FilledButton(
  style: ButtonStyle(
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OmniTheme.buttonPrimaryRadius),
      ),
    ),
  ),
  onPressed: ...,
  child: const Text('Edit Targets'),
)
```
Wrap in `SizedBox(width: double.infinity, height: OmniTheme.buttonPrimaryHeight)`.

**Recommend**: @developer

### 🟡 WARNING — Should fix

#### W1. Unused field `_selectedDate` (`nutrition_state.dart:17`)
Analyzer warning: field is assigned but never read. It is reset to today on every `loadNutritionTargetForDate` call, so it does not represent "currently viewed date" as the field name implies.

**Fix options**:
- Remove the field (current behaviour never needs it), **or**
- Wire it to a "view another day" feature and update it on every load.

**Recommend**: @developer

#### W2. Double `@override` annotation (`hive_workout_repository.dart:679`)
Cosmetic but obviously broken-looking; remove the second `@override`.

**Recommend**: @developer

#### W3. Duplicated `_getTodayMs()` in both repositories
`hive_workout_repository.dart:763` and `mock_workout_repository.dart:1418` have identical local-midnight logic. Extract to a single helper (e.g., `lib/core/utils/date_utils.dart` as `todayMidnightMs()`) and reuse.

**Recommend**: @developer

#### W4. Silent exception swallow in `NutritionState` (`nutrition_state.dart:43, 56, 71`)
All three async methods wrap calls in `try { ... } catch (e) { _nutritionTarget = null; }`. There is no `_error` field on the state and no UI surface for failures. The plan did not require error UI, but this should be flagged as a follow-up so users aren't told "no goals set" when the call actually failed.

**Recommend**: @developer (track as follow-up)

#### W5. Hub sheet routes "Nutrition" → `NutritionTargetScreen` (`lib/widgets/hub/hub_sheet.dart:71-79`)
Per plan clarification #4, the canonical nutrition entry is `NutritionScreen` (consumed summary) with a button to `NutritionTargetScreen`. The Hub still skips the summary and goes straight to the edit form. Both entry points (strip button, hub) should land on the same first screen.

**Recommend**: @developer

#### W6. `NutritionSummaryCard` shows progress bars with `consumed = 0` (`nutrition_summary_card.dart`)
Hardcoded `0` for the consumed value with a `// TODO` comment is now visible in production UI. Either show only the target value (e.g., "Goal: 2500 cal") until consumption logging exists, or explicitly label the row as "0 / 2500".

**Recommend**: @developer

### 🧪 Test coverage gaps (Phase 3 not delivered)

The plan required unit, widget, and integration tests for the new behaviour. Current state:

- `nutrition_test.dart` exists but is broken (see C1). When fixed, it only covers: fromMap/toMap round-trip, save+reload, target screen save, summary card empty/non-empty states. **Missing**: rollback, day-rollover, forward-propagation rule, S-001..S-007 scenario outcomes.
- `home_nutrition_strip_test.dart` is broken (see C1).
- No tests for `getNutritionTargetForDate` / `saveNutritionTargetForDate` on either `MockWorkoutRepository` or `HiveWorkoutRepository`.
- No `NutritionState` tests in `test/state_test.dart` (no `loadNutritionTargetForDate` / `saveNutritionTargetForDate` / `getTodayTarget` / `rolloverToDate` coverage).
- No `NutritionTarget` model tests in `test/models_test.dart` (the existing `nutrition_test.dart` fromMap test should be moved to `models_test.dart` per the test-file map).
- No `NutritionScreen` render test in `test/screen_widget_test.dart`.
- No `NutritionScreen → NutritionTargetScreen` navigation test in `test/interaction_flow_test.dart`.
- No edge cases in `test/edge_case_test.dart` (e.g., backward-walk through many empty days, forward-propagation across pre-existing different future targets).

**Recommend**: @developer

### 🟢 SUGGESTIONS — Nice to have

- S1. The legacy `NutritionTarget.dateMs` field is always `null` in legacy `get/saveNutritionTarget` calls; document that explicitly in the model doc comment to avoid future confusion.
- S2. Consider documenting the date-keyed storage contract in `lib/data/repositories/workout_repository.dart` with a short example.

### 📝 Doc Updates (Step 5c)

None of the relevant docs were updated to reflect this feature:

- `docs/navigation_and_screens.md` — still says the strip routes to `MaintenancePlaceholderScreen`; should say `NutritionScreen` → `NutritionTargetScreen`.
- `docs/state_management.md` — `NutritionState` is not in the State Classes section; new methods are undocumented.
- `docs/widget_catalog.md` — `NutritionSummaryCard` is not listed.
- `docs/data_models.md` — `NutritionTarget` model is not documented.
- `docs/db_integration.md` — date-aware methods and forward-propagation rule are not described; the schema comment is the only narrative.

**Recommend**: @developer (navig/state/widget) and @dba (models/db)

### 🌐 Global Conventions verification

| Rule | Status | Evidence |
|---|---|---|
| Units + canonical storage | **N/A** | Nutrition targets are dimensionless counts; not applicable. |
| Theme tokens only | **PASS** | `NutritionSummaryCard` uses `Theme.of(context).textTheme`; `NutritionStripButton` uses `OmniTheme.colors`. |
| Effort-kind drives analytics | **N/A** | No analytics in this feature. |
| Timestamps are source data | **PASS** | All date math uses `DateTime.now()` and persisted `int` ms-since-epoch. |
| Reuse the canonical owner | **PASS** | Day logic and storage delegated to repository; state and UI do not duplicate it. |
| Instrument panel, not influencer | **PASS** | UI is restrained: zero values hidden, no progress theatre. |

### Recommendation

**Do not merge.** Required fixes:
1. C1: Update `nutrition_test.dart` and `home_nutrition_strip_test.dart` to compile (CI).
2. C2: Apply `shape:` overrides + `OmniTheme.buttonPrimaryHeight` to both `FilledButton`s in nutrition screens.
3. W1–W6 + Test gaps + Doc updates: address before next review iteration.
