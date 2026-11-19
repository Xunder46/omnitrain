# Plan 179 — evidence

Base commit `7664f126` on `claude_develop` (the seed was written at `c95c4a23`; the tree moved forward by other sessions' commits that touch none of this plan's files).

## What was built

- P1 (builder, 2.5 min): `sessionTimeByModality` takes `hasSets`; with no set effort and measured time above zero it scales each measured modality to the session's duration; `StatsProgressService._sessionSplit` passes `_hasSetEffort(history, session)`. Twelve existing calls in `test/training_load_test.dart` gained `hasSets: true`. New `test/mix_no_sets_pure_test.dart` (S-20001..S-20006). Observed: `mix_no_sets_pure_test.dart` +6 and `training_load_test.dart` +50 green.
- P2 (builder, 4.3 min): new `test/mix_no_sets_service_test.dart` (S-20007..S-20011, Mock and Hive); one logged set added to the premise of fifteen existing tests in `test/mix_layer_service_test.dart` (`_seedS1503`), `test/modality_mix_period_service_test.dart` (`_seedWork`), `test/modality_mix_shift_signal_screen_test.dart` (`_seedFMix`, six sessions), `test/active_energy_service_test.dart` (S-13404, S-13414) and `test/active_energy_import_test.dart` (S-13419). No assertion value changed.
- Docs by the lead: `docs/training_load.md` (the set-holding rule, the new sharing rule, the verified-by list) and `docs/session_summary.md` (one sentence on the Free Training calorie split). `plan-lint after`: clean (11 scenarios, 5 docs-delta rows).

## Lead verification

- The 27 reader files (25 from the seed plus the two new ones): 609 tests, 0 red (base run was 593 tests, 0 red; the trial before the premise fixes had 15 red in five files).
- Mutation pass, nine mutants, nine killed: (a) `hasSets` ignored, killed by S-20004; (b) inverted, S-20001; (c) `totalMeasured > 0` test dropped, S-20006; (d) new branch before the overflow branch, S-20005; (e) no scaling (leftover dropped), S-20001..S-20003, S-20007, S-20010 (weekly load 90 instead of 120) and S-20011; (f) `_hasSetEffort` always false, S-20009 on both stores; (g) `_hasSetEffort` true for any effort, S-20007, S-20008, S-20011; (h) split passes `hasSets: true`, S-20007, S-20008, S-20011; (i) the kind test matches cardio instead of set, S-20007 on both stores. The sources were restored and compared after every mutant.
- Note on formatting: `dart format` was run by explicit path on the two new test files and `test/modality_mix_period_service_test.dart` only; on four other existing test files it rewrote unrelated lines, so those were restored and the intended lines re-applied by hand.

## Final runs

- Full suite (lead, 900 s cap): `+7700 ~4: All tests passed!`, 0 failures, 5 min 49 s. `flutter analyze`: 181 issues, 0 errors (baseline 181).
- Reviewer: APPROVE, 0 blocker / 0 major / 1 minor (the inline copy of the "holds a set" test in `interferenceSessions`). Fixed by the lead after the full run: the interference walk now calls `_hasSetEffort`; `dart analyze` on the file clean; the 27 reader files re-run, 609 tests green.

## Not done / residual

- A session with no effort that maps to a modality, or whose timed efforts have no finished instance, still reads as all Resistance (D-2). A separate rule decision; changing it breaks 113 reader tests whose fixtures are such sessions.
- A wrist-linked session keeps its planned set efforts until 157d, so it still follows the old rule if it holds a planned set it never logged.
