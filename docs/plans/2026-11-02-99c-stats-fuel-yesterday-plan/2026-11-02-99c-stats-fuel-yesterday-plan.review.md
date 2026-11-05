# Review: 99c · stats fuel yesterday · 418c1ea4..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · tests: +6126 ~2 -2 (2 skipped; both failures pre-existing, outside the diff — see below)
Diff vs Predicted Files: conforms (all ten predicted files, nothing else; 99a/99b and the nutrition-target edits excluded per the brief)

## Findings

None.

## Test run

`gateway.sh test` (this run, 900 s cap): `+6126 ~2 -2: Some tests failed.` The two failures are not in
any file this diff touched and both are already on record:

- `test/delete_focused_timer_test.dart` S-4905 — `Expected: '00:45' / Actual: '00:46'`, the wall-clock
  timer flake documented in the 95 review (`plans/2026-11-01-95-watch-water-bar-plan/...review.md:19`).
- `test/routine_save_removes_deleted_rows_test.dart` S-R3 — `Expected: empty / Actual: [Instance of
  'TemplateEffort']`, on the known-failure list per the 99b review (`...99b...review.md:6`).

Every 99c test file is green in this run: `test/fuel_summary_window_test.dart` (5 tests × 2 harnesses),
`test/fuel_section_widget_test.dart` (6 tests), `test/fuel_row_screen_test.dart` (all groups), and the
Fuel group of `test/nutrition_trend_screen_test.dart`. No `[E]` line names a fuel test.

## Answers to the brief's five questions

1. **Other readers of the Fuel window: none.** `FuelSummary` / `computeFuelSummary` are read only by
   `lib/features/stats/stats_screen.dart` (L73, L119, L180, L337-339) and
   `lib/features/stats/widgets/fuel_section.dart`. The signals (`lib/core/models/fuel_vs_load.dart`,
   `protein_consistency.dart`, `nutrition_consistency.dart`, `lib/core/services/signals/fuel_vs_load_signal.dart`)
   use their own `LoggedDay` types and never touch `FuelSummary` or its averages, so no reader assumed the
   window included or ended today.
2. **Today-only row: reachable and readable.** `stats_screen.dart:337` renders `FuelSection` whenever the
   summary is non-null; with `loggedDays == 0` the widget draws the sentence (`fuel_not_enough_days`) and
   `0/7 days logged` — asserted on the screen by `fuel_row_screen_test.dart` S-1107 (13 days) and S-1111,
   and at service level by `fuel_summary_window_test.dart` S-17204.
3. **S-1105 recompute: 580/58 is correct.** `_seedEveryDayLogged` seeds days 1..7 at 100×(k+1) kcal /
   10×(k+1) g; sessions on days 1 and 3 are training days, day 5 is rolling. Training (200+400)/2 = 300 kcal,
   (20+40)/2 = 30 g; rest over days 2,4,5,6,7 = (300+500+600+700+800)/5 = 580 kcal, (30+50+60+70+80)/5 = 58 g.
   The old 440/44 was the today-in-window figure. S-1107 (13 → renders with sentence, 14/15 → hidden),
   S-1111 (food only at d10 → `0/7` + sentence) and the overflow cases (three logged days → figures;
   one logged day → sentence, `1/7`) all re-derive from their fixtures; no weakened assertion found.
4. **`showsAverages` branching is complete.** In `fuel_section.dart` the two metric rows (L107-…), their
   target lines and both split captions (L234-…) are all inside `if (summary.showsAverages)`; only the
   sentence (L217-…) and `fuel_logged_days` (L230-…) draw otherwise. `_proteinBelowTarget` (L78-83) rounds
   both sides exactly as `_change` (L60-70) does: 149.5 vs 150 → 150 < 150 false and delta 0 → dash, muted;
   150.4 vs 150 → same; 149.4 vs 150 → red `↓ -1 g`. Consistent.
5. **Docs: no stale line.** `stats_screen.md` (Fuel row §, L471-560, constants table L697-698, file table
   L724-732), `nutrition.md` (`computeFuelSummary` §, L573-590, invariant table L687-688),
   `data_models.md` (FuelSummary §, L470-507) and `widget_catalog.md` (L42-44) all say "ending yesterday /
   today in neither" and tie every claim to an existing test (each named test read this run). The only
   "up to today" hit (`stats_screen.md:173`) is the Mix rated-week rule (99b), not Fuel. No doc colours
   up/down arrows; the comparison paragraph names protein-under-target as the sole error colour.

## Assumption Log rulings

The plan carries no Assumption Log section; its seven Decision Ledger rows (D-17201…D-17207) were each
verified against the code this run: window/previous/visibility arithmetic (`stats_progress_service.dart:2057-2110`),
`kFuelMinLoggedDays` + `showsAverages` (`fuel_summary.dart:17,119`), sentence + colour rule
(`fuel_section.dart:107,217-234,299`), no "Today so far" line (absent from the widget). All ratified.

## Scenario coverage

- S-17201 → `test/fuel_summary_window_test.dart` · `S-17201 window is the 7 finished days ending yesterday` (+ twin `previous range keeps its oldest day, d14`)
- S-17202 → `test/fuel_summary_window_test.dart` · `S-17202 three logged days show averages, two do not`
- S-17203 → `test/fuel_summary_window_test.dart` · `S-17203 a session started today does not make a training day`
- S-17204 → `test/fuel_summary_window_test.dart` · `S-17204 visibility: today alone shows, d14 hides, d13 is previous`
- S-17205 → `test/fuel_section_widget_test.dart` · `S-17205 Fuel with 2 logged days…` / `…3 logged days…`; on the screen: `test/fuel_row_screen_test.dart` · S-1107, S-1111, group `a row with fewer than three logged days`
- S-17206 → `test/fuel_section_widget_test.dart` · the four `S-17206 …` tests (error colour, over-target neutral, no-target neutral, rounding-absent muted)

No MISSING rows. The plan has no `## Docs delta` table, so no delta block is due; the four docs named in
the brief were all updated (read this run).
