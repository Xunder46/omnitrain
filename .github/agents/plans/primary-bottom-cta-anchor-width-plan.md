# Feature: primary-bottom-cta-anchor-width

## Overview
Continue the shared-bottom-CTA consistency pass (`shared-bottom-cta-plan.md`).
The existing `OmniBottomCTA` widget already centralizes the primary bottom CTA
height and corner radius, but two screens still render an inline `Spacer()` /
end-of-form `FilledButton` instead of using it, and the widget itself does
not yet expose an explicit, testable contract for **shared width** and
**shared vertical anchor**. This iteration: (1) defines that contract as a
token-driven invariant on the widget, (2) migrates the two outlier screens
(`NutritionTargetScreen`, `FoodForm` and its three host screens), and (3)
extends the test suite to assert the shared width and vertical anchor on at
least two different screens. Button label, color, and on-press behavior are
unchanged. Secondary and inline buttons are out of scope.

## Requirements
- Single source of truth for primary bottom CTA width, horizontal margin,
  vertical position (safe-area-anchored bottom), height, and corner radius —
  all expressed as `OmniTheme` tokens consumed only by `OmniBottomCTA`.
- `OmniBottomCTA` respects the device bottom safe area on both iOS (home
  indicator) and Android (gesture / 3-button nav) so the primary action is
  never covered by system chrome.
- `NutritionTargetScreen` ("Save"), `AddFoodScreen` ("New Food"),
  `EditFoodScreen` ("Save"), and `_LegacyLibraryEditScreen` ("Save") all use
  `OmniBottomCTA` as the `Scaffold.bottomNavigationBar`. The `FoodForm`
  widget no longer renders an inline save `FilledButton` at the end of its
  body — its host screens own the bottom CTA.
- `FoodForm`'s body gets a single `bottomContentPadding` (clearance equal to
  the shared CTA footprint) so the last form field is never hidden behind
  the CTA.
- Existing screens that already use `OmniBottomCTA` keep their current
  label, callback, and visual treatment:
  - `WorkoutSessionScreen` (3 list-view branches — "Finish Workout" /
    "Save Changes")
  - `SessionSummaryScreen` ("Done")
  - `PeriodListScreen` ("+ New Period")
  - `CreatePeriodScreen` ("Save")
  - `ExerciseEditorScreen` ("Save exercise")
- Button label, color, and on-press action for every migrated screen are
  preserved verbatim.
- Secondary and inline buttons (utility buttons, dialog `TextButton`s, row
  add/remove affordances, food library row buttons, etc.) are untouched.
- The shared `OmniBottomCTA` widget test gains width and vertical-anchor
  assertions; per-screen tests gain at least two additional cases that
  confirm their primary bottom CTA sits at the shared width and vertical
  anchor.

## Acceptance Criteria
- [ ] `OmniBottomCTA` consumes `OmniTheme.bottomCTAHorizontalPadding` (16),
      `OmniTheme.bottomCTAVerticalTopPadding` (24), `OmniTheme.bottomCTAVerticalBottomPadding` (16),
      `OmniTheme.buttonPrimaryHeight`, and `OmniTheme.buttonBorderRadius`
      directly — no hardcoded numbers in the widget.
- [ ] `OmniBottomCTA` wraps its button in `SafeArea(top: false)` (bottom on
      by default) so the button is always anchored above the home indicator
      / Android nav bar.
- [ ] `NutritionTargetScreen` uses `Scaffold.bottomNavigationBar:
      OmniBottomCTA(label: 'Save', ...)`. The form is a `SingleChildScrollView`
      with a bottom padding that clears the CTA.
- [ ] `FoodForm` no longer renders an inline save button. Its body uses a
      shared `bottomContentPadding` (a single token, equal to the
      `OmniBottomCTA` footprint) so the last form field is never hidden.
- [ ] `AddFoodScreen` (the `_NewFoodFormScreen` host), `EditFoodScreen`,
      and `_LegacyLibraryEditScreen` each use
      `Scaffold.bottomNavigationBar: OmniBottomCTA(...)` with the same label
      that `FoodForm.saveLabel` previously rendered.
