# Evidence — 92a Edit Food Save (planning run, 2026-10-29)

Research evidence for `2026-10-29-92a-edit-food-save-plan.md`. Collected by the planner; no code changed.

## Baselines

- Base commit `1b9bfb405168f9c629952802dfa4fd27f2aeb516` on `claude_develop` (from the brief).
- `flutter analyze` baseline: **180 issues, 0 errors** (from the brief). Phase Done Criteria compare against 180.
- `flutter test` full suite: several minutes (900 s timeout). Widget tests Mock-first; Hive seeded in `setUp`; real `Future.delayed`/Hive writes hang inside `testWidgets` (FakeAsync).
- Evidence file did not exist before this run; created by the planner.

## Key Flutter behaviour (resolved from repo evidence, not assumption)

Programmatic `Navigator.pop()` bypasses `PopScope(canPop: false)`; only `maybePop` paths (AppBar back via `pageBack`, system back via `handlePopRoute`) invoke `onPopInvokedWithResult(didPop: false)`. Proof: the legacy shim's dialog-Discard test (`test/nutrition_test.dart`, 'Discard pops and leaves the stored food unchanged') passes today with the shim's `PopScope(canPop: false)` — the dialog's Discard pops programmatically and is not intercepted. Consequences encoded in D-92a.14/D-92a.15: form-save pop, Reset pop and Delete pop never hit the guard; the guard fires only on back paths.

## Grep match lists (full)

### `EditFoodScreen` (grep `EditFoodScreen` over lib/test/docs)
- lib: `lib/features/nutrition/add_food_screen.dart` L1139 (`_UserFoodRowState._openEdit` — user-created catalog rows), L1468 (`_CatalogRowState` pencil; bundled `? copy : widget.food`).
- tests: `test/library_row_toggle_test.dart` L272, L435, L459, L557; `test/library_merge_test.dart` L327, L337, L345, L439, L453; `test/screen_widget_test.dart` L9291, L9360, L9520, L9646; `test/food_form_pick_saves_test.dart` and `test/food_photo_clear_legacy_edit_test.dart` (comments only).
- docs: `docs/navigation_and_screens.md` L136, L183-184; `docs/state_management/nutrition_state.md` L178-179; `docs/nutrition.md` L174, L206; `docs/widget_catalog/nutrition_widgets.md` L96, L206, L222; `docs/README.md` L126 (tree); `docs/app_philosophy.md` L28 (shipped list only — no change needed).

### `_LegacyLibraryEditScreen` (grep over lib/test/docs)
- lib: defined `add_food_screen.dart` L352, pushed L1151 (legacy branch of `_openEdit`).
- tests reach it indirectly via an AddFoodScreen row tap: `test/food_photo_clear_legacy_edit_test.dart`, `test/nutrition_test.dart` legacy guard group (~L3040), `test/screen_widget_test.dart` S-N2 (~L9812-9896).
- docs: `docs/nutrition.md` L194-199; `docs/design_system.md` L608. (`docs/history/` skipped by convention.)

### `FoodForm.onImageSave` (grep `onImageSave`)
- lib: `food_form.dart` L126 (field), L425-431 (`handlePickedImage`), L487-493 (`clearImage`), L438 (`_partialDraftFromInitial`); `edit_food_screen.dart` L151; `add_food_screen.dart` L487 (shim block).
- tests: `test/food_form_pick_saves_test.dart` (5 testWidgets, names at L67, L189, L296, L384, L512); `test/library_row_toggle_test.dart` L517 (`form.onImageSave!`).
- docs: `docs/widget_catalog/nutrition_widgets.md` L104, L122, L140-151; S-12719 test-name quotes containing "(onSave and onImageSave)": `docs/nutrition.md` L231, `docs/state_management/nutrition_state.md` L143 and L179, `docs/navigation_and_screens.md` L184.

