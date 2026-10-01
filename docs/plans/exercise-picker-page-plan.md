# Feature: Exercise Picker — Dialog → Full-Screen Page

## Overview

Replace the `ExercisePickerDialog` (a `Dialog`-based widget) with `ExercisePickerScreen` (a full-screen `Scaffold`-based page). All search, ranking, create-new, and exercise-return behaviour is preserved exactly. Only the container changes. All four call sites are updated to use `OmniNavigator.push<Exercise>` instead of `showDialog<Exercise>`. Tests that pump the picker as a dialog are updated to pump it as a full-screen screen.

> **Dependency**: Header standardisation (`OmniBackHeader`) has already landed. `lib/widgets/layout/omni_back_header.dart` exists and is production-ready.

## Acceptance Criteria

- [ ] Adding an exercise from a live workout, from the session overview, and from the routine builder each opens a full-screen exercise picker page (no `Dialog` widget in the tree).
- [ ] The picker page has a working search field that filters exercises by name.
- [ ] When opened in a session that has a modality, exercises recommended for that modality appear in a "Recommended" section above the rest.
- [ ] Creating a new custom exercise from the picker page returns to the picker with the new exercise present and selectable (existing `_openCreateExercise` flow preserved).
- [ ] Selecting an exercise returns the user to the originating screen and triggers the same next step (tracking-method or modality prompt where applicable).
- [ ] Backing out of the picker (back arrow) returns to the originating screen with no exercise added.
- [ ] The picker page header uses `OmniBackHeader(title: 'Select Exercise')`, consistent with all other secondary screens.
- [ ] No existing passing tests are broken.

---

## Analysis

### Current Architecture

`ExercisePickerDialog` in `lib/widgets/pickers/exercise_picker_dialog.dart`:

- A `StatefulWidget` rendered as a `Dialog` with a fixed `width = 90% viewport`, `height = 86% viewport` container.
- Contains: search field, discipline/muscle-group filter dropdowns, clear-filters button, results count label, sectioned `ListView` (Recommended / Other based on `RECOMMENDED_SCORE_THRESHOLD`), "New Exercise" `OutlinedButton`.
- Wraps its content in a custom `pickerTheme` (`Theme(data: pickerTheme, ...)`) to override `filledButtonTheme` and `colorScheme`. This theme override exists **only** to compensate for dialog isolation; it is not needed in a full-page screen.
- `onTap` in each exercise tile calls `Navigator.of(context).pop(exercise)` — unchanged in the new screen since `OmniNavigator.push<T>` resolves on pop, same as `showDialog`.

### Four Call Sites

| File | Method | Current | Notes |
|---|---|---|---|
| `lib/features/session/workout_session_screen.dart` | `_addExercise()` | `showDialog<Exercise>()` | Line ~1170 |
| `lib/features/session/session_overview_screen.dart` | `_addExercise()` | `showDialog<Exercise>()` | Line ~70 |
| `lib/features/routine/routine_setup_screen.dart` | `_addExercise()` | `showDialog<Exercise>()` | Line ~690 |
| `lib/features/session/session_summary_screen.dart` | `addExercise()` (inside `showModalBottomSheet` `StatefulBuilder`) | `showDialog<Exercise>()` | Line ~364 |

The request names three entry points — live workout, session overview, routine builder. `session_summary_screen.dart` ("Save as Routine" sheet) is a fourth call site that must also be converted.

### `session_summary_screen.dart` — Modal-Sheet Navigation

`addExercise()` is a local async closure inside `StatefulBuilder` inside `showModalBottomSheet`. The `context` parameter of the `StatefulBuilder.builder` is the sheet's route context; `Navigator.of(context)` resolves to the app's root navigator (the sheet IS a route, pushed by `showModalBottomSheet`). Pushing `ExercisePickerScreen` with this context will stack:

```
[SessionSummaryScreen → ModalSheet → ExercisePickerScreen]
```

When picker pops, we land back on the modal sheet with the result — exactly the right behavior. No special outer-context capture needed; just replace `showDialog` with `OmniNavigator.push` using the same `context`.

---

