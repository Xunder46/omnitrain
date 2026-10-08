# Evidence — 18a phone hardening

Plan: `2026-10-08-18a-phone-hardening-plan.md`. Implementers append to this file; the reviewer reads
it and appends its findings. One row per checklist item, with the command and the pasted counts.

## Baselines (taken before Phase 1)

| Check | Command | Result |
|---|---|---|
| Dart tests | `.github/copilot/scripts/macos/gateway.sh test` | 4061 tests, ~1 pre-existing failure (record the exact name here when re-measured) |
| Analyzer | `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors |
| Swift tests | `.github/copilot/scripts/macos/gateway.sh swift-test` | 335 tests / 0 failures |

## Phase 1 — no `initState` notifies during build (@developer)

| Item | Command | Result |
|---|---|---|
| Post-frame deferral in `WorkoutSessionScreen` | | pending |
| Contract test `test/initstate_notify_contract_test.dart` | | pending |
| S-150 widget test | | pending |

## Phase 2 — the summary never throws (@developer)

| Item | Command | Result |
|---|---|---|
| Guard in `computeSessionRestTimeMs` | | pending |
| S-153 test | | pending |

## Phase 3 — an end is never stored before its start (@developer)

| Item | Command | Result |
|---|---|---|
| Writers clamped | | pending |
| S-155 tests | | pending |

## Phase 4 — migration 14 → 15 (@dba)

| Item | Command | Result |
|---|---|---|
| Hive step + Mock step | | pending |
| `test/data_migration_test.dart` | | pending |
| S-156 test | | pending |

## Red → green (prove-red)

| Scenario | Command | At the base | After |
|---|---|---|---|
| S-150 | `gateway.sh prove-red <base-ref> test test/session_screen_build_phase_notify_test.dart -- lib/features/session/workout_session_screen.dart` | pending | pending |
| S-153 | `gateway.sh prove-red <base-ref> test test/session_summary_inverted_window_test.dart -- lib/core/services/session_summary_service.dart` | pending | pending |
| S-155 | `gateway.sh prove-red <base-ref> test test/session_window_never_inverted_test.dart -- lib/state/workout/session_core_lifecycle.dart` | pending | pending |
| S-156 | `gateway.sh prove-red <base-ref> test test/data_migration_test.dart -- lib/core/constants/data_version.dart lib/data/repositories/hive_workout_repository.dart` | pending | pending |

## Reviewer findings

[empty — the reviewer fills this: diff versus Predicted Files, per-S-x conformance, the Impact Check
rows re-run, `WorkoutRepository` parity on the touched rows, quantified defects, Assumption Log
adjudication.]
