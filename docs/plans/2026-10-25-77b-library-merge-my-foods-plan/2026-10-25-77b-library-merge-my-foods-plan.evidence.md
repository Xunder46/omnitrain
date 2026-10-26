# Evidence — 77b

- `test/library_merge_test.dart`: 11 tests green. The ten related nutrition test files (library_merge, nutrition, screen_widget, my_foods_unification, food_photo_clear_legacy_edit, library_row_toggle, food_library_copy_edit, food_library, food_group_membership, header_standardization): 473 green together. `flutter analyze` 180 issues, 0 errors (baseline 180).
- Phases: P1 delete helper and editor button; P2 tab merge (exact code); P3a new tests; P3b 21 tests reworked; fix round 1 (two surviving mutants).
- Lead's mutation pass: 11 one-line mutations; 9 killed at once; 2 survived (an edited copy of a bundled food listed as a legacy row; Delete offered on a bundled catalog row); both killed after fix round 1 (S-12812b, S-12816b).
- Seen on the iPhone 17 simulator: two tabs, the Create new food button at the bottom of Library. Not seen on a device: the Yours tag on a real created food, editor delete (owner checks ODC-1, ODC-2).
- Docs: the docs keeper stopped on a search loop (`STOP_REASON: loop`, 48 repeats of one search for test ids, nothing written); the lead wrote the doc edits.
