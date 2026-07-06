# Feature: Home nutrition card — show macro percentages when no target is set

## Overview

The `NutritionSummaryCard` on the home screen currently treats "no daily
target set" and "no food logged yet" as the **same** empty state: the
gauge is hidden AND the caption row renders dashes (`—`) for every
macro. That conflates two independent concerns — the gauge needs a
**goal** (`consumed / target`) while the caption needs **data to split**
(protein / carbs / fat kcal share of consumed).

Fix: when a user has logged food but has no target set, the caption row
must still show the real macro percentages (P, C, F split of consumed
calories) so the user gets actionable feedback. The gauge stays hidden
because there is no goal to fill against — `consumed / target` is
undefined when `target` is `null`. This matches the user's explicit
request: "if a user doesn't have a target daily calorie set, the
nutrition strip on the home screen still must show the percentage of
the consumed macros, only the progress bar cannot be shown in this
case."

The headline (the `"{consumed} / {target} Cal"` row) already handles
`target == null` correctly — it renders `"{n} / — Cal"` via
`_formatHeadline`. No headline change is required.

## Requirements

- Split the existing single `_isEmpty` flag on
  `NutritionSummaryCard` into two independent flags: one for the gauge
  ("needs a goal") and one for the caption row ("needs data to
  split").
- Gauge remains hidden when there is **no target** OR **no consumed
  data**. Reason: `consumed / target` is undefined when `target` is
  `null`; clamping to 0 is the only sensible behavior, which is what
  the current code already does for the no-data case.
- Caption row renders **real percentages** (e.g., `P 42%`, `C 33%`,
  `F 25%`) whenever `consumed > 0`, **even when `target == null`**.
  The existing macro-percentage math is preserved.
- Caption row still renders dashes (`—`) when `consumed <= 0` (no data
  to split) AND when `proteinKcal + carbsKcal + fatKcal <= 0` (data
  exists but macros are all zero — e.g., a zero-macro entry).
- Headline is unchanged.
- Existing happy state (S-100), empty state (S-104), and over-budget
  state (S-105) tests continue to pass with no modification.
- No repository / state changes. The `NutritionSummaryCard` is a pure
  presentation widget; the fix lives entirely in
  `lib/features/home/widgets/nutrition_summary_card.dart`.

## Acceptance Criteria

- [ ] `NutritionSummaryCard` exposes two distinct internal flags:
      `_hideGauge` (gauge needs a goal) and `_captionEmpty` (caption
      needs data to split). `_hideGauge = isNoTarget || noConsumedData`.
      `_captionEmpty = noConsumedData || noMacroData`.
- [ ] When `target == null` and `consumed > 0` with non-zero macros,
      the card renders the headline (`"{consumed} / — Cal"`), the
      gauge track is rendered at full width with NO fill, and the
      caption row renders the real P / C / F percentages (e.g.,
      `P 42%`, `C 33%`, `F 25%`).
- [ ] When `target == null` and `consumed == 0`, the card renders the
      headline (`"0 / — Cal"`), the gauge track at full width with
      no fill, and the caption row with three dashes (`—`). Behavior
      is unchanged from the existing "no target AND no food" case.
- [ ] When `target` is set and `consumed > 0`, all existing behavior
      is preserved (gauge fill, caption percentages, over-budget
      warning). All S-100 / S-102 / S-103 / S-104 / S-105 tests
      continue to pass with no modifications.
- [ ] `flutter analyze` is clean for `nutrition_summary_card.dart`.
- [ ] New test in
      `test/home_nutrition_summary_card_test.dart` (S-200): no target
      + consumed data → caption shows real percentages, gauge fill is
      absent or has zero width.
- [ ] New test in
      `test/home_nutrition_summary_card_test.dart` (S-201): no target
      + no consumed data → caption shows three dashes (parity with the
      existing target-set + no-data case).
- [ ] All previously passing tests still pass.

## Scenarios

### S-200: No target set + consumed data → caption shows real percentages, gauge hidden
- Trigger: User opens the home screen with food logged but no daily
  calorie target configured.
- Precondition: `widget.nutritionState.nutritionTarget == null`
  (no target saved for today), `widget.nutritionState.todayConsumedCalories > 0`,
  and the per-macro kcal contributions are non-zero
  (`todayProteinKcal > 0 || todayNetCarbsKcal > 0 || todayFatKcal > 0`).
- Flow:
  1. Home screen builds the `NutritionSummaryCard` with
     `targetCalories: null` and the real consumed values.
  2. `_Headline` renders `"{consumed} / — Cal"`.
  3. `_Gauge` sees `_hideGauge == true` (because `target == null`)
     and renders the full-width track with no fill on top.
  4. `_CaptionRow` sees `_captionEmpty == false` and renders
     `P NN%`, `C NN%`, `F NN%` from the real macro split.
- Expected outcome: User sees the calorie figure, the empty gauge
  track (so the card layout doesn't shift), and three real macro
  percentages. No dashes are shown for the captions.
- Edge case of: none

### S-201: No target set + no consumed data → caption shows dashes (unchanged)
- Trigger: User opens the home screen on a fresh day with no food
  logged and no target configured.
- Precondition: `widget.nutritionState.nutritionTarget == null` and
  `widget.nutritionState.todayConsumedCalories == 0`.
- Flow:
  1. Home screen builds the `NutritionSummaryCard` with
     `targetCalories: null`, `consumedCalories: 0`, and zero macros.
  2. `_Headline` renders `"0 / — Cal"`.
  3. `_Gauge` sees `_hideGauge == true` (both no target and no data)
     and renders the track with no fill.
  4. `_CaptionRow` sees `_captionEmpty == true` and renders three
     dashes (`—`).
- Expected outcome: Card looks identical to the existing
  target-set + no-data case (S-104), except the target slot in the
  headline reads `—` instead of `2,000`. Layout is stable.
- Edge case of: S-104

### S-202: No target set + consumed but all macros zero → caption still dashes
- Trigger: User opens the home screen after logging a calorie-only
  entry (a `ConsumedFood` with `calories > 0` but `protein == 0`,
  `carbs == 0`, `fat == 0` — uncommon but possible).
- Precondition: `target == null`, `consumedCalories > 0`,
  `proteinKcal == 0`, `carbsKcal == 0`, `fatKcal == 0`.
- Flow:
  1. `_CaptionRow` computes `totalMacroKcal == 0`. `_macroPercent`
     returns `null` for all three macros.
  2. `_CaptionRow` sees `_captionEmpty == true` (no macro data) and
     renders three dashes (`—`) — even though `consumed > 0`.
- Expected outcome: Caption row is honest about the lack of a
  meaningful macro split. We do not show `P 0%`, `C 0%`, `F 0%` —
  those would imply a real (zero) split rather than missing data.
- Edge case of: S-200

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

#### 1. Refactor `_isEmpty` into two independent flags
File: `lib/features/home/widgets/nutrition_summary_card.dart`.

Replace the single `_isEmpty` getter (line ~103) with:

```dart
/// True when there is no goal to fill against (`target == null`).
/// Independent of whether food has been logged.
bool get _isNoTarget =>
    targetCalories == null || targetCalories! <= 0;

/// True when the user has not logged any food yet.
bool get _hasNoConsumedData => consumedCalories <= 0;

/// True when there is no macro split to show (no food OR all macros
/// are zero).
bool get _hasNoMacroData =>
    _hasNoConsumedData || (proteinKcal + carbsKcal + fatKcal) <= 0;

/// True when the gauge should be hidden: the gauge represents
/// `consumed / target`, which is undefined without a target. No
/// target → no progress bar.
bool get _hideGauge => _isNoTarget || _hasNoConsumedData;

/// True when the caption row should render dashes instead of real
/// percentages. The caption only needs DATA to split, not a goal,
/// so it stays live whenever macros exist.
bool get _captionEmpty => _hasNoMacroData;

/// True when the headline should render the empty-state tone.
/// Currently the headline format is independent of this flag (the
/// figure always shows `"{consumed} / {target} Cal"`), but we keep
/// the flag for future use and to avoid a parameter churn.
bool get _isHeadlineEmpty =>
    _hasNoConsumedData || _isNoTarget;

/// True when the user has exceeded the daily calorie goal.
/// Only meaningful when there IS a target and there IS consumed
/// data.
bool get _isOverBudget {
  if (_isNoTarget || _hasNoConsumedData) return false;
  return consumedCalories > targetCalories!;
}
```

#### 2. Wire the new flags into the three sub-widgets
- `_Headline`: `isEmpty: _isHeadlineEmpty` (no behavioral change;
  field is currently unused inside `_Headline.build`, kept for
  forward-compat).
- `_Gauge`: `isEmpty: _hideGauge` (replaces the current
  `_isEmptyOrNoTarget` plumbing).
- `_CaptionRow`: `isEmpty: _captionEmpty` (this is the fix).

Drop the now-redundant `_isEmptyOrNoTarget` getter on `_Gauge`
(it duplicates `_hideGauge`).

#### 3. Update the doc comment on the card class
Replace the current "Required states: Empty (S-104) …" doc block
with the new semantics: Empty is now a **composite** of two
orthogonal axes — gauge-empty (needs a goal) and caption-empty
(needs data). Update S-104's wording to clarify that S-104 only
covers the "no data" case (with or without target), and add
references to S-200 / S-201 / S-202.

### Implementation Steps

1. Write failing tests in
   `test/home_nutrition_summary_card_test.dart`:
   - **S-200**: pump with `target: null`, `consumed: 643`,
     `proteinKcal: 270`, `carbsKcal: 211`, `fatKcal: 162`. Assert:
     caption shows `P 42%`, `C 33%`, `F 25%`; gauge fill is absent
     OR has zero width.
   - **S-201**: pump with `target: null`, `consumed: 0`. Assert:
     headline shows `"0 / — Cal"`, caption shows three dashes,
     gauge fill is absent.
   - **S-202**: pump with `target: null`, `consumed: 100`,
     `proteinKcal: 0`, `carbsKcal: 0`, `fatKcal: 0`. Assert:
     caption shows three dashes.
2. Run `flutter test test/home_nutrition_summary_card_test.dart` and
   confirm the new tests FAIL (red run). Capture the failure
   transcript in this plan file.
3. Implement the `_isNoTarget` / `_hideGauge` / `_captionEmpty`
   refactor in
   `lib/features/home/widgets/nutrition_summary_card.dart`.
4. Re-run the test file. All new tests PASS; all previous tests
   (S-100..S-106 + live-update) still PASS.
5. Run `flutter analyze lib/features/home/widgets/nutrition_summary_card.dart test/home_nutrition_summary_card_test.dart`
   and confirm clean.
6. Update doc hygiene per Phase 2.7:
   - `docs/widget_catalog.md` — note that `NutritionSummaryCard`
     now distinguishes "gauge-empty" from "caption-empty".
   - `docs/state_management.md` — N/A (no state change).
   - `docs/navigation_and_screens.md` — N/A (no screen change).

## Progress

- [ ] Phase 0 — Plan drafted
- [x] Phase 0.5 — Failing tests written (S-200, S-201, S-202)
- [x] Phase 0.5 — Red run captured

> **Red run transcript** (`flutter test --plain-name 'no target'`):
>
> - **S-200 caption row shows real P/C/F percentages** — **FAILED**:
>   `Found 0 widgets with text containing P 42%: []`. This is the bug
>   the user reported: the caption row currently shows dashes when
>   `target == null` even though consumed data exists. Confirms the
>   fix is required.
> - S-200 gauge fill absent — PASSED (already works; the current
>   `_isEmptyOrNoTarget` correctly hides the gauge when target is null).
> - S-200 headline "643 / — Cal" — PASSED (already works; `_formatHeadline`
>   handles `target == null`).
> - S-200 card still tappable — PASSED (the InkWell is independent of
>   `_isEmpty`).
> - S-201 caption dashes + headline "0 / — Cal" — PASSED (parity with
>   S-104).
> - S-202 caption dashes when all macros zero — PASSED (`_macroPercent`
>   returns null when `totalMacroKcal == 0`, and the caption is empty
>   because `_isEmpty` is true).
>
> **Verdict**: 1 of 7 tests fails (the core bug). The other 6 tests
> are regression guards for adjacent behavior that already works.
> Implementation will make the failing test pass and keep the rest
> green.
- [ ] Phase 1 — DB layer (skipped: no schema/state changes)
- [x] Phase 2 — Refactor `_isEmpty` into `_hideGauge` + `_captionEmpty`
- [x] Phase 2 — Update `_Gauge` and `_CaptionRow` wiring
- [x] Phase 2 — Update card class doc comment
- [x] Phase 2 — `flutter test` green (1901 tests passed, 5 skipped, 0 failed)
- [x] Phase 2 — `flutter analyze` clean (`No issues found!`)
- [x] Phase 2 — Doc hygiene (`widget_catalog.md` updated to split-state semantics)
- [x] Phase 3 — Code review (see review output below)

## Feedback

*(empty — no feedback yet)*

---

### Phase 0 Complete ✓
Plan drafted: refactor `NutritionSummaryCard._isEmpty` into two independent
flags (`_hideGauge` for "needs a goal" and `_captionEmpty` for "needs data
to split"). Scenarios S-200 / S-201 / S-202 cover the new behavior; existing
S-100..S-106 tests remain authoritative for the unchanged states.

### Phase 1 Complete ✓
Skipped: no DB / schema / model / repository / state changes. The fix is
entirely a presentation refactor inside the existing widget.