### `FoodForm.autoSaveOnBlur` (grep `autoSaveOnBlur`)
- lib: `food_form.dart` L105 (field), L256, L348 (`_onFocusChange`); `edit_food_screen.dart` L145.
- tests: `test/food_form_pick_saves_test.dart` comments L12, L363 only — no test drives it directly.
- docs: `docs/widget_catalog/nutrition_widgets.md` L133, L147, L168.

### `FoodForm.onImageChanged` (grep `onImageChanged`)
- lib: `food_form.dart` L136 (field, `ValueChanged<bool>?`), L417 (`handlePickedImage`), L486 (`clearImage`); `add_food_screen.dart` L961 (New Food only).
- tests: `test/nutrition_test.dart` S-2902 photo tests (indirect, via the `handlePickedImage` seam).
- docs: `docs/widget_catalog/nutrition_widgets.md` L105, L152-158.

### `FoodForm.skipPopOnSave` (grep `skipPopOnSave` over test/)
- `test/food_form_orphan_category_test.dart` L133, L218, L275, L336, L400, L460 (6 direct-drive sites).
- `test/food_form_decimals_and_autofocus_test.dart` L185, L260, L310, L382, L431, L494 (6 direct-drive sites).
- `test/food_form_pick_saves_test.dart` L12, L363 (comments).
- `skipPopOnSave` stays (D-92a.3), so all 12 sites keep compiling and passing unchanged.

### `food_form_save` key (grep over test/)
- `test/nutrition_test.dart` ~L1905, ~L2004 (New Item save tests tap it on New Food). Key unchanged in this unit.

### Extra doc finding (missed by the seed's grep pattern)
- `docs/design_system.md` L601-603, "Unsaved work" section, names Edit Food among "the screens that auto-save" — found by `grep -rn "Edit Food" docs/design_system.md`; Phase 3 item 3 removes the exception.

### Stale doc claim
- `docs/nutrition.md` EditFoodScreen section: "Clearing the photograph clears the stored path; the file on disk is left intact" — contradicts D-7 (the state methods `updateCatalogFood` ~L946, `editLibraryFood` ~L1022, `updateCustomFood` ~L1361 delete the replaced managed file; `test/food_photo_clear_legacy_edit_test.dart` asserts the deletion). Phase 3 item 2 fixes it.

## Prove-red rationale (why each guard fails on base)

- S-92a.1/2/3/11/12/13/14/17: no `food_form_save` exists in Edit Food on base; blur auto-saves; back closes silently.
- S-92a.5/6: `handlePickedImage`/`clearImage` write through `onImageSave` immediately on base.
- S-92a.8: the shim's `onImageSave` block writes on clear on base (`test/food_photo_clear_legacy_edit_test.dart` asserts exactly that today).
- S-92a.10: the New Food bar says Create on base.
- S-92a.15/16/18: green-on-base structural guards — they pin behaviour the new `PopScope` could break (guard intercepting direct pops, or Save routed through `_attemptExit`); they pass on base and must stay green.

## Test-seam notes for implementers

- Real photo I/O in widget tests: `tester.runAsync` (existing pattern in `test/food_photo_clear_legacy_edit_test.dart`); `TestImageStorage.create()` from `test/helpers/test_image_storage.dart`; the × button is found by tooltip `Remove photo`.
- S-92a.12/S-92a.17 need `MockWorkoutRepository` subclasses (call-counting / throwing `updateCatalogFood`).
- S-92a.14 uses `tester.binding.handlePopRoute()` for system back.
- `ConfirmationDialog.showUnsavedChanges(context, title:, body:, keepEditingKey:, discardKey:)` — verified signature.
- `FoodForm._onSave` starts with `if (_saving) return;` — the double-tap guard is synchronous.
- `FoodForm._categoryDropdownItems` (~L845) synthesises an orphan/archived dropdown item when the food's `_groupId` is not in active groups — S-92a.13 is testable at screen level.
- `test/docs_indexing_contract_test.dart` prints exact byte sizes for docs in the 52 KiB warning band and enforces the 64 KiB ceiling; Phase 3 reads sizes from its output (no `wc`/`ls` available; gateway-only shell).
- `test/ui_standards_contract_test.dart` food references are generic scanners only — no food-specific contract trips on this change (verified).

