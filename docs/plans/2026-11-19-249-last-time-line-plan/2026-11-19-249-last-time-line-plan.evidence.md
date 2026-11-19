# Evidence: plan 249 (last-time line in the logger)

Base commit e4c1fe19, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| `test/last_performance_service_test.dart` (Mock and Hive twins for S-24901..S-24906, Mock only for S-24907 and S-24907b) | +18 passed |
| `test/last_sets_line_test.dart` (S-24911..S-24916) | +8 passed |
| `test/exercise_set_last_value_test.dart` (reader of the logger) | passed with the two files above: 26 tests |
| Full suite | +7126 passed, 1073 failed; 0 names outside the base set (2 base names now pass) |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |
| `docs_indexing_contract_test`, `ui_standards_contract_test` | reds are all base names |

## Mutation pass (lead, in place, restored and byte-compared by script)

17 mutants over `last_performance_service.dart`, `last_sets_line.dart`, `workout_state.dart`, `workout_session_list_view.dart`. First pass: 12 killed, 5 alive or invalid. Closed: kind check removed (S-24904b now seeds a `timed` effort that holds set rows), current session id not passed (S-24907b loads a FINISHED workout as the current one: a running one is already excluded by the finished filter), and mutant n whose first form was a compile error (re-run as `const LastSets? last = null;`, killed). Left alive by design: no explicit sort (both stores already return newest first, the sort protects a store that does not) and the line's bottom padding value (a design number, the column scrolls).

## Layout probe (deleted)

The logger detail with the line at 320x568 and 360x640, text scale 1.3: no exception; the line sits above the Add set control.

## Crew runs

Scouts 1.8 min and 4.6 min (a first 7-question scout was stopped and split into two), P1 1.2, P2 4.5, P3a 1.8, P3b 2.1, P4 4.4, P5 (two tests) 1.8, reviewer 5.2. The gateway denied `lint` and `format` to builders on several runs (no interactive user); the lead ran analyze and format by explicit path. Running `dart format` on the three tracked session files also reformatted unrelated code; those hunks were put back by hand before the commit.
