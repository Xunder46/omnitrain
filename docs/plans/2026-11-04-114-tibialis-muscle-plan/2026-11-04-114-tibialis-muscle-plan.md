# 114 — Shins becomes its own muscle; Tibialis Raise moves to it

> Status: APPROVED to build. Q1–Q3 answered "all defaults" by the owner on 2026-11-04 (name "Shins"; no Calves assist; a user-edited Tibialis Raise keeps its muscles).
> Next handoff: @dba (Phase 1), run by the crew (`crew-builder-data`)
> Binding conventions: `docs/global_conventions.md`, `docs/data_models.md` (MuscleGroup section), `docs/db_integration.md` (catalog refresh, SQL contract)
> Track: phone only (`lib/`, `scripts/`, `test/`, `docs/`). Base: `claude_develop` at `d3c5bb4c`. Never branch or commit.
> Precedent: plan 33 (`docs/plans/2026-10-14-33-muscle-hierarchy-data-plan/`) built the hierarchy, roles and the refresh this plan reuses.

## Overview

Classification: **STANDARD**, but small. It is not TRIVIAL because it changes bundled reference data that existing installs receive through the catalog refresh, and it changes what a muscle filter returns.

What a user sees after this PR:

1. The exercise filter's **Muscle** list shows a new entry, **Shins**, indented under **Legs** between Calves and Adductors.
2. Picking **Shins** lists Tibialis Raise. Picking **Calves** no longer lists it. Picking **Legs** still lists it.
3. Tibialis Raise's detail shows **Main: Shins** and no "Assists" line.
4. The exercise editor offers a **Shins** chip in the Legs row. Choosing Shins together with "Whole legs" keeps just Shins, the same as for every other leg muscle.
5. Existing installs get all of this on the next launch. A Tibialis Raise the user has edited, any copy the user made of it, and the user's own exercises tagged Calves keep their muscles exactly as they are.
6. Nothing else changes: the other Calves exercises, Stats, the watch app, and the HIT Full Body routine (which still includes Tibialis Raise).

## Owner questions (one batch; the plan applies every default)

- **Q1. What is the muscle called on screen?** Default: **"Shins"**. It is plain language, matches the short gym names already in the list (Lats, Traps, Abs), and fits the half-width Muscle filter field, which cuts long names off with "…". The exercise's own name already says "Tibialis". Alternatives: "Tibialis / Shins" (your working title, which may be cut off in the closed filter field on narrow phones) or "Tibialis". *Swap cost:* change the one name literal in the four places listed under D-18801.
- **Q2. Should Tibialis Raise keep Calves as a secondary ("assists") muscle?** Default: **no**. The movement lifts the toes and does not work the calves. Either way, picking Calves would not list it, because only main muscles count for the filter.
- **Q3. If the user has edited their Tibialis Raise (renamed it, changed its muscles), does the update still move it to Shins?** Default: **no, their edit wins**, as you decided for the muscle hierarchy update (plan 33, D-8). Their Tibialis Raise stays on whatever muscles they chose, and the new Shins entry still appears in the list.

## Resolved Decisions (Ledger)

