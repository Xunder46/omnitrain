# Evidence — Modality Mix Shift (Stats PR 7a)

> Plan: `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.md`
> Review findings go in `2026-10-03-07a-stats-pr7a-mix-shift-plan.review.md`. Nothing in this file is
> ever copied into the plan.

## Baselines (measured by the planner on `develop`, before Phase 1)

| Command | Output |
|---|---|
| `flutter analyze` | `196 issues found.` (0 errors) |
| `flutter test` | `+3548 ~1: All tests passed!` |

## Per-phase results

### Phase 1 (@dba)

| Item | Command | Result |
|---|---|---|
| Red run (rule + copy) | `flutter test test/modality_mix_shift_test.dart` | `+11 -2` — S-1910 `Expected: not null Actual: <null>` (line 183); S-1911 `Expected: <8> Actual: <9>` (line 212) |
| Green run (rule + copy) | `flutter test test/modality_mix_shift_test.dart` | `+13: All tests passed!` (after the two scenario fixes below) |
| Red run (period payload) | `flutter test test/modality_mix_period_service_test.dart` | `Failed to load ...: The method 'computeMixPeriod' isn't defined for the type 'StatsProgressService'` (compile failure — the method did not exist yet) |
| Green run (period payload) | `flutter test test/modality_mix_period_service_test.dart` | `+6: All tests passed!` (S-1904a, S-1907, S-1913 × Mock/Hive) |
| Both Phase 1 suites | `flutter test test/modality_mix_shift_test.dart test/modality_mix_period_service_test.dart` | `+19: All tests passed!` |
| Mix suites unchanged | `flutter test test/mix_layer_service_test.dart test/mix_layer_screen_test.dart` | `+96: All tests passed!` |
| Analyze | `flutter analyze` | `196 issues found.` (0 errors) |
| Full suite | `flutter test` | `+3567 ~1: All tests passed!` (baseline `+3548 ~1`; delta `+19` = the 13 rule tests + the 6 period tests) |

**Two scenarios disagreed with the rule the plan pins (steps 1–3 of the resumed run):**

The rule is a direct transcription of D-1207 (exact-fraction fire test), D-1209 (smallest
`recentShare / baselineShare`, ties in declaration order) and D-1212 (second sentence only when the
largest recent share is not the reported modality). Both failures were in the scenarios' hand
arithmetic, not in the rule, and fixing the rule either way would have weakened a boundary:

| Scenario | Failure | Cause | Fix |
|---|---|---|---|
| S-1910 | `Expected: not null Actual: <null>` | The plan's fixture cannot fire under D-1207: a modality at 44% of the recent bar against a 60% baseline can never be below *half* its usual share (30%). The plan's own narrative shows the slip — its resistance line multiplies by 100 (the baseline total) instead of 46 (the recent total). | **Test.** Keep the recent bar (`cardio 20, resistance 18, isometric 8`, total 46, percents 44/39/17) and raise Cardio's baseline so it genuinely fires: `cardio 88, resistance 10, isometric 2` (`2 × 20 × 100 = 4000 < 88 × 46 = 4048`). Cardio is still the largest recent share, so D-1212 still omits sentence two. Copy: `usual 88%`. |
| S-1911 | `Expected: <8> Actual: <9>` | The plan assumed exact rationals; `mixSegments`' largest-remainder tie-break runs on doubles, so for `40 / 4 / 4` Cardio's remainder (`0.3333333333333357`) beats Resistance's (`0.3333333333333286`) and the unit goes to Cardio (9% / 83%), not Resistance (8% / 84%). | **Test.** Change the recent Resistance measure `40 → 42` (total 50). The percents are then exactly `84 / 8 / 8` with no remainder, so the plan's pinned observation holds character for character, the ratio tie `4 × 100 / (50 × 20)` is intact, and Cardio is reported per D-1209. |

Neither change touches `lib/core/models/modality_mix_shift.dart` or `mixSegments`.

**Mutation (a) — D-1207's `<` → `<=`:**

| Step | Command | Result |
|---|---|---|
| Apply the edit | `lib/core/models/modality_mix_shift.dart` | `2 * recentMeasure * baselineTotal >= baselineMeasure * recentTotal` → `>` |
| Red | `flutter test test/modality_mix_shift_test.dart` | `+11 -2: Some tests failed.` — S-1902 `exactly half does not fire` and S-1908 `the fire test is exact-fraction, not rounded-percentage` both `Expected: null Actual: <Instance of 'ModalityMixShift'>` |
| Restore | — | `>=` restored; `git-diff` shows no diff for the file (it is untracked, so the restore was read back in the editor) |
| Green | `flutter test test/modality_mix_shift_test.dart` | `+13: All tests passed!` |

