# 115b — 20 core, leg/hip and press exercises; Trap Bar and Sled equipment

> Status: Iteration 1 ready. One owner question (Q1, sled logging) is open with its default applied; only Phase 2B rows 19–20 depend on it.
> Next handoff: @dba (Phase 1), run by the crew (`crew-builder-data`). Phase 1 item 4 (the version bump) is made by the lead: `crew-builder-data` cannot write `lib/core/**`.
> Precondition met: 115a is committed (`7631ea34`).
> Binding conventions: `docs/global_conventions.md`, `docs/data_models.md` (MuscleGroup section), `docs/db_integration.md` (catalog refresh, SQL contract)
> Series index: `docs/plans/2026-11-04-115-strength-catalog-gaps-series.md`. Track: phone only (`lib/`, `scripts/`, `test/`, `docs/`). Never branch or commit.
> Precedent: plan 115a (`docs/plans/2026-11-04-115a-strength-catalog-gaps-plan/`). Its decisions D-18905, D-18907, D-18908, D-18909 and D-18910 bind this PR as written there; its test files are extended here.

## Overview

Classification: **STANDARD**. Bundled reference data that existing installs receive through the catalog refresh, plus
two new equipment rows that existing installs never receive.

What a user sees after this PR:

1. 20 new exercises in the library, the picker and the watch's exercise list (after its next sync), each with a
   description, how-to steps, and main and assisting muscles on its detail screen: Sit-Up, Crunch, Reverse Crunch,
   Bicycle Crunch, Russian Twist, Hanging Knee Raise, Dead Bug, Bird Dog, Cable Side Bend, Push Press, Trap-Bar
   Deadlift, Rack Pull, Lateral Lunge, Curtsy Lunge, Single-Leg Hip Thrust, Donkey Calf Raise, Leg Press Calf Raise,
   Reverse Hyperextension, Sled Push and Sled Drag.
2. The Muscle filter lists them under the muscles in the row table: for example **Obliques** gains Bicycle Crunch,
   Russian Twist and Cable Side Bend, **Calves** gains Donkey and Leg Press Calf Raise, **Core** gains the core rows,
   Bird Dog included. **Abductors**, **Adductors**, **Rotator cuff**, **Brachialis** and **Biceps** list the same
   exercises as before (the new rows only assist there, or not at all).
3. "Dead Bug" (moving, counted in reps) appears next to the existing "Dead Bug Hold" (a timed hold). Searching
   "dead bug" shows both.
4. Sled Push and Sled Drag log the way Farmer's Carry logs today (Q1): in a Strength workout as reps and weight; in
   a Free workout the user can choose Time and log a timer with distance and weight.
5. Existing installs get the 20 exercises on the next launch. Rows the user edited or copied, and the user's own
   exercises (a custom "Sit-Up" included), are not changed.
6. Nothing is visible about equipment, because no screen shows it. New installs know that a sled push uses a Sled and
   a trap-bar deadlift uses a Trap Bar. Updated phones never learn either.

## Owner question (one batch; the plan applies the default)

