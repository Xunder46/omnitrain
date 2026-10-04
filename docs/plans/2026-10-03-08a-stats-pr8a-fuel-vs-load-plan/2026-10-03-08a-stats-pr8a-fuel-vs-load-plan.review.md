# Review: Stats PR 8a

Status: complete

Reviewed `git diff 627199f` (base `627199f` + committed `0fea40a`, `2e60517` + the Phase 3 working
tree). Observed runs, not inferred:
`test/fuel_vs_load_test.dart test/nutrition_consistency_test.dart test/nutrition_series_service_test.dart
test/fuel_vs_load_signal_screen_test.dart test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart`
→ `00:02 +86: All tests passed!`; full suite → `01:49 +3678 ~1: All tests passed!`.

## 3a DOC CLAIMS

1. **major** — `docs/signals.md:387` — the Fuel vs Load "Kind and priority" bullet ends "below
   Modality Mix Shift and above **Protein Consistency**", but no Protein Consistency signal exists in
   the shipped product: `lib/core/models/` holds no `protein_consistency*.dart`,
   `lib/core/services/signals/` holds no protein adapter, no `kProteinConsistencyPriority` is defined
   in `lib/` (no constants file carries it), and `buildSignalRegistry()` lists four signals, none
   protein-related. The same document's caution-order paragraph (`docs/signals.md:64`) says "Three
   cautions are registered today", so the doc contradicts itself; the plan's D-1415 attributes Protein
   Consistency to 8b, which is unshipped. → delete "and above Protein Consistency" (or name only
   registered signals). A reference doc naming a non-existent entity, and a planned-work/unshipped
   note (prohibited class 6/7), actively misleads the next reader into "restoring" a signal.
2. **minor** — `docs/signals.md:3` — the Scope declaration covers only the four framework files
   (`signals.dart`, `signal.dart`, `signal_registry.dart`, `signals_service.dart`), while the doc's
   "Registered signals" section (from `docs/signals.md:156`) documents concrete rules and adapters:
   `progression_rate.dart`, `modality_mix_shift.dart`/`modality_mix_shift_signal.dart`,
   `interference.dart`/`interference_signal.dart` and now `fuel_vs_load.dart`/
   `fuel_vs_load_signal.dart`. The scope under-claims (pre-existing pattern, extended by this PR) →
   widen the Scope line, or give the registered-signal sections their own declared scope. Verified
   anyway, so nothing is unchecked.
3. **checked, no finding** — every other cited test name exists exactly in the named file, and every
   other named type/constant/function exists in `lib/`:
   - `docs/signals.md` Fuel vs Load block: `S-2101`, `S-2107`, `S-2102`, `S-2111`, `S-2103`,
     `S-2104`, `S-2109`, `S-2110`, `S-2105`, `S-2106`, `S-2108`, `the span is derived from its
     constant, not written`, `the constant contracts`, `the adapter`, `the adapter walks no history
     and calls no PR API` — all present in `test/fuel_vs_load_test.dart`,
     `test/nutrition_consistency_test.dart` and `test/fuel_vs_load_signal_screen_test.dart`;
     `the caution order holds and the registry is ordered by it` present in `test/interference_test.dart`;
     `the constant contracts` present in `test/modality_mix_shift_test.dart`. Named symbols exist:
     `fuelVsLoad`, `fuelVsLoadCopy`, `FuelVsLoadSignal`, `kFuelVsLoadWindowDays`,
     `kFuelVsLoadLoadRisePercent`, `kFuelVsLoadIntakeTolerancePercent`, `kFuelVsLoadPriority`,
     `kWeekDays`, `kConsistentWeekMinLoggedDays`, `MixMeasure.load`/`.time`,
     `MixLayerData.segments[].measure`, `StatsProgressService.computeMixPeriod`/`nutritionSeries`,
     `NutritionTrendPoint.date`/`calories`/`protein`/`carbs`/`fat`.
   - `docs/constants_reference.md`: both new groups name `lib/core/models/nutrition_consistency.dart`
     and `lib/core/models/fuel_vs_load.dart` (both exist) and the two suites' `the constant contracts`
     (both exist — added by Phase 1 Fix 1 for exactly this reason). The tables restate no value, so
     §3.4 holds.
   - `docs/nutrition.md`: the four `nutritionSeries` names exist in
     `test/nutrition_series_service_test.dart`; `test/stats_progress_test.dart` and
     `test/nutrition_trend_screen_test.dart` exist.
   - `docs/training_load.md`: `S-1904a`, `S-1907`, `S-1913` exist in
     `test/modality_mix_period_service_test.dart` (verified by reading the file, not by the run);
     the two `S-2112` names exist in `test/nutrition_series_service_test.dart`.
   - `docs/state_management/services_and_utils.md`: all six cited names exist; the signature it states
     (`required DateTime fromMs`, `required DateTime toMs`) matches the declaration exactly.
   - `docs/stats_screen.md`: "lists four" matches the registry; the fourth-signal paragraph's
     `S-2113` and the two `fuel_vs_load` files exist (the `S-2113` citation follows the same
     group-id form as the pre-existing `S-2013` sentence beside it).

