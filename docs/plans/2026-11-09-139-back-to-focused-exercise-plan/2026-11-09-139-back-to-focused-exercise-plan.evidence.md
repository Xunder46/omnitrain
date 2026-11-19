# Evidence — plan 139 (back returns to the exercise you left)

Base commit `11e38f8cd78a25334abb67de9a65023dae0222ed`; branch `claude_develop`. Observed 2026-11-10 by the lead.

## Probe before the build (throwaway, deleted)

60 uneven-height cards in a `ListView`: default list leaves row 45 unbuilt; `cacheExtent: 100000` builds 60 of 60 and `Scrollable.ensureVisible(alignment: 0.3)` lands the row at 159.6 px of a 600 px viewport (= 0.3 x (600 - 68 px row), not 0.3 x 600); `double.infinity` throws `Failed assertion: 'value.isFinite'`; a `SingleChildScrollView` + `Column` lands the same. A touch drag that starts on a routine row scrolls the outer list (offset 0 to 270).

## Production change

`lib/widgets/layout/list_row_focus.dart` (new, 66 lines), `lib/features/routine/routine_setup_screen.dart` (+45 / -17), `lib/features/session/workout_session_screen.dart` and `workout_session_list_view.dart` (+44 / -14 together). Diffs read by the lead against the briefs' exact text: identical, except the keyed `Builder` in the helper (lead edit).

## Tests

- `test/list_row_focus_test.dart` 3 tests; `test/routine_back_to_exercise_test.dart` 5 tests; `test/session_back_to_exercise_test.dart` 5 tests (all new).
- `test/interaction_flow_test.dart`: 56 tests before, 52 after (four obsolete bottom-landing tests removed); `+52: All tests passed!`.
- `test/routine_detail_screen_test.dart` `+25`, `pr4_session_controls_test.dart` `+17`, `logger_feedback_controls_test.dart` `+10`, `rest_timer_docked_strip_test.dart` `+15`, `session_screen_build_phase_notify_test.dart` `+6`, `ui_standards_contract_test.dart` + `docs_indexing_contract_test.dart` `+54`: all passed.
- Full suite, quiet tree (no other flutter process): `05:51 +7325 ~2: All tests passed!`, exit 0.
- `flutter analyze`: 181 issues, equal to the baseline (one new curly-braces issue in the session test was fixed).
- Invariant grep (`import .*hive_workout_repository` in `lib/state lib/features lib/widgets lib/core`): no output.

## Mutation pass (23 mutants, originals restored byte-identical, checked with cmp)

Killed first time (18): H1 never raise the extent, H2 always raised, H3 request kept, H4 no mounted check, H5 alignment 0.0, H6 Builder unkeyed, H7 reveal returns false, R2 nothing requested, R3 routine system back old jump, R4 routine header back old jump, R5 routine focus index 0, R6 routine no rebuild after reveal, R7 routine row tracked under another id, S2 standard list without the extent, S3 session header back old jump, S4 session PopScope old jump, S5 tile not tracked, S6 session focus index 0.
Survived and then killed after fixture changes: R1 routine list without the extent, S1 rolling list without it, S7 session no rebuild after reveal (tests now use six blocks of four and a two-frame pump).
Survive by design: R8, S8 (fallback `_scrollListToBottom` removed): not reachable from a screen test; documented.

## Not claimed

The app was not run on a simulator or device. (owner) device check is in the plan's Assumption Log.
