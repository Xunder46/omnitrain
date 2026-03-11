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
│   ├── Exercise list state
│   ├── Current exercise/set tracking
│   ├── Per-effort timer state (map-based)
│   ├── Rest timer state
│   └── View mode state (list vs detail)
├── UI Modes
│   ├── List View (exercise overview)
│   └── Detail View (single exercise tracking)
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
| **timed** | Duration, Distance | Timer + Scroller | "Interval X of Y" | Cardio Endurance, Sports (free time) |
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
    InlineMetricEditor(metricType: 'duration', ...), // Shows elapsed or preset
    Play/Pause Button,
    Status Text (RUNNING/STOPPED),
  ]
)
```
**User Flow**: 
- Option A: Tap play → timer counts up → tap "Log Set" when done
- Option B: Scroll to preset duration → tap "Log Set" without timer

#### `effortKind == 'round'` (Martial Arts/Sports)
```dart
Column(
  children: [
    Text('ROUND X', fontSize: 72),  // Large round counter
    InlineMetricEditor(metricType: 'duration', ...), // Shows countdown or preset
    Play/Pause Button,
    Status Text (RUNNING/STOPPED),
  ]
)
```
**User Flow**: Start timer → countdown from round duration → bell sound at 0:00 (future) → log round
**Terminology Adaptation**: "ROUND" for martial arts, "PERIOD" for sports modality

#### `effortKind == 'drill'` (Isometric/Stretching)
```dart
Column(
  children: [
    InlineMetricEditor(metricType: 'duration', ...), // Hold time timer
    InlineMetricEditor(metricType: 'extra-weight', ...), // Extra load (negative = band assist, positive = added load)
    Play/Pause Button,
    Status Text (RUNNING/STOPPED),
  ]
)
```
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
| `weight` | ±2.5 lbs | 0.0–999.0 |
| `duration` | ±5 seconds | 0–3600 |
| `rpe` | ±1 point | 1–10 |
| `extra-weight` | ±2.5 | -100.0–200.0 |

**Visual Design**:
- 72pt display value (massive for glanceability)
- Unit label in small caps below (12pt, 50% opacity)
- Drag-responsive (value updates during drag, not just on release)

### 2. Timer State Management

**Challenge**: Multiple exercises with multiple sets, each potentially with independent timers.

**Solution**: Two parallel timer strategies depending on effort kind.

#### Stopwatch-Based Timers (set / timed / drill efforts)
Keyed by `effortId-entryIndex`:
```dart
final Map<String, Timer?> _effortTimers = {};          // Active periodic timers
final Map<String, Stopwatch> _effortStopwatches = {};  // Elapsed time trackers
final Map<String, bool> _effortRunning = {};           // Running state flags
final Map<String, int> _effortElapsed = {};            // Elapsed seconds (UI display)
final Map<String, int> _effortElapsedBase = {};        // Base time (for pause/resume offset)
```

**Stopwatch Timer Lifecycle**:
1. **Start**: Create stopwatch, start periodic timer, set `_effortRunning[key] = true`
2. **Pause**: Stop stopwatch, cancel timer, persist elapsed time to repository
3. **Resume**: Store current elapsed as new base, reset stopwatch, restart timer
4. **Log Set**: Persist final value, stop timer, reset stopwatch

#### Wall-Clock Timers (round efforts only)
Keyed by `effortId-entryIndex` (same key convention as all other timers).

Round elapsed time is **not** tracked in UI maps. It is derived on-demand from `RoundInstance` timestamp fields persisted in the repository:

```dart
// Elapsed formula (implemented as RoundInstance.elapsedMs getter):
// - active:      now - startedAtMs - totalPausedDurationMs
// - paused:      pausedAtMs - startedAtMs - totalPausedDurationMs  (frozen)
// - finished:    actualDurationSecs * 1000
// - notStarted:  0
final elapsedMs = round.elapsedMs;
final elapsedSecs = (elapsedMs / 1000).toInt();
```

The UI tick timer reads `round.elapsedMs` on each 1-second tick (`_onEffortTick`) and updates `_effortElapsed[timerKey]` for display only. No separate round-specific UI maps exist.

**Why wall-clock?** If the OS suspends the app mid-round, a `Stopwatch` stops counting but epoch time keeps advancing. On resume, `now - startedAtMs - totalPausedDurationMs` correctly reflects real-world elapsed time, preventing the timer from appearing frozen.

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

**Behavior**:
- Appears automatically after logging a set
- Displays elapsed rest time (MM:SS format)
- Positioned in lower screen area (above controls, non-intrusive)
- Hides when exercise timer starts (focus shifts to work)
- Independent of exercise timers (global rest state)

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

**Bottom Control Bar** (always visible in detail view):

| Control | Icon | Function | Position |
|---------|------|----------|----------|
| Previous Set | ← | Navigate to previous set | Left |
| Play/Pause | ▶/⏸ | Start/stop timer (timer-based only) | Center-left |
| Add Set | + | Add new entry to current exercise | Center |
| Delete Set | 🗑 | Remove last set | Center-right |
| Log Set | ✓ | Save current set, advance to next | Right (primary) |

**Button Styling**:
- **Log Set (primary action)**: Large circular button, primary color, 28px icon
- **Previous Set**: Medium circular button, 10% surface, 24px icon
- **Other actions**: Icon buttons, 50% opacity, 28px icon

**Swipe Gestures** (Detail View):
- **Horizontal swipes**:
  - Swipe right (velocity > 500): Previous set
  - Swipe left (velocity < -500): Skip set
- **Vertical swipes**:
  - Swipe up (velocity < -300): Next exercise
  - Swipe down (velocity > 300): Previous exercise

### 7. List View vs Detail View Toggle

**List View**:
- Shows all exercises in session
- Summary stats per exercise:
  - **set**: "3 sets"
  - **timed**: "05:30 total"
  - **round**: "5 rounds"
  - **drill**: "3 holds"
- Tap exercise to enter detail view
- FAB button to add new exercise

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
4. System opens `ExercisePickerDialog` with `sessionModality: 'cardio_endurance'`
5. Picker shows exercises sorted by relevance score (cardio-compatible exercises first)
6. User selects exercise (e.g., "Running")
7. System calls `addExerciseToSession(exercise, chosenMetric: null)`
8. System determines `effortKind = 'timed'` from modality config
9. System creates `SegmentEffort` with `effortKind: 'timed'`
10. UI renders timer + duration editor

### Free Training (User-Driven)

1. User selects "Free Training" tile (modality = null)
2. User taps FAB to add exercise
3. System opens `ExercisePickerDialog` (no filtering)
4. User selects exercise (e.g., "Barbell Squat")
5. System opens `MetricChooserDialog` (user picks tracking method)
6. User chooses "Track by Time"
7. System calls `addExerciseToSession(exercise, chosenMetric: 'time')`
8. System determines `effortKind = 'timed'` from chosen metric
9. UI renders timer + duration editor

### Create Custom Exercise (Picker)

1. User taps "Add Custom Exercise" in `ExercisePickerDialog`
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
**Condition**: No exercises in session
**UI**: Centered message + "Add First Exercise" button
**Flow**: Tap button → ExercisePickerDialog → Add exercise → Detail view

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
- **Skip Set**: Advance without logging (set dot remains hollow)
- **Delete Set**: Remove last set from repository (set dot removed)
- Use case: Skip = "I'm too tired for this set", Delete = "I added extra set by mistake"

### Modality Change Warning
**Trigger**: User taps different modality tile while session active
**UI**: Alert dialog
```
"Start New Session?"
"Changing modality will start a new session. Current session will be saved."
[Cancel] [Start New]
```
**Behavior**: Confirm → End current session, create new session, navigate to new session

---

## Performance Optimizations

### Timer Update Frequency
- **Session timer**: 1 second interval (display only)
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

**Document Version**: 1.2  
**Last Updated**: February 28, 2026  
**Author**: Automated documentation generated from codebase analysis  
**Related Docs**: 
- [modality_tracking.md](.github/agents/docs/modality_tracking.md) — Data layer + business logic
- [exercise_ranking.md](.github/agents/docs/exercise_ranking.md) — Exercise picker sorting algorithm
- [create_new_exercise.md](.github/agents/docs/create_new_exercise.md) — Create custom exercises from the picker
- [my_routines.md](.github/agents/docs/my_routines.md) — Reusable workout template system
