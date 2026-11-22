# DB Integration

## Overview

OmniTrain uses a repository-first persistence architecture:

- Runtime app persistence: `HiveWorkoutRepository` (web and current cross-platform runtime)
- SQL schema assets: maintained in `scripts/` for SQLite parity work
- Single abstraction contract: `WorkoutRepository`

This document explains how to validate DB assets and how profile-related persistence is represented in both Hive runtime and SQL assets.

---

## Key Files

- `lib/data/repositories/workout_repository.dart`
- `lib/data/repositories/hive_workout_repository.dart`
- `lib/data/repositories/mock_workout_repository.dart`
- `lib/data/datasources/food_catalog_loader.dart`
- `scripts/sqlite_schema.sql`
- `scripts/sqlite_seed.sql`
- `test/db_seed_test.dart`

---

## Repository Contract

`WorkoutRepository` now includes profile and measurement APIs:

- `getProfile()`
- `saveProfile(UserProfile profile)`
- `getMeasurementHistory(String measurementType)`
- `getLatestMeasurement(String measurementType)`
- `saveMeasurementEntry(BodyMeasurementEntry entry)`
- `deleteMeasurementEntry(String entryId)`
- `updateSessionFeeling(String sessionId, int feeling)`

Active session persistence API:

- `getInProgressSessions()`
  - Returns sessions where `endedAtMs == null`
  - Sorted by `startedAtMs` descending (most recent first)
  - Hive implementation skips malformed records with per-row try/catch (no throw)

Bulk per-effort read:

- `getRoundInstancesByEffort()`
  - The bulk counterpart to `getRoundInstances(effortId)`: every round instance on the
    device, grouped by `effortId`, each group in `roundIndex` order.
  - An effort with no instances has no key, rather than an empty list.
  - Verified by `test/round_instances_by_effort_test.dart` (S-901, S-902).

Bulk per-session read:

- `getSensorSummariesBySession()`
  - Every `SensorSummary` on the device, grouped by `sessionId`, each group in the same
    order `getSensorSummariesForSession(sessionId)` returns: scope in
    `SensorSummary.scopes` order, then `windowStartMs`, then `targetId`. Both reads sort
    through one comparator per implementation, so the two orders cannot drift.
  - A session with no summaries has no key, rather than an empty list.
  - `MockWorkoutRepository` mirrors `HiveWorkoutRepository` value for value.
  - The read adds no schema or seed requirement: it groups rows already stored, so
    `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` need no change to
    serve it, and `test/db_seed_test.dart` executes both as SQL.
  - Verified by `test/sensor_summaries_by_session_test.dart` (S-1002, S-1003, S-1004).

Any repository implementation must satisfy this full contract and remain compile-safe.

Deterministic active-session ordering contract:

- Top-level sequence is persisted explicitly (not inferred from timestamps).
- `SessionBlock.topLevelOrderIndex` and `SegmentEffort.topLevelOrderIndex` are the canonical keys for mixed block + standalone ordering.
- `SegmentEffort.blockOrderIndex` is the canonical key for effort order inside a block.
- `assignEffortToBlock()` appends to block tail by `blockOrderIndex` without mutating unrelated top-level items.
- `cloneSessionBlock()` appends the cloned block to the end of top-level order and preserves source intra-block effort order exactly.

---

## Hive Runtime Persistence

`HiveWorkoutRepository` now opens profile-specific boxes during `initialize()`:

- `user_profile`
- `body_measurements`

Behavior:

- Profiles are saved by profile id.
- Measurement entries are saved by entry id.
- Measurement history is filtered by `measurementType` and sorted `recordedAtMs` descending.
- Latest measurement is derived from sorted history.

Session persistence behavior:

- `getInProgressSessions()` scans `sessions` box values.
- Parse failures for malformed rows are caught and skipped; valid rows still return.
- Returned list is sorted desc by `startedAtMs`.

Ordering persistence behavior:

- `createSessionBlock()` assigns `topLevelOrderIndex` when missing.
- `createEffort()` assigns canonical order metadata for standalone vs block effort placement.
- `getSessionBlocks()` and `getSegmentEfforts()` return deterministic order based on canonical order columns with stable tie-breakers.

### Catalog version + seed-entry tombstones (July 2026)

