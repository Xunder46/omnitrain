# Review: plan 245 (summary EXERCISES card) · all phases · f81d7d0a..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 3 · tests: not run per brief ("Run no test"); counts taken from the lead's evidence: 13 summary test files pass (157 tests), 14/14 mutants killed, full suite has the same environment-only failures as base (1074 here vs 1075 at base), analyze 178 vs baseline 181, plan-lint clean.
Diff vs Predicted Files: conforms with notes — outside the prediction: `test/food_catalog_load_test.dart` (1-line change, another session's uncommitted file, recorded in the plan's Assumption Log); `test/session_summary_distance_test.dart` changed though Readers lists it "untouched" (see finding 4); `test/session_finish_timers_test.dart` named in Readers but unchanged (see finding 2).

## Findings
1. [Major] `test/screen_widget_test.dart:5660` — the test is still named `rolling session still shows group card, note, and calendar sections`, but the calendar section no longer exists; the plan's Readers list names this test for rewriting in P3 and it was left untouched. `test/screen_widget_test.dart:5951-5956` — the comment above the `session note appears before calendar section` assertions still says the "Open Calendar" button "is rendered in the calendar card's OmniCardHeader's actions slot", which plan 245 removed. Both statements were made false by this diff. Fix: rename the test (drop "and calendar sections") and rewrite the comment to the new placement (2 changed lines); no behaviour change. Guard: none needed — name/comment only; the assertions themselves are still true and green.
2. [Minor] `test/session_finish_timers_test.dart:301` — comment "Scroll down to ensure the calendar card (and Open Calendar button) is built" names a card the diff deleted. The test itself is still valid (scroll to `Open Calendar`, `findsOneWidget`). Fix: change the comment to "the Open Calendar button". Guard: none (comment).
3. [Minor] `docs/session_summary.md:6-11` — the Overview hierarchy list was renumbered by this change (1..6) but still omits the Distance section, which in the code sits exactly between item 4 (Exercise list) and item 5 (Session note); the list now reads as a complete order and is wrong about what follows the EXERCISES card. Pre-existing omission, but this diff rewrote these very lines. Fix: add a `Distance` item (or a "see the layout table below" note) between 4 and 5. Guard: docs-indexing contract already runs; no new test needed.
4. [Minor] `test/session_summary_distance_test.dart:305-312, 796-800, 1026-1031` — changed although Readers lists this file as "param-only reader ... must stay green untouched". The changes are justified: plan 245's own EXERCISES card makes the bare `find.text(label)` / `find.textContaining(_plank)` ambiguous, so the scoped finds are the smallest fix that keeps the assertions' strength (nothing is loosened — the scoped `findsNothing` still asserts the plank is absent from the DISTANCE card, which is what the test meant). Ratified; recorded so the deviation from the plan is visible.

## Answers to the brief's questions
1. Yes. D-24504: `_buildExerciseSection` at `session_summary_screen.dart:991-1046` returns `[SizedBox, OmniCardHeader('EXERCISES'), OmniSurface(key omni_session_exercise_card)]` or `const []` (1001-1002), is placed after `..._buildGroupCards(theme)` and before `..._buildDistanceSection()` (763-765), reads `UnitFormatter.weightLabel` / `formatWeightValue` (995-999). D-24505: `_buildCalendarHeader`, `_buildCalendarCard`, `_buildCalendarGrid`, `_loadCalendarData` and its `_loadAsyncData` call, `_workoutDays`, `_daysInMonth`, `_viewMonth`, `_viewTodayDay`, `_monthName` are all gone (verified by grep over the file: no hits); `_calendarState` (105, 132), `_openCalendarScreen` (488), `_refreshOriginatingCalendar` (376), `openedFromCalendar` / `_isHistoricalView` (110), `originatingCalendarState` (64) kept. D-24506: the button is `Center(child: _buildOpenCalendarButton())` directly under the SESSION NOTE card (770), same handler. Nothing left over: the `date_utils.dart` import is still used (291, 347); no doc comment still describes the grid. D-24507 honoured: `OmniDateUtils.daysElapsedInMonth` stays at `date_utils.dart:18` with no remaining lib caller — its own test S-23901 holds it.
2. Not worse. `_openCalendarScreen` (488-508) and the `_calendarState` construction (132) are byte-identical to base (the diff touches only the comment above `_buildOpenCalendarButton`); both flows (`_isHistoricalView` pop vs `OmniNavigator.push`) are intact and S-002/S-003 stay green per the lead. On the brief's premise: `_calendarState` *is* constructed in initState (132); the real pre-existing gap (unified-card-and-header-plan.md history, A5) is that `CalendarState.init()` is never awaited here, so a post-workout push can build `CalendarScreen` over an uninitialised `late` field. The diff neither widens nor fixes that; it is the same single call-site as before.
3. Yes, with the nits in findings 2-3. The `## Exercise list` section (session_summary.md 74-131): every cited test name exists exactly as written — S-24501..S-24510 in `test/summary_exercise_rows_test.dart` and S-24511..S-24516 in `test/summary_exercise_list_screen_test.dart` (all six names checked against the files), and the S-002 group / S-003 test names in `calendar_summary_screen_bugs_test.dart:75, 178-180` match; every behaviour sentence matches the code (filters, unit rule, card key, placement, Open Calendar placement). The other three docs: `calendar_periods.md:96-100` item 1 correctly says the grid is gone and cites S-24514; `design_system.md:183` header row matches the code's four OmniCardHeader titles; `navigation_and_screens.md:191` matches the two flows.
4. No assertion is weaker without reason. Old→new for everything I doubted: header_standardization `OmniSurface findsNWidgets(3)→2` and `OmniCardHeader 3→2` (counts follow the deleted card, fixtures have no logged work — sound, and the S-007 rewrite *adds* a position check under SESSION NOTE); screen_widget_test `EXERCISES findsNothing→findsOneWidget` and exercise-name `findsNothing→findsOneWidget` (flips to the new intended behaviour, not loosenings); the renames 'rolling summary does not render block headers or exercise rows'→'...block headers' and 'removes session RPE and per-exercise rows from summary'→'removes session RPE from summary' are honest (the removed halves are now true in the opposite direction and the RPE assertions stay); distance-test scoping keeps strength (finding 4). Deleted: S-001 (grid gone, per plan), S-23902/S-23903 (totals line gone, per plan, and the file header says so). Nothing else removed.
5. No wrongly-hidden finished entry and no wrongly-shown unfinished one beyond the plan's stated tolerance. For `timed`/`drill` the builder computes `elapsedSecs` as finished→`actualDurationSecs`, else `(elapsedMs/1000).round()` (`session_summary_builder.dart:369-371`); `elapsedMs` is 0 for NotStarted, so a never-started hold is hidden and a finished one shows. For `round` the filter is the stored `actualDurationSecs` itself (builder:341), 0 for a never-started round. The one residual: a stored timer left running/paused at Finish (item 27's gap) yields nonzero elapsed and *is* listed — that is D-24503's deliberate value-based rule ("a stored 0-elapsed must not read as work"), not a defect of this change. Partial holds shown as partial times is defensible output.

