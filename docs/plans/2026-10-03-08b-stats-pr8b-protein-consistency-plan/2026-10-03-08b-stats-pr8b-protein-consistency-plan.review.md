# Review: Stats PR 8b
Status: complete

Base commit `73afe76`. Footprint: 14 tracked files (all `A`/`M`) plus the two untracked new files
`lib/core/services/signals/protein_consistency_signal.dart` and
`test/protein_consistency_signal_screen_test.dart`.

## Findings

### 1. DOC CLAIMS — checked, no finding

`docs/signals.md`, `docs/stats_screen.md`, `docs/nutrition.md`, `docs/constants_reference.md`,
`docs/state_management/services_and_utils.md`.

- Every cited test name resolves exactly (group names plus the test's own name) in the file it names:
  - `test/protein_consistency_test.dart` — `S-2210`, `S-2211`, `S-2205`, `S-2212`,
    `S-2213 the unit conventions and the hard rules`,
    `the span and the reference are derived, not written`,
    `the adapter walks no history and calls no PR API`.
  - `test/protein_consistency_service_test.dart` — `proteinTargetsByDay inherits the last stored
    target forward`, `a day before any stored target is absent`.
  - `test/protein_consistency_signal_screen_test.dart` —
    `drops the g/kg figure and renders no second line at all`.
  - `test/nutrition_test.dart` — group `NutritionTargetScreen — calories only (D-3 / S-040)` (line 55)
    plus test `save builds a macros-0 target (D-3)` (line 102); the citation matches character for
    character.
  - `test/nutrition_consistency_test.dart`, `test/fuel_vs_load_test.dart`,
    `test/signals_layer_screen_test.dart` — every name cited resolves.
- Every named type, constant and function exists in `lib/`: `proteinConsistency`,
  `proteinConsistencyCopy`, `proteinConsistencyGate`, `proteinConsistencyTargetMode`,
  `ProteinDay`, `ProteinConsistency`, `ProteinComparisonMode`, the eight `kProteinConsistency…`
  constants, `kProteinGuidancePerKg`, `weekBlockStarts`, `isConsistentWeek`,
  `kConsistentWeekMinLoggedDays`, `proteinTargetsByDay`, `resistanceSessionCount`,
  `latestBodyWeightKg`.
- No document names an unshipped signal: neither `Sustained High Load` nor
  `Cardio Efficiency Drift` appears in any of the five; `docs/signals.md`'s inventory and
  `docs/stats_screen.md` ("lists five") name only the five shipped signals.
- No document claims a surface that does not exist.
- `docs/signals.md` states that the two cautions can render together (the S-2215 reality), and
  `docs/nutrition.md` states the shipped daily target screen is calories-only and writes a protein
  target of zero, so the card always compares with the user's own usual level.
- **minor** — the unshipped-name check could not be a whole-text search (the gateway exposes no
  search verb), so it rests on reading each document's signal inventory and every changed region
  rather than every line of all five.

### 2. TONE / HARD RULES — checked, no finding

`lib/core/models/protein_consistency.dart`; `test/protein_consistency_test.dart` (`S-2213`).

- No card text carries a calorie amount (`\d+\s*(cal|kcal|calorie)`) or wording that suggests eating
  less (`eat less`, `eat fewer`, `reduce`, `cut back`, `lower your intake`) — asserted over every
  card the rule can produce.
- Protein figures are whole grams; the only decimal in an observation is the per-kilogram one, and
  the guard asserts the decimal match list is exactly `['1.7']`.
- The `1.6 g/kg` reference renders only in the no-target branch and only when a bodyweight is on file
  (S-2206). S-2207 (no bodyweight) pins `suggestion == null`, and the `1.6` string is absent from the
  definition file's stripped source because the value is `kProteinGuidancePerKg = 8 / 5`.
- A card with neither a target nor a bodyweight produces no suggestion, so no second line renders.

### 3. THE RULE — `lib/core/models/protein_consistency.dart` — checked, no finding

Against D-1502…D-1517 and the owner's answer (own baseline needs at least 2 consistent weeks of 8):

- D-1502/D-1503: calendar-day arithmetic, and a day counts only when it carries a logged row.
- D-1504: `recentDays.length >= 10` — exactly 10 of 14 passes.
- D-1506/D-1507: target mode requires every logged day's stored target to be positive; otherwise the
  rule falls back to the own baseline (no third mode). The target figure is the mean of the window's
  logged days' targets, not the most recent one.
- D-1508: inclusive shortfall via exact cross-multiplication on unrounded totals — target
  `100*recentTotal <= 85*targetSum`, own baseline
  `100*recentTotal*usualDays <= 85*usualTotal*recentDays`. Exactly 15% under fires; 13% does not.
- D-1505/D-1509: eight 7-day blocks abutting the window, blocks with ≥5 of 7 logged days contribute,
  ≥2 such blocks required, and their logged days pool into one mean (the divisor is logged days, never
  the window length).
- D-1510 resistance gate `>= 2`; D-1511 latest bodyweight in `unit-kg`; D-1512…D-1516 copy;
  D-1517 per-kilogram figure to one decimal.

### 4. THE SERVICE READS — `lib/core/services/stats_progress_service.dart` — checked, no finding

`proteinTargetsByDay` (1849), `resistanceSessionCount` (1875), `latestBodyWeightKg` (1902).

- Reuses the existing per-day repository lookup (`getNutritionTargetForDate`), the existing
  `_sessionInWindow` (2269) walk and the existing resistance rule
  (`_sectionForKind` (1346) `== ExerciseSection.resistance`), and `getLatestMeasurement('bodyweight')`
  filtered to `MetricIds.unitKg`.
- No repository method was added — `lib/data/repositories/workout_repository.dart` is not in the diff.
- Calendar arithmetic throughout; no `Duration`-based day stepping.

### 5. THE ADAPTER — `lib/core/services/signals/protein_consistency_signal.dart` — checked, no finding

- The 14-day window and the eight baseline blocks are derived from `context.now` with calendar
  arithmetic (`weekBlockStarts(anchorDay: windowStart - 1, weeks: 8)`, giving `day(69)…day(20)`).
- Exactly one `nutritionSeries` read, from the baseline start (`today − 69`), split at the window's
  first day — no second read and no history walk.
- The four reads all go through `context.progressService`; no repository access and no PR call
  (pinned by the adapter guard).

### 6. SCOPE — checked, no finding

- `git-diff 73afe76 --name-status`: 14 tracked entries, all `A`/`M`, plus the two untracked new files
  — exactly the plan's Predicted Files footprint across all three phases.
- No framework file (`lib/core/models/signals.dart`, `lib/core/services/signals_service.dart`,
  `lib/core/services/signals/signal.dart`, `lib/features/stats/widgets/signals_layer.dart`), no 8a
  file, no `lib/data/`, no `watch/` in the footprint.
- The two existing registry guards changed by a handful of lines only: `test/interference_test.dart`
  +1 line (the id list) and `test/modality_mix_shift_signal_screen_test.dart` 1 insertion /
  2 deletions (the count and the id list).
- `lib/core/services/signals/signal_registry.dart` lists `ProteinConsistencySignal()` first, and both
  guards pin the id order with `protein-consistency` at the head.

### 7. TESTS CAN FAIL — checked, no finding

- Every new suite has a recorded red run in the evidence file: the three new suites failed to compile
  before their code existed, and the screen suite has a meaningful red run (`+3 -6`, the six
  card-present scenarios failing on a missing `signal_card_protein-consistency` key) recorded
  *before* the registry line landed.
- Eight mutation pairs (a)–(h) are recorded, each with the failing assertion, the observed output and
  a byte-for-byte restore; (g) and (h) were run against the frozen model and the new adapter.
- **No assertion that cannot fail was found.** The copy assertions compare against literal strings
  declared in the test files, never against the production copy function; the structural guards scan
  stripped source with both a positive set (the four service reads must appear) and a negative set
  (the banned identifiers must not); the registry guards assert exact id lists.
- **minor** — the two registry-guard edits have no red run of their own recorded (their red run would
  have required the expected list to be edited before the registry line landed). Their assertions are
  falsifiable by construction, so this is a bookkeeping gap, not a test-quality one.

### 8. VERIFICATION — observed output (reviewer's own runs, this session)

- Six targeted suites (`protein_consistency_test.dart`, `protein_consistency_service_test.dart`,
  `protein_consistency_signal_screen_test.dart`, `interference_test.dart`,
  `modality_mix_shift_signal_screen_test.dart`, `docs_indexing_contract_test.dart`) →
  `00:02 +107: All tests passed!`
- `lint` → `196 issues found. (ran in 2.8s)`, with no `error •` line — identical to the evidence
  file's baseline, so no touched file carries a new issue.
- Full suite, run 1 → `01:46 +3730 ~1 -1: Some tests failed.` — the single failure is
  `test/food_photo_clear_legacy_edit_test.dart` "clearing a legacy library food's photo persists
  without a Save tap" (line 149, `Expected: null / Actual: '7e88d4b6-…jpg'`).
- That file alone → `+1: All tests passed!`; full suite, run 2 → `01:52 +3731 ~1: All tests passed!`,
  matching the evidence file.
- **minor** — `test/food_photo_clear_legacy_edit_test.dart` is order/timing dependent in the full
  suite (it fails in one run, passes alone and on the full-suite re-run). It is not in PR 8b's
  footprint and does not exercise protein consistency, so it is not a blocker here; it belongs in a
  separate flake report.

## Verdict

**APPROVE.** All seven brief items pass: the docs' claims resolve and name nothing unshipped; the
card's tone and unit rules hold; the rule matches D-1502…D-1517 with inclusive boundaries and exact
cross-multiplication; the three service reads reuse the existing lookups and rules; the adapter is a
thin `progressService`-only read; the footprint is exactly the plan's; and every new suite and guard
has a recorded red run or mutation with no unfalsifiable assertion.

Two minor bookkeeping notes only (an unrecorded red run for the two registry-guard edits, and one
unrelated order-dependent test in the full suite), neither blocking.

The plan's own S-2215 defect is handled correctly: the unreachable "exactly one card" expectation is
logged in the evidence file and the screen test pins the reachable contract instead, with no framework
file edited and no assertion relaxed.
