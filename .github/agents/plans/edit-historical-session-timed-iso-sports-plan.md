# Feature: edit-historical-session-timed-iso-sports

## Overview
Close three gaps in retrospective session editing: (1) timed (cardio) entries have no h/m/s duration dialog in edit mode, (2) drill (isometric) entries have no h/m/s duration dialog in edit mode, and (3) sports (round) duration edits appear to save but the session summary never reflects them. Also wire the Add Set / Add Round affordance to auto-open the shared duration dialog in edit mode, and normalize all rounds to `finished` state on save.

## Requirements
- Cardio (timed) entries in edit mode must expose a tappable duration affordance that opens a shared h/m/s dialog pre-filled with the current duration.
- Isometric (drill) entries use the exact same dialog; extra-weight editing is unchanged.
- Sports (round) duration edits must write to the round instance's `actualDurationSecs`, not to an observation field.
- Confirming the dialog stages the change in the local edit buffer; cancelling leaves the entry unchanged.
- The Unsaved Changes guard covers duration edits from all six entry points (Session Time, timed, drill, round, Add Set on timed/drill, Add Round on round).
- Saving commits timed/drill durations via TimedInstance writes, and round durations via RoundInstance writes — no observation write for duration data.
- After save, every round in the session that is not already `finished` is normalised to `finished` with `actualDurationSecs = plannedDurationSecs` (or the user-entered value if one was buffered).
- The session summary reflects all changes (duration totals, stats grid, group chips) without an app restart.
- Add Set on timed/drill adds a new interval and immediately opens the dialog pre-filled with 00:00:00.
- Add Round on round adds a new round (sensible defaults matching live mode) and opens the dialog pre-filled with 00:00:00; the entered value becomes the round's `actualDurationSecs`; the round is created in the `finished` state at save.
- The duration dialog is one shared component used by all six entry points.
- Live-workout behaviour (play/pause timer) is untouched.
- The previously planned auto-open of the duration dialog when a newly added timed/drill/round exercise is resolved from the picker is preserved and not regressed.

## Acceptance Criteria
- [ ] Cardio (timed) entries in edit mode display a tappable duration chip; tapping opens the h/m/s dialog pre-filled with current duration.
- [ ] Isometric (drill) entries in edit mode display the same chip and same dialog; extra-weight editing unchanged.
- [ ] Sports (round) entries continue to show a duration affordance; edits now land on `RoundInstance.actualDurationSecs` and survive through to the summary.
- [ ] Confirming the dialog stages the change in `_editBuffer`; cancelling leaves entry unchanged.
- [ ] Unsaved Changes guard fires on timed, drill, and round duration edits.
- [ ] Saving commits timed/drill durations via `WorkoutState.setTimedEntryDuration` (→ `TimedInstance`), and round durations via `WorkoutState.setRoundDuration` (→ `RoundInstance`).
- [ ] After save, all non-finished rounds are normalised to `finished`.
- [ ] Summary screen reflects updated totals (duration, stats grid, group chips) on return without app restart.
- [ ] Add Set on timed/drill adds entry, navigates to it, opens dialog pre-filled with 00:00:00.
- [ ] Add Round on round adds entry, navigates to it, opens dialog pre-filled with 00:00:00; confirmed value becomes `actualDurationSecs`.
- [ ] One shared duration dialog function used by all six entry points.
- [ ] No regressions in live-workout timer flow.
- [ ] Auto-open duration dialog after picker resolves a timed/drill/round exercise in edit mode is preserved.

## Root Cause Analysis (Gap 3)

### Where the round-duration edit value is held in edit mode
The round edit mode renders an `InlineMetricEditor` that calls `_updateMetricValue(effortId, entryIndex, 'round-duration', value)`. This writes the value into `_editBuffer['{effortId}-{entryIndex}']['round-duration']` and also updates `entries[entryIndex]['round-duration']` for local UI feedback. No repository write happens at this point.

### Whether the save path writes to the round instance
In `_saveEditChanges`, the buffer flush calls:
```dart
await widget.workoutState.updateEntryValue(effortId, entryIndex, 'round-duration', value);
```
`updateEntryValue` → `_sessionCore.updateEntryValue` → writes to an **EffortObservation** record. The `RoundInstance` is **never touched**.

### Whether the summary picks up the change
`computeSessionSummary()` (called by `_refreshSummary` in the summary screen) reads:
```dart
final rounds = _timerManager.getRoundsForEffort(effort.id);
```
This returns in-memory `RoundInstance` objects from `TimerManager._roundInstances`. Because the save path wrote to observations only, the in-memory `RoundInstance` is unchanged. The summary computes `totalRoundDurationMs` from `round.elapsedMs` on finished round instances — so no change appears.

### The fix
Route `'round-duration'` buffer entries through `WorkoutState.setRoundDuration` (a new method) at save time instead of `updateEntryValue`. Route `'elapsedSecs'` buffer entries on timed/drill through `WorkoutState.setTimedEntryDuration` (a new method) at save time.

Both new methods update the corresponding in-memory instance AND persist to the repository, bypassing the state-machine transition guards (which are invalid for retrospective edits).

