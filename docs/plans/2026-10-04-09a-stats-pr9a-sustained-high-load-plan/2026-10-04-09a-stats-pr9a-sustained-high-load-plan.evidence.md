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

| Check | Command | Result |
|---|---|---|
| green | `flutter test test/docs_indexing_contract_test.dart` | _to fill_ |
| size | `docs/signals.md` byte count (limit 52,428) | _to fill_ |
| full | `flutter test` | _to fill_ |

### Residue sweep

| Sweep | Result |
|---|---|
| `sustained_high_load.dart` imports | _to fill_ (must be `training_load.dart`, `signals.dart` only) |
| `sustainedHighLoad` mentioned outside the three production files | _to fill_ (must be tests and docs only) |
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
| `docs/training_load.md` | _to fill_ | _to fill_ |

## Closing

> Phase 1 rows below are the Phase 1 final re-verification; Phases 2 and 3 re-run the full suite and
> re-fill these at the end of the PR.

| Check | Result |
|---|---|
| `flutter analyze` | Phase 1: `196 issues found. (ran in 7.0s)` — 0 errors, no issue in either new file |
| full `flutter test` | Phase 1: `05:10 +3742 ~1: All tests passed!` (baseline `+3731 ~1` + the 11 added tests) |
| diff vs Predicted Files | Phase 1: exactly the four predicted paths — `lib/core/models/sustained_high_load.dart` (new), `test/sustained_high_load_test.dart` (new), `lib/core/models/training_load.dart` (edit), `test/training_load_test.dart` (edit) |

