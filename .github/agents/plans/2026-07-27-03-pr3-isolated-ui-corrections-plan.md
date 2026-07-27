# PR 3: Isolated UI Corrections

> **Priority 3 of 8 — Tier 2 quick wins.** Includes Item 4 (exercise-info hint alignment) and Item 5 (labelled nutrition target control).

## Overview

Anchor the exercise-info coach mark to the actual info icon rather than the title, and replace Nutrition's ambiguous target gear with a state-aware labelled control. Hint behavior and the target-setting destination remain unchanged.

## Requirements

- Derive hint geometry from the info icon's rendered position, not fixed offsets.
- Preserve wording, once-only persistence, timing, dismissal, and other hints.
- Replace the nutrition gear with a labelled control.
- Label invites setting a target when absent and changing it when present.
- Open the same unchanged target-setting surface.
- Follow explicit OmniTheme button-shape/color conventions.

## Acceptance Criteria

- [ ] Highlight centers on the info icon at small, medium, and large widths.
- [ ] Pointer aims at the icon and alignment holds at maximum text scale.
- [ ] Wording/once-only behavior is unchanged and no other hint changes.
- [ ] Gear is absent and a labelled control replaces it.
- [ ] Label reflects absent versus existing target.
- [ ] Tap opens the same target surface; the rest of Nutrition is unchanged.
- [ ] Control follows established button conventions.

## Scenarios

### S-001: Coach mark follows actual icon
- Trigger: First eligible workout-detail display.
- Precondition: Hint has not been dismissed.
- Flow: Resolve header layout → measure target → render overlay.
- Expected outcome: Highlight/pointer align across viewport and text-scale changes.
- Edge case of: none

### S-002: Target label reflects state
- Trigger: Nutrition renders with or without a saved target.
- Precondition: State is loaded.
- Flow: Render label and tap it.
- Expected outcome: Correct label opens unchanged target setting.
- Edge case of: none

## Iteration 1

### DB Changes
None.

### Backend Changes
None expected.

### Frontend Changes
- Anchor only the exercise-info hint to keyed icon geometry.
- Replace icon-only nutrition entry with a shaped labelled control.

### Implementation Steps
1. Add geometry tests at three widths and enlarged text.
2. Add label/navigation tests for both target states.
3. Implement target-relative positioning and labelled control.
4. Update hardcoded-position and icon-finder tests.
5. Run full suite.

## Unit Tests Required
- Assert hint center relative to actual icon at three widths and enlarged text.
- Rewrite hardcoded-position tests to target-relative assertions.
- Test absent/present target labels and navigation.
- Update old gear-icon finders and flag them in review.

## Iteration 1

### DB Changes
None.

### Backend Changes
None expected.

### Frontend Changes
- Item 4: Anchor the exercise-info coach mark geometrically to the actual `InfoIcon` glyph (key on the `Icon` widget — already in place at `_infoIconKey`); verify positioning across three viewport widths and at maximum text scale. Existing positioning code derives the glow center from the icon's `RenderBox` center, which is correct, but the existing test only covers one width.
- Item 5: Replace the icon-only `IconButton` (tune gear) on the Today card header with a labelled `OutlinedButton.icon` utility variant in the `OmniCardHeader.actions` slot:
  - Label: "Set target" when no saved target exists; "Change target" when one exists.
  - Icon: `Icons.tune` (kept) or `Icons.edit` — match the rest of the app's edit affordances.
  - Key: `nutrition_target_button` (replaces `edit_targets_icon`).
  - Shape: `RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius))` — explicit per the button-shape rule.
  - On tap: push the same `NutritionTargetScreen` via `_navigateToTargets()`.

### Implementation Steps
1. Add geometry tests at three widths (small/medium/large) and at enlarged text scale, asserting the coach-mark glow center sits on the icon glyph.
2. Add label/navigation tests for the nutrition target button (both states: absent and present).
3. Implement the labelled control and confirm the existing icon-only key is gone.
4. Update existing tests that referenced `edit_targets_icon` to use the new key.
5. Run full suite.

## Unit Tests Required
- Assert hint center relative to actual icon at three widths and enlarged text.
- Rewrite hardcoded-position tests to target-relative assertions.
- Test absent/present target labels and navigation.
- Update old gear-icon finders and flag them in review.

