# 117 — Retire the orphan template rows (seed lists + one-time cleanup)

> Status: Iteration 1 ready. Written by the lead (not conductor-v2) because it is a follow-up of plan 116 (`docs/plans/2026-11-04-116-catalog-delivery-plan/`), small, and fully specified by the owner decision below.
> Owner decision (relayed by the main session, 2026-11-05): "remove them if they are truly dead." Uncommitted, same working tree as plan 116.
> Track: phone only. Never branch, never commit.

## Overview

The first-install seed writes 4 template segments, 6 efforts and 5 targets (`SeedData.sampleTemplateSegments`, `sampleTemplateEfforts`, `sampleTemplateTargets`, `lib/mock/seed_data.dart` ~6095-6247) that belong to four templates nothing creates: `template-upper-strength`, `template-easy-run`, `template-boxing-rounds`, `template-mobility`. Plan 116 classified them EXCLUDED (orphans). This plan (a) stops seeding them and (b) removes them once from phones that already hold them. A user sees nothing: no screen can reach a row without its template.

**Dead-code audit (lead, 2026-11-04, re-run before this plan):** readers of the three lists: only `HiveWorkoutRepository._seedData` (:650-663), `MockWorkoutRepository.initialize` (:189-203) and the plan-116 contract test. Readers of the three Hive boxes (`template_segments`, `template_efforts`, `template_targets`): all repository methods look rows up by parent id (`getTemplateSegments(templateId)`, `getTemplateEfforts(segmentId)`, `getTemplateTargets(effortId)`), the cascades (`deleteTemplate`, `deleteTemplateSegment`, `deleteTemplateEffort`, `deleteTemplateTargetsForEffort`), the revision listeners (:279-281, counters only) and `clear` (:2728-2730). No export, stats, sync or screen iterates all rows. No file outside the seed, both repositories and the contract test mentions the retired ids (`grep -rnE` over lib, test, scripts, watch, ios, docs, excluding plans/history/releases and `seed_data.dart`: only the `demo-template-*` / `demo-tseg-*` / `demo-teff-*` ids of the demo routines, which are different ids). `scripts/sqlite_seed.sql` does not carry them.

## Resolved Decisions

- **D-19201 Cleanup is a data migration, not part of the refresh.** Append step `17 retireOrphanTemplateRows` to the Hive and Mock `_dataMigrationSteps()` and set `currentDataVersion = 17` (`lib/core/constants/data_version.dart`). This is a deliberate exception to the refresh's "never delete" rule; the docs say so.
- **D-19202 Exact ids, parent chain, bottom-up.** The retired ids live in one place, `lib/core/constants/retired_template_seed.dart`, class `RetiredTemplateSeed`:
  - `segmentTemplate`: `tseg-upper-1`→`template-upper-strength`, `tseg-run-1`→`template-easy-run`, `tseg-boxing-1`→`template-boxing-rounds`, `tseg-mobility-1`→`template-mobility`
  - `effortSegment`: `teff-upper-bench`, `teff-upper-ohp`, `teff-upper-row`→`tseg-upper-1`; `teff-run-main`→`tseg-run-1`; `teff-boxing-bag`→`tseg-boxing-1`; `teff-mobility-stretch`→`tseg-mobility-1`
  - `targetEffort`: `ttar-bench-sets`→`teff-upper-bench`; `ttar-run-duration`→`teff-run-main`; `ttar-boxing-rounds`, `ttar-boxing-duration`→`teff-boxing-bag`; `ttar-stretch-duration`→`teff-mobility-stretch`
