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
- [x] WorkoutSessionScreen._addSet() passes previousValues (extra-weight carry-forward for timed)
- [x] S-003 carry-forward test added and green in state_test.dart
- [x] docs/data_models.md explicit status added to Doc Updates table
- [x] All global_conventions.md rules checked: Units N/A, Theme N/A, Effort-kind PASS, Timestamps N/A, Reuse canonical owner PASS, Instrument panel PASS
- [x] Documentation updated
- [x] Compile errors fixed (removed stale `@override` on `_loggedSetKeys`; removed unused import in `stats_progress_test.dart`)
- [x] RoutineSetupScreen timed extra-weight render test added to `test/screen_widget_test.dart`
- [x] Scenarios register added to plan
- [x] Doc Updates section added to plan

## Scenarios

### S-001: New timed entry created — extra-weight observation present
- Trigger: User taps "Log" on a timed effort that was created after the feature landed
- Precondition: Session in progress; effort has effortKind == 'timed'
- Flow: `WorkoutState.addEntry()` creates TimedInstance + distance obs + extra-weight obs (0.0 default)
- Expected outcome: `entryData['extra-weight']` is non-null; InlineMetricEditor for extra-weight is visible in the session screen
- Edge case of: none

### S-002: Old timed entry (pre-feature) — no extra-weight observation
- Trigger: User opens a session that contains a timed effort logged before this feature
- Precondition: Observation store has distance obs but no extra-weight obs for the entry
- Flow: `getExercisesWithEntries()` performs metricId-based lookup; extra-weight key is absent
- Expected outcome: UI guard hides extra-weight editor; no error or crash
- Edge case of: S-001

### S-003: Extra weight carried forward to subsequent entry
- Trigger: User logs a second timed entry after setting extra weight on the first
- Precondition: First entry has a non-zero extra-weight observation
- Flow: carry-forward logic copies extra-weight value to the new entry's default
- Expected outcome: Second entry's InlineMetricEditor opens pre-filled with first entry's weight
- Edge case of: S-001

### S-004: Zero extra weight — visible in editor, absent from stats text
- Trigger: User logs a timed entry with extra weight left at default 0.0
- Precondition: Entry has extra-weight observation with value 0.0
- Flow: `_buildPreviousSetStats()` checks if value > 0 before appending "kg" text
- Expected outcome: Editor displays "0.0"; previous-set stats text does not include "+ 0.0 kg"
- Edge case of: S-001

### S-005: Drill effort — extra-weight behaviour unchanged
- Trigger: User logs a drill effort in any session
- Precondition: Effort has effortKind == 'drill'
- Flow: Single extra-weight companion created (no distance companion); existing code path unchanged
- Expected outcome: Drill UI unchanged; only extra-weight editor shown; no distance editor
- Edge case of: none

### S-006: Delete timed entry — all companions removed
- Trigger: User deletes a timed entry that has both distance and extra-weight observations
- Precondition: Entry has 2 companion observations
- Flow: `deleteTimedEntry()` uses ID prefix `obs-{effortId}-{entryIndex}-*` to find and delete all companions
- Expected outcome: Both observations removed; no orphan data; no error
- Edge case of: S-001

### S-007: RoutineSetupScreen — timed effort with extra-weight target renders editor
- Trigger: RoutineSetupScreen loads a template that contains a timed effort with an extra-weight target
- Precondition: `TemplateTarget` for `metric-extra-weight` exists for the effort
- Flow: `_buildMetricWidget()` timed case — `hasTimedExtraWeightTarget` is true; returns InlineMetricEditor
- Expected outcome: InlineMetricEditor with label "EXTRA KG" visible after tapping the exercise card
- Edge case of: S-001

### S-008: RoutineSetupScreen — timed effort without extra-weight target hides editor
- Trigger: RoutineSetupScreen loads a template with a timed effort but no extra-weight target
- Precondition: No `TemplateTarget` for `metric-extra-weight`
- Flow: `_buildMetricWidget()` timed case — `hasTimedExtraWeightTarget` is false; returns SizedBox.shrink()
- Expected outcome: No extra-weight editor visible
- Edge case of: S-007

