# 119 — Yoga poses in the bundled catalog

> Status: Iteration 1 ready. Five owner questions (Q1–Q5) are open with their defaults applied; none blocks Phase 1.
> Next handoff: @dba (Phase 1), run by the crew as `crew-builder-data`. Phase 1 item 4 (the version bump) is made by the lead: `crew-builder-data` cannot write `lib/core/**`.
> Binding conventions: `docs/global_conventions.md`, `docs/db_integration.md` ("Catalog version + seed-entry tombstones"), `docs/data_models.md` (MuscleGroup section)
> Track: phone only (`lib/`, `test/`, `docs/`). Never branch or commit.
> Precedent: plans 115a, 115b and 116 (`docs/plans/2026-11-04-115a-…`, `-115b-…`, `-116-catalog-delivery-plan/`). D-18905's "no new discipline" rule, D-18907 (text rules), D-18910 (user-owned rows never rewritten) and D-19009 (renamed touched rows) bind this PR as written there, except where D-19302 names the discipline.
> Parallel work in the tree: plan 117 (uncommitted: data version 17, template rows removed from `seed_data.dart`) and plan 118 (conditioning, catalog 16 → 17). Never edit plan 117's or 118's files beyond the order-tolerant edits named here. Anchors in `lib/mock/seed_data.dart` are grepped, never line numbers.

## Goal and acceptance

## Overview

Classification: **STANDARD**. Bundled reference data that existing installs receive through the catalog refresh.
No logic, screen, watch or contract change.

The Yoga discipline (`discipline-yoga`, category Isometric / Stretching) exists in the seed and on every install, but
no exercise uses it. Choosing **Yoga** in the Discipline filter of the library or the picker shows an empty list.

What a user sees after this PR:

1. 22 yoga poses in the library, the picker and the wrist's exercise list (after its next sync): Mountain Pose,
   Downward-Facing Dog, Upward-Facing Dog, Cobra Pose, Warrior I, Warrior II, Reverse Warrior, Triangle Pose, Half
   Moon Pose, Tree Pose, Chair Pose, Eagle Pose, Goddess Pose, Boat Pose, Bridge Pose, Low Lunge, Crescent Lunge,
   Locust Pose, Camel Pose, Happy Baby, Reclined Spinal Twist and Savasana. Each has a description, how-to steps and
   (except Savasana) main and assisting muscles on its detail screen, plus a **Yoga** discipline chip.
2. The Discipline filter **Yoga** lists exactly the 22 poses, Pigeon Pose and Child's Pose (24 bundled rows plus any
   exercise the user made under Yoga): **Pigeon Pose and Child's Pose move to Yoga on this bump** (Q1 option b by the
   owner, 2026-11-05). They leave the Stretching filter; existing installs follow on the next launch; searching their
   names still finds them. A user copy or edit keeps its own discipline.
3. A pose logs the way Pigeon Pose or Plank Hold does today. In an **Isometric / Stretching** workout it is a hold:
   a hold timer, with optional extra weight, repeatable as several holds. In a **Free** workout the user picks Hold.
   In the Isometric picker the poses rank level with the stretches and holds (same capabilities, same category),
   alphabetically among them; in a Strength workout they sit in the lower band, like the stretches.
4. Stats: logged poses count in the isometric section and the Hold Progress card, like any hold (keyed by the effort
   logged, not the discipline).
5. Health: a phone workout whose exercises are all under **Yoga** written on the phone records as **Yoga** on iOS and
   Android (owner, 2026-11-05 — the plan's "no change" default is superseded): the health writer reads the session's
   segments, resolves each exercised id's discipline, and when every present discipline is `discipline-yoga` writes
   the `yoga` kind; anything else keeps the modality mapping (Isometric → Flexibility on iOS, Other on Android). A
   wrist workout made of poses still records as **Flexibility** — the wrist selects by capabilities (a hold is
   flexibility) and the catalog sends it no `healthActivity` for holds; changing that is a watch PR (Notes).
6. Existing installs get the 22 poses on next launch. The user's own exercises (a custom "Downward-Facing Dog"
   included), copies, edited bundled rows, and a bundled row the user renamed to a pose name are not changed.
7. Updated phones store no equipment link for the poses; new installs link each to Body Weight. No screen shows
   equipment, so nothing is visible.

## Owner questions (one batch; the plan applies every default)

- **Q1. Pigeon Pose and Child's Pose.** Both exist under Stretching. **Owner decision (2026-11-05): option (b), move
  both to Yoga**, overriding the plan's default (a): they leave the Stretching filter and join Yoga (the Yoga filter
  lists 24 bundled rows); the refresh delivers the discipline change to existing installs next launch, and a user
  copy or edit keeps its own discipline (D-19312). (c) Duplicate them under Yoga: rejected by the brief.
- **Q2. Three near-twins.** Bridge Pose is close to Glute Bridge Hold, Low Lunge to Kneeling Hip Flexor Stretch, and
  Crescent Lunge to Split Squat Hold. Default **include all three** under Yoga, with texts that say how each differs
  (arms, back heel, chest lift). Alternative: drop any of them (the rest of the plan shrinks by one row each).
- **Q3. Savasana and Mountain Pose.** Default **include both**. Savasana (lying still, relaxing) carries no muscles, so
  it never appears under a Muscle filter. Mountain Pose (standing tall) is tagged Abs main, Quads and Glutes assisting.
  Alternatives: drop Savasana; or leave Mountain Pose untagged too.
- **Q4. Health type.** **Owner decision (2026-11-05): a phone workout of Yoga exercises records as Yoga**,
  superseding the plan's "no change" default (see Overview item 5 and D-19313). The wrist keeps its hold-tested
  Flexibility path unchanged (S-19306).
- **Q5. One-sided poses** (Warriors, Triangle, Half Moon, Tree, Eagle, the lunges, the twist). Default **like Pigeon
  Pose today**: no left/right marker; the last how-to step says to repeat on the other side, and the user logs each
  side as its own hold. Alternative: a left/right marker for holds is a logger change (separate @developer PR).

## Decision Ledger (Resolved Decisions)

| Id | Decision |
|---|---|
| D-19301 | The rows |
| D-19302 | Discipline and shape |
| D-19303 | Capabilities |
| D-19304 | Equipment |
| D-19305 | Muscles |
| D-19306 | Text |
| D-19307 | Catalog version (lead) |
| D-19308 | SQL contract |
| D-19309 | Order-tolerant guards |
| D-19310 | Out of this PR |
| D-19311 | Watch doc wording |
| D-19312 | The move (Q1b) |
| D-19313 | The Health kind (Q4) |

- **D-19301 The rows.** The 22 new exercises are exactly the rows of the **New-row table**: id, name, main (P) and
  assisting (S) muscles, all as written. Ids are `exercise-<slug>`. Rows are appended, in table order, at the end of
  `SeedData.sampleExercises` and at the end of each of the three maps (`exerciseMuscleLinks`,
  `exerciseEquipmentRelationships`, `exerciseCapabilityRelationships`): after whatever entry is last when the builder
  starts (115b's `exercise-sled-drag` today; plan 118's last row if it landed first). No id exists today:
  `grep -rn "'exercise-<slug>'" lib test watch scripts` → 0 hits for all 22 (run 2026-11-04). No bundled name equals a
  new name ignoring case and surrounding spaces (`grep -n "^      name: " lib/mock/seed_data.dart`, checked against
  all 22).
