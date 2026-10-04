# Evidence — Sustained High Load (Stats PR 9a)

> Companion to `2026-10-04-09a-stats-pr9a-sustained-high-load-plan.md`. Implementers write here;
> nothing from this file goes into the plan. One section per phase, filled as the phase runs.

## Opening baselines (measure before Phase 1, on the branch)

| Command | Result |
|---|---|
| `flutter analyze` | `196 issues found. (ran in 7.0s)` — 0 errors |
| `flutter test` | `+3731 ~1: All tests passed!` |

Known and untouched: `test/food_photo_clear_legacy_edit_test.dart` is order-dependent in a full run
and passes on re-run.

## Phase 1 — the pure rule

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/sustained_high_load_test.dart` | FAILS TO COMPILE as expected: `Error when reading 'lib/core/models/sustained_high_load.dart': No such file or directory` plus every symbol undefined (`kSustainedHighLoadPriority`, `sustainedHighLoadBaseline`, `sustainedHighLoadStreak`, `sustainedHighLoadEasierGapWeeks`, `sustainedHighLoad`, `sustainedHighLoadCopy`). `00:00 +0 -1: Some tests failed.` |
| green | `flutter analyze` | `196 issues found. (ran in 7.0s)` — 0 errors, no issue in either new file (identical to the baseline) |
| green | `flutter test test/sustained_high_load_test.dart test/training_load_test.dart` | `00:00 +60: All tests passed!` (10 new + 50 existing) |
| full | `flutter test` | `04:57 +3742 ~1: All tests passed!` (baseline `+3731 ~1` + the 11 added tests) |

### Mutation checks

Originals, copied before each edit:

- check 1 original: `}) => week.loadMinutes * 100 >= usual * kSustainedHighLoadHigherPercent;`
- check 2 original: `  return gaps[(gaps.length - 1) ~/ 2];`

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 1 | higher-load `>=` → `>` | S-2402 (exactly 110%) | RED: `Expected: <5> Actual: <4>` — `00:00 +0 -1: Some tests failed.` Restored, `S-2402` green again (`00:00 +1: All tests passed!`). |
| 2 | median `(n-1)~/2` → `n~/2` | S-2408 (expects 3, would report 5) | RED: `Expected: <3> Actual: <5>` — `00:00 +0 -1: Some tests failed.` Restored, full new suite green (`00:00 +10: All tests passed!`). |

### Final re-verification (after both mutations were reverted)

| Check | Command | Result |
|---|---|---|
| lint | `flutter analyze` | `196 issues found. (ran in 7.0s)` — 0 errors, no issue in either new file |
| suites | `flutter test test/sustained_high_load_test.dart test/training_load_test.dart` | `00:00 +60: All tests passed!` |
| full | `flutter test` | `05:10 +3742 ~1: All tests passed!` |
| revert proof | `sustained_high_load.dart:138,224` | `>= usual * kSustainedHighLoadHigherPercent` and `gaps[(gaps.length - 1) ~/ 2]` — both originals in place |
| diff | `git status --short` | only the four predicted files plus this plan and this evidence file |

## Phase 2 — the service read

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/sustained_high_load_service_test.dart` | FAILS TO COMPILE as expected: `The method 'weeklyLoads' isn't defined for the type 'StatsProgressService'` (8 sites) and `The method 'startOfWeekSetting' isn't defined …` (6 sites). `00:00 +0 -1: Some tests failed.` |
| green | `flutter test test/sustained_high_load_service_test.dart test/training_load_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/stats_progress_test.dart` | `00:07 +170: All tests passed!` (17 new + 153 existing) |
| lint | `flutter analyze` | `196 issues found. (ran in 7.9s)` — 0 errors, identical to the baseline, no issue in `stats_progress_service.dart` or the new test file |
| full | `flutter test` | `05:19 +3759 ~1: All tests passed!` (baseline `+3742 ~1` + the 17 added tests) |

### Mutation checks

Originals, copied before each edit:

- check 3 original:
  ```
      while (weekStart.millisecondsSinceEpoch <
          currentWeekStart.millisecondsSinceEpoch) {
  ```
