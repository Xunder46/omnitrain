# Feature: 92a — Edit Food gets a Save button; nothing saves until Save

> Status: SEEDED by the governor (decisions, scenarios, phase outline); the planner expands it. Series: `docs/plans/2026-10-29-92-food-form-rework-plan/` (92a of 92a/92b/92c). Base: `1b9bfb40` on `claude_develop` (plan 91 committed).
> Binding conventions: `docs/global_conventions.md`, `docs/design_system.md`, `.github/copilot/pr-scope-budget.md`. Never create or switch branches; git belongs to the governor.
> Hands off (another unit's uncommitted work): `docs/session_summary.md`, `docs/state_management/workout_state.md`, `lib/features/session/session_summary_screen.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/state/workout/session_core_entry.dart`, `lib/state/workout/workout_state.dart`, `test/watch_live_refresh_screen_test.dart`, `test/watch_routine_adoption_test.dart`, `test/watch_session_merge_test.dart`.

## Goal

Edit Food (`EditFoodScreen`) and the legacy edit shim (`_LegacyLibraryEditScreen`) get a bottom **Save**. Nothing is written until Save is tapped, **a picked or cleared photo included**. Leaving with changes asks "Discard?", exactly as New Food does. The New Food bottom button reads **Save** instead of Create. Serving fields, field order, calories and duplicate notes are NOT in this unit (92b, 92c).

## What the user sees

| | Now | After |
|---|---|---|
| Edit Food, text fields | saved when focus leaves the form; back arrow keeps whatever was saved | a bottom Save; focus leaving saves nothing; Save writes and closes |
| Edit Food, photo | written the moment it is picked or cleared | written on Save; Discard drops it |
| Edit Food, back arrow | closes silently | closes silently if nothing changed; otherwise asks "Unsaved changes" with Keep editing / Discard |
| Legacy edit shim, photo | written at once | written on Save (it already has Save and the guard) |
| New Food button | "Create" | "Save" |

## Acceptance criteria

- AC-1 Edit Food shows a bottom button `Save` (key `food_form_save`); tapping it with valid fields writes through the same path as today (`updateCatalogFood` for a user-created catalog food, `editLibraryFood` for a library copy) and closes the screen.
- AC-2 Focus leaving the Edit form writes nothing.
- AC-3 Photo pick and photo clear in Edit and in the legacy shim write nothing until Save; Save writes the new `imagePath` and the state layer deletes the previous managed file; Discard leaves the stored `imagePath` and its file untouched.
- AC-4 Back (header arrow and system back) on Edit: untouched form closes with no dialog; a changed form (any text field, category, photo) shows the `Unsaved changes` dialog; Discard closes without writing; Keep editing stays.
- AC-5 Reset to original and Delete food still show above Save for the same foods as before and work as before.
- AC-6 The New Food bottom button label is `Save`; its key, validation, create flow and unsaved guard are unchanged.
- AC-7 No test keeps asserting save-on-pick or save-on-blur; the tests that did are rewritten to the new rule (not deleted).

## Decision Ledger

- **D-92a.1** Edit Food's Save is `OmniBottomCTA(label: 'Save', buttonKey: const Key('food_form_save'), onPressed: _formController.submit)` as `Scaffold.bottomNavigationBar` of `EditFoodScreen` (same wiring as `_NewFoodFormScreen`, `add_food_screen.dart` ~L1001). The form pops itself after `onSave` returns true: `EditFoodScreen` stops passing `skipPopOnSave: true` (`edit_food_screen.dart` ~L142) and `autoSaveOnBlur: true` (~L141). `EditFoodScreen._save` (~L81) keeps returning true/false as today.
- **D-92a.2** A photo change in Edit never writes by itself. `FoodForm.onImageSave` (field ~L126, use in `handlePickedImage` ~L425-431 and `clearImage` ~L487-493, helper `_partialDraftFromInitial` ~L438) is **removed**; the form keeps its local `_imagePath` and the Save draft already carries it (`imagePath: _imagePath`, ~L526). The three save paths already delete the replaced managed file when `imagePath` changes: `FoodLibraryState.updateCatalogFood` (~L946), `editLibraryFood` (~L1022), `updateCustomFood` (~L1361). No state-layer change.
- **D-92a.3** The form-level blur save is removed: `FoodForm.autoSaveOnBlur` (~L105), `_focusNode`, `_onFocusChange` (~L346) and the `Focus(focusNode: _focusNode)` wrapper (~L555) go. `skipPopOnSave` stays (six tests pass it directly to `FoodForm`).
- **D-92a.4** One unsaved-work probe. `_FoodFormProbe` and `_RenderedField` (`add_food_screen.dart` ~L207-333) move unchanged to `lib/features/nutrition/widgets/food_form_unsaved_probe.dart` as public `FoodFormUnsavedProbe` (constructor `(GlobalKey formKey, {String? initialImagePath})`). Photo signal: `FoodForm.onImageChanged` (~L136) changes from `ValueChanged<bool>` (has photo) to `ValueChanged<String?>` reporting the form-local image path (null = none); the probe's `markImageChanged(String? path)` stores it and `isDirty` is true when the reported path differs from `initialImagePath`. For New Food (`initialImagePath` null) this is today's behaviour: pick = dirty, pick then clear = clean.
- **D-92a.5** `EditFoodScreen` gets the New Food exit pattern (`add_food_screen.dart` ~L887-1009): `PopScope(canPop: false)`, `_attemptExit`, `NotificationListener<ScrollNotification>` re-baselining on `ScrollEndNotification`, a post-frame `record()`. Dialog: `ConfirmationDialog.showUnsavedChanges`, title `Unsaved changes`, body `You have unsaved edits. Discard them to return to the food library.`, keys `edit-food-unsaved-keep` / `edit-food-unsaved-discard`. `EditFoodScreen` becomes the third host of the probe, beside `_NewFoodFormScreen` and `_LegacyLibraryEditScreen`.
- **D-92a.6** The legacy shim drops its `onImageSave` (`add_food_screen.dart` ~L487-494) and gains `onImageChanged` plus a probe built with `initialImagePath: widget.food.imagePath`. Its Save, guard and dialog keys (`legacy-food-unsaved-*`) are otherwise unchanged.
- **D-92a.7** Reset to original and Delete food stay in `EditFoodScreen`'s body column (`edit_food_screen.dart` ~L152-197), above the bottom Save. They keep their own confirmation dialogs and pop directly; they do not go through the unsaved guard.
- **D-92a.8** `_NewFoodFormScreen`'s `OmniBottomCTA` label `Create` becomes `Save` (~L1002); the `FoodForm(saveLabel: 'Create')` argument at ~L957 is changed to match. Key `food_form_save` unchanged.
- **D-92a.9** Discarding a photo pick leaves the picked file in the managed folder (as New Food does today when it is discarded). Accepted; no cleanup in this unit.

### Appended by the planner (derived from code and passing tests — vetoable at review)

- **D-92a.10** Save failure path: when `onSave` returns false (the state write threw), `FoodForm._onSave` shows `Could not save food` via its existing error message and the screen stays; nothing is written; the form is still dirty, so the exit guard still fires. No new error copy, no new state.
- **D-92a.11** Validation failure on Save (e.g. empty name): `FoodForm._onSave` returns before any write; the name field shows its inline error; the screen stays; nothing is persisted; the exit guard still fires on back.
- **D-92a.12** Double-tap Save: `FoodForm._onSave`'s `if (_saving) return;` re-entry guard makes a second tap while the first write is in flight a no-op — one write, one pop.
- **D-92a.13** Orphan category: a food whose `groupId` is not among the active groups renders the synthesised orphan dropdown item (`FoodForm._categoryDropdownItems`, ~L845); Save writes the food with its stored `groupId` unchanged — no crash, no silent re-group.
- **D-92a.14** Reset, Delete and the dialog's own Discard pop via direct `Navigator.pop()`, which does not consult `PopScope(canPop: false)`; only `maybePop` paths (header back, system back) hit the guard. Evidence: the shim's dialog-Discard test passes today with `canPop: false` (`test/nutrition_test.dart`, 'Discard pops and leaves the stored food unchanged'). Consequence: Reset/Delete with unsaved edits discard them silently — accepted, the user already confirmed a destructive action (D-92a.7).
- **D-92a.15** After a successful Save the form pops itself (direct `Navigator.pop`, `skipPopOnSave` no longer passed), so the guard does not fire on the way out; `EditFoodScreen` must not route the Save pop through `_attemptExit`.

## Core scenarios (each fails on the base for the reason given)

- **S-92a.1 Save exists and writes.** Fixture: a user-created catalog food `Trail Mix` (`isCatalog: true`) in a mock repo, `EditFoodScreen` pumped on an 800x1800 surface; enter `Trail Mix 2` in `food_form_name`, tap `food_form_save`. Expect: the catalog row's name is `Trail Mix 2`, no `EditFoodScreen` left. Red: no `food_form_save` in Edit.
- **S-92a.2 No write on blur.** Same fixture; enter a new name, then `FocusManager.instance.primaryFocus?.unfocus()` and pump. Expect: stored name unchanged. Red: blur auto-saves today.
- **S-92a.3 Back with changes asks.** Edit the name, trigger the header back; expect `Unsaved changes`; Discard pops with stored name unchanged; a second run: Keep editing stays with the typed name. Red: back closes silently today.
- **S-92a.4 Back untouched closes.** Open, trigger back: no dialog, screen closed. (Guards against a baseline that reads dirty.)
- **S-92a.5 Photo pick waits for Save.** Food with managed photo `A`; call `handlePickedImage` with a new file (test seam, real I/O under `tester.runAsync`); expect stored `imagePath` still `A` and file `A` exists. Tap Save: stored `imagePath` is the new basename and file `A` is gone. Red: pick writes at once today.
- **S-92a.6 Photo clear waits for Save.** Same food; `clearImage()`; stored `imagePath` still `A`; Save: stored null, file `A` deleted. Discard instead: stored `A`, file `A` still exists.
- **S-92a.7 Library copy routes through editLibraryFood.** A bundled food's library copy in `EditFoodScreen`; change a name, Save: the copy changes, the shipped catalog entry does not. (Adapts `test/library_row_toggle_test.dart` S-12719, which drove `form.onImageSave`.)
- **S-92a.8 Legacy shim photo waits for Save.** `_LegacyLibraryEditScreen` (via a `_UserFoodRow` tap on a `isCatalog: false` food) with a photo: clear it; stored `imagePath` unchanged until Save. (Rewrites `test/food_photo_clear_legacy_edit_test.dart`.)
- **S-92a.9 Reset and Delete remain.** A library copy that differs from its original shows `food_reset_original` above Save; a user-created catalog food with a `nutritionState` shows `food_delete_created` above Save; both still act as before.
- **S-92a.10 New Food says Save.** From Manage Food Library, header "+", `food_form_save` has text `Save` and no `Create` text is on the bar; creating a food still works; the S-2902 guard tests (`test/nutrition_test.dart` ~L2826 and ~L3040) stay green with the probe's new photo signal (pick = dirty; pick then clear = clean).

### Appended by the planner (edge scenarios; numbering continues)

- **S-92a.11 Save with an empty name writes nothing and stays open.** Fixture: S-92a.1's; clear `food_form_name`, tap `food_form_save`. Expect: the inline name error under the field, `EditFoodScreen` still on top, stored name still `Trail Mix`. Edge case of: S-92a.1. Red: no `food_form_save` in Edit.
- **S-92a.12 Second Save tap while saving is a no-op.** Fixture: S-92a.1's plus a `MockWorkoutRepository` subclass counting `updateCatalogFood` calls; enter `Trail Mix 2`; drive `formController.submit()` twice with no pump between (the first sets `_saving` synchronously). Expect: exactly one `updateCatalogFood` call, one pop. Edge case of: S-92a.1. Red: no Save button.
- **S-92a.13 Orphan category saves through Save.** Fixture: a user-created catalog food with `groupId: 'g-gone'`, no active group with that id; open Edit; the category dropdown shows the orphan item; change the name; Save. Expect: stored food keeps `groupId: 'g-gone'` and the new name; no crash. Edge case of: S-92a.1. Red: no Save button. (Screen-level twin of `test/food_form_orphan_category_test.dart`, which drives `FoodForm` directly.)
- **S-92a.14 System back routes through the guard.** Fixture: S-92a.3's; edit the name; `tester.binding.handlePopRoute()`. Expect: `Unsaved changes` with `edit-food-unsaved-keep`/`edit-food-unsaved-discard`; Discard pops without writing. Edge case of: S-92a.3. Red: back closes silently today.
- **S-92a.15 Reset pops through unsaved edits with no dialog.** Fixture: a bundled food's library copy that differs from its original (Reset visible); open Edit; type a new name; tap `food_reset_original`; confirm. Expect: no unsaved dialog; screen pops; the copy is restored to the shipped values. Edge case of: S-92a.9. Green on base — structural guard for D-92a.14 (the new `PopScope` must not intercept the direct pop).
- **S-92a.16 Delete pops through unsaved edits with no dialog.** Fixture: S-92a.9's delete food; open Edit; type a new name; tap `food_delete_created`; confirm. Expect: no unsaved dialog; screen pops; row, library copy and today's log gone. Edge case of: S-92a.9. Green on base — structural guard for D-92a.14.
- **S-92a.17 Save failure keeps the form and the guard.** Fixture: S-92a.1's with a `MockWorkoutRepository` subclass whose `updateCatalogFood` throws; enter a new name; Save. Expect: the `Could not save food` message, screen stays, stored name unchanged; back then shows the unsaved dialog. Edge case of: S-92a.1. Red: no Save button.
- **S-92a.18 Save pops without the guard.** Fixture: S-92a.1's; edit the name; Save. Expect: the screen closes and no `Unsaved changes` dialog ever appears. Edge case of: S-92a.1. Green on base — structural guard for D-92a.15 (Save's pop must not be routed through `_attemptExit`).

## Phase outline (one developer run each; at most 8 items per phase)

- **Phase 1 (developer) — shared probe and photo signal.** Items: extract `FoodFormUnsavedProbe` (D-92a.4); change `FoodForm.onImageChanged` to `ValueChanged<String?>`; `_NewFoodFormScreen` and `_LegacyLibraryEditScreen` use the shared probe; legacy shim drops `onImageSave` (D-92a.6); New Food label `Save` (D-92a.8); rewrite `test/food_photo_clear_legacy_edit_test.dart` (S-92a.8); S-92a.10 in `test/nutrition_test.dart`; keep the two S-2902 groups green. `FoodForm.onImageSave` and `autoSaveOnBlur` stay for now (`EditFoodScreen` still uses them).
- **Phase 2 (developer) — Edit gets Save.** Items: `EditFoodScreen` Save, `PopScope`, probe, dialog (D-92a.1, D-92a.5, D-92a.7); remove `onImageSave`, `autoSaveOnBlur`, `_focusNode` from `FoodForm` (D-92a.2, D-92a.3); rewrite `test/food_form_pick_saves_test.dart` to the new rule (S-92a.5, S-92a.6); S-92a.1-4, S-92a.7, S-92a.9 in a new `test/edit_food_save_test.dart`; adapt `test/library_row_toggle_test.dart` (~L445-520), and fix any of `test/library_merge_test.dart` (~L327-345, ~L439-453) and `test/screen_widget_test.dart` (~L9271-9530) that relied on blur-save.
- **Phase 3 (developer) — docs.** `docs/widget_catalog/nutrition_widgets.md` (the `FoodForm` section: the "EditFoodScreen is the exception" paragraph, the `onImageSave` and `onImageChanged` bullets, the `autoSaveOnBlur` select-all remark, the test-seam paragraph), `docs/nutrition.md` (guard paragraph ~L194: now three hosts), any other doc `grep -rn "autoSaveOnBlur\|onImageSave\|save on blur\|no Save button" docs` finds outside `docs/plans/` and `docs/history/`. Plan status line.

## Code pointers

`lib/features/nutrition/edit_food_screen.dart` (whole file, 195 lines) · `lib/features/nutrition/widgets/food_form.dart` (~L96-150 fields, ~L203 `_focusNode`, ~L346 `_onFocusChange`, ~L403 `handlePickedImage`, ~L484 `clearImage`, ~L555 `Focus`) · `lib/features/nutrition/add_food_screen.dart` (~L207-333 probe, ~L352-505 legacy shim, ~L878-1009 New Food) · tests: `test/food_form_pick_saves_test.dart` (603 lines, instant-save contract), `test/food_photo_clear_legacy_edit_test.dart`, `test/library_row_toggle_test.dart` ~L445-520, `test/nutrition_test.dart` ~L2826 and ~L3040, `test/library_merge_test.dart`, `test/screen_widget_test.dart`.

## Readers of what changes

`EditFoodScreen` / `_LegacyLibraryEditScreen` are read by: `test/food_form_pick_saves_test.dart`, `test/food_photo_clear_legacy_edit_test.dart`, `test/library_merge_test.dart`, `test/library_row_toggle_test.dart`, `test/screen_widget_test.dart`. `FoodForm.onImageChanged` is read only by `_NewFoodFormScreen` (`add_food_screen.dart` ~L961). `FoodForm.onImageSave` and `autoSaveOnBlur` are read by `edit_food_screen.dart`, the legacy shim and `test/food_form_pick_saves_test.dart`.

## Out of scope

Serving fields, macro order, calories, blank boxes, duplicate note (92b, 92c); the state layer; the watch; any new stored field.

## Feature Invariants

- Nothing writes until Save on any of the three `FoodForm` hosts — text, category and photo alike (S-92a.2, S-92a.5, S-92a.6, S-92a.8).
- The three save paths keep their D-7 managed-file delete when `imagePath` changes; no state-layer change in this unit — S-92a.5, S-92a.6, S-92a.8 regression-test it.
- One probe, three hosts: `FoodFormUnsavedProbe` behaves identically for New Food before and after (pick = dirty, pick then clear = clean) — the two S-2902 groups stay green (S-92a.10).
- Reset, Delete and the dialog's Discard pop directly and never through the guard (D-92a.14; S-92a.15, S-92a.16).
- Repository parity is untouched: no repository or model code changes in this unit.

## Existing-Functionality Impact

| Touched surface | Existing readers (grep that found them) | Effect of the change | Guarded by |
|---|---|---|---|
| `EditFoodScreen` (`lib/features/nutrition/edit_food_screen.dart`) | `grep -rn "EditFoodScreen" lib` → push sites `add_food_screen.dart` L1139 (`_UserFoodRowState._openEdit`, user-created catalog rows), L1468 (`_CatalogRowState` pencil). Tests: `library_row_toggle_test.dart` L272/L435/L459/L557, `library_merge_test.dart` L327-345/L439-453, `screen_widget_test.dart` L9291/L9360/L9520/L9646. Docs: `navigation_and_screens.md` L183-184, `nutrition.md` L206+, `widget_catalog/nutrition_widgets.md` L96/L206/L222, `state_management/nutrition_state.md` L179, `app_philosophy.md` L28 (shipped list only — no change). | Gains Save CTA, guard, probe; push sites and route unchanged. | S-92a.1-4, S-92a.7, S-92a.9, S-92a.11-18 |
| `_LegacyLibraryEditScreen` | `grep -rn "_LegacyLibraryEditScreen" lib` → defined and pushed at `add_food_screen.dart` L352/L1151. Tests reach it via a row tap: `food_photo_clear_legacy_edit_test.dart`, `nutrition_test.dart` legacy guard group (~L3040), `screen_widget_test.dart` S-N2 (~L9812). Docs: `nutrition.md` L194-199, `design_system.md` L608. | Drops instant photo save; keeps Save and guard; dialog keys unchanged. | S-92a.8, S-2902 legacy group |
| `FoodForm.onImageSave` | `grep -rn "onImageSave" lib test docs` → lib: `food_form.dart` L126/L425-431/L487-493/L438, `edit_food_screen.dart` L151, `add_food_screen.dart` L487; tests: `food_form_pick_saves_test.dart` (5 tests), `library_row_toggle_test.dart` L517; docs: `widget_catalog/nutrition_widgets.md` L104/L122/L140-151, plus S-12719 name quotes in `nutrition.md` L231, `state_management/nutrition_state.md` L143/L179, `navigation_and_screens.md` L184. | Removed in Phase 2 (the shim's wiring goes in Phase 1); the Save draft already carries `imagePath`. | S-92a.5, S-92a.6, S-92a.8, S-12719 rewrite |
| `FoodForm.autoSaveOnBlur` | `grep -rn "autoSaveOnBlur" lib test docs` → lib: `food_form.dart` L105/L256/L348, `edit_food_screen.dart` L145; tests: `food_form_pick_saves_test.dart` comments L12/L363 only; docs: `widget_catalog/nutrition_widgets.md` L133/L147/L168. | Removed in Phase 2; no test drives it directly. | S-92a.2 |
| `FoodForm.onImageChanged` | `grep -rn "onImageChanged" lib test docs` → lib: `food_form.dart` L136/L417/L486, `add_food_screen.dart` L961 (New Food only); tests: `nutrition_test.dart` S-2902 photo tests (indirect, via the `handlePickedImage` seam); docs: `widget_catalog/nutrition_widgets.md` L105/L152-158. | Type `ValueChanged<bool>` → `ValueChanged<String?>`; New Food wiring keeps its shape. | S-2902 groups green, S-92a.10 |
| `FoodForm.skipPopOnSave` | `grep -rn "skipPopOnSave" test` → `food_form_orphan_category_test.dart` (6 sites), `food_form_decimals_and_autofocus_test.dart` (6 sites), `food_form_pick_saves_test.dart` comments. | Stays (D-92a.3); Edit stops passing it; those 12 direct-drive sites keep compiling and passing unchanged. | S-92a.1, S-92a.18 |
| `food_form_save` key | `grep -rn "food_form_save" test` → `nutrition_test.dart` New Item save tests (~L1905, ~L2004) tap it on New Food. | Key unchanged; label becomes Save (D-92a.8). | S-92a.10 |

## UI Standards Impact

- Shared pieces used: `OmniBottomCTA` (bottom bar, as `_NewFoodFormScreen` already does) and `ConfirmationDialog.showUnsavedChanges` — both existing; no new exception to `docs/design_system.md`.
- `docs/design_system.md`'s "Unsaved work" section (~L601-603) currently names Edit Food among the screens that auto-save; Phase 3 removes that exception (found by `grep -rn "Edit Food" docs/design_system.md`; missed by the seed's grep pattern).
- No new colors, components, or keys beyond `edit-food-unsaved-*`.

## Iteration 1

### Phase 1: shared probe and photo signal (@developer)

1. [x] Create `lib/features/nutrition/widgets/food_form_unsaved_probe.dart`: move `_FoodFormProbe` and `_RenderedField` from `add_food_screen.dart` ~L207-333 unchanged, public as `FoodFormUnsavedProbe(GlobalKey formKey, {String? initialImagePath})`; `markImageChanged(String? path)` stores the reported form-local path; `isDirty` true when the reported path differs from `initialImagePath` (D-92a.4) — `lib/features/nutrition/widgets/food_form_unsaved_probe.dart` · `FoodFormUnsavedProbe`, `_RenderedField` — done: file created, `_RenderedField` private to it
2. [x] Change the photo signal: `onImageChanged` field to `ValueChanged<String?>?` (~L136); `handlePickedImage` calls `widget.onImageChanged?.call(<persisted path>)` (~L417); `clearImage` calls `widget.onImageChanged?.call(null)` (~L486); update the field's doc comment — `lib/features/nutrition/widgets/food_form.dart` · `FoodForm.onImageChanged`, `_FoodFormState.handlePickedImage`, `_FoodFormState.clearImage` — done: both call sites report the path
3. [x] Swap both hosts to the shared probe: delete `_FoodFormProbe`/`_RenderedField` (~L207-333); `_NewFoodFormScreenState` builds `FoodFormUnsavedProbe(_formKey)` (no `initialImagePath`); `_LegacyLibraryEditScreenState` builds `FoodFormUnsavedProbe(_formKey, initialImagePath: widget.food.imagePath)` and passes `onImageChanged: _probe.markImageChanged`; delete the shim's `onImageSave` block (D-92a.6) — `lib/features/nutrition/add_food_screen.dart` · `_NewFoodFormScreenState._probe`, `_LegacyLibraryEditScreenState._probe`, `_LegacyLibraryEditScreenState.build` — done: shim no longer writes a photo on pick or clear
4. [x] New Food label: `OmniBottomCTA` label `'Create'` → `'Save'` (~L1002) and `FoodForm(saveLabel: 'Create')` → `'Save'` (~L957); key `food_form_save` unchanged (D-92a.8) — `lib/features/nutrition/add_food_screen.dart` · `_NewFoodFormScreenState.build` — done
5. [x] Rewrite to S-92a.8: rename the test to `clearing a legacy library food's photo waits for the Save tap`; clear → stored `imagePath` and file unchanged; tap Save → stored null and file deleted; add the Discard leg (back → `legacy-food-unsaved-discard` → stored path and file untouched) — `test/food_photo_clear_legacy_edit_test.dart` · the single `testWidgets` — done: three legs green, prove-red RED AT base
6. [x] Add S-92a.10 to the '+ New Item' group: from Manage Food Library header '+', `food_form_save` renders text `Save` and no `Create` on the bar; creating still works — `test/nutrition_test.dart` · new `testWidgets` in group `AddFoodScreen — + New Item (S-004 / S-005)` — done: `the New Food bottom bar says Save, not Create (S-92a.10)`, prove-red RED AT base
7. [x] Verify the two S-2902 groups stay green with the `String?` signal (no edits expected; a red here is a probe-parity defect) — `test/nutrition_test.dart` · groups `AddFoodScreen — New Food form unsaved guard (S-2902)` and `AddFoodScreen — legacy edit shim unsaved guard (S-2902)` — done: 17 tests green, no edits

**Done Criteria** (run until green):
- `.github/copilot/scripts/macos/gateway.sh test test/food_photo_clear_legacy_edit_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test test/nutrition_test.dart --plain-name "S-2902"` and `.github/copilot/scripts/macos/gateway.sh test test/nutrition_test.dart --plain-name "New Item"`
- `.github/copilot/scripts/macos/gateway.sh lint` — compare with the 180-issue baseline (0 errors)
- `.github/copilot/scripts/macos/gateway.sh test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- Prove-red: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/food_photo_clear_legacy_edit_test.dart` must FAIL on base (the shim writes on clear today); the S-92a.10 test must fail on base (the bar says Create).

**Predicted Files**: `lib/features/nutrition/widgets/food_form_unsaved_probe.dart` (new), `lib/features/nutrition/widgets/food_form.dart`, `lib/features/nutrition/add_food_screen.dart`, `test/food_photo_clear_legacy_edit_test.dart`, `test/nutrition_test.dart`. Nothing else.

### Phase 2: Edit gets Save (@developer)

1. [x] Add the guard plumbing to `_EditFoodScreenState`: `_formKey`; `FoodFormUnsavedProbe _probe` built with `initialImagePath: widget.food.imagePath`; post-frame `record()` in `initState`; `_probe.dispose()` in `dispose`; `_attemptExit` showing `ConfirmationDialog.showUnsavedChanges(title: 'Unsaved changes', body: 'You have unsaved edits. Discard them to return to the food library.', keepEditingKey: 'edit-food-unsaved-keep', discardKey: 'edit-food-unsaved-discard')` (D-92a.5) — `lib/features/nutrition/edit_food_screen.dart` · `_EditFoodScreenState` (new members `_formKey`, `_probe`, `_attemptExit`, `initState`, `dispose`) — done
2. [x] Wrap the build: `PopScope(canPop: false, onPopInvokedWithResult: … _attemptExit …)`; body in `NotificationListener<ScrollNotification>` re-baselining on `ScrollEndNotification`; `FoodForm` gets `key: _formKey` and `onImageChanged: _probe.markImageChanged`; drop `autoSaveOnBlur: true` (~L145), `skipPopOnSave: true` (~L142), `onImageSave: _save` (~L151) (D-92a.1, D-92a.5) — `lib/features/nutrition/edit_food_screen.dart` · `_EditFoodScreenState.build` — done
3. [x] Add `bottomNavigationBar: OmniBottomCTA(label: 'Save', buttonKey: const Key('food_form_save'), onPressed: _formController.submit)`; Reset/Delete stay in the body column above it, unchanged (D-92a.1, D-92a.7) — `lib/features/nutrition/edit_food_screen.dart` · `_EditFoodScreenState.build` — done: block kept verbatim, only re-indented under `PopScope`
4. [x] Remove the dead form machinery: `onImageSave` field (~L126) and its uses in `handlePickedImage`/`clearImage`/`_partialDraftFromInitial` (~L425-431, ~L487-493, ~L438); `autoSaveOnBlur` (~L105), `_focusNode` (~L203), `_onFocusChange` (~L346), the `Focus(focusNode: _focusNode)` wrapper (~L555); update doc comments (D-92a.2, D-92a.3) — `lib/features/nutrition/widgets/food_form.dart` · `FoodForm.onImageSave`, `FoodForm.autoSaveOnBlur`, `_FoodFormState._focusNode`, `_FoodFormState._onFocusChange`, `_FoodFormState._partialDraftFromInitial`, `_FoodFormState.build` — done: −136/+25 lines, `ListView` is the `Form`'s child
5. [x] Rewrite to the waits-for-Save rule (S-92a.5, S-92a.6): the five `testWidgets` listed under Tests rewritten; rename both groups (`… triggers a state save …` → `… waits for Save …`); the create-mode tests keep their names' shape and now assert the `String?` signal — `test/food_form_pick_saves_test.dart` · the five `testWidgets` (L67, L189, L296, L384, L512) — done: `+5` green, both `onImageChanged` calls proven by mutation
6. [ ] New file, part A: S-92a.1 (Save exists and writes via `updateCatalogFood`), S-92a.2 (no write on blur), S-92a.3 (header back guard: Discard and Keep editing legs), S-92a.4 (back untouched closes), S-92a.7 (library copy routes through `editLibraryFood` via the Save tap), S-92a.9 (Reset/Delete remain above Save) — `test/edit_food_save_test.dart` · one `testWidgets` per S-id — **S-92a.1-4 done** (`+4` green, `RED AT HEAD`); S-92a.7 and S-92a.9 remain for Part B
7. [ ] Same file, part B: edge scenarios S-92a.11 (empty name), S-92a.12 (double tap, counting repo), S-92a.13 (orphan category), S-92a.14 (system back via `handlePopRoute`), S-92a.15 (Reset through unsaved edits), S-92a.16 (Delete through unsaved edits), S-92a.17 (save failure, throwing repo), S-92a.18 (save pops without the guard) — `test/edit_food_save_test.dart` · one `testWidgets` per S-id
8. [x] Rewrite S-12719: drop the `form.onImageSave` leg (L502-520), rename to `S-12719: the Edit screen routes a bundled copy's save through editLibraryFood`; then verify `test/library_merge_test.dart` (S-12815/S-12816/S-12816b) and `test/screen_widget_test.dart` (EditFoodScreen tests, S-N2) pass unchanged — edit only if red (research says they never relied on blur-save) — `test/library_row_toggle_test.dart` · `S-12719: the Edit screen routes a bundled copy's save through editLibraryFood (onSave and onImageSave)` (~L445-520) — done: `library_row_toggle_test` + `food_photo_clear_legacy_edit_test` `+11`; `library_merge_test` + `screen_widget_test` `+248`, neither edited

**Done Criteria** (run until green):
- `.github/copilot/scripts/macos/gateway.sh test test/edit_food_save_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test test/food_form_pick_saves_test.dart test/food_photo_clear_legacy_edit_test.dart test/library_row_toggle_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test test/library_merge_test.dart test/screen_widget_test.dart` (900 s; `screen_widget_test.dart` is large)
- `.github/copilot/scripts/macos/gateway.sh lint` — compare with the 180-issue baseline (0 errors)
- `.github/copilot/scripts/macos/gateway.sh test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- Prove-red: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/edit_food_save_test.dart` must FAIL on base (S-92a.1/2/3 are red there); `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/food_form_pick_saves_test.dart` must FAIL on base (the instant-save contract is gone).

**Predicted Files**: `lib/features/nutrition/edit_food_screen.dart`, `lib/features/nutrition/widgets/food_form.dart`, `test/edit_food_save_test.dart` (new), `test/food_form_pick_saves_test.dart`, `test/library_row_toggle_test.dart`; `test/library_merge_test.dart` and `test/screen_widget_test.dart` predicted unchanged (edit only if red).

### Phase 3: docs (@developer)

1. [ ] `docs/widget_catalog/nutrition_widgets.md` `### FoodForm` section: props paragraph (~L104-106 — drop `onImageSave`; `onImageChanged` now `ValueChanged<String?>`); the "EditFoodScreen is the exception" paragraph (~L132-135 → Edit now has the standard Save CTA and guard); the `onImageSave` bullet (~L140-151 → replaced by "nothing writes until Save; the Save draft carries `imagePath`; the state method owns the D-7 file delete"); the `onImageChanged` bullet (~L152-158 → all three hosts mark the probe); the select-all remark (~L168 — drop the form-level FocusNode / `autoSaveOnBlur`) — symbol: section `### FoodForm`
2. [ ] `docs/nutrition.md`: guard paragraph ~L194-196 (three hosts; Edit Food no longer auto-saves); `### EditFoodScreen` ~L206-224 (Save button, guard, photo-on-Save) including fixing the stale claim "Clearing the photograph clears the stored path; the file on disk is left intact" (contradicts D-7 — the state method deletes the replaced managed file; see `test/food_photo_clear_legacy_edit_test.dart`); the S-12719 name quote ~L231 — symbols: the three paragraphs
3. [ ] `docs/design_system.md` "Unsaved work" (~L601-603): Edit Food leaves the named auto-save exceptions; it now carries the standard guard — symbol: section `### Unsaved work`
4. [ ] `docs/navigation_and_screens.md` L183-184: the EditFoodScreen row gains Save + guard; drop the S-12719 name's `(onSave and onImageSave)` — symbol: the EditFoodScreen rows
5. [ ] `docs/state_management/nutrition_state.md` L143 and L179: drop the `(onSave and onImageSave)` quotes on `editLibraryFood` — symbols: the `editLibraryFood` table row and the pencil bullet
6. [ ] Residue sweep + status: `grep -rn "autoSaveOnBlur\|onImageSave\|save on blur\|no Save button" docs` outside `docs/plans/` and `docs/history/` must return zero hits (fix any found); update this plan's Status line to Iteration 1 complete, pending review — symbols: the grep; the plan header Status line

**Done Criteria** (run until green):
- `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` — its output prints exact byte sizes for any doc in the 52 KiB warning band; if `nutrition.md` or `design_system.md` appears there, split per the test's reason (a new part page needs a new directory → Governor action)
- `.github/copilot/scripts/macos/gateway.sh test test/ui_standards_contract_test.dart`
- `.github/copilot/scripts/macos/gateway.sh lint` — compare with the 180-issue baseline (0 errors)
- The residue grep with zero hits outside `docs/plans/` and `docs/history/`

**Predicted Files**: `docs/widget_catalog/nutrition_widgets.md`, `docs/nutrition.md`, `docs/design_system.md`, `docs/navigation_and_screens.md`, `docs/state_management/nutrition_state.md`, this plan file (Status line only).

## Tests rewritten (not deleted)

| # | File | Old name (base) | New name / change | Phase |
|---|---|---|---|---|
| 1 | `test/food_photo_clear_legacy_edit_test.dart` | `clearing a legacy library food's photo persists without a Save tap` | `clearing a legacy library food's photo waits for the Save tap` (+ Discard leg) | 1 |
| 2 | `test/food_form_pick_saves_test.dart` | `handlePickedImage persists the file AND fires onImageSave with a partial draft` | `handlePickedImage records the file and marks the probe dirty; nothing saves until Save` | 2 |
| 3 | `test/food_form_pick_saves_test.dart` | `handlePickedImage replaces the previous managed file (D-7 round-trip)` | same name; the D-7 delete assertion moves to after Save | 2 |
| 4 | `test/food_form_pick_saves_test.dart` | `handlePickedImage in create mode (initial == null) does NOT fire onImageSave` | `handlePickedImage in create mode (initial == null) reports the path through onImageChanged and saves nothing` | 2 |
| 5 | `test/food_form_pick_saves_test.dart` | `clearImage fires onImageSave with imagePath: null AND deletes the previous managed file (D-7)` | `clearImage reports null through onImageChanged; the stored path and file wait for Save (D-7)` | 2 |
| 6 | `test/food_form_pick_saves_test.dart` | `clearImage in create mode (initial == null) does NOT fire onImageSave` | `clearImage in create mode (initial == null) reports null and saves nothing` | 2 |
| 7 | `test/library_row_toggle_test.dart` | `S-12719: the Edit screen routes a bundled copy's save through editLibraryFood (onSave and onImageSave)` | `S-12719: the Edit screen routes a bundled copy's save through editLibraryFood` (onImageSave leg deleted) | 2 |

Unchanged but verified: `test/nutrition_test.dart` S-2902 photo tests (`a picked photo counts as unsaved work (S-2902)`, `picking then clearing the photo is clean again (S-2902)`); `test/library_merge_test.dart` S-12815/S-12816/S-12816b; `test/screen_widget_test.dart` EditFoodScreen tests and S-N2; `test/food_form_orphan_category_test.dart` and `test/food_form_decimals_and_autofocus_test.dart` (drive `skipPopOnSave` directly, which stays).

## Files Affected

- Production: `lib/features/nutrition/widgets/food_form_unsaved_probe.dart` (new, Phase 1), `lib/features/nutrition/widgets/food_form.dart` (Phases 1-2), `lib/features/nutrition/add_food_screen.dart` (Phase 1), `lib/features/nutrition/edit_food_screen.dart` (Phase 2).
- Tests: `test/food_photo_clear_legacy_edit_test.dart`, `test/nutrition_test.dart` (Phase 1); `test/food_form_pick_saves_test.dart`, `test/edit_food_save_test.dart` (new), `test/library_row_toggle_test.dart` (Phase 2).
- Docs: `docs/widget_catalog/nutrition_widgets.md`, `docs/nutrition.md`, `docs/design_system.md`, `docs/navigation_and_screens.md`, `docs/state_management/nutrition_state.md`, this plan's Status line (Phase 3).
- Read-only dependents: `lib/state/nutrition/food_library_state.dart` (verify only — the D-7 delete paths are already correct); the `EditFoodScreen.push` sites `add_food_screen.dart` L1139/L1468 (unchanged).

## Notes

- Phase dependency: Phase 2 needs Phase 1's probe file and `onImageChanged` type; Phase 3 needs both. Phase 1 is user-visible on its own (New Food says Save; the shim's photo waits for Save).
- Intermediate state after Phase 1: Edit Food still auto-saves on blur and on photo pick (old behaviour, old tests) — intended; `onImageSave`/`autoSaveOnBlur` still exist for it until Phase 2.
- The `food_form_save` key is shared by New Food and Edit; `nutrition_test.dart`'s New Item tests (~L1905, ~L2004) keep passing.
- Widget tests that need real photo I/O use `tester.runAsync` (existing pattern in `test/food_photo_clear_legacy_edit_test.dart`); keep Hive seeding in `setUp` and run Mock-first.
- The evidence file `2026-10-29-92a-edit-food-save-plan.evidence.md` holds the research baselines (grep match lists, prove-red rationale); it did not exist before this planning run.

## Progress

- [x] Phase 1 (developer) — shared probe and photo signal — **Complete** (`FoodFormUnsavedProbe` in its own file, `onImageChanged: ValueChanged<String?>`, shim photo waits for Save, New Food CTA says Save; full suite `+5873 ~2`, lint 180/0 errors; evidence in `…-plan.evidence.md`)
- [x] Phase 2 (developer) — Edit gets Save — **Complete** (Part A items 1-5, 8: `EditFoodScreen` gains the bottom Save CTA and the unsaved-changes guard, `FoodForm` loses `onImageSave`/`autoSaveOnBlur`/the form-level `FocusNode`, rewritten tests 2-7 green; scenarios S-92a.1-4 in `test/edit_food_save_test.dart` and S-92a.5/S-92a.6 in `test/food_form_pick_saves_test.dart`. Part B items 6-7: S-92a.7, 9, 11-18 added to the same file, 14 tests in it all green, each new guard proven red by mutation (5 mutations, originals restored verbatim, `git-diff --stat -- lib` back to the four hands-off files). No production change in Part B. Full suite `+5887 ~2`, contract pair `+54`, lint 180 issues / 0 errors — evidence in `…-plan.evidence.md`)
- [ ] Phase 3 (developer) — docs

## Assumption Log

- **A-92a.P1.1 S-92a.8 leg order** — the test runs the Discard leg before the Save leg. Options: Save first (plan's listing order) or Discard first. Chose Discard first because Save deletes the managed file and nulls the row, so a Discard leg after it would need a second seeded photo to assert anything.
- **A-92a.P1.2 Leg 1 settle window** — leg 1 polls stored state for up to 1 s (real timestamps, no fixed sleep) before asserting "nothing was written", so a save-on-clear has room to land and fail the assertion on base. Chose a bracket over a bare assertion because the bare version passed on base (the write had not completed yet) and so proved nothing.
- **A-92a.P1.3 `_RenderedField` stays private** — kept inside `food_form_unsaved_probe.dart` per the brief rather than exported beside the public probe; no host needs it.
- **A-92a.P2.1 Reset/Delete block is wrapped, not restructured** — the brief says its SafeArea block is "unchanged"; it now sits inside the `PopScope` → `Scaffold` body's `Column` with the CTA in `bottomNavigationBar`. Chose to keep the block's own widget tree and tokens verbatim (only re-indented) because D-92a.14 puts the CTA below it and `bottomNavigationBar` is the standard slot.
- **A-92a.P2.2 Create-mode clear test seeds no photo** — `FoodForm` exposes no seam for `_imagePath`, so the create-mode `clearImage` test asserts the `onImageChanged(null)` signal and "nothing saved" instead of staging a managed file it cannot inject. Chose the narrower assertion over adding a test-only parameter.
- **A-92a.P2.3 D-7 clear test asserts both sides of Save** — the managed file must survive the clear (nothing writes until Save) and be gone after the Save, both through `MockWorkoutRepository`. Chose two phases over the old single post-clear assertion so the new ownership rule is what fails if the delete moves back into the form.
- **A-92a.P2.4 S-92a.9 opens a second editor via a keyed MaterialApp** — `pumpWidget` on the same `MaterialApp` type reuses the Navigator element, so the second `_openEditor` in one test found the first route still on the stack. `_openEditorFor` now passes `key: UniqueKey()`; no production seam added.
- **A-92a.P2.5 S-92a.17's failure message is read without `runAsync`** — `Could not save food` arrives through `OmniMessage`, not a repository write, so the test uses plain `pump()` + `pump(300 ms)` rather than the bounded real-time poll the write assertions use.

## Feedback

(empty)
