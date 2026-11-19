# Review: plan 211 — a Best is one session · P1–P3 · ac1c9b33..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: not run by reviewer (brief directs no full-suite run; builders' runs cited: new service file 14 tests green on Mock and Hive, screen file 4 green, mutation pass 9 killed / 1 equivalent)
Diff vs Predicted Files: conforms except the predicted "series index status" row is not in the diff (`docs/plans/2026-11-13-157-stats-what-counts-series.md:35` still reads "not planned") — finding 2.

## Findings
1. [Minor] `docs/records_and_trends.md:109`, `:111` — the two table cells ("the longest single session's duration when no distance qualifies", "Rounds completed in the best session") state the new rule unqualified, but the Instruments rows over a window read the window's total for exactly those exercises. The paragraph at `:117-125` resolves this explicitly ("the Instruments rows keep the window's labelled totals"), so the claim is not false; a reader who stops at the table can misread the Stats-screen row. Fix: smallest change is appending "(all-time screens)" to the two Cardio/Sports metric cells, or leaving as is now the paragraph names it. Guard: none needed (doc only).
2. [Minor] Predicted Files lists "the series index status" but `docs/plans/2026-11-13-157-stats-what-counts-series.md` is not in the diff; its 211 row still reads "not planned". A maintainer consulting the series index sees the wrong status. Fix: at landing, set the row's status; do it with the plan-status flip, not in this change. Guard: none (doc only).

## Answers to the brief's five questions