The bundled app-authored catalog (exercises + capability / muscle-group
relationships + the food catalog + seeded demo workout templates) is
versioned. From catalog version `16` the refresh also delivers sport categories,
disciplines, units, metric definitions, metric effort kinds and tags: a stored
row that differs from the bundled one in a compared field is corrected,
timestamps are never compared, and rows whose id is not bundled are never
written (the tags leg lists the stored tags once and ignores ids the bundle
does not carry). Verified by `test/catalog_reference_refresh_test.dart`
(`S-19102 a v15 install missing reference rows refreshes to v16`,
`S-19103 user rows that share a name or key stay byte-identical`,
`S-19106 Mock: an interrupted refresh keeps version 15 and the next
launch finishes`). Equipment,
equipment links and the default food groups are written at first install only
(equipment pinned by `test/strength_catalog_refresh_test.dart`, `S-18906`;
food groups because users can delete them and no marker exists). Every public
`SeedData` member is classified as delivered or excluded with a written reason
by `test/catalog_delivery_contract_test.dart`, so a new seed list that the
refresh does not carry fails a test. At app start, `CatalogRefreshService`
(`lib/core/services/catalog_refresh_service.dart`) compares the device's
stored catalog version against the bundled constant
(`bundledCatalogVersion` in `lib/core/constants/catalog_version.dart`); if
the bundled version is newer, the refresh re-applies new / changed seed
entries to the device in place, never touching user-created entries and
never overwriting a seed entry the user has edited.

The refresh also carries the muscle hierarchy: `_refreshMuscleGroups`
upserts a group that is missing or whose name or `parentId` differs from the
bundled taxonomy, and `_refreshExerciseMuscleGroups` rewrites an untouched
exercise's links when they differ from the bundled ones, roles included and
order-insensitively. Verified by `test/catalog_refresh_test.dart`
(`S-MH-1: refresh from v10 lands the taxonomy parents, the Traps rename and
role-aware links, and leaves custom / copy / touched rows alone`). The
bundled version that ships the hierarchy is `11` (`bundledCatalogVersion`,
`lib/core/constants/catalog_version.dart`). Catalog version `13` adds the Shins
muscle (`muscle-tibialis`, under Legs) and moves the bundled Tibialis Raise to
it from Calves; a Tibialis Raise the user has edited keeps its muscles.
Verified by `test/tibialis_muscle_refresh_test.dart` (`S-18805 a v12 install
refreshes to v13`, `S-18806 a user-edited Tibialis Raise keeps its muscles`).
Catalog version `14` adds the Brachialis, Rotator cuff and Abductors muscles,
re-tags Cable Hip Abduction, Cable External Rotation and Hammer Curl, and adds
28 strength exercises; exercises the user edited or copied, and the user's own
exercises (including one with the same name as a new bundled one), are never
rewritten. Verified by `test/strength_catalog_refresh_test.dart` (`S-18906 a v13
install refreshes to v14`, `S-18907 a user-edited row keeps its muscles`).
Catalog version `15` adds 20 core, leg/hip and press exercises (Sit-Up through
Sled Drag); exercises the user edited or copied, a user's own exercise with a new
bundled name, and a bundled row the user renamed to a new name are never
rewritten. Verified by `test/strength_catalog_v15_refresh_test.dart` (`S-19006 a
v14 install refreshes to v15`, `S-19007 a renamed touched row and near-twins
keep their own`). The Trap Bar and Sled equipment rows reach new installs only
(`S-19008 a new install knows the equipment`).
Catalog version `17` adds 22 yoga poses under the Yoga discipline and moves
Pigeon Pose and Child's Pose into it from Stretching; the user's own, copied,
edited and renamed rows are never rewritten. Verified by
`test/yoga_catalog_refresh_test.dart` (`S-19304 a version-P install refreshes`,
`S-19305 a renamed touched row and near-twins keep their own`); the equipment
links reach new installs only (`S-19307`). A phone workout whose exercised rows
are all Yoga records as Yoga (`S-19311`, `test/health_yoga_kind_test.dart`).
Catalog version `18` adds the Conditioning discipline and 17 conditioning and
plyometric exercises (Burpee through Thruster). A phone missing the discipline
gets it before the exercises, so they rank with their discipline; the user's
own, copied, edited and renamed rows are never rewritten. Verified by
`test/conditioning_catalog_refresh_test.dart` (`S-19206 a v17 install
refreshes`, `S-19207 an exercise whose discipline is missing`) and, for the SQL
contract, `S-19203 app_discipline carries Conditioning under resistance_lifting`
in `test/db_seed_test.dart`. The equipment links reach new installs only.

`SeedEntryType` enumerates the tombstone key spaces the refresh understands:

| Constant | Tombstone space | Notes |
|---|---|---|
| `SeedEntryType.exercise` | `seed_entry_touched_exercise_<exerciseId>` | Bundled exercises. |
| `SeedEntryType.foodCatalog` | `seed_entry_touched_food_catalog_<foodId>` | Bundled food-catalog rows. |
| `SeedEntryType.routineTemplate` | `seed_entry_touched_routine_template_<demoTemplateId>` | Bundled demo routines (the `Demo`-tagged routines delivered through the catalog refresh; version bumped to `3` to ship the initial set). |

