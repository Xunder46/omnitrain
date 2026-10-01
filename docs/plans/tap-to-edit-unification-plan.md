# Plan: Tap-to-Edit Unification (All Three Surfaces)

## Overview

Unify the tap-to-edit interaction for every editable metric across the three
editing surfaces: active session (`WorkoutSessionScreen` live mode), routine
creation (`RoutineSetupScreen`), and historical session edit
(`WorkoutSessionScreen` with `editMode: true`).

### Current state (post Iteration 2 of tap-to-edit-metric-modal-plan)

**Active session — live mode (set effort)**: Tapping reps or weight opens
`showMetricEditPopup` (single "Ok" numeric modal). Correct.

**Active session — live mode (timed/round/drill)**: The outer
`GestureDetector` wrapping the timer column was removed in Iteration 2, and
`isReadOnly: true` was removed from those `InlineMetricEditor` instances. This
means tapping the timer value **does** open `showMetricEditPopup`. However
`showMetricEditPopup` shows a raw-seconds numeric field — not the h/m/s editor.
The spec requires the h/m/s time editor for duration inputs.

**Active session — edit mode (timed/round/drill)**: `onTap` is set on the
`InlineMetricEditor`, calling `_showDurationEntryDialog` (h/m/s). Correct
except `_showDurationEntryDialog` still has a "Cancel" button, which the spec
says must be removed (modal must have only "Ok"; outside-tap dismisses without
applying).

**Routine creation — set effort (reps/weight)**: Falls through to
`showMetricEditPopup`. Correct.

**Routine creation — round effort (duration)**: `InlineMetricEditor` with
`metricType: 'duration'` has no `onTap` — falls through to
`showMetricEditPopup`, which shows a raw-seconds field. Must use the h/m/s
editor instead.

**Routine creation — timed/drill effort**: Shows extra-weight only (no
duration target), falls through to `showMetricEditPopup`. Correct for
`extra-weight`.

**Historical edit (timed/round/drill)**: `onTap` calls
`_showDurationEntryDialog`. Correct except the "Cancel" button in
`_showDurationEntryDialog` must be removed.

### What must change

1. **Extract `_showDurationEntryDialog` into a shared function** accessible
   from both `WorkoutSessionScreen` part files AND `RoutineSetupScreen`. It
   currently lives as a `part of` free function in `workout_session_edit_mode.dart`,
   making it inaccessible to `RoutineSetupScreen`. Move it (or duplicate as a
   shared widget-layer function) to a location both screens can import.

2. **Remove "Cancel" from `_showDurationEntryDialog`** — bring it in line with
   the single-"Ok" spec. Rename "Apply" to "Ok". Outside-tap continues to
   dismiss without saving (Flutter `barrierDismissible: true` default).

3. **Wire duration `InlineMetricEditor` in `RoutineSetupScreen` (round effort)**
   to use `onTap: () async { ... _showDurationEntryDialog(...) }` instead of
   falling through to `showMetricEditPopup`.

4. **Wire duration `InlineMetricEditor` in active session live mode
   (timed/round/drill)** to use `onTap: () async { ... _showDurationEntryDialog(...) }`
   instead of falling through to `showMetricEditPopup`. These cases already had
   their `isReadOnly: true` removed; they just need the `onTap` added.

5. **Confirm the numeric keyboard for `weight` permits minus** — the current
   `_MetricEditDialog` uses `TextInputType.numberWithOptions(signed: true, decimal: true)`.
   This is already in place. No change needed.

6. **Confirm reps uses positive-only keyboard** — the current
   `_MetricEditDialog` passes the same keyboard options for all metric types,
   which allows a minus sign for reps. The keyboard must switch based on
   `metricType`: use `signed: false` for `'reps'` and other non-negative metrics.
   `weight` and `extra-weight` keep `signed: true`.

7. **Update tests** to cover the unified behavior on all three surfaces, the
   duration editor component identity guard, and the keyboard polarity
   difference.

---

## Scenarios

### S-001: Tapping a reps metric on any surface
- Trigger: User taps the displayed reps value
- Precondition: Metric is editable (not read-only)
- Flow: Single `AlertDialog` opens, pre-filled with current rep count; keyboard is positive-only (no minus key); user types value; taps "Ok"; dialog closes; value is applied
- Expected outcome: `onValueChanged` fires with the new int; if user taps outside, nothing changes
- Edge case of: none

### S-002: Tapping a weight/load metric on any surface
- Trigger: User taps the displayed weight value
- Precondition: Metric is editable
- Flow: Single `AlertDialog` opens, pre-filled with current weight; keyboard permits minus sign; user types e.g. `-50.0`; taps "Ok"; dialog closes; negative value applied
- Expected outcome: `onValueChanged` fires with negative double; reps dialog does NOT allow this
- Edge case of: none

