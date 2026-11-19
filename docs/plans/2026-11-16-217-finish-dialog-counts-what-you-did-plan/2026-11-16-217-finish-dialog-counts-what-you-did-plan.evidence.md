# Evidence — plan 217

- P1 builder (state + `test/finish_completed_exercise_count_test.dart`, 6 tests Mock+Hive): green; readers `finish_drops_unlogged_sets_test` +33, `watch_session_finish_test` +22.
- P2 builder (dialog line + `test/finish_completed_exercise_count_screen_test.dart`, 1 test): green; readers `finish_drops_unlogged_sets_screen_test`, `session_finish_timers_test` green.
- Lead mutation pass (7): every set effort counts, skip-marked counts, round always counts, timed always counts, rule off by one, dialog reads `_exercises.length`, plural inverted: all KILLED, sources restored and compared.
- Full suite on the final code: `+7797 ~4: All tests passed!`. `flutter analyze`: 181 issues, 0 errors (baseline).
- Review: APPROVE WITH FIXES (0 blocker, 0 major, 2 minor, both recorded in Open items 4 and 5). `plan-lint after`: see below.
