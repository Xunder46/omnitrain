# Evidence — 99c Fuel reports the last 7 finished days

Facts only. P5 (docs keeper, 2026-11-02) recorded the lead's facts and what it
read in the files this run; it ran no test (the lead runs the docs contract
test).

- P1: `test/fuel_summary_window_test.dart` +8 (lead's count). The file read this
  run holds 5 tests over both harnesses: `S-17201 window is the 7 finished days
  ending yesterday`, `S-17201 twin previous range keeps its oldest day, d14`,
  `S-17202 three logged days show averages, two do not`, `S-17203 a session
  started today does not make a training day`, `S-17204 visibility: today alone
  shows, d14 hides, d13 is previous`.
- P3: `test/fuel_section_widget_test.dart` +6 (read this run): S-17205 ×2
  (`Fuel with 2 logged days says so in words and draws no figures`, `Fuel with 3
  logged days draws the averages and no sentence`), S-17206 ×4 (`protein under
  its target is the error colour; the other comparisons are neutral`, `protein
  over its target is neutral even though it rose`, `protein with no target is
  neutral even when it fell`, `a comparison too small to survive rounding reads
  as absent and muted`).
- lint 181 (= baseline, per lead).
- P2 code read this run: `fuel_section.dart` draws `fuel_not_enough_days` when
  `!summary.showsAverages`, keeps `fuel_logged_days` always, and colours a
  missing comparison `textMuted`, protein-below-a-set-target
  `colorScheme.error.withValues(alpha: 0.8)`, everything else `textSecondary`.
- P4 code read this run: `test/fuel_row_screen_test.dart` groups S-1102,
  S-1105–S-1107, S-1111, S-14041, S-14043 and S-1259/S-1260/S-1261 (the latter
  including group `a row with fewer than three logged days`).
- P5 (this run): `docs/stats_screen.md`, `docs/nutrition.md`,
  `docs/widget_catalog.md`, `docs/data_models.md` updated to the new window,
  sentence and colours; every behavioural sentence cites a test read this run.
  Stale-claim sweep over `docs/` found no remaining "Fuel ends today" or
  "Today so far" claim outside `docs/plans/` records.
