# Review: 103 signals-waiting · P1a, P1b, P2a, P2b, P3 · working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 2 · tests: governor ran (brief: touched files green, `signals_waiting_test` + `signals_layer_screen_test` + `signals_service_test` + `signals_framework_test` +126 on both harnesses; full suite and analyze run by the lead) — not re-run
Diff vs Predicted Files: conforms; outside: `lib/core/services/stats_progress_service.dart` (another session's DST work, ignored per brief)

## Answers to the brief's questions

**Q1 — unlisted production behaviour?** No. Every production hunk is the plan's "Exact production code" verbatim: the `kSignalMaxWaitingLines` const, the two pure rules, the abstract `waitingFor` after `needsRatedWeeks`, the five `=> null` overrides, the two real `waitingFor`s, `SignalsService.waitingLines` (registry order, nulls dropped, throw skipped, `.take(3)`), the layer helper and both sections' `waiting` parameter, and the screen's `_signalsWaiting` computed under the same `evaluateSignals` gate and passed to both sections. Both real `waitingFor` windows are byte-identical to their `evaluate` windows (`protein_consistency_signal.dart`: `now.day - (kProteinConsistencyWindowDays - 1)`; `cardio_efficiency_drift_signal.dart`: `now.day - kCardioEfficiencyReferenceWeeksFrom * 7`), so the waiting count reads the same span the rule reads (D-17603/D-17604 hold).

**Q2 — screen walk.** `_load` computes `_signalsWaiting` only when `evaluateSignals` (`totals.completedSessions > 0`), the same condition as the cards; with no completed session it stays `const []` and the build takes the `_totalSessions == 0` empty-state branch, so no line is drawn (S-17606 asserts `waitingCalls == 0` and no `signals_waiting_0`). Gate unmet, no card → `SignalsLockedSection`: locked line, then the waiting lines. Gate unmet with a card → `SignalsLayerSection`: card, hint, then the waiting lines. Gate met, quiet → quiet line, then the waiting lines. Gate met with a card → cards, then the waiting lines (no hint, `lockedRatedWeeks` null). No state shows a line that should not show: a line can never sit next to its own signal's card, because the thresholds are disjoint — Protein Consistency's line needs 1–9 logged days and its card needs ≥10; Cardio Efficiency's line needs 1–5 eligible efforts and its card needs ≥6 (3 of one kind in each of two windows). No state hides a line that should show: `waitingLines` does not read the gate, so the lines appear at an unmet gate too (test (a) proves it with `needsRatedWeeks: true` stubs that `evaluateCandidates` skips). The block lives in a scrollable `ListView`, so three `bodySmall` lines cannot push it off screen; a dismissal re-resolves candidates without touching `_signalsWaiting` (D-17605, intended); the quiet, locked and hint keys and copy are untouched by the diff.

**Q3 — assertions true for the wrong reason?** None found. S-17601/S-17602 call the pure rules directly on the plan's boundary values (0, 1, 9, 10, 14; 0, 1, 5, 6, 9) and assert exact strings, so M1/M2 die on the upper bound. S-17603's order test asserts list contents (`['line a','line b']`), which fails if order flips; the thrower sits between two line-producing stubs, so removing the `catch` fails it; the cap test uses five stubs and asserts the first three, so removing `.take` fails it. S-17604 seeds real `ConsumedFood` rows on both harnesses: two foods on one day expect "6 more" (proves the per-day definition, not a per-row count), a food 14 days ago expects "7 more" with 3 in-window days (proves the far edge is excluded), and a food 13 days ago expects "6 more" (proves the first day is included) — an off-by-one window start fails either edge test. S-17605's position checks compare `getTopLeft` dy of uniquely keyed `Text`s in the render order the block actually has; a waiting line rendered above the locked line, hint or quiet line would have a smaller dy and fail. The `findsOneWidget`s target keys unique to one section (`signals_locked` vs `signals_layer`), and test (c) adds `signals_locked` `findsNothing` so the locked section cannot masquerade. S-17606 counts `waitingCalls` on a `needsRatedWeeks: false` stub, so forcing `evaluateSignals` true for the lines (M8) fails it.

**Q4 — docs sentences.** All true and tied to existing tests. Checked by reading the code: `SignalsService.waitingLines`, `kSignalMaxWaitingLines` (3), `proteinConsistencyWaitingLine` and `cardioEfficiencyWaitingLine` in the named files, the `signals_waiting_N` keys, the "same condition" claim (`evaluateSignals = totals.completedSessions > 0`), and "two signals answer today". Cited names exist verbatim: groups `S-17601 proteinConsistencyWaitingLine`, `S-17602 cardioEfficiencyWaitingLine`, `S-17603 SignalsService.waitingLines`, `S-17604 the Protein Consistency count — Mock` and `— Hive` (harness `name` getters are exactly `'Mock'`/`'Hive'`), `S-17605 the waiting lines sit under whatever the block shows` › `the quiet line keeps its copy and the line follows it`, and `the empty-state branch` › `a profile with no sessions shows the empty state and no layer, even with stubs registered`. One inaccuracy below (finding 1).

**Q5 — unlisted user-visible changes?** None. The only new visible text is the two waiting lines' copy, both in the plan; the only layout change is the 8 dp spacing, `bodySmall`/`textSecondary` styling and the lines' position under everything else, all in the plan. The quiet line (`kSignalQuietLine`), the locked line (`signalsLockedLine`) and the hint (`signalsMoreLine`) are untouched by the diff — no hunk edits their constants or their `Text`s.

## Findings

1. [Minor] docs/signals.md:214 — the contract sentence the keeper rewrote ("an id, a kind, a priority, `evaluate` and `waitingFor`") still omits `needsRatedWeeks`, which `Signal` declares (`lib/core/services/signals/signal.dart:26`). A maintainer reading the contract list would miss the rated-weeks flag. Pre-existing omission, but this diff rewrote the sentence and perpetuated it. Fix: add `needsRatedWeeks` to the list. Guard: none (doc sentence; `unguarded`).
2. [Minor] docs/stats_screen.md:762,764 — the "where things live" table rows for `signals_layer.dart` and `signals_service.dart` were edited (waiting lines added to both summaries), but the plan's Docs delta table does not name these edits. Both sentences are true against the code; this is plan bookkeeping only. Fix: none in docs; the governor may note the extra rows in the plan's Docs delta.

## Assumption Log rulings

- Scouts (heart rate single producer; distance typed/`gps`, only `estimated` excluded; the two logged-day counts deliberately not shared): ratified — the code reads `cardioEfforts`/`nutritionSeries` exactly as the plan says, and the doc sentences repeat the scout facts without contradicting anything I read.
- Rating gate still honest with Effort Rating off: ratified — the locked line and hint are untouched and D-17605 adds no gate read to `waitingLines`.
- Default taken (no lines for the four load-reading signals; no Fuel six-week line; at most three lines): ratified — the five `=> null` overrides and `.take(kSignalMaxWaitingLines)` are exactly that.

## Docs delta

- docs/signals.md MODIFIED (priority and `evaluate`… → what it is waiting for) -> applied
- docs/signals.md ADDED (Each signal can say what it is waiting for) -> applied
- docs/signals.md ADDED (proteinConsistencyWaitingLine) -> applied
- docs/signals.md ADDED (cardioEfficiencyWaitingLine) -> applied
- docs/stats_screen.md MODIFIED (its header and `kSignalQuietLine` and nothing else… → one line for each signal that is still waiting for data) -> applied
- docs/stats_screen.md ADDED (Protein Consistency: log food on) -> applied
- docs/stats_screen.md ADDED (Cardio Efficiency: needs heart rate from the watch) -> applied
- docs/widget_catalog.md MODIFIED (a dismiss callback and an optional `lockedRatedWeeks` → a dismiss callback, the waiting lines and an optional `lockedRatedWeeks`) -> applied
- Not named by the table: docs/stats_screen.md "where things live" rows for `signals_layer.dart` and `signals_service.dart` (finding 2).

## Scenario coverage

- S-17601 -> test/signals_waiting_test.dart · group `S-17601 proteinConsistencyWaitingLine` (5 tests)
- S-17602 -> test/signals_waiting_test.dart · group `S-17602 cardioEfficiencyWaitingLine` (4 tests)
- S-17603 -> test/signals_waiting_test.dart · group `S-17603 SignalsService.waitingLines` (3 tests)
- S-17604 -> test/signals_waiting_test.dart · groups `S-17604 the Protein Consistency count — Mock` and `S-17604 the Protein Consistency count — Hive` (5 tests each)
- S-17605 -> test/signals_layer_screen_test.dart · group `S-17605 the waiting lines sit under whatever the block shows` (3 testWidgets)
- S-17606 -> test/signals_layer_screen_test.dart · group `the empty-state branch` › `a profile with no sessions shows the empty state and no layer, even with stubs registered` (extended with `waitingCalls == 0` and no `signals_waiting_0`)
- S-17607 -> existing S-1702/S-17505/S-1703 tests untouched by the diff (stub change is additive, `waiting` defaults null); copy constants untouched; green per the brief's established facts
