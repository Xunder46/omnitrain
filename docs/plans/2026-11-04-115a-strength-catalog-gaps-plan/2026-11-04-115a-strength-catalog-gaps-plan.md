# 115a — Three new muscles, three re-tags, 28 strength exercises

> Status: APPROVED to build. Q1–Q4 answered "all defaults" by the owner on 2026-11-04. Phase 1 started.
> Next handoff: @dba (Phase 1), run by the crew (`crew-builder-data`). The version bump in Phase 1 item 4 is made by the lead (`crew-builder-data` cannot write `lib/core/**`).
> Precondition met: plan 114 is committed (`50a95486`).
> Binding conventions: `docs/global_conventions.md`, `docs/data_models.md` (MuscleGroup section), `docs/db_integration.md` (catalog refresh, SQL contract)
> Series index: `docs/plans/2026-11-04-115-strength-catalog-gaps-series.md`. Track: phone only (`lib/`, `scripts/`, `test/`, `docs/`). Never branch or commit.
> Precedent: plan 114 (Shins). Reuse its touch points and test shapes.

## Overview

Classification: **STANDARD**. The PR changes bundled reference data that existing installs receive through the
catalog refresh, and it changes what three muscle filters return.

What a user sees after this PR:

1. The **Muscle** filter in the exercise library and the exercise picker gains three indented rows:
   **Brachialis** under Arms (after Forearms), **Rotator cuff** under Shoulders (after Rear delts), and
   **Abductors** under Legs (after Adductors).
2. Picking **Abductors** lists Cable Hip Abduction, Machine Hip Abduction, Banded Clamshell and Banded
   Lateral Walk. Picking **Glutes** no longer lists Cable Hip Abduction.
3. Picking **Rotator cuff** lists Cable External Rotation, Side-Lying Dumbbell External Rotation and Cable
   Internal Rotation. Picking **Rear delts** no longer lists Cable External Rotation.
4. Picking **Brachialis** lists Hammer Curl, Cross-Body Hammer Curl, Zottman Curl and Reverse Curl.
   **Biceps** still lists Hammer Curl (Q2 default).
5. 28 new exercises appear in the library, the picker and the watch's exercise list (after its next sync),
   each with a description, how-to steps, and main and assisting muscles on its detail screen.
6. The exercise editor offers a Brachialis chip on the Arms row, Rotator cuff on the Shoulders row and
   Abductors on the Legs row.
7. Existing installs get all of this on the next launch. Exercises the user edited or copied, and the user's
   own exercises, keep their muscles. A user's own "Leg Extension" stays, next to the new bundled one.
8. Nothing else changes: Stats, sessions, routines (HIT Full Body still uses the three re-tagged exercises),
   and the other muscles' exercises.

## Owner questions (one batch; the plan applies every default)

- **Q1. New exercises on phones that already have the app: what about equipment?** Default: **tag the new
  exercises with equipment in the bundled catalog only, and do not build equipment delivery now.** Correction
  to the request's premise: **no screen shows equipment today.** `getExerciseEquipment` has no caller outside
  the two repositories (`grep -rn -i equipment lib/features lib/widgets lib/state` → 0 hits). So the gap
  cannot be seen: new installs carry the tags, and updated installs do not. Alternatives: (b) first build
  equipment delivery in the update, as a separate @dba PR of about 4 items and 100–150 production lines,
  which still shows nothing until a screen reads equipment; (c) do not tag new exercises at all. Choose (b)
  when you want an equipment filter or an equipment line on the detail screen. That PR fills the tags in on
  updated phones.
- **Q2. When an existing exercise moves to a new muscle, what happens to its old muscle?** Default, per exercise:
  - Cable Hip Abduction: main **Abductors**, assists **Glutes** (the Glutes filter stops listing it).
  - Cable External Rotation: main **Rotator cuff**, assists **Rear delts** (the Rear delts filter stops listing it).
  - Hammer Curl: main **Biceps and Brachialis**, assists Forearms. Both filters list it. This departs from
    the governor's suggested "new muscle only" rule on purpose: people program hammer curls as a biceps
    exercise, and dropping it from Biceps would surprise them. The alternative is main Brachialis only, with
    Biceps and Forearms assisting. Cross-Body Hammer Curl follows whichever you pick.
  - Barbell, Dumbbell and Preacher Curl are unchanged (no Brachialis link).
- **Q3. Names on screen?** Default: **"Abductors"** (pairs with "Adductors"), **"Rotator cuff"**,
  **"Brachialis"**. All three are short enough for the half-width Muscle field, which cuts long names off
  with "…".
- **Q4. A user already made their own exercise with the same name as a new one (say, "Leg Extension").**
  Default: **both stay.** The library shows two "Leg Extension" rows. The user's own row keeps its muscles
  and history, and nothing is merged or hidden. The user can delete either one. Alternative: skip delivering
  a bundled exercise whose name matches a custom one on that phone. That adds a name-matching rule to the
  update and its own tests (about 1 phase), and those users would never get the bundled description.

## Resolved Decisions (Ledger)

- **D-18901** Three taxonomy entries (Q3), placed in `MuscleTaxonomy.entries` (`lib/data/models/muscle_taxonomy.dart`). These positions are derived; they can be vetoed with Q3:
  `MuscleTaxonomyEntry('muscle-brachialis', 'Brachialis', 'muscle-arms')` directly after `muscle-forearms`;
  `MuscleTaxonomyEntry('muscle-abductors', 'Abductors', 'muscle-legs')` directly after `muscle-adductors`;
  `MuscleTaxonomyEntry('muscle-rotator-cuff', 'Rotator cuff', 'muscle-shoulders')` directly after `muscle-rear-delts`.
  Totals become 27 entries: 5 regions, 20 muscles, 2 standalone. Each name literal lives in the taxonomy,
  `scripts/sqlite_seed.sql`, `test/muscle_taxonomy_test.dart`, `test/muscle_filter_picker_test.dart` and `docs/data_models.md`.
