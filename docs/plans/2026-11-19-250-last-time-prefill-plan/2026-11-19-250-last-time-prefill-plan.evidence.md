# Evidence: plan 250 (a new set starts from last time)

Base commit 3468a258, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| `test/last_time_prefill_test.dart` (Mock and Hive twins for S-25001..S-25006, S-25008, S-25009, S-25011, S-25012; Mock only for S-25007, S-25010) | +22 passed |
| `test/last_performance_service_test.dart` (plan 249's tests plus S-25013, S-25014) | +20 passed |
| Full suite, first run (before the review fixes) | +7146 passed, 1075 failed; 0 names outside the base set |
| Full suite, final run (after the review fixes) | +7106 passed, 1080 failed: 1075 base names plus 8 stats test files that failed to LOAD ("Connection closed before test suite loaded", a machine-load fault while the suite ran) and one Mix horizon test that failed once; the 8 files re-ran green except that one, and it passes alone (+12). 0 real regressions |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |

## Mutation pass (lead, in place, restored and byte-compared by script)

15 mutants over `last_performance_service.dart`, `session_core_entry.dart`, `session_core_io.dart`. First pass: 3 alive. Closed by tests: self-exclusion (S-25011: a finished workout loaded as the current one), cache refresh on a new session id (S-25012). Left alive on purpose (equivalent): the `effortKind == 'set'` check, because the round, timed and drill branches return before it. Review fixes added two mutants (single-flight, failed read kept), both killed by S-25013 and S-25014.

## Crew runs

P1 2.8 min, P2 7.5 min, tests-only fix 3.4 min, reviewer 6.0 min. The P1 builder replaced the routine's whole `for` loop by one call (the brief said the call "becomes"), the P2 builder reported it as an incomplete P1, the lead restored the loop (a one-line fix: the four routine tests were red until then).
