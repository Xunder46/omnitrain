# Plan 292 — evidence

Base commit: `3ed6a106` (`.work/2026-11-22-292-wear-workout-summary/base.txt`). Machine: Windows 11, Git Bash.

## Who wrote what

- P1 production (the summary state, the screen, the engine's `endedByPhone`, the shell wiring): `crew-builder-watch`, run `20261122-020028`, about 3 minutes, no gateway command, DONE with exit 0, from exact code in the brief. The lead read the result through the analyzer and the tests: no change to the builder's code was needed.
- Tests (two new files), the update of seven existing tests, the docs and this file: the lead, as in plans 287-291.
- Not run: architect, prover, reviewer.

## A behaviour change the seven updated tests pin on purpose

After this plan, ending a workout that holds an effort shows the summary before the start surface. Seven tests in `test/wear_menu_screen_test.dart` (S-28123, S-28136) and `test/wear_effort_rating_screen_test.dart` (S-28502a, S-28503, S-28504, S-28511, S-28512) expected the start surface straight after the End and failed; each now dismisses the summary through a small `_doneSummary` helper before its original assertion. Nothing else in them changed.

## Observed output

- `flutter analyze`: 174 issues, 0 errors (the baseline).
- The two new files: `+17: All tests passed!` (9 state, 8 widget counting the fit scenario at both sizes).
- The whole Wear set (both new files, the water, bests, banner and pager files, `wear_app_test`, `wear_menu_screen_test`, `wear_phone_settings_test`, `wear_accent_theme_test`, `wear_effort_rating_screen_test`, `wear_logging_layout_test`, `wear_watch_transport_test`, `wear_os_config_test`): `+244 -1`; the one red is `wear_os_config_test` S-28132 (a Windows path separator in its allow-list), red on the base as well.
- `watch_session_finish_test`, `watch_session_engine_test`, `watch_effort_rating_state_test`, `watch_effort_rating_engine_test`: `+33 -108` with the change and `+33 -108` with every tracked edit set aside: this machine's existing failures, unchanged.
- Mutation pass (`mutate292.py`, backups outside the tree, files compared byte-for-byte): 25 mutants, 25 killed, 0 alive, every file `restored=True`: the hour threshold and the negative length; the Sets/Efforts label; every entry counting as an effort; an empty workout, the phone's end, an unseen workout and an abandoned one each owing a summary; the seen id kept; a new workout keeping the summary; the heart-rate window start, window end, rounding and kind; Done not dismissing; the heart-rate row always shown; the engine helper never recognising the phone's end; the shell never noting, never showing, the question never first, Done doing nothing, the dismiss not redrawing; the screen's inert Done, missing rows and rows read as parts. The heart-rate test first left two window mutants alive (nothing after the end, no other reading kind); a reading after the end and a gps reading were added and both died.
- `python3 -I .claude/scripts/macos/plan-lint.py after <plan>`: clean (16 scenario(s), 3 docs-delta row(s)).

## Not done

- No Wear emulator or watch run: owner check 12 in `docs/wear_os_app.md`.
- The "no heart rate" note (needs a Health-access state) and the heart-rate feed (plan 280 item 9).