The repository exposes four small methods used by the refresh orchestrator
and by the state layer:

| Method | Purpose |
|---|---|
| `getCatalogVersion({defaultValue})` | Reads the device's stored catalog version. Returns `0` for legacy installs (no prior refresh). |
| `setCatalogVersion(int)` | Persists the device's catalog version. Called once, at the end of a successful refresh. |
| `isSeedEntryTouched(type, id)` | Returns `true` if the user has ever mutated the seed entry at `(type, id)`. |
| `markSeedEntryTouched(type, id)` | Tombstone setter. Called by the state layer whenever the user edits / archives / deletes a seed entry. Idempotent. |

Storage shape:

- Hive: the meta box holds `catalog_version` (int) and a `bool` per
  tombstone under the key `seed_entry_touched_<type>_<id>`.
- Mock: in-memory `int _catalogVersion` (default `0`) and
  `Map<String, bool> _seedEntryTouched` keyed by `<type>_<id>`.
- SQLite parity: see the "CATALOG VERSION + SEED-ENTRY TOMBSTONES
  (July 2026)" block at the bottom of `scripts/sqlite_schema.sql`. The
  future `SqliteWorkoutRepository` is expected to use a single
  `app_meta` key/value table for both the version and the tombstones,
  keeping the orchestrator code identical across runtimes.

Idempotency + interruption safety:

- The refresh writes each entry individually (no clear-then-repopulate).
- On any error mid-refresh, the stored version is NOT advanced; the next
  launch retries from where it left off with the prior data still intact.
- Running the refresh twice yields identical state: the second pass is a
  no-op (stored version already at or above the bundled version).

### Data-migration version sequence (July 2026)

OmniTrain consolidates thirteen previously-independent one-time migration
steps (`seed_loaded`, `seed_units_migrated_v1`, …) into a single ordered
update sequence tracked by the device's `data_version` integer (see
[`lib/core/constants/data_version.dart`](../lib/core/constants/data_version.dart)
and [`DataMigrationService`](../lib/core/services/data_migration_service.dart)).
On startup, `HiveWorkoutRepository.initialize()` runs the service:

1. Reads the device's `data_version` (default `1`).
2. **Back-compat shim** — when `data_version == 1` AND any legacy one-shot
   marker is present, the shim maps the highest legacy marker to a
   starting version and writes it back. Existing installs land at the
   correct starting point in one launch; already-applied steps are not
   re-run.
3. Runs every pending step in ascending `targetVersion` order. After each
   step succeeds, `data_version` is advanced to the step's target. A
   failing step does NOT advance past itself; the next launch retries
   from that step.
4. Records the most recent `from → to` transition in the meta box for
   diagnostics.

The shim maps the highest legacy marker present to its implied version, because the legacy code
always ran the steps in order. The mapping lives in
[`lib/core/constants/data_version.dart`](../lib/core/constants/data_version.dart).

Repository methods used by the service:

| Method | Purpose |
|---|---|
| `getDataVersion({defaultValue})` | Reads the device's stored version. |
| `setDataVersion(int)` | Persists the device's version after each step. |
| `getLegacyAppliedDataVersion()` | Back-compat shim: returns the highest version implied by any legacy marker (`1` if none). |
| `getLastDataVersionTransition()` | Diagnostic: most recent `(from, to)` transition, or `null`. |
| `setLastDataVersionTransition(int from, int to)` | Diagnostic: records a transition. |
| `referenceRevision` | Null on the Mock; a counter on Hive that changes when any food, routine or exercise row is written. The watch sync reads it to skip re-reading storage. |
| `historyRevision` | Null on the Mock; a counter on Hive that changes when any session, segment, effort or observation row is written. The watch sync reads it to skip re-reading history for the bests: the same contract as `referenceRevision` — a number that differs whenever a row was written, compared for equality only, `null` meaning the repository cannot tell, so the caller must read. Pinned by `test/repository_reference_revision_test.dart` (group `S-87c-15 Hive: the four history boxes move the number`, tests `S-87c-15 session, segment, effort and observation writes move it` and `S-87c-15 timed instances, foods and exercises leave it alone`). |

Storage shape (Hive runtime; SQL parity noted for the future importer):

| Hive meta-box key | Type | Semantics |
|---|---|---|
| `data_version` | int | Current data-migration version; `1` on legacy installs not yet mapped by the shim. |
| `data_version_last_from` | int | Starting version of the most recent migration run (diagnostic). |
| `data_version_last_to` | int | Ending version of the most recent migration run (diagnostic). |

