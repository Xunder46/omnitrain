# Evidence: plan 255 (active-session list progress and done mark)

Base commit 4e62dd83, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| `test/session_list_progress_test.dart` (S-25501..S-25509) | +10 passed |
| `test/round_auto_expiry_test.dart` with it (the timer-expiry path I touched) | +15 passed |
| Readers after P1 (`screen_widget_test`, `interaction_flow_test`, `exercise_set_last_value_test`, `session_toolbar_rework_test`, `header_standardization_test`, `state_test`, `watch_session_summary_integration_test`, `last_sets_line_test`) | no test read the old `N sets` subtitle; 3 red, all in the base set |
| Full suite, first run | +7226 passed, 1074 failed, 0 names outside the base set |
| Full suite, final run (after the review fix) | +7227 passed, 1074 failed, 0 names outside the base set |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |

## Mutation pass (lead, in place, restored and byte-compared by script)

11 mutants over `workout_session_list_view.dart` and `workout_session_timer_mixin.dart`: count ignored, singular rule removed, mark when not all logged, mark never shown, edit mode not excluded (mark and text), drill unchanged, interval also marked, mark for zero entries, wrong semantic label, expiry refresh removed. First pass: 2 alive (interval also marked, zero entries): closed by S-25507b and S-25508. The review-driven expiry refresh was first unproven (a fast Mock store hides the bug): S-25509 now gates the store write and the mutant is killed.

## Crew runs

P1 1.2 min, P3 8.9, tests-only fix 4.0, tests-only fix 5.4, tests-only fix 5.1, reviewer 6.4. No run stopped.
