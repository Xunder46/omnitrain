# Plan — Food form: decimal macros & auto-select on focus

## Overview

Two small input-field polish items on the food form (`FoodForm`,
`lib/features/nutrition/widgets/food_form.dart`) used by both the
**+ New Item** and **Edit Food** flows:

1. **Allow decimals in macro inputs** — protein, carbs, fiber, fat,
   sodium currently reject `.5` because the form uses
   `FilteringTextInputFormatter.digitsOnly` and `int.parse`. The
   underlying `Food` model stores these as `int`, so storing `.5`
   requires widening the model + draft + state signatures from
   `int` to `double` and the `fromMap`/`toMap` round-trips to use
   the established `((m['k'] as num?) ?? 0.0).toDouble()` pattern.
2. **Auto-select all text on focus** for every text input on the
   form (name, reference amount, reference label, all five macros,
   notes). Today only the *form* (not the individual fields) has a
   `FocusNode`, used for `autoSaveOnBlur`. Per-field `FocusNode`s
   wired to `_selectAll` on focus are needed.

## Requirements

- `Food`, `ConsumedFood`, and `FoodDraft` macro fields
  (`protein`, `carbs`, `fiber`, `fat`, `sodium`) change from `int`
  to `double`.
- `Food.fromMap` / `ConsumedFood.fromMap` use the `((m['k'] as
  num?) ?? 0.0).toDouble()` pattern so existing SQLite INTEGER
  rows still read back correctly.
- `FoodLibraryState.createCustomFood` parameter types change from
  `int` to `double` (the only public `int` macro surface in state).
  All other call sites pass a `FoodDraft`, so the surface change
  is contained to `createCustomFood` and the matching call sites
  in tests.
- `FoodForm` macro fields accept `0.5`, `12.25`, etc. The
  `digitsOnly` formatter is replaced with the same decimal regex
  the reference-amount field already uses (`^\d*\.?\d*$`). The
  validator and `int.parse` switch to `double.tryParse` /
  `double.parse`; the validator message changes from
  `"Must be a whole number"` to `"Must be a number"`.
- Every `TextFormField` in `FoodForm` (name, reference amount,
  reference label, protein, carbs, fiber, fat, sodium, notes)
  gets a per-field `FocusNode` that calls `controller.selection =
  TextSelection(baseOffset: 0, extentOffset: controller.text.length)`
  on focus. `dispose` cleans up the focus nodes.
- `Food` and `ConsumedFood` model docs in
  `docs/data_models.md` are updated to note `double` macros.
- `docs/db_integration.md` notes the `double` columns on the
  SQLite schema and the back-compat read path.

## Acceptance Criteria

- [ ] `Food.protein`, `Food.carbs`, `Food.fiber`, `Food.fat`,
  `Food.sodium` are `double` and round-trip through
  `Food.toMap` / `Food.fromMap` for integer, fractional, and
  null values.
- [ ] `ConsumedFood` macros are `double` and round-trip the same
  way.
- [ ] `FoodDraft` macros are `double`.
- [ ] `FoodLibraryState.createCustomFood` accepts `double` macros.
- [ ] `FoodForm` macro field accepts `0.5`, `1.25`, and `12` (the
  last as a regression for the existing integer path) and rejects
  `1.2.3` and `abc`.
- [ ] `FoodForm` saves a `0.5` fat food end-to-end (form → state →
  repository → cached `Food`) and the cached `Food.fat` is `0.5`.
- [ ] Focusing a `TextFormField` on `FoodForm` with pre-existing
  text selects all text in that field; focusing an empty field is
  a no-op (no exception).
- [ ] `flutter test test/screen_widget_test.dart
  test/nutrition_test.dart test/models_test.dart
  test/food_form_pick_saves_test.dart` is green.
- [ ] `flutter analyze lib/` and `flutter analyze test/` are
  clean.

## Scenarios

### S-001: User enters a fractional macro value in a blank food form
- Trigger: User on `AddFoodScreen` taps into the **Fat (g)** field
  and types `0.5`
