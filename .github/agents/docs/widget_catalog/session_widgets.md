# Session, Picker & Presentation Widgets

> Part of the [Widget Catalog](../widget_catalog.md). Return to the index for the complete widget list and the widget → page lookup table.

---

## Session Metric Widgets

### `DominantMetricWidget`

**File**: `lib/widgets/session/set_metric_widget.dart`

Unified large-metric display widget used across all effort kinds. Renders exactly **one** large metric value.

| Prop | Type | Description |
|------|------|-------------|
| `displayText` | `String` | The value to show (e.g., "10", "03:00", "Round 1\n03:00") |
| `isMultiline` | `bool` | Multi-line rendering for round display |
| `onTap` | `VoidCallback?` | Tap handler (edit reps, toggle timer) |

> **Corrected 2026-07-26 (docs audit).** This entry listed three "stub
> redirect" files kept for import compatibility —
> `lib/widgets/session/drill_metric_widget.dart`, `round_metric_widget.dart`,
> and `timed_metric_widget.dart`. **None of them exist any more.**
> `lib/widgets/session/` now contains `set_metric_widget.dart` (which is where
> `DominantMetricWidget` is actually declared), `inline_metric_editor.dart`,
> `metric_crown_widget.dart`, `duration_entry_dialog.dart`, and
> `pr_toast.dart`. Import `DominantMetricWidget` from `set_metric_widget.dart`.

### `InlineMetricEditor`

**File**: `lib/widgets/session/inline_metric_editor.dart`

Touch-optimized value input for workout environments. Tap the number to open a numeric-entry modal (the crown scrub control is present in the codebase but not rendered — see `MetricCrownWidget`).

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | `reps`, `weight`, `duration`, `rpe`, `extra-weight` |
| `currentValue` | `dynamic` | Value to display |
| `unitLabel` | `String` | Label below value (e.g., "REPS", "LBS") |
| `emphasisTier` | `MetricEmphasisTier?` | Optional value emphasis: `dominant`, `secondary`, `muted`; default keeps legacy displayLarge styling |
| `isReadOnly` | `bool` | When true: disables tap-to-edit popup. Used for live timer displays. |
| `onTap` | `VoidCallback?` | When provided, tapping the number calls this instead of opening the generic popup (e.g. timer toggle, duration dialog). |
| `onValueChanged` | `Function(dynamic)` | Immediate callback on value change |

**Interaction model**:
- Number tap is the sole value-change mechanism.
  - `onTap` provided → delegates to `onTap`.
  - `onTap` null and `!isReadOnly` → opens `showMetricEditPopup`.
  - `isReadOnly: true` → no interactive affordance.
- The crown scrub control (`MetricCrownWidget`) is dormant — it remains in the codebase at `lib/widgets/session/metric_crown_widget.dart` and can be re-enabled in the row without rebuilding the widget.

**Visual**: Value size and styling unchanged. The crown is not rendered. When `isReadOnly` and `emphasisTier` are both set, the emphasis tier wins and the value is not dimmed.

**Session context (live timed/round/drill)**: In `WorkoutSessionScreen` detail view, the `InlineMetricEditor` for live timer-based efforts (`timed`, `round`, `drill`) uses `onTap` wired to `showDurationEntryDialog` so tapping the time value opens the h/m/s editor. When the effort is finished (`isTimedFinished`, `isFinished`, `isDrillFinished`), `isReadOnly: true` is set so the value cannot be edited from live mode (use edit mode for corrections). Play/pause control is a separate Start button — not a tap on the value display. Timed and drill timers render at the dominant tier; the play/pause status label sits on a line below the value.

---

### `MetricCrownWidget`

**File**: `lib/widgets/session/metric_crown_widget.dart`

**Status: dormant.** The widget is fully implemented and constructible but is not rendered by `InlineMetricEditor` in the default interaction path. It can be re-enabled by adding it to the `InlineMetricEditor` row without any other changes.

A rotatable thumb-wheel (crown) control painted as a thick vertical wheel edge-on.

| Prop | Type | Description |
|------|------|-------------|
| `metricType` | `String` | Metric type (forwarded to `MetricStepCalc`) |
| `currentValue` | `dynamic` | Current metric value; read on each drag tick |
| `onValueChanged` | `Function(dynamic)` | Fires on each 10px drag step |

**Behavior**: drag fires `onValueChanged` via `MetricStepCalc.apply`. Crown rotates `2π / 120px` radians per pixel. Rotation accumulates for the widget's lifetime but stops immediately on drag release (no momentum). No `AnimationController` or `Timer`.

**Style**: `44×60` touch target; `CustomPaint` centred inside; all colours from `OmniTheme.colors.textMuted`/`textSecondary` with opacity overlays.

**Drag step sensitivity** (from `MetricStepCalc.apply`):
| Metric | Increment per 10px | Range |
|--------|-------------------|-------|
| `reps` | ±1 | 0–999 |
| `weight` | ±0.5 | 0.0–999.0 |
| `duration` | ±5 sec | 0–3600 |
| `rpe` | ±1 | 1–10 |
| `extra-weight` | ±0.5 | -100.0–200.0 |

