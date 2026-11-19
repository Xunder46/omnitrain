# Review: plan 209 · P1 build + docs · base 4105405..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: not run (brief says governor runs the full suite; brief states the plan's five test files ran 90 green, mutations 6/6 killed)
Diff vs Predicted Files: conforms — the seven in-scope files are exactly the plan's Predicted Files. The stat also lists `docs/plans/2026-11-13-157-…` (index), `docs/watch-app-qa-wrist-logging.md`, `ios/**Watch*.swift` — other sessions' work, ignored per brief.

## Findings
1. [Major] `lib/core/services/stats_progress_service.dart:1131` — the per-day guard drops days from the shared `ExerciseMetricSummary.points`, and two surfaces the plan does not name read that list: `exercise_progress_screen.dart:150` (`RECENT SESSIONS` takes the last k points, so a cardio day with no distance silently vanishes from a list headed "sessions") and the two `.points.length` sorts, `stats_progress_service.dart:1316` (Instruments row order, key comment "byDays") and `records_and_trends_screen.dart:231` ("training-day share"), whose sort keys now under-count a mixed cardio exercise by its distance-less days. A user who trains four days, one without distance, sees three recent entries and a changed row order with nothing explaining either. Fix (smallest): one sentence in `docs/stats_screen.md` (or the services doc) naming that the reduced series is shared by Exercise Progress and the sorts, plus one scenario pinning the RECENT SESSIONS content for the S-21006 fixture. Guard: a test on `exercise_progress_screen` (or the summary) asserting the mixed fixture yields 2 recent entries, not 3.
2. [Minor] `lib/features/stats/widgets/native_value_format.dart:128-130` — a pace delta under half a second per unit formats as `↑ 0:00 /km`: arrow says better, magnitude reads zero. Reachable for pace because best pace is a minimum over runs, so two runs can differ by <0.5 s/km. Not introduced here: the magnitude has always gone through `formatNativeMetric`'s clock rounding (`native_value_format.dart:24-33`), so the old text read `↓ -0:00 /km` for the same delta, and hold/duration/roundMinutes have the same zero-magnitude case today (reps cannot: deltas of ints). Smallest fix if the owner wants it: a magnitude that rounds to 0 renders the dash. Not required for this plan.

## Assumption Log rulings
- Base commit and other sessions' uncommitted tree: ratify (watch Swift and plan-157 index visible in the diff stat, none in this plan's scopes).
- S-21001..S-21007 id freshness: ratify (no re-grep; plan states the sweep).
- `/km`-`/mi` suffix with no sign on a pace change: ratify — S-21001 pins `↑ 0:48 /mi`, so the suffix is the formatter's own.

## Scenario coverage
S-21001 -> `test/instrument_change_format_test.dart` · `S-21001 a pace change reads better or worse, unsigned` (would fail at base: the old text carries the sign)
S-21002 -> `test/instrument_change_format_test.dart` · `S-21002 every other metric keeps arrow and raw sign` (passes both ways by design; mutation (c) catcher)
S-21003 -> `test/instrument_change_format_test.dart` · `S-21003 pace inverts, every other metric is raw` (fails without the helper: compile)
S-21004 -> `test/stats_pace_reads_honestly_test.dart` · `S-21004 a faster pace reads up in the primary colour` — pins the chip text at tile level (the Text inside `instrument_change_ex-run`) and the colour against `colorScheme.primary`; a swap of the chip's colour branches or a raw-delta delta field both fail it
S-21005 -> same file · `S-21005 a slower pace reads down in the error colour` (pins `error.withValues(alpha: 0.8)`, matching `instrument_row.dart:170-172`)
S-21006 -> same file · `S-21006 a pace row plots only its pace days`, both harnesses — would fail at base (3 points, middle one metric duration, best 350 vs mixed)
S-21007 -> same file · `S-21007 one-metric exercises keep every day`, both harnesses (passes both ways by design; mutation (f) catcher)

## Q1–Q5 answers
Q1 OK — `formatNativeChange(`, `InstrumentChangeChip(`, `nativeChangeGain(` in `lib/`: only `native_value_format.dart:120/126/137` and `instrument_row.dart:105-112`. No other caller passes a raw delta or reads the old pace sign; Records & Trends, Exercise Progress and the watch sender have no call site. Test side: `instrument_list_screen_test.dart:689,1351` call it with the Squat's e1RM, untouched.
Q2 OK with finding 1 — `best` never is the zero fallback in this path: all four section helpers return non-null (they return `_zeroValueFor` themselves, `stats_progress_service.dart:1642,1649,1703,1743,1777`), so `?? _zeroValueFor` at :1114-1115 is defensive; and a day yielding a real value forces the range's best to a real value, so the guard is correct even if the fallback were reached.
Q3 Minor — finding 2.
Q4 OK — both tests pump a real `InstrumentRowTile`; the text is read from the chip's own `Text` (tile-level `formatNativeChange`, raw-delta path) and the colour from the `delta` field (gain path: `nativeChangeGain(best.metric, delta)` at `instrument_row.dart:111-113`). Flipping primary↔error in `InstrumentChangeChip.build`, or passing the raw delta from the tile, fails S-21004 and/or S-21005.
Q5 OK — the stale sweep outside `docs/plans|history|releases` finds only the two rewritten passages (`stats_screen.md:332-333`, `services_and_utils.md:449`), now true. `widget_catalog.md:26` describes the chip generically, no sign claim; `stats_screen.md:551` "Built from the window's own points" stays true (the narrower set is still the window's own).

## Docs delta
`docs/stats_screen.md` MODIFIED (*slower* pace reads as an increase… -> worse — a faster run reads a green…) -> applied (:332-336, names S-21001..S-21003, S-21004, S-21005 — all exist)
`docs/stats_screen.md` ADDED (row's trend line plots only the days that read in the row's own metric) -> applied (:347-350, names S-21006 in `test/stats_pace_reads_honestly_test.dart`)
`docs/state_management/services_and_utils.md` MODIFIED (the delta, with no per-metric inversion… -> the delta for every metric but pace; for pace the arrow says better…) -> applied (:449-453; `nativeChangeGain` named and exists)
Doc edits the table does not name: none found.

## Checks run
None beyond reading: the brief says the governor runs the full suite and forbids running it. No `prove-red` verdicts were supplied in the brief for any guard; the "fails without" claims above are my own reading of the base behaviour, not prover output (S-21004/05/06: unproven by the prover, but the base-commit behaviour is visible in the diff's removed lines and `instrument_change_format_test.dart:85-90` before this change).
