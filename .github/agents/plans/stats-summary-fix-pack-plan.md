# Feature: Stats & Summary Fix Pack (PR de-duplication, bodyweight inclusion, recency floor)

> **Status**: Iteration 1 active. Two-PR plan — PR1 is Tier 1 launch-critical
> (Session Summary PR de-duplication); PR2 is Tier 2 Stats correctness
> (bodyweight inclusion + recency floor). They share the same Stats
> exercise-selection machinery, so they ship together as PR2.

---

## Overview

Three post-launch fixes to OmniTrain's progress reporting:

1. **PR1 / Tier 1 — Session Summary PR de-duplication.** When the same
   exercise appears in more than one block (or cloned block) in a single
   session, the post-workout summary currently emits one "New best" line
   per block instead of one per exercise, burying the genuine record
   among duplicates. Collapse to at most one entry per exercise at the
   session's true maximum.

2. **PR2 / Tier 2a — Bodyweight exercises as first-class Strength.**
   Pull-ups, chin-ups, push-ups, dips and similar are silently excluded
   from Strength stats, records, and the exercise ranking when logged at
   bodyweight (no added load). Bring them in: progress trend = reps
   per training day; personal record = max reps in a single set;
   eligible for top slots alongside loaded lifts; ranked by training
   frequency. Added weight (e.g. dip belt) is annotation only — it does
   not switch the exercise onto a weight axis or contribute to the kg
   Total Volume.

3. **PR2 / Tier 2b — Recency floor on Strength/Cardio selection.**
   An exercise trained heavily long ago can hold a top slot long after
   the user has moved on, displacing current work. Drop exercises not
   trained within a recent threshold from the displayed top slots, while
   preserving full history/trend for any exercise that does appear, and
   applying the same recency logic to Cardio for behavioural parity.

---

## Phase Match Strategy

Classified as **STANDARD** — multi-surface, multi-PR work touching the
session summary surface (PR list), the stats service (selection +
trends + PR detection), the stats screen widget (rendering), and the
mock repository. Full plan with scenario discovery below; red tests
before implementation; doc hygiene on each pass.

---

## Requirements

| # | Requirement | Source |
|---|-------------|--------|
| R-1 | Session Summary's PR list collapses to at most one entry per exercise per session, at the session's true maximum e1RM. | Item 1 |
| R-2 | PR de-duplication is purely a count change — record verdict (PR / not-PR), set count, total volume, and per-exercise breakdown are unchanged. | Item 1 |
| R-3 | Bodyweight exercises (sets with no added external weight) appear in the Strength section, on a reps axis, with a max-reps personal record. | Item 2 |
| R-4 | Pull-ups and chin-ups are not excluded by any category or equipment technicality — inclusion is purely "no added load on the set". | Item 2 |
| R-5 | A bodyweight exercise competes for Strength top slots on the same training-frequency basis as a loaded lift. | Item 2 |
| R-6 | When a bodyweight set is logged with added weight, the added weight is recorded as annotation only — no separate weight record, no switch to a weight axis. | Item 2 |
| R-7 | The kg Total Volume figure is unchanged whether or not bodyweight sets are present. | Item 2 |
| R-8 | Loaded exercises (barbell / dumbbell / machine / cable) keep their existing weight-based trend and record unchanged. | Item 2 |
| R-9 | Rep-based PR parity — the same bodyweight set yields the same max-reps verdict on the Stats screen, the in-session record notification, and the post-workout summary. | Item 2 |
| R-10 | Strength/Cardio selection drops exercises not trained within a recent threshold from the displayed top slots, freeing slots for current work. | Item 3 |
| R-11 | Trend charts for exercises that DO appear still plot full history. Underlying data is never deleted or hidden. | Item 3 |
| R-12 | The threshold is generous enough that normal rotation (e.g. weekly / biweekly) does not flicker a lift in and out across consecutive sessions. | Item 3 |
| R-13 | A previously-dropped exercise that returns to training reappears with its complete historical trend intact. | Item 3 |
| R-14 | Same recency logic applies to Cardio selection. | Item 3 |

---

## Acceptance Criteria

### PR 1 — Session Summary de-duplication (Item 1)

- [ ] **AC-1.1** When an exercise appears in multiple blocks in one session, the summary's PR list shows exactly one entry for that exercise.
- [ ] **AC-1.2** The single entry reflects the highest qualifying effort of that exercise in the session, not the first, last, or a lower block.
- [ ] **AC-1.3** Cloning a block N times produces the same number of PR entries as performing it once for that exercise.
- [ ] **AC-1.4** The "was …" prior-best value on the collapsed entry matches the exercise's all-time best from before this session.
- [ ] **AC-1.5** Session's set count and total volume are identical before and after this change for the same logged data.
- [ ] **AC-1.6** An exercise that sets no new record still produces no record entry.
- [ ] **AC-1.7** Cross-surface record-parity guards continue to pass unchanged — entry count is the only surface affected.

### PR 2 — Strength Stats correctness (Items 2 + 3)

