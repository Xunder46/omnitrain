# Session Summary — Feature Documentation

## Overview

The Session Summary screen appears after workout completion and focuses on session-level outcomes instead of per-exercise detail.

Current hierarchy:

1. Header
2. Session info card (Duration and Rest Time for standard sessions; the EFFORT row for every session)
3. Context-aware modality group cards (Strength, Cardio, Sports, Isometric)
4. Session note
5. Calendar card

The screen keeps existing summary navigation actions (edit, save as routine, discard) and the bottom Done action.

### Effort Rating Capture

The **session effort rating** is how hard the whole session was: 1 is the easiest, 5 the hardest. It is stored in `TrainingSession.sessionFeeling` — the field name is historical; it is not a feeling score. Ratings recorded before the redefinition (when the prompt asked how the session felt) are read as effort ratings on the same scale with no conversion: an owner decision (Stats redesign D-5, `.github/agents/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md`).

**Structure.** One sheet widget, `_FeelingSheetContent` in `lib/features/session/session_summary_screen.dart`, serves two entry points: the **automatic post-workout prompt** (`_showFeelingSheet`) and the **EFFORT row's add/change control** (`_openEffortRatingSheet`) in the first summary card, which exists on post-workout and calendar-opened summaries whether or not the prompt is enabled. Both write through `WorkoutState.updateSessionFeeling`, and the summary rebuilds when the sheet closes. Rating colors come only from `feelingColor` / `effortTileTextColor` in `lib/core/utils/session_feeling_utils.dart`, which read `OmniThemeColors.intensityRamp` (see [Design System](design_system.md)).

**Rules.**

- **The automatic prompt must be answered.** It has no close or skip control and cannot be dismissed without a choice; the Effort Rating setting (`SettingsState.showFeelingSurvey`, see [Theme & Settings](theme_and_settings.md)) is the only way not to be asked. It appears only on a post-workout summary of an unrated session, at most once.
- **The user-opened sheet is optional.** The user chose to open it, so closing it without a choice leaves the rating unchanged.
- **A change reaches the calendar.** On a calendar-opened summary a saved rating refreshes the originating `CalendarState` — the same path Discard uses — so the day list shows the new tint on return.
- **The rating is never drawn as ramp-colored text.** The lower ramp steps sit below the text-contrast floor, so the EFFORT value uses the stat pills' shared value color and the intensity is carried by a non-text marker in the rating's ramp step (D-15 in `.github/agents/plans/2026-09-24-01-stats-pr1-effort-rating-plan.md`).
- **Rolling sessions can still be rated.** They have no session clock, so their info card drops Duration and Rest Time but keeps the EFFORT row.

Verified by:

- `test/screen_widget_test.dart` (group `SessionSummaryScreen`): `feeling modal is non-dismissible and blocks summary controls`, `selecting tile 3 dismisses the feeling modal and persists`, `does not show feeling modal when session feeling already exists`.
- `test/interaction_flow_test.dart`: `does not show feeling survey sheet when disabled in settings`.
- `test/session_summary_effort_row_test.dart`: the prompt's copy and refresh (`Task 1a`); add, change, pre-selection and the selected tile's text color (`S-3`, `Fresh session — Change replaces …`, `Change sheet pre-selects …`); closing without a choice by tap and by swipe (`S-5.5`, `Change sheet swiped down …`); calendar-opened summaries — no prompt, add/change, day-list refresh (`S-4/S-5`, `S-5: day list → …`); value color and marker (`EFFORT value is drawn …`); pre-redefinition answers (`S-6`); the sheet's date subtitle (`Sheet subtitle …`); rolling sessions (`Task 3`).
- `test/header_standardization_test.dart`: `S-008: rolling session shows combined card with EFFORT row only (Duration/Rest hidden)`.

---

## Screen Layout

The screen renders a CustomScrollView over OmniGradientBackground with this order:

| Section | Content |
|---------|---------|
| Header | Session title, formatted start date and time, modality badge |
| Session info card | Duration and Rest Time, then the EFFORT row (rolling sessions: EFFORT row only — see [Effort Rating Capture](#effort-rating-capture)) |
| Group Cards | One card per group that has data in this session |
| Session Note | Inline TextField with debounce save |
| Calendar | Month grid and Open Calendar navigation button |

What is not rendered in the active layout:

- Session RPE card
- Per-exercise rows
- Standalone PR card

Notes:

- Group cards are conditional by data presence; empty groups are hidden.

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

Rolling sessions have no session clock, so neither value is shown for them
(`test/header_standardization_test.dart`, `S-008`).

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
- optional `originatingCalendarState: CalendarState` (refreshed after
  Discard or a rating change when `openedFromCalendar == true`)

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

Effort rating sheet: see [Effort Rating Capture](#effort-rating-capture).

### Service: SessionSummaryService

File: lib/core/services/session_summary_service.dart

Key public methods:

- compareGroupsToPreviousSession
- computePRs — records PRs using the **Epley e1RM** formula (`StatsProgressService.epley1RM = weight × (1 + reps / 30)`), the same definition the in-workout toast and the Stats screen use. The screen passes its own session id so the just-finished workout's PRs are not compared against themselves. See `.github/agents/plans/summary-pr-parity-plan.md`.

  The returned list is collapsed to at most one `PRAchievement` per
  exercise — when the same exercise appears in more than one block
  (e.g. a user clones a block several times), the input list carries
  one `ExerciseSummary` per block and the method groups by `exerciseId`
  before emitting. The verdict ("is this a PR") is unchanged; only
  the entry count collapses. Set count, total volume, and the
  per-exercise breakdown are byte-equal before and after this step.
  See `.github/agents/plans/stats-summary-fix-pack-plan.md` PR 1.

  A parallel **reps-axis** pass emits bodyweight PRs
  (`metricLabel: 'reps'`) using `StatsProgressService.getAllTimeBestReps`
  — the same source-of-truth query the in-session reps-PR toast and
  the Stats screen use. The two passes cannot collide because an
  exercise on the e1RM axis never has a non-null `bestReps` and vice
  versa. See `.github/agents/plans/stats-summary-fix-pack-plan.md`
  Item 2 (rep-based record parity).
- saveRoutineFromDraft
- computeSessionRestTimeMs
- buildGroupMetrics
- groupPrsByEffortKind
- getPreferredWeightUnit

Repository compatibility:

- Uses WorkoutRepository interface only

---

## Models

File: lib/core/models/session_summary.dart

Key classes:

- SessionSummary
- SessionGroupMetrics
- ExerciseSummary
- PRAchievement
- GroupDelta
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

## Save as Routine

Available from the summary's overflow menu. The draft is editable — name, exercise order,
additions and removals — before it is persisted through `saveRoutineFromDraft`.

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