- Precondition: Fresh create form, no draft, no image
- Flow: Type `0.5` in Fat → tap **Save** in the bottom CTA
- Expected outcome: Food is persisted; cached `Food.fat == 0.5`;
  no validation error snackbar; total calories reflect
  `0.5 * 9 = 4.5 → 5 kcal` (rounded at the calorie boundary)
- Edge case of: none

### S-002: User edits an existing food's protein to a decimal
- Trigger: User on `EditFoodScreen` changes **Protein (g)** from
  `31` to `31.5` and blurs
- Precondition: Existing catalog food with `protein = 31`
- Flow: Change protein field to `31.5` → form auto-saves on blur
- Expected outcome: `Food.protein` is now `31.5`; macro ring
  recomputes (rounded display)
- Edge case of: S-001

### S-003: User enters a non-numeric macro value
- Trigger: User types `abc` into **Carbs (g)**
- Flow: Type `abc` → tap Save
- Expected outcome: Form validation surfaces
  `"Must be a number"`; save is blocked; no row is created
- Edge case of: none

### S-004: Focusing a pre-filled macro field selects all text
- Trigger: User on `EditFoodScreen` taps into the **Fat (g)**
  field (which is pre-filled with `4`)
- Precondition: Existing catalog food with `fat = 4`
- Flow: Tap on the field
- Expected outcome: The text `4` is fully selected, so typing
  `0` replaces it (not appends), letting the user overwrite
  quickly
- Edge case of: none

### S-005: Focusing an empty macro field is a no-op
- Trigger: User on `AddFoodScreen` taps into the **Fiber (g)**
  field (which is empty)
- Precondition: Fresh form, Fiber is empty (optional)
- Flow: Tap on the field
- Expected outcome: Focus is granted; no exception; selection is
  collapsed (cursor at start, length 0)
- Edge case of: S-004

### S-006: Auto-select applies to every text input in FoodForm
- Trigger: User opens the form and sequentially taps Name,
  Reference amount, Reference label, Protein, Carbs, Fiber, Fat,
  Sodium, Notes (where present)
- Precondition: Form is mounted; some fields are pre-populated
  from `widget.initial` (edit mode)
- Flow: Tap each field in turn
- Expected outcome: Every field with non-empty pre-fill has its
  text selected on focus; empty fields accept focus normally
- Edge case of: S-004, S-005

### S-007: Decimal value round-trips through SQLite-style map
- Trigger: A `Food.fromMap` row has `'protein': 1.5` (REAL)
- Flow: `Food.fromMap({'protein': 1.5, ...})` → field read
- Expected outcome: `food.protein == 1.5`
- Edge case of: none

### S-008: Integer row still reads back as integer-valued double
- Trigger: A legacy `Food.fromMap` row has `'protein': 31`
  (INTEGER)
- Flow: `Food.fromMap({'protein': 31, ...})` → field read
- Expected outcome: `food.protein == 31.0` (no exception)
- Edge case of: S-007

## Iteration 1

### DB Changes
- `scripts/sqlite_schema.sql`:
  - `app_food` table: change `protein INTEGER`, `carbs INTEGER`,
    `fiber INTEGER`, `fat INTEGER`, `sodium INTEGER` to
    `REAL NOT NULL` (fiber and sodium stay nullable).
  - `app_consumed_food` table: same column-type widening.
  - Add a SQL comment block above each change noting: "Macros
    were `INTEGER` in the bundled v1 schema; widened to `REAL` in
    v1.5 to support fractional grams. Existing rows with integer
    values are still readable because the column has no CHECK
    constraint and the repository's `fromMap` casts via
    `((m['k'] as num?) ?? 0.0).toDouble()`."
- No seed-data changes required (all current seed values are
  integers; the new column type accepts them).

### Backend Changes
- `lib/data/models/models.dart`:
  - `Food`: `protein`, `carbs`, `fiber`, `fat`, `sodium` →
    `double`. `calories` and `netCarbs` getters continue to
    return `int` (`.round()` at the boundary).
  - `Food.copyWith`: same parameter types change.
  - `Food.fromMap`: replace `m['protein'] as int`,
    `m['carbs'] as int`, `m['fiber'] as int?`, `m['fat'] as int`,
    `m['sodium'] as int?` with
    `((m['protein'] as num?) ?? 0.0).toDouble()` etc.
  - `ConsumedFood`: same field/constructor/`copyWith`/`fromMap`
    changes. `caloriesConsumed` formula unchanged
    (double math + `.round()`).
