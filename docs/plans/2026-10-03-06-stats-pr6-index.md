# Stats PR 6 — the Signals framework and its first card: PR series index

> **Status:** READY (planner) — 6a not started, 6b written but not started.
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` items 8 and 9, plus the owner decisions of 2026-10-03 in `.work/stats-pr6/brief-plan.md`.
> **Base:** `develop`, Stats PR 5 series DONE (`docs/plans/2026-10-02-05-stats-pr5-index.md`). The Mix layer is in the Stats body above ALL TIME, and `MixLayerData.ratedBaselineWeeks` is available to gate on.
> **Binding conventions:** `docs/global_conventions.md`, plus the `docs/README.md` entries each plan lists. Budget: `.github/agents/pr_scope_budget.md`.

## Why this is a series

A single plan for PR 6 would carry the framework's rules *and* the first real signal's math,
thresholds, copy and fixture population in one file — 32 ledger decisions and 30 scenarios across
six phases, two soft signals on their own, before counting a plan line. The natural seam is
**container before contents**: the framework's rules (interface, selection, gating, dismissal,
the layer, the empty state) are provable with stub signals and ship green with no signal in the
registry; the first signal then plugs in by implementing one interface and adding one registry
line, which is the property the framework exists to have. Each half is well under the hard limits.

## Scope check (the series)

| Measure | 6a | 6b | Soft | Hard |
|---|---|---|---|---|
| Plan lines | 615 | 536 | 500 | 800 |
| Phases | 3 | 3 | >3 | >5 |
| Tracks | 1 | 1 | >1 | — |
| Ledger decisions | 19 (D-1001…D-1019) | 13 (D-1101…D-1113) | >20 | — |
| Scenarios | 16 (S-1701…S-1716) | 14 (S-1801…S-1814) | >30 | — |
| Predicted production lines | ~560 | ~270 | — | ~1,500 |

Line counts are the planner's measurements, read back from each file with `wc -l`; each plan's
Progress table carries the executor's re-measurement.

**Verdict:** both halves are under every hard limit. Each exceeds one soft signal — plan length
(615 and 536 against 500) — and the split rule is "split if two or more soft signals", so neither
needs a further split. The length is the price of self-containment: fixture-enumerated scenarios,
per-phase Predicted Files and Done Criteria, and the mutation table are what let a non-planner agent
execute and verify the phase without this conversation. Trimming below 500 would cost content, not
fat.

## The PRs, in order

| # | Plan | One-line scope | Depends on | Owning agent |
|---|---|---|---|---|
| 6a | `docs/plans/2026-10-03-06a-stats-pr6a-signals-framework-plan/2026-10-03-06a-stats-pr6a-signals-framework-plan.md` | The Signals container: the pure model and its selection, gating and 14-day dismissal rules, the `Signal` contract and its one registry, repository-backed dismissal persistence, the layer widget with its header, cards and quiet line, and the screen's one-pass wiring — with stub signals only. No signal ships. | 5 DONE | @dba (Phase 1) → @developer (Phases 2–3) |
| 6b | `docs/plans/2026-10-03-06b-stats-pr6b-progression-rate-plan/2026-10-03-06b-stats-pr6b-progression-rate-plan.md` | Progression Rate: the per-session native value over set efforts, the two 28-day windows, the three thresholds, the copy, and the one registry line that puts the card on the layer. | 6a DONE | @dba (Phase 1) → @developer (Phases 2–3) |

Both halves are one release. 6a alone leaves the registry empty, so a user with rated history sees
the quiet line and nothing else; 6b's Phase 2 is the first point at which a real card is visible.
Shipping 6a alone is safe but pointless, so the two land together.

## Shared decisions (the ones both plans depend on)

- **D-1001…D-1019 live in 6a** and are the only definition of the card, the selection, the gate,
  the quiet line and the dismissal. 6b registers a signal and computes a rate; it restates no
  framework rule.
- **D-1015 and D-1016 are the whole point of the split.** 6b adds `ProgressionRateSignal`, one
  `ProgressionSample` walk on `StatsProgressService`, one pure math file and one registry line.
  If 6b needs a framework change, the seam is wrong and the split is wrong.
- **D-1006 (the gate) reuses `kTrainingLoadMinRatedWeeks`** from `lib/core/models/training_load.dart`
  — 5a's constant, never restated. Both plans import it.
- **D-1013's calendar-day arithmetic reuses `localMidnightDay`** from the same file, for the same
  reason: one definition of "a day" in the codebase.
- **D-1101 reuses `_resistanceValue`, `_repsAxisExercises` and `_hasBodyweightEntry`** — the
  existing native-value rule and axis classification — and the pack's rule that the progression
  measure must not share rules with the PR measure.
- **No schema change, no stored field, no migration.** Dismissals ride the existing repository
  preference API (`getPreferenceString` / `setPreferenceString`), which both
  `HiveWorkoutRepository` and `MockWorkoutRepository` implement, so the two stores agree
  value-for-value.
- **No `watch/` change.** `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` are
  read-only in both halves.

## Verification built into the series

- Each plan carries fixture-enumerated scenarios, runnable Done Criteria, Predicted Files, at least
  two inverse-edit mutations on tracked files, and a red run before the code it tests.
- Evidence goes to each plan's `.evidence.md`; review findings to its `.review.md`. Never into a
  plan file.
- 6a's Phase 3 adds the structural guards for its defect classes: a signal that shows without its
  data-sufficiency conditions, a third card on a two-card layer, a card that survives its
  dismissal, a layer that renders when the gate is unmet, and a colour or chart primitive the
  layer invented.
- 6b's Phase 3 adds the guards for its own classes: a second native-value rule, a rate computed
  from rounded percentages instead of exact fractions, and a progression measure that has drifted
  into the PR rule.
- The Code Reviewer verifies per phase: diff against Predicted Files, per-S-x test and fixture
  conformance, Hive↔Mock parity on the touched data, and the Assumption Log adjudication.

## Files to delete

None. Both plan folders hold live plans; nothing in `lib/`, `test/` or `docs/` is deleted, moved or
renamed by either half.
