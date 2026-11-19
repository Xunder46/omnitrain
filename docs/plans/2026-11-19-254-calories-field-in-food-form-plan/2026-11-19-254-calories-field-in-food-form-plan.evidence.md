# Evidence: plan 254 (the calories box in the food form)

Base commit a2c82b3f, branch `claude_develop`, Windows machine (1,075 environment failures at base; the check is the failing-name set against the base set).

## Suites

| Check | Result |
|---|---|
| `test/calories_field_state_test.dart` (Mock and Hive twins) | passed |
| `test/calories_field_form_test.dart` (S-25406..S-25413, S-25415) | passed |
| `test/food_form_label_test.dart` (four tests that read the old `= N cal` line rewritten) | passed |
| Probe readers (`edit_food_save_test`, `unsaved_changes_dialog_test`, `food_photo_clear_legacy_edit_test`) | green except `food_photo_clear_legacy_edit_test` "clearing a legacy library food's photo waits for the Save tap", a base failure (Windows temp-directory file lock) |
| Full suite, first run (before the review fixes) | +7010 passed, 1083 failed: 1075 base names plus 14 test files that failed to LOAD (machine load) |
| Full suite, final run | +7218 passed, 1073 failed, 0 names outside the base set |
| `flutter analyze --no-pub` | 178 issues, 0 errors (baseline 178) |

## Mutation pass (lead, in place, restored and byte-compared by script)

16 mutants: `createCatalogFood`, `createCustomFood`, `updateCustomFood`, `updateCatalogFood`, `createOwnCopyOfDefault` and `createFood` dropping the override, the form never sending it, macros overwriting an edited box, an equal value stored, `Use macros` not resetting, the edit form ignoring the stored number, a blank box storing 0, no validator, the probe counting selection changes, a typed zero treated as none. First pass: 2 alive: (1) "equal value stored" because S-25410(b) entered text identical to the box (Flutter's `enterText` sends no change event for identical text), fixed by typing another number first; (2) "untouched box stores the sum" is an equivalent mutant (the box then always equals the macro sum). All others killed.

## Crew runs

P1 3.2 min, P2 1.8, P3 2.7, P4 9.5, review fixes 3.7, reviewer 8.6. No run stopped.
