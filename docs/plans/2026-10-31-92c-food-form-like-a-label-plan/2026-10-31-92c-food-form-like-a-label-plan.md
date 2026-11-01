# Feature: 92c — the food form reads like a nutrition label

> Status: PLANNED — the planner's expansion is appended below (Iteration 1); the governor's seed above is kept verbatim. Next handoff: @developer (Phase 1). Series: `docs/plans/2026-10-29-92-food-form-rework-plan/` (92c of 92a/92b/92c; 92a and 92b are committed, last commit `3ed09c3f`). Base: `3ed09c3f` on `claude_develop`.
> Binding conventions: `docs/global_conventions.md`, `docs/design_system.md`, `.github/copilot/pr-scope-budget.md`. Never create or switch branches; git belongs to the governor.
> Hands off (another unit's uncommitted work): `docs/session_summary.md`, `docs/state_management/workout_state.md`, `lib/features/session/session_summary_screen.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/state/workout/session_core_entry.dart`, `lib/state/workout/workout_state.dart`, `test/watch_live_refresh_screen_test.dart`, `test/watch_routine_adoption_test.dart`, `test/watch_session_merge_test.dart`, `scripts/*.sh`.
> Owner-approved defaults (series plan V-1..V-3, approved 2026-10-29): calories read "= N cal" and are derived, not typeable; macro order follows a package label in create and edit; blank Protein/Carbs/Fat save as 0, blank Fiber/Sodium save as "not recorded". Owner decision D-92.3: a duplicate name shows a quiet note and never blocks. Category is NOT touched (D-92.2).

## Goal

The food form (`FoodForm`, hosted by New Food, Edit Food and the legacy edit screen) stops looking like a database form: it shows the calories the macros add up to, asks for the macros in the order a package prints them, starts with empty boxes instead of "0.0", shows whole numbers as "31" not "31.0", puts the optional photo below the name instead of above it, and tells the user when the name already exists. The stored model does not change.

## What the user sees

| | Now | After |
|---|---|---|
| Calories | derived, never shown | a live line "= 220 cal" under the macros |
| Macro order | Protein, Carbs, Fiber, Fat, Sodium | Fat, Carbs, Fiber, Protein, Sodium |
| New food boxes | every macro box shows "0.0" | empty boxes with a faint "0" |
| Edit boxes | "31.0", and "0.0" for a fiber that was never recorded | "31"; a never-recorded fiber/sodium stays empty |
| Blank Protein/Carbs/Fat | "Required" | saved as 0 |
| Blank Fiber/Sodium | a new food saves 0 | saved as "not recorded" (null) |
| Photo | the tile is the first thing in the form | the tile sits directly below the name |
| Duplicate name | silent | a quiet note under the name; Save still works |

## Acceptance criteria

- AC-1 A live line `food_form_calories` reads `= N cal` with N equal to `calculateCalories` of the same values (protein*4 + carbs*4 + fat*9, rounded); blank or unparsable boxes count as 0; fiber and sodium never change it.
- AC-2 The macro fields appear top to bottom: `food_form_fat`, `food_form_carbs`, `food_form_fiber`, `food_form_protein`, `food_form_sodium` (keys and labels unchanged: `Fat (g)`, `Carbs (g)`, `Fiber (g)`, `Protein (g)`, `Sodium (mg)`).
- AC-3 A new food opens with all five macro boxes empty and a faint `0` visible in each without focusing it.
- AC-4 Edit mode prefills with `formatGrams` (`31`, `3.6`); a stored-null fiber or sodium opens empty and saves null unless typed into.
- AC-5 Blank Protein/Carbs/Fat save 0.0; blank Fiber/Sodium save null; text that is not a number (a lone `.`) still shows `Must be a number` and blocks Save.
- AC-6 `food_form_image_tile` sits below `food_form_name` and above `food_form_group`.
- AC-7 `food_form_duplicate_note` shows `There's already a food called "<name>" in the Library` while the trimmed name equals (case-insensitive) a non-archived food of the Library other than the one being edited; it never blocks Save.
- AC-8 No new allowlist entry or ratchet raise; `test/ui_standards_contract_test.dart` and `test/docs_indexing_contract_test.dart` stay green.

## Decision Ledger

- **D-92c.1 Calories are computed in one place.** `lib/core/utils/food_helpers.dart` `calculateCalories(Food)` (~L11) is the rule `(protein*4 + carbs*4 + fat*9).round()`. Add `int caloriesFromMacros({required double protein, required double carbs, required double fat})` there and make `calculateCalories` call it. The form's line calls `caloriesFromMacros` with the parsed boxes (`double.tryParse(text.trim()) ?? 0`). The line text is `= <N> cal`, key `food_form_calories`, style as the heading (`bodySmall`, `OmniTheme.colors.textSecondary`), placed directly under the last macro field (Sodium) and above Notes. Fiber is not subtracted (V-1).
- **D-92c.2 Order.** In `food_form.dart` `build` (the `_macroField` calls, ~L766-805) reorder to Fat, Carbs, Fiber, Protein, Sodium. Keys, labels, focus nodes and controllers are unchanged; only the order changes. One order for create and edit.
- **D-92c.3 Blank boxes and the faint 0.** The five macro controllers start empty for a new food (today `(initial?.protein ?? 0.0).toString()` etc. in `initState`, ~L260-275). Each macro field shows `hintText: '0'` with `floatingLabelBehavior: FloatingLabelBehavior.always` so the hint is visible without focus (Material hides a hint while a label sits inside the box). Select-all-on-focus stays.
- **D-92c.4 Prefill.** Edit mode: `initial.protein/carbs/fat` through `formatGrams` (`lib/core/utils/food_helpers.dart` ~L45); `initial.fiber` and `initial.sodium` through `formatGrams` only when non-null, else empty (today `initial?.fiber ?? 0.0` writes 0.0 over an unrecorded value on any save).
- **D-92c.5 Saving blanks.** `_onSave` draft: protein/carbs/fat = `double.tryParse(text.trim()) ?? 0.0` after validation; fiber/sodium = null when empty (existing `fiberRaw.isEmpty ? null : ...`, ~L405-415), else parsed. The macro validator no longer returns `Required`; it returns `Must be a number` only when the trimmed text is non-empty and `double.tryParse` fails (a lone `.`); the `required` parameter of `_macroField` is removed. The existing test `test/food_form_decimals_and_autofocus_test.dart` ~L300-341 expects `Required` after typing `abc` into carbs (filtered to empty): it is rewritten to type `.` and expect `Must be a number`.
- **D-92c.6 Photo position.** Move `FoodFormImageTile` (`food_form.dart` build, first child of the `ListView`, ~L606) to directly after the name `TextFormField`, before the Category dropdown. No change to its behaviour or keys.
- **D-92c.7 Duplicate note, one rule in the state layer.** Add `bool nameExistsInLibrary(String name, {Food? excluding})` to `FoodLibraryState` (`lib/state/food_library_state.dart`, near `libraryIdFor`): true when any food in `catalogFoods` or `foods` that is not archived has a name equal to `name` after `trim()` and lower-casing, ignoring `excluding` and its twins (when `excluding` is a library copy, the catalog row with its `catalogId`; when it is a catalog row, the library copies whose `catalogId` equals its id). An empty/blank `name` is false. The form shows the note while that is true for the live name text; key `food_form_duplicate_note`; text `There's already a food called "<trimmed name>" in the Library`; `bodySmall`, `OmniTheme.colors.textSecondary`; placed under the name field. It listens to the name controller (rebuild on typing). Never blocks Save, never changes validation. `_matchesIdentity` (name + all values) is NOT reused: it needs every value to match.
- **D-92c.8 Out of scope.** Category default (D-92.2), the serving control (92b), the New Food double pop, any stored field, the watch.

## Core scenarios (each fails on the base for the reason given)

- **S-92c.1 Calories line.** New Food in `FoodForm`: protein 10, carbs 18, fat 12 gives `= 220 cal`; clearing fat gives `= 112 cal`; a lone `.` in carbs counts 0; filling fiber 5 and sodium 300 changes nothing; the same values through `calculateCalories(Food(...))` give 220. Red: no `food_form_calories`.
- **S-92c.2 Order.** `tester.getTopLeft(...).dy` of the five fields is strictly increasing in the order fat, carbs, fiber, protein, sodium. Red: base order is protein, carbs, fiber, fat, sodium.
- **S-92c.3 Blank boxes with a faint 0.** New Food: the five controllers are empty, no `0.0` text, and a hint `0` is visible five times without focusing anything (`find.text('0')` finds 5 widgets). Red: base shows `0.0`.
- **S-92c.4 Blank save.** New Food with only a name, tap save: draft protein/carbs/fat are 0.0 and fiber/sodium are null. Red: base blocks with `Required` (and would store 0.0 fiber/sodium).
- **S-92c.5 Edit prefill.** Seed a food protein 31.0, carbs 0.0, fat 3.6, fiber null, sodium 74.0; open edit: boxes read `31`, `0`, `3.6`, empty, `74`; Save untouched stores protein 31.0, carbs 0.0, fat 3.6, fiber null, sodium 74.0. A food with fiber 0.0 stored shows `0` and keeps 0.0. Red: base shows `31.0`, `0.0` for the null fiber and saves 0.0.
- **S-92c.6 Non-number blocks.** A lone `.` in fat then Save: `Must be a number`, `onSave` not called. Red-independent guard (the base also rejects it).
- **S-92c.7 Photo below name.** `dy` of name < photo tile < category dropdown. Red: the tile is first.
- **S-92c.8 Duplicate note.** Library has a catalog food `Chicken breast, skinless` (the shipped seed): typing ` chicken breast, skinless ` in a New Food shows the note with the trimmed text as typed; `Chicken` shows none; Save still creates the food. Edit a user-created food `My Bar`: its own name shows none; renaming it to `Oats, rolled` (an existing food) shows the note. Edit a library copy of a bundled food: its own name shows none. Red: no note.
- **S-92c.9 State helper.** `nameExistsInLibrary`: true for a catalog food, for a library-only food, false for an archived one, false for `excluding` itself and its catalog/library twin, false for blank text. Red: method absent (compile failure; proof by mutation).

## Phase outline (one developer run each; at most 8 items per phase)

- **Phase 1 (developer) — the two rules.** `caloriesFromMacros` + `calculateCalories` refactor (`food_helpers.dart`) with unit tests; `nameExistsInLibrary` (`food_library_state.dart`) with S-92c.9 in the closest existing state test file (`test/food_library_state_test.dart`).
- **Phase 2A (developer) — the boxes.** `food_form.dart`: blank/hint (D-92c.3), prefill (D-92c.4), saving blanks and the validator (D-92c.5), order (D-92c.2); tests S-92c.2-6 in a new `test/food_form_label_test.dart`; rewrite the `abc` test (D-92c.5) and any other test the blank boxes break (grep `Required`, `0.0`, select-all tests in `test/food_form_decimals_and_autofocus_test.dart`).
- **Phase 2B (developer) — calories, photo, duplicate note.** `food_form.dart`: the calories line (D-92c.1), photo position (D-92c.6), duplicate note (D-92c.7); tests S-92c.1, S-92c.7, S-92c.8 in the same new file; run the whole suite once.
- **Phase 3 (developer) — docs.** `docs/widget_catalog/nutrition_widgets.md` (`FoodForm`: order, blank boxes, calories line, photo position, duplicate note, keys), `docs/nutrition.md` if it describes the form; the series plan's 92c status; this plan's status.

## Code pointers

`lib/features/nutrition/widgets/food_form.dart`: controller seeding in `initState` (~L260-275), `_onSave` draft (~L400-425), `build`: image tile (~L606), name field (~L630-645), the five `_macroField(...)` calls (~L766-805), `_macroField` (~L843-880) · `lib/core/utils/food_helpers.dart` `calculateCalories` (~L11), `formatGrams` (~L45) · `lib/state/food_library_state.dart` `foods` (L96), `catalogFoods` (L101), `libraryIdFor`, `isBundledCatalogFood` (~L1636) · tests: `test/food_form_decimals_and_autofocus_test.dart` (~L300-341 the `Required` expectation; select-all tests that tap a prefilled field), `test/food_form_serving_test.dart` (fixtures to reuse; its line ~397 `Required` expectation concerns the serving label, not macros).

## Readers of what changes

`FoodForm` is built in `edit_food_screen.dart` and `add_food_screen.dart` (two hosts). Tests that pump `FoodForm` or the hosts and read macro boxes or `Required`: `food_form_decimals_and_autofocus_test.dart`, `edit_food_save_test.dart`, `food_form_orphan_category_test.dart`, `food_form_pick_saves_test.dart`, `nutrition_test.dart`, `food_form_serving_test.dart`, `library_row_toggle_test.dart`, `library_merge_test.dart`, `screen_widget_test.dart`.

---

## Planner expansion (Iteration 1)

Appended by the planner (conductor-v2) on base `3ed09c3f`. Everything above the `---` is the governor's seed, kept verbatim. New entries continue the seed's numbering (D-92c.9+, S-92c.10+). Research baselines, grep results and prove-red rationale live in `2026-10-31-92c-food-form-like-a-label-plan.evidence.md` (same folder) — the plan states conclusions, the evidence file holds the raw counts.

### Appended decisions (Ledger)

- **D-92c.9 Order under the name (derived — vetoable).** The seed's D-92c.6 ("tile directly after the name field") and D-92c.7 ("note under the name field") both claim the slot after the name. Pinned top-to-bottom: name field → `food_form_duplicate_note` (when present) → `food_form_image_tile` → Category dropdown. This satisfies AC-6 (tile below name, above group) and AC-7 (note under the name) simultaneously; the tile keeps its `SizedBox(height: 16)` spacing and the note its own `SizedBox(height: 4)`.
- **D-92c.10 The calories line is live (derived from D-92c.1).** `_macroField` gains `onChanged: (_) => setState(() {})` — the same mechanism the serving fields already use — so the line follows typing; the line's value is computed in `build` from the five controllers through `caloriesFromMacros` with `double.tryParse(text.trim()) ?? 0`. No new state, no listener beyond the rebuild.
- **D-92c.11 The duplicate note follows typing (derived from D-92c.7).** The note's visibility is evaluated in `build` from `_name.text` through `nameExistsInLibrary`; `_name` gets a listener that `setState`s, so the note appears and disappears while typing, including when the name is cleared (S-92c.11). The lookup runs on every rebuild — the same O(catalog + library) class as `libraryIdFor`'s documented cost, acceptable for the ~170-row catalog.
- **D-92c.12 Rounding is `.round()` — half away from zero (restating D-92c.1's math for the fractional case).** `caloriesFromMacros` returns `(protein*4 + carbs*4 + fat*9).round()`; 0.5 g fat alone gives 4.5 → 5. The form's line and every `calculateCalories` reader (Library rows, log rows, watch sync) share the one function, so a fractional-macro food shows the same calories everywhere (S-92c.13).
- **D-92c.13 Twin exclusion is catalogId-based only (derived from D-92c.7 — vetoable).** `nameExistsInLibrary` skips `excluding` and the rows linked to it by `catalogId` (a library copy's catalog row; a catalog row's library copies). A legacy library row with no `catalogId` whose name equals a catalog food's name is a separate row and DOES trigger the note — `_matchesIdentity` (name + all values) is never consulted, because D-92c.7 forbids reusing it and name-only matching is the point.
- **D-92c.14 The always-on label is macro-only (derived from D-92c.3).** `floatingLabelBehavior: FloatingLabelBehavior.always` and `hintText: '0'` go on the five macro fields only. `food_form_name`, `food_form_group`, `food_form_notes`, the serving fields and the package field keep today's decoration (S-92c.16 guards it).

### Appended scenarios

- **S-92c.10 Duplicate note with a padded or different-case name.**
  - Fixture: the shipped catalog (loaded via `loadCatalogFoods`), no library foods; New Food.
  - Trigger: type ` chicken breast, skinless ` (spaces both sides) into `food_form_name`; then clear and type `CHICKEN BREAST, SKINLESS`.
  - Flow: D-92c.7 trims and lower-cases for the match; the note text shows the trimmed text as typed.
  - Expected outcome: the note shows both times, reading `There's already a food called "chicken breast, skinless" in the Library` (padded case) and `There's already a food called "CHICKEN BREAST, SKINLESS" in the Library` (upper case); Save still creates the food.
  - Edge case of: S-92c.8. Red at base (no note).
- **S-92c.11 The note disappears when the name is cleared.**
  - Fixture: S-92c.10's; ` chicken breast, skinless ` typed, note showing.
  - Trigger: clear `food_form_name` (empty), pump.
  - Flow: D-92c.7 — a blank name is false; D-92c.11 — the listener rebuilds.
  - Expected outcome: no `food_form_duplicate_note`; typing the name again brings it back.
  - Edge case of: S-92c.8. Red at base (no note).
- **S-92c.12 Two Library rows with the same name show one note.**
  - Fixture: the shipped catalog plus TWO user-created foods both named `My Bar` (seeded in the repo via `seedCatalogFood`/`addFood`); New Food.
  - Trigger: type `My Bar`.
  - Flow: D-92c.7 — the first match makes the predicate true; the note is one widget regardless of how many rows match.
  - Expected outcome: exactly one `food_form_duplicate_note` (`findsOneWidget`); Save still creates a third `My Bar`.
  - Edge case of: S-92c.8. Red at base (no note).
- **S-92c.13 Fractional macros: the line and the Library row agree.**
  - Fixture: New Food.
  - Trigger: name `Half-fat spread`, leave protein/carbs blank, type `0.5` into `food_form_fat`; read the line; save; open the Library list and find the food's row.
  - Flow: the line calls `caloriesFromMacros(protein: 0, carbs: 0, fat: 0.5)` = `(0.5*9).round()` = 5 (4.5 rounds half away from zero, D-92c.12); the row's `<cal> cal per ...` line calls `calculateCalories` on the same stored food (`add_food_screen.dart` ~L1213).
  - Expected outcome: the form shows `= 5 cal`; the Library row shows `5 cal per 100 g`; the two figures are equal because both surfaces read the one function.
  - Edge case of: S-92c.1. Red at base (no line).
- **S-92c.14 Stored 0.0 vs null for fiber and sodium in edit.**
  - Fixture: food A stored fiber 0.0, sodium 74.0; food B stored fiber null, sodium null (both otherwise identical, seeded in the repo).
  - Trigger: open each in edit; Save untouched; then on B type `74` into sodium and clear it again, Save.
  - Flow: D-92c.4 prefill; D-92c.5 save.
  - Expected outcome: A opens `0` / `74` and saves fiber 0.0 / sodium 74.0; B opens empty / empty and saves null / null; B's type-then-clear save stores sodium null (an empty box is "not recorded", not 0).
  - Edge case of: S-92c.5. Red at base (B opens showing `0.0` and saves 0.0).
- **S-92c.15 Select-all still selects the whole prefilled value.**
  - Fixture: a food stored fat 4.0 (protein 31, carbs 0), opened in edit.
  - Trigger: tap `food_form_fat`.
  - Flow: the select-all binding is unchanged (D-92c.3); the prefill is now `formatGrams` (D-92c.4).
  - Expected outcome: the box reads `4` (not `4.0`) and the selection spans the whole text (`baseOffset: 0, extentOffset: text.length`).
  - Edge case of: S-92c.5. Red at base on the text (`4.0`); the selection half passes at base — the scenario's red is the text assertion.
- **S-92c.16 The always-on macro label leaves the other fields alone.**
  - Fixture: New Food, nothing focused.
  - Trigger: pump and read the labels.
  - Flow: D-92c.14.
  - Expected outcome: the five macro labels (`Fat (g)`, `Carbs (g)`, `Fiber (g)`, `Protein (g)`, `Sodium (mg)`) are each visible without focusing anything, each box showing the faint `0` hint while empty and unfocused; `Name` and `Category` render exactly as at base (a source-level grep in the Phase 2B sweep confirms `floatingLabelBehavior` appears only in `_macroField`).
  - Edge case of: S-92c.3. Red at base (no hint).

### Feature Invariants

- Calories are computed in exactly one place: `caloriesFromMacros` in `lib/core/utils/food_helpers.dart`; `calculateCalories` delegates to it and every reader keeps its value (D-92c.1, S-92c.13).
- The macro boxes' text never feeds the stored model except through `double.tryParse` in `_onSave`; a blank P/C/F is 0.0 and a blank fiber/sodium is null (D-92c.5) — the "blank = unset" contract for fiber/sodium becomes reachable for the first time (V-3).
- The duplicate rule lives in `FoodLibraryState.nameExistsInLibrary` and is name-only; `_matchesIdentity` (name + all values) is never reused (D-92c.7).
- The form never writes on typing: the calories line and the duplicate note are render-only; nothing persists until Save (92a's invariant, untouched).
- Repository parity untouched: no repository or model code changes; `FoodLibraryState` gains one read-only predicate.

### Existing-Functionality Impact

| Touched surface | Existing readers (the grep that found them) | Effect of the change | Guarded by |
| --- | --- | --- | --- |
| `calculateCalories` | grep `calculateCalories` in `lib/` + `test/`: `log_food_row.dart:339`, `add_food_screen.dart:897` and `:1212`, `watch_reference_sync.dart:648`, `food_helpers.dart:11`; tests `library_row_toggle_test.dart:379,406`, `library_merge_test.dart:171`, `food_library_state_test.dart:1459-1575` (two unit tests + the `Food.calories` getter parity test) | The body moves into `caloriesFromMacros`; `calculateCalories` returns the same int for the same Food — every reader's value is unchanged | S-92c.1, S-92c.13; the existing unit tests stay green (Phase 1 Done Criteria) |
| Macro controllers + `_macroField` | the form's own `initState`/`build`/`_onSave`; tests typing into the keys: `nutrition_test.dart:1963-1967, 2096-2098`, `food_form_serving_test.dart:85-87, 305-309, 751-766`, `food_form_decimals_and_autofocus_test.dart:196, 269, 326, 392-404`; key-presence: `screen_widget_test.dart:9481-9483` | Blank start, `formatGrams` prefill, hint `0`, order, validator, `tryParse` save | S-92c.2..6, S-92c.14..16; Phase 2A Done Criteria |
| The `Required` macro-validator string | grep `Required` in `test/`: `food_form_decimals_and_autofocus_test.dart:286-341` (macros — REWRITTEN), `food_form_serving_test.dart:397` (the package amount's `_validatePositiveDouble` — unchanged), `utils_test.dart` / `watch_sensor_recording_test.dart` / `settings_sounds_test.dart` / `nutrition_data_audit_test.dart` (unrelated features) | The macro validator stops returning `Required`; `_validatePositiveDouble` keeps it | Phase 2A item 5; S-92c.6 |
| The `0.0` prefill text | grep `find.text('0.0')` in `test/`: `screen_widget_test.dart:1857`, `interaction_flow_test.dart:280`, `crown_control_tap_to_edit_test.dart:430`, `tap_to_edit_unification_test.dart:493` — all four are routine-setup / value-stepper screens, not `FoodForm` (contexts read); the only FoodForm prefill-text assertion is `food_form_decimals_and_autofocus_test.dart:399` (`'4.0'`) | Prefill becomes `formatGrams`; the one assertion changes `'4.0'` → `'4'` | Phase 2A item 6; S-92c.15 |
| `FoodFormImageTile` position | grep `food_form_image_tile` in `test/`: `screen_widget_test.dart:9221-9536` (findsOneWidget, position-agnostic); `food_form_shipped_photo_test.dart` taps the tile by key | The tile moves below the name; behaviour and keys unchanged | S-92c.7; Phase 2B Done Criteria |
| `FoodLibraryState` public API | `nameExistsInLibrary` is new; the nearest neighbours `libraryIdFor` (~L640) / `catalogIdFor` (~L668) / `_matchesIdentity` (~L705) keep their behaviour | One added read-only predicate; no existing method changes | S-92c.9; Phase 1 |
| `FoodDraft` / stored fields | `FoodDraft(` in `lib/state/` — unchanged | None (D-92c.8) | none needed |
| Hosts | `FoodForm(` in `lib/` → `edit_food_screen.dart`, `add_food_screen.dart` (two hosts, three builds) | Untouched | Phase 2B full suite |

### UI Standards Impact

- The two new text lines (`food_form_calories`, `food_form_duplicate_note`) use `theme.textTheme.bodySmall` + `OmniTheme.colors.textSecondary` — the exact style the `food_form_per_heading` / `food_form_per_note` lines already use in the same file (theme tokens only; no raw colour, so the S-2608 colour scan and the white/black ratchets are untouched).
- `hintText: '0'` + `FloatingLabelBehavior.always` are `InputDecoration` properties: no scan in `test/ui_standards_contract_test.dart` covers hints or label behaviour (the S-2601 scan covers button constructor names only; the Card/colour/dialog/sheet scans don't apply) → no allowlist entry, no ratchet change (AC-8).
- No new button, dialog, bottom sheet or snackbar; the hand-built ratchets (16 / 9) are untouched.
- `docs/design_system.md` has no hint/label rule in "Shared pieces and rules per job"; predicted: no edit (Phase 3 item 4 records the check).

### Docs impact

| Doc | What it says today | Change |
| --- | --- | --- |
| `docs/widget_catalog/nutrition_widgets.md` (FoodForm section ~L90-245; under 20 KB — full read, no truncation) | describes the serving control in full; the other fields behind the hedge "the remaining fields' keys and defaults are the file's own" (~L101-103); the macro/decimal paragraph ~L173-180; the select-all bullet; the test list | Phase 3 item 1: field order, blank boxes + faint `0`, `formatGrams` prefill, blank-save contract, the calories line + `caloriesFromMacros`, photo position, duplicate note + `nameExistsInLibrary`, new keys, new tests |
| `docs/nutrition.md` (~31.6 KB per the 92b evidence; 630 lines) | the New Food paragraph ~L112-113 and the EditFoodScreen section ~L206-240 describe the serving control; the form's macro boxes are not described field-by-field | Phase 3 item 2: one paragraph on the label-like form (order, blanks, calories line, duplicate note) in the EditFoodScreen section and a sentence in the New Food paragraph |
| `docs/state_management/nutrition_state.md` (~26.9 KB per the 92b evidence) | method table rows for `editLibraryFood` (~L143) / `resetLibraryFood` (~L145) | Phase 3 item 3: a `nameExistsInLibrary` row (read-only predicate, name-only, catalogId twins excluded) |
| `docs/design_system.md` (730 lines) | no hint/label rule | checked-no-edit (Phase 3 item 4) |
| `docs/data_models.md`, `docs/db_integration.md` | model / snapshot contract | checked-no-edit — no stored field changes (D-92c.8) |

### Iteration 1

#### Phase 1 (developer) — the two rules

1. [ ] Add `int caloriesFromMacros({required double protein, required double carbs, required double fat})` returning `(protein*4 + carbs*4 + fat*9).round()` and make `calculateCalories` delegate to it — `lib/core/utils/food_helpers.dart` · `caloriesFromMacros`, `calculateCalories`
2. [ ] Add the unit tests: whole numbers (31/0/0 → 124), fractional rounding (0/0/0.5 → 5, D-92c.12), delegation parity with `calculateCalories` on a `Food` — `test/food_library_state_test.dart` · group `Food Helper Functions` (~L1455)
3. [ ] Add `bool nameExistsInLibrary(String name, {Food? excluding})` next to `libraryIdFor` (~L640): trim + lowercase; blank → false; iterate `_catalogFoods.values` + `_foods.values`, skip archived, skip `excluding` and its catalogId twins in both directions (D-92c.13) — `lib/state/food_library_state.dart` · `nameExistsInLibrary`
4. [ ] Add the S-92c.9 tests: catalog food true, library-only food true, archived false, `excluding` itself false, catalogId twin false both directions, blank false — `test/food_library_state_test.dart` · new group `nameExistsInLibrary`
5. [ ] Preserve the unrelated uncommitted line in `lib/state/food_library_state.dart` (`'chicken_thigh_skin_on',` in the bundled-id list ~L1495) — verify it survives the edit (Open question 2)

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/food_library_state_test.dart` (paste counts); `.github/copilot/scripts/macos/gateway.sh lint` (0 errors; issue count vs the 180 baseline); `.github/copilot/scripts/macos/gateway.sh test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green.
**Prove-red**: the new symbols do not exist at base, so carrying `test/food_library_state_test.dart` to HEAD cannot compile — mutation proofs instead, run and restored verbatim: (a) in `caloriesFromMacros` return the sum + 1 → the new unit tests must FAIL; (b) in `nameExistsInLibrary` drop the archived skip → the S-92c.9 archived leg must FAIL. Restore check: `.github/copilot/scripts/macos/gateway.sh git-diff HEAD --stat -- lib/core/utils/food_helpers.dart lib/state/food_library_state.dart` shows only the feature's additions.
**Predicted Files**: `lib/core/utils/food_helpers.dart`, `lib/state/food_library_state.dart`, `test/food_library_state_test.dart`, this plan's Progress/Assumption Log.

#### Phase 2A (developer) — the boxes

1. [ ] Seed the five macro controllers from `''` (blank) instead of `(initial?.protein ?? 0.0).toString()` etc. — `lib/features/nutrition/widgets/food_form.dart` · `initState` (~L260-275)
2. [ ] Prefill on edit through `formatGrams`: `initial == null ? '' : formatGrams(initial.protein)` etc. for protein/carbs/fat; fiber/sodium keep the null-aware `''` when null — `lib/features/nutrition/widgets/food_form.dart` · `initState`
3. [ ] In `_macroField` (~L843-880): `hintText: '0'`, `floatingLabelBehavior: FloatingLabelBehavior.always` (D-92c.14), validator empty → `'Must be a number'` (D-92c.5), add `onChanged: (_) => setState(() {})` (D-92c.10, inert until 2B) — `lib/features/nutrition/widgets/food_form.dart` · `_macroField`
4. [ ] Reorder the five `_macroField` calls to fat → carbs → fiber → protein → sodium (D-92c.2) — `lib/features/nutrition/widgets/food_form.dart` · `build` (~L766-805)
5. [ ] In `_onSave` (~L400-425): protein/carbs/fat `double.tryParse(text.trim()) ?? 0.0`; fiber/sodium keep `isEmpty ? null : double.tryParse(...) ?? null` (D-92c.5) — `lib/features/nutrition/widgets/food_form.dart` · `_onSave`
6. [ ] Rewrite the two changed assertions: S-003 types `.` into carbs and expects `find.text('Must be a number')` (was `abc`/`Required`, L286-341); S-004 expects the fat prefill `'4'` (was `'4.0'`, L399) — `test/food_form_decimals_and_autofocus_test.dart` · S-003, S-004 tests
7. [ ] Create `test/food_form_label_test.dart` with S-92c.2 (blank start), S-92c.3 (hint + always-on label), S-92c.4 (order by `find.byKey(...).dy`), S-92c.5 (blank save → 0.0/0.0/null/null; type-then-clear → null), S-92c.6 (no `Required`), S-92c.14 (0.0 vs null), S-92c.15 (select-all on `'4'`), S-92c.16 (name/category decoration untouched) — Mock-first, Hive seeded in `setUp`, tall surface (800x3000) where the whole form must be visible
8. [ ] Run the neighbouring suites and paste counts into the evidence file — `test/food_form_serving_test.dart`, `test/food_form_orphan_category_test.dart`, `test/food_form_pick_saves_test.dart`, `test/edit_food_save_test.dart`, `test/nutrition_test.dart`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/food_form_label_test.dart test/food_form_decimals_and_autofocus_test.dart test/food_form_serving_test.dart test/food_form_orphan_category_test.dart test/food_form_pick_saves_test.dart test/edit_food_save_test.dart test/nutrition_test.dart` (paste counts); the two contract tests green; `lint` vs the 180 baseline.
**Prove-red**: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/food_form_label_test.dart` must FAIL on base — the file compiles there (only existing keys and APIs) and S-92c.2/3/4/5/6/14/15 are red for the reasons the seed states.
**Predicted Files**: `lib/features/nutrition/widgets/food_form.dart`, `test/food_form_label_test.dart` (new), `test/food_form_decimals_and_autofocus_test.dart`, this plan's Progress/Assumption Log.

#### Phase 2B (developer) — calories, photo, duplicate note

1. [ ] Add the calories line under the heading: `Text('= ${caloriesFromMacros(protein: tryParse(_protein), carbs: tryParse(_carbs), fat: tryParse(_fat))} cal', key: Key('food_form_calories'), style: bodySmall + textSecondary)` — `lib/features/nutrition/widgets/food_form.dart` · `build` (after `food_form_per_heading`)
2. [ ] Move `FoodFormImageTile` from first child (~L606) to after the name field, below the duplicate note (D-92c.9) — `lib/features/nutrition/widgets/food_form.dart` · `build`
3. [ ] Add the duplicate note: visible when `nameExistsInLibrary(_name.text.trim(), excluding: initial)`; `Text('There\'s already a food called "${_name.text.trim()}" in the Library', key: Key('food_form_duplicate_note'), style: bodySmall + textSecondary)`; give `_name` a listener that `setState`s (D-92c.11) — `lib/features/nutrition/widgets/food_form.dart` · `build`, `initState`
4. [ ] Add S-92c.1 (line appears and follows typing), S-92c.7 (photo below name), S-92c.8 (duplicate note; rename to `Oats, dry` — see Open question 1), S-92c.10 (padded/case), S-92c.11 (cleared name), S-92c.12 (one note for two rows), S-92c.13 (fractional line = Library row) — `test/food_form_label_test.dart`
5. [ ] Residue sweep, counts into the evidence file: grep `lib/` for `Required` (expected: only `_validatePositiveDouble` and `Name is required`), for `?? 0.0).toString()` (zero), for `floatingLabelBehavior` (only `_macroField`), for the two new keys (only the new sites); grep `test/` for `find.text('Required')` (only the serving test's package-amount leg)
6. [ ] Run the whole suite once (900 s timeout) and paste counts — `.github/copilot/scripts/macos/gateway.sh test`

**Done Criteria** (run until green): targeted `test/food_form_label_test.dart` + the Phase 2A neighbours (paste counts); the full suite once (paste counts); the two contract tests green; `lint` vs the 180 baseline.
**Prove-red**: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/food_form_label_test.dart` must FAIL on base (S-92c.1/7/8/10-13 red at base).
**Predicted Files**: `lib/features/nutrition/widgets/food_form.dart`, `test/food_form_label_test.dart`, this plan's Progress/Assumption Log.

#### Phase 3 (developer) — docs

1. [ ] Update the FoodForm section: field order, blank boxes + faint `0`, `formatGrams` prefill, blank-save contract, the calories line + `caloriesFromMacros`, photo position, duplicate note + `nameExistsInLibrary`, new keys, new tests — `docs/widget_catalog/nutrition_widgets.md` · FoodForm section (~L90-245)
2. [ ] Add one paragraph on the label-like form (order, blanks, calories line, duplicate note) to the EditFoodScreen section and a sentence to the New Food paragraph — `docs/nutrition.md` · ~L112, ~L206-240
3. [ ] Add a `nameExistsInLibrary` row to the method table (read-only predicate, name-only, catalogId twins excluded) — `docs/state_management/nutrition_state.md` · method table (~L143-145)
4. [ ] Checked-no-edit records in the evidence file: `docs/design_system.md` (no hint/label rule), `docs/data_models.md` + `docs/db_integration.md` (no stored field change); re-measure the three edited docs against the 52 KB band
5. [ ] Update the series index's 92c status and this plan's status line — `docs/plans/2026-10-29-92-food-form-rework-plan/2026-10-29-92-food-form-rework-plan.md`, this plan

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` green (sizes within the band); the no-edit checks recorded; Progress updated.
**Predicted Files**: the three docs, the series index, this plan, the evidence file.

### Files Affected (whole feature)

- `lib/core/utils/food_helpers.dart` — Phase 1 (writes: `caloriesFromMacros`, `calculateCalories`)
- `lib/state/food_library_state.dart` — Phase 1 (writes: `nameExistsInLibrary`). NB the file carries another unit's uncommitted one-line edit (`'chicken_thigh_skin_on',` ~L1495) — preserve it (Open question 2).
- `test/food_library_state_test.dart` — Phase 1 (writes)
- `lib/features/nutrition/widgets/food_form.dart` — Phases 2A / 2B (writes)
- `test/food_form_label_test.dart` — new (Phases 2A / 2B)
- `test/food_form_decimals_and_autofocus_test.dart` — Phase 2A (rewrites S-003, S-004's text assertion)
- `docs/widget_catalog/nutrition_widgets.md`, `docs/nutrition.md`, `docs/state_management/nutrition_state.md`, the series index, this plan — Phase 3
- Read-only dependents: `edit_food_screen.dart`, `add_food_screen.dart` (hosts); `log_food_row.dart`, `watch_reference_sync.dart` (`calculateCalories` readers, value unchanged); `lib/core/models/food_draft.dart`, `lib/data/models/models.dart` (unchanged); tests that pump the form and must stay green: `food_form_serving_test.dart`, `food_form_orphan_category_test.dart`, `food_form_pick_saves_test.dart`, `edit_food_save_test.dart`, `screen_widget_test.dart`, `library_merge_test.dart`, `library_row_toggle_test.dart`, `nutrition_test.dart`

### Notes

- Dependency graph: 1 → 2A → 2B → 3. Phase 1's two rules are independent of each other; the serial order is kept because 2A's Done Criteria run the Phase 1 file.
- Intermediate state after 2A: the boxes are label-like and the order is package-order, but no calories line, no note, tile still first — the app is consistent; the suite must be green at the boundary. `_macroField`'s new `onChanged` setState is inert until 2B's line lands.
- Intermediate state after 2B: feature complete; Phase 3 is docs-only.
- Widget tests are FakeAsync: Mock-first, Hive seeded in `setUp`, no real `Future.delayed` or Hive write inside `testWidgets` (`docs/global_conventions.md`). The label test file pumps `FoodForm` directly on a tall surface (800x3000 where a scenario needs the whole form visible — the 92b precedent, A-92b.13).
- The seed's S-92c.8 names `Oats, rolled`; the shipped seed has `Oats, dry` (`lib/mock/food_catalog_seed.dart:931`) — see Open question 1; the Phase 2B test uses `Oats, dry`.
- The duplicate-note lookup runs per keystroke over catalog + library; the same O(n) class as `libraryIdFor`'s documented cost — acceptable for the ~170-row catalog.

### Progress

- [x] Phase 1 — the two rules (**Complete**: 72/72 in `test/food_library_state_test.dart`; mutations (a) calories +1 and (b) drop archived skip proved red and restored)
- [x] Phase 2A — the boxes (**Complete**: 10/10 in `test/food_form_label_test.dart`; 154/154 across the Phase 2A neighbours; prove-red RED AT `da266e05`; full suite 5942 passed / 2 skipped; lint 181 = baseline)
- [x] Phase 2B — calories, photo, duplicate note (**Complete**: 19/19 in `test/food_form_label_test.dart`; 144/144 neighbours; 54/54 contracts; prove-red RED AT `9ce61a07`; full suite 5951 passed / 2 skipped; lint 181 = baseline)
- [ ] Phase 3 — docs

### Assumption Log

_Executors append: decision made, options considered, choice + why. Conductor marks each RATIFIED (promote to D-x) or REVERT (remediation)._

- **A-92c.P1.1 Twin linkage uses cache membership, not the `isCatalog` flag.** `nameExistsInLibrary` knows each candidate's source map (`_catalogFoods` vs `_foods`) and skips a catalog row whose id equals `excluding.catalogId` / a library row whose `catalogId` equals `excluding.id`. Considered: branching on `excluding.isCatalog`/`candidate.isCatalog`; rejected because legacy rows can carry a stale flag (92a/92b import paths) while the cache is authoritative. Same rule as D-92c.13.
- **A-92c.2B.1 Calories computed once at the top of `build`.** `caloriesFromMacros` is called outside the `ListenableBuilder` builder so the line and any later reader see one value per frame; the macro boxes' own listeners already rebuild the form on every keystroke, so the listener set is unchanged.
- **A-92c.2B.2 The duplicate note follows typing via a `_name` listener.** `TextEditingController` changes do not rebuild on their own; `_onNameChanged` calls `setState` (guarded by `mounted`) and is removed in `dispose`. Chosen over a `ValueListenableBuilder` wrapper so the note and the calories line share one rebuild path.
- **A-92c.2B.3 The library-copy leg (S-92c.8) carries a positive control.** The original assertion was `findsNothing` against a form that had no note in any state, which would pass on a form that never shows a note; it now also renames to `Oats, dry` and expects the note, so the pair proves the twin exclusion rather than the absence of the feature.
- **A-92c.2B.4 `--plain-name` matches by substring.** `--plain-name "S-92c.1"` also runs S-92c.10-.16; the mutation runs were read accordingly, not treated as single-test runs.
- **A-92c.2B.5 The brief's mutation (b) does not discriminate.** Passing `_name.text` instead of `_name.text.trim()` to `nameExistsInLibrary` stays green because the state trims its own argument; the display trim (`"${_name.text.trim()}"`) is the observable one, so that is the mutation recorded. The case-folding leg is proved by the prove-red only, since `lib/state/food_library_state.dart` is outside this phase's files.
- **A-92c.2A.1 `_macroField`'s validator returns null for empty text.** Phase 2A item 3 says "validator empty → `'Must be a number'`"; D-92c.5 and AC-5 say blank Protein/Carbs/Fat save 0 and blank Fiber/Sodium save null, so the item's wording is a slip. Followed D-92c.5 (the brief confirms the seeded definition wins).
- **A-92c.2A.2 S-92c.16 reads the resolved `InputDecorator.decoration`.** `TextFormField.decoration` is private, and an unset `floatingLabelBehavior` resolves to `auto`. Considered asserting `isNull`; rejected because resolution never yields null. The guard is `hintText == null && floatingLabelBehavior != always` on the name and category fields.
- **A-92c.2A.3 The class doc's field list was reordered with the code.** The header comment listed protein → … → sodium; leaving it would contradict D-92c.2 in the same file. `_macroField`'s doc comment now states the blank-save contract.
- **A-92c.2A.4 S-003 and S-004 keep their ids in `test/food_form_decimals_and_autofocus_test.dart`.** S-003 now types `.` (was `abc`) and expects `Must be a number`; S-004 expects `'4'`. No other assertion in that file changed; S-001's comment was updated only.

### Feedback

[empty — fold into a new Iteration block when non-empty, then clear]

### Open questions

1. **S-92c.8's fixture `Oats, rolled` does not exist in the shipped seed.** Grep `Oats` over `lib/mock/food_catalog_seed.dart` finds `Oats, dry` (L931) and no `rolled`. Default applied: the Phase 2B test renames to `Oats, dry`; the seeded scenario text stays verbatim.
2. **`lib/state/food_library_state.dart` carries another unit's uncommitted one-line edit** (git-diff HEAD: `+ 'chicken_thigh_skin_on',` in the bundled-id list ~L1495; also `lib/mock/food_catalog_seed.dart` and `assets/data/food_catalog.json`). The file is not on the hands-off list, but Phase 1 edits it. Default applied: proceed; Phase 1 item 5 explicitly preserves that line.
3. **D-92c.9 (name → note → tile → category) resolves the seed's D-92c.6/D-92c.7 slot conflict.** Derived — vetoable.
4. **D-92c.13 (legacy twins trigger the note).** Derived — vetoable.
5. **Doc byte sizes could not be re-measured this run** (`wc`/`ls` are outside the gateway's allowed commands); the sizes cited come from the 92b evidence file plus a full untruncated read of `nutrition_widgets.md` (<20 KB). Phase 3 item 4 re-measures against the 52 KB band.
