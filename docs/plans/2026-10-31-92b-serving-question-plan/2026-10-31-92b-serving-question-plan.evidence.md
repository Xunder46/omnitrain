# 92b plan — evidence (planner research baselines)

Planner run on base `dcd4dc88` (branch `claude_develop`), 2026-10-31. All greps below were run with the file tools against the working tree at that base. Implementers append their own baselines and suite outputs below the planner sections.

## Lint / test baselines

- `flutter analyze` baseline: 180 pre-existing info notices, 0 errors (carried from the 92a plan; compare Phase Done Criteria counts against this).
- Full `flutter test`: several minutes — run via the gateway `test` check (900 s timeout). Widget tests Mock-first; Hive seeded in `setUp`; no real `Future.delayed` or Hive write inside `testWidgets` (FakeAsync).
- Gateway checks available (from `.github/copilot/scripts/macos/gateway.sh list`): `lint` 300s, `test` 900s, `build` 900s, `codegen` 300s, `pub-get` 300s, `format` 120s (requires args, new-files-only), `swift-test` 900s, `base-setup` 300s; git views; `prove-red <ref> <check> [args] [-- <files...>]`.

## Grep baselines (old keys and strings)

- `food_form_unit_type|food_form_reference_amount|food_form_reference_label`:
  - `lib/`: only `lib/features/nutrition/widgets/food_form.dart` (dropdown ~L497-531, reference Row ~L533-575).
  - `test/`: only `test/nutrition_test.dart` — L1956-1960 (test 'fills the form, saves, and the new food is rendered in the library', test body starts L1906) and L2094-2098 (test 'the New Food bottom bar says Save, not Create (S-92a.10)', test body starts L2046). No other test file references the keys.
- Strings "Unit type" / "Reference amount" / "Reference label" / "Macros (the reference above)" in `lib/`:
  - `food_form.dart` L39-40 (class doc comment field list) and L497-577 (dropdown label, Row, heading) — removed by Phases 2A.
  - `lib/data/models/models.dart` doc comments ~L1946-1953 ("Unit type: count…", "Reference amount —…", "Reference label —…") — model documentation; stays per D-92b.10 (the one expected exception in the Phase 2B sweep).
- Docs hits (case-insensitive) outside `docs/plans/`: `docs/documentation_standard.md:253`, `docs/db_integration.md:520`, `docs/data_models.md:394`, `docs/nutrition.md:29` + `:251`, `docs/state_management/nutrition_state.md:50` — all describe the model / snapshot contract (unchanged by this feature), not the form's boxes → checked-no-edit (Phase 3 item 4).

## FoodForm builders

`FoodForm(` in `lib/` → exactly three: `edit_food_screen.dart`, `add_food_screen.dart` (`_NewFoodFormScreen`, `_LegacyLibraryEditScreen`). None passes serving-specific params; hosts are untouched (S-92b.16 covers both edit hosts).

## `lastAmountConsumed` write sites (`lib/state/food_library_state.dart`)

- `_propagateCatalogEditToLinkedFoods` (~L749): loop 1 `updatedLibFood` passes `lastAmountConsumed: libFood.lastAmountConsumed` (~L790); loop 2 `upgradedLibFood` passes `lastAmountConsumed: legacyFood.lastAmountConsumed` (~L806).
- `editLibraryFood` (~L1008): the `current.copyWith(...)` block (~L1034-1050) keeps `lastAmountConsumed`.
- `resetLibraryFood` (~L1088): the explicit `Food(...)` (~L1115-1135) passes `lastAmountConsumed: copy.lastAmountConsumed` (~L1127).
- `updateCustomFood` (~L1339) already builds a `Food` without it (clears); `updateCatalogFood` (~L930) edits the catalog row (always null) — neither changes (D-92b.7).
- `Food.copyWith(lastAmountConsumed: null)` clears via the `_foodCopyWithUnset` sentinel (`models.dart` ~L2131).

## Tests whose assertions change

- `test/nutrition_test.dart` L1906 and L2046 — both rewritten to the new control (Phase 2A item 8). The seed said "the one test"; there are two (A-92b.1).
- `test/food_library_copy_edit_test.dart`:
  - `_draft()` helper builds count / 1 / `tbsp` — serving-CHANGING against the almond_butter copy's grams / 100 / `g`.
  - S-12702 'lastAmountConsumed and catalogId survive an edit' (test L140, assertion `expect(edited.lastAmountConsumed, 250)` L153): under D-92b.7 the `_draft()` edit would now clear → its `editLibraryFood(copy, _draft())` call (L150) gets a serving-preserving draft; the assertion becomes the keep-path guard (D-92b.12).
  - S-12704 'resetLibraryFood restores the shipped values' (test L218, assertion `expect(reset.lastAmountConsumed, 250)` L246): same treatment (D-92b.12).
  - Stays green: S-12701 (L113), S-12703 (L158), S-12703b (L192), S-12705 (L249), S-12706 (L267), S-12708 (L348), S-12709 (L363) and the whole Hive group (L401) — grep shows `lastAmountConsumed` assertions only at L153 and L246.
- `test/food_library_edit_test.dart`: S-003 'preserves lastAmountConsumed on the linked library copy across a catalog edit' (L591-630) stays green — its `catalogDraft` keeps grams / 100 / `g` (serving-preserving → keep path). New S-92b.10 propagation tests go in group 'FoodLibraryState updateCatalogFood' (L337).
- `test/library_row_toggle_test.dart` S-12713 (L243): its edit draft keeps the copy's serving triple (`unitType: copy.unitType, referenceAmount: copy.referenceAmount, referenceLabel: copy.referenceLabel`, L274-277) → keep path → green.
- Tests pumping `FoodForm` directly (`test/food_form_decimals_and_autofocus_test.dart`, `test/food_form_orphan_category_test.dart`, `test/food_form_pick_saves_test.dart`, `test/edit_food_save_test.dart`): none references the old keys; fixtures seed reference values only → stay green.

## UI standards confirmation

- `test/ui_standards_contract_test.dart` L30-60: the S-2601 button-shape scan covers `TextButton` / `FilledButton` / `OutlinedButton` / `ElevatedButton` constructor names only. `SegmentedButton` and `FilterChip` are not scanned → no allowlist entry needed (AC-6).
- `test/helpers/ui_standards_allowlist.dart`: exceptions register (buttonShape, rawCard, iconButtonTooltip, rawColour, colorsWhite/Black ratchets, handBuiltSheetRatchet = 16, handBuiltDialogRatchet = 9, rawSnackBar, exceptionInMessage) — unchanged by this feature; no new dialog/sheet, no raw Card, no `Colors.white`/`Colors.black` in `food_form.dart` (the file is in neither ratchet map).
- Precedents cited in the plan: `SegmentedButton` — `lib/features/nutrition/widgets/nutrition_trend_card.dart` ~L111; `TextButton` with explicit `shape:` — `lib/features/nutrition/add_food_screen.dart` ~L1043; `FilterChip` in a `Wrap(spacing: 8, runSpacing: 8)` — `lib/features/exercise/exercise_editor_screen.dart` ~L538.
- `docs/design_system.md` "Shared pieces and rules per job" has no segmented-control entry; predicted: no edit (Phase 3 item 5).

## Doc sizes (against the 52 KiB band; the contract test warns past it)

- `docs/nutrition.md` — 31.6 KB.
- `docs/state_management/nutrition_state.md` — 26.9 KB.
- `docs/widget_catalog/nutrition_widgets.md` — under 20 KB (full read, no truncation).
- All under the band; no part-page split predicted.

## S-92b.1 fixture

28 distinct catalog triples + 5 odd cases, exactly as the seed enumerates them (grams/100/`g`, grams/100/`ml`, grams/28/`g`, count/1/<label> for 25 labels; odd: (count, 3, `tbsp`), (grams, 100, `per 100g`), (grams, 100.5, `g`), (count, 1, ``), (grams, 0, `g`)). Not re-derived from the seed file, per the brief.

## Prove-red rationale per phase

- Phase 1, state tests: the new S-92b.10 tests compile at base (existing APIs only) and fail there (today all three paths keep the stale value) → `prove-red HEAD test test/food_library_copy_edit_test.dart test/food_library_edit_test.dart` must FAIL on base.
- Phase 1, `test/food_serving_test.dart`: cannot compile at base (`lib/core/utils/food_serving.dart` does not exist) → mutation proof instead: map label `ml` to `Per100G` in `servingChoiceFrom`, the suite must FAIL, restore verbatim.
- Phases 2A/2B, `test/food_form_serving_test.dart`: compiles at base (only `Key` lookups on absent widgets → `findsNothing`/`findsOneWidget` mismatches) and fails there → `prove-red HEAD test test/food_form_serving_test.dart` must FAIL on base.

## On-device bug (confirmed in source)

`food_form.dart` initState seeds the amount controller with `(initial?.referenceAmount ?? 100).toString()` (L225-227) → `100.0` on a device; the dropdown's `onChanged` compares `_referenceAmount.text == '1'` / `'100'` (L519-526) → never matches → the switch silently does nothing. The mapper compares numeric values, never text (D-92b.3).

## Planner process notes

- Files written by the planner: the plan file (seed kept verbatim + "Planner expansion (Iteration 1)" appended) and this evidence file. Nothing else.
- One process slip, recorded for transparency: a single no-op shell command (`true`) was run before correcting course to gateway-only shell use. It changed no state.

## Phase 1 execution (developer, executed)

