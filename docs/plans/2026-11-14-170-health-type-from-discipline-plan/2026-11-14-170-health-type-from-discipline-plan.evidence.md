# Plan 170 — evidence

Plan: `2026-11-14-170-health-type-from-discipline-plan.md`. Every run below is
`.github/copilot/scripts/macos/gateway.sh`; the long outputs are under `.work/gateway/`.

## Baselines (before this run's changes)

| What | Baseline | Source |
|---|---|---|
| `lint` | 181 issues, 0 failures | plan 168's recorded baseline; re-measured on this tree before Phase 5 |
| full `test` (HEAD) | reds limited to plan 167/168 in-flight work + `S-15207` corpus staleness | plan 168 Assumption Log; plan 169 measured `+7577 ~5 -1` with `S-15207` the only red |
| full `swift-test` | 1446 tests, 0 failures | this tree, before Phase 3 |

`S-15207 the corpus is fresh` is a **known, pre-existing red**: the replay corpus
under `watch/sync_protocol/fixtures/replay/` is stale and is regenerated only by
the `--dart-define=REPLAY_CORPUS_WRITE=true` run, which plans 160/161/163/169 list
as a **governor action** (the developer's tools may not write files through a
test). It is not caused by plan 170: `seed-408.json` carries no `healthActivity`
and the recording's `expected` classes are `status, entries, timers, current` —
the corpus records the session surface only (`kReplayFrameTypes`), so the widened
vocabulary cannot reach it.

## Phase 1 — wire contract

| Guard | Red at HEAD | Green after |
|---|---|---|
| `test/sync_protocol_fixtures_test.dart` | `RED AT HEAD (exit 1)` — `valid/exercises_down_health_activity_kinds.json conforms to exercises_down` (the new valid fixture is refused while the enum has five names) | `182 tests passed` |
| `swift-test --filter SyncProtocolFixturesTests` | — | 6 tests, 0 failures |

## Phase 2 — the store's name map

| Guard | Red first | Green after |
|---|---|---|
| `swift-test --filter WatchWorkoutStoreSourceTests` | `testS1509TheStoreMapsEveryContractActivityName` — the contract's name set and the store's `activityType(for:)` set differ | 3 tests, 0 failures |

The app-target store (`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`) cannot
be compiled by `swift test` on macOS (no `HKWorkoutActivityType`); the source-scan
guard is the only suite that reads it, which is why it is a source test.

## Phase 3 — the wrist resolves every kind

`prove-red HEAD swift-test --filter WatchHealthActivityTests -- <the two suites>`:
`RED AT HEAD (exit 1)`, `Executed 32 tests, with 74 failures (0 unexpected)`.

| After the change | Result |
|---|---|
| `WatchHealthActivityTests` focused run | 52 tests, 0 failures |

## Phase 4 — the phone derives the kind

`prove-red HEAD test test/watch_health_activity_test.dart test/watch_reference_sync_test.dart
test/conditioning_catalog_test.dart`: `RED AT HEAD (exit 1)`, `+72 -6: Some tests failed.`

| After the change | Result |
|---|---|
| the three files together | 84 tests passed |
| `test/watch_health_activity_test.dart` alone | 22 tests passed |

## Phase 5 — Dart mirror, docs, residue

`prove-red HEAD test test/watch_sensor_recording_test.dart`: `RED AT HEAD (exit 1)` —
five failures, the assertions being the renamed contract helper (three `S-16810`
null-crashes), the `S-17009` row test and `"yoga hold is yoga, not flexibility"`.

| After the change | Result |
|---|---|
| `test/watch_sensor_recording_test.dart` | 45 tests passed |

### Mutations (each restored to the exact original line, then re-run green)

| Mutation | Failure observed | Restored |
|---|---|---|
| `_kindType` in `_forExercise` made to answer `_flexibility` for unknown kinds (`?? _flexibility`) | `S-17009` inert-kind test — expected `running`, got `flexibility` | yes |
| `'discipline-yoga': 'yoga'` deleted from `healthActivityByDiscipline` | 5 tests: `S-17001` ×2, `S-17002` ×2, `S-10513` ×1 | yes |

## Final state

| Check | Result |
|---|---|
| `test` (full) | `+7626 ~4 -1: Some tests failed.` — the single red is the pre-existing `S-15207 the corpus is fresh` (`Actual: ['seed-408.json']`); against plan 169's `+7577 ~5 -1` the net is +49 passed, same one red, no new red |
| `swift-test` (full) | `Executed 1456 tests, with 0 failures (0 unexpected)`; replay differential `classes: none` (1446 → 1456 is plan 170's ten new cases) |
| `lint` | 181 issues, 0 failures — the plan-168 baseline, no new issue, none in a touched file |
| `test/ui_standards_contract_test.dart` | 41 tests, all passed |
| invariant grep (`import .*hive_workout_repository` over `lib/`) | only `lib/main.dart`, the composition root — `lib/state`, `lib/features`, `lib/widgets`, `lib/core` clean |

Not exercised: `flutter run` (not available in this mode) and the iOS app target's
HealthKit store (source-scan only, above).