---

# Phase 1 evidence — shared probe and photo signal (developer, 2026-10-29)

Base `1b9bfb40` (HEAD); no code changes beyond the Phase 1 Predicted Files.

## Tests written first (red before implementation)

1. `test/food_photo_clear_legacy_edit_test.dart` — rewritten to S-92a.8, name
   `clearing a legacy library food's photo waits for the Save tap`. One
   `testWidgets`, three legs: clear writes nothing → Discard (back →
   `legacy-food-unsaved-discard`) leaves stored path + file → Save writes null
   and deletes the file (D-7). Leg 1 is bracketed by a 1 s real-time settle
   (`DateTime.now()` deadline in `runAsync`) so a save-on-clear has room to
   land before the assertion; no fixed sleep, no wall-clock threshold.
   Red run on base code (before implementation):

   ```
   Expected: true
     Actual: <false>
   the managed file must survive an unwritten clear
   ... food_photo_clear_legacy_edit_test.dart line 177
   00:01 +0 -1: Some tests failed.
   ```

2. `test/nutrition_test.dart`, group `AddFoodScreen — + New Item (S-004 / S-005)`,
   new `testWidgets` `the New Food bottom bar says Save, not Create (S-92a.10)`:
   header `new_food_button` → `food_form_save` renders `Save`, no `Create` text;
   then the create flow still writes a catalog row. Red run on base code:

   ```
   Expected: exactly one matching candidate
     Actual: _DescendantWidgetFinder:<Found 0 widgets with text "Save" descending from widgets with key [<'food_form_save'>]: []>
   the New Food bottom button reads Save (D-92a.8)
   00:01 +2 -1: Some tests failed.
   ```

   No existing test in `test/nutrition_test.dart` expected the text `Create`
   (`grep "'Create'"` → 0 hits), so no expectation needed updating.

## Prove-red (gateway, base `1b9bfb405168f9c629952802dfa4fd27f2aeb516`)

```
$ gateway.sh prove-red 1b9bfb4… test test/food_photo_clear_legacy_edit_test.dart
the managed file must survive an unwritten clear
gateway: prove-red: RED AT 1b9bfb405168f9c629952802dfa4fd27f2aeb516 (exit 1).

$ gateway.sh prove-red 1b9bfb4… test test/nutrition_test.dart --plain-name S-92a.10
the New Food bottom button reads Save (D-92a.8)
gateway: prove-red: RED AT 1b9bfb405168f9c629952802dfa4fd27f2aeb516 (exit 1).
```

Both fail by assertion on base (not a compile or load error), each for the
reason its scenario names.

## Green runs after implementation

| Check | Result |
|---|---|
| `gateway.sh test test/food_photo_clear_legacy_edit_test.dart` | `+1: All tests passed!` |
| `gateway.sh test test/nutrition_test.dart --plain-name "New Item"` | `+3: All tests passed!` |
| `gateway.sh test test/nutrition_test.dart --plain-name "S-2902"` | `+17: All tests passed!` (both S-2902 groups, no edits) |
| `gateway.sh test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` | `+54: All tests passed!` |
| `gateway.sh lint` | `180 issues found.` — 0 errors, equal to the 180 baseline |
| `gateway.sh test` (full suite) | `03:51 +5873 ~2: All tests passed!` (5873 passed, 2 skipped, 0 failed) |
| `grep -rln "import .*hive_workout_repository" lib/{state,features,widgets,core}` | no matches |

## What changed

- `lib/features/nutrition/widgets/food_form_unsaved_probe.dart` (new):
  `FoodFormUnsavedProbe(GlobalKey formKey, {String? initialImagePath})` — the
  moved `_FoodFormProbe` as public API and `_RenderedField` private to the new
  file. Photo signal now `markImageChanged(String? path)`; `isDirty` reports a
  change when the reported path differs from `initialImagePath`.
