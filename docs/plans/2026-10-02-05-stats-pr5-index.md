# Stats PR 5 — the Mix layer (training load by modality): PR series index

> **Status:** DONE (2026-10-03) — 5a committed at `9d5dca2`, 5b committed at `e993751`. The fixes
> carried out of their reviews are listed under *Review follow-ups* below; the ones that needed
> their own change are 5c, `docs/plans/2026-10-03-05c-stats-pr5c-housekeeping-plan/2026-10-03-05c-stats-pr5c-housekeeping-plan.md`.
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 7, plus the owner decisions of 2026-10-02 in `.work/stats-pr5/brief-plan.md`.
> **Base:** `develop`, Stats PR 4 series DONE (`docs/plans/2026-09-30-04-stats-pr4-index.md`). Effort rating (PR 1) is in: `TrainingSession.sessionFeeling` is the stored 1–5 rating.
> **Binding conventions:** `docs/global_conventions.md`, plus the `docs/README.md` entries the individual plans list. Budget: `.github/agents/pr_scope_budget.md`.

## Why this is a series

A single plan for PR 5 would carry >3 phases, >20 ledger decisions and >30 scenarios — three soft
budget signals at once. The natural seam is **data before presentation**: the load, attribution,
baseline and strip arithmetic is a shared definition later signals (pack items 8, 10–15) import,
and it ships green and invisible on its own; the layer the user sees is a screen change with its
own test re-stabilisation. Each half is well under the hard limits.

## Scope check (the series)

| Measure | 5a | 5b | Soft | Hard |
|---|---|---|---|---|
| Plan lines | 333 | 307 | 500 | 800 |
| Phases | 2 | 2 | >3 | >5 |
| Tracks | 1 | 1 | >1 | — |
| Ledger decisions | 21 (D-901…D-919, D-934, D-935) | 16 (D-920…D-933, D-936, D-937) | >20 | — |
| Scenarios | 17 (S-1501…S-1517) | 16 (S-1601…S-1616) | >30 | — |
| Predicted production lines | ~330 | ~260 | — | ~1,500 |

Line counts are the planner's measurements, read back from each file; each plan's Progress table
carries the executor's re-measurement.

## The PRs, in order

| # | Plan | One-line scope | Depends on | Owning agent | Status |
|---|---|---|---|---|---|
| 5a | `docs/plans/2026-10-02-05a-stats-pr5a-mix-data-plan/2026-10-02-05a-stats-pr5a-mix-data-plan.md` | Session load, the effort→modality rule, the per-session time split and its dominant-modality fallback, rolling handling, the load baseline, the percentage rounding, the 8-week strip and the week-start helper — as value types and one service call. No visible change. | — | @dba | DONE — `9d5dca2` |
| 5b | `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/2026-10-02-05b-stats-pr5b-mix-screen-plan.md` | The Mix layer on the Stats screen: header with the window chip, measure label, split bar with the usual-split bar beneath it, the baseline note, the unrated count and the 8-week modality-stacked strip; the screen edit; the existing widget tests re-stabilised; the docs for what the user sees. | 5a DONE | @developer | DONE — `e993751` |
| 5c | `docs/plans/2026-10-03-05c-stats-pr5c-housekeeping-plan/2026-10-03-05c-stats-pr5c-housekeeping-plan.md` | Housekeeping carried out of the 5a and 5b reviews: the stale inbox `applied_at_ms` contract comment, the duplicated stamp-clear folded into `WatchInboxEntry.unapplied()`, the three Mix-layer texts capped to one line, two doc sentences corrected, and this index refreshed. | 5b DONE | @developer | PLANNED |

Both are one release: 5a alone changes nothing a user can see, so there is no intermediate state to
ship. 5b's Phase 1 is the first point at which anything is visible.

## Shared decisions (the ones both plans depend on)

- **D-901…D-919, D-934, D-935 live in 5a** and are the only definition of load, attribution, the
  baseline and the strip. 5b renders that payload and does no arithmetic of its own beyond the
  presentation the layer owns — the flex that turns a measure into a share of the bar, and the
  tallest week that sets one scale for all eight strip columns. It may not restate a figure or a
  rule.
- **D-516** (the window chip is one widget, from one place) binds both: 5b puts the same
  `StatsWindowChip` on the Mix header, which is why the screen goes from one chip to two.
- **D-3/D-15** (an effort's modality follows its *kind*): 5a reuses `_sectionForKind`; 5b proves the
  rendered layer and the Instruments list agree for the same effort (a timed Plank).
- **D-8/D-9** (sets take the remainder; rolling sessions count measured time only): 5a's time split.
- **D-5** (a rating is `sessionFeeling`, 1–5, and pre-redefinition answers read on the same scale):
  the rating 5a multiplies by.
- **D-606/D-666** (no legacy section name returns): 5b's legend renders `'<label> <pct>%'`, never a
  bare modality name, because `test/stats_legacy_removal_test.dart` asserts each modality label
  appears exactly once on the screen.
- **No schema change, no stored field, no migration.** Every figure derives from sessions,
  segments, efforts, timed instances, round instances and the rating as they are.
- **No `watch/` change.** `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` are
  read-only in both halves.

## Verification built into the series

- Each plan carries fixture-enumerated scenarios, runnable Done Criteria, Predicted Files, at least
  two inverse-edit mutations on tracked files, and a red run before the code it tests.
- Evidence goes to each plan's `.evidence.md`; review findings to its `.review.md`. Never into a
  plan file.
- 5b's Phase 2 adds the structural guards for this PR's defect classes: a second modality mapping, a
  bare modality name leaking from the layer, a chart primitive or new colour on the screen, and a
  strip that collapses back to one colour per week.
- The Code Reviewer verifies per phase: diff against Predicted Files, the per-S-x test and fixture
  conformance, Hive↔Mock parity on the touched data, and the Assumption Log adjudication.

## Review follow-ups

Both halves were reviewed. The findings that needed a change of their own are 5c; the rest were
fixed inside the half that owned them.

- **5a review.** The inbox `applied_at_ms` contract comment in `scripts/sqlite_schema.sql` claimed
  the stamp is "set once, never cleared", which `clearWatchInboxApplied` contradicts. Corrected in
  5c.
- **5b review.** The stamp-clear was written out twice, once per repository, as a map spread with a
  null literal. Folded into `WatchInboxEntry.unapplied()` in 5c, so the two repositories call the
  same method and the null literal exists in one place.
- **5b review.** Three Mix-layer texts could wrap at a narrow width. Capped to one line with an
  ellipsis in 5c.
- **5b review.** Two doc sentences overstated the layer: `docs/stats_screen.md` said it "computes
  nothing", and `docs/design_system.md` described the Profile header as carrying the `+` add button
  in its actions. Both corrected in 5c.

## Files to delete

None. Both plan folders hold live plans; nothing in `lib/`, `test/` or `docs/` is deleted, moved or
renamed by either half.