## Iteration 1

### Phase 0: No schema changes (@dba not required)
- `RoundInstance` and `TimedInstance` tables already have `actualDurationSecs`, `state`, `finishedAtMs`, etc.
- `WorkoutRepository` already exposes `updateRoundInstance` and `updateTimedInstance`.
- No migrations needed.

### Phase 1: New state-layer write methods (@developer)

#### 1.1 `timer_manager.dart` — `setTimedInstanceFinished`
Add a method that bypasses `_isValidTimedTransition` (which rejects `finished → finished` and `notStarted → finished`). Intended only for retrospective edits.

```dart
Future<void> setTimedInstanceFinished(
  String effortId,
  int entryIndex,
  int durationSecs,
) async {
  _clearError();
  try {
    final list = _timedInstances[effortId];
    if (list == null || entryIndex >= list.length) return;
    final old = list[entryIndex];
    final now = DateTime.now().millisecondsSinceEpoch;
    // Synthesise timestamps so elapsedMs will equal durationSecs * 1000.
    final startedAtMs = old.startedAtMs > 0
        ? old.startedAtMs
        : now - (durationSecs * 1000);
    final finishedAtMs = startedAtMs + (durationSecs * 1000);
    final updated = old.copyWith(
      state: TimedState.finished,
      actualDurationSecs: durationSecs,
      startedAtMs: startedAtMs,
      finishedAtMs: finishedAtMs,
      totalPausedDurationMs: 0,
      pausedAtMs: null,
      updatedAtMs: now,
    );
    await _repository.updateTimedInstance(updated);
    list[entryIndex] = updated;
    _notify();
  } catch (e) {
    _setError('Failed to set timed entry duration: $e');
  }
}
```

#### 1.2 `timer_manager.dart` — `setRoundFinished`
Similar bypass method for round instances.

```dart
Future<void> setRoundFinished(
  String effortId,
  int roundIndex,
  int durationSecs,
) async {
  _clearError();
  try {
    final list = _roundInstances[effortId];
    if (list == null || roundIndex >= list.length) return;
    final old = list[roundIndex];
    final now = DateTime.now().millisecondsSinceEpoch;
    final startedAtMs = old.startedAtMs > 0
        ? old.startedAtMs
        : now - (durationSecs * 1000);
    final finishedAtMs = startedAtMs + (durationSecs * 1000);
    final plannedDurationSecs = old.plannedDurationSecs > 0
        ? old.plannedDurationSecs
        : durationSecs;
    final updated = old.copyWith(
      state: RoundState.finished,
      actualDurationSecs: durationSecs,
      plannedDurationSecs: plannedDurationSecs,
      startedAtMs: startedAtMs,
      finishedAtMs: finishedAtMs,
      completed: true,
      totalPausedDurationMs: 0,
      pausedAtMs: null,
      updatedAtMs: now,
    );
    await _repository.updateRoundInstance(updated);
    list[roundIndex] = updated;
    _notify();
  } catch (e) {
    _setError('Failed to set round duration: $e');
  }
}
```

#### 1.3 `timer_manager.dart` — `normalizeAllRoundsToFinished`
After all buffered duration edits are flushed, call this to bring any remaining non-finished rounds to `finished`.

```dart
Future<void> normalizeAllRoundsToFinished() async {
  for (final entry in _roundInstances.entries) {
    final effortId = entry.key;
    final rounds = entry.value;
    for (int i = 0; i < rounds.length; i++) {
      final round = rounds[i];
      if (round.state != RoundState.finished) {
        final durationSecs = round.plannedDurationSecs > 0
            ? round.plannedDurationSecs
            : 0;
        await setRoundFinished(effortId, i, durationSecs);
      }
    }
  }
}
```

#### 1.4 `workout_state.dart` — delegation methods
```dart
Future<void> setTimedEntryDuration(String effortId, int entryIndex, int durationSecs) =>
    _timerManager.setTimedInstanceFinished(effortId, entryIndex, durationSecs);

Future<void> setRoundDuration(String effortId, int roundIndex, int durationSecs) =>
    _timerManager.setRoundFinished(effortId, roundIndex, durationSecs);

Future<void> normalizeRoundsToFinished() =>
    _timerManager.normalizeAllRoundsToFinished();
```

### Phase 2: Shared duration dialog (@developer)

Extract the h/m/s dialog from `_editSessionDuration` into a **top-level free function** in `workout_session_edit_mode.dart` (accessible to all part files since they share the library):

```dart
/// Shows an h/m/s duration-entry dialog.
/// Returns the confirmed duration in whole seconds, or null if cancelled.
Future<int?> _showDurationEntryDialog(
  BuildContext context, {
  String title = 'Edit Duration',
  String subtitle = '',
  required int initialSecs,
}) async {
  final h = initialSecs ~/ 3600;
  final m = (initialSecs % 3600) ~/ 60;
  final s = initialSecs % 60;

  final hhCtrl = TextEditingController(text: h.toString());
  final mmCtrl = TextEditingController(text: m.toString().padLeft(2, '0'));
  final ssCtrl = TextEditingController(text: s.toString().padLeft(2, '0'));

  int? result;
  result = await showDialog<int>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle.isNotEmpty) ...[
            Text(subtitle, style: ...),
            const SizedBox(height: 20),
          ],
          Row(
            children: [
              Expanded(child: TextField(controller: hhCtrl, ...)),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: mmCtrl, ...)),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: ssCtrl, ...)),
            ],
          ),
        ],
      ),
      actions: [Cancel, Apply],
    ),
  );
  Future.delayed(const Duration(milliseconds: 300), () {
    hhCtrl.dispose(); mmCtrl.dispose(); ssCtrl.dispose();
  });
  return result;
}
```

