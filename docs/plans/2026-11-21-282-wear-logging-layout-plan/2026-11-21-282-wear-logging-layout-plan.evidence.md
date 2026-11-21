# Evidence: plan 282, the Wear logging surface fits 192 and 227 dp (2026-11-21)

Base commit 7df00769, working tree (plan 281 still uncommitted beside it), nothing committed.

## Suites (observed output)

- Full suite after the last change: `flutter test` -> `+8736 ~4: All tests passed!`, exit 0 (plan 281's last full run was +8709).
- `test/wear_logging_layout_test.dart`: `+25: All tests passed!` (re-run by the lead after the last fix round).
- Neighbours: `test/watch_logging_surfaces_test.dart` +33, `test/wear_app_test.dart` +6, `test/wear_menu_screen_test.dart` +22, `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart` `+54: All tests passed!`.
- `flutter analyze`: 174 issues (the baseline), 0 errors. Invariant grep: no output. `plan-lint before` and `after`: clean (8 scenarios, 4 Docs delta rows).

## Before the change (throwaway probe, deleted)

`RenderFlex overflowed` on the Wear logging surface: 227 dp: set 25 px, timed 25, drill 25, round 9; 192 dp: set 96, timed 132, drill 132, round 80.

## Mutation pass (the lead's, scripted: one-line mutant, run `test/wear_logging_layout_test.dart` (+ neighbours for the large-layout mutant), restore, `cmp`)

18 mutants over the threshold, the scale-down net, the compact header and rows, the numerals, the padding, the Log button, the step buttons and the shell's Menu button. First pass: 3 killed, 14 survived (the `FittedBox` hid every size change and the tests only checked lower bounds). A tests-only fix round turned the checks into exact sizes (`closeTo`), a row-height bound, a `Label · unit` check, and a crowded-header test (S-28204b); a second pass killed all but two, and the leftover was closed in a third tests-only round. Final: 18 of 18 killed.

Defect found by the fix round, not by the first build: the compact `Log` button was drawn 48 dp tall, not 40 (Material pads a button's tap target), so it was missing `tapTargetSize: shrinkWrap` (D-28207, fixed in production, proved by S-28202 and its mutant B8).

## Looking at it

A throwaway widget probe (deleted) rendered the shell to PNG at 227x227 and 192x192 (Roboto and MaterialIcons loaded): set, timed and round all show the exercise name, two rows, `Log` and `Menu` fully on screen with no overflow. Copies: `.work/2026-11-21-282-wear-logging-layout/png-final/`. Not looked at on a Wear emulator or a watch (no Android SDK on this Mac).

## Not verified here

- A real watch or emulator: the round bezel clipping the corners of `Log`, the real pixel density, whether 40/32/36 dp controls are comfortable to hit (owner check 5 in `docs/wear_os_app.md`).
- The 260 dp threshold itself: tests pin 192/227 as compact and 800x600 as large, nothing between (the doc says 260; it is a constant).
- Where the rest of the screens (the start list, the picker) fit 192 dp: not measured here.

## Review

Lead's own read of the production diff (small, three files): no finding. The compact branch leaves the large layout's widgets and texts unchanged (S-28207 and the 33 existing logging-surface tests), the shell's `Builder` rebuilds with the shell, and the `FittedBox` hit-tests through its transform (S-28205 dials by tap and crown). No separate reviewer run (about 100 production lines).
