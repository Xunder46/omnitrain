# Feature: Session Summary PR Parity (use same PR definition as toast and Stats)

> **Status**: Iteration 1 active.

---

## Overview

The in-workout "Congrats! New PR" toast and the Stats screen both judge personal records with Epley estimated 1-rep-max (`weight × (1 + reps / 30)`), via `StatsProgressService.epley1RM` and `StatsProgressService.getAllTimeBestE1RM`. The post-workout Session Summary instead uses the raw top weight: `SessionSummaryService.computePRs` queries `getPersonalRecordCandidates(metricId: MetricIds.weight)` and compares against `summary.bestWeight`. The same set can therefore trigger the mid-workout PR celebration and then **not** appear as a record in the summary a moment later — or vice versa. This change makes the summary's PR definition equal to the other two surfaces so all three always agree on the same set. The toast and Stats surfaces and the persistence layer are unchanged.

---

## Resolved Decisions (Ledger)

| # | Decision | Contract |
|---|----------|----------|
| **D-1** | **PR definition** in the Session Summary is the Epley 1-rep-max estimate, `weight × (1 + reps / 30)`, **identical** to the formula used by the toast and the Stats screen. Single source of truth: `StatsProgressService.epley1RM`. | Both Stats and the toast already share `epley1RM`. The summary now also calls it (no parallel helper is created). |
| **D-2** | **New best** for a session is the maximum `epley1RM(weight, reps)` across that session's `set`-kind entries — **not** the maximum `weight`. A rep-driven improvement (more reps at a weight below the previous heaviest) can be the new best when its e1RM exceeds all earlier sets' e1RM in that session. | Computed in `SessionSummaryBuilder.buildSessionSummary` alongside `bestWeight`, exposed via a new `ExerciseSummary.bestE1RM` (nullable double). |
| **D-3** | **Previous best** is the maximum `epley1RM` across **all completed sessions for this exercise, excluding the current session**. The current session is excluded so the just-finished workout's own PR cannot compare against itself. | `StatsProgressService.getAllTimeBestE1RM` gains an optional `excludeSessionId` parameter that drops one session from the walk. The existing zero-arg call (used by the in-session toast) is unchanged. |
| **D-4** | **Strict comparison** — a set is a PR in the summary iff `summary.bestE1RM > previousBest`, matching the strict `>` already used by the toast and Stats. First-ever (no prior history) is a PR because `bestE1RM > 0.0`. | Mirrors D-3 in `.github/agents/plans/in-session-pr-toast-plan.md`. |
| **D-5** | **Effort-kind filter** — `computePRs` continues to short-circuit on `effortKind != 'set'`. Cardio / timed / round / drill efforts never trigger a PR in the summary, same as today. | Matches Stats' Effort-Type Keying rule and the toast's D-5. |
| **D-6** | **No change to the in-workout celebration** (`WorkoutSessionScreen._maybeShowPRToast`, `widgets/session/pr_toast.dart`). | Out of scope per the prompt. |
| **D-7** | **No change to the Stats screen's PR detection** (`StatsProgressService.computeProgressData`'s PR loop, the `RecentPR` card, the e1RM trend). | Out of scope per the prompt. |
| **D-8** | **No change to record storage** — no new Hive boxes, no new SQLite columns, no `PR` row, no event log. The summary derives its PR signal from the same `EffortObservation` rows the toast and Stats already use. | The prompt's "do not change how records are stored, and do not add any new record type or UI" rule. |
| **D-9** | **No visual change** — the summary continues to render `${pr.exerciseName}: New best ${formatted} (was ${formatted})` in each group's PR list. `unitLabel` of values is still the user's preferred weight unit (`kg` / `lbs`); e1RM values formatted through the same path read naturally as weight numbers. | "Out of scope: … visual redesign." |
| **D-10** | **No new repository methods**, no new entry points on `WorkoutRepository`. `computePRs` reuses `StatsProgressService` over the same repository injected at startup. | Preserves dual-environment parity (Hive ↔ SQLite) and the "reuse the canonical owner" rule in `docs/global_conventions.md`. |