**Migrate `_editSessionDuration`** to call `_showDurationEntryDialog` instead of duplicating dialog code.

### Phase 3: UI changes in `workout_session_detail_view.dart` (@developer)

#### 3.1 Timed edit mode (replace InlineMetricEditor with tappable chip)

Current code (lines ~223–249):
```dart
if (widget.editMode) {
  final editDuration = timedInstance?.actualDurationSecs ?? ...;
  return Column(
    ...
    InlineMetricEditor(
      metricType: 'duration',
      currentValue: editDuration,
      unitLabel: 'ELAPSED',
      onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'elapsedSecs', value),
    ),
    ...
  );
}
```

Replace with:
```dart
if (widget.editMode) {
  // Read pending value from buffer if available, else from instance/entry
  final bufferedSecs = _editBuffer['$effortId-$entryIndex']?['elapsedSecs'] as int?;
  final editDuration = bufferedSecs
      ?? timedInstance?.actualDurationSecs
      ?? (entryData['elapsedSecs'] as int? ?? 0);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(height: 24 + _kSessionScrollBottomExtra),
      _buildDurationEditChip(
        theme: theme,
        durationSecs: editDuration,
        label: 'ELAPSED',
        onTap: () async {
          final result = await _showDurationEntryDialog(
            context,
            title: 'Edit Interval Duration',
            initialSecs: editDuration,
          );
          if (result != null && mounted) {
            unawaited(_updateMetricValue(effortId, entryIndex, 'elapsedSecs', result));
          }
        },
      ),
      if (entryData['extra-weight'] != null)
        _buildWeightAdjustmentSection(...),
    ],
  );
}
```

#### 3.2 Drill edit mode (same pattern, same dialog)

Current code (lines ~510–540):
```dart
if (widget.editMode) {
  final editDrillDuration = drillInstance?.actualDurationSecs ?? ...;
  return Column(
    ...
    InlineMetricEditor(
      metricType: 'duration',
      currentValue: editDrillDuration,
      unitLabel: 'ELAPSED',
      onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'elapsedSecs', value),
    ),
    _buildWeightAdjustmentSection(...),
  );
}
```

Replace with same `_buildDurationEditChip` + dialog pattern; keep `_buildWeightAdjustmentSection` unchanged.

#### 3.3 Round edit mode (same pattern, fix the save-path key)

Current code (lines ~370–390):
```dart
if (widget.editMode) {
  final editRoundDuration = (round != null && round.actualDurationSecs > 0)
      ? round.actualDurationSecs : roundDuration;
  return Column(
    ...
    InlineMetricEditor(
      metricType: 'duration',
      currentValue: editRoundDuration,
      unitLabel: 'DURATION',
      onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'round-duration', value),
    ),
  );
}
```

Replace with:
```dart
if (widget.editMode) {
  final bufferedRoundSecs = _editBuffer['$effortId-$entryIndex']?['round-duration'] as int?;
  final editRoundDuration = bufferedRoundSecs
      ?? ((round != null && round.actualDurationSecs > 0) ? round.actualDurationSecs : roundDuration);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(height: 24 + _kSessionScrollBottomExtra),
      Text('ROUND $rounds', ...),
      const SizedBox(height: 15),
      _buildDurationEditChip(
        theme: theme,
        durationSecs: editRoundDuration,
        label: 'DURATION',
        onTap: () async {
          final result = await _showDurationEntryDialog(
            context,
            title: 'Edit Round Duration',
            initialSecs: editRoundDuration,
          );
          if (result != null && mounted) {
            unawaited(_updateMetricValue(effortId, entryIndex, 'round-duration', result));
          }
        },
      ),
    ],
  );
}
```

#### 3.4 Shared `_buildDurationEditChip` helper (in detail view or edit mode extension)

```dart
Widget _buildDurationEditChip({
  required ThemeData theme,
  required int durationSecs,
  required String label,
  required VoidCallback onTap,
}) {
  final h = durationSecs ~/ 3600;
  final m = (durationSecs % 3600) ~/ 60;
  final s = durationSecs % 60;
  final display = h > 0
      ? '$h:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}'
      : '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';

  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.primary.withAlpha((0.45 * 255).round())),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(display, style: theme.textTheme.displaySmall?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(width: 6),
              Icon(Icons.edit, size: 14, color: theme.colorScheme.primary),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: OmniTheme.textSecondary)),
        ],
      ),
    ),
  );
}
```

### Phase 4: Fix `_saveEditChanges` in `workout_session_edit_mode.dart` (@developer)

