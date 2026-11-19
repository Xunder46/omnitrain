# Evidence — plan 157a (Finish keeps only the sets that were logged)

Companion to `2026-11-13-157a-stats-unlogged-sets-plan.md`. Facts recorded by the docs phase; sources are the lead's runs.

## Base

- Base commit `cd117f79`.

## New tests (all green)

- `test/finish_drops_unlogged_sets_test.dart` — 33 tests (16 Mock + 16 Hive + the Mock-only S-15711).
- `test/finish_drops_unlogged_sets_screen_test.dart` — 1 test.

## Reader fixtures made to log their sets (assertions unchanged)

| File | Fixtures | Note |
|---|---|---|
| `test/data_tracking_fixes_test.dart` | 2 | |
| `test/state_test.dart` | 1 | |
| `test/session_finish_timers_test.dart` | 2 | rest index 0 to 1 |
| `test/pr4_session_controls_test.dart` | S-185a | via a `logSet` option on `_pumpSession` |
| `test/watch_session_import_test.dart` | S-274 | |
| `test/health_yoga_kind_test.dart` | E | |

## Analyze

- `gateway.sh lint`: **181 issues (baseline 181, 0 errors)**.

## Mutation pass (lead)

- 25 mutants, **24 killed, 1 equivalent**: `_observations.remove(effort.id)` removed — the rows list is already trimmed empty before it, so nothing observable differs.

## Full suite

- First run of the suite had two scratch-file failures of `pre_release_gate_*` tests caused by another session deleting a Swift scratch file while the tests copied the tree; green when re-run alone (**28 tests**).