- **D-18902** Re-tags (Q2), in `SeedData.exerciseMuscleLinks`, are the only existing rows whose links change:
  `exercise-cable-hip-abduction` → `_muscles(primary: ['muscle-abductors'], secondary: ['muscle-glutes'])`;
  `exercise-cable-external-rotation` → `_muscles(primary: ['muscle-rotator-cuff'], secondary: ['muscle-rear-delts'])`;
  `exercise-hammer-curl` → `_muscles(primary: ['muscle-biceps', 'muscle-brachialis'], secondary: ['muscle-forearms'])`.
- **D-18903** The filter rules are unchanged (plan 33 D-3). Only main links count. A region matches a main
  link to the region or to any of its muscles. A muscle matches only itself. A link that is only assisting
  never matches.
- **D-18904** The 28 new exercises are exactly the rows of the **New-row table** below: id, name, movement
  pattern, capabilities, main and assisting muscles, and equipment, all as written. Ids are
  `exercise-<slug>`, muscle ids `muscle-<x>`, and equipment ids `equipment-<x>`. Rows are appended, in table
  order, at the end of `SeedData.sampleExercises` (after `exercise-lateral-neck-flexion`) and at the end of
  each of the three maps. Appending keeps Mock's `getExercises()` order for every existing row. Hive returns
  key order, and no new id sorts before `exercise-2k-row-test`.
- **D-18905** Every new row has `disciplineId: 'discipline-bodybuilding'`, which every existing strength row
  uses, and no `ownerUserId`. It ranks in the picker the way its siblings do. No discipline is added.
- **D-18906** `bundledCatalogVersion` 13 → 14. Append one history sentence to the doc comment in
  `lib/core/constants/catalog_version.dart`: "When Brachialis, Rotator cuff and Abductors were added,
  Cable Hip Abduction, Cable External Rotation and Hammer Curl were re-tagged and 28 strength exercises were
  added, we bumped to `14` so existing installs receive them on next launch." In the same comment, change
  the opening list from "exercises, capability / muscle-group / equipment relationships" to "exercises,
  capability and muscle-group relationships", because equipment is not refreshed (D-18909). Refresh code is
  unchanged, and `currentDataVersion` is unchanged.
- **D-18907** Text rules for each new row. `description`: one or two plain sentences that name what the
  movement is and the main muscle in plain words, with no brand names. `howToSteps`: 3 or 4 imperative
  sentences covering setup, the movement, and the controlled return. The style is that of
  `exercise-barbell-curl` (`seed_data.dart:1350-1364`). Cable Crossover's description says the handles
  move from high to low. Low-to-High Cable Fly's says low to high. The reviewer reads every text.
- **D-18908** Capability sets, by the precedent of each row's sibling. **L** = `['reps', 'sets', 'load', 'time']`
  for barbell, machine and two-handed cable lifts, and for Bench Dip (Dip carries load). **LB** =
  `['reps', 'sets', 'load', 'bilateral', 'time']` for dumbbell isolation and single-arm work (Dumbbell Curl,
  Cable External Rotation). **BW** = `['reps', 'sets', 'time']` for unloaded bodyweight or band work
  (Push-Up). **BWB** = `['reps', 'sets', 'bilateral', 'time']` for one-side-at-a-time band work.
- **D-18909** (Q1) Each new row gets one entry in `exerciseEquipmentRelationships`, using existing ids only.
  The refresh does not deliver equipment (`CatalogSource` has no equipment field), so updated installs carry
  no equipment for the new rows. That is invisible, because no screen reads equipment. No equipment id is
  added in 115a.
- **D-18910** (derived from plan 33 D-8 and plan 114 D-18805; can be vetoed with Q4) Rows the user owns are
  never rewritten. That covers a bundled row marked touched, a copy (`copyAsCustom`), and any custom
  exercise, including one whose name equals a new bundled name. The refresh adds the bundled row next to it.
- **D-18911** (derived) `exercise-rear-delt-fly`'s description drops "or a reverse pec-deck", because
  Reverse Pec Deck is now its own exercise. The new text is "A reverse fly performed with dumbbells,
  isolating the rear delts and upper back." Untouched installs receive it through the refresh
  (`_exerciseDiffers`).
- **D-18912** SQL contract: `scripts/sqlite_schema.sql` is unchanged. `scripts/sqlite_seed.sql` gains three
  muscle inserts in the existing form, each after its sibling: `'Brachialis'` with parent `Arms` after the
  `Forearms` line, `'Abductors'` with parent `Legs` after `Adductors`, and `'Rotator cuff'` with parent
  `Shoulders` after `Rear delts`. No exercise or link rows are added: the SQL fixture carries none of the
  re-tagged or new exercises (`grep -c "Cable Hip Abduction" scripts/sqlite_seed.sql` → 0).
- **D-18913** Out of this PR: equipment delivery, discipline delivery, search by muscle name, and the 115b
  rows. No change to the watch, the sync contract, Stats, sessions or routines.

### New-row table (D-18904; P = main, S = assists; "—" = none / no `movementPattern`)