- check 4 original:
  ```
        WeeklyLoad(
          weekStart: weekStart,
          loadMinutes: loadByWeekStartMs[weekStartMs] ?? 0.0,
          hasRatedSession: ratedWeekStartsMs.contains(weekStartMs),
        ),
  ```

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 3 | include the week containing `now` | S-2411 | RED: all four S-2411 cases `Expected: an object with length of <17> Actual: … has length of <18>` — `00:01 +0 -4: Some tests failed.` Restored, suite green again (`00:07 +170: All tests passed!`). |
| 4 | drop empty weeks from the list | S-2401 service case (usual changes) | RED: `Expected: an object with length of <17> … has length of <15>` and the rule case `Expected: <5> Actual: <0>` (streak) — `00:01 +0 -4: Some tests failed.` Restored, suite green again (`00:07 +170: All tests passed!`). |

## Phase 3A — the card, the registry, the guards

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/sustained_high_load_signal_screen_test.dart --plain-name "Mock"` | `00:04 +4 -3: Some tests failed.` — the three card scenarios fail on the missing registration: `Found 0 widgets with key [<'signal_card_sustained-high-load'>]` (S-2412 card, dismissal) and, in the two-caution fixture, Protein Consistency renders while `signal_card_sustained-high-load` is absent. The four abstention/measure cases pass (they assert absence, so they are green before and after). |
| green | same, Mock-first | `00:04 +7: All tests passed!` |
| green | whole new file (Mock + Hive) | `00:07 +13: All tests passed!` |
| green | `flutter test test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart` | `00:07 +45: All tests passed!` |
| green | `flutter test test/signals_framework_test.dart test/signals_service_test.dart` (with the four signal screen suites) | `00:10 +69` — every suite green. (One further path in that command, `test/stats_screen_test.dart`, does not exist and failed to load; re-run without it below.) |
| green | `flutter test test/signals_framework_test.dart test/signals_service_test.dart test/signals_layer_screen_test.dart test/interference_signal_screen_test.dart test/mix_layer_screen_test.dart test/screen_widget_test.dart test/screen_overflow_contract_test.dart test/stats_legacy_removal_test.dart test/stats_progress_test.dart test/sustained_high_load_service_test.dart test/sustained_high_load_test.dart` | `00:59 +513 -3` — the only three failures are S-2013 in `test/interference_signal_screen_test.dart` (see the blocker below). `signals_framework_test.dart` and `signals_service_test.dart` are green. |
| lint | `flutter analyze` | `196 issues found. (ran in 8.2s)` — identical to the baseline, 0 errors, no issue in `sustained_high_load_signal.dart`, `signal_registry.dart` or the new test file |
| full | `flutter test` | `05:12 +3769 ~1 -3: Some tests failed.` — baseline `+3759 ~1` plus the 13 added tests minus the 3 S-2013 failures; no other failure anywhere |

### Blocker: S-2013 (PR 7b's screen fixture) now also qualifies for this signal

`test/interference_signal_screen_test.dart` is red, and it is not in the plan's Predicted Files.

| Test | Failure |
|---|---|
| Mock/Hive `S-2013 the card on the layer …` | `Expected: exactly one matching candidate / Actual: Found 2 widgets with text "Worth a look" / Which: is too many` (`interference_signal_screen_test.dart:430`) |
| Mock `S-2013 the card is dismissible …` | `Found 0 widgets with key [<'signals_quiet_line'>]` (`:494`) — after Interference is dismissed the Sustained High Load card is still on the layer, so there is no quiet line |

The cause is F-INT's own load history, which satisfies the new rule (a run of weeks above its usual
with no easier week) as well as Interference. Nothing in the adapter is wrong: the card the rule
returns is the correct card for that history. Confirmed self-contained — the suite fails the same
three ways when run alone. It passed in Phase 2's full run (`+3759 ~1`), so the registry line is
what changed it. It cannot be fixed in the new test file, so Phase 3A was **Blocked (scope)** —
resolved by the governor's decision below.

### Resolution of the S-2013 blocker (governor decision, technical call)

Decision: **scope the assertions to Interference's own card; change no fixture, registry, seam or
production code.** The fixture stays on the real registry — "Interference is the only card on the
layer" is not a property of Interference.

Edits to `test/interference_signal_screen_test.dart` (12 changed lines):

1. `the caution card shows with the exact copy, the caution label and its key, below the Mix layer`:
   the caution-label expectation is now card-scoped — `find.descendant(of:
   find.byKey(const Key(_kCardKey)), matching: find.text(_kCautionLabel))`. The `signals_quiet_line`
   `findsNothing`, the `_cardKeys().first` priority check and the geometry are unchanged.
2. `one tap removes the card in the tap frame, the store holds the id, and the next open still hides
   it` (renamed from `… the next open is still quiet`): the two `signals_quiet_line` `findsOneWidget`
   expectations were deleted. The card-key `findsNothing` assertions, the dismissal-store assertion
   and the tooltip assertion are kept.

The sole-card dismissal-to-quiet-line behaviour is still asserted in
`test/signals_layer_screen_test.dart`, group `S-1709 dismissing removes the card at once`, test
`one tap removes that card, keeps the other, writes the store and re-evaluates nothing`: after the
one remaining card (`signal_card_p-1`) is dismissed, `signals_quiet_line` is `findsOneWidget`.
Gateway-verified: `flutter test test/signals_layer_screen_test.dart --plain-name "S-1709"` →
`00:03 +2: All tests passed!`.

| Check | Command | Result |
|---|---|---|
| Mock-first | `flutter test test/interference_signal_screen_test.dart --plain-name "Mock"` | `00:04 +3: All tests passed!` |
| whole file | `flutter test test/interference_signal_screen_test.dart` | `00:05 +5: All tests passed!` |
| full | `flutter test` | `05:15 +3772 ~1: All tests passed!` (baseline `+3759 ~1` + the 13 added tests, no failure anywhere) |
| diff | `git-diff --stat -- test/interference_signal_screen_test.dart` | `1 file changed, 8 insertions(+), 4 deletions(-)` |
| lint | `flutter analyze` | `196 issues found. (ran in 8.6s)` — identical to the baseline, 0 errors |

### Mutation checks

Originals, copied before each edit:

- check 5 original: `SustainedHighLoadSignal(),` as the first entry of the const list in `signal_registry.dart`
- check 6 original: `    final mixShowsLoad = mix != null && mix.measure == MixMeasure.load;`

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 5 | registry entry moved to the end | both registry guards | RED: both `at location [0] is 'protein-consistency' instead of 'sustained-high-load'` — `interference_test.dart:1092` and `modality_mix_shift_signal_screen_test.dart:621`; `00:07 +43 -2: Some tests failed.` Restored, both green again (`00:07 +45: All tests passed!`). |
| 6 | Mix gate ignores the measure (`mixShowsLoad = true`) | S-2410(b) | RED: `the card does not appear and the layer is quiet` fails with `Found 0 widgets with key [<'signals_quiet_line'>]` — the card wrongly appears; `00:03 +1 -1: Some tests failed.` Restored, the five 3A suites green again (`00:07 +85: All tests passed!`). |

## Phase 3B — guards, residue, docs

### Mutation checks

The two guards passed on first write (they pin behaviour Phases 1-3A already shipped), so each was
given a mutation that must make it fail. Originals copied before each edit:

- check 7 original: `  SustainedHighLoadSignal(),` — first entry of the const list in `signal_registry.dart`
- check 8 original: `    'training load, with no easier week.',` — the observation's second line
- check 9 original: `    suggestion: 'An easier week is one option.',`

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 7 | registry entry moved to the end of the const list | `the registry lists the cautions in strictly ascending priority` | RED: `Expected: a value greater than <500> Actual: <100> — sustained-high-load (100) must sit after cross-modality-interference (500)`, `test/sustained_high_load_test.dart:277`, `00:00 +0 -1: Some tests failed.` Restored; `git-diff` on the file is empty. |
| 8 | observation reworded: `with no easier week.` → `and no easier week in that run.` | `the copy is the exact shipped wording` | RED: `is different … Differ at offset 63`, `test/sustained_high_load_test.dart:294`, `00:00 +0 -1: Some tests failed.` Restored. |
| 9 | causal word inserted into the suggestion: `'An easier week is one option, because fatigue builds up.'` | `the copy carries no amount, no percentage and no causal word` | RED: `Expected: not contains 'fatigue' Actual: 'an easier week is one option, because fatigue builds up.'`, `test/sustained_high_load_test.dart:366`, `00:00 +0 -1: Some tests failed.` Restored. |

After all three restores: `git-diff` on both mutated files is empty and the file is green again —
`00:00 +13: All tests passed!`.

| Check | Command | Result |
|---|---|---|
| green | `flutter test test/sustained_high_load_test.dart` | `00:00 +13: All tests passed!` (10 pre-existing + 3 new) |
| size | `docs/signals.md` byte count (limit 52,428) | **39,952 bytes** after the edit (was 34,099). Read-only byte count; the gateway has no such verb. 12,476 bytes of headroom. |
| done criteria | `flutter test test/sustained_high_load_test.dart test/sustained_high_load_service_test.dart test/sustained_high_load_signal_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/docs_indexing_contract_test.dart` | `00:11 +91: All tests passed!` (re-run after the plan and evidence edits: same `+91`) |
| lint | `flutter analyze` | `196 issues found. (ran in 8.0s)` — identical to the baseline, 0 errors, and no issue mentions `sustained_high_load` |
| full | `flutter test` | `05:15 +3775 ~1: All tests passed!` — baseline `+3772 ~1` plus the three new guards; no other change |

### Residue sweep

Read-only sweep of the PR 9a diff (`git-diff c42e526`) plus the files it names. Every row below is
a check by **reading**; the ones also covered by a test are marked.

| Sweep | Result |
|---|---|
| `sustained_high_load.dart` imports | `training_load.dart` only. That is a **subset** of D-1701's allowed set (which also permits `signals.dart`); the rule needs no signal type, so the narrower import is the shipped one (Assumption Log #1). |
| `sustainedHighLoad` mentioned outside the three production files | Tests and docs only. Tests: the three new 9a suites plus the two registry id-lists updated in 3A (`test/interference_test.dart`, `test/modality_mix_shift_signal_screen_test.dart`). No framework file names it. |
| literal `nutritionTrend` in `stats_progress_service.dart` | Absent. The file's diff adds only `startOfWeekSetting()` and `weeklyLoads()`; it gains no reader of the replaced representation (`S-1263`). |
| framework files absent from the PR diff | Confirmed: `lib/core/services/signals/signal.dart`, `lib/core/models/signals.dart`, `lib/core/services/signals_service.dart` and `test/signals_framework_test.dart` are all absent from the 14-file list. |
| `watch/` absent | Confirmed: no path under `watch/` appears in the diff. |
| `lib/data/` absent | Confirmed: no path under `lib/data/` appears in the diff. |
| 8a/8b files absent | Confirmed: no `protein_consistency*`, `fuel_vs_load*`, `progression_rate*` or `nutrition*` path appears in the diff. |
| `Cardio Efficiency Drift` absent | Confirmed: no such path, id or name in the diff. PR 9b does not exist yet. |
| the three new production files | Exactly `lib/core/models/sustained_high_load.dart` (new), `lib/core/services/signals/sustained_high_load_signal.dart` (new), `lib/core/services/signals/signal_registry.dart` (+1 line), `lib/core/services/stats_progress_service.dart` (+74 lines), `lib/core/models/training_load.dart` (+20 lines). |
| `interference_signal_screen_test.dart` | Untouched in 3B; its 3A edit scoped S-2013's assertions to Interference's card and is unchanged here. |


## Doc-claim-to-test table

Every behavioural sentence added to `docs/` in Phase 3B, with the test that proves it. A sentence
with no test is deleted, not kept.

| Doc | Claim | Test |
|---|---|---|
| `docs/signals.md` | five cautions are registered, in ascending priority, Sustained High Load first | `test/sustained_high_load_test.dart` (`the registry lists the cautions in strictly ascending priority`); `test/interference_test.dart` (`the caution order holds and the registry is ordered by it`) |
| `docs/signals.md` | the list is the priority order, not the render order: the higher priority renders first, so Protein Consistency sits above Sustained High Load | `test/sustained_high_load_signal_screen_test.dart` (`S-2412 two cautions qualifying` › `renders the higher-priority caution above the Sustained High Load card`) |
| `docs/signals.md` | the rule reads completed weeks only, the week containing `now` never among them | `test/sustained_high_load_service_test.dart` (`S-2411 the incomplete current week is never counted`, `S-2411 the current week holding nothing changes nothing`); `test/training_load_test.dart` (`WeeklyLoad (D-1702) sums its sessions and an empty week is zero`) |
| `docs/signals.md` | a candidate's baseline is the twelve weeks strictly before it, an empty week counting as zero, and fewer than twelve preceding weeks means no baseline | `test/sustained_high_load_test.dart` (`the baseline stage abstains below twelve earlier weeks`) |
| `docs/signals.md` | the baseline needs `kSustainedHighLoadMinRatedWeeks` rated weeks, inclusive | `test/sustained_high_load_test.dart` (`S-2404 the rated-history floor, and the twelve-week requirement`) |
| `docs/signals.md` | a higher-load week reaches `kSustainedHighLoadHigherPercent` of the usual, inclusive, by exact cross-multiplication | `test/sustained_high_load_test.dart` (`S-2402 the 110% boundary is inclusive`) |
| `docs/signals.md` | the streak is the largest run of consecutive higher-load weeks whose own baseline clears the rated floor, and a run shorter than the floor never fires | `test/sustained_high_load_test.dart` (`S-2403 four weeks is not five`, `S-2405 a 105% week resets the count at that week`) |
| `docs/signals.md` | the card shows only when the Mix layer measures the streak's own span in load | `test/sustained_high_load_signal_screen_test.dart` (`S-2410(b) the streak period measures time` › `the rule qualifies but the period the adapter reads is time`, `the card does not appear and the layer is quiet`) |
| `docs/signals.md` | the history fact reports the median gap between earlier easier weeks under its gap band, the lower middle one on an even count, and is absent otherwise | `test/sustained_high_load_test.dart` (`S-2406 the easier boundary, and an ordinary week that is neither`, `S-2407 the history fact shows the interval`, `S-2408 the even-count median is the lower one`, `S-2409 the fact is absent when the habit is not there`) |
| `docs/signals.md` | the kind is caution and the priority is `kSustainedHighLoadPriority`, the bottom of the caution order | `test/sustained_high_load_test.dart` (`the constant contracts`); `test/interference_test.dart` (`the caution order holds and the registry is ordered by it`) |
| `docs/signals.md` | the copy names the run's own week count, appends the fact's sentence only when the fact fired, and carries no amount, percentage or causal claim | `test/sustained_high_load_test.dart` (`S-2407 the history fact shows the interval`, `the copy is the exact shipped wording`, `the copy carries no amount, no percentage and no causal word`); `test/sustained_high_load_signal_screen_test.dart` (`S-2412 the card on the layer` › `the caution card shows with S-2401's copy, the caution label and its key, below the Mix layer`) |
| `docs/signals.md` | the definition reads no clock, repository or service; the adapter reads `weeklyLoads` and one `computeMixPeriod` payload and walks no history of its own | `test/sustained_high_load_service_test.dart` (`S-2401 the service's weeks feed the rule the pack's figures`); `test/sustained_high_load_signal_screen_test.dart` (`S-2412 the card on the layer` › `the caution card shows with S-2401's copy, the caution label and its key, below the Mix layer`) |
| `docs/signals.md` | Protein Consistency sits above Sustained High Load and below Fuel vs Load | `test/protein_consistency_test.dart` (`the constant contracts`); `test/modality_mix_shift_signal_screen_test.dart` (`the registry lists exactly the six shipped signals, in order`) |
| `docs/stats_screen.md` | the registry lists six signals | `test/modality_mix_shift_signal_screen_test.dart` (`the registry lists exactly the six shipped signals, in order`) |
| `docs/stats_screen.md` | the sixth signal reports weeks above usual with no easier week, its copy built by `sustainedHighLoadCopy` | `test/sustained_high_load_signal_screen_test.dart` (`S-2412 the card on the layer` › `the caution card shows with S-2401's copy, the caution label and its key, below the Mix layer`, `S-2412 the card is dismissible` › `one tap removes the card in the tap frame, the store holds the id, and the next open is still quiet`); `test/sustained_high_load_test.dart` |
| `docs/constants_reference.md` | each named constant's rule, and the inclusive boundaries | `test/sustained_high_load_test.dart` (the constant contracts and S-2402–S-2409) |
| `docs/state_management/services_and_utils.md` | a week's load is the session split's own load components summed over the sessions of that week | `test/sustained_high_load_service_test.dart` (`S-2401 the service's weeks feed the rule the pack's figures`) |
| `docs/state_management/services_and_utils.md` | the series runs from the earliest completed week to the week before `now`'s, empty weeks present, an empty history yielding an empty list | `test/sustained_high_load_service_test.dart` (`D-1702 an empty week between sessions is present`, `D-1703 no completed session yields an empty list`, `S-2401 the service returns the seventeen completed weeks`, `S-2411 the incomplete current week is never counted`) |
| `docs/state_management/services_and_utils.md` | the boundaries follow the saved start-of-week setting, which is the value `SettingsState` writes | `test/sustained_high_load_service_test.dart` (`S-2413 the saved start-of-week moves the boundaries`, `S-2413 SettingsState writes the value the service reads`) |
| `docs/state_management/services_and_utils.md` | the two reads are one walk of the cached snapshot, identical under both repositories | `test/sustained_high_load_service_test.dart` (`S-2414 Hive and Mock return identical week lists`) |
| `docs/training_load.md` | a week's load is the Mix layer's own figure and a week's start follows the saved start-of-week setting | `test/training_load_test.dart` (`WeeklyLoad (D-1702) sums its sessions and an empty week is zero`, `OmniDateUtils.startOfWeek (D-910, D-935)`); `test/sustained_high_load_service_test.dart` (`S-2401 the service's weeks feed the rule the pack's figures`) |
| `docs/training_load.md` | the weekly baseline is twelve consecutive entries of the same series, not `baselineBlockStarts` | `test/sustained_high_load_test.dart` (`the baseline stage abstains below twelve earlier weeks`); `test/training_load_test.dart` (`baselineBlockStarts (D-934)`) |

