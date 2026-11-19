# Evidence: plan 257 (Finish drops never-started intervals, holds and rounds)

Base commit c34d81e6, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| `test/finish_drops_never_started_timers_test.dart` (S-25701..S-25710, Mock and Hive; S-25708 Mock only) | +19 passed |
| Readers after P1 | 3 red outside base: S-15707 (Mock and Hive, the plan 157a test that pinned the opposite rule) and S-820 (session summary distance) |
| Full suite (before the fixture fixes) | +7256 passed, 1077 failed: 4 names outside the base set, all fixtures that relied on a never-started timer surviving Finish (`health_yoga_kind_test` S-19311, `mix_session_with_nothing_done_test` S-22403 twice, `watch_timer_adoption_test` S-6112) |
| After the fixture fixes: the six affected files together with the new one | +122 passed, 0 red |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |

## Mutation pass (lead, in place, restored and byte-compared by script)

12 mutants over `session_core_lifecycle.dart`: new method not called, timed kind skipped, round kind skipped, hold kind skipped, a running entry dropped, rests not re-keyed (timed and round), an emptied exercise kept, `keepEfforts` ignored, the wrist path without the drop, the error not cleared, an ascending walk. First pass: 2 not proven (round rests: no test; the error clearing: a pattern typo in the script): S-25710 added, pattern fixed, all 12 killed.

## Crew runs

P1 1.3 min, P2 8.3, tests-only fix 2.5, tests-only fix 2.0, fixture fixes 4.9 and 3.9, reviewer 11.1. No run stopped.
