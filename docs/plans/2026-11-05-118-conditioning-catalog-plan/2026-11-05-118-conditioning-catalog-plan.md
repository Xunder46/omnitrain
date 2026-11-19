# 118 — 17 conditioning and plyometric exercises under a new "Conditioning" discipline

> Status: Iteration 2 ready (re-based 2026-11-05 on the committed yoga tree, HEAD ecf2d050). Q2 is answered by the owner
> ("Conditioning", the long name is too long); Q1, Q3 and Q4 apply their defaults.
> Next handoff: @dba (Phase 1), run by the crew as `crew-builder-data`. Phase 1 item 3 (the version bump) is made by the
> lead: `crew-builder-data` cannot write `lib/core/**`.
> Precondition met: plan 117 (`docs/plans/2026-11-04-117-retire-orphan-template-rows-plan/`) and plan 119 (yoga,
> commit ecf2d050: 22 poses, `bundledCatalogVersion` 17, 322 seeded exercises) are committed. Never touch plan 119's
> folder or the 115 series index.
> Binding conventions: `docs/global_conventions.md`, `docs/db_integration.md` ("Catalog version + seed-entry tombstones"), `docs/data_models.md`
> Track: phone only (`lib/mock/`, `lib/core/constants/catalog_version.dart`, `scripts/`, `test/`, `docs/`). Never branch or commit.
> Precedent: plans 115a, 115b and 116. Their decisions D-18907 (text), D-18908 (capability codes), D-18910 and D-19009
> (user-owned rows) and D-19101/D-19102 (reference-data delivery) bind this PR as written there.

## Goal and acceptance

17 conditioning and plyometric exercises and one new "Conditioning" discipline ship in the bundled catalog, reach
existing installs on catalog version 18, and rank as recommended in Strength workouts. Acceptance rows A1–A9 are in
"Requirements and Acceptance Criteria" below.

## Overview

Classification: **STANDARD**. The PR adds bundled reference data: one discipline and 17 exercises. Existing installs
receive both through the catalog refresh. The watch's exercise list stays four batches (339 rows).

What a user sees after this PR:

1. 17 new exercises in the library, the picker and the watch's exercise list (after its next sync): Burpee, Squat
   Thrust, Box Jump, Jump Squat, Tuck Jump, Broad Jump, Jump Lunge, Skater Jump, Plyo Push-Up, Mountain Climber,
   Bear Crawl, Jumping Jack, High Knees, Battle Ropes, Medicine Ball Slam, Wall Ball and Thruster. Each has a
   description, how-to steps, and main and assisting muscles on its detail screen.
2. The **Discipline** filter in the library and the picker gains **Conditioning**. Picking it lists
   exactly these 17. The picker and library rows show that name under each exercise.
3. In a **Strength** workout the picker lists them in the "recommended" part. The bodyweight ones sit just below the
   weighted lifts, next to Push-Up. They are logged as sets of reps, with the usual weight box (on a bodyweight move a
   typed weight counts as added weight, as on Push-Up). In a **Free** workout, adding one asks "How to track?" with
   Reps or Time. In a **Cardio** workout they appear only in the lower, "other" part of the list.
4. The **Muscle** filter lists them under their main muscles. For example, Chest gains Burpee and Plyo Push-Up,
   Core gains Mountain Climber, Bear Crawl, Squat Thrust and Medicine Ball Slam, and Calves gains Jumping Jack.
5. Existing installs get the discipline and all 17 exercises on the next launch. The user's own exercises (a custom
   "Burpee" included), copies, and bundled rows the user edited are not changed.
6. A Burpee workout records in Apple Health the way any lift does (Q3). No equipment shows anywhere, because no
   screen shows equipment.
7. A circuit such as "5 rounds of 40 seconds" is a saved routine of these exercises. There is no new logging mode.

## Owner questions (one batch; the plan applies every default)

- **Q1. Where do these exercises live?** Default: **(a) a new discipline, "Conditioning", under
  Resistance / Lifting.** They rank as recommended in Strength workouts and are filterable as one group.
  Alternatives:
  - (b) Put them under the existing **Calisthenics** discipline. Today Calisthenics holds no exercise at all, so
    picking it in the Discipline filter shows an empty list. Choosing (b) would fill it, but Medicine Ball Slam, Wall
    Ball, Thruster and Battle Ropes would be labelled "Calisthenics".
  - (c) Put them under Cardio. They would then rank low in Strength workouts and could not be logged as sets there
    by default.
- **Q2. The discipline's name on screen.** **Owner decision (2026-11-05): "Conditioning"** (the proposed
  "Plyometrics & Conditioning" was too long for the half-width Discipline filter). Id `discipline-conditioning`, key
  `conditioning`. No existing discipline, sport or seed key uses either.
- **Q3. What Apple Health records for a workout of these exercises.** Default: **no change**. A **Strength** workout
  records as "Traditional Strength Training" from the phone and from the watch. A **Free** workout records as "Other"
  when logged on the phone. On the watch it records as "Traditional Strength Training", because the watch picks the
  type that most of the workout's exercises fit, and all 17 are counted in reps. Alternative: record such workouts as
  "High Intensity Interval Training". That changes the phone's Health writer, the phone-watch contract and the watch
  app. It would be a separate PR of about 3 phases across three tracks.
- **Q4. Naturally timed moves (Battle Ropes, Mountain Climber, High Knees, Jumping Jack) in a Strength workout.**
  Default: **(a) log them like Push-Up, as sets of reps.** You count waves or steps, and Time is offered in Free
  workouts. Alternative: (b) a timer logger inside Strength workouts. That changes the logger rather than the
  catalog: a separate @developer PR of about 2 phases, and it would also change Farmer's Carry and the sleds
  (115b Q1 option c).

## Decision Ledger (Resolved Decisions)

- **D-19201 (Q1 default, Q2 owner answer) The discipline.** Insert, directly after the `discipline-calisthenics` row in
  `SeedData.sampleDisciplines` (`lib/mock/seed_data.dart`, grep `id: 'discipline-calisthenics'`), in the existing
  form: `Discipline(id: 'discipline-conditioning', categoryId: 'category-resistance', key: 'conditioning',
  name: 'Conditioning', createdAtMs: DateTime.now().millisecondsSinceEpoch, updatedAtMs: …same)`. The
  catalog refresh delivers it (plan 116 D-19101; leg order D-19106 runs disciplines before exercises).
  `catalog_delivery_contract_test.dart` covers it with no edit, because its checks 4 and 5 compare id sets.
  Under Q1(b) a superseding entry drops this row and points every new row at `discipline-calisthenics`.
