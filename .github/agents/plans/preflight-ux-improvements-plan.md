# Feature: Pre-TestFlight UX Improvements (4 items)

## Overview
Four targeted UX improvements identified during a pre-TestFlight product review. All changes are
scoped to UI layer and minor state wiring. No new DB tables or model classes are required.
Each item is independent and can be implemented in any order.

## Acceptance Criteria

### Item 1 — Empty Session State
- [ ] Empty canvas shows 'Add Exercise' (primary, filled) and 'Add Block' (secondary, outline) buttons when zero exercises and Implkeblocks are present.
- [ ] Top-level standalone 'Add Block' button is removed from both empty and non-empty list states.
- [ ] 'Add Exercise' button triggers the exercise picker — same as the existing FAB/add exercise flow.
- [ ] 'Add Block' button triggers block creation — same as the existing add block flow.
- [ ] Once exercises/blocks are added, both buttons appear at the bottom of the list with a gap above them.
- [ ] Buttons remain visible as the list grows — never hidden.
- [ ] Tapping 'Finish Workout' with zero exercises shows a simplified "End empty session?" dialog.
- [ ] "End empty session?" dialog copy: title 'End empty session?', body 'No exercises have been logged. Are you sure you want to finish?', actions 'Cancel' (dismisses) and 'Finish' (proceeds with `_finishSession()`).
- [ ] Tapping 'Finish Workout' with one or more logged exercises skips the empty-session dialog and shows the normal dialog (unchanged).
- [ ] All button styles use existing theme tokens — no new design components.

### Item 2 — 'SYSTEM' → 'HUB'
- [ ] Bottom sheet section header displays 'HUB' instead of 'SYSTEM'.
- [ ] Letter spacing, font size, and label styling are unchanged.
- [ ] No variable names, class names, or identifiers are renamed.
- [ ] All four utility tiles (Calendar, Stats, Profile, Settings) remain fully functional.

### Item 3 — Weight Adjustment Opt-In Field
- [ ] Extra weight field is hidden by default on all applicable exercise types.
- [ ] 'Weight adjustment' text link appears below primary metrics, above the set/interval/round counter.
- [ ] Tapping the link reveals the extra weight inline scroller.
- [ ] Tapping again collapses the field without clearing the stored value.
- [ ] The link takes the accent color (`theme.colorScheme.primary`) when a non-zero value is stored and the field is collapsed.
- [ ] The link uses muted text color (`OmniTheme.textSecondary`) when value is zero/null and collapsed.
- [ ] The scroller accepts negative values without restriction.
- [ ] Toggle appears on `timed` effort kind.
- [ ] Toggle appears on `drill` effort kind.
- [ ] Toggle appears on `set` effort kind where the exercise does NOT have the `load` capability.
- [ ] Toggle does NOT appear on `set` exercises that have the `load` capability.
- [ ] Toggle does NOT appear on `round` exercises.
- [ ] No changes to the data model (no new DB columns or model classes). For `set` without load: the existing observation infrastructure is used — `metric-extra-weight` is already a recognized metric ID.

### Item 4 — Day Details Session Cards
- [ ] Each completed session card shows start time and duration on a single line below the session name.
- [ ] Time is formatted in 12-hour format with AM/PM.
- [ ] Duration is formatted compactly: '45m' under an hour, '1h 12m' over.
- [ ] If `endedAtMs` is null, only start time is shown with no duration suffix.
- [ ] Sessions with a `sessionFeeling` value (1–5) show a 4dp colored left border.
- [ ] Sessions without a `sessionFeeling` show no left border — no neutral placeholder.
- [ ] The feeling color scale matches `session_summary_screen.dart._getFeelingColor()` exactly.
- [ ] The feeling color scale is extracted to a shared utility so both files reference the same source.
- [ ] Tapping a card still navigates to the session summary screen (unchanged).
- [ ] The modality color dot and 'Completed' label are unchanged.
- [ ] All text styles use existing theme tokens.

---

## Analysis

All four items are @developer work. No DBA involvement needed:
- No new DB tables or columns
- No new model classes
- No migrations

Item 3 has a small state-layer addition for `set` without load: the `metric-extra-weight`
observation already exists in the DB schema. The developer needs to wire it up for this
effort-kind scope (add to `_persistEntryValues`, `getExercisesWithEntries`, and `addEntry`).

