# Session Summary — Feature Documentation

## Overview

The Session Summary screen appears after workout completion and focuses on session-level outcomes instead of per-exercise detail.

Current hierarchy:

1. Header
2. Top Stats (Duration, Rest Time for standard sessions; EFFORT row for every session)
3. Context-aware modality group cards (Strength, Cardio, Sports, Isometric)
4. Session note
5. Calendar card

The screen keeps existing summary navigation actions (edit, save as routine, discard) and the bottom Done action.

### Effort Rating Capture

The post-session survey records the **session effort rating**: how hard the whole session was, 1 (Very easy) → 5 (Max effort). It is stored in the existing `TrainingSession.sessionFeeling` field (nullable `int`; the name is historical — it is not a feeling score). Ratings recorded before the redefinition (when the prompt asked "How did it feel?", Rough → Great) are read as effort ratings on the same scale with no conversion — a deliberate owner decision (Stats redesign D-5, `.github/agents/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md`).

#### Automatic post-workout prompt

After the first frame, when `sessionFeeling == null`, `SettingsState.showFeelingSurvey == true` and the summary was reached from the post-workout flow (not from the calendar), the summary shows a modal bottom sheet (`_FeelingSheetContent`):

- **Copy:** title "How hard was this session?"; five numbered tiles 1–5; end labels "Very easy" under 1 and "Max effort" under 5. There are no per-number words (they don't fit the tile row).
- **Colors:** tiles use the theme's one-color intensity ramp via `feelingColor(rating, themeColors)` (1 faintest → 5 the full accent); the selected tile's number uses `effortTileTextColor(...)`. Both live in `lib/core/utils/session_feeling_utils.dart`; the ramp is `OmniThemeColors.intensityRamp` (see [Design System](design_system.md)).
- **Must answer:** `isDismissible: false, enableDrag: false`. The sheet has no close or skip control; one tap on a tile writes through `WorkoutState.updateSessionFeeling(sessionId, rating)` and closes it. The settings toggle is the only way not to be asked.
- **Once per session:** `_hasShownFeelingSheet` guards against re-show on rebuilds, and the sheet is skipped when the session already has a rating.
- **Refresh:** when the sheet closes, the summary rebuilds so the EFFORT row shows the new value immediately.
- **Toggle:** the "Effort Rating" switch in `Settings → WORKOUT` (default on, preference key `show_feeling_survey`, see [Theme & Settings](theme_and_settings.md)) disables the automatic prompt.
- **Never shown** on a summary opened from the calendar (`openedFromCalendar: true`), during the discard / "Unsaved changes" guard, or in-session.

#### EFFORT row (add or change the rating)

The first summary card always carries an EFFORT row, whether or not the toggle is on and for both post-workout and calendar-opened summaries. It sits beneath the Duration | Rest Time row as a second full-width row:

- `_StatPill` labelled EFFORT, value `n / 5` in that step's ramp color, or `—` when unrated.
- A trailing text button: **Add rating** when unrated, **Change** when rated.
- The button opens the same `_FeelingSheetContent` with the current value pre-selected. Unlike the automatic prompt, this user-opened sheet **is dismissible** (tap outside or swipe down) and dismissing changes nothing. Picking a value saves through `updateSessionFeeling`, closes the sheet and refreshes the row.
- **Rolling sessions:** the card still renders, but with only the EFFORT row — Duration and Rest Time stay hidden as before.

Tests: `test/session_summary_effort_row_test.dart` (automatic-prompt refresh, add / change / dismiss on fresh and calendar-opened sessions, rolling sessions).

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

Effort rating sheet behavior:

- automatic prompt shown after first frame when sessionFeeling is null, the toggle is on and the summary is not calendar-opened
- automatic prompt is non-dismissible until the user selects a value; the EFFORT row's Add rating / Change sheet is dismissible
- both write through updateSessionFeeling and refresh the summary when they close

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
