# Evidence — Stats PR 8b (Protein Consistency)

Plan: `2026-10-03-08b-stats-pr8b-protein-consistency-plan.md`. Review findings go in
`2026-10-03-08b-stats-pr8b-protein-consistency-plan.review.md`.

Executors write here, never into the plan: baselines, suite summaries, red→green tables, mutation pairs,
residue-sweep hits, doc byte sizes. Append a dated section per run; never rewrite an earlier one.

## Opening measurement (taken at Phase 1, on 8a's merged state)

| Command | Result |
|---|---|
| `flutter analyze` | `196 issues found.` (0 errors — checked by scanning the saved output for `error •`); ran in 3.0s |
| `flutter test` | not re-measured before the new suite existed; see the Phase 1 full-suite summary below, whose total includes this phase's 14 new tests |

For reference, the pre-8a `develop` (`2b6e8e5`) numbers were `196 issues found.` (0 errors) and
`+3635 ~1: All tests passed!`. 8a adds suites, so a higher test total here is expected; compare each
phase against this table, not against the pre-8a numbers.

## Phase 1 — the pure protein rule

### Red runs (before the code exists)

| Suite | Command | Output |
|---|---|---|
| `test/protein_consistency_test.dart` (new, before `lib/core/models/protein_consistency.dart` exists) | `.github/copilot/scripts/macos/gateway.sh test test/protein_consistency_test.dart` | `00:00 +0 -1: Some tests failed.` — `Failed to load ... Compilation failed for testPath=.../test/protein_consistency_test.dart: test/protein_consistency_test.dart:11:8: Error: Error when reading 'lib/core/models/protein_consistency.dart': No such file or directory`, then 40 further `Error: Type 'ProteinDay' not found.` / `Method not found:` / `Undefined name ...` lines |

### Green runs

| Suite | Command | Output |
|---|---|---|
| `test/protein_consistency_test.dart` | `.github/copilot/scripts/macos/gateway.sh test test/protein_consistency_test.dart` | `00:00 +14: All tests passed!` (14 tests: the constant contract plus S-2201…S-2213) |

### Mutation pairs (each applied, observed, restored, re-run green)

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (a) | `lib/core/models/protein_consistency.dart` (NEW — original line copied here first) | D-1508 target-mode `<=` → `<` | S-2201 (120 g against a 150 g target) | `00:00 +1 -1: S-2201 ... [E] Expected: true / Actual: <false>` at `test/protein_consistency_test.dart 120:5` (the inclusive-boundary assertion `proteinShortfallTestAgainstTarget(recentTotal: 1530, targetSum: 1800)`); `00:00 +13 -1: Some tests failed.` | yes — restored, `+14: All tests passed!` |
| (b) | same file | D-1504's `>= 10` → `>= 11` | S-2204 (exactly 10 of 14) | `00:00 +4 -1: S-2204 ... [E] Expected: true / Actual: <false>` at `test/protein_consistency_test.dart 183:5` (`proteinConsistencyGate(recentDays: rows)`); `00:00 +13 -1: Some tests failed.` | yes — restored, `+14: All tests passed!` |
| (c) | same file | D-1508 own-mode comparison divides both totals by `kProteinConsistencyWindowDays` | S-2205(b) (equal means, different logged-day counts) | `00:00 +5 -1: S-2205 ... [E] Expected: null / Actual: <Instance of 'ProteinConsistency'>` at `test/protein_consistency_test.dart 262:5`; `00:00 +13 -1: Some tests failed.` | yes — restored, `+14: All tests passed!` |
| (d) | same file | D-1509's minimum consistent blocks 2 → 1 | S-2212 (0 consistent blocks) | `00:00 +12 -1: S-2212 ... [E] Expected: null / Actual: <Instance of 'ProteinConsistency'>` at `test/protein_consistency_test.dart 441:5` (the exactly-one-consistent-block boundary case); `00:00 +13 -1: Some tests failed.` | yes — restored, `+14: All tests passed!` |

_For the NEW file, paste each mutated original line under the file name in this table before mutating it,
so the restore is provable from this file alone._

**`lib/core/models/protein_consistency.dart` — original lines, copied before any mutation (NEW file, so
these are its first committed state):**

(a) `proteinShortfallTestAgainstTarget`'s comparison —
```dart
  return 100 * recentTotal <=
      (100 - kProteinConsistencyShortfallPercent) * targetSum;
```

(b) `proteinConsistencyGate`'s comparison —
```dart
    recentDays.length >= kProteinConsistencyMinLoggedDays;
```

(c) `proteinConsistency`'s own-baseline comparison —
```dart
    if (!proteinShortfallTestAgainstBaseline(
      recentTotal: recentTotal,
      recentDays: recentLoggedDays,
      usualTotal: baseline.total,
      usualDays: baseline.days,
    )) {
```

(d) `proteinConsistency`'s baseline minimum —
```dart
    if (baseline.consistentBlocks < kProteinConsistencyMinBaselineWeeks) {
      return null;
    }
```

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
02:00 +3692 ~1: All tests passed!
```

`+3692` is the pre-phase total plus this phase's 14 new tests. `flutter analyze` after the phase:
`196 issues found.` (0 errors, unchanged from the opening measurement; no issue in either new file).
Targeted run of the three nutrition-rule suites
(`test/protein_consistency_test.dart test/nutrition_consistency_test.dart test/fuel_vs_load_test.dart`):
`00:00 +35: All tests passed!`.

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