- [ ] The existing `OmniBottomCTA` widget test (`test/screen_widget_test.dart`
      "uses the shared primary height and corner radius") is extended to
      also assert:
      - button width = surface width − 2 ×
        `OmniTheme.bottomCTAHorizontalPadding`
      - button bottom = surface height − bottom safe area −
        `OmniTheme.bottomCTAVerticalBottomPadding`
- [ ] At least two additional per-screen tests (e.g. `PeriodListScreen` and
      `NutritionTargetScreen`) assert that the primary bottom CTA uses
      `OmniBottomCTA` and sits at the shared width and vertical anchor.
- [ ] The existing per-screen test that asserts "inline `SizedBox` save
      button" in `FoodForm` is reconciled to the new contract (the inline
      `SizedBox` is gone, the host's `bottomNavigationBar` is the CTA).
- [ ] The "Save button is still present" assertion in
      `nutrition_test.dart` (`NutritionTargetScreen — calories only
      (D-3 / S-040)`) continues to pass — the label is the same; the
      widget hosting it is now `Scaffold.bottomNavigationBar` instead of
      an inline `Spacer()`.
- [ ] No regression: all previous passing tests still pass; button labels,
      colors, and on-press actions on every migrated screen are byte-for-byte
      preserved.

## Scenarios

### S-001: OmniBottomCTA shared contract (height, width, anchor)
- Trigger: pump a `Scaffold` with `OmniBottomCTA(label: 'Continue', onPressed: () {})` as `bottomNavigationBar`
- Precondition: surface 400×800, zero bottom safe-area inset
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: `FilledButton` height = `OmniTheme.buttonPrimaryHeight`,
  radius = `OmniTheme.buttonBorderRadius`, width = surface width − 2 ×
  `OmniTheme.bottomCTAHorizontalPadding`, and the button bottom is anchored
  at the scaffold's bottom (the bottom of the bottomNavigationBar slot,
  immediately above the bottom safe-area inset, then offset by
  `OmniTheme.bottomCTAVerticalBottomPadding`).
- Edge case of: none

### S-002: OmniBottomCTA bottom safe-area handling
- Trigger: pump a `Scaffold` whose `MediaQuery.padding.bottom = 34` (iPhone
  home indicator) with `OmniBottomCTA` as `bottomNavigationBar`
- Precondition: surface 400×800, bottom safe-area 34
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: the `FilledButton`'s render-box bottom is offset upward
  by the full 34 px safe area plus `OmniTheme.bottomCTAVerticalBottomPadding`,
  so the button is fully visible above the home indicator.
- Edge case of: S-001

### S-003: PeriodListScreen primary bottom CTA
- Trigger: pump `PeriodListScreen`
- Precondition: `PeriodState` initialized
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: `Scaffold.bottomNavigationBar` is `OmniBottomCTA`
  with label "+ New Period" and shared width / vertical anchor.
- Edge case of: S-001

### S-004: CreatePeriodScreen primary bottom CTA
- Trigger: pump `CreatePeriodScreen`
- Precondition: none
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: `Scaffold.bottomNavigationBar` is `OmniBottomCTA`
  with label "Save" and shared width / vertical anchor.
- Edge case of: S-001

### S-005: ExerciseEditorScreen primary bottom CTA
- Trigger: pump `ExerciseEditorScreen`
- Precondition: `WorkoutState` initialized
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: `Scaffold.bottomNavigationBar` is `OmniBottomCTA`
  with label "Save exercise" and shared width / vertical anchor. Existing
  `extendBody: true` assertion is preserved.
- Edge case of: S-001

### S-006: NutritionTargetScreen migrated to OmniBottomCTA
- Trigger: pump `NutritionTargetScreen`
- Precondition: `NutritionState` initialized
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: `Scaffold.bottomNavigationBar` is `OmniBottomCTA`
  with label "Save" and shared width / vertical anchor. The calories
  field is still present and tappable. The form scrolls with bottom
  padding that clears the CTA.
- Edge case of: S-001

