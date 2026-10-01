# Feature: Scope Stats screen Strength/Cardio exercise selection to a current-state window

## Overview

The Stats screen's Strength and Cardio cards auto-select the user's most-frequently-trained exercises. Today that selection ranks across the user's entire training history, so a lift hammered a year ago can occupy a card while the user's current focus never appears. This change scopes **which exercises get selected** to a current-state window — an active training period if the user is in one, otherwise the most recent stretch of training days — so the cards reflect what the user is actually doing now. Only the selection changes: each selected exercise's trend chart keeps using full history (progression lives there), and Recent PRs stays all-time (a PR's whole point is being a lifetime high). The window is also surfaced on-screen so the readout explains itself.

## Requirements

- Determine a single "current window" used to choose which exercises appear in BOTH the Strength and Cardio sections:
  - If today falls inside a user-defined training period that contains at least one qualifying completed session, use that period's date range.
  - Otherwise, use the most recent N training days, where a "training day" is a calendar day with at least one completed session, and N is a single tunable constant in one place.
- Within that window, choose the top exercises exactly the way they are chosen today (same notion of "most trained", same counts per section, same tiebreaking). Only the session set selection runs over changes — the ranking method itself does not change.
- Each section displays which window is currently in use: the period's name when period-scoped, or a clear "recent training days" label otherwise.
- For each exercise that gets selected, its trend chart continues to use that exercise's FULL history, not the window. The window decides who appears, not how far back their trend is drawn.
- Recent PRs stays all-time.
- All Time pills, Activity bar chart, Streak, and Rest Time chart are byte-for-byte unchanged in behavior.
- When no exercises qualify within the window, the existing Strength/Cardio empty states render — never silently widen to all-time.

## Acceptance Criteria

- [ ] When today falls inside a user-defined training period that contains qualifying completed sessions, the Strength and Cardio sections select only from exercises trained within that period's date range, ignoring exercises trained only outside it.
- [ ] When today is not inside any period (or the active period has no qualifying sessions), both sections select only from exercises trained within the most recent N training days, where N is defined in a single place and changing it changes the window everywhere it applies.
- [ ] A "training day" counts as any calendar day with at least one completed session; the window is the N most recent such days, not the last N calendar days, so rest days and breaks do not shrink the data.
- [ ] Both sections use the same resolved window in a given load — they never reach back different distances.
- [ ] Each section visibly states its active window: the period's name when period-scoped, or a recent-training-days label otherwise.
- [ ] Every selected exercise's trend chart plots its full history, including training days that fall outside the current window.
- [ ] The Recent PRs card lists all-time PRs, unaffected by the window.
- [ ] The All Time pills, Activity chart, Streak, and Rest Time chart are byte-for-byte unchanged in behavior.
- [ ] When no exercises qualify within the window, the existing Strength/Cardio empty states render, rather than silently widening to all-time.

## Scenarios

### S-001: No active period — selection uses recent training days
- Trigger: User opens Stats with no periods defined, has sessions spread over the last several months.
- Precondition: Repository has at least 10 completed sessions across more than N training days; the most recent N training days include exercises A, B, C, and an older exercise D trained exclusively 90 days ago.
- Flow: `StatsScreen._loadData()` calls `StatsProgressService.computeProgressData()`.
- Expected outcome: topLifts/topCardio are chosen from sessions within the most recent N training days only. Exercise D (trained only 90+ days ago) does not appear. PRs and trend charts for the selected exercises still include the all-time data.
- Edge case of: none

### S-002: Active period that contains today — selection uses the period's range
- Trigger: User opens Stats while inside a user-defined training period (e.g., "Off-Season Strength Block") that runs from `2026-06-01` to `2026-08-31`.
- Precondition: Period exists in repository covering today. An exercise (ExA) was trained inside the period. An exercise (ExB) was trained heavily before the period started and not since.
- Flow: `StatsScreen._loadData()` calls `StatsProgressService.computeProgressData()`.
- Expected outcome: topLifts includes ExA. ExB is excluded because all of its training days are before the period's start. Strength and Cardio sections display the period's name as their window label.
- Edge case of: none

### S-003: Active period contains today but no qualifying sessions — falls back to recent training days
- Trigger: User opens Stats inside a period that was created but no sessions were logged within it.
- Precondition: Period exists covering today. Other sessions exist in the most recent N training days.
- Flow: `StatsScreen._loadData()` calls `StatsProgressService.computeProgressData()`.
- Expected outcome: The period is rejected (no qualifying session), the recent-training-days window is used, the section's window label shows "Last N training days" (or equivalent), and selection is non-empty.
- Edge case of: S-002

