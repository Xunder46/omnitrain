# Plan 301 evidence

Base commit `66a62f8a`. Windows PC: the full suite is red in the baseline; evidence is the touched file, the Wear test set, `flutter analyze`, the APK and the emulator.

## The finding (measured before the change)

Emulator `OmniWear_Small` (round, 192 dp), the real app with a restored session: the logging header sat left-aligned at the top-left; the first words of `No exercise` and the heart-rate number were cut off by the bezel. Geometry: the name's box top-left corner was 128 dp from the centre of a 96 dp-radius face.

## Builds

- P1: `crew-builder-watch`, run `20261122-160642`, 1.0 min, no denial, no stop. One file, as briefed.
- Lead edit after the builder: the top inset 20 -> 22 dp, because the circle test showed the 112 dp name row's top corners 0.4 dp outside the face (with a 2 dp margin) at 192 dp; then the tests, the docs and the mutation pass.

## Checks (observed)

- `flutter test test/wear_logging_bezel_test.dart`: `+11: All tests passed!` (S-30101 and S-30102 and S-30103 at 192 and 227, S-30104 for four effort kinds, S-30105).
- `flutter test test/wear_logging_bezel_test.dart test/wear_logging_layout_test.dart`: `+36: All tests passed!` (plan 282's fit, `Log`/`Menu`, worst-header and rows guards).
- The Wear set (`flutter test test/wear_*_test.dart test/watch_logging*_test.dart`): 13 failures, all in the Windows baseline except two, which were looked at: `wear_os_config_test` S-28132 compares paths containing `lib/watch/debug/` with Windows backslashes (a path-separator failure that exists without this change), and `wear_diagnostics_shell_test` S-29322, which was **caused by plan 297's formatter**: `dart format` split `DiagnosticsLog(storage: await openDefaultDiagnosticsStorage())` over three lines in `wear_main.dart`, and the test greps the one-line form. Fixed in its own commit; both files' tests pass after it.
- `flutter analyze` (whole repo): `174 issues found.` (baseline 174, 0 errors).
- `flutter build apk --debug --flavor wear -t lib/watch/wear_main.dart`: built.
- Emulator, after the change: the header `No exercise` and `90 bpm` is whole and centred, `Log` and `Menu` where they were (screenshot seen). The `90 bpm` is the real app's live Health Services reading (restored session, permission granted, synthetic walking), which also shows plan 298's chain inside the shell.

## Mutation pass (lead; in place, backup outside the tree, restored and compared after each)

9 mutants over `watch_logging_screen.dart`: no top inset; name width unbounded; sensor width unbounded; header not centred; the name row filling its box; the roomy header centred; the counter dropped; the name not ellipsized; the compact bottom padding changed. **9 of 9 killed.** Two survived the first pass and were closed by tests: the roomy sensor line's left alignment (S-30105 now has a sensor line) and the 2 dp bottom padding (`Log`'s bottom is exactly 190 at 192 dp).

## Not verified here

- A real watch: whether 22 dp is right for every round bezel (owner check 18), and the lower corners of `Log` (check 5).
- The rest surface, the menu and the nutrition screen on a round face were not looked at.
