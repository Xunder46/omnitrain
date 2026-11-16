# Review: plan 212 (one failing signal or Fuel read no longer blanks the Stats screen) · P1-P2 · b70dc61b..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: not run by reviewer (brief: builders' runs green, mutation pass 4/4 killed, lint baseline 181, plan-lint clean)
Diff vs Predicted Files: conforms except `docs/plans/2026-11-13-157-stats-what-counts-series.md` — a one-line status flip of the plan 211 row ("built, verified, uncommitted" -> "committed"), bookkeeping for the other plan's landing, not this plan's change. All other changed files match the Predicted Files.

## Findings

1. [Major] docs/widget_catalog/layout_and_inputs.md:269-270 — the `LoadFailureView` entry says the surface is rendered "when their one load read throws". After plan 212 that is false for the Stats screen: the optional reads (signals, Fuel summary, weight trend) no longer fail the load; only the core reads do. The plan's Stale-term sweep pattern included `one load read` and should have matched this line, but the sweep row lists only `stats_screen.md:603-604`, `signals.md:264` and `widget_catalog/layout_and_inputs.md:278` — the entry at :269-270 was missed. Fix: reword to name core reads (e.g. "when the host's core load read throws — for Stats, the totals, the Instruments list or the Mix layer") and add the line to the plan's Stale-term sweep. Guard: doc-only; extend the sweep list, no test.

2. [Minor] lib/core/services/signals_service.dart:110-112 — one signal-adjacent optional read can still throw into `_loadData`'s outer catch: `loadDismissals()` calls `_repository.getPreferenceString(kSignalDismissalsKey)` with no guard, so a preference store that cannot be read still blanks the whole screen even though every signal evaluation is now guarded. The parse half is safe — `parseSignalDismissals` (`lib/core/models/signals.dart:155-171`) catches `FormatException`, rejects non-map and non-int entries, and never throws. Pre-existing behaviour that D-1/D-4 deliberately leave untouched and no doc claims otherwise, so not a violation of this plan; suggest recording it in Open items next to item 1.

## Answers to the brief's five questions

1. **Remaining throw paths after the two guards** (read: `stats_screen.dart:119-243`, `signals_service.dart` whole):
   - Core, deliberately unguarded (D-2): `computeTotals`, `computeInstrumentSections`, `computeMixLayer` (its history reads go through `_loadHistory`, `stats_progress_service.dart:107-123`, including `getAllSessions`).
   - Optional, guarded: `signal.evaluate` (per-signal try/catch, `signals_service.dart:59-65`), `computeFuelSummary` (`stats_screen.dart:146-151`).
   - Optional, already safe: `waitingLines` wraps every `signal.waitingFor` per line ("Absent rather than broken", `signals_service.dart:92-102`); `WeightTrendService.compute` catches and returns null (`weight_trend_service.dart:12-18`).
   - Optional, still able to throw: the `getPreferenceString` read inside `loadDismissals` — Finding 2. The parse half cannot throw.
   - Pure, no reads, cannot reach the repository: `signalsGateMet(mixLayer)` (computed from the already-built mix), `resolveSignals(...)` (pure resolver over candidates + the read dismissal map, `signals.dart:169+`).
   - `_signalsWriteTail`: awaiting it cannot rethrow — the chain is built from `persistDismissals`, which swallows write failures (`signals_service.dart:126-136`).
   - The Fuel vs Load signal's own nutrition reads run inside `signal.evaluate`, so they are covered by D-1, not by the Fuel guard.

2. **Does swallowing a signal's throw change anything else in a load?** No. The throw is caught at `signals_service.dart:59-65` with `continue`: the loop keeps registry order, the other signals' cards pass through the same dismissal filter with the same `dismissed` map read once before the loop, and the gate (`signalsGateMet(mix)`) is computed before the loop and is unaffected. The throwing signal's `evaluate` is still called, so an evaluation count a test reads (e.g. S-1709's) is unchanged. **Stale state:** none. `evaluateCandidates` builds a fresh `cards` list per call; `SignalsService` caches nothing (only `StatsProgressService` caches the history index, and the screen builds one service per load, `stats_screen.dart:136-137`). The screen assigns `_signalsCandidates` and `_signalsData` from one load's results in a single `setState` guarded by the generation check, so a signal that throws on load 1 and works on load 2 simply reappears on load 2; nothing from load 1 survives except the fields load 1 itself assigned.

