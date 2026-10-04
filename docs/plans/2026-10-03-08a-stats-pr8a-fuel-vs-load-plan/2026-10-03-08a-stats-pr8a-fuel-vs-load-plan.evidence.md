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