---

## Implementation Plan

### Item 1 — Empty Session State

**File: `lib/features/session/workout_session_screen.dart`**

#### 1a. New shared button widget (inline private):
Build a `_AddExerciseAndBlockBar` widget (or inline Column) that renders:
- `FilledButton` → 'Add Exercise' → calls `_addExercise(segmentId: segmentId)`
- Vertical spacer (8px)
- `OutlinedButton` with `OmniTheme.buttonUtilityRadius` border → 'Add Block' → calls
  `addSessionBlock()` then `setState()`

Both buttons should be `double.infinity` width. Wrap in `Padding` with
`EdgeInsets.symmetric(horizontal: 16)`.

#### 1b. `_buildStandardSessionListView()` — Empty branch:
- Current empty branch has one `OutlinedButton.icon` for 'Add Block'.
- Remove that button.
- Replace with a centered `Column` in the expanded area containing the icon/message text
  (keep the orientation text if desired) and at the bottom of the expanded area, insert the
  new `_AddExerciseAndBlockBar`.
- OR: Place the button bar at the bottom of the `ListView` children (inside the empty branch's
  existing `ListView`), so it sits at the top of the empty canvas with comfortable spacing.
- Recommended: use `Expanded` → `Column` → `Spacer()` + button bar at bottom, matching the
  same pattern as existing empty-state layouts in the codebase.

#### 1c. `_buildStandardSessionListView()` — Non-empty branch:
- Remove the existing `OutlinedButton.icon('Add Block')` at the bottom of the `ListView`.
- Add `const SizedBox(height: 24)` gap, then the `_AddExerciseAndBlockBar`.
- The `_addExercise` call should use `segmentId` (already in scope: `final segmentId = ...`).

#### 1d. `_buildRollingSessionListView()` — Non-empty (and implicit empty):
- Remove the existing `OutlinedButton.icon('Add Block')` at the bottom of the `ListView`.
- Add `const SizedBox(height: 24)` gap, then the `_AddExerciseAndBlockBar`.
- `_addExercise` for rolling sessions calls the same `_addExercise(segmentId: segmentId)` —
  same as the FAB. Note: in rolling sessions, standalone exercises (no blockId) are hidden in
  this view, but behavior matches the existing FAB (acceptable; same gap).
- For `segmentId` in rolling, use:
  ```dart
  final segmentId = widget.workoutState.segments.isNotEmpty
      ? widget.workoutState.segments.first.id
      : null;
  ```
  This is identical to the standard session pattern.

#### 1e. `_showFinishSessionDialog()`:
Add a guard at the top of the method:
```dart
final hasExercises = widget.workoutState.getExercisesWithEntries().isNotEmpty;
if (!hasExercises) {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('End empty session?'),
      content: const Text(
        'No exercises have been logged. Are you sure you want to finish?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: ButtonStyle(shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(
              OmniTheme.buttonUtilityRadius)),
          )),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: ButtonStyle(shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(
              OmniTheme.buttonUtilityRadius)),
          )),
          child: const Text('Finish'),
        ),
      ],
    ),
  );
  if (confirmed == true && mounted) await _finishSession();
  return;  // <-- exit early, skip normal dialog
}
// existing dialog follows unchanged...
```

#### Files affected:
- `lib/features/session/workout_session_screen.dart`

---

### Item 2 — SYSTEM → HUB

**File: `lib/features/home/home_screen.dart`**, line 637:
```dart
// Before:
'SYSTEM',
// After:
'HUB',
```
One-line change. All styling is preserved as-is.

#### Files affected:
- `lib/features/home/home_screen.dart`

---

### Item 3 — Weight Adjustment Opt-In Field

**Overview of current state:**
- `timed`: `extra-weight` key is present in `entryData` for new entries (always `!= null`);
  the UI currently shows `InlineMetricEditor` when key is present.
- `drill`: `extra-weight` is always in `entryData`; UI always shows `InlineMetricEditor`.
- `set`: `extra-weight` is NOT currently tracked; not in `_persistEntryValues` or `getExercisesWithEntries`.

**Per-effort expand/collapse state:**
- Add a `Map<String, bool> _weightAdjustExpanded = {}` to `_WorkoutSessionScreenState`.
- Key format: `'$effortId-$entryIndex'` (same pattern as other per-entry state).
- Default: `false` (collapsed).

