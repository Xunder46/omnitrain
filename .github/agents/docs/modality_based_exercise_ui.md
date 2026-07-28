# Modality-Based Exercise Details Screen — UX/UI Technical Documentation

## Overview

The **modality-based exercise details screen** (`WorkoutSessionScreen`) is the core workout tracking interface that dynamically adapts its UI and interaction patterns based on the training modality selected by the user. This document describes the UX/UI architecture, design patterns, and implementation details of this adaptive exercise tracking system.

## Business Context

### Problem
Traditional workout apps force a single tracking paradigm (typically reps/sets/weight for strength training), making them poorly suited for other training types. Athletes across different sports need different tracking methods:
- **Runners** track continuous time and distance
- **Powerlifters** track sets, reps, and weight
- **Martial artists** track timed rounds
- **Yogis** track static hold durations

### Solution
A **context-aware UI** that automatically configures its tracking controls, metric inputs, progress indicators, and terminology based on the workout modality. The same screen adapts to display:
- Rep/weight editors for resistance training
- Duration timers for cardio work
- Round counters for martial arts
- Hold timers with extra weight tracking for isometric work

### Key Benefits
1. **Zero Configuration**: Users never manually select tracking modes; the UI adapts automatically
2. **Consistent Experience**: Same screen layout, different context-appropriate controls
3. **Universal Compatibility**: Single implementation supports all training types
4. **Cognitive Ergonomics**: Terminology and controls match the user's mental model of their activity

---

## Architecture Overview

### Component Hierarchy
```
WorkoutSessionScreen (StatefulWidget)
├── State Management (_WorkoutSessionScreenState)
│   ├── with WorkoutSessionTimerMixin (workout_session_timer_mixin.dart)
│   │   ├── Per-effort timer state maps
│   │   └── Timer lifecycle methods (toggle, tick, pause, freeze, persist)
│   ├── Exercise list state
│   ├── Current exercise/set tracking
│   ├── Rest timer state
│   └── View mode state (list vs detail)
├── UI Modes (split across part files)
│   ├── List View builders → workout_session_list_view.dart
│   └── Detail View builders → workout_session_detail_view.dart
└── Reusable Widgets
    ├── InlineMetricEditor (scrollable value adjustment)
    ├── Header (navigation + context)
    ├── Set Progress Indicator
    ├── Set Dots (visual progress)
    └── Control Buttons
```

### Key Design Principles

1. **Single Responsibility per View Mode**
   - List View: Exercise overview, navigation, add exercises
   - Detail View: Exercise execution, metric tracking, set logging

2. **State-Driven UI Rendering**
   - `effortKind` determines which metrics to display
   - ModalityConfig provides terminology (rounds vs periods vs intervals)
   - Timer states control start/pause/resume behavior

3. **Progressive Disclosure**
   - Start in list view (see all exercises)
   - Tap to drill into detail view (focus on one exercise)
   - Back returns to list view (overview)

4. **Haptic + Visual Feedback**
   - Light haptic on successful log (non-web)
   - Rest timer appears after logging set
   - Timer state indicators (RUNNING/STOPPED)
   - Completed set dots fill in

---

## Modality-Based UI Adaptation

### Effort Kinds (UI Rendering Modes)

The `effortKind` field on each `SegmentEffort` drives UI rendering. Determined by modality during exercise addition.

| Effort Kind | Primary Metrics | Controls | Progress Label | Example Modalities |
|-------------|----------------|----------|----------------|-------------------|
| **set** | Reps, Weight | Scrollers | "Set X of Y" | Resistance Lifting |
| **timed** | Duration, Distance, Extra Weight (optional) | Timer + Scroller | "Interval X of Y" | Cardio Endurance, Sports (free time) |
| **round** | Rounds, Round Duration | Timer + Round Count | "Round X of Y" or "Period X of Y" | Martial Arts, Sports (segmented) |
| **drill** | Hold Duration, Extra Weight | Timer + Extra Weight Scroller | "Hold X of Y" | Isometric/Stretching |

### Metric Widget Rendering

The `_buildMetricWidget()` method implements a switch statement on `effortKind` to render context-appropriate controls:

#### `effortKind == 'set'` (Resistance Training)
```dart
Column(
  children: [
    InlineMetricEditor(metricType: 'reps', ...),  // Vertical scrolling
    InlineMetricEditor(metricType: 'weight', ...), // Lbs/kg adjustment
  ]
)
```
**User Flow**: Swipe up/down on numbers to adjust → Tap "Log Set" to save

#### `effortKind == 'timed'` (Cardio/Endurance)
```dart
Column(
  children: [
    InlineMetricEditor(metricType: 'duration', onTap: _toggleEffortTimer, ...),
    Status Text (RUNNING/STOPPED),
    // Extra-weight editor shown only when entry has an extra-weight observation
    // (new entries always do; pre-feature legacy entries do not — UI guard):
    if (entryData['extra-weight'] != null)
      OutlinedButton('Weight adjustment', ...), // collapsed by default, tap to expand
  ]
)
```
**User Flow**: 
- Option A: Tap the duration display to start or pause timing → tap "Log Interval" when done
- Option B: Scroll to a preset duration → tap "Log Interval" without starting the timer
- Option C (loaded cardio): Tap "Weight adjustment" to expand extra-weight scroller → adjust load → tap "Log Interval"

#### `effortKind == 'round'` (Martial Arts/Sports)
```dart
Column(
  children: [
    Text('ROUND X', fontSize: 72),  // Large round counter
    InlineMetricEditor(metricType: 'duration', onTap: _toggleEffortTimer, ...),
    Status Text (RUNNING/STOPPED),
  ]
)
```
**User Flow**: Tap the duration display to start or pause the countdown → configured effort-timer sound fires at 0:00 → tap "Log Round" or "Log Period"
**Terminology Adaptation**: "ROUND" for martial arts, "PERIOD" for sports modality

#### `effortKind == 'drill'` (Isometric/Stretching)
```dart
Column(
  children: [
    InlineMetricEditor(metricType: 'duration', onTap: _toggleEffortTimer, ...), // Hold time timer
    InlineMetricEditor(metricType: 'extra-weight', ...), // Extra load (negative = band assist, positive = added load)
    Status Text (RUNNING/STOPPED),
  ]
)
```
**User Flow**: Tap the duration display to time the hold → adjust extra weight if needed → tap "Log Hold"
**User Flow**: Start timer for hold → release and stop timer → adjust extra weight → log entry

---

## Core UX Patterns

### 1. InlineMetricEditor (Scrollable Value Adjustment)

**Purpose**: Touch-optimized value input without keyboard, ideal for workout environments (gym, outdoors).

**Interaction**:
- Swipe up → increase value
- Swipe down → decrease value
- No tap/keyboard required (eyes-free operation)

**Implementation Details**:
```dart
class InlineMetricEditor extends StatefulWidget {
  final String metricType;        // 'reps', 'weight', 'duration', 'rpe', 'extra-weight'
  final dynamic currentValue;     // Current value to display
  final String unitLabel;         // 'REPS', 'LBS', 'TIME', 'EXTRA WEIGHT'
  final Function(dynamic) onValueChanged; // Immediate callback
}
```

**Sensitivity Tuning**:
| Metric Type | Increment per 10px Drag | Range |
|-------------|------------------------|-------|
| `reps` | ±1 rep | 0–999 |
| `weight` | ±0.5 kg/lbs | 0.0–999.0 |
| `duration` | ±5 seconds | 0–3600 |
| `rpe` | ±1 point | 1–10 |
| `extra-weight` | ±0.5 kg/lbs | -100.0–200.0 |

**Visual Design**:
- 72pt display value (massive for glanceability)
- Unit label in small caps below (12pt, 50% opacity)
- Drag-responsive (value updates during drag, not just on release)

### 2. Timer State Management

**Challenge**: Multiple exercises with multiple sets, each potentially with independent timers.

**Solution**: All effort timers are **wall-clock derived from persisted records**; the only `Stopwatch` / `Timer.periodic` in the session screen is a 1-Hz UI repaint driver. There is no `Stopwatch`-based elapsed counter in the active source.

