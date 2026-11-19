# Review: 118 — 17 conditioning and plyometric exercises under a new "Conditioning" discipline · Phases 1, 2A, 2B, 3 · ecf2d050..working tree

Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: not run — the brief says the lead is running the full suite; `flutter analyze` 181 = baseline (lead's record). The D-19214 boundary diff printed nothing (run this review, exit 0).

Diff vs Predicted Files: conforms. The 11 changed files are exactly the phases' Predicted Files plus `test/helpers/conditioning_catalog_rows.dart`, which A-118-1 names (the shared helper list that replaced the plan's `_conditioningAdded` const). The evidence file sits in the untracked plan folder, so it cannot appear in `git diff`. `docs/state_management/watch_reference_data.md` is unchanged, as Phase 3 item 6 predicts.

## Findings

1. [Minor] `test/conditioning_catalog_refresh_test.dart:575-605` — S-19206's plan expectation "A second `refresh()` returns false, and everything above is unchanged" is asserted only through the muscle links of the watched ids; the customs' `toMap()`, capabilities, the copy's map and the touched row's name are not re-compared after the second refresh. A future refresh that returned false but still rewrote names or capabilities would pass. The exposure is small (returning false gates every leg), so Minor. Fix: after the second refresh, re-assert `customBefore`/`customCapsBefore`/`copyBefore` and the push-up name. Guard: the existing S-19206 test.

No blocker or major: all 17 seed rows, the discipline row, the version bump, the SQL insert and every scenario assertion were read against the plan (details under the questions below).

## Answers to the brief's questions

**Q1 — the 17 texts (`lib/mock/seed_data.dart:5080-5362`) against D-18907 and D-19204.** All conform. Every description is one or two plain sentences naming the movement and the main muscles; every `howToSteps` is 3 or 4 imperative sentences covering setup, movement and return; no brand names; nothing unsafe or anatomically wrong (Box Jump steps down one foot at a time; Medicine Ball Slam says to use a non-bouncing ball and to squat to pick the ball up; Plyo Push-Up lands on bent arms; Thruster sets the elbows in front of the bar). D-19204's required sentences are all present: Burpee chest-touch + finishing jump (:5084-5085); Squat Thrust "no push-up and no jump" (:5100); Box Jump step-down (:5124); Plyo Push-Up hands leave the floor (:5216-5217, :5223); Bear Crawl knees hover (:5251); Battle Ropes alternating waves (:5301, :5306); Wall Ball target high on a wall, caught into the next squat (:5333-5334); Thruster one motion (:5350); Medicine Ball Slam non-bouncing ball (:5318). The four timed moves end with "Count reps, or log it by time.": Mountain Climber (:5234-5235), Jumping Jack (:5269), High Knees (:5285-5286), Battle Ropes (:5302).

**Q2 — the four seed lists vs the New-row table.** No mismatch. All 17 `Exercise` blocks carry the tabled `movementPattern` (null for rows 1, 2, 11, 12, 13, 14, 15; squat/lunge/horizontal_push/abs as tabled). `exerciseMuscleLinks` (:6056-6072), `exerciseEquipmentRelationships` (:6360-6376) and `exerciseCapabilityRelationships` (:6807-6823) match the table row for row: P/S sets, `[]` for Box Jump, Battle Ropes, Medicine Ball Slam and Wall Ball, `equipment-bodyweight` elsewhere, `equipment-barbell` for Thruster, BW caps on rows 1–14 and `load` on rows 15–17 only. The test-side mirror `test/helpers/conditioning_catalog_rows.dart` matches the table too, and `expectConditioningRowMatchesPlan` asserts the shipped row against it, including the region/forbidden-muscle tagging guard.

**Q3 — boundary and Predicted Files.** `git-diff --stat -- lib/features lib/widgets lib/state lib/core/services lib/core/utils lib/data lib/watch watch lib/core/constants/data_version.dart scripts/sqlite_schema.sql` printed nothing. The full diff vs ecf2d050 is the 11 files listed above; see "Diff vs Predicted Files". The discipline row sits directly after `discipline-calisthenics` (`seed_data.dart:126-137`) with `category-resistance` / `conditioning` / `Conditioning`; `bundledCatalogVersion` is 18 with the D-19207 history sentence; `sqlite_seed.sql:273-276` adds the one guarded insert after the calisthenics insert. D-19209's arithmetic holds: `buildExercisesDown` batches at `batchSize = 100` (`watch_reference_sync.dart:222,246`), so 339 capable rows are 4 batches.

**Q4 — `test/conditioning_catalog_refresh_test.dart` quality.** Every assertion of S-19205, S-19206 and S-19207 is present, in plan order, over both harnesses via `harnessFactories` with plain `test()`. S-19205: the three customs, the discipline fields, 70/80 per row, the below-50 ordering, the Bear-Crawl-before-Box-Jump tie, the discipline filter as a set with the customs excluded, Cardio 15/5, Chest/Core/Calves/Lats/Shoulders filters (Core over both `muscle-core` and `muscle-abs`, each id exactly once), the Burpee name search with the near-twins, and the Thruster/Box-Jump equipment. S-19206: staged missing discipline, all 17 rows removed (equipment box on Hive), recorded customs, the renamed touched push-up with a tombstone, the Kettlebell Swing copy, the literal version 17, refresh true, version == bundled and >= 18, the discipline restored, per-row name/discipline/capabilities/links (multiset via toSet + length), the untouched user rows, the search finding both Plyo Push-Ups, burpee at 70.0, the Hive-only empty Thruster equipment, and the second refresh returning false. S-19207: rows present with the discipline missing, 30.0/40.0 before, the filter still returning the 17, and 70.0/80.0 after. The Mock/Hive split matches the plan: the equipment-empty line is `if (harness.name == 'Hive')` only; everything else runs on both. Nothing vacuous: every expectation compares a concrete value or would throw on a missing row (`position[id]!`, `rows.single`); the multiset checks pair `toSet` equality with a length assert. Symbols the file relies on exist: `ExerciseCapabilities.copyWith` (`exercise_helpers.dart:38`), `MockWorkoutRepository.deleteReferenceRowForTest` (`mock_workout_repository.dart:1021`), `searchExercises(disciplineId:)` (`workout_repository.dart:16`), `healthActivityOf({disciplineId, exerciseId, capabilities})` (`watch_reference_sync.dart:499`).

