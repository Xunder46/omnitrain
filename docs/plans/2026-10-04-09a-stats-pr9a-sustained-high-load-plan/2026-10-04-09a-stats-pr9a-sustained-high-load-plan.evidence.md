# Evidence — Sustained High Load (Stats PR 9a)

> Companion to `2026-10-04-09a-stats-pr9a-sustained-high-load-plan.md`. Implementers write here;
> nothing from this file goes into the plan. One section per phase, filled as the phase runs.

## Opening baselines (measure before Phase 1, on the branch)

| Command | Result |
|---|---|
| `flutter analyze` | _to fill_ (expected: `196 issues found.`, 0 errors) |
| `flutter test` | _to fill_ (expected: `+3731 ~1: All tests passed!`) |

Known and untouched: `test/food_photo_clear_legacy_edit_test.dart` is order-dependent in a full run
and passes on re-run.

## Phase 1 — the pure rule

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/sustained_high_load_test.dart` | _to fill_ (must fail: file not found / does not compile) |
| green | `flutter analyze` | _to fill_ |
| green | `flutter test test/sustained_high_load_test.dart test/training_load_test.dart` | _to fill_ |
| full | `flutter test` | _to fill_ |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 1 | higher-load `>=` → `>` | S-2402 (exactly 110%) | _to fill_ |
| 2 | median `(n-1)~/2` → `n~/2` | S-2408 (expects 3, would report 5) | _to fill_ |

## Phase 2 — the service read

| Check | Command | Result |
|---|---|---|
| red run | `flutter test test/sustained_high_load_service_test.dart` | _to fill_ |
| green | `flutter test test/sustained_high_load_service_test.dart test/training_load_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/stats_progress_test.dart` | _to fill_ |
| full | `flutter test` | _to fill_ |

### Mutation checks

| # | Mutation | Test that must fail | Result |
|---|---|---|---|
| 3 | include the week containing `now` | S-2411 | _to fill_ |
| 4 | drop empty weeks from the list | S-2401 service case (usual changes) | _to fill_ |

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

| Check | Result |
|---|---|
| `flutter analyze` | _to fill_ |
| full `flutter test` | _to fill_ |
| diff vs Predicted Files | _to fill_ |
