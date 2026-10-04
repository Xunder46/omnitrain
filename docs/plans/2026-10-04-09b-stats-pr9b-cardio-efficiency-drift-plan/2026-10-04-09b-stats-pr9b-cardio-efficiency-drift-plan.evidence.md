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
| green | `flutter test test/docs_indexing_contract_test.dart` | _to fill_ |
| size | `docs/signals.md` byte count after the edit (must stay below 52,428) | _to fill_ |
| full | `flutter test` | _to fill_ |

### Residue sweep

| Sweep | Result |
|---|---|
| `cardio_efficiency_drift.dart` imports | _to fill_ (must be `training_load.dart`, `signals.dart` only) |
| `cardioEfficiencyDrift` / `cardioEfforts` mentioned outside the three production files | _to fill_ (must be tests and docs only) |
| `DistancePairing.forEntries` callers in `stats_progress_service.dart` | _to fill_ (one added, no second pairing introduced) |
| literal `nutritionTrend` in `stats_progress_service.dart` | _to fill_ (must be absent — `S-1263`) |

## Doc-claim-to-test table

Every behavioural sentence added to `docs/` in Phase 3B, with the test that proves it. A sentence
with no test is deleted, not kept.

| Doc | Claim | Test |
|---|---|---|
| `docs/signals.md` | _to fill_ | _to fill_ |
| `docs/stats_screen.md` | _to fill_ | _to fill_ |
| `docs/constants_reference.md` | _to fill_ | _to fill_ |
| `docs/state_management/services_and_utils.md` | _to fill_ | _to fill_ |
| `docs/distance_source.md` | _to fill_ | _to fill_ |
| `docs/training_load.md` (only if edited) | _to fill_ | _to fill_ |

## Closing

| Check | Result |
|---|---|
| `flutter analyze` | `196 issues found. (ran in 7.3s)` — the pre-existing baseline, 0 errors, and 0 issues in either file this run touched |
| full `flutter test` | `04:57 +3833 ~1: All tests passed!` — Phase 3A's `+3829` plus this run's four new cases (two per harness), re-run after `dart format` |
| diff vs Predicted Files | _to fill_ |