### S-007: AddFoodScreen — New Food form uses shared bottom CTA
- Trigger: open `AddFoodScreen`, switch to "My Foods" tab, tap "+ New Food"
- Precondition: food groups loaded
- Flow: open form
- Expected outcome: the `_NewFoodFormScreen` host's
  `Scaffold.bottomNavigationBar` is `OmniBottomCTA` with label "New Food"
  (the same label `FoodForm.saveLabel` previously rendered) and shared
  width / vertical anchor. The "Save" key on the form becomes the
  `FoodForm` test's `food_form_save` key on the new bottom CTA.
- Edge case of: S-001

### S-008: EditFoodScreen — primary bottom CTA
- Trigger: pump `EditFoodScreen(food, foodLibraryState)`
- Precondition: catalog loaded with at least one food
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: `Scaffold.bottomNavigationBar` is `OmniBottomCTA`
  with label "Save" and shared width / vertical anchor. The `FoodForm`
  pre-fills the name field.
- Edge case of: S-001

### S-009: _LegacyLibraryEditScreen — primary bottom CTA
- Trigger: open a non-catalog library food and tap the edit affordance
- Precondition: a non-catalog library food exists
- Flow: open `_LegacyLibraryEditScreen`
- Expected outcome: `Scaffold.bottomNavigationBar` is `OmniBottomCTA`
  with label "Save" and shared width / vertical anchor.
- Edge case of: S-001

### S-010: FoodForm no longer renders an inline save button
- Trigger: pump `FoodForm` in any host
- Precondition: none
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: the `food_form_save` key is no longer a child of the
  form body. It is now rendered as the `OmniBottomCTA` on the host's
  `Scaffold.bottomNavigationBar`. The form body still contains all macro
  fields and the notes field (when enabled).
- Edge case of: S-001

### S-011: SessionSummaryScreen — Finish / Done primary CTA
- Trigger: pump `SessionSummaryScreen` for a completed session
- Precondition: session finished
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: a `Positioned(left: 0, right: 0, bottom: 0, child:
  OmniBottomCTA(label: 'Done', ...))` sits at the shared vertical anchor
  and shared width.
- Edge case of: S-001

### S-012: WorkoutSessionScreen — Finish / Save Changes primary CTA
- Trigger: pump `WorkoutSessionScreen` (active or edit mode)
- Precondition: workout state initialized
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: each of the three list-view branches ends with a
  `Positioned(left: 0, right: 0, bottom: 0, child: OmniBottomCTA(label:
  editMode ? 'Save Changes' : 'Finish Workout', ...))` at the shared
  width and vertical anchor. The rest-timer chip continues to sit 130 px
  above the bottom.
- Edge case of: S-001

## Iteration 1

### DB Changes
None. The repository, models, and persistence layer are untouched.

### Backend Changes
None. No service or state method changes.

### Frontend Changes (@developer)

#### 1. Add tokens to `OmniTheme`
File: `lib/core/constants/omni_theme.dart`
- `static const double bottomCTAHorizontalPadding = 16.0;`
- `static const double bottomCTAVerticalTopPadding = 24.0;`
- `static const double bottomCTAVerticalBottomPadding = 16.0;`
- Document the contract in code comments.

#### 2. Update `OmniBottomCTA` to consume the tokens and respect bottom safe area
File: `lib/widgets/layout/omni_bottom_cta.dart`
- Replace the hardcoded `EdgeInsets.fromLTRB(16, 24, 16, 16)` with
  `EdgeInsets.fromLTRB(bottomCTAHorizontalPadding,
  bottomCTAVerticalTopPadding, bottomCTAHorizontalPadding,
  bottomCTAVerticalBottomPadding)`.
- Change `SafeArea(top: false, bottom: false)` to
  `SafeArea(top: false)` so the widget respects the device's bottom safe
  area.
- Document the contract at the top of the file (height, width rule, radius,
  bottom anchor, safe area). The widget is the single source of truth — no
  per-screen CTA styling drift.

#### 3. Migrate `NutritionTargetScreen`
File: `lib/features/nutrition/nutrition_target_screen.dart`
- Replace the inline `Spacer() + SizedBox(width: double.infinity, height:
  buttonPrimaryHeight, child: FilledButton(...))` with
  `Scaffold.bottomNavigationBar: OmniBottomCTA(label: 'Save', onPressed:
  _save)`.