---

## Feature Invariants

1. **The toast, Stats, and Session Summary use the same PR definition for the same set.** Any change to `StatsProgressService.epley1RM` is reflected in all three automatically. The cross-surface parity test (S-T-001 below) is the guard.
2. **A PR is only ever strength (effortKind == 'set') effort in any of the three surfaces.** Non-strength efforts never produce a PR signal anywhere.
3. **First-ever performance of an exercise is a PR in all three surfaces**, because `getAllTimeBestE1RM` returns `0.0` with no history, and the strict `>` comparison fires on any positive e1RM.
4. **The `ExerciseSummary.bestE1RM` field is populated only for `effortKind == 'set'` efforts**; it is `null` for cardio / round / drill / other.

---

## Requirements

| # | Requirement | Source |
|---|-------------|--------|
| R-1 | `SessionSummaryService.computePRs` judges a PR the same way `StatsProgressService.getAllTimeBestE1RM` does — using the Epley e1RM formula, not raw top weight. | AC-1, AC-2 |
| R-2 | A rep-driven improvement (more reps at a non-top weight) registers as a PR in the summary where previously it did not. | AC-2 |
| R-3 | A first-ever set for an exercise registers as a PR in the summary, consistent with toast and Stats. | AC-3 |
| R-4 | The in-workout celebration and the Stats screen behave identically before and after this change. | AC-4 |
| R-5 | No change to persistence, no new repository methods, no new UI surfaces. | global_conventions + prompt |

---

## Acceptance Criteria (each maps to ≥1 scenario)

- [ ] **AC-1** A set that triggers the in-workout PR celebration also appears as a PR in that workout's post-workout summary; likewise a summary PR must correspond to a moment where the toast would have fired. *(S-T-001 cross-surface parity)*
- [ ] **AC-2** A rep-PR (more reps at a weight below the all-time top weight, yielding a higher estimated 1RM) is recognised as a PR in the summary where previously it was not. *(S-T-003)*
- [ ] **AC-3** First-ever performance of an exercise is a PR in the summary, just as it is in toast and Stats. *(S-T-002 + first-ever pre-existing test, now re-pointed)*
- [ ] **AC-4** No change to the in-workout celebration or Stats screen behavior. *(structural-guard S-009 in `in_session_pr_toast_test.dart` continues to pass unchanged)*
- [ ] **AC-5** `SessionSummaryExerciseSummary.bestE1RM` is populated by the builder. The existing `bestWeight` field is unchanged and continues to drive the volume stats. *(model round-trip + builder smoke)*
- [ ] **AC-6** `getAllTimeBestE1RM` works with and without the new optional `excludeSessionId` parameter; the no-arg path used by the toast is identical. *(no-regression test)*
- [ ] **AC-7** The summary's PR display continues to render inside each group card, formatted as `${name}: New best X kg/lbs (was Y kg/lbs)` — the unit label is the user's preferred weight unit. *(existing UI rendering preserved, no screenshot regression)*

---

## Scenarios

Stable IDs. Test code references these.

### S-T-001: Cross-surface parity — same set, all three surfaces agree