### 1. Other readers — OK
`grep -n computeExerciseMetrics lib` returns exactly: `records_and_trends_screen.dart:97`, `exercise_progress_screen.dart:68` (both `bestSingleSession: true`), the definition `stats_progress_service.dart:1089`, and the two internal calls `:1290`, `:1294` — both inside `_buildInstrumentSections`, both without the flag, so the Instruments current and previous-window reads keep totals (pinned by S-21204's row assertions). No other reader exists, so nothing can depend on `best` being a total. Cross-surface checks: `session_summary_service.dart:430-432` counts finished rounds with the same predicate `_sportsValue` applies (`RoundState.finished && startedAtMs > 0 && finishedAtMs != null`), so the Best for rounds agrees with the winning session's own summary count; the PR path (`computePRs`) reads `getAllTimeBestE1RM`/`getAllTimeBestReps` (weight/reps axes), never this value, so the in-workout toast cannot disagree with the new figure. Not checked: nothing else in lib consumes `ExerciseMetricSummary.best`.

### 2. Per-day versus per-session — OK
Records & Trends renders only `summary.best` (`records_and_trends_screen.dart:306`, `:354`); its `points` are used solely to sort (`:233`). Exercise Progress shows the Best pill, `Total time` pill and Sessions pill from `summary.best`/`sessionCount` (`exercise_progress_screen.dart:170-200`), the trend chart from `trendPoints` (`:215`), and RECENT SESSIONS from `summary.points` (`:152`) — one figure per training day. A day's total exceeds the Best only when the day holds two or more sessions (D-3): a single-session day's total equals that session's value, which cannot exceed the Best. S-21207 pins exactly that divergence (`best.value == 1500`, `points.last.value.value == 2400`), and the doc paragraph `records_and_trends.md:119-120` discloses it. What the user sees on such a day: the chart's peak (or that day's RECENT SESSIONS figure, e.g. `40:00`) above the Best pill (`35:00`) — accepted, rare, documented.

### 3. The re-read — OK
`_bestSingleSessionValue` (`stats_progress_service.dart:1604-1636`) calls `_nativeValueFor(sessionLogs, section, isRepsAxis)` (`:1576-1590`), which dispatches to the same `_cardioValue`/`_sportsValue` the all-history read used — identical predicates over only the logs given (`TimedState.finished` for cardio sums; `finished && startedAtMs > 0 && finishedAtMs != null` for rounds). Both read `history.observationsOf(log.effort.id)` / `roundInstancesOf(log.effort.id)` scoped per effort, so a session's value is exactly what an all-history read of that session alone would give; `_loadHistory()` is a cached index (`:108-137`), so no extra repository read — the plan's cost line holds. The early return for non-duration/non-rounds is right for the mixed case: if any entry anywhere had a distance, the all-history `_cardioValue` would have returned `pace`, so a `duration` total implies no session has a distance and every per-session read is a duration; conversely a `pace` total returns untouched, and the sessions without distance are ignored for the Best, as open item 2 states. The `value.metric != total.metric` guard (`:1629`) then cannot misfire for cardio.

### 4. Tests — OK
Each scenario the plan marks "fails without" would fail on base behaviour, read as a test:
- S-21201 (`stats_best_single_session_test.dart:148-206`): expects `best.value == 2100`; base total is 4800 → red without the change.
- S-21202 (`:208-273`): expects `5` rounds / `10` min; base reads 10 rounds / 22 min → red.
- S-21207 (`:530-589`): expects `1500`, not the 2400 day total; base reads 4800 total → red.
- S-21205 (`stats_best_single_session_screen_test.dart:127-158`): expects `35:00` present, `1:20:00` absent; base renders `1:20:00` → red.
- S-21206 (`:240-283`): expects pills `5 rounds` / `10 min`, `10 rounds` and `22 min` absent; base pills read `10 rounds` / `22 min` → red.
S-21209 (`service test :663-701`) would also fail on base (`4` rounds vs expected `2`) and kills mutant (i): the `>=` variant takes the later session and reads `10` min vs `closeTo(200/60, 0.01)`.
S-21204 (`:275-434`) pins the Instruments rows: it asserts both the default `computeExerciseMetrics()` totals (4800 / 10 rounds / 22 min) and `computeInstrumentSections(window: windowOfDays(10))` row values (`ellRow.summary.best.value == 4800`, `bjjRow.summary.best.value == 10`); if `_buildInstrumentSections` (`stats_progress_service.dart:1289-1300`) passed the flag, both window reads return per-session bests and those assertions fail — mutant (h) is killed here. S-21203 (the pace test) and S-21208 are the plan's deliberate "passes with and without" pins (pace never re-read; zero fallback unchanged), matching the plan's own "fails without" column.

### 5. Docs — OK (finding 1 aside)
The new paragraph (`records_and_trends.md:115-125`) says only what the code does: best one session by `session.id` (D-3's two-sessions-on-one-day behaviour, verified by S-21207), pace kept with distance (S-21203), both screens pass the flag (both screen diffs show it), Instruments rows keep totals (S-21204). The verified-by sentence names test files and scenario ids that exist. Stale-term sweep re-run: `total duration`, `summed duration`, `Rounds completed`, `Total round minutes`, `running total` outside `docs/plans`/`docs/history`/`docs/releases` — remaining hits are `records_and_trends.md:111`/`:117` (the new wording itself), `stats_screen.md:323` (`Total time` on the Instruments row, still true after this change), and energy/calorie "running total" sentences in `rest_tracking.md:324` and `modality_based_exercise_ui.md:387`, unrelated to the Best. Generic "all-time bests" descriptions (`README.md:71`, `navigation_and_screens.md:200-201`) remain true.

## Docs delta
`docs/records_and_trends.md` MODIFIED "Pace, or the longest single session's duration when no distance qualifies" -> applied (:109)
`docs/records_and_trends.md` ADDED "Rounds completed in the best session" -> applied (:111)
`docs/records_and_trends.md` MODIFIED "That session's round minutes" -> applied (:111)
`docs/records_and_trends.md` ADDED "the Instruments rows keep" -> applied (:117-125)
`docs/records_and_trends.md` ADDED "test/stats_best_single_session_test.dart" -> applied (:139-141)
Doc edit the table does not name: the verified-by sentence also adds `test/stats_best_single_session_screen_test.dart` (`S-21205`, `S-21206`) — true and tied to the screen tests; consider adding it as a sixth row at landing.

## Assumption Log rulings
- Base commit / other sessions' files: ratified — the diff contains exactly the seven files listed in the brief; no watch Swift, no 208 files, no `stats_gallery_render_test.dart` in it.
- Scenario ids S-212xx unique: ratified — no S-212xx outside the plan and its two test files (grep over test/docs).
- "Session" = `session.id`, not day: ratified — code (`:1621-1626`) and S-21207/S-21209 agree; D-3 disclosed in the doc and pinned by a test.

## Scenario coverage
S-21201 -> test/stats_best_single_session_test.dart · "S-21201 a no-distance cardio Best is its longest session" (both harnesses)
S-21202 -> test/stats_best_single_session_test.dart · "S-21202 a rounds Best is the session with the most rounds"
S-21203 -> test/stats_best_single_session_test.dart · "S-21203 a distance cardio keeps its pace, flag or not"
S-21204 -> test/stats_best_single_session_test.dart · "S-21204 the default call and the Instruments rows keep totals"
S-21205 -> test/stats_best_single_session_screen_test.dart · S-21205 group, testWidgets
S-21206 -> test/stats_best_single_session_screen_test.dart · S-21206 group, testWidgets
S-21207 -> test/stats_best_single_session_test.dart · "S-21207 two sessions on one day are not summed into the Best"
S-21208 -> test/stats_best_single_session_test.dart · "S-21208 an unfinished entry alone reads the zero fallback"
S-21209 -> test/stats_best_single_session_test.dart · "S-21209 a tie between two sessions keeps the earlier one"
No MISSING rows.
