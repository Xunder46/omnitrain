# Evidence: plan 251 (finishing a routine workout completes its plan)

Base commit 6b1cd237, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| `test/plan_completes_on_routine_finish_test.dart` (Mock and Hive twins, S-25101..S-25111) | +22 passed |
| `test/state_test.dart` (the optional constructor parameter keeps every construction compiling) | +240 passed |
| Full suite | +7173 passed, 1072 failed; 0 names outside the base set |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |

## Mutation pass (lead, in place, restored and byte-compared by script)

10 mutants over `calendar_state.dart` and `session_core_lifecycle.dart`: hook not called, day check removed, routine check removed, started plans not skipped, completed plans not skipped, newest plan first, already-linked guard removed, throw not caught, day taken from the end time, no-routine workout matching free plans. First pass: 3 alive (the started-plan check, the completed-plan check, the already-linked guard): S-25104's started plan had both flags set so each flag alone was untested, and no fixture had a plan already linked to the ending workout. Closed by S-25109, S-25110, S-25111; all 10 killed.

## Crew runs

P1 2.1 min, P2 4.1 min, tests-only fix 1.5 min, reviewer 6.4 min. No run stopped; no fix round on the builders' own output.
