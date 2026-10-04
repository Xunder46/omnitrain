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

Opening measurement on `develop` HEAD `627199f` (per the brief): `flutter analyze` = `196 issues found.`
(0 errors); `flutter test` = `+3637 ~1: All tests passed!`.

### Red runs (before the code exists)

| Suite | Command | Output |
|---|---|---|
| `test/nutrition_consistency_test.dart` (step 1, before the file exists) | `.github/copilot/scripts/macos/gateway.sh test test/nutrition_consistency_test.dart` | compile failure: `Error when reading 'lib/core/models/nutrition_consistency.dart': No such file or directory`; 16 × `Method not found` / `Undefined name`; `00:00 +0 -1: Some tests failed.` |
| `test/fuel_vs_load_test.dart` (step 4, before the file exists) | `.github/copilot/scripts/macos/gateway.sh test test/fuel_vs_load_test.dart` | compile failure: `Error when reading 'lib/core/models/fuel_vs_load.dart': No such file or directory`; `Type 'LoggedDay' not found`, `Type 'FuelVsLoad' not found`, 22 × `Method not found` / `Undefined name`; `00:00 +0 -1: Some tests failed.` |

### Green runs

| Suite | Command | Output |
|---|---|---|
| `test/nutrition_consistency_test.dart` (step 3) | `.github/copilot/scripts/macos/gateway.sh test test/nutrition_consistency_test.dart` | `00:00 +7: All tests passed!` |
| `test/fuel_vs_load_test.dart` (step 6) | `.github/copilot/scripts/macos/gateway.sh test test/fuel_vs_load_test.dart` | `00:00 +10: All tests passed!` |
| both (step 6) | `.github/copilot/scripts/macos/gateway.sh test test/nutrition_consistency_test.dart test/fuel_vs_load_test.dart` | `00:00 +17: All tests passed!` |

### Mutation pairs (each applied, observed, restored, re-run green)

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (a) | `lib/core/models/fuel_vs_load.dart` (NEW — original line copied here first) | D-1408's `>=` → `>` | S-2104 (exactly +20%) | `00:00 +3 -1: S-2104 exactly +20% load fires [E]` / `Expected: true Actual: <false>` / `00:00 +9 -1: Some tests failed.` — S-2104 the only failure | restored → `00:00 +10: All tests passed!` |
| (b) | `lib/core/models/fuel_vs_load.dart` (NEW) | D-1410's `<=` → `<` | S-2105 (exactly +5%) | `00:00 +4 -1: S-2105 exactly +5% intake still fires [E]` / `Expected: true Actual: <false>` / `00:00 +9 -1: Some tests failed.` — S-2105 the only failure | restored → `00:00 +10: All tests passed!` |
| (c) | `lib/core/models/nutrition_consistency.dart` (NEW) | D-1404's `>= 5` → `> 5` | S-2110 (5 of 7 passes) | `00:00 +12 -2: ... S-2110 exactly 5 of 7 passes and 4 of 7 fails [E]` / `Expected: true Actual: <false>` / `test/nutrition_consistency_test.dart 76:7` — plus S-2107 collaterally (its gate reads the same 5-of-7 rule) / `00:00 +15 -2: Some tests failed.` | restored → `00:00 +17: All tests passed!` |

_For the two NEW files, paste the original line under the file name in this table before mutating it,
so the restore is provable from this file alone._

Original lines (copied before mutating):

`lib/core/models/fuel_vs_load.dart` — `fuelVsLoadLoadTest`, mutation (a):
```dart
  return 100 * recentLoad >=
      (100 + kFuelVsLoadLoadRisePercent) * priorLoad;
```

`lib/core/models/fuel_vs_load.dart` — `fuelVsLoadIntakeTest`, mutation (b):
```dart
  return 100 * recentIntakeTotal * priorLoggedDays <=
      (100 + kFuelVsLoadIntakeTolerancePercent) *
          priorIntakeTotal *
          recentLoggedDays;
```

`lib/core/models/nutrition_consistency.dart` — `isConsistentWeek`, mutation (c):
```dart
  return loggedDaysInWeek(blockStart: blockStart, loggedDays: loggedDays) >=
      kConsistentWeekMinLoggedDays;
```

### Full-suite summary (Phase 1)

```
01:37 +3654 ~1: All tests passed!
```

Baseline on `develop` HEAD `627199f` was `+3637 ~1`; the 17 new tests in
`test/nutrition_consistency_test.dart` (7) and `test/fuel_vs_load_test.dart` (10)
account for the whole difference. No pre-existing test changed its result.

### Phase 1 Done Criteria

