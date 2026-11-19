# Plan 209 — evidence

Base commit `4105405937965267e4236e823e457c8d06a9d99d` on `claude_develop` (other sessions' commits moved HEAD forward during the build; none touch this plan's files).

## What was built

- P1 (builder, 6.4 min): `formatNativeChange` reads a pace change as better or worse (`↑ 0:10 /km` faster, `↓ 0:10 /km` slower, no sign); new `nativeChangeGain`; the Instruments tile passes the chip a gain; the first build also dropped other-metric days inside `computeExerciseMetrics`. New tests S-21001..S-21003 (`test/instrument_change_format_test.dart`) and S-21004..S-21007 (new `test/stats_pace_reads_honestly_test.dart`).
- Review (crew-reviewer): APPROVE WITH FIXES. Major: the service guard also shrank Exercise Progress's RECENT SESSIONS list and the two `points.length` sort keys (`stats_progress_service.dart` row order, `records_and_trends_screen.dart` training-day share); the Exercise Progress chart had the same mixing defect. Minor: a pace change under half a second reads `↑ 0:00 /km` (not introduced here; the old text read `↓ -0:00`; duration and hold have it too). Not changed.
- Fix round 1 (builder): the service guard reverted to HEAD; new `ExerciseMetricSummary.trendPoints` (days in `best.metric` only); the Instruments sparkline and Exercise Progress's TREND card and chart read it; RECENT SESSIONS and both sorts keep `points`. S-21006/S-21007 rewritten, S-21008 (sparkline gets two points) and S-21009 (Exercise Progress screen with the mixed history: RECENT SESSIONS lists three entries, the chart plots two) added. The lead corrected a stale comment in `lib/core/models/instrument_list.dart`.
- Docs by the lead: `docs/stats_screen.md` (the pace reading, the single-metric trend line and chart) and `docs/state_management/services_and_utils.md` (the pace sign). `plan-lint after`: clean (9 scenarios, 3 docs-delta rows).

## Lead verification

- Plan test files after fix round 1 (builder run, re-run by the lead for the first build: 90 tests green across five files): `test/stats_pace_reads_honestly_test.dart` +8, the seven related files +144, all green. `flutter analyze`: 181 issues (baseline 181), 0 errors.
- Mutation pass on the final code, ten mutants, ten killed: (a) pace branch removed; (b) `nativeChangeGain` returns the raw delta; (c) pace branch for every metric; (d) tile passes the raw delta; (e) the service drops other-metric days again (S-21006 `points` length and the Exercise Progress screen test); (f) `trendPoints` unfiltered; (g) `trendPoints` filters against a constant metric; (h) sparkline reads `points`; (i) the chart reads `points`; (j) RECENT SESSIONS reads `trendPoints`. The sources were restored and compared after every mutant.

## Final runs

Full suite (lead, 900 s cap, after fix round 1): `+7723 ~4: All tests passed!`, 0 failures, 6 min 20 s. `flutter analyze`: 181 issues (baseline 181), 0 errors.

## Not done / residual

- A pace change under half a second per unit reads `↑ 0:00 /km` or `↓ 0:00 /km` (review minor, not introduced here).
- Records & Trends's all-time Best for a cardio exercise with no distance is still a running total: plan 211.
- (owner) A device check: log two runs with a distance a week apart, the second quicker, and one run with no distance between them; open Stats, then that exercise's Exercise Progress.