Adding a new step: append a row to `HiveWorkoutRepository._dataMigrationSteps()`
and bump `currentDataVersion` in
[`lib/core/constants/data_version.dart`](../lib/core/constants/data_version.dart).
The next launch runs the new step exactly once per device. No new meta-box
key is required for the step itself.

Step 17 is `retireOrphanTemplateRows` (target version 17): it
runs once per device and removes the retired first-install template rows —
4 segments, 6 efforts and 5 targets, ids in
[`lib/core/constants/retired_template_seed.dart`](../lib/core/constants/retired_template_seed.dart) —
that belonged to four templates nothing creates (`template-upper-strength`,
`template-easy-run`, `template-boxing-rounds`, `template-mobility`). A row is
deleted only if its id is one of the retired ids AND its retired template does
not exist; a segment or effort that still holds a row the cleanup did not
delete is kept; deletion is bottom-up, so an interrupted run retries cleanly.
The logic is `RetiredTemplateRowsCleanup`
([`lib/core/services/retired_template_rows_cleanup.dart`](../lib/core/services/retired_template_rows_cleanup.dart)),
shared by both stores. New installs no longer create those rows (the
`SeedData` lists were removed). This is a data migration, NOT part of the
catalog refresh, and a deliberate exception to the refresh's never-delete
rule: it is safe because it deletes only rows whose exact id is in the retired
list and whose parent template is gone. Nothing a user can see changes.
Verified by `test/retire_orphan_template_rows_test.dart`.

**Step 18 `backfillRoutineSessionModality` — ONE-OFF (plan 122) — retire after launch.** Runs once per device: for every past session with `intent == 'routine'`, no modality, and a `routineTemplateId` whose routine still exists and has a Focus, it writes that Focus into the session's `modality` (only that field; `updated_at_ms` and every other field unchanged). In-progress sessions are included; planned (calendar) entries are never read or written; a routine that was deleted, or has no Focus, leaves its sessions untouched. The Focus used is the routine's value at update time. Rows are written one at a time and a failure leaves `data_version` at 17, so the next launch retries; stamped rows no longer match, so a rerun writes nothing. The logic is `RoutineSessionModalityBackfill` ([`lib/core/services/routine_session_modality_backfill.dart`](../lib/core/services/routine_session_modality_backfill.dart)), shared by both stores. Retirement (not yet done): replace the step's run body in both repositories with a no-op that keeps version 18 and the name, delete the service and `test/routine_session_modality_backfill_test.dart`, update this section; never renumber or remove a version. Verified by tests S-12207, S-12210..S-12216 in `test/routine_session_modality_backfill_test.dart`.

**Step 21 `mergeDuplicateFoodGroups` — ONE-OFF (plan 303) — retire after launch.** Runs once per device. For every set of active food categories whose names match (trimmed, case-insensitive) it keeps the shipped category when the set holds one, otherwise the oldest, re-files every library food and every catalog food (bundled rows included) from the others under the keeper, then archives the others; nothing is deleted and no food or logged entry is removed. A shipped category is never archived, so two shipped categories sharing a name are left alone. A shipped category missing from storage while an active category of the same name stands in (the old default seeding skipped it) is re-created from the seed first; one found archived beside such a category is un-archived. Foods are re-filed before the category is archived, so a failed run (`data_version` stays 20) is finished by the next launch; after a full pass a second run writes nothing. The logic is `DuplicateFoodGroupsMerge` ([`lib/core/services/duplicate_food_groups_merge.dart`](../lib/core/services/duplicate_food_groups_merge.dart)), shared by both stores. Default seeding (step 13) no longer skips a shipped category whose name is taken, and `FoodLibraryState.createFoodGroup` / `renameFoodGroup` refuse a name another active category has (`DuplicateFoodGroupNameError`), so the duplicates cannot come back. Retirement (not yet done): replace the step's run body in both repositories with a no-op that keeps version 21 and the name, delete the service and `test/duplicate_food_groups_merge_test.dart`, update this section; never renumber or remove a version. Verified by S-30301..S-30316 in `test/duplicate_food_groups_merge_test.dart` and by S-156 in `test/data_migration_test.dart`.

