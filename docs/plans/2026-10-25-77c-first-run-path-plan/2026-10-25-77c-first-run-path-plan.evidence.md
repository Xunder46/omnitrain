# Evidence — 77c

- `test/first_run_path_test.dart` green; the ten related nutrition/home files 487 green together; `flutter analyze` 180 issues, 0 errors.
- P1 exact code (one run, 1.5 min), P2 tests (8 min). The tests builder found a real defect: at 320 wide and 2.0x text the new label overflowed the row by 63 px; it skipped that one test instead of weakening it. The lead fixed it (label in a `Flexible` with ellipsis, figure `Expanded(flex: 2)` in a scale-down box), un-skipped the test and added rect assertions.
- Lead's mutation pass: 8 mutants; 6 killed at once, `BoxFit.none` survived until the rect assertions were added, then killed; label-not-flexible killed.
- Not seen on a device (owner check ODC-1).
