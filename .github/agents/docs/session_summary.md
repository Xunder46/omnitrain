# Session Summary — Feature Documentation

## Overview

The **Session Summary** screen is displayed after a user finishes (or navigates away from) an active workout session. It provides post-workout analytics: duration, sets, per-group progress deltas vs the previous session, personal records, a monthly training calendar, and the ability to save the completed session as a reusable routine.

---

## User Workflow

```
WorkoutSessionScreen → "Finish Workout" (or back navigation)
  → SessionSummaryScreen
    ├── View stats (duration, sets, volume)
    ├── See volume delta vs previous session
    ├── See new personal records (PRs)
    ├── Add/edit session note (auto-saves with 600ms debounce)
    ├── View monthly training calendar
    ├── Popup menu:
    │     ├── Edit Session → SessionOverviewScreen (push, refresh on return)
    │     ├── Save as Routine → bottom sheet (name + exercise list + save)
    │     └── Discard → confirmation → delete session → pop to home
    └── "Done" button → end + clear session → pop to home with SnackBar
```

---

## Screen Layout

The screen renders a `CustomScrollView` over an `OmniGradientBackground` with the following card sections:

| Section | Content |
|---------|---------|
| **Header** | Session title, formatted start date/time, modality badge |
| **Stats** | Four metrics in a fixed 2×2 grid: Duration, Exercises, Sets, Rounds — always all four visible |
| **Exercise Groups** | Always rendered group headers (even for single-modality sessions) with per-group comparison chips |
| **PRs** | New personal records (conditional — only shown when PRs exist) |
| **Note** | Editable `TextField` with 600ms debounce save via `workoutState.updateSessionNote()` |
| **Calendar** | Current-month grid highlighting workout days and today |

> The standalone **Volume Comparison** card was removed. Progress feedback is now embedded as per-group chips in each exercise group header.

---

## Technical Architecture

### Screen: `SessionSummaryScreen`

**File**: `lib/features/session/session_summary_screen.dart`

A `StatefulWidget` receiving:
- `WorkoutState` — session data, compute summary, end/discard session
- `RoutineState` — reload routines after save-as-routine
- `SessionSummaryService` — async PR/volume computations

### Data Flow on Init

1. `workoutState.computeSessionSummary()` → synchronous `SessionSummary` (duration, sets, volume, exercise list)
2. `workoutState.buildTemplateDraftExercises()` → `List<SessionTemplateExercise>` (for save-as-routine sheet)
3. Async: `sessionSummaryService.compareGroupsToPreviousSession(session, summary)` → `Map<String, GroupDelta>`
4. Async: `sessionSummaryService.computePRs(exerciseSummaries)` → `List<PRAchievement>`
5. Async: `_loadCalendarData()` → fetches sessions in current month date range

### Service: `SessionSummaryService`

**File**: `lib/core/services/session_summary_service.dart`

Wraps a `WorkoutRepository`. Key methods:

| Method | Signature | Purpose |
|--------|-----------|---------|
| `compareGroupsToPreviousSession` | `Future<Map<String, GroupDelta>>(TrainingSession, SessionSummary)` | Finds the most recent previous session, computes per-group stats (volume/duration/rounds), returns delta map keyed by group (`'strength'`, `'cardio'`, `'rounds'`, `'isometric'`) |
| `computePRs` | `Future<List<PRAchievement>>(List<ExerciseSummary>)` | For each `set`-type exercise, checks `bestWeight` against `repository.getPersonalRecordCandidates()` |
| `saveRoutineFromDraft` | `Future<String>(SessionTemplateDraft, {String? focusModality})` | Creates `WorkoutTemplate` + `TemplateSegment` + N `TemplateEffort` + N×M `TemplateTarget`. Returns template ID |

Private helpers:
- `_computeGroupStats(sessionId)` — iterates segments → efforts; accumulates strength volume, cardio/isometric elapsed ms, and round counts per group key
- `_computeSessionVolume(sessionId)` — iterates segments → efforts (set-kind only) → observations, sums reps × weight using `ObservationGrouper`
- `_metricOrderForEffort(effortKind)` — sort-order for observation grouping per effort kind

### Models: `session_summary.dart`

**File**: `lib/core/models/session_summary.dart`

Six plain-data classes (no persistence, no JSON serialization):