- **D-19202 The 17 rows.** They are exactly the **New-row table** below. Ids are `exercise-<slug>`. Every row has
  `disciplineId: 'discipline-conditioning'` and no `ownerUserId`. The rows are appended in table order after the
  `exercise-sled-drag` entry of `SeedData.sampleExercises`, and after the `exercise-sled-drag` key of each of
  `exerciseMuscleLinks`, `exerciseEquipmentRelationships` and `exerciseCapabilityRelationships`. Use grep anchors,
  not line numbers. Plan 119 has landed: its rows already follow `exercise-sled-drag`, so append after the LAST existing entry of each
  list and map (the yoga rows' tail), keeping table order. No id exists
  today: `grep -rn "discipline-conditioning\|exercise-burpee\|exercise-box-jump\|exercise-thruster\|exercise-wall-ball\|exercise-battle-ropes\|exercise-mountain-climber" lib test watch scripts docs`
  outside `docs/plans` → 0 (run 2026-11-04). Every new id sorts after `exercise-2k-row-test`.
- **D-19203 Capabilities.** Codes from D-18908: **BW** = `['reps', 'sets', 'time']` (the exact list of
  `exercise-push-up`) and **L** = `['reps', 'sets', 'load', 'time']`. No row carries `bilateral`, `hold`, `distance`
  or `rounds`. The ranking that follows (`ModalityConfig.calculateRelevanceScore`,
  `lib/core/constants/modality_config.dart:277-329`): "discipline points" are the +40 a row gets when its
  discipline's `categoryId` equals the modality's `categoryId`. The repositories resolve that category from the
  stored discipline (`mock_workout_repository.dart` / `hive_workout_repository.dart` `getExercisesRankedForModality`).
  - Strength: BW = 40 + 30·2/3 + 10 = **70**; L = 40 + 30 + 10 = **80**. Both are ≥ 50, so both are "recommended".
  - Strength with the discipline row missing: BW = 0 + 20 + 10 = **30**; L = **40**. Both fall under "other".
  - Cardio: BW = 15·1 = **15** (time is 1 of 2 primaries); L = 15 − 20·1/2 = **5**.
- **D-19204 Text.** D-18907 applies. On top of it:
  - Burpee says the chest touches the floor and the rep ends in a jump. Squat Thrust says it is a burpee with no
    push-up and no jump.
  - Box Jump says to step down, not jump down. Plyo Push-Up says the hands leave the floor.
  - Bear Crawl says the knees hover just off the floor. Battle Ropes says the arms alternate in waves.
  - Wall Ball says the ball is thrown to a target high on a wall and caught into the next squat. Thruster says a
    front squat flows into an overhead press in one motion. Medicine Ball Slam says to use a ball that does not bounce.
  - The descriptions of Mountain Climber, High Knees, Jumping Jack and Battle Ropes end with "Count reps, or log it
    by time."
  - No brand names.
- **D-19205 Muscles.** Existing ids only, and never a region id, so the twelve-row region guard stays exact. No
  new row links `muscle-tibialis`, `-abductors`, `-adductors`, `-rotator-cuff`, `-brachialis` or `-biceps`. The
  115a/115b exact sets for those stay exact. Calves changes deliberately: Main Calves gains `jumping-jack`.
  Assisting Calves gains `box-jump`, `jump-squat`, `tuck-jump`, `broad-jump`, `jump-lunge`, `skater-jump` and
  `high-knees`. Because only main links count in the filter (D-18903), the Calves filter gains Jumping Jack only.
- **D-19206 Equipment (owner: no equipment delivery).** Each row gets one entry in
  `exerciseEquipmentRelationships`, using existing ids only. Where no existing row fits, the entry is `[]`: Box Jump
  (no box), Battle Ropes, Medicine Ball Slam and Wall Ball (no rope or ball). This is the form of the 51 existing
  `[]` rows, `exercise-kettlebell-swing` among them. No equipment row is added. Updated phones hold no equipment link
  for any new row. That is invisible: `grep -rn -i equipment lib/features lib/widgets lib/state` → 0.
- **D-19207 Version (lead).** Raise `bundledCatalogVersion` (`lib/core/constants/catalog_version.dart:74`) from
  **17 to 18** (plan 119 took 17). Append to the history:
  "When the Conditioning discipline and 17 conditioning and plyometric exercises (Burpee through
  Thruster) were added, we bumped to `18` so existing installs receive the discipline and the exercises on next
  launch." Tests stage the literal `17` and assert `bundledCatalogVersion >= 18`, never `== 18`.
  `currentDataVersion` is not touched.
- **D-19208 SQL contract.** `scripts/sqlite_seed.sql` gains one `app_discipline` insert, in the existing
  `INSERT … SELECT … FROM app_sport_category c WHERE c.key='resistance_lifting' AND NOT EXISTS (… key='conditioning')`
  form, directly after the `calisthenics` insert. No exercise, link or equipment rows. `scripts/sqlite_schema.sql`
  is unchanged. Seen, not fixed: the SQL lacks 10 seed disciplines (tennis, volleyball, badminton, table_tennis,
  cricket, ice_hockey, baseball, american_football, rugby, lacrosse). See Notes, Optional extras.
- **D-19209 Watch (no watch, contract, Swift or watch-test change).** `WatchReferenceSync.buildExercisesDown`
  (`lib/core/utils/watch_reference_sync.dart`) sends every exercise that has capabilities, in batches of ≤ 100.
  Plan 119 already took the list from 3 to 4 batches (322 rows) and re-pinned the five assertions (`hasLength(4)`;
  `[0, 1, 2, 3]`; four `exercises_down`). 322 + 17 = 339 rows is still 4 batches, so every pin stays green and
  **nothing in the watch tests changes**. S-19208 only runs them as a guard. The count would reach 5 batches at 401
  rows, which is a later plan's pin to move. Nothing on the wrist limits the count (schema `batchCount` has
  `minimum: 1` and no maximum; Swift completeness is `Set(batchIndex) == Set(0..<batchCount)`).
- **D-19210 (Q3 default) Health unchanged.** `WatchReferenceSync.healthActivityOf` returns null for every new row,
  because none has `distance`. So `exercises_down` carries no `healthActivity` for them. The watch types the
  workout through `WatchActivityTypes` (modality first, otherwise the majority by capabilities → strength). The phone
  writes through `mapModalityToActivityKind` (`lib/core/services/health_modality_mapper.dart`). No code changes.
- **D-19211 User-owned rows.** D-18910 and D-19009 apply. A custom "Burpee", near-twins ("burpee ", "Burpees"), a
  copy, and a bundled row the user renamed to a new name and that is marked touched are never rewritten. The bundled
  row arrives beside them, and the device may hold the same name twice. Bundled-name uniqueness is a seed rule only.