- Move the existing form body into a `SingleChildScrollView` whose
  bottom padding is at least `OmniTheme.buttonPrimaryHeight + topPadding +
  bottomPadding` (i.e. a `bottomContentPadding` token = 96, reused across
  forms). The current `Spacer()` is removed.
- Keep the existing `calories_field` key, validator, and `_save` callback
  unchanged.

#### 4. Migrate `FoodForm` and its three host screens
Files:
- `lib/features/nutrition/widgets/food_form.dart`
- `lib/features/nutrition/add_food_screen.dart` (the `_NewFoodFormScreen`
  host)
- `lib/features/nutrition/edit_food_screen.dart`
- `lib/features/nutrition/add_food_screen.dart` (the
  `_LegacyLibraryEditScreen` host, also in `add_food_screen.dart`)

Changes:
- Add a `bottomContentPadding` constant (single token, e.g.
  `OmniTheme.formBottomCTAClearance = 112`) to `OmniTheme` so `FoodForm`'s
  body can use it as its `ListView`/`SingleChildScrollView` bottom padding.
- Remove the inline `SizedBox + FilledButton` ("food_form_save") from
  `FoodForm`'s build method.
- Reassign the `food_form_save` `Key` to the `OmniBottomCTA` rendered on
  each of the three host screens' `Scaffold.bottomNavigationBar`. This
  keeps the existing tests (`await tester.tap(find.byKey(const
  Key('food_form_save')))`) working with no test-code changes.
- Use the same label that `FoodForm.saveLabel` currently provides.

#### 5. Existing screens — no structural change required
`WorkoutSessionScreen` (3 branches), `SessionSummaryScreen`,
`PeriodListScreen`, `CreatePeriodScreen`, and `ExerciseEditorScreen` already
use `OmniBottomCTA` in a way that benefits automatically from the new
shared `SafeArea(bottom: true)` and shared padding tokens. The behaviour
contract is unchanged.

#### 6. Doc hygiene
- `docs/widget_catalog.md` — add the width and vertical-anchor
  descriptors to the `OmniBottomCTA` section.
- `docs/design_system.md` — add a one-line rule in the **Buttons**
  section: "All primary bottom CTAs use `OmniBottomCTA` and share width
  and vertical anchor via `OmniTheme.bottomCTA*` tokens. No inline
  `Spacer() + SizedBox + FilledButton` is permitted at the bottom of a
  screen."

### Implementation Steps
1. [ ] Add `bottomCTAHorizontalPadding`, `bottomCTAVerticalTopPadding`,
       `bottomCTAVerticalBottomPadding`, and `formBottomCTAClearance` to
       `OmniTheme`.
2. [ ] Update `OmniBottomCTA` to consume the new tokens and switch
       `SafeArea(top: false, bottom: false)` to `SafeArea(top: false)`.
3. [ ] Update the `OmniBottomCTA` widget test to assert width and
       vertical anchor in addition to height and corner radius.
4. [ ] Add a new `OmniBottomCTA` widget test for safe-area handling
       (S-002).
5. [ ] Add per-screen tests asserting shared width and anchor on at
       least `PeriodListScreen` and `NutritionTargetScreen`.
6. [ ] Migrate `NutritionTargetScreen` to use
       `Scaffold.bottomNavigationBar: OmniBottomCTA(label: 'Save', ...)`.
7. [ ] Migrate `FoodForm`: drop the inline save button; have the three
       host screens render `OmniBottomCTA` with the
       `Key('food_form_save')` and the form's `saveLabel`.
8. [ ] Run `flutter test test/screen_widget_test.dart
       test/nutrition_test.dart test/interaction_flow_test.dart
       test/edge_case_test.dart` until green.
9. [ ] Run `flutter test` for the full suite.
10. [ ] Update `docs/widget_catalog.md` and `docs/design_system.md` per
        the doc-hygiene section.

## Progress
- [x] Phase 0 complete ✓
- [x] Phase 1 complete (skipped; UI-only)
- [x] Phase 2 complete ✓
- [x] Phase 3 complete ✓

