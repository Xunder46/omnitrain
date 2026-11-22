# Evidence: plan 285 (series 283 unit c), the Wear effort-rating prompt (2026-11-21)

Base commit `c8f0d6e4`, working tree, nothing committed.

## Suites (observed output)

- Full suite after the last change: `flutter test` -> `+8808 ~4: All tests passed!` (plan 284's last run: +8789; 19 tests added).
- `test/wear_effort_rating_screen_test.dart`: `+19: All tests passed!`, three consecutive runs green (the builder had seen one unexplained flip in an intermediate run that did not reproduce).
- `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart`: `+54: All tests passed!`.
- `flutter analyze`: 174 issues (the baseline), 0 errors. Invariant grep: no output. `plan-lint before` and `after`: clean (14 scenarios, 5 Docs delta rows).

## Mutation pass (the lead's, scripted)

21 mutants over the screen (Confirm gating, Skip, rotary direction, drag, scroll, picked highlight, semantics, tap, rebuild, scale-down, compact sizes), the menu's End (bypass, empty finish) and the shell (prompt takeover, boot restore, listener, menu wiring). First pass: 15 killed, 6 survived (the scale-down net hid every size change, and the shell's own listener hid the screen's own rebuild). A tests-only fix round added exact sizes for Confirm, Skip and the number buttons, a crowded-watch test (S-28507c) and a screen-alone rebuild test (S-28505c); all re-killed. Final: 21 of 21 killed.

## Looking at it

A throwaway widget probe (deleted) rendered the screen to PNG at the watch size over a real owed prompt: the title, five numbers with `4` filled, the two end labels, Confirm and Skip all on the round-face-sized square, nothing clipped (`.work/2026-11-21-285-wear-effort-rating-prompt/png/`). The probe's 192 dp image was in fact drawn at 227 dp (the test harness resets the view size), so 192 dp is covered by the numeric tests (S-28507a/b/c) only. Confirm looked pale in the PNG because it was captured mid-way through the button's enable animation; a direct check showed `onPressed` non-null after a pick.

## Not verified here

- A real Wear watch or emulator: the rotary feel, the round bezel, the paired-phone behaviours (owner check 7 in `docs/wear_os_app.md`).
- A prompt on top of a pushed route (nutrition) at the moment a rating becomes owed (D-28506: not reachable from the menu's End).
- No separate reviewer run; the lead read the production diff (screen, menu End, shell): no finding. Skip's height is floored at 32 dp by Material's text-button minimum rather than set exactly (noted by the builder, not an issue at 192/227).