- **D-18801** New muscle entry: id `muscle-tibialis`, name `Shins` (Q1), parent `muscle-legs`. It goes in `MuscleTaxonomy.entries` directly after `muscle-calves` and before `muscle-adductors` (derived; veto with Q1). That position fixes its place in the filter dropdown, the editor chips and the stored link order. The name literal lives in exactly four places: `lib/data/models/muscle_taxonomy.dart`, `scripts/sqlite_seed.sql`, `test/muscle_taxonomy_test.dart` (one assertion) and `docs/data_models.md`. Every other test refers to the muscle by id or through the taxonomy.
- **D-18802** `SeedData.exerciseMuscleLinks['exercise-tibialis-raise']` becomes exactly `_muscles(primary: ['muscle-tibialis'])`: no secondary (Q2). No other bundled exercise's links change, and the map keeps 178 entries.
- **D-18803** The filter rules are unchanged (plan 33 D-3). Only main links count. Selecting Legs matches main links to Legs or any Legs muscle, now Shins included. Selecting Shins matches exactly `muscle-tibialis`. A secondary-only Shins link never matches.
- **D-18804** `bundledCatalogVersion` goes from 12 to 13, with one history sentence appended to the doc comment in `lib/core/constants/catalog_version.dart`: "When Shins (`muscle-tibialis`, under Legs) was added and Tibialis Raise moved to it from Calves, we bumped to `13` so existing installs receive the new muscle and the corrected tagging on next launch." The existing refresh steps (`_refreshMuscleGroups`, `_refreshExerciseMuscleGroups`) deliver the change. No refresh code changes, and there is no data migration: `currentDataVersion` is unchanged.
- **D-18805** (derived from the plan 33 D-8 owner answer; veto via Q3) Rows the user owns are never rewritten. That covers a bundled Tibialis Raise marked touched (`isSeedEntryTouched(exercise, 'exercise-tibialis-raise')`), a user copy (`copyAsCustom`, a new custom id), and any custom exercise tagged Calves, including one the user named "Tibialis Raise". The refresh code already enforces this; this plan adds guards.
- **D-18806** The other Calves-tagged bundled exercises are untouched. Main Calves stays on exactly 8: `exercise-standing-calf-raise`, `exercise-seated-calf-raise`, `exercise-calf-raise-hold`, `exercise-single-leg-calf-raise-hold`, `exercise-standing-calf-stretch`, `exercise-soleus-stretch`, `exercise-jump-rope-steady`, `exercise-jump-rope-intervals`. Assisting Calves stays on exactly 2: `exercise-nordic-curl`, `exercise-wall-sit`.
- **D-18807** SQL contract: `scripts/sqlite_schema.sql` is unchanged, because `app_muscle_group.parent_id` already exists. `scripts/sqlite_seed.sql` gains one insert directly after the `Calves` line (~381), in the same form: `('Shins', (SELECT id FROM app_muscle_group WHERE name = 'Legs'))`. No SQL link rows are added; the SQL fixture has no Tibialis Raise (`grep -ci tibialis scripts/sqlite_seed.sql` → 0).
- **D-18808** Out of this PR: equipment tags and `movementPattern` on Tibialis Raise, and matching search against muscle names (see Notes → Optional extras). The watch, the sync contract, Stats, the home screen, sessions and routines get no change (see the Impact table greps).

## Feature Invariants

- `MuscleTaxonomy.entries` is the single code source of muscles. `SeedData.sampleMuscleGroups` is derived from it and never hand-edited.
- The catalog refresh never rewrites a touched, custom or copied exercise's links (D-18805).
- `MockWorkoutRepository` and `HiveWorkoutRepository` return the same filter results and the same post-refresh links in S-18804 to S-18806. The one documented exception is that Mock cannot remove a group, so it cannot stage a device without Shins (plan 33 precedent).
- Diff boundary: no file under `lib/features/`, `lib/widgets/`, `lib/state/`, `lib/core/services/`, `lib/data/repositories/`, `lib/watch/`, `watch/`, or `lib/core/constants/data_version.dart` changes.

## Requirements and Acceptance Criteria

| Id | Acceptance (what a user sees) | Scenarios |
|---|---|---|
| A1 | Muscle filter lists "Shins" indented under Legs, between Calves and Adductors, on fresh and refreshed installs | S-18801, S-18809, S-18805 |
| A2 | Shins lists Tibialis Raise; Calves does not; Legs still does, once | S-18804 |
| A3 | Tibialis Raise: Main = Shins, no Assists | S-18803 |
| A4 | Editor: Shins + Whole legs stores just Shins; Calves + Shins stores both, Calves first | S-18802 |
| A5 | v12 installs receive it on next launch; user-edited, copied and own Calves exercises keep their muscles | S-18805, S-18806, S-18807 |
| A6 | Other Calves exercises, the SQL contract, the HIT routine, Stats and the watch are unchanged | S-18803, S-18808, Impact table |

## Existing-Functionality Impact