### S-003: Tapping a duration metric on any surface (historical edit, routine, active-session live timed/round/drill)
- Trigger: User taps the displayed time value
- Precondition: Metric is editable
- Flow: Single h/m/s `AlertDialog` opens (the existing `_showDurationEntryDialog` UI), pre-filled with current seconds decomposed into h/m/s fields; user edits fields; taps "Ok"; dialog closes; seconds value applied
- Expected outcome: `onValueChanged` fires with total seconds; if user taps outside, nothing changes; "Cancel" button is NOT present
- Edge case of: none

### S-004: Tapping a timed metric in active session live mode
- Trigger: User taps the elapsed-seconds display (timed, round, or drill effort in live non-edit mode)
- Precondition: Timer is not suppressed by `isReadOnly`; no outer `GestureDetector` intercepts tap
- Flow: Tap opens h/m/s modal for the relevant metric (`elapsedSecs` for timed/drill, `round-duration` for round); user enters value; "Ok" applies; timer continues from new value
- Expected outcome: `_updateMetricValue` called with new seconds; timer does NOT toggle (Start control is separate)
- Edge case of: S-003

### S-005: Outside-tap dismisses any metric modal without applying
- Trigger: User taps outside the dialog barrier
- Precondition: Any metric edit dialog is open
- Flow: `showDialog` barrier tap fires; dialog closes; `onValueChanged` is never called
- Expected outcome: No state change; screen returns to normal
- Edge case of: S-001, S-002, S-003

---

## Files to Change

### 1. `lib/widgets/session/metric_crown_widget.dart`

**`_MetricEditDialog` — keyboard polarity per metric type**

In `_MetricEditDialogState.build`, the `NumericFieldWithDoneBar` currently uses
`TextInputType.numberWithOptions(signed: true, decimal: true)` for all metric
types. Change to conditionally set `signed`:

- `'weight'`, `'extra-weight'`: `signed: true, decimal: true`
- `'reps'`, `'duration'`, `'rpe'`, all others: `signed: false, decimal: false` (or `decimal: true` where sensible, but no signed)

This is the only behavioral change to `_MetricEditDialog`; the "Ok" button is
already the sole action (Iteration 2 already removed Cancel).

### 2. `lib/widgets/session/duration_entry_dialog.dart` (NEW FILE)

Extract the h/m/s dialog into a shared function importable from anywhere:

```dart
/// Shared h/m/s duration-entry dialog used by WorkoutSessionScreen (live and
/// edit modes) and RoutineSetupScreen (round/timed targets).
///
/// Returns the confirmed duration in whole seconds, or null if dismissed
/// without confirming. There is NO Cancel button; tapping outside the dialog
/// barrier dismisses without applying.
Future<int?> showDurationEntryDialog(
  BuildContext context, {
  String title = 'Edit Duration',
  String subtitle = '',
  required int initialSecs,
}) async { ... }
```

The dialog content is identical to the current `_showDurationEntryDialog` in
`workout_session_edit_mode.dart` EXCEPT:
- The `TextButton` "Cancel" action is removed entirely.
- The `FilledButton` label changes from "Apply" to "Ok".
- The function is exported as a public top-level function.

### 3. `lib/features/session/workout_session_edit_mode.dart`

- Remove the private `_showDurationEntryDialog` free function.
- Add an import for the new shared `showDurationEntryDialog`.
- Replace all six call sites of `_showDurationEntryDialog` with `showDurationEntryDialog` (same signature, same arguments).

### 4. `lib/features/session/workout_session_detail_view.dart`

**Active session live-mode timed/round/drill — add `onTap` for duration editor**

For each of the three live-mode branches in `_buildMetricWidget`:

- `'timed'` live-mode `InlineMetricEditor`: add `onTap: () async { final result = await showDurationEntryDialog(context, title: 'Edit Elapsed', initialSecs: timedDisplayValue); if (result != null && mounted) { _updateMetricValue(effortId, entryIndex, 'elapsedSecs', result); } }`. Remove `onValueChanged: isTimedFinished ? (_) {} : ...` and replace with a no-op `onValueChanged: (_) {}` (the tap path handles updates; the crown path is dormant).
- `'round'` live-mode `InlineMetricEditor`: add `onTap` for `'round-duration'` with `showDurationEntryDialog`.
- `'drill'` live-mode `InlineMetricEditor`: add `onTap` for `'elapsedSecs'` with `showDurationEntryDialog`.

