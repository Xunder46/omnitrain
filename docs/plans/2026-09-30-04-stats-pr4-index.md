# Stats PR 4 series — The new Stats structure (index)

> Status (2026-09-30): **4a** is READY, with its full plan written. **4b** and **4c** are not planned yet;
> plan each when its turn comes, against the code as it is then (`.github/agents/pr_scope_budget.md`).
>
> Source: `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` items 5 and 6, and the
> pack's Suggested Batching row "PR 4 = items 5 + 6". The owner delegated the split to the planner.
> Implementer: Copilot with DeepSeek V4.1 Flash, running locally in this checkout. Plans are written for a
> small model: numbered one-concern steps, exact strings, commands and greps, and rules inline.
> Next handoff: Copilot implements 4a, then `/code-reviewer`.
> Evidence for 4a: `2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.evidence.md`.

## Why three PRs

Items 5 and 6 together are one PR in the pack's batching table, but they are over the scope budget
(`.github/agents/pr_scope_budget.md`): the combined estimate is about 2,500 production lines across 7
phases, against hard limits of 1,500 lines and 5 phases. So the series is split, and the split is ordered
so that `develop` stays shippable after every PR.

## Branch policy (owner)

- Only `develop` and `main` persist.
- All work happens directly on `develop`. Plans must never create, switch or delete branches.
- Executors never commit, stage, merge or push; the owner does.

## PRs in order

| PR | Scope | Depends on | Plan |
|---|---|---|---|
| **4a** | Phone, **additive**: the shared exercise-metric layer, the **Exercise Progress** view, and the **Records & Trends** screen with the Stats header's chart-icon entry point.<br>• a bulk round-instance read on the repository (there is none today);<br>• the per-exercise native value and all-time best for all four effort kinds, computed once and reused;<br>• Records & Trends: all-time totals, the existing Recent PRs moved unchanged, and a searchable list of every exercise ever logged, grouped into the four sections, each showing its all-time best and when it was last trained;<br>• Exercise Progress: the full-history chart, the all-time best, and the recent-sessions list;<br>• nothing is removed — the old Stats sections stay exactly as they are. | — | `2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.md` |
| **4b** | Phone, **additive**: the **Instruments list** and the **Fuel row** on the main Stats screen.<br>• the four sections ordered by share of training, exercises ordered by training-day share, up to 5 rows with "Show all (n)";<br>• each row: name, native value, change against that exercise's own previous comparable value, a trend line;<br>• cadence and average heart rate, the first readers of `SensorSummary`, plus a bulk sensor read;<br>• the Fuel row: 7-day averages against the user's own target, logged-days indicator, training-day vs rest-day split, hidden after 14 days without logs, tapping through to the existing nutrition trend.<br>The old Stats sections stay for one more PR. | 4a | not planned |
| **4c** | Phone, **removal**: delete the STRENGTH, CARDIO, ISOMETRIC, SPORTS and NUTRITION sections from the Stats screen, retire the top-N selection constants and the code only they used, update or retire their tests, and prove the old layout is unreachable from anywhere in the app.<br>Also rewrites `docs/stats_screen.md` to describe the screen that is left. | 4b | not planned |

## Shared decisions (defined once in the plans named; later PRs cite them and never restate them)

- **4a D-401: the split.** Items 5 and 6 ship as 4a → 4b → 4c. 4a and 4b add; only 4c removes.
- **4a D-402: single release.** Inherits 3b D-332. No user data exists, so no migration, no old-data
  handling, no backward compatibility and no feature flag anywhere in this series.
- **4a D-403: one section per exercise.** Resistance / Cardio / Isometric / Sports, assigned by the effort
  kind the exercise was actually logged under (pack D-3, D-15), never by the session's modality label.
  4a evaluates this over all history; 4b over the current window.
- **4a D-405 … D-408: the native value per effort kind** — Resistance, Cardio, Isometric, Sports. These
  are the values the Instruments rows (4b), Records & Trends (4a) and Exercise Progress (4a) all show.
- **4a D-409: an all-time best is descriptive.** It creates no PR event, no toast and no Summary row.
  The PR path is untouched by this series, so the PR parity tests stay as they are.
- **4a D-413: the header entry point.** An `OmniBackHeader` action with an accessible label, routed with
  `OmniNavigator` (`docs/navigation_contract.md`).
- **4a D-416: `docs/stats_screen.md` is reconciled in 4a**, because the pack's D-13 requires it and 4a
  already touches that doc. 4c rewrites it again for the screen that is left.

## Series risks

- **Temporary duplicate content on `develop`.** Until 4c lands, Recent PRs and the nutrition trend appear
  on both the Stats screen and Records & Trends. This is expected, not a defect.
- **Two rounds of doc churn on `docs/stats_screen.md`** (4a and 4c). Accepted: the pack's D-13 requires
  the drift fixed, and 4a is the PR that makes the doc's "what Stats shows" claim wrong in a new way.
- **The old SPORTS chart reads timed instances, the new Sports value reads round instances.** They can
  disagree for the same session until 4c removes the old chart. See 4a Notes.
- **Small-model implementer.** Every plan must keep its rules inline and its steps mechanical.
- **The analyzer bar is "none new":** 199 issues with 0 errors on the tree 4a starts from.

## Scope check (2026-09-30)

**4a** is 651 lines with 3 phases (Phase 1 is the @dba repository read; Phases 2 and 3 are @developer), one
track (the phone), 16 decisions, 16 scenarios, and about 1,000 predicted production lines. That is one soft
signal — length over 500 — and no hard limit, so it is within budget
(`.github/agents/pr_scope_budget.md` §1). **4b** and **4c** were not estimated in detail; 4b carries a
second repository addition, and 4c's churn is mostly test deletions in `test/screen_widget_test.dart`, so
both are expected to fit.