| Touched surface | Readers (grep run 2026-11-04) | Effect | Guard |
|---|---|---|---|
| `MuscleTaxonomy.entries` | `grep -rln "MuscleTaxonomy" lib` → `muscle_taxonomy.dart`, `core/utils/muscle_display.dart`, `core/utils/muscle_selection.dart`, `widgets/exercise/muscle_picker.dart`, `mock/seed_data.dart`, both repos (filter), `catalog_refresh_service.dart` (via source) | All are taxonomy-driven: the dropdown (`muscleFilterEntries`), the editor chips (`musclesOf`) and `normalize` pick up Shins with no code change | S-18801, S-18802, S-18809 |
| Muscle counts in tests | `grep -n "hasLength(23)\|16 muscles\|23 groups" test` → `muscle_taxonomy_test.dart:27-28,45`, `muscle_display_test.dart:55` (+ ordered list :27-54), `catalog_refresh_test.dart:277`, `db_seed_test.dart:417,436` | Literal 23/16 go red by design; update to 24/17 and add `muscle-tibialis` to the ordered lists | Phase 1 item 5 |
| `musclesOf('muscle-legs')` set | `test/muscle_taxonomy_test.dart:57-63` | Gains `muscle-tibialis` | S-18801 |
| R-005 "groups added after first launch" list | `test/catalog_referential_integrity_test.dart:266-~345` (`addedInV9` list) | Add `muscle-tibialis` so R-005 also proves it survives a refresh | Phase 1 item 5 |
| `exercise-tibialis-raise` | `grep -rn "exercise-tibialis-raise" lib test` → `seed_data.dart:3912` (exercise row, unchanged), `:4636` (links, changed), `:4852` (equipment, unchanged), `:5169` (capabilities, unchanged), `demo_routines_seed.dart:962` (HIT Full Body effort 4, id only); 0 test hits | Only the link row changes; the routine stores the id, not muscles (`grep -ci muscle lib/mock/demo_routines_seed.dart` → 1, a description string) | S-18803; `seeded_demos_test.dart`, `seeded_demos_state_test.dart` stay green |
| `bundledCatalogVersion` | `grep -rn "bundledCatalogVersion" test` shows no literal pin (`grep -rn "equals(12)" test` → only an unrelated protein value) | Refresh runs once on every v12 device | S-18805 (stages the literal `12`, asserts the literal `13`) |
| Hive group order after refresh | `hive_workout_repository.dart:1759` `getMuscleGroups` returns box order, so a refreshed device has Shins last; display reorders via taxonomy (`muscle_display.dart` `muscleFilterEntries`), list rows and detail use stored link order (`exercise_library_screen.dart:254`, `musclesWithRole`) | No visible ordering drift | S-18805 asserts dropdown order on Hive |
| Stats / Records, home, session, routine, calendar | `grep -rli muscle lib/features/stats lib/features/home lib/features/session lib/features/routine lib/features/calendar` → 0; stats services 0 | Unaffected | grep |
| Watch app and phone↔watch contract | `grep -rli muscle watch lib/watch` → 0 | Unaffected | grep |
| Search | `lib/core/utils/fuzzy_search.dart` matches the exercise name only; "tibialis" already finds Tibialis Raise | Unaffected | none needed |
| SQL contract | `scripts/sqlite_seed.sql:368-390` muscle inserts; `test/db_seed_test.dart:417` S-9 | +1 insert; S-9 count 23 → 24 | S-18808 |
| Docs | `grep -rln "Calves\|23 groups\|23 entries" docs` (excluding plans/history/releases) → `data_models.md:202,209`, `db_integration.md:599-601`; `constants_reference.md:575` carries the literal `12` | Updated in Phase 2 | Phase 2 |

## UI Standards Impact

None. No UI file changes. The existing Muscle dropdown and the `MusclePicker` FilterChips render the new entry.

## Scenarios

### S-18801: Shins sits under Legs, after Calves
- Fixture: `MuscleTaxonomy.entries` and `SeedData.sampleMuscleGroups` as shipped.
- Trigger/Flow: read the taxonomy.
- Expected: `entries.length == 24`; regions unchanged (the same 5); entries with a parent == 17; `musclesOf('muscle-legs')` as an ordered list == `[muscle-quads, muscle-hamstrings, muscle-glutes, muscle-calves, muscle-tibialis, muscle-adductors]`; `regionOf('muscle-tibialis') == 'muscle-legs'`; `isRegion('muscle-tibialis')` false; its name == `'Shins'`; `sampleMuscleGroups` ids/names/parents still equal the taxonomy. The existing test title becomes `24 entries: 5 regions, 17 muscles, 2 standalone`. Red today: entry absent.
- Edge case of: none

