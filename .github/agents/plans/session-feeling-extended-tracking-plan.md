# Feature: session-feeling-extended-tracking

## Overview
Upgrade the training/session data layer to support richer analytics fields and add a first-load Session Feeling modal on Session Summary that persists a 1-5 feeling score immediately on selection.

## Requirements
- Add nullable `sessionFeeling` to `TrainingSession` model and persistence layers.
- Add nullable `qualityRating` to `TrainingSession` model and persistence layers.
- Add nullable `rpeRating` to `EffortObservation` model and persistence layers.
- Add nullable `restDurationMs` to `EffortObservation` model and persistence layers.
- Update SQLite schema idempotently: only add columns if missing.
- Ensure Hive/mock repository read/write paths include new session fields.
- Add repository API `updateSessionFeeling(String sessionId, int feeling)` if missing.
- Add migration marker key `session_feeling_fields_migrated_v1` following existing migration pattern.
- Add Session Feeling modal on initial Session Summary load with non-dismissible behavior and immediate persist-on-tap.
- Do not change existing Session Summary layout beyond modal trigger/wiring.

## Iteration 1

## Analysis
Request spans both data and UI:
1. Data/model/schema additions are backward-compatible nullable fields, requiring map serialization updates and repository contract updates.
2. Persistence must be dual-environment safe (current Hive/mock-backed flow now, SQLite-ready schema for production path).
3. UI asks for a focused modal interaction only on Session Summary first load, with strict non-dismissible behavior and immediate save.

## Questions (if any)
1. Should the feeling sheet display every time Session Summary opens until feeling is set, or exactly once per screen load regardless of existing value?
2. If a session already has `sessionFeeling`, should the sheet still auto-open and allow overwrite, or skip showing entirely?

## Implementation Plan

### Phase 1: Data Layer (@dba)
1. [ ] Inspect current models/repository/schema for existing `sessionFeeling`, `qualityRating`, `rpeRating`, and `restDurationMs`; skip duplicates silently.
2. [ ] Update `TrainingSession` model in `lib/data/models/models.dart`:
3. [ ] Add nullable `int? sessionFeeling` with 1-5 comment.
4. [ ] Add nullable `int? qualityRating` with future-computed comment.
5. [ ] Ensure constructor, `fromMap`, `toMap`, and `copyWith` include both fields.
6. [ ] Update `EffortObservation` model in `lib/data/models/models.dart`:
7. [ ] Add nullable `int? rpeRating` with 1-10 comment.
8. [ ] Add nullable `int? restDurationMs` with ms comment.
9. [ ] Ensure constructor, `fromMap`, `toMap`, and `copyWith` include both fields.
10. [ ] Update `scripts/sqlite_schema.sql` idempotently:
11. [ ] Add `session_feeling INTEGER` to `app_training_session` if absent.
12. [ ] Add `quality_rating INTEGER` to `app_training_session` if absent.
13. [ ] Add `rpe_rating INTEGER` to `app_effort_observation` if absent.
14. [ ] Add `rest_duration_ms INTEGER` to `app_effort_observation` if absent.
15. [ ] Add inline SQL comments describing nullable/future-use semantics.
16. [ ] Update repository contract in `lib/data/repositories/workout_repository.dart`:
17. [ ] Add `Future<void> updateSessionFeeling(String sessionId, int feeling);` if missing.
18. [ ] Update both repository implementations:
19. [ ] `lib/data/repositories/hive_workout_repository.dart` (current persistent runtime)
20. [ ] `lib/data/repositories/mock_workout_repository.dart` (web-compatible in-memory)
21. [ ] Ensure session map read/write includes `sessionFeeling` and `qualityRating`.
22. [ ] Implement `updateSessionFeeling` with safe lookup and persistence write-through.
23. [ ] Add/extend migration routine in Hive initialization:
24. [ ] Add migration note comment for nullable no-op behavior.
25. [ ] Add meta key `session_feeling_fields_migrated_v1` patterned after existing migration keys.
26. [ ] Keep migration idempotent and non-destructive.

### Phase 2: Logic/UI (@developer)