- [ ] **AC-2.1** Bodyweight-only sets (no added weight) produce a reps trend and a max-reps personal record; the exercise is eligible for the Strength top slots.
- [ ] **AC-2.2** Pull-ups and chin-ups logged at bodyweight are included — not excluded by any label or category.
- [ ] **AC-2.3** A bodyweight exercise trained on more days ranks ahead of a loaded exercise trained on fewer.
- [ ] **AC-2.4** A bodyweight set logged with added weight records the added weight as annotation only; no weight-axis record; the exercise's reps trend is unchanged.
- [ ] **AC-2.5** The kg Total Volume figure is identical with and without bodyweight sets present.
- [ ] **AC-2.6** Rep-based record parity — the same bodyweight set yields the same max-reps verdict on the Stats screen, the in-session notification, and the post-workout summary.
- [ ] **AC-2.7** An exercise not trained within the recency threshold does not occupy a Strength top slot, even when its historical frequency is high.
- [ ] **AC-2.8** A currently-trained exercise takes the slot vacated by a stale one.
- [ ] **AC-2.9** An exercise trained on a regular cadence (e.g. weekly / biweekly) stays present across multiple consecutive sessions.
- [ ] **AC-2.10** A previously-dropped exercise that returns to training reappears with its full historical trend intact — no data lost.
- [ ] **AC-2.11** Number of displayed Strength/Cardio slots is unchanged; only which exercises fill them changes.
- [ ] **AC-2.12** Cardio selection honours the same recency floor as Strength.
- [ ] **AC-2.13** Loaded exercises' trends and records are unchanged from current behaviour.

---

## Scenarios

### PR 1 — Session Summary PR de-duplication (Item 1)

#### S-001: Same exercise in 3 cloned blocks → exactly one PR entry
- **Trigger**: User logs a 3-block session where each block contains the
  same exercise (cloned three times). All sets beat the prior all-time
  e1RM.
- **Precondition**: Mock repo has one prior completed session for
  `exerciseX` with `reps=5, weight=60` (e1RM 70.0). Current session has
  three blocks, each with one effort for `exerciseX` at
  `reps=5, weight=70` (e1RM 81.67).
- **Flow**: User finishes the session. `SessionSummaryScreen._loadAsyncData`
  calls `SessionSummaryService.computePRs(exercises, currentSessionId)`.
- **Expected outcome**: `prs.length == 1`. The single entry's
  `exerciseName == exerciseX.name`, `newBest ≈ 81.67`, `previousBest == 70.0`.
- **Edge case of**: none.

#### S-002: Two different exercises across blocks → one entry each
- **Trigger**: Session contains `exerciseA` in 2 blocks and `exerciseB`
  in 2 blocks, all beating the prior best.
- **Precondition**: Both exercises have prior completed history.
- **Flow**: User finishes the session.
- **Expected outcome**: `prs.length == 2`, one per exercise name, at
  each exercise's true session maximum.
- **Edge case of**: S-001.

#### S-003: Cloned block that does NOT beat prior best → zero entries
- **Trigger**: Session contains `exerciseX` cloned twice, but every set
  is below or equal to the prior all-time best.
- **Precondition**: Prior best for `exerciseX` strictly exceeds every
  set in the session.
- **Flow**: User finishes the session.
- **Expected outcome**: `prs` is empty for that exercise. No duplicate,
  no duplicate of zero, no entry at all.
- **Edge case of**: S-001.

#### S-004: Set count and total volume unchanged after de-duplication
- **Trigger**: Same session data as S-001.
- **Flow**: Compare session's `totalSets` and `totalVolume` against the
  pre-change expected values.
- **Expected outcome**: `totalSets` and `totalVolume` are byte-equal to
  the pre-change values — the de-duplication only touches the PR list.
- **Edge case of**: S-001.

#### S-005: Cross-surface parity guard unchanged
- **Trigger**: Same set produces a verdict in the in-session toast,
  the Stats screen, and the post-workout summary.
- **Flow**: `S-T-001` cross-surface test in `services_test.dart` and
  `S-009` parity guard in `in_session_pr_toast_test.dart`.
- **Expected outcome**: Both tests pass without modification — the
  record verdict, not the entry count, is what they assert.
- **Edge case of**: none.

### PR 2 — Bodyweight inclusion (Item 2)

#### S-101: Bodyweight pull-up logged → reps trend + max-reps PR + eligible
- **Trigger**: User logs a session containing only `exercise-pullup`
  with `reps=12, weight=0` (no added load).
- **Precondition**: Empty mock repo (or no prior pull-up history).
- **Flow**: `StatsProgressService.computeProgressData()`.
- **Expected outcome**:
  - `data.topLifts` contains a `LiftProgress` for `Pull-Up`.
  - Its `e1RmTrend` is replaced by a `repsTrend` (new field), with one
    point per training day at the day's max reps.
  - `data.recentPRs` (now accepting rep-based PRs) contains a
    `StatsPR` with `reps == 12`, `weight == null`, `date == today`,
    and `exerciseName == "Pull-Up"`.
- **Edge case of**: none.

#### S-102: Pull-ups and chin-ups at bodyweight are not excluded by label
- **Trigger**: User logs only `exercise-pullup` and `exercise-chin-up`
  (no added load) for several sessions.
- **Precondition**: Seed data's `equipment-pullup-bar` is on the pull-up
  and chin-up exercises — they are NOT labelled `equipment-bodyweight`.
- **Flow**: `StatsProgressService.computeProgressData()`.
- **Expected outcome**: Both exercises appear in `data.topLifts`. The
  selection does not depend on the exercise's equipment label — only
  on whether sets were performed without added weight.
- **Edge case of**: S-101.

