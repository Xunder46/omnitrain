# Feature: Session Detail Set Count Label Fix

## Overview
The set count label on the session details screen currently shows only **logged** items. For resistance (`set`) this means zero until the first set is logged. For `round` it only counts finished rounds, ignoring planned-but-not-started ones. For `timed`/`drill` it counts finished `TimedInstance`s, ignoring those in `notStarted` state. The fix makes every modality show the **total** (logged + planned) without changing the label format or screen layout.

## Requirements
- `_buildExerciseSubtitle` in `workout_session_list_view.dart` must show the total scope for all four modalities.
- `_buildSetProgress` / `_buildSetIndicator` in `workout_session_detail_view.dart` rely on `entries.length`, which is already correct for `set` and `drill` (all observations are present from add-time), but **wrong for `round`** (entries come from RoundInstances which include notStarted) and potentially wrong for `timed` (same reason).
- No changes to label wording, format, or screen layout.

## Root Cause Analysis

### `set` modality
`entries` = grouped observations from `ObservationGrouper`. Observations are created at add-time (even before logging). So `entries.length` = total planned sets. **Already correct in `_buildSetProgress`.**

`_buildExerciseSubtitle` for `set` uses `entries.length` directly. **Already correct.**

### `timed` / `drill` modality
`entries` in the exercise map = built from `_timerManager.getTimedInstancesForEffort()`, which includes ALL instances (notStarted, active, paused, finished). So `entries.length` = total, already correct for `_buildSetProgress`.

`_buildExerciseSubtitle` for `timed` iterates `entries.length` but sums duration differently (only `finished` instances contribute elapsed). The **count** shown is a duration string, not a set count — so the set count issue doesn't apply to the duration label here. However the underlying loop uses `entries.length` including unstarted entries. **No set-count bug in the duration label.**

`_buildExerciseSubtitle` for `drill` uses `entries.length` directly as "holds". **Already correct.**

### `round` modality — **BUGGY**
`_buildExerciseSubtitle` for `round`:
```dart
final completedRounds = widget.workoutState
    .getRoundsForEffort(effortId)
    .where((round) => round.completed && round.startedAtMs > 0 && round.finishedAtMs != null)
    .length;
return '$completedRounds round${completedRounds != 1 ? 's' : ''}';
```
This counts only fully-completed (countdown hit zero) rounds, which starts at 0. **BUG: should be total round instances.**

`_buildSetProgress` for `round` uses `entries.length` where entries = `rounds.map(...)` from all RoundInstances. **Already correct** (shows total rounds in "Round X of Y").

`_buildSetIndicator` for `round` uses `entries.length`. **Already correct.**

## Acceptance Criteria
- [ ] `_buildExerciseSubtitle` for `round` shows total round instances (not just completed ones)
- [ ] All four modalities have stable set counts from session open
- [ ] No label format or screen layout changes
- [ ] Unit tests for `_buildExerciseSubtitle`-equivalent logic: zero logged, partially logged, fully logged × all 4 modalities
- [ ] Existing tests that encoded old `round` subtitle behavior updated/removed

## Scenarios
- `round` effort with 3 rounds, none started → label: "3 rounds"
- `round` effort with 3 rounds, 1 completed → label: "3 rounds"
- `round` effort with 3 rounds, all completed → label: "3 rounds"
- `set` effort with 4 sets → label: "4 sets" (unchanged)
- `timed` effort with 2 intervals → label: "MM:SS total" (unchanged, counts entries)
- `drill` effort with 2 holds → label: "2 holds" (unchanged)

## Implementation Plan

### Phase 1: Fix `_buildExerciseSubtitle` for `round` (single-line change)

**File:** `lib/features/session/workout_session_list_view.dart`

Change the `round` case from:
```dart
case 'round':
  final completedRounds = widget.workoutState
      .getRoundsForEffort(effortId)
      .where((round) => round.completed && round.startedAtMs > 0 && round.finishedAtMs != null)
      .length;
  return '$completedRounds round${completedRounds != 1 ? 's' : ''}';
```
To:
```dart
case 'round':
  final totalRounds = widget.workoutState
      .getRoundsForEffort(effortId)
      .length;
  return '$totalRounds round${totalRounds != 1 ? 's' : ''}';
```

### Phase 2: Unit Tests

**File:** `test/session_toolbar_rework_test.dart` OR new file `test/session_detail_set_count_test.dart`

Tests needed (state-level, no widget rendering required — test `getExercisesWithEntries()` output):

1. **`set` modality** — 0 logged (entries exist from init), 2 logged of 4, 4 of 4 → `entries.length` == total
2. **`timed` modality** — 0 finished, 1 finished of 3, 3 of 3 → `entries.length` == total
3. **`drill` modality** — same as timed
4. **`round` modality** — 0 completed, 1 completed of 3, 3 of 3 → `entries.length` == total AND subtitle shows total

All four: verify the value is stable (equals the total regardless of logged count).

### Phase 3: Check / update existing tests

Search for any tests asserting "0 rounds" or the old completed-only round subtitle and update to new expected value.

## Files Affected
- `lib/features/session/workout_session_list_view.dart` (fix round subtitle)
- `test/session_detail_set_count_test.dart` (new test file)

## Notes
- `_buildSetProgress` and `_buildSetIndicator` already use `entries.length` which is correct for all modalities; no changes needed there.
- The `timed` duration subtitle is intentionally a time string, not a count — no bug there.
- The `timed` and `drill` `entries.length` in the exercise map already includes notStarted instances (all TimedInstances are added eagerly at `addEntry` time), so those subtitles are stable.
- Only `round` subtitle is buggy: it filtered for `completed` rounds instead of all rounds.

## Progress
- [x] Fix round subtitle in `workout_session_list_view.dart`
- [x] Write new unit tests in `test/session_detail_set_count_test.dart`
- [x] Check and update any existing tests encoding old round subtitle — none found encoding the old completed-only behavior; no tests required removal

## Feedback