### S-18802: Storage rules with Shins (pure, `test/muscle_taxonomy_test.dart`)
- Fixture (links; P = primary, S = secondary): (a) `[legs P, tibialis P]`; (b) `[tibialis P, calves P]`; (c) `[adductors P, tibialis P]`; (d) `[tibialis S]`; (e) `[tibialis P, tibialis S]`; (f) `[tibialis P, tibialis P]`.
- Flow: `normalize` each; `matches` on (g) `matches('muscle-legs', [tibialis P])`, (h) `matches('muscle-calves', [tibialis P])`, (i) `matches('muscle-tibialis', [calves P, tibialis S])`.
- Expected: (a) `[tibialis P]`; (b) `[calves P, tibialis P]`; (c) `[tibialis P, adductors P]`; (d) throws `ArgumentError`; (e) throws; (f) `[tibialis P]`; (g) true; (h) false; (i) false. Red today: (a), (c) and (g), because the unknown id is not a Legs muscle and sorts last. (b), (d), (e), (f), (h) and (i) pass both ways and are guards only; say so in the evidence.
- Edge case of: S-18801

### S-18803: The bundled Tibialis Raise row (`test/catalog_referential_integrity_test.dart`, S-3 approved rows)
- Fixture: `SeedData.exerciseMuscleLinks` as shipped.
- Expected: `['exercise-tibialis-raise']` equals exactly `[ExerciseMuscleLink('muscle-tibialis', primary)]` (list equality, no secondary); map length 178; exactly one entry contains `muscle-tibialis`; the set of entries with a main Calves link == the 8 ids of D-18806; the set with an assisting Calves link == `{exercise-nordic-curl, exercise-wall-sit}`. Red today: the row is Calves, and the main-Calves set has 9.
- Edge case of: none

### S-18804: Filtering on a fresh install, Mock and Hive (`test/muscle_filter_test.dart`, `harnessFactories`, plain `test()`)
- Fixture: the bundled catalog plus five custom exercises created in the test, each with `setExerciseMuscleLinks`:
  X "Shin Box Hop" `[calves P, tibialis P]`; Y "Step-Down" `[quads P, tibialis S]`; Z "Hill Walk" `[legs P]`; E "Mobility Flow" `[]` (empty);
  W "Tibialis Raise" (custom near-twin, same name as the bundled one) `[calves P]`.
- Flow/Expected (`searchExercises(muscleGroupIds: …)`):
  - `['muscle-tibialis']` → id set == `{exercise-tibialis-raise, X}`, each once (not Y, Z, W or E).
  - `['muscle-calves']` → contains X, W and `exercise-standing-calf-raise`; excludes `exercise-tibialis-raise`, `exercise-nordic-curl` and Y.
  - `['muscle-legs']` → contains `exercise-tibialis-raise`, X, Y, Z and W, each exactly once; excludes E.
  - `['muscle-tibialis', 'muscle-legs']` → `exercise-tibialis-raise` exactly once.
  - Ranked query: `getExercisesRankedForModality('resistance_lifting', muscleGroupIds: ['muscle-tibialis'])` ids == the unfiltered ranked ids, kept in order, restricted to `{exercise-tibialis-raise, X}`.
- Red today: the Shins result lacks the bundled row, and Calves includes it.
- Edge case of: none

### S-18805: A v12 install refreshes to v13 (new `test/tibialis_muscle_refresh_test.dart`, `harnessFactories`, plain `test()`)
- Fixture (staged after `harness.open()`):
  1. Hive only: delete key `muscle-tibialis` from box `muscle_groups`, then assert `getMuscleGroups()` lacks it. Mock cannot remove a group: log this in the Assumption Log and assert the rest.
  2. `setExerciseMuscleLinks('exercise-tibialis-raise', [calves P])` (the v12 bundled row).
  3. Custom C "My Shin Raise" `[calves P]`.
  4. User copy K = `copyAsCustom('exercise-tibialis-raise')`, taken after step 2, so K = `[calves P]`.
  5. `exercise-seated-calf-raise` untouched at its bundled `[calves P]`.
  6. `setCatalogVersion(12)`: the literal 12, not `bundledCatalogVersion - 1`.