**Q5 — the two doc edits.** Both state only what the named tests assert. `docs/db_integration.md` (version-18 paragraph): the refresh outcome is S-19206/S-19207's asserted 30→70 / 40→80 ranking and untouched user rows; the SQL sentence cites the exact existing test title `S-19203 app_discipline carries Conditioning under resistance_lifting` in `test/db_seed_test.dart`; "equipment links reach new installs only" is S-19205's fresh-install Barbell plus S-19206's Hive-only empty check. "Gets it before the exercises" is the D-19106 leg order; the testable outcome it claims (the rows rank with their discipline after the refresh) is what S-19207 asserts. `docs/constants_reference.md`: the value cell is `17` → `18`, matching `catalog_version.dart` and S-19206's `greaterThanOrEqualTo(18)` pin. Doc sizes were not measured this run (no size check available to the reviewer); `docs_indexing_contract_test.dart` guards them and is in every phase's Done Criteria.

## Assumption Log rulings

- Phase 1, "five watch files but names four": **ratify** — D-19209 and S-19208 name four files; the plan's "five" is the typo.
- Phase 1, `disciplinesForModality` order: **ratify** — the S-19201 test asserts the five-id list I read in the plan.
- Phase 1, S-19201's vacuous-while-absent red run: **ratify** — the "no other row shares its key or name" test passes when the row is absent; the recorded `+1 -4` is the honest red count.
- Phase 1, gateway `--plain-name` not forwarded: **ratify** as a process record; not re-verifiable in this run.
- Phase 2A, A-118-1 (shared helper list instead of `_conditioningAdded`): **ratify** — both size guards and the row tests read `conditioningCatalogRows`.
- Phase 2A, "no exact Main Chest / Core set exists": **ratify** — the referential-integrity diff adds `containsAll` for Chest and abs and exact sets only where they already existed.
- Phase 2A/2B red-run counts and the one-row red mutation: **ratify** as process records; the lead's eight mutations (M1–M6, M8, M9) are the review-grade red evidence.
- Phase 2B, Battle Ropes carrying the BW list: **ratify** — it is the plan table's row 14.
- Phase 2B, Core over `muscle-core` and `muscle-abs`: **ratify** — the refresh test runs both groups.
- Phase 3, the blocked red table (write scope): **ratify** — covered by the lead's mutations M1 (version 17), M2 (row removed), M3 (refresh skips disciplines), M4 (ranking ignores the stored discipline), which are exactly items 4(a)–(c) plus M4.
- Phase 3, `searchExercises(muscleGroupIds:)` shape: **ratify** — seen in the test.
- Phase 3, ranking split derived from the helper and asserted over outer positions: **ratify** — seen in the test; the per-row 70/80 loop covers each row individually anyway.
- Phase 3, `copyWith` from the `ExerciseCapabilities` extension: **ratify** — `exercise_helpers.dart:38`.
- Phase 3, "S-19207's refreshed thruster has no equipment is Hive-only": **ratify with a correction** — that assertion lives in S-19206, not S-19207; S-19207 asserts no equipment claim.

## Scenario coverage

- S-19201 → `test/conditioning_catalog_test.dart` · the five tests of group "S-19201 the Conditioning discipline row"
- S-19202 → `test/conditioning_catalog_test.dart` · group "S-19202 the conditioning rows" (17 per-row tests + filter, uniqueness, id-order) and `test/strength_catalog_gaps_test.dart` · "catalog sizes"
- S-19203 → `test/db_seed_test.dart` · `S-19203 app_discipline carries Conditioning under resistance_lifting`
- S-19204 → `test/catalog_referential_integrity_test.dart` · link-map lengths at both sites, Main/Assisting Calves sets, Lats/Chest/abs containment
- S-19205 → `test/conditioning_catalog_refresh_test.dart` · `S-19205 a fresh install ranks and filters the 17`
- S-19206 → `test/conditioning_catalog_refresh_test.dart` · `S-19206 a v17 install refreshes`
- S-19207 → `test/conditioning_catalog_refresh_test.dart` · `S-19207 an exercise whose discipline is missing`
- S-19208 → guard only; the four watch files run unedited (builder recorded them green at Phase 2B; the lead's full suite re-runs them)
- S-19209 → `test/conditioning_catalog_test.dart` · group "S-19209 no Health kind for the conditioning rows"

Input-reality: the feature reads only the bundled seed and the stored catalog version; the writers are `SeedData` (first install) and `CatalogRefreshService` (update), both exercised by S-19205/S-19206; user-owned rows, copies and touched rows are covered by S-19206's recordings; no setting, clock or competition dependency is introduced.

## Docs delta

| Doc | Change | Status |
|---|---|---|
| `docs/db_integration.md` | ADDED (version-18 paragraph) | applied |
| `docs/constants_reference.md` | ADDED (version cell `17` → `18`) | applied |

No doc edit outside the table appears in the diff.

## Summary

The change is exactly the plan: one discipline row, 17 conforming seed rows across the four lists, version 18 with its history sentence, one guarded SQL insert, and tests that carry every scenario assertion on both harnesses. One minor coverage gap on the second-refresh no-op; approve.

