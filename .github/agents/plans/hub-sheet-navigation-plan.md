# Feature: hub-sheet-navigation

## Overview

The Hub sheet (`lib/widgets/hub/hub_sheet.dart`) opens its five destination
screens through direct `Navigator.of(context).push(MaterialPageRoute(...))`
calls, bypassing the app's standard `OmniNavigator` → `OmniRoute` path.
Because `MaterialPageRoute` is `opaque == false` by default and every
`Scaffold` in the app is transparent, the outgoing Hub sheet stays painted
throughout the slide transition and snaps out when the compositor finally
culls it — the same brief "two screens overlapping" flash being fixed for
the nutrition Add Food flow. This iteration migrates the Hub sheet's five
internal navigation calls to `OmniNavigator.push` so each destination is
wrapped in the standard `OmniRoute` (opaque + `OmniGradientBackground`) and
transitions identically to every other screen push in the app. The Hub
sheet's layout, the five destinations it offers, and how it is opened/
dismissed are unchanged.

> TRIVIAL feature: no schema change, no new state, no new user-facing
> behavior. Single lean `## Iteration 1` block; no scenario Q&A beyond the
> one block below.

## Requirements

- `lib/widgets/hub/hub_sheet.dart` no longer imports `package:flutter/material.dart`'s `MaterialPageRoute` (or any other raw route type) for screen pushes.
- All five destinations (`Calendar`, `Stats`, `Nutrition`, `Profile`, `Settings`) push through `OmniNavigator.push(context, (_) => …Screen(...))`.
- The pushed route is the standard `OmniRoute<T>` for each destination — not `MaterialPageRoute`.
- The Hub sheet's layout, its `MaintenanceTile` grid, the set of five destinations, the active-theme constant, and the `_HubItem` wrapper remain unchanged.
- No new repository / state / model changes. Pure navigation routing migration.

## Acceptance Criteria

- [ ] `grep -n 'MaterialPageRoute\|PageRouteBuilder' lib/widgets/hub/hub_sheet.dart` returns zero matches.
- [ ] `grep -n 'OmniNavigator' lib/widgets/hub/hub_sheet.dart` shows five `push` calls (one per destination).
- [ ] New widget test in `test/hub_interaction_test.dart` taps each of the five destinations inside the open Hub sheet and asserts the pushed route runtime type is `OmniRoute<dynamic>` (or the typed variant) — never `MaterialPageRoute`.
- [ ] All previously passing Hub-related tests (`test/home_logo_hub_open_test.dart`) continue to pass without modification.
- [ ] `flutter analyze lib/widgets/hub/` reports no errors.

## Scenarios

### S-001: HubSheet destinations push via OmniRoute
- Trigger: Hub sheet is open with all five destination tiles visible.
- Precondition: `HubSheet` rendered inside a `Navigator` equipped with a
  `NavigatorObserver` that captures pushed routes; test state wired with
  `MockWorkoutRepository`, `SettingsState` (mock prefs), and the five
  required services / states (`CalendarState`, `PeriodState`, `WorkoutState`,
  `RoutineState`, `NutritionState`, `FoodLibraryState`, `ProfileState`,
  `TimerAlertService`, `RestNotificationService`,
  `RoutineSessionService`, `SessionSummaryService`).
- Flow:
  1. Render `HubSheet` inside a `MaterialApp` with a capturing `NavigatorObserver`.
  2. Tap each of the five tiles in turn (`Calendar`, `Stats`, `Nutrition`,
     `Profile`, `Settings`).
  3. After each tap, `pumpAndSettle()` and inspect the observer's
     captured `pushedRoute` for the last push.
- Expected outcome: For every destination, the captured pushed route is
  `OmniRoute<dynamic>` (or its typed variant). None are
  `MaterialPageRoute<dynamic>`.
- Edge case of: none.

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes

#### File 1: `lib/widgets/hub/hub_sheet.dart`
- Add `import '../../core/navigation/navigation.dart';` (already exports
  `OmniNavigator`).
- Replace each `Navigator.of(context).push(MaterialPageRoute(builder: (context) => …Screen(...)))` with `OmniNavigator.push(context, (_) => …Screen(...))`. There are exactly five of these — one each for `CalendarScreen`, `StatsScreen`, `NutritionScreen`, `ProfileScreen`, `SettingsScreen`.
- Remove the `MaterialPageRoute` usages entirely. Do not import
  `package:flutter/material.dart`'s `MaterialPageRoute` (it is not
  re-exported by the nav barrel, and Flutter's analyzer will catch any
  leftover symbol reference).
- Keep the existing `final maintenanceItems = [...]` list, the
  `MaintenanceTile` invocations, the `_HubItem` class, the
  `Container` + `ListView` chrome, and the `AppTheme.abyssalNeon`
  active-theme constant exactly as written.

#### File 2: `test/hub_interaction_test.dart`
- Add a new `group('HubSheet destination navigation', ...)` with one
  test that exercises S-001. The test must:
  1. Build a `MockWorkoutRepository`, run `await repository.initialize()`,
     then construct the eleven required state / service dependencies
     exactly the way `test/hub_interaction_test.dart`'s `setUp` already
     does (the helper already builds them — reuse it).
  2. Install a `NavigatorObserver` subclass (e.g. `_RouteCaptureObserver`)
     into the `MaterialApp(navigatorObservers: [...])`.
  3. Render `HubSheet` directly inside the `MaterialApp`'s `home` (or
     behind a `Builder`), `pumpAndSettle()`, then `find.byType(MaintenanceTile)`
     and tap each tile by its known title (`Calendar`, `Stats`, `Nutrition`,
     `Profile`, `Settings`).
  4. After each tap, `await tester.pumpAndSettle()` and assert the
     observer's most recent `pushedRoute.runtimeType` is `OmniRoute`
     (typed as `Route<dynamic>` — assert by `runtimeType.toString()` or
     by `is OmniRoute`).
  5. After all five taps, assert none of the captured routes is a
     `MaterialPageRoute`.
- The pre-existing skipped tests in the file stay as-is.

#### File 3: `.github/agents/docs/route-migration-audit.md`
- Add an "Addendum — Hub sheet navigation alignment" section at the
  bottom (after the Add Food addendum), mirroring its structure:
  - Table row per destination (5 rows total: 32–36) listing the
    pre-alignment line, before, and after.
  - "Why" paragraph explaining the bleed-through in the same words as
    the Add Food addendum.
  - "Test coverage" paragraph noting the new `hub_interaction_test.dart`
    group and the `NavigatorObserver` assertion.
- Update the "Migrated Call Sites" count from 30 to 35 and the totals
  row.
- Update the doc's lead paragraph to note the Hub sheet is now aligned.

#### File 4: `.github/agents/docs/navigation_and_screens.md`
- No content changes required. The navigation contract rule and the
  Hub sheet's destination list are already authoritative.

### Implementation Steps
1. [x] Write the new failing widget test in `test/hub_interaction_test.dart` (S-001).
2. [x] Run `flutter test test/hub_interaction_test.dart` and confirm the new test fails because `MaterialPageRoute` is currently pushed.
3. [x] Migrate `lib/widgets/hub/hub_sheet.dart` to `OmniNavigator.push` for all five destinations.
4. [x] Run `flutter test test/hub_interaction_test.dart` again and confirm the new test passes.
5. [x] Run `flutter test test/home_logo_hub_open_test.dart` — must remain green.
6. [x] Run `flutter analyze lib/widgets/hub/` — zero errors.
7. [x] Update `.github/agents/docs/route-migration-audit.md` addendum and totals.
8. [x] Mark `### Phase 0/1/2/3 Complete ✓` in this plan file as each phase lands.

## Progress
- [x] Phase 0 Complete ✓
- [x] Phase 1 Complete ✓ (skipped — pure UI migration)
- [x] Phase 2 Complete ✓
- [x] Phase 3 Complete ✓

### Phase 3 Complete ✓

Layers in scope: widgets (`lib/widgets/hub/hub_sheet.dart`), tests (`test/hub_interaction_test.dart`), docs (`.github/agents/docs/route-migration-audit.md`).
Layers skipped: models, repositories, state, features, core (none touched).

PASS (5 rules): env-agnostic (no `dart:io` / `Platform.is*` introduced); centralized navigation contract (5/5 HubSheet destinations now `OmniNavigator.push` → `OmniRoute`); repository-interface-only (state unchanged, no concrete repo touched); immutable models (none changed); no new business logic in widgets (HubSheet stays presentation-only).
N/A (3 rules): unit tokens (no new user-facing values with units); card chrome / `OmniSurface` / `OmniCardHeader` (no card chrome touched); effort-kind / timestamp rules (no new analytics).
FAIL: none.

Critical: 0 | Warnings: 0 | Suggestions: 0

Migration summary: 35 total `Navigator.*` calls now aligned across `lib/features/` and `lib/widgets/` (audit addendum updated); zero raw `MaterialPageRoute` / `PageRouteBuilder` outside `lib/core/navigation/`. Hub sheet layout, destinations, open/dismiss behavior unchanged.

## Feedback
(none)