- Trigger: `CatalogRefreshService(repo, const BundledCatalogSource()).refresh()`.
- Expected: returns true; `getCatalogVersion() == 13` (literal); group `muscle-tibialis` present, named `Shins`, parent `muscle-legs`; `exercise-tibialis-raise` links == `[tibialis P]`; C, K and `exercise-seated-calf-raise` each == `[calves P]`; `muscleFilterEntries(await repo.getMuscleGroups())` ids list the Legs block in this order: legs, quads, hamstrings, glutes, calves, tibialis, adductors (on Hive this guards the box-append order); `searchExercises(muscleGroupIds: ['muscle-tibialis'])` contains `exercise-tibialis-raise` and neither C nor K. A second `refresh()` returns false and every link above is identical.
- Red today: with the bundled version at 12 the refresh returns false.
- Edge case of: none

### S-18806: A user-edited Tibialis Raise keeps its muscles (same file, both harnesses)
- Fixture: S-18805 steps 1 and 6; `exercise-tibialis-raise` links `[calves P, quads S]`; `markSeedEntryTouched(SeedEntryType.exercise, 'exercise-tibialis-raise')`.
- Expected after `refresh()`: the row's links are exactly `[calves P, quads S]`; the Shins group exists (Hive: was re-added); the Shins filter excludes it; version 13. Red today on Hive (no group added); on Mock it is a guard only. Record which in the evidence.
- Edge case of: S-18805

### S-18807: A legacy-shape row is upgraded (same file, Hive only)
- Fixture: S-18805 steps 1 and 6; write the raw value `['muscle-calves']` (a `List<String>`, the pre-plan-33 shape) into box `exercise_muscle_groups` under key `exercise-tibialis-raise`.
- Expected after `refresh()`: `getExerciseMuscleLinks('exercise-tibialis-raise') == [tibialis P]`; the raw box value is now a list of maps. Red today: the refresh does not run.
- Edge case of: S-18805

### S-18808: The SQL contract carries Shins (`test/db_seed_test.dart`, S-9)
- Fixture: execute `scripts/sqlite_schema.sql` then `scripts/sqlite_seed.sql` in memory (the existing S-9 harness).
- Expected: `app_muscle_group` has 24 rows; exactly one row named `Shins`, whose `parent_id` equals the id of the row named `Legs`. The S-9 title becomes `… seeds the 24 groups the taxonomy defines`. Red today: 23 rows, no Shins.
- Edge case of: none

### S-18809: The filter dropdown order (`test/muscle_display_test.dart`, S-1)
- Fixture: the test's existing `_groups()` built from the taxonomy.
- Expected: `muscleFilterEntries` id list == the existing expected list with `muscle-tibialis` inserted between `muscle-calves` and `muscle-adductors`, at depth 1; length 24. Red today: absent.
- Edge case of: S-18801

## Iteration 1

### Phase 1: Data, seed, SQL and guards (@dba)
1. [ ] Record baselines in the evidence file: `flutter analyze` issue count (plan 113 measured 181) and pass/fail counts of the Done Criteria suites. — `2026-11-04-114-tibialis-muscle-plan.evidence.md`
2. [ ] Add `MuscleTaxonomyEntry('muscle-tibialis', 'Shins', 'muscle-legs')` directly after the Calves entry (D-18801) — `lib/data/models/muscle_taxonomy.dart` · `MuscleTaxonomy.entries`
3. [ ] Change the row to `_muscles(primary: ['muscle-tibialis'])` (D-18802); touch no other row — `lib/mock/seed_data.dart:4636` · `exerciseMuscleLinks`
4. [ ] Set `bundledCatalogVersion = 13` and append the D-18804 sentence after the `12` sentence; add the Shins insert after the Calves line (D-18807) — `lib/core/constants/catalog_version.dart` · `bundledCatalogVersion`; `scripts/sqlite_seed.sql:~381`
5. [ ] Update the existing enumerations: 23→24 and 16→17 plus the test title; Legs set + `muscle-tibialis`; ordered list + length 24; `hasLength(23)` → `MuscleTaxonomy.entries.length`; `addedInV9` + `muscle-tibialis`; S-9 count and title — `test/muscle_taxonomy_test.dart:27-63`, `test/muscle_display_test.dart:22-55`, `test/catalog_refresh_test.dart:277`, `test/catalog_referential_integrity_test.dart` (R-005), `test/db_seed_test.dart:417-436`
6. [ ] Write S-18801, S-18802 (`test/muscle_taxonomy_test.dart`), S-18803 (`test/catalog_referential_integrity_test.dart`, approved-rows test), S-18808 (`test/db_seed_test.dart`), S-18809 (`test/muscle_display_test.dart`)
7. [ ] Write S-18804 in a new group of `test/muscle_filter_test.dart` (both harnesses)
8. [ ] Write S-18805, S-18806 and S-18807 in new `test/tibialis_muscle_refresh_test.dart` (both harnesses, plain `test()`, Hive staging in the test body, never `testWidgets`). Show every scenario marked "Red today" red with items 2–4 reverted, then green; record the red→green table in the evidence. Update Progress and the Assumption Log.