| # | id (`exercise-…`) | Name | Pattern | Caps | P | S | Equipment |
|---|---|---|---|---|---|---|---|
| 1 | side-lying-external-rotation | Side-Lying Dumbbell External Rotation | — | LB | rotator-cuff | rear-delts | dumbbell |
| 2 | cable-internal-rotation | Cable Internal Rotation | — | LB | rotator-cuff | — | cable |
| 3 | band-pull-apart | Band Pull-Apart | shoulder_isolation | BW | rear-delts | traps, rotator-cuff | resistance-band |
| 4 | machine-hip-abduction | Machine Hip Abduction | — | L | abductors | glutes | machine |
| 5 | banded-clamshell | Banded Clamshell | — | BWB | abductors | glutes | resistance-band |
| 6 | banded-lateral-walk | Banded Lateral Walk | — | BW | abductors | glutes | resistance-band |
| 7 | incline-dumbbell-curl | Incline Dumbbell Curl | arm_isolation | LB | biceps | forearms | dumbbell |
| 8 | cable-curl | Cable Curl | arm_isolation | L | biceps | forearms | cable |
| 9 | concentration-curl | Concentration Curl | arm_isolation | LB | biceps | — | dumbbell |
| 10 | reverse-curl | Reverse Curl | arm_isolation | L | brachialis, forearms | biceps | barbell |
| 11 | zottman-curl | Zottman Curl | arm_isolation | LB | biceps, brachialis | forearms | dumbbell |
| 12 | cross-body-hammer-curl | Cross-Body Hammer Curl | arm_isolation | LB | biceps, brachialis | forearms | dumbbell |
| 13 | close-grip-bench-press | Close-Grip Bench Press | horizontal_push | L | triceps | chest, front-delts | barbell |
| 14 | triceps-kickback | Triceps Kickback | arm_isolation | LB | triceps | — | dumbbell |
| 15 | diamond-push-up | Diamond Push-Up | horizontal_push | BW | triceps, chest | front-delts, abs | bodyweight |
| 16 | bench-dip | Bench Dip | horizontal_push | L | triceps | chest, front-delts | bodyweight |
| 17 | leg-extension | Leg Extension | squat | L | quads | — | machine |
| 18 | lying-leg-curl | Lying Leg Curl | posterior_chain | L | hamstrings | — | machine |
| 19 | seated-leg-curl | Seated Leg Curl | posterior_chain | L | hamstrings | — | machine |
| 20 | dumbbell-fly | Dumbbell Fly | horizontal_push | L | chest | front-delts | dumbbell |
| 21 | incline-dumbbell-fly | Incline Dumbbell Fly | horizontal_push | L | chest | front-delts | dumbbell |
| 22 | cable-crossover | Cable Crossover | horizontal_push | L | chest | front-delts | cable |
| 23 | low-to-high-cable-fly | Low-to-High Cable Fly | horizontal_push | L | chest | front-delts | cable |
| 24 | pec-deck-fly | Pec Deck Fly | horizontal_push | L | chest | — | machine |
| 25 | machine-shoulder-press | Machine Shoulder Press | vertical_push | L | front-delts | triceps, side-delts | machine |
| 26 | cable-rear-delt-fly | Cable Rear Delt Fly | shoulder_isolation | L | rear-delts | traps | cable |
| 27 | reverse-pec-deck | Reverse Pec Deck | shoulder_isolation | L | rear-delts | traps | machine |
| 28 | dumbbell-shrug | Dumbbell Shrug | — | L | traps | forearms | dumbbell |

Rows 1–16 are Phase 2A and rows 17–28 are Phase 2B. "—" in Pattern means the sibling has none
(Machine Hip Adduction, Cable External Rotation and Barbell Shrug carry no `movementPattern`). Under the Q2
alternative, rows 12 and the Hammer Curl re-tag become P `brachialis`, S `biceps, forearms`.

## Feature Invariants

- `MuscleTaxonomy.entries` is the single code source of muscles. `SeedData.sampleMuscleGroups` is derived from it.
- The refresh never rewrites a touched, copied or custom exercise (D-18910).
- `MockWorkoutRepository` and `HiveWorkoutRepository` return the same filter results and the same
  post-refresh links in S-18905 to S-18907. There are two documented exceptions, both on Mock: it cannot
  remove a muscle group, and it cannot remove an equipment link. Those staging steps run on Hive only
  (plan 114 precedent).
- Diff boundary: no file under `lib/features/`, `lib/widgets/`, `lib/state/`, `lib/core/services/`,
  `lib/data/repositories/`, `lib/watch/` or `watch/` changes, and neither do
  `lib/core/constants/data_version.dart` or `scripts/sqlite_schema.sql`.

## Requirements and Acceptance Criteria

| Id | Acceptance (what a user sees) | Scenarios |
|---|---|---|
| A1 | The three muscles appear indented under their regions, in D-18901 order, on fresh and updated phones | S-18901, S-18903, S-18906, S-18911 |
| A2 | Abductors, Rotator cuff and Brachialis list exactly their exercises; Glutes and Rear delts drop the re-tagged rows; Biceps keeps Hammer Curl | S-18904, S-18905 |
| A3 | 28 new exercises exist with text, capabilities, muscles and (on fresh installs) equipment as tabled | S-18909, S-18905 |
| A4 | The editor offers the three chips in their rows; a region chip next to one of its muscles keeps just the muscle | S-18902, S-18912 |
| A5 | Phones at version 13 receive everything on next launch; user-owned rows and same-name customs are untouched | S-18906, S-18907 |
| A6 | The SQL contract carries the three muscles | S-18910 |

## Existing-Functionality Impact (greps run 2026-11-04 on `claude_develop` with plan 114 in the tree)