#### S-103: Bodyweight trained more frequently ranks above loaded
- **Trigger**: `BW` (e.g. pull-ups) trained on 5 distinct days; `LD`
  (e.g. bench press) trained on 2 distinct days, all within the window.
- **Precondition**: Both have at least one set with positive reps in
  the window. `BW`'s sets have `weight == 0`; `LD`'s sets have
  `weight > 0`.
- **Flow**: `StatsProgressService.computeProgressData()` and
  `_selectTopN(setsByExercise, kTopLiftCount, …)`.
- **Expected outcome**: `BW` ranks ahead of `LD` in `data.topLifts` by
  distinct training-day count, with the same alphabetical tiebreak.
- **Edge case of**: none.

#### S-104: Weighted bodyweight set → annotation only, no weight-axis PR
- **Trigger**: User logs a pull-up set with `reps=8, weight=0,
  extra-weight=10` (10 kg added at the belt).
- **Precondition**: Mock repo has the set with the three observations:
  `metric-reps`, `metric-weight (= 0.0)`, `metric-extra-weight (= 10.0)`.
- **Flow**: `StatsProgressService.computeProgressData()` and
  `getAllTimeBestE1RM`.
- **Expected outcome**:
  - The exercise's `repsTrend` is unchanged from the unweighted case —
    the 10 kg belt does NOT produce a `metric-weight` value above zero.
  - No `StatsPR` with a weight/e1RM verdict is produced for this set.
  - The set's added weight is preserved in the
    `EffortObservation` rows but never read into the trend or the
    PR verdict.
- **Edge case of**: S-101.

#### S-105: kg Total Volume unchanged by bodyweight sets
- **Trigger**: Two otherwise-identical sessions — one with a bodyweight
  pull-up set, one with no exercises.
- **Precondition**: Same `exerciseX` loaded set in both sessions at
  `reps=5, weight=100` (e1RM 116.67).
- **Flow**: Read `summary.totalVolume` from each session summary, and
  read the same field from the `SessionGroupMetrics` for the `strength`
  group.
- **Expected outcome**: `totalVolume == 500.0` in both — bodyweight sets
  do not contribute to the kg total. The pull-up adds reps and sets but
  not kilograms.
- **Edge case of**: S-101.

#### S-106: Rep-based record parity across three surfaces
- **Trigger**: User logs a new pull-up max (`reps=15`) at bodyweight,
  then finishes the session.
- **Precondition**: Mock repo has no prior pull-up history.
- **Flow**:
  - **Surface A (in-session toast)**: at the moment of logging, the
    standing best for reps is 0; the just-logged 15 reps exceeds the
    threshold → toast fires.
  - **Surface B (Stats screen)**: `StatsProgressService` walks the
    pull-up's reps trend, detects `15` as a new max-reps high for the
    exercise, adds it to `recentPRs`.
  - **Surface C (Session Summary)**: `SessionSummaryService.computePRs`
    for the just-finished session detects the 15-rep pull-up as a new
    rep-based PR against the prior best (0).
- **Expected outcome**: All three surfaces record the same `15 reps`
  verdict for the same set.
- **Edge case of**: none.

### PR 2 — Recency floor on Strength/Cardio selection (Item 3)

#### S-201: Stale exercise dropped from Strength top slots
- **Trigger**: `StaleLift` trained on 10 distinct days, all > N days
  ago (outside the recency threshold). `CurrentLift` trained on 2
  distinct days, both today.
- **Precondition**: `StaleLift`'s most-recent training day is older
  than the recency threshold (default: see "Threshold selection"
  below).
- **Flow**: `StatsProgressService.computeProgressData()`.
- **Expected outcome**: `StaleLift` does NOT appear in `data.topLifts`.
  `CurrentLift` does.
- **Edge case of**: none.

#### S-202: Currently-trained exercise takes the freed slot
- **Trigger**: 4 exercises all eligible by frequency; top 3 would be
  selected without the floor. With the floor, `StaleLift` (most
  frequent but stale) drops; `FreshLift` (less frequent but recent)
  enters.
- **Precondition**: `StaleLift` last trained 30 days ago (e.g.);
  `FreshLift` last trained today.
- **Flow**: `StatsProgressService.computeProgressData()`.
- **Expected outcome**: `data.topLifts` contains the three most-recent
  (and still-frequent-enough) exercises. `StaleLift` is excluded;
  `FreshLift` is included.
- **Edge case of**: S-201.

#### S-203: Regular-cadence exercise stays present across consecutive sessions
- **Trigger**: User trains `WeeklyLift` on Mondays for several weeks.
  The recency threshold must be generous enough that a 7-day gap does
  not drop the lift.
- **Precondition**: `WeeklyLift` has a training day 5 days ago; the
  recency threshold is 14 days.
- **Flow**: Two consecutive loads of `computeProgressData()`, with a
  new session in between that also trains `WeeklyLift`.
- **Expected outcome**: `WeeklyLift` appears in `topLifts` on both
  loads. It does not flicker.
- **Edge case of**: S-201.

#### S-204: Dropped exercise returns → full historical trend intact
- **Trigger**: `StaleLift` trained 60 days ago, then dropped. User
  trains `StaleLift` again today.
- **Precondition**: `StaleLift` has historical trend points from the
  original training cycle.
- **Flow**: `StatsProgressService.computeProgressData()` after the
  new session.
