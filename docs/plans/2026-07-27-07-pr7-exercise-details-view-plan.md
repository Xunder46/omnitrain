# PR 7: Exercise Details View

> **Priority 7 of 8 — Tier 4 prerequisite.** Item 11 only; must land before PR 8.

## Overview

Preserve picker row-tap immediate addition while adding a separate view control and reusable read-only details surface. Opening/back adds nothing; an explicit details Add action adds exactly once.

## Requirements

- Add distinct non-overlapping details control to each picker row.
- Row body still adds immediately.
- Details show read-only name, optional description, discipline, muscles, and tracking methods.
- Add from details exactly once or go back without adding.
- Mark user-created exercises in picker/details.
- Collapse absent description/muscles cleanly.
- Preserve search/filter/ranking/order.
- Build surface for PR 8 reuse without management actions.

## Acceptance Criteria

- [ ] Distinct details control does not overlap row add hit area.
- [ ] Row body still adds immediately.
- [ ] Opening/back adds nothing.
- [ ] Details render all available reference data and no editable fields.
- [ ] Add from details adds exactly once and returns to session.
- [ ] Custom marker appears in both surfaces.
- [ ] Missing optional data leaves no gap/placeholder.
- [ ] Search/filter/order are unchanged.

## Scenarios

### S-001: Inspect without adding
- Trigger: Tap details control.
- Precondition: Picker open for active session.
- Flow: Open details → back.
- Expected outcome: Session unchanged.
- Edge case of: none

### S-002: Add from either path exactly once
- Trigger: Tap row body or details Add.
- Precondition: Exercise selectable.
- Flow: Execute one path.
- Expected outcome: Exercise added once.
- Edge case of: none

### S-003: Sparse custom exercise renders cleanly
- Trigger: Open custom exercise lacking description/muscles.
- Precondition: Ownership identity is reliable.
- Flow: Render row/details.
- Expected outcome: Marker visible and optional sections collapse.
- Edge case of: S-001

## Iteration 1

### DB Changes
- None. PR 1's baseline doc flagged `ownerUserId` nullability as
  unreliable but the implementation reality is consistent:
  - `lib/state/workout/exercise_library.dart` -> `createExercise`
    stamps every custom row with `ownerUserId: 'user-1'`.
  - `lib/mock/seed_data.dart` leaves `ownerUserId` null on every
    bundled row.
  - `HiveWorkoutRepository` round-trips the field losslessly.
  No migration is required for PR 7; the existing data is already
  in the contract-conforming shape.

### Backend Changes
- **Ownership contract**: PR 7 establishes the canonical marker as
  `Exercise.isCustomExercise` (see the new `ExerciseCapabilities`
  extension getter in `lib/core/utils/exercise_helpers.dart`). It
  is `ownerUserId != null`. Every UI surface that needs to highlight
  custom exercises MUST go through this getter; reading
  `ownerUserId` directly is now a code-review warning.
- **Details Add idempotency**: enforced in the screen layer
  (`_ExerciseDetailViewScreenState._hasPoppedWithAdd`) rather than
  in the repository. The Add action is a presentation concern;
  business state should never see a second tap.

### Frontend Changes
- **New screen**: `lib/features/exercise/exercise_detail_view_screen.dart`
  (`ExerciseDetailViewScreen`) — reusable read-only surface. Pushed
  via `OmniNavigator.push<Exercise>` from the picker; pop result is
  the chosen `Exercise` (Add action) or `null` (back).
- **Picker affordance**: per-row trailing `IconButton`
  (`Icons.info_outline`, key `exercise_row_details_button`) opens
  the details screen. The row body continues to pop the picked
  exercise immediately — the existing immediate-add contract is
  preserved.
- **Custom marker**: rows whose exercise has `isCustomExercise`
  render a `Custom` chip on the title row
  (key `exercise_row_custom_marker`). The marker is also surfaced
  on the details screen title row (key `exercise_detail_custom_marker`).
- **Optional sections**: description, discipline, capabilities, and
  muscles collapse cleanly when absent. Each section has its own
  test key so tests can assert collapse behaviour
  (`exercise_detail_{description,discipline,capabilities,muscles}_section`).
- **Buttons**: the bottom Add `FilledButton` uses
  `OmniTheme.buttonPrimaryHeight` × `double.infinity` with
  `RoundedRectangleBorder(BorderRadius.circular(OmniTheme.buttonBorderRadius))`.
  The trailing row IconButton uses
  `RoundedRectangleBorder(BorderRadius.circular(OmniTheme.buttonIconRadius))`
  via the standard `IconButton` defaults — the icon button is an
  icon-only hit region, so the icon-radius token applies. All colors
  derive from `theme.colorScheme`.

### Implementation Steps
1. **Ownership contract** — added `Exercise.isCustomExercise` getter
   in `lib/core/utils/exercise_helpers.dart`. Pure Dart, no model
   change.
2. **TDD** — `test/pr7_exercise_details_view_test.dart` (12 tests,
   one per acceptance scenario + sparse + idempotency).
3. **Details screen** — `lib/features/exercise/exercise_detail_view_screen.dart`.
   `OmniBackHeader` for the AppBar, `SurfaceContainer`-shaped cards
   via `OmniTheme.colorsForTheme(activeTheme).surface` +
   `surfaceBorder`. Add action as a bottomNavigationBar with the
   canonical button shape.
4. **Picker affordance** — `lib/features/exercise/exercise_picker_screen.dart`
   updated. Trailing `IconButton` (`exercise_row_details_button`) +
   title-row `Custom` chip (`exercise_row_custom_marker`).
5. **Verification** — `flutter test` is green: 2066 / 2066 pass,
   5 pre-existing skipped, 0 failures.
6. **Doc hygiene** — `docs/navigation_and_screens.md` updated
   (new screen inventory row + screen-flow branch).

## Unit Tests Required
- Open/back no mutation; details Add exactly once; row direct add.
- Sparse-data rendering and custom markers.
- Narrow “any row tap adds” tests to correct hit region.
- New screen render and interaction tests.

## Progress
- [x] TDD red run recorded
- [x] Phase 1 — Ownership persistence completed or N/A
- [x] Details view implemented
- [x] Picker affordance implemented
- [x] Full suite green (2066 / 2066, 5 pre-existing skipped)
- [x] Doc hygiene
- [x] Phase 3 — Code Review (✅ APPROVED — see review verdict below)
- [ ] Release-ready

## Feedback


### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

