# Plan 213 — evidence

Base commit `da111335` on `claude_develop` (other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan's scopes).

## What was built

- P1 (builder, 3.0 min): pure `signalDismissalsWithout`; `StatsScreen._dismissSignal` shows `Signal hidden for 14 days.` with an `Undo` action (after clearing any current message); new `_undoDismissal` (re-resolves the view while mounted, chains the store write either way); `test/stats_signal_undo_service_test.dart` (S-21390, 3 tests).
- P2 (builder, 16.7 min): `test/stats_signal_undo_screen_test.dart` (S-21391..S-21395, 5 tests, Mock). Its S-21394 could not observe the message expiring, which led to the finding below.
- Finding (lead, confirmed in Flutter's `snack_bar.dart:303`): a `SnackBar` with an action ignores `duration` and persists until dismissed or replaced. Fix 1 (builder, 2.9 min): `OmniMessage.show`/`showOn` take an optional `persist` (null keeps every other caller as it was), the dismissal passes `persist: false`; S-21394 now observes the real expiry; new group `S-21396` in `test/omni_message_test.dart` (with the unchanged-default control).
- Lead: docs (`docs/signals.md`, `docs/stats_screen/signals_layer.md`, `docs/widget_catalog.md`, `docs/design_system.md`, and `docs/widget_catalog/layout_and_inputs.md` the review found).

## Lead verification

- Mutation pass, nine mutants, nine killed: message text changed; undo does not re-resolve; undo does not write; undo restores nothing; first message not cleared; undo skipped when unmounted; `persist: false` dropped at the call site; `OmniMessage` ignores `persist`; the pure function removes every entry. Sources restored and compared after each.
- Review (crew-reviewer): APPROVE WITH FIXES, 0 blocker, 0 major. Minors: the `OmniMessage` API rows in the widget catalog lacked `persist` (fixed); an Undo that overlaps a silent reload can show the card hidden until the next reload (view only, Open item 2).

## Final runs

Full suite (lead, 900 s cap): `+7784 ~4: All tests passed!`, 0 failures. `flutter analyze`: 181 issues (baseline 181), 0 errors. Docs-indexing and UI-standards contract tests `+54` green. `plan-lint after`: clean (7 scenarios, 5 docs-delta rows).

## Not done / residual

- The rest of review item 9 (jargon, findability).
- No screen to see or restore dismissed signals later (a dismissal still lasts 14 days unless undone within 6 s).
- (owner) Dismiss a signal card, tap Undo within 6 seconds.
