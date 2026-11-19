# Evidence: plan 252 (no record for a first-ever exercise, "est. 1RM" label)

Base commit 31436d3f, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| Readers after P1 (`in_session_pr_toast_test`, `pr_toast_test`, `services_test`, `state_test`, `progression_rate_test`, `session_summary_effort_row_test`, `screen_widget_test`, `interaction_flow_test`) | +661 passed, 5 red: exactly the five tests that pinned the old rule (three in `in_session_pr_toast_test`, two in `services_test`); all five rewritten |
| After the rewrites and the new tests: `in_session_pr_toast_test`, `services_test`, `no_first_time_records_test`, `pr_toast_test` | +104 passed (then +61 in `services_test` alone after the reps-arm tests, +3 in the new file after the wiring test) |
| Full suite | +7011 passed, 1083 failed: 1075 base names, 13 test files that failed to LOAD ("Connection closed before test suite loaded", a machine-load fault), re-run: 10 of them green, 3 red in `test/watch_wrist_declared_kind_test.dart` (S-20606). Those 3 also fail on a CLEAN checkout of base commit 31436d3f at the same time of day (a temporary `git worktree`, removed), so they are not this change (time-dependent test, not investigated). 0 regressions from this change |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |

## Mutation pass (lead, in place, restored and byte-compared by script)

9 mutants over `workout_session_screen.dart`, `session_summary_service.dart`, `session_summary_screen.dart`: toast weight guard removed, toast reps guard removed, summary e1RM guard removed, summary reps guard removed, label removed, label on the reps line, both toast guards `>` turned `>=`, the summary wiring reverted to the unlabelled text. First pass: 1 alive (summary reps guard) and the wiring mutant was unproven (the review found S-25207 vacuous). Closed by S-25201b and S-25207b; all 9 killed.

## Crew runs

P1 1.6 min, tests P3 7.0, tests-only fix P4 2.5, tests-only fix P5 1.5, reviewer 5.8. No run stopped.
