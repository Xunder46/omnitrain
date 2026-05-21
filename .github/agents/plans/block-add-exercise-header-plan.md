# Feature: Move "Add Exercise" into Block Header as Plus Icon

## Overview
The block view in both `RoutineSetupScreen` and `WorkoutSessionScreen` (list view) currently shows a full-width `OutlinedButton.icon("Add Exercise")` at the bottom of each block card. This conflicts with the instrument-panel philosophy of dense, functional, low-chrome UI. Replacing it with a compact `IconButton` (plus icon) placed in the block header removes visual noise while preserving the action.

## Requirements
- Remove the full-width "Add Exercise" `OutlinedButton.icon` from the block body in both block-view screens
- Add a compact plus `IconButton` to the block header row in both screens
- The plus icon must trigger the same add-exercise flow as the current button
- The icon must carry an accessible tooltip/semantic label

## Acceptance Criteria
- [ ] The full-width "Add Exercise" button is absent from all block card bodies
- [ ] A plus `IconButton` appears in each block's header row (before the `PopupMenuButton`)
- [ ] Tapping the plus icon opens the same add-exercise flow (exercise picker → modality picker) as the previous button
- [ ] The `IconButton` has a `tooltip: 'Add exercise to block'` for accessibility
- [ ] Widget test: tapping the plus icon in a `RoutineSetupScreen` block header invokes the add-exercise flow
- [ ] Widget test: `find.text('Add Exercise')` findsNothing after the change
- [ ] Accessibility assertion: the icon button's semantic label is present

## Scenarios
UI-only reorganization. No schema changes, no new state methods, no new user-facing behavior.

## Iteration 1

### DB Changes
None.

### Backend / State Changes
None. `_addExercise` already exists in both screens; only the call site changes.

### Frontend Changes

#### `lib/features/routine/routine_setup_screen.dart` — `_buildSegmentCard`

**Current header row** (approx. line 345–430):
```
Row(children: [
  Expanded(Column([name, subtitle])),
  IconButton(up),
  IconButton(down),
  PopupMenuButton,
])
```

**Change 1 — Add plus icon before `PopupMenuButton`:**
```dart
IconButton(
  icon: const Icon(Icons.add),
  tooltip: 'Add exercise to block',
  onPressed: () => _addExercise(context, segment.id),
),
```

**Change 2 — Remove full-width button** (approx. line 485–502):
Delete the entire `const SizedBox(height: 12)` + `Row(children: [Expanded(OutlinedButton.icon(...))])` block at the bottom of the `_buildSegmentCard` column.

---

#### `lib/features/session/workout_session_list_view.dart` — `_buildSessionBlockCard`

**Current header row** (approx. line 160–230):
```
Row(children: [
  Expanded(Text(block.name)),
  PopupMenuButton,
])
```

**Change 1 — Add plus icon before `PopupMenuButton`:**
```dart
IconButton(
  icon: const Icon(Icons.add),
  tooltip: 'Add exercise to block',
  onPressed: () => _addExercise(segmentId: segmentId, blockId: block.id),
),
```

**Change 2 — Remove full-width button** (approx. line 244–265):
Delete the `const SizedBox(height: 4)` + `Row(children: [Expanded(OutlinedButton.icon(...))])` block at the bottom of the card column.

---

#### `test/screen_widget_test.dart` — new tests

Add a group (or tests within the existing `RoutineSetupScreen` group) covering:

1. **`'block header plus icon triggers add-exercise flow'`**
   - Build `RoutineSetupScreen` with a `RoutineState` that already has one segment
   - Pump and settle
   - `find.byIcon(Icons.add)` → `findsWidgets` (at least one in a block header)
   - Tap the first `Icons.add` icon button
   - `pumpAndSettle()`
   - Assert `find.byType(ExercisePickerDialog)` findsOneWidget (or the modality picker, whichever appears first)

2. **`'old full-width Add Exercise button is gone'`**
   - Build `RoutineSetupScreen` with at least one segment
   - Pump and settle
   - `expect(find.widgetWithText(OutlinedButton, 'Add Exercise'), findsNothing)`

3. **`'block header plus icon has accessible tooltip'`**
   - Build `RoutineSetupScreen` with at least one segment
   - Pump and settle
   - `expect(find.byTooltip('Add exercise to block'), findsWidgets)`

### Implementation Steps
1. [ ] Edit `_buildSegmentCard` in `routine_setup_screen.dart`: add `IconButton` before `PopupMenuButton`
2. [ ] Edit `_buildSegmentCard` in `routine_setup_screen.dart`: delete bottom `Row(OutlinedButton.icon)` + its `SizedBox`
3. [ ] Edit `_buildSessionBlockCard` in `workout_session_list_view.dart`: add `IconButton` before `PopupMenuButton`
4. [ ] Edit `_buildSessionBlockCard` in `workout_session_list_view.dart`: delete bottom `Row(OutlinedButton.icon)` + its `SizedBox`
5. [ ] Add three widget tests to `test/screen_widget_test.dart`
6. [ ] Run `flutter test` to confirm green

## Progress
- [x] Edit `_buildSegmentCard` — add plus icon to header
- [x] Edit `_buildSegmentCard` — remove bottom Add Exercise button
- [x] Edit `_buildSessionBlockCard` — add plus icon to header
- [x] Edit `_buildSessionBlockCard` — remove bottom Add Exercise button
- [x] Add widget tests (plus icon invokes flow, old button gone, tooltip present)
- [x] Confirm all tests pass

### Phase Complete ✓
Implementation done. All 812 tests green. Ready for Code Reviewer.

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->
