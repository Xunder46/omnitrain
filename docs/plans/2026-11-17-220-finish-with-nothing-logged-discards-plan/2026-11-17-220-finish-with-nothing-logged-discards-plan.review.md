# Review: plan 220 finish-with-nothing-logged-discards · P1+P2 · 964dc4c7..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 3 · tests: builders' runs pasted in the brief (220: 8 + 2 green; the two fixed readers green); full suite not run per brief
Diff vs Predicted Files: conforms, outside: `test/session_finish_timers_test.dart` (two readers fixed — the plan's Readers rule said "reported, not edited"; brief-sanctioned, finding 3), `docs/modality_based_exercise_ui.md` (named by the Docs delta but not the Predicted list; the Predicted list's "one doc" is stale — the delta names two)

## Findings
1. [Minor] lib/state/workout/session_core_lifecycle.dart:161-206, lib/features/session/workout_session_finish.dart:31 — a session whose only logged content is skip-marked sets reads `completedExerciseCount() == 0` (the count's own doc: "a skip-marked set alone does not count", :163), so Finish asks `Discard Workout?` with the sentence "Nothing was logged, so this workout won't be saved." — but the user did log skips, and `endSession`'s own rule keeps skip-marked sets in a saved workout (:148). The user who marked skips to record what they did not do loses that record on Discard, and the dialog's sentence is untrue for this case. No scenario covers a skip-only session. Fix (owner call, one line either way): treat a skip-marked set as something done in `finishWouldSaveNothing`, or pin the current behaviour with a state test and accept the wording. Guard: a skip-only case in `test/finish_nothing_logged_discards_test.dart`.
2. [Minor] docs/rolling_sessions.md:42 — the Finish/Done row's standard-session cell ("non-empty sessions end with elapsed time recorded") is now false for a non-empty session with nothing logged: it now asks `Discard Workout?` and may discard. The plan's stale-term sweep covered only `session_summary.md` and `modality_based_exercise_ui.md`. Fix: one clause in that row (a non-empty session with nothing logged asks to discard, plan 220). :63 (truly-empty session discards immediately, no confirmation) stays true.
3. [Minor] test/session_finish_timers_test.dart:137-147, :260-270 — the plan's Readers rule says a reader whose session has nothing logged "is reported, not edited"; the lead edited two readers instead (sanctioned by the brief: "two readers fixed"). The edits preserve both tests' premises: both finish a workout with a started timed entry (`effortKindOverride: 'timed'` + `startTimedEntry`) and still assert timer finalisation and the no-Back guarantee, so the names stay true. Fix: record the decision in the plan's Feedback so plan and tree agree.

## Assumption Log rulings
- Base commit `964dc4c7` with plan 219 uncommitted in the tree — ratify: the diff stat shows 219's files (`records_link_row.dart`, `stats_records_link_test.dart`, `stats_gallery_render_test.dart`, primer files); excluded per brief.
- "Scenario ids checked: none in the five-digit form" — ratify: no other S-220xx seen in the test files read this run; repo-wide uniqueness not checked.

## Scenario coverage
S-22001 -> test/finish_nothing_logged_discards_test.dart · four tests (typed-unlogged then logged; started timed; wrist runs; staged wrist row) × both harnesses | present
S-22002 -> test/finish_nothing_logged_discards_screen_test.dart · 'S-22002 Finish on a typed-but-unlogged workout asks to discard, then discards on confirm' | present
S-22003 -> test/finish_nothing_logged_discards_screen_test.dart · 'S-22003 a workout with something done keeps the normal Finish dialog' | present
Not covered: a skip-only session (finding 1); a rolling session with exercises but nothing logged (follows the owner decision; same path).

## Brief questions
Q3 — verdict OK (minors 1, 3): the discard path is identical to the empty-workout path (`_leaving = true; await discardCurrentSession(); pop`, workout_session_finish.dart:16-18 vs :37-39); `discardCurrentSession` closes in-memory rests, deletes the row, clears state, then hands the row to the health delete (session_core_lifecycle.dart:269-292). A started timed/round/drill exercise counts (:190-204); block/superset work is set/timed/drill/round efforts — no other effort kind exists. The reload concern is covered: an in-progress session is restored through `loadHistoricalSession` (home_screen.dart:186-190), which re-reads entry rests, timed and round instances from the store (session_core_io.dart:88-103), and the watch merge refreshes the same caches (`refreshEfforts`), so a logged set is never invisible to the count after a reload. A wrist row staged after the check but before Discard is the plan's documented gap (Input-reality 7). `if (!mounted) return;` sits directly after the await and before any context use — correct.
Q4 — S-22001 fails at base (the method does not exist); S-22002 fails at base (base shows `Finish Workout?` and saves an empty workout); S-22003 passes on both by design (pins, mutation target "the check ignores the count").
Q5 — the two new doc sentences are true and name the new tests; the wrist docs that say the wrist End asks `Finish Workout?` (docs/watch-app-qa-wrist-logging.md:594, docs/state_management/watch_surface_wrist_logging.md:14) stay true because a watch-linked workout never takes the new path; `rolling_sessions.md` is the one stale file (finding 2).

## Docs delta
docs/session_summary.md ADDED `Discard Workout?` -> applied (paragraph after the plan-217 sentence, names both new test files)
docs/session_summary.md ADDED `finishWouldSaveNothing` -> applied (same paragraph names `WorkoutState.finishWouldSaveNothing`)
docs/modality_based_exercise_ui.md ADDED `Discard Workout?` -> applied (Finish Workout Flow section)
Not named by the table: docs/rolling_sessions.md:42 (finding 2).
