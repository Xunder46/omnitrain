# Stats PR 8 — Fuel vs Load, Protein Consistency and housekeeping: PR series index

> **Status:** READY (planner) — none of the three started.
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` items 12
> (Fuel vs Load) and 13 (Protein Consistency), plus the drift the research for those two turned up.
> **Base:** `develop`, Stats PR 7 DONE — 7a shipped as `b3b91fa`, 7b as `2b6e8e5`
> (`docs/plans/2026-10-03-07-stats-pr7-index.md`). The Signals framework is live with three registered
> signals and the Mix layer's period-scoped walk, `StatsProgressService.computeMixPeriod`, is in place.
> **Binding conventions:** `docs/global_conventions.md`, plus the `docs/README.md` entries each plan lists
> by path. Budget: `.github/agents/pr_scope_budget.md`.

## Why this is a series

The two signals share a small foundation: the week-block and logged-day helpers both need, and one
period-scoped entry point into the existing per-day nutrition aggregation. 8b does not compile without 8a.
Neither half can absorb the other's scenarios inside the soft budget, and each is a complete, reviewable
unit on its own. The housekeeping item is independent of both.

## The three PRs

| PR | Scope (one line) | Depends on | Plan | Phases | Ledger | Scenarios | Predicted production lines |
|---|---|---|---|---|---|---|---|
| **8a** | Fuel vs Load caution + the shared nutrition foundation (week-block/logged-day helpers and `nutritionSeries`) | — | `docs/plans/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan/` | 3 | D-1401…D-1419 | S-2101…S-2113 | ~285 |
| **8b** | Protein Consistency caution (target or own-baseline comparison, resistance gate, g/kg figure) | **8a Phases 1–2** | `docs/plans/2026-10-03-08b-stats-pr8b-protein-consistency-plan/` | 3 | D-1501…D-1519 | S-2201…S-2216 | ~270 |
| **8h** | Derive two hardcoded window strings from their constants, guard them, and bring four plan files' status lines up to date | — | `docs/plans/2026-10-03-08h-stats-pr8h-housekeeping-plan/` | 1 | D-1601…D-1605 | S-2301…S-2303 | ~8 |

## Order

1. **8a** — it creates the foundation 8b needs. Within it, Phases 1 → 2 → 3, strictly.
2. **8b** — starts only once 8a's Phase 2 is green. Within it, Phases 1 → 2 → 3.
3. **8h** — any time: before 8a, between 8a and 8b, or after both. Nothing depends on it and it depends on
   nothing. It is listed last only because it is the smallest.

**Merge rule:** 8b may be *written* against 8a's Phase 1–2 interfaces before 8a merges, but 8b must not
merge before 8a does.

## The seam (shared decisions)

These are the contracts the two plans agree on. Each is written out in full in the owning plan; this table
is a map, not a substitute.

| Contract | Owner | 8b's obligation |
|---|---|---|
| `lib/core/models/nutrition_consistency.dart` — `kWeekDays = 7`, `kConsistentWeekMinLoggedDays = 5`, the block-start helper, the logged-day count, the consistency test, the logged-days-only mean (D-1401) | 8a Phase 1 | consume unchanged; add no member, edit no line (D-1501) |
| `StatsProgressService.nutritionSeries({fromMs, toMs})` — the one per-day `ConsumedFood` aggregation, shared with `computeNutritionTrend` (D-1402, D-1403) | 8a Phase 2 | consume for the window's protein figures (D-1505) |
| A logged day = at least one `ConsumedFood` row; a day with none is absent and never zero-filled (D-1403) | 8a Phase 1 | same rule (D-1503) |
| Caution priority order, descending: Interference 500 > Mix Shift 400 > **Fuel vs Load 300** > **Protein Consistency 200** (D-1415, D-1517) | 8a Phase 3 | append below 8a's line; the pack requires it "below Fuel vs Load" |
| The registry guards in `test/interference_test.dart` and `test/modality_mix_shift_signal_screen_test.dart` assert the **whole** id list and the caution order | 8a Phase 3 extends them to four | 8b Phase 3 extends them to five |
| `docs/signals.md`'s caution-order paragraph is corrected by 8a to the three shipped cautions (it is stale today: it claims Mix Shift is the only one) | 8a Phase 3 | extends it to five and adds its own paragraph |
| `docs/constants_reference.md` gains one constant group per signal; `docs/nutrition.md` gains the shared logged-day rule | 8a Phases 1–3 | adds its own group and its per-day-target rule |
| One signal = one pure file in `lib/core/models/` + one thin adapter in `lib/core/services/signals/` + one line in `buildSignalRegistry()`; no framework file changes | both | same |

## Scope check (each plan, against `.github/agents/pr_scope_budget.md`)

| Plan | Lines | Phases | Tracks | Decisions | Scenarios | Soft signals | Verdict |
|---|---|---|---|---|---|---|---|
| 8a | 576 | 3 | 1 | 19 | 13 | 1 (length) | inside the hard budget |
| 8b | 671 | 3 | 1 | 19 | 16 | 1 (length) | inside the hard budget; the length is scenario-bound |
| 8h | 250 | 1 | 1 | 5 | 3 | 0 | inside the budget |

Hard limits: 800 plan lines, 5 phases, ~1,500 predicted production lines. No plan reaches two soft signals,
so no further split is required.

## Files deleted by this series

**None.** No file is deleted, moved or renamed; no schema, model field or stored value changes. The only
production edits outside new files are: one registry line, the `StatsProgressService` extraction and its
four 8b reads, and 8h's two copy interpolations.

## Notes

- **Evidence and review live beside each plan**: `<plan>.evidence.md` for executors' baselines, suite
  summaries and mutation pairs; `<plan>.review.md` for the reviewer's findings. Neither is written into a
  plan file.
- **Docs trail code by zero phases** in every plan here, so the final phase of each closes with the doc it
  invalidated. No `docs/` file approaches the 64 KiB ceiling (8h's evidence records the measurements).
- **`docs/README.md` needs no change** from any of the three: it indexes feature docs, not plan files, and
  every feature doc this series touches is already in its index.
- **Owner-visible consequence to decide separately:** 8b's Finding F-1 — the daily nutrition target screen
  is calories-only by design (D-3 / S-040) and persists `protein: 0.0`, so no user can reach Protein
  Consistency's target-comparison branch. The pack puts changing targets out of scope, so 8b implements and
  tests that branch without making it reachable. Every shipped user will see the own-baseline wording.
- **Every defaulted choice is listed** under "Open questions" in each plan, marked "owner to confirm".
  Nothing in this series is blocked on an answer: the defaults are the conservative reading of the pack.