> **Note on prior implementations:** Earlier drafts of this file described "Stopwatch-Based Timers (set / timed / drill efforts)" with a `_effortStopwatches` field. That implementation no longer exists in the source. The current `set` effort has no timer at all (reps + weight are scroller inputs persisted on every `updateEntryValue`); `timed` and `drill` elapsed time is derived from `TimedInstance` wall-clock records; `round` elapsed time is derived from `RoundInstance` wall-clock records. A single `_ticker = Timer.periodic(1 s)` drives UI repaints; it never computes elapsed time itself.

#### Effort kinds and their timer model

| Effort kind | Has a running timer? | Source of truth for elapsed time | Persisted record |
|---|---|---|---|
| `set` | No — reps + weight are scroller inputs | n/a (no clock) | `EffortObservation` rows written on every `updateEntryValue` |
| `timed` | Yes (start / pause / resume from the timer display) | Wall-clock derived from `TimedInstance.startedAtMs` − `pausedAtMs` − `totalPausedDurationMs` | `TimedInstance` row |
| `drill` | Yes (same UX as `timed`) | Wall-clock derived from `TimedInstance` (same formula as `timed`) | `TimedInstance` row |
| `round` | Yes (start / pause / resume from the timer display) | Wall-clock derived from `RoundInstance` timestamps via the `elapsedMs` getter | `RoundInstance` row |

#### Per-tick UI state (timer mixin)

The session-screen timer mixin (`WorkoutSessionTimerMixin` in
`lib/features/session/workout_session_timer_mixin.dart`) owns the per-effort UI state, all keyed by `effortId-entryIndex`:

```dart
final Map<String, Timer?> _effortTimers = {};          // Active periodic ticks (UI repaint drivers)
final Map<String, bool> _effortRunning = {};           // Running state flags
final Map<String, int> _effortElapsed = {};            // Elapsed seconds (UI display cache)
final Map<String, bool> _effortAlerted = {};           // Expiry alert already fired
final Map<String, int> _effortTargetDuration = {};     // Countdown / expiry check
```

`_effortElapsed` is **derived on each tick** by reading the relevant persisted record (`TimedInstance.elapsedMs` or `RoundInstance.elapsedMs`) — it is a display cache, not a source of truth. The mixin never holds a `Stopwatch`.

#### Wall-Clock Timer Lifecycle (`timed` / `drill` / `round`)

1. **Start**: persist `startedAtMs = now` (or resume from `pausedAtMs` / `totalPausedDurationMs`); start a `Timer.periodic(1 s)` to drive UI repaints; set `_effortRunning[key] = true`.
2. **Pause**: persist `pausedAtMs = now`; cancel the periodic tick; clear `_effortRunning[key]`.
3. **Resume**: fold `pausedAtMs` into `totalPausedDurationMs`; clear `pausedAtMs`; restart the periodic tick.
4. **Log / Finish**: persist the final value; cancel the tick; clear `_effortRunning[key]`. The persisted timestamps stay so the final elapsed is reproducible on reload.
5. **Round specifics**: `completeRound` (natural countdown) vs `endRoundEarly` (user-ended) both write `finishedAtMs`; `elapsedMs` returns `actualDurationSecs * 1000` for the `finished` state.

The 1-Hz `_ticker` reads the persisted record on each tick and repaints; it never owns elapsed time. App suspension, foreground return, and reload all derive the same elapsed from the persisted timestamps.

**Round State Machine**:
Round lifecycle is enforced by `RoundState` enum in `RoundInstance`:
- `notStarted` → `active` (via `WorkoutState.startRound`)
- `active` → `paused` (via `WorkoutState.pauseRound`)
- `paused` → `active` (via `WorkoutState.resumeRound`; folds pause into `totalPausedDurationMs`)
- `active` / `paused` → `finished` (via `completeRound` / `endRoundEarly`)
- `finished` is terminal — no further transitions allowed

Transitions are validated by `_isValidRoundTransition()` in `WorkoutState`. Rapid-tap protection is provided by the `_pendingRoundTransitions` set in `WorkoutSessionScreen`, which blocks duplicate dispatches while a write is in-flight.