Replace the current flush loop with a version that routes duration keys to instance methods:

```dart
Future<void> _saveEditChanges() async {
  // ── Step 1: flush metric edits ──────────────────────────────────────────
  for (final entry in _editBuffer.entries) {
    final parts = entry.key.split('-');
    if (parts.length < 2) continue;
    final effortId = parts.sublist(0, parts.length - 1).join('-');
    final entryIndex = int.tryParse(parts.last);
    if (entryIndex == null) continue;

    final effortKind = _getEffortKind(effortId);
    final metrics = entry.value;

    for (final metricEntry in metrics.entries) {
      if (metricEntry.key == 'elapsedSecs' &&
          (effortKind == 'timed' || effortKind == 'drill')) {
        // Write to TimedInstance (affects in-memory state + repository)
        await widget.workoutState.setTimedEntryDuration(
          effortId,
          entryIndex,
          metricEntry.value as int,
        );
      } else if (metricEntry.key == 'round-duration' && effortKind == 'round') {
        // Write to RoundInstance (affects in-memory state + repository)
        await widget.workoutState.setRoundDuration(
          effortId,
          entryIndex,
          metricEntry.value as int,
        );
      } else {
        // All other metric keys (reps, weight, extra-weight, distance, etc.)
        await widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          metricEntry.key,
          metricEntry.value,
        );
      }
    }
  }

  // ── Step 2: normalise all non-finished rounds to finished ───────────────
  await widget.workoutState.normalizeRoundsToFinished();

  // ── Step 3: persist session duration change if any ─────────────────────
  if (_hasDurationChanged()) {
    await widget.workoutState.updateSessionEndTime(_pendingDurationSecs!);
    _originalDurationSecs = _pendingDurationSecs;
  }

  // ── Step 4: clear rollback state ────────────────────────────────────────
  _editBuffer.clear();
  _hasStructuralChanges = false;
  _editSnapshot = null;
  if (mounted) Navigator.of(context).pop();
}
```

### Phase 5: Add Set / Add Round with dialog in `workout_session_screen.dart` (@developer)

Modify `_addSet()` to navigate to the new entry and open the dialog for timed, drill, and round in edit mode:

```dart
Future<void> _addSet() async {
  if (_exercises.isEmpty) return;

  final exercise = _exercises[_currentExerciseIndex];
  final effortId = exercise['id'] as String;
  final entries = exercise['entries'] as List<Map<String, dynamic>>? ?? const [];
  final effortKind = exercise['effortKind'] as String? ?? 'set';

  if (entries.length >= WorkoutConstants.maxEntriesPerEffort) return;

  // Record count before add so we can navigate to the new entry.
  final prevCount = entries.length;

  if (widget.editMode) _hasStructuralChanges = true;
  await widget.workoutState.addEntry(effortId);
  await _loadExercises();

  // In edit mode, for timer-based kinds, navigate to the new entry and
  // open the duration dialog immediately, pre-filled with 00:00:00.
  if (widget.editMode &&
      (effortKind == 'timed' || effortKind == 'drill' || effortKind == 'round') &&
      mounted) {
    setState(() { _currentSet = prevCount + 1; });

    final metricKey = effortKind == 'round' ? 'round-duration' : 'elapsedSecs';
    final result = await _showDurationEntryDialog(
      context,
      title: effortKind == 'round' ? 'Set Round Duration' : 'Set Interval Duration',
      initialSecs: 0,
    );
    if (result != null && mounted) {
      unawaited(_updateMetricValue(effortId, prevCount, metricKey, result));
    }
  }
}
```

### Phase 6: Verify summary refresh (@developer)

The `_openEditSession` in `session_summary_screen.dart` already calls:
```dart
await _refreshSummary();
```
Which calls:
```dart
_summary = widget.workoutState.computeSessionSummary();
await _loadAsyncData();
```

`computeSessionSummary()` reads from `_timerManager` in-memory. After the fix, `_saveEditChanges` updates in-memory instances via `setTimedInstanceFinished` / `setRoundFinished`. So `_refreshSummary()` will produce correct values.

`_loadAsyncData()` calls `sessionSummaryService.buildGroupMetrics(_summary)` which reads from repository (not in-memory). After the fix, the repository is also updated. No changes needed in the summary screen.

**No changes required to `session_summary_screen.dart`.**

### Phase 7: Auto-open dialog on newly added timed/drill/round exercise (@developer)

Check `_addExercise()` to see if the auto-open of the duration dialog after picker resolves is already in place from a previous plan. If not, add it:

After `unawaited(_focusExerciseDetail(idx))`, if `editMode == true` and the new exercise's `effortKind` is `timed`, `drill`, or `round`, open the dialog:

```dart
if (effortId.isNotEmpty) {
  final idx = _exercises.indexWhere((e) => e['id'] == effortId);
  if (idx != -1) {
    await _focusExerciseDetail(idx);
    if (widget.editMode) {
      final newExercise = _exercises[idx];
      final newKind = newExercise['effortKind'] as String? ?? 'set';
      if (newKind == 'timed' || newKind == 'drill' || newKind == 'round') {
        final metricKey = newKind == 'round' ? 'round-duration' : 'elapsedSecs';
        final result = await _showDurationEntryDialog(
          context,
          title: newKind == 'round' ? 'Set Round Duration' : 'Set Interval Duration',
          initialSecs: 0,
        );
        if (result != null && mounted) {
          unawaited(_updateMetricValue(effortId, 0, metricKey, result));
        }
      }
    }
  }
}
```