- **Expected outcome**: `StaleLift` reappears in `topLifts`. Its
  `e1RmTrend` / `repsTrend` contains both the old points and the new
  point — full history preserved.
- **Edge case of**: S-201.

#### S-205: Cardio selection honours the same recency floor
- **Trigger**: `StaleCardio` trained on 8 distinct days, all > 30 days
  ago. `CurrentCardio` trained on 3 distinct days, all recent.
- **Precondition**: Mock repo has timed instances for both, with
  `state == TimedState.finished` and positive duration.
- **Flow**: `StatsProgressService.computeProgressData()`.
- **Expected outcome**: `StaleCardio` does NOT appear in
  `data.topCardio`. `CurrentCardio` does. The threshold is the same
  constant used for Strength.
- **Edge case of**: S-201.

---

## Iteration 1

### DB Changes

None — no schema changes, no model field changes. New logic only in the
service layer + a small extension to `StatsProgress` value types for
the reps trend and the recency threshold. The model-layer changes are
additive:

- `LiftProgress` gains an optional `repsTrend: List<TrendPoint>` (the
  bodyweight axis). `e1RmTrend` and `volumeTrend` stay exactly as
  they are for loaded exercises.
- `StatsPR` gains an optional `reps: int?` (the bodyweight PR verdict).
  `e1Rm` stays as the loaded-exercise verdict. Exactly one of `reps`
  or `e1Rm` is non-null for any given `StatsPR`.
- `StatsProgressService` gains two constants: the recency threshold
  (`kStrengthRecencyDays`, default 30) and a setter-friendly knob for
  tests.

No `fromMap`/`toMap` changes are required because `LiftProgress` and
`StatsPR` are pure value types without persistence — they live
exclusively in the service layer.

### Backend Changes

`lib/core/services/stats_progress_service.dart` is the primary surface
for both Item 2 and Item 3:

- **Bodyweight inclusion (Item 2)**:
  - The `_processSetEffort` step currently skips entries where
    `weight <= 0 || reps <= 0`. Change the predicate so that:
    - entries with `weight > 0` go on the weight axis as today (e1RM +
      volume), unchanged.
    - entries with `weight == 0` AND `reps > 0` go on a new reps axis.
    - entries with `weight > 0` AND a separate `extra-weight`
      observation go on the weight axis; the extra-weight value is
      stored on the observation row for annotation purposes but is
      not added to the trend or to `totalVolume`.
  - Add a parallel `setsByExerciseByReps` accumulator for bodyweight
    entries. Both axes share the same per-exercise training-day map
    for selection (a training day is a training day regardless of
    axis).
  - `e1RmTrend` is populated only when the exercise has at least one
    weighted set; `repsTrend` is populated when the exercise has at
    least one bodyweight set. Exercises with BOTH axes (mixed
    training) populate both. The UI sees whichever is non-empty.
  - The `recentPRs` walker checks: did this day's reps exceed the
    exercise's prior max reps on the reps axis? If yes, add a
    `StatsPR(reps: …, e1Rm: null, …)`. The existing e1RM walker is
    unchanged.
  - `getAllTimeBestE1RM` is unchanged — bodyweight sets do not
    contribute to e1RM (they have `weight == 0`).
  - **NEW** `getAllTimeBestReps(exerciseId, {excludeSessionId})`
    mirrors `getAllTimeBestE1RM` but walks the reps axis. Returns
    `0` for no prior history (strict `>` comparison → first-ever is
    a PR). Used by the in-session toast and the Session Summary.

`lib/core/services/session_summary_service.dart`:

- **PR de-duplication (Item 1)**:
  - `computePRs` already iterates `exercises` (a `List<ExerciseSummary>`)
    and emits at most one `PRAchievement` per `ExerciseSummary`. The
    remaining duplication source is that the same exercise appears as
    multiple `ExerciseSummary` entries (one per block). The fix is to
    group `exercises` by `exerciseId` BEFORE the loop, take the
    `max(bestE1RM)` across the group, and emit one `PRAchievement`
    per group. The `previousBest` is unchanged (`getAllTimeBestE1RM`
    with `excludeSessionId`).
  - The de-duplication logic lives in `computePRs` itself so every
    caller (the summary screen and any future caller) gets it for
    free. No state, feature, or widget code changes for Item 1.
- **Rep-based PR detection (Item 2)**:
  - Extend `computePRs` to additionally emit `PRAchievement` for
    bodyweight exercises, with `metricLabel: 'reps'`,
    `newBest: summary.bestReps`, `previousBest: maxRepsBeforeSession`.
    Use the new `getAllTimeBestReps` helper. The current e1RM path
    is unchanged — bodyweight exercises never have a non-null
    `bestE1RM`, so the existing loop continues to skip them, and the
    new reps path picks them up.
  - `groupPrsByEffortKind` keeps the existing mapping — both e1RM
    and reps PRs for `set`-kind efforts land in the `'strength'`
    bucket.

`lib/widgets/session/pr_toast.dart`:

- **Rep-based toast (Item 2)**:
  - Add a sibling builder `PRToast.buildRepPRSnackBar(theme, reps)` so
    the in-session toast can also celebrate a new max-reps record.
    Mirrors `buildPRSnackBar` in shape, copy, and timing. The toast
    copy for a rep PR stays `"Congrats! New PR"` (the in-session
    toast is intentionally minimal — D-11 in the existing in-session
    toast plan — and the body's "instrument panel" rule forbids
    showing the value on the toast).