- **Trigger**: One exercise has one prior completed session (s-old) with `reps=5, weight=60` (e1RM `70.0`). The user logs a new `reps=5, weight=70` set in the active session (s-new). Then they finish the session.
- **Precondition**: Repository has `s-old` (ended) plus the now-finished `s-new`. MockWorkoutRepository.
- **Flow**:
  - **Surface A (toast)**: `StatsProgressService.getAllTimeBestE1RM(exA.id)` walks completed sessions. With `s-new` excluded (the active session was in-progress at the moment the toast fired), returns `70.0`. Just-logged e1RM = `81.67`. `81.67 > 70.0` → toast fires.
  - **Surface B (Stats)**: `computeProgressData` walks per-day e1RM and detects the day-2 point (`81.67`) exceeds the standing `70.0`. `recentPRs` contains the entry.
  - **Surface C (summary)**: `computePRs` walks the current session (`s-new`'s efforts), computes `bestE1RM = 81.67`, then queries `getAllTimeBestE1RM(exA.id, excludeSessionId: s-new.id)` → `70.0`. `81.67 > 70.0` → PR recorded.
- **Expected outcome**: All three surfaces record exactly one PR for this set. The summary's `PRAchievement` list contains the entry for `exA`.
- **Edge case of**: none.

### S-T-002: First-ever performance is a PR in the summary

- **Trigger**: User logs `reps=5, weight=60` on a never-before-trained exercise, then finishes.
- **Precondition**: Repo has no completed sessions for this exercise.
- **Flow**: `bestE1RM = 70.0`; `getAllTimeBestE1RM(exA.id, excludeSessionId: …)` = `0.0`. `70.0 > 0.0` → PR.
- **Expected outcome**: The summary records a PR. The summary's `previousBest` field reads `0` (first-ever).
- **Edge case of**: S-T-001.

### S-T-003: Rep-driven PR — same top weight, more reps

- **Trigger**: Repo has `s-old` with `reps=1, weight=100` for `exA` (e1RM `~103.33`). The user logs `reps=10, weight=80` (e1RM `~106.67`). Top weight in `s-old` was `100`; new top weight is `80` (lower); new e1RM is higher.
- **Precondition**: Old summary would have **not** recorded a PR (because `80 < 100` is the old definition's comparison). New summary must record one.
- **Flow**: `bestE1RM = 106.67`. `getAllTimeBestE1RM(exA.id, excludeSessionId: …)` = `103.33`. `106.67 > 103.33` → PR.
- **Expected outcome**: PR recorded in the summary. Under the old definition (raw weight) no PR would have been recorded; the regression coverage in this scenario protects against re-introducing that behavior.
- **Edge case of**: S-T-001.

### S-T-004: Non-strength effort never produces a PR in the summary

- **Trigger**: User finishes a cardio / timed / round / drill session (no set efforts, no history).
- **Flow**: `computePRs` short-circuits on `effortKind != 'set'`.
- **Expected outcome**: `prs` is empty for that exercise.
- **Edge case of**: S-T-002.

### S-T-005: A set equal to the historical best (e1RM-wise) is NOT a PR

- **Trigger**: Repo has `s-old` with `reps=5, weight=60` (e1RM `70.0`). User logs `reps=5, weight=60` (e1RM exactly `70.0`). Strict `>` fails.
- **Flow**: `70.0 > 70.0` is `false` → no PR.
- **Expected outcome**: `prs` is empty for `exA`.
- **Edge case of**: S-T-001.

### S-T-006: A set below the historical best (e1RM-wise) is NOT a PR

- **Trigger**: Repo has `s-old` with `reps=5, weight=60` (e1RM `70.0`). User logs `reps=3, weight=50` (e1RM `55.0`). Strict `>` fails.
- **Flow**: `55.0 > 70.0` is `false` → no PR.
- **Expected outcome**: `prs` is empty for `exA`.
- **Edge case of**: S-T-001.

### S-T-007: `getAllTimeBestE1RM` zero-arg path is unchanged

- **Trigger**: A different call site (the toast) calls `getAllTimeBestE1RM(exA.id)` with no exclusion.
- **Flow**: Same walking semantics as before — completed sessions only, set-kind efforts only, e1RM max.
- **Expected outcome**: Returns `105.0` for `reps=5, weight=90` in an in-progress session excluded by default; returns the e1RM of the completed-session-best when there is one. Identical to pre-change behavior.
- **Edge case of**: S-T-001.

### S-T-008: `getAllTimeBestE1RM(exA.id, excludeSessionId: s)` excludes the named session only

- **Trigger**: Repo has `s-1` (e1RM `70.0`) and `s-2` (e1RM `93.33`) for the same exercise. Call with `excludeSessionId: s-2.id`.
- **Flow**: Walk skips `s-2`. Returns `70.0` (max of just `s-1`).
- **Expected outcome**: `70.0`, not `93.33`.
- **Edge case of**: S-T-007.

---

## Iteration 1

### DB Changes
None — no schema, no migration, no seed change. Existing observations are the source data.

### Backend Changes

1. **Add `bestE1RM` field to `ExerciseSummary`** ([lib/core/models/session_summary.dart](lib/core/models/session_summary.dart)). Nullable `double?`, default `null`. Populated only for `effortKind == 'set'`; null for cardio / round / drill. No `fromMap` / `toMap` (model is pure-Dart, not persisted — see `docs/data_models.md` note on summary model classes).
2. **Compute `bestE1RM` in `SessionSummaryBuilder`** ([lib/state/workout/session_summary_builder.dart](lib/state/workout/session_summary_builder.dart), inside `buildSessionSummary`, immediately after the existing `bestWeight` loop). For each entry where `reps > 0 && weight > 0`, compute `StatsProgressService.epley1RM(weight, reps)` and keep the max. Default to `null`. Pass to the `ExerciseSummary` constructor.
3. **Add `excludeSessionId` parameter to `StatsProgressService.getAllTimeBestE1RM`** ([lib/core/services/stats_progress_service.dart](lib/core/services/stats_progress_service.dart)). Default `null`; when non-null, skip the session whose `id == excludeSessionId` while walking. Zero-arg call site (the in-session toast) continues to work unchanged. This is the cleanest expression of "standing best BEFORE this session's contribution".
4. **Rewrite `SessionSummaryService.computePRs`** ([lib/core/services/session_summary_service.dart](lib/core/services/session_summary_service.dart)) to use the new `bestE1RM` field and the new `getAllTimeBestE1RM(exerciseId, excludeSessionId: …)` path. For each `set`-kind `ExerciseSummary`:
   - Take `summary.bestE1RM`. If `null` or `≤ 0` → skip.
   - Query `_repository`-backed `StatsProgressService.getAllTimeBestE1RM(exerciseId, excludeSessionId: currentSessionId)`. We need `currentSessionId`. **Two cleanest options** (chosen: option A):
     - **(A)** Pass the current session id into `computePRs`. Slightly enlarges the method signature but keeps the call site (`session_summary_screen.dart`) honest about what the comparison means. Add an optional `currentSessionId` parameter (default `null` to preserve the existing unit-test signature).
     - **(B)** Filter out the current session inside `computePRs` by walking the repository. Re-implements the walk; not preferred.
   - Construct `PRAchievement(exerciseName, 'e1RM', previousBest, newBest = summary.bestE1RM)` when `newBest > previousBest` (strict).
5. **Update `session_summary_screen.dart`** `computePRs(...)` call to pass the current session id. One-line change; pure plumbing.

### Frontend Changes

6. **Update all `ExerciseSummary(` callers** in `test/`:
   - `test/services_test.dart` — 9 call sites. Add `bestE1RM: null` (or the appropriate per-test value if any future tests want to assert behavior). Existing tests must be re-pointed at the **e1RM** definition; the previous "set `bestWeight: 80.0` and expect `newBest == 80.0`" assertions no longer match the new behavior. Updated assertions use the e1RM values that follow from the seeded `reps` / `weight`.
   - The matching unit tests in `test/in_session_pr_toast_test.dart` (S-009 structural guard, `getAllTimeBestE1RM` tests) **do not change** — they go through the canonical helper directly, not through `ExerciseSummary`.

### Implementation Steps

1. Add the `bestE1RM` field to `ExerciseSummary` with default `null`.
2. Update `SessionSummaryBuilder` to populate it (one extra loop, ~8 lines).
3. Add `excludeSessionId` to `StatsProgressService.getAllTimeBestE1RM`.
4. Rewrite `SessionSummaryService.computePRs` (signature: `(exercises, {String? currentSessionId})`, body: `epley1RM`-driven, falls back to no exclusion when `currentSessionId == null` for test compatibility).
5. Update the call site in `session_summary_screen.dart` to pass `currentSession.id`.
6. Update `test/services_test.dart` `computePRs` group:
   - "detects a new PR when no previous best exists" → use e1RM values
   - "detects a new PR when exceeding previous best" → use e1RM values (s-old e1RM 70.0, current set 70 kg × 5 → e1RM 81.67)
   - "no PR when bestWeight equals previous best" → ensure the equal-e1RM case is asserted (existing test was based on equal-weight; rework to equal-e1RM or seed equal-e1RM data)
   - "skips non-set effort kinds" → unchanged in shape; new field `bestE1RM: null` is fine
   - "skips exercises with null or zero bestWeight" → rework to `bestE1RM: null` (or `bestE1RM: 0.0`) and assert the new short-circuit
7. Add the **new** tests to `test/services_test.dart`:
   - **S-T-001 cross-surface parity**: same seed → `computePRs` records a PR matching toast + Stats.
   - **S-T-002 first-ever is a PR**: `bestE1RM: 70.0`, no prior history → one PR entry.
   - **S-T-003 rep-PR**: historical `100×1` (e1RM 103.33) and current `80×10` (e1RM 106.67) → PR recorded (would NOT be under old definition).
   - **S-T-004 non-strength**: cardio effort with `bestE1RM: null` → no PR.
   - **S-T-005 equal e1RM best**: current set's e1RM equals historical e1RM → no PR.
   - **S-T-006 lower e1RM**: current set's e1RM < historical e1RM → no PR.
   - **S-T-007 zero-arg `getAllTimeBestE1RM`** path unchanged: in-progress session excluded; completed-session max returned. (This may already be covered by `in_session_pr_toast_test.dart`'s S-009; add a minimal test in `services_test.dart` next to the new `excludeSessionId` tests for visibility.)
   - **S-T-008 `excludeSessionId`** parameter: two completed sessions, exclude `s-2`, returns max of `s-1` only.
8. Run the full test suite.
   - `flutter analyze` (must pass)
   - `flutter test test/services_test.dart` (computePRs + new scenarios)
   - `flutter test test/in_session_pr_toast_test.dart` (S-009 parity guard unchanged)
   - `flutter test test/screen_widget_test.dart` (no UI regression in summary)
   - `flutter test test/interaction_flow_test.dart` (no log-flow regression)
   - `flutter test test/stats_progress_test.dart` (Stats PR detection unchanged)

### Predicted Files

- [lib/core/models/session_summary.dart](lib/core/models/session_summary.dart) — `ExerciseSummary.bestE1RM` added.
- [lib/state/workout/session_summary_builder.dart](lib/state/workout/session_summary_builder.dart) — populate `bestE1RM` alongside `bestWeight`.
- [lib/core/services/stats_progress_service.dart](lib/core/services/stats_progress_service.dart) — `getAllTimeBestE1RM` gains `excludeSessionId`.
- [lib/core/services/session_summary_service.dart](lib/core/services/session_summary_service.dart) — `computePRs` uses e1RM, gains optional `currentSessionId`.
- [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart) — call site pass the current session id.
- [test/services_test.dart](test/services_test.dart) — repoint 5 existing `computePRs` tests + add 8 new scenarios.

### Doc Hygiene

- [docs/data_models.md](docs/data_models.md) — note `ExerciseSummary.bestE1RM` field.
- [docs/session_summary.md](docs/session_summary.md) — note `computePRs` now uses Epley e1RM and is consistent with `StatsProgressService.epley1RM`.
- [docs/stats_screen.md](docs/stats_screen.md) — extend the "Source of truth" section to include **3 surfaces** (toast + Stats + session summary) instead of 2, with the same single source of truth anchor.
- [docs/global_conventions.md](docs/global_conventions.md) — no rule changes needed.

---

## Progress

- [x] Phase 0: Plan
- [x] Phase 1: Data layer (`ExerciseSummary.bestE1RM`, `getAllTimeBestE1RM(excludeSessionId: …)`)
- [x] Phase 2: TDD — write new red tests + repoint existing tests
- [x] Phase 2: Implementation — repoint `computePRs` + builder
- [x] Phase 2: Verify green + docs updated (`docs/session_summary.md`, `docs/data_models.md`, `docs/stats_screen.md`)
- [x] Phase 3: Code review

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

