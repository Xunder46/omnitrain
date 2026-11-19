# Plan 137 — shipped food categories can never be deleted; one-time repair of archived ones

Slug `2026-11-09-137-shipped-food-categories-locked`. Branch `claude_develop` (the working branch; never switched).
Base commit `ff398e1a7ec18409d9fc8c890bf35d2fde656e69`. Series: **137a (this plan)** = lock + repair.
**137b (separate PR, not in this plan)** = Archived section with Restore / Delete forever and the
"restore the old one?" offer when a new category reuses an archived name (scope budget: two tracks of UI + data in one
plan would pass the soft limits; the owner approved all three pieces on 2026-11-09, 137b follows this plan).

## Goal and acceptance

Owner report (2026-11-09): the Dairy category was archived by accident; foods filed under it now show as
Uncategorized, and because editing a default food only makes a copy (plan 133) there is no way to put them back.

What the user sees after this plan:

1. The nine categories the app ships with (Proteins, Dairy, Grains & Starches, Fruits, Vegetables, Nuts, Seeds & Fats,
   Snacks & Prepared, Drinks, Condiments — ids in `SeedData.defaultFoodGroups`) have **no trash control** in the
   Categories tab. They can still be renamed. Custom categories keep the trash control and behave exactly as today.
2. On the first launch after the update, any shipped category that is archived comes back, and the user's Foods I Eat
   copies of default foods that sit under no category go back under their shipped category. Foods the user made
   themselves, and copies that already have a category, are not touched.
3. The state layer refuses to archive or delete a shipped category (typed error, nothing written), independent of the
   hard-coded `_bundledCatalogFoodIds` list.

Acceptance: S-13701..S-13709 pass under Mock and Hive where stored; `flutter analyze` count not above baseline;
invariant grep clean; `test/ui_standards_contract_test.dart` and `test/docs_indexing_contract_test.dart` pass; full
`flutter test` green; every guard proven by a mutation the lead observed.

Root cause (reported to the owner, honest status): **not reproduced.** In the current code `deleteFoodGroupReassigningFoods`
refuses to archive Dairy while any of the 17 bundled dairy foods still points at it (`test/food_library_state_delete_guard_test.dart`
passes; the 169 ids in `_bundledCatalogFoodIds` equal the 169 ids in `assets/data/food_catalog.json`). Gaps found by reading:
the guard looks only at bundled catalog rows, so a group holding only the user's own rows or copies is archived and those
rows are moved to no category with no way back; there is no un-archive anywhere in `lib/`. The lock in this plan keys on
the shipped category id, so it does not depend on the list or on what the catalog cache holds.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | A "shipped category" is an id in `SeedData.defaultFoodGroups`. A new const `shippedFoodGroupIds` in `lib/core/constants/shipped_food_groups.dart` mirrors the nine ids (state may not import `lib/mock`); a test asserts it equals the seed list so a tenth category cannot be forgotten. | `lib/mock/seed_data.dart:5578`, S-13701 |
| D-2 | `FoodLibraryState.deleteFoodGroupReassigningFoods` and `FoodLibraryState.archiveFoodGroup` throw a new typed `ShippedFoodGroupError` (extends `StateError`) for a shipped id, as the FIRST check after the group lookup, before any read of the catalog cache or any write. | S-13702, S-13703 |
| D-3 | The old bundled-food guard is replaced, not kept: `FoodGroupHasBundledFoodsError`, the `strandedBundled` block in `deleteFoodGroupReassigningFoods`, and the Categories tab's `_bundledMessage` catch are deleted. A custom category cannot hold a bundled food, so the guard was reachable only through shipped categories. `_bundledCatalogFoodIds`, `isBundledCatalogFood` and `isDefaultFood` stay (other callers). | `lib/state/food_library_state.dart:343-376`, `add_food_screen.dart:1614-1700` |
| D-4 | Categories tab: a shipped row keeps its name field and food count but renders no `group_delete_<id>` control; a same-size empty box keeps the name fields aligned. Custom rows unchanged. No new copy, no tooltip, no message. | `add_food_screen.dart:1733-1792`, S-13705 |
| D-5 | Repair = data-migration step 19 `restoreShippedFoodGroups`, class `ShippedFoodGroupsRepair(repository).run()` in `lib/core/services/shipped_food_groups_repair.dart`, registered in `HiveWorkoutRepository._dataMigrationSteps` and the Mock mirror, `currentDataVersion` 18 → 19. Not the catalog refresh: that service promises never to modify user rows, and the repair edits the user's library copies. Same pattern as step 18. | `lib/data/repositories/hive_workout_repository.dart:405-412`, `mock_workout_repository.dart:297-304`, `lib/core/constants/data_version.dart:36` |
| D-6 | Repair rule 1: every food group with `isArchived == true` and an id in `shippedFoodGroupIds` is rewritten un-archived (name, color, createdAtMs unchanged, `updatedAtMs` = now). Archived custom groups stay archived. | S-13706 |
| D-7 | Repair rule 2: for every active library food (`getFoods()`; `isCatalog == false`) with `groupId == null` and a non-null `catalogId`, read the catalog row `getCatalogFoodById(catalogId)`; when that row's `groupId` is in `shippedFoodGroupIds`, the copy's `groupId` becomes that value (one `reassignFoodsToGroup` call per target group). Everything else is untouched: copies with any category, library foods with no `catalogId`, copies whose catalog row is a user-created food (its own category was cleared by the archive and cannot be known). | S-13707 |
| D-8 | Idempotent: after one run no copy matches rule 2 and no group matches rule 1, so a second run writes nothing. A failure propagates (no try/catch) so `data_version` stays 18 and the next launch retries. Fresh installs: no-op. | S-13708 |
| D-9 | No change to the repository interface, to `archiveFoodGroup` in the repositories (tests use it to simulate the damage), to the watch protocol, or to the catalog refresh. The wrist's Foods I Eat sections follow the phone's groups on the next normal sync. | `lib/core/utils/foods_i_eat_order.dart:25-60` |

