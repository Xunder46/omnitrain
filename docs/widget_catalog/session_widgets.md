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

**Status: dormant — not rendered anywhere in `lib/`.** A rotatable thumb-wheel control that
`InlineMetricEditor` does not use in any interaction path. Its value-step maths live in
`MetricStepCalc`, which *is* live (see below). Whether this widget should be wired up or deleted
is an open product decision, not a documented behaviour.

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

Verified by `test/crown_control_tap_to_edit_test.dart` (parse, clamp, rounding
and the dialog title).

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
- `TextEditingController`s are deferred-disposed shortly after the
  dialog closes (inline delay in
  `lib/widgets/session/duration_entry_dialog.dart`) to avoid
  use-after-dispose errors.

**Usage**: Wire to `onTap` on `InlineMetricEditor` when `metricType == 'duration'`.

---

### `MetricStepCalc`

**File**: `lib/widgets/session/metric_crown_widget.dart` (static class)

Shared utility for value-adjustment math and popup parsing. Used by both `MetricCrownWidget` and `showMetricEditPopup`.

- `MetricStepCalc.apply(metricType, currentValue, deltaY)` — drag step math (identical to previous `InlineMetricEditor._calculateNewValue`).
- `MetricStepCalc.parseAndClamp(metricType, text)` — parse popup input, clamp to metric range, return typed result (`int` for reps, `double` for others). Returns `null` if unparseable.

### `SessionDistanceCard`

**File**: `lib/widgets/session/session_distance_card.dart`

The Session Summary's DISTANCE card. Renders one `DistanceRowModel` per entry that carries a
distance; the screen builds the models, so the card reads no state and holds no distance rule.
Presentation-only: it renders the name, value text and unit label it is given, and the estimate
marker is a suffix of the unit label rather than a flag of its own. An entry with no distance is
rendered as `absentValue`, never as a zero. Rows are tap-to-edit — the callback is the caller's —
and the card says so: a hint above the rows reads `Tap a row to enter or correct it.` and each row
ends with a pencil. Hides itself when its row list is empty, so the hint cannot appear without rows.
Verified by `test/session_summary_distance_test.dart` (`S-3213 the card says how to edit a row,
above the rows`, `S-3213 a session with no distance rows shows neither the card nor the hint`,
`S-3214 every row ends with a pencil, and the row still opens the editor`, and the narrow-width
fit guard `S-3215`).