**Round Countdown Display**:
- Display value = `round.remainingMs / 1000` (i.e. `plannedDurationSecs - elapsedSecs`)
- Clamped to [0, plannedDurationSecs] by the `remainingMs` getter — never negative
- Actual duration capped at `plannedDurationSecs * WorkoutConstants.roundActualDurationCapFactor` on persist

### 3. Set Progress Visualization

**Dual Indicators**:

#### Text Progress ("Set 3 of 5")
Terminology adapts to modality:
```dart
switch (effortKind) {
  case 'set': return 'Set $_currentSet of $totalEntries';
  case 'timed': return 'Interval $_currentSet of $totalEntries';
  case 'round': 
    final label = modality == 'sports' ? 'Period' : 'Round';
    return '$label $_currentSet of $totalEntries';
  case 'drill': return 'Hold $_currentSet of $totalEntries';
}
```

#### Visual Dots
- Hollow dots: Future sets
- Filled dots: Completed sets
- Larger dot: Current set (50% opacity primary color)
- Skipped sets: Remain hollow (not counted as completed)
- Tappable: Jump to any set

### 4. Previous Set Stats

**Context Display**: Shows last set's performance above current set.

**Examples**:
- **set**: "Previous: 10 reps @ 135.0 lbs"
- **timed**: "Previous: 05:30 @ 1200.0 m"
- **round**: "Previous: 3 rounds @ 03:00"
- **drill**: "Previous: 00:45 hold @ +5.0 lbs" (negative values shown as e.g. "-2.5 lbs" for band assist)

**Visibility**: Hidden when current set is the first set.

### 5. Rest Timer Overlay

**Purpose**: Passive rest tracking between sets without requiring user action.

**Architecture**: Rest intervals are backed by `EntryRest` repository records — **not** a Stopwatch. The old `_restTimer`, `_restStopwatch`, and `_restElapsedSeconds` fields have been removed. See [rest_tracking.md](rest_tracking.md) for the full data layer documentation.

**Behavior**:
- Appears automatically after logging a set (a new `EntryRest` record is written via `workoutState.recordRestStart(effortId, entryIndex)`)
- Overlay visibility is gated on `workoutState.hasRestRecord(effortId, entryIndex)` — no record, no overlay
- Elapsed time is read from `workoutState.getRestElapsedSeconds(effortId, entryIndex)` on each `_ticker` tick (wall-clock derived from `EntryRest.startedAtMs`)
- Displays elapsed rest time (MM:SS format)
- Positioned in lower screen area (above controls, non-intrusive)
- The current chip is display-only: it has no tap handler and `EntryRest` has no paused/stopped state
- Hides when the next effort timer starts (overlay check gates on `hasRestRecord`)
- Independent of effort timers — rest records are keyed per effortId+entryIndex, not globally

> **Scheduled, not current:** feedback-pack PR 4 makes the whole rest tile
> toggle persisted pause/resume state and visually distinguishes not-started,
> running, and stopped states.

**Visual Design**:
```dart
Container(
  decoration: BoxDecoration(
    color: theme.colorScheme.primaryContainer,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [primary color glow],
  ),
  child: Row(
    children: [
      Icon(Icons.self_improvement),  // Meditation icon
      Column(
        children: [
          Text('MM:SS', fontSize: 20, fontWeight: w600),
          Text('Rest', fontSize: 20, letterSpacing: 2),
        ],
      ),
    ],
  ),
)
```

### 6. Set Navigation and Control

Detail view now uses two distinct control rows instead of a single toolbar.

**Set Progress Row**:

| Control | Icon | Function | Position |
|---------|------|----------|----------|
| Remove Entry | − | Delete the current entry; may remove the whole exercise if it is the last one | Left |
| Progress Label | — | Shows `Set/Interval/Round/Hold X of Y` | Center |
| Add Set | + | Add a new entry to the current exercise | Right |

**Action Row**:

| Control | Function | Notes |
|---------|----------|-------|
| Back Arrow | Navigate to previous set or previous exercise | Disabled only when nothing exists behind the current position |
| Center Action | `Start`, `Log ...`, or `LOGGED` state | Timer entries show `Start` before first activation; logged entries show status text instead of a button |
| Forward Arrow | Move to the next set or exercise | Always visible |

**Timer Control Rule**:

- timed, round, and drill entries are started or paused from the timer display itself
- there is no separate play button in the action row
- jumping to another set auto-pauses any active timer first

**Delete / Remove Rule**:

- removing a logged entry shows a confirmation dialog
- removing the last remaining entry shows a stronger confirmation because it deletes the whole exercise from the session

**Current Screen-Level Swipe Gestures** (workout detail view):
- The detector uses `primaryVelocity` with an absolute threshold of `200`.
- **Horizontal**: right → previous set; left → next/skip set (`_nextSetInEditMode` while editing).
- **Vertical**: up → next exercise; down → previous exercise.
- Routine setup detail currently mirrors the same four gestures; see [My Routines](my_routines.md).
- Metric/number scrollers own separate drag handlers; do not confuse those value-edit gestures with screen-level navigation.

> **Scheduled, not current:** feedback-pack PR 2 removes all four screen-level
> navigation gestures from workout and routine detail, adds no replacement
> gesture, and preserves explicit controls and number-scroller sensitivity.

### 7. List View vs Detail View Toggle

**List View**:
- Shows all exercises in session
- Ordering behavior:
  - Non-rolling sessions: detail navigation follows the exact same sequence as the rendered list.
  - With blocks present, block anchors define group placement in the list and detail traversal.
  - Within a block, exercises are ordered by `createdAtMs`, then `executionOrder`, then id.
  - Standalone (no-block) exercises are ordered by `createdAtMs`, then `executionOrder`, then id.
  - Rolling sessions: exercises render grouped by session block order.
- Summary stats per exercise:
  - **set**: "3 sets"
  - **timed**: "05:30 total"
  - **round**: "5 rounds"
  - **drill**: "3 holds"
- Tap exercise to enter detail view
- FAB button to add new exercise
- Non-rolling list view does not render modality group headers.

**Detail View**:
- Single exercise focus
- Full metric editors
- Set-by-set tracking
- Back button returns to list view

**State Management**:
```dart
bool _showListView = true;  // Default to list view
```

**Navigation Flow**:
```
HomeScreen → Select Modality
  → WorkoutSessionScreen (list view)
    → Tap exercise → Detail view
      → Back → List view
        → Back → HomeScreen

HomeScreen → My Routines tile
  → MyRoutinesScreen → Tap routine
    → WorkoutSessionScreen (list view, pre-populated from routine)
      → (same flow as above)
```

---

## Exercise Addition Flow

### Modality-Driven (Structured Workout)

1. User selects modality tile on home screen (e.g., "Cardio / Endurance")
2. System creates session with `modality = 'cardio_endurance'`
3. User taps FAB (➕) in session screen
4. System opens `ExercisePickerScreen` with `sessionModality: 'cardio_endurance'`
5. Picker shows exercises sorted by relevance score (cardio-compatible exercises first)
6. User selects exercise (e.g., "Running")
7. System calls `addExerciseToSession(exercise, chosenMetric: null)`
8. System determines `effortKind = 'timed'` from modality config
9. System creates `SegmentEffort` with `effortKind: 'timed'`
10. UI renders timer + duration editor

### Free Training / Routine Session (Null Modality)

1. User selects "Free Training" tile or starts a Routine session (modality = null)
2. User taps FAB to add exercise
3. System opens `ExercisePickerScreen` (no filtering)
4. User selects exercise (e.g., "Barbell Squat")
5. System opens `ModalityPickerDialog` — user selects a modality for this exercise
   - **Specific modality picked** (e.g., Cardio): `effortKindOverride = ModalityConfig.forModality(modality)?.effortKind`; no metric chooser shown
   - **"General" picked** (null modality): system falls back to `MetricChooserDialog`
   - **Cancelled**: exercise not added
6. System calls `addExerciseToSession(exercise, chosenMetric: ..., effortKindOverride: ...)`
7. System determines `effortKind` from override or chosen metric
8. UI renders appropriate tracking controls

### + New Item Exercise (Picker)

1. User taps "New Exercise" in `ExercisePickerScreen`
2. App opens `ExerciseEditorScreen` (form with name, description, discipline, capabilities, muscle groups)
3. User saves → `WorkoutState.createCustomExercise(...)` persists the new exercise
4. Editor closes and returns the new `Exercise`
5. Picker refreshes results and pre-fills search with the new exercise name

