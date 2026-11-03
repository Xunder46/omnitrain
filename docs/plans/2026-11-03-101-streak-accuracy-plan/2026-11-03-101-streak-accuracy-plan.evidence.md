# Evidence: 101 — the training streak says what is true

Observed output, 2026-11-03, base 27172ae5, branch `claude_develop`.

## Tests

- `flutter test test/calendar_streak_state_test.dart test/calendar_streak_screen_test.dart`: `+19: All tests passed!` (14 state tests, of
  which 2 clock-change days x 4 tests = 8; 5 screen tests). The zone is America/New_York; the clock-change days found are 2026-03-08 and
  2026-11-01.
- Full suite (`flutter test`, 900 s cap): `+6174 ~2 -1`. The one failure is `routine_save_removes_deleted_rows_test.dart` S-R3, red at the base.
- `flutter analyze`: 181 issues (baseline 181, 0 errors).
- `ui_standards_contract_test.dart` + `docs_indexing_contract_test.dart`: green (`+54`, `+13`).
- Invariant grep (`hive_workout_repository` imported outside `lib/data`): empty.
- `plan-lint.py before` and `after`: clean, 10 scenarios, 9 Docs delta rows.

## Lead mutation pass (each mutant applied, both new test files run, original restored and `cmp`-checked)

| Mutant | Change | Result | Killed by |
|---|---|---|---|
| M1 | `yesterday` back to `today.subtract(Duration(days: 1))` | killed (-2) | S-17402 |
| M2 | walk step back to `day.subtract(Duration(days: 1))` | killed (-4) | S-17402 |
| M3 | `isActiveStreak` back to `... && _streakDays > 0` | killed (-3) | S-17404, S-17407 |
| M4 | `liveStreakDays` returns `_streakDays` | killed (-2) | S-17404, S-17408 |
| M5 | strip condition back to `completedSessions == 0` | killed (-1) | S-17406 |
| M6 | `apart == 1` back to `curr.difference(prev).inDays == 1` | killed (-1) | S-17409 |
| M7 | R&T reads `streakDays` | killed (-1) | S-17408 |

`prove-red` at the base was not used: the new tests do not compile there (no `now` parameter), which says nothing about behaviour.

## Review

APPROVE: 0 blocker, 0 major, 2 minor. Both fixed: the calendar doc sentence regained "in the current month"; the S-17406 dash assertion is
pinned to the SESSIONS slot (re-run: `+5`).

## Crew cost

5 runs, 21 agent-minutes, 113 model requests, 3.0M input tokens.