## Implementation Plan

### Phase 1: Create `ExercisePickerScreen` (@developer)

**New file**: `lib/features/exercise/exercise_picker_screen.dart`

Place it alongside `exercise_editor_screen.dart` in `lib/features/exercise/` since it is a screen, not a reusable widget.

**Class structure** (rename widget and state, transplant all existing logic):

```dart
class ExercisePickerScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final String? sessionModality;

  const ExercisePickerScreen({
    super.key,
    required this.workoutState,
    this.sessionModality,
  });

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}
```

**State class**: Transplant all fields and methods verbatim from `_ExercisePickerDialogState`:
- `_searchController`, `_debounce`, `_filteredExercises`, `_recommendedExercises`, `_otherExercises`, `_muscleGroups`, `_disciplines`, `_exerciseMuscleGroupsCache`, `_selectedDisciplineId`, `_selectedMuscleGroupId`, `_isLoading`
- `initState`, `didUpdateWidget`, `dispose`
- `_loadData`, `_onSearchChanged`, `_searchExercises`, `_clearFilters`, `_partitionExercises`, `_openCreateExercise`
- `_buildExerciseList`, `_buildSectionHeader`, `_buildExerciseTile`

**`build()` method — full replacement**:

```dart
@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final themeColors = OmniTheme.colorsForTheme(OmniTheme.activeTheme);

  return Scaffold(
    backgroundColor: Colors.transparent,
    extendBodyBehindAppBar: true,
    appBar: const OmniBackHeader(title: 'Select Exercise'),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "New Exercise" button — same OutlinedButton.icon as before
            SizedBox(width: double.infinity, child: OutlinedButton.icon(...)),
            const SizedBox(height: 16),
            // Search field — identical
            TextField(...),
            const SizedBox(height: 12),
            // Filter row — identical (discipline + muscle dropdowns)
            Row(children: [...]),
            // Clear filters (conditional) — identical
            ...
            const SizedBox(height: 16),
            // Results count — identical
            Text('...'),
            const SizedBox(height: 8),
            // Exercise list — identical
            Expanded(child: ...),
          ],
        ),
      ),
    ),
  );
}
```

Key differences from the old `build()`:
1. **Remove** the `Theme(data: pickerTheme, ...)` wrapper — not needed in a full-page screen.
2. **Remove** `MediaQuery.removeViewInsets`, `Dialog`, `Container(width: ..., height: ..., padding: ...)`.
3. **Remove** the header `Row(IconButton(close), Text('Select Exercise'))` — replaced by `OmniBackHeader`.
4. **Keep** the existing `OutlinedButton.icon(onPressed: _openCreateExercise, label: 'New Exercise')` and all content below it, now placed inside a `SafeArea > Padding > Column`.
5. `extendBodyBehindAppBar: true` so the gradient renders behind the transparent header (consistent with all other secondary screens).
6. `backgroundColor: Colors.transparent` on the Scaffold (same as `ExerciseEditorScreen`).

> **Note**: The `pickerTheme` overrides were providing `colorScheme.surface` for the dialog container background and `filledButtonTheme` for the "New Exercise" button look. In a full-page screen these come from the app theme automatically. The "New Exercise" button is an `OutlinedButton`, not a `FilledButton`, so the `filledButtonTheme` override was actually irrelevant to it — it only applied to buttons _inside_ the dialog hierarchy. Remove `pickerTheme` entirely.

### Phase 2: Update Call Sites (@developer)

For each call site, replace:
```dart
final selectedExercise = await showDialog<Exercise>(
  context: context,
  barrierColor: Colors.black.withOpacity(0.78),
  builder: (context) => ExercisePickerDialog(
    workoutState: widget.workoutState,
    sessionModality: modality,
  ),
);
```
with:
```dart
final selectedExercise = await OmniNavigator.push<Exercise>(
  context,
  (_) => ExercisePickerScreen(
    workoutState: widget.workoutState,
    sessionModality: modality,
  ),
);
```

#### 1. `lib/features/session/workout_session_screen.dart` — `_addExercise()`