- **D-19203 The rule (belt and braces).** A row is deleted only if (a) its id is in the retired map AND (b) the retired parent template of its chain does not exist in storage (`getTemplateById(parentTemplateId) == null`). Nothing else is deleted. Implemented ONCE in a core service `RetiredTemplateRowsCleanup` (`lib/core/services/retired_template_rows_cleanup.dart`) that depends on the `WorkoutRepository` interface only, so Mock and Hive run the same code: for each retired template id `T` where `getTemplateById(T) == null`: for each segment `s` in `getTemplateSegments(T)` whose id is retired and maps to `T`: for each effort `e` in `getTemplateEfforts(s.id)` whose id is retired and maps to `s.id`: delete each target `t` in `getTemplateTargets(e.id)` whose id is retired and maps to `e.id` (`deleteTemplateTarget`), then if no target remains delete `e` (`deleteTemplateEffort`); then if no effort remains under `s` delete `s` (`deleteTemplateSegment`). A segment or effort that still holds a row the cleanup did not delete (a user's own) is kept. No new repository method.
- **D-19204 Interruption and idempotency.** Deletion goes bottom-up (targets, efforts, segments) so the parent chain is intact at every point; the migration service does not advance `data_version` on a throw, the next launch re-runs, a second run finds nothing and writes nothing.
- **D-19205 Stop seeding.** Remove `sampleTemplateSegments`, `sampleTemplateEfforts`, `sampleTemplateTargets` from `SeedData`, the three `putAll` blocks in `HiveWorkoutRepository._seedData` and the three loops in `MockWorkoutRepository.initialize`. A fresh install never creates them. Step 2 `seedData` still runs on a fresh install and writes none.
- **D-19206 Contract test.** Remove the three EXCLUDED rows and the "orphan" reason from `test/catalog_delivery_contract_test.dart`; the member count becomes 21 (11 COVERED + 10 EXCLUDED); update every place that says 24/13.
- **D-19207 Docs.** `docs/db_integration.md` (the data-migration section and the "most recent step" sentences at ~250 and ~679), `docs/constants_reference.md` (`currentDataVersion` row 16→17, `retired_template_seed.dart`), and the catalog sentence that lists the orphan rows if any. Say: this is a migration, a deliberate exception to the refresh's never-delete rule, exact-id and parent-missing guarded.
- **D-19208 Tests that pin version 16** (`test/data_migration_test.dart` S-156 and S-8 sequence tests, lines ~549-566, ~729-731, ~775) are updated to expect 17 / `retireOrphanTemplateRows` as the last step.

## Scenarios (new file `test/retire_orphan_template_rows_test.dart`, Mock and Hive via `harnessFactories`, plain `test()`, rows staged through the public `createTemplate*` methods with ids from `RetiredTemplateSeed`; the step is run through `dataMigrationStepsForTest().firstWhere(name == 'retireOrphanTemplateRows').run()`)

- **S-19201 orphans are removed.** Stage the full retired set (4 segments, 6 efforts, 5 targets, no parent templates). Run the step. All 15 rows are gone (`getTemplateSegments(T)`, `getTemplateEfforts`, `getTemplateTargets` empty for every retired parent). Fails without the change: the step does not exist.
- **S-19202 user routine untouched.** A user template `tpl-user` with segment `seg-user` (id not retired), effort `eff-user`, target `tar-user`, plus the orphan set. After the step the user rows are identical (`toMap()`) and the orphans are gone.
- **S-19203 retired id with a live parent is kept.** Create `template-easy-run` as a real template (a user happens to hold it) with `tseg-run-1`, `teff-run-main`, `ttar-run-duration`, and also the other orphans. After the step the easy-run rows are all still there; the other orphans are gone.
- **S-19204 a user row under a retired segment keeps it.** `tseg-upper-1` (parent missing) holds a retired effort and a user effort `eff-user-under-retired`. After the step the retired effort and its targets are gone, the segment and the user effort remain.
- **S-19205 second run is a no-op and a fresh install creates none.** Run twice; the second run changes nothing (a counting Mock subclass records no delete call on the second run). A freshly initialised store holds none of the 15 ids (`getTemplateSegments` of the four retired templates empty).
- **S-19206 interrupted run retries.** Mock-only: a subclass whose `deleteTemplateEffort` throws on the first call while failing; the step throws; the `tseg-*` row is still present (bottom-up); with failing off the step completes and everything retired is gone.
- **S-19207 version sequence.** `currentDataVersion == 17`; both stores' last step is `17:retireOrphanTemplateRows`; sequences identical; an install staged at data version 16 with orphans runs the real `DataMigrationService` and lands at 17 with the orphans gone (Hive via the `harness.restart()` path if simple, else Mock only; say which).
- **S-19208 contract test** counts 21 members; none of the three lists exists in `SeedData` (the existing parsing test fails if one is re-added without a table row).

## Phases

### Phase 1 (`crew-builder-app`, writes `lib/core/**`): constants, service, step 17 (about 110 production lines)
1. `lib/core/constants/retired_template_seed.dart` (D-19202), exact text in the brief.
2. `lib/core/services/retired_template_rows_cleanup.dart` (D-19203/D-19204).
3. `currentDataVersion = 17`; step in Hive `_dataMigrationSteps()` and Mock `_dataMigrationSteps()` (needs `crew-builder-data`; separate run).
Done: `flutter test test/data_migration_test.dart` updated and green; `flutter analyze` ≤ 181.

### Phase 2 (`crew-builder-data`): seed removal, tests (about -150 production lines)
Remove the three lists and their seeding (D-19205); write the scenarios; update the contract test (D-19206) and the data-migration tests (D-19208).

### Phase 3 (docs keeper) and review (narrow).

## Progress
- [ ] Phase 1 · [ ] Phase 2 · [ ] Phase 3 · [ ] review

## Assumption Log

## Feedback
