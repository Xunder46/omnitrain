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
| `test/protein_consistency_service_test.dart` (new, before the reads exist) | `.github/copilot/scripts/macos/gateway.sh test test/protein_consistency_service_test.dart` | `00:00 +0 -1: Some tests failed.` — `Failed to load ... Compilation failed for testPath=.../test/protein_consistency_service_test.dart: test/protein_consistency_service_test.dart:247:58: Error: The method 'proteinTargetsByDay' isn't defined for the type 'StatsProgressService'.` plus 12 further `The method 'proteinTargetsByDay' / 'resistanceSessionCount' / 'latestBodyWeightKg' isn't defined for the type 'StatsProgressService'.` lines |

### Green runs

| Suite | Command | Output |
|---|---|---|
| `test/protein_consistency_service_test.dart` (after the three reads land) | `.github/copilot/scripts/macos/gateway.sh test test/protein_consistency_service_test.dart` | `00:04 +21: All tests passed!` |
| neighbours: `nutrition_series_service_test.dart`, `interference_test.dart`, `stats_progress_test.dart`, `db_seed_test.dart` | `.github/copilot/scripts/macos/gateway.sh test test/nutrition_series_service_test.dart test/interference_test.dart test/stats_progress_test.dart test/db_seed_test.dart` | `00:19 +112: All tests passed!` |

### Mutation pair