When `isTimedFinished` / `isDrillFinished` / `isFinished`, set `isReadOnly: true` on the editor so finished efforts cannot be edited from live mode (they should use the edit-mode path for corrections).

Add import for `showDurationEntryDialog` from the new shared file.

### 5. `lib/features/routine/routine_setup_screen.dart`

**Round effort duration editor — add `onTap`**

In `_buildMetricWidget` for the `'round'` case, the `InlineMetricEditor` with
`metricType: 'duration'` needs:

```dart
onTap: () async {
  final result = await showDurationEntryDialog(
    context,
    title: 'Edit Round Duration',
    initialSecs: roundDuration,
  );
  if (result != null && mounted) {
    await widget.routineState.setTargetValue(
      effort.id,
      MetricIds.roundDuration,
      MetricIds.unitSeconds,
      setIndex: setIndex,
      targetInt: result,
    );
    await widget.routineState.setTargetValue(
      effort.id,
      MetricIds.rounds,
      MetricIds.unitRounds,
      setIndex: setIndex,
      targetInt: 1,
    );
  }
},
```

Move the existing `onValueChanged` async block to inside the `onTap` (the
`onValueChanged` slot becomes a no-op since the real update is via `onTap`).

Add import for `showDurationEntryDialog`.

### 6. `lib/features/session/workout_session_screen.dart`

Add import for the new `duration_entry_dialog.dart` if `workout_session_edit_mode.dart`
no longer exports the function via `part of`.

---

## Files to Create

### `lib/widgets/session/duration_entry_dialog.dart`

Public shared h/m/s dialog function. Extracted from
`workout_session_edit_mode.dart`. Single "Ok" button (no Cancel). Handles
controller lifecycle with a deferred dispose. Identical field layout (h / m / s
in a `Row`).

---

## Test Plan

### Tests to ADD

**File: `test/tap_to_edit_unification_test.dart`** (new file)

Group: `Surface parity — reps/weight open numeric modal`

- `U-01`: Active session live mode, `'set'` effort — tapping reps value opens `AlertDialog`; Ok applies; outside-tap cancels
- `U-02`: Active session live mode, `'set'` effort — tapping weight value opens `AlertDialog` with signed keyboard (check `keyboardType` on `TextField`); negative value applies
- `U-03`: Routine creation, `'set'` effort — tapping reps value opens `AlertDialog`; Ok applies; outside-tap cancels
- `U-04`: Routine creation, `'set'` effort — tapping weight value opens `AlertDialog`; signed keyboard; negative applies
- `U-05`: Historical edit (`editMode: true`), `'set'` effort — tapping reps opens `AlertDialog`; Ok applies

Group: `Duration inputs use h/m/s dialog, not raw-seconds modal`

- `U-06`: Routine creation, `'round'` effort — tapping duration value opens the h/m/s dialog (assert the dialog contains three `TextField` instances for h/m/s, not one); Ok applies seconds total; outside-tap cancels
- `U-07`: Active session live mode, `'timed'` effort — tapping elapsed value opens h/m/s dialog (three `TextField`s); does NOT toggle timer state
- `U-08`: Active session live mode, `'round'` effort — tapping duration value opens h/m/s dialog; does NOT toggle timer
- `U-09`: Active session live mode, `'drill'` effort — tapping elapsed value opens h/m/s dialog; does NOT toggle timer
- `U-10`: Historical edit, `'timed'` effort — tapping elapsed value opens h/m/s dialog; Ok applies; no Cancel button present
- `U-11`: Historical edit, `'round'` effort — tapping duration value opens h/m/s dialog; Ok applies; no Cancel button present
- `U-12`: Historical edit, `'drill'` effort — tapping elapsed value opens h/m/s dialog; Ok applies; no Cancel button present

Group: `Duration dialog identity guard`

- `U-13`: In any surface where duration tap is expected, assert the dialog contains exactly three `TextField` instances (h/m/s), confirming `showDurationEntryDialog` was used and not `showMetricEditPopup` (which produces a single `TextField`)
- `U-14`: `showDurationEntryDialog` (called directly) returns total seconds = `h*3600 + m*60 + s` from entered values

Group: `Reps keyboard is positive-only`

- `U-15`: `_MetricEditDialog` for `metricType: 'reps'` has `TextInputType` with `signed: false`
- `U-16`: `_MetricEditDialog` for `metricType: 'weight'` has `TextInputType` with `signed: true`

Group: `Single Ok, no Cancel on all modal surfaces`

- `U-17`: `showMetricEditPopup` dialog (reps) has exactly one button "Ok", no "Cancel" — already tested in T-13; reference that assertion here or add a parallel cross-surface assertion
- `U-18`: `showDurationEntryDialog` dialog has exactly one "Ok" button (a `FilledButton`) and no "Cancel" button