`lib/features/session/workout_session_screen.dart`:

- **Rep-based toast wiring (Item 2)**:
  - `_maybeShowPRToast` gains a parallel reps-axis check: if the
    exercise has no e1RM-eligible set in this log (i.e. `weight == 0`
    and `reps > 0`), call the new `getAllTimeBestReps` and compare
    against the just-logged reps. If the new reps strictly exceeds
    the standing best AND the session's running best, show the
    rep-PR toast and update the running best. The e1RM path is
    unchanged — bodyweight sets never enter it.

- **Recency floor selection (Item 3)**:
  - In `computeProgressData()`, after `_selectTopN` produces the
    candidate lists, apply a second-pass filter: drop any candidate
    whose most-recent training day is older than
    `kStrengthRecencyDays` ago (default 30). After the filter,
    refill the top-N list from the next-most-recent candidates
    that DO qualify. If the filter empties a bucket (e.g. all
    candidates are stale), the bucket stays empty — the existing
    empty states render.
  - The threshold is applied symmetrically to Strength and Cardio
    selection — both share the same constant.
  - Trend charts and `recentPRs` are unaffected — the filter is a
    selection-time decision only.

### Frontend Changes

`lib/features/stats/stats_screen.dart`:

- **Item 2 — reps trend display**:
  - The lift card's e1RM and Volume charts are rendered when the
    exercise has ≥ 2 weighted points. Add a parallel reps-trend
    chart rendered when the exercise has ≥ 2 reps points and no
    weighted points (purely bodyweight exercise). For mixed-axis
    exercises, render both. The reps chart uses the same
    `ScrollableTrendChart` wrapper, with `'reps'` as the axis label
    (no kg/lbs suffix).
  - The single-point fallback mirrors the existing single-point
    cards: e.g. `"Pull-Ups: 15 reps — Mon DD, YYYY"` for a single
    training day.
- **Item 2 — Recent PRs card**:
  - When a `StatsPR` has `reps != null`, render `"Pull-Ups — 15 reps"`
    on the right side instead of the e1RM/weight value. When
    `e1Rm != null`, render as today. The date column is unchanged.