---

### `showMetricEditPopup`

**File**: `lib/widgets/session/metric_crown_widget.dart` (top-level function)

Opens an `AlertDialog` for exact numeric entry of a metric value.

```dart
Future<void> showMetricEditPopup(
  BuildContext context, {
  required String metricType,
  required dynamic currentValue,
  required String unitLabel,
  required Function(dynamic) onValueChanged,
})
```

- Pre-fills field with formatted current value; selects all text on open.
- Confirm ("Ok"): parses + clamps → `onValueChanged` → closes.
- Barrier tap (outside dialog): closes without calling `onValueChanged`. There is NO Cancel button.
- Empty or unparseable text → treated as dismiss (no value change).
- Keyboard: `signed: true` for `weight`/`extra-weight`; `signed: false` for all other metric types (e.g., `reps`).
- Ok button has explicit `shape: RoundedRectangleBorder(borderRadius: OmniTheme.buttonUtilityRadius)`.

---

### `showDurationEntryDialog`

**File**: `lib/widgets/session/duration_entry_dialog.dart` (top-level function)

Shared h/m/s duration-entry dialog. Used by `WorkoutSessionScreen` (both live and edit modes) and `RoutineSetupScreen` (round effort duration targets).

```dart
Future<int?> showDurationEntryDialog(
  BuildContext context, {
  String title = 'Edit Duration',
  String subtitle = '',
  required int initialSecs,
})
```

- Returns confirmed duration in whole seconds (`h*3600 + m*60 + s`), or `null` if dismissed.
- Three `TextField` instances for hours, minutes, seconds. Pre-filled from `initialSecs`.
- Single "Ok" `FilledButton`. No Cancel button. Barrier tap dismisses without applying.
- `TextEditingController`s are deferred-disposed (300 ms after dialog close) to avoid use-after-dispose errors.

**Usage**: Wire to `onTap` on `InlineMetricEditor` when `metricType == 'duration'`.

---

### `MetricStepCalc`

**File**: `lib/widgets/session/metric_crown_widget.dart` (static class)

Shared utility for value-adjustment math and popup parsing. Used by both `MetricCrownWidget` and `showMetricEditPopup`.

- `MetricStepCalc.apply(metricType, currentValue, deltaY)` — drag step math (identical to previous `InlineMetricEditor._calculateNewValue`).
- `MetricStepCalc.parseAndClamp(metricType, text)` — parse popup input, clamp to metric range, return typed result (`int` for reps, `double` for others). Returns `null` if unparseable.

### `PRToast`

**File**: `lib/widgets/session/pr_toast.dart`

Static factory for the in-session "Congrats! New PR" celebration `SnackBar` that fires when a strength set beats the user's all-time best e1RM (per the Stats screen's PR definition). Non-blocking, auto-dismissing, theme-token-only. Two axis variants share the same visual treatment — the only difference is which `SnackBar` builder the caller picks:

- `PRToast.buildPRSnackBar(ThemeData theme)` → weight-axis `SnackBar` (loaded-exercise e1RM PR), and
- `PRToast.buildRepPRSnackBar(ThemeData theme, {int? reps})` → reps-axis `SnackBar` (bodyweight max-reps PR).