- **D-19302 Discipline and shape.** Every row: `disciplineId: 'discipline-yoga'`, no `ownerUserId`, no
  `movementPattern` (null, like every stretch and hold row), no `modality`. No discipline, category, muscle or
  equipment row is added. `discipline-yoga` (`category-isometric`) is in `SeedData.sampleDisciplines` and in
  `scripts/sqlite_seed.sql` (`key='yoga'`), and the refresh delivers disciplines since catalog version 16 (plan 116),
  so a device missing it gets it back in the same refresh, before the exercise leg runs.
- **D-19303 Capabilities.** Every row carries **H** = `['hold', 'time', 'sets']`, in that order: the exact set of
  every one of the 45 Isometric Holds and Stretching rows (`grep -c "\['hold', 'time', 'sets'\]" lib/mock/seed_data.dart`
  → 46, the 46th is Plate Pinch Hold; no other hold set exists). No `bilateral` (Q5), no `load` (extra weight is the
  modality's optional metric, not a capability).
- **D-19304 Equipment.** Every row maps to `['equipment-bodyweight']`, as every stretch and hold does. New installs
  only (D-18909 / D-19104): updated phones get no equipment link. Nothing reads equipment on screen.
- **D-19312 The move (Q1b).** `exercise-pigeon-pose` and `exercise-childs-pose` change `disciplineId` from
  `discipline-stretching` to `discipline-yoga` in `SeedData.sampleExercises` and in `scripts/sqlite_seed.sql`
  (the SQL moves both — no new exercise names, no database running them. The SQL has **no Yoga exercise block
  today**: the per-discipline exercise blocks run `WHERE d.key='running'` through `WHERE d.key='climbing'` and
  `grep -n "WHERE d.key" scripts/sqlite_seed.sql` shows no `'yoga'` one, so the move **creates** one new Yoga
  exercise INSERT block carrying the two unions verbatim and removes the two unions from the stretching block;
  D-19308's invariance for the SQL is amended to
  "the SQL fixture changes only by that new block and the two unions' removal — in effect the two rows'
  `discipline_id` values — and `test/db_seed_test.dart` still passes").
  The refresh delivers the change to existing installs through the normal changed-row upsert; a touched marker or a
  user copy keeps its discipline. No other field of either row changes; their muscles, equipment and capability
  entries stay in place. Sizes after this PR alone: exercises 300 → 322, capabilities 300 → 322, equipment map
  236 → 258, links 226 → 247 (21: Savasana has none) — the moves change no count.
- **D-19313 The Health kind (Q4, owner).** `HealthActivityKind` gains `yoga`. `pluginActivityTypeFor(yoga)` returns
  `HealthWorkoutActivityType.YOGA` for iOS AND Android: health 13.3.1's `_isOnIOS` and `_isOnAndroid` sets both
  carry `YOGA` (checked against `~/.pub-cache/hosted/pub.dev/health-13.3.1/lib/src/health_plugin.dart`). The phone
  writer (`HealthSyncService.onSessionCompleted`) resolves the kind as: if every `SegmentEffort` of the session's
  segments (via `getSegmentsBySession` + `getEffortsBySegment`, both already on the repository interface) names an
  exercised id whose discipline is `discipline-yoga` AND the list is non-empty, the kind is `yoga`; otherwise
  the existing `mapModalityToActivityKind(session.modality)` stands, including a Free session where some — but not
  all — exercised rows are Yoga. An exercise id with no row (a deleted custom) breaks the Yoga-only condition, so it
  never mislabels: absent→"not all yoga". A session with no efforts at all (empty session) keeps the modality
  mapping. The wrist's `forExercise` path (a hold is flexibility first) and `healthActivityOf` are untouched; the
  S-19306 assertion "no healthActivity key for the poses" stays.
- **D-19305 Muscles.** Existing ids only; never a region id, Calves as a main muscle, Abductors, Rotator cuff,
  Brachialis, Biceps, Tibialis or Neck, so every exact set guarded today stays exact except one: Downward-Facing Dog
  assists Calves, so the **assisting** Calves exact set gains `exercise-downward-facing-dog`. Savasana has **no entry**
  in `exerciseMuscleLinks` (the S-3 guard requires a primary in every entry; 74 bundled rows already have none).
- **D-19306 Text** (on top of D-18907, adapted to holds). `description`: one or two plain sentences that name the pose
  and what it stretches or strengthens, in English only (no Sanskrit; derived, vetoable). `howToSteps`: 3 or 4
  imperative sentences: getting into the pose, the shape held, one cue, coming out. One-sided poses end with a step
  that says to repeat on the other side (Q5). Near-twins (Q2) say how they differ: Bridge Pose lifts the chest toward
  the chin with the arms under the body; Low Lunge keeps the back knee down with the arms overhead; Crescent Lunge
  lifts the back heel and knee with the arms overhead. Savasana's steps cover lying still and coming out by rolling to
  one side. No brand names. The reviewer reads all 22.
- **D-19307 Catalog version (lead).** Let **P** be the value of `bundledCatalogVersion` when the builder starts
  (17 if plan 118 landed first, 16 if not). Set it to **P + 1** and append to the doc comment in
  `lib/core/constants/catalog_version.dart`: "When 22 yoga poses were added under the Yoga discipline (Mountain Pose
  through Savasana), we bumped to `P+1` so existing installs receive them on next launch; their equipment links reach
  new installs only." Record P in the evidence file. `currentDataVersion` is unchanged.
- **D-19308 SQL contract.** By the 115a/115b precedent (D-18912, D-19005) the SQL fixture carries none of the
  catalog-gap exercises, so `scripts/sqlite_seed.sql` changes **only** by a new Yoga exercise block
  (`WHERE d.key='yoga'`, created by this PR — none exists today) carrying Pigeon Pose's and Child's Pose's
  unions verbatim, and their removal from the stretching block (D-19312); `scripts/sqlite_schema.sql` does not change. `grep -n -i
  "count\|app_exercise\b" test/db_seed_test.dart` asserts no exercise count, so nothing there drifts; `flutter test
  test/db_seed_test.dart` keeps passing after the move.
- **D-19309 Order-tolerant guards.** Every size or version assertion this PR touches is written so it stays right
  whether plan 118 lands before or after it:
  - The table lives in one test helper, `test/helpers/yoga_catalog_rows.dart` (`yogaCatalogRows`), read by the yoga
    test and by the two global guards. `test/strength_catalog_gaps_test.dart` "catalog sizes": each of the four
    expectations gains `+ yogaCatalogRows.length` (links: `+ yogaCatalogRows.where((r) => r.main.isNotEmpty).length`),
    keeping any plan-118 term. `test/catalog_referential_integrity_test.dart`: both `hasLength(<n>)` sites gain the
    same links term.
  - `test/watch_reference_sync_test.dart` S-3858: `hasLength(3)` becomes `hasLength(4)` with reason "the seeded
    catalog is more than three batches" (300 + 22 = 322, 300 + 22 + plan 118's rows ≤ 400). If it already says 4,
    leave it.
  - `test/catalog_reference_refresh_test.dart`: each `equals(16)` on `getCatalogVersion()` becomes
    `equals(bundledCatalogVersion)`, and `expect(bundledCatalogVersion, equals(16))` becomes
    `greaterThanOrEqualTo(16)`. If plan 118 already did this, leave it.
  - The refresh tests stage `setCatalogVersion(P)` with P as a literal and assert `bundledCatalogVersion > P`.
- **D-19310 Out of this PR.** Moving any pose besides Pigeon Pose and Child's Pose, duplicating existing poses, a
  wrist Health change for holds (Q4-wrist), a left/right marker (Q5), Sanskrit names, aliases in search, equipment
  delivery, SQL backfill of catalog rows, any screen, logger, ranking, sync-contract, Stats, session or routine
  change, and plan 117's or 118's files beyond D-19309.
- **D-19311** `docs/state_management/watch_reference_data.md` "a phone with 300 seeded exercises would send tens of
  kilobytes" becomes "a phone with more than 300 seeded exercises would send tens of kilobytes" (true in either order).

### New-row table (D-19301; P = main, S = assists; "—" = none; caps H and equipment bodyweight on every row)

| # | id (`exercise-…`) | Name | P | S |
|---|---|---|---|---|
| 1 | mountain-pose | Mountain Pose | abs | quads, glutes |
| 2 | downward-facing-dog | Downward-Facing Dog | hamstrings | front-delts, lats, calves |
| 3 | upward-facing-dog | Upward-Facing Dog | lower-back | chest, triceps |
| 4 | cobra-pose | Cobra Pose | lower-back | chest |
| 5 | warrior-i | Warrior I | quads, glutes | front-delts |
| 6 | warrior-ii | Warrior II | quads | glutes, adductors, side-delts |
| 7 | reverse-warrior | Reverse Warrior | quads, obliques | lats |
| 8 | triangle-pose | Triangle Pose | hamstrings, obliques | adductors |
| 9 | half-moon-pose | Half Moon Pose | glutes | obliques, hamstrings |
| 10 | tree-pose | Tree Pose | glutes | quads, abs |
| 11 | chair-pose | Chair Pose | quads | glutes, front-delts |
| 12 | eagle-pose | Eagle Pose | quads, glutes | rear-delts |
| 13 | goddess-pose | Goddess Pose | quads, adductors | glutes |
| 14 | boat-pose | Boat Pose | abs | obliques |
| 15 | bridge-pose | Bridge Pose | glutes | hamstrings, lower-back |
| 16 | low-lunge | Low Lunge | quads | glutes |
| 17 | crescent-lunge | Crescent Lunge | quads, glutes | hamstrings |
| 18 | locust-pose | Locust Pose | lower-back, glutes | hamstrings, rear-delts |
| 19 | camel-pose | Camel Pose | lower-back | quads, chest |
| 20 | happy-baby | Happy Baby | adductors | hamstrings |
| 21 | reclined-spinal-twist | Reclined Spinal Twist | lower-back | glutes, obliques |
| 22 | savasana | Savasana | — (no link entry) | — |

Rows 1–11 are Phase 1; rows 12–22 are Phase 2. Siblings: the near-twins copy their twin's main muscle (Low Lunge =
Kneeling Hip Flexor Stretch `[quads P, glutes S]`; Bridge Pose = Glute Bridge Hold's main `glutes`). Sizes after this
PR alone: exercises 300 → 322, capabilities 300 → 322, equipment map 236 → 258, links 226 → 247 (21: Savasana has none).

## Feature Invariants

- The refresh never rewrites a touched, copied or custom exercise (D-18910, D-19009).
- Mock and Hive return the same rows, capabilities, links, filters and refresh outcomes in S-19303 to S-19305. The
  one documented divergence (115b precedent): Mock cannot delete an equipment link, so the "no equipment link after
  refresh" check is Hive-only.
- Diff boundary: no file under `lib/features/`, `lib/widgets/`, `lib/state/`, `lib/core/utils/`, `lib/data/`,
  `watch/` or `scripts/` changes, and neither does `lib/core/constants/data_version.dart`. Three boundaries change
  against the original: `lib/core/services/health_constants.dart`, `lib/core/services/health_platform_gateway_io.dart`,
  `lib/core/services/health_sync_service.dart` and possibly `health_modality_mapper.dart` (D-19313), and `scripts/
  sqlite_seed.sql` (two discipline values, D-19312). `lib/core/utils/watch_reference_sync.dart` stays untouched
  (S-19306 pins the poses' absence of a `healthActivity` key).

## Requirements and Acceptance Criteria

| Id | Acceptance (what a user sees) | Scenarios |
|---|---|---|
| A1 | 22 poses exist under Yoga with text, H capabilities, muscles and (new installs) Body Weight; names unique | S-19301, S-19307 |
| A2 | The Yoga filter lists exactly the 24 bundled rows (22 poses + Pigeon Pose + Child's Pose, plus user rows under Yoga); the Stretching filter no longer lists those two | S-19301, S-19303, S-19304, D-19312 |
| A3 | Muscle filters list poses by main muscle only; Savasana under none; guarded exact sets unchanged except assisting Calves | S-19302, S-19303 |
| A4 | Poses rank with the stretches in every modality's picker | S-19303 |
| A5 | A phone at version P gets the poses and the two discipline moves (and the Yoga discipline if missing); user-owned, copied, edited and renamed rows untouched | S-19304, S-19305, D-19312 |
| A6 | The wrist receives every pose once, as a hold, in one more batch; no Health kind of its own on the wrist | S-19306 |
| A7 | A phone session whose exercised rows are all Yoga records as **Yoga** on both platforms; a mixed session (any non-Yoga or unknown exercise) records as the modality mapping says; an empty session too | S-19311 |
| A8 | `HealthActivityKind.yoga` resolves to the plugin's `YOGA` type on iOS and Android | S-19311 |

## Existing-Functionality Impact (greps run 2026-11-04 on `claude_develop`, `d6052375` + plan 117 working tree)

| Touched surface | Readers (grep) | Effect | Guard |
|---|---|---|---|
| `discipline-yoga` | `grep -rn "discipline-yoga" lib test watch` outside `seed_data.dart` → 0; `grep -rni yoga lib` → comments only (`modality_config.dart:90`, `health_platform_gateway_io.dart:64`, `modality_picker_dialog.dart:144`) | No code reads it by id; the Discipline filter (`exercise_filter_row.dart`) and the `searchExercises(disciplineId:)` filter (Mock `:396`, Hive `:950`) start returning rows | S-19303 |
| Isometric discipline ids in code | `grep -rn "discipline-stretching\|discipline-isometric-holds" lib` outside the seed → 0 | Stats, Hold Progress and logging key on effort, not discipline | none needed |
| Isometric ranking | `mock_workout_repository.dart` `getExercisesRankedForModality` (score by caps + category, ties by name); `isometric_stretching` config (`modality_config.dart:92-105`) | Poses tie with stretches; "90/90 Hip Hold" stays first; "Boat Pose" lands before "Calf Raise Hold" | S-19303; full suite |
| Name-ordered lists | 115b list (`pr8_exercise_library_test`, `pr7_exercise_details_view_test`, `screen_widget_test`, `interaction_flow_test`, `widget_test`, `library_grouping_test`, `exercise_library_filters_test`, `muscle_filter_picker_test`); `grep -rn "find.text('<any new name>" test` → 0 | New names start B, C, D, E, G, H, L, M, R, S, T, U, W: none before "Barbell…" | full suite (Phase 2) |
| Name search | `grep -rn "searchText:" test`, `enterText` strings → none matches a pose name; search reads names only (`FuzzySearch.score(searchText, exercise.name)`) | "pose", "lunge", "bridge", "dog" return more rows | S-19303 |
| Catalog sizes | `strength_catalog_gaps_test.dart` "catalog sizes" (`252 + added` …); `catalog_referential_integrity_test.dart` two `hasLength(226)` | Red unless edited; D-19309 | S-19302 |
| Exact muscle sets | `catalog_referential_integrity_test.dart` (main/assisting Calves, Abductors, Rotator cuff, Brachialis, Biceps, Tibialis, 12 region-tagged); `muscle_filter_test.dart` S-18804, S-18905, S-19005 | Only assisting Calves changes (D-19305) | S-19302 |
| Catalog version literals | `grep -rn "equals(16)" test` → `catalog_reference_refresh_test.dart:500,501,970,979,1003,1124`; `greaterThanOrEqualTo(14/15)` in the v14/v15 tests stay true | Red on any bump unless edited (D-19309) | S-19302 |
| Delivery contract | `test/catalog_delivery_contract_test.dart` (modified by plan 117) checks COVERED ids as sets | New rows are in `sampleExercises`: auto-covered, no edit | Phase 1 suites |
| Watch list | `lib/core/utils/watch_reference_sync.dart` `buildExercisesDown` (batches ≤ 100); S-3858 `hasLength(3)`; S-3843 is synthetic (250 rows), unaffected; `exercises_down.schema.json` has no `batchCount` maximum; wrist merges any batch count (`WatchStartPaths.swift` `isComplete`) | 300 → 322 rows = 4 batches | S-19306, S-3858 |
| Health | `healthActivityOf` (`watch_reference_sync.dart:499-519`) returns null without `distance`; wrist `forExercise` hold → `flexibility` (`WatchPlatformWorkout.swift`); phone `mapModalityToActivityKind` isometric → flexibility; `test/health_platform_mapper_test.dart` pins the kind grid; `test/health_platform_test.dart` `_Rig` creates sessions through `WorkoutState` | The phone writer gains the Yoga-only branch (D-19313): new kind `yoga`, gateway → `YOGA` on both platforms, sessions of all-Yoga exercises write `yoga`, everything else unchanged; the wrist stays as it is | S-19311 |
| SQL contract | `grep -n "yoga" scripts/sqlite_seed.sql` → discipline at `:325`; no exercise block carries `WHERE d.key='yoga'` today (blocks `:421`–`:2504`); `db_seed_test.dart` has no exercise count | Pigeon Pose and Child's Pose move discipline in the SQL via a new Yoga block (D-19312); `db_seed_test.dart` stays green | `db_seed_test.dart` green |
| Docs counting exercises | `grep -rn "300 seeded" docs` → `state_management/watch_reference_data.md:22`; `modality_tracking.md` "40 exercises" is historical (seen, not fixed) | D-19311 | Phase 3B sweep |
| Docs listing catalog versions | `docs/db_integration.md` "Catalog version `15` adds …" paragraph; `docs/constants_reference.md` `bundledCatalogVersion` row (both carry plan 117 edits) | Add / bump | Phase 3B |
| Stats, sessions, routines, demos | `grep -rn "exercise-pigeon-pose\|exercise-childs-pose" lib/test outside seed+SQL → 0; demo bundles name no new id | The two moved rows keep their ids, muscles, equipment and capabilities, so nothing by id breaks; discipline-visible lists change (A2) | S-19303 |

## UI Standards Impact

None. No UI file changes.

## Scenarios

Index of the scenarios below; the row form is for the linter, the bodies carry the fixtures.

| S-n | Fixture | Expect | Fails without |
|---|---|---|---|
| S-19301 | seed vs `yogaCatalogRows` | rows conform | rows absent |

| S-n | Fixture | Expect | Fails without |
|---|---|---|---|
| S-19302 | shipped guards | exact sets re-baselined | guards red on old counts |
| S-19303 | fresh install filters | Yoga/Stretching/ muscle/rank | empty Yoga filter |
| S-19304 | v P refresh | 22 rows + 2 moves land | version gate skips |
| S-19305 | renamed + near-twins | user rows win | refresh rewrites them |
| S-19306 | batches to wrist | 4 batches, holds | ids absent |
| S-19307 | fresh equipment | Body Weight links | links absent |
| S-19311 | rig fixtures A–E | yoga kind only when all-yoga | kind doesn't exist |

Bodies follow; each body repeats its scenario's why (Why fails without, in each).

Shared fixture notes. "Custom" = `createExercise(Exercise(id, ownerUserId: 'user-1', name, disciplineId, createdAtMs: 1700000000000, updatedAtMs: same))`
then `setExerciseMuscleLinks`. Mock+Hive scenarios run over `harnessFactories` with plain `test()`. "Remove id" =
`deleteExercise(id)`, `setExerciseCapabilities(id, [])`, `setExerciseMuscleLinks(id, [])`, and on Hive delete `id`
from box `exercise_equipment`. "Stage missing" = the `_stageMissing` shape of `test/catalog_reference_refresh_test.dart`
(Mock `deleteReferenceRowForTest`, Hive `Hive.box<Map>(box).delete`). YOGA = the 22 table ids.

### S-19301: Row conformance and the Yoga set (new `test/yoga_catalog_test.dart`, pure)
- Fixture: `yogaCatalogRows` (Phase 1: rows 1–11; Phase 2: all 22) and `SeedData` as shipped.
- Expected, per row: name; `disciplineId == 'discipline-yoga'`; `movementPattern`, `ownerUserId`, `modality` null;
  description non-empty; 3–4 non-empty steps; capabilities `equals(['hold', 'time', 'sets'])` and equal to
  `exerciseCapabilityRelationships['exercise-pigeon-pose']`; equipment `['equipment-bodyweight']`; links equal
  `MuscleTaxonomy.normalize(...)` of the row, and for Savasana `exerciseMuscleLinks.containsKey` is false.
- Expected, whole seed: the ids of `sampleExercises` with `discipline-yoga` equal YOGA as a set (Phase 1: rows 1–11);
  `exercise-pigeon-pose` and `exercise-childs-pose` have `discipline-yoga` (D-19312) and stay members of the guard
  below; no new name equals any other bundled name ignoring case and surrounding spaces; every new id sorts after `exercise-2k-row-test`.- Red today: rows absent. Edge case of: none

### S-19302: Global guards stay exact (edits in existing files, pure)
- Fixture: as shipped. Expected: "catalog sizes" = previous totals + the D-19309 terms (alone: 322/322/258/247);
  both referential `hasLength` = previous + links term; assisting Calves = `{nordic-curl, wall-sit, sled-push,
  sled-drag, downward-facing-dog}` plus any plan-118 ids; every other exact set unchanged; S-3858 4 batches;
  catalog-version pins per D-19309. Red today: none (they are re-baselined, not new). Edge case of: S-19301

### S-19303: Filters, Yoga discipline and rank on a fresh install (`test/muscle_filter_test.dart`, new group, Mock + Hive)
- Fixture: bundled catalog plus customs U "Downward-Facing Dog" (no discipline) `[hamstrings P]` and E "Sun Salutation
  Flow" (no discipline) `[]`.
- Expected (`searchExercises(muscleGroupIds: …)` ids; "once" = exactly one occurrence):
  - Hamstrings contains `downward-facing-dog`, `triangle-pose`, U; excludes `bridge-pose`, `happy-baby`, `half-moon-pose`.
  - Calves excludes `downward-facing-dog`. Abductors equals the 4 bundled abductor ids.
  - Obliques contains `reverse-warrior`, `triangle-pose`; excludes `boat-pose`, `half-moon-pose`, `reclined-spinal-twist`.
  - Abs contains `mountain-pose`, `boat-pose`; excludes `tree-pose`. Core: `triangle-pose` once, `reverse-warrior` once.
  - Lower back contains `upward-facing-dog`, `cobra-pose`, `locust-pose`, `camel-pose`, `reclined-spinal-twist`;
    excludes `bridge-pose`. Back: `locust-pose` once.
  - Adductors contains `goddess-pose`, `happy-baby`; excludes `warrior-ii`, `triangle-pose`.
  - Glutes contains `warrior-i`, `half-moon-pose`, `tree-pose`, `eagle-pose`, `bridge-pose`, `crescent-lunge`,
    `locust-pose`; excludes `warrior-ii`, `chair-pose`. Quads contains `chair-pose`, `warrior-ii`, `low-lunge`,
    `goddess-pose`; excludes `mountain-pose`. `['muscle-legs', 'muscle-quads']`: `crescent-lunge` once.
  - For every `MuscleTaxonomy.entries` id: the result excludes `exercise-savasana` and E.
  - `searchExercises(disciplineId: 'discipline-yoga')` ids as a set == YOGA ∪ {pigeon-pose, childs-pose} (U excluded:
    no discipline); `searchExercises(disciplineId: 'discipline-stretching')` contains neither `pigeon-pose` nor
    `childs-pose` nor any of YOGA (D-19312).
  - `searchExercises(searchText: 'Downward-Facing Dog')` contains U and `exercise-downward-facing-dog`.
  - In `getExercisesRankedForModality('isometric_stretching')` and `('resistance_lifting')`, every YOGA row's
    `relevanceScore` equals `exercise-pigeon-pose`'s in the same list; in the isometric list, the non-YOGA ids keep
    the relative order they had with YOGA removed (compare against the same query after removing YOGA on a second
    fresh harness, or filter the list).
- Red today: rows absent. Edge case of: none

### S-19304: A version-P install refreshes (new `test/yoga_catalog_refresh_test.dart`, Mock + Hive, `const BundledCatalogSource()`)
- Fixture (after `harness.open()`):
  1. Remove each YOGA id.
  2. Stage missing `disciplines/discipline-yoga`; assert `getDisciplineById('discipline-yoga')` is null.
  3. Custom U "Downward-Facing Dog", `disciplineId: 'discipline-yoga'`, `[hamstrings P, calves S]`; record `toMap()`.
  4. K = `ExerciseLibraryService(repo).copyAsCustom(exercise-pigeon-pose)`; record its row and links.
  5. Child's Pose edited: `updateExercise` with description `'My own cue'`, then
     `markSeedEntryTouched(SeedEntryType.exercise, 'exercise-childs-pose')` — the tombstone keeps the user's edit,
     so the fixture updates the stored exercise to `discipline-stretching` as its baseline first (a user edit that
     predates the update; D-18910).
  6. `exercise-pigeon-pose` untouched (also without a marker): the refresh restores its row as bundled, so it comes
     back `discipline-yoga` (D-19312). 7. `setCatalogVersion(P)` (literal, D-19307).
- Trigger: `CatalogRefreshService(repo, const BundledCatalogSource()).refresh()`.
- Expected: returns true; `getCatalogVersion() == bundledCatalogVersion`; `bundledCatalogVersion > P`.
  `discipline-yoga` is back: name "Yoga", `categoryId` `category-isometric`. Each YOGA id exists with its table name
  and `discipline-yoga`; capabilities and links equal the bundled ones as sets (Savasana's links `[]`). Pigeon Pose
  and Child's Pose now carry `discipline-yoga` (D-19312) with every other field and their muscles, equipment and
  capabilities unchanged. U's `toMap()`
  and links unchanged; `searchExercises(searchText: 'Downward-Facing Dog')` contains U and the bundled id;
  `searchExercises(disciplineId: 'discipline-yoga')` == YOGA + U. K unchanged. Child's Pose keeps `'My own cue'`
  (a touched marker skips its rewrite; its stored discipline stays whatever the fixture left, the user's edit wins);
  Pigeon Pose (untouched, no marker) carries the bundled `discipline-yoga` (D-19312). Hive only: `getExerciseEquipment`
  of `exercise-tree-pose` and `exercise-savasana` is empty. A second `refresh()` returns false; U, K and YOGA links identical.
- Red today: with the rows reverted the 22 stay absent; with the version unbumped the refresh is skipped.
- Edge case of: none

### S-19305: A renamed touched row and near-twins keep their own (same file, Mock + Hive)
- Fixture: 1. Remove `exercise-low-lunge`. 2. `exercise-kneeling-hip-flexor-stretch` renamed "Low Lunge" via
  `updateExercise`, links `[quads P]`, then marked touched. 3. Customs N1 "Downward Dog" `[hamstrings P]` and N2
  "downward-facing dog " (lower case, trailing space) `[hamstrings P]`, no discipline. 4. `setCatalogVersion(P)`.
- Expected after `refresh()`: the hip-flexor row keeps "Low Lunge", `discipline-stretching` and `[quads P]`;
  `exercise-low-lunge` exists as "Low Lunge", `discipline-yoga`, `[quads P, glutes S]`; `searchText: 'Low Lunge'`
  contains both ids. N1 and N2 keep names and links; the Hamstrings filter contains `downward-facing-dog`, N1 and N2,
  each once.
- Red today: version gate skips the refresh, so `exercise-low-lunge` stays absent. Edge case of: S-19304

### S-19306: The wrist receives the poses (`test/watch_reference_sync_test.dart`, new test in the batches group, Mock)
- Fixture: the file's seeded `MockWorkoutRepository` (`setUp`, `:172`).
- Expected: `buildExercisesDown` returns 4 batches; across all batches each YOGA id appears exactly once, with
  `capabilities == ['hold', 'time', 'sets']` and no `healthActivity` key; every batch is under 16,000 bytes.
  `WatchReferenceSync.healthActivityOf(disciplineId: 'discipline-yoga', exerciseId: 'exercise-tree-pose',
  capabilities: ['hold', 'time', 'sets'])` is null.
- Red today: the ids are absent. Edge case of: none

### S-19307: Equipment on a new install (`test/yoga_catalog_refresh_test.dart`, Mock + Hive, fresh)
- Fixture: no staging. Expected: `getExerciseEquipment` names of `exercise-downward-facing-dog`, `exercise-savasana`
  and `exercise-bridge-pose` == `['Body Weight']`; `getEquipment()` still has 12 rows. Red today. Edge case of: S-19304

### S-19311: The phone Health kind (new `test/health_yoga_kind_test.dart`, Mock harness only — the `_Rig` of
`test/health_platform_test.dart` runs on the in-memory store and never opens Hive, so one implementation is enough;
D-19313)
- Fixture A (all-yoga): through `WorkoutState` (`_Rig` shape): `createNewSession(modality: isometricStretching)`,
  `addExerciseToSession` a bundled pose (e.g. Mountain Pose) twice; `endSession`; the written draft answers `yoga`.
- Fixture B (mixed): one pose + one Rowing exercise → `flexibility` (the modality mapping; a mixed session never
  half-labels).
- Fixture C (unknown row): one pose + an exercised id the store does not know → `flexibility` (absent discipline is
  not a Yoga discipline; absent resolves to 'not all yoga').
- Fixture D (empty): a completed session with no exercises → `flexibility`.
- Fixture E (free): a Free session (null modality) containing only a pose → `yoga`.
- Expected per fixture: the written draft's `activityKind` exactly as named; never a throw. Each case runs on a
  fresh `_Rig`; no widget is pumped, so plain `test()` over the Mock harness.
- Unit level, in `test/health_platform_mapper_test.dart` (S-19311): `HealthActivityKind.yoga` is a member;
  `pluginActivityTypeFor(yoga, isIOS: true).name == 'YOGA'` and the same for `isIOS: false` (health 13.3.1 carries
  `YOGA` in BOTH platform sets — checked); the existing "every activity kind resolves on both platforms" loop then
  covers the new value.
- Red today: no `yoga` kind exists — the rig fixtures answer `flexibility`, the mapper tests fail to compile/assert.
- Edge case of: none

## Phases (Iteration 1)

### Phase 1: Rows 1–11, the two moves, guards, version (@dba · `crew-builder-data`; item 4 by the lead)
`--scope`: `lib/mock/seed_data.dart lib/core/constants/catalog_version.dart test/helpers/yoga_catalog_rows.dart test/yoga_catalog_test.dart test/strength_catalog_gaps_test.dart test/catalog_referential_integrity_test.dart test/watch_reference_sync_test.dart test/catalog_reference_refresh_test.dart "docs/plans/2026-11-05-119-yoga-catalog-plan/*"`
1. [x] Record baselines in the evidence file: P (D-19307), the `flutter analyze` issue count, and pass/fail counts of the Done Criteria suites — `2026-11-05-119-yoga-catalog-plan.evidence.md`
2. [x] New `test/helpers/yoga_catalog_rows.dart` (`yogaCatalogRows`, rows 1–11, fields as `_Row` in `strength_catalog_gaps_test.dart`) and new `test/yoga_catalog_test.dart` with S-19301; run it and paste the red
3. [x] Append rows 1–11 (D-19301..D-19306) to `SeedData.sampleExercises` and the three maps; change `disciplineId` of `exercise-pigeon-pose` and `exercise-childs-pose` to `discipline-yoga` (D-19312) — `lib/mock/seed_data.dart` (grep anchors: `static final List<Exercise> sampleExercises`, `exerciseMuscleLinks = {`, `exerciseEquipmentRelationships = {`, `exerciseCapabilityRelationships = {`, the two pose rows' `disciplineId:` lines)
4. [ ] (lead) `bundledCatalogVersion = P + 1` and the D-19307 sentence — `lib/core/constants/catalog_version.dart`
5. [x] D-19309 guard edits: "catalog sizes" — `test/strength_catalog_gaps_test.dart`; both `hasLength` sites and assisting Calves + `exercise-downward-facing-dog` — `test/catalog_referential_integrity_test.dart`; S-3858 → 4 — `test/watch_reference_sync_test.dart`; version pins — `test/catalog_reference_refresh_test.dart`
6. [x] Show S-19301 red with item 3 reverted, then green; paste counts; update Progress and the Assumption Log — `lib/mock/seed_data.dart` + `test/yoga_catalog_test.dart` (revert, then green), evidence file

**Done Criteria** (Claude agents wrap in `bash .claude/scripts/macos/with-timeout.sh`; Copilot agents use the gateway):
- `flutter analyze`: issue count ≤ the item-1 baseline
- `flutter test test/yoga_catalog_test.dart test/strength_catalog_gaps_test.dart test/catalog_referential_integrity_test.dart test/catalog_reference_refresh_test.dart test/catalog_delivery_contract_test.dart test/catalog_refresh_test.dart test/strength_catalog_v15_refresh_test.dart test/muscle_filter_test.dart test/watch_reference_sync_test.dart test/db_seed_test.dart`
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -c "disciplineId: 'discipline-yoga'" lib/mock/seed_data.dart` → 13 (11 new + 2 moves); `grep -n "bundledCatalogVersion = " lib/core/constants/catalog_version.dart` shows P + 1

**Predicted Files**: `lib/mock/seed_data.dart`, `lib/core/constants/catalog_version.dart`, `test/helpers/yoga_catalog_rows.dart` (new), `test/yoga_catalog_test.dart` (new), `test/strength_catalog_gaps_test.dart`, `test/catalog_referential_integrity_test.dart`, `test/watch_reference_sync_test.dart`, `test/catalog_reference_refresh_test.dart`, evidence file. Production diff: about 220 lines.

### Phase 2: Rows 12–22, wrist scenario, full suite (@dba · `crew-builder-data`)
`--scope`: `lib/mock/seed_data.dart test/helpers/yoga_catalog_rows.dart test/watch_reference_sync_test.dart "docs/plans/2026-11-05-119-yoga-catalog-plan/*"` (an unpredicted name- or rank-ordered test fix widens the scope by that one file, recorded in the evidence file)
1. [x] Append rows 12–16 as in Phase 1 item 3 — `lib/mock/seed_data.dart`
2. [x] Append rows 17–22 (Savasana: no `exerciseMuscleLinks` entry) — `lib/mock/seed_data.dart`
3. [x] Extend `yogaCatalogRows` to 22 rows — `test/helpers/yoga_catalog_rows.dart`
4. [x] Write S-19306 in the `S-3840..` batches group — `test/watch_reference_sync_test.dart`
5. [x] Show S-19301 and S-19306 red with items 1–2 reverted, then green; run the full suite (`flutter test`, 900 s, output to a file). Fix any name- or rank-ordered test in place and list it as an unpredicted file in the evidence file — `lib/mock/seed_data.dart`, `test/helpers/yoga_catalog_rows.dart`, `test/watch_reference_sync_test.dart` (revert, then green), evidence file — red (`+42 -13`) and green (`+55`) done; the full suite's 11 stale three-batch pins (four files) were fixed by the lead after the run, then re-run green (`+139` four files, `+6588 ~2 -0` full suite) — see the evidence file's Phase 2 section

**Done Criteria**: Phase 1's suites; full `flutter test` with 0 failures; `grep -c "disciplineId: 'discipline-yoga'" lib/mock/seed_data.dart` → 24 (11 + 11 new rows + the 2 moves); `flutter analyze` ≤ baseline.
**Predicted Files**: `lib/mock/seed_data.dart`, `test/helpers/yoga_catalog_rows.dart`, `test/watch_reference_sync_test.dart`, evidence file. Production diff: about 220 lines.

### Phase 3A: Filter, refresh and Health scenarios, SQL move (@dba · `crew-builder-data`)
`--scope`: `test/muscle_filter_test.dart test/yoga_catalog_refresh_test.dart test/health_yoga_kind_test.dart test/health_platform_mapper_test.dart scripts/sqlite_seed.sql "docs/plans/2026-11-05-119-yoga-catalog-plan/*"`
1. [x] Write S-19303 as a new group — `test/muscle_filter_test.dart`
2. [x] Write S-19304, S-19305 and S-19307 in new `test/yoga_catalog_refresh_test.dart` (shape of `test/strength_catalog_v15_refresh_test.dart`; header naming this plan and the S-ids; `_stageMissing` copied from `test/catalog_reference_refresh_test.dart`); D-19312 asserts piggyback on S-19304 (the Yoga-filter set of 24, the Stretching-filter absence, Pigeon's bundled row restored, Child's Pose's tombstone) — `test/yoga_catalog_refresh_test.dart`
3. [x] Write S-19311: the five rig fixtures + the two mapper pins — `test/health_yoga_kind_test.dart` (new) + `test/health_platform_mapper_test.dart`. To make the rig fixtures able to pass before the fix the brief carries the D-19313 rule itself
4. [ ] Red→green: version set back to P by hand (the lead, `lib/core/constants/catalog_version.dart`) for S-19304/S-19305; rows reverted (and the two discipline moves reverted) in `lib/mock/seed_data.dart` for S-19303/S-19307; S-19311 red on the pre-change tree by definition. Then green. Table in the evidence file, with the Mock-only exceptions (equipment-link staging is Hive-only; S-19311 is Mock-only by rig) — the four test files of items 1–3, evidence file
   — *open: the version/seed revert and the D-19313 implementation are the governor's*
5. [x] In `scripts/sqlite_seed.sql` (D-19312): create the Yoga exercise block — a new `INSERT INTO app_exercise … FROM (…unions…) e WHERE d.key='yoga' AND NOT EXISTS (…)` statement carrying the Pigeon Pose and Child's Pose unions verbatim (no Yoga exercise block exists today: the per-discipline blocks run `WHERE d.key='running'` through `WHERE d.key='climbing'`) — and remove the two unions from the stretching block (`WHERE d.key='stretching'`); run `flutter test test/db_seed_test.dart` and paste — this is the plan rewriting an artifact statement D-19308 used to forbid: the written SQL is contract, the git-diff reads as schema work, so the review re-checks it against `db_seed_test`

**Done Criteria**: `flutter test test/muscle_filter_test.dart test/yoga_catalog_refresh_test.dart test/health_yoga_kind_test.dart test/health_platform_mapper_test.dart test/yoga_catalog_test.dart test/ui_standards_contract_test.dart test/db_seed_test.dart`; `flutter analyze` ≤ baseline.
**Predicted Files**: `test/muscle_filter_test.dart`, `test/yoga_catalog_refresh_test.dart` (new), `test/health_yoga_kind_test.dart` (new), `test/health_platform_mapper_test.dart`, `scripts/sqlite_seed.sql`, evidence file.

### Phase 3B: Docs delta, residue sweep, full suite (@dba · `crew-builder-data`)
`--scope`: `docs/db_integration.md docs/constants_reference.md docs/state_management/watch_reference_data.md "docs/plans/2026-11-05-119-yoga-catalog-plan/*"`
The items are the rows of the Docs delta table.
1. [x] After the last "Catalog version `N` adds …" sentence, add: version `P+1` adds 22 yoga poses under the Yoga discipline and moves Pigeon Pose and Child's Pose into it; the user's own, copied, edited and renamed rows are never rewritten (cite `S-19304 a version-P install refreshes`, `S-19305 a renamed touched row and near-twins keep their own`); their equipment links reach new installs only (`S-19307`); a phone workout of Yoga exercises records as Yoga (`S-19311`) — `docs/db_integration.md` (44,887 B; stay under 53,248)
2. [x] `bundledCatalogVersion` table value → P + 1 — `docs/constants_reference.md` (row `| \`bundledCatalogVersion\` |`)
3. [x] `HealthActivityKind` vocabulary row gains `yoga` in the kind list — `docs/constants_reference.md` (row `| \`HealthActivityKind\` |`, D-19313)
4. [x] D-19311 wording — `docs/state_management/watch_reference_data.md` (line with "300 seeded exercises")
5. [x] Residue sweep pasted into the evidence file: `grep -rn "hasLength(226)\|hasLength(3),\|equals(16)" test` prints only lines proven unrelated; `grep -rn --exclude-dir=plans --exclude-dir=history --exclude-dir=releases "300 seeded" docs` → 0; `grep -n "bundledCatalogVersion" docs/constants_reference.md` shows P + 1; `git diff --stat -- scripts` prints exactly the `sqlite_seed.sql` hunks of Phase 3A item 5
6. [x] Full `flutter test` (900 s); paste totals; update Progress — evidence file — `+6607 ~2 -0: All tests passed!` (04:49 wall; log `.work/2026-11-05-119-yoga-catalog/full-suite-p3b.log`), run by the lead

**Done Criteria**: `flutter test test/docs_indexing_contract_test.dart`; full `flutter test` with 0 failures; `flutter analyze` ≤ baseline; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` prints nothing; `wc -c docs/db_integration.md docs/constants_reference.md docs/state_management/watch_reference_data.md` each < 53,248.
**Predicted Files**: `docs/db_integration.md`, `docs/constants_reference.md`, `docs/state_management/watch_reference_data.md`, evidence file.

### Phase 4: Review (@code-reviewer)
`--scope`: `"docs/plans/2026-11-05-119-yoga-catalog-plan/*"` (the review file; everything else read-only)
Diff versus every phase's Predicted Files; Diff-boundary check:
`git diff --stat -- lib/features lib/widgets lib/state lib/core/services lib/core/utils lib/data lib/watch watch scripts lib/core/constants/data_version.dart`
prints nothing attributable to this plan (plan 117's files are another unit: exclude them by name). Re-run every Impact
grep. Read all 22 texts against D-19306 and the tagging against the table. Mutations, each must turn the named tests red:
- M1: version left at P → S-19304, S-19305
- M2: Downward-Facing Dog's discipline set to `discipline-stretching` → S-19301, S-19303
- M3: `sets` dropped from Boat Pose → S-19301
- M4: Savasana given `[abs P]` → S-19301, S-19302 (sizes), S-19303
- M5: Bridge Pose renamed "Glute Bridge Hold" → S-19301 (name uniqueness)
- M6: the `_refreshDisciplines` call removed from `refresh()` → S-19304 (`discipline-yoga` still null)
- M7: the touched-skip in `_refreshExercises` removed → S-19304 (Child's Pose), S-19305
- M8: Pigeon Pose's seed discipline set back to `discipline-stretching` → S-19301, S-19303 (the inverse mutation: the
  play now asserts the move)
- M9: the link row of `exercise-cobra-pose` removed → S-19301, S-19302, S-19304
- M10: the health writer's all-yoga branch answered without querying segments (always `yoga` when a session exists)
  → S-19311 fixture B or C answers `yoga` wrongly
- M11: `pluginActivityTypeFor(yoga, isIOS: false)` returning `OTHER` → S-19311 (the Android pin)

Findings go in `2026-11-05-119-yoga-catalog-plan.review.md`.

## Files Affected

Production: `lib/mock/seed_data.dart`, `lib/core/constants/catalog_version.dart` (lead), `lib/core/constants/health_constants.dart`,
`lib/core/services/health_platform_gateway_io.dart`, `lib/core/services/health_sync_service.dart` (D-19313; the lead
briefs the exact shapes because these are shared files), `scripts/sqlite_seed.sql` (two rows' discipline). About 440 + ~60 lines.
Tests: `test/helpers/yoga_catalog_rows.dart`, `test/yoga_catalog_test.dart`, `test/yoga_catalog_refresh_test.dart` (new),
`test/health_yoga_kind_test.dart` (new); `strength_catalog_gaps_test.dart`, `catalog_referential_integrity_test.dart`,
`watch_reference_sync_test.dart`, `catalog_reference_refresh_test.dart`, `muscle_filter_test.dart`,
`health_platform_mapper_test.dart`. Docs: three files above.
Read-only dependents, guarded by tests: both repositories, `catalog_refresh_service.dart`, `bundled_catalog_source.dart`,
`watch_reference_sync.dart`, `modality_config.dart`, the exercise library, picker, editor and detail screens, the wrist,
`health_platform.dart`, `health_sync_service.dart`'s callers, `data_migration_test.dart`'s version-16 pins (its steps
pin migrations, not the catalog: they stay true).

## Notes

- **Scope budget (measured at planning):** 3 implementation phases + review (Phase 3 split into 3A/3B at
  validation for the ≤ 8-items rule; same scope, same owner, serial), one track, 13 decisions, 8 scenarios,
  about 500 predicted production lines, no missing prerequisite (discipline delivery shipped in 116). No soft signal
  fires: **no split**.
- **Dependency graph:** 1 → 2 → 3A → 3B → 4. Phase 3A item 1 only needs Phase 2; nothing gains from reordering.
- **Order with plan 118:** either order works. The second PR to land reads P from `catalog_version.dart`, appends after
  the other's last rows, and adds its own term to each D-19309 guard. If both are built in the same tree at once, the
  lead serializes the version bump and the guard edits.
- **Intermediate states:** after Phase 1, version P+1 ships 11 poses; do not ship it. After Phase 2, docs are stale
  until Phase 3B.
- **No migration:** the refresh delivers rows, capabilities and links (`catalog_refresh_service.dart` `refresh()`).
- **Optional extras (priced, NOT in this PR):**
  - *Wrist yoga type for holds* (Q4-wrist): `forExercise` health-activity refinement + native `activityType(for:)`
    row + contract + `watch_sensor_contract.json`; two tracks, about 2 phases — the phone kind landed here does not
    reach the wrist.
  - *Left/right marker for one-sided holds* (Q5): @developer logger PR, about 2 phases; changes Pigeon Pose too.
  - *Search by alias or Sanskrit name* ("down dog", "Adho Mukha Svanasana"): a search change, about 1 phase.
  - *More poses* (Pyramid, Wide-Legged Forward Fold, Plank-to-Side variants, Garland, Fish, Puppy): seed only,
    about 20 lines each.
  - *SQL backfill* of the 115a/115b/118/119 rows into `scripts/sqlite_seed.sql`: contract hygiene, about 600 SQL lines.
- **Seen, not fixed:** `docs/modality_tracking.md` "40 exercises with hand-curated capabilities" is historical.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/db_integration.md` | ADDED | - | Catalog version | S-19304 |
| `docs/constants_reference.md` | MODIFIED | the value cell held `16` | Content version of the bundled catalog | D-19307 |
| `docs/state_management/watch_reference_data.md` | MODIFIED | a phone with 300 seeded exercises | a phone with more than 300 seeded exercises | D-19311 |
| `docs/constants_reference.md` | MODIFIED | `sport`, `conditioning`, `other`) | `sport`, `yoga`, `conditioning`, `other`) | D-19313 |

## Progress
- [x] Owner answered Q1 (move both poses to Yoga, 2026-11-05) and Q4 (phone Yoga Health kind) outside the defaults;
  D-19312 / D-19313 record both; the plan was amended in place before the first run
- [x] Phase 1 · [x] Phase 2 · [x] Phase 3A · [x] Phase 3B · [ ] Phase 4 review
- Phase 1: items 1–3, 5 and 6 are done by `crew-builder-data` (counts in `2026-11-05-119-yoga-catalog-plan.evidence.md`);
  item 4, the version bump to 17, done by the lead; Done Criteria re-run green (272 tests).
- Phase 2: items 1–5 done by `crew-builder-data` (red `+42 -13` → green `+55` in the evidence file); the full
  suite's eleven three-batch pins in four files went stale from the whole catalog growth and were fixed by the
  lead as closed one-line edits (list + post-fix runs in the evidence file: the four files `+139`, the full
  suite `+6588 ~2 -0`, analyze still 181).

## Assumption Log

- A-119-1: the two moved rows keep their ids, names, texts, muscles, equipment and capabilities — only `disciplineId`
  changes (D-19312). Verified by grep 2026-11-05: no test, screen or state class outside the seed reads either id.
- A-119-2: `HealthWorkoutActivityType.YOGA` exists in health 13.3.1's iOS AND Android supported sets (checked in
  `~/.pub-cache/hosted/pub.dev/health-13.3.1/lib/src/health_plugin.dart`). If a pub upgrade dropped it from a set,
  `pluginActivityTypeFor` would throw on a write — pinned by S-19311's both-platform assertion.
- A-119-3: the shared table's row type is the public `YogaCatalogRow`, not a private `_Row` — a public
  `const List` cannot be typed with a private class without tripping
  `library_private_types_in_public_api`, which the Phase 1 Done Criteria (`flutter analyze` ≤ baseline)
  forbid. The pinned name `yogaCatalogRows` and the `_Row` field shape are unchanged.
- A-119-4: `test/helpers/yoga_catalog_rows.dart` imports `package:omnitrain/data/models/muscle_taxonomy.dart`
  in addition to the three the brief names: `models.dart` declares no `export`, so `MuscleTaxonomy.normalize`
  (and the links assertion S-19301 requires) is only reachable through its own library.

## Feedback
