# Review: 92a edit-food-save (round 1)

Reviewer: code-reviewer (Copilot CLI edition)
Base: `1b9bfb405168f9c629952802dfa4fd27f2aeb516` → HEAD
Layers in scope: features (nutrition), widgets (probe). Skipped: models, persistence, state, core (no in-scope changes).
Hands-off files (session summary, watch bridge, workout state, watch tests, `scripts/*.sh`) excluded per brief.

## Diff vs Predicted Files

Conforms. Production: the four predicted `lib/features/nutrition/` files only. Tests: the five predicted files. Docs: the five predicted docs plus the plan/evidence files. `test/library_merge_test.dart` and `test/screen_widget_test.dart` untouched as predicted.

## Acceptance criteria (AC-1..7) — all verified in code

- AC-1 PASS — `edit_food_screen.dart:262-267` bottom `OmniBottomCTA('Save', food_form_save)` → `_formController.submit`; `_save` branches `updateCatalogFood` / `editLibraryFood` (`edit_food_screen.dart:96-108`); S-92a.1/S-92a.7 prove both routes.
- AC-2 PASS — `autoSaveOnBlur`/`_focusNode`/`_onFocusChange` gone from `food_form.dart` (diff −136/+25); grep `onImageSave|autoSaveOnBlur` over `lib/` → 0 hits; S-92a.2 red at base ('Trail Mix 2' written on blur) proves the old behaviour.
- AC-3 PASS — `handlePickedImage`/`clearImage` now only set the local path and report it (`food_form.dart` diff); the shim's `onImageSave` block deleted (`add_food_screen.dart` diff); D-7 delete asserted *after* Save in `test/food_form_pick_saves_test.dart` ('replaces the previous managed file') and `test/food_photo_clear_legacy_edit_test.dart` leg 3; Discard legs assert stored path + file untouched.
- AC-4 PASS — `PopScope(canPop: false)` → `_attemptExit` (`edit_food_screen.dart:216-243`); header back (S-92a.3 `pageBack`) and system back (S-92a.14 `handlePopRoute`) both covered; untouched form closes silently (S-92a.4, green at base as designed).
- AC-5 PASS — Reset/Delete block kept verbatim inside the body column above the CTA; S-92a.9 asserts both keys and their position above `food_form_save`; S-92a.15/S-92a.16 prove the direct pop bypasses the guard.
- AC-6 PASS — `_NewFoodFormScreen` CTA and `saveLabel` both `Save`, key unchanged (`add_food_screen.dart:819,864`); S-92a.10 asserts the label and that creation still writes.
- AC-7 PASS — all seven rows of the plan's "Tests rewritten" table match the observed renames; no test asserting save-on-pick/save-on-blur remains.

## Brief focus items

1. No remaining write-on-blur/pick/clear path in `lib/`: grep clean; exactly three `FoodForm(` hosts, all probe-wired, none passing the removed parameters.
2. Probe dirty rule walked: photo A → pick B → clear ⇒ dirty (null ≠ A); no photo → pick → clear ⇒ clean (null == null); photo A → clear ⇒ dirty. "Clean again by re-picking the same path" is unreachable: `persistPickedImage` names every copy `<uuid-v4>.<ext>` (`image_storage_service_io.dart:170-186`), so a re-pick can never reproduce `initialImagePath` — the rule cannot be fooled into dropping a real change.
3. No worse leak than the accepted D-92a.9 orphan: pick/clear never delete; the state layer's four `deleteIfManaged` sites are intact (`food_library_state.dart:950,1027,1104,1365`); Discard of an Edit leaves the stored file alone (leg 2 of the legacy test). Note: pick B then pick C before Save orphans B too — same accepted class, listed below for the owner.
4. Save is a real `tester.tap` on `food_form_save` in S-92a.1/11/17/18 and `_tapSave`; back covered via header (`pageBack`, S-92a.3/4/15/17) and system (`handlePopRoute`, S-92a.14).
5. Test-name comparison base vs HEAD: every removed name is a documented rename (table rows 1-7); `library_merge_test.dart` and `screen_widget_test.dart` untouched and green (+248).
6. UI standards: `git-diff 1b9bfb40 -- test/helpers` is empty (no allowlist entry, no ratchet raise); no raw `Card`/`SnackBar`/bare `IconButton`/colour literal introduced by any changed `lib` hunk; the new `OutlinedButton` carries an explicit `shape` from `OmniTheme.buttonBorderRadius` and `theme.colorScheme` colours.
7. Docs: residue grep `autoSaveOnBlur|onImageSave` over `docs/` → hits only under `docs/plans/` (7 files, all historical by design). Every test name, group, key, type and file the five docs name exists (S-92a.1/3/4/15/16/18, S-92a.10 test, S-92a.5/S-92a.6 groups, `edit-food-unsaved-*`, `food_form_save`, `FoodFormUnsavedProbe`, `ValueChanged<String?>`).
8. No missed caller: `FoodForm(` has exactly three hosts; both `EditFoodScreen.push` sites (`add_food_screen.dart:1139,1468`) route through the guarded screen — no flow reaches Edit Food without the guard.