- `lib/features/nutrition/widgets/food_form.dart`: `onImageChanged` is
  `ValueChanged<String?>?`; `handlePickedImage` reports the persisted path,
  `clearImage` reports `null`; doc comment rewritten. `onImageSave` and
  `autoSaveOnBlur` untouched (Edit still uses them until Phase 2).
- `lib/features/nutrition/add_food_screen.dart`: probe block removed (moved);
  both hosts use `FoodFormUnsavedProbe` (the shim with
  `initialImagePath: widget.food.imagePath` and `onImageChanged:
  _probe.markImageChanged`); the shim's `onImageSave` block deleted; New Food
  `saveLabel` and CTA label `Create` → `Save`. `food_form_save` key unchanged.

## Diff footprint

`git-diff --stat` for the files this run touched: `add_food_screen.dart`
(−160 lines net: the moved probe block plus the deleted shim `onImageSave`),
`food_form.dart` 22 lines, `food_photo_clear_legacy_edit_test.dart` 131,
`nutrition_test.dart` +71, plus the new untracked probe file. No other file was
edited; `docs/`, `edit_food_screen.dart` and the hands-off watch/session files
are untouched by this run.

---

# Phase 2 Part A evidence (2026-10-29, developer)

Scope: plan Phase 2 items **1-5, 8** — `EditFoodScreen` gets the bottom Save CTA
and the unsaved-changes guard; `FoodForm` loses `onImageSave`, `autoSaveOnBlur`,
the form-level `_focusNode`/`Focus` wrapper and `_partialDraftFromInitial`; the
rewritten tests (table rows 2-7) go green. Items 6-7 (S-92a.7, 9, 11-18) are
Part B and were not touched.

## Tests written first (red before implementation)

New file `test/edit_food_save_test.dart` (S-92a.1-S-92a.4), written before any
production edit. First run against the base code:

```
00:0x +1 -3: Some tests failed.
  S-92a.1: Save writes the edited food and closes the screen
    Expected: exactly one matching candidate
      Actual: _KeyFinder:<Found 0 widgets with key [<'food_form_save'>] …>
  S-92a.2: focus leaving the form writes nothing
    Expected: 'Trail Mix'
      Actual: 'Trail Mix 2'          <- the blur auto-save landed
  S-92a.3: back with edits asks; Discard drops them and Keep editing stays
    Expected: exactly one matching candidate
      Actual: _TextFinder:<Found 0 widgets with text "Unsaved changes" …>
  S-92a.4: back on an untouched form closes with no dialog  … passed
```

S-92a.4 is a structural guard (no dialog on an untouched form) and is expected
to be green on base; the three behaviour guards are red for exactly the reason
each scenario names (no Save button, blur writes, no guard).

## Prove-red (gateway, base `1b9bfb405168f9c629952802dfa4fd27f2aeb516`)

```
$ gateway.sh prove-red HEAD test test/edit_food_save_test.dart
S-92a.1: Save writes the edited food and closes the screen
S-92a.2: focus leaving the form writes nothing
S-92a.3: back with edits asks; Discard drops them and Keep editing stays
gateway: prove-red: RED AT HEAD (exit 1).
```

`prove-red HEAD test test/food_form_pick_saves_test.dart` cannot compile at the
base commit (`onImageChanged` is `ValueChanged<bool>` there, the rewritten tests
pass `String?`), so that file's guards are proven by mutation instead. Original
lines, verbatim, in `lib/features/nutrition/widgets/food_form.dart`:

| Mutation (removed line) | Tests that went red | Restored? |
|---|---|---|
| `    widget.onImageChanged?.call(persistedPath);` in `handlePickedImage` | 3 S-92a.5 tests (`Expected: <1> Actual: <0>` — the probe never went dirty) at L145, L293, L381 | yes, exact re-insert; re-run `+9: All tests passed!` |
| `    widget.onImageChanged?.call(null);` in `clearImage` | 2 S-92a.6 tests (`Expected: <1> Actual: <0>`) at L508, L599 | yes, exact re-insert; re-run `+9: All tests passed!` |

