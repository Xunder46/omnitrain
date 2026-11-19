# Review: 157c · phases 1-2 (build + docs) · cd117f79..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: not run (brief forbids the full suite; lead's facts accepted: new tests green on Mock and Hive, five reader files green unedited, mutation pass 9/9 killed, analyze at baseline 181)
Diff vs Predicted Files: conforms — `training_load.dart` (+13), `sustained_high_load.dart` (+22 incl. comment wraps), `stats_progress_service.dart` (the `weeklyLoads` hunks only; the `epley1RM`/`_repsAxisExercises` hunks in the same file are 157b's, as the plan's Assumption Log records), new `test/sustained_high_load_unrated_weeks_test.dart`, `_seedFTwo` edit in `test/cardio_efficiency_drift_signal_screen_test.dart` (the plan's Feedback row), three docs. Everything else in `git-diff --stat` belongs to 157a/157b/another session.

## Findings

1. [Major] `lib/core/models/sustained_high_load.dart:112` and `docs/signals_registered.md:37-38` — the clause "an empty week counts as zero, never the mean of the rated weeks only/alone" is now false in a reachable shape. The new divisor is `12 − unrated` = rated + empty; in a window with unrated weeks and no empty weeks (8 rated at 100 + 4 unrated), the usual is exactly the mean of the rated weeks alone (800/8 = 100). A maintainer reading the "never" clause would believe that shape impossible. The operative formula in the same sentence ("divided by the twelve weeks less the weeks that held only unrated sessions") is correct and pinned by S-15901, so this is a leftover contrast clause the change made falsifiable, not a wrong rule — hence Major, not Blocker. Fix: drop the "never the mean of the rated weeks only/alone" clause in both places, or reword to "an empty week counts as zero; the divisor is the twelve less the unrated ones". Guard: none (comment/doc only). The code comment is verbatim the plan's own text, so this is a plan-text defect carried through, not a builder deviation.
2. [Minor] `lib/core/models/training_load.dart:94` + `lib/core/models/sustained_high_load.dart:125` — residual partial-rating bias, reachable but outside this plan's stated scope. A week holding both rated and unrated sessions still reads `hasRatedSession: true`, keeps its place in the divisor and in the 8-rated-weeks floor, and its unrated sessions contribute 0 to `loadMinutes` (`_sessionSplit` zeroes unrated sessions). A user who rates half of each week's sessions sees those weeks count as fully rated weeks whose load is only the rated half, so the usual is biased low and the card can fire although true training was steady. This is a finer-grained version of the very bias the Goal removes, but the Goal and D-6 deliberately scope to whole unrated weeks (`hasRatedSession` semantics unchanged; the Mix layer keeps its own behaviour). Fix: none in this plan; record the partial-week bias in the plan's Open items for the series. Guard: a future scenario seeding a half-rated week in the baseline window.

## Assumption Log rulings

- Base `cd117f79`, branch `claude_develop`, 157a/157b uncommitted in the same tree, `stats_progress_service.dart` shared with 157b (different methods): ratified — the file's diff shows 157b's hunks in `computeProgressData`/`_repsAxisExercises`/`epley1RM`, disjoint from the three `weeklyLoads` hunks this plan claims.
- Mirror-script fixtures (S-15903 old streak 5 / new 0; S-15901 usual 66.67 → 80.0; S-15904 gap 3 → null; S-15905 streak 2 under both): ratified by hand — for S-15903 any candidate's window holds weeks 0-11 with unrated count 4, total 800, usual 100, and 100×100 < 100×110, so no week is higher; under the old rule usual 66.67 qualifies a 5-week run with ratedWeeks 8 ≥ 8.
- Lead's Feedback edit (rated zero-minute sessions in F-9A's quiet weeks, S-2511): ratified — tests-only, the added comment in `_seedFTwo` states the reason (unrated cardio sessions would make those weeks unrated and shrink the baseline), and the brief records all weekday variants green.

## Brief questions

