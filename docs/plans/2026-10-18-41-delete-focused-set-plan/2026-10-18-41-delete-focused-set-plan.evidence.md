# Evidence — plan 41 (`−` deletes the focused set)

Docs-keeper run 2026-10-18. The code was built before this run; the docs keeper
verified the facts in code and rewrote the docs. The numbers below are the
lead's run results handed over in the brief; the docs keeper did not re-run the
suite.

## What was run

| Check | Result |
|---|---|
| `test/delete_focused_set_test.dart` (S-4901, S-4902, S-4907) | 3 pass |
| `test/delete_focused_timer_test.dart` (S-4904, S-4905, S-4906, S-4908) | 4 pass |
| `test/logger_shell_screen_test.dart` | 43 pass |
| `test/session_toolbar_rework_test.dart` | 29 pass |
| `test/set_shell_widgets_test.dart` | 18 pass |
| Full suite | 5036 pass, 8 fail |
| `flutter analyze` | 181 issues (same as before the change) |

The 8 failures are all in `test/mix_layer_screen_test.dart` and are identical
on the untouched base commit `e6ff75b0` — pre-existing, not caused by plan 41.

## Mutation checks (lead)

| Mutation | Result |
|---|---|
| Aim `−` at the last set again (restore the 38a target) | 6 of the 7 new tests fail |
| Remove the running-set dialog | S-4904 and S-4906 fail |
| Timer-state shift guard (a test for the stale started-marker) | being added in a fix round; proven separately |

## Verified in code this run (docs keeper)

- `lib/features/session/workout_session_list_view.dart:843` — `onRemove: () => _deleteSetAt(_currentSet - 1)`.
- `lib/features/session/workout_session_screen.dart` `_deleteSetAt` — single-set branch `Remove Exercise?` (unchanged); logged branch `Delete logged <label>?` (unchanged); new started-but-unlogged branch `Delete running <label>?` / "The timer is running. Deleting it loses this progress." with keys `workout-delete-running-entry-cancel` / `-confirm`; `_rekeyTimerStateAfterDelete` called after `deleteEntry` in both branches; focus stays on the same position or clamps to the new last set.
- `lib/features/session/workout_session_timer_mixin.dart:227` — `_rekeyTimerStateAfterDelete(String effortId, int deletedIndex)`.
- `_deleteLastUnloggedSet` — no hit in `lib/`.
- New tests present with the exact names cited in the docs; the old `S-4220: − drops the last set when the last two are unlogged` and the S-4225 test are gone from `test/logger_shell_screen_test.dart`.