- **Item 3 — recency chip**:
  - No new chip. The existing `_buildWindowChip` already explains
    the window the selection was drawn from. The threshold change
    is invisible to the user unless the chip's wording changes —
    leaving the wording as `· Last 14 training days` (or the
    period's name) preserves the existing UX.

### Implementation Steps

#### PR 1 — Session Summary PR de-duplication (Item 1)
1. Add `getAllTimeBestReps` constant + helper in `StatsProgressService`
   (placeholder for now, used by PR 2 / Item 2 — keeps the diff small).
2. Modify `SessionSummaryService.computePRs` to group `exercises` by
   `exerciseId` before the e1RM loop, take `max(bestE1RM)` per group,
   and emit at most one `PRAchievement` per `exerciseId`.
3. Add a parallel reps-axis pass inside `computePRs` that emits a
   `PRAchievement(metricLabel: 'reps')` per `exerciseId` for bodyweight
   exercises (gated on `bestE1RM == null && bestReps != null &&
   bestReps > 0`).
4. Add the rep-based axis to `ExerciseSummary` model
   (`bestReps: int?`, set in `SessionSummaryBuilder`).
5. Red tests (Phase 0.5):
   - `services_test.dart`: S-001, S-002, S-003, S-004, S-005.
   - New `rep_based_pr_parity_test.dart` (or extend
     `in_session_pr_toast_test.dart`): S-106 reps-axis parity.
6. Implement the changes; tests must go green.
7. Doc hygiene: update `docs/session_summary.md`, `docs/stats_screen.md`
   with the reps-axis contract.

#### PR 2 — Stats correctness (Items 2 + 3)
1. Extend `_processSetEffort` in `StatsProgressService` to populate a
   parallel reps axis for bodyweight sets (weight == 0, reps > 0).
   Preserve the e1RM and volume axes unchanged for loaded sets.
2. Extend `LiftProgress` model with `repsTrend: List<TrendPoint>` (and
   keep `e1RmTrend` + `volumeTrend` for loaded).
3. Extend `StatsPR` model with `reps: int?` (and keep `e1Rm: double`).
4. Extend `computeProgressData`'s PR walker with the reps-axis pass.
5. Add `getAllTimeBestReps(exerciseId, {excludeSessionId})` to
   `StatsProgressService`. Returns `0` for no prior history.
6. Wire the in-session reps-PR toast:
   - `PRToast.buildRepPRSnackBar(theme, reps)`.
   - `_maybeShowPRToast` checks the reps axis when the set's weight is
     zero and reps are positive; uses `_sessionRunningBestReps`
     alongside `_sessionRunningBestE1RM`.
7. Apply the recency floor:
   - New constant `kStrengthRecencyDays` (default 30) in
     `StatsProgressService`.
   - Second-pass filter inside `computeProgressData`: drop candidates
     whose last training day is older than the threshold, refill the
     top-N list from the next-most-recent eligible candidates.
8. Update `lib/features/stats/stats_screen.dart` to render the
   reps-trend card, the reps-verdict in the Recent PRs card, and
   ensure the existing e1RM / Volume charts stay unchanged for
   loaded exercises.
9. Red tests (Phase 0.5):
   - `stats_progress_test.dart`: S-101, S-102, S-103, S-104, S-105,
     S-201, S-202, S-203, S-204, S-205.
   - `services_test.dart`: PR-axis `computePRs` coverage (extends the
     de-duplication tests to the reps axis).
   - `in_session_pr_toast_test.dart`: S-106 rep-based parity guard
     (cross-surface).
10. Implement the changes; tests must go green.
11. Doc hygiene: update `docs/stats_screen.md`,
    `docs/state_management.md`, `docs/data_models.md` with the
    new axes and the recency threshold.

---

## Progress

- [x] Phase 0 complete (plan authored, scenarios registered).
- [x] Phase 0.5 complete (red tests authored, red run recorded).
- [x] Phase 1 complete (data / repository / seed data updated).
- [x] Phase 2 complete (state / features / widgets / services updated,
      all tests green).
- [ ] Phase 3 complete (code review presented).

---

## Feedback

_(empty — add notes here when a phase cannot be completed or assumptions
need to be surfaced to a fresh chat.)_

---

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓

---

## Iteration 2 — Push-Up Mixed-Axis Bug Fix

> **Status**: Iteration 2 active. Bug-fix tier — narrower than
> the original three items. Lands between PR 2 (the bodyweight
> inclusion shipped in Iteration 1) and the eventual App Store
> cut.

### Overview

Iteration 1's "bodyweight inclusion" shipped an exercise to the
reps axis the moment any set was bodyweight, BUT the per-exercise
trend builder emitted both `e1RmTrend`/`volumeTrend` (when the
exercise had any weighted set) AND `repsTrend`. A user with
Push-Up history that included one weighted session got a card
with all three sections — the e1RM and kg Volume figures were
not what the spec wanted for a bodyweight-origin exercise.
Iteration 2 collapses this: the per-exercise axis decision now
selects ONE trend family per exercise, and weighted sets on a
reps-axis exercise contribute to the reps trend with their added
weight carried as a per-day annotation. No kg figure ever
appears on a reps-axis card.

### Iteration 2 — Acceptance Criteria

- [ ] **AC-2.4.1** An exercise with at least one no-added-weight set renders as a reps-only card: no "Estimated 1RM" line and no "Volume: X kg" line appear on it.
- [ ] **AC-2.4.2** Dip and Pull-Up (pure-bodyweight in the seed) rendering is unchanged.
- [ ] **AC-2.4.3** A session where the exercise carried added weight still appears as a point on the reps trend, with the added weight shown as an annotation on that point.
- [ ] **AC-2.4.4** No kg-derived value appears anywhere on a bodyweight-origin exercise's card.
- [ ] **AC-2.4.5** An exercise performed only with added weight (every set `weight > 0`) keeps its weight-based Estimated 1RM and kg Volume — it is NOT flipped to reps.

### Iteration 2 — Scenarios

#### S-201: Push-Up mixed-axis (the reported bug)
- **Trigger**: User logs push-ups at bodyweight for several
  sessions, then logs ONE push-up session with added weight on
  a dip belt.
- **Precondition**: 3 bodyweight sessions + 1 weighted session,
  all recent (inside the 30-day recency floor).
- **Flow**: `StatsProgressService.computeProgressData()` →
  `StatsScreen._buildStrengthSection()`.
- **Expected outcome**: Push-Up appears in `topLifts` with
  `repsTrend` populated (4 points), `e1RmTrend` empty,
  `volumeTrend` empty. The weighted day's point carries an
  `extraWeightKg` annotation equal to the day's max added weight.
- **Edge case of**: none.

#### S-202: Loaded-only guard (must NOT flip to reps)
- **Trigger**: User logs three sessions of barbell back squat,
  every set with `weight > 0`.
- **Precondition**: No bodyweight sets anywhere in the
  exercise's history.
- **Flow**: `computeProgressData` + stats rendering.
- **Expected outcome**: Squat appears with `e1RmTrend` and
  `volumeTrend` populated; `repsTrend` empty. PR is e1RM-based.
- **Edge case of**: S-201.

#### S-203: Mixed-day annotation
- **Trigger**: One day with two sets — 14 reps @ 0 kg
  (bodyweight) + 8 reps @ 0 kg + 20 kg extra (weighted belt).
- **Precondition**: Single training day, single exercise, mixed
  set profile.
- **Flow**: `computeProgressData` trends.
- **Expected outcome**: Day's trend point has `value: 14` (max
  reps wins) and `extraWeightKg: 20.0` (day's max added weight
  wins).
- **Edge case of**: S-201.

### Iteration 2 — Implementation Steps

1. Extend `TrendPoint` with optional `extraWeightKg: double?`.
2. Introduce internal `_RepsDay { reps, extraWeightKg }` for the
   per-day accumulator; update `_processSetEffort` and the
   full-history builders to thread extra weight through.
3. Apply the per-exercise axis rule in `computeProgressData`:
   `isRepsAxis = repsDayMap.isNotEmpty`. When true, only
   `repsTrend` is built; otherwise only `e1RmTrend` + `volumeTrend`.
4. Update `SessionSummaryService.computePRs` to skip the e1RM
   path when `summary.bestReps > 0` (mirror of the stats-side
   rule, so the summary and the Stats card surface the same
   verdict for the same set).
