# Plan 219 — Records & Trends is a labelled row at the end of Stats (the header icon goes)

Series: Stats pre-launch review item 9, findability (index `docs/plans/2026-11-13-157-stats-what-counts-series.md`). Owner answers 2026-11-16: add a visible way in, after the last section; "either the icon in the header or a row at the end, not both": the row stays, the icon goes (owner: "yes agreed"); leave where Stats lives alone; no dropped-sets warning in the Finish dialog. Phone only (`lib/features/stats`), P1 built the row; P2 removes the icon and moves every reader; then docs. Status: BUILT (owner decided row-only), reviewed (APPROVE WITH FIXES, fixed), verified, COMMITTED.

## Goal and acceptance

Records & Trends (personal records and every exercise's full history) was reachable only through an unlabeled chart icon in the Stats header. After this change the Stats list ends with a labelled row that opens it, and the header icon is gone.

Acceptance: S-21901..S-21906 green, the ones marked "fails without" red at the base commit; the readers of the icon (below) moved to the row and green; `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart` green; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- At the very end of the Stats list (after the Weight row when there is one, else after Fuel, else after the Instruments list, and after the "No sessions yet" card when there is no history): a card row `Records & Trends`, a muted line `Your personal records and the full history of each exercise.` and a chevron. Tapping it opens Records & Trends.
- The header no longer has the chart icon. The "?" help stays (when the screen offers it), alone.
- The first-run explainer's third block no longer talks about an icon: it reads `RECORDS & TRENDS` / `Opens from the row at the end of this page: your personal records and the full history of each exercise. Tap an exercise there to see its progress.`
- No row while the screen is loading or shows the load-failure message.
- To SEE it: any history; scroll to the bottom of Stats.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | New `RecordsLinkRow` (`lib/features/stats/widgets/records_link_row.dart`, built in P1): `OmniSurface` > `Semantics(label: 'Records & Trends', button)` > `InkWell(key: stats_records_link)` > Row (title `stats_records_link_title`, hint `stats_records_link_hint`, chevron). Same shape as the Fuel row's tappable surface. | `fuel_section.dart:98-110` |
| D-2 | `StatsScreen` owns `_openRecords` and passes it to the row. The row is the last child of the list in BOTH the populated and the empty-state branch (the empty history still reaches Records & Trends' own empty state, as the icon did), with one 24 gap above it and never a double gap. Not in the loading or failure branches. | `stats_screen.dart` list `children` |
| D-3 | The header icon (`Icons.show_chart`, tooltip and semantics `Records & Trends`) is removed from `StatsScreen`'s `OmniBackHeader.actions`; the "?" (`stats_primer_help`, shown when `showPrimerHelp`) stays. | `stats_screen.dart:355-387` |
| D-4 | The primer sheet's third block (key `stats_primer_block_records`, unchanged) gets the label `RECORDS & TRENDS` and the body above; its comments stop naming the icon. The `StatsPrimerState` header comment likewise. | `stats_primer_sheet.dart:113-122` |
| D-5 | Readers that reached Records & Trends by the icon's tooltip tap the row instead: `find.byKey(const Key('stats_records_link'))` after `ensureVisible`. | Readers |
| D-6 | Words and shapes are the lead's defaults (owner: proceed, explain defaults). | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21901 | `RecordsLinkRow` pumped directly. | title `Records & Trends`, the hint text, one chevron; a tap on `stats_records_link` calls `onTap` once. | the widget does not exist |
| S-21902 | `StatsScreen` over Mock with one completed session. | `stats_records_link` found once, below the Instruments list; tapping it shows `RecordsAndTrendsScreen`. | there is no such row on the screen |
| S-21903 | The same plus a weight trend (and Fuel if cheap). | the row is below the Weight row, exactly one. | there is no row; kills the mutation that puts it before Fuel/Weight |
| S-21904 | (a) no sessions: the empty card AND `stats_records_link` are shown, the row below the card; (b) a failing core read: the failure view shows and no row. | as described. | (a) there is no row in the empty state; (b) passes both ways on purpose: pins "no row in the failure view" (mutation: the row added outside the list branch) |
| S-21905 | `StatsScreen` with `showPrimerHelp: true` and one session. | `find.byIcon(Icons.show_chart)` and `find.byTooltip('Records & Trends')` find nothing in the header; `stats_primer_help` and `byTooltip('About Stats')` are found. | the header still carries the icon |
| S-21906 | The primer sheet pumped as `test/stats_primer_screen_test.dart` does. | the third block (`stats_primer_block_records`) shows the label `RECORDS & TRENDS` and the new body; no text `THE CHART ICON` anywhere in the sheet. | the block still reads `THE CHART ICON` |

## Input-reality checklist

1. Writers and units: none; navigation only.
2. Lifecycle: the row follows every load (it is part of the list).
3. Settings: `showPrimerHelp` only decides the "?".
4. Time: none.
5. Cost: one widget.
6. Words: two plain lines; the title equals the screen's own title; the primer copy no longer names an icon.
7. Slot competition: the header loses an action (nothing replaces it); the row sits below every section with the list's 32 bottom padding.

## Phases

1. **P1 (done) builder-app:** `RecordsLinkRow`, `StatsScreen` row, `test/stats_records_link_test.dart` (S-21901..S-21904 in the first shape).
2. **P2 builder-app:** remove the icon (D-3), put the row in the empty branch (D-2), the primer copy (D-4), S-21904 (a)/(b), S-21905, S-21906, and move the readers (D-5).
3. **P3 lead:** docs, mutation pass, `crew-reviewer`, full suite.

## Readers (tests that reach Records & Trends by the tooltip or name the icon)

`test/stats_primer_screen_test.dart` (lines ~76, the group `S-2708`, ~246-249, the primer blocks), `test/stats_primer_home_test.dart` (~138), `test/stats_primer_copy_test.dart`, `test/stats_heading_consistency_screen_test.dart` (~941), `test/records_and_trends_screen_test.dart` (~409-435 `the header icon opens Records & Trends`, the comment ~713; the source scan `StatsScreen is the only file in lib/ that constructs RecordsAndTrendsScreen` stays true), `test/omni_back_header_centering_test.dart` (uses `Icons.show_chart` as a stand-in icon: untouched), `test/stats_gallery_render_test.dart` (another session's, untracked, a string only: untouched), plus the Stats readers of P1.

## Mutation list (lead)

(a) the row never shows; (b) the row is missing in the empty state; (c) the row sits above Fuel/Weight; (d) the tap does nothing; (e) the tap opens another screen; (f) the header icon is back; (g) the primer block keeps the old label.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/stats_screen.md` | MODIFIED | the header icon that opens [Records & Trends] | the row at the end of the list that opens [Records & Trends] | S-21902 |
| `docs/stats_screen.md` | MODIFIED | └── header chart icon → RecordsAndTrendsScreen | └── Records & Trends row → RecordsAndTrendsScreen | S-21902 |
| `docs/stats_screen.md` | MODIFIED | The chart icon in the screen's header is the only way into | The Records & Trends row at the end of the list (`RecordsLinkRow` | S-21902 |
| `docs/stats_screen.md` | MODIFIED | placed before the chart icon so the chart icon stays | the header carries one action | S-21905 |
| `docs/stats_screen.md` | MODIFIED | and the chart icon coexist | the "?" and the row coexist | S-21905 |
| `docs/stats_screen.md` | MODIFIED | Signals cards, and the chart icon — over one | Signals cards, and Records & Trends — over one | S-21906 |
| `docs/stats_screen.md` | MODIFIED | the per-exercise screens the header icon opens | the per-exercise screens the Stats row opens | S-21902 |
| `docs/nutrition.md` | MODIFIED | └── header chart icon → RecordsAndTrendsScreen | └── Records & Trends row → RecordsAndTrendsScreen | S-21902 |
| `docs/records_and_trends.md` | MODIFIED | ├── header chart icon → RecordsAndTrendsScreen | ├── Records & Trends row → RecordsAndTrendsScreen | S-21902 |
| `docs/records_and_trends.md` | MODIFIED | so the header chart icon is the only entry point into | so the Stats row is the only entry point into | S-21902 |
| `docs/records_and_trends.md` | MODIFIED | the screen the chart icon sits in | the screen the Records & Trends row sits in | S-21902 |
| `docs/widget_catalog.md` | MODIFIED | the Signals cards, the chart icon) | the Signals cards, Records & Trends) | S-21906 |
| `docs/widget_catalog.md` | ADDED | - | `RecordsLinkRow` | S-21901 |
| `docs/stats_screen.md` | ADDED | - | `stats_records_link` | S-21902, S-21903 |

Stale-term sweep (`grep -rInE "chart icon|header icon" docs`, minus plans/history/releases): the rows above; also `lib/` comments in `stats_primer_sheet.dart` and `stats_primer_state.dart` (P2).

## Open items

1. (owner) A look at the row on a device; the gallery test (`test/stats_gallery_render_test.dart`) is another session's and its "when" string for Records & Trends still says "chart icon".
2. The row shows even for a history Records & Trends would show nearly empty; that screen handles its own empty cases.
3. A user who knew the icon finds the row one scroll away at the end of the list (owner chose this).

## Predicted files

`records_link_row.dart` (+60), `stats_screen.dart` (+20/-15), `stats_primer_sheet.dart` (+6/-6), `stats_primer_state.dart` (comment), seven test files, seven docs.

## Progress

- [x] Seeded, P1 built (row + S-21901..S-21904 first shape)
- [x] Owner decision: row only, icon removed
- [x] P2 build (8.8 min)
- [x] Docs, mutation pass (6 mutants killed; the row-above-Fuel mutant was not run: S-21903 pins the position), review (APPROVE WITH FIXES: README sentence, one comment; fixed), full suite (below)

## Assumption Log

- 2026-11-16: base commit `964dc4c7` on `claude_develop`; other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-16: scenario ids S-219xx; grep found none in the five-digit form.
- 2026-11-16: the row also shows on the empty first-use state (the icon was reachable there; the screen has its own empty state) and the primer wording are the lead's defaults.

## Feedback

- 2026-11-16 owner: not both icon and row; "yes agreed" to the row only. An earlier build of the row before this answer was held, then kept on this answer.