**Toggle widget (inline helper or local builder):**
```dart
// Determine link color
final extraWeightValue = entryData['extra-weight'] as double? ?? 0.0;
final isNonZero = extraWeightValue != 0.0;
final linkColor = isNonZero
    ? theme.colorScheme.primary
    : OmniTheme.textSecondary.withOpacity(0.7);

GestureDetector(
  onTap: () => setState(() {
    final key = '$effortId-$entryIndex';
    _weightAdjustExpanded[key] = !(_weightAdjustExpanded[key] ?? false);
  }),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      'Weight adjustment',
      style: theme.textTheme.bodySmall?.copyWith(color: linkColor),
    ),
  ),
)
```

When `_weightAdjustExpanded['$effortId-$entryIndex'] == true`, render the
existing `InlineMetricEditor` for `extra-weight` immediately below the toggle.

**Changes in `_buildMetricWidget()`:**

**`case 'timed'`:**
- Remove the current conditional `InlineMetricEditor` block for `extra-weight` in both
  non-edit and edit mode.
- In non-edit mode: Insert toggle + conditional scroller between the RUNNING/STOPPED label
  and the next widget.
- In edit mode: Also replace with toggle + conditional scroller.
- Guard: Only show if `entryData['extra-weight'] != null` (backward compat with old entries).
  If key is absent, omit the toggle entirely (same guard as before — existing behavior preserved).

**`case 'drill'`:**
- Remove the current always-visible `InlineMetricEditor` for `extra-weight` in both
  non-edit and edit mode.
- Replace with toggle + conditional scroller (no null guard needed — drill always has the key).

**`case 'set'`:**
The exercise's capabilities are needed. Get the exercise from the cache:
```dart
final exerciseId = exercise['exerciseId'] as String?;
final exerciseObj = widget.workoutState.getExercise(exerciseId);
final hasLoad = exerciseObj?.capabilities.contains('load') ?? false;
```
(`ExerciseCapability.load` constant = `'load'` from `lib/core/constants/capability.dart`.)

- If `effortKind == 'set'` AND `!hasLoad`: show toggle + conditional scroller after the
  `weight` InlineMetricEditor.
- If `effortKind == 'set'` AND `hasLoad`: no toggle shown (unchanged layout).

**⚠️ State/persistence for `set` without load (minor state wiring):**
Because `extra-weight` is not currently in the `set` entry map, the developer must also:

1. **`lib/core/constants/effort_defaults.dart`**: Add `MetricIds.extraWeight: 0.0` to the
   set defaults (conditionally on capability, or always — set exercises without load already
   store weight=0.0, so extra-weight=0.0 default is safe).

2. **`lib/state/workout/workout_state.dart` → `addEntry()`**: For effort kind `'set'`,
   after persisting reps+weight observations, also create an `extra-weight` observation
   when the exercise does NOT have the `load` capability.
   ```dart
   // Add this after writing reps/weight observations for 'set':
   final exercise = _exerciseCache[effort.exerciseId];
   final hasLoad = exercise?.capabilities.contains('load') ?? false;
   if (!hasLoad) {
     // Create extra-weight observation at 0.0
   }
   ```

3. **`lib/state/workout/workout_state.dart` → `getExercisesWithEntries()`**: For `set` kind,
   include `extra-weight` in the entry map when observation exists. Modify
   `ObservationGrouper._groupSetObservations` OR add post-grouping code in
   `getExercisesWithEntries()` to attach extra-weight:
   ```dart
   // After grouping set observations, attach extra-weight companion if present
   final ewObs = effortObservations
       .where((o) => o.metricId == MetricIds.extraWeight)
       .toList();
   for (int i = 0; i < entries.length; i++) {
     if (i < ewObs.length) entries[i]['extra-weight'] = ewObs[i].valueReal ?? 0.0;
   }
   ```

4. **`lib/features/session/workout_session_screen.dart` → `_persistEntryValues()`** `case 'set'`:
   Add extra-weight persistence when the key is present (same guard pattern as `timed`):
   ```dart
   if (currentEntry['extra-weight'] != null) {
     await widget.workoutState.updateEntryValue(effortId, entryIndex, 'extra-weight',
       currentEntry['extra-weight'] as double);
   }
   ```

