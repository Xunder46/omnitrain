# Evidence — Stats PR 8b (Protein Consistency)

Plan: `2026-10-03-08b-stats-pr8b-protein-consistency-plan.md`. Review findings go in
`2026-10-03-08b-stats-pr8b-protein-consistency-plan.review.md`.

Executors write here, never into the plan: baselines, suite summaries, red→green tables, mutation pairs,
residue-sweep hits, doc byte sizes. Append a dated section per run; never rewrite an earlier one.

## Opening measurement (taken at Phase 1, on 8a's merged state)

| Command | Result |
|---|---|
| `flutter analyze` | |
| `flutter test` | |

For reference, the pre-8a `develop` (`2b6e8e5`) numbers were `196 issues found.` (0 errors) and
`+3635 ~1: All tests passed!`. 8a adds suites, so a higher test total here is expected; compare each
phase against this table, not against the pre-8a numbers.

## Phase 1 — the pure protein rule

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
| (a) | `lib/core/models/protein_consistency.dart` (NEW — original line copied here first) | D-1508 target-mode `<=` → `<` | S-2201 (120 g against a 150 g target) | | |
| (b) | same file | D-1504's `>= 10` → `>= 11` | S-2204 (exactly 10 of 14) | | |
| (c) | same file | D-1508 own-mode comparison divides both totals by `kProteinConsistencyWindowDays` | S-2205(b) (equal means, different logged-day counts) | | |
| (d) | same file | D-1509's minimum consistent blocks 2 → 1 | S-2212 (0 consistent blocks) | | |

_For the NEW file, paste each mutated original line under the file name in this table before mutating it,
so the restore is provable from this file alone._

### Exact-string checks (the strings the tests pin)

| Scenario | Observation | Suggestion |
|---|---|---|
| S-2201 | `Protein has averaged 120 g/day over the last 2 weeks, about 20% under your 150 g target.` | `Bringing protein back toward your target is one option.` |
| S-2204 | `Protein has averaged 126 g/day over the last 2 weeks, about 16% under your 150 g target.` | as S-2201 |
| S-2205(a) | `Protein has averaged 118 g/day over the last 2 weeks, down from your usual 145 g.` | `null` (no bodyweight) |
| S-2206 | `Protein has averaged 118 g/day (1.7 g/kg) over the last 2 weeks, down from your usual 145 g.` | `Commonly cited guidance for strength training is around 1.6 g/kg of bodyweight.` |
| S-2208 | `Protein has averaged 120 g/day (1.7 g/kg) over the last 2 weeks, about 20% under your 150 g target.` | `Bringing protein back toward your target is one option.` |
| S-2210 | `Protein has averaged 120 g/day over the last 2 weeks, about 22% under your 154 g target.` | as S-2201 |
| S-2211 | `Protein has averaged 118 g/day over the last 2 weeks, down from your usual 145 g.` | `null` (no bodyweight) |

### Full-suite summary (Phase 1)

```
<paste `flutter test`'s summary line>
```

## Phase 2 — the service reads

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
| (e) | `lib/core/services/stats_progress_service.dart` | the resistance count accepts any effort kind instead of Resistance efforts | the timed-only fixture | | |

### S-2214 parity detail

| Read | Mock | Hive | Equal |
|---|---|---|---|
| the window's nutrition series | | | |
| the per-day stored protein targets | | | |
| the resistance-session count | | | |
| the latest bodyweight in kilograms | | | |
| the fired card's observation and suggestion | | | |

### Full-suite summary (Phase 2)

```
<paste `flutter test`'s summary line>
```

## Phase 3 — the card, the registry line, the guards

### Red runs

| Suite | Command | Output |
|---|---|---|
| `test/protein_consistency_signal_screen_test.dart` (before the registry line) | | |

### Green runs

| Suite | Command | Output |
|---|---|---|
| _not run yet_ | | |

### Mutation pair

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (f) | `lib/core/services/signals/protein_consistency_signal.dart` (NEW — original line copied here first) | target mode accepted when only some logged days carry a positive target | S-2211 | | |

### Structural guards (each a permanent test, named)

| Guard | Test | Status |
|---|---|---|
| No calorie amount or reduction wording in any card text; whole grams, one decimal only for g/kg; no `cal`/`kcal`/`1.6` literal in the definition file's stripped source (S-2213) | | |
| The 2-week span and the 1.6 reference are derived, not written | | |
| The adapter walks no history and calls no PR API | | |
| A null suggestion renders without an empty second line (S-2207) | | |

### Residue sweep

Search terms: `ProteinConsistencySignal`, `protein-consistency`, `proteinConsistency`,
`kProteinConsistencyWindowDays`, `kProteinConsistencyMinLoggedDays`,
`kProteinConsistencyShortfallPercent`, `kProteinConsistencyMinResistanceSessions`,
`kProteinConsistencyMinBaselineWeeks`, `kProteinConsistencyBaselineWeeks`, `kProteinGuidancePerKg`,
`kProteinConsistencyPriority`, and the observation's opening words.

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
| `docs/state_management/services_and_utils.md` | | |

### Full-suite summary (Phase 3)

```
<paste `flutter test`'s summary line, and explain any delta from Phase 2's>
```

## Plan size, measured

| Measure | Predicted | Measured |
|---|---|---|
| Plan lines | 666 | |
| Ledger decisions | 19 | |
| Scenarios | 16 | |
| Production lines added | ~270 | |
| Files deleted | 0 | |
