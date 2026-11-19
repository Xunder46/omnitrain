# Evidence — 77d

- `test/row_caption_and_primer_test.dart` green; the seventeen related files 610+ green together; `flutter analyze` 180 issues, 0 errors.
- P1 exact code (3.5 min); P2 tests (11 min; 12 red tests moved by the primer now rising over the nutrition screen and the shorter caption).
- A real defect surfaced: with the primer now shown over the nutrition screen, `test/screen_overflow_contract_test.dart` (Nutrition cases) failed with the primer sheet overflowing on small phones / large text (27 px on iPhone SE at normal text). The sheet existed before but was shown over the home screen and never covered by that contract. Fix (lead): the sheet content scrolls. The contract test is unchanged.
- Lead's mutation pass: 8 mutants; 7 killed at once; the empty-fallback survived until the table row `100` → `100` was added, then killed.
- Not seen on a device (owner check ODC-1).