Group: `Active session timer does not start on metric tap`

- `U-07` through `U-09` above also explicitly assert `_toggleEffortTimer` was NOT called (no timer state change after modal is closed)

### Tests to UPDATE

**`test/crown_control_tap_to_edit_test.dart`**

- `T-10b`: Currently asserts a custom `onTap` on a `duration` editor delegates correctly — keep as-is; it remains valid.
- Any test that asserts timed `InlineMetricEditor` is `isReadOnly: true` in live mode: remove that assertion (live-mode editors are no longer read-only; finished efforts get `isReadOnly: true` instead).

**`test/interaction_flow_test.dart`** / **`test/session_toolbar_rework_test.dart`**

- Any test that asserts timer toggling via a tap on the timer value display (formerly `GestureDetector` key `'timer-gesture-detector'`): these were already updated in Iteration 2 to use the Start button; verify they still pass after the `onTap`-for-duration is added.

### Tests to leave untouched

- All `MetricStepCalc` unit tests
- T-07, T-08, T-09 (crown rotation mechanics — dormant widget)
- T-G01 (crown codebase guard)
- T-W01 through T-W04, T-NW01 through T-NW03 (negative weight / reps clamping)
- All Set X of Y stepper tests
- Rest timer tests
- Navigation / swipe tests

---

## Progress

- [x] Phase 1: Extract `showDurationEntryDialog` to `lib/widgets/session/duration_entry_dialog.dart` — remove Cancel, rename Apply to Ok
- [x] Phase 2: Update `workout_session_edit_mode.dart` — delete private function, import shared one, update call sites
- [x] Phase 3: Update `workout_session_screen.dart` — add import for `duration_entry_dialog.dart`
- [x] Phase 4: Update `workout_session_detail_view.dart` — add `onTap` for live timed/round/drill duration editors; set `isReadOnly: true` for finished efforts in live mode
- [x] Phase 5: Update `routine_setup_screen.dart` — add `onTap` for round duration editor; import shared function
- [x] Phase 6: Update `metric_crown_widget.dart` — keyboard polarity per metric type (`signed: false` for reps/duration/rpe, `signed: true` for weight/extra-weight)
- [x] Phase 7: Write `test/tap_to_edit_unification_test.dart` — 15 tests covering U-01 through U-18
- [x] Phase 8: Update `test/session_edit_duration_test.dart` — replaced 'Cancel' tap with barrier tap, 'Apply' with 'Ok'
- [x] Phase 9: Run full `flutter test` — all 1078 tests pass

**Status: Complete**

---

## Acceptance Criteria

- [ ] On active session live mode, routine creation, AND historical edit — tapping any editable reps or weight metric opens a single-"Ok" numeric `AlertDialog`; no Cancel button; outside-tap dismisses without applying
- [ ] Weight/load modal keyboard permits minus sign (`signed: true`); negative values apply correctly
- [ ] Reps modal keyboard is positive-only (`signed: false`); reps modal has `signed: false` on its `TextInputType`
- [ ] Duration/time tap on ALL three surfaces opens the shared h/m/s `showDurationEntryDialog` dialog (three `TextField` instances), not the single-field `showMetricEditPopup`
- [ ] `showDurationEntryDialog` has exactly one "Ok" button (FilledButton) and no Cancel button
- [ ] Tapping a timed metric in live active session mode opens the h/m/s modal and does NOT start/toggle the timer
- [ ] The crown remains absent from the UI and present in code (unchanged)
- [ ] The Set X of Y stepper behavior is unchanged
- [ ] All value math, bounds, and step increments are unchanged

---

## Files Affected Summary

| File | Action |
|------|--------|
| `lib/widgets/session/duration_entry_dialog.dart` | CREATE — shared h/m/s dialog |
| `lib/widgets/session/metric_crown_widget.dart` | MODIFY — keyboard polarity per metric type |
| `lib/features/session/workout_session_edit_mode.dart` | MODIFY — replace private function with import |
| `lib/features/session/workout_session_screen.dart` | MODIFY — add import if needed |
| `lib/features/session/workout_session_detail_view.dart` | MODIFY — add onTap for live timed/round/drill |
| `lib/features/routine/routine_setup_screen.dart` | MODIFY — add onTap for round duration |
| `test/tap_to_edit_unification_test.dart` | CREATE — parameterized surface tests |
| `test/crown_control_tap_to_edit_test.dart` | MODIFY — remove stale isReadOnly assertions if any |

---

## Next Agent: developer

Feedback