See [Session Summary](../session_summary.md#distance) for what the section lists and
[Distance Source & Pairing](../distance_source.md) for what a stored distance means.

### `PRToast`

**File**: `lib/widgets/session/pr_toast.dart`

Static factory for the in-session "new PR" celebration `SnackBar`. Two axis variants share one
visual treatment: a weight-axis toast for loaded-exercise e1RM records and a reps-axis toast for
bodyweight max-reps records.

**It is the one exception to the shared `OmniMessage` look**: the celebration toast keeps its own
`SnackBar` construction by design, and the message-look scan lets the `PRToast.` argument through.
Verified by `test/ui_standards_contract_test.dart` (group `S-2702 one message look`: `the scan
flags a raw bar and lets the PRToast argument through`).

**The toast never asks the user to dismiss it.** There is no `action:` field, it auto-dismisses,
and it floats rather than displacing the bottom controls — the user can keep logging through it.
A celebration that interrupts logging would defeat the point of celebrating.

**PR definition is shared, not local.** The in-session check uses the same
`StatsProgressService.epley1RM` / `getAllTimeBestE1RM` helpers for the weight axis and
`getAllTimeBestReps` for the reps axis that the Stats screen and the Session Summary use. There is
exactly one PR definition per axis; all three surfaces change together.

Triggered from `WorkoutSessionScreen._logSet()`, gated on `set`-kind efforts, suppressed in edit
mode, and fired on a strict `>` against both the standing best and the session's running best.

### `EffortRatingSheet`

**File**: `lib/widgets/session/effort_rating_sheet.dart`

The session effort rating question, for every phone surface that asks it: the Session Summary's
automatic prompt and its EFFORT row's add/change control. `EffortRatingSheet.show` decides only
whether the question must be answered (`mustAnswer`); where the answer goes is the caller's
`onRated`, so the sheet writes nothing and the caller owns the rating — `WorkoutState` for a
session in history.

**Shared, so both copies ask one question.** The question, the scale and the end labels are held
to `watch/contract/watch_effort_rating_contract.json`, the file the wrist's copy is held to.
Verified by `test/watch_effort_rating_copy_parity_test.dart` (`S-287`). The rules the
session-summary caller applies are in [Session Summary](../session_summary.md) ("Effort Rating
Capture"); the wrist's own ask is in [Watch Session Capture](../watch_session_capture.md).

### `MusclePicker`

**File**: `lib/widgets/exercise/muscle_picker.dart`

The exercise editor's muscle section: the fixed taxonomy rows of chips (each region row starting
with a `Whole <region>` chip) plus the `Main: …` / `Assists: …` summary lines.

**Presentation only** — it holds no state, reads no repository and never persists. Inputs:

| Prop | Type | Description |
|------|------|-------------|
| `groups` | `List<MuscleGroup>` | Names by id; an id missing here gets no chip, the summary still names it from `MuscleTaxonomy` |
| `selection` | `MuscleSelection` | The roles the host owns and renders |
| `onTap` | `ValueChanged<String>` | Called with the tapped chip's group id; the host cycles the selection |

Row order comes from `lib/core/utils/muscle_display.dart` (`kMuscleStandaloneIds`
for the standalone row, `kMuscleRegionOrder` for the region rows). Chip keys
`muscle_chip_<id>`, summary keys `muscle_summary_main` / `muscle_summary_assists`, hint key
`muscle_picker_hint`. Verified by `test/muscle_picker_test.dart` (`S-3 the six
row labels run top to bottom in plan order`, `S-12 a group id missing from
groups is skipped and still named`).

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
- Filter by discipline or muscle group; the muscle filter is one list grouped
  by region (`muscleFilterEntries` in `lib/core/utils/muscle_display.dart`),
  and each row shows the exercise's main (primary) muscles as chips
  (verified by `test/muscle_filter_picker_test.dart`, groups
  `S-2: Muscle filter grouped by region` and `S-3 / S-9: rows show main
  muscles only`)
- Empty-state "New Exercise" creation: when the filtered list is empty, the
  `No exercises found` `OmniEmptyState` carries an outlined `New Exercise`
  button (`exercise_picker_new_button`) that pushes `ExerciseEditorScreen` with
  the session modality prefilled via `contextModality`; on return the created
  exercise's name is placed in the search field and the list re-searches
  (verified by `test/screen_widget_test.dart`, group `ExercisePickerScreen` ·
  `S-4108: empty results offer New Exercise; a populated list does not`,
  `S-4109: the button opens the editor with the session modality`,
  `S-4110: a saved exercise lands in the picker search field and list`). With
  any result listed the button is not shown, and the picker has no top create
  button (`S-4101: no New Exercise button; search field comes first`) —
  creating from the library lives on `ExerciseLibraryScreen`'s header `+`
- Returns the selected `Exercise` on pop

Pushed from `WorkoutSessionScreen`,
`RoutineSetupScreen`, and the save-as-routine sheet on
`SessionSummaryScreen`. (`SessionOverviewScreen` also pushes it, but that screen
is not reachable from the app — no code in `lib/` builds it.)

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
- Shows the four modalities (Cardio, Resistance, Sports, Isometric); there is no "General" option
- Returns `(true, String? modality)` record when the user picks an option:
  - Specific modality: `(true, 'cardio_endurance')` etc.
- Returns `null` when the user cancels (so callers can distinguish cancel from a pick)
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

> **Doc freshness** — Last reconciled against source: 2026-10-15. This page is one part of the [Widget Catalog](../widget_catalog.md); see that index for the full component list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
