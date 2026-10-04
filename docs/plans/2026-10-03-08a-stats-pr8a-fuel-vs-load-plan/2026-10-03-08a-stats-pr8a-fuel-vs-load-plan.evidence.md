# Evidence — Stats PR 8a (Fuel vs Load + the shared nutrition foundation)

Plan: `2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.md`. Review findings go in
`2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.review.md`.

Executors write here, never into the plan: baselines, suite summaries, red→green tables, mutation
pairs, residue-sweep hits, doc byte sizes. Append a dated section per run; never rewrite an earlier
one.

## Baselines (measured by the planner on `develop` at `2b6e8e5`, before any phase)

| Command | Result |
|---|---|
| `flutter analyze` | `196 issues found.` — 0 errors |
| `flutter test` | `+3635 ~1: All tests passed!` |

Phase 1's own Done Criteria repeats these numbers; a change in either is a finding, not a new
baseline.

## Phase 1 — the pure foundation and the rule

### Red runs (before the code exists)

| Suite | Command | Output |
|---|---|---|
| _not run yet_ | | |

### Green runs

| Suite | Command | Output |
|---|---|---|
| _not run yet_ | | |

### Mutation pairs (each applied, observed, restored, re-run green)

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (a) | `lib/core/models/fuel_vs_load.dart` (NEW — original line copied here first) | D-1408's `>=` → `>` | S-2104 (exactly +20%) | | |
| (b) | `lib/core/models/fuel_vs_load.dart` (NEW) | D-1410's `<=` → `<` | S-2105 (exactly +5%) | | |
| (c) | `lib/core/models/nutrition_consistency.dart` (NEW) | D-1404's `>= 5` → `> 5` | S-2110 (5 of 7 passes) | | |

_For the two NEW files, paste the original line under the file name in this table before mutating it,
so the restore is provable from this file alone._

### Full-suite summary (Phase 1)

```
<paste `flutter test`'s summary line>
```

## Phase 2 — the period-scoped per-day series

### Red runs

| Suite | Command | Output |
|---|---|---|
| _not run yet_ | | |

### Green runs

| Suite | Command | Output |
|---|---|---|
| _not run yet_ | | |

### Mutation pair

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (d) | `lib/core/services/stats_progress_service.dart` | anchor the new read on the real clock instead of its bounds | S-2112 / the past-dated fixture | | |

### S-2112 detail

| Assertion | Observed |
|---|---|
| 21-day period call equals the equivalent window call, field for field | |
| prior call's last instant is the millisecond before the recent call's first | |
| session at `day(20) 00:00` in recent only; at `day(21) 00:00` in prior only | |
| `test/modality_mix_period_service_test.dart` passes unmodified | |

### Full-suite summary (Phase 2)

```
<paste `flutter test`'s summary line>
```

## Phase 3 — the card, the registry line, the guards

### Red runs

| Suite | Command | Output |
|---|---|---|
| `test/fuel_vs_load_signal_screen_test.dart` (before the registry line) | | |

### Green runs

| Suite | Command | Output |
|---|---|---|
| _not run yet_ | | |

### Mutation pair

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (e) | `lib/core/services/signals/fuel_vs_load_signal.dart` (NEW — original line copied here first) | drop D-1407's `measure == MixMeasure.load` requirement | S-2111 | | |

### Structural guards (each a permanent test, named)

| Guard | Test | Status |
|---|---|---|
| No calorie amount or reduction wording in any card text, and no `cal`/`kcal` in the definition file's stripped source (S-2108) | | |
| The 3-week span is derived, not written: no `3 weeks` literal in the file, `'3 weeks'` in the built observation | | |
| The adapter walks no history and calls no PR API | | |

### Residue sweep

Search terms: `FuelVsLoadSignal`, `fuel-vs-load`, `fuelVsLoad`, `kFuelVsLoadWindowDays`,
`kFuelVsLoadLoadRisePercent`, `kFuelVsLoadIntakeTolerancePercent`, `kFuelVsLoadPriority`,
`nutritionSeries`, `nutrition_consistency`, and the observation's opening words.

| Term | Files hit | Framework files, `watch/`, `lib/data/` absent? |
|---|---|---|
| _not run yet_ | | |

### Doc sizes (64 KiB ceiling; the indexing test warns past 52 KiB)

| Doc | Bytes before | Bytes after |
|---|---|---|
| `docs/signals.md` | | |
| `docs/stats_screen.md` | | |
| `docs/constants_reference.md` | | |
| `docs/nutrition.md` | | |
| `docs/training_load.md` | | |
| `docs/state_management/services_and_utils.md` | | |

### Full-suite summary (Phase 3)

```
<paste `flutter test`'s summary line, and explain any delta from Phase 2's>
```

## Plan size, measured

| Measure | Predicted | Measured |
|---|---|---|
| Plan lines | 574 | |
| Ledger decisions | 19 | |
| Scenarios | 13 | |
| Production lines added | ~285 | |
| Files deleted | 0 | |
