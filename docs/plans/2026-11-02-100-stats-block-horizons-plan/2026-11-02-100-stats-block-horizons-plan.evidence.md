# Evidence — 2026-11-02-100-stats-block-horizons (P4a, docs/stats_screen.md)

## Baseline

From the plan's Assumption Log (not run this run): `flutter analyze` 181 issues, 0 errors at HEAD 07829d0d.

## Docs delta result

One line per `## Docs delta` row whose Doc is `docs/stats_screen.md` (41 rows, in table order):

1. docs/stats_screen.md MODIFIED "no Signals layer, no ALL TIME card, no Instruments list" -> done
2. docs/stats_screen.md MODIFIED "it is five blocks in a fixed order" -> done
3. docs/stats_screen.md MODIFIED "no block beyond those five" -> done
4. docs/stats_screen.md MODIFIED "[ALL TIME card](#all-time-card)" -> done
5. docs/stats_screen.md MODIFIED "The Mix layer is the first block in the body, above the ALL TIME card, and there" -> done
6. docs/stats_screen.md MODIFIED "One sentence under the card's title says what the bars are:" -> done
7. docs/stats_screen.md ADDED "Last 4 weeks. Your training split by time spent." -> done (verbatim, one line)
8. docs/stats_screen.md ADDED "Last 4 weeks. Your training split by how hard each session felt." -> done (verbatim, one line)
9. docs/stats_screen.md MODIFIED "**The note and the unrated line.**" -> done
10. docs/stats_screen.md REMOVED "An unrated line says what the missing ratings do to the figures" -> done
11. docs/stats_screen.md REMOVED "S-3205 the unrated line says which measure" -> done
12. docs/stats_screen.md REMOVED "the unrated line" -> done
13. docs/stats_screen.md MODIFIED "Week by week · last 8 weeks" -> done
14. docs/stats_screen.md MODIFIED "carries its own `StatsWindowChip` naming it" -> done
15. docs/stats_screen.md REMOVED "the second of the screen's two chips" -> done
16. docs/stats_screen.md MODIFIED "window and the chip never" -> done (both occurrences: The window, Resolution Rule 2)
17. docs/stats_screen.md MODIFIED "it draws the header, the chip and one line" -> done
18. docs/stats_screen.md MODIFIED "and above the ALL TIME card, and there is exactly one of it" -> done
19. docs/stats_screen.md REMOVED "### ALL TIME card" -> done (whole section deleted)
20. docs/stats_screen.md REMOVED "One surface holding three pills:" -> done
21. docs/stats_screen.md REMOVED "Current consecutive-day streak via" -> done
22. docs/stats_screen.md REMOVED "asserts the `STREAK` pill inside the `ALL TIME` card" -> done
23. docs/stats_screen.md MODIFIED "first of them carries the window chip, so the scope of the readout is never" -> done
24. docs/stats_screen.md MODIFIED "the change is against the 28 days before it" -> done
25. docs/stats_screen.md ADDED "Last 4 weeks. Change is against the 4 weeks before." -> done (verbatim, one line)
26. docs/stats_screen.md MODIFIED "it reads the no-change dash rather than a" -> done
27. docs/stats_screen.md ADDED "a change of exactly zero reads the dash" -> done
28. docs/stats_screen.md MODIFIED "reads the same no-change dash the Instruments rows use" -> done
29. docs/stats_screen.md MODIFIED "so it carries no `StatsWindowChip`." -> done
30. docs/stats_screen.md MODIFIED "the ALL TIME card and the [Fuel row](#fuel-row) sit" -> done
31. docs/stats_screen.md REMOVED "ALL TIME card (Sessions / Time / Streak)" -> done (table row deleted)
32. docs/stats_screen.md MODIFIED "### On-screen Window Label" -> done (now "### Naming the Window", rewritten)
33. docs/stats_screen.md REMOVED "inline chip reading" -> done
34. docs/stats_screen.md REMOVED "Those two are the chip's only hosts" -> done
35. docs/stats_screen.md MODIFIED "S-1612 exactly two window chips" -> done (both occurrences)
36. docs/stats_screen.md REMOVED "StatsWindowChip" -> done
37. docs/stats_screen.md REMOVED "window_chip.dart" -> done (Core Files row deleted)
38. docs/stats_screen.md MODIFIED "The ALL TIME stat pill, shared with Records & Trends" -> done
39. docs/stats_screen.md MODIFIED "builds one `CalendarState` and one" -> done
40. docs/stats_screen.md MODIFIED "asks the service for the all-time totals (`computeTotals()`), the" -> done
41. docs/stats_screen.md REMOVED "(created internally by `StatsScreen`)" -> done (calendar_state.dart Core Files row deleted)

Extra in-scope fixes (not delta rows, same doc, allowed by the brief):
- Windowed table, "Each row's figure and change readout" row: "the change compares it with the 28 days before it" -> "the change compares it with the previous window of the same length" (stale against the new span rule; backed by S-17306, S-4011).
- Core Files, `lib/core/models/training_load.dart` row: "the unrated line" -> "the unrated session count (`unratedSessionCount`, which no widget reads)" (field verified at `lib/core/models/training_load.dart:107`; brief item 2).
- Related Documentation, Calendar & Periods line: "streak calculation details" -> "the calendar-day arithmetic the window and the Fuel row use" (the streak pill no longer exists on this screen).
- Document Version 3.2 -> 3.3.

## Tests cited

Every behaviour sentence added or kept cites a group · test name read from the test file this run:

- `test/stats_mix_horizon_screen_test.dart`: `S-17301 the time-measure explainer opens with the window` › `the explainer names the window and the chip is gone`; `S-17302 the load-measure explainer opens with the window` › `the explainer names the window and the measure`; `S-17303 the strip is titled by its horizon` › `the strip title leads with the horizon`; `S-17312 the empty-window card has no chip` › `the empty line stands alone under the header`.
- `test/stats_instruments_horizon_screen_test.dart`: `S-17304 the caption is one plain line` › `the caption names the window and its previous span, and no chip names it`; `S-17305 a row with nothing to compare against reads new` › `the three rows read new, the dash, and an arrow figure`; `S-17306 the caption counts the window's own span` › `a ten-day window reads the ten days before it` / `a seven-day window reads the one week before it` / `a one-day window reads the one day before it`; `S-17307 ALL TIME is on Records & Trends only` › `Stats shows no all-time block, and its blocks keep their order`.
- `test/stats_fuel_horizon_screen_test.dart`: `S-17310 averages shown` › `S-17310 the Fuel card opens with its horizon`; `S-17310 too few logged days` › `S-17310 the Fuel card opens with its horizon`; `S-17311` › `S-17311 the horizon is built from the window constant`.
- `test/mix_layer_screen_test.dart`: `S-1612 the window is named in words, not by a chip` › `the explainer and the Instruments caption each start with the window, and no chip renders anywhere`; `S-1613 the layer reads the same window as the list`; `S-3201 one sentence says what the split is`; `S-3201 the twin: the time measure reads in its own words`; `S-3204 the baseline note says what happens and when`; `S-3204 the twin: no rated week at all`; `S-3204 the load measure explains nothing`.
- `test/stats_four_week_window_screen_test.dart`: `S-17004 a period no longer scopes Stats` › `the bar reads the 28-day window and the explainer never names the period`; `S-17005 the Instruments compare with the 28 days before` › `the caption names the window length, not the period`; `S-17007 after a break the card is one line` › `the empty window draws one line and no bar, strip or list`.
- `test/instrument_list_screen_test.dart`: `S-1011` › `the Instruments list is the four-week window, named in words, whatever periods exist`; `S-1001` › `the change chip compares against the previous range, and reads new when there is nothing to compare`; `S-4010 the caption states the window's real span` › `the caption names the 4 weeks the window holds and the 4 weeks before it`; `S-4017 the caption counts the comparison` › `the number is the previous range's span, and the caption names the four weeks`; `S-4018 one caption, under the first header`.
- `test/fuel_row_screen_test.dart`: `S-1112` › `the Fuel card has no window chip and its first line reads Last 7 days, with the window named in words`.
- `test/stats_window_day_count_test.dart`: `S-4011 StatsWindow.dayCount is the previous range's own length`.

## Stale-claim search (docs/ outside this doc)

Searched `docs/` for `ALL TIME`, `chip`, `StatsWindowChip`, `unrated line`, `Week by week`, `no-change dash` (excluding `docs/plans`, `docs/history`, `docs/releases` per the plan's note). Hits outside `docs/stats_screen.md`:

- `docs/09-24-stats-redesign-modality-lens-prompt-pack.md:463`, `:643`, `:1232` — "window chip" (historical prompt pack, not in the delta table; not edited).
- `docs/design_system.md:185`, `:186` — `ALL TIME` for Records & Trends / Exercise Progress, which keep the card; not stale.
- `docs/navigation_and_screens.md:199` — cites the new group `S-17307 ALL TIME is on Records & Trends only`; already updated by P4b; not stale.
- `docs/widget_catalog.md` — no hits for any old term.
- `docs/plans/**` hits are historical plan/evidence records, excluded by the plan's own note.

## Size

`docs/stats_screen.md`: 761 lines after the edit (git-diff --stat via gateway: 103 insertions, 97 deletions). Byte size not directly measurable with the allowed tools (view truncates at 20 KB; gateway has no size check); the pre-edit file was ~41.9 KB and the net change is +6 lines, so the file is well under the 52 KB limit. The lead's `test/docs_indexing_contract_test.dart` run is the authoritative check.

## Governor verification (2026-11-03)

- `flutter analyze`: 181 issues, 0 errors (baseline 181).
- Full `flutter test`: `+6151 ~2 -5`. The 5 failures (`test/instrument_list_service_test.dart` S-1005 and S-1010 on Mock and Hive;
  `test/routine_save_removes_deleted_rows_test.dart` S-R3) are RED at 07829d0d too (`gateway.sh prove-red`). The new and adapted files are green.
- Invariant grep (`hive_workout_repository` imports): clean. `ui_standards_contract_test.dart` and `docs_indexing_contract_test.dart`: green.
- Prover (`07829d0d`): all 15 new guard bodies RED for the stated reason; the two twins (S-17307 Records & Trends keeps ALL TIME, S-17308 empty state) are green at the base by design.
- Mutations (lead, in place with restore + cmp): M1 weeks `~/ 7`→`~/ 4`, M2 caption drops the label, M3 multiple-of-7 test removed, M4 row label back to the dash,
  M5/M6 explainer drops the label (load / time), M7 strip title reverted, M8 fuel horizon text changed, M10 explainer on the empty card: all KILLED.
  M9 hard-coded `Last 7 days` instead of the constant: SURVIVED, equivalent (the constant is 7).
- `plan-lint.py after`: clean, 50 of 50 Docs delta rows applied.
- Review: APPROVE WITH FIXES, one Blocker fixed (the `stats_pill.dart` row), one Minor left as follow-up.
