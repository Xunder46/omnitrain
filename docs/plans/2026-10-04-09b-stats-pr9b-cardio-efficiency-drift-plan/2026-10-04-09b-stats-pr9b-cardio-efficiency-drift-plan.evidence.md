# Evidence — Cardio Efficiency Drift (Stats PR 9b)

> Companion to `2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan.md`. Implementers write
> here; nothing from this file goes into the plan. One section per phase, filled as the phase runs.

## Opening baselines (measure before Phase 1, on the branch)

| Command | Result |
|---|---|
| `flutter analyze` | `196 issues found. (ran in 7.2s)` — 0 errors. Taken on the branch with the two new files present; neither file name appears in the output, so the count is the pre-phase baseline. |
| `flutter test` | `05:08 +3789 ~1: All tests passed!` — 14 of those are this phase's new tests, so the pre-phase count was 3775. |
| `docs/signals.md` bytes | 34,099 (the plan's recorded baseline; Phase 1 touches no docs, so it is unchanged). The gateway-only tool set in this session has no byte-count command, so this figure is carried from the plan rather than re-measured. |

Known and untouched: `test/food_photo_clear_legacy_edit_test.dart` is order-dependent in a full run
and passes on re-run. (It passed in the run above.)

## Phase 1 — the pure rule

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/cardio_efficiency_drift_test.dart` | `00:00 +0 -1: Some tests failed.` — compile failure: `Error: 'with' can't be used as an identifier because it's a keyword.` plus `Method not found` / `isn't a type` for every rule symbol, since `lib/core/models/cardio_efficiency_drift.dart` did not exist. |
| green | `flutter analyze` | `196 issues found. (ran in 7.2s)` — 0 errors, no issue in either new file. |
| green | `flutter test test/cardio_efficiency_drift_test.dart test/training_load_test.dart` | `00:00 +64: All tests passed!` (14 new + 50 neighbours; the new suite alone is `00:00 +14: All tests passed!`). |
| full | `flutter test` | `05:08 +3789 ~1: All tests passed!` |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 1 | drift test `<=` → `<` (strict): guard `recentMean * 100 > referenceMean * (100 - k)` → `>=` | S-2502 (exactly 5%) | PASS — `00:00 +0 -1: S-2502 the 5% boundary is inclusive [E] Expected: not null / Actual: <null>`. Reverted. |
| 2 | group member compared with the previous member instead of the anchor (`anchor.durationSecs` → `list[j - 1].durationSecs`) | S-2506 (529 s merges into the 480 s group) | PASS, after a fixture gap was closed. S-2506 B and C did **not** catch it — neither has a bridging duration, so 529 s is rejected against the previous member too. S-2506 D was added (480 s + 500 s + 529 s, where 480→500 and 500→529 are each within 10% but 480→529 is not); with the mutation it failed with `Expected: [480, 529] / Actual: [480]`. Reverted. |

## Phase 2 — the service read

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/cardio_efficiency_service_test.dart` | `00:00 +0 -1: Some tests failed.` — compile failure: `Error: The method 'cardioEfforts' isn't defined for the type 'StatsProgressService'.` at the two call sites (the helper and the span-exclusion case). No other error, so the red is exactly the missing method. |
| green | `flutter test test/cardio_efficiency_service_test.dart` | `00:04 +27: All tests passed!` (13 cases × 2 stores + the parity case). |
| green | `flutter test test/cardio_efficiency_service_test.dart test/stats_progress_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/distance_source_test.dart` | `00:06 +128: All tests passed!` |
| green | `flutter analyze` | `196 issues found. (ran in 7.0s)` — 0 errors, unchanged from baseline; neither `test/cardio_efficiency_service_test.dart` nor `lib/core/services/stats_progress_service.dart` appears in the output. |
| full | `flutter test` | `05:12 +3816 ~1: All tests passed!` (baseline 3789 + this phase's 27). |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 3 | drop `!DistanceSource.isEstimated(...)` (guard short-circuited with `if (false && …)`) | S-2504 (the estimated effort becomes eligible) | PASS — `00:05 +21 -6: Some tests failed.` The three estimated-source cases failed in both stores (`Expected: an object with length of <7> / Actual: … has length of <8>`). Reverted; re-ran green `+27`. |
| 4 | read the heart rate from the session-scope summary (`scopeTimedInstance, instance.id` → `scopeSession, session.id`) | S-2505 (third variant) | PASS — `00:05 +0 -27: Some tests failed.` Every case failed, since no fixture stores a session-scope reading (`Expected: an object with length of <8> / Actual: []`). Reverted; re-ran green `+27`. |

### Test-authoring notes

- The plan's S-2504 variants need **one** estimated effort among the four recent ones, so
  `_seedS2501`'s `recentSource` names the first recent effort's source and leaves the other three
  measured. Applying it to all four made the first red run report 4 eligible efforts instead of 7.
- There is no `deleteSensorSummary` on `WorkoutRepository`. A fixture that needs an effort without a
  summary deletes the instance (`deleteTimedInstance`, which cascades the instance's summaries per
  D-131) and re-seeds the instance. The "session in progress" variant clears `endedAtMs` through
  `updateSession` rather than deleting the session, so the effort, its distance and its summary stay
  in place and only the completion flag changes.

## Phase 3A — the card, the registry, the guards

### The screen fixture, worked out before the test

The real registry is evaluated, so the fixture must (a) make the layer render at all, (b) make the
Cardio Efficiency Drift rule fire, and (c) leave every other signal silent. All days are local
calendar days off the real `DateTime.now()`; a "cardio session" is a rated session whose segment
holds one finished `timed` effort (480 s, one timed instance) for `ex-run` (`Treadmill Run`), a
paired distance row and an instance-scope summary at 150 bpm. Its measured cardio time equals its
duration, so its resistance remainder is 0.

**S-2501 (one card).** Four recent efforts at days 3, 6, 9, 12 (2790 m each) and four reference
efforts at days 30, 33, 36, 39 (3000 m each), all 480 s at 150 bpm.

- efficiency = `metres × 60 ÷ (150 × 480)`: 2790 → 2.325, 3000 → 2.5.
- drift `p = (1 − 2.325/2.5) × 100 = 7.0 → 7`, and `2.325 × 100 = 232.5 <= 2.5 × 95 = 237.5`, so it
  fires. Both windows hold 4 ≥ 3 efforts, and all eight durations equal 480 s, so there is one
  group.
- A training period `[day(20), end of today]` holds the recent efforts, so `resolveWindow` is
  period-scoped and the Mix layer's window starts at `day(20)`.
- Layer gate: the window's baseline is the 12 blocks before `day(20)` (`day(104)…day(21)`). Four
  rated filler cardio sessions at days 48, 62, 76 and 90 sit in four distinct blocks, and the
  reference efforts add two more (days 30/33 in `day(34)…day(28)`, days 36/39 in
  `day(41)…day(35)`), so `ratedBaselineWeeks = 6 >= 4` and `signalsGateMet` holds. Every session is
  rated, so the unrated share is 0 and the window's measure is load.
- Lifting: the adapter's own payload `[day(27), now]` is measured in load too (its baseline holds
  the same six rated blocks). Every baseline session is cardio, so `liftUsualLoad` (resistance
  segments) is 0 and no second sentence appears.
- Modality Mix Shift: recent and baseline bars are both 100 % cardio, so no modality has a baseline
  share ≥ 10 % to fall from. Protein Consistency: no resistance session and (after the food log is
  cleared) no logged days. Progression Rate: no `set` effort. Interference: no sports time.
  Sustained High Load: no five-week streak. All abstain.

**S-2503 (two recent efforts).** S-2501 with `recentCount = 2`: the group holds 2 < 3 in the recent
window, so the rule returns null; the layer still renders (gate met) and shows the quiet line.

**S-2504 at the screen (an estimate).** S-2501 with `recentCount = 3` and the first recent effort's
distance stored `estimated`: 2 eligible recent efforts < 3, so no card.

**S-2509 (the lifting sentence).** S-2501 plus four rated resistance sessions in the last 28 days
(days 2, 8, 15, 22) at 69 min × rating 5 = 345 each → `liftRecentLoad = 1380`, and twelve rated
resistance sessions in the twelve baseline blocks of `[day(27), now]` at 60 min × 5 = 300 each →
`liftUsualLoad = 3600`. `1380 × 84 × 100 = 11,592,000 >= 3600 × 28 × 115 = 11,592,000`, so the
sentence appears with `q = 15`. Modality Mix Shift: recent resistance share `1380/1476 = 93.5 %`
against a baseline share `3600/3696 = 97.4 %`, and `2 × 1380 × 3696 > 3600 × 1476`, so resistance
does not fire; cardio's baseline share is 2.6 % < 10 %.

**The two-caution variant (S-2511).** 9a's `_seedF9A` seventeen weeks (all resistance) plus the
period and the S-2501 cardio fixture. Sustained High Load's streak weeks gain at most 24 load each
(the cardio sessions), so every week stays above 110 % of the usual 200. The cautions that survive
are Sustained High Load (100) and Cardio Efficiency Drift (50); `resolveSignals` sorts a kind by
priority **descending**, so Sustained High Load renders first — the plan's "ascending priority
(Cardio Efficiency Drift first)" is the S-2511 defect, logged in the Assumption Log.

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/cardio_efficiency_drift_signal_screen_test.dart --plain-name "Mock"` | `00:05 +2 -5: Some tests failed.` — the five card-bearing cases fail on `Found 0 widgets with key [<'signal_card_cardio-efficiency-drift'>]` (the signal is not registered), and the service case fails `Expected: <12> / Actual: <8>` because the four rated baseline sessions are not yet counted by the fixture's own expectation. The two abstain cases pass, as they must. |
| green | same, Mock-first | `00:04 +7: All tests passed!` (Mock), then the whole file `00:08 +13: All tests passed!` (Mock + Hive). |
| guards | `flutter test test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart` | `00:07 +45: All tests passed!` |
| full | `flutter test` | `04:57 +3829 ~1: All tests passed!` — 13 over the 3816 baseline, no regressions. `flutter analyze` = `196 issues found.` (0 errors), none in a touched file. |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 5 | registry entry moved to the end | both registry guards | Both fail: `interference_test.dart:1092` and `modality_mix_shift_signal_screen_test.dart:621`, each `at location [0] is 'sustained-high-load' instead of 'cardio-efficiency-drift'`. Restored exactly; both pass again (`+2: All tests passed!`). |
| 6 | `liftMeasure: MixMeasure.load` passed unconditionally | S-2509 (the time-measure variant gains a sentence) | **First run: not observed.** The Mock suite stayed `+7: All tests passed!` with the mutation in place, so no test in this file pinned the measure guard. Restored exactly; green again. Logged as an Open Item. **Re-run with the new screen case: caught** — see the subsection below. |

### Mutation check 6, re-run — the payload's own measure

Hand-computed **before** the test was written. F-TIME is S-2501's cardio fixture with every session
unrated, plus unrated set-only resistance sessions on both sides of the payload's window; days are
local calendar days off the real clock.

| Figure | Value | Arithmetic |
|---|---|---|
| recent cardio efforts | 4 | days 3, 6, 9, 12 at 480 s / 2790 m / 150 bpm, no rating |
| reference cardio efforts | 4 | days 30, 33, 36, 39 at 480 s / 3000 m / 150 bpm, no rating |
| efficiency, recent / reference | 2.325 / 2.5 | `metres × 60 ÷ (150 × 480 = 72000)` |
| drift | 7 | `(1 − 2.325/2.5) × 100 = 7.0`; `232.5 <= 237.5`, so it fires |
| payload window | `[day(27), now]` | `kCardioEfficiencyLiftLoadWindowDays − 1 = 27` |
| payload measure | `time` | no session is rated anywhere, so `ratedBaselineWeeks = 0 < kTrainingLoadMinRatedWeeks = 4` |
| window resistance measure | 300 min | 4 unrated set-only sessions at days 2, 8, 15, 22 × 75 min (no efforts, so the whole duration is Resistance) |
| baseline resistance time | 720 min | 12 unrated set-only sessions, one per block of `[day(111), day(27))`, × 60 min |
| **payload `baselineSegments`** | **empty** | `_mixPayload` returns `const []` unless `measure == load`, so the baseline's 720 min never reach the adapter |
| the +15 % test on those figures | would pass at +25 % | `300 × 84 × 100 = 2,520,000 >= 720 × 28 × 115 = 2,318,400` — but only if the payload carried a baseline at all, which in the time measure it never does |

**Why the prescribed all-unrated fixture cannot fail.** `liftUsualLoad` is
`_resistanceLoad(mix.baselineSegments)`, which is **0** for every time-measured payload, and
`_liftRisePercent` returns null on `liftUsualLoad <= 0` before it ever looks at the measure. So the
measure argument is inert wherever `mix.measure` is `time`. The mutant and the shipped line agree on
every payload `_mixPayload` can emit — proved by exhaustion over the three reachable cases:

| Reachable payload | Shipped `liftMeasure` | Mutated `liftMeasure` | Same card? |
|---|---|---|---|
| `measure == load` (`baselineSegments` non-empty) | `load` | `load` | yes |
| `measure == time` (`baselineSegments` `const []`) | `time` → null at guard 1 | `load` → null at guard 2 (`liftUsualLoad = 0`) | yes |
| `mix == null` (`liftUsualLoad = 0`) | `time` → null | `load` → null | yes |

**How the mutant is killed.** The distinguishing payload is a *time-measured payload that carries a
baseline* — a shape `_mixPayload` never emits, and the only shape where the two lines disagree. The
second case below hands the adapter F-LIFT's own real payload (1380 window / 3600 usual, which clear
the +15 % test exactly) with its measure label forced to `time`, which is the single field the
service gates the baseline on. Then `liftUsualLoad = 3600 > 0`, so the mutant's `load` reaches the
+15 % test and the sentence appears, while the shipped `time` still short-circuits at guard 1. F-LIFT
is used rather than the unrated fixture because it is the only seed set whose two resistance figures
both sit in the payload's own units.

| Check | Command | Result |
|---|---|---|
| new cases, Mock only | `flutter test test/cardio_efficiency_drift_signal_screen_test.dart --plain-name "Mock"` | `00:04 +9: All tests passed!` — the file's Mock harness goes 7 → 9 |
| mutation 6 applied, Mock only | same | `00:05 +8 -1: Some tests failed.` — **caught**, by the relabelled-payload case alone: `Expected: 'At similar durations, your Treadmill Run efforts are about 7% less efficient (slower pace at the same heart rate) than 4–6 weeks ago.' / Actual: '…than 4–6 weeks ago. Lifting load is 15% above your usual over the same period.'`. The all-unrated case stayed green, exactly as the reachability table above predicts. |
| restored, whole file | `flutter test test/cardio_efficiency_drift_signal_screen_test.dart` | `00:08 +17: All tests passed!` — 13 → 17, both harnesses. The adapter line is byte-identical to the copy above (`liftMeasure: mix?.measure ?? MixMeasure.time,`). |

**What the two cases do and do not pin.** The all-unrated case is a behaviour pin, not a mutation
check: it records that an unrated history measures time with no baseline, so the sentence cannot
fire, and it passes with the mutant in place. The relabelled-payload case is the mutation check, and
it is the only test in the repository that fails under mutation 6 — the rule-level S-2509 case pins
the rule's own measure guard, and no payload the shipped service emits can distinguish the adapter's
pass-through from a hard-coded `load`.

## Phase 3B — guards, residue, docs

| Check | Command | Result |
|---|---|---|
| green | `flutter test test/docs_indexing_contract_test.dart` | `00:01 +9: All tests passed!` — including `no documentation file exceeds the indexing ceiling` and `no documentation file is within the warning band of the ceiling`, so no doc is at or above 52,428 bytes. |
| size | `docs/signals.md` byte count after the edit (must stay below 52,428) | **47,366 bytes** (measured with `wc -c`; the file was 39.0 KB before this phase's edits, so the new block and the two count corrections added ~8.3 KB). Below the 52,428-byte warning band, so no split into `docs/signals/` was needed. The other four edited docs: `docs/stats_screen.md` 32,064, `docs/constants_reference.md` 24,845, `docs/state_management/services_and_utils.md` 30,506, `docs/distance_source.md` 10,791, `docs/training_load.md` 12,920 — all far below the ceiling. |
| Done Criteria suites | `flutter test test/cardio_efficiency_drift_test.dart test/cardio_efficiency_service_test.dart test/cardio_efficiency_drift_signal_screen_test.dart test/distance_source_test.dart test/signals_framework_test.dart test/docs_indexing_contract_test.dart` | `00:09 +142: All tests passed!` |
| full | `flutter test` | `05:12 +3852 ~1: All tests passed!` — the Phase 3A baseline was `+3833 ~1`, so this phase adds 19: the eligibility table's 16 cases (4 sources × 2 heart-rate states × 2 harnesses) and the copy guard's 3. No regressions; the known order-dependent `test/food_photo_clear_legacy_edit_test.dart` passed in this run. |

### Residue sweep

The gateway exposes no search verb, so every check below is a **reading or diff check**, not a
test. Each row says which. Nothing here is inferred from a passing suite.

| Sweep | Method | Result |
|---|---|---|
| `cardio_efficiency_drift.dart` imports | reading the file's import block | **`training_load.dart` only.** The plan's step 3 and D-1801 both say "`training_load.dart` and `signals.dart`"; the file imports `training_load.dart` and nothing else. `signals.dart` is not needed — the rule returns its own `CardioEfficiencyDriftResult` and never names a `Signal`, `SignalKind` or `SignalContext`; the adapter owns the kind. No unused import was added to satisfy the plan text. |
| `cardioEfficiencyDrift` / `cardioEfforts` outside the three production files | `git-diff 91295d2 --name-only` (both identifiers are new in this PR, so any file naming them is in the diff) | **Four production files, and no others.** `lib/core/models/cardio_efficiency_drift.dart` (the rule), `lib/core/services/stats_progress_service.dart` (`cardioEfforts`), `lib/core/services/signals/cardio_efficiency_drift_signal.dart` (the adapter) and `lib/core/services/signals/signal_registry.dart` (the one line). The remaining diff entries are the three test files, the two guard files, the plan and this evidence file. No framework file, no `watch/` file, no `lib/data/` file, and no 8a/8b/9a file appears in the diff. |
| `DistancePairing.forEntries` callers in `stats_progress_service.dart` | reading the `cardioEfforts` diff hunk | **One caller added, no second pairing.** The hunk adds exactly one `DistancePairing.forEntries(distanceRows: …, entryCount: …)` call, inside `cardioEfforts`, and the method's own doc comment names D-324 as the pairing it reuses. No other line in the hunk touches a pairing, a sensor index or a history walk. |
| literal `nutritionTrend` in `stats_progress_service.dart` | reading the `cardioEfforts` diff hunk | **Absent.** The hunk's only added identifiers are `cardioEfforts`, `CardioEffort`, `DistancePairing`, `DistanceSource`, `SensorSummary`, `TimedState` and `_exerciseById`; the string `nutritionTrend` does not appear in any added line. The retired-name sweep is `test/stats_legacy_removal_test.dart` (`S-1263`), which is green in the full run below. |

### Mutation checks

The two new guards were written red-first. Each was proved to fail by mutating the production line
it pins, then the exact original line was restored and the suite re-run green. The original lines are
copied here **before** the mutation, as the brief requires.

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 7 | drop the estimate guard in `stats_progress_service.dart` — the original line is `            if (DistanceSource.isEstimated(row?.valueSource)) continue;` | the eligibility table's `a estimated distance with a heart rate` | PASS — `+14 -2: Some tests failed.` The case failed in **both** harnesses (`Mock — cardioEfforts` and `Hive — cardioEfforts`), each `Expected: an object with length of <0> / Actual: … has length of <1>`. Restored byte-identically (`git-diff` on the file empty); re-ran green. |
| 8 | write the span as a literal in `cardio_efficiency_drift.dart` — the original is `  final span =\n      '$kCardioEfficiencyReferenceWeeksTo–$kCardioEfficiencyReferenceWeeksFrom';`, mutated to `  const span = '4–6';` | `the copy structural guards` › `the span is derived from the two week constants, not written` | PASS — `+2 -1: Some tests failed.` The source scan found the `4–6` literal and the missing interpolation. Restored byte-identically; re-ran green. |
| 9 | put a banned word in the suggestion — the original is `    suggestion: 'An easier week is one option.',`, mutated to a sentence containing `fatigue` | `the copy structural guards` › `the observation, the optional sentence and the suggestion are exact` and `the copy carries no banned word` | PASS — `+1 -2: Some tests failed.` Both the exact-string case and the banned-word case failed. Restored byte-identically (`git-diff` on both production files empty); re-ran green. |

Post-restore: `flutter test test/cardio_efficiency_drift_test.dart
test/cardio_efficiency_service_test.dart` = `+60: All tests passed!`, and
`test/cardio_efficiency_drift_signal_screen_test.dart` = `+17: All tests passed!`.

## Doc-claim-to-test table

Every behavioural sentence added to `docs/` in Phase 3B, with the test that proves it. A sentence
with no test is deleted, not kept.

| Doc | Claim | Test |
|---|---|---|
| `docs/signals.md` | Six cautions are registered, in ascending priority, Cardio Efficiency Drift first | `test/interference_test.dart` › `the caution order holds and the registry is ordered by it` |
| `docs/signals.md` | When two cautions qualify together the framework draws the higher priority first, so Sustained High Load renders above Cardio Efficiency Drift | `test/cardio_efficiency_drift_signal_screen_test.dart` › `S-2511 two cautions qualifying` › `renders the higher-priority caution above the Cardio Efficiency Drift card` |
| `docs/signals.md` | The registry lists exactly the seven shipped signals, in order | `test/modality_mix_shift_signal_screen_test.dart` › `the registry` › `lists exactly the seven shipped signals, in order` |
| `docs/signals.md` | The two windows are local calendar spans, and an effort belongs to the window its own start falls in | `test/cardio_efficiency_drift_test.dart` › `D-1801 the two windows are local calendar spans`; `S-2508 the window edges, and a gap effort changes nothing` |
| `docs/signals.md` | An eligible effort needs a measured distance and an instance-scope heart rate; a row with no source stays eligible | `test/cardio_efficiency_service_test.dart` › `Mock — cardioEfforts` › `the eligibility table` › `a estimated distance with a heart rate`, `a no source distance with a heart rate` |
| `docs/signals.md` | Efficiency is distance per heart-rate-minute | `test/cardio_efficiency_drift_test.dart` › `D-1803 the efficiency is distance per heart-rate-minute` |
| `docs/signals.md` | Grouping is anchored at the shortest member, bounded by the tolerance constant, with no chaining | `test/cardio_efficiency_drift_test.dart` › `S-2506 A the ±10% boundary groups inclusively`, `S-2506 C 30 and 45 minutes never merge`, `S-2506 D a middle duration does not chain 480 s to 529 s` |
| `docs/signals.md` | The comparison never crosses exercises | `test/cardio_efficiency_drift_test.dart` › `S-2507 different exercises are never compared` |
| `docs/signals.md` | The drift test is exact cross-multiplication, boundary inclusive | `test/cardio_efficiency_drift_test.dart` › `S-2502 the 5% boundary is inclusive` |
| `docs/signals.md` | One card, the largest drift | `test/cardio_efficiency_drift_test.dart` › `S-2510 one card, the largest drift` |
| `docs/signals.md` | The lifting sentence needs a load-measured payload, a positive baseline and the rise constant, compared per day | `test/cardio_efficiency_drift_test.dart` › `S-2509 the lifting sentence fires only at 15% or more`; `test/cardio_efficiency_drift_signal_screen_test.dart` › `the payload's own measure` › `a time-measured payload that still carries a baseline never earns the lifting sentence` |
| `docs/signals.md` | The card fires on the drift alone; a lift rise with no drift shows nothing | `test/cardio_efficiency_drift_signal_screen_test.dart` › `the payload's own measure` › `an all-unrated history measures time and carries no baseline, so no sentence` |
| `docs/signals.md` | Kind is caution; priority is the bottom of the caution order | `test/cardio_efficiency_drift_test.dart` › `the constant contracts`; `test/interference_test.dart` › `the caution order holds and the registry is ordered by it` |
| `docs/signals.md` | The copy is exact, the span is derived from the two week constants, and no banned word appears | `test/cardio_efficiency_drift_test.dart` › `S-2501 four comparable runs, 7% worse, fires with the exact copy`; `the copy structural guards` › `the observation, the optional sentence and the suggestion are exact`, `the span is derived from the two week constants, not written`, `the copy carries no banned word` |
| `docs/signals.md` | The adapter walks no history of its own and calls no PR API | `test/cardio_efficiency_service_test.dart` › `S-2508 the span is the caller's, ordered by start`, `S-2512 Hive and Mock return identical eligible efforts`; `test/cardio_efficiency_drift_signal_screen_test.dart` › `S-2501 the card on the layer` › `the service reads the eight efforts and the rule reports 7%` |
| `docs/stats_screen.md` | `buildSignalRegistry()` lists seven | `test/modality_mix_shift_signal_screen_test.dart` › `the registry` › `lists exactly the seven shipped signals, in order` |
| `docs/stats_screen.md` | The seventh signal is the Cardio Efficiency Drift, and its card renders on the layer | `test/cardio_efficiency_drift_signal_screen_test.dart` › `S-2501 the card on the layer` › `the caution card shows with S-2501's copy, the caution label and its key, below the Mix layer` |
| `docs/stats_screen.md` | The card is dismissible | `test/cardio_efficiency_drift_signal_screen_test.dart` › `S-2511 the card is dismissible` › `one tap removes the card in the tap frame, the store holds the id, and the next open is still quiet` |
| `docs/constants_reference.md` | Each `kCardioEfficiency…` constant governs the rule named beside it, and `kTrainingLoadBaselineWeeks` is shared | `test/cardio_efficiency_drift_test.dart` › `the constant contracts` |
| `docs/constants_reference.md` | The boundaries the constants set are inclusive | `test/cardio_efficiency_drift_test.dart` › `S-2502 the 5% boundary is inclusive`, `S-2503 three efforts per window is the floor`, `S-2506 A the ±10% boundary groups inclusively`, `S-2508 the window edges, and a gap effort changes nothing`, `S-2509 the lifting sentence fires only at 15% or more` |
| `docs/state_management/services_and_utils.md` | `cardioEfforts` returns eligible efforts ordered by start then instance id, over the cached history read | `test/cardio_efficiency_service_test.dart` › `S-2508 the span is the caller's, ordered by start` |
| `docs/state_management/services_and_utils.md` | Eligibility is the service's and the span is the caller's | `test/cardio_efficiency_service_test.dart` › `Mock — cardioEfforts` › `the eligibility table` › `a estimated distance with a heart rate`; `S-2505 no instance summary is never eligible` |
| `docs/state_management/services_and_utils.md` | The distance pairing is the shipped one and a row with no source is eligible | `test/cardio_efficiency_service_test.dart` › `S-2504 a gps row and a row with no source stay eligible` |
| `docs/state_management/services_and_utils.md` | A correction changes eligibility | `test/cardio_efficiency_service_test.dart` › `S-2504 a correction to entered makes the effort eligible` |
| `docs/state_management/services_and_utils.md` | Hive and Mock return identical eligible efforts | `test/cardio_efficiency_service_test.dart` › `S-2512 Hive and Mock return identical eligible efforts` |
| `docs/distance_source.md` | The cardio-efficiency read admits a distance above zero whose stored source is not the estimate, and a row with no source is eligible | `test/cardio_efficiency_service_test.dart` › `Mock — cardioEfforts` › `the eligibility table` › `a estimated distance with a heart rate` |
| `docs/distance_source.md` | A correction that changes the stored source changes that verdict | `test/cardio_efficiency_service_test.dart` › `S-2504 a correction to entered makes the effort eligible` |
| `docs/training_load.md` | The Cardio Efficiency Drift lifting comparison is the one caller that compares the payload's resistance segments per day | `test/cardio_efficiency_drift_test.dart` › `S-2509 the lifting sentence fires only at 15% or more` |

## Closing

| Check | Result |
|---|---|
| `flutter analyze` | `196 issues found. (ran in 7.1s)` — the pre-existing baseline, 0 errors, and 0 issues in any file this phase touched (the five docs and the two guard test files) |
| full `flutter test` | `05:12 +3852 ~1: All tests passed!` — Phase 3A's `+3833` plus this phase's 19 new cases (16 eligibility + 3 copy guards) |
| diff vs Predicted Files | **Matches, with one addition the plan allowed.** Predicted: `test/cardio_efficiency_drift_test.dart` (EDIT), `test/cardio_efficiency_service_test.dart` (EDIT), `docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`, `docs/state_management/services_and_utils.md`, `docs/distance_source.md` (EDIT), `docs/training_load.md` (EDIT only if step 8 needed it). All eight are edited. `docs/training_load.md` **was** edited: the lifting comparison is the one `computeMixPeriod` caller that compares the payload's resistance segments per day, which is a fact about the shared entry point that belongs in its own document. No out-of-bounds file was touched: `git-status` shows only the two guard test files modified on top of the committed PR, and `git-diff 91295d2 --name-only` lists exactly the 11 PR files plus the two plan artefacts. |
