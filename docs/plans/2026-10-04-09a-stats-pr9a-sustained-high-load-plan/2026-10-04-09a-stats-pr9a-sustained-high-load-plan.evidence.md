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
| red run | `flutter test test/sustained_high_load_signal_screen_test.dart --plain-name "Mock"` | _to fill_ |
| green | same, Mock-first | _to fill_ |
| guards | `flutter test test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart` | _to fill_ |
| full | `flutter test` | _to fill_ |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 5 | registry entry moved to the end | both registry guards | _to fill_ |
| 6 | `mixShowsLoad: true` unconditionally | S-2410(b) | _to fill_ |

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