### S-004: Training days count ignores calendar gaps
- Trigger: User trained on Mon, Wed, Fri, Mon (4 distinct days with 2 rest days in between).
- Precondition: Most recent training days are Mon, Wed, Fri — 3 days, not 5 calendar days.
- Flow: `StatsProgressService` resolves the window.
- Expected outcome: The 3 most recent training days define the window. Calendar days with no completed session do not count toward the window.
- Edge case of: S-001

### S-005: Trend charts are not windowed
- Trigger: Selected exercise has training days both inside and outside the window.
- Precondition: An exercise (ExA) has a training day 90 days ago (outside any window) and another training day 3 days ago (inside the window).
- Flow: `StatsScreen._loadData()` calls `StatsProgressService.computeProgressData()`.
- Expected outcome: ExA is in topLifts. ExA's `e1RmTrend` and `volumeTrend` contain data points from BOTH the 90-day-old day and the 3-day-old day.
- Edge case of: S-001

### S-006: Recent PRs are all-time
- Trigger: A selected exercise's all-time PR was set 90 days ago; the user trained the same exercise this week with a smaller load.
- Precondition: One exercise (ExA) was set to a high e1RM 90 days ago. This week the user logged a smaller e1RM for ExA.
- Flow: `StatsScreen._loadData()` calls `StatsProgressService.computeProgressData()`.
- Expected outcome: Recent PRs for ExA reflects the all-time high (the 90-day-old day), not the smaller this-week value.
- Edge case of: S-005

### S-007: Both sections share one window in a given load
- Trigger: User is in an active period that contains both strength and cardio sessions.
- Precondition: Period covers today and contains sessions for both kinds. An exercise only trained outside the period is in the repository.
- Flow: `StatsScreen._loadData()` calls `StatsProgressService.computeProgressData()`.
- Expected outcome: topLifts and topCardio BOTH use the period as the window. They never reach back different distances. Both section labels show the period's name.
- Edge case of: S-002

### S-008: No qualifying exercises within the window — empty state
- Trigger: The most recent N training days have zero qualifying sessions (e.g., only drill or round efforts, no set/timed with positive metrics).
- Precondition: Repository has only drill or round efforts in the recent N training days.
- Flow: `StatsScreen._loadData()` calls `StatsProgressService.computeProgressData()`.
- Expected outcome: `topLifts` and `topCardio` are empty. The Strength section shows "No strength history yet" and the Cardio section shows "No cardio history yet" — the existing empty states. The service does NOT silently widen the window to all-time.
- Edge case of: S-001

### S-009: When the active period is in the past (today not in any period), fall back to recent training days
- Trigger: User has periods defined but none of them contain today.
- Precondition: Repository has one or more periods, none covering today. Sessions exist in the most recent N training days.
- Flow: `StatsScreen._loadData()` calls `StatsProgressService.computeProgressData()`.
- Expected outcome: The recent-training-days window is used. Section labels show the recent-training-days label, not any period's name.
- Edge case of: S-001

### S-010: N is a single tunable constant
- Trigger: Implementer changes `kRecentTrainingDaysWindow` to a different value.
- Precondition: The constant is the only place the window size is defined.
- Flow: Compile the app, run the test suite.
- Expected outcome: Every scenario above re-evaluates against the new N automatically; no other file has a hard-coded window size for this purpose.
- Edge case of: S-001

## Iteration 1

### DB Changes
None. The period and session models already exist; no schema, table, column, or migration changes.

### Backend Changes
None. The repository interface is unchanged.

### Frontend Changes

**`lib/core/models/stats_progress.dart`** — Add a new value type:

```
class StatsWindow {
  final DateTime fromMs;     // start-of-day, local midnight
  final DateTime toMs;       // end-of-day, local
  final String label;        // "Off-Season Strength Block" or "Last 14 training days"
  final bool isPeriodScoped; // true if from a TrainingPeriod
  final String? periodId;    // id when isPeriodScoped
  final String? periodName;  // name when isPeriodScoped
  final int? recentDays;     // N when !isPeriodScoped
}
```

Add `final StatsWindow window;` to `StatsProgressData`.

**`lib/core/services/stats_progress_service.dart`** — Window resolution + filtering:

- Add `static const int kRecentTrainingDaysWindow = 14;` as the single tunable.
- Add `static StatsWindow resolveWindow({required List<TrainingPeriod> periods, required List<TrainingSession> completedSessions, DateTime? now})`:
  - `now ??= DateTime.now()`.
  - For each period where `startDateMs <= startOfDayMs(now)*1000 <= endDateMs` (or appropriate midnight-anchored check), check if it contains at least one completed session whose `startedAtMs` falls within `[startDateMs, endDateMs]`. Pick the most recently-started such period; if multiple, the one with the latest `startDateMs`.
  - If found: return `StatsWindow(..., isPeriodScoped: true, periodId, periodName)`.
  - Otherwise: collect distinct calendar days from completed sessions, sort descending, take the first N (where N = `kRecentTrainingDaysWindow`), the window's `fromMs` = start-of-day of the earliest selected day, `toMs` = end-of-day of today, label = `"Last $N training days"`.
  - Edge case: N=0 sessions → window has empty `fromMs`/`toMs` (use today's start/end) and label = `"Last $N training days"`. Selection filters on this window and yields empty.
- Update `computeProgressData()`:
  - Fetch all sessions (existing) AND all periods via `_repository.getPeriods()`.
  - Resolve the window.
  - When iterating sessions for setsByExercise / cardioByExercise, skip sessions whose `startedAtMs` falls outside `[window.fromMs, window.toMs]`.
  - When iterating for the trend chart for a SELECTED exercise, do NOT skip — the selected exercise's `e1RmTrend` and `volumeTrend` must include all completed sessions for that exercise.
  - When iterating for `recentPRs` and `getAllTimeBestE1RM`, do NOT skip — PRs stay all-time.
  - Construct `StatsProgressData` with the resolved `window`.

**`lib/features/stats/stats_screen.dart`** — UI:

- In `_loadData()`, the call to `StatsProgressService.computeProgressData()` already exists; it now receives the resolved window as part of the data.
- In `_buildStrengthSection` and `_buildCardioSection`, render a small "window chip" line above each section's contents:
  - `data.window.label` (e.g., "Off-Season Strength Block" or "Last 14 training days").
  - Style: small label, muted color, same row as the section header (or just below it).
- No new state, no new repository calls — the service does the work and returns the window inside `StatsProgressData`.
- The empty-state copy and the rest of the screen remain unchanged.

**`test/stats_progress_test.dart`** — Update existing tests + add new ones:

- Rewrite the following tests to seed sessions relative to "now" so they fall inside the recent-training-days window:
  - `respects kTopLiftCount when fewer exercises exist`
  - `top 2 cardio selected correctly with alphabetical tiebreak`
  - The effort-routing tests that seed dated sessions (set effort in null-modality session, timed effort in lifting-modality session, drill effort in lifting session, only-set / only-timed empty-state tests, e1RM trend test, volume trend test, PR detection tests, single-rep set, cardio pace, single-PR, multiple-exercises PR).
  - Replace `DateTime(2024, 1, 1)` etc. with a helper `_daysAgo(int n)` that returns local midnight N days before now.
- New tests (with TDD red→green):
  - `S-001: an exercise trained only outside the recent window does not appear in selection; one trained inside does.`
  - `S-002: with an active period covering today, selection includes an exercise trained inside the period and excludes one trained before the period started.`
  - `S-003: an active period that contains no qualifying completed sessions falls back to the recent-training-days window rather than rendering empty.`
  - `S-005: a selected exercise's trend still contains data points from training days that fall outside the current window.`
  - `S-006: Recent PRs still reflects an all-time high that was set outside the current window.`
  - `S-004: training days counting ignores gaps — sessions spread across a date range with rest days in between still resolve the intended number of training days, not calendar days.`
  - `S-007: both sections resolve to the same window in a single computation (e.g., a period active for one section is active for both).`
  - `S-008: when no exercises qualify within the window, topLifts and topCardio are empty (the service does not silently widen to all-time).`
  - `S-009: when the active period is in the past (today not in any period), the recent-training-days window is used.`
  - `S-010: kRecentTrainingDaysWindow is the single tunable (compile-time check: any other path that selects top-N uses the resolved window).`

### Implementation Steps

**`lib/core/models/stats_progress.dart`**
1. [ ] Add `StatsWindow` class with `fromMs`, `toMs`, `label`, `isPeriodScoped`, `periodId?`, `periodName?`, `recentDays?`, plus a `const` constructor and a named factory `StatsWindow.recentDays(int n, {required DateTime today, required int trainingDaysAvailable})`.
2. [ ] Add `final StatsWindow window;` to `StatsProgressData`. Update `StatsProgressData.empty` to use a placeholder (e.g., a `StatsWindow` with `label: 'No data'`).

**`lib/core/services/stats_progress_service.dart`**
3. [ ] Add `static const int kRecentTrainingDaysWindow = 14;` next to the other constants.
4. [ ] Implement `static StatsWindow resolveWindow({required List<TrainingPeriod> periods, required List<TrainingSession> completedSessions, DateTime? now})`:
   - Compute today's local midnight and end-of-day.
   - Iterate periods, filter to those that cover today (start ≤ today ≤ end) and contain ≥1 completed session in their range. If multiple, pick the one with the latest `startDateMs`; tiebreak by `id` ascending for determinism.
   - If a period is found, return `StatsWindow(periodId, periodName, ...)`.
   - Otherwise, take distinct calendar days from `completedSessions` (date-component of `startedAtMs`), sort descending, take the first N, derive `fromMs`/`toMs`, and label.
5. [ ] Update `computeProgressData()`:
   - Fetch periods via `_repository.getPeriods()`.
   - Call `resolveWindow(periods: periods, completedSessions: completed)` and store the result.
   - For the per-session iteration that builds `setsByExercise` and `cardioByExercise`, filter to sessions whose `startedAtMs` falls within `[window.fromMs, window.toMs]`. This is the **selection** iteration.
   - After `topLiftIds` and `topCardioIds` are chosen, iterate the FULL `completed` session list again (NOT filtered) to build the trend data for the selected exercises. This is the **trend** iteration.
   - For the PR detection loop, iterate the FULL `completed` session list (NOT filtered).
   - Return `StatsProgressData(..., window: window)`.

**`lib/features/stats/stats_screen.dart`**
6. [ ] In `_buildStrengthSection`, after the `STRENGTH` section label, render `_buildWindowChip(data.window)` showing the window's label.
7. [ ] In `_buildCardioSection`, after the `CARDIO` section label, render `_buildWindowChip(data.window)` showing the window's label.
8. [ ] Implement `_buildWindowChip(StatsWindow window)` as a small `Text` widget in `textTheme.labelSmall` muted color with optional period-color accent.

**`test/stats_progress_test.dart`**
9. [ ] Add helper `_daysAgo(int n)` returning `DateTime(today.year, today.month, today.day).subtract(Duration(days: n))`.
10. [ ] Update all currently-2024-dated tests to use `_daysAgo(0)`, `_daysAgo(1)`, etc. Keep the assertions on counts / names / values intact.
11. [ ] Add the S-001..S-010 tests above, using `_daysAgo(...)` for relative dates and `repo.createPeriod(TrainingPeriod(...))` for the period scenarios.

**Docs**
12. [ ] Update `docs/stats_screen.md` to describe the window resolution rule, the `StatsWindow` value type, the `kRecentTrainingDaysWindow` constant, and the on-screen window label rendering.
13. [ ] Update `docs/state_management.md` (or a sub-section) to note that `StatsProgressService.computeProgressData()` now depends on the `WorkoutRepository.getPeriods()` method (no interface change, just an internal extra call).
14. [ ] Update `docs/widget_catalog.md` if a new `StatsWindowChip` widget is added (or skip if it's an inline `_buildWindowChip` on the screen).

## Progress
- [x] Phase 0 plan file written
- [x] Phase 1: `StatsWindow` model added to `lib/core/models/stats_progress.dart`
- [x] Phase 1: `kRecentTrainingDaysWindow` and `resolveWindow` added to `StatsProgressService`
- [x] Phase 1: `computeProgressData` filters selection sessions by window; trends and PRs use full history
- [x] Phase 2.1: TDD red tests written and confirmed failing before implementation
- [x] Phase 2: Stats screen renders the window label for Strength and Cardio sections
- [x] Phase 2: All Phase 0 tests pass; no previously passing tests are now failing
- [x] Phase 2.7: `docs/stats_screen.md`, `docs/navigation_and_screens.md` updated
- [x] Phase 3: Code review completed

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

## Feedback

### TDD Red Run (Phase 2.1)

The 10 windowed-selection tests (S-001..S-010) were written against
`StatsProgressService` and confirmed failing before implementation:

```
test/stats_progress_test.dart:1972:37: Error: Member not found: 'kRecentTrainingDaysWindow'.
test/stats_progress_test.dart:1977:32: Error: Member not found: 'kRecentTrainingDaysWindow'.
lib/core/services/stats_progress_service.dart:191:29: Error: Required named parameter 'window' must be provided.
```

These are exactly the implementation gaps the new tests exercise:
- The single tunable constant is missing.
- `computeProgressData()` does not resolve or pass a window to
  `StatsProgressData`.

Resolution: Phase 2.2-2.4 will add the constant, the static
`resolveWindow` method, the filtering inside `computeProgressData`
(selection uses the window; trends and PRs use full history), and
the `StatsWindow` is plumbed into `StatsProgressData`.

