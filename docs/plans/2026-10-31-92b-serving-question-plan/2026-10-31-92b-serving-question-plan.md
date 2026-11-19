# Feature: 92b — one serving question: "Nutrition facts are per"

> Status: CLOSED — implemented and reviewed (APPROVE; 2 minor findings left: untested g/ml package-amount carry-over, cosmetic heading fallback while an invalid package amount is typed), committed. The governor's seed below is kept verbatim; the planner's expansion is appended after it (see "Planner expansion (Iteration 1)"). Series: `docs/plans/2026-10-29-92-food-form-rework-plan/` (92b of 92a/92b/92c; 92a is committed, `2b8feff4`..`dcd4dc88`). Base: `dcd4dc88` on `claude_develop`.
> Binding conventions: `docs/global_conventions.md`, `docs/design_system.md`, `.github/copilot/pr-scope-budget.md`. Never create or switch branches; git belongs to the governor.
> Hands off (another unit's uncommitted work): `docs/session_summary.md`, `docs/state_management/workout_state.md`, `lib/features/session/session_summary_screen.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/state/workout/session_core_entry.dart`, `lib/state/workout/workout_state.dart`, `test/watch_live_refresh_screen_test.dart`, `test/watch_routine_adoption_test.dart`, `test/watch_session_merge_test.dart`, `scripts/*.sh`.
> Owner decisions are in the series plan (D-92.4 keep numbers and say so; D-92.5..D-92.8). Field order, calories, blank boxes, photo position and the duplicate note are 92c, NOT here.

## Goal

The food form (New Food, Edit Food, the legacy edit screen all host `FoodForm`) replaces three boxes that ask one question (`food_form_unit_type` dropdown, `food_form_reference_amount`, `food_form_reference_label`) with one: **Nutrition facts are per** 100 g / 100 ml / 1 serving. "1 serving" asks "called a…" with chips (slice, scoop, bar, piece, cup) and a free-text label. A link "Enter package serving instead (e.g. 30 g)" covers a package serving size for g and ml. The heading above the macros reads "Nutrition per 100 g" with the live value. The stored model does not change (`Food.unitType`, `referenceAmount`, `referenceLabel`), so logging, snapshots and the watch are untouched.

## What the user sees

| | Now | After |
|---|---|---|
| Serving | "Unit type" dropdown + "Reference amount" + "Reference label" | one control "Nutrition facts are per": 100 g / 100 ml / 1 serving |
| 1 serving | label defaults to "unit" | "called a…" with chips slice, scoop, bar, piece, cup and a text field; a name is required |
| Package size | unexplained "Reference amount" | link "Enter package serving instead (e.g. 30 g)" (g and ml only) |
| Heading | "Macros (the reference above)" | "Nutrition per 100 g" / "per 100 ml" / "per 1 slice" / "per 30 g" |
| Switching on an existing food | silently does nothing on a device ("100.0" is not "100") | works; the numbers stay and a line says "Check these numbers are per 1 slice" |
| A food with an odd stored serving | shows odd boxes | opens on an extra choice "As saved: 3 tbsp" and saves unchanged |

## Acceptance criteria

- AC-1 No `food_form_unit_type`, `food_form_reference_amount` or `food_form_reference_label` widget remains; no text "Unit type", "Reference amount", "Reference label" or "Macros (the reference above)" in `lib/`.
- AC-2 The draft the form produces maps exactly as the table in D-92b.1; the mapper round-trips every distinct (unitType, referenceAmount, referenceLabel) in the shipped catalog (28 combinations) and the odd cases in S-92b.1, byte-identical.
- AC-3 Opening and saving an existing food without touching the serving control never changes its stored serving.
- AC-4 Switching the control on an existing food changes the stored serving on Save (the on-device bug), keeps the typed numbers, and shows the "Check these numbers are per X" line only while the serving differs from the one the food was opened with.
- AC-5 Any change to a library food's serving clears its `lastAmountConsumed` on every path that can change it.
- AC-6 No new allowlist entry or ratchet raise; the contract tests `test/ui_standards_contract_test.dart` and `test/docs_indexing_contract_test.dart` stay green.

## Decision Ledger

- **D-92b.1 Mapping (control to stored fields; the only place the three stored fields are written).** `FoodDraft.unitType/referenceAmount/referenceLabel` are derived from the choice:

  | Choice | unitType | referenceAmount | referenceLabel |
  |---|---|---|---|
  | 100 g | grams | 100 | `g` |
  | 100 ml | grams | 100 | `ml` |
  | package serving, unit g or ml | grams | the typed amount (> 0) | `g` or `ml` |
  | 1 serving called X | count | 1 | X (trimmed, non-empty) |
  | As saved (only when the opened food does not fit above) | the opened food's values | the opened food's | the opened food's |

- **D-92b.2 Loading (stored fields to choice).** `grams` + amount exactly 100 + label exactly `g` is 100 g; label exactly `ml` is 100 ml; `grams` + amount > 0 and != 100 + label `g` or `ml` is the package row with that amount; `count` + amount exactly 1 + label non-empty and equal to its own trim is 1 serving with that label; anything else (legacy `per 100g` labels, a count food with amount != 1, a grams food with another label, an empty label, a non-positive amount) is **As saved**. A new food starts as 100 g.
- **D-92b.3 One pure mapper, no text matching.** The choice is derived from stored values, never from the text of a box (the on-device bug: `food_form.dart` `_referenceAmount.text == '1'`/`'100'` compared against `100.0`). The mapper is a pure Dart file `lib/core/utils/food_serving.dart` (new) with no Flutter import: the choice type, `servingChoiceFrom(unitType, amount, label)`, `storedServingFrom(choice)` and `servingHeading(choice)`; the form calls it, nothing else computes these.
- **D-92b.4 Heading.** One string from `servingHeading`: `Nutrition per 100 g`, `Nutrition per 100 ml`, `Nutrition per 30 g` (package; amount through `formatGrams`, `lib/core/utils/food_helpers.dart`), `Nutrition per 1 slice`, `Nutrition per 1 serving` while the label is empty, `Nutrition per 3 tbsp` (As saved). Key `food_form_per_heading`. It updates as the user types.
- **D-92b.5 The control.** A single-choice control with three segments `100 g`, `100 ml`, `1 serving` (key `food_form_basis`), plus a fourth segment `As saved: <amount> <label>` only when D-92b.2 gave As saved. The app's existing segmented control is `SegmentedButton` (`lib/features/nutrition/widgets/nutrition_trend_card.dart` ~L111); use that precedent and the design-system rules for shape and colour. Package row: link text `Enter package serving instead (e.g. 30 g)` (key `food_form_package_link`) under 100 g / 100 ml; tapping shows a `Serving size (g)` / `(ml)` numeric field (key `food_form_package_amount`, positive number required, empty at first with hint `30`) and the link becomes `Back to per 100 g` / `100 ml`. Serving: a text field `Called a…` (key `food_form_serving_label`, hint `slice`, required: `Name the serving, e.g. slice`) and chips for slice, scoop, bar, piece, cup (keys `food_form_serving_chip_<word>`) that fill the field; the chip whose word equals the field text shows selected. Switching segments keeps the typed label and package amount, so switching back loses nothing.
- **D-92b.6 Switching on an existing food keeps the typed numbers (owner, D-92.4).** In edit mode, while the stored serving the control would save differs from the one the food was opened with, a line `Check these numbers are per <X>` (key `food_form_per_note`, `<X>` is the heading without "Nutrition per ") is shown under the heading; it is hidden when the serving equals the opened one and never shown for a New Food.
- **D-92b.7 `lastAmountConsumed` (owner-approved consequence of D-92.4; plan D-92.6).** A library food's remembered log amount is cleared whenever its serving triple (unitType, referenceAmount, referenceLabel) changes. Paths in `lib/state/food_library_state.dart`: `editLibraryFood` (~L1008; builds `current.copyWith(...)`, which keeps `lastAmountConsumed`), `_propagateCatalogEditToLinkedFoods` (~L756-815; two loops pass `lastAmountConsumed: libFood.lastAmountConsumed` and `legacyFood.lastAmountConsumed`), `resetLibraryFood` (~L1090-1130; passes `copy.lastAmountConsumed`). `updateCustomFood` (~L1339) already builds a `Food` without it, and `updateCatalogFood` edits the catalog row, so neither changes. `Food.copyWith(lastAmountConsumed: null)` clears (sentinel `_foodCopyWithUnset`, `models.dart` ~L2131). A save that leaves the triple equal keeps it.
- **D-92b.8 Validation.** 1 serving needs a non-empty trimmed label; the package amount needs a number > 0 (reuse `_validatePositiveDouble`); non-numeric text cannot be typed (existing `^\d*\.?\d*$` formatter). Name is still required. Nothing else changes in validation.
- **D-92b.9 Out of scope in this unit.** Macro order, calories line, blank boxes, `formatGrams` prefill of macros, photo position, duplicate note (92c); the New Food double pop; any stored field; the watch; the catalog JSON.

## Core scenarios (each fails on the base for the reason given)

- **S-92b.1 Round trip.** Pure test over `servingChoiceFrom`/`storedServingFrom`: for every distinct (unitType, referenceAmount, referenceLabel) among `FoodCatalogSeed.sampleCatalogFoods` (168 foods, 28 combinations: grams/100/g, grams/100/ml, grams/28/g, and count/1/<label> for 25 labels), plus (count, 3, `tbsp`), (grams, 100, `per 100g`), (grams, 100.5, `g`), (count, 1, ``), (grams, 0, `g`): `storedServingFrom(servingChoiceFrom(t)) == t`. Also: grams/100/g gives 100 g, grams/100/ml gives 100 ml, grams/28/g gives package 28 g, count/1/slice gives serving `slice`, the five odd cases give As saved. Red at base: the file does not exist (the test cannot compile there; the plan's proof is a mutation, e.g. mapping `ml` to `g` turns it red).
- **S-92b.2 New Food defaults to 100 g.** `FoodForm(initial: null)` pumped on an 800x1800 surface: segment `100 g` selected, heading `Nutrition per 100 g`, none of the three old keys present. Fill name `My Trail Mix`, protein 10, carbs 18, fat 12, tap the host's `food_form_save`: created food is grams / 100 / `g`. Red: the old dropdown and boxes are there.
- **S-92b.3 100 ml.** Same fixture; tap segment `100 ml`; heading `Nutrition per 100 ml`; saved food is grams / 100 / `ml`. Red: no such segment.
- **S-92b.4 1 serving with chips.** Tap `1 serving`; saving with an empty label shows `Name the serving, e.g. slice` and writes nothing; tap chip `food_form_serving_chip_slice`: field text `slice`, heading `Nutrition per 1 slice`; save: count / 1 / `slice`. Typing `bar` instead of using a chip saves `bar`. Red: no control.
- **S-92b.5 Package serving.** On 100 g tap `food_form_package_link`; the amount field shows and is empty; saving with it empty shows an error and writes nothing; type `30`: heading `Nutrition per 30 g`; save: grams / 30 / `g`. Tap `Back to per 100 g`: heading `Nutrition per 100 g`, the field is gone, saved food is grams / 100 / `g`. Same with 100 ml and 250: grams / 250 / `ml`. Red: no link.
- **S-92b.6 The on-device bug, both directions (edit).** Seed `Egg` as count / 1.0 / `egg` (a double, as on a device) and open `EditFoodScreen`: segment `1 serving`, label field text `egg` (no `1.0`), heading `Nutrition per 1 egg`. Tap `100 g`, Save: stored grams / 100 / `g`. Seed `Rice` as grams / 100 / `g`, open, tap `1 serving`, type `cup`, Save: stored count / 1 / `cup`. Red: on the base the switch does nothing when the amount text is `100.0`.
- **S-92b.7 Beef jerky opens in package mode.** Seed grams / 28 / `g`; open edit: `food_form_package_amount` shows `28` (not `28.0`), heading `Nutrition per 28 g`; Save without touching: stored grams / 28 / `g`. Red: the old form shows the boxes with `28.0`.
- **S-92b.8 As saved.** Seed count / 3 / `tbsp`; open edit: segment `As saved: 3 tbsp` is selected and heading `Nutrition per 3 tbsp`; Save untouched: stored count / 3 / `tbsp`. Tap `100 g`, then tap `As saved: 3 tbsp` again: the heading is back and Save stores count / 3 / `tbsp`. Red: no such segment.
- **S-92b.9 The "check" line.** Edit a seeded grams / 100 / `g` food; no `food_form_per_note`. Tap `1 serving`, type `slice`: `food_form_per_note` reads `Check these numbers are per 1 slice`; macros fields still hold their values; Save keeps the macros. Tap `100 g` again: the note is hidden. A New Food never shows the note. Red: no note.
- **S-92b.10 Remembered amount clears on a serving change (state layer, `FoodLibraryState`).** A library copy with `lastAmountConsumed: 150` and grams/100/g: `editLibraryFood` with a draft changing only the name keeps 150; with a draft count/1/`slice` gives null. The same for `resetLibraryFood` (a copy edited to a different serving and then reset to the catalog's: null) and for the catalog propagation (edit a user-created catalog food's serving: its linked library copy's value is null; a name-only edit keeps it). Red: today all three keep the stale value.
- **S-92b.11 A liquid reads right.** Seed a catalog-like grams / 100 / `ml` food (`Milk`) and open edit: segment `100 ml` selected, heading `Nutrition per 100 ml`; Save untouched keeps grams / 100 / `ml`. Red: the old form shows `Grams (100 g)` with label `ml`.

## Phase outline (one developer run each; at most 8 items per phase)

- **Phase 1 (developer) — mapper and state rule.** New `lib/core/utils/food_serving.dart` (D-92b.1-4 pure part), `test/food_serving_test.dart` (S-92b.1), D-92b.7 in `food_library_state.dart` (`editLibraryFood`, both propagation loops, `resetLibraryFood`) with S-92b.10 in `test/food_library_edit_test.dart` or the closest existing state test file.
- **Phase 2A (developer) — the control for a new food.** `food_form.dart`: remove the three old widgets, the `_unitType`/`_referenceAmount`/`_referenceLabel` state and the text-matching `onChanged`; add the control, heading, package link, serving label and chips, validation, draft mapping through the mapper, loading through the mapper. Tests S-92b.2-5 in a new `test/food_form_serving_test.dart`; rewrite the one test that types reference amount/label (`test/nutrition_test.dart` ~L1950, "My Trail Mix", 50 g) to the package link.
- **Phase 2B (developer) — existing foods.** The note (D-92b.6), As saved segment, loading from stored doubles; tests S-92b.6-9 and S-92b.11 in the same new file; fix any other test the removal breaks.
- **Phase 3 (developer) — docs.** `docs/widget_catalog/nutrition_widgets.md` (`FoodForm`: the serving control, keys, heading, note), `docs/nutrition.md`, `docs/data_models.md` if it describes the form's serving boxes, `docs/design_system.md` only if a new rule is needed, the plan status.

## Code pointers

`lib/features/nutrition/widgets/food_form.dart`: state fields `_referenceAmount`, `_referenceLabel`, their focus nodes (~L173-191), `_unitType` (~L210), initState seeding (~L225-244) and select-all bindings (~L261-267), dispose (~L285-295), `_onSave` draft (~L409-411), build: unit-type dropdown (~L497-531), reference Row (~L533-575), heading text `Macros (the reference above)` (~L577) · `lib/features/nutrition/widgets/nutrition_trend_card.dart` ~L111 (`SegmentedButton` precedent) · `lib/core/utils/food_helpers.dart` `formatGrams`, `foodServingLabel` · `lib/state/food_library_state.dart` as in D-92b.7 · tests: `test/nutrition_test.dart` ~L1950-1975 (the only test that types reference amount/label) · seeds: `lib/mock/food_catalog_seed.dart` `FoodCatalogSeed.sampleCatalogFoods`.

## Readers of what changes

`FoodForm` is built in exactly three places: `edit_food_screen.dart`, `add_food_screen.dart` (`_NewFoodFormScreen`, `_LegacyLibraryEditScreen`). The three old widget keys are referenced only by `test/nutrition_test.dart` (~L1956-1960). `FoodDraft` and the stored fields are unchanged. Tests that pump `FoodForm` directly (`food_form_orphan_category_test.dart`, `food_form_decimals_and_autofocus_test.dart`, `food_form_pick_saves_test.dart`, `edit_food_save_test.dart`) read the form's other keys and must stay green.

## Out of scope

See D-92b.9.

---

## Planner expansion (Iteration 1)

Appended by the planner (conductor-v2) on base `dcd4dc88`. Everything above this section is the governor's seed, kept verbatim. New entries continue the seed's numbering: D-92b.10.., S-92b.12... Research baselines live in `2026-10-31-92b-serving-question-plan.evidence.md` (same folder).

### Appended decisions (Ledger)

- **D-92b.10 AC-1 residue-sweep scope (derived — vetoable).** The AC-1 string ban ("Unit type", "Reference amount", "Reference label", "Macros (the reference above)") targets user-facing strings and widget keys in `lib/`. The stored fields' own doc comments in `lib/data/models/models.dart` (~L1946-1953: "Unit type: count…", "Reference amount —…", "Reference label —…") document the model that does not change (D-92b.9) and stay. The Phase 2B sweep greps `lib/` for the three old widget keys with zero tolerance everywhere, and for the four strings with the models.dart doc comments as the one expected, recorded exception.
- **D-92b.11 One serving sub-control at a time (derived from D-92b.5 — vetoable).** The package row (link + `food_form_package_amount`) is visible only while a `100 g` / `100 ml` segment is selected; the serving field + chips are visible only while `1 serving` is selected. Switching segments hides the inactive sub-control but keeps its typed values (D-92b.5's "keeps the typed label and package amount"), so switching back restores them.
- **D-92b.12 S-12702/S-12704 keep their assertions (derived — vetoable).** `test/food_library_copy_edit_test.dart` S-12702 (test at L140, `expect(edited.lastAmountConsumed, 250)` at L153) and S-12704 (test at L218, `expect(reset.lastAmountConsumed, 250)` at L246) become the "equal serving triple keeps the remembered amount" guards: their `editLibraryFood(copy, _draft())` call sites get serving-preserving drafts (the file's `_draft()` helper builds count/1/`tbsp` against a grams/100/`g` copy, which would now clear). The clearing legs are the new S-92b.10 tests; no test asserts a stale keep after a serving change.

### Appended scenarios

- **S-92b.12 Trimmed serving label.**
  - Fixture: New Food form, nothing seeded.
  - Trigger: tap `1 serving`, type ` slice ` (spaces both sides), Save.
  - Flow: `_onSave` trims the label.
  - Expected outcome: stored count / 1 / `slice` (trimmed); heading `Nutrition per 1 slice`.
  - Edge case of: S-92b.4. Guard — the trim exists at base (L411), so the assertion is green at base; the scenario still needs the new control to exist.
- **S-92b.13 Package amount `0` and `.` rejected.**
  - Fixture: New Food on `100 g`.
  - Trigger: tap `food_form_package_link`, type `0`, Save; then type `.`, Save.
  - Flow: `_validatePositiveDouble` rejects both.
  - Expected outcome: the field shows its error both times and nothing is saved; typing `30` then saves grams / 30 / `g`.
  - Edge case of: S-92b.5. Red at base (no package field exists).
- **S-92b.14 Package row survives a rebuild.**
  - Fixture: New Food on `100 g`, package row open with `30` typed.
  - Trigger: a parent rebuild while the row is open (another field's `onChanged` → `setState`, or a keyboard toggle pump).
  - Flow: the row's state lives in `_FoodFormState`, not in local build variables.
  - Expected outcome: the link still reads `Back to per 100 g`, `food_form_package_amount` still shows `30`, heading `Nutrition per 30 g`.
  - Edge case of: S-92b.5. Red at base (no control).
- **S-92b.15 Chips hidden off the serving segment.**
  - Fixture: New Food.
  - Trigger: select `100 g` (the default) and then `100 ml`.
  - Flow: D-92b.11.
  - Expected outcome: no `food_form_serving_label` and no `food_form_serving_chip_*` on either; selecting `1 serving` brings them back with any typed text intact.
  - Edge case of: S-92b.4. Red at base (no chips).
- **S-92b.16 Both hosts show the same control.**
  - Fixture: a library copy of a bundled catalog food (grams / 100 / `g`).
  - Trigger: open the legacy edit shim (`_LegacyLibraryEditScreen` in `add_food_screen.dart`) and `EditFoodScreen`.
  - Flow: both host `FoodForm`; the control is the form's own.
  - Expected outcome: both render `food_form_basis` with `100 g` selected and neither shows the old dropdown or boxes.
  - Edge case of: S-92b.2. Red at base (old dropdown).
- **S-92b.17 Propagation clears for the legacy-upgrade loop too.**
  - Fixture: catalog food `Almond butter` grams / 100 / `g`; a legacy library food (no `catalogId`) also named `Almond butter` with `lastAmountConsumed: 200`.
  - Trigger: `updateCatalogFood` changes the catalog serving to count / 1 / `jar`; then a second `updateCatalogFood` changes only the name.
  - Flow: `_propagateCatalogEditToLinkedFoods` loop 2 (`upgradedLibFood`, ~L805-815) upgrades the legacy food on both edits.
  - Expected outcome: after the serving change the upgraded copy's `lastAmountConsumed` is null; after the name-only change it is kept (200).
  - Edge case of: S-92b.10. Red at base (keeps 200).
- **S-92b.18 Switching segments keeps typed values.**
  - Fixture: New Food.
  - Trigger: `1 serving` → type `bar`; `100 g` → open the package row, type `30`; back to `1 serving`; back to `100 g`.
  - Flow: D-92b.5 / D-92b.11.
  - Expected outcome: `food_form_serving_label` still reads `bar`, the package row is still open with `30`, and the heading follows each segment.
  - Edge case of: S-92b.5. Red at base (no control).
- **S-92b.19 Note hidden when the package row reproduces the opened serving.**
  - Fixture: edit a seeded grams / 30 / `g` food.
  - Trigger: open (loads as the package row with 30), do not touch the control.
  - Flow: D-92b.6 compares the would-save triple with the opened triple.
  - Expected outcome: no `food_form_per_note` (the triples are equal); after typing `45` the note reads `Check these numbers are per 45 g`.
  - Edge case of: S-92b.9. Red at base (no note).

### Feature Invariants

- The three stored serving fields are derived in exactly one place: `storedServingFrom` in `lib/core/utils/food_serving.dart` (D-92b.1 / D-92b.3). No widget text ever feeds them.
- Opening and saving a food without touching the serving control stores a byte-identical serving triple (AC-3) — including the `100.0`-vs-`100` and `1.0`-vs-`1` double forms a device round-trip produces (S-92b.6 / S-92b.7).
- A serving-triple change clears `lastAmountConsumed` on every `FoodLibraryState` path that writes a library food (AC-5); an equal triple keeps it (D-92b.7).
- `lib/core/utils/food_serving.dart` imports no Flutter library (D-92b.3).
- The serving rule lives in `FoodLibraryState`, shared by both repository implementations — `MockWorkoutRepository` / `HiveWorkoutRepository` parity holds by construction (conventions doc: `docs/global_conventions.md`).

### Existing-Functionality Impact

| Touched surface | Existing readers (the grep that found them) | Effect of the change | Guarded by |
|---|---|---|---|
| `FoodForm` (the widget) | `FoodForm(` in `lib/` → `edit_food_screen.dart`, `add_food_screen.dart` (`_NewFoodFormScreen`, `_LegacyLibraryEditScreen`) — exactly 3 builds, none passes serving-specific params | Control replaced inside the form; hosts untouched | S-92b.16 |
| Old widget keys `food_form_unit_type` / `food_form_reference_amount` / `food_form_reference_label` | grep → only `test/nutrition_test.dart` L1956-1960 and L2094-2098 | Keys removed; both tests rewritten | Phase 2A item 8; AC-1 |
| Strings "Unit type" / "Reference amount" / "Reference label" / "Macros (the reference above)" in `lib/` | grep → `food_form.dart` L39-40 (class doc comment) and L497-577 (dropdown, Row, heading); `models.dart` doc comments ~L1946-1953 | Form strings gone; model doc comments stay | D-92b.10; Phase 2B sweep |
| `FoodDraft.unitType/referenceAmount/referenceLabel` | `FoodDraft(` in `lib/state/` → `createCustomFood`, `updateCustomFood`, `updateCatalogFood`, `editLibraryFood` | Fields unchanged; only the derivation of their values moves to the mapper | S-92b.1, S-92b.2 |
| `lastAmountConsumed` writes | grep in `food_library_state.dart` → L790 (propagation loop 1), L806 (loop 2), L1127 (reset), the `editLibraryFood` `copyWith` block (~L1034-1050); tests S-12702 (L153), S-12704 (L246), S-003 (`test/food_library_edit_test.dart` L592-630) | Conditional clear added; the keep path preserved | S-92b.10, S-92b.17, D-92b.12 |
| S-003 preserve test | its `catalogDraft` keeps grams / 100 / `g` | Serving-preserving catalog edit → keep path → stays green | Phase 1 Done Criteria |
| Tests pumping `FoodForm` directly (`test/food_form_decimals_and_autofocus_test.dart`, `test/food_form_orphan_category_test.dart`, `test/food_form_pick_saves_test.dart`, `test/edit_food_save_test.dart`) | grep → none references the three old keys; fixtures seed reference values only | Stay green (their other keys are untouched) | Phase 2A / 2B Done Criteria |
| `test/library_row_toggle_test.dart` S-12713 / S-12719 | its edit draft keeps the copy's serving triple (L274-277) | Serving-preserving → keep path → green | Phase 2B full suite |
| `nutrition_trend_card.dart` `SegmentedButton` (~L111) | precedent only | Untouched | none needed |

### UI Standards Impact

Read `test/helpers/ui_standards_allowlist.dart` and `docs/design_system.md` ("Shared pieces and rules per job"). Findings:

- **`SegmentedButton`** (`food_form_basis`): the S-2601 button-shape scan covers `TextButton` / `FilledButton` / `OutlinedButton` / `ElevatedButton` constructor names only (`test/ui_standards_contract_test.dart` L30-60) — `SegmentedButton` is not scanned, so no allowlist entry and no ratchet change (AC-6). Style follows the existing precedent in `lib/features/nutrition/widgets/nutrition_trend_card.dart` ~L111: `ButtonStyle` with selected = primary background / onPrimary foreground, unselected = surface background / textSecondary foreground, `RoundedRectangleBorder` with `OmniTheme.buttonUtilityRadius`.
- **Package link** (`food_form_package_link`): a `TextButton` carrying an explicit `shape:` (`RoundedRectangleBorder`, `OmniTheme.buttonUtilityRadius`), like the existing `TextButton` sites in `lib/features/nutrition/add_food_screen.dart` (~L1043) — satisfies the S-2601 shape rule without an allowlist entry.
- **Chips** (`food_form_serving_chip_<word>`): `FilterChip` in a `Wrap(spacing: 8, runSpacing: 8)`, the app's precedent (`lib/features/exercise/exercise_editor_screen.dart` ~L538). Not scanned; no entry.
- No new dialog or bottom sheet (hand-built ratchets 16 / 9 untouched), no raw `Card`, no `Colors.white` / `Colors.black` (`food_form.dart` is in neither ratchet map — theme tokens only).
- `docs/design_system.md` has no segmented-control entry in "Shared pieces and rules per job"; Phase 3 adds a rule only if the reviewer finds drift (predicted: no edit).

### Iteration 1

#### Phase 1: mapper and state rule (@developer)

1. [x] Create `lib/core/utils/food_serving.dart`: the choice type (sealed classes `Per100G`, `Per100Ml`, `PackageServing{amount, label}`, `NamedServing{label}`, `AsSavedServing{unitType, amount, label}`), `servingChoiceFrom(FoodUnitType, double, String)`, `storedServingFrom(choice)` returning a `(FoodUnitType, double, String)` record, and `servingHeading(choice)` — rules exactly D-92b.1-D-92b.4; imports only `package:omnitrain/data/models/models.dart` and `food_helpers.dart` (for `formatGrams`), no Flutter import — `lib/core/utils/food_serving.dart` · `servingChoiceFrom`
2. [x] Create `test/food_serving_test.dart`: S-92b.1 — the round trip over the 28 catalog triples from `FoodCatalogSeed.sampleCatalogFoods` plus the 5 odd cases, and the per-choice assertions (grams/100/`g` → 100 g, grams/100/`ml` → 100 ml, grams/28/`g` → package 28 g, count/1/`slice` → serving `slice`, the five odd cases → As saved) — `test/food_serving_test.dart` · test `S-92b.1 round trip`
3. [x] `food_library_state.dart` `editLibraryFood` (~L1008, the `current.copyWith(...)` block ~L1034-1050): when the draft's serving triple differs from `libraryCopy`'s, pass `lastAmountConsumed: null` (the `Food.copyWith` sentinel clears); when equal, keep. Add a private `_servingChanged(Food, FoodDraft)` helper in the same file — `lib/state/food_library_state.dart` · `editLibraryFood`, `_servingChanged`
4. [x] `food_library_state.dart` `_propagateCatalogEditToLinkedFoods` (~L749): both loops pass `lastAmountConsumed: servingChanged ? null : <kept>` — loop 1 `updatedLibFood` (~L785-795, compares the catalog's old triple with the new one), loop 2 `upgradedLibFood` (~L805-815, compares the legacy food's triple with the new catalog triple) — `lib/state/food_library_state.dart` · `_propagateCatalogEditToLinkedFoods`
5. [x] `food_library_state.dart` `resetLibraryFood` (~L1088, the explicit `Food(...)` at ~L1115-1135): pass `lastAmountConsumed: servingChanged(copy triple → catalog triple) ? null : copy.lastAmountConsumed` — `lib/state/food_library_state.dart` · `resetLibraryFood`
6. [x] `test/food_library_copy_edit_test.dart`: S-92b.10 edit + reset legs in BOTH groups — 'FoodLibraryState edit own copy (Mock)' (L112) and '(Hive)' (L401): a serving-changing edit clears a seeded 150; a name-only edit keeps it; a reset after a serving-changing edit clears — `test/food_library_copy_edit_test.dart` · new `test(...)` in each group
7. [x] `test/food_library_copy_edit_test.dart`: S-12702 (L140) and S-12704 (L218) get serving-preserving drafts at their `editLibraryFood(copy, _draft())` call sites (L150 and the S-12704 edit) so their `lastAmountConsumed` assertions (L153, L246) become the keep-path guards (D-92b.12) — `test/food_library_copy_edit_test.dart` · S-12702, S-12704
8. [x] `test/food_library_edit_test.dart`: S-92b.10 propagation legs in group 'FoodLibraryState updateCatalogFood' (L337), beside the S-003 preserve test (L591): a serving-changing catalog edit clears the linked library copy's value; a name-only one keeps it — `test/food_library_edit_test.dart` · new `test(...)`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/food_serving_test.dart test/food_library_copy_edit_test.dart test/food_library_edit_test.dart` (paste pass/fail counts) · `.github/copilot/scripts/macos/gateway.sh lint` (0 errors; issue count vs the 180 baseline) · `.github/copilot/scripts/macos/gateway.sh format lib/core/utils/food_serving.dart test/food_serving_test.dart` (new-files-only) · prove-red: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/food_library_copy_edit_test.dart test/food_library_edit_test.dart` must FAIL on base (the new S-92b.10 tests are red there; the files compile at base) · S-92b.1 cannot compile at base (the file does not exist there): prove it by mutation instead — in `servingChoiceFrom`, map label `ml` to `Per100G`, run `test test/food_serving_test.dart`, it must FAIL, then restore the file verbatim · Progress + Assumption Log updated.

**Predicted Files**: `lib/core/utils/food_serving.dart` (new), `test/food_serving_test.dart` (new), `lib/state/food_library_state.dart`, `test/food_library_copy_edit_test.dart`, `test/food_library_edit_test.dart` — nothing else.

**Phase 1 verification notes (Conductor, date):** _added at verification_

#### Phase 2A: the control for a new food (@developer)

Depends on Phase 1 (the mapper).

1. [x] `food_form.dart` `_FoodFormState`: remove `_unitType` (L210), `_referenceAmount` / `_referenceLabel` (L173-174), their focus nodes (L190-191), the initState seeding (L225-244) and the select-all bindings for them (L261-267), and their dispose calls (L285-295); add `ServingChoice _servingChoice` (initState: New Food → `Per100G`; edit mode loads through `servingChoiceFrom`), `_servingLabelController`, `_packageAmountController`, `_packageOpen`; update the class doc comment's field list (L39-40 drops the AC-1 strings) — `lib/features/nutrition/widgets/food_form.dart` · `_FoodFormState`
2. [x] `food_form.dart` build: remove the unit-type dropdown (L497-531, including its text-matching `onChanged` L517-527) and the reference Row (L533-575); add the `SegmentedButton` (key `food_form_basis`; segments `100 g` / `100 ml` / `1 serving`; style per the `nutrition_trend_card.dart` ~L111 precedent) with the fourth `As saved: <amount> <label>` segment rendered only when the loaded choice is `AsSavedServing` (its selection behaviour and tests are Phase 2B) — `lib/features/nutrition/widgets/food_form.dart` · build
3. [x] `food_form.dart` build: the package row under `100 g` / `100 ml` (D-92b.11) — link `food_form_package_link` (`TextButton` with an explicit `shape:`, per UI Standards) toggling `_packageOpen`, and the `Serving size (g)` / `(ml)` field `food_form_package_amount` (hint `30`, validator `_validatePositiveDouble` L695, the existing `^\d*\.?\d*$` formatter) — `lib/features/nutrition/widgets/food_form.dart` · build
4. [x] `food_form.dart` build: the serving row under `1 serving` (D-92b.11) — field `food_form_serving_label` (`Called a…`, hint `slice`, required error `Name the serving, e.g. slice`) plus `FilterChip`s `food_form_serving_chip_<word>` for slice, scoop, bar, piece, cup in a `Wrap` (a chip is selected when its word equals the field text; tapping fills the field) — `lib/features/nutrition/widgets/food_form.dart` · build
5. [x] `food_form.dart` build: heading `food_form_per_heading` = `servingHeading(_servingChoice)` replacing `Macros (the reference above)` (L577); the package and serving fields' `onChanged` call `setState` so the heading follows typing (D-92b.4) — `lib/features/nutrition/widgets/food_form.dart` · build
6. [x] `food_form.dart` `_onSave` (~L409-411): the draft triple comes from `storedServingFrom(_servingChoice)`; validation per D-92b.8 (serving label non-empty after trim; package amount > 0) — `lib/features/nutrition/widgets/food_form.dart` · `_onSave`
7. [x] Create `test/food_form_serving_test.dart` (Mock-first `testWidgets`): S-92b.2 (Part 2A-i) and S-92b.3, S-92b.4, S-92b.5, S-92b.12, S-92b.13, S-92b.15 (Part 2A-ii) — group 'FoodForm serving (S-92b)' — `test/food_form_serving_test.dart` · one `testWidgets` per scenario
8. [x] `test/nutrition_test.dart`: rewrite BOTH tests that type the old keys — 'fills the form, saves, and the new food is rendered in the library' (L1906; old keys at L1956-1960) and 'the New Food bottom bar says Save, not Create (S-92a.10)' (L2046; old keys at L2094-2098) — to the new control (the 50 g case goes through `food_form_package_link` + `food_form_package_amount`; the S-92a.10 case keeps the default 100 g) — `test/nutrition_test.dart` · both `testWidgets`

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test test/food_form_serving_test.dart test/nutrition_test.dart test/food_form_decimals_and_autofocus_test.dart test/food_form_orphan_category_test.dart test/food_form_pick_saves_test.dart test/edit_food_save_test.dart` (paste counts) · `.github/copilot/scripts/macos/gateway.sh test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green (AC-6) · `.github/copilot/scripts/macos/gateway.sh lint` (0 errors; vs the 180 baseline) · `.github/copilot/scripts/macos/gateway.sh format lib/features/nutrition/widgets/food_form.dart test/food_form_serving_test.dart` · prove-red: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/food_form_serving_test.dart` must FAIL on base (the new keys do not exist there; the file compiles at base because it only uses `Key` lookups) · file-tool grep: the three old keys and the four AC-1 strings have zero hits in `lib/features/` (record counts in the evidence file) · Progress + Assumption Log updated.

**Predicted Files**: `lib/features/nutrition/widgets/food_form.dart`, `test/food_form_serving_test.dart` (new), `test/nutrition_test.dart` — nothing else.

**Phase 2A verification notes (Conductor, date):** _added at verification_

#### Phase 2B: existing foods (@developer)

Depends on Phase 2A.

1. [x] `food_form.dart` initState: edit mode loads the choice through `servingChoiceFrom(initial.unitType, initial.referenceAmount, initial.referenceLabel)` (D-92b.2 — doubles like `100.0` / `1.0` load through the numeric value, never text) and stores the opened triple (`_openedServing`) for the note and the As-saved segment — `lib/features/nutrition/widgets/food_form.dart` · `_FoodFormState.initState` — done: `_openedServing` is a `(FoodUnitType, double, String)?` set beside the 2A `servingChoiceFrom` load; the load itself needed no change.
2. [x] `food_form.dart`: the D-92b.6 note — `food_form_per_note` reading `Check these numbers are per <X>` under the heading, shown in edit mode while `storedServingFrom(_servingChoice)` differs from `_openedServing`, hidden when equal, never for a New Food — `lib/features/nutrition/widgets/food_form.dart` · build — done: `_perNote` getter compares `storedServingFrom(_currentChoice)` (A-92b.16) and reuses `servingHeading`'s text, so the note and the heading can never disagree.
3. [x] `test/food_form_serving_test.dart`: S-92b.6 (Egg seeded count / 1.0 / `egg`, both directions; Rice grams / 100 / `g` → count / 1 / `cup`), S-92b.7 (Beef jerky grams / 28 / `g` shows `28`, not `28.0`), S-92b.8 (As saved count / 3 / `tbsp`, including the round trip back), S-92b.9 (the note appears and hides; macros preserved), S-92b.11 (Milk grams / 100 / `ml`) — `test/food_form_serving_test.dart` · one `testWidgets` per scenario — done: five `testWidgets`, each seeding a catalogue food and opening the real `EditFoodScreen`; 16/16 in the file.
4. [x] `test/food_form_serving_test.dart`: the appended edge scenarios S-92b.14 (package row survives a rebuild), S-92b.16 (both hosts render `food_form_basis`), S-92b.18 (switching keeps typed values), S-92b.19 (note hidden at package-100 equality) — `test/food_form_serving_test.dart` · one `testWidgets` per scenario — done: three new `testWidgets` (S-92b.18 was already green from 2A) plus shared edit-host helpers.
5. [x] Fix any other test the removal breaks (expected: none beyond Phase 1's two — the impact table's grep found no other reader of the old keys); run the full suite once with a 900 s timeout, Mock-first, Hive seeded in `setUp` — whole `test/` · full suite — done: no other test broke; full suite 5918 passed / 2 skipped / 0 failed (the 2A `logger_feedback_controls_test.dart` red is green in this working tree).
6. [x] Residue sweep (file tools, counts recorded in the evidence file): grep `lib/` for the three old keys (zero tolerance) and the four AC-1 strings (only the `models.dart` ~L1946-1953 doc comments may remain, per D-92b.10); grep `test/` for the old keys (zero) — `lib/`, `test/` · grep — done: keys 0 in `lib/`, 6 hits in `test/` all inside `findsNothing` assertions; AC-1 strings only the three `models.dart` doc comments.
7. [x] Progress + Assumption Log update; hand off to Phase 3 — plan file · Progress — done.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test test/food_form_serving_test.dart` (paste counts) · full `.github/copilot/scripts/macos/gateway.sh test` (900 s timeout; paste counts) · `.github/copilot/scripts/macos/gateway.sh test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green · `.github/copilot/scripts/macos/gateway.sh lint` (0 errors; vs the 180 baseline) · prove-red: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/food_form_serving_test.dart` must FAIL on base (the 2B scenarios are red there) · the residue grep counts recorded in the evidence file · Progress + Assumption Log updated.

**Predicted Files**: `lib/features/nutrition/widgets/food_form.dart`, `test/food_form_serving_test.dart`, plus any test file the full suite proves broken (each named in the Assumption Log) — nothing else.

**Phase 2B verification notes (Conductor, date):** _added at verification_

#### Phase 3: docs (@developer)

Depends on Phase 2B. Doc sizes today (all under the 52 KiB band; the contract test warns past it): `docs/nutrition.md` 31.6 KB, `docs/state_management/nutrition_state.md` 26.9 KB, `docs/widget_catalog/nutrition_widgets.md` < 20 KB.

1. [x] `docs/widget_catalog/nutrition_widgets.md` `FoodForm` section (~L120-165): replace the "field set … read them in food_form.dart" hedge for the serving part with the serving contract — the `food_form_basis` control and its segments, the package link and field, the serving field and chips, `food_form_per_heading`, `food_form_per_note`, the D-92b.7 conditional clear, and the verifying tests — `docs/widget_catalog/nutrition_widgets.md` · FoodForm section — done: Serving control subsection + mapping table; 16 form tests and 6 mapper tests named.
2. [x] `docs/nutrition.md`: the EditFoodScreen section (~L206-240) describes the new control; the reset description (~L251, "keeping the copy's … last amount") gains the conditional (cleared when the serving changed, kept otherwise); L29 (model description) stays — `docs/nutrition.md` · EditFoodScreen + reset paragraphs — done: control paragraph, conditional reset, and the same rule on catalog propagation.
3. [x] `docs/state_management/nutrition_state.md`: the `editLibraryFood` row (~L143) and the `resetLibraryFood` row (~L145) replace "Keeps … lastAmountConsumed" with the conditional rule (D-92b.7); the propagation section (~L179-180) likewise — `docs/state_management/nutrition_state.md` · method table rows — done: both rows + `updateCatalogFood` + the pencil consumer bullet; test names added.
4. [x] Checked-no-edit (record in the evidence file): `docs/data_models.md` L394 (`FoodUnitType` — model, unchanged), `docs/db_integration.md` L520 (snapshot contract — unchanged), `docs/documentation_standard.md` L253, `docs/nutrition.md` L29, `docs/state_management/nutrition_state.md` L50 — `docs/` · none — done: reasons in the evidence file; residue grep 0 hits outside `docs/plans/`.
5. [x] `docs/design_system.md`: no edit predicted (the `SegmentedButton` precedent already exists in `nutrition_trend_card.dart`); add a rule only if the Phase 2B review found drift — `docs/design_system.md` · none predicted — done: no edit; the precedent holds.
6. [x] Plan status → implementation complete, pending review; Progress updated — plan file · Status — done (the reviewer closes it; brief supersedes the seed's CLOSED).

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` green (doc sizes within the band) · the no-edit checks recorded in the evidence file · Progress updated.

**Predicted Files**: `docs/widget_catalog/nutrition_widgets.md`, `docs/nutrition.md`, `docs/state_management/nutrition_state.md`, the plan file — nothing else.

**Phase 3 verification notes (Conductor, date):** _added at verification_

### Files Affected (whole feature)

- `lib/core/utils/food_serving.dart` — new (Phase 1)
- `test/food_serving_test.dart` — new (Phase 1)
- `lib/state/food_library_state.dart` — Phase 1 (writes: `editLibraryFood`, `_propagateCatalogEditToLinkedFoods`, `resetLibraryFood`)
- `test/food_library_copy_edit_test.dart`, `test/food_library_edit_test.dart` — Phase 1 (writes)
- `lib/features/nutrition/widgets/food_form.dart` — Phases 2A / 2B (writes)
- `test/food_form_serving_test.dart` — new (Phases 2A / 2B)
- `test/nutrition_test.dart` — Phase 2A (rewrite of two tests)
- `docs/widget_catalog/nutrition_widgets.md`, `docs/nutrition.md`, `docs/state_management/nutrition_state.md` — Phase 3 (writes)
- Read-only dependents: `edit_food_screen.dart`, `add_food_screen.dart` (build `FoodForm`, untouched); `lib/data/models/models.dart` (stored fields unchanged; doc comments stay per D-92b.10); `lib/core/utils/food_helpers.dart` (`formatGrams`, read by the mapper); `lib/mock/food_catalog_seed.dart` (fixture source); `test/food_form_decimals_and_autofocus_test.dart`, `test/food_form_orphan_category_test.dart`, `test/food_form_pick_saves_test.dart`, `test/edit_food_save_test.dart`, `test/library_row_toggle_test.dart` (must stay green)

### Notes

- **Phase dependency graph**: 1 → 2A → 2B → 3. Phase 1's state rule (items 3-8) is independent of the form work and could run in parallel with 2A once items 1-2 land; the serial order is kept because 2A's Done Criteria run the state test files too. Re-ordering trade-off: running 2A first gives the visible win sooner but leaves S-92b.10's stale-keep bug live in the meantime.
- **Intermediate state after 2A**: edit mode already loads and saves through the mapper (loading is in 2A's item 1), so the app is consistent; the note, the As-saved selection behaviour and the 2B scenarios trail in 2B. The suite must be green at each phase boundary.
- **Legacy handling**: the text-matching `onChanged` (L517-527) is deleted, not deprecated — no compat shim, no feature flag.
- **The on-device bug** the seed fixes: initState seeds `(initial?.referenceAmount ?? 100).toString()` = `100.0` (L225-227), so the base's `_referenceAmount.text == '1'` / `'100'` comparisons (L519-526) never fire on a device; the mapper compares numeric values, never text (D-92b.3).
- **Widget tests are FakeAsync**: run Mock-first, seed Hive in `setUp`, never await a real `Future.delayed` or a Hive write inside `testWidgets` (`docs/global_conventions.md`).

### Progress

- [x] Phase 1 — mapper and state rule — **Complete.** Mapper + `_servingChanged` rule in place; 44/44 in the three owned files, prove-red RED AT HEAD (6 guarded failures), mutation caught by S-92b.1, full suite 5902 passed / 2 skipped / 0 failed, lint 180 (baseline). Evidence in the `.evidence.md`.
- [x] Phase 2A — the control for a new food — **Complete** (Part 2A-i: items 1-6, 8, S-92b.2; Part 2A-ii: item 7's remaining scenarios S-92b.3, S-92b.4, S-92b.5, S-92b.12, S-92b.13, S-92b.15): the control, package row, serving row, heading, validation and mapper-based save/load are in; targeted file 8 passed / 0 failed, UI standards contract 41 passed, lint 180 (baseline), three mutation proofs red then restored (S-92b.12, S-92b.13, S-92b.5). Full suite 5909 passed / 2 skipped / 1 failed — the red is `logger_feedback_controls_test.dart` S-5115, GREEN AT HEAD and red only with the working tree's uncommitted hands-off sources (A-92b.15). Evidence in the `.evidence.md`.
- [x] Phase 2B — existing foods — **Complete**: the D-92b.6 note (`_openedServing` + `food_form_per_note`), the As-saved selection round trip, and S-92b.6, S-92b.7, S-92b.8, S-92b.9, S-92b.11, S-92b.14, S-92b.16, S-92b.19 are in; targeted file 16 passed / 0 failed, UI standards + docs contract 54 passed, lint 180 (baseline, none in the touched files), full suite 5918 passed / 2 skipped / 0 failed. prove-red RED AT HEAD on the two note guards (S-92b.9, S-92b.19); the five behaviour guards that already pass at HEAD were proven red by mutation (S-92b.19 note-always, S-92b.7 `.toString()`, S-92b.8 As-saved restore) and restored (A-92b.17). Evidence in the `.evidence.md`.
- [x] Phase 3 — docs — **Complete**: the FoodForm serving contract + field-mapping table in `docs/widget_catalog/nutrition_widgets.md`, the control / conditional reset / propagation rule in `docs/nutrition.md`, and the D-92b.7 conditional rows in `docs/state_management/nutrition_state.md`; five checked-no-edits and the zero-hit residue sweep recorded in the `.evidence.md`; docs contract 13 passed, UI standards contract 41 passed, full suite 5918 passed / 2 skipped / 0 failed, lint 180 (baseline).
- [x] Status → implementation complete, pending review (the reviewer closes it).

### Assumption Log

_Executors append here (decision made, options considered, choice + why). The conductor marks each RATIFIED (promote to D-x) or REVERT (remediation) at verification._

- **A-92b.1 (planner, derived — vetoable).** The seed's Phase 2A says "the one test that types reference amount/label (`test/nutrition_test.dart` ~L1950)". Grep shows TWO: L1906 ('fills the form, saves…', keys at L1956-1960) and L2046 ('the New Food bottom bar says Save, not Create (S-92a.10)', keys at L2094-2098). Both are rewritten in Phase 2A item 8; leaving the second would fail AC-1's zero-key grep.
- **A-92b.2 (planner, derived — vetoable).** AC-1's string ban read as targeting user-facing strings/keys; `models.dart` ~L1946-1953 doc comments keep the terms (D-92b.10). Options: rewrite the model doc comments too (edits a file the feature otherwise never touches, for no user-visible change) vs scope the ban. Chose scoping; the Phase 2B sweep records the exception explicitly.
- **A-92b.3 (planner, derived — vetoable).** S-12702/S-12704 resolved by serving-preserving drafts (keep-path guards) rather than flipping their assertions to `isNull` (D-92b.12). Options: flip to null (loses the equal-triple-keeps coverage AC-5 needs) vs preserve. Chose preserve; the clearing legs live in the new S-92b.10 tests.
- **A-92b.4 (planner, derived — vetoable).** Phase 2A renders the As-saved fourth segment (it is part of "the control", D-92b.5) while the seed lists "As saved segment" under Phase 2B; 2B owns its loading, selection behaviour and scenarios (S-92b.8). Options: defer the segment's widget to 2B (2A's `food_form_basis` would be incomplete for edit-mode pumps) vs render early. Chose render-in-2A, behaviour + tests-in-2B.
- **A-92b.5 (planner, derived — vetoable).** The package link is a `TextButton` with an explicit `shape:` (S-2601-compliant, no allowlist entry) rather than a bare `InkWell` + Text. Options: InkWell (unscanned, but no in-form precedent) vs TextButton + shape (the form's own precedent). Chose TextButton + shape.
- **A-92b.6 (developer, Phase 1).** Item 7's premise is wrong: the bundled `almond_butter` is count / 1 / `tbsp` (seed ~L1909-1919), and the file's `_draft()` already builds that triple — so it is serving-PRESERVING and S-12702/S-12704 are already the keep-path guards D-92b.12 asks for. Options: edit the seed fixture (data layer, out of scope) vs leave the drafts. Chose leaving `_draft()` untouched; a `_draftKeepingServing` replacement made both red (8 failures). Clearing legs run through the new `_draftChangingServing()` (grams / 100 / `g`).
- **A-92b.7 (developer, Phase 1).** D-92b.2's "the five odd cases → As saved" is loose: rule 3 makes `(grams, 100.5, g)` a `PackageServing`. Options: special-case 100.5 as As saved (contradicts rule 3 as written) vs follow rule 3. Chose rule 3 (a real device can store a fractional per-100 amount only with a non-`g` label); `test/food_serving_test.dart` asserts the package case and the four genuine As-saved cases separately.
- **A-92b.8 (developer, Phase 1).** No doc was edited in this phase. The plan assigns all doc writes to Phase 3; Phase 1 adds a pure mapper and a state rule, changes no screen, route, widget or constructor dependency. Recorded as a checked-no-edit in the `.evidence.md`.
- **A-92b.9 (developer, Part 2A-i).** The As-saved segment is rendered but inert: selection is not wired to `_asSaved` beyond display (A-92b.4 defers the behaviour to 2B). Options: wire it now (its scenarios S-92b.8 / S-92b.9 are Part 2A-ii's) vs render only. Chose render only, so `food_form_basis` is complete for edit-mode pumps without untested selection logic.
- **A-92b.10 (developer, Part 2A-i).** The package row's visibility is state (`_packageOpen`), and the amount validator runs only while the field is mounted — so an invalid amount typed and then hidden by closing the row is ignored and the save falls back to `100 g` / `100 ml`. Options: keep validating a hidden field (blocks saving on a value the user can no longer see) vs ignore it. Chose ignore, matching D-92b.11's "the field belongs to the segment it is open under".
- **A-92b.11 (developer, Part 2A-i).** `gateway.sh format` refuses tracked files, so `lib/features/nutrition/widgets/food_form.dart` could not be machine-formatted; it was hand-formatted to the surrounding style and `lint` reports no notice in it. Only the new `test/food_form_serving_test.dart` was formatted by the gateway.
- **A-92b.12 (developer, Part 2A-i).** Edit mode loading a `PackageServing` rides the `100 g` / `100 ml` segment with the package row already open, rather than adding a fifth segment. Options: a dynamic package segment vs the base segment + open row. Chose base + open row: it keeps the segment set stable and is what Part 2A-ii's S-92b.7 expects (`28`, not `28.0`).
- **A-92b.13 (developer, Part 2A-ii).** The new 2A-ii tests pump the form on an 800x3000 surface rather than S-92b.2's 800x1800: the serving row and the open package row push the chips below the shorter viewport, where `tester.tap` would miss them. Options: keep 1800 and `ensureVisible` before every tap (brittle) vs a taller surface. Chose 800x3000 in the new `_pumpNewFoodForm` helper; S-92b.2 is unchanged.
- **A-92b.14 (developer, Part 2A-ii).** `gateway.sh format test/food_form_serving_test.dart` is refused now that the file is tracked ("only runs on files this change created"), so the brief's format step could not run; the additions follow the surrounding style and `lint` reports no notice in the file. Same recorded state as A-92b.11. The restore check is `git-diff --stat -- lib/features/nutrition/widgets/food_form.dart` empty plus 0 `MUTANT` hits in `lib`/`test`.
- **A-92b.15 (developer, Part 2A-ii).** The full suite ends `5909 passed / 2 skipped / 1 failed`, and the one red is not this run's: `logger_feedback_controls_test.dart` S-5115 (rolling list view) is GREEN AT HEAD via `prove-red HEAD test test/logger_feedback_controls_test.dart` and red only with the working tree's uncommitted hands-off `lib/state/workout/` + `session_summary_screen.dart` edits. Left untouched (another feature's test, hands-off sources). Options: edit that test (forbidden) vs report it. Reported; Phase 2A stays Complete on its own checks.
- **A-92b.16 (developer, Phase 2B).** Item 2 says the note compares `storedServingFrom(_servingChoice)`; it compares `storedServingFrom(_currentChoice)`. Options: `_servingChoice` (the note would ignore the typed package amount until the segment changes, contradicting S-92b.19) vs `_currentChoice` (what the heading renders and what `_onSave` writes). Chose `_currentChoice` so note, heading and saved draft can never disagree.
- **A-92b.17 (developer, Phase 2B).** `prove-red HEAD test test/food_form_serving_test.dart` is RED AT HEAD only for the two note guards (S-92b.9, S-92b.19 — `Actual: <null>` where the note text is expected); S-92b.6/7/8/11/14/16 pass at HEAD because 2A shipped the edit-mode load, the As-saved rendering, the package row and both hosts. Options: delete those guards (loses the regression net) vs keep them proven by mutation. Kept; three mutations (note-always → S-92b.19 red, `amount.toString()` → S-92b.7 red, As-saved not restoring → S-92b.8 red) were run and restored exactly.
- **A-92b.18 (developer, Phase 2B).** `gateway.sh format test/food_form_serving_test.dart` is refused again ("only runs on files this change created"; the file is tracked), so the brief's format step could not run; `lint` reports no notice in either touched file. Same recorded state as A-92b.11 / A-92b.14; the restore check is 0 `MUTANT` hits in `lib`/`test`.
- **A-92b.19 (developer, Phase 2B).** No doc was edited: the plan assigns every doc write to Phase 3, and this phase changes no screen, route, widget prop or state API — the note is a private detail inside `FoodForm`. Recorded as a checked-no-edit in the `.evidence.md` per A-92b.8's precedent.

### Feedback

- **Part 2A-ii full-suite note (developer).** All seven 2A-ii scenarios pass and the targeted file is 8/8, but the full suite carries one red outside this plan: `test/logger_feedback_controls_test.dart` S-5115 (rolling list view) fails in the working tree while `prove-red HEAD test test/logger_feedback_controls_test.dart` passes at HEAD, so the uncommitted hands-off sources under `lib/state/workout/` are the cause. The test and those sources were not touched; the governor should green that suite before Phase 2B starts.

[empty — fold into a new Iteration block when non-empty, then clear]

## Open questions

None blocking. The derived decisions above (D-92b.10..12, A-92b.1..5) are vetoable before the first handoff that depends on them; the three that reinterpret the seed are:

1. The seed's Phase 2A says "the one test that types reference amount/label", but two tests do (evidence: `test/nutrition_test.dart` L1906 and L2046, keys at L1956-1960 and L2094-2098). Default applied: both rewritten in Phase 2A (A-92b.1).
2. AC-1 bans the strings "Unit type" / "Reference amount" / "Reference label" in `lib/`, but `lib/data/models/models.dart` ~L1946-1953 doc comments use them for the stored fields this feature must not change. Default applied: the ban covers user-facing strings/keys; the model doc comments stay (D-92b.10, A-92b.2).
3. The seed lists the "As saved segment" under Phase 2B, but D-92b.5 makes it part of the control Phase 2A builds. Default applied: 2A renders the segment, 2B owns its behaviour and tests (A-92b.4).