**Negative value support:**
`InlineMetricEditor` already supports negative values for `extra-weight` metric type.
No change needed there — just confirm the `min` clamp is not restricting negative input.

#### Files affected:
- `lib/features/session/workout_session_screen.dart` (expand/collapse state + toggle UI)
- `lib/state/workout/workout_state.dart` (addEntry + getExercisesWithEntries for set-without-load)
- `lib/core/constants/effort_defaults.dart` (extra-weight default for set)

---

### Item 4 — Day Details Session Cards

**Shared feeling color utility:**
Extract `_getFeelingColor` from `session_summary_screen.dart` to a shared, context-aware helper.

**Option A (recommended):** Create a standalone function in a new file
`lib/core/utils/session_feeling_utils.dart`:
```dart
import 'package:flutter/material.dart';

Color feelingColor(int feeling, BuildContext context) {
  switch (feeling) {
    case 1: return Colors.red;
    case 2: return Colors.orange;
    case 3: return Colors.yellow[700]!;
    case 4: return Colors.green;
    case 5: return Theme.of(context).primaryColor;
    default: return Theme.of(context).primaryColor;
  }
}
```

**Update `session_summary_screen.dart`**: Replace `_getFeelingColor(number)` calls with
`feelingColor(number, context)` and remove the private method.

**Changes in `_SessionRow` (day_session_list_screen.dart):**

The `_SessionRow` widget is a `StatelessWidget` that has access to `BuildContext` in `build()`.

**1. Time + duration line:**
Add a new private method to `_SessionRow`:
```dart
String _formatTimeDuration(TrainingSession s) {
  final start = DateTime.fromMillisecondsSinceEpoch(s.startedAtMs);
  final hour = start.hour;
  final minute = start.minute.toString().padLeft(2, '0');
  final period = hour >= 12 ? 'PM' : 'AM';
  final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  final timeStr = '$hour12:$minute $period';

  if (s.endedAtMs == null) return timeStr;

  final durationMs = s.endedAtMs! - s.startedAtMs;
  final totalMinutes = (durationMs / 60000).round();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  final durationStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  return '$timeStr · $durationStr';
}
```

**2. Left border:**
In `build()`, compute feeling color:
```dart
final feeling = entry.session?.sessionFeeling;
final leftBorderColor = (feeling != null)
    ? feelingColor(feeling, context)
    : null;
```
Modify the `Container.decoration`:
```dart
decoration: BoxDecoration(
  color: themeColors.surface.withOpacity(0.85),
  borderRadius: BorderRadius.circular(12),
  border: leftBorderColor != null
      ? Border(
          left: BorderSide(color: leftBorderColor, width: 4),
          top: BorderSide(color: themeColors.surfaceBorder),
          right: BorderSide(color: themeColors.surfaceBorder),
          bottom: BorderSide(color: themeColors.surfaceBorder),
        )
      : Border.all(color: themeColors.surfaceBorder),
),
```

**3. Subtitle restructuring:**
The current `ListTile.subtitle` is a single-line text. For completed sessions, extend it:

Change `subtitle:` from `Text(subtitle)` to a `Column` with:
```dart
subtitle: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(subtitle, style: TextStyle(color: stateColor, fontSize: 12)),
    if (entry.isCompleted && entry.session != null)
      Text(
        _formatTimeDuration(entry.session!),
        style: TextStyle(color: OmniTheme.textMuted, fontSize: 12),
      ),
  ],
),
```
Note: `OmniTheme.textMuted` needs to be confirmed or replaced with
`OmniTheme.colorsForTheme(OmniTheme.activeTheme).textMuted`.

Also add `isThreeLine: entry.isCompleted && entry.session != null` to the `ListTile`
to give Flutter the layout hint.

#### Files affected:
- `lib/features/calendar/day_session_list_screen.dart`
- `lib/features/session/session_summary_screen.dart` (refactor `_getFeelingColor` → utility)
- `lib/core/utils/session_feeling_utils.dart` (new file)

---

## Progress
- [x] Item 1: Empty session state (workout_session_screen.dart)
- [x] Item 2: SYSTEM → HUB (home_screen.dart)
- [x] Item 3: Weight adjustment toggle (workout_session_screen.dart + state wiring)
- [x] Item 4: Day details session cards (day_session_list_screen.dart + feeling color utility)

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback
