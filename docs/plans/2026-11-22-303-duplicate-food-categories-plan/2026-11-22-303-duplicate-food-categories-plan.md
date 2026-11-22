# Feature: 303 — food categories never share a name; devices with two "Dairy" are repaired

> Status: built 2026-11-22 by the lead directly (the crew's OpenCode runner is not installed on this Windows machine); uncommitted on `claude_develop`. One track: phone app. Investigation: `.work/investigations/duplicate-food-categories.md` (gitignored).
> Base: `af1c676f`. Baseline: `flutter analyze` on the touched folders 3 infos, all pre-existing, 0 errors.

## Overview

| What you do | Now | After 303 |
|---|---|---|
| Open the food library on a device that has two "Dairy" categories | Two "Dairy" headings; a default food (Cottage cheese) cannot be moved between them | One "Dairy" with all its foods; the extra category is archived, no food or logged entry is lost |
| Rename a category to a name another category has | Allowed | Refused with "A category called "X" already exists"; the old name returns to the field |
| Press the header "+" on Categories twice | Two categories named "New Category" | "New Category", then "New Category 2" |

## Decision Ledger
- **D-1** (owner, 2026-11-22) A user's category that collides with a shipped name is merged INTO the shipped one.
- **D-2** Same name = trimmed, case-insensitive, active categories only (an archived name is free).
- **D-3** Keeper = shipped id in the set (oldest shipped if several), else the oldest by `createdAtMs`, then id. A shipped category is never archived; two shipped categories sharing a name are left alone.
- **D-4** Repair is data-migration step 21 `mergeDuplicateFoodGroups` (`lib/core/services/duplicate_food_groups_merge.dart`), both stores; `currentDataVersion` 20 -> 21. Foods are re-filed (library AND catalog rows, bundled ones included, via `reassignCatalogFoodsToGroup`) before the duplicate is archived, so a partial run is finished by the next one. Nothing is deleted.
- **D-5** A shipped category missing from storage while a same-name active category exists is re-created from `SeedData.defaultFoodGroups`; one found archived beside such a category is un-archived (both before the merge).
- **D-6** Prevention in the state layer: `createFoodGroup`/`renameFoodGroup` throw `DuplicateFoodGroupNameError`, reading the repository (a cold cache cannot let one through). `freeGroupName` numbers the header "+" default. The Categories tab catches the rename error and restores the field.
- **D-7** `_seedDefaultFoodGroups` (step 13) no longer skips a shipped category whose name is taken (it left bundled foods pointing at a missing row). A pre-existing same-name category is folded in by step 21 in the same launch.

## Scenarios (ids S-30301..S-30316, all in `test/duplicate_food_groups_merge_test.dart`)
Each fails without the change (mutation-checked, see evidence): S-30301 custom Dairy folded into shipped, Cottage cheese catalog row + copies re-filed, counts unchanged, second run writes nothing; S-30302 plan 137 path (step 19 then 21); S-30303 case/space duplicates of a custom name merge into the oldest, different names stay apart; S-30304 archived shipped beside active Dairy comes back; S-30305 two shipped sharing a name kept; S-30306 fresh install untouched; S-30307 missing shipped row re-created (Mock, hidden-row repo); S-30308 not invented without a stand-in; S-30309 failure after re-filing is finished by the next run; S-30310 step 21 in both lists; S-30311 create refuses; S-30312 rename refuses / own-name case change allowed / archived name free; S-30313 `freeGroupName`; S-30314 Hive box pre-populated with a custom Dairy ends with one Dairy; S-30315 rename refused in the UI; S-30316 "+" twice.

## Docs delta
- `docs/constants_reference.md` `currentDataVersion` row 20 -> 21 + step 21 text.
- `docs/db_integration.md` new Step 21 paragraph; "latest step" sentence.
- `docs/state_management/nutrition_state.md` `createFoodGroup`, `renameFoodGroup`, new `freeGroupName`.
- `docs/widget_catalog/nutrition_widgets.md` Categories tab "+" and rename message.

## Assumption Log
- **A-1** (lead) Existing tests that made a second "Proteins"/"Dairy" through the state now use "My Proteins"/"My Dairy" (they exercised the bug); `nutrition_test` S-9163 now expects "New Category" + "New Category 2".
- **A-2** (lead) The seed-skip removal (D-7) cannot be proven alone: step 21 recreates a skipped shipped row, so S-30314 guards the end state, not the step-13 line.

## Owner device checks
- **(owner)** ODC-1 On the phone with the doubled Dairy: after updating, open Manage Food Library -> Categories: one Dairy, extra row gone, Cottage cheese under Dairy; Foods I Eat shows one Dairy heading.
- **(owner)** ODC-2 Rename a category to "Fruits": the message shows and the name snaps back.
- **(owner)** ODC-3 The watch food list shows each category once after the next sync (not exercised here).

## Goal and acceptance
One category per name; a device that already has two is repaired on the next launch without losing a food or a logged entry; the two cannot be recreated. Accepted when `test/duplicate_food_groups_merge_test.dart` and `test/data_migration_test.dart` pass and the affected-set comparison shows no new failure against the base.

## Phases
- **P1** (lead, one pass) service + step 21 in both stores + version bump; state refusal + `freeGroupName` + Categories-tab handling; seed-skip removal.
- **P2** (lead) tests, fixture fixes in four existing files, docs.

## Progress
- P1 done, P2 done 2026-11-22. Uncommitted. Plan-lint's table format (scenario rows, Docs delta rows) was not applied: the plan is prose.
