# Evidence: plan 115a (three muscles, three re-tags, 28 strength exercises)

Base: `50a95486` (plan 114) on `claude_develop`. Not committed. Production change: `muscle_taxonomy.dart` (+3 entries), `seed_data.dart` (3 re-tags, 1 description, 28 exercise rows with their capability, muscle and equipment entries), `catalog_version.dart` (version 14), `sqlite_seed.sql` (+3 inserts).

## Baselines and results (all observed by the lead)

| Check | Result |
|---|---|
| `flutter analyze` | 181 issues before and after (baseline 181) |
| Phase 1a files (taxonomy, display, db_seed, referential integrity, tibialis refresh, catalog refresh, links storage, filter) | `+114: All tests passed!` |
| Phase 1b screen tests (`muscle_filter_picker_test`, `muscle_picker_test`) | `+23: All tests passed!` (one test was red after Phase 1a: the 28-row menu no longer fit the 800x1400 test surface; surface raised to 800x1800) |
| Phase 2A/2B files (`strength_catalog_gaps`, referential integrity, `watch_reference_sync`, `muscle_filter`) | `+78` after rows 1-16; passes with all 28 rows |
| Phase 3 files (`muscle_filter`, `strength_catalog_refresh`, `tibialis_muscle_refresh`, `catalog_refresh`) | `+51: All tests passed!` |
| Full `flutter test`, after the exercises were in | run 1: `+6439 ~2 -1` (one failure that I did not capture by name); run 2: `+6440 ~2: All other tests passed!` (0 failed). The failing test of run 1 is unidentified. Later runs save their output to a file. |
| Full `flutter test`, final (run 3) | see "Final full run" at the end |
| Exercise rows | 252 before; 258 after rows 1-6; 268 after 7-16; 280 after 17-28 |

## Red to green (the lead applied each mutation by hand, ran the guards, restored from a copy, `cmp` identical)

| Mutation | Red tests |
|---|---|
| A Brachialis moved before Biceps in the taxonomy | S-18901, S-18902, S-18903, S-18809 and the S-1 display order, S-2 menu order (`muscle_filter_picker_test`), S-18912 chip order |
| B Cable Hip Abduction back to `[glutes]` | S-18904 approved rows |
| C Hammer Curl without Brachialis | S-18904 approved rows |
| D Cable External Rotation back to `[rear-delts]` | S-18904 approved rows |
| E 'Rotator cuff' SQL insert removed | S-18910 (`S-9 ... 27 groups`) |
| F catalog version left at 13 | S-18906 and S-18907 on Mock and Hive |
| G touched-skip removed in `_refreshExerciseMuscleGroups` | S-18907 on Mock and Hive |
| H touched-skip removed in `_refreshExercises` | S-18907 on Mock and Hive |
| I Rear Delt Fly description back to the old text | S-18906 on Mock and Hive |
| J `exercise-reverse-curl` muscle row removed | S-18909 (row and sizes), S-18904 (map size and approved rows), S-18905 on Mock and Hive |
| K `bilateral` dropped from Triceps Kickback | S-18909 (triceps-kickback row) |
| L Cable Curl renamed "Hammer Curl" | S-18909 (name uniqueness and the cable-curl row) |

## Final full run

Run 3 (output saved to a file, 0 `[E]` lines): `+6446 ~2: All other tests passed!`. After it: `test/docs_indexing_contract_test.dart` + `test/ui_standards_contract_test.dart` `+54: All tests passed!`; `flutter analyze` 181 issues; the repository import grep prints nothing; the diff-boundary `git diff --stat` prints nothing. After the review fix (Cable Rear Delt Fly step text) the touched test files were re-run: `+48: All tests passed!`.

## Deviations and notes

- `catalog_version.dart` was edited by the lead (the data builder's ceiling excludes `lib/core/**`): version 14, the history sentence, and the opening list no longer says "equipment".
- The 28 rows were built in four runs (rows 1-6, 7-16, 17-28 by the data builder) and the lead read all 28 descriptions and step lists.
- The docs also corrected a sentence the plan did not list: `constants_reference.md` said a version bump alone delivers any catalog change; it now names what the refresh carries (exercises, capabilities, muscle links, foods, demo routines) and says equipment, disciplines and categories are written at first install only.
- The only remaining match of `reverse pec-deck` is the deliberate old-description fixture in `test/strength_catalog_refresh_test.dart`.
- `S-18908` was not issued (the planner skipped the number).
- Docs sizes: data_models 48,053 B; db_integration 42,197 B; constants_reference 27,482 B (all < 53,248).