## Progress
- [x] TDD red run recorded
  - **Coach mark multi-width / text-scale tests (S-001a–d)**: 6/6 PASS on the existing implementation. The icon-anchored geometry already handles small (720×1600), default (~800×600), large (1680×2800), and 3.0× text scale correctly. No implementation change needed for the geometry; the new tests are the safety net going forward.
  - **Nutrition target button tests (S-002a–e)**: 5/5 FAIL on the current implementation. The old `edit_targets_icon` IconButton is still present, and the new `nutrition_target_button` + "Set target" / "Change target" labels are missing. This is the expected TDD red state.
- [x] Phase 1 — Data Layer (N/A)
- [x] Hint alignment corrected (geometry already correct; new tests in place)
- [x] Nutrition control replaced
- [x] Full suite green
  - **All tests**: 1985 passed, 5 skipped, 0 failed.
  - **Docs indexing contract**: 5/5 passed.
- [x] Phase 3 — Code Review
- [x] Release-ready

### Phase 1 Complete ✓ (N/A — no data-layer changes)
### Phase 2 Complete ✓
### Phase 3 Complete ✓

## Code Review — ✅ Approved with Suggestions

**Layers in scope**: features (nutrition), docs.
**Layers skipped**: models, repositories, state, widgets, core.

PASS (8 rules): theme tokens only; card chrome via OmniSurface; card headers via OmniCardHeader; units + canonical storage; effort-kind drives analytics; timestamps are source data; reuse canonical owner; instrument panel (not influencer).
N/A (2 rules): shared unit formatter (no units in this PR); shared analytics classification (no analytics).

### Findings

🟡 WARNING  | `lib/features/nutrition/nutrition_screen.dart:211` | `target.calories > 0` is a magic-number "is set" check duplicated from `CalorieRingCard` (`targetCalories = (target != null && target.calories > 0) ? target.calories : null`). | Extract a single `NutritionTarget.hasUsableCalories` getter on the model so the rule lives in one place — currently the screen and the card both treat `calories > 0` as "set". | @developer

💡 SUGGEST  | `lib/features/nutrition/nutrition_screen.dart:209` | The inline `Builder` rebuilds the labelled control on every `ListenableBuilder` notification, but the only input that changes is `nutritionState.nutritionTarget`. | Wrap the `OutlinedButton.icon` inside a `ListenableBuilder(listenable: widget.nutritionState, builder: ...)` already wrapping the body — the existing `Builder` is redundant because the outer `ListenableBuilder` already rebuilds the children. | @developer

💡 SUGGEST  | `test/exercise_detail_coach_mark_positioning_test.dart:107` | The S-001d test sets `textScaleFactor: 3.0` but the surrounding helper `_primeSessionForCoachMark` does not pass a textScaler. | If the same scenario is later reused at other text scales, parameterise `_primeSessionForCoachMark` so the multi-scale and multi-width tests share one helper. | @developer

### Test gaps

🧪 STALE: `test/nutrition_test.dart:1357` — comment was updated; no remaining stale references.

### Doc hygiene table

| Doc | Status |
|---|---|
| `docs/widget_catalog/home_screen.md` | ✅ Updated |
| `docs/widget_catalog/layout_and_inputs.md` | ✅ Updated |
| `docs/design_system.md` | ✅ Updated |
| `docs/navigation_and_screens.md` | ✅ Updated |
| `docs/data_models.md` | N/A |
| `docs/db_integration.md` | N/A |
| `docs/state_management.md` | N/A |
| `docs/navigation_contract.md` | N/A |

**Critical**: 0 | **Warnings**: 1 | **Suggestions**: 2

---
⏸️ **PIPELINE COMPLETE** — Implementation, tests, doc hygiene, and review delivered.
Approved for merge. Suggestion and warning are non-blocking improvements.

## Doc hygiene
- [x] `docs/widget_catalog/home_screen.md` — replaced `edit_targets_icon` IconButton description with the new `nutrition_target_button` `OutlinedButton.icon` PR 3 description.
- [x] `docs/widget_catalog/layout_and_inputs.md` — Daily Nutrition `Today` header now references `nutrition_target_button`.
- [x] `docs/design_system.md` — Daily Nutrition headers row updated to mention the labelled `OutlinedButton.icon`.
- [x] `docs/navigation_and_screens.md` — `NutritionScreen` row updated to describe the labelled control and its state-aware label.
- [x] `docs/data_models.md` — N/A (no model changes).
- [x] `docs/db_integration.md` — N/A (no repository changes).
- [x] `docs/state_management.md` — N/A (no state-class changes).
- [x] `docs/navigation_contract.md` — N/A (no new routes).

## Feedback

<!-- Append feedback from blocked iterations here. -->

### Phase 0 Complete ✓