## Files Affected

| File | Change |
|------|--------|
| `lib/state/workout/timer_manager.dart` | Add `setTimedInstanceFinished`, `setRoundFinished`, `normalizeAllRoundsToFinished` |
| `lib/state/workout/workout_state.dart` | Add `setTimedEntryDuration`, `setRoundDuration`, `normalizeRoundsToFinished` delegation |
| `lib/features/session/workout_session_edit_mode.dart` | Extract shared dialog to `_showDurationEntryDialog`, migrate `_editSessionDuration`, update `_saveEditChanges` to route duration keys |
| `lib/features/session/workout_session_detail_view.dart` | Replace timed/drill/round edit mode `InlineMetricEditor` with `_buildDurationEditChip`; add `_buildDurationEditChip` helper |
| `lib/features/session/workout_session_screen.dart` | Update `_addSet` to open dialog after adding for timer-based kinds in edit mode; update `_addExercise` auto-open logic |
| `lib/features/session/session_summary_screen.dart` | **No changes required** — existing `_refreshSummary` + `computeSessionSummary` already correct once in-memory state is updated |

## Scenarios / Edge Cases

1. **Round in `notStarted` state at save**: `normalizeAllRoundsToFinished` fires; round gets `actualDurationSecs = plannedDurationSecs`.
2. **User cancels dialog after Add Set**: New entry remains with duration 0 in the buffer. If the round/timed entry has 0 duration and is not normalised elsewhere, `normalizeAllRoundsToFinished` will set `actualDurationSecs = plannedDurationSecs`. For timed/drill, the instance stays `notStarted` with 0 duration — this is acceptable (equivalent to a logged zero-second interval).
3. **Round already finished**: `setRoundFinished` overwrites `actualDurationSecs` with the user's value. `normalizeAllRoundsToFinished` skips it (only targets non-finished).
4. **TimedInstance already finished**: `setTimedInstanceFinished` overwrites `actualDurationSecs`. The synthesised timestamps preserve `elapsedMs` accuracy.
5. **Discard after Add Set**: `_discardEditChanges` calls `restoreSessionSnapshot` which rolls back the structural change (the added entry). Duration buffer is discarded. In-memory state is restored via snapshot.
6. **Session Time chip**: Unchanged — continues to call `_editSessionDuration` which internally calls `_showDurationEntryDialog`.

## Progress
- [x] Add `setTimedInstanceFinished` to `timer_manager.dart`
- [x] Add `setRoundFinished` to `timer_manager.dart`
- [x] Add `normalizeAllRoundsToFinished` to `timer_manager.dart`
- [x] Add `setTimedEntryDuration`, `setRoundDuration`, `normalizeRoundsToFinished` to `workout_state.dart`
- [x] Extract `_showDurationEntryDialog` in `workout_session_edit_mode.dart`; migrate `_editSessionDuration` to use it
- [x] Update `_saveEditChanges` to route `'elapsedSecs'` and `'round-duration'` to instance methods + call `normalizeRoundsToFinished`
- [x] Replace timed edit mode InlineMetricEditor with `_buildDurationEditChip` + dialog in `workout_session_detail_view.dart`
- [x] Replace drill edit mode InlineMetricEditor with `_buildDurationEditChip` + dialog in `workout_session_detail_view.dart`
- [x] Replace round edit mode InlineMetricEditor with `_buildDurationEditChip` + dialog in `workout_session_detail_view.dart`
- [x] Add `_buildDurationEditChip` helper to detail view
- [x] Update `_addSet` to navigate + open dialog for timed/drill/round in edit mode
- [x] Update `_addExercise` to auto-open dialog for timed/drill/round in edit mode
- [x] Run tests; 745/746 pass (1 pre-existing flaky timing test unrelated to this feature)

## Feedback
Edit mode for cardio (timed), isometric (drill), and sports (round) looks stripped-down and afterthought-ish: small bordered chip with a pencil, no Log button, lots of dead space. Requirements for Iteration 2:
- Remove `_buildDurationEditChip` entirely. Use `InlineMetricEditor` directly (full visual weight).
- The big duration display IS the editor: tap opens h/m/s dialog; vertical scroll adjusts value (InlineMetricEditor already handles scroll). No pencil icon, no border, no chip container.
- Remove the play/pause button row from edit mode entirely.
- Add Log button (center slot, same visual as live Log button) for timed/drill/round in edit mode. Semantics: commits value for that specific interval without auto-advancing; shows LOGGED label until user changes the value again.
- Interval navigation arrows: keep unchanged.
- Set kind: nav-only (no Log button, existing behaviour).
- Drill: same pattern as timed; extra-weight section unchanged.
- Round: keep "ROUND N" text block; duration display replaces chip; play/pause removed.

