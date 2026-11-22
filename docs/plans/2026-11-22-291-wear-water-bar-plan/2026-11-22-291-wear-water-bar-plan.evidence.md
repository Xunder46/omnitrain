# Plan 291 — evidence

Base commit: `670892e4` (`.work/2026-11-22-291-wear-water-bar/base.txt`). Machine: Windows 11, Git Bash.

## Who wrote what

- P1 production (the bar, the nutrition screen's optional owner, the shell's pass-through): `crew-builder-watch`, run `20261122-015207`, about 3 minutes, no gateway command, DONE with exit 0, from exact code in the brief. The lead read the result through the analyzer and the tests: no change to the builder's code was needed.
- Tests (`test/wear_water_bar_test.dart`), the docs and this file: the lead, as in plans 287-290.
- Not run: architect, prover, reviewer.

## Observed output

- `flutter analyze`: 174 issues, 0 errors (the baseline).
- `flutter test --no-pub test/wear_water_bar_test.dart`: `+13: All tests passed!` (the fit scenario runs at both sizes).
- The whole Wear set (the bar file, the plan 290, 289, 288 and 287 files, `wear_app_test`, `wear_menu_screen_test`, `wear_phone_settings_test`, `wear_accent_theme_test`, `wear_effort_rating_screen_test`, `wear_logging_layout_test`, `wear_watch_transport_test`): `+218: All tests passed!`.
- `test/watch_nutrition_quick_log_test.dart` (the screen's older tests): `+7 -40` with the change and `+7 -40` with every tracked edit set aside: this machine's existing failures, unchanged; so the "screen is exactly as before without an owner" claim rests on S-29101, not on that file.
- Mutation pass (`mutate291.py`, backups outside the tree, files compared byte-for-byte): 20 mutants. 17 killed first. Three lived: the compact flag on each button (the fit test found no overflow either way: closed by asserting the controls are at most 36 dp high on the short screens, S-29109: both killed); and the `mounted` guard of the bar's rebuild (unreachable: the owner's listener is cleared when the bar goes and its timer is cancelled, so nothing calls the rebuild after dispose: equivalent, named). The refresh-interval mutant first looked alive because the test pumped the constant itself; the test now pumps a literal minute and the mutant is killed.
- `python3 -I .claude/scripts/macos/plan-lint.py after <plan>`: clean (12 scenario(s), 3 docs-delta row(s)).

## Not done

- No Wear emulator or watch run: owner check 11 in `docs/wear_os_app.md`.
- The launch prune of old confirmed taps (plan 96) is still open.
