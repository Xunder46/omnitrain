# Feature: Standardize Back-and-Title Screen Headers

## Overview

Every screen that uses a "back arrow + title" header currently uses a different implementation: some use `AppBar` with no explicit leading, some use `AppBar` with an explicit `IconButton`, some use a custom `Row` with no `AppBar` at all. Arrow color, title weight, header height, and padding all differ. The fix is a single shared `OmniBackHeader` widget used by all 12 target screens.

## Acceptance Criteria

- [ ] Every listed screen displays `Icons.arrow_back` in an `IconButton` at the same position with the same color.
- [ ] Every listed screen title uses `titleLarge` with `fontWeight: FontWeight.w600` and `letterSpacing: 0.4`.
- [ ] Header height and padding are identical across all listed screens (`kToolbarHeight` / `AppBar` default).
- [ ] All screens set `extendBodyBehindAppBar: true` so the gradient background renders behind the transparent header.
- [ ] Each screen's back action still navigates to the same destination as before.
- [ ] Calendar's `+` (Periods) action button is still present and functional, now as an `actions` entry in `OmniBackHeader`.
- [ ] SessionSummary's `PopupMenuButton` (Edit/Save/Discard) is still present and functional as an `actions` entry.
- [ ] SessionOverview's subtitle (modality name) is still rendered using `OmniBackHeader`'s optional `subtitle` parameter.
- [ ] RoutineSetup's dynamic subtitle (exercise count / exercise index) is still rendered.
- [ ] No screen's body content below the header is visually changed.
- [ ] Widget tests assert `OmniBackHeader` is present on each listed screen.
- [ ] Tests assert back button navigates to the previous screen.
- [ ] Tests confirm Calendar's Periods button and SessionSummary's overflow menu still work.
- [ ] No existing passing tests are broken.

---

## Analysis

### Current Header Inventory

| Screen | Current approach | Back arrow | Notes |
|---|---|---|---|
| `CalendarScreen` | `AppBar`, transparent bg | Auto (Flutter) | Has `FilledButton('+')` action |
| `DaySessionListScreen` | `AppBar`, transparent bg | Auto | None |
| `ExerciseEditorScreen` | `AppBar`, transparent + explicit `foregroundColor` | Auto | `foregroundColor` inconsistency |
| `CreatePeriodScreen` | `AppBar`, transparent bg | Auto | None |
| `PeriodListScreen` | `AppBar`, transparent bg | Auto | None |
| `ProfileScreen` | `AppBar`, transparent bg | Auto | None |
| `MyRoutinesScreen` | `AppBar`, transparent bg, **explicit `leading: IconButton`** | Explicit | Only screen with explicit leading in AppBar |
| `RoutineSetupScreen` | **Custom `_buildHeader()` Row**, no `AppBar` | `IconButton(Icons.arrow_back)` | Dynamic title + subtitle; `_buildListView` and `_buildDetailView` each return their own `Scaffold` |
| `SettingsScreen` | `AppBar`, transparent bg | Auto | None |
| `StatsScreen` | `AppBar`, transparent bg | Auto | None |
| `SessionOverviewScreen` | `AppBar`, **themed bg** (not transparent), `Column` title | Auto | Uses `themeColors.backgroundTop` on AppBar; multi-row title |
| `SessionSummaryScreen` | **Custom `Row` in `SliverToBoxAdapter`**, no `AppBar` | `IconButton(Icons.arrow_back)` | `PopupMenuButton` in trailing position; `Scaffold` has no `appBar:` |

### Key Inconsistencies

1. **Back arrow color**: `MyRoutines` defaults to theme icon color; `WorkoutSessionListView._buildHeader` uses `OmniTheme.textPrimary`; other AppBar screens use Flutter auto-color (inherits `foregroundColor`).
2. **Title weight**: AppBar screens use default `titleLarge` (no explicit weight); custom Row screens use `titleLarge.copyWith(fontWeight: FontWeight.w600)`.
3. **Letter spacing**: Not set on any screen; design system specifies `0.4` for titles.
4. **Header height**: AppBar = `kToolbarHeight` (56px); `RoutineSetup._buildHeader` uses `padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16)` which adds ~32px of vertical padding to a single-line `titleLarge` row (~56px total).
5. **Background**: 10 screens use `Colors.transparent`; `SessionOverview` uses `themeColors.backgroundTop`.
6. **Structure**: 10 screens use `Scaffold.appBar`; `SessionSummary` and `RoutineSetup` put headers inline in the body.

---

## Implementation Plan

### Phase 1: Create `OmniBackHeader` widget (@developer)

**New file**: `lib/widgets/layout/omni_back_header.dart`

Create `OmniBackHeader` that implements `PreferredSizeWidget` so it can be used as `Scaffold.appBar`.

```
class OmniBackHeader extends StatelessWidget implements PreferredSizeWidget {
  const OmniBackHeader({
    super.key,
    required this.title,
    this.subtitle,       // optional second line below title
    this.onBack,         // null = Navigator.of(context).pop()
    this.actions,        // optional trailing widgets
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        color: OmniTheme.textPrimary,
        onPressed: onBack ?? () => Navigator.of(context).pop(),
      ),
      title: subtitle == null
          ? Text(title)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title),
              Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(
                color: OmniTheme.textSecondary,
              )),
            ]),
      titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: OmniTheme.titleLetterSpacing, // 0.4
        color: OmniTheme.textPrimary,
      ),
      actions: actions,
    );
  }
}
```

> **Note**: The `titleTextStyle` override is required because `AppBar` does not inherit `fontWeight` or `letterSpacing` from the theme's `titleLarge` by default.

### Phase 2: Update AppBar screens (@developer)

For each screen below, replace the `AppBar(...)` call with `OmniBackHeader(title: ..., ...)`. Ensure `extendBodyBehindAppBar: true` is set (some already have it, add where missing). Remove `backgroundColor`, `elevation`, `surfaceTintColor` (now in `OmniBackHeader`). Remove any `leading:` argument (now handled by `OmniBackHeader`).

1. **`lib/features/calendar/calendar_screen.dart`**
   - Replace `AppBar(title: Text('Calendar'), ..., actions: [FilledButton...])` with `OmniBackHeader(title: 'Calendar', actions: [FilledButton...])`
   - Keep `FilledButton('+')` in `actions`; add `extendBodyBehindAppBar: true`

2. **`lib/features/calendar/day_session_list_screen.dart`**
   - Replace `AppBar(title: Text(title), ...)` with `OmniBackHeader(title: title)`
   - Add `extendBodyBehindAppBar: true`

3. **`lib/features/exercise/exercise_editor_screen.dart`**
   - Replace the `final appBar = AppBar(...)` + manual `foregroundColor` with `final appBar = OmniBackHeader(title: _isEditMode ? 'Edit Exercise' : 'New Exercise')`
   - Remove `foregroundColor` argument (now uniform)

4. **`lib/features/period/create_period_screen.dart`**
   - Replace `AppBar(title: Text(widget.existingPeriod == null ? 'Create Period' : 'Edit Period'), ...)` with `OmniBackHeader(title: widget.existingPeriod == null ? 'Create Period' : 'Edit Period')`

5. **`lib/features/period/period_list_screen.dart`**
   - Replace `AppBar(title: Text('Training Periods'), ...)` with `OmniBackHeader(title: 'Training Periods')`
   - Add `extendBodyBehindAppBar: true`

6. **`lib/features/profile/profile_screen.dart`**
   - Replace `AppBar(title: Text('Profile'), ...)` with `OmniBackHeader(title: 'Profile')`

7. **`lib/features/routine/my_routines_screen.dart`**
   - Replace `AppBar(title: Text('My Routines'), ..., leading: IconButton(...))` with `OmniBackHeader(title: 'My Routines')`
   - Remove the `leading:` argument (OmniBackHeader supplies the back button)

8. **`lib/features/settings/settings_screen.dart`**
   - Replace `AppBar(title: Text('Settings'), ...)` with `OmniBackHeader(title: 'Settings')`

9. **`lib/features/stats/stats_screen.dart`**
   - Replace `AppBar(title: Text('Stats'), ...)` with `OmniBackHeader(title: 'Stats')`

10. **`lib/features/session/session_overview_screen.dart`**
    - Replace `AppBar(title: Column([Text('Workout Session'), Text(modalityName, ...)]), backgroundColor: themeColors.backgroundTop, ...)` with `OmniBackHeader(title: 'Workout Session', subtitle: modalityName)`
    - Add `extendBodyBehindAppBar: true`; remove `backgroundColor` from AppBar (Scaffold still sets it)

### Phase 3: Migrate custom-Row screens (@developer)

These screens have no `Scaffold.appBar`; the header lives inside the body. The plan is to lift the header to `Scaffold.appBar: OmniBackHeader(...)` and remove the custom row from the body.

#### `lib/features/session/session_summary_screen.dart`

Current structure:
```
Scaffold(
  backgroundColor: transparent, extendBody: true,
  body: Stack([
    SafeArea(body: CustomScrollView(slivers: [
      SliverToBoxAdapter(     // ← this is the custom header row
        child: Padding(Row([IconButton(back), Expanded(Text(title)), PopupMenuButton(...)]))
      ),
      ...other slivers
    ])),
  ]),
)
```

Target structure:
```
Scaffold(
  backgroundColor: transparent, extendBody: true,
  extendBodyBehindAppBar: true,          // NEW
  appBar: OmniBackHeader(                // NEW
    title: title,
    actions: [PopupMenuButton(...)],
  ),
  body: Stack([
    SafeArea(body: CustomScrollView(slivers: [
      // SliverToBoxAdapter header ROW IS REMOVED
      ...other slivers (unchanged)
    ])),
  ]),
)
```

The `onBack` callback for the `OmniBackHeader` must call `Navigator.of(context).pop()` (same as the old `IconButton.onPressed`). The `PopupMenuButton` moves to the `actions` list.

#### `lib/features/routine/routine_setup_screen.dart`

`RoutineSetupScreen` is complex: it returns two separate `Scaffold` instances (`_buildListView` and `_buildDetailView`), each containing `_buildHeader(theme)` in its body `Column`. The `_buildHeader()` shows a dynamic title and subtitle.

Strategy: Add `appBar: OmniBackHeader(...)` to each of the two returned `Scaffold`s and add `extendBodyBehindAppBar: true`. Remove `_buildHeader(theme)` from each body column. The `onBack` and title logic come from `_buildHeader()`'s existing logic.

**`_buildListView` Scaffold change:**
- Add `extendBodyBehindAppBar: true`
- Add `appBar: OmniBackHeader(title: 'Exercises', subtitle: '${efforts.length} exercise${efforts.length != 1 ? 's' : ''}', onBack: () { _discardAndPop(); })`
- Remove `_buildHeader(theme)` from the body `Column`

**`_buildDetailView` Scaffold change:**
- Add `extendBodyBehindAppBar: true`
- Add `appBar: OmniBackHeader(title: exerciseName, subtitle: 'Exercise ${_currentExerciseIndex + 1} / ${efforts.length}', onBack: () { setState(() => _showListView = true); })`
- Remove `_buildHeader(theme)` from the body `Column`

> **Note**: The `_buildHeader()` method and its associated `Row`/`IconButton` can be deleted after this migration.

### Phase 4: Write tests (@developer)

**New file**: `test/header_standardization_test.dart`

1. **Shared header presence test** — For each of the 12 listed screens, pump the screen and assert `find.byType(OmniBackHeader).findsOneWidget`.

2. **Back arrow presence test** — For each screen, `find.byIcon(Icons.arrow_back).findsOneWidget`.

3. **Back navigation test** — Wrap each screen in a `Navigator`; tap the back arrow; assert the screen pops (verify `Navigator.canPop()` or use a `didPop` spy).

4. **Calendar Periods button test** — Pump `CalendarScreen`; assert `FilledButton` (or its text `'+'`) is present inside the `OmniBackHeader`.

5. **SessionSummary overflow menu test** — Pump `SessionSummaryScreen` with a completed session; assert `PopupMenuButton` is present; tap it; assert the menu items are present.

6. **OmniBackHeader unit test** — Pump a bare `OmniBackHeader(title: 'Test')` inside a `MaterialApp > Scaffold`; assert `Icons.arrow_back`, the title text, and correct `TextStyle` (`fontWeight: FontWeight.w600`, `letterSpacing: 0.4`).

7. **OmniBackHeader with subtitle test** — Pump with `subtitle: 'Sub'`; assert subtitle text is present.

8. **OmniBackHeader with custom onBack test** — Pump with `onBack: () { called = true; }`; tap back arrow; assert `called`.

**Update existing test**: 
- In `test/screen_widget_test.dart`, add assertions to the existing per-screen groups that `OmniBackHeader` is found (so the test documents both content AND header type going forward).

---

## Files Affected

### New
- `lib/widgets/layout/omni_back_header.dart`
- `test/header_standardization_test.dart`

### Modified
- `lib/features/calendar/calendar_screen.dart`
- `lib/features/calendar/day_session_list_screen.dart`
- `lib/features/exercise/exercise_editor_screen.dart`
- `lib/features/period/create_period_screen.dart`
- `lib/features/period/period_list_screen.dart`
- `lib/features/profile/profile_screen.dart`
- `lib/features/routine/my_routines_screen.dart`
- `lib/features/routine/routine_setup_screen.dart`
- `lib/features/session/session_overview_screen.dart`
- `lib/features/session/session_summary_screen.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/features/stats/stats_screen.dart`
- `test/screen_widget_test.dart`

---

## Notes

### `extendBodyBehindAppBar` consistency
When adding `OmniBackHeader` as `Scaffold.appBar`, all screens should have `extendBodyBehindAppBar: true` so the gradient background (rendered by `OmniGradientBackground` below the Scaffold's `backgroundColor: Colors.transparent`) shows through the header. Screens that already set this are unaffected; screens that were missing it get it added.

### `SessionSummaryScreen` SliverAppBar alternative
If migrating the custom Row to `Scaffold.appBar` causes any visual regression in the summary's sliver scroll behavior (e.g., the header sticking when it shouldn't), the fallback is to replace the `SliverToBoxAdapter` header row with a `SliverPersistentHeader` that internally renders an `OmniBackHeader` widget at the correct size. In practice, using `Scaffold.appBar` is simpler and should be tried first.

### `RoutineSetupScreen` WillPopScope
The existing `WillPopScope(onWillPop: _handleWillPop)` wraps the content returned by the builder. After the migration, the `OmniBackHeader.onBack` callbacks take over from `_buildHeader()`'s manual `onPressed` logic. The `_handleWillPop` callback (for Android back gesture) must remain intact — it is not removed. Ensure `WillPopScope` still wraps the returned widget tree.

### No body content changes
The task is header-only. Body content (`ListView`, `CustomScrollView`, `Column`, etc.) must remain pixel-for-pixel identical after removing the custom header row.

### Design token for back-arrow color
Use `OmniTheme.textPrimary` for the `IconButton.color`. This is consistent with the explicit usages in `WorkoutSessionListView._buildHeader()` and `RoutineSetupScreen._buildHeader()`.

---

## Progress

- [x] Create `lib/widgets/layout/omni_back_header.dart`
- [x] Update `CalendarScreen`
- [x] Update `DaySessionListScreen`
- [x] Update `ExerciseEditorScreen`
- [x] Update `CreatePeriodScreen`
- [x] Update `PeriodListScreen`
- [x] Update `ProfileScreen`
- [x] Update `MyRoutinesScreen`
- [x] Migrate `RoutineSetupScreen` (both `_buildListView` and `_buildDetailView`)
- [x] Update `SettingsScreen`
- [x] Update `StatsScreen`
- [x] Update `SessionOverviewScreen`
- [x] Migrate `SessionSummaryScreen` (custom Row → `appBar: OmniBackHeader`)
- [x] Update `test/screen_widget_test.dart` with header assertions
- [x] Write `test/header_standardization_test.dart`
- [x] Run all tests and confirm no regressions — **974 tests passed, 0 failed**

## Phase Status: Complete

