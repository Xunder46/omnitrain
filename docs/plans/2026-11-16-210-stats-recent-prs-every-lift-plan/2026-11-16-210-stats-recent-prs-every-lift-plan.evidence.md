# Plan 210 — evidence

Base commit `9ce80fd5` on `claude_develop` (the seed was written at that commit; other sessions' uncommitted watch files and `test/stats_gallery_render_test.dart` are outside this plan's scopes).

## What was built

- Seed trial (lead): the production change was applied to the base and the nine reader files run before the plan was written (299 passed, 0 red); the file was then restored (compared byte for byte).
- P1 (builder, 4.9 min): `computeProgressData` scans `scanIds` (the window's top lifts, then every other lift with a `set` effort, sorted); new `_liftIdsInHistory`; `topLifts` keeps only the top lifts; doc comments of `kTopLiftCount` and `StatsProgressData.topLifts`; new `test/stats_recent_prs_every_lift_test.dart` (S-21101..S-21107, Mock and Hive). The production diff is the trial's, apart from comments.
- Lead additions: S-21108 (a lift outside the 14-training-day window keeps its catalog name; written after the mutation pass showed S-21102's Old Lift is inside that window), the stale function dartdoc of `computeProgressData` (review blocker), the docs sentence in `docs/records_and_trends.md`. `plan-lint after`: clean (8 scenarios, 2 docs-delta rows).

## Lead verification

- Plan tests: the new file (16 tests) and the nine reader files: 313 green before S-21108; the new file alone 16 green after it.
- Cost (throwaway probe, 417 sessions over two years, 40 lifts, 3 efforts of 4 sets per session, 3 timed runs after a warm-up, deleted afterwards): base `computeProgressData` Mock 9-11 ms, Hive 14-17 ms; after the change Mock 29-32 ms, Hive 36-37 ms. The base figure came from a copy of the base commit outside the repository. About +20 ms; the Mock ratio is about 3x, which touches D-7's three-times limit, judged immaterial at that absolute figure and reported to the owner.
- Mutation pass, six mutants: (a) scan the top lifts only, killed by S-21101, S-21102, S-21104, S-21107, S-21108; (b) the `topLifts` guard removed, killed by S-21103 and four `stats_progress_test` cases; (c) non-`set` ids kept in the id walk, SURVIVED and is equivalent (the three full-history walkers read only `set` efforts, so a cardio id adds nothing but a lookup); (d) the `exclude` test dropped, killed by S-21103 and six `stats_progress_test` cases; (e) the name lookup dropped, first SURVIVED (S-21102's Old Lift is name-cached because it sits inside the 14-training-day window), killed once S-21108 was added; (f) the axis decision over the top lifts only, killed by S-21104. Sources restored and compared after each mutant.
- Review (crew-reviewer): APPROVE WITH FIXES. Blocker: the function dartdoc still said the PR scan covers `topLifts` (fixed). Major: a stored placeholder (0 kg x 10 reps, from before plan 157a) can now give a "10 reps" record on any lift, not only the three window lifts; recorded as Open item 3, not fixed here. Minor: S-21106's wording (fixed).

## Final runs

Full suite (lead, 900 s cap, after S-21108 and the dartdoc fix; the dartdoc edit landed during the run and is comment-only): `+7739 ~4: All tests passed!`, 0 failures, 5 min 49 s. `flutter analyze`: 181 issues (baseline 181), 0 errors.

## Not done / residual

- Open item 3: placeholder sets and a watch-linked session's planned sets (until plan 157d) can produce records for lifts never trained; reachable for every lift now.
- Plan 211 (all-time Best for cardio without distance and for rounds) is the other half of review item 6.
- (owner) A device check: log a first set on four or more lifts over a few days and open Records & Trends: five entries.
