# Evidence: plan 253 (calories override: data and math)

Base commit 8e1b2838, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| `test/calories_override_test.dart` (pure model scenarios; stored scenarios on Mock and Hive) | +17 passed |
| Readers (`db_seed_test`, `models_test`, `nutrition_log_from_library_test`, `watch_nutrition_quick_log_test`, `watch_sync_request_handler_test`) | 65 red, all in the Windows base set (`db_seed_test` cannot run SQL on this machine, so the schema was checked by eye: three added nullable columns, no positional INSERT exists) |
| Full suite | +7020 passed, 1062 failed: 1051 base names plus 11 test files that failed to LOAD ("Connection closed before test suite loaded", machine load); re-run: 23 red, 0 outside the base set. 0 regressions |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |

## Mutation pass (lead, in place, restored and byte-compared by script)

10 mutants over `models.dart`, `food_helpers.dart`, `nutrition_state.dart`: Food calories ignores the override, `fromMap` ignores the key (both classes), `toMap` omits it (both classes), `copyWith` cannot clear, consumed math ignores it, the log-time snapshot does not copy it, `calculateCalories` uses macros, `foodFromConsumedSnapshot` drops it. First pass: 1 alive (the last); closed by S-25310; all 10 killed.

## Crew runs

P1a (data builder) 3.6 min, P1b 1.5, P2 5.3, reviewer 5.1. No run stopped.