**Mutation (b) — fire test reads the rounded `percent` instead of the exact `measure`:**

| Step | Command | Result |
|---|---|---|
| Apply the edit | `lib/core/models/modality_mix_shift.dart` | the fire test's `recentMeasure` read from the rounded `percent` instead of the exact `measure` |
| Red | `flutter test test/modality_mix_shift_test.dart` | `+13: All tests passed!` — **the mutation did not fail the suite** |
| Restore | — | reverted to the exact `measure` |
| Green | `flutter test test/modality_mix_shift_test.dart` | `+13: All tests passed!` |

**Mutation (b) did not produce a red.** The rounded `percent` and the exact `measure` agree on every
fixture in the suite, so no assertion in `test/modality_mix_shift_test.dart` distinguishes them. The
plan's step 7(b) therefore has no observable effect and is recorded as **not demonstrated** rather
than as a passing mutation. S-1908's own name claims the fire test is exact-fraction, and mutation (a)
is what actually falsifies that claim: it fails S-1908 as well as S-1902. A fixture that separates the
two reads (a modality whose exact share and floored share straddle the half-share boundary) is the
missing coverage; it is listed under Open Items in the plan.

**Plan line count re-measured:** 577 lines (was 558 at planning; the delta is the Assumption Log
entries this run appended).

### Phase 2 (@developer)

| Item | Command | Result |
|---|---|---|
| Red run (card absent) | `flutter test test/modality_mix_shift_signal_screen_test.dart --plain-name "Mock"` | RED — `+1 -2: Some tests failed.` S-1909's card assertion: `Found 0 widgets with key [<'signal_card_modality-mix-shift'>]`; the dismissal test fails on the same finder. S-1904(b) passes vacuously (no signal exists, so no card can appear) — it is the green half of the pair and is re-asserted after the signal lands. |
| Green run | `flutter test test/modality_mix_shift_signal_screen_test.dart` | GREEN — `+7: All tests passed!` (Mock 4, Hive 3; the dismissal test is Mock-only). |
| Framework + surface suites | `flutter test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/mix_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/screen_widget_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart` | GREEN — `+432: All tests passed!` No surface-height re-stabilisation was needed: neither `test/mix_layer_screen_test.dart` nor `test/progression_rate_signal_screen_test.dart` changed. |
| PR path untouched | `flutter test test/in_session_pr_toast_test.dart test/pr_toast_test.dart` | GREEN — `+41: All tests passed!`, with no edit to either file. |
| Analyze | `flutter analyze` | `196 issues found.` — matches the baseline. Three issues raised by the new files (an unused `exercise_metric.dart` import in the signal, and two unused test helpers) were removed; the count returned to 196. |
| Full suite | `flutter test` | GREEN — `+3574 ~1: All tests passed!` Baseline was `+3567 ~1`; the delta is exactly the new screen suite's 7 tests. No other suite changed its count. |

**Mutation — the period follows the window chip (`fromMs` = the window's start):**

The plan names `toMs` = the window's end. That edit is **not detectable** on this surface: the
window's `toMs` is today's end-of-day (`23:59:59.999`), which is *after* `context.now`, so the
period only widens and no fixture can separate the two. The equivalent and detectable form of the
same defect is `fromMs` = the window's start, which is what was applied. The fixture was also
re-scoped: F-MIX's window is now period-scoped to the last 3 days (narrower than the signal's own
28-day period) and its isometric session sits at `day(2)`, so a period that followed the chip loses
the isometric work entirely.

| Step | Command | Result |
|---|---|---|
| Apply the edit | `lib/core/services/signals/modality_mix_shift_signal.dart` — `fromMs` = `context.window.fromMs` | applied |
| Red | `flutter test test/modality_mix_shift_signal_screen_test.dart` | RED — `+2 -5: Some tests failed.` Failing: S-1909 the card on the layer (Mock and Hive), S-1909 the period does not follow the window chip (Mock and Hive), S-1909 the card is dismissible (Mock). S-1904(b) still passes — it asserts an absence. |
| Restore | `fromMs` back to `DateTime(now.year, now.month, now.day - (kModalityMixShiftPeriodDays - 1))` | restored; the spot was read back and matches the original |
| Green | `flutter test test/modality_mix_shift_signal_screen_test.dart` | GREEN — `+7: All tests passed!` |

