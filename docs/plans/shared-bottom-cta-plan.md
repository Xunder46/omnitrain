# Feature: shared-bottom-cta

## Overview
Standardize every single full-width bottom primary action across the app with a shared `OmniBottomCTA` widget so footer actions look and behave consistently across screens.

This is a UI-only consistency pass. No repository, database, or state-model changes are required.

## Requirements
- Create `lib/widgets/layout/omni_bottom_cta.dart`.
- Widget API: `label`, `onPressed`, optional `isDestructive = false`.
- Internally render a full-width `FilledButton` using `OmniTheme.buttonPrimaryHeight` and `OmniTheme.buttonBorderRadius`.
- Wrap in `SafeArea(top: false)`.
- Include a shared bottom fade/gradient treatment behind the CTA so it lifts cleanly above scrollable content.
- Use theme-derived colors from `Theme.of(context).colorScheme`.
- Support destructive styling for `isDestructive == true` using the app’s error/destructive theme token aligned to the red-700 design intent.
- Preserve all existing labels, callbacks, and navigation behavior.
- Do not change layout above the CTA.
- Remove duplicated gradient/footer CTA implementations where the new widget replaces them.

---

## Analysis
The current app has several independently styled footer buttons with slightly different padding, background treatment, and button styling:
- `SessionSummaryScreen` has a custom bottom container and border.
- `PeriodListScreen` and `CreatePeriodScreen` each define their own bottom-sheet CTA.
- `WorkoutSessionScreen` has a floating/positioned finish CTA and existing gradient treatment to preserve.
- Additional single-CTA candidates exist in `exercise_editor_screen.dart` and a few form-like screens that should be audited during implementation.

Because this is strictly a shared UI extraction with no new persistence or state methods, it qualifies for the fast-track path directly to `@developer`.

## Questions (if any)
None. The scope and constraints are sufficiently clear to proceed.

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes (@developer)

#### 1. Create shared CTA widget
Add `lib/widgets/layout/omni_bottom_cta.dart` with:
- `final String label`
- `final VoidCallback? onPressed`
- `final bool isDestructive`

Implementation requirements:
- Root wrapper provides the footer gradient treatment.
- Use `SafeArea(top: false)`.
- Apply padding of 16 horizontal, 12 top, and 16 bottom inside the safe area.
- Render a `SizedBox` with `height: OmniTheme.buttonPrimaryHeight` and `width: double.infinity`.
- Render a `FilledButton` with a radius of `OmniTheme.buttonBorderRadius`.
- Use `theme.colorScheme.surface` for the gradient/background treatment.
- Use `theme.colorScheme.primary` / `onPrimary` for default CTA colors.
- Use the destructive theme token via `colorScheme.error` / matching foreground token so it remains theme-aware while honoring the red destructive design intent.
- Do not expose padding, radius, height, or color overrides at call sites.

#### 2. Migrate required screens
Replace existing bottom CTA implementations with `OmniBottomCTA` in:
- `lib/features/session/session_summary_screen.dart` — `Done`
- `lib/features/period/period_list_screen.dart` — `Create Period`
- `lib/features/period/create_period_screen.dart` — `Save`
- `lib/features/session/workout_session_screen.dart` — `Finish Workout` / `Save Changes` area

Migration rules:
- Keep the same label text and callback behavior.
- Do not change content layout above the footer.
- If a screen already has a gradient overlay for the CTA area, remove the old wrapper and let `OmniBottomCTA` own the full treatment.
- Ensure `WorkoutSessionScreen` does not end up with double gradients or double safe-area padding.

#### 3. Audit comparable single-footer CTA screens
During implementation, inspect and migrate any other clearly comparable single full-width bottom CTA screens, especially:
- `lib/features/exercise/exercise_editor_screen.dart` — `Save exercise`

Potentially comparable but verify before changing:
- form sheets or modals with embedded save buttons
- dual-action footer rows (for example cancel + save) should stay out of scope unless they can adopt the same visual language without changing structure