**`lib/core/services/stats_progress_service.dart` — original line, copied before the mutation (an
existing tracked file, so this is its state at the phase's first green run):**

```dart
          if (_sectionForKind(effort.effortKind) ==
              ExerciseSection.resistance) {
```

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (e) | `lib/core/services/stats_progress_service.dart` | the resistance count accepts any effort kind instead of Resistance efforts (`== ExerciseSection.resistance` → `!= null`) | the timed-only fixture (`a session with only timed efforts is not counted`) | failed on **both** factories — `Mock — ... a session with only timed efforts is not counted` and `Hive — ... a session with only timed efforts is not counted`, each `Expected: <0> Actual: <1>` (`00:01 +10 -2: Some tests failed.`) | yes — the line above was put back verbatim and the suite re-ran green (`00:04 +21: All tests passed!`) |

### S-2214 parity detail

The parity test runs one identical fixture through `MockRepositoryHarness` and
`HiveRepositoryHarness`, reduces the four reads to a list of strings, and asserts the two lists are
equal and 28 long (2 series points + 14 target days + 1 count + 1 bodyweight).

| Read | Mock | Hive | Equal |
|---|---|---|---|
| the window's nutrition series | 2 points: day 13 → 120.0 g, day 0 → 130.0 g | identical | ✓ |
| the per-day stored protein targets | 14 days: day 13–7 → 150.0, day 6–0 → 160.0 | identical | ✓ |
| the resistance-session count | 1 | identical | ✓ |
| the latest bodyweight in kilograms | 78.5 | identical | ✓ |
| the fired card's observation and suggestion | _Phase 3 — this phase's parity test compares the four reads only_ | | |

### Full-suite summary (Phase 2)

```
02:00 +3713 ~1: All tests passed!
```

(Phase 1's baseline was `+3692 ~1`; this phase adds the new file's 21 tests. `flutter analyze`
re-ran unchanged at `196 issues found.` with no issue in either file this phase touched.)

Re-ran `test/docs_indexing_contract_test.dart` after the plan and doc edits (the plan grew past the
suite's 80%-of-64 KiB warning threshold at 52 429 bytes): `00:00 +30: All tests passed!` with the plan
at 51 892 bytes and the evidence file at 11 868 — both still under the threshold, with ~500 bytes of
headroom left on the plan before Phase 3's additions.

## Phase 3 — the card, the registry line, the guards

### Fixture math (worked out before the test was written)

`day(n)` = local midnight n days before today; the rule's window is `day(13)`…`day(0)`
(`kProteinConsistencyWindowDays = 14`) and its own baseline is the eight 7-day blocks
`[69-63] … [20-14]` (`weekBlockStarts(anchorDay: day(14), weeks: 8)`).

**F-PROT (S-2216, target mode).** Load = 8a's `_seedLoad` + `_seedPeriod(daysAgo: 20)`; food =
`_clearConsumedFoods` then 12 rows on `day(13)`…`day(2)`, protein 120 g each (calories 2,040 →
carbs 390, `4 × (120 + 390) = 2040`); target 150 g stored once on `day(13)`
(`saveNutritionTargetForDate` walks backward, so `day(13)`…`day(0)` all read 150).

| Gate | Figure | Threshold | Verdict |
|---|---|---|---|
| logged days in the window | 12 | ≥ 10 | pass |
| resistance sessions in the window | 3 (`day(12)`, `day(8)`, `day(4)`) | ≥ 2 | pass |
| every window day has a positive target | 14 of 14 at 150 | all | target mode |
| shortfall vs target | `20 × 1440 = 28,800` | `≤ 17 × 2100 = 35,700` | fires, `p = 20` |
| Fuel vs Load's six-block gate | ≤ 3 of 7 in every block | 5 of 7 | abstains |
| Mix layer's rated baseline | 7 rated blocks | ≥ 4 | gate met |

Copy: average 120, comparison 150, perKg null →
`Protein has averaged 120 g/day over the last 2 weeks, about 20% under your 150 g target.`
+ `Bringing protein back toward your target is one option.`

**F-OWN (own baseline + bodyweight).** Same load and period; 12 rows on `day(13)`…`day(2)` at 118 g;
no target; baseline rows at 145 g — `[69-63]` and `[62-56]` 7 of 7, the other six blocks 3 of 7
(`day(55,54,53)`, `day(48,47,46)`, `day(41,40,39)`, `day(34,33,32)`, `day(27,26,25)`,
`day(20,19,18)`); bodyweight 70 kg on `unit-kg`.

| Gate | Figure | Threshold | Verdict |
|---|---|---|---|
| consistent baseline blocks | 2 | ≥ 2 | pass |
| shortfall vs baseline | `100 × 1416 × 14 = 1,982,400` | `≤ 83 × 2030 × 12 = 2,021,880` | fires |
| per-kg | `118 / 70 = 1.686 → 1.7` | — | renders |

Copy: `Protein has averaged 118 g/day (1.7 g/kg) over the last 2 weeks, down from your usual 145 g.`
+ `Commonly cited guidance for strength training is around 1.6 g/kg of bodyweight.`

**F-OWN-NBW (S-2207).** F-OWN without the measurement → same observation minus ` (1.7 g/kg)`, and
`suggestion == null` (`proteinConsistencyCopy`'s third branch), so no second line renders.

**F-MERGED (S-2215).** `_seedLoad` + `_seedPeriod(20)` + 42 rows (`day(41)`…`day(0)`; 2,040 cal on
`day(20)`…`day(0)`, 2,000 cal on `day(41)`…`day(21)`; protein 120 g throughout) + target 150 g on
`day(13)`…`day(0)` (stored once on `day(13)`).

| Gate | Figure | Threshold | Verdict |
|---|---|---|---|
| Fuel vs Load six blocks | 7 of 7 in all six | 5 of 7 | fires |
| Fuel vs Load intake rise | 2040 / 2000 = +2% | ≤ 5% | fires |
| Protein window logged days | 14 | ≥ 10 | pass |
| Protein shortfall vs target | `20 × 1680 = 33,600` | `≤ 17 × 2100 = 35,700` | fires, `p = 20` |

**Finding (S-2215, see the Assumption Log and Open items):** two cautions qualify, and
`resolveSignals` renders the top `kSignalMaxCards = 2` of a single kind
(`lib/core/models/signals.dart`, pinned by `test/signals_layer_screen_test.dart`'s
"the top two cautions render, in priority order"). The plan's S-2215 expectation — "exactly one
card, Fuel vs Load" — is therefore unreachable without editing a frozen framework file, which
D-1518 and the brief forbid. The screen test pins the reachable contract instead: Fuel vs Load
(300) renders above Protein Consistency (200), and dismissing Fuel vs Load leaves the Protein
Consistency card on screen with S-2201's copy.

### Red runs

| Suite | Command | Output |
|---|---|---|
| `test/protein_consistency_signal_screen_test.dart` (before the adapter exists) | `gateway.sh test test/protein_consistency_signal_screen_test.dart --plain-name "Mock"` | `00:00 +0 -1: Some tests failed.` — the file does not load: `Error when reading 'lib/core/services/signals/protein_consistency_signal.dart': No such file or directory` and `Couldn't find constructor 'ProteinConsistencySignal'` (lines 45 and 770 of the new file) |
| `test/protein_consistency_signal_screen_test.dart` (adapter present, before the registry line) | `gateway.sh test test/protein_consistency_signal_screen_test.dart --plain-name "Mock"` | `00:01 +3 -6: Some tests failed.` — the six card-present scenarios fail with `Found 0 widgets with key [<'signal_card_protein-consistency'>]` at lines 563, 616, 650, 669, 697, 717 (S-2216 ×2, S-2206, S-2207, S-2215 ×2). The three that do not need the registry — both abstentions and the adapter group — already pass, which is what pins the adapter's reads and its copy before the registry line lands. |

### Green runs

| Suite | Command | Output |
|---|---|---|
| `test/protein_consistency_signal_screen_test.dart` (whole file, Mock then Hive) | `gateway.sh test test/protein_consistency_signal_screen_test.dart` | `00:01 +16: All tests passed!` — 9 Mock + 7 Hive; the Hive harness skips the two tap scenarios, as the pattern requires |
| the two re-applied registry guards | `gateway.sh test test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart --plain-name "registry"` | `00:00 +2: All tests passed!` — `the caution order holds and the registry is ordered by it` and `the registry lists exactly the five shipped signals, in order` |
| the surface/framework set (11 files) | `gateway.sh test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart test/fuel_vs_load_signal_screen_test.dart test/mix_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/interference_signal_screen_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart` | `00:06 +261: All tests passed!` — no screen-overflow or surface-height change was needed, and no framework or service test moved |
| S-2211, after the mutation was restored | `gateway.sh test test/protein_consistency_test.dart --plain-name "S-2211"` | green again (see the mutation pair) |

### Mutation pair

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (f) | `lib/core/models/protein_consistency.dart` line 139, in `proteinConsistencyTargetMode` — **temporarily** mutated and restored; the frozen-file rule forbids leaving it edited | target mode accepted when only some logged days carry a positive target: `if (target == null || target <= 0) return false;` → `if (target == null || target <= 0) continue;` (original line copied below before applying) | S-2211 | `gateway.sh test test/protein_consistency_test.dart --plain-name "S-2211"` → `00:00 +0 -1: Some tests failed.` — `Expected: <false> Actual: <true>` at the `proteinConsistencyTargetMode(...)` expectation (line 385); the rule then also reports `target` mode where S-2211 pins `ownBaseline` | yes — the exact original line was re-applied and S-2211 re-ran green |

Original line, copied verbatim before the mutation was applied:

```dart
    if (target == null || target <= 0) return false;
```

Verification that the file was restored byte-for-byte: `gateway.sh git-diff -- lib/core/models/protein_consistency.dart` printed nothing (the file is unchanged against `HEAD`).

### Structural guards (each a permanent test, named)

| Guard | Test | Status |
|---|---|---|
| No calorie amount or reduction wording in any card text; whole grams, one decimal only for g/kg; no `cal`/`kcal`/`1.6` literal in the definition file's stripped source (S-2213) | `S-2213 the unit conventions and the hard rules` — `test/protein_consistency_test.dart` | present from Phase 1 (carries the `_strippedSource` scan); confirmed, not edited |
| The 2-week span and the 1.6 reference are derived, not written | `the span and the reference are derived, not written` — `test/protein_consistency_test.dart` | **added in step 7** |
| The adapter walks no history and calls no PR API | `the adapter walks no history and calls no PR API` — `test/protein_consistency_test.dart` | **added in step 7** |
| A null suggestion renders without an empty second line (S-2207) | `with no bodyweight drops the g/kg figure and renders no second line at all` — `test/protein_consistency_signal_screen_test.dart` | present from Phase 3 step 1; confirmed, not edited |

### Residue sweep

Search terms: `ProteinConsistencySignal`, `protein-consistency`, `proteinConsistency`,
`kProteinConsistencyWindowDays`, `kProteinConsistencyMinLoggedDays`,
`kProteinConsistencyShortfallPercent`, `kProteinConsistencyMinResistanceSessions`,
`kProteinConsistencyMinBaselineWeeks`, `kProteinConsistencyBaselineWeeks`, `kProteinGuidancePerKg`,
`kProteinConsistencyPriority`, and the observation's opening words.

| Term | Files hit | Framework files, `watch/`, `lib/data/` absent? |
|---|---|---|
| `ProteinConsistencySignal` | `lib/core/services/signals/protein_consistency_signal.dart` (declared), `lib/core/services/signals/signal_registry.dart` (the registry line), `test/protein_consistency_signal_screen_test.dart`, `docs/signals.md` | yes — none of the four is a framework file, and none is under `watch/`, `lib/data/` or `lib/features/` |
| `protein-consistency` (the id and the card key) | `lib/core/services/signals/protein_consistency_signal.dart` (the id), `test/interference_test.dart` and `test/modality_mix_shift_signal_screen_test.dart` (the two registry guards' id lists), `test/protein_consistency_signal_screen_test.dart` (the card key and the dismissal assertions), `docs/state_management/services_and_utils.md` (the caution named by id) | yes |
| `proteinConsistency` (the rule's function prefix) | `lib/core/models/protein_consistency.dart`, `lib/core/services/signals/protein_consistency_signal.dart`, `test/protein_consistency_test.dart`, `test/protein_consistency_signal_screen_test.dart`, `test/protein_consistency_service_test.dart`, `docs/signals.md` (names `proteinConsistencyCopy`) | yes |
| the eight `kProteinConsistency…` / `kProteinGuidancePerKg` constants | `lib/core/models/protein_consistency.dart` (defined), `lib/core/services/signals/protein_consistency_signal.dart` (the window and baseline arithmetic), `test/protein_consistency_test.dart` (the constant contract), `docs/constants_reference.md` (the only document that lists them) | yes |
| the observation's opening words (`Protein has averaged`) | `lib/core/models/protein_consistency.dart` (the one place the string is written), `test/protein_consistency_signal_screen_test.dart`, `docs/signals.md` | yes |
| `ProteinDay`, `proteinTargetsByDay`, `resistanceSessionCount`, `latestBodyWeightKg` | `lib/core/models/protein_consistency.dart` and `lib/core/services/signals/protein_consistency_signal.dart`; the three reads also in `lib/core/services/stats_progress_service.dart` (the declarations), `docs/state_management/services_and_utils.md` (documented), the three new test files | yes |

**Method.** The gateway exposes no search verb, so the sweep was derived instead of grepped: the
footprint is exhaustive (`gateway.sh git-diff 73afe76 --name-status` → 16 files, and `git-status`
adds the two untracked ones, which `git diff` cannot show), and each of the six edited files' patches
was read in full to place every introduced name. Every hit above lands inside that footprint; the
three new suites name the rule's symbols, copy and card key in their fixtures and assertions. No
framework file (`lib/core/models/signals.dart`, `lib/core/services/signals_service.dart`,
`lib/core/services/signals/signal.dart`, `lib/features/stats/widgets/signals_layer.dart`), no
`watch/`, `lib/data/` or `lib/features/` file, no 8a file and neither `test/mix_layer_screen_test.dart`
nor `test/fuel_vs_load_signal_screen_test.dart` appears in the footprint — so no term can reach them.

### Doc sizes (64 KiB ceiling; the indexing test warns past 52 KiB)

| Doc | Changed lines in this phase (`git-diff --stat`) | Byte size | Indexing contract |
|---|---|---|---|
| `docs/signals.md` | 131 | not observable | ceiling and warning-band guards pass |
| `docs/stats_screen.md` | 19 | not observable | pass |
| `docs/nutrition.md` | 12 | not observable | pass |
| `docs/constants_reference.md` | 0 in the working tree — its 8b edit is already committed | not observable | pass |
| `docs/state_management/services_and_utils.md` | 0 in the working tree — already committed | not observable | pass |

Byte sizes are not observable with the permitted verbs (the gateway has no size or search verb), so the
contract is evidenced by its own guards instead: `gateway.sh test test/docs_indexing_contract_test.dart`
→ `00:00 +9: All tests passed!`, including `no documentation file exceeds the indexing ceiling`,
`no documentation file is within the warning band of the ceiling`, `every relative link resolves to a
file that exists`, `every doc page is reachable from another doc page` and
`no document carries a step-by-step flow walkthrough`. The three edited docs total
`151 insertions(+), 11 deletions(-)` for the phase.

### Full-suite summary (Phase 3)

```
01:50 +3729 ~1: All tests passed!
```

Phase 2's baseline was `+3713 ~1: All tests passed!`, so the delta is exactly **+16** — the new
screen suite (9 Mock + 7 Hive). The two registry guards were edits to existing tests, so they add
no count; the `~1` skip is the same pre-existing one. `gateway.sh lint` reports
`196 issues found.` with 0 errors — identical to the baseline, and no issue names a touched file
(`grep protein_consistency` over the analyzer output is empty).

## Phase 3 — steps 7–9 (structural guards, residue sweep, docs)

### Step 7 — structural guards

The four guards the brief names, and where each lives:

| Guard | Test (exact name) | File | Status |
|---|---|---|---|
| (a) No calorie amount or reduction wording in any card text; whole grams, one decimal only for g/kg; no `cal`/`kcal`/`1.6` literal in the definition file's stripped source (S-2213) | `S-2213 the unit conventions and the hard rules` | `test/protein_consistency_test.dart` | **already present** (written in Phase 1) — confirmed by name, no edit needed; it already carries the `_strippedSource` scan of `lib/core/models/protein_consistency.dart` |
| (b) The 2-week span and the 1.6 reference are derived, not written | `the span and the reference are derived, not written` | `test/protein_consistency_test.dart` | **new** (step 7b) |
| (c) The adapter walks no history and calls no PR API | `the adapter walks no history and calls no PR API` | `test/protein_consistency_test.dart` | **new** (step 7c) |
| (d) A card with a null suggestion renders without an empty second line (S-2207) | `drops the g/kg figure and renders no second line at all` | `test/protein_consistency_signal_screen_test.dart` | **already present** (written in Phase 3 step 1) — confirmed by name, no edit needed |

Guards (b) and (c) passed on their first run (they guard code already shipped in Phases 1–3), so each
gets a mutation that makes it fail, per the red-first rule.

### Mutation pairs (step 7)

**Original line, copied before the guard-(b) mutation (the file is the frozen Phase 1 model; this is its
committed state):**

```dart
        'Protein has averaged $average g/day$perKg over the last $span weeks, '
```

**Original line, copied before the guard-(c) mutation (the adapter is a NEW, untracked file, so the
restore is provable from this file alone):**

```dart
    final bodyWeightKg = await context.progressService.latestBodyWeightKg();
```

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (g) | `lib/core/models/protein_consistency.dart` (frozen file — mutated then restored; the original line is copied above) | the observation writes the span as a `2 weeks` literal instead of interpolating `$span` (`kProteinConsistencyWindowDays ~/ 7`) | `the span and the reference are derived, not written` | `00:00 +0 -1: Some tests failed.` — the stripped source now contains `2 weeks`; `Expected: not contains '2 weeks'` at `test/protein_consistency_test.dart 509:5`, reason *the span must be derived from kProteinConsistencyWindowDays, not written as a literal* | yes — the exact original line was re-applied; the guard re-ran green (`00:00 +1: All tests passed!`) and `gateway.sh git-diff -- lib/core/models/protein_consistency.dart` printed nothing |
| (h) | `lib/core/services/signals/protein_consistency_signal.dart` (NEW, untracked — original line copied above) | the adapter gains a repository read: `await context.repository.getAllSessions();` inserted after the bodyweight read | `the adapter walks no history and calls no PR API` | `00:00 +0 -1: Some tests failed.` — `Expected: false / Actual: <true>` at `test/protein_consistency_test.dart 568:7`, reason *the adapter must not walk history itself ("context.repository"); it calls the four service reads and nothing else (D-1519)* (the inserted line trips the first banned identifier, `context.repository`) | yes — the inserted line was removed and the whole suite re-ran green (`00:00 +16: All tests passed!`) |

### Step 8 — residue sweep

Run as described under **Residue sweep** above: no term leaves the 16-file footprint, and no framework
file, `watch/`, `lib/data/`, `lib/features/` or 8a file is in it. Nothing was found to clean up.

### Step 9 — docs

| Doc | Change | Why it was false or incomplete before |
|---|---|---|
| `docs/signals.md` | Scope list gains the definition file; "The caution order." becomes **four** cautions with Protein Consistency first; a Protein Consistency paragraph joins "Registered signals" (window, logged-days gate, resistance gate, two comparison modes and no third, own baseline, shortfall test, per-kilogram figure, kind and priority, copy), plus a paragraph on both cautions rendering together and one on the adapter; Related Documentation gains Nutrition | the doc listed three cautions, and the registry now ships five signals |
| `docs/stats_screen.md` | "lists five" instead of four, plus a paragraph naming the fifth signal's card | the registry line changed the count |
| `docs/nutrition.md` | the per-day-target paragraph now states that the shipped target screen is calories-only and writes a protein target of zero, so Protein Consistency always compares against the user's own usual level; cites `test/nutrition_test.dart` | the F-1 consequence was unstated, and the doc's protein section read as though a target could exist |

Two plan texts were corrected rather than implemented: the "three cautions" list, and S-2215's
"exactly one card, Fuel vs Load" (see the Phase 2 finding). No test was relaxed to accommodate either.

### Final verification (steps 7–9)

| Check | Command | Result |
|---|---|---|
| lint, whole tree | `gateway.sh lint` | `196 issues found. (ran in 2.9s)` — identical to the opening baseline |
| lint, touched paths only | `gateway.sh lint lib/core/services/signals lib/core/models test/protein_consistency_test.dart test/protein_consistency_signal_screen_test.dart test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart` | `No issues found! (ran in 1.1s)` — no touched file carries an issue of any severity, so all 196 belong to the untouched pre-existing set |
| Phase 3 Done-Criteria suites (8 files) | `gateway.sh test test/protein_consistency_signal_screen_test.dart test/protein_consistency_test.dart test/protein_consistency_service_test.dart test/fuel_vs_load_signal_screen_test.dart test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart test/signals_layer_screen_test.dart test/docs_indexing_contract_test.dart` | `00:04 +161: All tests passed!` |
| full suite | `gateway.sh test` | `01:44 +3731 ~1: All tests passed!`, and again on the final tree after the plan and evidence edits: `02:00 +3731 ~1: All tests passed!` |

The full-suite total moved from Phase 2's `+3713` to Part A's `+3729` (the 16-test screen suite) and to
`+3731` here — exactly the two step-7 guards. No previously passing test fails, and the `~1` skip is the
same pre-existing one.

## Plan size, measured

| Measure | Predicted | Measured |
|---|---|---|
| Plan lines | 666 | not observable — the gateway exposes no line-count verb |
| Ledger decisions | 19 | 19 — `D-1501`…`D-1519`, counted from the plan's Decision Ledger |
| Scenarios | 16 | 16 — `S-2201`…`S-2216` |
| Production lines added | ~270 | `lib/core/models/protein_consistency.dart` 360 and `lib/core/services/stats_progress_service.dart` 65 (`git-diff 73afe76 --stat`), the registry line `2 insertions(+)`; the adapter is untracked, so no diff reports its length |
| Files deleted | 0 | 0 — `git-diff 73afe76 --name-status` lists 14 tracked entries, all `A` or `M`, plus the 2 untracked files `git diff` cannot show |
