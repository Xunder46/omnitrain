# Evidence: plan 114 (Shins muscle)

Base: `d3c5bb4c` on `claude_develop`. Nothing committed. Production change: 4 files, 5 lines. Whole diff: 14 files, +755/-18 (almost all tests).

## Baselines and results (all observed by the lead)

| Check | Result |
|---|---|
| `flutter analyze` | 181 issues before and after (baseline 181, plan 113) |
| Phase 1a files (`muscle_taxonomy`, `muscle_display`, `catalog_referential_integrity`, `catalog_refresh`, `db_seed`, `muscle_links_storage`) | `+88: All tests passed!` |
| Phase 1b files (`muscle_filter`, `tibialis_muscle_refresh`) | `+23: All tests passed!`; refresh file alone after the review fix `+5: All tests passed!` |
| `test/docs_indexing_contract_test.dart` + `test/ui_standards_contract_test.dart` | `+54: All tests passed!` |
| Full `flutter test` (900 s cap) | `+6404 ~2: All other tests passed!` (0 failed, 2 skipped, as before) |
| Invariant: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | prints nothing |
| Diff boundary: `git diff --stat -- lib/features lib/widgets lib/state lib/core/services lib/data/repositories lib/watch watch lib/core/constants/data_version.dart scripts/sqlite_schema.sql` | prints nothing |
| Docs sizes (`wc -c`) | data_models 47,949 · db_integration 41,547 · constants_reference 27,286 (all < 53,248) |

## Red to green (the lead applied each mutation by hand, ran the guards, restored from a copy and `cmp`'d identical)

| Mutation | Red tests |
|---|---|
| M1 seed row back to `muscle-calves` | S-18803 (S-3 approved rows); S-18804 on Mock and Hive; S-18805 on Mock and Hive; S-18807 (Hive) |
| M2 Shins entry moved after Adductors | S-18801; S-18802 (c); S-18809 plus the existing S-1 filter-order test; `musclesOf` Legs list; S-18805 on Mock and Hive (dropdown order) |
| M3 `bundledCatalogVersion` left at 12 | all five refresh tests (S-18805, S-18806 on both stores; S-18807 on Hive); re-run after the review fix against the production source: still all five |
| M4 SQL Shins insert removed | S-18808 (`S-9 ... seeds the 24 groups`) |
| M5 touched-skip commented out in `_refreshExerciseMuscleGroups` | S-18806 on Mock and Hive |

S-18802 cases (b), (d), (e), (f), (h), (i) pass without the change by design (guards only); (a), (c), (g) are the red ones.

## Residue sweep (Phase 2 item 4)

- `grep -rn "23 groups\|23 entries\|16 muscles\|hasLength(23)\|23 taxonomy" lib test docs` (excluding plans, history, releases): one hit, `test/muscle_display_test.dart:121`, which is correct (24 groups minus the excluded Obliques = 23).
- `grep -c "muscle-calves" lib/mock/seed_data.dart` is 10, none for `exercise-tibialis-raise`.

## Deviations and notes

- `lib/core/constants/catalog_version.dart` was edited by the lead, not the builder: `crew-builder-data` cannot write `lib/core/**`.
- The two docs sentences and three small doc edits were made by the lead (no docs-keeper run); `docs/data_models.md`, `docs/db_integration.md`, `docs/constants_reference.md`.
- The builder's first draft of `test/tibialis_muscle_refresh_test.dart` copied a fake catalog source (the lead's brief said to). The review flagged it (Minor); the lead replaced it with `const BundledCatalogSource()`, so the demo-routine leg of the refresh now runs too.
- One stale message in `test/catalog_referential_integrity_test.dart` ("the 23 taxonomy ids") was reworded without a number.
- The builder renamed a second count in `test/muscle_display_test.dart` (`hasLength(22)` to 23, the obliques-excluded list) that the brief did not name; it is the same enumeration.
- Review: `.review.md` verdict APPROVE WITH FIXES (0 blocker, 1 major = this evidence file, 1 minor = the fake source); both fixed.
