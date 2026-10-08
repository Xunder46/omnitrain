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

The `effortKind` field on each `SegmentEffort` drives UI rendering. Determined by modality during exercise addition. The four kinds are `set`, `timed`, `round`, and `drill`; see [Constants Reference](constants_reference.md) for their definitions and [Modality Tracking](modality_tracking.md) for how a modality resolves to one.

**Terminology Adaptation**: `round` efforts render as "ROUND" for martial arts and "PERIOD" for the sports modality.

---

## Core UX Patterns

### 1. InlineMetricEditor (Scrollable Value Adjustment)

**Purpose**: Touch-optimized value input without keyboard, ideal for workout environments (gym, outdoors).

**Implementation Details**:
```dart
class InlineMetricEditor extends StatefulWidget {
  final String metricType;        // 'reps', 'weight', 'duration', 'rpe', 'extra-weight'
  final dynamic currentValue;     // Current value to display
  final String unitLabel;         // 'REPS', 'LBS', 'TIME', 'EXTRA WEIGHT'
  final Function(dynamic) onValueChanged; // Immediate callback
}
```

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

### 5. Rest Timer Overlay

**Purpose**: Passive rest tracking between sets without requiring user action.

**Architecture**: Rest intervals are backed by `EntryRest` repository records — **not** a Stopwatch. The old `_restTimer`, `_restStopwatch`, and `_restElapsedSeconds` fields have been removed. See [rest_tracking.md](rest_tracking.md) for the full data layer documentation.

**Behavior**:
- Appears automatically after logging a set (a new `EntryRest` record is written via `workoutState.recordRestStart(effortId, entryIndex)`)
- Overlay visibility is gated on `workoutState.hasRestRecord(effortId, entryIndex)` — no record, no overlay
- Elapsed time is read from `workoutState.getRestElapsedSeconds(effortId, entryIndex)` on each `_ticker` tick (wall-clock derived from `EntryRest.startedAtMs`)
- Displays elapsed rest time (MM:SS format)
- Positioned in lower screen area (above controls, non-intrusive)
- **Hides immediately when a timed/round/drill timer starts**: When `_toggleEffortTimer` is called to start a timed, round, or drill timer, all open rest records for that effort are closed **synchronously in-memory** before the timer UI begins rendering. This ensures `hasRestRecord()` returns `false` and `getRestElapsedSeconds()` returns `0` immediately, even if the async repository persist is still in-flight. Without this synchronous close, a race condition could occur where the rest overlay displays stale elapsed time (rest time + new timer time) in the millisecond window before the async persist completes. See [Rest Record Lifecycle — Synchronous Close on Effort Start](rest_tracking.md#rest-record-lifecycle--synchronous-close-on-effort-start) for details.
- Independent of effort timers — rest records are keyed per effortId+entryIndex, not globally

### 6. Set Navigation and Control

Detail view uses two distinct control rows instead of a single toolbar.

**Timer Control Rule**:

- timed, round, and drill entries are started from the action-row centre button (`Start`); the timer display itself is read-only
- there is no separate play button in the action row
- navigating to another set or exercise leaves a running timer running — elapsed time is wall-clock derived, so it keeps advancing and still expires on schedule while the user is elsewhere
- a paused entry (only reachable from a session persisted mid-pause) shows `Resume` in the same centre slot

**Delete / Remove Rule**:

- removing a logged entry shows a confirmation dialog
- removing the last remaining entry shows a stronger confirmation because it deletes the whole exercise from the session

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

## State Persistence Strategy

### Immediate Persistence
All metric changes persist immediately via `updateEntryValue()`.

**Why Immediate**:
- No data loss if app crashes mid-workout
- No "unsaved changes" warnings needed
- User can leave app and return without losing progress

### Logging vs Persisting
- **Persist**: Save value to repository (happens on every metric change)
- **Log**: Mark set complete, advance to next set (explicit user action)

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

## Edge Cases and Error Handling

### Empty State
**Condition**: No exercises or blocks in the session.

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

### State Locality
- Timer state stored in maps (O(1) lookup by key)
- No unnecessary rebuilds (setState scoped to affected widgets)

### Lazy Loading
- Exercises loaded once on screen mount
- Reload only after mutations (add, delete, update)
- No polling or background refresh

---

## Session Finalization

### Finish Workout Flow

Finishing a workout runs a deterministic shutdown sequence: local UI timers are frozen, every active or paused timer-based entry is persisted, the session is ended (idempotently), and the summary replaces the workout screen on the back-stack so Back cannot return to an active-timer view. A `_isFinishingSession` flag prevents double-tap races, and tick callbacks guard against ghost updates by checking `session.endedAtMs != null`.

Verified by `test/session_finish_timers_test.dart`.

### Edit Mode — Session Duration Editing

In edit mode (`editMode: true`) the session duration becomes editable.

- Pending duration is stored in `_pendingDurationSecs`; `_originalDurationSecs` holds the value at edit entry.
- `_hasDurationChanged()` returns `true` if the two differ — this feeds into the **Unsaved Changes** guard.
- On **Save**: `workoutState.updateSessionEndTime(_pendingDurationSecs!)` writes `endedAtMs = max(startedAtMs, startedAtMs + durationSecs × 1000)` (D-153; a stored end never precedes its start).
- On **Discard**: `_pendingDurationSecs` is reset to `_originalDurationSecs`; no repository write occurs.

Discard throws away the user's own edits but never a wrist entry that arrived
while the screen was open: the restore un-marks exactly the entries applied
after the snapshot's watermark and runs one import pass, so a set the user
logged on the wrist is still in the session after Discard. Verified by
`test/watch_session_edit_restore_late_entry_test.dart` (`S-1401` to `S-1410`).

### Unsaved Changes Dialog

Leaving edit mode with pending changes must prompt before discarding them. Pending state covers inline metric edits, structural changes (add/remove exercise or set), and a session duration edit.

Verified by `test/unsaved_changes_dialog_test.dart`.

---

## Developer Notes

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
  workout_session_screen.dart
    ├── State (_WorkoutSessionScreenState)
    ├── Lifecycle (initState, dispose, _loadExercises)
    ├── Actions (_logSet, _skipSet, _addSet, _deleteLastSet)
    ├── Timer Management (_startEffortTimer, _pauseEffortTimer, _resumeEffortTimer)
    ├── UI Builders (_buildHeader, _buildListView, _buildMetricWidget, _buildSetControls)
    └── Helpers (_formatValue, _jumpToSet, _switchExercise)

lib/widgets/session/
  inline_metric_editor.dart
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
