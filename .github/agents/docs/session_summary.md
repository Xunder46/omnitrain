# Session Summary — Feature Documentation

## Overview

The Session Summary screen appears after workout completion and focuses on session-level outcomes instead of per-exercise detail.

Current hierarchy:

1. Header
2. Top Stats (Duration, Rest Time) for standard sessions only
3. Context-aware modality group cards (Strength, Cardio, Sports, Isometric)
4. Session note
5. Calendar card

The screen keeps existing summary navigation actions (edit, save as routine, discard) and the bottom Done action.

---

## User Workflow

WorkoutSessionScreen -> Finish Workout
  -> SessionSummaryScreen
    -> [if sessionFeeling is null] mandatory 1-5 feeling sheet
    -> review top stats when present and modality cards
    -> optionally edit session note (debounced autosave)
    -> optionally open calendar
    -> optionally use overflow menu (Edit Session, Save as Routine, Discard)
    -> Done

---

## Screen Layout

The screen renders a CustomScrollView over OmniGradientBackground with this order:

| Section | Content |
|---------|---------|
| Header | Session title, formatted start date and time, modality badge |
| Top Stats | Standard sessions only: Duration and Rest Time |
| Group Cards | One card per group that has data in this session |
| Session Note | Inline TextField with debounce save |
| Calendar | Month grid and Open Calendar navigation button |

What is not rendered in the active layout:

- Session RPE card
- Per-exercise rows
- Standalone PR card

Notes:

- Group cards are conditional by data presence; empty groups are hidden.
- Rolling sessions omit the top-stats section entirely because they have no
  session clock.

---

## Group Cards

Cards are shown in fixed order when data exists:

1. Strength
2. Cardio
3. Sports
4. Isometric

Each card contains:

- Group title
- Existing comparison delta chip from GroupDelta
- Two metrics
- Inline PR rows for that group (if any)

Per-group metrics:

- Strength: Sets and Total Volume
- Cardio: Rounds and Total Time
- Sports: Rounds and Total Time
- Isometric: Holds and Total Time

Behavior details:

- Cardio rounds are counted from timed entries.
- Sports time comes from completed round durations.
- Strength volume is formatted using preferred weight unit (kg or lbs).

---

## Rest Time and Duration

Top stats are rendered only for standard sessions and contain exactly:

- Duration
- Rest Time

Rolling sessions do not render the top-stats card or its surrounding spacing.

Rest Time is aggregated from EntryRest records by:

- collecting rests for all efforts in the current session
- including only closed rests where restEndMs is non-null
- summing positive durations only

Formatting:

- Human-readable duration for positive values
- 0 when no closed rests exist

---

## Technical Architecture

### Screen: SessionSummaryScreen

File: lib/features/session/session_summary_screen.dart

Inputs:

- WorkoutState
- RoutineState
- SessionSummaryService
- optional onSessionSaved callback

Summary data loaded on entry:

1. computeSessionSummary from WorkoutState
2. buildTemplateDraftExercises from WorkoutState
3. compareGroupsToPreviousSession from SessionSummaryService
4. computePRs from SessionSummaryService
5. groupPrsByEffortKind from SessionSummaryService
6. buildGroupMetrics from SessionSummaryService
7. computeSessionRestTimeMs from SessionSummaryService
8. getPreferredWeightUnit from SessionSummaryService
9. calendar-day data for current month

Feeling sheet behavior:

- shown after first frame when sessionFeeling is null
- non-dismissible until user selects a value
- writes through updateSessionFeeling

### Service: SessionSummaryService

File: lib/core/services/session_summary_service.dart

Key public methods:

- compareGroupsToPreviousSession
- computePRs
- saveRoutineFromDraft
- computeSessionRestTimeMs
- buildGroupMetrics
- groupPrsByEffortKind
- getPreferredWeightUnit

Repository compatibility:

- Uses WorkoutRepository interface only
- Works with both HiveWorkoutRepository and SqliteWorkoutRepository

---

## Models

File: lib/core/models/session_summary.dart

Key classes:

- SessionSummary
- SessionGroupMetrics
- ExerciseSummary
- PRAchievement
- GroupDelta
- VolumeComparison
- SessionTemplateDraft
- SessionTemplateExercise
- TemplateTargetDraft

Important SessionSummary fields used by the current UI:

- totalDurationMs
- totalSets
- totalVolume
- totalRounds
- totalRoundDurationMs
- totalCardioDurationMs
- totalDrillDurationMs
- exercises

---

## Save as Routine Flow

Save as Routine remains available from the overflow menu.

Flow:

1. Open bottom sheet
2. Edit routine name
3. Reorder/add/remove draft exercises
4. Save through saveRoutineFromDraft
5. Reload routines and finish session

---

## Code References

| Concern | File |
|---------|------|
| Summary screen | lib/features/session/session_summary_screen.dart |
| Summary service | lib/core/services/session_summary_service.dart |
| Summary models | lib/core/models/session_summary.dart |
| Summary computation in state | lib/state/workout/workout_state.dart |
| Repository interface | lib/data/repositories/workout_repository.dart |

---

## Related Documentation

- modality_based_exercise_ui.md
- my_routines.md
- app_philosophy.md
- data_models.md

---

Document Version: 1.3
Last Updated: April 13, 2026
