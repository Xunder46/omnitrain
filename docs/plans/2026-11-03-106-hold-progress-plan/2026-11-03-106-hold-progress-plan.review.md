# Review: 2026-11-03-106-hold-progress-plan · P1, P2a, P2b, P3 · base..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · tests: per brief — touched files green (+48: `hold_progress_test`, `hold_progress_signal_test` on both harnesses, `signals_service_test`, `modality_mix_shift_signal_screen_test`); full suite, analyze, contract tests and `plan-lint after` run by the lead, green. Not re-run here.
Diff vs Predicted Files: conforms; outside: `docs/README.md` (one line, the Registered Signals index row `nine`→`ten` plus the list gaining `Hold Progress`). The plan's P3 mandate has the keeper search `docs/` for stale `nine` hits; this is that hit, fixed rather than only reported. The sentence is true against the code. `lib/core/services/stats_progress_service.dart` in the stat is the other session's DST work, ignored per brief.

## Findings

None.

## Answers to the brief's questions

1. **Unlisted production behaviour: none.** `hold_progress.dart` (89 lines), `hold_progress_signal.dart` (45 lines) and the two `signal_registry.dart` edits match the plan's "Exact production code" line for line: constants 3/10/10/40, the isometric + both-hold-metrics + session + previous>0 + gain + percent filters, `_beats` (gain desc, name asc, id asc), the copy sentence, and the adapter (id `hold-progress`, positive, priority 40, `needsRatedWeeks` false, `waitingFor` null, title `Hold progress`, no suggestion, weeks `kStatsWindowDays ~/ 7`, registered after `ConsistencySignal()`). No other lib file is touched by this change.

2. **What a real isometric row carries** (`stats_progress_service.dart`, current state):
   - `previousValue` on `hold` while `best` is not (or the reverse) cannot happen: `computeInstrumentSections` sets `previousValue: comparable ? previousSummary.best : null` and `comparable` requires `previousSummary.best.metric == summary.best.metric`; for an isometric exercise both bests come from `_isometricValue`/`_zeroValueFor`, which always emit metric `hold`. The rule's double metric check is redundant for real rows but is what the synthetic-row tests pin (S-17905).
   - `sessionCount` is the window's count, not all time: `computeExerciseMetrics(fromMs, toMs)` only admits completed sessions (`endedAtMs != null`) whose `startedAtMs` is inside the range, and `sessionCount` is the distinct session ids of those logs.
   - The longest hold is the value the row shows: `_isometricValue` returns metric `hold` with `value = longestHoldSecs` (total hold time only as `secondaryValue`), and the card reads `row.summary.best.value.round()` — the same figure the row renders.
   - Added weight / rolling session: a hold with added weight only sets `addedWeightKg` on the same `NativeValue` the row shows; the card's numbers are the row's numbers, and the card (like the plan) says nothing about weight — no mismatch. A session spanning the window boundary is attributed wholly to the window of its start (`startedAtMs` filter), by the same computation the row uses — the card cannot count a hold the row does not.

3. **Cards together:** yes, that is what the existing selection does. `resolveSignals` (`lib/core/models/signals.dart`) ranks survivors of a kind by priority descending (tie by id ascending) and, when only one kind survives, takes the top `kSignalMaxCards`; with positives at 100/50/40 the top two are Progression Rate and Consistency, so Hold Progress renders only when one of them is dismissed or absent. By reading: the one signals-block screen test that seeds isometric holds (`modality_mix_shift_signal_screen_test.dart`, F-MIX) cannot produce the card — each hold session is a distinct exercise id (`ex-hold-$sessionId`, so per-exercise `sessionCount` is 1, below the floor of 3) and its baseline holds sit 80–108 days back, outside the previous 28-day range, so `previousValue` is null. F-TIME seeds only cardio `timed` efforts; `stats_four_week_window_screen_test.dart`'s hold seed is likewise a cardio `timed` effort; no other signals-block test seeds `drill` efforts (grep). Other hold-seeding files assert the Instruments/Mix surfaces, not the Signals block (not read in full).

