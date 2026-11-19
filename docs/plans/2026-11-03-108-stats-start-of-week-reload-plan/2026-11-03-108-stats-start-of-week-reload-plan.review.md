# Review: 108 stats-start-of-week-reload · P1-P4 · 8dc98c18..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 0 · minor 0 · tests: not run (brief forbids a suite run; brief reports the targeted suites green and `flutter analyze` at the base count 181)
Diff vs Predicted Files: conforms — exactly the four plan files; the two out-of-scope dirty files (`lib/core/services/stats_progress_service.dart`, `test/stats_dst_day_arithmetic_test.dart`) are another session's, per brief, and untouched by this diff.

## Findings

1. [Blocker] lib/features/stats/stats_screen.dart:126-131 and 224-233 — a successful silent reload never clears a previous failure. `_loadFailed = false` now lives only inside the `if (!silent)` head setState; the success setState does not reset it. A user whose first load failed (or whose silent reload failed, D-18204) and who then flips Start of Week keeps the `LoadFailureView` even though the reload just put fresh data into state (build at :334-339 shows the error view whenever `_loadFailed` is true); only Retry recovers. Unmet acceptance 2 ("swaps it when the new numbers are ready") in that state. Fix: add `_loadFailed = false;` to the success setState (one line). Guard: a test that fails the first load (a throwing repository or stub), flips Start of Week, and expects the content and not `LoadFailureView` after the reload — it would fail without the fix. Note: the diff implements the plan's exact code verbatim; the gap is in the plan's code, not in the builder's execution of it.

## Assumption Log rulings

- "lead-seeded with exact code, no architect run" — ratify: the on-disk production code matches the plan's P1 hunks hunk for hunk, and the six scenarios have real tests.
- "the reload is silent …; a failed silent reload shows the same error view (D-18204)" — ratify the failure half as stated; escalate the success half: the same assumption did not consider a silent reload succeeding after a failure, which is finding 1.

## Docs delta

- docs/theme_and_settings.md ADDED "changing `Start of Week` while Stats is open" -> applied
- Doc edits the table does not name: none (the only doc in the diff is `docs/theme_and_settings.md`; `docs/stats_screen.md` untouched as the plan requires).

## Scenario coverage

- S-18201 -> test/signals_layer_screen_test.dart · 'S-18201 flipping to Sunday re-asks the signals, with no spinner'
- S-18202 -> test/signals_layer_screen_test.dart · 'S-18202 Weight on Stats and a repeated Start of Week do not reload'
- S-18203 -> test/signals_layer_screen_test.dart · 'S-18203 a slow older load never overwrites a newer one'
- S-18204 -> test/signals_layer_screen_test.dart · 'S-18204 a Stats screen under another route follows the flip'
- S-18205 -> test/mix_layer_screen_test.dart · 'S-18205 the oldest column's date moves when the setting flips mid-session'
- S-18206 -> test/signals_layer_screen_test.dart · 'S-18206 the reload waits for the dismissal write'

All six assert a state the base cannot reach (the lead's M1-M5 each turned one red; M6 is declared diff-read only). The S-18203 and S-18206 tests inline a copy of `pumpStats`'s body with the settling `pumpAndSettle` deliberately omitted (commented in both places); the copies match the helper today.

## Brief questions

1. No. Only the newest load's two completion paths touch `_isLoading`, and both set it false (success :232, catch :237); a superseded load returns at the generation guard before any setState. The only spinner window is a flip during the first non-silent load: that load's own spinner stays up until the silent reload finishes — honest (a load is in flight), never stuck.
2. No path in practice. The listener is removed synchronously in `dispose`, and `_loadData` re-checks `mounted`. Between `initState` and the post-frame first load, `_startOfWeekInUse == null` makes `_onSettingsChanged` return, and the post-frame load reads the current value — correct.
3. Consistent with D-18204. A failed silent reload swaps content straight to `LoadFailureView` with no preceding spinner; `onRetry: _loadData` (:339) runs non-silent, so Retry shows the spinner first, as today. The only difference a user notices is the missing spinner before the error — the intended "no flash" behaviour. (The adjacent success case is finding 1.)
4. True clause by clause, each tied to a named group that exists: background refresh with no spinner and the signals' week/waiting lines -> S-18201 (`seenOnEvaluate`/`seenOnWaiting` `'sunday'`, no `CircularProgressIndicator`); underneath another screen -> S-18204; Mix strip columns -> S-18205; no other setting and no same-value reload -> S-18202 (`evaluations` stays 1); dismissed card stays dismissed -> S-18206. All three named group names match the test files verbatim.
5. Survivors: (a) M6 — one `startOfWeek:` argument read per-await again; the setting is stable for the whole of every load in all six tests, so no test can kill it (plan declares this, covered by diff reading). (b) Removing the generation guard in the `catch` only (half of M3): no test has an older load throw after a newer one completes; if it happened, a dead load could paint `_loadFailed` over good data. (c) Removing `removeListener` in `dispose` and removing the `inUse == null` guard both survive, but are defensive only (a post-dispose leak; a benign double load the generation counter drops). The two hinted hiding places do not hide anything: S-18201's spinner assertion is made exactly when M5's spinner would already be up (the silent head's setState runs synchronously inside `runAsync`), and S-18202's `settleStore` gives a wrongful reload the real turns it needs to increment `evaluations`.

## Resolution (lead, 2026-11-03)

Finding 1 (Blocker) fixed in fix round 1: `_loadFailed = false;` added to the success `setState` (D-18207); guard test S-18207 `a reload that succeeds replaces the failure view` fails when the line is removed (M7) and passes with it. Full suite green afterwards.
