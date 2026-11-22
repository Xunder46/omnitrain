# Plan 293 — evidence

Base commit: `96963900` (`.work/2026-11-22-293-wear-diagnostics/base.txt`). Machine: Windows 11, Git Bash.

## Who wrote what

- P1 production (the summary, the screen, the transport's notes, the shell's lifecycle and reachability notes and entry, the Start screen's button, the entry-point wiring): `crew-builder-watch`, run `20261122-021127`, about 3 minutes, no gateway command, DONE with exit 0, from exact code in the brief. The lead read the result through the analyzer and the tests: no change to the builder's code was needed.
- Tests (three new files), the docs and this file: the lead, as in plans 287-292.
- Not run: architect, prover, reviewer.

## Observed output

- `flutter analyze`: 174 issues, 0 errors (the baseline).
- The three new files: `+21: All tests passed!` (summary 7, transport 7, shell 5 plus the fit scenario at both sizes and the entry scan).
- The whole Wear set (the three new files, the workout-summary, water, bests, banner and pager files, `wear_app_test`, `wear_menu_screen_test`, `wear_phone_settings_test`, `wear_accent_theme_test`, `wear_effort_rating_screen_test`, `wear_logging_layout_test`, `wear_watch_transport_test`, `wear_os_config_test`): `+265 -1`; the one red is `wear_os_config_test` S-28132 (a Windows path separator), red on the base as well.
- The phone's diagnostics readers (`diagnostics_entry`, `diagnostics_file_receive_source`, `diagnostics_lifecycle`, `diagnostics_log`, `diagnostics_merged_text`, `diagnostics_received_storage`, `diagnostics_watch_transport`, `diagnostics_wiring_source`): `+36 -1` with the change and `+36 -1` with every tracked edit set aside.
- Mutation pass (`mutate293.py`, backups outside the tree, files compared byte-for-byte): 31 mutants, 30 killed first time. The one that lives is equivalent in a debug build: the shell's gate `widget.diagnostics != null && kDiagnosticsEntryVisible` without its second half, because `kDiagnosticsEntryVisible` is true in every debug build the suite runs in; the visibility truth table is the phone's own `diagnostics_entry_test.dart`. Not mutated: the ordering of the `frame_received` line before the handler (S-29314 asserts it, but moving a block is not a one-line mutation; the test reads the log from inside the handler).
- `python3 -I .claude/scripts/macos/plan-lint.py after <plan>`: clean (20 scenario(s), 3 docs-delta row(s)).

## Not done

- No Wear emulator or watch run: owner check 13 in `docs/wear_os_app.md`.
- Sending the log to the phone: the platform plugin has no file transfer, and changing its Kotlin half cannot be tested here.
- The workout, sensor and recovery lines: the Wear wrist has no platform workout yet (plan 280 item 9).