### Phase 2 Complete ✓
Implementation done. New `OmniTheme.bottomCTA*` tokens added
(`bottomCTAHorizontalPadding`, `bottomCTAVerticalTopPadding`,
`bottomCTAVerticalBottomPadding`, `formBottomCTAClearance`).
`OmniBottomCTA` consumes the tokens and now uses
`SafeArea(top: false)` (bottom on by default) so the button clears
the device safe area. New `buttonKey` prop forwards a test `Key` to
the rendered `FilledButton`. `NutritionTargetScreen` migrated to
`Scaffold.bottomNavigationBar: OmniBottomCTA`. `FoodForm` no longer
renders an inline save button; the three host screens
(`EditFoodScreen`, `_NewFoodFormScreen`, `_LegacyLibraryEditScreen`)
own the bottom CTA via a new `FoodFormController` that the form
attaches its `_onSave` pipeline to. The `food_form_save` test key
is preserved on the host's bottom CTA.

Test coverage added:
- `OmniBottomCTA` widget test extended to assert shared width and
  vertical anchor in addition to height and corner radius.
- New `OmniBottomCTA` widget test for safe-area handling (S-002).
- `PeriodListScreen` per-screen test asserts shared width and
  vertical anchor (S-003).
- `NutritionTargetScreen` per-screen test asserts shared width and
  vertical anchor (S-006).
- `FoodForm` widget test asserts the inline `food_form_save` key
  is no longer a child of the form body (S-010).
- `EditFoodScreen` per-screen test asserts the host's bottom CTA
  hosts `food_form_save` at the shared width and vertical anchor
  (S-008).

Full test suite: 1439 passing (vs 1410 on master — +29 new
passes, 0 new failures). Both pre-existing failures
(`Catalog row on the Library tab opens EditFoodScreen on row tap`
and `NutritionStripBar empty state`) are unrelated to this work
and were already failing on master before this iteration. Web smoke
verification: `flutter run -d chrome --target lib/main.dart`
launched and rendered the new bottom CTAs without runtime errors
on both the Edit Food and Period List screens.

Doc hygiene: `docs/widget_catalog.md` and `docs/design_system.md`
updated to document the shared-CTA contract, the new tokens, the
mandatory call-site rule, and the forbidden patterns.

## Feedback
(none)

### Phase 3 Complete ✓
Review verdict: ✅ APPROVED. All 11 acceptance criteria verified.
All 12 scenarios mapped to passing tests. Doc hygiene: ✅
`widget_catalog.md` + `design_system.md` updated to reflect
post-implementation code. Global conventions: PASS (5 rules), N/A
(1 rule), FAIL 0. Architecture compliance: ✅ across all in-scope
layers. Buttons rule: ✅ every migrated screen uses the shared
`OmniBottomCTA`. Dead code: none introduced. Test coverage: +29
new passing tests, 0 new failures. Two pre-existing test failures
(`Catalog row on the Library tab opens EditFoodScreen on row tap`
and `NutritionStripBar empty state`) are unrelated to this work
and were already failing on master.

### Phase 0 Complete ✓
Plan filed. Iteration 1 scope:
- 1 token addition (`OmniTheme.bottomCTA*` and `formBottomCTAClearance`).
- 1 widget update (`OmniBottomCTA` consumes tokens + `SafeArea(top: false)`).
- 2 screens migrate from inline `Spacer()+SizedBox` /
  end-of-form `FilledButton` to `Scaffold.bottomNavigationBar: OmniBottomCTA`
  (`NutritionTargetScreen`, `FoodForm` + its 3 hosts).
- 5 already-shared screens (`WorkoutSessionScreen` × 3, `SessionSummaryScreen`,
  `PeriodListScreen`, `CreatePeriodScreen`, `ExerciseEditorScreen`) keep
  their current `OmniBottomCTA` usage and benefit automatically from the
  shared `SafeArea(bottom: true)` and shared padding tokens.
- Test extension: existing `OmniBottomCTA` widget test gains width +
  vertical-anchor assertions; at least `PeriodListScreen` and
  `NutritionTargetScreen` get fresh per-screen assertions. The
  `food_form_save` `Key` is preserved on the new bottom CTAs.
- Phase 1 skipped: this iteration is pure UI consistency, no
  repository / state / model changes.