1. Readers of `WeeklyLoad`/`weeklyLoads`/`hasRatedSession` in `lib/` (grep): only `stats_progress_service.dart` (producer), `sustained_high_load.dart` (the rule) and `signals/sustained_high_load_signal.dart:43-58` (calls `weeklyLoads` → `sustainedHighLoadStreak` → `sustainedHighLoad`; both covered by the change). No other reader assumes an unrated week is empty. OK.
2. `hasSessions` vs `loadByWeekStartMs`: they cannot disagree. Both are keyed by the same `weekStartMs` computed per session from `startedAtMs` via `OmniDateUtils.startOfWeek` (local midnight of the week's first day, `date_utils.dart:95-101`) with the `startOfWeek` setting read once at the top of `weeklyLoads` (`stats_progress_service.dart:600`); the emit loop rebuilds weeks as local-midnight `DateTime(y, m, d+7)` steps from `earliestWeekStartMs`, which reproduces the same local-midnight keys on a DST-change walk (both sides are local midnight of the same calendar days, so the UTC offsets agree). A session in `now`'s week is bucketed but that week is never emitted — consistently for all three maps. OK.
3. See Finding 2: reachable, outside the stated scope; a half-rating user sees the card fire against a usual built from rated-half loads.
4. Excluding unrated weeks can make the card fire when it should not only in this sense: relative to the truth, the usual becomes the mean of the rated weeks (plus empty-week zeros), so if the excluded weeks' real training was heavy the usual understates it and the 110% bar is passed too easily — the error direction is usual-low → too-eager firing. Relative to the old rule the direction is the opposite (divisor shrinks while the total keeps the zeros, so the usual rises and firing becomes harder). The 8-of-12 floor bounds it (at most 4 excluded weeks, divisor ≥ 8). This is the accepted "unknown, not zero" tradeoff of D-3, not a regression the plan claims to remove. OK (analysis; no code finding).
5. Docs delta: all four rows applied and true against the code; one stale clause the rows leave behind is Finding 1.

## Scenario coverage

S-15901 -> test/sustained_high_load_unrated_weeks_test.dart · 'S-15901 unrated weeks are left out of the baseline divisor' (red at base: usual 66.67 ≠ 80.0)
S-15902 -> same file · 'S-15902 an empty week still counts as zero in the baseline' (passes with and without by design; mutation (c) guard)
S-15902b -> same file · 'S-15902b a window of twelve unrated weeks has no usual and no rated week' (passes with and without by arithmetic; mutation (h) guard)
S-15903 -> same file · 'S-15903 starting to rate late no longer fires the card' (red at base: old rule fires)
S-15904 -> same file · 'S-15904 an unrated week is not an easier week' (red at base: gap 3)
S-15905 -> same file · 'S-15905 an unrated week breaks a higher-load run' (passes with and without by design; mutation (i) guard)
S-15906 -> same file · 'S-15906 ${harness.name}: weeklyLoads marks which weeks held sessions', Mock and Hive harness groups (red at base: `hasSessions` does not exist; mutation (f)/(g) guards)

## Docs delta

- `docs/training_load.md` MODIFIED ("the twelve weeks less any week that held only unrated sessions, an empty week counting as zero", line 181) -> applied; sentence true against `sustainedHighLoadBaseline`.
- `docs/signals_registered.md` MODIFIED (baseline divisor, lines 37-41) -> applied; names `test/sustained_high_load_test.dart` (`the baseline stage abstains below twelve earlier weeks`, seen at `test/sustained_high_load_test.dart:45`) and the new test file; the leftover "never the mean of the rated weeks alone" clause is Finding 1.
- `docs/signals_registered.md` MODIFIED (easier week, line 68) -> applied; true against `sustainedHighLoadEasierGapWeeks` (`isUnrated` skip at `sustained_high_load.dart:216`).
- `docs/state_management/services_and_utils.md` ADDED (hasSessions bullet, line 534) -> applied; true against `weeklyLoads`, names `test/sustained_high_load_unrated_weeks_test.dart` with the exact test names as they appear in the file.
- Doc edit the table does not name: none found in the three docs for this plan (the other `services_and_utils.md` hunks — axis rule, Epley cap — are 157b's).
