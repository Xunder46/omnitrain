# Review: 107 stats-load-reads · P1-P3 · 7e645703..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: not run (brief says the lead ran the targeted suites green, analyzer at base 181, mutations M1-M6 each red; this review runs no suite per brief)
Diff vs Predicted Files: conforms — the 8 changed files are exactly the plan's list; `stats_progress_service.dart` additionally carries the two pre-existing DST hunks (`topExerciseRecencyCutoff`, nutrition-target cursor loop) the plan declares as another session's work; this plan's three hunks there are additive and never touch them.

## Findings
1. [Minor] test/stats_load_single_read_test.dart:196-206 — S-18104's third window is asserted only by `identical(first, third), isFalse`; no content figure of the third build is asserted. With this fixture no figure *can* differ (the extra day is after `now`, the hold session sits inside both windows, and the preceding comparison range is unchanged), so the plan's "its row's summary.sessionCount or points differ" clause is vacuous here — but a `_buildInstrumentSections` that ignored the window entirely would pass this test. That mutant is outside M1-M6 and window-content behaviour is covered by the existing `stats_progress_service` tests, so this is a coverage nuance, not a gap in the plan's mutation proof. Fix (optional, smallest): assert `third` equals a fresh service's build for the same third window (value equality), proving it was built for its own window rather than merely a different object. Guard: the same test, one extra expect.

## Answers to the brief's five questions
1. Yes, behaviourally identical for a freshly constructed service: same predicate (`endedAtMs != null`, `0 <= startedAtMs <= now` — the old read's lower bound came from the repository's `fromMs=0` range filter, the new code makes it explicit with `startedAtMs >= 0`), same ascending order (the old order came from `getSessionsByDateRange`'s sort, the new from `..sort()`), same `DateTime.fromMillisecondsSinceEpoch` mapping. The only difference is the source — the cached `_loadHistory()` snapshot instead of a live repository read — which is the intended change (D-18102); the freshness contract ("construct a new service") is unchanged.
2. No. `lib/` call sites: `stats_screen.dart:126` constructs a fresh `StatsProgressService` inside `_loadData()` per load, so the memo never survives a write; `hold_progress_signal.dart:29` asks the same instance for the same window — the intended reuse. No caller holds a service across a data write and expects fresh sections.
3. Yes. The Consistency paragraph's "served from the service's cached history snapshot, so the repository is not read again" matches `completedSessionStarts` → cached `_loadHistory()`; the Hold Progress paragraph's "returns the same sections the Instruments list built" matches the memo with the screen's same-instance/same-window call; the two `services_and_utils.md` additions state the return contract, the `session_history.dart` path, and the one-build-per-window rule, each citing a test whose group/test names I matched character for character against the new file (including harness names `Mock`/`Hive`). The remaining `walks no history of its own` sentences in `signals_registered.md` (92, 207, 293, 350, 467, 572) are the Mix-payload signals and stay true; the two `docs/stats_screen.md` "no second walk of history" lines (323, 727) are true as written and correctly left unedited.

   Docs delta:
   - docs/signals_registered.md Consistency adapter sentence -> applied
   - docs/signals_registered.md Hold Progress adapter sentence -> applied
   - docs/state_management/services_and_utils.md ADDED `completedSessionStarts({required DateTime now})` paragraph -> applied
   - docs/state_management/services_and_utils.md ADDED "a second call for the same window returns the first call's sections" -> applied
   - Doc edits the table does not name: none (the added "Verified by" citations are part of the two MODIFIED rows).
4. No. `First day shown in the calendar` survives only under `docs/plans/` (excluded by the question); `lib/`, `test/` and the other `docs/` are clean.
5. No hiding place for the plan's mutants: the S-18102 counters are reset after seeding and before the load (`repo.allReads = 0; repo.rangeReads = 0;`), so seeding reads are not counted; S-18103 seeds newest-first with an open, a future and an exactly-at-`now` session, so M1 (open included), M2 (`<` drops the at-`now` session) and M3 (unsorted gives seed/snapshot order, not oldest-first) each flip the `equals([...])`; S-18104's `expect(first, isNotEmpty)` stops an empty-list build from passing the `identical` checks by accident, M4 (direct call → two distinct lists) breaks `identical(first, second)` and M5 (`fromMs`-only key → third returns the cached first list) breaks `identical(first, third), isFalse`. Residual hole: the Minor above (a window-ignoring build), which is not one of M1-M6.

## Scenario coverage
S-18101 -> test/interaction_flow_test.dart:1537 (the changed `find.text` expect) | covered
S-18102 -> test/stats_load_single_read_test.dart › `S-18102 one Stats load reads the session list once` › `computeTotals plus the signals evaluate on one getAllSessions` | covered
S-18103 -> test/stats_load_single_read_test.dart › `S-18103 completedSessionStarts — Mock` and `— Hive` › both tests | covered
S-18104 -> test/stats_load_single_read_test.dart › `S-18104 the Instruments sections are built once per window` › `a second ask for the same window is the first list; a new window rebuilds` | covered (identity-only on the third window; see Minor 1)

## Assumption Log rulings
- Lead-seeded plan, no architect run: ratify — the production code in the diff matches the plan's exact code hunk for hunk.
- Prover skipped, lead's mutations M1-M6 stand in (D-18106): ratify — per the brief's established facts each mutation made a new test fail; the tests' sensitivity to M1-M6 is consistent with my own reading of them.
