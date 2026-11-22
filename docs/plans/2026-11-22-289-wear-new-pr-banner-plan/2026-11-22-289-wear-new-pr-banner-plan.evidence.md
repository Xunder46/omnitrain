# Plan 289 — evidence

Base commit: `7a71dde2` (`.work/2026-11-22-289-wear-new-pr-banner/base.txt`). Machine: Windows 11, Git Bash.

## Who wrote what

- P1 production (the record state on `WatchLoggingState`, the banner widget, the two overlays, the tap, the shell wiring): `crew-builder-watch` from the exact code in the brief, run `20261122-013033`, 2.6 minutes, no gateway command, DONE with exit 0. The lead read the whole diff: it matches the brief; the library comment edit in `wear_app.dart` is the brief's.
- Tests (`test/wear_personal_record_state_test.dart`, `test/wear_personal_record_banner_test.dart`), the `playPersonalRecord` method on the test double in `test/watch_logging_surfaces_test.dart` (its only other `WatchHaptics` implementer), the docs and this file: the lead, as in plans 287 and 288 (a crew run cannot execute a test here).
- Not run: architect, prover, reviewer.

## Observed output

- `flutter analyze`: 174 issues, 0 errors (the baseline).
- `flutter test --no-pub` over the two new files: `+17: All tests passed!` (11 state, 6 widget).
- The whole Wear set (both new files, the plan 288 files, the pager files, `wear_app_test`, `wear_menu_screen_test`, `wear_phone_settings_test`, `wear_accent_theme_test`, `wear_effort_rating_screen_test`, `wear_logging_layout_test`): `+159: All tests passed!`.
- `watch_logging_surfaces_test`, `watch_dialled_per_exercise_test`, `watch_session_engine_test`: `+42 -85` with the change and `+42 -85` with the five edited files set aside: this machine's existing failures, unchanged.
- Mutation pass (`mutate289.py`, backups outside the tree, each file compared byte-for-byte): 19 mutants, 19 KILLED, 0 alive, every file `restored=True`: the exercise id, the reps and the load reaching the judge; the flag never cleared; every log stamping; the window length (5 s); the inclusive window end; no restart; the banner always on; not a live region; the words read aloud too; the banner taking touches; a fixed colour instead of the accent; no tap on a record; a tap on every log; no banner on the logging screen; none on the rest screen; the shell not giving the state its owner; the wrong platform vibration.
- Not killable and not mutated: the `kind` argument of the verdict call. A timed effort or a hold carries no `reps`, so the judge's own `reps < 1` guard refuses it first; the kind guard is the judge's (plan 288, S-28815), not this call site's.
- `python3 -I .claude/scripts/macos/plan-lint.py after <plan>`: clean (14 scenario(s), 3 docs-delta row(s)).

## Not done

- No Wear emulator or watch run: owner check 10 in `docs/wear_os_app.md`.
- `holdsBests` on the routines request, and a fold of phone-logged sets during a live workout, are still open (series 87c/87d).