- Add import: `import '../../features/exercise/exercise_picker_screen.dart';`
- Remove import of `exercise_picker_dialog.dart` (if it becomes unused here).
- Replace `showDialog<Exercise>(...)` with `OmniNavigator.push<Exercise>(...)`.
- All logic after `selectedExercise != null` is unchanged.

#### 2. `lib/features/session/session_overview_screen.dart` — `_addExercise()`

- Add import: `import '../../features/exercise/exercise_picker_screen.dart';`
- Remove import of `exercise_picker_dialog.dart`.
- Replace `showDialog<Exercise>(...)` with `OmniNavigator.push<Exercise>(...)`.

#### 3. `lib/features/routine/routine_setup_screen.dart` — `_addExercise()`

- Add import: `import '../../features/exercise/exercise_picker_screen.dart';`
- Remove import of `exercise_picker_dialog.dart`.
- Replace `showDialog<Exercise>(context: context, ..., builder: (_) => ExercisePickerDialog(workoutState: widget.workoutState!))` with `OmniNavigator.push<Exercise>(context, (_) => ExercisePickerScreen(workoutState: widget.workoutState!))`.
- Note: `routine_setup_screen.dart` passes no `sessionModality` (routines are modality-agnostic at picker time — modality is chosen afterward via `ModalityPickerDialog`). This is preserved.

#### 4. `lib/features/session/session_summary_screen.dart` — `addExercise()` inside `StatefulBuilder`

- Add import: `import '../../features/exercise/exercise_picker_screen.dart';`
- Remove import of `exercise_picker_dialog.dart`.
- Replace `showDialog<Exercise>(context: context, ..., builder: (context) => ExercisePickerDialog(...))` with `OmniNavigator.push<Exercise>(context, (_) => ExercisePickerScreen(...))`.
- The `context` used is the `StatefulBuilder.builder`'s first parameter, which is the sheet route's context. `Navigator.of(context)` resolves to the app navigator. The picker pushes on top of the sheet; when it pops, the sheet is restored. ✓

### Phase 3: Delete Old Dialog File (@developer)

Delete `lib/widgets/pickers/exercise_picker_dialog.dart` once all imports have been updated to `exercise_picker_screen.dart`.

> **Before deleting**: run `grep -r "exercise_picker_dialog" lib/` to confirm zero remaining references in `lib/`. Test files will need updating first (Phase 4).

### Phase 4: Update Tests (@developer)

#### A. `test/screen_widget_test.dart` — `ExercisePickerDialog` group (lines ~4046–4320)

1. Update import: replace `import 'package:omnitrain/widgets/pickers/exercise_picker_dialog.dart';` with `import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';`.

2. Rename the group: `group('ExercisePickerDialog', ...)` → `group('ExercisePickerScreen', ...)`.

3. For every test that does:
   ```dart
   MaterialApp(home: Scaffold(body: ExercisePickerDialog(workoutState: workoutState)))
   ```
   change to:
   ```dart
   MaterialApp(home: ExercisePickerScreen(workoutState: workoutState))
   ```
   (The screen is a `Scaffold` itself; no outer `Scaffold` wrapper needed.)

4. **Update or remove dialog-specific assertions**:

   | Old assertion | Action | Replacement |
   |---|---|---|
   | `find.byType(Dialog)` | Replace | `find.byType(OmniBackHeader)` |
   | `tester.widget<Dialog>(find.byType(Dialog)).backgroundColor` | Replace | No equivalent — surface color now comes from app theme |
   | `find.ancestor(of: find.byType(Dialog), matching: find.byType(Theme))` + picker theme assertions | **Remove test** — this was testing a dialog implementation detail (the `pickerTheme` wrapper). The page version intentionally removes the theme override. | N/A |

5. **Add header assertion** to each existing test (or create one dedicated test):
   ```dart
   expect(find.byType(OmniBackHeader), findsOneWidget);
   expect(find.text('Select Exercise'), findsOneWidget);
   ```

6. **Test: "uses the active themed sheet surface"** — This tested `dialog.backgroundColor`. Replace with a structural check that `ExercisePickerScreen` renders a `Scaffold` with `backgroundColor: Colors.transparent` (page inherits background from navigator). Or simply drop it and cover surface styling through the existing app-level theme tests.