- **D-19212 Readers of the old version literal.** Plan 119 already made `test/catalog_reference_refresh_test.dart`
  read `bundledCatalogVersion` (no `equals(16)`/`equals(17)` pin is left: `grep -n "equals(1[67])" test/catalog_reference_refresh_test.dart`
  → 0; the one literal assert is `greaterThanOrEqualTo(16)`). Nothing needs a mechanical change. The new refresh
  test stages `17` and asserts `>= 18`.
- **D-19213 The global size guard.** After plan 119 `test/strength_catalog_gaps_test.dart` "catalog sizes" reads
  `252 + added + yogaCatalogRows.length` (exercises, capabilities), `188 + …` (equipment) and `178 + added + yogaLinks`
  (links, 21 of 22 yoga rows have a main muscle). Add a named const `_conditioningAdded = 17` (comment: "118
  conditioning: 17") and one term to each. `test/catalog_referential_integrity_test.dart` has the same `226 +
  yogaCatalogRows…` expression at two sites: each gains `+ 17`. Final sizes in the tree after this PR: exercises and
  capability rows **339**, equipment map **275**, link map **264**. A later plan adds its own term.
- **D-19214 Out of scope.** Equipment rows or delivery; any logger, effort-kind or Health change (Q3/Q4
  alternatives); a demo circuit routine; moving existing rows into Calisthenics; the SQL discipline drift; new
  muscles; any sport. No file under `lib/features/`, `lib/widgets/`, `lib/state/`, `lib/core/services/`,
  `lib/core/utils/`, `lib/data/`, `lib/watch/`, `watch/` changes.

### New-row table (D-19202; P = main, S = assists; "—" = null `movementPattern` / no equipment id)

| # | id (`exercise-…`) | Name | Pattern | Caps | P | S | Equipment |
|---|---|---|---|---|---|---|---|
| 1 | burpee | Burpee | — | BW | quads, chest | glutes, triceps, front-delts, abs | bodyweight |
| 2 | squat-thrust | Squat Thrust | — | BW | quads, abs | glutes, front-delts | bodyweight |
| 3 | box-jump | Box Jump | squat | BW | quads, glutes | hamstrings, calves | — (`[]`) |
| 4 | jump-squat | Jump Squat | squat | BW | quads, glutes | hamstrings, calves | bodyweight |
| 5 | tuck-jump | Tuck Jump | squat | BW | quads, glutes | abs, calves | bodyweight |
| 6 | broad-jump | Broad Jump | squat | BW | glutes, quads | hamstrings, calves | bodyweight |
| 7 | jump-lunge | Jump Lunge | lunge | BW | quads, glutes | hamstrings, calves | bodyweight |
| 8 | skater-jump | Skater Jump | lunge | BW | glutes, quads | hamstrings, calves | bodyweight |
| 9 | plyo-push-up | Plyo Push-Up | horizontal_push | BW | chest | triceps, front-delts, abs | bodyweight |
| 10 | mountain-climber | Mountain Climber | abs | BW | abs | quads, front-delts | bodyweight |
| 11 | bear-crawl | Bear Crawl | — | BW | abs, front-delts | quads, triceps | bodyweight |
| 12 | jumping-jack | Jumping Jack | — | BW | calves | glutes, side-delts | bodyweight |
| 13 | high-knees | High Knees | — | BW | quads | calves, abs | bodyweight |
| 14 | battle-ropes | Battle Ropes | — | BW | front-delts | side-delts, forearms, abs | — (`[]`) |
| 15 | medicine-ball-slam | Medicine Ball Slam | — | L | lats, abs | triceps, glutes | — (`[]`) |
| 16 | wall-ball | Wall Ball | squat | L | quads, glutes | front-delts, triceps | — (`[]`) |
| 17 | thruster | Thruster | squat | L | quads, front-delts | glutes, triceps, abs | barbell |

Rows 1–9 are Phase 2A and rows 10–17 are Phase 2B. Patterns come from the existing vocabulary
(`grep -o "movementPattern: '[a-z_]*'" lib/mock/seed_data.dart | sort -u`). `movementPattern` has no reader but the
refresh diff (115b D-19007), so a full-body move with no single sibling pattern gets none. Before writing, the
duplicate check ran against existing names: Kettlebell Swing, Push-Up, Pistol Squat, Jump Rope Steady/Intervals,
Farmer's Carry and Sled Push/Drag exist and are not re-added. None of the 17 names exists.

## Feature Invariants

- The refresh never rewrites a touched, copied or custom exercise, nor a reference row whose id is not bundled (D-19211, D-19102).
- `MockWorkoutRepository` and `HiveWorkoutRepository` return the same rows, scores, filter results and refresh outcomes
  in S-19205 to S-19207. The documented Mock exception is the 115a/115b one: Mock cannot remove an equipment link,
  so the "updated phone has no equipment" assertion runs on Hive only. Mock *can* remove a discipline (D-19108 hook).
- Diff boundary: D-19214's list prints nothing in `git diff --stat`; `scripts/sqlite_schema.sql` and
  `lib/core/constants/data_version.dart` are unchanged.

## Requirements and Acceptance Criteria

| Id | Acceptance (what a user sees) | Scenarios |
|---|---|---|
| A1 | The discipline exists under Resistance / Lifting, after Calisthenics in the bundle; its filter lists exactly the 17 | S-19201, S-19205 |
| A2 | 17 exercises exist with text, capabilities, muscles and (on new installs) equipment as tabled; bundled names stay unique | S-19202 |
| A3 | Strength picker: BW rows score 70, L rows 80 (recommended); Cardio: 15 / 5 | S-19205 |
| A4 | Muscle filters list them by main muscle only; Calves gains Jumping Jack only; 115a/115b exact sets unchanged | S-19204, S-19205 |
| A5 | A v17 phone missing the discipline and rows gets both on next launch; user-owned rows untouched | S-19206 |
| A6 | An exercise whose discipline is missing ranks without discipline points, and with them after the refresh | S-19207 |
| A7 | The watch list still arrives in four batches at 339 rows, each accepted, each under the frame budget | S-19208 |
| A8 | Health type unchanged; no `healthActivity` on new rows | S-19209 |
| A9 | The SQL contract carries the discipline | S-19203 |

## Existing-Functionality Impact (greps run 2026-11-05 on `claude_develop`, HEAD ecf2d050, plans 117 and 119 committed)

| Touched surface | Readers (grep) | Effect | Guard |
|---|---|---|---|
| `SeedData.sampleDisciplines` | `grep -rn sampleDisciplines lib test` → `bundled_catalog_source.dart:46`, Mock init `:155`, Hive seed `:626` and migration `:838`, `catalog_reference_refresh_test.dart:92,401,1071-1074`, `catalog_delivery_contract_test.dart:67-69,156` | New installs and the refresh gain one row. S-19106 depends only on golf preceding climbing, which holds. Contract checks compare id sets | S-19201, S-19206, contract test green |
| Discipline lists on screen | `getDisciplines()` → `exercise_library.dart:274` → `ExerciseFilterRow` (`lib/widgets/exercise/exercise_filter_row.dart:49`, all disciplines, store order) and editor (`ModalityConfig.disciplinesForModality`, `exercise_editor_screen.dart:215`) | Hive returns key order, so the menu shows it between Padel and Powerlifting. Mock shows it after Calisthenics on a fresh install and last after a refresh. No test pins the list: `grep -rn "Calisthenics\|Olympic Weightlifting" test` → 0 | S-19201 (bundle order) |
| Discipline label fallback | `exercise_picker_screen.dart:391-400,476` and `exercise_library_screen.dart:259-264,329` use `orElse:` with an empty name, and hide the label when it is empty | A missing discipline shows no label and no crash | S-19207 (repository half) |
| Ranking | `calculateRelevanceScore` (`modality_config.dart:277-329`); category lookup in both repositories' `getExercisesRankedForModality` | D-19203 numbers. New BW names (Bear Crawl … Plyo Push-Up) sort before "Pull-Up" in the 70 band | S-19205, S-19207; full suite |
| Exact muscle sets | `catalog_referential_integrity_test.dart`: region-tagged 12 (`:208-231`), tibialis (`:~311`), main/assisting Calves, Abductors, Rotator cuff, Brachialis, Biceps (`:~320-400`); link map `hasLength(226)` at `:205,270` | Calves sets grow per D-19205; link map 226 → 243; the rest stay green by D-19205 | S-19204 |
| Catalog size guard | `strength_catalog_gaps_test.dart` "catalog sizes" (`252 + added + yogaCatalogRows.length`) | Red by design until D-19213 | S-19202 |
| First bilateral in ranked lists | `catalog_refresh_test.dart:1245`, `exercise_info_sheet_bilateral_test.dart:72` | No new row is bilateral | none needed |
| Catalog version literal | `grep -rn "equals(1[67])" test` → only `data_migration_test.dart` migration-step pins; the refresh tests read `bundledCatalogVersion` | None go red at 18 | D-19212 |
| Watch batch count | `hasLength(4)` at `watch_reference_sync_test.dart:596,624`; `[0, 1, 2, 3]` at `watch_sync_request_handler_test.dart:616,649,786,908,936,1050,1193` and `watch_sync_changed_only_test.dart:280,751`; four `exercises_down` in `watch_sync_request_handler_test.dart` and `watch_transport_test.dart` (S-003). All run over `MockWorkoutRepository().initialize()` | 339 rows → still 4 batches: all stay green. 5 batches start at 401 rows | S-19208 (guard only) |
| Health type | `healthActivityOf` (`watch_reference_sync.dart:499-519`) returns null without `distance`; `WatchActivityTypes.forSession` (`WatchPlatformWorkout.swift`); `mapModalityToActivityKind` | Unchanged (D-19210) | S-19209 |
| Name search | `grep -rn -i "searchText: '\|enterText(" test` matched against new names → only the synthetic `'squat'` in `records_and_trends_screen_test.dart:291` | "squat", "jump" and "push-up" return more rows on real catalogs | none needed |
| Name-ordered widget tests | 115a/115b list (`pr8_exercise_library_test`, `screen_widget_test`, `muscle_filter_picker_test`, …). `muscle_filter_picker_test.dart:292-295` "Press" + Triceps: no new row is main Triceps | Lazy lists could push a found name down | Phase 2B full suite |
| Stats, sessions, routines, calendar | `grep -rln "getExerciseMuscleLinks\|MuscleRole.primary" lib/core/services lib/state lib/features/stats` → only catalog/library code; routines store ids, and no routine names a new id | Unaffected | grep |
| SQL contract | `grep -n "app_discipline" test/*.dart` → 0; SQL has 26 of 36 disciplines | One insert added and newly guarded | S-19203 |
| Docs | `docs/constants_reference.md` (`bundledCatalogVersion` `17`, ~`:575`); `docs/db_integration.md` (version history, the version-17 paragraph plan 119 added); `docs/state_management/watch_reference_data.md:22` ("more than 300 seeded exercises", still true) | Version number stale after the PR | Phase 3 items 5–6 |

## UI Standards Impact

None. No UI file changes. The existing Discipline dropdown, picker tiles and detail screens render the new rows.

## Scenarios

Index of the scenarios below; the row form is for the linter, the bodies carry the fixtures.

| S-n | Fixture | Expect | Fails without |
|---|---|---|---|
| S-19201 | `SeedData.sampleDisciplines` | one Conditioning row after Calisthenics, 37 rows | the row is absent |
| S-19202 | const table of the 17 rows | rows conform, sizes 339/339/275/264 | the rows are absent |
| S-19203 | SQL seed in memory | one Conditioning discipline under resistance_lifting | the insert is absent |
| S-19204 | `exerciseMuscleLinks` | Calves/Lats/Chest sets extended, 264 entries | the ids are absent |
| S-19205 | fresh install, both harnesses | rank 70/80, filters, search | the rows and discipline are absent |
| S-19206 | v17 install refreshes | discipline and 17 rows land, user rows untouched | version gate skips the refresh |
| S-19207 | discipline row missing | rank 30/40 before, 70/80 after refresh | the rows do not exist |
| S-19208 | watch pins at 339 rows | four batches, unedited pins green | guard only, red past 400 rows |
| S-19209 | healthActivityOf and wire object | no healthActivity for the 17 | the rows do not exist |

Bodies follow; each body repeats its scenario's why.

Shared fixture notes:
- "Custom" means `createExercise(Exercise(id, ownerUserId: 'user-1', name, createdAtMs: 1700000000000, updatedAtMs: same))`
  followed by `setExerciseCapabilities` and `setExerciseMuscleLinks`.
- Mock and Hive cases run over `harnessFactories` (`test/helpers/repository_harness.dart`) with plain `test()`,
  never `testWidgets`, and with `const BundledCatalogSource()`.
- "Stage missing discipline" is the `_stageMissing` helper shape of `test/catalog_reference_refresh_test.dart:69-83`:
  the D-19108 hook on Mock, `Hive.box<Map>('disciplines').delete(id)` on Hive.
- `N` is the 17 table ids; `BW17` is rows 1–14 and `L17` is rows 15–17.

### S-19201: The discipline row (new `test/conditioning_catalog_test.dart`, pure)
- Fixture: `SeedData.sampleDisciplines` as shipped.
- Expected:
  - Exactly one row has id `discipline-conditioning`, with `categoryId` `category-resistance`, key
    `conditioning` and name `Conditioning`. Its index is calisthenics' index + 1.
  - Ids are unique, and the length is 37 (36 today).
  - `ModalityConfig.disciplinesForModality('resistance_lifting', SeedData.sampleDisciplines)` ids ==
    `[discipline-powerlifting, discipline-bodybuilding, discipline-weightlifting, discipline-calisthenics, discipline-conditioning]`.
  - No other row has the same key or name, ignoring case.
- Red today: the row is absent. Edge case of: none

### S-19202: New-row conformance and catalog guards (same file, pure; size guard in `test/strength_catalog_gaps_test.dart`)
- Fixture: a const table in the test mirroring the New-row table (BW and L written out). Phase 2A holds rows 1–9 and
  2B holds all 17.
- Expected, per row:
  - The row exists with the exact name, `discipline-conditioning`, the tabled pattern (null for "—"), `ownerUserId`
    null, a non-empty description and 3–4 non-empty `howToSteps`.
  - Its capabilities equal the tabled list in order, and its equipment equals the tabled list (`[]` for "—").
  - Its links equal `MuscleTaxonomy.normalize` of the tabled P/S.
- Tagging guard over the table: no link names a region id, `muscle-tibialis`, `-abductors`, `-adductors`,
  `-rotator-cuff`, `-brachialis` or `-biceps`.
- Every id sorts after `exercise-2k-row-test`. Bundled names stay unique ignoring case and spaces (the existing gaps
  test covers the whole list).
- Sizes, through D-19213: exercises 339, capabilities 339, equipment 275, links 264.
- Red today: rows absent. Edge case of: none

### S-19203: The SQL contract carries the discipline (`test/db_seed_test.dart`, new test in `Pipeline schema documentation`)
- Fixture: the S-9 harness (schema, then every statement of `sqlite_seed.sql`).
- Expected: `SELECT d.name, c.key FROM app_discipline d JOIN app_sport_category c ON d.category_id = c.id WHERE d.key = 'conditioning'`
  returns exactly one row: (`Conditioning`, `resistance_lifting`). Running the seed twice still gives one
  row (the `NOT EXISTS` guard). Title: `S-19203 app_discipline carries Conditioning under resistance_lifting`.
- Red today. Edge case of: none

### S-19204: The bundled link sets (`test/catalog_referential_integrity_test.dart`, approved-rows test)
- Fixture: `SeedData.exerciseMuscleLinks` as shipped.
- Expected:
  - Map length 264 at both sites (256 after 2A).
  - Main Calves == the existing ids (read the set in the tree) plus `jumping-jack`.
  - Assisting Calves == the set in the tree today (it now includes plan 119's yoga ids) plus `{box-jump, jump-squat, tuck-jump, broad-jump, jump-lunge, skater-jump, high-knees}`.
  - Tibialis-tagged == `{tibialis-raise}`. The region-tagged 12 and every 115a/115b Abductors, Rotator cuff,
    Brachialis and Biceps set are unchanged.
  - Main Lats contains `medicine-ball-slam`.
- Red today: the new ids are absent. Edge case of: none

### S-19205: Fresh install, ranking and filters (new `test/conditioning_catalog_refresh_test.dart`, both harnesses)
- Fixture: the bundled catalog plus three customs (no discipline, caps BW):
  - U "Burpee" `[quads P]`, the same name as a bundled row;
  - T1 "burpee " (lower case, trailing space) `[quads P]`;
  - T2 "Burpees" `[chest P]`.
- Expected:
  - `getExercisesRankedForModality('resistance_lifting')`: each BW17 row has `relevanceScore == 70.0` and each L17
    row `80.0`. Every N row precedes every row scoring below 50. Ties follow name order (Bear Crawl before Box Jump).
  - `getExercisesRankedForModality('resistance_lifting', disciplineId: 'discipline-conditioning')` ids as a set == N.
    U, T1 and T2 are excluded.
  - `getExercisesRankedForModality('cardio_endurance')`: `burpee` scores `15.0` and `thruster` `5.0`.
  - `searchExercises(muscleGroupIds: …)`:
    - Chest contains `burpee` and `plyo-push-up`, and T2.
    - Core contains `mountain-climber`, `bear-crawl`, `squat-thrust` and `medicine-ball-slam`, each once.
    - Calves contains `jumping-jack` and excludes `box-jump` and `high-knees`.
    - Lats contains `medicine-ball-slam`. Shoulders contains `thruster` and `battle-ropes`, each once.
  - `searchExercises(searchText: 'Burpee')` contains U, T1, T2 and `exercise-burpee`.
  - `getDisciplineById('discipline-conditioning')!.name == 'Conditioning'`.
  - `getExerciseEquipment('exercise-thruster')` names == `['Barbell']`, and `exercise-box-jump` == `[]`.
- Red today: the rows and the discipline are absent. Edge case of: none

### S-19206: A v17 install refreshes (same file, both harnesses)
- Fixture (after `harness.open()`):
  1. Stage missing discipline `discipline-conditioning`, then assert `getDisciplineById` is null.
  2. For each N id: `deleteExercise(id)`, `setExerciseCapabilities(id, [])`, `setExerciseMuscleLinks(id, [])`. On
     Hive, also delete the id from box `exercise_equipment`.
  3. Customs U, T1 and T2 as in S-19205. Record each one's `toMap()`, capabilities and links.
  4. A user-edited bundled row: `exercise-push-up` renamed "Plyo Push-Up" via `updateExercise`, links
     `[chest P, triceps S]`, then `markSeedEntryTouched(SeedEntryType.exercise, 'exercise-push-up')`.
  5. Copy K = `ExerciseLibraryService(repo).copyAsCustom(exercise-kettlebell-swing)`. Record its links.
  6. `setCatalogVersion(17)` (the literal).
- Trigger: `CatalogRefreshService(repo, const BundledCatalogSource()).refresh()`.
- Expected:
  - Returns true. `getCatalogVersion() == bundledCatalogVersion`, and `bundledCatalogVersion >= 18`.
  - The discipline equals the bundled row on `categoryId`, `key` and `name`.
  - Each N id exists with its table name and `discipline-conditioning`. Its capabilities and links equal the bundled
    ones (as multisets).
  - U, T1, T2 and K are identical to their recordings.
  - `exercise-push-up` keeps the name "Plyo Push-Up" and its links. `searchExercises(searchText: 'Plyo Push-Up')`
    contains both `exercise-push-up` and `exercise-plyo-push-up`.
  - The ranked Strength list now scores `burpee` 70.0.
  - Hive only: `getExerciseEquipment('exercise-thruster')` is empty. This pins D-19206.
  - A second `refresh()` returns false, and everything above is unchanged.
- Red today: with the version at 17 the refresh returns false, and the discipline and rows stay absent.
  Edge case of: none

### S-19207: An exercise whose discipline is missing (same file, both harnesses)
- Fixture: fresh install. Stage missing `discipline-conditioning` only; all 17 rows stay. `setCatalogVersion(17)`.
- Expected before the refresh:
  - `getDisciplineById('discipline-conditioning')` is null. `exercise-burpee` still has that `disciplineId`.
  - The ranked Strength list scores `burpee` **30.0** and `thruster` **40.0** (D-19203), both below the 50
    threshold, and neither throws.
  - The discipline filter still returns the 17, because it matches on the exercise's id.
- After `refresh()` (true): the discipline is back, `burpee` scores 70.0 and `thruster` 80.0.
- Red today: on today's code the rows do not exist. After Phase 2B, a guard: it turns red if the ranking stops
  resolving the category from the stored discipline.
- Edge case of: S-19206

### S-19208: The watch list stays four batches at 339 rows (guard only; no test file changes)
- Fixture: `MockWorkoutRepository().initialize()` (the seeded catalog).
- Expected: the existing pins of D-19209 (`watch_reference_sync_test.dart` S-3858, `watch_sync_request_handler_test.dart`
  S-3851/S-3852, `watch_sync_changed_only_test.dart` S-9201, `watch_transport_test.dart` S-003) stay green unedited at
  339 rows: four batches, indices `[0, 1, 2, 3]`, four `exercises_down` then `bests_down`.
- Red today: none. A guard: it turns red only if the catalog crosses 400 capable rows. The builder runs the five files
  after Phase 2B and records the counts. Edge case of: none

### S-19209: No Health kind for the new rows (`test/conditioning_catalog_test.dart`, pure + Mock)
- Fixture: the 17 table rows.
- Expected: `WatchReferenceSync.healthActivityOf(disciplineId: 'discipline-conditioning', exerciseId: id, capabilities: caps)`
  is null for each row. In `buildExercisesDown` over a fresh Mock, the wire object of `exercise-burpee` has no
  `healthActivity` key.
- A guard (green once the rows exist). Under the Q3 alternative this scenario is superseded. Edge case of: none

## Phases (Iteration 2)

### Phase 1: Discipline, version, SQL (@dba · `crew-builder-data`; item 3 by the lead)
1. [ ] Record baselines in the evidence file: the `flutter analyze` issue count and the pass/fail counts of the Done Criteria suites. Plan 119 has landed (record HEAD) — `2026-11-05-118-conditioning-catalog-plan.evidence.md`
2. [ ] Add the D-19201 row — `lib/mock/seed_data.dart` · `SeedData.sampleDisciplines` (anchor `id: 'discipline-calisthenics'`)
3. [ ] (lead) Raise `bundledCatalogVersion` and add the D-19207 history sentence — `lib/core/constants/catalog_version.dart`
4. [ ] Add the D-19208 insert after the `calisthenics` insert — `scripts/sqlite_seed.sql`
5. [ ] Run the five watch files of D-19209 as they stand and record the counts (S-19208 baseline, no edit)
6. [ ] Write S-19201 (new `test/conditioning_catalog_test.dart`) and S-19203 (`test/db_seed_test.dart`, title `S-19203 app_discipline carries Conditioning under resistance_lifting`). Show them red with items 2 and 4 reverted, then green; record it in the evidence file; update Progress and the Assumption Log

**Done Criteria** (Claude agents wrap in `bash .claude/scripts/macos/with-timeout.sh`; Copilot agents use the gateway):
- `flutter analyze`: issue count ≤ the item-1 baseline
- `flutter test test/conditioning_catalog_test.dart test/db_seed_test.dart test/catalog_reference_refresh_test.dart test/catalog_delivery_contract_test.dart test/reference_data_upsert_test.dart test/catalog_refresh_test.dart test/watch_reference_sync_test.dart test/watch_sync_request_handler_test.dart test/watch_sync_changed_only_test.dart test/watch_transport_test.dart`
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -c "discipline-conditioning" lib/mock/seed_data.dart` → 1; `grep -c "key='conditioning'\|'conditioning', 'Conditioning'" scripts/sqlite_seed.sql` → 2 (value + guard); `grep -n "bundledCatalogVersion = 18" lib/core/constants/catalog_version.dart` → 1
**Predicted Files**: `lib/mock/seed_data.dart`, `lib/core/constants/catalog_version.dart`, `scripts/sqlite_seed.sql`, `test/conditioning_catalog_test.dart` (new), `test/db_seed_test.dart`, evidence file. Production diff: about 15 lines.

### Phase 2A: Rows 1–9, jumps, burpees and Plyo Push-Up (@dba · `crew-builder-data`)
1. [x] Append rows 1–5 to `sampleExercises` (D-19202, D-19204) and to the three maps (D-19203, D-19205, D-19206) — `lib/mock/seed_data.dart`
2. [x] Same for rows 6–9
3. [x] Add S-19202 to `test/conditioning_catalog_test.dart` over rows 1–9; apply D-19213 with `_conditioningAdded` at 9 — `test/strength_catalog_gaps_test.dart`
4. [x] S-19204 so far: link map 256 (247 + 9); Assisting Calves gains the six 2A ids — `test/catalog_referential_integrity_test.dart`
5. [x] Show S-19202 red with items 1–2 reverted; paste counts into the evidence file; update Progress and the Assumption Log

Items 3–4 read the shared `conditioningCatalogRows` list instead of a `_conditioningAdded` const (A-118-1).

**Done Criteria**: Phase 1's suites plus `test/strength_catalog_gaps_test.dart test/catalog_referential_integrity_test.dart test/muscle_filter_test.dart`; `flutter analyze` ≤ baseline; `grep -c "disciplineId: 'discipline-conditioning'" lib/mock/seed_data.dart` → 9.
**Predicted Files**: `lib/mock/seed_data.dart`, `test/conditioning_catalog_test.dart`, `test/strength_catalog_gaps_test.dart`, `test/catalog_referential_integrity_test.dart`, evidence file. Production diff: about 210 lines.

### Phase 2B: Rows 10–17, timed moves and loaded throws (@dba · `crew-builder-data`)
1. [ ] Append rows 10–13 as in 2A item 1 — `lib/mock/seed_data.dart`
2. [ ] Append rows 14–17
3. [ ] Extend the S-19202 table to 17 and set `_conditioningAdded` to 17; S-19204 complete (link map 264 at both sites, Main Calves + `jumping-jack`, Assisting Calves + `high-knees`, Main Lats contains `medicine-ball-slam`)
4. [ ] Add S-19209 to `test/conditioning_catalog_test.dart`; S-19208: run the five watch files unedited and record that they are green at 339 rows (four batches)
5. [ ] Report any name-ordered widget test you suspect (the lead runs the full suite and brings back failures)

**Done Criteria**: Phase 2A's suites plus the five watch files; the builder does NOT run the full suite (the lead does); `grep -c "disciplineId: 'discipline-conditioning'" lib/mock/seed_data.dart` → 17; `grep -c "^      id: 'exercise-" lib/mock/seed_data.dart` → 339 (count the same pattern before the phase and add 8, then 9 earlier).
**Predicted Files**: `lib/mock/seed_data.dart`, `test/conditioning_catalog_test.dart`, `test/strength_catalog_gaps_test.dart`, `test/catalog_referential_integrity_test.dart`, evidence file. Production diff: about 190 lines.

### Phase 3: Ranking, refresh and missing-discipline scenarios; docs; residue sweep (@dba · `crew-builder-data`)
1. [ ] Write S-19205 in new `test/conditioning_catalog_refresh_test.dart`. Copy the header and shape of `test/strength_catalog_v15_refresh_test.dart`: the plan path, the S-ids, `harnessFactories`, Hive staging in the test body
2. [ ] Write S-19206 in the same file
3. [ ] Write S-19207 in the same file
4. [ ] Red→green. For S-19206 and S-19207, set the version back to 17 by hand, then remove the D-19201 row by hand, and show red. For S-19205, revert the rows. Restore all and show green. Record the table in the evidence file
5. [ ] `docs/db_integration.md` (check `wc -c` first; stay under 53,248): after the version-`17` (yoga) paragraph, add one sentence. Catalog version `18` adds the Conditioning discipline and 17 conditioning and plyometric exercises. A phone missing the discipline gets it before the exercises, so they rank with their discipline. Exercises the user owns are never rewritten. Cite `test/conditioning_catalog_refresh_test.dart` (`S-19206`, `S-19207`) and the SQL test title of S-19203
6. [ ] `docs/constants_reference.md`: `bundledCatalogVersion` `17` → `18` (the lead checks `grep -c "| `bundledCatalogVersion` | `18` |" docs/constants_reference.md` → 1; the lint row cannot hold a pipe). `docs/state_management/watch_reference_data.md` needs no edit ("more than 300 seeded exercises" stays true)
7. [ ] Residue sweep, pasted into the evidence file:
   - `grep -rn "Plyometrics & Conditioning\|discipline-plyometrics" lib test docs scripts | grep -v "docs/plans"` → 0
   - `grep -rn "equals(17)" test/catalog_reference_refresh_test.dart test/conditioning_catalog_refresh_test.dart` → 0
   - `wc -c` of the three docs, each < 53,248
8. [ ] Update Progress and the Assumption Log (the lead runs the full suite)

**Done Criteria**: `flutter test test/conditioning_catalog_refresh_test.dart test/conditioning_catalog_test.dart test/catalog_reference_refresh_test.dart test/catalog_delivery_contract_test.dart test/strength_catalog_v15_refresh_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`; full `flutter test` with 0 failures; `flutter analyze` ≤ baseline; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` prints nothing; the item-7 greps as stated.
**Predicted Files**: `test/conditioning_catalog_refresh_test.dart` (new), `docs/db_integration.md`, `docs/constants_reference.md`, `docs/state_management/watch_reference_data.md`, evidence file.

### Phase 4: Review (@code-reviewer)
Diff the change against every phase's Predicted Files and the D-19214 boundary:
`git diff --stat -- lib/features lib/widgets lib/state lib/core/services lib/core/utils lib/data lib/watch watch lib/core/constants/data_version.dart scripts/sqlite_schema.sql`
must print nothing. Then:
- Re-run every Impact grep, and read all 17 texts against D-18907 and D-19204.
- Check that the D-19209 claim holds: 339 capable rows is four batches (`watch_reference_sync.dart` batch size 100).
- Run the mutations below. Each must turn the named tests red:
  - M1: version left at 17 → S-19206, S-19207
  - M2: D-19201 row removed → S-19201, S-19205, S-19206 (the contract test stays green, as it compares sets: say so)
  - M3: `_refreshDisciplines` call removed from `refresh()` → S-19206, S-19207, the contract test check 5
  - M4: the ranking looks up the category by `exercise.disciplineId` without reading the stored discipline (for example, a constant `category-resistance`) → S-19207's before-refresh 30.0
  - M5: `jumping-jack` tagged Calves as an assist only → S-19204, S-19205
  - M6: Thruster's `load` dropped → S-19202, S-19205 (80 → 70)
  - M7: (retired: the watch pins do not change in this PR)
  - M8: row 1 renamed "Push-Up" → the gaps test's name-uniqueness guard
  - M9: the SQL insert removed → S-19203

Findings go in `2026-11-05-118-conditioning-catalog-plan.review.md`.

## Files Affected

Production: `lib/mock/seed_data.dart`, `lib/core/constants/catalog_version.dart` (lead), `scripts/sqlite_seed.sql`.
About 400 lines.
Tests: `conditioning_catalog_test.dart` (new), `conditioning_catalog_refresh_test.dart` (new), `db_seed_test.dart`,
`strength_catalog_gaps_test.dart`, `catalog_referential_integrity_test.dart`. No watch test file changes.
Read-only dependents, guarded by tests: `catalog_refresh_service.dart`, `bundled_catalog_source.dart`, both
repositories' ranking and discipline getters, `ExerciseFilterRow`, the picker, library, editor and detail screens,
`watch_reference_sync.dart`, `health_modality_mapper.dart`, the Swift `WatchActivityTypes` and `WatchStartPaths`.

## Notes

- **Scope budget (measured at planning):**
  - 4 implementation phases plus review, which is one soft signal (> 3 phases).
  - One track (phone; the watch tests exercise `lib/core/utils`, not `lib/watch/`).
  - 14 decisions, 9 scenarios, about 400 predicted production lines, no missing prerequisite.

  One soft signal does not require a split.
- **Dependency graph:** 1 → 2A → 2B → 3 → 4. 2A and 2B touch the same anchors, so run them in order. Phase 3 needs
  all 17 rows. Re-ordering 2B before 2A only changes the intermediate muscle sets.
- **Intermediate states:** after Phase 1, the discipline exists with no exercise, so its filter shows an empty list.
  The version is already bumped. Do not ship that state. After 2A the watch list is still 4 batches (331 rows).
- **Plan 119 interplay:** plan 119 landed first (ecf2d050). This plan is re-based on it: version 17 → 18, sizes 339 / 339 / 275 / 264, no
  watch pin edits. The Calves sets must be read in the tree before they are extended, because yoga rows joined them.
- **Optional extras (priced, NOT in this PR):**
  - *HIIT in Health* (Q3 alternative): phone mapper, `healthActivity` enum in the contract, and Swift. Three tracks,
    about 3 phases, its own PR.
  - *Timer logger in Strength workouts* (Q4 alternative): a @developer PR of about 2 phases.
  - *A "Conditioning Circuit" demo routine* (for example 5 rounds of Burpee, Mountain Climber and Jump Squat): a
    seed-only @dba PR, 1 phase, about 60 lines, delivered by the refresh.
  - *Fill Calisthenics* (Push-Up, Pull-Up, Dip, Pistol Squat and others): a product call. 1 @dba phase. It changes
    the discipline label those rows show.
  - *SQL discipline drift*: add the 10 missing sport disciplines and a test that the SQL disciplines equal the seed
    ones. 1 @dba phase, about 50 lines.
  - *Equipment delivery*: carried from 115a/115b/116, about 100–150 lines.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/db_integration.md` | ADDED | - | Conditioning discipline and 17 conditioning | S-19206 |
| `docs/constants_reference.md` | ADDED | - | Content version of the bundled catalog | S-19206 |

## Progress
- [x] Phase 1 · [x] Phase 2A · [x] Phase 2B · [x] Phase 3 (items 1–3 and 5 by `crew-builder-data`; item 4(b)/(c)
  blocked, see the Assumption Log; docs items were outside that run's write scope) · [ ] Phase 4 review

## Assumption Log

- 2026-11-05 Phase 1 (`crew-builder-data`): the brief says "five watch files" but names four
  (`watch_reference_sync_test.dart`, `watch_sync_request_handler_test.dart`, `watch_sync_changed_only_test.dart`,
  `watch_transport_test.dart`); those four ran unedited and green (`+156`), which is the S-19208 baseline.
- 2026-11-05 Phase 1: `ModalityConfig.disciplinesForModality('resistance_lifting', …)` returns
  powerlifting, bodybuilding, weightlifting, calisthenics, conditioning — the plan's expected order, read from the
  real bundle (the test asserts it, `+5` green).
- 2026-11-05 Phase 1: S-19201's "no other row shares its key or name" assertion passes vacuously while the row is
  absent, so the item-6 red run is `+1 -4`, not 0/5.
- 2026-11-05 Phase 1: the gateway `test` check does not forward `--plain-name` in the position used; red and green
  runs were made by whole file path.
- 2026-11-05 Phase 2A (`crew-builder-data`): **A-118-1** — the size guards read a shared helper list
  (`test/helpers/conditioning_catalog_rows.dart`), as plan 119's yoga guards do, instead of the plan's
  `_conditioningAdded` const; 2B extends the same list.
- 2026-11-05 Phase 2A: no exact Main Chest / Core set exists in `test/catalog_referential_integrity_test.dart`, so
  the only exact set the new links change is Assisting Calves, which gained the six jumping rows; Main Calves,
  Main Lats, Abductors, Rotator cuff, Brachialis and Biceps are untouched by rows 1-9.
- 2026-11-05 Phase 2A: the S-19202 group is red at `+5 -10` when the nine seed `Exercise` blocks are removed (the
  nine per-row tests plus the discipline's exact-set test), green at `+17` restored; the two Done Criteria suite
  runs are `+84` and `+140`, and `flutter analyze` stays at the 181 baseline.
- 2026-11-05 Phase 2B (`crew-builder-data`): rows 10–17 extend the same shared helper (A-118-1), so the plan's
  "set `_conditioningAdded` to 17" became "extend `conditioningCatalogRows` to 17"; the seed now holds 339
  exercise ids and 17 `discipline-conditioning` rows.
- 2026-11-05 Phase 2B: the plan's capability table gives row 14 (Battle Ropes) the BW list, so it carries
  `['reps', 'sets', 'time']` even though a rope is an implement; only rows 15–17 carry `load`, as the table says.
- 2026-11-05 Phase 2B: the "Core filter's group" assertion uses `mainIds('muscle-abs')`, since the library's Core
  filter maps to the abs muscle group; no exact Core set exists to extend, so the new block asserts containment.
- 2026-11-05 Phase 2B: the phase's red run removes one row (Mountain Climber) rather than all eight; it is `+36 -4`
  (that row's S-19202 test, the discipline's exact-set test, and the two keyed-by-real-exercises guards), green at
  `+40` restored. Name-ordered widget tests (`screen_widget_test`, `pr8_exercise_library_test`,
  `library_grouping_test`, `library_row_toggle_test`) were not run here; the full suite is the lead's.
- 2026-11-05 Phase 3 (`crew-builder-data`): the phase's red table has only half a red column. Item 4(a) (drop the
  discipline row) needed an edit to `lib/mock/seed_data.dart`, which is outside that run's write scope and was
  denied; 4(b) and 4(c) need the same file. `prove-red HEAD` cannot substitute: it copies only the named test files,
  so the untracked `test/helpers/conditioning_catalog_rows.dart` is missing at HEAD and the file fails to compile
  (`+6607 ~2 -1`), which says nothing about the assertions. The evidence file records those rows as blocked.
- 2026-11-05 Phase 3: the muscle-filter expectations use `searchExercises(muscleGroupIds: [...])`, the call shape
  `test/yoga_catalog_refresh_test.dart` uses, and the Core row runs over both `muscle-core` and `muscle-abs`, since
  `MuscleTaxonomy.matches` counts a region as its children's primary links (Phase 2B note) and the library's Core
  filter maps to abs.
- 2026-11-05 Phase 3: D-19203's 14-bodyweight / 3-loaded split is derived from `conditioningCatalogRows` (rows
  without `load` score 70, the three with `load` score 80) rather than from hand-typed id lists, and the ranking
  comparison is asserted once over the outer positions (last Conditioning index before the first below-50 index),
  not per pair.
- 2026-11-05 Phase 3: `Exercise` has no `copyWith` of its own; the S-19206 rename uses the `ExerciseCapabilities`
  extension in `lib/core/utils/exercise_helpers.dart`. S-19207's "the refreshed thruster has no equipment" is
  Hive-only, because `MockWorkoutRepository` cannot delete an equipment link.

## Feedback