## Assumption Log rulings
- Base f81d7d0a / branch `claude_develop`: ratified (gateway diff-stat ran against that base; unrelated food_catalog and GeneratedPluginRegistrant changes visible and excluded, as logged).
- S-245xx ids unused before: ratified (no collisions seen in `test/`).
- Scout-sheet spot-checks (`formatTimerDigits` at `date_utils.dart:251`, builder timed keys): re-verified this run — both correct.
- `_calendarState` "never initialised" (brief premise): corrected — it is constructed at `session_summary_screen.dart:132`; the actual pre-existing gap is the missing `CalendarState.init()` (see answer 2).

## Docs delta
| Doc | Change | Status |
|---|---|---|
| `docs/session_summary.md` | overview MODIFIED | applied |
| `docs/session_summary.md` | 5. Calendar card → 6. Open Calendar button | applied |
| `docs/session_summary.md` | 4. Session note → 5. Session note | applied |
| `docs/session_summary.md` | ADDED 4. Exercise list | applied |
| `docs/session_summary.md` | layout table row | applied |
| `docs/session_summary.md` | REMOVED `- Per-exercise rows` | applied |
| `docs/session_summary.md` | post-workout entry row | applied |
| `docs/session_summary.md` | historical entry row | applied |
| `docs/session_summary.md` | `Summary data loaded on entry` item 9 removed | applied |
| `docs/calendar_periods.md` | item 1 rewritten | applied |
| `docs/design_system.md` | header table row | applied |
| `docs/navigation_and_screens.md` | SessionSummaryScreen row | applied |
| `docs/calendar_periods.md` item 2 | "Open Calendar" **header button** — the button no longer lives in a header | edit the table does not name (Minor wording; behaviour claim true and S-002-tied) |

## Scenario coverage
S-24501..S-24510 → `test/summary_exercise_rows_test.dart` (one test each, same names) | present
S-24511, S-24512, S-24513, S-24514, S-24515, S-24516 → `test/summary_exercise_list_screen_test.dart` (one test each, same names) | present
S-001 → deleted intentionally (grid gone; deletion comment points at S-24511..S-24514) | n/a
S-002, S-003, S-004 → `test/calendar_summary_screen_bugs_test.dart`, untouched and green per lead | present
S-007, S-008, Phase 2.2 headers → `test/header_standardization_test.dart`, rewritten | present
S-23901 → `test/summary_rest_days_elapsed_test.dart`, kept | present
S-23902, S-23903 → deleted intentionally (totals line gone; file header says so) | n/a
S-003-alternative (post-workout push) → `test/session_finish_timers_test.dart:256 'Session summary shows Open Calendar button'` + `calendar_summary_screen_bugs_test.dart` S-003 | present

STATUS: COMPLETE — blocker 0 · major 1 · minor 3