#### SessionSummaryScreen changes

1. [ ] In `SessionSummaryScreen` State's `initState()`, after existing initialization logic, add:
   ```dart
   WidgetsBinding.instance.addPostFrameCallback((_) {
     final session = widget.workoutState.currentSession;
     if (session != null && session.sessionFeeling == null) {
       _showFeelingSheet(context);
     }
   });
   ```
   Do not modify any other part of `initState` or the existing build method.

2. [ ] Add private method `_showFeelingSheet(BuildContext context)` to SessionSummaryScreen State:
   - Call `showModalBottomSheet` with:
     - `isDismissible: false`
     - `enableDrag: false`
     - `backgroundColor: Colors.transparent`
     - `barrierColor: Colors.black54`
     - `isScrollControlled: true`
     - `builder: (context) => _FeelingSheetContent(workoutState: widget.workoutState, modality: widget.workoutState.currentSession?.modality)`

#### _FeelingSheetContent StatefulWidget

3. [ ] Create private `StatefulWidget` class `_FeelingSheetContent` in same file. Constructor accepts:
   - `WorkoutState workoutState`
   - `String? modality`

4. [ ] State class local state: `int? _selectedFeeling`

5. [ ] In `build()`, construct outer container:
   - `Container` with:
     - `decoration: BoxDecoration(color: Color(0xFF1A1F2E), borderRadius: BorderRadius.vertical(top: Radius.circular(20)))`
     - `padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).padding.bottom + 40)`
     - Child: `Column(mainAxisSize: MainAxisSize.min, children: [...])`

6. [ ] Build Column stack (top to bottom):

   **6a. Handle bar** (centered, 28px bottom margin):
   - `SizedBox(width: 36, height: 4, child: Container(decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))))`

   **6b. Title** (6px bottom margin, centered):
   - `Text("How did it feel?", style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white.withOpacity(0.9)), textAlign: TextAlign.center)`

   **6c. Subtitle** (36px bottom margin, centered):
   - Resolve modality to display name via `ModalityDisplay.displayName(modality)` or equivalent utility.
   - If modality is null, use `'Free Training'`.
   - `Text("$displayName · Today", style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4)), textAlign: TextAlign.center)`

   **6d. Number tiles row** (5 equal tiles, 1–5 numbers):
   - `Row(children: [for (int i = 1; i <= 5; i++) ...[Expanded(child: _buildFeelingTile(i)), if (i < 5) SizedBox(width: 10)]])`
   - Delegate tile building to `_buildFeelingTile(int number)` method (see step 7).

   **6e. Range labels row** (10px top margin):
   - `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, padding: EdgeInsets.symmetric(horizontal: 4), children: [Text("Rough", style: TextStyle(fontSize: 11, letterSpacing: 1.0, color: Colors.white.withOpacity(0.25))), Text("Great", style: TextStyle(fontSize: 11, letterSpacing: 1.0, color: Colors.white.withOpacity(0.25)))])`

7. [ ] Implement `_buildFeelingTile(int number)` helper method in State:
   - Returns `GestureDetector` with `onTap: () => _selectFeeling(number)`
   - Child: `AspectRatio(aspectRatio: 1.0, child: AnimatedContainer(...))`
   - AnimatedContainer:
     - `duration: Duration(milliseconds: 150)`
     - Unselected: `decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5), borderRadius: BorderRadius.circular(14))`
     - Selected: `decoration: BoxDecoration(color: accentColor, border: Border.all(color: accentColor, width: 1.5), borderRadius: BorderRadius.circular(14))`
     - Child: centered `Text(number.toString(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: _selectedFeeling == number ? Colors.white : Colors.white.withOpacity(0.35)))`
   - Compute `accentColor` once in build as: `ModalityColors.forModality(widget.modality)` (store as local var for reuse).

8. [ ] Implement `_selectFeeling(int n)` private method in State:
   - `setState(() => _selectedFeeling = n)`
   - `await widget.workoutState.updateSessionFeeling(n)`
   - `if (mounted) Navigator.of(context).pop()`
   - No confirm button; tapping a number is the complete interaction.