## Scenarios

Fixtures are exact. "Shipped" ids: `food-group-proteins`, `food-group-dairy`, `food-group-grains-starches`,
`food-group-fruits`, `food-group-vegetables`, `food-group-nuts-seeds-fats`, `food-group-snacks-prepared`,
`food-group-drinks`, `food-group-condiments`.

| ID | Fixture | Expectation | Fails without the change because |
|---|---|---|---|
|  S-13701 | `shippedFoodGroupIds` has 9 entries and equals the set of `SeedData.defaultFoodGroups` ids. | `isShippedFoodGroupId('food-group-dairy')` true, a `createFoodGroup('Dairy')` generated id false. | the constant and helper do not exist, the file does not compile  |
|  S-13702 | Mock and Hive repo, initialized. Remove every bundled dairy row from the catalog (`deleteCatalogFood` for the 17 ids) so no bundled row points at Dairy; add a library copy `copy-milk` (`isCatalog:false`, `catalogId:'whole_milk'`, `groupId:'food-group-dairy'`). | `state.loadFoodGroups(); state.loadFoods();` then `deleteFoodGroupReassigningFoods('food-group-dairy', null)` throws `ShippedFoodGroupError`; afterwards `food-group-dairy` is not archived and `copy-milk.groupId == 'food-group-dairy'`. | the old guard only looks at bundled rows: with none left it archives Dairy and moves `copy-milk` to no category (the owner's loss)  |
|  S-13703 | Same repo, `state.archiveFoodGroup('food-group-dairy')` throws `ShippedFoodGroupError`. | `getFoodGroups(includeArchived:true)` shows Dairy `isArchived == false`. A custom group (`createFoodGroup('My Proteins')`) still archives. | `archiveFoodGroup` has no lock and archives any group  |
|  S-13704 | `deleteFoodGroupReassigningFoods(customId, destId)` still moves library and user-created catalog foods and archives the custom group. | (the existing S-007 case rewritten on a custom group; a custom group with a library food and a user catalog food). | Same: guards against over-reach, passes before and after.  |
|  S-13710 | Mock and Hive. Custom group `Temp` with one user-created catalog food (`isCatalog:true`, generated id) and a second group `Dest`; the state loads groups and foods but NOT the catalog. | `deleteFoodGroupReassigningFoods(tempId, destId)` moves the catalog food to `destId` (read back from the repo) and archives `Temp`. | the cold-cache `loadCatalogFoods()` step is gone, so the cache is empty and the catalog food is left pointing at the archived group (caught in P1a: the first build removed that step because the brief said to)  |
|  S-13711 | Mock and Hive. `state.updateFoodGroup` with the Dairy group copied with `isArchived: true`. | throws `ShippedFoodGroupError`; the repo still shows Dairy not archived. A rename through `renameFoodGroup('food-group-dairy', 'Milk')` still works. | `updateFoodGroup` stores `isArchived` verbatim, so the lock can be bypassed through it (review minor 1)  |
|  S-13705 | Widget (Mock): Categories tab with the 9 shipped groups plus one custom group `Snacks 2`:. | `find.byKey(Key('group_delete_food-group-dairy'))` and the other eight `findsNothing`; `group_delete_<customId>` `findsOneWidget`; typing a new name into `group_name_food-group-dairy` and submitting renames it (state name changes). | every row has a `group_delete_<id>` control today  |
|  S-13706 | Mock and Hive, data version 17 → run steps ≥ 18 via `runDataMigrationStepForTest`-style helper used by `test/routine_session_modality_backfill_test.dart`: Dairy archived through `repo.archiveFoodGroup('food-group-dairy')`, custom group `Old` archived. | After `ShippedFoodGroupsRepair(repo).run()` Dairy `isArchived == false` with name `Dairy`, same color and `createdAtMs`; `Old` still archived; `state.loadFoodGroups()` lists Dairy in `activeFoodGroups`. | the repair class does not exist  |
|  S-13707 | Mock and Hive. Library foods: A `catalogId:'whole_milk'`, `groupId:null`; B `catalogId:'whole_milk'`, `groupId:'food-group-snacks-prepared'`; C no `catalogId`, `groupId:null`; D `catalogId` = a user-created catalog food with `groupId:null`; E `catalogId:'apple'`, `groupId:null`. | After the repair: A `food-group-dairy`, E `food-group-fruits`, B/C/D unchanged. | there is no repair; A and E stay uncategorized  |
|  S-13708 | After one run, record every food's and group's `updatedAtMs`; a second `run()` leaves all of them equal. | `currentDataVersion == 19`; both repositories' last step is `19:restoreShippedFoodGroups`; a fresh Mock install reaches version 19 with no group change. | the step and the version bump do not exist  |
|  S-13709 | The failing-write case: a repository wrapper whose `updateFoodGroup` throws. | makes `run()` throw and leaves `data_version` 18 (reuse the failure-injection pattern of `routine_session_modality_backfill_test.dart`). | there is no step to fail  |

## Phases

| Phase | Agent | Items (max 8) | Write scope | Parallel |
|---|---|---|---|---|
| P1a | crew-builder-app | 1 new `shipped_food_groups.dart` (D-1); 2 `ShippedFoodGroupError`, lock in two state methods, delete old guard + `FoodGroupHasBundledFoodsError` (D-2, D-3); 3 Categories row: no trash for shipped, `_bundledMessage` and its catch removed (D-4); 4 rewrite the three old tests that expect `FoodGroupHasBundledFoodsError`; 5 new `test/shipped_food_groups_lock_test.dart` S-13701..S-13704 under Mock AND Hive | `lib/core/constants/shipped_food_groups.dart`, `lib/state/food_library_state.dart`, `lib/features/nutrition/add_food_screen.dart`, `test/shipped_food_groups_lock_test.dart`, `test/food_library_state_delete_guard_test.dart`, `test/food_group_membership_test.dart`, `test/food_orphan_category_integration_test.dart` | serial, first |
| P1b | crew-builder-app | 1 new `test/shipped_food_groups_ui_test.dart` S-13705, exact helper block given in the brief (Mock only) | `test/shipped_food_groups_ui_test.dart` | after P1a |
| P2 | crew-builder-data | 1 `ShippedFoodGroupsRepair` (D-6, D-7, D-8); 2 step 19 in both repositories; 3 `currentDataVersion = 19`; 4 update the pinned tests (`data_migration_test.dart` S-156 and its `.last`/index checks, `routine_session_modality_backfill_test.dart` lines pinning `18`); 5 new `test/shipped_food_groups_repair_test.dart` S-13706..S-13709 under Mock AND Hive | `lib/core/services/shipped_food_groups_repair.dart`, `lib/core/constants/data_version.dart`, `lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`, `test/shipped_food_groups_repair_test.dart`, `test/data_migration_test.dart`, `test/routine_session_modality_backfill_test.dart` | serial, after P1a (needs the constant) |
| P3 | crew-docs-keeper | the Docs delta table below | `docs/**` named in the table, this plan's evidence file | after P2 |

Predicted production code: about 120 lines (constant 20, state 25 net after deletions, UI 15, repair 60). Plan budget respected.
Shared-tree note: `hive_workout_repository.dart` and `mock_workout_repository.dart` also carry plan 134's staged changes;
this plan adds one step each. Hunks mix at commit time and need `git add -p`.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/nutrition.md` | MODIFIED | Group deletion refuses to strand a shipped food | The categories the app ships with can never be deleted | S-13702 |
| `docs/nutrition.md` | REMOVED | ungrouped bucket would silently orphan a bundled catalog food, so that case raises | - | D-3 |
| `docs/nutrition.md` | REMOVED | FoodGroupHasBundledFoodsError` instead | - | D-3 |
| `docs/nutrition.md` | MODIFIED | and it refuses the bundled-food case described above rather | and it refuses a shipped category rather | S-13703 |
| `docs/nutrition.md` | ADDED | - | has no trash control in the Categories tab | S-13705 |
| `docs/state_management/nutrition_state.md` | MODIFIED | **Refuses the deletion** by throwing `FoodGroupHasBundledFoodsError | **Refuses the deletion** by throwing `ShippedFoodGroupError | S-13702 |
| `docs/db_integration.md` | ADDED | - | **Step 19 `restoreShippedFoodGroups` | S-13706 |
| `docs/db_integration.md` | MODIFIED | Their latest step is `backfillRoutineSessionModality` (version 18) | Their latest step is `restoreShippedFoodGroups` (version 19) | S-13708 |
| `docs/constants_reference.md` | MODIFIED | the last step is a one-off back-fill of past routine sessions' modality | the last step is a one-off restore of the shipped food categories | S-13708 |

The same constants_reference line's value cell changes from `18` to `19` (the keeper edits the whole line).

Stale-term sweep run 2026-11-09: `grep -rIn "Cannot delete\|FoodGroupHasBundledFoodsError\|trash icon\|group_delete\|Delete category\|bundled-food guard\|deleteFoodGroupReassigningFoods\|version 18\|currentDataVersion" docs` (excluding plans/history/releases). Hits covered above; `docs/widget_catalog/nutrition_widgets.md:462` and `docs/db_integration.md:503` stay true (custom-group tests; `reassignCatalogFoodsToGroup` still used for user-created foods).

## Input-reality checklist

- Writers and units: groups and foods are rows, no units. The repair is the only new writer, once per device, before any screen.
- Lifecycle: runs at repository initialize (step 19) before the UI reads groups; the in-memory `FoodLibraryState` caches load afterwards. A device that already ran the app on 18 gets it on next launch.
- Settings changing while open: none.
- Time edges: `updatedAtMs` = now on rewritten rows only; unchanged rows keep their stamp (S-13708).
- Load cost: one `getFoodGroups`, one `getFoods`, one catalog read per uncategorized copy (copies only, tens at most).
- Wording: no new user text. The trash control disappears silently.
- Slot competition: none. Watch: groups sync with the normal reference sync; no protocol field changes.

## Progress

- [x] P1a lock (state + Categories row + tests)
- [x] P1b UI test
- [x] P2 repair step 19
- [x] P3 docs
- [x] Verify: analyze 181 = baseline, touched tests, invariant grep, ui standards + docs contract green; full suite only red in load-sensitive files that pass alone (see evidence)
- [x] Prove: lead mutations
- [x] Review

## Assumption Log

- Plan written by the lead without an architect run: the seed already carries exact fixtures, code pointers and the Docs delta (saves one run). Recorded in the unit summary.
- P1a regression found by the lead's diff read: the brief told the builder to delete the cold-cache `loadCatalogFoods()` step together with the old guard, but that step also feeds the user-created catalog foods' reassignment. The lead restored the step in `deleteFoodGroupReassigningFoods` (6 lines) and S-13710 guards it.
- Root cause of the original archive is unproven (see Goal). The lock is closed by id, so the plan does not need it.
- (owner) Device checks: after updating, Dairy and its foods are back in the Library and Foods I Eat; no trash control on the nine built-in categories; a category you made still deletes. 137b (Archived section) is next.