- **Q1. Logging a Sled Push or Sled Drag.** Default: **(a) exactly like Farmer's Carry.** The exercise can be logged
  with time, distance and load. In a **Strength** workout it is logged like a lift: reps and weight, with no timer and
  no distance field (a user types the number of lengths as reps). In a **Free** workout the user picks Time and gets a
  timer plus distance and weight. In the Strength picker it ranks below the plain lifts (score 53 against 80), the same
  as Farmer's Carry, but still in the "recommended" band. On the watch it logs the same way, and no Health workout type
  of its own is recorded for it (same as Farmer's Carry).
  Alternatives: (b) treat sleds as plain lifts (reps, sets, load, time): they rank with the lifts and lose the
  distance option in Free workouts. (c) A timer-and-distance logger for carries and sleds inside Strength workouts.
  That changes the logger, not the catalog: a separate @developer PR of about 2 phases with its own product calls,
  and it would change Farmer's Carry too.

## Resolved Decisions (Ledger)

- **D-19001** The 20 new exercises are exactly the rows of the **New-row table** below: id, name, movement pattern,
  capabilities, main and assisting muscles, and equipment, all as written. Ids are `exercise-<slug>`. Rows are
  appended, in table order, at the end of `SeedData.sampleExercises` (after `exercise-dumbbell-shrug`,
  `lib/mock/seed_data.dart:4438`) and at the end of each of the three maps (after the `exercise-dumbbell-shrug` entries
  at `:5091`, `:5335`, `:5722`). Every new id sorts after `exercise-2k-row-test`. No id exists today
  (`grep -rc "'exercise-<slug>'" lib test watch` → 0 for all 20, run 2026-11-04).
- **D-19002** D-18905 (discipline `discipline-bodybuilding`, no `ownerUserId`, no new discipline), D-18907 (text
  rules) and D-18908 (capability codes L, LB, BW) apply to every row. One more code: **C** =
  `['time', 'distance', 'load']`, the exact set and order of `exercise-farmers-carry` (`seed_data.dart:5478`).
- **D-19003** Text specifics on top of D-18907. Dead Bug and Bird Dog say the limbs move and return each rep (so they
  read differently from Dead Bug Hold). Hanging Knee Raise says the knees stay bent and that it is the easier step
  before Hanging Leg Raise. Rack Pull says the bar starts on safety pins or blocks at about knee height. Push Press
  says a short knee dip and leg drive start the press. Trap-Bar Deadlift says the lifter stands inside the bar. Sled
  Push and Sled Drag end with "Time- or distance-based.", as Farmer's Carry does. Leg Press Calf Raise says the knees
  stay straight but not locked. No brand names.
- **D-19004** Two equipment rows, appended in this order after `equipment-machine` in `SeedData.sampleEquipment`
  (`seed_data.dart:4453-4504`): `Equipment(id: 'equipment-trap-bar', name: 'Trap Bar', …)` and
  `Equipment(id: 'equipment-sled', name: 'Sled', …)`, in the existing `createdAtMs` form. D-18909 holds: equipment
  rows and equipment links are written at first install only (`hive_workout_repository.dart:634-636, 670-673`), and
  the refresh writes neither (`catalog_refresh_service.dart:59-64`). Updated installs therefore have neither the two
  rows nor any equipment link for the 20 new exercises. No repository code changes. Both readers skip a link whose
  equipment row is missing: Mock at `mock_workout_repository.dart:1026-1031` (`.map(_equipment[id]).whereType<Equipment>()`)
  and Hive at `hive_workout_repository.dart:1817-1823` (`.map(_equipmentBox.get).whereType<Map>()`). Neither throws.
- **D-19005** SQL contract. `scripts/sqlite_seed.sql` gains four `app_equipment` inserts, in the existing two-line
  form, after the `'Body Weight'` insert (`:353-354`) in this order: `'Cable Machine'`, `'Machine'`, `'Trap Bar'`,
  `'Sled'`. The SQL then names the same 12 equipment rows as the seed. No exercise or link rows are added: the SQL
  fixture carries none of the 115a/115b exercises. `scripts/sqlite_schema.sql` changes in one comment only:
  `:1631-1632` "(exercises + capability / muscle-group / equipment relationships + the food catalog)" becomes
  "(exercises + capability / muscle-group relationships + the food catalog; equipment is written at first install
  only)". No DDL changes.
- **D-19006** `bundledCatalogVersion` 14 → 15 (lead). Append to the doc comment in
  `lib/core/constants/catalog_version.dart`: "When 20 core, leg/hip and press exercises were added (Sit-Up through
  Sled Drag) with the Trap Bar and Sled equipment rows, we bumped to `15` so existing installs receive the exercises
  on next launch; the two equipment rows reach new installs only." `currentDataVersion` is unchanged.
- **D-19007** (Q1 default) Sled Push and Sled Drag carry capability set C. No logger, effort-kind or Health change.
  Their movement pattern is null, because no existing pattern describes a push or drag and `movementPattern` has no
  reader except the refresh diff (`grep -rn movementPattern lib`: only the model, `exercise_helpers.dart`,
  `exercise_library_service.dart:245` and `catalog_refresh_service.dart:361`).
- **D-19008** Muscle tagging uses existing ids only, and never a region id, so the "only the twelve region-tagged
  exercises carry a region" guard stays exact. No new row links Rotator cuff, Brachialis or Biceps, so the 115a exact
  sets stay exact. Curtsy Lunge *assists* Abductors and Lateral Lunge *assists* Adductors; neither appears in those
  filters, because only main links count (D-18903). Bird Dog is main on Lower back **and** Abs, so it appears under
  both Back and Core.
- **D-19009** D-18910 applies. Also, a bundled row that the user renamed to one of the new names (for example
  Hanging Leg Raise renamed "Hanging Knee Raise", marked touched) keeps its name and links, and the new bundled row
  arrives beside it. Bundled-name uniqueness is a seed rule (S-19001). A device may hold the same name twice.
- **D-19010** Out of this PR: equipment delivery, a screen that shows equipment, any logger change for carries or
  sleds, re-tagging Farmer's Carry's equipment, the 51 empty equipment rows carried from 115a, new muscles and new
  disciplines. No change to the watch, the sync contract, Stats, sessions or routines.
- **D-19011** `docs/state_management/watch_reference_data.md:22` says "a phone with 252 seeded exercises would send
  about 28 KB". It becomes "a phone with 300 seeded exercises would send tens of kilobytes". The 252 is stale since
  115a, and the byte figure was never re-measured.

### New-row table (D-19001; P = main, S = assists; "—" = none / null `movementPattern`)