---

## State Persistence Strategy

### Immediate Persistence
All metric changes persist immediately via `updateEntryValue()`:
```dart
await widget.workoutState.updateEntryValue(
  effortId,
  entryIndex,
  'reps',
  newValue,
);
```

**Why Immediate**:
- No data loss if app crashes mid-workout
- No "unsaved changes" warnings needed
- User can leave app and return without losing progress

### Logging vs Persisting
- **Persist**: Save value to repository (happens on every metric change)
- **Log**: Mark set complete, advance to next set (explicit user action)

**Example**:
1. User scrolls reps to 10 → Persist immediately
2. User scrolls reps to 12 → Persist immediately (overwrites)
3. User taps "Log Set" → Mark complete, move to next set, start rest timer

### Timer Value Persistence
- **timed/drill efforts**: Save `_effortElapsed[key]` (seconds) on pause/log via `updateEntryValue`
- **round efforts**: Write a `RoundInstance` record — never raw observations. Fields persisted:
  - `state` — `RoundState` enum (`notStarted` | `active` | `paused` | `finished`); `finished` is terminal
  - `startedAtMs` — wall-clock epoch ms when timer started (0 when `notStarted`)
  - `pausedAtMs` — epoch ms when most recent pause occurred (`null` when not paused)
  - `totalPausedDurationMs` — cumulative pause time folded in on each `resumeRound` call
  - `finishedAtMs` — epoch ms when round ended (0 when not yet finished)
  - `actualDurationSecs` — clamped to `plannedDurationSecs * WorkoutConstants.roundActualDurationCapFactor`
  - `completed` — `true` only when round ends via natural countdown (`completeRound`); `false` otherwise
  - `plannedDurationSecs` — target round length (default: `WorkoutConstants.defaultRoundDurationSecs = 180`)

---

## Responsive Design Considerations

### Large Touch Targets
- Metric editors: Full-width swipeable area (padding: 32px vertical)
- Control buttons: 44x44pt minimum (iOS guideline compliance)
- Set dots: 10-14px diameter, 12px spacing (easy tap targets)

### Text Hierarchy
| Element | Size | Weight | Purpose |
|---------|------|--------|---------|
| Metric value | 72pt | Light (w300) | Primary focus |
| Unit label | 12pt | Medium (w500) | Context |
| Progress text | 16pt | Medium (w500) | Status |
| Previous stats | 12pt | Regular, italic | Reference |

### Color Semantics
- **Primary color**: Active actions (Log Set, running timers)
- **OnSurface 50%**: Secondary actions, disabled states
- **OnSurface 20%**: Future/incomplete set dots
- **PrimaryContainer**: Rest timer background (non-intrusive highlight)

### Dark Mode Support
All colors use theme-based values (no hardcoded colors):
```dart
theme.colorScheme.primary
theme.colorScheme.onSurface.withAlpha((0.5 * 255).round())
theme.colorScheme.primaryContainer
```

---

## Edge Cases and Error Handling

### Empty State
**Condition**: No exercises or blocks in the session.

**Current first-load behavior**: after an empty non-edit session loads, `_shouldAutoOpenPicker()` schedules `_addExercise()`, so `ExercisePickerScreen` opens automatically. If the picker is dismissed, the underlying list surface exposes Add Exercise (filled) and Add Block (outlined); the actions are not equally weighted. A rolling session with an existing block and a routine-populated session bypass this auto-open condition.

> **Scheduled, not current:** feedback-pack PR 6 removes auto-open and makes the neutral empty session's Add Exercise/Add Block choices equally weighted.

### Loading State
**Condition**: Fetching exercises from repository
**UI**: Centered CircularProgressIndicator
**Trigger**: Initial load, after adding/deleting exercises

### Error State
**Condition**: Repository error during load
**UI**: 
- Red error icon (64px)
- "Error Loading Session" title
- Error message text
- "Retry" button
**Recovery**: Retry button calls `_loadExercises()` again