4. **Assertions for the wrong reason: none found.** S-17902's three fixtures isolate the floors (49/40 fails only the gain floor; 110/100 passes both inclusive bounds; 111/101 fails only the percent floor); S-17903's 2-session fixture passes every other filter; S-17904's four fixtures each trip exactly one guard; S-17905's extra tests isolate M4 (best on `duration`, previous on `hold`) and M8 (hold metrics in the cardio section) as the brief says the lead added. S-17906's tie (Plank 25, Dead Hang 25) resolves by name ascending to `Dead Hang`; M5 would pick Wall Sit (15). S-17908's copy pins the weeks (M6 would print "2 weeks"). Adapter day offsets: the window is the 28 calendar days ending today, the previous range is `[midnight(today−55), midnight(today−28)−1ms]`; seeds at 31 and 34×24 h back land on calendar days 30–32 back even across a midnight crossing or a DST hour, ≥2 days inside the range's edges, and window seeds at 1/3/5 days back stay inside the 27-day span — both sides derive from the same `DateTime.now()`, so they move together. No flip.
   **Docs:** every sentence checked against the code; every cited name exists verbatim — `hold_progress_test.dart` groups `S-17901 a hold that improved`, `S-17902 the gain thresholds are inclusive`, `S-17903 at least three sessions`, `S-17904 an earlier window is needed`, `S-17905 only isometric holds count`, `S-17906 the biggest gain wins`, `S-17907 the copy`, test `the constants the rule is built from are the ones the plan names`; `signals_service_test.dart` group `S-17503 which registered signals need rated weeks`; `modality_mix_shift_signal_screen_test.dart` group `the registry` › `lists exactly the ten shipped signals, in order`; harness names `Mock`/`Hive` (so the two S-17908 group names in `signals_registered.md` are exact). The merged `stats_screen.md` paragraph loses only the two inline one-line rule summaries of Consistency and Training Gap; both rules remain fully described in the linked `signals_registered.md` and both verified-by citations are preserved — the replacement text is the plan's own, so nothing unintended is lost.

5. **Unlisted user-visible changes: none.** The lib diff adds only the new card (title `Hold progress`, the plan's observation copy, `suggestion` null — asserted in the adapter test). No widget, label or layout file is touched; no existing card's copy changed.

## Assumption Log rulings

- "Instruments computes the longest single hold, not an average" — ratified (`_isometricValue`: `longestHoldSecs`, total as secondary).
- "Each row already shows its own change against the four weeks before" — ratified (`previousValue` from `previousRangeFor`).
- "Progression Rate walks `set` efforts only" — ratified (`progressionSamples` skips non-`set` efforts).
- Defaults taken (no cardio card; thresholds 10 s / 10 % / 3 sessions; one card max) — ratified; owner pre-approved defaults per the plan header.
- "Not run on a device or simulator" — noted; the change adds no widget and the track is phone-only; acceptable.

## Docs delta

- docs/signals.md positives sentence (`Rate, whose priority is …`) -> applied
- docs/signals.md `The nine registered signals —` -> applied (`ten`, list gains Hold Progress)
- docs/signals.md `which pins the nine registered ids` -> applied (`ten`)
- docs/signals_registered.md scope `The nine registered signals' definitions and adapters` -> applied (`ten`)
- docs/signals_registered.md ADDED `holdProgress(List<InstrumentSectionData>` -> applied
- docs/stats_screen.md `lists nine, described here in the order they shipped` -> applied (`ten`)
- docs/stats_screen.md `The eighth is the Consistency …` -> applied (replaced by `The eighth to tenth are the Consistency`)
- docs/stats_screen.md REMOVED `The ninth is the Training Gap …` -> applied (paragraph gone)
- Doc edit the table does not name: docs/README.md — Registered Signals index row `nine`→`ten`, list gains Hold Progress (see Diff vs Predicted Files).

## Scenario coverage

- S-17901 -> test/hold_progress_test.dart · `S-17901 a hold that improved` › `60 s against 40 s over three sessions` (+ `no sections at all is no result`)
- S-17902 -> test/hold_progress_test.dart · `S-17902 the gain thresholds are inclusive` (3 tests)
- S-17903 -> test/hold_progress_test.dart · `S-17903 at least three sessions` (2 tests)
- S-17904 -> test/hold_progress_test.dart · `S-17904 an earlier window is needed` (4 tests)
- S-17905 -> test/hold_progress_test.dart · `S-17905 only isometric holds count` (4 tests; the last two isolate M4 and M8)
- S-17906 -> test/hold_progress_test.dart · `S-17906 the biggest gain wins` (2 tests)
- S-17907 -> test/hold_progress_test.dart · `S-17907 the copy`
- S-17908 -> test/hold_progress_signal_test.dart · `S-17908 the Hold Progress signal on real sessions — Mock` and `— Hive` (4 tests each)
- S-17909 -> test/signals_service_test.dart · `S-17503 which registered signals need rated weeks`; test/modality_mix_shift_signal_screen_test.dart · `the registry` › `lists exactly the ten shipped signals, in order`
