# Plan 296 evidence

Base commit `eaa0a44e`. Windows PC: the full suite is red in the baseline and was not run; evidence is the touched and neighbouring files, `flutter analyze`, the APK and the emulator.

## The finding (measured before the change)

A throwaway widget probe (deleted) rendered the Start screen at 192, 227 and 300 dp with 0, 1 and 4 routines, minimal (Sync, Free workout, Log food) and full (plus Diagnostics and the phone in range):

- 192 dp minimal: no overflow, but the routine list had zero height (`Routine 0` not on screen, with 1 or 4 routines): no routine could be started.
- 192 dp full: overflow 96 px. 227 dp full: overflow 45 px, no routine visible. 227 dp minimal: routine visible. 300 dp: fits in every case.

## Builds

- P1: `crew-builder-watch`, run `20261122-140651`, 1.7 min, no denial, no stop. One file, as briefed.
- Lead edits after the builder: `dart format` on the two files; the compact list's top and bottom padding (one `padding:` line and the constant `compactEdgeInset`, found on the emulator: the round bezel clipped the first words of the empty sentence); the tests, docs, the doc split and the mutation pass.

## Checks (observed)

- `flutter test test/wear_start_screen_compact_test.dart`: `+9: All tests passed!` (S-29601 twice, S-29602, S-29603, S-29604, S-29605 twice, S-29606, S-29607).
- Neighbouring: `watch_session_start_test.dart` fails 35 tests that are all in `.work/windows-base-failing-tests.txt` (Windows baseline); `watch_nutrition_quick_log_test.dart` and `wear_menu_screen_test.dart` ran in the same invocation with no new failure naming them.
- `flutter analyze` (whole repo): `174 issues found.` (baseline 174, 0 errors).
- `flutter build apk --debug --flavor wear -t lib/watch/wear_main.dart`: built.
- `docs_indexing_contract_test.dart`: the same 7 tests fail as in the Windows baseline; none now names a Wear doc (the one hex-literal hit in the moved accent section was reworded: it was a real violation carried since plan 286).
- Emulator `OmniWear_Small` (round, 192 dp), debug build, no phone paired: the Start screen before the change showed the overflow banner; after it shows no banner, the sentence is whole, and a swipe scrolls to `Free workout`, `Log food` and `Diagnostics` (screenshots seen).

## Mutation pass (lead; in place, backup outside the tree, restored and compared after each)

20 mutants over `watch_start_screen.dart` against the new test file: always the roomy layout; always the compact layout; the primary and utility compact heights ignored; both shrink-wraps dropped; the routines reversed; the compact and roomy empty sentences blanked; the compact hint dropped; the compact separator removed; the Free workout compact flag ignored (two ways); each of the four compact buttons not compact; the roomy list not expanded; the compact edge padding removed; the roomy height changed. **20 of 20 killed.** The first pass left one alive (routines reversed: with four routines `Routine 0` still sat on screen), closed by asserting the order of two routines; the padding mutant was added after the emulator finding.

## Not verified here

- A real watch: how the round bezel clips the 40 dp buttons near the edges, and whether 16 dp is enough everywhere (owner check 16 in `docs/wear_os_app.md`).
- The Apple wrist's own Start layout was not compared; this plan only repairs the Wear overflow and the unreachable routines.