Both factories build a `SnackBar` with:
  - `duration: 4.0 s` — auto-dismisses; never blocks the rest timer or the next set.
  - `behavior: SnackBarBehavior.floating` — does not push the bottom controls up; the user can keep typing in the numeric editor.
  - `margin: EdgeInsets.only(bottom: 150, left: 16, right: 16)` — the 150 px bottom lift clears `WorkoutSessionScreen._kBottomControlsClearance` (140 px CTA + scroll padding) with a small tolerance.
  - `backgroundColor: theme.colorScheme.surface` — derived from the active theme, never hardcoded.
  - `content`: trophy `Icon(Icons.emoji_events, size: 36, color: theme.colorScheme.primary)` (2× the default 18 px icon) + `SizedBox(width: 8)` + `Flexible(child: Text('Congrats! New PR', softWrap: false, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface, fontSize: 18.0)))` (2× `bodyMedium`'s default 14 px text, truncated with `ellipsis` so the toast never overflows on narrow phones).
  - **No `action:`** field — the user is never asked to tap "Dismiss" or anything similar. The reps variant accepts the `reps` value but currently renders the same minimal copy per D-11 (the in-session toast is intentionally value-free) — the parameter is part of the public API so a future call-site that wants to surface the value has it available without a signature change.

> **Note on plan vs source drift:** the in-session PR toast plan (Decision Ledger D-9 / D-10 / D-12) recorded 4.0 s / `top: 100` / 28 px text; the actual source evolved to 4.0 s / `bottom: 150` / 18 px text. This doc now matches source. The plan is preserved under `.github/agents/plans/in-session-pr-toast-plan.md` as the historical spec; the binding contract for any future tweak is the source in `lib/widgets/session/pr_toast.dart`.

**Where it is triggered**: `WorkoutSessionScreen._logSet()` calls `_maybeShowPRToast()` after `_persistEntryValues(...)` and before the rest-timer / advance logic. The check is gated on `effortKind == 'set' && !isSkippedSetKindEntry`, and the helper additionally blocks in `widget.editMode` (edit-mode suppression) and on non-positive reps. Inside the helper:

- When the set has added external weight (`weight > 0`): weight-axis path. Uses `StatsProgressService.epley1RM(weight, reps)` and `StatsProgressService.getAllTimeBestE1RM(exerciseId)`. Fires `buildPRSnackBar` on strict `>` against both the standing best and the session's running best.
- When the set has no added weight (`weight == 0`) and positive reps: reps-axis path. Uses `StatsProgressService.getAllTimeBestReps(exerciseId)`. Fires `buildRepPRSnackBar` on strict `>` against both the standing best and the session's running best. New for the bodyweight-inclusion plan (`.github/agents/plans/stats-summary-fix-pack-plan.md` Item 2).

The SnackBar call is fire-and-forget — `showSnackBar` is synchronous and the call chain continues immediately to `recordRestStart` and the set advance.

**PR definition source of truth**: the in-session check uses `StatsProgressService.epley1RM(weight, reps)` + `StatsProgressService.getAllTimeBestE1RM(exerciseId)` for the weight axis and `StatsProgressService.getAllTimeBestReps(exerciseId)` for the reps axis — the same helpers the Stats screen's PR detection loop and the Session Summary's `computePRs` use. There is exactly one PR definition per axis; all three surfaces change together.

---

---

## Picker Dialogs

### `ExercisePickerScreen` (was `ExercisePickerDialog`)

**File**: `lib/features/exercise/exercise_picker_screen.dart`

> **Corrected 2026-07-26 (docs audit).** This entry described an
> `ExercisePickerDialog` modal at
> `lib/widgets/pickers/exercise_picker_dialog.dart`. **That class and file no
> longer exist** — `lib/widgets/pickers/` holds only
> `metric_chooser_dialog.dart` and `modality_picker_dialog.dart`. Exercise
> selection is now a **full-screen page push**, not a modal dialog:
> `OmniNavigator.push<Exercise>(context, (_) => ExercisePickerScreen(...))`,
> which returns the selected `Exercise` on pop (or `null` if dismissed).

Full-screen exercise search and selection. Receives `sessionModality` to rank
exercises by relevance.

**Key features**:
- Real-time search with `TextField`, filtered and ranked through `FuzzySearch.filterAndRank`
- Exercises ranked by `getExercisesRankedForModality()` (relevance score)
- Filter by discipline or muscle group
- Inline "New Exercise" creation → pushes `ExerciseEditorScreen` with picker/session modality prefilled via `contextModality`
- Returns the selected `Exercise` on pop

Pushed from `SessionOverviewScreen`, `WorkoutSessionScreen`,
`RoutineSetupScreen`, and the save-as-routine sheet on
`SessionSummaryScreen`.

### `MetricChooserDialog`

**File**: `lib/widgets/pickers/metric_chooser_dialog.dart`

Modal dialog for choosing a tracking method. Shown in Free Training mode and routine creation.

**Key features**:
- Displays only capabilities the selected exercise supports
- Each capability shown as tappable tile with icon and label
- Returns chosen metric string (e.g., `'time'`, `'reps'`, `'hold'`, `'rounds'`)

### `ModalityPickerDialog`

**File**: `lib/widgets/pickers/modality_picker_dialog.dart`

Modal dialog for selecting a modality for an exercise being added.

**Where it appears**:
- Live Free Training sessions (null modality)
- Routine building when the routine's **Focus Modality is "Mixed / Not set"** (null)
- Per-exercise `Change Tracking` override on an already-added exercise (both focus-set and Mixed routines)

**Where it does NOT appear**:
- Live Resistance / Cardio / Sports / Isometric sessions (the session's modality is already known)
- Routine building when the routine's Focus Modality is set — the new exercise silently inherits the focus modality's `effortKind`

**Key features**:
- Shows all five modalities plus a "General" option
- Returns `(true, String? modality)` record when the user picks an option:
  - Specific modality: `(true, 'cardio_endurance')` etc.
  - "General": `(true, null)`
- Returns `null` when the user cancels (so callers can distinguish cancel from "General")
- Callers use `showDialog<(bool, String?)>` and check for `null` before destructuring

---

---

## Presentation Models

### `UiSetData`

**File**: `lib/widgets/models/ui_set_data.dart`

Mutable presentation-layer data class for set tracking. **Not a persistence model.**

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Unique identifier |
| `exerciseId` | `String` | Parent exercise |
| `reps` | `int` | Mutable — current reps value |
| `weight` | `double` | Mutable — current weight value |
| `duration` | `int` | Mutable — current duration in seconds |
| `timestamp` | `DateTime` | When created |

Used by `WorkoutSessionScreen` and `RoutineSetupScreen` for ephemeral UI state.

---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