**Step 20 `repairDayKeys` — ONE-OFF (plan 264) — retire after launch.** Hive only (the Mock step is a no-op). Moves daily targets, water totals and logged-food days stored under the pre-plan-235 day key (local midnight) to the current key (the date's UTC midnight); a newer target wins, water for the same date is added. Idempotent. Logic: `lib/data/repositories/day_key_repair.dart`; verified by `test/day_key_repair_test.dart`.

**Step 19 `restoreShippedFoodGroups` — ONE-OFF (plan 137) — retire after launch.** Runs once per device: rule 1 un-archives every archived shipped category (name, color and creation time unchanged); rule 2 puts every active library copy that has no category and a `catalogId` back under its catalog row's category when that category is a shipped one (copies with any category, library foods without a `catalogId`, and copies of user-created catalog foods are untouched). A second successful run writes nothing; a failed write propagates so `data_version` stays 18 and the next launch re-runs the step. The logic is `ShippedFoodGroupsRepair` ([`lib/core/services/shipped_food_groups_repair.dart`](../lib/core/services/shipped_food_groups_repair.dart)), shared by both stores. Retirement (not yet done): replace the step's run body in both repositories with a no-op that keeps version 19 and the name, delete the service and `test/shipped_food_groups_repair_test.dart`, update this section; never renumber or remove a version. Verified by tests S-13706, S-13707, S-13708 and S-13709 in `test/shipped_food_groups_repair_test.dart` and by S-156 in `test/data_migration_test.dart` (steps 15 to 19 appended to both sequences).

The previous step is `muscleLinkRoles` (target version 16): it rewrites
every stored exercise→muscle link row into the role-aware shape — a legacy
all-primary row keeps its ids as primaries, and a region tag sitting next to
one of its own muscles is dropped. Verified by `test/data_migration_test.dart`
(`S-8: the muscleLinkRoles step on the Mock`,
`S-8: the muscleLinkRoles step on Hive (seeded before step 16)`).

Idempotency: every consolidated step preserves its existing effect — same
box writes, same upsert semantics, same idempotency — only the gating
changes (legacy `bool` marker → version check). The legacy `bool` markers
are still read by the shim for back-compat but are otherwise inert.

Catalog content versioning (`catalog_version`, `seed_entry_touched_*`) is
a separate always-on mechanism and is unaffected by `data_version`.

Tests: see `test/data_migration_test.dart` for the ordered-sequence,
back-compat shim, retry-on-failure, idempotency, and orthogonality cases.

---

## Backup file

Data export and import from Settings share one UTF-8 JSON file, `omnitrain-backup-YYYY-MM-DD.json`
(`S-27811 fileName is the local date, zero-padded`). Header: `format: omnitrain-backup`,
`formatVersion`, `appVersion`, `exportedAtMs`, `dataVersion`, `catalogVersion`; the body is three
maps keyed by box name — `collections`, `lists`, `meta`.

The export is `HiveWorkoutRepository`'s declared box allowlist; never carried are the bundled
`foods_catalog`, the watch's own `watch_session_*` boxes and the device-only meta keys; the wrist
inbox is carried. Two things stay behind on purpose: the profile photo file (only its stored
name travels in the profile row) and `hub_open_count`, which lives in SharedPreferences, not in the
store (unguarded by a test).

A restore replaces every carried collection and meta value; boxes the file lacks stay alone; it
refuses, changing nothing, for a non-backup, another format version, a newer data version, a
running workout or a malformed collection; a failed write rolls the store back; an older backup is
accepted.

Verified by `test/backup_codec_test.dart` (`S-27812 encodeBackup writes the header and
decodeBackupHeader reads it`) and by `test/backup_snapshot_repository_test.dart` (group
`Hive — backup snapshot`: `S-27818 every box initialize opens is classified for the backup`,
`S-27801b the export carries rows for every box the fixture fills`; group `Mock — backup
snapshot`: `S-27802 import replaces a carried collection instead of merging`,
`S-27803 boxes and meta the snapshot does not carry are left alone`) and by
`test/backup_service_test.dart` (groups `Mock — BackupService`, `Hive — BackupService`; test
names in [Service & Utility Classes](state_management/services_and_utils.md#backupservice)).

---

## Nutrition Targets (Daily Rollover)

`WorkoutRepository` exposes date-aware nutrition-target APIs in addition
to the legacy single-row methods:

| Method | Behaviour |
|---|---|
| `getNutritionTargetForDate(int dateMs)` | Returns the target stored for [dateMs]. If no explicit entry exists, walks backward one day at a time (24 h) until it finds the most recent ancestor and returns a copy rolled forward to [dateMs]. Returns `null` when no ancestor exists. |
| `saveNutritionTargetForDate(int dateMs, NutritionTarget target)` | Persists [target] for [dateMs]. Fetches the old target (if any) and forward-propagates the new values to any future dates that still hold the old values. Past dates are never modified. |
| `getNutritionTarget()` | Legacy convenience; delegates to `getNutritionTargetForDate(todayMs)`. |
| `saveNutritionTarget(NutritionTarget target)` | Legacy convenience; delegates to `saveNutritionTargetForDate(todayMs, target)`. |

Implementation requirements (both `HiveWorkoutRepository` and `MockWorkoutRepository`):

- **Backward-walk fallback**: `getNutritionTargetForDate(dateMs)` must check the requested date, then decrement by 24 h until an entry is found or the search space is exhausted. Returning `null` is the correct "no goals ever set" answer.
- **Forward-propagation rule**: When `saveNutritionTargetForDate(dateMs, new)` is called, the implementation must compare the **old** target at [dateMs] (if any) to all future dates. Any future date whose stored target is *identical* to the old target is replaced with [new]. Future dates that already differed from the old target are left untouched (they were explicit user edits).
- **Past dates are immutable**: The implementation must never walk forward and modify dates earlier than [dateMs].
- **Backward compat**: Legacy `getNutritionTarget()` / `saveNutritionTarget()` continue to work and target today's date. This is how the rest of the app stays unchanged during the migration.

Storage shape:
- Hive: a dedicated box `nutrition_targets_by_date` keys each entry by `dateMs.toString()` with a `Map<String, dynamic>` value matching `NutritionTarget.toMap()`.
- Mock: an in-memory `Map<int, NutritionTarget>` keyed by `dateMs`.
- SQLite: the `app_nutrition_target` table is keyed by `date_ms` (`INTEGER UNIQUE`); see `scripts/sqlite_schema.sql` for the schema narrative.

Tests: see `test/edge_case_test.dart` (`NutritionTarget (date-keyed) edge cases` group) for the boundary conditions — backward-walk, nearest-ancestor preference, forward-propagation across matching and non-matching future dates, and legacy delegation.

## Daily Water Log

This section moved to [db_integration_nutrition.md](db_integration_nutrition.md) (`## Daily Water Log`).

## Food Library & Catalog

This section moved to [db_integration_nutrition.md](db_integration_nutrition.md) (`## Food Library & Catalog`).

## SQLite Assets (Parity And Future Runtime)

`scripts/sqlite_schema.sql` now includes profile structures:

- `app_user_profile`
- `app_body_measurement_entry`
- Indexes for measurement history queries by type/user + recorded time desc

It also includes session/observation extensions:

- `app_training_session.session_feeling`
- `app_training_session.quality_rating`
- `app_effort_observation.rpe_rating`
- `app_effort_observation.rest_duration_ms`
- `app_effort_observation.value_source` — the provenance of a distance
  (`gps` / `entered` / `estimated`), null on every other row; CHECK-enforced.
  See [Distance Source & Pairing](distance_source.md).
- `app_effort_observation`'s value CHECK — at most one of `value_int`,
  `value_real` and `value_text`; `value_bool` is a flag the model writes on
  every row (0 or 1) and does not count. Verified by `test/db_seed_test.dart`
  (`S-861`).

And exercise modality persistence for custom exercise parity:

- `app_exercise.modality` (nullable for legacy rows)

`scripts/sqlite_seed.sql` now seeds stable unit IDs and metric IDs, including:

- `unit-cm`
- `unit-pct`
- canonical `metric-*` rows aligned with constant IDs

Active-session ordering parity columns for future `SqliteWorkoutRepository`:

- `app_session_block.top_level_order_index`
- `app_segment_effort.top_level_order_index`
- `app_segment_effort.block_order_index`

And the muscle hierarchy:

- `app_muscle_group.parent_id` — the parent region of a muscle; NULL for a
  region and for a standalone entry.
- `app_exercise_muscle_group.is_primary` — 1 = primary link, 0 = secondary
  link.

Verified by `test/db_seed_test.dart` (`Pipeline schema documentation` ·
`S-9 app_muscle_group carries parent_id and seeds the 27 groups the taxonomy
defines`).

Recommended SQL ordering for retrieval parity:

- Blocks: `ORDER BY top_level_order_index, order_index, created_at_ms, id`
- Efforts: `ORDER BY top_level_order_index, block_order_index, order_index, created_at_ms, id`

---

## SQLite Schema Versioning

> **Corrected 2026-07-26 (docs audit).** This section described a live
> `DatabaseProvider.open(..., version: 7)` runtime and a `migrations.dart`
> holding incremental SQL migrations. **Neither file exists any more.** The
> SQLite *runtime* was retired (see
> `docs/plans/retire-sqlite-runtime-plan.md`):
> `lib/data/datasources/database_provider.dart`, `db_helper.dart`, and
> `migrations.dart` were deleted, `sqflite` was dropped from `dependencies`
> (only `sqflite_common_ffi` remains, under `dev_dependencies`, for the
> validation test), and the SQL files are no longer bundled as Flutter
> assets. The app persists exclusively through `HiveWorkoutRepository` on
> every platform. `pubspec.yaml` also sets `hooks: user_defines: sqlite3:
> source: system`, so the dev-only `sqlite3` package uses the operating
> system's SQLite and no `sqlite3.framework` is bundled into iOS builds (an
> unsigned copy of it once made a device install fail).

What remains is the **schema documentation**, and it is still authoritative
for the data model:

- `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` are maintained in
  the repository as the pipeline's canonical data-model contract.
- Schema evolution is expressed as `ALTER TABLE` / `CREATE TABLE IF NOT
  EXISTS` statements appended to `sqlite_schema.sql` itself, not as separate
  numbered migration files.
- The historical migration steps the retired provider applied are listed
  below for reference. They are **history**, not a live upgrade path:
  - v2: `modality`, `intent` fields on `app_training_session`
  - v3: `session_feeling`, `quality_rating`, `rpe_rating`, `rest_duration_ms`
  - v4: `app_entry_rest` table
  - v5: exercise content and `app_exercise_note`
  - v6: rolling sessions, `app_session_block`, and `block_id`
  - v7: canonical ordering fields (`top_level_order_index`,
    `block_order_index`) and indexes for deterministic active-session ordering

Runtime **data** migrations (the ones that actually execute today) are a
separate mechanism keyed on `currentDataVersion` — see
[Constants Reference](constants_reference.md#data_versiondart). Their latest step is `mergeDuplicateFoodGroups` (version 21, below); the one before it is `repairDayKeys` (version 20); before that `restoreShippedFoodGroups` (version 19), a one-off
restore of the shipped food categories, preceded by step 18
`backfillRoutineSessionModality`, a one-off back-fill of past routine
sessions' modality; step 17
`retireOrphanTemplateRows` removes the retired first-install template
rows; see the data-migration sequence above.

---

## Practical Notes

- The schema/seed SQL are read from disk with `File` by
  `test/db_seed_test.dart`, which executes them against an in-memory
  `sqflite_common_ffi` database to prove they remain valid, executable SQL.
  They are **not** loaded via `rootBundle` and are no longer shipped as app
  assets.
- Runtime persistence is Hive on every platform. The SQL files are
  maintained as the data-model contract so the documented schema cannot
  drift from the models.

---

## Session Block Semantics (Iteration 5 change)

`deleteSessionBlock(blockId)` now **cascade-deletes** all linked `SegmentEffort` records and their sub-records (observations, round instances, timed instances, entry rests, and the sensor summaries of the efforts and instances it deletes — verified by `test/watch_capture_repository_parity_test.dart`, `D-131 deleteSessionBlock removes …`). This changed from the Iteration 1 design which only nulled `blockId` on linked efforts.

- Both `HiveWorkoutRepository` and `MockWorkoutRepository` implement the cascade.
- `WorkoutState.deleteSessionBlock` mirrors the cascade in its in-memory caches.
- The SQLite schema remains `ON DELETE SET NULL` on `app_segment_effort.block_id`; the app layer performs the cascade before any FK action fires.

`cloneSessionBlock(blockId)` names clones using the current wall-clock time label (`"h:mm AM/PM"`) across all session modalities/intents.

`addSessionBlock({String? name})` now accepts an optional `name` parameter. When `name` is omitted, the current time in `"h:mm AM/PM"` format is used.

---

## Watch Capture Storage

Covers the watch session inbox and wrist-measured sensor summaries: the
watch-capture methods of `WorkoutRepository`, their `HiveWorkoutRepository` and
`MockWorkoutRepository` implementations, and the `app_watch_inbox_entry` and
`app_sensor_summary` tables in `scripts/sqlite_schema.sql`. The models are in
[Data Models](data_models.md#watch-capture-models).

Structure:
- Hive keeps each in its own box: `watch_inbox`, keyed by entry id, and
  `sensor_summaries`, keyed by `SensorSummary.id`. Each value is the model's
  `toMap()`. `MockWorkoutRepository` keeps one in-memory map per box.
- `scripts/sqlite_schema.sql` documents both tables, with CHECK constraints
  mirroring the models' refusals and a method-by-method SQL contract.
  `test/db_seed_test.dart` (`Watch capture schema contract (D-131 / D-132)`)
  proves every `toMap()` key is a column, that model rows insert and read back
  unchanged, and that the constraints refuse what the models refuse.

Invariants:
- **Put-if-absent, reported.** Staging an inbox row and creating a summary
  never replace an existing row, and report whether they stored anything.
- **Summaries cascade; the inbox does not.** Every repository delete that
  removes a summary target also removes that target's summaries, and
  `deleteSession` removes all of the session's. No delete touches the inbox:
  its applied rows are tombstones that must outlive the history they describe,
  which is also why `app_watch_inbox_entry` has no foreign key. A summary's
  target is polymorphic, so its SQL table can only hold a foreign key to the
  owning session; the repository enforces the rest.
- **One write unsets a stamp; nothing deletes.** `clearWatchInboxApplied`
  unsets `appliedAtMs` on the named rows and only on them: an id that names no
  row, and a row that is not applied, are skipped, and no row is created. It is
  the one write that ever removes an applied stamp, and it exists for the Edit
  Session Discard that has to recover an entry which arrived after the
  snapshot (D-804). `test/watch_capture_repository_parity_test.dart` (`S-1412`)
  runs it against both stores. No inbox row is ever deleted, and the schema is
  unchanged: `applied_at_ms` is already nullable, and `test/db_seed_test.dart`
  proves the tables.
- **Parity.** Hive and Mock agree value for value, ordering included.
  `test/watch_capture_repository_parity_test.dart` runs one test body against
  both, and compares one scripted sequence row by row by `toMap()`.

Rationale:
- **The payload is stored as JSON text.** Hive returns nested maps untyped,
  and the SQL contract holds the event in one `TEXT` column. Storing the
  encoding keeps the two stores identical and the staged payload immutable.
- **No data-migration step.** Both boxes start empty on existing installs and
  no existing row changes, so `currentDataVersion` is unchanged.

---

## Session Energy Storage

Covers `SessionEnergy`, the energy methods of `WorkoutRepository`, and the
`app_session_energy` table in `scripts/sqlite_schema.sql`. The model is in
[Data Models](data_models.md#session-energy-model).

Structure:
- Hive keeps one row per session in its own `session_energy` box, keyed by the
  session id, each value the model's `toMap()`; `MockWorkoutRepository` keeps
  an in-memory map beside its `_sensorSummaries` map and a `clear()` empties
  it with the rest.
- Deleting a session deletes its energy row on both stores and a full wipe of
  either store removes every row (`test/session_energy_repository_test.dart`,
  group `Session energy — Mock` and group `Session energy — Hive`:
  `S-13408 deleteSession removes the session's energy row`,
  `S-13408 a full wipe of the repository removes the energy rows`).

Methods:
- `putSessionEnergy(SessionEnergy) -> Future<bool>`: an upsert named by the
  row's `sessionId`. A `measured` row always replaces; an `estimated` put over
  a `measured` row returns `false` and writes nothing — Hive reads the stored
  row and puts with no await in between, so a measured row cannot land between
  the read and the write. Parity is one test body over both factories:
  `S-13410 putSessionEnergy stores an estimated row and getSessionEnergy reads
  it back unrounded`, `S-13410 a measured row replaces an estimated one`,
  `S-13410 an estimated put over a measured row returns false and writes
  nothing`, `S-13410 getSessionEnergy of a session with no row is null`.
- `getSessionEnergy(String) -> Future<SessionEnergy?>`: the stored row, or
  null when none.

SQL: `app_session_energy` in `scripts/sqlite_schema.sql`, columns `session_id`
(its primary key), `active_kcal`, `source`, `body_weight_kg`, `updated_at_ms`,
a `FOREIGN KEY (session_id)` to `app_training_session` `ON DELETE CASCADE`
and CHECKs that refuse a source outside the two, negative kcal, a `measured`
row with a weight and an `estimated` row without one. The contract group is
`test/db_seed_test.dart`, group `app_session_energy contract (D-13401 /
D-13402)`.

Why it is not a `SensorSummary`: a summary is put-if-absent per (scope,
target), its `source` allows only `watch`, and it needs a heart rate or steps,
so an estimate stored as a summary would block the wrist's later session
summary.

---

## Sub-Holder Architecture and Repository Access

After the `workout-state-and-screen-refactor`, `WorkoutState` is a thin `ChangeNotifier` facade that constructs three sub-holders. Each sub-holder independently holds a `WorkoutRepository` reference — they do **not** share a single repository reference through the facade.

```
WorkoutRepository (injected into WorkoutState)
   │
   ├─► TimerManager(_repository, notify: ...)
   │     Owns: RoundInstance, TimedInstance, EntryRest writes
   │
   ├─► ExerciseLibrary(_repository, notify: ...)
   │     Owns: Exercise, ExerciseNote reads/writes
   │
   └─► SessionCore(_repository, notify: ..., timerManager, exerciseLibrary)
         Owns: TrainingSession, SessionSegment, SegmentEffort, EffortObservation
         Delegates timer creation to TimerManager
         Delegates note cache clearing to ExerciseLibrary
```

All repository reads and writes go through the same `WorkoutRepository` interface. The concrete implementation (`HiveWorkoutRepository` or future `SqliteWorkoutRepository`) is injected once at app startup and passed to each sub-holder.

---

**Document Version**: 1.6
**Last Updated**: September 25, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