| Command | Result |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh lint` | `196 issues found. (ran in 2.9s)` — 0 errors, 1 warning, 195 infos; identical to the baseline, and no issue in either new file or either new test |
| `.github/copilot/scripts/macos/gateway.sh test test/nutrition_consistency_test.dart test/fuel_vs_load_test.dart` | `00:00 +17: All tests passed!` |
| `.github/copilot/scripts/macos/gateway.sh test` | `01:37 +3654 ~1: All tests passed!` |

`.github/copilot/scripts/macos/gateway.sh format` on the four new files reported
`Formatted 4 files (3 changed)`; both suites were re-run afterwards and stayed
`00:00 +17: All tests passed!`.

## Phase 2 — the period-scoped per-day series

### Red runs

| Suite | Command | Output |
|---|---|---|
| `test/nutrition_series_service_test.dart` (step 2, before the service change) | `.github/copilot/scripts/macos/gateway.sh test test/nutrition_series_service_test.dart` | compile failure: `test/nutrition_series_service_test.dart:270:38: Error: The method 'nutritionSeries' isn't defined for the type 'StatsProgressService'.` — same error at 287:11, 303:11, 403:31, 409:27, 429:9 (6 ×), plus `69:12: Error: The getter 'millisecondsSinceEpoch' isn't defined for the type 'Object'.`; `00:00 +0 -1: Some tests failed.` |

### Green runs

| Suite | Command | Output |
|---|---|---|
| `test/nutrition_series_service_test.dart` (step 2, after the service change) | `.github/copilot/scripts/macos/gateway.sh test test/nutrition_series_service_test.dart` | `00:00 +11: All tests passed!` |
| the four neighbouring suites (step 4) | `.github/copilot/scripts/macos/gateway.sh test test/stats_progress_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/db_seed_test.dart` | `00:01 +112: All tests passed!` — no existing expectation changed |
| the new suite plus the sweep the extraction tripped (step 4, second pass) | `.github/copilot/scripts/macos/gateway.sh test test/nutrition_series_service_test.dart test/stats_legacy_removal_test.dart test/stats_progress_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/db_seed_test.dart` | `00:01 +132: All tests passed!` |

### Extraction defect found and fixed (step 4)

The first full-suite run after the extraction was `01:35 +3666 ~1 -1: Some tests failed.` —
`test/stats_legacy_removal_test.dart` / `S-1263 residue sweep` / `no lib reader of a removed
projection name survives`:

```
Expected: false
  Actual: <true>
D-666: `nutritionTrend` was deleted by 4c2 and must not come back to lib/core/services/stats_progress_service.dart
test/stats_legacy_removal_test.dart 511:11
```

The sweep is a case-sensitive `source.contains(name)` over `_kRetiredNames`, which lists
`nutritionTrend`. The first helper name was `_nutritionTrendInRange`, which contains that literal
(`computeNutritionTrend` does not — capital `N`). Fixed the extraction, not the test: the helper is
now `_nutritionPointsInRange`. `grep` for `nutritionTrend` in
`lib/core/services/stats_progress_service.dart` afterwards returns nothing.

### Mutation pair

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (d) | `lib/core/services/stats_progress_service.dart` | anchor the new read on the real clock instead of its bounds | S-2112 / the past-dated fixture | `00:00 +2 -9: Some tests failed.` — the three `nutritionSeries` tests fail in both stores (each returns only today's point), the S-2112 boundary test fails on `nutritionSeries(fromMs: _day(41), toMs: priorTo)` returning `[]` instead of `[day(21)]`, and the Mock/Hive parity test fails `hasLength(3)`; the two-period call itself is unaffected | restored → `00:00 +11: All tests passed!` |

Original line (copied before mutating):

`lib/core/services/stats_progress_service.dart` — `nutritionSeries`, mutation (d):
```dart
  }) => _nutritionPointsInRange(
    fromMs: fromMs.millisecondsSinceEpoch,
    toMs: toMs.millisecondsSinceEpoch,
  );
```

### S-2112 detail

| Assertion | Observed |
|---|---|
| 21-day period call equals the equivalent window call, field for field | pass (Mock and Hive) — `measure`, `segments`, `baselineSegments`, `unratedSessionCount`, `ratedBaselineWeeks` all equal; `weeks` empty; measure is `MixMeasure.load` |
| prior call's last instant is the millisecond before the recent call's first | pass — `day(20) 00:00 − 1 ms` vs `day(20) 00:00` |
| session at `day(20) 00:00` in recent only; at `day(21) 23:59` in prior only | pass — recent has Sports > 0 and Isometric 0; prior has Isometric > 0 and Sports 0 |
| the boundary rows land in the period whose day they carry | pass — `nutritionSeries(prior bounds)` = `[day(21)]`, `nutritionSeries(recent bounds)` = `[day(20)]` |
| `test/modality_mix_period_service_test.dart` passes unmodified | pass — `00:01 +112: All tests passed!` over the four neighbouring suites |

### Full-suite summary (Phase 2)

```
01:46 +3667 ~1: All tests passed!
```

Baseline at Phase 1's close was `+3656 ~1`; the 11 new tests in
`test/nutrition_series_service_test.dart` account for the whole difference. No pre-existing test
changed its result.

### Phase 2 Done Criteria

| Command | Result |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh lint` | `196 issues found. (ran in 3.0s)` — 0 errors; identical to the baseline, and no issue in `lib/core/services/stats_progress_service.dart` or `test/nutrition_series_service_test.dart` |
| `.github/copilot/scripts/macos/gateway.sh test test/nutrition_series_service_test.dart test/stats_progress_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/db_seed_test.dart` | `00:01 +123: All tests passed!` |
| `.github/copilot/scripts/macos/gateway.sh test` | `01:46 +3667 ~1: All tests passed!` |

