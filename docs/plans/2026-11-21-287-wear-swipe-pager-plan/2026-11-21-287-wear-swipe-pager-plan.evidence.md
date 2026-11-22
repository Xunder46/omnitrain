# Plan 287 — evidence

Base commit: `5123702f` (`.work/2026-11-21-287-wear-swipe-pager/base.txt`). Machine: Windows 11, Git Bash. Nothing committed.

## Who wrote what

- P1 production (`watch_pager_state.dart`, `watch_logging_pager.dart`, the counter in `watch_logging_screen.dart`, the shell wiring in `wear_app.dart`): `crew-builder-watch` from the exact code in the brief (run `20261121-234532`). The run wrote all four files in about a minute and then spent the remaining 24 minutes on gateway commands that hang on this machine (`git-diff`, `test`); the lead stopped it after 25 minutes and verified the files himself. No report was written.
- Lead edits to the builder's files (stated, not hidden): the widget's `AnimatedSwitcher` was changed after the lead's own test found two copies of one exercise on screen for a moment after a swipe onward and straight back (page key by number, constant duration, `if (!animate) return child`); the landing now survives a failing store write (`try`/`catch` plus a `debugPrint`).
- P2a/P2b tests (`test/watch_pager_state_test.dart`, `test/wear_pager_screen_test.dart`): written by the lead, not the crew: the crew's gateway cannot run a test here, and a builder writing widget tests blind is the shape that ends `no_write` in this repo's history.
- P3 docs (`docs/wear_os_app.md`, plan 280 open item 2): by the lead, for the same reason (a docs keeper's only check is the gateway).
- No architect run (the seed named files, symbols and exact code), no prover (the lead's mutation pass is the proof), no reviewer run (the gateway hangs; the lead read the final code and the diff).

## Seed changes during the build

- D-28705 as built: the page is keyed by a counter that moves each time the current slot changes (`_page`), the switcher's duration is constant, and a move the user did not make returns the child with no transition (the seed said duration zero; a zero-duration `AnimatedSwitcher` left two entries for the same exercise alive after a quick swipe onward and back: S-28725).
- Scenarios added beyond the seed: S-28722 (a second swipe during a landing is ignored), S-28723 (the vibrations), S-28724 (only the user's own swipe slides), S-28725 (onward and straight back leaves one logger), S-28726 (the counter fits beside a long name at 192 and 227 dp), S-28727 (a failing write leaves the logger usable). S-28718 and S-28721 are as seeded. S-28721's shell half reads the rest surface.

## Observed output

- `flutter analyze`: 174 issues, the plan's baseline (0 errors).
- `flutter test --no-pub test/wear_pager_screen_test.dart test/watch_pager_state_test.dart`: `+28: All tests passed!` (9 state, 19 widget).
- Mutation pass (`mutate287.py`, backups outside the tree, each file compared byte-for-byte after each mutant): 23 mutants, 23 KILLED, 0 alive, every file `restored=True`: threshold 24 to 0; direction sign; wrap instead of stop; the lock ignored by `showsPager`; the landing guard removed; the locked branch removed; the notice end made inclusive; `AbsorbPointer` removed; the slide side fixed; animate always; animate never; reduced motion ignored; the outgoing page kept; the shell without the pager; landing on the current page re-selecting; `land` not jumping; the label shown with one page; no heavy tap; no click; the notice never repainting; the page key by slot; a non-swipe move sliding; the swipe target never expiring; a failed landing not caught. Separately, S-28726 turned red when the header's `Flexible` was replaced by a plain box (both sizes), then the file was restored and compared.
- Existing Wear files with the pager in the shell, the base against my tree: `wear_app_test`, `wear_menu_screen_test`, `watch_logging_surfaces_test`, `wear_logging_layout_test`, `ui_standards_contract_test` give `+111 -16` on the base (my two edited files set aside) and `+111 -16` with the change: the 16 reds are this machine's, not the change's (below).
- Full suite on this machine: `+7734 ~4 -1113`, exit 1. Not a green run and not comparable to a baseline: see "Environment" below. The two pager test files were touched while it ran (S-28727 and the `try`/`catch` landed mid-run: the run's one pager failure, S-28727, is the test seeing the code before the catch); the final state of both files is the `+28` run above.
- `python3 -I .claude/scripts/macos/plan-lint.py after <plan>`: clean (21 scenario(s), 4 docs-delta row(s)).

## Environment (not from this change, observed on this machine)

- `sync_protocol` schema documents are not found (`SyncProtocolRejection:missing_schema ... observations_up`, 536 lines in the full run): 11 `watch_logging_surfaces_test` tests and the whole sync-fixture family fail on the base the same way.
- `test/ui_standards_contract_test.dart` and `test/docs_indexing_contract_test.dart` are red on the base with findings in files this unit never touched (button shapes in the menu and rating screens, hexadecimal colours and relative links in older plan files); none of their findings names a line this unit wrote.
- `test/wear_os_config_test.dart` S-28132 fails on `lib\watch\debug\wear_menu_debug_main.dart` (a Windows path separator in the test's allow-list).
- `test/pre_release_gate_ios_artifact_test.dart` shows as modified in `git status` and I did not edit it: another session is working in this tree (its file time is during this unit). It is outside this plan's scope and was left alone.

## Not done

- The macOS-style simulator look is not applicable (Wear OS); no Wear emulator or watch was run. Owner check 9 in `docs/wear_os_app.md` is the device check, including whether the system takes the right swipe as "leave the app".
- No reviewer run.
