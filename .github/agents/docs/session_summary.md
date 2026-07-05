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

### Feeling Survey Capture

After the first frame, when `sessionFeeling == null` AND `SettingsState.showFeelingSurvey == true`, the summary shows a non-dismissible modal bottom sheet (`_FeelingSheetContent`) with a 1–5 prompt:

- **Range:** 1 (Rough) → 5 (Great); colour-mapped via `feelingColor(feeling, themeColors)` in `lib/core/utils/session_feeling_utils.dart`.
- **Sheet mechanics:** `showModalBottomSheet` with `isDismissible: false, enableDrag: false` — the user must pick a value (or skip via the explicit close affordance) before the sheet dismisses. Selection writes through `WorkoutState.updateSessionFeeling(sessionId, feeling)` which persists `TrainingSession.sessionFeeling` (nullable `int`) and updates the in-memory session.
- **Idempotent:** `_hasShownFeelingSheet` guards against re-show on rebuilds; the persistence path skips when `session.sessionFeeling != null`.
- **Toggle:** the `Show Feeling Survey` switch in `Settings → WORKOUT` (default `true`, preference key `show_feeling_survey`, see [Theme & Settings](theme_and_settings.md)) disables the sheet for the whole post-workout flow.

#### Where the feeling survey does and does NOT surface today

- **Surfaces:** Post-workout `SessionSummaryScreen` only (when reached via the post-workout flow — i.e. `openedFromCalendar == false`).
- **Does NOT surface:**
  - The historical summary opened from the calendar (`openedFromCalendar: true`) does not trigger the sheet; the historical session is for review / discard only and has no feeling capture moment.
  - There is no in-session feeling prompt; the survey is post-workout only.
  - The sheet does not fire when the user opens the summary as part of the discard / "Unsaved changes" guard.
- **Toggling `showFeelingSurvey = false`** suppresses the sheet globally; the `sessionFeeling` field can still be set elsewhere (e.g. directly via the repository) but no in-app UI surfaces the prompt when the toggle is off.

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

- collecting closed rest intervals across all efforts in the session
- clipping each interval to the session wall-clock window (`startedAtMs` to
  `endedAtMs`)
- merging overlapping or adjacent intervals so concurrent rests are not
  double-counted
- summing merged positive durations

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
- SettingsState, TimerAlertService, RestNotificationService
- optional onSessionSaved callback
- optional `openedFromCalendar: bool` (default `false`)
- optional `originatingCalendarState: CalendarState` (used to refresh
  the month grid after Discard when `openedFromCalendar == true`)

Two entry points feed this screen:

| Entry | `openedFromCalendar` | Behaviour |
|-------|----------------------|-----------|
| `WorkoutSessionScreen` finish → `pushReplacement` (post-workout) | `false` (default) | Calendar card renders today's month; "Open Calendar" pushes a fresh `CalendarScreen`; "Done" ends + clears + `popUntil(isFirst)`; "Discard" deletes + `popUntil(isFirst)`. |
| `CalendarScreen` past-day tap with a single completed entry, or `DaySessionListScreen` completed-row tap (historical) | `true` | Calendar card renders the **session's month**; "Open Calendar" pops back like the system back button; "Done" just clears in-memory state and pops back; "Discard" permanently deletes the historical session and pops back to the originating calendar or day list (the originating `CalendarState.refresh()` is awaited so the deleted indicator disappears from the grid). |

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
- computePRs — records PRs using the **Epley e1RM** formula (`StatsProgressService.epley1RM = weight × (1 + reps / 30)`), the same definition the in-workout toast and the Stats screen use. The screen passes its own session id so the just-finished workout's PRs are not compared against themselves. See `.github/agents/plans/summary-pr-parity-plan.md`.
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
- VolumeComparison — **retained in the model, not rendered in the active layout.** The earlier standalone volume-comparison surface on the summary was removed; progress feedback now lives as per-group `GroupDelta` chips on each modality group card (see "Group Cards" above). The class is preserved because the summary service still constructs one internally and the type is pinned by tests.
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


---

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
