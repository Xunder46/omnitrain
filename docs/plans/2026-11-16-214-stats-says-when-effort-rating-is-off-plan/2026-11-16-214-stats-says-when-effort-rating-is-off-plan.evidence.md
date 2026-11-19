# Plan 214 — evidence

Base commit `56196f09` on `claude_develop` (other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan's scopes).

## What was built

- P1 (builder, 3.5 min): `signalsLockedLine` / `signalsMoreLine` take `ratingOff` (off copy, count clamped, defaults unchanged); `SignalsLockedSection`, `SignalsLayerSection`, `MixLayerSection` take `ratingOff`; `StatsScreen` passes `!settingsState.showFeelingSurvey` inside its existing `ListenableBuilder`; new `test/stats_effort_rating_off_copy_test.dart` (S-21401, 3 tests).
- P2 (builder, 4.2 min): new `test/stats_effort_rating_off_screen_test.dart` (S-21402..S-21405, 7 tests, Mock; S-21405 flips the setting while the screen is open and counts `getAllSessions` reads to show no reload).
- Lead: docs (`docs/signals.md`, `docs/stats_screen/signals_layer.md`, `docs/stats_screen.md`, and the two `docs/widget_catalog.md` rows the review found).

## Lead verification

- Readers (builders' runs): `signals_layer_screen_test` 74, `progression_rate_signal_screen_test`, `mix_layer_screen_test` 111, `stats_rated_weeks_screen_test`, `signals_framework_test`, all green.
- Mutation pass, five mutants, five killed: screen passes `false`; flag inverted; Mix ignores the flag; the more-line ignores it; the count unclamped in the off locked line.
- Review (crew-reviewer): APPROVE WITH FIXES. Major: two widget-catalog rows missing the new input (fixed). Minors: a missing citation (fixed), a stray first line in the screen test (removed), the Signals primer text (left, Open item 3).

## Final runs

Full suite (lead, 900 s cap): `+7774 ~4: All tests passed!`, 0 failures. After the small test-file and doc fixes: the two new files, the docs-indexing and UI-standards contract tests `+64` green. `flutter analyze`: 181 issues (baseline 181), 0 errors. `plan-lint after`: clean.

## Not done / residual

- The Mix note's second wording, the waiting lines and the Signals primer do not mention the setting.
- A wrist whose Effort Rating setting has not yet synced can still prompt while the phone says it is off (transient).
- (owner) Settings, Workout, Effort Rating off; open Stats with under 4 rated weeks.
