# Evidence — plan 39 (logger polish round 2)

Lead-run checks, per phase. Counts are as the lead pasted them; this file
records them, it does not re-run anything (docs-only phase).

## Baseline

- `flutter analyze`: 181 issues — the plan's baseline.
- `flutter test` (full suite): `+5034 ~1`, all passed (before fix 2).

## Phases

- **P1 — hours + ceiling**: `OmniDateUtils.formatTimerDigits` (S-4701) and
  every display site on it; `MetricStepCalc.maxDurationSeconds` (S-4704);
  header, rest chip, round-length row and list totals past an hour
  (S-4702, S-4703, S-4705, S-4706). 516 tests in the touched files, green.
- **P2 — label + hint**: the unit label under the number and the
  `tap to type` hint (`unitGap`, `showTapHint`, S-4707, S-4712).
- **P3 — cardio weight**: the interval's weight row back in live, session
  editor and routine editor (S-4708, S-4709); the "no weight on interval"
  tests flipped. New `test/cardio_interval_weight_storage_test.dart`, 6 tests
  under Mock and Hive.
- **P4 — hero / ring / tightening**: `MetricEmphasisTier.hero` +
  `kCountUpDigitsFontSize`, ring digits `kRingDigitsFontSize`, set-bar cell
  heights and the tighter top (S-4710, S-4711). New
  `test/count_up_hero_layout_test.dart`, 7 tests.
- **Fix 1 — dialog ceiling**: `showDurationEntryDialog` gained `maxSecs`; the
  three round-length callers pass `MetricStepCalc.maxDurationSeconds`
  (U-19..U-21 in `test/tap_to_edit_unification_test.dart`).

## iOS simulator (iPhone 17 Pro, real font)

- The cardio interval screen was looked at.
- A sports period was looked at.
- A 230 h round length was looked at (the dialog clamps to the ceiling).

## Docs

- Docs phase (P5, this run): `docs/modality_based_exercise_ui.md`,
  `docs/my_routines.md`, `docs/data_models.md`,
  `docs/widget_catalog/session_widgets.md`, `docs/constants_reference.md`,
  `docs/rest_tracking.md`, the series index
  `docs/plans/2026-10-15-38-logger-rework-series.md`.
- `flutter test test/docs_indexing_contract_test.dart
  test/ui_standards_contract_test.dart`: run at the end of the docs phase;
  result recorded in the docs report.