A first attempt at the mutation (`toMs` = `context.window.toMs`) failed to compile
(`window.toMs` is a `DateTime`, not an `int`) and was corrected before any test ran; it then ran
green, which is what prompted the `fromMs` form above.

### Phase 3 (@developer)

| Item | Command | Result |
|---|---|---|
| Guards added | the three test files | `test/modality_mix_shift_test.dart` +4 (exact-fraction half-share, no local percentage, no history walk, the registered contract); `test/modality_mix_shift_signal_screen_test.dart` +3 (payload-equality × Mock/Hive, the registry) |
| Residue sweep | search every name this PR introduces | every hit's file listed below; the framework files and `watch/` are absent |
| Framework + PR path no diff | `gateway.sh git-diff --stat -- <paths>` | empty output, exit 0, for the five framework source files, `watch/` and the two PR-path test files |
| Analyze | `flutter analyze` | `196 issues found.` — matches the baseline |
| Full suite | `flutter test` | GREEN — `+3582 ~1: All tests passed!` (Phase 1 was `+3567 ~1`; delta `+15` = the 4 rule guards + the constant-contracts guard + the 3 screen guards × 2 harnesses + the 1 registry guard) |
| Docs re-read | `docs/signals.md`, `docs/stats_screen.md` | one drift corrected: both files pointed at a `test/modality_mix_shift_test.dart` test named "the constant contracts" that did not exist. The test was added (it asserts the three constant values) and the docs' pointer is now true. Both files are under the 64 KiB ceiling (`signals.md` 15,505 B, `stats_screen.md` 27,249 B) |

**Guards added (step 1).** Each names what breaks it and was shown to fail under an inverse edit.

| Guard | File | What breaks it |
|---|---|---|
| `D-1207 the half-share test compares exact fractions, not the two rounded percentages` | `test/modality_mix_shift_test.dart` | a fire test that reads the segments' rounded `percent` instead of their exact `measure` — the fixture's exact share (5.3%) and floored share (5%) straddle the half-share boundary against a baseline of 10.6% / 11% |
| `the rule derives no percentage of its own` | `test/modality_mix_shift_test.dart` | a local `* 100`, `round(`, `toStringAsFixed` or `percent =` in either shipped file |
| `the adapter walks no history of its own` | `test/modality_mix_shift_test.dart` | `context.repository`, `computeMixLayer`, `computeTotals`, `computeProgressData` or any repository read in the signal; it also requires `computeMixPeriod` to be present |
| `the registered signal declares the contract the docs describe` | `test/modality_mix_shift_test.dart` | a changed id, kind or priority |
| `the signal reads the period payload's own segments` | `test/modality_mix_shift_signal_screen_test.dart` | a signal that rebuilds the bar itself (or reads a different payload) — the card's copy must equal the copy built from the payload the service returns |
| `the registry lists exactly the two shipped signals, in order` | `test/modality_mix_shift_signal_screen_test.dart` | a registry that drops, adds or reorders a signal |

**Mutation (a) — the half-share comparison reads the rounded `percent`:**

| Step | Command | Result |
|---|---|---|
| Original line (untracked file, copied before the edit) | `lib/core/models/modality_mix_shift.dart` | `if (2 * recentMeasure * baselineTotal >= baselineMeasure * recentTotal) {` |
| Apply the edit | same file | `if (2 * (recentBySection[section]?.percent ?? 0) >= (baselineBySection[section]?.percent ?? 0)) {` |
| Red | `flutter test test/modality_mix_shift_test.dart` | `+14 -3: Some tests failed.` — the new guard `D-1207 the half-share test compares exact fractions…` `[E]` at line 349 `Expected: null Actual: <Instance of 'ModalityMixShift'>`; S-1908 `[E]` at line 185; S-1910 `[E]` at line 207 |
| Restore | — | the exact-fraction line restored; the spot was read back and matches the original |
| Green | `flutter test test/modality_mix_shift_test.dart` | `+17: All tests passed!` |

**Mutation (b) — the signal derives a percentage itself instead of using the payload's segments:**

