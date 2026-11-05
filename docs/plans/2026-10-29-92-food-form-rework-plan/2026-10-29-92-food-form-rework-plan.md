# Series 92 — New/Edit Food form: one serving question, a Save button on edit, a form that reads like a label

> Status: 92a CLOSED, 92b CLOSED, 92c CLOSED; owner device checks pending (Edit Food Save and discard, serving control, label-like form). Owner answers 2026-10-29 are binding (D-92.1..D-92.4). Owner approved defaults V-1..V-4 on 2026-10-29: they are now decisions, not vetoable. Phone app only (`lib/`); no data-model change, no watch change.
> Binding conventions: `docs/global_conventions.md`, `docs/design_system.md`, `.github/copilot/pr-scope-budget.md`. Branch: `claude_develop`; git belongs to the governor.
> **Do not start until plan 91 is committed.** It has uncommitted edits in `add_food_screen.dart`, `nutrition_test.dart`, `screen_widget_test.dart` and the nutrition docs, which this series also touches.
> Each PR below gets its own plan file when it is handed off; this index stays short.

## What the user sees

| | Now | After |
|---|---|---|
| Edit Food | no Save button; saves when focus leaves the form; a photo saves the instant it is picked | a bottom **Save**; nothing saves until Save; leaving with changes asks "Discard?" (92a) |
| Serving | Unit type + Reference amount + Reference label (three boxes, one fact) | one question: **Nutrition facts are per** 100 g / 100 ml / 1 serving; "1 serving" asks "called a…" with chips (92b) |
| Package serving | unexplained "Reference amount" | link "Enter package serving instead (e.g. 30 g)" (92b) |
| Macros heading | "Macros (the reference above)" | "Nutrition per 100 g" (live) (92b) |
| Calories | derived, never shown | live "= 120 cal" under the macros (92c) |
| Macro boxes | pre-filled "0.0" / "31.0" | new food: blank with faint "0"; edit: "31" not "31.0" (92c) |
| Photo | top of a new food | below the name (92c) |
| Duplicate name | silent | quiet note under the name, never blocks (92c) |

## Owner decisions (Ledger)