No mutation was left applied; the tree was re-run green after each restore.

## Green runs after implementation

| Check | Result |
|---|---|
| `gateway.sh test test/edit_food_save_test.dart test/food_form_pick_saves_test.dart` | `+9: All tests passed!` |
| `gateway.sh test test/food_photo_clear_legacy_edit_test.dart test/library_row_toggle_test.dart` | `+11: All tests passed!` |
| `gateway.sh test test/library_merge_test.dart test/screen_widget_test.dart` | `+248: All tests passed!` (both predicted unchanged; neither was edited) |
| `gateway.sh test test/nutrition_test.dart` | `+94: All tests passed!` |
| `gateway.sh test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` | `+54: All tests passed!` |
| `gateway.sh lint` | `180 issues found.` — 0 errors, equal to the 180 baseline; none in a file this run touched |
| `gateway.sh test` (full suite) | `03:42 +5877 ~2: All tests passed!` (5877 passed, 2 skipped, 0 failed; Phase 1 was `+5873 ~2`, the +4 being the new `edit_food_save_test.dart`) |
| invariant grep `import .*hive_workout_repository` over `lib/` | only `lib/main.dart` (the composition root) — none in `lib/state`, `lib/features`, `lib/widgets`, `lib/core` |

## What changed

- `lib/features/nutrition/edit_food_screen.dart` (+ guard, + CTA): class doc
  comment rewritten to the Save/guard contract; `_formKey` +
  `FoodFormUnsavedProbe(initialImagePath: widget.food.imagePath)`; `initState`
  post-frame `record()`; `dispose` → `_probe.dispose()` then
  `_formController.detach()`; `_attemptExit()` (clean form pops, dirty form asks
  via `ConfirmationDialog.showUnsavedChanges` with keys
  `edit-food-unsaved-keep`/`edit-food-unsaved-discard`); `build` wrapped in
  `PopScope(canPop: false)`, body `Column[Expanded(NotificationListener<
  ScrollNotification> re-baselining on `ScrollEndNotification` → `FoodForm`),
  the existing Reset/Delete `SafeArea` block]`; `bottomNavigationBar:
  OmniBottomCTA(label: 'Save', buttonKey: Key('food_form_save'))`. The removed
  args are `autoSaveOnBlur`, `skipPopOnSave` and `onImageSave`; the form now
  gets `onImageChanged: _probe.markImageChanged`.
- `lib/features/nutrition/widgets/food_form.dart` (25 insertions, 136
  deletions): `onImageSave`, `autoSaveOnBlur`, `_focusNode`, its listener, its
  `dispose` lines, `_onFocusChange`, `_partialDraftFromInitial` and the
  `Focus(...)` wrapper gone; `handlePickedImage` ends at
  `onImageChanged(persistedPath)` and `clearImage` at `onImageChanged(null)`,
  both documented as form-local until Save with the D-7 delete owned by state.
- `test/food_form_pick_saves_test.dart`: rewritten to the "waits for Save" rule
  (groups S-92a.5 and S-92a.6, tests 2-6 of the plan's table).
- `test/library_row_toggle_test.dart`: S-12719 renamed and its `onImageSave` leg
  deleted (table row 7); the `onSave` leg kept.
- `test/edit_food_save_test.dart` (new): S-92a.1-S-92a.4.

## Diff footprint

`git-diff --stat` for this run's files: `edit_food_screen.dart` 167 (mostly the
re-indent of the body under `PopScope` plus the new guard/CTA code),
`food_form.dart` 161 (25 insertions, 136 deletions — the machinery removal),
`food_form_pick_saves_test.dart` 414 (five rewritten tests),
`library_row_toggle_test.dart` 23, plus the new untracked
`test/edit_food_save_test.dart`. No doc file was edited: Phase 3 owns
`docs/nutrition.md`, `docs/widget_catalog/nutrition_widgets.md`,
`docs/design_system.md`, `docs/navigation_and_screens.md` and
`docs/state_management/nutrition_state.md`. The hands-off watch/session files
and `add_food_screen.dart` were not touched by this run.