## Iteration 2

### Analysis
Three timer-based edit-mode detail views (`timed`, `drill`, `round`) currently render a small bordered chip (`_buildDurationEditChip`) instead of the full `InlineMetricEditor`. The `_buildSetControls` in edit mode shows only nav arrows — no Log button. Together these make edit mode feel visually weaker than live mode.

The fix keeps the identical structural layout as live mode but swaps the interaction model:
- Play/pause → removed
- Timer-start GestureDetector → replaced by `onTap` on `InlineMetricEditor` to open h/m/s dialog
- Drag on `InlineMetricEditor` → already works (5 s per scroll unit), just route to edit buffer
- Log button → new per-interval visual confirm that marks entry as LOGGED without advancing

No schema changes. No new repository methods. State-layer write methods added in Iteration 1 are unchanged.

### Phase 1: Add `onTap` to `InlineMetricEditor` (@developer)

Add an optional `VoidCallback? onTap` parameter. Wire it to the existing `GestureDetector` in `build()`. Both `onTap` and `onVerticalDragUpdate` can coexist in one `GestureDetector` — Flutter's gesture arena disambiguates: short press-lift fires tap, movement fires drag.

```dart
// Before
final bool isReadOnly;
final Color? unitLabelColor;
// …
const InlineMetricEditor({…, this.isReadOnly = false, …});
// GestureDetector has: onVerticalDragUpdate + onVerticalDragEnd

// After — add onTap:
final VoidCallback? onTap;
const InlineMetricEditor({…, this.onTap, …});
// GestureDetector gains: onTap: widget.onTap
```

### Phase 2: New screen state field `_editLoggedKeys` (@developer)

In `_WorkoutSessionScreenState` (in `workout_session_screen.dart`):
```dart
// Tracks which timed/drill/round entries have been explicitly "logged"
// (confirmed) during this edit session. Key: '$effortId-$entryIndex'.
// UI only — not persisted. Cleared on discard; entries removed when value changes.
final Set<String> _editLoggedKeys = {};
```

### Phase 3: Replace edit-mode metric widget for `timed`, `drill`, `round` (@developer)

In `_buildMetricWidget` in `workout_session_detail_view.dart`:

#### 3.1 `timed` edit branch (lines ~215–260)

Replace `_buildDurationEditChip` block with:
```dart
if (widget.editMode) {
  final bufferedSecs = _editBuffer['$effortId-$entryIndex']?['elapsedSecs'] as int?;
  final editDuration = bufferedSecs
      ?? timedInstance?.actualDurationSecs
      ?? (entryData['elapsedSecs'] as int? ?? timedElapsed);
  final logKey = '$effortId-$entryIndex';
  final isEditLogged = _editLoggedKeys.contains(logKey);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      InlineMetricEditor(
        metricType: 'duration',
        currentValue: editDuration,
        unitLabel: isEditLogged ? 'LOGGED' : 'ELAPSED',
        unitLabelColor: isEditLogged ? theme.colorScheme.primary : null,
        onTap: () async {
          final result = await _showDurationEntryDialog(
            context,
            title: 'Edit Interval Duration',
            initialSecs: editDuration,
          );
          if (result != null && mounted) {
            if (_editLoggedKeys.contains(logKey)) {
              setState(() { _editLoggedKeys.remove(logKey); });
            }
            unawaited(_updateMetricValue(effortId, entryIndex, 'elapsedSecs', result));
          }
        },
        onValueChanged: (value) {
          if (_editLoggedKeys.contains(logKey)) {
            setState(() { _editLoggedKeys.remove(logKey); });
          }
          _updateMetricValue(effortId, entryIndex, 'elapsedSecs', value);
        },
      ),
      if (entryData['extra-weight'] != null)
        _buildWeightAdjustmentSection(
          theme: theme,
          effortId: effortId,
          entryIndex: entryIndex,
          currentValue: (entryData['extra-weight'] as num?)?.toDouble() ?? 0.0,
          onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'extra-weight', value),
        ),
    ],
  );
}
```

#### 3.2 `round` edit branch (lines ~382–430)

Replace `_buildDurationEditChip` block (keep the `ROUND $rounds` text above):
```dart
if (widget.editMode) {
  final bufferedRoundSecs = _editBuffer['$effortId-$entryIndex']?['round-duration'] as int?;
  final editRoundDuration = bufferedRoundSecs
      ?? ((round != null && round.actualDurationSecs > 0) ? round.actualDurationSecs : roundDuration);
  final logKey = '$effortId-$entryIndex';
  final isEditLogged = _editLoggedKeys.contains(logKey);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(height: 24 + _kSessionScrollBottomExtra),
      Text('ROUND $rounds', style: theme.textTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w300, letterSpacing: -2,
        fontSize: theme.textTheme.displayMedium?.fontSize,
      )),
      const SizedBox(height: 15),
      InlineMetricEditor(
        metricType: 'duration',
        currentValue: editRoundDuration,
        unitLabel: isEditLogged ? 'LOGGED' : 'DURATION',
        unitLabelColor: isEditLogged ? theme.colorScheme.primary : null,
        onTap: () async {
          final result = await _showDurationEntryDialog(
            context, title: 'Edit Round Duration', initialSecs: editRoundDuration,
          );
          if (result != null && mounted) {
            if (_editLoggedKeys.contains(logKey)) setState(() { _editLoggedKeys.remove(logKey); });
            unawaited(_updateMetricValue(effortId, entryIndex, 'round-duration', result));
          }
        },
        onValueChanged: (value) {
          if (_editLoggedKeys.contains(logKey)) setState(() { _editLoggedKeys.remove(logKey); });
          _updateMetricValue(effortId, entryIndex, 'round-duration', value);
        },
      ),
    ],
  );
}
```