### Set Skip vs Delete
- **Skip Set**: Advance without logging via forward navigation (set dot remains hollow)
- **Remove Entry**: When the exercise has **more than one set**, the minus (`Icons.remove`) icon deletes the current entry (set dot removed). When **only one set remains**, the minus icon is replaced by a trash-can (`Icons.delete_outline`) at the same colour and size — signalling that confirming will remove the entire exercise from the session. Tooltip text also switches from "Remove set" to "Remove exercise".
- Use case: Skip = "I'm moving on without logging this effort", Remove = "This entry should not exist"

### Modality Change Warning
**Trigger**: User taps different modality tile while session active
**UI**: Alert dialog
```
"Start New Session?"
"Changing modality will start a new session. Current session will not be saved."
[Cancel] [Start New]
```
**Behavior**: Confirm → End current session, create new session, navigate to new session

---

## Performance Optimizations

### Timer Update Frequency
- **Session timer**: 1 second interval (display only), derived from `session.startedAtMs` and held at `00:00` until the first exercise is added
- **Effort timers**: 1 second interval (persisted on pause)
- **Rest timer**: 1 second interval (display only)

**Trade-off**: 1-second granularity vs battery/CPU usage (acceptable for workout context)

### State Locality
- Timer state stored in maps (O(1) lookup by key)
- No unnecessary rebuilds (setState scoped to affected widgets)
- Stopwatch instances reused across pause/resume cycles

### Lazy Loading
- Exercises loaded once on screen mount
- Reload only after mutations (add, delete, update)
- No polling or background refresh

---

## Session Finalization

### Finish Workout Flow

When the user taps **Finish Workout**, the screen executes a deterministic shutdown sequence before navigating away:

1. **Freeze all local UI timers** — `_ticker`, all `_effortTimers`, `_restTimer` cancelled; `_effortRunning[key]` set to `false`.
2. **Persist all active timer-based entries** — iterates all `round`, `timed`, and `drill` efforts; calls `endRoundEarly` / `finishTimedEntry` for any `active` or `paused` instances.
3. **End session** — `workoutState.endSession()` sets `endedAtMs` (idempotent; safe to call if already ended).
4. **Navigate via `pushReplacement`** → `SessionSummaryScreen`; the workout screen is removed from the back-stack so pressing Back from the summary cannot return to an active-timer view.

> Tick callbacks (`_onEffortTick`, `_tick`) guard against ghost updates by checking `session.endedAtMs != null` before processing.

A `_isFinishingSession` flag prevents double-tap race conditions.

### Edit Mode — Session Duration Editing

In edit mode (`editMode: true`) the **Session Time** chip gains a tinted border, an edit icon, and becomes tappable. Tapping opens an `AlertDialog` with hours/minutes/seconds fields.

- Pending duration is stored in `_pendingDurationSecs`; `_originalDurationSecs` holds the value at edit entry.
- `_hasDurationChanged()` returns `true` if the two differ — this feeds into the **Unsaved Changes** guard.
- On **Save**: `workoutState.updateSessionEndTime(_pendingDurationSecs!)` writes `endedAtMs = startedAtMs + durationSecs × 1000`.
- On **Discard**: `_pendingDurationSecs` is reset to `_originalDurationSecs`; no repository write occurs.

### Unsaved Changes Dialog

The "Unsaved changes" dialog appears when the user attempts to leave edit mode with pending changes:

| Trigger | Shown for |
|---------|-----------|
| `_editBuffer.isNotEmpty` | Any inline metric edit |
| `_hasStructuralChanges` | Add/remove exercise or set |
| `_hasDurationChanged()` | Session duration edit |

Dialog layout:
- **Close icon (×)** in title bar → keep editing (no action)
- **Discard** (outlined button) → roll back all changes
- **Save** (filled button) → persist all changes

---

## Future Enhancements

### Planned Features
1. **Round Bell**: Audio/haptic alert when countdown reaches 0:00
2. **Auto-advance**: Optional auto-advance to next set after rest period
3. **Template Pre-fill**: Load previous workout's values as defaults
4. **Voice Commands**: "Log set" voice trigger (hands-free)
5. **Chart Overlay**: Mini-graph showing set history for current exercise
6. **Swipe-to-delete**: Swipe set dot to delete that specific set