9. [ ] Ensure the sheet is non-dismissible by design (isDismissible/enableDrag already set to false in step 2).

### Phase 3: Validation (@developer)

1. [ ] Widget test for `_FeelingSheetContent` behavior:
   - [ ] Sheet appears modally on SessionSummaryScreen load if `sessionFeeling == null`
   - [ ] Sheet does not appear if `sessionFeeling` already has a value
   - [ ] Tapping a number tile updates selected state and triggers `updateSessionFeeling` call
   - [ ] Sheet closes after successful `updateSessionFeeling` await
   - [ ] Sheet cannot be dismissed by tapping outside or dragging

2. [ ] Repository/state test for `updateSessionFeeling`:
   - [ ] `WorkoutState.updateSessionFeeling(int feeling)` correctly passes to repository and notifies listeners
   - [ ] `HiveWorkoutRepository.updateSessionFeeling` persists value to session and returns successfully
   - [ ] `MockWorkoutRepository.updateSessionFeeling` updates in-memory session map

3. [ ] Integration test for post-session flow:
   - [ ] Complete a workout, navigate to SessionSummaryScreen
   - [ ] Feeling sheet auto-opens
   - [ ] Select a feeling (e.g., 4)
   - [ ] Sheet closes, SessionSummaryScreen remains properly rendered
   - [ ] Re-open SessionSummaryScreen from back-navigation
   - [ ] Feeling sheet does NOT appear on re-open (sessionFeeling already set)

4. [ ] Update any existing Session Summary tests to handle new post-frame callback without affecting layout assertions

5. [ ] Verify no regressions:
   - [ ] SessionSummaryScreen navigation flow unchanged
   - [ ] Session data load and display unaffected
   - [ ] Query/refresh of existing sessions without `sessionFeeling` loads safely as null
   - [ ] Modality display utility handles null modality correctly (shows 'Free Training')

### Acceptance Criteria
- [ ] `TrainingSession` supports nullable `sessionFeeling` and `qualityRating` end-to-end (constructor/map/copyWith/persistence).
- [ ] `EffortObservation` supports nullable `rpeRating` and `restDurationMs` end-to-end.
- [ ] SQLite schema includes all requested nullable columns without duplicate definitions.
- [ ] Repository interface includes `updateSessionFeeling`, and implementation persists correctly.
- [ ] Both `HiveWorkoutRepository` and `MockWorkoutRepository` implement `updateSessionFeeling` and persist/read new session fields.
- [ ] Hive/mock migration includes idempotent marker `session_feeling_fields_migrated_v1` and migration-note comment.
- [ ] Session Summary auto-opens a non-dismissible feeling sheet on first load (per agreed trigger rule).
- [ ] Tapping a feeling writes value and closes the sheet immediately.
- [ ] No unintended UI changes outside the new modal behavior.
- [ ] Works on current web/dev environment and stays repository-agnostic for production SQLite path.

### Files Affected
- lib/data/models/models.dart
- lib/data/repositories/workout_repository.dart
- lib/data/repositories/hive_workout_repository.dart
- lib/data/repositories/mock_workout_repository.dart
- scripts/sqlite_schema.sql
- lib/features/session/session_summary_screen.dart
- test/profile_state_test.dart
- test/profile_data_layer_test.dart
- test/profile_screen_test.dart

### Notes
- All added fields are nullable; migration/backfill should remain no-op by design.
- Prefer state-layer call path (`workoutState.updateSessionFeeling`) to preserve architecture boundaries.
- Keep styling aligned with current design tokens and modality accent source; avoid introducing new theme systems.

## Progress
- [x] Confirm existing-field overlap and skip duplicates
- [x] Implement model and schema additions
- [x] Implement repository interface plus Hive/mock persistence updates
- [x] Add migration key and note for nullable field rollout
- [x] Align SQLite datasource schema/migrations for new fields
- [x] Implement Session Feeling modal trigger and interaction
- [ ] Add/adjust tests for persistence and modal behavior
- [ ] Validate no regressions

## Feedback
<!-- Implementation complete. Ready for Phase 3 (Validation) -->