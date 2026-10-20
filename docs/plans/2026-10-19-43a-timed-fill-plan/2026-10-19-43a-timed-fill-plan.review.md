# Review: 2026-10-19-43a-timed-fill-plan · P1–P3 · e6ff75b0 + 42a/42b..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 2 · nit 0 · tests: 5078 passed, 1 skipped, 0 failed (`02:54 +5078 ~1: All tests passed!`, gateway `test`, 2026-10-19 23:45 log)
Diff vs Predicted Files: conforms — every 43a predicted file appears in `git-diff --stat e6ff75b0` (importer, timer mixin, session screen, 2 new test files, 2 docs, plan dir); the rest of the 74-file diff is the plan-declared co-tenant work (plans 41, 42a/42b uncommitted in the same tree).

## Findings
1. [Minor] docs/plans/2026-10-19-43a-timed-fill-plan/2026-10-19-43a-timed-fill-plan.md (Core scenarios list) — the plan defines S-5001..S-5009 only, but the brief and the evidence review S-5001..S-5011; S-5010 (hole fixture: instances 0,1 with rows 0,2) and S-5011 exist as passing tests and evidence rows with no definition in the plan, so a maintainer reading the plan alone cannot tell what S-5010/S-5011 assert. Fix: add S-5010 and S-5011 to the plan's scenario list with one-line definitions matching the evidence table. Guard: none (doc-only); the tests already exist.
2. [Minor] docs/plans/2026-10-19-43a-timed-fill-plan/2026-10-19-43a-timed-fill-plan.md (D-4) vs lib/features/session/workout_session_timer_mixin.dart:222-245 — D-4's letter says finished-timer keys are dropped when "finished or gone"; the code deliberately leaves a gone key (comment: a reload may be in flight) and only drops keys whose instance is finished. A maintainer implementing D-4 verbatim would delete state a concurrent reload still needs. Fix: one sentence in the plan ratifying the gone-key deviation (or align D-4's wording). Guard: S-5007b asserts the current behaviour.

## Assumption Log rulings
- A-1 — ratify. D-6 (no new user-facing copy) is implemented; S-5008/S-5009 prove the screen surfaces filled intervals without new strings.
- A-2 — ratify. The evidence states the pre-existing crash was not reproduced and S-5008 is kept as a guard; the full run above is green.

## Scenario coverage
- S-5001 -> test/watch_timed_fill_test.dart · test named S-5001 (Mock and Hive groups)
- S-5002a -> test/watch_timed_fill_test.dart · test named S-5002a (Mock and Hive groups)
- S-5002b -> test/watch_timed_fill_test.dart · test named S-5002b (Mock and Hive groups)
- S-5003 -> test/watch_timed_fill_test.dart · test named S-5003 (Mock and Hive groups)
- S-5004 -> test/watch_timed_fill_test.dart · test named S-5004 (Mock and Hive groups)
- S-5005 -> test/watch_timed_fill_test.dart · test named S-5005 (Mock and Hive groups)
- S-5006 -> test/watch_timed_fill_test.dart · test named S-5006 (Mock and Hive groups)
- S-5007 -> test/watch_timed_fill_test.dart · test named S-5007 (Mock and Hive groups)
- S-5007b -> test/watch_timed_fill_test.dart · test named S-5007b (Mock and Hive groups)
- S-5008 -> test/watch_timed_fill_screen_test.dart · test named S-5008
- S-5009 -> test/watch_timed_fill_screen_test.dart · test named S-5009
- S-5010 -> test/watch_timed_fill_test.dart · test named S-5010 (Mock and Hive groups)
- S-5011 -> test/watch_timed_fill_test.dart · test named S-5011 (Mock and Hive groups)
None MISSING.

## Brief questions (answers, condensed)
1. Row-id collision on fill: not reachable. The fill row reuses the doomed row's number and `createObservation` derives the row id from that number, so the new row replaces exactly the deleted one; the `rowNumber ?? index` fallback is unreachable because half-written instances are caught by the unfinished branch first; `deleteTimedEntry` reindexes densely, so numbers never diverge from positions in a way that could clobber a neighbour. S-5002a/S-5002b/S-5006/S-5010 pin the fixtures.
2. `_placed` index assumptions: sound. Positions equal entry indices for non-set kinds; timed/hold/round corrections ignore the index and resolve the instance by id; `_reindexInstance` is a no-op after a fill; sets are never filled.
3. `fillPlanned` callers: exactly one — `_mergeHeld`, reached only when the phone owns the session; the history-import path never fills. An ended-but-still-held session can still fill, which matches "logs once" and is harmless.
4. `_dropFinishedTimerState`: safe. The log flow resets timer state before the unawaited finish; the expiry handler cleans the key synchronously; reset is idempotent; only one effort timer runs at a time (in-progress lock); fill targets the first unfinished instance, so no live key is dropped. Gone keys are left by design — finding 2.
5. Docs claims: conform. Every test name the docs and evidence cite exists verbatim; watch_surface.md and watch_session_capture.md paragraphs match the code; no 43b/43c behaviour claimed; the crash is stated plainly as not reproduced.
