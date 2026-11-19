# Review: 2026-11-16-219 stats-visible-records-link · working tree (base 964dc4c7)
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: not run (brief forbids the full suite; facts established: 7 new + 18 reader files green in builders' runs, six mutants killed, lint at baseline 181)
Diff vs Predicted Files: conforms — outside the brief's list: `docs/plans/2026-11-16-217-finish-dialog-counts-what-you-did-plan.md` (1 line) and `test/stats_gallery_render_test.dart` (untracked), both other sessions' per the brief; the plan's "seven test files / seven docs" is 4 test files / 6 docs on this tree (the brief's list is the truth).

## Findings
1. [Major] docs/README.md:69 — the Stats Screen index row still reads "Its header opens [Records & Trends](records_and_trends.md)." The diff edited the adjacent Records & Trends row (line 71) in the same table but left this sentence, which is now false: the header has no action that opens Records & Trends (stats_screen.dart:371-384, only the conditional "?"). The plan's stale-term sweep greps `chart icon|header icon`, so "Its header opens" slipped through. Fix: change the sentence to name the closing row, e.g. "Its list ends with a [Records & Trends](records_and_trends.md) row that opens it." Guard: none needed (doc sentence; the behaviour is pinned by S-21902/S-21905).
2. [Minor] lib/features/stats/stats_screen.dart:461-462 — the comment "(S-21902: never a 48 gap after Instruments)" cites S-21902 for a gap size that test does not assert: `stats_records_link_test.dart:204-211` only asserts the row's top is below `InstrumentList`'s bottom, never the 24 dp distance. Fix: drop the parenthetical or reword to "(the sections' own 24 closers, verified positionally by S-21902/S-21903)".