7. **Test: "enforces filled CTA styling for the active picker theme"** — This tested `pickerTheme.filledButtonTheme`. The `pickerTheme` is removed in the page version. **Drop this test** as it tested an implementation detail that no longer exists. The "New Exercise" button is `OutlinedButton.icon`, not a `FilledButton`, so the `filledButtonTheme` never applied to it anyway.

8. **Retain all other tests**, only changing the pump widget:
   - "shows Select Exercise title" ✓
   - "shows search field" ✓
   - "shows New Exercise button" ✓
   - "uses subdued styling for recommended label and metadata chips" ✓
   - "sports modality recommends boxing exercises" ✓
   - "shows exercises from repo" ✓
   - "filters exercises by search text" ✓
   - "does not overflow when keyboard is open with empty results" ✓
   - "New Exercise label is not wrapped in shrink-to-fit FittedBox" ✓
   - "New Exercise label type role is more prominent than dropdown value text" ✓

#### B. `test/screen_widget_test.dart` — `RoutineSetupScreen` test at line ~843

Locate: `'block header plus icon triggers add-exercise flow'`

```dart
// OLD:
expect(find.byType(ExercisePickerDialog), findsOneWidget);

// NEW:
expect(find.byType(ExercisePickerScreen), findsOneWidget);
```

Also update the import at the top: add `import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';`, remove the `exercise_picker_dialog.dart` import if it becomes unused.

#### C. `test/interaction_flow_test.dart` — `ExercisePickerDialog interactions` group (lines ~763–830)

1. Update import: replace `exercise_picker_dialog.dart` → `exercise_picker_screen.dart`.
2. Rename group to `ExercisePickerScreen interactions`.
3. **Test: "tapping an exercise navigates back with exercise result"**:
   - This test already uses `MaterialPageRoute(builder: (_) => Scaffold(body: ExercisePickerDialog(...)))`. Since `ExercisePickerScreen` is itself a `Scaffold`, change to `MaterialPageRoute(builder: (_) => ExercisePickerScreen(...))`. The rest of the test is unchanged — it taps a `ListTile` and asserts `tappedExercise != null`.
4. **Test: "search field filters exercise list"**:
   - Change pump widget: `MaterialApp(home: Scaffold(body: ExercisePickerDialog(...)))` → `MaterialApp(home: ExercisePickerScreen(...))`. The search assertion is unchanged.

#### D. `test/capitalization_defaults_test.dart` (line ~16, 200)

1. Update import: `exercise_picker_dialog.dart` → `exercise_picker_screen.dart`.
2. Replace `ExercisePickerDialog(...)` with `ExercisePickerScreen(...)` at the usage site.
3. Adjust pump widget if it wraps in `Scaffold` (same pattern as above).

#### E. New tests to add (per acceptance criteria)

In `test/screen_widget_test.dart`, within the new `ExercisePickerScreen` group, add:

1. **"header uses OmniBackHeader with 'Select Exercise' title"**
   ```dart
   testWidgets('uses OmniBackHeader with Select Exercise title', (tester) async {
     ...
     expect(find.byType(OmniBackHeader), findsOneWidget);
     expect(find.text('Select Exercise'), findsOneWidget);
   });
   ```

2. **"back arrow is present"**
   ```dart
   expect(find.byIcon(Icons.arrow_back), findsOneWidget);
   ```

3. **"modality ranking sections present with modality"** — confirm `find.text('Recommended')` and `find.text('Other')` when `sessionModality` is non-null and exercises loaded. (The existing sports-modality test already covers this; just verify it passes.)

4. **"no ranking sections without modality"** — `sessionModality: null`, confirm `find.text('Recommended')` and `find.text('Other')` are absent.

In `test/interaction_flow_test.dart`, add (or confirm existing tests cover):

5. **"tapping an exercise from RoutineSetupScreen opens ExercisePickerScreen"**:
   - Pump `RoutineSetupScreen`, tap the block "+" icon, assert `find.byType(ExercisePickerScreen).findsOneWidget`.
   - Already covered by the updated B test above.

6. **"tapping an exercise from SessionOverviewScreen opens ExercisePickerScreen"**:
   - Pump `SessionOverviewScreen`, tap "Add Exercise", assert `find.byType(ExercisePickerScreen).findsOneWidget`.
   - Add this test to the existing `SessionOverviewScreen interactions` group.

---

## Files Affected

### New
- `lib/features/exercise/exercise_picker_screen.dart`

### Modified
- `lib/features/session/workout_session_screen.dart` (1 `showDialog` → `OmniNavigator.push`)
- `lib/features/session/session_overview_screen.dart` (1 `showDialog` → `OmniNavigator.push`, import update)
- `lib/features/routine/routine_setup_screen.dart` (1 `showDialog` → `OmniNavigator.push`, import update)
- `lib/features/session/session_summary_screen.dart` (1 `showDialog` → `OmniNavigator.push`, import update)
- `test/screen_widget_test.dart` (import, group rename, pump widget, 2 test removals, assertion updates)
- `test/interaction_flow_test.dart` (import, group rename, pump widget updates, new nav test)
- `test/capitalization_defaults_test.dart` (import, usage update)

### Deleted
- `lib/widgets/pickers/exercise_picker_dialog.dart`

### Docs to update after implementation
- `docs/navigation_and_screens.md` — update `ExercisePickerDialog` → `ExercisePickerScreen` in the screen table and navigation tree

---

## Notes

### `pickerTheme` removal is safe
The dialog used a custom `Theme` wrapper with overridden `colorScheme` and `filledButtonTheme`. In a full-page screen inside the normal navigator, the app's root `MaterialApp` theme already provides correct tokens (`themeColors.primary`, `themeColors.surface`, etc.). The `filledButtonTheme` override was superfluous since the "New Exercise" button is an `OutlinedButton`, not a `FilledButton`.

### Session-summary sheet navigation pattern
`showModalBottomSheet` pushes a route onto the navigator. The `BuildContext` passed to `StatefulBuilder.builder` is that route's context; `Navigator.of(context)` resolves the same app navigator. Pushing `ExercisePickerScreen` from within the sheet stacks:
```
[SessionSummaryScreen → ModalSheet → ExercisePickerScreen]
```
Popping from the picker restores the modal sheet. This is standard Flutter navigation — no root-navigator tricks required.

### `_openCreateExercise` is already a page push
Inside `ExercisePickerScreen`, the `_openCreateExercise` method already uses `OmniNavigator.push<Exercise>` to push `ExerciseEditorScreen`. No change needed there.

### No state, repository, or search-logic changes
This is purely a presentation-layer change. `getExercisesRankedForModality`, `RECOMMENDED_SCORE_THRESHOLD`, `_partitionExercises`, all filter dropdowns, the results count label — all transplanted verbatim.

---

## Progress

- [x] Create `lib/features/exercise/exercise_picker_screen.dart` (transplant state + new Scaffold build)
- [x] Update `workout_session_screen.dart` call site
- [x] Update `session_overview_screen.dart` call site
- [x] Update `routine_setup_screen.dart` call site
- [x] Update `session_summary_screen.dart` call site
- [x] Update `test/screen_widget_test.dart` (ExercisePickerScreen group + RoutineSetupScreen test)
- [x] Update `test/interaction_flow_test.dart`
- [x] Update `test/capitalization_defaults_test.dart`
- [x] Delete `lib/widgets/pickers/exercise_picker_dialog.dart`
- [x] Update `docs/navigation_and_screens.md`
- [x] Fix 4 WorkoutSessionScreen test regressions (dismiss auto-opened ExercisePickerScreen via Icons.arrow_back)
- [x] Fix 2 additional regressions in `widget_test.dart` and `session_finish_timers_test.dart` (same root cause, residual Icons.close dismissal)
- [x] Add missing test: "no ranking sections shown when sessionModality is null" (screen_widget_test.dart)
- [x] Add missing test: "tapping Add Exercise opens ExercisePickerScreen" (interaction_flow_test.dart SessionOverviewScreen group)
- [x] Fix stale comment in `home_screen.dart` line 385 (ExercisePickerDialog → ExercisePickerScreen)
- [x] Run all tests — 977 passed, 0 failed

