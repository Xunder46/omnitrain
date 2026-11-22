# Evidence — plan 303

- New file `test/duplicate_food_groups_merge_test.dart`: 22 tests (Mock + Hive store cases, state, one Hive seed case, two widget cases), all pass.
- Mutation pass over the new code (16 mutants: step no-op; no catalog / library re-file; keeper ignores shipped; no archive; no re-create / un-archive; shipped losers archived; case-sensitive name key; create/rename without the check; check counting itself; `freeGroupName` returning the base; case-sensitive check; step 21 no-op in either store): 16 of 16 killed.
- Not provable alone: removing the step-13 seed skip (A-2).
- Affected-set comparison, same 28 files, base `af1c676f` (git archive copy) vs the working tree: base 61 failures, tree 60; zero failures only in the tree. The failing set is the Windows-red baseline (ui_standards, docs_indexing, watch layout, ...); one base-only failure, `picker_polish_test` S-13112, is flaky.
- `flutter analyze` on touched folders: 3 info notices, all pre-existing.
- `test/data_migration_test.dart` updated for version 21 and the new last step; `nutrition_test`, `food_library_state_test`, `food_library_test`, `shipped_food_groups_lock_test` fixtures stopped creating same-name categories (A-1).
- Full `flutter test` NOT run (the baseline is red on Windows).
