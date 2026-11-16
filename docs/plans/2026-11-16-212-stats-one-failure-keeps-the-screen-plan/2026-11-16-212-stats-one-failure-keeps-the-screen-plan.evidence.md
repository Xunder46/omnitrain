# Plan 212 — evidence

Base commit `b70dc61b` on `claude_develop` (other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan's scopes).

## What was built

- P1 (builder, 3.2 min): per-signal `try`/`catch` in `SignalsService.evaluateCandidates` (+ dartdoc); the Fuel summary read in `StatsScreen._loadData` guarded; new `test/stats_one_failure_service_test.dart` (S-21301, S-21302, Mock and Hive).
- P2 (builder, 8.4 min): new `test/stats_one_failure_screen_test.dart` (S-21303; S-21304 with a control that shows the row when the food read works); `S-18207` in `test/signals_layer_screen_test.dart` rewritten (its first load now fails through a core read: a Mock subclass whose `getAllSessions` throws once, armed after `initialize()`; `_FlakySignal` deleted).
- Lead: docs (`docs/stats_screen.md`, `docs/signals.md`, and the stale `LoadFailureView` sentence in `docs/widget_catalog/layout_and_inputs.md` the review found).

## Lead verification

- Reader found before P1: `S-18207` used a throwing signal to make the load fail, so it went red by design; recorded in the plan's Readers section and rewritten in P2 (whole `signals_layer_screen_test`: 74 green).
- Mutation pass, four mutants, four killed: (a) signal guard removed, (b) guard stops at the first throw (`break`), (c) Fuel guard removed, (d) guard rethrows. Sources restored and compared after each.
- Review (crew-reviewer): APPROVE WITH FIXES. Major: a stale sentence in the widget catalog (fixed). Minor: `loadDismissals` still reads the preference store unguarded (Open item 2).

## Final runs

Full suite (lead, 900 s cap): `+7764 ~4: All tests passed!`, 0 failures. `flutter analyze`: 181 issues (baseline 181), 0 errors. Docs and UI-standards contract tests green.

## Not done / residual

- A swallowed signal or Fuel failure leaves no trace (no diagnostics event).
- Totals, Instruments and Mix remain all-or-nothing; `loadDismissals` is unguarded.
- Reloading Stats while open: dropped by the owner for good.
- (owner) Nothing to see on a healthy history; the guard shows only on malformed data.