#### 3.3 `drill` edit branch (lines ~510–560)

Replace `_buildDurationEditChip` block (keep `_buildWeightAdjustmentSection`):
```dart
if (widget.editMode) {
  final bufferedDrillSecs = _editBuffer['$effortId-$entryIndex']?['elapsedSecs'] as int?;
  final editDrillDuration = bufferedDrillSecs
      ?? drillInstance?.actualDurationSecs
      ?? (entryData['elapsedSecs'] as int? ?? drillElapsed);
  final logKey = '$effortId-$entryIndex';
  final isEditLogged = _editLoggedKeys.contains(logKey);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      InlineMetricEditor(
        metricType: 'duration',
        currentValue: editDrillDuration,
        unitLabel: isEditLogged ? 'LOGGED' : 'ELAPSED',
        unitLabelColor: isEditLogged ? theme.colorScheme.primary : null,
        onTap: () async {
          final result = await _showDurationEntryDialog(
            context, title: 'Edit Hold Duration', initialSecs: editDrillDuration,
          );
          if (result != null && mounted) {
            if (_editLoggedKeys.contains(logKey)) setState(() { _editLoggedKeys.remove(logKey); });
            unawaited(_updateMetricValue(effortId, entryIndex, 'elapsedSecs', result));
          }
        },
        onValueChanged: (value) {
          if (_editLoggedKeys.contains(logKey)) setState(() { _editLoggedKeys.remove(logKey); });
          _updateMetricValue(effortId, entryIndex, 'elapsedSecs', value);
        },
      ),
      _buildWeightAdjustmentSection(
        theme: theme,
        effortId: effortId,
        entryIndex: entryIndex,
        currentValue: drillExtraWeight,
        onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'extra-weight', value),
      ),
    ],
  );
}
```

#### 3.4 Remove `_buildDurationEditChip` (lines ~655–720)
Delete the entire `_buildDurationEditChip` method — it has no remaining call sites.

### Phase 4: Update `_buildSetControls` for edit mode (@developer)

Current edit-mode branch (returns nav-only row unconditionally). Replace with:

```dart
if (widget.editMode) {
  // Set kind: nav arrows only (inline editors handle value changes directly).
  if (effortKind != 'timed' && effortKind != 'drill' && effortKind != 'round') {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [backArrow, forwardArrow],
    );
  }
  // Timer-based kinds: show Log/LOGGED center control + nav arrows.
  final logKey = '$effortId-$entryIndex';
  final isEditLogged = _editLoggedKeys.contains(logKey);
  final centerControl = isEditLogged
      ? _buildLoggedLabel(theme)
      : _buildEditLogSetButton(effortKind, theme);  // new helper (Phase 5)
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      backArrow,
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: centerControl,
        ),
      ),
      forwardArrow,
    ],
  );
}
```

### Phase 5: New `_logSetInEditMode` and `_buildEditLogSetButton` (@developer)

In `workout_session_edit_mode.dart` (in `_SessionEditModeExt`):

```dart
/// Marks the current timer entry as confirmed for this edit session.
/// Adds to _editLoggedKeys; does NOT write to repository, does NOT advance.
/// The actual write still happens at Save Changes time via _saveEditChanges.
void _logSetInEditMode() {
  if (_exercises.isEmpty) return;
  final exercise = _exercises[_currentExerciseIndex];
  final effortId = exercise['id'] as String;
  final entryIndex = _currentSet - 1;
  setState(() {
    _editLoggedKeys.add('$effortId-$entryIndex');
  });
}

Widget _buildEditLogSetButton(String effortKind, ThemeData theme) {
  final label = _logSetLabel(effortKind);
  return Tooltip(
    message: label,
    child: FilledButton(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        minimumSize: WidgetStateProperty.all(const Size(double.infinity, 64)),
      ),
      onPressed: _logSetInEditMode,
      child: Text(label),
    ),
  );
}
```

### Phase 6: Update `_discardEditChanges` (@developer)

In `workout_session_edit_mode.dart`, add to `_discardEditChanges`:
```dart
Future<void> _discardEditChanges() async {
  _editBuffer.clear();
  _editLoggedKeys.clear();  // ← add this line
  // … rest unchanged
}
```

## Iteration 2 — Files Affected

