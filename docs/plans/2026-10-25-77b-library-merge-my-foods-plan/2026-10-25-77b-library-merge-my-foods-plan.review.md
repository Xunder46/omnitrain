# Review: 77b library-merge-my-foods · code/tests/docs final · c395f572..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 4 · tests: 5601 passed / 2 skipped / 8 failed (all 8 in `test/mix_layer_screen_test.dart`, untouched by this diff — pre-existing, unrelated to nutrition)
Diff vs Predicted Files: conforms — all 11 changed files are the plan's P1/P2 lib files, P3a/P3b test files and P4 docs; `food_library_test.dart`, `food_group_membership_test.dart`, `header_standardization_test.dart` unchanged (they do not tap the tab, as the plan anticipated). No allowlist entry added, no ratchet raised.

## Findings
1. [Minor] `lib/features/nutrition/add_food_screen.dart:1471` — stale section banner `// ─── Tab 2: + New Item ───` above `_NewFoodFormScreen`: the form is not a tab and "+ New Item" no longer exists anywhere in the UI. Fix: retitle to `// ─── New Food form ───`. Guard: extend S-12818.
2. [Minor] `lib/features/nutrition/add_food_screen.dart:1478` — stale banner `// ─── Tab 3: Groups ───`: Categories is now tab index 1 (`_groupsTabIndex = 1`). Fix: `// ─── Tab 2: Categories ───`. Guard: extend S-12818.
3. [Minor] `lib/features/nutrition/add_food_screen.dart:610-613` and `:641-647` — the Library tab's two empty states (`No catalog foods available`, `No matches for "…"`) do not reserve `OmniTheme.formBottomCTAClearance`, while the list does (D-4). The new bottom CTA now overlays that region; impact is low because both empty states center their content, but the clearance rule is applied inconsistently within one tab. Fix: wrap both `OmniEmptyState`s with the same bottom clearance the list uses. Guard: a widget test asserting the empty state's bottom padding on the Library tab.
4. [Minor] `docs/navigation_and_screens.md:183` — the `EditFoodScreen` row still describes only the edit/Reset behaviour; the new **Delete food** footer button (D-5) is documented in `docs/nutrition.md` but not in the screen table row a reader checks first. Fix: one clause in that row naming `food_delete_created` and `test/library_merge_test.dart` (`S-12815`).

## Brief questions (1–5), answered
1. **Legacy filter loses nothing, shows nothing twice.** Old My Foods surfaced `userCreatedCatalogFoods` (non-archived) + legacy library customs; user-created catalog rows are a subset of `catalogFoods`, so the new list is a superset. Dedup: `seen` is seeded with every catalog row's `_FoodIdentity` and legacy rows are added only on a fresh identity, so the catalog row wins — same priority as the old tab. Two legacy rows with the same identity collapse to the first, as before. Archived catalog rows appear in the list unfiltered, but that is pre-existing Library-tab behaviour (`catalogFoods` was already used unfiltered before 77b). Cost: `catalogIdFor(f)` walks the catalog per library food per rebuild — the old My Foods tab did the identical work on every rebuild; it now runs on the default tab and per search keystroke. O(foods × catalog) with tens-to-hundreds rows is cheap; not a regression, no finding.
2. **Async safety is sound; partial-state on throw is pre-existing parity.** The helper captures `messenger`/`theme` before the dialog await and touches no `BuildContext` after any await; `_onDeleteCreated` guards `mounted` before `Navigator.pop`. If `deleteCatalogFood` throws after `removeFood` succeeded, the catalog row survives without its library copy — but that is the exact sequence and catch of `_UserFoodRowState._onDelete`'s catalog branch (`add_food_screen.dart:1103-1121`), which D-5 mandated verbatim, so it is accepted parity, not a new defect.
3. **Stale text:** only the two banners in findings 1–2 (`Tab 2: + New Item`, `Tab 3: Groups`). No `My Foods`, `+ New Food`, "third tab" or `Tab 2: + New Item` in strings or doc comments otherwise. `_deleteTrailingSize` is still used (`:923`, `:989-990`) — not a leftover; `_FoodIdentity` is used by the new filter; no unused import (analyze stays at the 180 baseline, 0 errors).
4. **Yours tag is consistent with D-3 as written.** `_CatalogRow` shows the copy's name (`shown = copy ?? widget.food`) and tags on `!isBundledCatalogFood(widget.food.id)` of the catalog row, so a renamed library copy of a created food keeps its tag (correct — the user created it) and a renamed copy of a bundled food never gets one. This is exactly D-3(a); no finding.
5. **No assertion found that would pass with its behaviour broken.** The strongest are S-12812b (a mutant listing an edited bundled copy as a legacy row is caught by the empty no-match list) and S-12816b (a precondition asserts the created row's editor DOES show the button, so the bundled-absence assertions cannot pass vacuously). One self-referential pattern, noted not flagged: S-12812's macro-line expectation is recomputed with the same `calculateCalories`/`formatGrams` helpers the row uses, so a shared-helper break would pass — pre-existing test style, helpers out of this diff's scope.

## Assumption Log rulings
The plan carries no Assumption Log entries; nothing to ratify. (No builder/prover report was attached to this brief, so no unlogged-choice sweep was possible — not counted as a finding.)

## Scenario coverage
S-12810 → `test/library_merge_test.dart` · `S-12810: tabs are Library and Categories, no My Foods`
S-12811 → `test/library_merge_test.dart` · `S-12811: a created food carries the Yours tag; a bundled food does not`
S-12812 → `test/library_merge_test.dart` · `S-12812: a legacy custom renders as a row with delete and Yours tag; …` (plus extra S-12812b)
S-12813 → `test/library_merge_test.dart` · `S-12813: search is case-insensitive and filters; …`
S-12814 → `test/library_merge_test.dart` · `S-12814: the Library CTA opens the New Food form; …`
S-12815 → `test/library_merge_test.dart` · `S-12815: deleting a created food from its editor removes …`
S-12816 → `test/library_merge_test.dart` · `S-12816: Delete food is absent for a bundled food; …` (plus extra S-12816b)
S-12817 → `test/library_merge_test.dart` · `S-12817: confirmAndDeleteCreatedFood returns false on Cancel …`
S-12818 → `test/library_merge_test.dart` · `S-12818: source guard on add_food_screen.dart`
All present; none MISSING.