# Phase 2 Part B — edge scenarios (tests only, no production change)

Date: 2026-10-29. Base: `e41a4c10` (Phase 1 + Phase 2 Part A). Worktree files this
run: `test/edit_food_save_test.dart` only, plus this evidence file and the plan's
Progress/Assumption Log.

## Scenario → test map (all in `test/edit_food_save_test.dart`)

| S-id | Test name | Fixture |
|---|---|---|
| S-92a.7 | `S-92a.7: a bundled food's library copy saves through editLibraryFood` | `chicken_breast` seeded + `addCatalogFoodToLibrary` + `editLibraryFood` name change |
| S-92a.9 | `S-92a.9: Reset and Delete remain above Save` | differing library copy (Reset) and a user-created catalog food with a `NutritionState` (Delete); `getTopLeft(...).dy` compared with `food_form_save` |
| S-92a.11 | `S-92a.11: Save with an empty name writes nothing and stays open` | `_trailMix`; name cleared to `''` |
| S-92a.12 | `S-92a.12: a second Save while saving writes once` | `_CountingCatalogRepo` (counts `updateCatalogFood`); two `controller.submit()` calls with no pump |
| S-92a.13 | `S-92a.13: an orphan category survives Save` | `_orphanSnack` with `groupId: 'g-gone'` (no such catalog group) |
| S-92a.14 | `S-92a.14: system back routes through the guard` | `_trailMix`, name typed, `handlePopRoute()` |
| S-92a.15 | `S-92a.15: Reset pops through unsaved edits with no dialog` | differing copy + typed edit, then `food-reset-confirm` |
| S-92a.16 | `S-92a.16: Delete pops through unsaved edits with no dialog` | user-created food + typed edit, then `food-delete-confirm` |
| S-92a.17 | `S-92a.17: a failed save keeps the form and the guard` | `_FailingCatalogRepo` (throws from `updateCatalogFood`) |
| S-92a.18 | `S-92a.18: Save pops without the guard` | `_trailMix`, name typed, Save |

## Red proof: mutation, not `prove-red`

`prove-red HEAD` cannot prove these tests: the guarded behaviour shipped in
`e41a4c10`, so the code and the tests are on the same side of HEAD and the new
tests do not exist in HEAD's test file at all. Each guard was therefore proven by
mutating the production line it protects — original recorded, mutated, target test
observed red, original restored verbatim, file re-run green.

| # | File | Original (restored verbatim) | Mutation | Verdict |
|---|---|---|---|---|
| a | `lib/features/nutrition/edit_food_screen.dart` | `showNotesField: true,` in the hosted `FoodForm` (no `skipPopOnSave`) | inserted `skipPopOnSave: true,` | S-92a.18 RED — `Expected: no matching candidates / Actual: Found 1 widget with type "EditFoodScreen"` (test line 727) |
| b | same | `if (didPop) return;` + `_attemptExit();` inside `onPopInvokedWithResult` | body replaced by `return;` | S-92a.14 RED — `Found 0 widgets with text "Unsaved changes"` (line 567) |
| c | `lib/features/nutrition/widgets/food_form.dart` | `return 'Name is required';` | line deleted (if-body left empty) | S-92a.11 RED — `Found 0 widgets with text "Name is required"` (line 470) |
| d | `lib/features/nutrition/edit_food_screen.dart` | `catch (_) {` / `return false;` in `_save` | `return true;` | S-92a.17 RED — `Found 0 widgets with text "Could not save food"` (line 686) |
| e | same | `Navigator.of(context).pop();` at the end of `_onReset` | `await _attemptExit();` | S-92a.15 RED — `Found 1 widget with text "Unsaved changes"` where none expected (line 611) |