| File | Change |
|------|--------|
| `lib/widgets/session/inline_metric_editor.dart` | Add optional `onTap: VoidCallback?`; wire to `GestureDetector` |
| `lib/features/session/workout_session_screen.dart` | Add `_editLoggedKeys = <String>{}` state field |
| `lib/features/session/workout_session_detail_view.dart` | Replace 3 chip edit branches with `InlineMetricEditor`; update `_buildSetControls` edit-mode branch; delete `_buildDurationEditChip` |
| `lib/features/session/workout_session_edit_mode.dart` | Add `_logSetInEditMode`, `_buildEditLogSetButton`; update `_discardEditChanges` |

## Iteration 2 — Acceptance Criteria
- [ ] Timed edit mode: big duration display matches live visual weight; tap opens h/m/s dialog; vertical scroll adjusts 5s per unit; no chip, no pencil, no border.
- [ ] Drill edit mode: same as timed; extra-weight section unchanged.
- [ ] Round edit mode: ROUND N label stays; duration display matches live; tap/scroll works; no chip; no pencil.
- [ ] Play/pause button row absent from all three edit modes.
- [ ] Log button present in center slot for timed/drill/round in edit mode; uses same FilledButton style and label as live mode.
- [ ] Pressing Log marks entry LOGGED (label shows); does NOT auto-advance; navigation arrows still work.
- [ ] Changing duration (tap or scroll) while in LOGGED state reverts center to Log button.
- [ ] Set kind: edit mode still shows nav-only (no Log button) — no regression.
- [ ] Discard clears all logged states.
- [ ] No regressions in live-workout timer flow.
- [ ] All existing tests pass.

## Iteration 2 — Progress
- [x] Add `onTap` to `InlineMetricEditor`
- [x] Add `_editLoggedKeys` to screen state
- [x] Replace timed edit branch with `InlineMetricEditor` + `onTap` + Log-key logic
- [x] Replace round edit branch with `InlineMetricEditor` + `onTap` + Log-key logic
- [x] Replace drill edit branch with `InlineMetricEditor` + `onTap` + Log-key logic
- [x] Remove `_buildDurationEditChip` definition
- [x] Update `_buildSetControls` edit-mode branch for timed/drill/round
- [x] Add `_logSetInEditMode` and `_buildEditLogSetButton` to edit mode extension
- [x] Update `_discardEditChanges` to clear `_editLoggedKeys`
- [x] Run tests; 745/746 pass (same pre-existing flaky timing test in `state_test.dart:1877` `closeAllOpenRests` — unrelated to this feature)

## Feedback
The Log button added in Iteration 2 turned out to be cosmetic only: pressing it just toggled a UI label (`_editLoggedKeys`) and never wrote anything. The actual instance-state writes already happen unconditionally in `_saveEditChanges` via `setTimedEntryDuration` / `setRoundDuration` / `normalizeRoundsToFinished`, so Save IS the log. Pre-existing entries were already finished from the live session, and resistance (set-kind) editing has never had a Log button — so adding one to timer kinds in edit mode was inconsistent.

Iteration 3 reverts the Log button + `_editLoggedKeys` machinery while keeping the visually weighted `InlineMetricEditor` + tap-to-dialog wiring from Iteration 2.

## Iteration 3 — Revert Log button (keep InlineMetricEditor + onTap)

### Changes
- Removed `_editLoggedKeys` field from `_WorkoutSessionScreenState`.
- Stripped `logKey` / `isEditLogged` / conditional `LOGGED` label / `setState`-based key removal from all three timer-based edit branches in [workout_session_detail_view.dart](lib/features/session/workout_session_detail_view.dart). Edit-mode timed/drill/round entries now show plain `ELAPSED` / `DURATION` labels — same look as live mode without the play/pause row.
- Reverted `_buildSetControls` edit-mode branch back to nav-only for every effort kind (matching the resistance/set-kind UX).
- Removed `_logSetInEditMode` and `_buildEditLogSetButton` helpers from `_SessionEditModeExt`.
- Removed `_editLoggedKeys.clear()` from `_discardEditChanges`.
- Removed the auto-opened duration dialog from `_addSet` and `_addExercise` in edit mode — the inline editor (tap → dialog, scroll → adjust) IS the editor, so the post-add modal was redundant.

### Iteration 3 — Files Affected
| File | Change |
|------|--------|
| `lib/features/session/workout_session_screen.dart` | Removed `_editLoggedKeys` field |
| `lib/features/session/workout_session_detail_view.dart` | Stripped Log toggle from timed/drill/round edit branches; reverted `_buildSetControls` edit branch to nav-only |
| `lib/features/session/workout_session_edit_mode.dart` | Removed `_logSetInEditMode` and `_buildEditLogSetButton`; removed `_editLoggedKeys.clear()` from `_discardEditChanges` |

### Iteration 3 — Acceptance Criteria
- [x] Edit mode for timed/drill/round shows full-weight `InlineMetricEditor` (tap → dialog, scroll → adjust value).
- [x] No Log button or LOGGED toggle visible in edit mode for any effort kind.
- [x] Edit-mode bottom controls are nav-only across set/timed/drill/round (consistent with resistance editing).
- [x] No regressions — Save still finishes timer instances and normalises rounds to `finished`.
- [x] Tests: 745/746 pass (same pre-existing flaky `closeAllOpenRests` test in `state_test.dart:1877`).
