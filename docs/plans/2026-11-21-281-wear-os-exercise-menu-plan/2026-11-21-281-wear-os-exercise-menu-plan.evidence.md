# Evidence: plan 281, the Wear OS exercise menu (2026-11-21)

Base commit 7df00769, working tree, nothing committed.

## Suites (observed output)

- Plan files and neighbours, last run: `flutter test test/wear_menu_screen_test.dart test/watch_menu_state_test.dart test/watch_session_menu_engine_test.dart test/wear_app_test.dart test/wear_os_config_test.dart test/watch_session_start_test.dart test/watch_session_engine_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` -> `+249: All tests passed!`.
- Full suite (run after the last production change, before the last three tests were added): `flutter test` -> `+8709 ~4: All tests passed!`, exit 0.
- `flutter analyze`: 174 issues (the plan's baseline), 0 errors.
- Invariant `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`: no output.
- `plan-lint after`: clean (31 scenarios, 13 Docs delta rows).

## Mutation pass (the lead's, scripted: one-line mutant, run the plan's files, restore, `cmp`)

51 mutants over the engine jump, the Add path, `WatchMenuState`, `WatchMenuScreen`, the picker and the shell. First pass: 37 killed, 12 survived. Every survivor was closed by tests only and re-killed (all 11 real ones), except one judged equivalent:

- Equivalent: removing `if (!_isActive) return;` from `WatchMenuState.finish`. The engine's own terminal guard (D-14602) makes `finishSession` on an ended session a no-op, and `discard` has its own guard.
- Gaps found and closed: the exact slot id of a second pick (token kept), a rest not counted as a logged effort, a paused work clock still locking, a dismissed question not counting as a yes, a phone ending the session while the question is up, a stale row tap leaving the menu open, the current row being the prominent one, the picker's default flag, the double-tap guard (the first version of the test never raced), and the shell ticker after End.
- Two guards added from the review and proved red by reverting the fix: the full-screen question page (`Dialog.fullscreen` -> `Dialog`) and the shell's navigator (`_navigator.currentState?.push` -> `Navigator.of(context).push`).
- One production gap found by the ticker test and fixed: a session restored at launch never ticked (D-28116).

## Looking at it without a watch

- A throwaway widget probe (deleted) rendered the surfaces to PNG at 227x227 and 192x192 dp. Findings: the menu fits both sizes; the stock `AlertDialog` did not (fixed: D-28113); the logging surface itself overflows with its bottom button (25 px at 227, 60 px at 192), the same height as the `End` it replaced (D-28115, not fixed here).
- The macOS desktop harness (`flutter run -d macos -t lib/watch/debug/wear_menu_debug_main.dart`) built and ran; its log showed the same one-pixel logging overflow, and a missing-plugin error from the radio (now logged by the harness instead of left unhandled). Run again after the Back button and Esc were added: it launches and the radio errors are logged quietly (one framework exception remains, the logging overflow above). Nobody clicked through it here: a screenshot of the window was not available to this session, so the click-through (Menu, rows, Add, the questions, Back and Esc) is an owner check.
- Shell defect found by reading: `Navigator.of(context)` from the shell's own context had no navigator, so the nutrition quick-log could not open (D-28114); proved by S-28137 and its mutant.

## Not verified here

- Any real Wear OS emulator or watch (no Android SDK on this Mac): the round bezel, the system swipe-back, the pixel density, the paired-phone behaviours. They are the five owner checks in `docs/wear_os_app.md` "Checks on a watch".
- A click-through of the macOS harness window (see above).

## Review

`2026-11-21-281-wear-os-exercise-menu-plan.review.md`: APPROVE WITH FIXES (1 major, 3 minors). All four closed: the full-screen guard test (S-28123c), the stale test header, the picker sentence reworded, and the nutrition sentence backed by S-28137.