| Touched surface | Readers (grep) | Effect | Guard |
|---|---|---|---|
| `MuscleTaxonomy.entries` | `grep -rli muscle lib/features lib/core/services lib/state lib/watch lib/core/utils` → exercise library, picker, editor, detail screens; `muscle_display.dart`, `muscle_selection.dart`; library state; refresh + bundled source. All taxonomy-driven. | New rows appear in the dropdown and the editor chips with no code change | S-18901, S-18903, S-18911, S-18912 |
| Muscle counts in tests | `grep -rn "hasLength(24)\|24 entries\|17 muscles\|24 groups\|hasLength(23)" test` → `muscle_taxonomy_test.dart:27,28,46,124,142`; `muscle_display_test.dart:56,106,121` (23 = 24 − Obliques); `db_seed_test.dart:418,436` | These go red by design: 24 → 27, 17 → 20, 23 → 26. Ordered lists gain the 3 ids. | Phase 1 item 5 |
| Ordered region lists | `muscle_taxonomy_test.dart:57,144` (Legs list); `muscle_display_test.dart:22-55, 75-105` | Legs gains abductors last; full order gains 3 ids | S-18901, S-18903 |
| Picker menu labels | `test/muscle_filter_picker_test.dart:26-71` `_displayOrder`/`_indentedOrder`. **Plan-114 residue:** the comment says 24 rows but the list lacks "Shins". | Add Shins and the 3 new names. The menu grows to 28 rows; if the bottom rows fall off the 800×1400 surface, raise its height (the test's own constant). | S-18911 |
| R-005 group list | `catalog_referential_integrity_test.dart:318-336` `addedInV9` | Add the 3 ids | Phase 1 item 5 |
| Link-map size | `catalog_referential_integrity_test.dart:205,270` `hasLength(178)` | 178 + 28 = 206 (the re-tags add no entry) | S-18904 |
| Region-tagged / Calves sets | `catalog_referential_integrity_test.dart:208-231, 281-305` | Unchanged; they stay green and guard that no sport row was re-tagged | none needed |
| Literal catalog version | `grep -n "equals(13)\|Version(12)" test/tibialis_muscle_refresh_test.dart` → `equals(13)` at 145, 225, 283; `setCatalogVersion(12)` at 140, 258, 307 | After the bump, `equals(13)` goes red. Change each to `equals(bundledCatalogVersion)` and keep staging the literal `12`. | Phase 1 item 5 |
| Re-tagged ids | `grep -rn "exercise-hammer-curl\|exercise-cable-hip-abduction\|exercise-cable-external-rotation" lib test` outside seed → `demo_routines_seed.dart:316,819,859,903` (ids only) | Routines store ids, not muscles; HIT Full Body is unchanged | `seeded_demos_test.dart`, `seeded_demos_state_test.dart` green |
| `exercise-rear-delt-fly` description | `grep -rn "reverse pec-deck" lib test docs` → only `seed_data.dart:1306` | Text changes on fresh and untouched installs | S-18906 |
| Catalog size (252 exercises, 252 capability rows, 188 equipment rows) | `grep -c "^      id: 'exercise-" lib/mock/seed_data.dart` → 252. No test pins 252 (`grep -rn "252\|hasLength(25[0-9])" test` → 0 catalog hits). | 280 / 280 / 216 after 115a | S-18909 |
| Lists ordered by name | Widget tests that find seeded names in the library or picker: `pr8_exercise_library_test`, `pr7_exercise_details_view_test`, `screen_widget_test`, `interaction_flow_test`, `widget_test`, `library_grouping_test`, `exercise_library_filters_test`, `muscle_filter_picker_test`. New "Band…"/"Banded…" names sort above "Barbell…". | A lazily built list could push a found name off-screen. Expect none; the full suite decides. | Done Criteria full suite |
| Name search | `lib/core/utils/fuzzy_search.dart` (names only). Existing tests use exact `find.text` or `contains` (`grep -rn "searchText:" test`). | "hammer curl" now also returns Cross-Body Hammer Curl | none needed |
| Watch exercise list | `watch_reference_sync.dart:234` builds `exercises_down` from `getExercises()` in batches of ≤ 100 (`exercises_down.schema.json` `maxItems: 100`); the S-3843 fixture is synthetic (250 rows) | 280 rows are 3 batches; the wrist accepts any batch count. Health mapping needs `distance`; no new row has it. | `watch_reference_sync_test.dart` green |
| Equipment | `grep -rn -i equipment lib/features lib/widgets lib/state` → 0; only the repositories read it | Invisible (D-18909) | S-18905 (fresh), S-18906 (updated, Hive) |
| Docs claiming equipment is refreshed | `constants_reference.md:575`, `db_integration.md:107-109`, `catalog_version.dart:3-4` | Docs disagree with code; corrected in Phase 1 (code comment) and Phase 4 | Phase 4 |
| Stats, summary, home, sessions, calendar | Same grep as row 1: no muscle reader there | Unaffected | grep |

## UI Standards Impact

None. No UI file changes. The existing Muscle dropdown and `MusclePicker` chip rows render the new entries.

## Scenarios

Shared fixture notes: "custom" means `createExercise(Exercise(id, ownerUserId: 'user-1', name, …))` followed by
`setExerciseMuscleLinks`. Mock+Hive tests run over `harnessFactories` with plain `test()`, never `testWidgets`.

### S-18901: The three muscles sit in their regions (`test/muscle_taxonomy_test.dart`)
- Fixture: `MuscleTaxonomy.entries` as shipped.
- Expected: length 27. The 5 regions are unchanged, there are 20 entries with a parent, and the standalone
  set is `{chest, neck}`. `musclesOf('muscle-arms')` == `[biceps, triceps, forearms, brachialis]`;
  `musclesOf('muscle-shoulders')` == `[front-delts, side-delts, rear-delts, rotator-cuff]`;
  `musclesOf('muscle-legs')` == `[quads, hamstrings, glutes, calves, tibialis, adductors, abductors]`. Each
  new id has `regionOf` equal to its parent, `isRegion` false, and the D-18901 name. Red today.
- Edge case of: none

### S-18902: Storage rules with the new muscles (pure, same file)
- Fixture (P main, S assists): (a) `[arms P, brachialis P]`; (b) `[brachialis P, biceps P]`; (c) `[abductors P, adductors P]`; (d) `[shoulders P, rotator-cuff P, rear-delts S]`; (e) `[abductors P, abductors S]`.
- Expected `normalize`: (a) `[brachialis P]`; (b) `[biceps P, brachialis P]`; (c) `[adductors P, abductors P]`;
  (d) `[rotator-cuff P, rear-delts S]`; (e) throws `ArgumentError`. `matches`: `('muscle-legs', [abductors P])`
  true; `('muscle-glutes', [abductors P, glutes S])` false; `('muscle-shoulders', [rotator-cuff P])` true;
  `('muscle-rear-delts', [rotator-cuff P, rear-delts S])` false; `('muscle-arms', [brachialis P])` true.
  Red today: (a), (b), (c), (d) and the three region `matches`. Record which cases are guards only.
- Edge case of: S-18901

### S-18903: Dropdown order (`test/muscle_display_test.dart`)
- Fixture: the test's `_groups()` from the taxonomy; also `_groups(exclude: {'muscle-obliques'})`.
- Expected: the `muscleFilterEntries` id list is the existing S-1 list with `muscle-brachialis` after
  `muscle-forearms`, `muscle-rotator-cuff` after `muscle-rear-delts` and `muscle-abductors` after
  `muscle-adductors`. Each new id has depth 1, and the length is 27. The Obliques-excluded list has
  length 26. Red today.
- Edge case of: S-18901

### S-18904: The bundled link rows (`test/catalog_referential_integrity_test.dart`, approved rows)
- Fixture: `SeedData.exerciseMuscleLinks` as shipped.
- Expected: the three D-18902 rows, as lists: cable-hip-abduction `[abductors P, glutes S]`; cable-external-rotation `[rotator-cuff P, rear-delts S]`; hammer-curl `[biceps P, brachialis P, forearms S]`.
  The map length is 206. Main Abductors == `{cable-hip-abduction, machine-hip-abduction, banded-clamshell, banded-lateral-walk}`.
  Main Rotator cuff == `{cable-external-rotation, side-lying-external-rotation, cable-internal-rotation}`.
  Assisting Rotator cuff == `{band-pull-apart}`.
  Main Brachialis == `{hammer-curl, reverse-curl, zottman-curl, cross-body-hammer-curl}`.
  Assisting Brachialis == `{}`. Main Biceps == the four existing curls (`barbell-curl, dumbbell-curl, hammer-curl, preacher-curl`)
  plus `{incline-dumbbell-curl, cable-curl, concentration-curl, zottman-curl, cross-body-hammer-curl}` (9).
  Main Glutes excludes `cable-hip-abduction`. Main Rear delts excludes `cable-external-rotation`.
  The plan-114 Calves sets are unchanged. Red today.
- Edge case of: none

### S-18905: Filtering on a fresh install, Mock and Hive (`test/muscle_filter_test.dart`, new group)
- Fixture: the bundled catalog plus customs.
  - G "Glute Side Raise" `[glutes P]`: the user tagged it Glutes before the change.
  - B "Band Abduction" `[abductors P, glutes P]`: both the old and the new muscle.
  - H "Hammer Curl" `[biceps P]`: a custom near-twin with the same name.
  - R "Shoulder Prehab" `[rear-delts P, rotator-cuff S]`: the new muscle only as assisting.
  - E "Empty Move" `[]`.
- Expected (`searchExercises(muscleGroupIds: …)`):
  - Abductors → id set == the 4 bundled abductor ids plus B, each once.
  - Glutes → contains G, B and `exercise-barbell-hip-thrust`; excludes `exercise-cable-hip-abduction` and `exercise-machine-hip-abduction`.
  - Legs → contains both abduction rows, G and B, each exactly once; excludes E.
  - Rotator cuff → == the 3 cuff ids; excludes R and `exercise-band-pull-apart`.
  - Rear delts → contains R, `band-pull-apart`, `cable-rear-delt-fly`, `reverse-pec-deck` and `rear-delt-fly`; excludes `cable-external-rotation`.
  - Shoulders → `cable-external-rotation` once and R once.
  - Brachialis → == the 4 brachialis ids; excludes H.
  - Biceps → contains `hammer-curl`, H and `incline-dumbbell-curl`; excludes `reverse-curl`.
  - `['muscle-arms', 'muscle-brachialis']` → `hammer-curl` exactly once.
  - The ranked query `getExercisesRankedForModality('resistance_lifting', muscleGroupIds: ['muscle-abductors'])` returns the unfiltered ranked ids, in order, restricted to the Abductors set.
  - `getExerciseEquipment('exercise-leg-extension')` names == `['Machine']`; for `exercise-band-pull-apart` == `['Resistance Band']`.
- Red today: the new ids are absent.
- Edge case of: none

### S-18906: A v13 install refreshes (new `test/strength_catalog_refresh_test.dart`, Mock + Hive, `const BundledCatalogSource()`)
- Fixture (staged after `harness.open()`):
  1. Hive only: delete keys `muscle-brachialis`, `muscle-rotator-cuff` and `muscle-abductors` from box `muscle_groups`, then assert they are absent. Mock cannot do this; log it.
  2. For each of the 28 new ids: `deleteExercise(id)`, `setExerciseCapabilities(id, [])`, `setExerciseMuscleLinks(id, [])`; on Hive also delete the id from box `exercise_equipment`.
  3. The v13 rows: cable-hip-abduction `[glutes P]`; cable-external-rotation `[rear-delts P]`; hammer-curl `[biceps P, forearms S]`; `updateExercise` of rear-delt-fly with the old description text.
  4. Custom G "Glute Side Raise" `[glutes P]`.
  5. Custom D "Leg Extension" `[quads P]`: the same name as a new bundled row.
  6. Copy K = `ExerciseLibraryService(repo).copyAsCustom(cable-hip-abduction)`, taken after step 3, so K is `[glutes P]`.
  7. `exercise-machine-hip-adduction` untouched at `[adductors P]`.
  8. `setCatalogVersion(13)` (the literal).
- Trigger: `CatalogRefreshService(repo, const BundledCatalogSource()).refresh()`.
- Expected:
  - The refresh returns true. `getCatalogVersion() == bundledCatalogVersion`, and `bundledCatalogVersion >= 14`.
  - The 3 groups are present with the D-18901 name and parent.
  - The three re-tags equal D-18902.
  - Each of the 28 new ids exists with its table name, and its capabilities and links equal the bundled ones.
  - G and K are `[glutes P]`. D still exists with `[quads P]` and its name. `searchExercises(searchText: 'Leg Extension')` contains both D and `exercise-leg-extension`.
  - Machine Hip Adduction is unchanged. Rear Delt Fly's description equals D-18911.
  - The `muscleFilterEntries(getMuscleGroups())` Arms block reads arms, biceps, triceps, forearms, brachialis; Shoulders ends rear-delts, rotator-cuff; Legs ends adductors, abductors.
  - Hive only: `getExerciseEquipment('exercise-leg-extension')` is empty. This pins D-18909: an equipment-delivery PR must change this assertion on purpose.
  - A second `refresh()` returns false, and every link above is identical.
- Red today: the stored version 13 is not behind the bundled 13.
- Edge case of: none

### S-18907: User-edited rows keep their muscles (same file, both harnesses)
- Fixture: S-18906 steps 1 and 8. cable-hip-abduction links `[glutes P, hamstrings S]` plus `markSeedEntryTouched(SeedEntryType.exercise, 'exercise-cable-hip-abduction')`. hammer-curl renamed "My Hammer Curl" via `updateExercise`, links `[biceps P]`, touched.
- Expected after `refresh()`: both rows keep exactly those names and links. The Abductors filter excludes cable-hip-abduction, and the Brachialis filter excludes hammer-curl. The 3 groups exist, and the version is bumped. Red today on Hive (groups not re-added); a guard only on Mock. Record which.
- Edge case of: S-18906

### S-18909: New-row conformance and catalog guards (new `test/strength_catalog_gaps_test.dart`, pure)
- Fixture: a const table in the test that mirrors the New-row table (28 entries). Phase 2A writes rows 1–16 and 2B adds 17–28.
- Expected, for every table row:
  - The row exists in `sampleExercises` with the exact name, `discipline-bodybuilding`, the tabled `movementPattern` (null for "—") and `ownerUserId` null.
  - `description` is non-empty, and `howToSteps` has 3–4 non-empty entries.
  - Its capabilities equal the tabled set, its links equal `_muscles` of the tabled P/S, and its equipment equals the tabled list.
- Global guards: no two bundled names are equal ignoring case and surrounding spaces.
  `sampleExercises.length == 252 + N`, the capability map `== 252 + N`, the equipment map `== 188 + N`, and
  the link map `== 178 + N`, where N is the table length. Every new id sorts after `exercise-2k-row-test`.
- Red today: rows absent.
- Edge case of: none

### S-18910: The SQL contract carries the three muscles (`test/db_seed_test.dart`, S-9)
- Fixture: the existing S-9 in-memory harness (schema then seed).
- Expected: 27 rows. Exactly one each of `Brachialis` (parent = id of `Arms`), `Rotator cuff` (parent = `Shoulders`) and `Abductors` (parent = `Legs`). The title becomes `… seeds the 27 groups the taxonomy defines`. Red today.
- Edge case of: none

### S-18911: The picker's Muscle menu (`test/muscle_filter_picker_test.dart`, S-2, Mock, widget)
- Fixture: a fresh Mock repo; the picker on the test surface.
- Expected: `_displayOrder` is All plus the 27 names in S-18903 order, Shins included. Each row sits below the
  previous one, and the 20 muscle names (Shins and the 3 new ones included) are indented. Red today.
- Edge case of: S-18903

### S-18912: Editor chips (`test/muscle_picker_test.dart`, widget, no persistence)
- Fixture: `_PickerHost(groups: _allGroups())`.
- Expected: the chip labels read, in order, Biceps, Triceps, Forearms, Brachialis in the Arms row; Front
  delts, Side delts, Rear delts, Rotator cuff in the Shoulders row; and the Legs row ends Adductors,
  Abductors. Choosing Whole arms then Brachialis stores `[brachialis P]` only. Red today.
- Edge case of: S-18902

## Iteration 1

### Phase 1: Muscles, re-tags, version, SQL, enumerations (@dba; item 4 by the lead)
1. [ ] Record baselines in the evidence file: the `flutter analyze` issue count (plan 114: 181) and pass/fail counts of the Done Criteria suites — `2026-11-04-115a-strength-catalog-gaps-plan.evidence.md`
2. [ ] Add the three D-18901 entries — `lib/data/models/muscle_taxonomy.dart` · `MuscleTaxonomy.entries`
3. [ ] Apply the three D-18902 re-tags and the D-18911 description — `lib/mock/seed_data.dart:4519,4631,4634` · `exerciseMuscleLinks`; `:1306` · `exercise-rear-delt-fly`
4. [ ] (lead) Set `bundledCatalogVersion = 14` and make the two D-18906 doc-comment edits — `lib/core/constants/catalog_version.dart`
5. [ ] Add the three D-18912 SQL inserts — `scripts/sqlite_seed.sql:377,383,389`
6. [ ] Update the existing enumerations (Impact rows 2–6 and the version row): 24→27, 17→20, 23→26 plus titles; the ordered lists; `addedInV9` + the 3 ids; `_displayOrder`/`_indentedOrder` + Shins and the 3 names; `tibialis_muscle_refresh_test.dart` `equals(13)` → `equals(bundledCatalogVersion)`; leave `hasLength(178)` for Phase 2.
7. [ ] Write S-18901, S-18902 (`muscle_taxonomy_test.dart`), S-18903 (`muscle_display_test.dart`), S-18910 (`db_seed_test.dart`), S-18911 (`muscle_filter_picker_test.dart`), S-18912 (`muscle_picker_test.dart`), and the re-tag rows of S-18904 (`catalog_referential_integrity_test.dart`). Show the Red-today ones red with items 2–5 reverted, then green; record it in the evidence file.

**Done Criteria** (Claude agents wrap in `bash .claude/scripts/macos/with-timeout.sh`; Copilot agents use the gateway):
- `flutter analyze`: issue count ≤ the item-1 baseline
- `flutter test test/muscle_taxonomy_test.dart test/muscle_display_test.dart test/muscle_picker_test.dart test/muscle_filter_picker_test.dart test/muscle_filter_test.dart test/muscle_links_storage_test.dart test/catalog_referential_integrity_test.dart test/catalog_refresh_test.dart test/tibialis_muscle_refresh_test.dart test/db_seed_test.dart test/seeded_demos_test.dart test/seeded_demos_state_test.dart`
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -c "muscle-brachialis\|muscle-rotator-cuff\|muscle-abductors" lib/data/models/muscle_taxonomy.dart` → 3; `grep -n "bundledCatalogVersion = 14" lib/core/constants/catalog_version.dart` → 1 line; `grep -c "'Brachialis'\|'Rotator cuff'\|'Abductors'" scripts/sqlite_seed.sql` → 3

**Predicted Files**: `lib/data/models/muscle_taxonomy.dart`, `lib/mock/seed_data.dart`, `lib/core/constants/catalog_version.dart`, `scripts/sqlite_seed.sql`, `test/muscle_taxonomy_test.dart`, `test/muscle_display_test.dart`, `test/muscle_picker_test.dart`, `test/muscle_filter_picker_test.dart`, `test/catalog_referential_integrity_test.dart`, `test/tibialis_muscle_refresh_test.dart`, `test/db_seed_test.dart`, evidence file. Production diff: about 15 lines.

### Phase 2A: Rows 1–16, the new-muscle exercises and arms (@dba)
1. [ ] Append rows 1–6 to `sampleExercises` (D-18904, D-18905, D-18907) and to the capability, link and equipment maps (D-18908, D-18909) — `lib/mock/seed_data.dart`
2. [ ] Same for rows 7–12 (curls)
3. [ ] Same for rows 13–16 (triceps)
4. [ ] Create `test/strength_catalog_gaps_test.dart` with S-18909 over rows 1–16 (N = 16)
5. [ ] Add the new-row sets of S-18904 that 2A completes (Abductors, Rotator cuff, Brachialis, Biceps) and set the link-map length to 178 + 16
6. [ ] Show S-18909 red with item 1 reverted; paste the counts into the evidence file; update Progress and the Assumption Log

**Done Criteria**: Phase 1's suites plus `test/strength_catalog_gaps_test.dart` and `test/watch_reference_sync_test.dart`; `flutter analyze` ≤ baseline; `grep -c "^      id: 'exercise-" lib/mock/seed_data.dart` → 268.
**Predicted Files**: `lib/mock/seed_data.dart`, `test/strength_catalog_gaps_test.dart` (new), `test/catalog_referential_integrity_test.dart`, evidence file. Production diff: about 320 lines.

### Phase 2B: Rows 17–28, machine and isolation lifts (@dba)
1. [ ] Append rows 17–19 (legs), 20–24 (chest) and 25–28 (shoulders, traps) as in 2A item 1 — `lib/mock/seed_data.dart`
2. [ ] Extend the S-18909 table to 28 rows (N = 28); link-map length 206 in both `hasLength` sites
3. [ ] Run the full suite (`flutter test`, 900 s): the catalog grew, so any name-ordered widget test the greps missed fails here. Fix it in place and list it in the evidence file as an unpredicted file.

**Done Criteria**: Phase 2A's suites; `flutter test` (full) with 0 failures; `grep -c "^      id: 'exercise-" lib/mock/seed_data.dart` → 280.
**Predicted Files**: `lib/mock/seed_data.dart`, `test/strength_catalog_gaps_test.dart`, `test/catalog_referential_integrity_test.dart`, evidence file. Production diff: about 240 lines.

### Phase 3: Filter and refresh scenarios, Mock and Hive (@dba)
1. [ ] Write S-18905 as a new group in `test/muscle_filter_test.dart`
2. [ ] Write S-18906 and S-18907 in new `test/strength_catalog_refresh_test.dart` (Hive staging in the test body; plain `test()`)
3. [ ] Show each "Red today" red. For S-18906/7, set the version back to 13 by hand; for S-18905, revert the 2A/2B rows. Then show green, and record the red→green table and the Mock-only exceptions in the evidence file.

**Done Criteria**: `flutter test test/muscle_filter_test.dart test/strength_catalog_refresh_test.dart test/tibialis_muscle_refresh_test.dart test/catalog_refresh_test.dart`; `flutter test` (full, 900 s) with 0 failures; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` prints nothing.
**Predicted Files**: `test/muscle_filter_test.dart`, `test/strength_catalog_refresh_test.dart` (new), evidence file.

### Phase 4: Docs and residue sweep (@dba)
1. [ ] Arms, Legs and Shoulders rows gain the new muscles in D-18901 order; the cited title becomes `27 entries: 5 regions, 20 muscles, 2 standalone` — `docs/data_models.md:202-211` (47,949 B; stay under 53,248)
2. [ ] Drop "equipment" from the refreshed-catalog list and add a sentence: equipment links are written at first install only, and the refresh does not deliver them (cite S-18906). Add a sentence after the version-13 one: version `14` adds Brachialis, Rotator cuff and Abductors, the three re-tags and 28 exercises (cite S-18906, S-18907). Cite the S-9 title with 27 groups — `docs/db_integration.md:107-109,126-129,603`
3. [ ] `bundledCatalogVersion` `13` → `14`; the description drops "equipment" — `docs/constants_reference.md:575`
4. [ ] Residue sweep, pasted into the evidence file: `grep -rn "24 groups\|24 entries\|17 muscles\|hasLength(24)\|hasLength(178)\|equals(13)" lib test docs | grep -v "docs/plans\|docs/history\|docs/releases"` prints only hits proven unrelated; `grep -rn "reverse pec-deck" lib` → 0

**Done Criteria**: `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`; `wc -c docs/data_models.md docs/db_integration.md docs/constants_reference.md` each < 53,248; the item-4 greps as stated.
**Predicted Files**: `docs/data_models.md`, `docs/db_integration.md`, `docs/constants_reference.md`, evidence file.

### Phase 5: Review (@code-reviewer)
Diff versus every phase's Predicted Files, and the Diff-boundary invariant:
`git diff --stat -- lib/features lib/widgets lib/state lib/core/services lib/data/repositories lib/watch watch lib/core/constants/data_version.dart scripts/sqlite_schema.sql` prints nothing.
Re-run every Impact grep. Read all 28 texts against D-18907. Mutations, each of which must turn the named tests red:
- M1: cable-hip-abduction back to `[glutes P]` → S-18904, S-18905, S-18906
- M2: Brachialis moved before Biceps → S-18901, S-18903, S-18911, S-18912, S-18906
- M3: version left at 13 → S-18906, S-18907
- M4: one SQL insert removed → S-18910
- M5: the touched-skip in `_refreshExerciseMuscleGroups` removed → S-18907
- M6: `bilateral` dropped from Triceps Kickback → S-18909
- M7: the link row of `exercise-reverse-curl` removed → S-18909, S-18905
- M8: row 8 renamed "Hammer Curl" → S-18909 (the name-uniqueness guard)

Findings go in `2026-11-04-115a-strength-catalog-gaps-plan.review.md`.

## Files Affected

Production: `muscle_taxonomy.dart`, `seed_data.dart`, `catalog_version.dart` (lead), `sqlite_seed.sql`. About 575 lines.
Read-only dependents, guarded by tests: `muscle_display.dart`, `muscle_selection.dart`, `muscle_picker.dart`, the exercise library, picker, editor and detail screens, `catalog_refresh_service.dart`, `bundled_catalog_source.dart`, both repositories, `demo_routines_seed.dart`, `watch_reference_sync.dart`.

## Notes

- **Dependency graph:** 1 → {2A, 2B} → 3 → 4 → 5. 2A and 2B are independent of each other, and either may
  go first. Running 2B first gives no new-muscle exercises until 2A, so the new filter rows list only the
  re-tagged row. Phase 3 needs both, because S-18906 checks all 28 rows.
- **Intermediate states:** after Phase 1, Abductors lists only Cable Hip Abduction, Rotator cuff only Cable
  External Rotation, and Brachialis only Hammer Curl. That is acceptable between phases, but do not ship it.
- **No migration:** the refresh delivers groups, rows, capabilities and links (`catalog_refresh_service.dart:59-62`).
- **Optional extras (priced, NOT in this PR):**
  - *Equipment delivery in the update* (Q1 option b): a `CatalogSource` field, a `WorkoutRepository` setter in
    both repositories, and a refresh step that honours touched rows, with Mock+Hive tests. One @dba PR, about
    100–150 production lines. Nothing changes on screen until the next extra lands.
  - *Show equipment* (a detail-screen line or an equipment filter): a @developer PR of about 2 phases. Needs
    the previous extra first, or updated phones show none.
  - *Search that also matches muscle names* (carried from plan 114): a @developer PR of about 2 phases, with
    product calls on ranking.
  - *Empty equipment on existing rows*: 51 rows in `exerciseEquipmentRelationships` are `[]` (Face Pull,
    Glute Kickback, Cable Crunch, Seated Calf Raise, Cable Lateral Raise and others; count taken with awk over
    `seed_data.dart:4659-4862`). A seed-only fix of about 51 lines, invisible today.
- **Follow-ups:** PR 115b (see the series index), then conditioning/plyometrics (needs discipline delivery or
  an existing discipline), then yoga.

## Progress
- [x] Phase 1 (muscles, re-tags, version 14, SQL, enumerations, screen tests) · [x] Phase 2A rows 1-16 · [x] Phase 2B rows 17-28 · [x] Phase 3 (filter + refresh tests, Mock and Hive) · [x] Phase 4 (docs, residue sweep) · [x] Phase 5 review: APPROVE, 0 blocker, 0 major, 2 minors, both fixed
- Full suite final run: `+6446 ~2`, 0 failed. Analyze 181 (= baseline). Not committed.

## Assumption Log
- `catalog_version.dart` is outside `crew-builder-data`'s ceiling: the lead made the version 14 bump, its history sentence and the "equipment" wording fix. Ratified.
- The 28 rows were built in three data-builder runs (rows 1-6, 7-16, 17-28) instead of the two phases the plan names. Same scope and files; Ratified.
- `docs/constants_reference.md` gained one sentence beyond the plan (a version bump alone does not deliver equipment, disciplines or categories). Ratified: the old sentence was false.
- `test/muscle_filter_picker_test.dart` surface raised from 800x1400 to 800x1800 (28-row menu). Ratified.
- Mock cannot remove a muscle group or an equipment link: the "device without the new groups / equipment" staging steps run on Hive only; Mock asserts the rest (plan 114 precedent). Ratified.
- S-18908 was never issued. No action.
- Full-suite run 1 after the rows landed had one failure the lead did not capture by name; runs 2 and 3 were green (`+6440`, `+6446`). Unidentified, escalated to the owner as a note in the report.

## Feedback
Review: `2026-11-04-115a-strength-catalog-gaps-plan.review.md`. Minor 1 (Cable Rear Delt Fly said "low pulley", which loads the side delt): fixed, step now says a pulley at shoulder height. Minor 2 (empty Assumption Log): fixed above.