| # | id (`exercise-…`) | Name | Pattern | Caps | P | S | Equipment |
|---|---|---|---|---|---|---|---|
| 1 | sit-up | Sit-Up | abs | BW | abs | obliques | bodyweight |
| 2 | crunch | Crunch | abs | BW | abs | obliques | bodyweight |
| 3 | reverse-crunch | Reverse Crunch | abs | BW | abs | obliques | bodyweight |
| 4 | bicycle-crunch | Bicycle Crunch | abs | BW | abs, obliques | — | bodyweight |
| 5 | russian-twist | Russian Twist | loaded_core | L | obliques | abs | bodyweight |
| 6 | hanging-knee-raise | Hanging Knee Raise | abs | BW | abs | obliques | pullup-bar |
| 7 | dead-bug | Dead Bug | abs | BW | abs | obliques | bodyweight |
| 8 | bird-dog | Bird Dog | — | BW | lower-back, abs | glutes | bodyweight |
| 9 | cable-side-bend | Cable Side Bend | loaded_core | LB | obliques | lower-back | cable |
| 10 | push-press | Push Press | vertical_push | L | front-delts | triceps, side-delts, quads | barbell |
| 11 | trap-bar-deadlift | Trap-Bar Deadlift | hinge | L | glutes, quads, hamstrings | lower-back, traps, forearms | trap-bar |
| 12 | rack-pull | Rack Pull | hinge | L | lower-back, glutes, traps | hamstrings, forearms | barbell |
| 13 | lateral-lunge | Lateral Lunge | lunge | L | quads, glutes | adductors | dumbbell |
| 14 | curtsy-lunge | Curtsy Lunge | lunge | L | glutes, quads | abductors | dumbbell |
| 15 | single-leg-hip-thrust | Single-Leg Hip Thrust | hinge | LB | glutes | hamstrings | bodyweight |
| 16 | donkey-calf-raise | Donkey Calf Raise | calves | L | calves | — | machine |
| 17 | leg-press-calf-raise | Leg Press Calf Raise | calves | L | calves | — | machine |
| 18 | reverse-hyperextension | Reverse Hyperextension | hinge | L | glutes, lower-back | hamstrings | machine |
| 19 | sled-push | Sled Push | — | C | quads, glutes | hamstrings, calves | sled |
| 20 | sled-drag | Sled Drag | — | C | quads, glutes | hamstrings, calves | sled |

Rows 1–10 are Phase 2A, and rows 11–20 are Phase 2B. Siblings for each choice: crunch-family rows follow Hanging Leg
Raise and Cable Crunch (`abs`, abs/obliques). Russian Twist and Cable Side Bend follow Cable Woodchop (`loaded_core`).
Push Press follows Overhead Press. The hinge rows follow Deadlift, Barbell Hip Thrust and Back Extension. The lunges
follow Walking and Reverse Lunge (L, no `bilateral`). Single-Leg Hip Thrust follows Single-Leg RDL (LB). The calf
rows follow Standing Calf Raise. The "loaded" bodyweight rows (Russian Twist, Single-Leg Hip Thrust) carry `load`
with `bodyweight` equipment, as Bench Dip does.

## Feature Invariants

- The refresh never rewrites a touched, copied or custom exercise (D-18910, D-19009).
- `MockWorkoutRepository` and `HiveWorkoutRepository` return the same filter results, rows, capabilities and links in
  S-19005 to S-19008. Documented Mock exceptions (115a precedent): Mock cannot remove an equipment row or an
  equipment link, so the "updated phone" equipment staging and the dangling-link case run on Hive only.
- Diff boundary: no file under `lib/features/`, `lib/widgets/`, `lib/state/`, `lib/core/services/`,
  `lib/core/utils/`, `lib/data/repositories/`, `lib/data/models/`, `lib/watch/` or `watch/` changes, and neither does
  `lib/core/constants/data_version.dart`. `scripts/sqlite_schema.sql` changes in the D-19005 comment only.

## Requirements and Acceptance Criteria

| Id | Acceptance (what a user sees) | Scenarios |
|---|---|---|
| A1 | 20 exercises exist with text, capabilities, muscles and (on new installs) equipment as tabled; bundled names stay unique | S-19001, S-19008 |
| A2 | The Muscle filter lists them by main muscle only; Abductors, Adductors, Rotator cuff, Brachialis and Biceps are unchanged | S-19004, S-19005 |
| A3 | Phones at version 14 receive the 20 rows on next launch; user-owned rows, same-name customs and renamed touched rows are untouched | S-19006, S-19007 |
| A4 | Trap Bar and Sled exist on new installs; updated phones lack them without any error; a link to a missing row is skipped | S-19002, S-19008 |
| A5 | The SQL contract names the same 12 equipment rows as the seed | S-19003 |
| A6 | Sled rows log like Farmer's Carry (Q1) | S-19001 (caps C) |

## Existing-Functionality Impact (greps run 2026-11-04 on `claude_develop` at `7631ea34`)