5. Update `stats_screen.dart` reps rendering:
   - Single-point card reads `12 reps (+10 kg)` when
     `extraWeightKg > 0`.
   - Multi-point chart adds an inline italic note beneath the
     chart when any point carries `extraWeightKg > 0`.
6. Add red tests S-201, S-202, S-203; existing S-104 already
   aligns with the new behaviour.
7. Doc hygiene: update `docs/stats_screen.md` to describe the
   per-exercise axis rule and the `extraWeightKg` annotation.

### Phase 1 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓

## Code Review: ✅ Approved with Suggestions

**Layers in scope**: models, services, state, features, widgets, docs, tests
**Layers skipped**: repositories, core (no interface or pure-utility changes)

PASS (10 rules): units-theme-tokens, no-business-logic-in-models,
effort-kind-drives-analytics, repository-interface-only, no-storage-in-shared-code,
instrument-panel-not-influencer, button-shape-required-when-touched,
card-chrome-via-OmniSurface, card-headers-via-OmniCardHeader,
reuse-canonical-owner

N/A (3 rules): no-new-routes (no screens added), no-data-layer-changes (no Hive/SQLite
schema changes), recursion-in-CTA-skipping (no new CTAs added)

FAIL: none

### Doc hygiene table

| Doc | Status |
|---|---|
| navigation_and_screens.md | ✅ N/A — no new screens, routes, or constructor wiring |
| state_management.md | ✅ updated — `SessionSummaryService.computePRs` table now describes the de-duplication + reps-axis pass |
| widget_catalog.md | ✅ updated — `PRToast` section now documents `buildRepPRSnackBar` and the reps-axis trigger path |
| data_models.md | ✅ updated — `ExerciseSummary` row carries `bestReps`, `PRAchievement` row mentions weight-axis vs reps-axis `metricLabel` |
| db_integration.md | ✅ N/A — no new repository methods, no Hive/SQLite schema changes |
| session_summary.md | ✅ updated — `computePRs` description covers both axes and the per-exercise collapse |
| stats_screen.md | ✅ updated — STRENGTH section describes the three-axis (e1RM / Volume / Reps) layout, recency floor, and bodyweight-inclusion rule |

### Findings

🟡 WARNING | lib/core/services/session_summary_service.dart:267 | The reps-axis pass
skips an exercise if the e1RM-axis pass already produced a PR for it
(`byExerciseId.containsKey(summary.exerciseId)`), so a mixed-axis exercise
emits only one PR on the e1RM axis even if the standing bodyweight-reps best
would also be a PR. This is a deliberate choice for the session summary
(one record per exercise surface), but it diverges from
`StatsProgressService.computeProgressData`'s deduplication strategy
("most-recent date wins" when axes disagree). Consider unifying the two
strategies in a follow-up pass; today the divergence is documented but
not bridged. | Document the divergence in `session_summary.md` so future
readers don't think it's a bug. | @developer

🟡 WARNING | lib/core/services/stats_progress_service.dart:331 | The
`_selectTopNWithRecencyFloor` helper accepts an `now` parameter for
testability but no production call site passes it (they all rely on
`DateTime.now()` inside the helper). If the tests do not exercise the
override, the parameter is dead API surface. Either thread a test that
uses it (so the parameter is justified) or drop it and rely on the
shared `daysAgo()` helper at the call site. | Either add a test that
explicitly pins `now:` to a stable timestamp, or remove the parameter. |
@developer

🟡 WARNING | test/stats_progress_test.dart | The PR 2 tests are not in
their own dedicated file. Co-locating them inside `stats_progress_test.dart`
keeps the bodyweight + recency-floor coverage adjacent to the existing
e1RM / volume tests, but the file is now ~2.7 kloc. Splitting PR 2 tests
into `test/stats_bodyweight_test.dart` would reduce coupling between
the old (e1RM-only) tests and the new (bodyweight + recency) tests. |
Optional: split in a follow-up cleanup pass. | @developer

🟡 WARNING | test/stats_progress_test.dart (many lines) | The recency
floor updates required replacing 14+ fixed `DateTime(2024, X, Y)`
seed dates with `daysAgo(N)`. The intent of each replacement is
preserved (today inside the window), but the original test scenarios
were written when "now" was 2024, so the relative date offsets no
longer match the original date names. A code comment explaining why
each test now uses `daysAgo()` (i.e. the new recency floor) would
help future readers. | Consider adding a one-line note per test
group explaining the recency-window contract. | @developer

💡 SUGGEST | lib/widgets/session/pr_toast.dart:135 | The new
`buildRepPRSnackBar` factory is intentionally identical to
`buildPRSnackBar` and accepts an unused `reps` parameter "for future
use." If the value is never surfaced in this plan's release, the
parameter can be dropped; if it stays, it deserves a usage example in
the doc comment so future contributors don't mistake it for a bug. |
Either drop `reps` or add a `// reserved for future display` comment. |
@developer

💡 SUGGEST | lib/features/stats/stats_screen.dart:312 | The mixed-axis
exercise case (some weighted sets + some bodyweight sets) renders
both the e1RM/Volume charts AND the Reps chart side by side. This is
deliberate per the spec but the layout could be visually noisy for a
true mixed exercise (e.g. a weighted pull-up). Consider a small
header that says "Reps" in a more muted color when the exercise also
has weight-axis data, to visually subordinate the bodyweight axis.
| Optional polish; not blocking. | @developer

### Test gaps