| Class | Key Fields |
|-------|------------|
| `SessionSummary` | `sessionId`, `title`, `startedAtMs`, `endedAtMs`, `totalDurationMs`, `totalVolume`, `totalSets`, `totalRounds`, `totalCardioDurationMs`, `totalDrillDurationMs`, `List<ExerciseSummary>` |
| `ExerciseSummary` | `exerciseId`, `name`, `effortKind`, `setsCompleted`, `bestWeight?` |
| `PRAchievement` | `exerciseName`, `metricLabel`, `previousBest`, `newBest` |
| `GroupDelta` | `delta?` (raw numeric, null = no comparison), `unit` (`'kg'`/`'ms'`/`'rounds'`), `hasPrevious` | 
| `VolumeComparison` | `currentVolume`, `previousVolume?`, `delta?`, `hasPrevious` getter |
| `SessionTemplateDraft` | `name`, `focusModality?`, `List<SessionTemplateExercise>` |
| `SessionTemplateExercise` | `exerciseId`, `name`, `effortKind`, `List<TemplateTargetDraft>` (has `copyWith`) |
| `TemplateTargetDraft` | `metricId`, `setIndex`, `unitId?`, `valueReal?`, `valueInt?`, `valueText?` |

### Connection Chain

```
WorkoutState.computeSessionSummary() → SessionSummary
  → fed into SessionSummaryService.computePRs()
  → rendered by SessionSummaryScreen

WorkoutState.buildTemplateDraftExercises() → List<SessionTemplateExercise>
  → displayed in save-as-routine bottom sheet
  → saved via SessionSummaryService.saveRoutineFromDraft()
```

---

## Save as Routine Flow

The **Save as Routine** bottom sheet allows turning a completed session into a reusable routine template:

1. User taps popup menu → "Save as Routine"
2. Bottom sheet opens with:
   - Routine name text field (pre-filled with session title)
   - Reorderable exercise list from `_draftExercises`
   - Each exercise shows name + effort kind label
   - ⋮ menu per exercise: "Remove" or "Change Tracking"
   - (+) Add Exercise button → `ExercisePickerDialog` → `MetricChooserDialog` → adds to draft list
3. User taps "Save" → `sessionSummaryService.saveRoutineFromDraft(draft)` → template ID returned
4. `routineState.loadRoutines()` refreshes the routine list
5. Bottom sheet closes with success SnackBar

---

## Key Design Decisions

### 1. Summary is Computed, Not Stored
The `SessionSummary` is calculated on-the-fly from session data. No separate summary table exists. This ensures the summary always reflects the actual session state.

### 2. PR Detection is Exercise-Scoped
PRs are only computed for `set`-type exercises (where weight is tracked). The service queries all historical observations for the same exercise to find the previous best.

### 3. Volume = Reps × Weight (Set Exercises Only)
Only `set`-kind efforts contribute to total volume. Timed, round, and drill efforts are excluded from the volume calculation.

### 4. Debounced Note Persistence
Session notes auto-save with a 600ms debounce to avoid excessive repository writes during typing.

### 5. Per-Group Progress Chips (replaces standalone Volume Comparison card)
Each exercise group header row carries a right-aligned comparison chip showing the delta vs the most recent previous session:
- `strength` → volume delta in kg (`↑ +6.6 kg` / `↓ -2 kg`)
- `cardio` / `isometric` → duration delta in minutes/seconds (`↑ +2 min` / `↓ -30s`)
- `rounds` → round count delta (`↑ +2 rounds`)
- Arrow color: teal (`colorScheme.primary`) for positive, muted-red (`colorScheme.error.withOpacity(0.8)`) for negative; `—` when no comparison data.

### 6. Exercise Group Headers Always Rendered
Group headers are shown for every session, including single-modality ones. The `rounds` group header label reads **Sports** (not "Rounds"). Header label color is driven by `ModalityColors.forSummaryGroupLabel(groupKey)` from the consolidated color constants.

### 7. Stats Card Fixed Layout
The top stats card uses a deterministic 2×2 grid (Duration, Exercises, Sets, Rounds) — always all four, no conditional hiding based on zero values. This eliminates orphaned metric rows from the previous `Wrap`-based layout.

---

## Code References

| Concern | File |
|---------|------|
| Summary screen | `lib/features/session/session_summary_screen.dart` |
| Summary service | `lib/core/services/session_summary_service.dart` |
| Summary models | `lib/core/models/session_summary.dart` |
| Workout state (compute) | `lib/state/workout/workout_state.dart` |
| Observation grouper | `lib/core/utils/observation_grouper.dart` |
| Routine state (reload) | `lib/state/routine/routine_state.dart` |

---

## Related Documentation

- [Modality-Based Exercise UI](modality_based_exercise_ui.md) — The workout session screen that precedes this summary
- [My Routines](my_routines.md) — Routine template system (save-as-routine creates templates)
- [App Philosophy](app_philosophy.md) — Core design principles

---

**Document Version**: 1.1
**Last Updated**: March 14, 2026