| Touched surface | Readers (grep) | Effect | Guard |
|---|---|---|---|
| `SeedData.sampleEquipment` | `grep -rn "sampleEquipment" lib test` → Hive first-install seed `:635`, Mock init `:169`, `catalog_referential_integrity_test.dart:21` (R-002) | New installs gain 2 rows; R-002 stays green because the links' targets are added in the same seed | S-19002, R-002 |
| Equipment readers | `grep -rn -i equipment lib/features lib/widgets lib/state` → 0; only the two repositories read it | Invisible on screen (D-19004) | S-19008 |
| `exerciseEquipmentRelationships` size | `strength_catalog_gaps_test.dart:363` (`188 + N`) | 216 → 236 | S-19001 |
| Link-map size | `catalog_referential_integrity_test.dart:205,270` `hasLength(206)` | 216 after 2A, 226 after 2B | S-19004 |
| Exact Calves sets | `catalog_referential_integrity_test.dart:317-341` | Main Calves gains `donkey-calf-raise`, `leg-press-calf-raise` (10 ids); assisting Calves gains `sled-push`, `sled-drag` (4 ids). Red by design in 2B | S-19004 |
| 115a exact sets (Abductors, Rotator cuff, Brachialis, Biceps main; Rotator cuff and Brachialis assist), region-tagged 12 | same file `:208-231, 355-397` | Unchanged by D-19008; they stay green and guard the tagging | none needed |
| Calves / Shins filters | `muscle_filter_test.dart:189-290` (S-18804): Shins is exact; Calves "excludes nordic-curl" | No Shins tag; sled rows only assist Calves | full Phase 3 suite |
| Catalog sizes | `strength_catalog_gaps_test.dart:356-367` (`252 + N`, `178 + N`) | Exercises and capability rows 280 → 300; links 206 → 226 | S-19001 |
| Catalog version literals | `grep -rn "equals(14)\|Version(14)" test` → 0 catalog hits; `setCatalogVersion(13)` at `strength_catalog_refresh_test.dart:245,484` and `(12)` in the tibialis test are staging literals and stay | Bumping to 15 turns nothing red | Phase 1 suites |
| Watch exercise list | `watch_reference_sync.dart:234` batches of ≤ 100; `watch_reference_sync_test.dart` S-3858 `hasLength(3)` on the seeded catalog | 300 rows stay 3 batches. Health mapping (`:500-519`) returns null for sleds (bodybuilding discipline), as for Farmer's Carry | `watch_reference_sync_test.dart` green |
| Sled logging | `session_core_entry.dart:24-33` (a modality session uses its config's effort kind: Strength → `set`); `ModalityConfig.effortKindFromMetric` (Free) | Same as Farmer's Carry (Q1) | S-19001 caps |
| Strength picker rank | `modality_config.dart:277-327` | BW core rows 70, L/LB rows 80, sled rows 53 | full suite |
| First bilateral in ranked list | `catalog_refresh_test.dart:1245`, `exercise_info_sheet_bilateral_test.dart:72` (`firstWhere(bilateral)`) | New LB rows (Cable Side Bend, Single-Leg Hip Thrust) may be picked instead; those tests assert behaviour of any bilateral row | full suite |
| Lists ordered by name | 115a list: `pr8_exercise_library_test`, `pr7_exercise_details_view_test`, `screen_widget_test`, `interaction_flow_test`, `widget_test`, `library_grouping_test`, `exercise_library_filters_test`, `muscle_filter_picker_test`. Bundled names that tests find by text (intersect of `find.text('…')` with seed names): Barbell Back Squat, Barbell Bench Press, Easy Run, Heavy Bag Rounds, Pull-Up, Tennis Match, Trail Run, Triceps Pressdown | Every new name sorts after "Barbell…"; the "Press" + Triceps search in `muscle_filter_picker_test.dart:292-295` does not list Push Press (triceps is an assist) | full suite (2B) |
| Name search | `grep -rn "searchText:" test` → only 'Leg Extension' and 'bech press'; `enterText` strings: none matches a new name | "dead bug", "crunch", "hip thrust", "calf raise", "lunge", "deadlift" now return more rows | S-19005 |
| SQL contract | `db_seed_test.dart` has no equipment assertion today (`grep -n -i equipment test/db_seed_test.dart` → 0) | 8 → 12 inserts, newly guarded | S-19003 |
| Docs claiming equipment is refreshed | `scripts/sqlite_schema.sql:1631-1632` | Fixed by D-19005 | Phase 1 |
| Docs naming the equipment set | `grep -rn "Heavy Bag\|Pull-up Bar\|Cable Machine\|equipment-" docs` (excluding plans/history/releases) → none lists the equipment rows; `data_models.md:291` names the model only | No equipment-list doc to update | Phase 3 sweep |
| Stats, summary, home, routines, calendar | `grep -rn "exercise-farmers-carry" lib test` outside seed → 0; routines store ids, and no routine names a new id | Unaffected | grep |

## UI Standards Impact

None. No UI file changes.

## Scenarios

Shared fixture notes: "custom" means `createExercise(Exercise(id, ownerUserId: 'user-1', name, createdAtMs: 1700000000000, updatedAtMs: same))`
then `setExerciseMuscleLinks`. Mock+Hive tests run over `harnessFactories` with plain `test()`, never `testWidgets`.
"P" = `MuscleRole.primary`, "S" = `MuscleRole.secondary`.

### S-19001: New-row conformance and catalog guards (`test/strength_catalog_gaps_test.dart`, pure)
- Fixture: a second const table `_rows115b` in the same file that mirrors the New-row table (C written out as
  `['time', 'distance', 'load']`). Phase 2A holds rows 1–10, and 2B holds all 20.
- Expected: each row passes the same per-row checks as S-18909 (name, discipline, pattern, null owner, non-empty
  description, 3–4 non-empty steps, capabilities equal to the tabled list in order, equipment, `normalize`d links).
  The global guards run over both tables: names unique ignoring case and surrounding spaces; every id in both tables
  sorts after `exercise-2k-row-test`; sizes `sampleExercises == 252 + 28 + M`, capabilities `== 252 + 28 + M`,
  equipment map `== 188 + 28 + M`, links `== 178 + 28 + M`, where M = `_rows115b.length`. Final: 300 / 300 / 236 / 226.
- Red today: rows absent. Edge case of: none

### S-19002: The seed's equipment rows (same file, pure)
- Fixture: `SeedData.sampleEquipment` as shipped.
- Expected: the id list equals `[barbell, dumbbell, kettlebell, resistance-band, pullup-bar, treadmill, heavy-bag,
  bodyweight, cable, machine, trap-bar, sled]` (each `equipment-`-prefixed); `trap-bar` is named `Trap Bar` and
  `sled` is named `Sled`; the 12 names are unique. Red today (10 rows).
- Edge case of: none

### S-19003: The SQL contract names the seed's equipment (`test/db_seed_test.dart`, new test in `Pipeline schema documentation`)
- Fixture: the S-9 harness (`_openSchemaDatabase()` then every statement of `sqlite_seed.sql`).
- Expected: `SELECT name FROM app_equipment` as a set equals `SeedData.sampleEquipment` names as a set (12), and the
  row count is 12. Title: `S-19003 app_equipment carries the 12 equipment names the seed defines`. Red today (8 rows:
  Cable Machine, Machine, Trap Bar and Sled are missing).
- Edge case of: none

### S-19004: The bundled link sets (`test/catalog_referential_integrity_test.dart`, approved-rows test)
- Fixture: `SeedData.exerciseMuscleLinks` as shipped.
- Expected: map length 226 at both sites. Main Calves == the 8 existing ids + `donkey-calf-raise`,
  `leg-press-calf-raise`. Assisting Calves == `{nordic-curl, wall-sit, sled-push, sled-drag}`. Assisting Abductors
  == `{curtsy-lunge}` (empty today). Main Abductors is unchanged (the existing 4-id assertion stays). Main Adductors
  excludes `lateral-lunge`. Main Lower back contains `bird-dog`, `rack-pull` and `reverse-hyperextension`.
  The region-tagged set and every 115a set are unchanged. Red today: the new ids are absent.
- Edge case of: none

### S-19005: Filtering on a fresh install, Mock and Hive (`test/muscle_filter_test.dart`, new group)
- Fixture: the bundled catalog plus customs.
  - U "Sit-Up" `[abs P]`, the same name as a bundled row.
  - O "Oblique Reach" `[abs P, obliques S]`, Obliques as an assist only.
  - B "Side Bend" `[obliques P, lower-back P]`.
  - E "Hip Flexor Raise" `[]`.
- Expected (`searchExercises(muscleGroupIds: …)`, ids):
  - Obliques → contains `bicycle-crunch`, `russian-twist`, `cable-side-bend` and B, each once; excludes `sit-up`, `crunch`, `reverse-crunch`, `hanging-knee-raise`, `dead-bug` and O.
  - Abs → contains `sit-up`, `crunch`, `reverse-crunch`, `bicycle-crunch`, `hanging-knee-raise`, `dead-bug`, `bird-dog`, U and O; excludes `russian-twist` and `cable-side-bend`.
  - Core → contains all 9 core ids, U, O and B, each exactly once; excludes E.
  - Lower back → contains `bird-dog`, `rack-pull`, `reverse-hyperextension` and B; excludes `cable-side-bend` and `trap-bar-deadlift`.
  - Back → `rack-pull` and `bird-dog`, each exactly once.
  - Calves → contains `donkey-calf-raise` and `leg-press-calf-raise`; excludes `sled-push` and `sled-drag`.
  - Abductors → equals the 4 bundled abductor ids (excludes `curtsy-lunge`). Adductors → excludes `lateral-lunge`.
  - Glutes → contains `trap-bar-deadlift`, `rack-pull`, `lateral-lunge`, `curtsy-lunge`, `single-leg-hip-thrust`, `reverse-hyperextension`, `sled-push` and `sled-drag`.
  - Front delts → contains `push-press`. Triceps → excludes `push-press`.
  - `['muscle-legs', 'muscle-glutes']` → `sled-push` exactly once.
  - `searchExercises(searchText: 'Sit-Up')` contains U and `exercise-sit-up`; `searchText: 'Dead Bug'` contains `exercise-dead-bug` and `exercise-dead-bug-hold`.
  - `getExercisesRankedForModality('resistance_lifting', muscleGroupIds: ['muscle-obliques'])` equals the unfiltered ranked ids, in order, restricted to the Obliques set.
- Red today: the new ids are absent. Edge case of: none

### S-19006: A v14 install refreshes to v15 (new `test/strength_catalog_v15_refresh_test.dart`, Mock + Hive, `const BundledCatalogSource()`)
- Fixture (staged after `harness.open()`):
  1. For each of the 20 new ids: `deleteExercise(id)`, `setExerciseCapabilities(id, [])`, `setExerciseMuscleLinks(id, [])`. On Hive also delete the id from box `exercise_equipment`.
  2. Hive only: delete `equipment-trap-bar` and `equipment-sled` from box `equipment` (`Box<Map>`) and assert they are absent. Mock cannot do this; log it.
  3. Custom U "Sit-Up" `[abs P, obliques S]`.
  4. Copy K = `ExerciseLibraryService(repo).copyAsCustom(exercise-hanging-leg-raise)`; record its links.
  5. `exercise-farmers-carry` untouched (caps C).
  6. `setCatalogVersion(14)` (the literal).
- Trigger: `CatalogRefreshService(repo, const BundledCatalogSource()).refresh()`.
- Expected:
  - The refresh returns true. `getCatalogVersion() == bundledCatalogVersion`, and `bundledCatalogVersion >= 15`.
  - Each of the 20 ids exists with its table name. Its capabilities equal the bundled ones (as a set, and the same length), and so do its links.
  - U keeps its name and `[abs P, obliques S]`. `searchExercises(searchText: 'Sit-Up')` contains U and `exercise-sit-up`. K keeps its recorded links.
  - Farmer's Carry's capabilities are still the set C.
  - Hive only: `getExerciseEquipment` of `trap-bar-deadlift`, `sled-push` and `cable-side-bend` is empty, and `getEquipment()` names contain neither `Trap Bar` nor `Sled`. This pins D-19004: an equipment-delivery PR must change it on purpose.
  - A second `refresh()` returns false, and the links of U, K and the 20 ids are identical.
- Red today: stored 14 is not behind the bundled 14.
- Edge case of: none

### S-19007: A renamed touched row and near-twins keep their own (same file, both harnesses)
- Fixture:
  1. S-19006 step 1 for `exercise-hanging-knee-raise` only.
  2. `exercise-hanging-leg-raise` renamed "Hanging Knee Raise" via `updateExercise`, with links `[abs P, forearms S]`, then `markSeedEntryTouched(SeedEntryType.exercise, 'exercise-hanging-leg-raise')`.
  3. Customs N1 "Situp" `[abs P]` and N2 "sit-up " (lower case, trailing space) `[abs P]`.
  4. `setCatalogVersion(14)`.
- Expected after `refresh()`: `exercise-hanging-leg-raise` keeps the name "Hanging Knee Raise" and those links. `exercise-hanging-knee-raise` exists with the bundled name and links. `searchExercises(searchText: 'Hanging Knee Raise')` contains both ids. N1 and N2 exist with their names and links. The Abs filter contains `exercise-hanging-knee-raise`, N1 and N2, each once.
- Red today: the version gate skips the refresh, so `exercise-hanging-knee-raise` stays absent.
- Edge case of: S-19006

### S-19008: Equipment on a new install and a missing equipment row (same file)
- Fixture (a) both harnesses, fresh: no staging.
- Expected (a): `getExerciseEquipment` names: `trap-bar-deadlift` == `['Trap Bar']`; `sled-push` and `sled-drag` == `['Sled']`; `cable-side-bend` == `['Cable Machine']`; `hanging-knee-raise` == `['Pull-up Bar']`. `getEquipment()` names as a set == the 12 S-19002 names. Red today.
- Fixture (b) Hive only (Mock has no equipment write path; log it): put box `exercise_equipment` key `exercise-trap-bar-deadlift` = `['equipment-barbell', 'equipment-trap-bar']` and key `exercise-sled-push` = `['equipment-sled']`; delete `equipment-trap-bar` and `equipment-sled` from box `equipment`.
- Expected (b): no throw. `trap-bar-deadlift` names == `['Barbell']`, and `sled-push` == `[]`. A guard only (green on today's code once the rows exist). Record it as a guard in the evidence file. The reviewer reads Mock's `whereType<Equipment>()` at `mock_workout_repository.dart:1030` as the Mock half.
- Edge case of: S-19006

## Iteration 1

### Phase 1: Equipment rows, SQL, version (@dba; item 4 by the lead)
1. [ ] Record baselines in the evidence file: the `flutter analyze` issue count (115a: 181) and pass/fail counts of the Done Criteria suites — `2026-11-04-115b-strength-catalog-gaps-plan.evidence.md`
2. [ ] Append the two D-19004 rows — `lib/mock/seed_data.dart:4500-4504` · `SeedData.sampleEquipment`
3. [ ] Add the four D-19005 inserts after `'Body Weight'`, and make the D-19005 comment edit — `scripts/sqlite_seed.sql:354`; `scripts/sqlite_schema.sql:1631-1632`
4. [ ] (lead) Set `bundledCatalogVersion = 15` and append the D-19006 sentence — `lib/core/constants/catalog_version.dart`
5. [ ] Write S-19002 (new group in `test/strength_catalog_gaps_test.dart`) and S-19003 (`test/db_seed_test.dart`, import `package:omnitrain/mock/seed_data.dart`). Show both red with items 2–3 reverted, then green; record it in the evidence file.

**Done Criteria** (Claude agents wrap in `bash .claude/scripts/macos/with-timeout.sh`; Copilot agents use the gateway):
- `flutter analyze`: issue count ≤ the item-1 baseline
- `flutter test test/strength_catalog_gaps_test.dart test/db_seed_test.dart test/catalog_referential_integrity_test.dart test/catalog_refresh_test.dart test/strength_catalog_refresh_test.dart test/tibialis_muscle_refresh_test.dart test/muscle_filter_test.dart`
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -c "INSERT OR IGNORE INTO app_equipment" scripts/sqlite_seed.sql` → 12; `grep -n "bundledCatalogVersion = 15" lib/core/constants/catalog_version.dart` → 1 line; `grep -c "id: 'equipment-" lib/mock/seed_data.dart` → 12

**Predicted Files**: `lib/mock/seed_data.dart`, `lib/core/constants/catalog_version.dart`, `scripts/sqlite_seed.sql`, `scripts/sqlite_schema.sql`, `test/strength_catalog_gaps_test.dart`, `test/db_seed_test.dart`, evidence file. Production diff: about 25 lines.

### Phase 2A: Rows 1–10, core and Push Press (@dba)
1. [ ] Append rows 1–5 to `sampleExercises` (D-19001, D-19002, D-19003) and to the capability, link and equipment maps — `lib/mock/seed_data.dart`
2. [ ] Same for rows 6–10
3. [ ] Add `_rows115b` (rows 1–10) and the S-19001 group to `test/strength_catalog_gaps_test.dart`. The shared guards (uniqueness, id order, sizes) cover both tables.
4. [ ] Set the link-map length to 216 at both `hasLength` sites — `test/catalog_referential_integrity_test.dart:205,270`
5. [ ] Show S-19001 red with items 1–2 reverted; paste the counts into the evidence file; update Progress and the Assumption Log

**Done Criteria**: Phase 1's suites plus `test/watch_reference_sync_test.dart`; `flutter analyze` ≤ baseline; `grep -c "^      id: 'exercise-" lib/mock/seed_data.dart` → 290.
**Predicted Files**: `lib/mock/seed_data.dart`, `test/strength_catalog_gaps_test.dart`, `test/catalog_referential_integrity_test.dart`, evidence file. Production diff: about 210 lines.

### Phase 2B: Rows 11–20, legs and hips (@dba; rows 19–20 follow Q1)
1. [ ] Append rows 11–15 as in 2A item 1 — `lib/mock/seed_data.dart`
2. [ ] Append rows 16–20 (rows 19–20 use C, or the Q1 answer if the owner picks (b))
3. [ ] Extend `_rows115b` to 20 rows; link-map length 226 at both sites; write the S-19004 assertions (Calves sets, assisting Abductors, Adductors, Lower back) — `test/strength_catalog_gaps_test.dart`, `test/catalog_referential_integrity_test.dart`
4. [ ] Show S-19001/S-19004 red with items 1–2 reverted; then run the full suite (`flutter test`, 900 s, output saved to a file). Fix any name-ordered or rank-ordered widget test in place and list it as an unpredicted file in the evidence file.

**Done Criteria**: Phase 2A's suites; `flutter test` (full) with 0 failures; `grep -c "^      id: 'exercise-" lib/mock/seed_data.dart` → 300.
**Predicted Files**: `lib/mock/seed_data.dart`, `test/strength_catalog_gaps_test.dart`, `test/catalog_referential_integrity_test.dart`, evidence file. Production diff: about 210 lines.

### Phase 3: Filter, refresh and equipment scenarios; docs; residue sweep (@dba)
1. [ ] Write S-19005 as a new group in `test/muscle_filter_test.dart`
2. [ ] Write S-19006, S-19007 and S-19008 in new `test/strength_catalog_v15_refresh_test.dart` (Hive staging in the test body; plain `test()`; reuse the 115a file's shape)
3. [ ] Show each "Red today" red: set the version back to 14 by hand for S-19006/7, and revert the 2A/2B rows for S-19005 and S-19008(a). Then show green. Record the red→green table and the Mock-only exceptions in the evidence file.
4. [ ] Add a sentence after the version-14 one: version `15` adds 20 core, leg/hip and press exercises; user-owned rows, same-name customs and renamed touched rows are never rewritten (cite `S-19006`, `S-19007`); the Trap Bar and Sled equipment rows reach new installs only (cite `S-19008`) — `docs/db_integration.md:133-138` (42,197 B; stay under 53,248)
5. [ ] `bundledCatalogVersion` `14` → `15` — `docs/constants_reference.md:575`
6. [ ] Apply the D-19011 wording — `docs/state_management/watch_reference_data.md:22`
7. [ ] Residue sweep, pasted into the evidence file: `grep -rn 'hasLength(206)\|hasLength(216)\|252 seeded' lib test docs | grep -v 'docs/plans\|docs/history\|docs/releases'` prints only hits proven unrelated; `grep -n 'bundledCatalogVersion' docs/constants_reference.md` shows `15` in the table row; `grep -rn "equipment relationships" scripts docs lib | grep -v "docs/plans\|docs/history\|docs/releases"` prints no claim that the refresh delivers equipment; `grep -n "Trap\|Sled\|equipment-" docs/data_models.md` → 0 (no equipment list to update)

**Done Criteria**: `flutter test test/muscle_filter_test.dart test/strength_catalog_v15_refresh_test.dart test/strength_catalog_refresh_test.dart test/catalog_refresh_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`; `flutter test` (full, 900 s) with 0 failures; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` prints nothing; `wc -c docs/db_integration.md docs/constants_reference.md docs/state_management/watch_reference_data.md` each < 53,248.
**Predicted Files**: `test/muscle_filter_test.dart`, `test/strength_catalog_v15_refresh_test.dart` (new), `docs/db_integration.md`, `docs/constants_reference.md`, `docs/state_management/watch_reference_data.md`, evidence file.

### Phase 4: Review (@code-reviewer)
Diff versus every phase's Predicted Files, and the Diff-boundary invariant:
`git diff --stat -- lib/features lib/widgets lib/state lib/core/services lib/core/utils lib/data lib/watch watch lib/core/constants/data_version.dart` prints nothing,
and `git diff -- scripts/sqlite_schema.sql` touches comment lines only. Re-run every Impact grep. Read all 20 texts
against D-18907 and D-19003, and the tagging against the table. Mutations, each of which must turn the named tests red:
- M1: Trap Bar row removed from `sampleEquipment` → S-19002, R-002, S-19008(a)
- M2: the `'Sled'` SQL insert removed → S-19003
- M3: version left at 14 → S-19006, S-19007
- M4: the touched-skip in `_refreshExercises` removed → S-19007
- M5: Curtsy Lunge's Abductors link made main → S-19001, S-19004, S-19005
- M6: `distance` dropped from Sled Push → S-19001
- M7: row 2 renamed "Cable Crunch" → S-19001 (name uniqueness)
- M8: the link row of `exercise-donkey-calf-raise` removed → S-19001, S-19004, S-19006

Findings go in `2026-11-04-115b-strength-catalog-gaps-plan.review.md`.

## Files Affected

Production: `seed_data.dart`, `catalog_version.dart` (lead), `sqlite_seed.sql`, `sqlite_schema.sql` (comment). About 445 lines.
Read-only dependents, guarded by tests: both repositories (equipment readers), `catalog_refresh_service.dart`,
`bundled_catalog_source.dart`, `watch_reference_sync.dart`, `modality_config.dart`, `session_core_entry.dart`, the
exercise library, picker, editor and detail screens.

## Notes

- **Scope budget (measured at planning):** 4 implementation phases, one track, 11 decisions, 8 scenarios, about 445
  predicted production lines, and no missing prerequisite (equipment delivery is decided out of scope, D-18909). That
  is one soft signal (more than 3 phases), so there is **no split**. A 115b1/115b2 split was weighed and rejected: it
  would double the version bumps, the refresh test files and the review rounds to save about 210 seed lines.
- **Dependency graph:** 1 → 2A → 2B → 3 → 4. 2A and 2B touch the same table and sizes, so run them in order. 2B can
  run before Q1 is answered, because the default is applied. If the owner picks (b), only rows 19–20's capabilities
  and S-19004/S-19005's sled expectations change.
- **Intermediate states:** after Phase 1, version 15 ships no new exercises and the two equipment rows have no
  links. After 2A, the core rows exist but the leg rows do not. Do not ship either state.
- **No migration:** the refresh delivers rows, capabilities and links (`catalog_refresh_service.dart:59-64`).
- **How an updated phone could hold a link to a missing equipment row:** only through
  `_migrateExerciseLibraryRefresh` (`hive_workout_repository.dart:836-871`), which writes the whole equipment-link
  map once on an install from before data version 10, but no equipment rows. S-19008(b) covers it.
- **Optional extras (priced, NOT in this PR):**
  - *Equipment delivery in the update* (carried from 115a): one @dba PR, about 100–150 production lines. After it,
    updated phones also get Trap Bar and Sled.
  - *Show equipment* on the detail screen or as a filter: a @developer PR of about 2 phases; needs the previous extra.
  - *Timer-and-distance logging for carries and sleds inside Strength workouts* (Q1 option c): a @developer PR of
    about 2 phases, with product calls; changes Farmer's Carry too.
  - *Tag Farmer's Carry with Trap Bar* as well as Dumbbell (its description names both): 1 seed line, invisible today.
  - *Empty equipment on existing rows* (51 rows, carried from 115a; Leg Press among them): seed only, about 51 lines.
- **Follow-ups:** conditioning/plyometrics (needs discipline delivery or an existing discipline), then yoga.

## Progress
- [ ] Phase 1 · [ ] Phase 2A · [ ] Phase 2B · [ ] Phase 3 · [ ] Phase 4 review

## Assumption Log

## Feedback