Per-question evidence (Q1..Q5), brief order:
- Q1 spacing: exact one-24-gap in all named cases — stats_screen.dart:385-467. Empty: `_buildEmptyState` (OmniSurface, no trailing space, :515-527) + `SizedBox(24)` + row. Populated: every block closes with its own 24 (:401, :414, :425, :442); InstrumentList has no trailing gap (grep: only an internal 8, instrument_list.dart:159); FuelSection ends with content, no trailing gap; WeightTrendRow ends with `OmniSurface`, no trailing gap (whole file read); the Fuel/Weight branch adds exactly one closer for whichever is present (:461-462). `computeMixLayer` is nullable but returns an empty-window payload, never null, when history exists (stats_progress_service.dart:510-519, `keepEmptyWindow: true`), so a populated branch always renders the Mix section and the row is never the first child with a missing gap. Hint wrap: `Expanded` column, no fixed height, plain wrapping `Text` (records_link_row.dart:38-55) — safe at 320 dp and large scale. OK.
- Q2 leftovers: `Icons.show_chart` remains only at records_and_trends_screen.dart:438 and exercise_progress_screen.dart:424 (both screens' own `OmniEmptyState` icons — unrelated), omni_back_header_centering_test.dart:12 (stand-in in a host test, planned untouched), stats_records_link_test.dart:378 (negative assertion). No `byTooltip('Records & Trends')` left anywhere (only the negative at stats_records_link_test.dart:379). No tour/coach mark names the Stats header icon (all coach-mark hits are the session screen's info/notes icons). No hits in `integration_test/`, `test/ui_standards*`, `docs/*qa*`, `docs/watch*`; no allowlist entry or ratchet added by this diff. The only leftover that could mislead is test/stats_gallery_render_test.dart:1355 ("The chart icon in the Stats header") — another session's untracked file, already plan Open item 1. OK.
- Q3 header: `OmniBackHeader` forwards `actions` straight to `AppBar` (omni_back_header.dart:64) and pins `centerTitle: true` on Apple platforms regardless of action count (:52-57, with the comment explaining the two-action drift it fixed); an empty list is the AppBar default. Tap targets: the back arrow lives in `leading`, unaffected. No contract test assumed two actions: `omni_back_header_centering_test.dart` parametrises 0–3 actions plus an Android case, so 0 and 1 are already covered. OK.
- Q4 tests: S-21901 fails on base (the widget/key did not exist); S-21902 (:190-224) and S-21903 (:251-283) fail on base (no row) and also pin position; S-21904(a) (:287-317) fails on base, (b) (:320-337) passes both ways by design as the plan states (pins "no row on failure"); S-21905 (:354-381) fails on base (icon present); S-21906 (:384-413) fails on base (`THE CHART ICON` label). Moved readers keep their points: stats_primer_screen_test.dart S-2703 now asserts `stats_records_link` renders with help off (:76), S-2708 renamed to "the '?' and the Records & Trends row coexist" and taps the row (:243-251); stats_heading_consistency_screen_test.dart:941-945 taps the row with `ensureVisible`; records_and_trends_screen_test.dart S-913 renamed and still asserts the Semantics label plus the landing (:406-437), and the source scan (:714) still holds. OK.
- Q5 docs: all changed sentences say what the code does and name existing tests (`records_and_trends_screen_test.dart` single-entry scan at :714, `stats_records_link_test.dart`, `stats_primer_contract_test.dart`, S-2708's new name, S-17307 group in `stats_instruments_horizon_screen_test.dart:438`). Stale-term sweep across docs (minus plans) finds only the new true sentences (stats_screen.md:36, navigation_and_screens.md:199) plus Finding 1. `docs/watch*` and QA docs: no mention. One stale sentence left (Finding 1).

## Docs delta
- stats_screen.md "the row at the end of the list that opens [Records & Trends]" -> applied
- stats_screen.md "└── Records & Trends row → RecordsAndTrendsScreen" -> applied
- stats_screen.md "The Records & Trends row at the end of the list is the only way into" -> applied (gains the `RecordsLinkRow`/key wording)
- stats_screen.md "alone in the header" -> applied (marker differs: actual wording is "the header carries one action, the '?'" — true, tied to S-21905)
- stats_screen.md "and the Records & Trends row coexist" -> applied
- stats_screen.md "Signals cards, and Records & Trends — over one" -> applied
- stats_screen.md "the per-exercise screens the Stats row opens" -> applied
- stats_screen.md ADDED `stats_records_link` -> applied (:30)
- nutrition.md "└── Records & Trends row → RecordsAndTrendsScreen" -> applied
- records_and_trends.md "├── Records & Trends row → RecordsAndTrendsScreen" -> applied
- records_and_trends.md "so the Stats row is the only entry point into" -> applied
- records_and_trends.md "the screen the Records & Trends row sits in" -> applied
- widget_catalog.md "the Signals cards, Records & Trends)" -> applied
- widget_catalog.md ADDED `RecordsLinkRow` -> applied (matches the code: OmniSurface, key, title, muted line, chevron, presentation-only claim)

Doc edits the table does not name:
- docs/navigation_and_screens.md:199-200 (two rows, `StatsScreen` and `RecordsAndTrendsScreen`) — applied, true, tied to S-17307/S-21902.
- docs/README.md:71 (Records & Trends index row) — applied, true. But its Stats Screen neighbour (:69) was NOT updated — Finding 1.

## Assumption Log rulings
- Base commit 964dc4c7: ratified (used as the git-diff base this run).
- Scenario ids S-219xx: ratified (no collision seen).
- Row on the empty first-use state + the lead's wording: ratified (owner-approved per the plan's Feedback; S-21904(a) pins it).

## Scenario coverage
S-21901 -> test/stats_records_link_test.dart · 'S-21901 the row itself › title, hint, chevron, and a tap calls onTap once'
S-21902 -> test/stats_records_link_test.dart · 'S-21902 the row closes a populated list › the row sits below the Instruments list and opens Records'
S-21903 -> test/stats_records_link_test.dart · 'S-21903 the row is the last section, below Weight and Fuel › the row is below the Weight trend and still exactly one'
S-21904 -> test/stats_records_link_test.dart · 'S-21904 the row closes every branch › no sessions: the row follows the empty card' + 'a failed load shows no row'
S-21905 -> test/stats_records_link_test.dart · 'S-21905 the header has no chart icon › the "?" stays and the chart icon is gone'
S-21906 -> test/stats_records_link_test.dart · 'S-21906 the primer names the row, not an icon › the third block reads RECORDS & TRENDS with the new body, reached through the "?"'
Moved readers: test/stats_primer_screen_test.dart (S-2703, S-2708), test/stats_heading_consistency_screen_test.dart:941, test/records_and_trends_screen_test.dart (S-913, source scan) — all re-verified above. MISSING: none.
