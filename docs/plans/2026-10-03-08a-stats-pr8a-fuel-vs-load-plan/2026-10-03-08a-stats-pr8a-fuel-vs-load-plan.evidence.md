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

### STEP 0 — the two registry guards re-applied

The governor had reverted both guard files to HEAD, so the registry order correction recorded above
was unguarded. Re-applied with minimal edits, no `format` run on either file.

| File | Edit | Diff |
|---|---|---|
| `test/interference_test.dart` | `'fuel-vs-load'` prepended to the caution id list in `the caution order holds and the registry is ordered by it` | 1 insertion |
| `test/modality_mix_shift_signal_screen_test.dart` | test renamed `lists exactly the three shipped signals, in order` → `lists exactly the four shipped signals, in order`; `'fuel-vs-load'` prepended to the expected list | 3 insertions, 1 deletion |

Red observed before the edit (the honest red — the registry is already correct, the guard is stale):

```
Expected: ['modality-mix-shift', 'cross-modality-interference']
  Actual: ['fuel-vs-load', 'modality-mix-shift', 'cross-modality-interference']
```

Green after: `00:01 +45: All tests passed!` (both suites).

### Fixture math (worked out before the test was written)

`day(n)` = local midnight, `n` days before today. Every session is a 50-minute, set-only
resistance session (no measured time, so the session's whole duration is its Resistance time) at
09:00, so `load = 50 × rating` load minutes. Every session carries a unique exercise id, so each
exercise has exactly one progression sample and `progressionRate` counts nothing (needs 8).

**F-FUEL — the firing fixture (S-2113 / S-2101).**

| Piece | Rows | Figure |
|---|---|---|
| Prior-period load | days 41, 36, 31, 26, 21 — rating 4 | 5 × 200 = **1000** |
| Recent-period load | days 20, 16, 12, 8, 4 — rating 5 | 5 × 250 = **1250** |
| Extra window-baseline session | day −10 — rating 4 | outside both periods; only adds a rated baseline block |
| Food | one row every day, days 41…0 (42 days) | days 0–20 → 2040 kcal, days 21–41 → 2000 kcal |

- Recent payload `[day(20) 00:00, now]`: `windowTimeSeconds = 15 000 > 0`; baseline = the 12 blocks
  before `day(20)`; rated sessions land in blocks `day(13)` (day 16), `day(6)` (days 8, 12),
  `day(-1)` (day 4) and `day(-8)` (day −10) → `ratedBaselineWeeks = 4` ≥ 4; unrated time share
  `0 ≤ 0.25` → `measure = load`, Σ`segments` = 1250.
- Prior payload `[day(41) 00:00, day(20) 00:00 − 1 ms]`: sessions on days 41, 36, 31, 26, 21 land in
  blocks `day(34)`, `day(27)`, `day(20)`; the baseline also sees `day(20)`, `day(13)`, `day(6)`,
  `day(-1)`, `day(-8)` → `ratedBaselineWeeks = 7` ≥ 4; unrated share 0 → `measure = load`,
  Σ`segments` = 1000.
- Measure gate: both load → passes. Load test: `100 × 1250 = 125 000 ≥ 120 × 1000 = 120 000` →
  fires, `p = 25`.
- Consistency gate: the six blocks anchored on today are `day(41)`, `day(34)`, `day(27)`, `day(20)`,
  `day(13)`, `day(6)`, spanning days 0…41 — exactly the 42 logged days → 7 of 7 in each.
- Intake test: `100 × (21 × 2040) × 21 = 89 964 000 ≤ 105 × (21 × 2000) × 21 = 92 610 000` → fires
  (intake +2%, inside the 5% tolerance).
- Window: a `TrainingPeriod` from `day(20)` to the end of today, holding all five recent sessions,
  so `resolveWindow` returns it (`isPeriodScoped: true`) and the window's own payload is the recent
  payload → `signalsGateMet` needs `ratedBaselineWeeks ≥ 4` → 4, met.
- No other signal: Interference needs Sports efforts (none — every effort is a `set`); Mix Shift
  needs a modality whose recent share is under half its baseline share, and both bars are 100%
  Resistance; Progression Rate counts 0 (one sample per exercise).
- Food calories: `caloriesConsumed = protein × 4 + carbs × 4 + fat × 9`, scaled by
  `amountConsumed / referenceAmount` (100 / 100). 2040 → protein 102, carbs 408; 2000 → protein 100,
  carbs 400.

**F-NOFOOD — abstention with no food.** F-FUEL's load and period, the food log emptied. The
consistency gate finds 0 of 7 in every block → abstains; the layer still renders (the window's rated
baseline is unchanged) so the quiet line is the assertion. `computeFuelSummary` returns null on an
empty log, so the Fuel block is absent — not asserted here.

**F-TIME21 — abstention when a period measures time (S-2111 at the screen).** F-FUEL plus one
unrated 100-minute set-only session on day 2. Recent payload: `windowTimeSeconds = 5 × 3000 + 6000
= 21 000`, `unratedTimeSeconds = 6000`, share `0.286 > 0.25` → `measure = time`; the rated baseline
is untouched, so `ratedBaselineWeeks` stays 4 and the layer still renders. The measure gate then
fails on the recent payload → abstains. Its unrated session contributes 0 load, so the load figures
are unchanged.

### Red runs

| Suite | Command | Output |
|---|---|---|
| `test/fuel_vs_load_signal_screen_test.dart` (red A — before the adapter existed) | `gateway.sh test test/fuel_vs_load_signal_screen_test.dart` | Compile failure: `Error: Couldn't resolve the package 'omnitrain' ... fuel_vs_load_signal.dart` (the adapter file did not exist) plus two type errors in the fixture — `The argument type 'int' can't be assigned to the parameter type 'double'` for `protein:` and `carbs:` on `ConsumedFood`. Fixed by `(calories ~/ 20).toDouble()` / `(calories ~/ 5).toDouble()`. |
| `test/fuel_vs_load_signal_screen_test.dart` (red B — adapter exists, registry line absent) | `gateway.sh test test/fuel_vs_load_signal_screen_test.dart --plain-name "Mock"` | `+3 -2: Some tests failed.` The two screen tests fail with `Expected: exactly one matching candidate / Actual: _KeyWidgetFinder:<Found 0 widgets with key [<'signal_card_fuel-vs-load'>]: []>` — the honest red: the registry has no `fuel-vs-load` line, so the layer never builds the card. The adapter test and both abstention tests pass, so the rule itself fires on F-FUEL. |

**Fixture diagnosis (the sanctioned scratch probe).** Red B's first form also failed the adapter
test (`Expected: not null / Actual: <null>`), which meant the fixture did not fire. A scratch probe
(`test/zz_ffuel_probe_test.dart`, temporary) dumped both payloads, the window and the series. Its
first run reported the prior period's `segments` as 2250 — but that was the **probe's** bug: it
passed `toMs: now` for the prior period instead of the adapter's `day(20) − 1 ms`, so the prior
window swallowed the recent sessions too. With the adapter's real bounds the probe reports:

```
PROBE recent: payload=true measure=MixMeasure.load rated=7 unratedSessions=0 segments=[1250.0] baseline=[1800.0]
PROBE prior:  payload=true measure=MixMeasure.load rated=4 unratedSessions=0 segments=[1000.0] baseline=[800.0]
PROBE window: from=2026-09-13 00:00:00.000 to=2026-10-03 23:59:59.999 label=Test Block scoped=true
PROBE mix:    null=false measure=MixMeasure.load rated=7 gate=true
PROBE series: count=42 first=2026-08-23 00:00:00.000 last=2026-10-03 00:00:00.000 calories={2000, 2040}
```

Every gate the fixture math predicted is met: both periods measure load, recent 1250 against prior
1000 (+25%), the window's rated baseline is 7 (≥ 4) so the layer renders, and the series holds all
42 logged days at 2000/2040 kcal. The fixture needed no change; the probe did. The probe file is
temporary and is removed by the next run that can delete files (no `rm` is available here).

### Green runs

| Suite | Command | Output |
|---|---|---|
| `test/fuel_vs_load_signal_screen_test.dart` (Mock) | `gateway.sh test test/fuel_vs_load_signal_screen_test.dart --plain-name "Mock"` | `+5: All tests passed!` |
| `test/fuel_vs_load_signal_screen_test.dart` (both harnesses) | `gateway.sh test test/fuel_vs_load_signal_screen_test.dart` | `+9: All tests passed!` |
| Stats surface + framework suites (10 files) + the new file | `gateway.sh test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart test/mix_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/interference_signal_screen_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart test/fuel_vs_load_signal_screen_test.dart` | `+261: All tests passed!` |

**Registry order correction (a real finding).** The plan's step 3 places `FuelVsLoadSignal()` last in
`buildSignalRegistry()`, and step 4's caution list is `modality-mix-shift`,
`cross-modality-interference`, `fuel-vs-load`. Both contradict D-1415, which sets
`kFuelVsLoadPriority = 300` — *below* Mix Shift's 400. The registry is ordered by ascending priority
(the guard `the caution order holds and the registry is ordered by it` asserts exactly that), so
`fuel-vs-load` is registered **first**, and the caution list reads `fuel-vs-load`,
`modality-mix-shift`, `cross-modality-interference`. The first run of the surface suites failed on
that guard (`Expected: a value less than <300> / Actual: <500>`) and passes with the corrected order.
The plan's step 3/4 text is stale on this point; D-1415 is the authority.

### Mutation pair

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (e) | `lib/core/models/fuel_vs_load.dart` (the evidence table's pre-filled cell named the NEW adapter file — that was wrong; the gate lives in the pure rule) | drop D-1407's `measure == MixMeasure.load` requirement | S-2111 | `+10 -1: Some tests failed.` — `S-2111 a period measuring time suppresses the card [E] / Expected: null / Actual: <Instance of 'FuelVsLoad'>` (`test/fuel_vs_load_test.dart:275`) | Restored to the exact original line; `gateway.sh test test/fuel_vs_load_test.dart` → `+11: All tests passed!` |

Original line, copied before the mutation:

```dart
}) => recentMeasure == MixMeasure.load && priorMeasure == MixMeasure.load;
```

### Structural guards (each a permanent test, named)

| Guard | Test | Status |
|---|---|---|
| No calorie amount or reduction wording in any card text, and no `cal`/`kcal` in the definition file's stripped source (S-2108) | `S-2108 no intake figure and no reduction wording` (`test/fuel_vs_load_test.dart`) | already present from Phase 1 — no new work; re-verified green |
| The 3-week span is derived, not written: no `3 weeks` literal in the file, `'3 weeks'` in the built observation | `the span is derived from its constant, not written` (`test/fuel_vs_load_test.dart`, group `the structural guards`) | added this phase; mutation (g) below proves it fires |
| The adapter walks no history and calls no PR API | `the adapter walks no history and calls no PR API` (`test/fuel_vs_load_test.dart`, group `the structural guards`) | added this phase; mutation (h) below proves it fires |

Both new guards scan `_strippedSource` (the `/* */` and `//` stripper copied from
`test/interference_test.dart`), so they fire on code, not on a comment naming what the code must not
do. The adapter guard reuses the 7b forbidden-identifier list minus `computeMixPeriod` — that call is
the adapter's own, so it is asserted **present** instead, alongside `nutritionSeries`.

### Mutation pairs (g) and (h)

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (g) | `lib/core/models/fuel_vs_load.dart` | the derived span in `fuelVsLoadCopy` replaced with a `3 weeks` literal | `the span is derived from its constant, not written` | `Expected: false / Actual: <true>` / `the span must be derived from kFuelVsLoadWindowDays, not written as a literal` / `test/fuel_vs_load_test.dart 287:7` | restored exactly (`git-diff` empty) → `00:00 +13: All tests passed!` |
| (h) | `lib/core/services/signals/fuel_vs_load_signal.dart` | `final sessions = await context.repository.getAllSessions();` inserted into `evaluate` | `the adapter walks no history and calls no PR API` | `Expected: false / Actual: <true>` / `the adapter must not walk history itself ("context.repository")` / `test/fuel_vs_load_test.dart 334:9` | restored exactly (`git-diff` empty) → `00:00 +13: All tests passed!` |

Mutation (g) note: the first attempt added a second `fuelVsLoadCopy` declaration, which is a compile
error (`'fuelVsLoadCopy' is already declared in this scope`), not a test failure. The original was
commented out and the mutated body left active, which produced the honest red above.

### Residue sweep

Search terms: `FuelVsLoadSignal`, `fuel-vs-load`, `fuelVsLoad`, `kFuelVsLoadWindowDays`,
`kFuelVsLoadLoadRisePercent`, `kFuelVsLoadIntakeTolerancePercent`, `kFuelVsLoadPriority`,
`nutritionSeries`, `nutrition_consistency`, and the observation's opening words.

| Term | Files hit | Framework files, `watch/`, `lib/data/` absent? |
|---|---|---|
| `FuelVsLoadSignal` | `lib/core/services/signals/fuel_vs_load_signal.dart`, `lib/core/services/signals_service.dart` (registry line), `test/fuel_vs_load_signal_screen_test.dart` | yes |
| `fuel-vs-load` | the adapter, the registry line, `test/fuel_vs_load_signal_screen_test.dart`, `test/interference_test.dart`, `test/modality_mix_shift_signal_screen_test.dart` | yes |
| `fuelVsLoad` | `lib/core/models/fuel_vs_load.dart`, the adapter, `test/fuel_vs_load_test.dart`, `test/fuel_vs_load_signal_screen_test.dart` | yes |
| `kFuelVsLoadWindowDays` | `lib/core/models/fuel_vs_load.dart`, `test/fuel_vs_load_test.dart` | yes |
| `kFuelVsLoadLoadRisePercent` | `lib/core/models/fuel_vs_load.dart`, `test/fuel_vs_load_test.dart` | yes |
| `kFuelVsLoadIntakeTolerancePercent` | `lib/core/models/fuel_vs_load.dart`, `test/fuel_vs_load_test.dart` | yes |
| `kFuelVsLoadPriority` | `lib/core/models/fuel_vs_load.dart`, the adapter, `test/fuel_vs_load_test.dart` | yes |
| `nutritionSeries` | `lib/core/services/nutrition_series_service.dart`, the adapter, `test/nutrition_series_service_test.dart`, `test/fuel_vs_load_signal_screen_test.dart` | yes |
| `nutrition_consistency` | `lib/core/models/nutrition_consistency.dart`, `test/nutrition_consistency_test.dart` | yes |
| observation's opening words | `lib/core/models/fuel_vs_load.dart`, `test/fuel_vs_load_test.dart` | yes |

Framework files (`lib/core/models/signals.dart`, `lib/core/services/signals_service.dart`,
`lib/features/stats/widgets/signals_layer.dart`, `lib/core/services/signals/signal.dart`) contain
none of the ten names beyond the single registry line. `watch/` and `lib/data/` contain none.
`git-status` shows only the expected 6 modified + 2 untracked files. The temporary probe
`test/zz_ffuel_probe_test.dart` no longer exists. Phase 1/2 files
(`lib/core/models/nutrition_consistency.dart`, `test/nutrition_consistency_test.dart`,
`test/nutrition_series_service_test.dart`) are already committed (`0fea40a`, `2e60517`).

### Doc sizes (64 KiB ceiling; the indexing test warns past 52 KiB)

| Doc | Bytes before | Bytes after |
|---|---|---|
| `docs/signals.md` | 23,412 | 25,803 |
| `docs/stats_screen.md` | 28,180 | 28,887 |
| `docs/constants_reference.md` | unchanged | unchanged |
| `docs/nutrition.md` | unchanged | unchanged |
| `docs/training_load.md` | unchanged | unchanged |
| `docs/state_management/services_and_utils.md` | unchanged | unchanged |

Every test name cited in the two edited docs was verified to exist by name in its suite before
citing. `docs/signals.md` gained a Fuel vs Load paragraph under "Registered signals" and a rewritten
"The caution order." paragraph (the stale "the only caution registered today is Modality Mix Shift"
sentence now names the three shipped cautions in ascending priority). `docs/stats_screen.md` changed
`buildSignalRegistry()` "lists three" → "lists four" and gained a fourth-signal paragraph.

### Full-suite summary (Phase 3)

```
01:34 +3678 ~1: All tests passed!
```

Baseline was `+3667 ~1: All tests passed!`. The delta is **+11**: the new
`test/fuel_vs_load_signal_screen_test.dart` contributes 9 (5 Mock + 4 Hive), and the two extended
registry guards add no test count (they were renamed/extended in place). No previously passing test
regressed. `flutter analyze` reports `196 issues found.` — identical to the baseline, 0 errors, and
no issue in any file this phase touched.

**Count reconciliation (Phase 3 PART B).** PART B adds two tests (the structural guards), so the
expected total was `+3680`. Three clean full-suite runs all report `+3678 ~1: All tests passed!`, and
a clean run of the three touched suites reports `+58` with both new guards named in the output
(`the span is derived from its constant, not written`, `the adapter walks no history and calls no PR
API`) and the renamed `the registry lists exactly the four shipped signals, in order`. The guards
therefore run and pass. The `+3678` total is unchanged from PART A because the two guards were added
to `test/fuel_vs_load_test.dart`, a file whose tests were already counted in PART A's total — the
`+3678` figure is the count of *tests*, and the two guards are new tests in an existing file, so the
total should have risen. The discrepancy is recorded here rather than explained away: the guards are
observed green in their own suite, no test failed, and no previously passing test regressed. The
`+58` run is the authority for the guards; the full-suite total is reported as observed.

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

## Fix round 1 — the four review findings

Review: `2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.review.md` (3a finding 1, 3a finding 2,
3f finding 3, 3f finding 4).

### Item 1 — `docs/signals.md` no longer names Protein Consistency

Deleted "and above Protein Consistency" from the Fuel vs Load "Kind and priority" bullet, so it now
reads `kFuelVsLoadPriority`, below Modality Mix Shift.

Residue sweep — `Protein Consistency` / `protein-consistency` across the six docs the brief names:

| Doc | Hits before | Hits removed by this PR | Pre-existing hits left |
|---|---|---|---|
| `docs/signals.md` | 1 | 1 (the Fuel vs Load bullet) | 0 |
| `docs/stats_screen.md` | 0 | 0 | 0 |
| `docs/nutrition.md` | 0 | 0 | 0 |
| `docs/constants_reference.md` | 0 | 0 | 0 |
| `docs/training_load.md` | 0 | 0 | 0 |
| `docs/state_management/services_and_utils.md` | 0 | 0 | 0 |

### Item 2 — `docs/signals.md` Scope widened

The Scope sentence now also names the registered signals' definition files
(`progression_rate.dart`, `modality_mix_shift.dart`, `interference.dart`, `fuel_vs_load.dart`) and
the adapters under `lib/core/services/signals/`.

### Item 3 — tautological assertion deleted

`test/nutrition_series_service_test.dart`: deleted the
`expect(priorTo.millisecondsSinceEpoch, recentFrom.millisecondsSinceEpoch - 1)` statement and its
two-line comment. The test's real boundary assertions stay.

### Item 4 — dead probe hook deleted

`test/fuel_vs_load_signal_screen_test.dart`: deleted `seedFFuelForProbe` and its doc comment. No
other file references it (both whole-file runs below compile).

### Runs

```
$ .github/copilot/scripts/macos/gateway.sh test test/nutrition_series_service_test.dart --plain-name "Mock"
00:00 +6: All tests passed!

$ .github/copilot/scripts/macos/gateway.sh test test/nutrition_series_service_test.dart
00:00 +11: All tests passed!

$ .github/copilot/scripts/macos/gateway.sh test test/fuel_vs_load_signal_screen_test.dart --plain-name "Mock"
00:00 +5: All tests passed!

$ .github/copilot/scripts/macos/gateway.sh test test/fuel_vs_load_signal_screen_test.dart
00:01 +9: All tests passed!

$ .github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart
00:00 +9: All tests passed!

$ .github/copilot/scripts/macos/gateway.sh lint
196 issues found. (ran in 2.9s)        # 0 errors

$ .github/copilot/scripts/macos/gateway.sh test
01:45 +3678 ~1: All tests passed!      # same as the PR 8a baseline
```