### Accessibility Improvements
1. **VoiceOver**: Full screen reader support for all controls
2. **Large Text**: Respect system text size settings
3. **Contrast**: WCAG AA compliance for all text/background pairs
4. **Haptic Alternatives**: Visual indicators for all haptic feedback

---

## Developer Notes

### Testing Strategy
**Unit Tests**:
- Timer state transitions (start/pause/resume)
- Metric value calculations (InlineMetricEditor increments)
- EffortKind selection logic

**Widget Tests**:
- Metric widget rendering per effortKind
- Button enable/disable states
- Navigation between list and detail views

**Integration Tests**:
- Full add-exercise-to-log-set flow
- Modality change with session conflict
- Timer persistence across pause/resume

### Common Pitfalls
1. **Timer Keys**: Always use `effortId-entryIndex` format (not just effortId)
   - Reason: Same exercise can have multiple timers (one per set)

2. **setState Scope**: Wrap only affected variables in setState
   - Anti-pattern: `setState(() { /* entire method */ })`
   - Better: Call method, then `setState(() { _localVar = newValue })`

3. **Timer Cleanup**: Always cancel timers in `dispose()`
   - Memory leak risk if timers survive widget lifecycle

4. **Round Persistence**: Round efforts use `RoundInstance` records, not observations
   - Never call `updateEntryValue` for round metrics — use `WorkoutState.startRound`, `pauseRound`, `resumeRound`, `endRoundEarly`, `completeRound`
   - Elapsed is always derived at read time via `RoundInstance.elapsedMs` getter — never stored as a raw counter
   - The display value comes from `_getRoundInstance(...).elapsedMs`, not from dedicated round UI maps
   - State transitions are strictly enforced by `_isValidRoundTransition()` in `WorkoutState`; `finished` is terminal
   - Rapid-tap protection: `_pendingRoundTransitions` set in `WorkoutSessionScreen` prevents concurrent duplicate transitions
   - See `WorkoutConstants.roundActualDurationCapFactor` for the safety cap on `actualDurationSecs`

### Code Organization
```
lib/features/session/
  workout_session_screen.dart       (1412 lines)
    ├── State (_WorkoutSessionScreenState)
    ├── Lifecycle (initState, dispose, _loadExercises)
    ├── Actions (_logSet, _skipSet, _addSet, _deleteLastSet)
    ├── Timer Management (_startEffortTimer, _pauseEffortTimer, _resumeEffortTimer)
    ├── UI Builders (_buildHeader, _buildListView, _buildMetricWidget, _buildSetControls)
    └── Helpers (_formatValue, _jumpToSet, _switchExercise)

lib/widgets/session/
  inline_metric_editor.dart          (200 lines)
    ├── State (_InlineMetricEditorState)
    ├── Value Formatting (_formatValue)
    ├── Gesture Handling (onVerticalDragUpdate)
    └── UI (GestureDetector + Text display)
```

---

## Conclusion

The modality-based exercise details screen represents a **context-aware, adaptive UI pattern** that eliminates manual configuration while supporting diverse training methodologies. Key achievements:

1. **Single Implementation**: One screen serves all modalities via configuration-driven rendering
2. **Zero Learning Curve**: UI terminology and controls match user's mental model
3. **Robust State Management**: Map-based timer state prevents conflicts
4. **Progressive Disclosure**: List/detail view split balances overview and focus
5. **Touch-Optimized**: Swipe gestures and large targets suit workout environments

This architecture demonstrates how **data-driven UI rendering** (effortKind → widget switch) combined with **domain-specific configuration** (ModalityConfig) can create a flexible system without sacrificing usability or code maintainability.

---

**Document Version**: 1.5
**Last Updated**: July 27, 2026
**Author**: Automated documentation generated from codebase analysis
**Related Docs**:
- [modality_tracking.md](modality_tracking.md) — Data layer + business logic
- [exercise_ranking.md](exercise_ranking.md) — Exercise picker sorting algorithm
- [create_new_exercise.md](create_new_exercise.md) — Create custom exercises from the picker
- [my_routines.md](my_routines.md) — Reusable workout template system


---

> **Doc freshness** — Last reconciled against source: 2026-07-27. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