| Step | Command | Result |
|---|---|---|
| Original lines (untracked file, copied before the edit) | `lib/core/services/signals/modality_mix_shift_signal.dart` | `recent: period.segments,` (and no `training_load.dart` import) |
| Apply the edit | same file | `recent:` rebuilt from `period.segments` with a local `measure * 100 / total` and `.floor()`, plus the `training_load.dart` import |
| Red | `flutter test test/modality_mix_shift_signal_screen_test.dart` | `+8 -2: Some tests failed.` — `the signal reads the period payload's own segments` `[E]` at line 581 on both harnesses: `Expected: 'Isometric is 3% of your load…' Actual: 'Isometric is 2% of your load…'` |
| Restore | — | `recent: period.segments,` and the import list restored; both spots were read back and match the original |
| Green | `flutter test test/modality_mix_shift_signal_screen_test.dart` | `+10: All tests passed!` |

A first attempt at mutation (b) used `.round()` and ran **green**: on F-MIX the payload's
largest-remainder percents happen to equal the locally rounded ones, so the copy was identical. The
`.floor()` form is the same defect in its detectable shape — it diverges from `mixSegments`' shared
percents, which is exactly what the guard exists to catch.

## Residue sweep — every hit, by file

| Name | Files that mention it | Verdict |
|---|---|---|
| `ModalityMixShiftSignal` | `lib/core/services/signals/modality_mix_shift_signal.dart`, `lib/core/services/signals/signal_registry.dart`, `test/modality_mix_shift_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`, `docs/signals.md`, the 7a plan | expected — the class, its one registry line, its tests and its docs |
| `modality-mix-shift` | `lib/core/services/signals/modality_mix_shift_signal.dart`, `test/modality_mix_shift_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`, the 7a plan and its evidence | expected — the id, the dismissal key and the widget key |
| `computeMixPeriod` | `lib/core/services/stats_progress_service.dart`, `lib/core/services/signals/modality_mix_shift_signal.dart`, `test/modality_mix_period_service_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`, `test/modality_mix_shift_test.dart`, `docs/signals.md`, `docs/state_management/services_and_utils.md`, `docs/training_load.md`, the 7a plan and its evidence, `docs/plans/2026-10-03-07-stats-pr7-index.md` | expected — the service method, its one caller, its tests and its docs; the PR 7 index is 7b's untracked file and is listed, not edited |
| `modalityMixShift` | `lib/core/models/modality_mix_shift.dart`, `lib/core/services/signals/modality_mix_shift_signal.dart`, `test/modality_mix_shift_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`, `docs/signals.md`, `docs/stats_screen.md`, the 7a plan | expected — the rule, its caller, its tests and its docs |
| `ModalityMixShift` | `lib/core/models/modality_mix_shift.dart`, `lib/core/services/signals/modality_mix_shift_signal.dart`, `lib/core/services/signals/signal_registry.dart`, `lib/core/services/stats_progress_service.dart`, `test/modality_mix_shift_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`, `docs/constants_reference.md`, `docs/signals.md`, the 7a plan and its evidence, `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.md` | expected — the result type and the constants; 7b's plan is untracked and is listed, not edited |
| `kModalityMixShiftPeriodDays` | `lib/core/models/modality_mix_shift.dart`, `lib/core/services/signals/modality_mix_shift_signal.dart`, `lib/core/services/stats_progress_service.dart`, `test/modality_mix_shift_signal_screen_test.dart`, `docs/constants_reference.md`, `docs/signals.md`, the 7a plan and its evidence | expected |
| `kModalityMixShiftMinBaselineShare` | `lib/core/models/modality_mix_shift.dart`, `docs/constants_reference.md`, `docs/signals.md`, the 7a plan | expected |
| `kModalityMixShiftPriority` | `lib/core/models/modality_mix_shift.dart`, `lib/core/services/signals/modality_mix_shift_signal.dart`, `test/modality_mix_shift_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`, `docs/constants_reference.md`, `docs/signals.md`, the 7a plan, `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.md` | expected; 7b's plan is untracked and is listed, not edited |
| `of your load over the last 4 weeks` | `test/modality_mix_shift_test.dart`, the 7a plan, `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` | expected — the observation's opening words in the test and the source pack |

**Absent, as required:** `lib/core/models/signals.dart`, `lib/core/services/signals_service.dart`,
`lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/stats_screen.dart` and `watch/`
mention none of the names above.

## Doc claim → test that fails when the claim goes false

