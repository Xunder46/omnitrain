# Personal-Record Surface Verification — June 27, 2026

> **Scope:** Read-only verification. No source, repository, or test code was
> modified for this report. No definition was changed. Per the brief, choosing
> the personal-record (PR) definition is a product call, not a cleanup task.

## Question

> Do the three places the app shows personal records — the in-workout
> celebration, the Stats screen, and the post-workout Session Summary — all
> use the same record definition?

## Short answer

**No.** The in-workout toast and the Stats screen agree on one definition
(Epley estimated 1RM, strict `>`, completed sessions only, `set`-kind efforts
only). The post-workout Session Summary uses a **different metric** — raw
weight, not Epley e1RM — under an otherwise structurally identical rule. This
divergence is real, observable from the code, and surfaces in normal use.

## Per-surface summary

| Surface | Metric | Standing-best source | Comparison | First-ever is a PR? | Source |
|---|---|---|---|---|---|
| **In-workout toast** | Epley e1RM = `w × (1 + r/30)` | `StatsProgressService.getAllTimeBestE1RM(exerciseId)` (all completed sessions, `set`-kind only) | Strict `>` (and `>` vs the session's running best as a per-session throttle) | Yes — any positive e1RM > the returned `0.0` | [`workout_session_screen.dart:847-880`](../../lib/features/session/workout_session_screen.dart#L847) |
| **Stats screen — Recent PRs card** | Epley e1RM = `w × (1 + r/30)` | Walks the per-day max e1RM trend of the top-lift exercises over all completed sessions; first PR per exercise is the first day the e1RM exceeds the running best | Strict `>` | Yes — the first day with positive e1RM is its own PR | [`stats_progress_service.dart:130-170`](../../lib/core/services/stats_progress_service.dart#L130) |
| **Session Summary — inline PR rows** | **Raw weight** (not e1RM) | `WorkoutRepository.getPersonalRecordCandidates(exerciseId, metricId: MetricIds.weight)` over all completed sessions, `set`-kind only | Strict `>` | Yes — `previousBest == null` counts as PR | [`session_summary_service.dart:185-210`](../../lib/core/services/session_summary_service.dart#L185) |

The first two rows share `StatsProgressService.epley1RM(...)` and
`StatsProgressService.getAllTimeBestE1RM(...)` as a single source of truth
(pinned by plan D-1 / D-2 / D-3 in
`.github/agents/plans/in-session-pr-toast-plan.md` and the structural-guard
test S-009). The Session Summary does not call either helper.

## Exactly how the Session Summary diverges

1. **Metric is raw weight, not Epley e1RM.**
   - Session Summary reads `summary.bestWeight` (the largest raw weight the
     user logged in the session, regardless of reps) and queries the
     repository's `MetricIds.weight` observation pool.
   - In-workout toast and Stats screen compute `epley1RM(weight, reps) = weight × (1 + reps / 30)` for every set, and compare those e1RM numbers.
2. **The standing-best query is a different helper.**
   - In-workout / Stats: `StatsProgressService.getAllTimeBestE1RM(exerciseId)`.
   - Session Summary: `WorkoutRepository.getPersonalRecordCandidates(exerciseId, metricId: MetricIds.weight)`.
3. **Both surfaces use strict `>` (a tie is not a PR on either), and both
   restrict to completed sessions with `effortKind == 'set'`** — so the
   structural shape matches; only the metric being compared differs.

### Worked example showing the divergence

Take a user whose all-time best on an exercise is the set `100 kg × 5 reps`
(stored as `MetricIds.weight = 100.0`, `reps = 5`).

- All-time Epley best: `100 × (1 + 5/30) = 116.67`.
- All-time raw-weight best: `100.0`.

**Case A — heavier single, fewer reps.** New set: `110 kg × 1 rep`.
- In-workout toast: `110 × (1 + 1/30) = 113.67`. `113.67 > 116.67` is **false** → **no toast**, **no Stats-screen PR**.
- Session Summary: `110.0 > 100.0` is **true** → **inline PR row appears** ("Weight: 100.0 → 110.0").

**Case B — lighter working set, more reps.** New set: `95 kg × 5 reps`.
- In-workout toast: `95 × (1 + 5/30) = 110.83`. `110.83 > 116.67` is **false** → **no toast**, **no Stats-screen PR**.
- Session Summary: `95.0 > 100.0` is **false** → **no inline PR row**.

**Case C — heavier working set, fewer reps, lower e1RM.** New set: `108 kg × 3 reps`.
- In-workout toast: `108 × (1 + 3/30) = 118.80`. `118.80 > 116.67` is **true` → **toast fires**, **Stats-screen PR recorded**.
- Session Summary: `108.0 > 100.0` is **true` → **inline PR row appears**.

Cases A and C are where the surfaces disagree on whether the same logged set
counts as a PR. Case A is the common "heavy single off a working-set best"
case — the user gets a Session Summary PR but no in-session celebration or
Stats-screen entry. Case C, both surfaces agree.

### Why the divergence is hard to notice from the UI

The Session Summary's inline PR rows live **inside the modality group cards**
(Strength / Cardio / Sports / Isometric). They are small and easy to miss
versus the modal-grade in-workout toast and the explicit Recent PRs card on
Stats. A user who doesn't open the Session Summary after every workout can go
months without ever seeing a Session-Summary-only PR. When they do open it,
the row reads "Weight: 100 → 110" — which reads naturally and rarely invites
the question "why didn't the in-workout toast fire?".

## What is NOT in scope for this report

- Changing the Session Summary metric to Epley e1RM (or vice-versa for the
  other surfaces).
- Changing the comparison operator.
- Changing which session states contribute to the standing best (all three
  surfaces already agree on "completed sessions only").
- Changing which effort kinds count (`set`-kind only on all three).
- Changing the first-ever-is-a-PR rule.
- Changing when the in-workout toast fires.

Any of the above is a product call — they change what users see and when
they see it, which is exactly what this cleanup pass was instructed to leave
alone.

## Recommendation for owner decision

Owner has three coherent choices, each with a non-trivial UX implication:

1. **Adopt Epley e1RM everywhere.** Update `SessionSummaryService.computePRs`
   to call `StatsProgressService.epley1RM(...)` and `getAllTimeBestE1RM(...)`
   (or an equivalent raw-observation Epley walker), so all three surfaces
   share the helper. S-009 becomes the structural guard for all three.
2. **Adopt raw weight everywhere.** Replace the in-workout toast and the
   Stats-screen PR detection with raw-weight comparisons. Loses the
   reps-aware signal — a `100 kg × 1` and a `100 kg × 10` would count the
   same on both surfaces.
3. **Keep the divergence, document it.** The Session Summary would explicitly
   read as "Heaviest single weight lifted today" rather than "New e1RM PR".
   The metric label on `PRAchievement.metricLabel` is already `'Weight'`
   today, so the surface is at least labeled honestly; the user just needs
   to know that this is a different definition from the in-workout toast
   and Stats screen.

Each option is one PR-size change. None were attempted here per the brief's
"do NOT change it" clause.

## Source pointers

- In-workout toast: [`workout_session_screen.dart:823-883`](../../lib/features/session/workout_session_screen.dart#L823) — `_maybeShowPRToast`.
- Toast widget contract: [`pr_toast.dart`](../../lib/widgets/session/pr_toast.dart) and [widget catalog entry](../agents/docs/widget_catalog.md).
- Stats screen PR detection: [`stats_progress_service.dart:130-170`](../../lib/core/services/stats_progress_service.dart#L130) — the `for (final point in e1RmTrend)` walk.
- Epley formula and standing-best helper: [`stats_progress_service.dart:418-475`](../../lib/core/services/stats_progress_service.dart#L418).
- Session Summary PR computation: [`session_summary_service.dart:185-210`](../../lib/core/services/session_summary_service.dart#L185) — `computePRs`.
- `PRAchievement` model: [`session_summary.dart:87-105`](../../lib/core/models/session_summary.dart#L87).
- Repository helper used by Session Summary: [`workout_repository.dart:25`](../../lib/data/repositories/workout_repository.dart#L25) (`getPersonalRecordCandidates`), implementations in [mock](../../lib/data/repositories/mock_workout_repository.dart#L293) and [Hive](../../lib/data/repositories/hive_workout_repository.dart#L774).
- `MetricIds.weight`: [`metric_ids.dart:6`](../../lib/core/constants/metric_ids.dart#L6) — the metric id the Session Summary uses; the in-workout / Stats path does not use `MetricIds` at all because it derives e1RM from the set tuple directly.

Last Updated: June 27, 2026