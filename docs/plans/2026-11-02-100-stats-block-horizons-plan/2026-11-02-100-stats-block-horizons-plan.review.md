# Review: 100-stats-block-horizons · P1-P4 · 07829d0d..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 0 · minor 1 · tests: governor run pasted in brief: +6151 ~2 -5 (all 5 failures RED at base; not re-run)
Diff vs Predicted Files: conforms — production is the five widget files + the `stats_progress.dart` comment + the planned deletion of `window_chip.dart`; tests and docs as phased. Outside: `lib/core/services/stats_progress_service.dart` and `test/stats_dst_day_arithmetic_test.dart` (the other session's, per brief) and the plan/evidence artifacts themselves.

## Questions

1. **Unlisted production behaviour?** No. `stats_screen.dart`, `instrument_list.dart`, `mix_layer.dart`, `instrument_row.dart`, `fuel_section.dart` and the `window_chip.dart` deletion match the plan's exact code item for item (D-17301..D-17307); `stats_progress.dart` is the planned comment change. The only extra edits are doc comments whose subject the change removed (`fuel_section.dart` class doc, `instrument_list.dart` `_caption` doc — item 5 names the latter).
2. **Weakened assertions?** No. Deleted tests: `mix_layer_screen_test.dart` groups `S-1607 the unrated count in words, or absent` › `one unrated session reads in the singular`, `S-1607 three unrated sessions` › `read in the plural`, and the three `S-3205` groups (`the unrated line says which measure leaves sessions out`, `the twin: three unrated sessions under the time measure`, `the load measure says the session is not counted`). Every deleted claim describes the unrated note's presence or wording — the note is removed by D-17305/O-8, so the claims are obsolete by design; `S-17309` (both measures, note absent, baseline note still shown under the time measure) covers the removal. The kept `S-1607 no unrated session` and `S-3205 the twin: every session rated` tests retain the absence claims. The local seeders `_seedSessionOnDay` (`fuel_row_screen_test.dart`) and `_seedSetSessionOnDay` (`instrument_list_screen_test.dart`) change only the fixture start to local noon via calendar arithmetic (DST drift); the sessions, efforts and assertions they feed are unchanged. Other adaptations (`S-1601`, `S-1612`, `S-1112`, `S-1011`, `S-4010`, `S-004`, the six signal-screen ordering tests, `S-4004`) swap the removed ALL TIME/chip markers for equivalent or stronger claims.
3. **Moved Stats ALL-TIME tests?** Yes, same figures. `screen_widget_test.dart` group `Records & Trends`: `aggregate totals reflect seeded completed sessions` asserts `SESSIONS`/`3`/`2h 15m`; `rolling sessions are excluded from duration aggregates` asserts `2`/`45m` and `2h 45m` absent; the `S-005` guard keeps all its assertions. Each gained `seedOneSetEffort` because the Records & Trends aggregate card renders only with an exercise summary, and the first also asserts Stats no longer shows `ALL TIME`. The card finder changed from `Key('all_time_card')` to `find.byType(OmniSurface).first` (the card has no key — see Minor 2).
4. **docs/stats_screen.md sentences?** All true against the code and cited tests exist (each cited group and test name verified in the test files this run), except one: the file-table row for `stats_pill.dart` says "used only by Records & Trends" — false, see Blocker 1. The `_span` sentence, the `new`/dash sentences, the Fuel `Last 7 days` sentence, the "whether any session exists (`computeTotals()`)" sentence, the `date_utils.dart` row (`formatShort` at `mix_layer.dart:135,286,303`) and the `training_load.dart` row (`unratedSessionCount` read by no widget — grep confirms) are all true.
5. **Unlisted user-visible change?** None. Every copy/layout change on screen is a planned one (explainer, strip title, caption, `new`, fuel horizon, unrated note removed, ALL TIME card removed, chips removed).

## Findings

1. [Blocker] docs/stats_screen.md (file table, row `lib/features/stats/widgets/stats_pill.dart`) — "The ALL TIME stat pill, used only by Records & Trends" is false: `lib/features/stats/exercise_progress_screen.dart:20` imports the file and renders `StatsPill` at `:176`, `:186`, `:196`, so a maintainer trusting the row would conclude the widget has one host. Fix: reword to "used by Records & Trends and Exercise Progress" (the Docs delta row's intent — the Stats screen dropped it — is already carried by the `CalendarState`/`computeTotals()` rows). Guard: none possible in the indexing contract; the sentence should name both hosts.
2. [Minor] test/screen_widget_test.dart (group `Records & Trends`, all three tests) — the aggregate card is located positionally (`find.byType(OmniSurface).first`) because `RecordsAndTrendsScreen._buildAggregateCard` (~`:247`) sets no key; a surface added above it would make the tests assert the wrong card (they would fail loudly, not silently). Fix (follow-up, outside this unit's predicted files): give the card `key: const Key('all_time_card')` and restore the keyed finder.

## Assumption Log rulings

- Baseline `flutter analyze` 181 issues — ratify (governor fact).
- `MixLayerData.unratedSessionCount` stays, no widget reads it — ratify (grep: only the service and the model mention it).
- Load measure still omits unrated sessions without a line saying so — ratify (O-8, owner decision).

## Scenario coverage

- S-17301 -> test/stats_mix_horizon_screen_test.dart · `S-17301 the time-measure explainer opens with the window` › `the explainer names the window and the chip is gone`
- S-17302 -> test/stats_mix_horizon_screen_test.dart · `S-17302 the load-measure explainer opens with the window` › `the explainer names the window and the measure`
- S-17303 -> test/stats_mix_horizon_screen_test.dart · `S-17303 the strip is titled by its horizon` › `the strip title leads with the horizon`
- S-17304 -> test/stats_instruments_horizon_screen_test.dart · `S-17304 the caption is one plain line` › `the caption names the window and its previous span, and no chip names it`
- S-17305 -> test/stats_instruments_horizon_screen_test.dart · `S-17305 a row with nothing to compare against reads new` › `the three rows read new, the dash, and an arrow figure`
- S-17306 -> test/stats_instruments_horizon_screen_test.dart · `S-17306 the caption counts the window's own span` › three window-span tests
- S-17307 -> test/stats_instruments_horizon_screen_test.dart · `S-17307 ALL TIME is on Records & Trends only` › both tests (order + twin)
- S-17308 -> test/stats_instruments_horizon_screen_test.dart · `S-17308 twin: no session at all` › `the empty state stands alone, with no all-time block`
- S-17309 -> test/stats_mix_horizon_screen_test.dart · `S-17309 the unrated line is gone` › time-measure and load-measure tests
- S-17310 -> test/stats_fuel_horizon_screen_test.dart · `S-17310 averages shown` and `S-17310 too few logged days` › `S-17310 the Fuel card opens with its horizon`
- S-17311 -> test/stats_fuel_horizon_screen_test.dart · `S-17311` › `S-17311 the horizon is built from the window constant`
- S-17312 -> test/stats_mix_horizon_screen_test.dart · `S-17312 the empty-window card has no chip` › `the empty line stands alone under the header`
- S-17313 -> test/stats_instruments_horizon_screen_test.dart · `S-17313 the chip is gone from the source`
- S-17314 -> test/records_and_trends_screen_test.dart (whole file green in the governor's run) + test/stats_instruments_horizon_screen_test.dart · `S-17307 twin: Records & Trends keeps ALL TIME`

## Docs delta

docs/stats_screen.md: rows 1-40 -> applied, except row 38 (`stats_pill` "used only by Records & Trends") -> applied, sentence false (Blocker 1).
docs/widget_catalog.md: 3 rows -> applied. docs/design_system.md: 2 rows -> applied (one line). docs/navigation_and_screens.md: 2 rows -> applied. docs/signals.md: 1 row -> applied.

Doc edits the table does not name (all verified true or benign):
- docs/stats_screen.md Overview: dropped "the all-time totals," from the opening sentence.
- docs/stats_screen.md file table: `date_utils.dart` row rewritten to `formatShort()`; `mix_layer.dart` row dropped "the unrated line"; `training_load.dart` row rewritten; version 3.2 -> 3.3.
- docs/stats_screen.md Related Documentation: Calendar & Periods line rewritten (no test claim).
- docs/signals.md: the `S-1909` citation replaced — the old test `the period does not follow the window chip` no longer exists; the new citation (group `S-1909 the card renders for the mixed history` › `a window narrower than the period still shows the card`) exists and is about the period not following the window.
- docs/navigation_and_screens.md, docs/widget_catalog.md, docs/design_system.md: added citations to the new test files (all cited names exist).