# Stats PR 7 — Mix Shift and Interference: PR series index

> **Status:** READY (planner) — neither half started.
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` items 10
> (Modality Mix Shift) and 11 (Cross-Modality Interference After Hard Sports Sessions).
> **Base:** `develop`, Stats PR 6 series DONE (`docs/plans/2026-10-03-06-stats-pr6-index.md`). The
> Signals framework is live with one registered signal (Progression Rate); `signalsGateMet` reads
> `MixLayerData.ratedBaselineWeeks`; `StatsProgressService.computeMixLayer` is the only Mix walk.
> **Binding conventions:** `docs/global_conventions.md`, plus the `docs/README.md` entries each plan
> lists by path. Budget: `.github/agents/pr_scope_budget.md`.

## Why this is a series

Both items are *signals* — one class and one registry line each — but they share almost nothing else.
Item 10 compares two modality bars over a fixed 28-day period and needs a period-scoped entry point
into the Mix walk that does not exist yet. Item 11 is a session-level rule — a 90-day percentile, a
36-hour follow-up, a per-exercise dip, a 45-day pattern — and needs a second walk over the history.

Written as one plan they would carry ~44 ledger decisions and 28 scenarios across six phases, two of
which sit on the same 2,247-line service file — a hard-limit breach on phases before counting a plan
line. The seam is the two items themselves: same files, different regions, no shared decision, and
either can ship alone. 7a first, because 7b's caution priority is defined *relative to* 7a's.

## Scope check (the series)

| Measure | 7a | 7b | Soft | Hard |
|---|---|---|---|---|
| Plan lines | 558 | 652 | 500 | 800 |
| Phases | 3 | 3 | >3 | >5 |
| Tracks | 1 | 1 | >1 | — |
| Ledger decisions | 18 (D-1201…D-1218) | 20 (D-1301…D-1320) | >20 | — |
| Scenarios | 13 (S-1901…S-1913) | 15 (S-2001…S-2015) | >30 | — |
| Predicted production lines | ~230 | ~360 | — | ~1,500 |

Line counts are the planner's measurements, read back from each file; each plan's Progress table
carries the executor's re-measurement.

**Verdict:** both halves are under every hard limit. Each exceeds one soft signal — plan length — and
the split rule is "split if two or more soft signals", so neither needs a further split. The length is
the price of self-containment: fixture-enumerated scenarios with hand-computed values, per-phase
Predicted Files, Done Criteria and mutation pairs are what let a non-planner agent execute and verify
a phase without this conversation. 7b's 20 decisions sit exactly on the soft boundary.

## The PRs, in order

| # | Plan | One-line scope | Depends on | Owning agent |
|---|---|---|---|---|
| 7a | `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.md` | Modality Mix Shift: a period-scoped second entry point into the Mix walk, the exact-fraction "halved its usual share" rule over the payload's own segments, the two-sentence copy, and the one registry line that puts the caution card on the layer. | 6 DONE | @dba (Phase 1) → @developer (Phases 2–3) |
| 7b | `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.md` | Cross-Modality Interference: a session walk carrying per-session Sports load and per-exercise bests, the 90-day top-25% hard rule, the 36-hour follow-up, the per-exercise dip and the 45-day pattern, the copy, and the one registry line. | 7a DONE (priority order) | @dba (Phases 1–2) → @developer (Phase 3) |

7a and 7b are one release. 7a alone is complete — one more caution card a user with a shrinking
modality can see; 7b adds the second. Landing 7b first is possible (it depends on no 7a symbol) but
would leave the caution order's top entry undefined and force the two to be re-verified together.

## Shared decisions (the ones both plans depend on)

- **The Signals framework is closed.** 6a's `Signal`, `buildSignalRegistry`, `resolveSignals`,
  `signalsGateMet`, `SignalCard` and the 14-day dismissal store are the container; neither plan
  changes a framework file, adds a `SignalContext` member, or re-states a framework rule. Each plan
  adds one class and one registry line (6a D-1015, D-1016).
- **The service is the only history walker.** Neither signal walks history itself; both ask
  `StatsProgressService` for a payload. 7a adds `computeMixPeriod`; 7b adds `interferenceSessions`.
  Both ride the cached history index, so a screen evaluation still reads the repository once.
- **One split, three readers.** 7a extracts nothing from the split; 7b extracts `_sessionSplits` from
  `computeMixLayer`'s loop body so the Mix layer and the signal cannot disagree about a session's
  Sports load. `computeMixLayer`'s rendered figures do not change in either half.
- **Shared constants come from `lib/core/models/training_load.dart`** — `MixMeasure`, `MixSegment`,
  `mixSegments`, `sessionTimeByModality`, `sessionLoadByModality`, `baselineBlockStarts`,
  `localMidnightDay`, `kTrainingLoadBaselineWeeks`, `kTrainingLoadMinRatedWeeks`,
  `kTrainingLoadMaxUnratedShare` — and `ExerciseSection` from `lib/core/models/exercise_metric.dart`.
  Neither plan restates one.
- **The caution order is one order, defined once.** Interference 500 > Mix Shift 400 > Fuel vs Load
  300 > Protein Consistency 200 > Sustained High Load 100 > Cardio Efficiency Drift 50, written into
  `docs/signals.md` by 7a (which creates the order's second entry) and referenced by 7b. The positive
  stays `kProgressionRatePriority`; priorities are comparable only within a kind.
- **No schema change, no stored field, no migration.** Dismissals ride the existing repository
  preference API; neither plan touches `scripts/sqlite_schema.sql` or `lib/data/`.
- **No `watch/` change and no PR-rule change.** `test/in_session_pr_toast_test.dart` and
  `test/pr_toast_test.dart` are read-only in both halves, and neither signal reads an all-time best.

## Verification built into the series

- Each plan carries fixture-enumerated scenarios with hand-computed values, runnable Done Criteria,
  Predicted Files, at least two inverse-edit mutations on tracked files, and a red run before the code
  it tests.
- Evidence goes to each plan's `.evidence.md`; review findings to its `.review.md`. Never into a plan
  file.
- 7a's Phase 3 adds the structural guards for its defect classes: a fire test that reads a rounded
  percentage instead of an exact fraction, a signal that re-derives a bar instead of reading the
  payload's own segments, a signal that walks history itself, and a framework file that drifted.
- 7b's Phase 3 adds the guards for its classes: a hard rule that counts unrated sessions, a follow-up
  bound that admits the boundary or not as specified, a dip that fires on rounded arithmetic, a
  per-exercise average that lets a follow-up vote for itself, and a priority order that collides.
- The Code Reviewer verifies per phase: diff against Predicted Files, per-S-x test and fixture
  conformance, Hive↔Mock parity on the touched data, and the Assumption Log adjudication.

## Files to delete

None. Both plan folders hold live plans; nothing in `lib/`, `test/` or `docs/` is deleted, moved or
renamed by either half.