**Done Criteria** (run until green; Claude agents wrap in `bash .claude/scripts/macos/with-timeout.sh`, Copilot agents run through the gateway):
- `flutter analyze`: issue count ≤ the item-1 baseline
- `flutter test test/muscle_taxonomy_test.dart test/muscle_display_test.dart test/muscle_filter_test.dart test/tibialis_muscle_refresh_test.dart test/catalog_referential_integrity_test.dart test/catalog_refresh_test.dart test/db_seed_test.dart test/muscle_links_storage_test.dart test/muscle_picker_test.dart test/seeded_demos_test.dart test/seeded_demos_state_test.dart`
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `flutter test` (full suite, 900 s): a shared registry changed, so any reader the greps missed fails here. Fix it in place and list it in the evidence as an unpredicted file.
- `grep -c "muscle-tibialis" lib/data/models/muscle_taxonomy.dart` → 1; `grep -n "'exercise-tibialis-raise': _muscles" lib/mock/seed_data.dart` shows `primary: ['muscle-tibialis']` and no `secondary`; `grep -c "'Shins'" scripts/sqlite_seed.sql` → 1; `grep -n "bundledCatalogVersion = 13" lib/core/constants/catalog_version.dart` → 1 line
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` prints nothing

**Predicted Files**: `lib/data/models/muscle_taxonomy.dart`, `lib/mock/seed_data.dart`, `lib/core/constants/catalog_version.dart`, `scripts/sqlite_seed.sql`, `test/muscle_taxonomy_test.dart`, `test/muscle_display_test.dart`, `test/muscle_filter_test.dart`, `test/tibialis_muscle_refresh_test.dart` (new), `test/catalog_referential_integrity_test.dart`, `test/catalog_refresh_test.dart`, `test/db_seed_test.dart`, plus the evidence file. Production diff is about 5 lines.

### Phase 2: Docs and residue sweep (@dba)
1. [ ] Legs row gains `Shins (\`muscle-tibialis\`)` after Calves; the cited test title becomes `24 entries: 5 regions, 17 muscles, 2 standalone`. The doc is 47,922 B: stay under the 52 KB band — `docs/data_models.md:202-209` · MuscleGroup section
2. [ ] Cite the renamed S-9 title (24 groups); add one sentence after the version-11 sentence: catalog version `13` delivers Shins and the Tibialis Raise re-tag, cited to S-18805 — `docs/db_integration.md:125,599-601`
3. [ ] `bundledCatalogVersion` `12` → `13` — `docs/constants_reference.md:575`
4. [ ] Residue sweep, pasted into the evidence: `grep -rn "23 groups\|23 entries\|16 muscles\|hasLength(23)" lib test docs | grep -v "docs/plans\|docs/history\|docs/releases"` prints nothing; `grep -rn "muscle-calves" lib/mock/seed_data.dart` prints exactly 10 lines, none for `exercise-tibialis-raise`

**Done Criteria**: `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` green; `wc -c docs/data_models.md docs/db_integration.md docs/constants_reference.md` each < 53,248; the item-4 greps as stated.
**Predicted Files**: `docs/data_models.md`, `docs/db_integration.md`, `docs/constants_reference.md`, evidence file.

### Phase 3: Review (@code-reviewer)
Diff vs both phases' Predicted Files. The Diff-boundary invariant must hold; check it with `git diff --stat -- lib/features lib/widgets lib/state lib/core/services lib/data/repositories lib/watch watch lib/core/constants/data_version.dart scripts/sqlite_schema.sql`, which prints nothing. Re-run every Impact-table grep. Re-run each red→green claim. Mutations, each of which must turn the named test red:
- M1: the seed row goes back to Calves → S-18803, S-18804, S-18805
- M2: the taxonomy entry moves after Adductors → S-18801, S-18809, S-18802(c)
- M3: the version stays at 12 → S-18805
- M4: the SQL insert is removed → S-18808
- M5: the touched-skip in `_refreshExerciseMuscleGroups` is removed → S-18806
Findings go in `2026-11-04-114-tibialis-muscle-plan.review.md`.

## Files Affected

Production files: `muscle_taxonomy.dart`, `seed_data.dart`, `catalog_version.dart`, `sqlite_seed.sql`.
Read-only dependents (no edit, guarded by tests): `muscle_display.dart`, `muscle_selection.dart`, `muscle_picker.dart`, `exercise_filter_row.dart`, `catalog_refresh_service.dart`, `bundled_catalog_source.dart`, both repositories, `demo_routines_seed.dart`.

## Notes

- **Dependency graph:** Phase 1 → Phase 2 → Phase 3, strictly serial. Phase 2 cites test titles that Phase 1 creates. Intermediate state: after Phase 1 item 2, the existing count tests (item 5) are red by design until item 5 lands.
- **No migration:** `normalize` already accepts unknown ids, and no stored row needs rewriting except through the refresh.
- **Optional extras (priced, NOT in this PR):**
  - *Equipment tags (dumbbell, band) on Tibialis Raise.* Changing the seed is 1 line, but **the catalog refresh never delivers equipment**: `CatalogSource` has no equipment field, `WorkoutRepository` has no equipment setter, and there is no refresh step. A change would reach new installs only, so users would disagree. Doing it properly is its own @dba PR: a setter in the interface and both repos, a `CatalogSource` field, a refresh step that honours the touched rule, and Mock+Hive tests. That is about 4 items, roughly 100–150 production lines. It is user-visible on the detail screen only; there is no equipment filter today.
  - *`movementPattern` on Tibialis Raise.* 1 line, and the refresh already delivers it (`_exerciseDiffers` compares it). Nothing on screen reads `movementPattern`, though (only the copy does), so it changes nothing a user sees. It also needs a vocabulary call: reuse `calves`, or add a new pattern. Leave it to the catalog-gaps follow-up.
  - *Search that also matches muscle names* (typing "shins" finds Tibialis Raise). Search matches names only (`lib/core/utils/fuzzy_search.dart`). This needs product calls: does "legs" return every leg exercise, and do muscle matches rank below name matches? It touches the picker and library search state. A separate @developer PR of about 2 phases.
- **Follow-up (not planned here):** catalog gaps: leg extension, leg curl, chest flies; thin coverage for biceps and obliques; missing muscles (hip abductors, rotator cuff, serratus, brachialis).

## Progress
- [x] P1.1 baselines (181 issues) · [x] P1.2 taxonomy · [x] P1.3 seed row · [x] P1.4 version 13 (lead) + SQL · [x] P1.5 enumerations 23→24, 16→17 · [x] P1.6 pure/seed/SQL/display tests · [x] P1.7 filter tests (Mock+Hive) · [x] P1.8 refresh tests; red→green by M1–M5 in the evidence file
- [x] P2.1 data_models · [x] P2.2 db_integration · [x] P2.3 constants_reference · [x] P2.4 residue sweep (docs edits made by the lead)
- [x] P3 review: APPROVE WITH FIXES, both findings fixed. Full suite `+6404 ~2`, 0 failed. Not committed.

## Assumption Log
- Mock cannot remove a muscle group, so the "device without Shins" step of S-18805 to S-18807 runs on Hive only; Mock asserts the rest (plan 33 precedent).
- `catalog_version.dart` is outside `crew-builder-data`'s write ceiling; the lead made the version bump and its history sentence.

## Feedback
Review findings and fixes: `2026-11-04-114-tibialis-muscle-plan.review.md` (both fixed: evidence file written, production `BundledCatalogSource` used in the refresh test).