After every restore `git-diff --stat -- lib` showed only the four pre-existing
hands-off files (`session_summary_screen.dart`, `watch_session_adoption_bridge.dart`,
`session_core_entry.dart`, `workout_state.dart`); neither mutated file appeared.
Residue: `grep -r MUTANT` hits only `docs/plans/**` and
`.claude/commands/feature.md`, nothing in `lib/` or `test/`.

## Green runs

| Run | Result |
|---|---|
| `gateway.sh test test/edit_food_save_test.dart` | `+14: All tests passed!` (S-92a.1-4 from Part A plus the ten above) |
| `gateway.sh test test/edit_food_save_test.dart --plain-name S-92a.13` | `+1: All tests passed!` (after the import cleanup) |
| `gateway.sh test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` | `+54: All tests passed!` |
| `gateway.sh lint` | **180 issues, 0 errors** — equal to the baseline. The first run reported 181: `unnecessary_import` for `core/models/food_draft.dart` in the new test (`food_form.dart` re-exports it); the import was removed and no other issue appeared. |
| `gateway.sh test` (full suite) | `+5887 ~2: All tests passed!` — 5887 against the Part A baseline 5877, the ten new tests. |

## Diff footprint

`git-diff --stat -- test/edit_food_save_test.dart`: 490 insertions, 6 deletions
against `e41a4c10` — nine new `testWidgets`, the `_openEditorFor` / `_seedCatalog` /
`_tapSave` / `_typeName` / `_draftOf` helpers they share, the `_orphanSnack` and
`_seedEditedLibraryCopy` fixtures, and the counting/failing repository subclasses.
No `lib/` file is modified by this part.

---

# Phase 3 — docs (developer)

Date: 2026-10-29. Base: the Phase 2B commit. Worktree files this run: the five
docs below, this plan (`> Status:` line, `## Progress`, `## Assumption Log`), and
this evidence file. No `lib/`, `test/` or app file was written.

## What changed, per doc

| Doc | Edit |
|---|---|
| `docs/widget_catalog/nutrition_widgets.md` | `FoodForm` props paragraph loses `onImageSave` and states `onImageChanged` is `ValueChanged<String?>` (form-local path, null after a clear); the "EditFoodScreen is the exception" paragraph became "every host owns a bottom `Save` (`food_form_save`)", naming New Food's label test; the `onImageSave` contract bullet became "nothing writes until Save … the state method owns the D-7 delete", citing `test/food_photo_clear_legacy_edit_test.dart` and the two `test/food_form_pick_saves_test.dart` groups; the `onImageChanged` bullet now covers all three hosts marking a probe (S-2902 tests kept, cross-referenced); the select-all bullet loses the form-level `FocusNode`/`autoSaveOnBlur` sentence; the test-seam paragraph states neither seam saves; the internal S-12719 quote loses `(onSave and onImageSave)`; a new `### FoodFormUnsavedProbe` entry lists `lib/features/nutrition/widgets/food_form_unsaved_probe.dart` |
| `docs/nutrition.md` | guard paragraph now covers three hosts with the three key pairs and says Save pops without the guard (New Food reads `Save`), citing `test/nutrition_test.dart` S-2902 groups and `test/edit_food_save_test.dart` S-92a.3 / S-92a.18; `### EditFoodScreen` gains the Save + guard + Reset/Delete-bypass paragraph (S-92a.1/3/4/15/16/18) and a photo-on-Save paragraph replacing the false "the file on disk is left intact" claim (D-7, `test/food_photo_clear_legacy_edit_test.dart`); the S-12719 quote loses `(onSave and onImageSave)` |
| `docs/design_system.md` | "Unsaved work": the live session is the one named exception; the food editors are explicitly not, Edit Food included, with `test/edit_food_save_test.dart` `S-92a.3` added to the verified-by list |
| `docs/navigation_and_screens.md` | `EditFoodScreen` row: Save + guard + photo-on-Save, the S-12719 quote without `(onSave and onImageSave)`, and `test/edit_food_save_test.dart` S-92a.3 / S-92a.18 added |
| `docs/state_management/nutrition_state.md` | the `editLibraryFood` table row and the pencil bullet: S-12719 quoted without `(onSave and onImageSave)` |