`.github/copilot/scripts/macos/gateway.sh format test/nutrition_series_service_test.dart` reported
`Formatted 1 file (1 changed)`; the suite was re-run afterwards and stayed green. `dart format` was
not run on `lib/core/services/stats_progress_service.dart` (not format-clean).

### Doc edits (step 6)

| Doc | Added |
|---|---|
| `docs/state_management/services_and_utils.md` | `nutritionSeries` under the `StatsProgressService` entry: the shared walk, the inclusive bounds, the absent-day rule; verification names all six tests |
| `docs/training_load.md` | the period entry point's callers: the shift rule's period and a 21-day period, the 21-day call needing no code of its own; verified by the two S-2112 tests alongside the unmodified 7a suite |
| `docs/nutrition.md` | the shared per-day source under `computeNutritionTrend`; verified by the four `nutritionSeries` tests alongside the existing two suites |

Every test name cited above was read back from `test/nutrition_series_service_test.dart` after the
last edit to that file, so no doc names a test that does not exist.

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

## Phase 1 — Fix 1 (the constant-contract tests the docs name)

**Finding.** `docs/constants_reference.md` claims the two new constant groups are
"Verified by `test/nutrition_consistency_test.dart` (the constant contracts and …)"
and "`test/fuel_vs_load_test.dart` (the constant contracts and …)", and
`docs/nutrition.md` names the same suite. Neither file had a test named
"the constant contracts", so the doc claim was false. Fixed by adding the tests
the docs name — not by weakening the docs.

### Tests added

| File | Test name | Asserts |
|---|---|---|
| `test/nutrition_consistency_test.dart` | `the constant contracts` | `kWeekDays == 7`, `kConsistentWeekMinLoggedDays == 5` |
| `test/fuel_vs_load_test.dart` | `the constant contracts` | `kFuelVsLoadWindowDays == 21`, `kFuelVsLoadLoadRisePercent == 20`, `kFuelVsLoadIntakeTolerancePercent == 5`, `kFuelVsLoadPriority == 300` |

### Green run (both suites)

```
$ .github/copilot/scripts/macos/gateway.sh test test/nutrition_consistency_test.dart test/fuel_vs_load_test.dart
00:00 +0: /Users/irinakutsenko/Developer/omnitrain/test/fuel_vs_load_test.dart: the constant contracts
...
00:00 +11: /Users/irinakutsenko/Developer/omnitrain/test/nutrition_consistency_test.dart: the constant contracts
...
00:00 +19: All tests passed!
```

### Mutation pair (applied, observed, restored, re-run green)

Original line, copied before mutating — `lib/core/models/fuel_vs_load.dart`:

```dart
const int kFuelVsLoadPriority = 300;
```

| # | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|
| (f) | `kFuelVsLoadPriority = 300` → `301` | `the constant contracts` (`test/fuel_vs_load_test.dart`) | `00:00 +0 -1: the constant contracts [E]` / `Expected: <300> Actual: <301>` / `test/fuel_vs_load_test.dart 73:5` / `00:00 +10 -1: Some tests failed.` — the new test the only failure | restored to `const int kFuelVsLoadPriority = 300;` → `00:00 +11: All tests passed!` |

### Doc re-read

| Doc | Named test | Exists? |
|---|---|---|
| `docs/constants_reference.md` — Nutrition Consistency Constants | `test/nutrition_consistency_test.dart` ("the constant contracts and the block-boundary scenarios") | yes — `the constant contracts` plus the block-start and 5-of-7 tests |
| `docs/constants_reference.md` — Fuel vs Load Constants | `test/fuel_vs_load_test.dart` ("the constant contracts and the boundary scenarios S-2103–S-2106") | yes — `the constant contracts` plus S-2103…S-2106 |
| `docs/nutrition.md` — "Logged-day consistency" | `test/nutrition_consistency_test.dart` (block starts, month-end block, 5-of-7 boundary, logged-days-only mean) | yes — every described scenario exists by that description; the section names no test literally, so no wording change needed |

No doc wording change was required: every test the docs name now exists.

### Final checks

```
$ .github/copilot/scripts/macos/gateway.sh lint
196 issues found. (ran in 2.5s)        # 0 errors (no `error •` line)

$ .github/copilot/scripts/macos/gateway.sh test
01:36 +3656 ~1: All tests passed!      # expected `+3656 ~1`; +2 over Phase 1's +3654 = the two new tests
```
