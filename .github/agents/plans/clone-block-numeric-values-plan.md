# Feature: Clone Block Numeric Values Preservation

## Overview
When cloning a session block (in active sessions), `EffortObservation` values are reset to zero/null instead of being copied from the source. The clone should be a true duplicate with all numeric values (reps, weight, duration, RPE, rest) preserved. The routine template path (`cloneSegment`) already works correctly — only the session block path is broken.

## Requirements
- Cloned `EffortObservation` carries over `valueInt`, `valueReal`, `valueText`, `valueBool`, `rpeRating`, `restDurationMs` from source
- Cloned block is fully independent — editing it does not affect the source
- Works for all modalities (resistance, cardio, etc.)
- Works in both `MockWorkoutRepository` and `HiveWorkoutRepository`

## Acceptance Criteria
- [x] `cloneSessionBlock` in `mock_workout_repository.dart` copies observation values from source
- [x] `cloneSessionBlock` in `hive_workout_repository.dart` copies observation values from source
- [x] Existing test in `session_blocks_repository_test.dart` updated to assert values are preserved (not zero)
- [x] New test: clone with all observation fields populated asserts all values are identical to source
- [x] New test: mutating cloned block's observation does not change source block's observation

## Root Cause

### `mock_workout_repository.dart` (line ~1260)
```dart
// Clone observations with values reset to zero/null  ← intentional reset, which is wrong
final newObs = EffortObservation(
  ...
  valueInt: 0,       // ← WRONG: should be obs.valueInt
  valueReal: 0.0,    // ← WRONG: should be obs.valueReal
  valueText: null,   // ← WRONG: should be obs.valueText
  valueBool: null,   // ← WRONG: should be obs.valueBool
  rpeRating: null,   // ← WRONG: should be obs.rpeRating
  restDurationMs: null, // ← WRONG: should be obs.restDurationMs
```

### `hive_workout_repository.dart` (line ~1748)
Same problem — identical reset pattern.

## Scenarios
- Resistance block with reps + weight observations → clone has same reps + weight
- Cardio block with duration observations → clone has same duration
- Block with RPE and rest recorded → clone has same RPE and rest
- Modify cloned block weight → source block weight unchanged

## Iteration 1
### DB Changes
None required — pure in-memory/Hive value copy change.

### Backend Changes
1. [x] Fix `MockWorkoutRepository.cloneSessionBlock`: copy all `EffortObservation` value fields from source instead of zeroing
2. [x] Fix `HiveWorkoutRepository.cloneSessionBlock`: same fix

### Frontend Changes
None.

### Implementation Steps
1. [x] Edit `lib/data/repositories/mock_workout_repository.dart`: replace reset values with `obs.*` values in the observation clone block
2. [x] Edit `lib/data/repositories/hive_workout_repository.dart`: same
3. [x] Update `test/session_blocks_repository_test.dart`: change `valueInt: 0` → `valueInt: 10`, `valueReal: 0.0` → `valueReal: isNull` in the existing clone test
4. [x] Add test: `cloneSessionBlock preserves all observation numeric values`
5. [x] Add test: `cloneSessionBlock produces independent copy — mutating clone does not affect source`

## Progress
- [x] Fix mock repository observation clone
- [x] Fix hive repository observation clone
- [x] Update existing test assertions
- [x] Add numeric preservation test
- [x] Add independence test
- [x] Run tests green

## Feedback