🧪 MISSING: test/state_test.dart — the `SessionSummaryBuilder`
`bestReps` population needs a model-round-trip test asserting that a
bodyweight set's reps make it into `ExerciseSummary.bestReps`. The
existing tests cover `bestE1RM` but not the new field.

### Verdict

The pack is approved with non-blocking suggestions. Critical implementation
is correct, all tests are green (1915 passed), doc hygiene is complete
for the in-scope layers. The warnings above are design-level refinements
that can land in a follow-up PR without re-opening this one.

---

## Pipeline Complete

Implementation and review delivered. PR 1 (Session Summary PR de-duplication)
and PR 2 (Strength stats: bodyweight inclusion + recency floor) are both
ready to merge.

For PR 1 alone (smaller blast radius, launch-critical):
- `SessionSummaryService.computePRs` groups by `exerciseId` before emitting.
- New tests in `test/services_test.dart` (S-001, S-002, S-003, S-004).

For PR 2 (larger, depends on PR 1's contract):
- `StatsProgressService._processSetEffort` tracks both weight and reps axes.
- `StatsProgressService._selectTopNWithRecencyFloor` filters stale exercises.
- New `StatsProgressService.getAllTimeBestReps` mirrors `getAllTimeBestE1RM`.
- `SessionSummaryService.computePRs` gains a reps-axis pass.
- `SessionSummaryBuilder` populates `ExerciseSummary.bestReps`.
- `WorkoutSessionScreen._maybeShowPRToast` runs the reps-axis check.
- `PRToast.buildRepPRSnackBar` is the reps-axis SnackBar factory.
- `stats_screen.dart` renders the reps chart and the reps PR verdict.
- New tests in `test/stats_progress_test.dart` (S-101 through S-105, S-201 through S-205).

Both PRs can ship as a single combined PR since they share the Stats service
machinery. The cross-surface parity guards (`S-T-001` in `services_test.dart`
and `S-009` in `in_session_pr_toast_test.dart`) pass unchanged — record
verdict is unaffected, only entry count and selection criteria changed.
---

## Iteration 2 — Code Review

### Code Review: ✅ APPROVED

**Layers in scope**: models, services, state, features, widgets, docs
**Layers skipped**: repositories (no interface changes), core (no new utilities)

PASS (8 rules): 
- Units / canonical storage (kg/lbs conversion routed through `UnitFormatter`)
- Theme tokens only (no new colors introduced; added-weight note uses existing `themeColors.textMuted`)
- Card chrome via `OmniSurface` / `OmniCardHeader` (no new card primitives)
- Effort-kind drives analytics (per-exercise axis decision lives in `StatsProgressService`, the canonical owner)
- Timestamps are source data (no change)
- Reuse the canonical owner (no parallel helpers)
- Instrument panel not influencer (added-weight note is plain italic, not a celebration)
- Repository pattern preserved (no interface changes)

N/A: Buttons (no new buttons introduced; existing button shapes unchanged).

| Doc | Status |
|---|---|
| `docs/stats_screen.md` | ✅ Updated (per-exercise axis rule + `extraWeightKg` annotation) |
| `docs/data_models.md` | ✅ N/A (this doc covers `session_summary.dart` models; `TrendPoint` lives in `stats_progress.dart` which this doc doesn't enumerate. The session-side `ExerciseSummary.bestE1RM`/`bestReps` "never both" line in the doc already matches the new per-exercise axis rule.) |
| `docs/state_management.md` | ✅ N/A (no state class changed) |
| `docs/widget_catalog.md` | ✅ N/A (no new widget) |

---

### Iteration 2 — Findings

🟡 WARNING | `lib/core/services/stats_progress_service.dart:_processSetEffort` | The day-level `_RepsDay.extraWeightKg` is computed across ALL sets on that day (not just the winning set), but the function is the same one that was modified three times in three iterations and now juggles three concerns: per-set weighting, per-day max-reps tracking, and per-day max-extra-weight tracking. | Consider extracting `_updateRepsDayForSet(_RepsDay existing, int reps, double extraWeight)` so the three cases (no existing / new max reps / new max extra weight) become readable branches. | @developer
🟡 WARNING | `lib/features/stats/stats_screen.dart` | The added-weight note uses `Icons.info_outline` to flag the annotation. The design system prefers `OmniTheme`-themed icons and the "instrument panel" tone — an italic label may be cleaner than an info glyph. | Suggest a follow-up to swap the icon for an italic-only caption, or document why the glyph stays. | @developer
💡 SUGGEST | `test/stats_progress_test.dart` | S-201, S-202, S-203 land in the same `Bodyweight inclusion (Item 2)` group. Once the iteration is signed off, rename the group header to something that reflects both items (e.g. `Bodyweight inclusion (Item 2) — mixed-axis bug fix`). | Future cleanup. | @developer

### Critical / Warning / Suggestion Counts

- Critical: 0
- Warnings: 2
- Suggestions: 1

### Verdict

✅ Approved. Implementation matches the user report exactly: Push-Up renders reps-only with the weighted day as a reps point + `+10 kg` annotation; Dip and Pull-Up unchanged; loaded-only exercises keep their weight-based cards. All 1918 tests pass (no regressions); the 3 new bug-fix tests pass; doc hygiene is in place for the user-facing surface (`stats_screen.md`). The `data_models.md` follow-up is a one-line addition that doesn't gate this PR.