## Closing

> Phase 1 rows below are the Phase 1 final re-verification; Phases 2 and 3 re-run the full suite and
> re-fill these at the end of the PR.

| Check | Result |
|---|---|
| `flutter analyze` | Phase 1: `196 issues found. (ran in 7.0s)` — 0 errors, no issue in either new file |
| full `flutter test` | Phase 1: `05:10 +3742 ~1: All tests passed!` (baseline `+3731 ~1` + the 11 added tests) |
| diff vs Predicted Files | Phase 1: exactly the four predicted paths — `lib/core/models/sustained_high_load.dart` (new), `test/sustained_high_load_test.dart` (new), `lib/core/models/training_load.dart` (edit), `test/training_load_test.dart` (edit) |

### Phase 3B closing re-verification

| Check | Result |
|---|---|
| `flutter analyze` | `196 issues found. (ran in 8.0s)` — 0 errors, unchanged from the baseline, no issue mentions `sustained_high_load` |
| full `flutter test` | `05:15 +3775 ~1: All tests passed!` — Phase 3A's `+3769 ~1 -3` plus the three S-2013 fixes (committed in `becb06d`) is the `+3772 ~1` baseline, plus the three new guards. No other movement. |
| diff vs Predicted Files | exactly the predicted paths: `test/sustained_high_load_test.dart` (EDIT — the three guards) and the five docs (`docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`, `docs/state_management/services_and_utils.md`, `docs/training_load.md`). Nothing else in the working tree. |
| no mutation left applied | `git-diff` on `signal_registry.dart` and `sustained_high_load.dart` is empty |