3. **The rewritten S-18207** (`test/signals_layer_screen_test.dart:1097-1160`): OK. It keeps the meaning of its name: first pump shows `Could not load your stats.` with `firstFails.calls == 1`; after `setStartOfWeek('sunday')` + reload, the failure line is gone, `stub.seenOnEvaluate == 'sunday'` (set inside `_StubSignal.evaluate`, :185) and the card `recovered on sunday` shows. The failure is a real core failure on the screen's path: `_FirstLoadFailsRepository.getAllSessions` is read by `_loadHistory` (`stats_progress_service.dart:113`), which backs `computeTotals`, the first read of `_loadData`; arming after `initialize()` is correct because the Mock's migration reads `getAllSessions` during initialization. It cannot pass for another reason: the failure view asserts `findsOneWidget` on the first pump and pins exactly one armed call (`calls == 1`), and the silent reload runs because `_loadData` sets `_startOfWeekInUse` before the try, so a failed load still registers the old week. `_FlakySignal` is deleted; no other reference remains.

4. **Base-behaviour failures:** S-21301/S-21302 (`test/stats_one_failure_service_test.dart`): without the guard `evaluateCandidates` rethrows the first signal's throw, so the `await` in each test throws and the expectation of a returned list fails — red at base. S-21303: without the guard the throw propagates through `evaluateCandidates` into `_loadData`'s outer catch, the failure view renders, and `find.text('Could not load your stats.'), findsNothing` fails — red at base. S-21304: without the Fuel guard `computeFuelSummary` (which reads `getConsumedFoodsInRange`, `stats_progress_service.dart:2057` — the exact method `_FoodReadFailsRepository` overrides) rethrows into the outer catch — red at base. The control (`S-21304 the control`, failing=false) asserts `fuel_row` present with the same seeding and viewport, which makes the failing test's `findsNothing` meaningful: it rules out the row being absent for a false reason (off-screen at the 400x2400 viewport, food never seeded, wrong key).

5. **Docs:** the new sentences say only what the code does — "nothing is logged" is true (both catches are `catch (_)` with no logging); "The Weight block already behaved this way" is true (`weight_trend_service.dart:10-18`); "The waiting lines already worked this way" is true (`signals_service.dart:92-102`); every test name quoted in the additions exists. `signals.md:263-264` ("evaluates each registered signal once") stays true under the guard — `evaluate` is still called, the throw is caught after. Stale sweep outside plans/history/releases found exactly three live files: `stats_screen.md:604` (the rewritten sentence, true), `signals.md:264` (true), `widget_catalog/layout_and_inputs.md:273/278` — :278 is the example string, still true; :273's neighbour at :269-270 is Finding 1. Nothing else stale.

## Docs delta

- `docs/stats_screen.md` MODIFIED "When a core read throws ... LoadFailureView" -> applied (stats_screen.md:603-609, names `stats_load_failure_test.dart` S-2704).
- `docs/stats_screen.md` ADDED "Each signal and the Fuel row are optional" -> applied (stats_screen.md:611-617, names `stats_one_failure_screen_test.dart` S-21303/S-21304).
- `docs/signals.md` ADDED "A signal that throws is left out" -> applied (signals.md:268-272).
- `docs/signals.md` ADDED `test/stats_one_failure_service_test.dart` -> applied (signals.md:271-272, S-21301/S-21302).

Doc edits the table does not name: the series-index row flip (`docs/plans/2026-11-13-157-stats-what-counts-series.md:35`, plan 211's status, another session's bookkeeping); the stale line of Finding 1 should also be added to the sweep row.

## Assumption Log rulings

- base commit `b70dc61b` on `claude_develop`; other sessions' files in the tree -> ratify (confirmed by the diff stat; the named ignores did not appear in this diff).
- scenario ids S-213xx unique -> ratify (grep in the log; not re-run).
- Fuel read added to the owner's item-8 wording -> ratify (`computeFuelSummary` reads `getConsumedFoodsInRange`, `stats_progress_service.dart:2057`, an unguarded repo read before this change).

## Scenario coverage

S-21301 -> test/stats_one_failure_service_test.dart · `the throwing signal is skipped, the others speak in order` (Mock and Hive groups)
S-21302 -> test/stats_one_failure_service_test.dart · `the result is empty and the call does not throw` (Mock and Hive groups)
S-21303 -> test/stats_one_failure_screen_test.dart · `S-21303 a signal that throws does not blank the screen`
S-21304 -> test/stats_one_failure_screen_test.dart · `S-21304 the control: with the food log readable the row shows` + `S-21304 a food read that throws leaves the row out, not the screen`
S-18207 (rewritten) -> test/signals_layer_screen_test.dart:1125 · `S-18207 a reload that succeeds replaces the failure view`
