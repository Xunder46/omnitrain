# Evidence — plan 32 (Training Mix card + Session Summary clarity)

Base commit `69ef72d2a5b8cb42ebfdc2949dbd678d6635fd5d`. Builder reports:
`.work/crew/2026-10-13-32/report-builder-a.md`, `report-builder-b.md`; prover:
`report-prover-32.md`.

## Baselines and results

- `flutter analyze`: 181 issues at base, 182 after both builds — the one new
  notice is the `withOpacity` deprecation on the `_StatPill` caption line
  (D-3207's named API); 0 errors throughout.
- Full `flutter test` after both builds: 4518 passed, 1 skipped, 1 failed —
  `test/pre_release_gate_ios_artifact_test.dart`, caused by the governor running
  the suite while the prover's temporary checkout existed under `.work/gateway`;
  the file re-run alone passes. The final full-suite re-run is recorded by the
  governor later.
- Prover: 12 scenarios red at base for their guarded reason (S-3201–S-3207,
  S-3211–S-3214; the negative twins green at base as expected). S-3208 and the
  S-3215 fit half were proven by governor mutation: removing the legend label's
  `Flexible` (`mix_layer.dart` `_buildLegend`) and the distance row name's
  `Expanded` (`session_distance_card.dart` `_buildRow`) turns each red;
  originals restored and `cmp`-checked, then green.
- Invariant grep clean (no `hive_workout_repository` import under `lib/state`,
  `lib/features`, `lib/widgets`, `lib/core`).

## Docs (phase C)

- `docs/stats_screen.md` Mix layer section: explainer, bar labels, legend, note
  and unrated line, strip title/caption/stubs — each behaviour sentence cites
  its `S-32xx` group or test in `test/mix_layer_screen_test.dart`.
- `docs/widget_catalog.md` `MixLayerSection` note and
  `docs/widget_catalog/session_widgets.md` `SessionDistanceCard` entry: same
  copy, cited to the same tests.
- `docs/session_summary.md`: EFFORT caption and `Change rating` / `Add rating`
  (`test/session_summary_effort_row_test.dart` groups `S-3211`, `S-3212`);
  distance hint and pencil (`test/session_summary_distance_test.dart`
  `S-3213`–`S-3215`).
- `test/docs_indexing_contract_test.dart` after the edits: `+13: All tests
  passed!` (the value scan forced `widget_catalog.md` to say "modalities with
  no share" instead of a percentage literal, and `session_widgets.md` to cite
  `S-3215` by id — its name carries a `dp` value the scan forbids on catalog
  pages).