## Findings

- 🟡 minor | `lib/state/food_library_state.dart:1018` | comment "The edit screen auto-saves repeatedly with the snapshot it was opened with" is now false — this unit removed auto-save (A-92a.P3.3 left it for the owner) | one-line comment fix: the cached row is still the right source; reword the rationale | @developer
- 💡 minor | `test/food_photo_clear_legacy_edit_test.dart:131,148` | `///` doc comments on local closures inside a test body; `//` is the norm for in-test commentary | cosmetic; convert or leave | @developer
- 💡 note (accepted class, for the owner) | `lib/features/nutrition/widgets/food_form.dart` (`handlePickedImage`) | pick B then pick C before Save orphans B as well as the accepted D-92a.9 orphan; Save deletes only the stored file | same accepted leak class as D-92a.9; candidate for a later cleanup unit | owner

## Test run verification

- Handoff evidence contains pasted counts (not claims): full suite `+5887 ~2`, contract pair `+54`, lint `180 issues / 0 errors`.
- My own runs: full `gateway.sh test` → **5887 passed, 2 skipped, 0 failed**; `gateway.sh lint` → **180 issues, 0 errors** (baseline equal); contract pair → **+54 All tests passed**.
- Prove-red spot-checks (mine, both RED AT base for the guarded reason):
  - `prove-red 1b9bfb40 test test/edit_food_save_test.dart` → 12 failures: no `food_form_save`, blur wrote 'Trail Mix 2', no 'Unsaved changes' dialog — exactly the behaviours the guards pin (S-92a.4/S-92a.16 green at base as designed structural guards).
  - `prove-red 1b9bfb40 test test/food_photo_clear_legacy_edit_test.dart` → 'the managed file must survive an unwritten clear' (the shim deleted on clear at base).
- Evidence file additionally documents 5 mutation proofs (Part B) and 2 (Part A) with verbatim restores; sampled and consistent with the code.

## DOC FALSIFICATION

✅ PASS (5 implicated) — `widget_catalog/nutrition_widgets.md`, `nutrition.md`, `design_system.md`, `navigation_and_screens.md`, `state_management/nutrition_state.md`. The false "the file on disk is left intact" claim was replaced with the D-7 truth and a test pointer. No doc made false by this change; no conflicts found.

## DOC STANDARD

✅ PASS — no prohibited content added; behavioural prose points at named tests.

## IMPACT

✅ PASS (6 rows checked, 0 unlisted readers) — push sites, test readers and doc readers match the plan's table; the two predicted-unchanged test files pass untouched.

## Conventions

PASS (applicable): shared-piece usage, button shape/colour tokens, no raw pieces, no allowlist/ratchet change, residue sweep, test-pointer doc style.
N/A (grouped): watch contract, repository parity (no repo/model change), serving fields (out of scope).

## Assumption Log adjudication

- A-92a.P1.1, P1.2, P1.3, P2.1, P2.2, P2.3, P2.4, P2.5, P3.1, P3.2 — RATIFY (each consistent with the recorded decisions; P1.2's bounded poll and P2.4's `UniqueKey` are the right calls).
- A-92a.P3.3 — RATIFY as recorded, and promoted above as the one follow-up item (stale comment at `food_library_state.dart:1018`).

## Verdict

Critical: 0 | Warnings: 1 (stale comment, one line) | Suggestions: 2
