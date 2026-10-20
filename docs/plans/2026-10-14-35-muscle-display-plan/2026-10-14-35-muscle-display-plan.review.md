# Review: plan 35 (muscle display, PR 3 of 3) · phases A1–D · 7c89489..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 2 · tests: 4674 passed, 1 skipped, 0 failed (`03:21 +4674 ~1: All tests passed!`); `flutter analyze` 182 issues (= baseline, all info)
Diff vs Predicted Files: conforms — all 24 changed files sit inside the phases' predicted files. `exercise_row_density_test.dart` changed only for the C1 seeding migration (predicted "possibly"); `screen_widget_test.dart` unchanged (no predicted red, as recorded). Docs: 4 of the 6 predicted docs files changed; `docs/state_management/workout_state.md` and `docs/exercise_ranking.md` were verify-only items (no stale mention, filter param still live) — nothing to change, matches the plan's own notes. Nothing outside the prediction.

## Findings
1. [Minor] `scripts/sqlite_schema.sql:855` — the comment still names `SqliteWorkoutRepository.setExerciseMuscleGroups(exerciseId, ids)`; this diff removed that method from `WorkoutRepository`, so a maintainer implementing the future SQLite repository from this contract would look for a method that no longer exists anywhere in `lib/`. The described behaviour (replace the exercise's rows) is now the links setter's. Fix: rename the comment to `SqliteWorkoutRepository.setExerciseMuscleLinks(exerciseId, links)`. Guard: none (comment-only; the C2 grep covered `lib`/`test` only — extend it to `scripts` or fix the line).
2. [Minor] `lib/state/workout/exercise_library.dart:317-319` — the doc comment on `getExerciseMuscleLinks` says "callers must not treat `null` as an empty list", but every display caller this diff added now does exactly that (`?? const []` in `exercise_picker_screen.dart:120-125`, `exercise_library_screen.dart:306-311`, `exercise_detail_view_screen.dart:84-86`, `exercise_library_detail_screen.dart:78-80`), per plan decisions D-3/D-4 and guarded by `test/muscle_filter_picker_test.dart` ('a failing links read leaves rows chip-less, not crashed'). The comment is now contrary to the codebase it describes. Fix: reword to name the deliberate display degradation (rows lose their chips, the detail section collapses) and point at the guarding test; the editor keeps the strict reading.

No blocker or major findings. Not more than 6 substantive findings; no design finding spanning layers.

## Assumption Log rulings
- B (package-style imports in both detail screens): ratify — matches every other import in those files (seen in the diff).
- B (muscles section is a `Column`, 12 pt spacer between the rows, section stays the last block): ratify — `test/exercise_detail_muscle_groups_test.dart` asserts the gap is `moreOrLessEquals(12.0)`.
- B (`_DetailRow`s keep the exercise's link order, not taxonomy order): ratify — guarded by `test/muscle_display_test.dart` ('S-1 musclesWithRole keeps link order and skips missing groups') and `test/muscle_filter_picker_test.dart` ('Conventional Deadlift shows its main muscles in link order … (S-9)').

## Scenario coverage
S-1 → `test/muscle_display_test.dart` (7 tests: order/depth, missing-group skip, role names, link order + missing-group skip, empty links, `muscleTaxonomyName`, constants)
S-2 → `test/muscle_filter_picker_test.dart` · group `S-2: Muscle filter grouped by region` (3 testWidgets: 24-item order + indent + weights, region/muscle filter semantics, closed field plain name)
S-3 → same file · group `S-3 / S-9: rows show main muscles only` (picker bench/Arnold/tennis/custom/ghost-link/failing-read cases + `the library list row shows only the main muscle`)
S-4 → `test/exercise_detail_muscle_groups_test.dart` (4 body-level cases incl. INV-4 both-empty collapse; both screens with bench press, tennis match, Easy Run)
S-5 → verified: grep `getExerciseMuscleGroups|setExerciseMuscleGroups` over the repo → zero hits in `lib/` and `test/`; remaining mentions are historical plan records under `docs/plans/` and finding 1 (`scripts/sqlite_schema.sql:855`, stale)
S-6 → verified in the diff: `docs/future-work.md` taxonomy entry deleted, "Nothing is deferred at the moment." added; `test/docs_indexing_contract_test.dart` green in the full suite
S-7 → `test/muscle_filter_picker_test.dart` · group `S-7` (Volleyball Match at 800×1400 and 390×844, no overflow)
S-8 → same file · 'a region-only main link shows the region name (S-8)'
S-9 → same file · 'Conventional Deadlift shows its main muscles in link order and no secondary-only chip (S-9)'
S-10 → same file · group `S-10 / S-11` · 'choosing All restores the unfiltered list'
S-11 → same file · 'Clear Filters resets the muscle dropdown to All'

Guard provenance: no `prove-red` verdict is recorded in the evidence file (builders don't prove); the brief carries the lead's evidence that 26 hand-applied mutations all turned their guarding tests red — taken as the prover record for every guard above.

## Part 2 — original acceptance criteria, whole series (PR 1 `fd57bf6`, PR 2 `0983075`+`7c89489`, PR 3 working tree)
1. Grouped filter, Chest/Neck standalone — **satisfied** · `test/muscle_filter_picker_test.dart` · `S-2` order/indent test (Chest, Neck at the region x, w600 depth-0 rows).
2. Legs → squat + tennis; Quadriceps → squat only — **satisfied** · same file · 'a region matches a region or one of its muscles; a muscle matches only itself'.
3. Triceps filter excludes a bench press whose triceps tag is secondary — **satisfied** · same test ('Barbell Bench Press' absent) + `test/muscle_filter_test.dart` · 'S-5 a secondary-only link excludes the exercise'.
4. Bench press detail: Chest primary; Triceps, Front delts secondary — **satisfied** · `test/exercise_detail_muscle_groups_test.dart` · 'bench press shows Primary Chest and Secondary Triceps / Front delts' (both `ExerciseDetailViewScreen` and `ExerciseLibraryDetailScreen`).
5. Tennis detail: "Legs" under Primary as the region-level tag — **satisfied** · same file · 'tennis match shows Primary Legs / Shoulders / Core and no secondary row'.
6. No seed entry links a region next to its own muscle; no known-mover lift region-tagged — **satisfied** · `test/catalog_referential_integrity_test.dart` · 'S-3: no entry links a region next to one of its own muscles' and 'S-3: only the twelve region-tagged exercises carry a region' (the allowed set is the sports entries, not the lifts).
7. Migration: [Legs, Quadriceps] → Quadriceps only; [Chest, Triceps] → both primary — **satisfied** · `test/data_migration_test.dart` · S-8 group ('the step rewrites every old-shape row', fixtures `_s8OldShape`/`_s8Normalised`, run on Mock and Hive).
8. User copy keeps its tagging through the refresh; the catalog original gets the new tagging — **satisfied** · `test/catalog_refresh_test.dart` · 'S-MH-1: refresh from v10 lands the taxonomy parents, the Traps rename and role-aware links, and leaves custom / copy / touched rows alone' (copy keeps `SeedData.exerciseMuscleLinks['exercise-barbell-squat']`).
9. Quadriceps after Legs leaves only Quadriceps — **satisfied** · `test/muscle_selection_test.dart` · 'a muscle gaining a role removes its region's own entry'; screen level: `test/muscle_editor_screen_test.dart` · 'shows the stored roles and saves the tapped change'.
10. Secondary-only save blocked with a visible message; empty save succeeds — **satisfied** · `test/muscle_editor_screen_test.dart` · 'an assists-only selection is blocked and creates nothing' (asserts the message 'Pick at least one main muscle.') and 'saving with nothing chosen succeeds with no links'.
11. No muscle-based number changes — **satisfied** · grep over `lib/features/stats` for `muscle` → no matches; `lib/state` and `lib/core/services` muscle mentions are the links API and seed/refresh plumbing, no calculation; `gateway.sh git-diff --stat 1ca3b41 -- lib/features/stats lib/features/session lib/watch watch` → empty (untouched from before PR 1 through the working tree; the gateway refuses two refs, so one ref against the working tree covers HEAD + tree).
12. Deferred-changes entry removed; data model docs describe hierarchy and roles — **satisfied** · `docs/future-work.md` diff; `docs/data_models.md` interpretation-rules and new display-rules sections with citations.

Original-brief sections "Tagging rules" and "How the hierarchy is interpreted everywhere": the brief text itself is not in the repository (grep for both headings → no matches), so a clause-by-clause guard mapping is **not verifiable from the repo**. The closest guarded equivalents: normalisation/tagging rules → `test/muscle_taxonomy_test.dart` (`normalize drops the region that sits next to its own muscle`, role/throw tests) and `test/muscle_links_storage_test.dart`; interpretation everywhere (filter, ranking, display) → `test/muscle_filter_test.dart`, `test/muscle_selection_test.dart`, `test/muscle_display_test.dart`, `test/muscle_filter_picker_test.dart`, `test/exercise_detail_muscle_groups_test.dart`.