## 3b TONE / HARD RULES

**checked, no finding.** `fuelVsLoadCopy`'s observation is the owner-approved sentence verbatim —
`'Training load is up $p% over the last ${kFuelVsLoadWindowDays ~/ 7} weeks; your average daily
intake has not risen with it.'` (D-1412) — and the suggestion is the pack's text verbatim,
`'Worth checking that intake is keeping up with training.'` (D-1413). No card text carries a calorie
amount, a calorie target or any eating-less wording: S-2108 asserts both the card's own strings and a
stripped-source scan of the definition file for `cal`/`kcal`; the observation names no intake figure
at all. There is no reverse version — `fuelVsLoadLoadTest` is one-directional
(`100 * recentLoad >= (100 + 20) * priorLoad`), so a falling load can never fire, and S-2109 asserts
a −30% load with flat intake produces null.

## 3c THE RULE (`lib/core/models/fuel_vs_load.dart` vs D-1405…D-1411)

**checked, no finding.** Constants `kFuelVsLoadWindowDays = 21`,
`kFuelVsLoadLoadRisePercent = 20`, `kFuelVsLoadIntakeTolerancePercent = 5`,
`kFuelVsLoadPriority = 300`. The two tests are exact integer cross-multiplications on the totals, with
no rounding anywhere in the fire path (`p` is rounded only for the copy, D-1412):
`100 * recentLoad >= 120 * priorLoad` (≡ D-1408's `5×recent >= 6×prior`) and
`100 * recentTotal * priorDays <= 105 * priorTotal * recentDays` (≡ D-1410's
`20×recentTotal×priorDays <= 21×priorTotal×recentDays`). Both boundaries are inclusive and both are
paired with a just-outside case: S-2104 exactly +20% fires / S-2103 +19% does not; S-2105 exactly +5%
intake fires / S-2106 +6% does not. The six-block gate is `weekBlockStarts(anchor, weeks: 6)` →
starts `[−41, −34, −27, −20, −13, −6]`, which tiles the two periods exactly, and one block under
`kConsistentWeekMinLoggedDays` abstains whatever the figures say (S-2102, S-2110). The intake means
are logged-days-only (S-2107's two halves are the discriminating cases). `fuelVsLoadMeasureGate`
requires `recentMeasure == MixMeasure.load && priorMeasure == MixMeasure.load` — BOTH periods
(S-2111). A prior load of zero abstains (S-2109).
Mutation (a) (`>=`→`>`) red only on S-2104, (b) (`<=`→`<`) red only on S-2105, (e) (dropping the
measure gate) red on S-2111 — each restored green.
**minor** — the plan's D-1417 says this file "imports `lib/core/models/nutrition_consistency.dart`
only"; it also imports `training_load.dart` (for `MixMeasure`). Disclosed as Assumption A-1 with the
reasoning (a parallel enum would be a second source of truth) but not marked RATIFIED; the import is
pure and the constraint that matters (no Flutter, repository, service or clock) holds.

## 3d THE ADAPTER (`lib/core/services/signals/fuel_vs_load_signal.dart`)

**checked, no finding.** `priorEnd` is
`DateTime.fromMillisecondsSinceEpoch(recentStart.millisecondsSinceEpoch - 1)`, so the prior period's
last instant is the millisecond before the recent period's first and the whole of day 21 is inside it.
Every bound is built with calendar arithmetic (`DateTime(y, m, d − n)`) — no `Duration` — so a DST
transition cannot shift a boundary. It reads only through `context.progressService`
(`computeMixPeriod` twice, `nutritionSeries` once) and never touches `context.repository`, walks no
history and calls no PR API: the structural guard `the adapter walks no history and calls no PR API`
was observed red when `context.repository.getAllSessions()` was inserted (mutation (h)). Its identity
is D-1415's: id `fuel-vs-load`, kind caution, priority `kFuelVsLoadPriority`, title `Fuel vs load`.

## 3e SCOPE

**checked, no finding.** `git-status` and `git-diff 627199f --name-only` show exactly the Predicted
Files: `lib/core/models/nutrition_consistency.dart`, `lib/core/models/fuel_vs_load.dart`,
`lib/core/services/signals/fuel_vs_load_signal.dart`, `lib/core/services/signals/signal_registry.dart`,
`lib/core/services/stats_progress_service.dart`, the four test files, the two registry guards, the six
docs and the two plan artifacts. No file outside the lists. The framework files are untouched
(`signals.dart`, `signals_service.dart`, `signals_layer.dart`, `signal.dart` appear in no diff). The
two registry guards changed by a handful of lines: `test/interference_test.dart` 1 insertion;
`test/modality_mix_shift_signal_screen_test.dart` 3 insertions, 1 deletion. The registry change is one
import plus one list entry, and the order (`fuel-vs-load` first) matches D-1415's 300 < 400 < 500,
which A-5/A-8 record as overriding the plan's stale step 3/4 text — the guard asserts ascending
priority and passes. The two new files are untracked, as the brief states; the only other untracked
file is this review.

## 3f TESTS CAN FAIL

**checked, no finding** for the guards and screen tests — each has a recorded red in the evidence
file: the span guard by mutation (g) (`3 weeks` literal → `Expected: false / Actual: <true>`), the
adapter guard by mutation (h) (`context.repository` inserted → red on that guard), and the screen
tests by red A (compile: the adapter file absent) and red B (`+3 -2`: registry line absent →
`Found 0 widgets with key [<'signal_card_fuel-vs-load'>]`), with the rule-level tests covered by
mutations (a)–(f). The fixture's firing was proved by the sanctioned scratch probe rather than
assumed, and the probe's own bug (prior `toMs: now`) is recorded rather than hidden.

3. **minor** — `test/nutrition_series_service_test.dart:388` — the assertion
   `priorTo.millisecondsSinceEpoch == recentFrom.millisecondsSinceEpoch - 1` cannot fail: `priorTo` is
   defined two lines above as `_day(20).subtract(const Duration(milliseconds: 1))`, so the expectation
   restates a `DateTime` arithmetic identity. → drop it or assert against a literal. The test's real
   assertions (the boundary rows) do fail — mutation (d) reddened them.
4. **minor** — `test/fuel_vs_load_signal_screen_test.dart:309` — `seedFFuelForProbe` is the scratch
   probe's entry point (A-6). `test/zz_ffuel_probe_test.dart` no longer exists, so the function has no
   caller and is dead test code. → delete it.
5. **note, no finding** — the evidence file records a count discrepancy (expected `+3680`, observed
   `+3678` three times). It reconciles exactly and is not a defect: base `627199f` = `+3637 ~1`, now
   `+3678 ~1`, delta 41 = 17 (Phase 1's two suites) + 11 (Phase 2) + 9 (the screen file) + 2 (the
   registry guards) + 2 (the constant-contract tests). The `+3680` expectation double-counted the
   guards, which PART A's run already included. My own full-suite run reproduces `+3678 ~1: All tests
   passed!`.

## Verdict

**CHANGES_REQUESTED** — one major: `docs/signals.md:387` names a signal that does not exist and
contradicts the same doc's "three cautions are registered today". The fix is to delete the clause
"and above Protein Consistency". Everything else passes: acceptance criteria AC-1…AC-11 all map to
passing tests, the rule and the adapter match D-1405…D-1419, the scope is exactly the predicted set,
the tone/hard rules hold, and every other doc claim and cited test name was verified by reading the
code and the suites. The three minor items (scope under-claim, tautological assertion, dead probe
hook) are cheap and can ride in the same pass.

