# Plan 215 — evidence

Base commit `d83ad529` on `claude_develop` (other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan's scopes).

## What was built

- P1 (builder, 2.3 min): the Mix legend's first label `In this window` became `Recent` (`mix_layer.dart`); `progressionRateCopy`'s observation became `In the last 4 weeks, N% of your lifting sessions matched or beat your previous one for that lift, up from M% before.`; the three readers that pinned the old strings updated (`mix_layer_screen_test`, `progression_rate_test`, `progression_rate_signal_screen_test`).
- Lead: docs (`stats_screen.md`, `widget_catalog.md`, `signals_registered.md`); the fourth reader found by the full suite (`test/progression_samples_service_test.dart:400`, S-1811, `contains('over the last 4 weeks')`) updated.

## Lead verification

- Mutation pass, four mutants, four killed: label back to `In this window`; observation back to the old sentence; the two percentages swapped; `Recent` also on the `Your usual` bar. Sources restored and compared.
- Review (crew-reviewer): APPROVE, one minor (the rate counts exercise-sessions, so "lifting sessions" is a slight simplification; Open item 3).

## Final runs

First full suite: `+7782 ~4 -2` (both failures were the missed reader above, Mock and Hive). After the fix: the four affected files green (150), then the full suite `+7784 ~4: All tests passed!`, 0 failures. `flutter analyze`: 181 issues (baseline 181), 0 errors. Docs and UI-standards contract tests green. `plan-lint after`: clean.

## Not done / residual

- Findability (Stats in the swipe-up sheet, Records & Trends icon with no visible text) is a layout call, not changed.
- Other labels (`Est. 1RM`, `Best pace`, the other signal cards' jargon) not changed.
- (owner) Read the two new phrases on a device.