- **D-92.1** Edit gets a bottom Save (`OmniBottomCTA`, key `food_form_save`). Nothing persists until Save, **photo pick and clear included**. Leaving a form with changes asks "Discard?", exactly as New Food does. (Owner: "Nothing saves until Save".)
- **D-92.2** Category is not pre-chosen. The user picks it from the dropdown; the default stays Uncategorized. (Owner: "users can select a category, why pre-choose for them?") No category work in this series.
- **D-92.3** A duplicate name (case-insensitive, trimmed, against the Library: bundled + the user's own) shows a quiet note under the name field and never blocks Save. Applies when renaming in Edit; the food being edited does not match itself. (Owner.)
- **D-92.4** Changing "Nutrition facts are per" on an existing food keeps the typed numbers; the heading updates and a one-line note says "Check these numbers are per 1 slice". Remembered log amounts for that food are reset (see D-92.6). (Owner.)

## Technical decisions (Claude; no owner input needed)

- **D-92.5** The control maps one-to-one onto today's stored fields, so nothing downstream changes (logging row, watch sync, snapshots):

  | Control | unitType | referenceAmount | referenceLabel |
  |---|---|---|---|
  | 100 g | grams | 100 | g |
  | 100 ml | grams | 100 | ml |
  | 1 serving called X | count | 1 | X |
  | package serving, g/ml (e.g. 30 g) | grams | 30 | g (or ml) |

  Package serving applies to g/ml only. A count food's "serving" already is the package unit.
- **D-92.6** Any change to unit type, amount or label on an existing food also clears that food's `lastAmountConsumed` (today a "150 g" memory survives a switch to servings and pre-fills 150 servings). One place in `FoodLibraryState` (`updateCatalogFood`, `editLibraryFood`, `updateCustomFood`).
- **D-92.7** Loading an existing food never rewrites its serving. A food that fits the table maps to a control choice; anything else (legacy "per 100 g" labels, a count food with amount ≠ 1, grams with a label other than g/ml) opens in the package-serving row showing the stored amount and label, and saves byte-identical unless the user changes it. No new stored field.
- **D-92.8** The "100.0" prefill and the "only when the text is exactly 1 or 100" switch logic disappear with the three boxes: the choice is derived from the stored fields, not from box text. Number prefill uses `formatGrams` (`31`, not `31.0`).
- **D-92.9** The unsaved-work probe (`_FoodFormProbe`, private to `add_food_screen.dart`) moves to a shared file so New, the legacy shim and Edit use one guard. Edit mode compares the form's photo to the food's saved photo.

## Approved defaults (owner approved 2026-10-29)

- **V-1** Calories read "= 120 cal" (the app says "cal" everywhere), derived from P·C·F as today (`calculateCalories`, fiber not subtracted). Not typeable: that would need a stored calories field.
- **V-2** Macro order follows a package label in create **and** edit: Fat, Carbs, Fiber, Protein, Sodium, one order everywhere. Alternative: keep Protein, Carbs, Fiber, Fat, Sodium.
- **V-3** Blank Protein/Carbs/Fat save as 0 (the faint "0" hint is what is stored). Blank Fiber/Sodium save as "not recorded" (today a new food stores 0 for both, so the "blank = unset" contract is unreachable). Non-numeric text still fails validation.
- **V-4** The create button's label changes from "Create" to "Save" so both forms say the same word (it already has a bottom button).

## PR split (pr-scope-budget: three small PRs, not one)

### 92a — Edit gets Save (about 150 lines of production code)
`edit_food_screen.dart`, the shared probe file, `add_food_screen.dart` (legacy shim and New use the shared probe; legacy shim loses instant photo save), `food_form.dart` (drop `autoSaveOnBlur`, `onImageSave`, the form-level blur node).
Tests: `test/food_form_pick_saves_test.dart` pins the instant-save-on-pick behaviour this reverses, so it is **rewritten, not patched** (new rule: pick does not write until Save; Discard drops the pick). New: Edit Save writes and pops; back with changes asks; back untouched pops; Reset/Delete buttons still show above Save. Docs: `widget_catalog/nutrition_widgets.md` (the "EditFoodScreen is the exception" paragraph), `nutrition.md`.

### 92b — The serving question (about 250 lines)
`food_form.dart` (new control, chips slate: slice, scoop, bar, piece, cup, plus free text), a small pure mapper (stored fields ↔ choice) in `lib/core/utils/`, D-92.6 in `food_library_state.dart`.
Tests: **round-trip every distinct (unitType, amount, label) in the shipped catalog (28 combinations) through control and back; the draft must be identical.** Plus: legacy-label food saves unchanged (D-92.7); switching basis on an existing food clears `lastAmountConsumed`; the one create test that types reference amount/label (`nutrition_test.dart` ~1950) is rewritten to use the new control. No other test references the serving keys.

### 92c — The rest of the form (about 200 lines)
`food_form.dart`: live calories, macro order, blank boxes + hints, `formatGrams` prefill, photo below name, duplicate note (a name-only check in `FoodLibraryState`; the existing `_matchesIdentity` needs every value to match so it cannot be reused). V-1..V-4 apply here.
Tests: calories line equals `calculateCalories`; blank P/C/F saves 0; blank fiber/sodium saves null; duplicate note shows and does not block, ignores the food's own name in Edit; photo tile order.

## Not in scope

Typing calories directly (needs a model field); pre-selecting a category (D-92.2); any watch change (the watch shows `referenceAmount referenceLabel` and steps in servings, unchanged by D-92.5); the catalog JSON.

## Risks

- Touches files plan 91 has uncommitted (see top).
- 92a reverses an owner-visible behaviour (photo saves instantly) and rewrites one test file.
- D-92.7's fallback row is the only path for odd stored servings; the 27-combination round-trip test is what proves no shipped food is rewritten.
