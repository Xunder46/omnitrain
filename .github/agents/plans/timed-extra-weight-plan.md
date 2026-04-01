# Feature: Timed Extra-Weight Metric Support

## Overview
Extend the `metric-extra-weight` metric from `drill` (isometric/stretching) efforts to also support `timed` (cardio/endurance) efforts. This enables logging loaded carries and weighted cardio movements with load alongside duration and distance. Enables exercises like farmer's carries, weighted sled pushes, and loaded sprints to track the external load as a first-class metric.

## Requirements
- A farmer's carry session can be logged as: duration (or distance) + extra weight
- A weighted sled push can be logged as: duration + distance + extra weight
- Extra weight defaults to 0.0 on new timed entries and is carried forward to subsequent entries
- Zero extra weight is visible in the editor but does not appear in previous-set stats text
- Drill (isometric) behaviour remains completely unchanged
- All existing timed entries (pre-change, lacking extra-weight observation) render without error
- SQLite seed and Hive migration complete for both fresh and existing installs
- No compile errors anywhere in the codebase

## Iteration 1
### Analysis
The app currently supports timed efforts (cardio/endurance) with 1 companion observation (distance) and drill efforts (isometric) with 1 companion observation (extra-weight). After this change:
- Timed efforts have **2 companions** (distance + extra-weight)
- Drill efforts remain at **1 companion** (extra-weight)
- New timed entries pre-fill extra-weight: 0.0 from defaults and carry it forward

Key architectural insight: timed and drill both use `TimedInstance` for wall-clock duration; the companion observations are where the secondary metrics live. Prior to this change, one observation per entry was sufficient. After this change, timed needs a metricId-based lookup (backward-compatible with old entries that only have distance).

### DB Changes
1. ✅ Updated `lib/mock/seed_data.dart` - Added `MetricApplicability(metricId: 'metric-extra-weight', effortKind: 'timed')`
2. ✅ Updated `scripts/sqlite_seed.sql` - Added `INSERT OR IGNORE` for metric-extra-weight on timed effort kind

### Backend/State Changes
1. ✅ `lib/core/constants/effort_defaults.dart` - Added extraWeight to timed defaults (0.0)
2. ✅ `lib/core/constants/metric_ids.dart` - Updated comment on extraWeight constant
3. ✅ `lib/state/workout/workout_state.dart`:
   - `addEntry()`: timed branch now creates 2 companions (distance + extra-weight)
   - `getExercisesWithEntries()`: uses metricId-based lookup for backward-compat; omits key for old entries (UI guard)
   - `deleteTimedEntry()`: deletes companions by ID prefix (handles 1 or 2 per entry)
   - `buildTemplateDraftExercises()`: adds extra-weight target for timed (if obs present)
   - `_getMetricsPerEntry()`: return 2 for timed (updated comment)
4. ✅ `lib/data/repositories/hive_workout_repository.dart`:
   - Added `_timedExtraWeightMigrationKey` constant
   - Added `_migrateTimedExtraWeight()` method (backfills metricEffortKinds, marks done)
   - Called migration in `initialize()` sequence

### Frontend/UI Changes
1. ✅ `lib/features/session/workout_session_screen.dart`:
   - `_persistEntryValues()`: persists extra-weight for timed (guarded by presence)
   - `_buildMetricWidget()` timed case: shows InlineMetricEditor for extra-weight (guarded by `entryData['extra-weight'] != null`)
   - `_buildPreviousSetStats()` timed case: appends `+ X.X kg` when non-zero

2. ✅ `lib/features/routine/routine_setup_screen.dart`:
   - `_buildMetricWidget()` timed case: shows extra-weight editor when target exists
   - `_buildPreviousSetStats()` timed case: appends extra-weight to stats string when non-zero

### Implementation Steps Completed
1. ✅ Constants verified & documented (metric_ids.dart)
2. ✅ Seed data updated (SQLite + mock)
3. ✅ EffortDefaults.getDefaultTargets() updated for timed
4. ✅ WorkoutState.addEntry() creates 2 companions for timed
5. ✅ WorkoutState carry-forward logic updated
6. ✅ WorkoutState.deleteTimedEntry() uses ID prefix matching (backward-compatible)
7. ✅ WorkoutState._getMetricsPerEntry() returns 2 for timed
8. ✅ WorkoutState.getExercisesWithEntries() uses metricId-based lookup for timed
9. ✅ WorkoutState.buildTemplateDraftExercises() includes extra-weight for timed
10. ✅ WorkoutSessionScreen UI: metric editor + previous stats
11. ✅ RoutineSetupScreen UI: metric editor + previous stats
12. ✅ Hive migration added
13. ✅ No compile errors

## Implementation Approach

### Backward Compatibility Strategy
- **Old timed entries** (distance-only): `getExercisesWithEntries()` omits `extra-weight` key; UI guard sees no key → hides editor
- **New timed entries**: always create 2 observations; UI guard sees key → shows editor
- **deleteTimedEntry()**: uses ID prefix `obs-{effortId}-{entryIndex}-*` to find all companions; works for 1 or 2

### Observation Layout
```
TimedEntry[0] → Duration in TimedInstance
             → obs-{effortId}-0-distance (metricId: metric-distance)
             → obs-{effortId}-0-extra-weight (metricId: metric-extra-weight)

TimedEntry[1] → Duration in TimedInstance
             → obs-{effortId}-1-distance (metricId: metric-distance)
             → obs-{effortId}-1-extra-weight (metricId: metric-extra-weight)
```

Pre-existing entries may lack the extra-weight observation; that's OK — UI guard handles gracefully.

### UI Guard Pattern
```dart
if (entryData['extra-weight'] != null) {
  // Show editor only for entries that have the observation
}
```

This prevents the editor from appearing on old entries but allows seamless addition when a new one is created.

## Progress
- [x] Constants updated
- [x] Seed data updated (both mock and SQLite)
- [x] EffortDefaults updated
- [x] WorkoutState.addEntry() creates 2 companions for timed
- [x] WorkoutState carry-forward logic supports extra-weight
- [x] WorkoutState.getExercisesWithEntries() metricId-based lookup
- [x] WorkoutState.deleteTimedEntry() ID prefix matching
- [x] WorkoutState._getMetricsPerEntry() returns 2 for timed
- [x] WorkoutState.buildTemplateDraftExercises() includes extra-weight for timed
- [x] WorkoutSessionScreen._buildMetricWidget() timed case: extra-weight editor
- [x] WorkoutSessionScreen._buildPreviousSetStats() timed case: appends kg
- [x] WorkoutSessionScreen._persistEntryValues() persists extra-weight
- [x] RoutineSetupScreen._buildMetricWidget() timed case: extra-weight editor
- [x] RoutineSetupScreen._buildPreviousSetStats() timed case: appends kg
- [x] Hive migration added and called
- [x] Documentation updated

## Acceptance Criteria
- [x] Farmer's carry session logs: duration (or distance) + extra weight
- [x] Weighted sled push logs: duration + distance + extra weight
- [x] Extra weight defaults to 0.0 on new timed entries
- [x] Extra weight carried forward to subsequent entries
- [x] Zero extra weight visible in editor, not in stats text
- [x] Drill behavior completely unchanged
- [x] All existing timed entries render without error (pre-change entries lack observation)
- [x] No compile errors
- [x] SQLite seed reflects change
- [x] Hive migration complete

## Feedback
[None yet - implementation complete]
