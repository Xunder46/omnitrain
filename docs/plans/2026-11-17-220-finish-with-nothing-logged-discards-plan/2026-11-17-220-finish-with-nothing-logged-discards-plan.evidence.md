# Evidence — plan 220

- P1 builder: `finishWouldSaveNothing`, the discard dialog, S-22001 (8 tests Mock+Hive), S-22002/S-22003 (2): green.
- Fix 1: two readers in `session_finish_timers_test.dart` start a timed entry before Finish.
- Lead mutation pass (6): wrist clause, staged clause, always false, always true, Cancel discards, Discard only pops: all KILLED.
- Review: APPROVE WITH FIXES (0 major, 3 minor).