### Implementation Steps
1. [ ] Create `lib/widgets/layout/omni_bottom_cta.dart`.
2. [ ] Build the shared gradient + safe-area footer container inside the widget.
3. [ ] Centralize fixed CTA height and border radius using `OmniTheme` constants only inside the shared widget.
4. [ ] Use theme-derived colors from `Theme.of(context).colorScheme` for both normal and destructive states.
5. [ ] Replace the custom footer in `session_summary_screen.dart` with `OmniBottomCTA(label: 'Done', ...)`.
6. [ ] Replace the bottom-sheet CTA in `period_list_screen.dart` with `OmniBottomCTA(label: 'Create Period', ...)`.
7. [ ] Replace the bottom-sheet CTA in `create_period_screen.dart` with `OmniBottomCTA(label: 'Save', ...)`.
8. [ ] Replace the existing active workout finish/save CTA wrapper in `workout_session_screen.dart` with the shared widget, removing duplicate gradient treatment.
9. [ ] Audit `exercise_editor_screen.dart` and any other true single-bottom CTA screens for adoption.
10. [ ] Run targeted Flutter tests and a web smoke check for each migrated screen.

## Progress
- [x] Create shared `OmniBottomCTA` widget
- [x] Migrate `SessionSummaryScreen`
- [x] Migrate `PeriodListScreen`
- [x] Migrate `CreatePeriodScreen`
- [x] Migrate `WorkoutSessionScreen`
- [x] Audit and migrate other comparable single-CTA screens
- [x] Verify layout and theming on web

## Acceptance Criteria
- [x] `OmniBottomCTA` exists in `lib/widgets/layout/omni_bottom_cta.dart` and is reusable across screens.
- [x] The widget owns the full-width button, safe-area behavior, gradient background, padding, and shared sizing.
- [x] `SessionSummaryScreen`, `PeriodListScreen`, `CreatePeriodScreen`, and `WorkoutSessionScreen` all use the shared widget.
- [x] Button labels, callbacks, and navigation behavior remain unchanged.
- [x] No target screen has duplicate gradient/footer wrappers after migration.
- [x] Colors remain theme-reactive and do not introduce hardcoded button colors at the call site.
- [x] The bottom CTA clears device home indicators/navigation bars correctly on web/mobile layouts.

## Files Affected
- `lib/widgets/layout/omni_bottom_cta.dart`
- `lib/features/session/session_summary_screen.dart`
- `lib/features/period/period_list_screen.dart`
- `lib/features/period/create_period_screen.dart`
- `lib/features/session/workout_session_screen.dart`
- `lib/features/exercise/exercise_editor_screen.dart` (if confirmed comparable during audit)

## Notes
- This task is UI-only and does not need `@dba`.
- Fast-track applies: the user may skip Conductor and go directly to `@developer` for implementation.
- For the destructive style, use the active theme’s destructive/error tokens rather than introducing ad-hoc hardcoded values at screen level.
- Keep dual-button bottom bars (for example cancel/save pairs) structurally unchanged unless explicitly requested.

## Feedback
- Red verification before implementation: `flutter test test/screen_widget_test.dart` failed with compile errors because `OmniBottomCTA` did not yet exist.
- Green verification after implementation: `flutter test test/screen_widget_test.dart test/interaction_flow_test.dart test/session_finish_timers_test.dart` completed with `00:06 +137: All tests passed!`.
- Web smoke verification: `flutter run -d chrome --target lib/main.dart` launched successfully and initialized the Hive-backed boxes with no runtime errors in the captured log.
- Audit result: the only additional comparable single-footer CTA that needed migration beyond the required list was `ExerciseEditorScreen`.
- Follow-up compliance fix: the period list and create period screens were moved from scaffold bottom sheets to the shared bottom navigation footer pattern, and the shared CTA now preserves the exact passed label text.
- April 2026 regression fix: `ExerciseEditorScreen` now sets `extendBody: true` so the gradient body continues behind the footer CTA and avoids the stray light band at the bottom; the targeted footer regression test now passes.

### Phase 2 Complete ✓
Implementation done. Shared footer CTA migration verified on tests and web. Ready for Code Reviewer.