## Residue sweep

`grep -rn "autoSaveOnBlur\|onImageSave\|save on blur\|saves on blur\|no Save button" docs`
returns **7 files, all under `docs/plans/`** — zero hits outside `docs/plans/`
and `docs/history/`:

- `docs/plans/2026-10-13-27-ui-messages-plan/2026-10-13-27-ui-messages-plan.review.md`
- `docs/plans/2026-10-29-92-food-form-rework-plan/2026-10-29-92-food-form-rework-plan.md`
- `docs/plans/2026-10-29-92a-edit-food-save-plan/2026-10-29-92a-edit-food-save-plan.md` (its own D-92a.2/3/6 text, historical by design)
- `docs/plans/2026-10-29-92a-edit-food-save-plan/2026-10-29-92a-edit-food-save-plan.evidence.md`
- `docs/plans/food-library-edit-image-plan.md`
- `docs/plans/food-form-decimals-and-autofocus-plan.md`
- `docs/plans/2026-10-12-25-ui-standards-refresh-plan/survey/s8-area-nutrition.md`

Symbols the edited sentences name, each confirmed present: `test/edit_food_save_test.dart` (S-92a.1/3/4/15/16/18 names read from the file),
`test/food_photo_clear_legacy_edit_test.dart` (`clearing a legacy library food's
photo waits for the Save tap`), `test/food_form_pick_saves_test.dart` (groups
`FoodForm: a picked photo waits for Save (S-92a.5)` / `FoodForm: a cleared photo
waits for Save (S-92a.6)`), `test/nutrition_test.dart` (groups
`AddFoodScreen — New Food form unsaved guard (S-2902)`,
`AddFoodScreen — legacy edit shim unsaved guard (S-2902)`,
`AddFoodScreen — + New Item (S-004 / S-005)` · "the New Food bottom bar says
Save, not Create (S-92a.10)"), `test/library_row_toggle_test.dart` (S-12719 as
renamed), `lib/features/nutrition/widgets/food_form_unsaved_probe.dart` /
`FoodFormUnsavedProbe`, and the keys `food_form_save`,
`new-food-unsaved-*`, `legacy-food-unsaved-*`, `edit-food-unsaved-*`.

## Checks (this phase)

| Run | Result |
|---|---|
| `gateway.sh test test/docs_indexing_contract_test.dart` | `+13: All tests passed!` — no file landed in the 52 KiB warning band, so nothing needed splitting |
| `gateway.sh test test/ui_standards_contract_test.dart` | `+41: All tests passed!` |
| `gateway.sh lint` | **180 issues, 0 errors** — equal to the baseline; docs-only change |
| `gateway.sh test` (full suite) | `+5887 ~2: All tests passed!` — identical to the Phase 2B baseline, as expected for a docs-only change |

## Diff footprint

`git-diff --stat` over the six touched paths: `docs/widget_catalog/nutrition_widgets.md`
(94 changed lines), `docs/nutrition.md` (52), `docs/design_system.md` (11),
`docs/navigation_and_screens.md` (2), `docs/state_management/nutrition_state.md`
(4), the plan (19), plus this evidence file (68 added) — 187 insertions,
63 deletions in total. The other files in the
worktree-wide stat are the other unit's pre-existing hands-off work, untouched by
this run.

## Not fixed (out of this phase's hands)

- `lib/state/food_library_state.dart:1018` — `// The edit screen auto-saves repeatedly with the snapshot it was opened with`: the conclusion (use the cached row) still holds, the rationale is stale. Code, not docs.
- `lib/features/nutrition/add_food_screen.dart:1488` — `/// Used to maintain focus after auto-save.` in `_GroupsTabState`: still accurate (group rename saves on blur), left alone.