Baselines taken from this file: lint 180 info notices / 0 errors; full suite green before the change.

### Phase 0 — tests written first, confirmed red

- Register: plan `## Core scenarios` + `## Appended scenarios`; S-92b.1 and S-92b.10 / S-92b.17 name their fixtures (see "S-92b.1 fixture" above and the tests' own setups). No material gap.
- `test/food_serving_test.dart` written first → red on a compile error (`food_serving.dart` absent), so the mapper guard is proved by the mutation below, as the plan requires.

### Red → green

| Guard | Red evidence | Green |
|---|---|---|
| S-92b.1 (6 tests) | mutation (see below) | `test/food_serving_test.dart` 6 passed, 0 failed |
| S-92b.10 / S-92b.17 (state) | `prove-red HEAD test` → RED AT HEAD, 6 failures | `test/food_library_copy_edit_test.dart` 20 passed; `test/food_library_edit_test.dart` 18 passed |

Prove-red verdict line, verbatim:

```
00:00 +32 -6: Some tests failed.
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the reason the test guards; a compile or load error means the test could not run there (use a mutation instead).
```

Command: `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/food_library_copy_edit_test.dart test/food_library_edit_test.dart`

The six failures are the guarded reason — the stale value is kept where it must be cleared:

| Test | Base assertion failure |
|---|---|
| (Mock) S-92b.10 a serving-changing edit clears the remembered amount | `Expected: null / Actual: <150.0>` |
| (Mock) S-92b.10 a reset after a serving-changing edit clears the remembered amount | `Expected: null / Actual: <150.0>` |
| (Hive) S-92b.10 a serving-changing edit clears the remembered amount | `Expected: null / Actual: <150.0>` |
| (Hive) S-92b.10 a reset after a serving-changing edit clears the remembered amount | `Expected: null / Actual: <150.0>` |
| updateCatalogFood S-92b.10 a serving-changing catalog edit clears the linked copy's remembered amount | `Expected: null / Actual: <100.0>` |
| updateCatalogFood S-92b.17 the legacy-upgrade propagation clears a changed serving and keeps an unchanged one | `Expected: null / Actual: <200.0>` |

The three "name-only keeps" legs (S-92b.10 ×2, S-92b.17 fixture B) pass at base, which is correct: they are keep-path guards.

### Mutation proof for the mapper (S-92b.1)

Original line, recorded before mutating:

```dart
      if (label == 'ml') return const Per100Ml();
```

Mutated to `if (label == 'ml') return const Per100G();` (plus a `// MUTANT` marker comment):

```
00:00 +0 -1: food_serving S-92b.1 round trip over every shipped catalog triple [E]
  Expected: (FoodUnitType, double, String):<(FoodUnitType.grams, 100.0, ml)>
    Actual: (FoodUnitType, double, String):<(FoodUnitType.grams, 100.0, g)>
00:00 +1 -2: food_serving S-92b.1 stored serving loads as the matching choice [E]
  Expected: <Instance of 'Per100Ml'>
    Actual: <Instance of 'Per100G'>
00:00 +4 -2: Some tests failed.
```

Restored verbatim, re-ran the three touched files: **44 passed, 0 failed** (`All tests passed!`). `grep MUTANT lib test` → no matches; `git-diff --stat` shows only the five files Phase 1 owns.

### Done Criteria results

- `gateway.sh test test/food_serving_test.dart test/food_library_copy_edit_test.dart test/food_library_edit_test.dart` → **44 passed, 0 failed**.
- `gateway.sh lint` → **180 issues, 0 errors** (equal to the baseline; no notice names a file this phase touched).
- `gateway.sh format lib/core/utils/food_serving.dart test/food_serving_test.dart` → both formatted (new files only).
- `gateway.sh test` (full suite, 900 s) → `03:52 +5902 ~2: All tests passed!` — **5902 passed, 2 skipped, 0 failed**.
- `gateway.sh test test/ui_standards_contract_test.dart` → **41 passed, 0 failed** (no `lib/` UI changed; no allowlist entry added or ratchet raised).
- Invariant grep `import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core` → only `lib/main.dart` (the composition root), unchanged.
- `lib/core/utils/food_serving.dart` imports only `../../data/models/models.dart` and `food_helpers.dart` — no Flutter, no storage.

### Docs

- No doc edit in Phase 1: the plan assigns every doc write to Phase 3 (`docs/nutrition.md`, `docs/state_management/nutrition_state.md`, `docs/widget_catalog/nutrition_widgets.md`). Phase 1 changes no screen, route, widget or constructor dependency, so `docs/navigation_and_screens.md` and `docs/widget_catalog.md` need no update. The Phase 1 state behaviour is exercised by the S-92b.10 / S-92b.17 tests named above, which Phase 3 cites.