_Phase 3 filled the `docs/signals.md` and `docs/stats_screen.md` rows. Phase 1's four doc edits are
below._

| Claim | File | Test that fails when it goes false |
|---|---|---|
| The three `modality_mix_shift` constants exist and govern the period span, the baseline-share floor and the priority | `docs/constants_reference.md` | `test/modality_mix_shift_test.dart` (`the constant contracts`) |
| `computeMixPeriod` returns the same payload shape for an arbitrary period, carries no weekly strip, and shares the measure gate and baseline rule with `computeMixLayer` | `docs/state_management/services_and_utils.md`, `docs/training_load.md` | `test/modality_mix_period_service_test.dart` (S-1904a, S-1907, S-1913) |
| The caution order is Interference, Modality Mix Shift, Fuel vs Load, Protein Consistency, Sustained High Load, Cardio Efficiency Drift, carried by each signal's own priority constant | `docs/signals.md` | `test/modality_mix_shift_test.dart` (`the constant contracts`) for the Mix Shift entry; the other five entries are Phase 2/3 and 7b's |
| The Modality Mix Shift is the second registered signal, and its rules live in `docs/signals.md` rather than being restated | `docs/stats_screen.md` | `test/modality_mix_shift_signal_screen_test.dart` (`S-1909`, `S-1904b`) |
| The period is the 28 local calendar days ending today and never follows the Stats window chip | `docs/signals.md` | `test/modality_mix_shift_signal_screen_test.dart` (`S-1909 the period does not follow the window chip`) |
| The baseline is the 12 blocks abutting the period's start day, and the signal defines no second baseline | `docs/signals.md` | `test/modality_mix_period_service_test.dart` (`S-1913`) |
| The measure gate is the Mix layer's own, read over the period | `docs/signals.md` | `test/modality_mix_period_service_test.dart` (`S-1904a`), `test/modality_mix_shift_signal_screen_test.dart` (`S-1904b`) |
| The regularly-trained floor is inclusive and the fire test is strict, on exact fractions | `docs/signals.md` | `test/modality_mix_shift_test.dart` (`S-1902`, `S-1903`, `S-1906`, `S-1908`, `D-1207 the half-share test compares exact fractions…`) |
| The reported modality has the largest relative drop, ties in declaration order | `docs/signals.md` | `test/modality_mix_shift_test.dart` (`S-1905`, `S-1911`) |
| The copy names the span, and the second sentence is omitted when the reported modality is the largest | `docs/signals.md` | `test/modality_mix_shift_test.dart` (`S-1901`, `S-1910`) |
| The adapter walks no history of its own — it calls `computeMixPeriod` and hands the payload's own segments to the rule | `docs/signals.md` | `test/modality_mix_period_service_test.dart` (`S-1907`), `test/modality_mix_shift_test.dart` (`the adapter walks no history of its own`), `test/modality_mix_shift_signal_screen_test.dart` (`the signal reads the period payload's own segments`) |
| The signal is one class plus one registry line, and no framework file names a concrete signal | `docs/signals.md` | `test/modality_mix_shift_signal_screen_test.dart` (`the registry lists exactly the two shipped signals, in order`) |

**Drift corrected in Phase 3.** `docs/constants_reference.md` and `docs/signals.md` both pointed at a
`test/modality_mix_shift_test.dart` test named "the constant contracts" that did not exist — the
pointer was written in Phase 1 against a test that was never added. The test was added in Phase 3
(it asserts `kModalityMixShiftPeriodDays == 28`, `kModalityMixShiftMinBaselineShare == 0.10` and
`kModalityMixShiftPriority == 400`), so the docs' pointer is now true. No doc prose changed.

## Assumption Log entries raised in this PR

| Phase | Decision | Options considered | Choice and why |
|---|---|---|---|
| 1 | S-1910's fixture was arithmetically impossible under D-1207 | keep the fixture and drop the assertion; re-baseline the fixture | Re-baselined to 88/10/2 with the observation reading "usual 88%" — keeps the scenario's intent and makes the arithmetic satisfiable; no rule changed |
| 1 | S-1911's exact ratio tie was broken by floating-point noise in `mixSegments` | assert the declaration-order winner and accept a flaky tie; move the fixture off the tie | Recent resistance 40 → 42, making the tie exact in the integers the rule compares; the tie-break rule is unchanged and still covered |
| 1 | The walk helper is an instance method, not `static` | `static` helper; instance helper | Instance — it calls `_measuredSecsFor` and `_dominantSectionFor`, which are instance members; `static` produced `instance_member_access_from_static` |
| 1 | `_sessionInWindow` takes explicit `fromMs`/`toMs` | keep the `StatsWindow` parameter and add a second predicate; widen the predicate | Widened the predicate; the period call has no `StatsWindow`, and the one other caller passes `window.fromMs, window.toMs`, so behaviour is unchanged |
| 3 | The docs pointed at a "constant contracts" test that did not exist | delete the pointer from the docs; add the test | Added the test — the constants are a rule, and a doc pointer to a non-existent test is worse than no pointer |

## Phase 3 Done Criteria — command and observed result

| Done Criterion | Command | Observed result |
|---|---|---|
| `flutter analyze` | `gateway.sh lint` | `196 issues found.` (0 errors) — matches the baseline |
| The three Phase 3 suites | `gateway.sh test test/modality_mix_shift_test.dart test/modality_mix_period_service_test.dart test/modality_mix_shift_signal_screen_test.dart test/signals_framework_test.dart test/docs_indexing_contract_test.dart` | `+74: All tests passed!` |
| Full suite | `gateway.sh test` | `+3582 ~1: All tests passed!` (Phase 1 `+3567 ~1`; delta `+15`, all added tests) |
| Structural guards fail under an inverse edit | two mutations, each restored | mutation (a) `+14 -3` with the new guard `[E]` at line 349; mutation (b) `+8 -2` with the payload-equality guard `[E]` at line 581 on both harnesses |
| Residue sweep | every introduced name searched across `lib/`, `test/`, `docs/` | every hit listed above; the framework files and `watch/` absent |
| Untouched files show no diff | `gateway.sh git-diff --stat -- <paths>` | empty output, exit 0, for the five framework source files, `watch/` and the two PR-path test files |
| Docs re-read | `docs/signals.md`, `docs/stats_screen.md` against the shipped code | one drift corrected (the missing "constant contracts" test); both files under the 64 KiB ceiling |

## Fix round 1 — review findings 1–6

One line per finding; docs and test hygiene only, no behaviour change.

| # | Finding | Fix applied | Command | Observed result |
|---|---|---|---|---|
| 1 | `docs/signals.md` caution order written in shipped voice (six cautions asserted, five constants absent) | Rewrote to the shipped fact only (per-kind priority carried by each signal's own `k…Priority` constant; only Mix Shift and Progression Rate registered); the planned order stays in the plan's D-1214, whose wording now says so | `gateway.sh test test/docs_indexing_contract_test.dart` | `All tests passed!` (see paired run below) |
| 2 | `docs/stats_screen.md` restated `kModalityMixShiftPeriodDays` as "28 days" | Named the constant in the clause | `gateway.sh test test/docs_indexing_contract_test.dart` | `All tests passed!` |
| 3 | `docs/signals.md` restated the baseline span as "the 84 days" | Deleted the restatement; the named constant and block count carry it | `gateway.sh test test/docs_indexing_contract_test.dart` | `All tests passed!` |
| 4 | `docs/signals.md` Copy bullet omitted the suggestion | Added the shipped suggestion template and the `modalityMixShiftArticle`/`modalityMixShiftNoun` source, pointing at the same tests | `gateway.sh test test/docs_indexing_contract_test.dart` | `All tests passed!` |
| 5 | S-1909 test claimed "the exact copy" but asserted no copy | Added hard-coded F-MIX observation and suggestion assertions (hand arithmetic: period 97%/3%, baseline 67%/33%) | `gateway.sh test test/modality_mix_shift_signal_screen_test.dart` | `+10: All tests passed!`; perturbing the literal to `4%` → `+8 -2: Some tests failed.` on both harnesses, restored exactly |
| 6 | Stale comment: window "10 days" / `day(5)`, contradicted by A-6 | Comment now reads "last 3 days" / `day(2)` and the correct reason the card would disappear | (same run as 5) | `+10: All tests passed!` |

Fix-round commands and observed results:

| Command | Observed result |
|---|---|
| `gateway.sh lint` | `196 issues found.` — matches baseline |
| `gateway.sh test test/modality_mix_shift_signal_screen_test.dart test/docs_indexing_contract_test.dart` | `+19: All tests passed!` |
| `gateway.sh test` | `+3582 ~1: All tests passed!` — matches baseline |
