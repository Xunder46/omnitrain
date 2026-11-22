# Plan 288 (part 1) — evidence

Base commit: `0d98db14` (`.work/2026-11-22-288-wear-personal-bests/base.txt`). Machine: Windows 11, Git Bash.

## Who wrote what

- P1 production (`WatchBestsRecord`, the stores' `bests` and `pruneBests`, `WatchPersonalBests`, the orchestrator route, the shell restore, the entry-point wiring): `crew-builder-watch` from the exact code in the brief, run `20261122-011438`, 3.4 minutes, no gateway command (the brief forbade them), DONE with exit 0.
- Lead edits to the builder's file, both found by the lead's own tests: the applies are serialised (`_applying`), because S-28823 showed two frames applied together could end with the older frame's prune deleting the newer frame's stored row while memory decided by the newer one; and the `_frameRecordId` field that serialisation made unused was removed (analyzer).
- Tests (`test/watch_bests_store_test.dart`, `test/watch_personal_bests_test.dart`, `test/wear_personal_bests_wiring_test.dart`), the S-004 guard edit, a `pruneBests` forwarder in the `_SuspendingStore` test double of `test/watch_dialled_per_exercise_test.dart` (it implements the store interface and would not compile), the docs and this file: the lead, as in plan 287.
- Not run: architect, prover, reviewer (the gateway cannot run a test here).

## Observed output

- `flutter analyze`: 174 issues, 0 errors (the baseline). The plan 287 commit left it at 175 (a braces finding in `test/wear_pager_screen_test.dart` after the formatter); fixed in this change.
- `flutter test --no-pub` over the three new files: `+28: All tests passed!` (the store file runs its scenarios under both backends, the judge file holds 19 tests including a Hive round trip, the wiring file 3).
- The whole Wear set (the new files, `wear_pager_screen_test`, `watch_pager_state_test`, `wear_app_test`, `wear_menu_screen_test`, `wear_phone_settings_test`, `wear_accent_theme_test`, `wear_effort_rating_screen_test`, `wear_logging_layout_test`): `+142: All tests passed!`.
- `watch_session_engine_test.dart` S-004 (the append-only guard, edited to allow `pruneBests`): passes by name. The rest of that file, and eight other files, carry this machine's existing failures: the nine files the change could touch give `+120 -86` with my edits and `+120 -86` with them set aside. A patch that normalised the schema keys of eleven test loaders did not reduce them, so the cause is not the path separator; it was reverted.
- Mutation pass (`mutate288.py`, backups outside the tree, files compared byte-for-byte): 35 mutants. 33 killed on the first pass; two lived and were closed by tests: the Epley operation order (a fixture where `w*(1+r/30.0)` and `w+w*r/30.0` differ in the last bit: 20 kg x 4 and x 5, S-28811b) and a rebuild that counted every observation kind (a stored round carrying reps and a load, S-28822). Final: 35 of 35 killed, every file `restored=True`. The pass also needed S-28825 (a restore over two stored frames) for the two restore-ordering mutants.
- `python3 -I .claude/scripts/macos/plan-lint.py after <plan>`: clean (22 scenario(s), 2 docs-delta row(s)).

## Not done

- The decision is not used by the screen: the banner and the tap are plan 288b; `holdsBests` and the rest-screen banner are 288c.