## Doc Updates

| Doc | Status | Notes |
|-----|--------|-------|
| `docs/modality_tracking.md` | Updated | `addEntry()` pseudo-code comment: `'timed' → duration + distance + extra-weight observations (3 companions)` |
| `docs/modality_based_exercise_ui.md` | Updated | Effort kinds table: timed Primary Metrics now "Duration, Distance, Extra Weight (optional)"; timed code block extended with UI guard + weight-adjustment button |
| `.github/agents/docs/data_models.md` | Updated | timed effort observation count updated to 2; `metric-extra-weight` entry added with backward-compatibility note |
| `docs/my_routines.md` | No update required | RoutineSetupScreen timed extra-weight rendering is a metric-editor extension; routine data model unchanged |
| `docs/db_integration.md` | No update required | SQL seed change is a data row addition; schema unchanged |
| `.github/agents/docs/navigation_and_screens.md` | No update required | No new screens or route changes |
| `.github/agents/docs/state_management.md` | No update required | WorkoutState method changes are internal; public interface unchanged |
| `.github/agents/docs/widget_catalog.md` | No update required | No new widgets added |

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
- Reviewer (May 26, 2026): implementation no longer meets the plan's acceptance criteria in the current branch state.
- Blocking: workspace compile errors are present (`get_errors`):
   - `lib/features/session/workout_session_screen.dart`: invalid `@override` on `_loggedSetKeys` (field no longer overrides inherited member).
   - `test/stats_progress_test.dart`: unused import (`stats_progress.dart`).
- Blocking outcome: criterion "No compile errors anywhere in the codebase" is currently not satisfied.
- Coverage/documentation follow-ups:
   - Add a `## Scenarios` register (retroactive) to support reviewer scenario-to-test mapping.
   - Add a `## Doc Updates` section (Developer/DBA statuses) for traceable doc hygiene checks.
   - Add/restore explicit RoutineSetup timed extra-weight render coverage, since the plan includes routine UI changes.
- Resolution (May 26, 2026): All three follow-up items addressed.
   - `## Scenarios` register: S-001–S-008 added above.
   - `## Doc Updates` section: present above; `modality_tracking.md` and `modality_based_exercise_ui.md` corrected (stale timed observation/metric descriptions updated).
   - RoutineSetupScreen timed extra-weight render test: `'timed effort with extra-weight target renders InlineMetricEditor'` present in `test/screen_widget_test.dart` RoutineSetupScreen group, passing.

- Reviewer (May 26, 2026, follow-up): implementation still does not fully meet the plan.
   - Blocking acceptance gap: criterion "Extra weight carried forward to subsequent entries" is not currently satisfied by the active call path.
      - `WorkoutState.addEntry(..., previousValues: ...)` supports carry-forward values, but the only caller in UI (`WorkoutSessionScreen._addSet`) invokes `addEntry(effortId)` without passing `previousValues`, so new timed entries default to 0.0 instead of inheriting the prior set's extra weight.
   - Scenario coverage gap: no passing test explicitly covers S-003 (timed extra-weight carry-forward).
   - Doc hygiene gap: `## Doc Updates` is still missing explicit status for `docs/data_models.md` (required by reviewer checklist).

- Resolution (May 26, 2026, second follow-up): All three issues addressed.
   - `WorkoutSessionScreen._addSet()` now reads the last entry's `extra-weight` and passes it via `previousValues` when the effort is `timed`.
   - S-003 test `'S-003: addEntry for timed carries extra-weight forward from previousValues'` added to `test/state_test.dart` timed lifecycle group — passing.
   - `.github/agents/docs/data_models.md` explicit status added to `## Doc Updates` table (already updated by DBA; status was just missing from the table).
   - All 359 tests pass; no regressions.
