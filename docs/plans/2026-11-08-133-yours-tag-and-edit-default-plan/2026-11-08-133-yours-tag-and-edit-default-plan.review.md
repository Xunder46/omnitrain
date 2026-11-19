# Review: 133 (yours tag + edit default) · 133a/b · fcd727b..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 2 · minor 4 · tests: not run (brief forbids the reviewer from running `gateway.sh test`; the lead's runs reported 20/20 for `food_form_serving_test.dart` and the mutation pass killed 9 mutants)
Diff vs Predicted Files: conforms. Scope `git-diff --stat fcd727b3afc81a5deb3d1c75712c298809256f61` → 22 files, 1965 insertions, 1204 deletions; every file is on the brief's predicted list. `test/food_form_serving_test.dart` (seed ids `egg`/`rice` → `egg_of_mine`/`rice_of_mine`, S-92b.6 fix) is named by the brief as allowed. Deleted `test/food_library_copy_edit_test.dart` is a Governor action (deletion), not a finding.
## Findings

1. **[Blocker]** `lib/features/nutrition/widgets/save_default_as_own_food.dart:69-84` with `lib/state/food_library_state.dart:1202-1212` — D-13321's restore guarantee does not hold for failures after `removeFood`. Sequence (in-list default, logged today 150 g): `createCatalogFood` succeeds → `removeFood(oldLibraryId)` succeeds → `_imageStorage?.deleteIfManaged(replacedPath)` raises (disk error) or `addCatalogFoodToLibrary(newId)` raises (storage error, the failure class S-13327 already models for `createCatalogFood`). The row is gone from `_foods` and `newId` is still null (the state method never returned), so the catch's `foods.where((f) => f.id == oldLibraryId || f.id == newId)` finds nothing: no re-log, "Could not save food", and **today's 150 g log is lost** while the library holds neither the old copy nor the new row and a new catalog row exists — the half-swap INV-133-E ("a state-layer failure never leaves a half-swapped library") and D-13321 ("a storage error cannot lose today's log") both forbid. S-13327 only covers the `createCatalogFood` window. Fix (two parts): (a) wrap the `deleteIfManaged` call in its own try/catch — a file-cleanup failure is cosmetic and must not abort the swap; (b) in `createOwnCopyOfDefault`, on failure after `removeFood`, restore the in-list row via `addCatalogFoodToLibrary(source.catalogId ?? source.id)` before rethrowing (resurrects the copy at shipped values — acceptable; the alternative is a lost log). Guard: a Mock repository failing `addCatalogFoodToLibrary`, asserting `nutritionState.isFoodLoggedToday(oldCopyId)` after `saveDefaultAsOwnFood`.
2. **[Major]** `lib/state/food_library_state.dart:1637-1643` (`isDefaultFood` requires `catalogId`) + `lib/features/nutrition/add_food_screen.dart:1311-1320` (`_openEdit`) — a **legacy value-matched copy** (library row with `catalogId == null` value-matching a bundled catalog row) bypasses the "Save as your own food?" dialog and is edited **in place**. Trace: `libraryIdFor` (`food_library_state.dart:642-665`) falls back to identity-matching rows without `catalogId`, so the bundled row's pencil opens `EditFoodScreen` on that legacy row; there `_onSavePressed` sees `isDefaultFood == false` → no dialog; the shim's save (`add_food_screen.dart:749,892-915`) calls `updateCustomFood` and writes the user's copy of a bundled food in place — exactly what the owner decision removed ("editing a default food no longer edits a hidden personal copy"). By D-13310's letter the row is not "a default", but the copy-flow route reaches it through the bundled row's pencil — the same entry point S-13310 describes. Fix: extend `isDefaultFood` (or the screen check) to also return true for a non-catalog row whose `catalogIdFor` names a bundled row. Guard: a test seeding a catalogId-less value-matched copy and asserting the dialog appears before its Save.
3. **[Major]** Missing edge-scenario coverage — five plan Edge scenarios have no test: **S-13321** (in-list default *not* logged: `unlogFoodToday`/`logConsumedFoodAt` must not fire — the plan says a Mock spy is needed; none exists, this leg is unproven), **S-13322** (running the copy flow twice: second save finds no list row, amount null), **S-13323** (draft photo deleted before Save → copy leg swallows → photoless save succeeds), **S-13325** (remove-before-add ordering unpinned; nothing asserts the old copy's *removal* on the not-logged path), **S-13326** (archived copy left untouched, addToList false). Smallest fix: a Hive+Mock pair for S-13325/S-13326 and a Mock `unlogFoodToday` spy for S-13321 in `test/food_library_own_copy_test.dart`. S-13324 is covered via S-13314(c).
4. **[Minor]** `docs/nutrition.md:253-255` — "a default food's Save ... pops through that dialog on Cancel and on Confirm alike" reads as false: on **Cancel** the editor stays open (pinned by S-13328, `find.byType(EditFoodScreen), findsOneWidget`); only Confirm pops. Fix: "...asks `Save as your own food?` first — only when the form was edited; Confirm saves and pops, Cancel keeps the editor open — and the unsaved-changes guard is never raised."
5. **[Minor]** `docs/widget_catalog/nutrition_widgets.md:376` — "(body naming a new food of the user's own...)": the dialog body names the **default's** shipped name (pinned by S-13311's `_copyDialogBody(_shippedName)` assertion in `test/edit_default_food_test.dart`), not the new food's name. Fix: "body naming the default's own name".
6. **[Minor]** `lib/state/food_library_state.dart:1186-1229` (`_copyImagePathFor`) — the managed photo file is written **before** `createCatalogFood` (:1187). When `createCatalogFood` throws after a successful copy, the fresh managed file is orphaned: nothing references it and nothing deletes it (D-6's sweep does not exist by decision). Repeated failed saves accumulate unmanaged files. Smallest change is an owner decision: best-effort delete on `createOwnCopyOfDefault`'s failure path, or an accepted-orphan note in the plan.
7. **[Minor]** `lib/widgets/layout/omni_bottom_cta.dart:31` — doc comment still names `**Reset to original**` as a competing CTA; Reset no longer exists on any food editor (D-13317). File outside this unit's predicted scope → Governor/owner action, flagged so it is not lost.

Questions (brief's five), answers in short:
1. No bypass found. `_onSavePressed` is the only save trigger: `FoodFormController.attach(_onSave)` (`lib/features/nutrition/food_form.dart:259`) is wired only to the `food_form_save` button; no keyboard action submits; `_attemptExit` only offers Discard/Keep editing; Cancel returns before `submit()` (S-13311/S-13328 pin this). Residual quirk (D-13320 owns it, no test): a Save whose validation then fails leaves the screen open with edits, so the next Save press asks again — listed for the owner.
2. Log — safe in the tested window, lost in the post-remove window (Finding 1). Library row — hard-deleted via `removeFood`, resurrectable per Finding 1's fix. Photo file — copy result abandoned on `createCatalogFood` failure (Finding 6); the replaced copy's file is deleted only after a successful remove and the new copy always owns a fresh basename, so no referenced file is ever deleted.
3. No wrong row removed and no surviving old copy found: `libraryIdFor` skips catalog and archived rows; `addCatalogFoodToLibrary` early-returns on an existing id, so two live copies cannot exist (removed-then-readded — hence remove-before-add is load-bearing per S-13325, unpinned per Finding 3). Archived + legacy-copy coexistence is intentional but untested (Finding 3). The legacy gap is Finding 2.
4. `_openEdit` never opens the wrong food: bundled in-list → copy; bundled not-in-list → catalog row (a copy would be archived, hence absent); user-created → its catalog row; `_UserFoodRowState._openEdit` now passes `nutritionState` (missing pre-diff). Editor-opens-legacy-copy gap is Finding 2. NutritionState null is production-unreachable (`_openEdit` receives the state from `AddFoodScreen`); in tests a dirty default confirm-then-fails with "Could not save food", untested, no finding.
5. Doc sentences vs code/test names checked (Findings 4/5 are the only mismatches): `confirmSaveAsOwnFood`/`saveDefaultAsOwnFood`/`createOwnCopyOfDefault`/`isDefaultFood` exist; `S-12714: the pencil does not toggle the row` (`test/library_row_toggle_test.dart:330`), `S-12716: source guard on _CatalogRowState` (`:558`), `S-12815` (`test/library_merge_test.dart:351`), `S-12816b` (`:457`) all exist verbatim; nutrition.md's recap-table citations name real files/groups.
## Assumption Log rulings
- "Unchanged form + Save pops with no dialog" — ratified (S-13311 pins it).
- "A default edited before keeps its edits ordinary" — ratified (S-13316 pins the semantics).
- "Midnight crossing during carry not handled" — ratified (accepted edge, logged in plan).
- "(architect) unlog-before-swap; a throw between unlog and re-log loses today's entry" — **escalate**: superseded by D-13321, which promises the opposite; Finding 1 shows the promise does not hold for every window. Owner must re-ratify under D-13321's wording.
- "(architect) `(source.catalogId ?? source.id)` must name a bundled row; not found" — ratified (`createOwnCopyOfDefault` throws `StateError` first, `food_library_state.dart:1180-1184`).
- "(architect) Mock pick/clear test independence" — ratified (outside unit scope).
- "On web the photo is not copied (stub throws → caught → photoless save)" — ratified (catch at `food_library_state.dart:1226-1230`).
- Prover/guard verdicts: the brief carries the lead's mutation summary (9 mutants killed) but no per-guard `prove-red` verdicts; the S-12716/S-13318 source guards and the S-13315 "passes before and after" guard are therefore **unproven** by the rule, though each is red at base by construction (`editLibraryFood`/`if (inList || isYours`/`food_reset_original` do not occur in the guarded sources — checked by reading them).
## Scenario coverage
S-13301 → `test/library_merge_test.dart` `S-13301 the Yours tag sits at the end of the macros line` | OK
S-13310 → `test/edit_default_food_test.dart` both legs | OK
S-13311 → `... Save on an edited default asks first; Cancel writes nothing; an untouched form pops with no dialog` | OK
S-13312 → `Confirm makes a food of your own, not added to the list` | OK
S-13313 → `Confirm on an in-list logged default replaces it and carries today's amount` | OK
S-13314 a/b/c → `test/food_library_own_copy_test.dart` (Mock) photo cases | OK
S-13315 → `a normal custom-food save still saves directly, no dialog` | OK
S-13316 → `the shipped name is stored; Yours tag elsewhere renders the stored name` | OK
S-13317 → own-copy Mock AND Hive groups (`not in list adds nothing` / `in list swaps the row`) | OK
S-13318 → top-level source guard `source guards pin the copy flow` | OK (unproven-red note above)
S-13319 → `Cancel on the dialog leaves the log alone` | OK
S-13320 → `deleting the new own food leaves the bundled row intact` | OK
S-13321 → MISSING (needs Mock `unlogFoodToday` spy; plan expected one — Finding 3)
S-13322 → MISSING (Finding 3)
S-13323 → MISSING (Finding 3)
S-13324 → covered via S-13314(c) (stale-draft leg) | OK
S-13325 → MISSING (remove-before-add ordering unpinned — Finding 3)
S-13326 → MISSING (archived-copy branch — Finding 3)
S-13327 → `a failed swap keeps today's log` | OK
S-13328 → `Cancel shows no error snackbar` | OK
S-12713 → `test/library_row_toggle_test.dart` `the pencil on an in-list bundled food opens its copy; Save asks and makes a food of your own` | OK
S-12716 → `:558` guard (extended) | OK
S-12719 → rewritten copy-flow route | OK
S-92a.7 / S-92a.9 → `test/edit_food_save_test.dart` rewritten (copy flow / no Reset) | OK
S-92a.15 → deleted with the Reset flow | OK
S-12812b → `test/library_merge_test.dart` via `seedEditedCopy` | OK
S-12816b → `:457` `no Delete food on a bundled catalog row` | OK
S-92b.6 → `test/food_form_serving_test.dart` unblocked by seed ids (brief's stated fix) | OK
## Docs delta
All rows applied (sentence truth-judged per the brief; the governor ran the marker check):
`nutrition.md` rows 1-9 → applied
`state_management/nutrition_state.md` rows 1-5 → applied
`data_models.md` rows 1-2 → applied
`design_system.md` row 1 → applied
`widget_catalog/layout_and_inputs.md` row 1 → applied
`widget_catalog/nutrition_widgets.md` rows 1-4 → applied
`navigation_and_screens.md` row 1 → applied

Doc edits the table does not name (informational, sentences true, citations verified):
- `docs/nutrition.md` ~:142 — Yours-tag position sentence in the tag paragraph.
- `docs/nutrition.md` ~:147-150 — Created-foods paragraph's expanded S-12815/S-12816b citations.
- `docs/widget_catalog/nutrition_widgets.md` ~:159 — S-92b.10 citations moved from deleted `test/food_library_copy_edit_test.dart` to `test/food_library_edit_test.dart`.
- `docs/widget_catalog/nutrition_widgets.md` :362-380 — new `### save_default_as_own_food.dart (screen-level helper)` section.

Doc edit NOT applied (outside the table, Finding 7): `lib/widgets/layout/omni_bottom_cta.dart:31` still names "Reset to original". `docs/global_conventions.md` unchanged — no rule there required a change (checked).
## Confidence checks
- State/features depend on `WorkoutRepository` only: no `hive_workout_repository` import found in `lib/state`, `lib/features`, `lib/widgets`, `lib/core` (grep).
- No hex colour literals or raw allowlisted pieces introduced by this diff; no allowlist entry added, no ratchet raised (`test/helpers/ui_standards_allowlist.dart` untouched).
- Analyzer baseline 181 issues not re-run (test/analyzer forbidden by the brief); the lead's runs reported baseline parity.