- `lib/core/models/food_draft.dart`:
  - `FoodDraft`: `protein`, `carbs`, `fiber`, `fat`, `sodium` →
    `double`.

### Frontend Changes
- `lib/features/nutrition/widgets/food_form.dart`:
  - Add per-field `FocusNode` for: name, reference amount,
    reference label, protein, carbs, fiber, fat, sodium, notes.
    Wire each to a `_selectAll` handler that runs on `focusNode`
    focus events; dispose them in `dispose`.
  - `_macroField`:
    - `inputFormatters`: `digitsOnly` →
      `[FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))]`
      (mirrors the reference-amount field).
    - `keyboardType`: `TextInputType.number` →
      `TextInputType.numberWithOptions(decimal: true)`.
    - Validator: `int.tryParse` → `double.tryParse`; error
      message `"Must be a whole number"` →
      `"Must be a number"`.
  - `_onSave`: `int.parse(_protein.text.trim())` etc. →
    `double.parse(...)`; `int.parse(fiberRaw)` (in the optional
    branch) → `double.parse(fiberRaw)`.
- `lib/state/food_library_state.dart`:
  - `createCustomFood`: macro parameter types `int` → `double`.
- `lib/features/nutrition/add_food_screen.dart`:
  - `_FoodIdentity`: `protein`, `carbs`, `fiber`, `fat`,
    `sodium` → `double` (mirror of `Food`).
- `lib/mock/seed_data.dart`:
  - `sampleConsumedFoods` local `row` helper signature:
    `int protein, int carbs, int? fiber, int fat` →
    `double protein, double carbs, double? fiber, double fat`.
  - `olderDayMeals` typedef:
    `int protein, int carbs, int? fiber, int fat` →
    `double protein, double carbs, double? fiber, double fat`.

### Implementation Steps
1. Phase 0 — write this plan file.
2. Phase 1 — widen `Food` + `ConsumedFood` + `FoodDraft` to
   `double`; update `fromMap` casts; update `createCustomFood`
   and the `_FoodIdentity` mirror; update `seed_data.dart`
   helpers; update `sqlite_schema.sql` column types and
   comments. Run `flutter analyze lib/` — must be clean.
3. Phase 2.1 — write tests:
   - `test/screen_widget_test.dart`: S-001..S-006 (decimal
     input, validation, autofocus, no-op on empty).
   - `test/models_test.dart`: S-007, S-008 (REAL and INTEGER
     round-trip on `Food`; same on `ConsumedFood`).
   - `test/edge_case_test.dart` (or existing): S-003 negative
     case (validator error).
   - Confirm tests fail before implementation where they assert
     new behaviour (autofocus, decimal parsing).
4. Phase 2.2–2.5 — implement per-field `FocusNode` + `selectAll`;
   switch macro field formatter, validator, and parser to
   decimal.
5. Phase 2.6 — run targeted tests; iterate to green; run full
   `flutter test` and confirm no regressions.
6. Phase 2.7 — update `docs/data_models.md` (macro types) and
   `docs/db_integration.md` (column widening + back-compat
   read path). Add a brief note in
   `docs/widget_catalog.md` if the macro field's appearance
   changes (it should not — only validation message).
7. Phase 3 — code review per the standard review checklist;
   ensure all `Acceptance Criteria` are met and tests cover
   every scenario in `## Scenarios`.

## Progress

- [x] Phase 0 — Plan written
- [x] Phase 1 — Data layer (models, repository, schema, seed)
- [x] Phase 2.1 — Red tests written
- [x] Phase 2.2-2.5 — Implementation (form fields + focus nodes)
- [x] Phase 2.6 — Tests green (570 passing; 9 new)
- [x] Phase 2.7 — Doc hygiene (data_models.md, db_integration.md, widget_catalog.md)
- [x] Phase 3 — Code review

### Phase 0 Complete ✓

### Phase 1 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓

## Feedback

_(empty — feature delivered end-to-end in one pass.)_