## Feedback

**Added by Code Reviewer — iteration 1**

### CRITICAL — 4 Test Regressions (Root Cause Identified)

The plan's acceptance criteria AC8 ("No existing passing tests are broken") is violated. 4 tests that passed before the feature now fail:

1. `screen_widget_test.dart` — `WorkoutSessionScreen – Finish Workout button theme context – Finish Workout and add buttons inherit the active accent across themes`
2. `screen_widget_test.dart` — `WorkoutSessionScreen – rolling session block UI – non-rolling empty session shows Add Exercise and Add Block above Finish Workout`
3. `screen_widget_test.dart` — `WorkoutSessionScreen – rolling session block UI – rolling session shows Add Exercise and Add Block actions`
4. `interaction_flow_test.dart` — `WorkoutSessionScreen – shows centered add actions when session is empty`

**Root cause:** All 4 tests create an empty session and pump `WorkoutSessionScreen`. The screen's `_scheduleAutoOpenPicker()` fires (via `Future.microtask`) because `_exercises.isEmpty = true`. It calls `_addExercise()` which now calls `OmniNavigator.push<Exercise>` (a full-screen navigation push) instead of the old `showDialog<Exercise>` (a dialog overlay).

Because `OmniRoute.opaque = true`, Flutter puts `WorkoutSessionScreen` in an `Offstage` state when `ExercisePickerScreen` is on top. After `pumpAndSettle()`, the widget tree has `ExercisePickerScreen` as the active route and `WorkoutSessionScreen` offstage. `find.widgetWithText(FilledButton, 'Finish Workout')` cannot find the button because offstage widgets are excluded from `find` results.

Previously with `showDialog`, the dialog was an overlay on the SAME route; `WorkoutSessionScreen` remained the active route with its buttons visible. With `OmniNavigator.push`, `WorkoutSessionScreen` is a background route (offstage).

**Fix needed (test-only — no production code change required):**

After `await tester.pumpAndSettle()`, if `ExercisePickerScreen` is present (auto-opened), pop it before asserting session-screen state:

```dart
await tester.pumpAndSettle();
// Dismiss auto-opened picker so WorkoutSessionScreen is foregrounded
if (find.byType(ExercisePickerScreen).evaluate().isNotEmpty) {
  await tester.pageBack();
  await tester.pumpAndSettle();
}
// Now WorkoutSessionScreen empty state is visible; _autoOpenAttempted = true prevents re-open
expect(find.widgetWithText(FilledButton, 'Finish Workout'), findsOneWidget);
```

Apply this pattern to all 4 failing tests. `_autoOpenAttempted` is set to `true` before `OmniNavigator.push` is called, so after popping back the picker will not re-open.

**The plan's Progress checklist shows `[x] Run all tests — confirm no regressions` — this is incorrect. Un-check this item and re-check only after the 4 regressions are fixed.**

---

### WARNING — Missing Tests (Plan Phase 4E items 3, 4, 6)

Three tests specified in the plan's Phase 4E were not added:

- **4E item 3/4** (`screen_widget_test.dart` `ExercisePickerScreen` group): "no ranking sections without modality" test. The `find.text('Recommended')` / `find.text('Other')` assertion for `sessionModality: null` was not written.
- **4E item 6** (`interaction_flow_test.dart` `SessionOverviewScreen interactions` group): "tapping Add Exercise from SessionOverviewScreen opens ExercisePickerScreen" test was not added.

---

### WARNING — Stale Comment in `home_screen.dart`

`lib/features/home/home_screen.dart` line 385 still contains:
```dart
// Pass the tapped tile's modality so ExercisePickerDialog pre-filters.
```
Should be: `ExercisePickerScreen`.

---

**Hand off to**: @developer to fix the 4 regressions, add the 3 missing tests, and correct the stale comment. Re-run all tests before returning to reviewer.

