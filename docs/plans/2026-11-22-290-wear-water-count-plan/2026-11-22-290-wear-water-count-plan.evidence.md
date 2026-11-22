# Plan 290 — evidence

Base commit: `3d5f88af` (`.work/2026-11-22-290-wear-water-count/base.txt`). Machine: Windows 11, Git Bash.

## Who wrote what

- P1 (records, stores, engine) and P2 (the state, the route, the request flags, the wiring): `crew-builder-watch`, two runs in parallel on disjoint scopes (`20261122-014058`, 2.3 minutes; `20261122-014109`, about 3 minutes), no gateway command, both DONE with exit 0, from exact code in the briefs. The lead read the results through the analyzer and the tests: no change to the builders' code was needed.
- Tests (four new files), the S-004 guard edit, the `_SuspendingStore` forwarder, the two pinned-test edits (`watch_water_log_test` D-14, `watch_nutrition_quick_log_test` closed set), the docs and this file: the lead, as in plans 287-289.
- Not run: architect, prover, reviewer.

## Observed output

- `flutter analyze`: 174 issues, 0 errors (the baseline).
- The four new files: `+36` tests green (store 7 across both backends plus a Hive reopen, engine 8, state 16, wiring 5).
- The whole Wear set (the new files, plans 287-289's, `wear_app_test`, `wear_menu_screen_test`, `wear_phone_settings_test`, `wear_accent_theme_test`, `wear_effort_rating_screen_test`, `wear_logging_layout_test`, `wear_watch_transport_test`): `+221` green; the one red in the 20-file run, `watch_phone_preferences_test` S-28308g (a schema-validator test whose loader keys schemas by `\` on Windows), is red on the base as well (`+16 -1` both ways).
- The seven reader files that carry this machine's existing failures (`watch_logging_surfaces`, `watch_dialled_per_exercise`, `watch_session_engine`, `watch_water_log`, `watch_nutrition_quick_log`, `watch_session_start`, `watch_session_finish`): `+70 -186` with the change and `+70 -186` with every tracked edit set aside. S-004 (the append-only guard, edited) passes by name.
- Mutation pass (`mutate290.py`, backups outside the tree, files compared byte-for-byte): 42 mutants. 38 killed first. Four lived: the local-date check (the first fixture used a tap two days old, which the session-id filter had already refused: closed by taps stored under today's session id but logged two days, a month and a year earlier, S-29030: the year, month and day checks each killed separately); the session-id filter (a performance-only filter: the local-date check refuses the same taps, so removing it changes no result: equivalent, named); and `press` of an unknown change (the engine refuses an unknown change and `press` catches it, so the state's own guard is redundant: equivalent, named). Two more tests closed gaps the pass pointed at: S-29017 (the water log holds only water) and S-29035 (a restore over two stored frames). Final: every non-equivalent mutant killed, every file `restored=True`.
- `python3 -I .claude/scripts/macos/plan-lint.py after <plan>`: clean (31 scenario(s), 2 docs-delta row(s)).

## Not done

- The bar (plan 291). The launch prune of old confirmed taps (plan 96 D-43/D-44, a fifth prune): not built; taps grow by at most 500 a day and a read skips unneeded days unread.
- The request flags are on the Wear transport, not the `WatchSyncTransport` interface (eight implementers would change); a different sender that wants the flags has to set them the same way.
