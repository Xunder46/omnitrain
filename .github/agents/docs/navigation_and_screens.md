# Navigation & Screen Map

## Navigation Contract

> **Rule**: All screen-level navigation goes through `OmniNavigator`. `OmniRoute` and `OmniFadeRoute` are the only route types used for screen pushes. Any `MaterialPageRoute` or `PageRouteBuilder` outside `lib/core/navigation/` is a **code-review blocker**.

### Architecture

```
OmniNavigator.push / pushReplacement / pushReplacementFade
    └── OmniRoute<T> / OmniFadeRoute<T>
            └── OmniGradientBackground  ← wraps every pushed page
                    └── Screen widget
```

The app-level `OmniGradientBackground` (in `app.dart` `builder:`) covers static areas (status bar, overscroll, sheet gaps). Each `OmniRoute` also wraps its page in `OmniGradientBackground` and sets `opaque = true`, ensuring the incoming route fully occludes the outgoing one at every animation frame and eliminating transition bleed-through.

### When to use each method

| Method | Use case |
|---|---|
| `OmniNavigator.push(context, (_) => Screen(...))` | Standard forward navigation |
| `OmniNavigator.pushReplacement(context, (_) => Screen(...))` | Replace current route (e.g. session → summary) |
| `OmniNavigator.pushReplacementFade(context, (_) => Screen(...))` | Fade-replace (splash → home) |
| `OmniNavigator.popUntil(context, predicate)` | Pop multiple routes (e.g. back to root) |

See `docs/navigation_contract.md` for the full rationale.

---

## Overview

OmniTrain uses **imperative navigation** via `OmniNavigator` (wrapping Flutter's `Navigator.push` / `Navigator.pop`). There is no named-route system or declarative router (no GoRouter, no AutoRoute). All dependencies are passed via constructor injection — no Provider, Riverpod, or Bloc.

---

## App Entry Point

**File**: `lib/main.dart`

```
main()
  → _createRepository() → HiveWorkoutRepository
  → repository.initialize()
  → Creates: WorkoutState, HomeState, RoutineState, CalendarState, PeriodState, ProfileState, SettingsState, TimerAlertService, RestNotificationService, RoutineSessionService, SessionSummaryService
  → runApp(MyApp(...))   // All dependencies injected via constructor
```

**File**: `lib/app.dart`

`MyApp` is a `StatelessWidget` that:
- Builds the theme via `buildTheme()`
- Sets `MaterialApp.home` based on the `showOnboarding` flag (read from SQLite preference `onboarding_complete` in `main.dart`):
  - Fresh install (`onboarding_complete` absent or `false`) → `OnboardingScreen`
  - Returning user (`onboarding_complete = true`) → `HomeScreen`
- Passes all dependencies via constructor

```
main.dart → (fresh install, onboarding_complete absent/false) → OnboardingScreen → [Get Started] → HomeScreen
main.dart → (returning user, onboarding_complete = true)       → HomeScreen
```

---

## Complete Screen Flow

```
HomeScreen
  │
  ├── Modality Tile (1 of 5) ──→ SessionOverviewScreen (creates session)
  │                                  │
  │                                  ├── Add Exercise → ExercisePickerScreen (page push)
  │                                  │                    └── [ModalityPickerDialog] (if null modality: pick modality or General)
  │                                  │                         └── [MetricChooserDialog] (if General picked)
  │                                  │                         └── → WorkoutSessionScreen (auto-navigate, focused on new exercise)
  │                                  │
  │                                  └── Start Workout → WorkoutSessionScreen
  │                                                        │
  │                                                        ├── finish → **pushReplacement** → SessionSummaryScreen
  │                                                        │   (back after finish pops to caller; cannot resume active session)
  │                                                        │                       │
  │                                                        ├── back → SessionSummaryScreen
  │                                                        │                       │
  │                                                        │                       ├── Edit Session → SessionOverviewScreen (push)
  │                                                        │                       ├── Save as Routine → bottom sheet
  │                                                        │                       ├── Discard → popUntil(isFirst)
  │                                                        │                       └── Done → popUntil(isFirst)
  │                                                        │
  │                                                        └── Add Exercise → ExercisePickerScreen (page push)
  │                                                              └── [ModalityPickerDialog] (if null modality: pick modality or General)
  │                                                                    └── [MetricChooserDialog] (if General picked)
  │                                                              └── [ExerciseEditorScreen] (create custom)
  │
  ├── My Routines Tile ──→ (if routine session active) → WorkoutSessionScreen
  │                     ──→ (else) → MyRoutinesScreen
  │                                    │
  │                                    ├── Tap routine card → start session → WorkoutSessionScreen
  │                                    ├── FAB (+) → RoutineSetupScreen (new)
  │                                    └── ⋮ menu → Edit → RoutineSetupScreen (existing)
  │                                               → Delete → confirmation dialog
  │
  ├── Free Training Tile ──→ Free Training start sheet
  │                            ├── Rolling Session toggle
  │                            └── Start Session ──→ WorkoutSessionScreen (modality = null)
  │                                                  └── Empty finish discards the session and returns to HomeScreen
  │
  ├── Nutrition Strip (footer) ──→ NutritionScreen
  │                                   ├── ring-card edit icon → NutritionTargetScreen
  │                                   └── Food Library card pencil icon → AddFoodScreen
  │                                                                     │
  │                                                                     ├── Library tab row tap → EditFoodScreen
  │                                                                     └── + New Item tab → creates a new catalog food
  │
    └── Hub (via logo tap)
      ├── Calendar ──→ CalendarScreen
      ├── Profile ──→ ProfileScreen
      ├── Stats ──→ StatsScreen
      ├── Nutrition ──→ NutritionScreen
      │                   ├── ring-card edit icon → NutritionTargetScreen
      │                   └── Food Library card pencil icon → AddFoodScreen
      │                                                                     │
      │                                                                     ├── Library tab row tap → EditFoodScreen
      │                                                                     └── + New Item tab → creates a new catalog food
      └── Settings ──→ SettingsScreen
```

Both entry points (home strip, hub) land on `NutritionScreen` (daily summary)
first; the small edit icon on the `CalorieRingCard` at the top of the
screen pushes `NutritionTargetScreen`. The legacy bottom "Edit Targets"
button is gone. The legacy placeholder no longer exists.

Day rollover:
- `HomeScreen` calls `NutritionState.rolloverToDate(todayMs)` from
  `addPostFrameCallback` whenever `_lastSeenDate` differs from today.
- This re-loads today's target (walking back to the most recent ancestor
  if no entry exists for the new day) so the user always sees the current
  day's target after midnight.

---

## Screen Inventory

| Screen | File | Purpose |
|--------|------|---------|
| `HomeScreen` | `lib/features/home/home_screen.dart` | 2×3 tile grid + maintenance sheet. Hosts the **NutritionSummaryCard** gauge card (Iteration 5 / S-100..S-106 — supersedes the Phase 4.1 D-8 `NutritionStripBar`) below the tile grid with top gap = 2 × `standardGridSpacing`; the card is INSET from the screen edges (16 px horizontal padding, matching the tile grid's side margin) — NOT a full-bleed rectangle. The card chrome matches the training-tile visual family: rounded corners, hairline border, soft shadow lift. The card is always tappable → `NutritionScreen` (the entire card body is one tap target, not just the chevron). On `initState` the home screen loads today's target + consumed foods (`Future.microtask` deferred so the notify-during-build race is avoided) and runs a one-shot `_checkAndHandleDateRollover` that calls `NutritionState.rolloverToDate(todayMs)` when the date has changed. The card rebuilds live on every `nutritionState` notify (a log/unlog on `NutritionScreen` propagates back to the card via the shared `NutritionState`). The previous Phase 4 D-5 two-row layout (label row + 14-px-tall segmented pill) and the Phase 4.1 D-8 `NutritionStripBar` (full-height bottom strip with chevron-shaped fill, in-segment "%" labels, and label row) were replaced in Iteration 5 with a self-contained gauge card. The new `NutritionSummaryCard` widget is a pure, math-free widget that renders three regions top-to-bottom: (1) a headline row with the calorie figure `"{consumed} / {target} Cal"` (comma-grouped thousands) as the LARGEST, BRIGHTEST text on the card, plus a chevron-right navigation cue at the right edge; (2) a horizontal gauge with a `track` (full-width `divider`-colored pill) and a `fill` (`clamp(consumed / target, 0, 1) × trackWidth`) subdivided P → C → F by each macro's share of CONSUMED calories (S-103); (3) a caption row with three `(colorMarker, "M N%")` entries for protein, carbs, fat. The fill clamps to 100% of the track width when consumed exceeds the goal (S-105), the headline text switches to the theme's `colorScheme.error` warning tone in that case, and the caption row renders DASHES (`—`) — not `0%` — when nothing is logged (S-104). The card uses the new `OmniTheme.colors.stripMacros` muted palette (terracotta / steel-blue / amber) so it reads as a lit panel, not a status light. See [the widget catalog](widget_catalog.md#nutritionsummarycard) for the full prop table and behavior contract. |
| `NutritionScreen` | `lib/features/nutrition/nutrition_screen.dart` | Daily nutrition summary (D-1 / S-042). The top of the page is a `CalorieRingCard` (D-7 / S-043) showing consumed calories vs the daily target (or consumed-only when no target is set); the card header hosts the **Today** title, a sodium daily-total chip (`Na N mg`, key `nutrition_sodium_total`) computed from `NutritionState.todayConsumedSodium` (D-7 freeze — null source sodium is treated as 0), and a small edit-targets icon (key `edit_targets_icon`) that pushes `NutritionTargetScreen`. The bottom row of the same card hosts the **`WaterTrackerControl`** (key `water_tracker_control`) — a tap-only +/− stepper with a glass icon + `250 ml` annotation + glass count (key `water_tracker_count`) + plus / minus buttons (`water_tracker_plus` / `water_tracker_minus`); the control mirrors the sodium chip on the left and reads from `NutritionState.waterTodayGlasses` / `.waterTodayMl` (stored as milliliters at `kWaterGlassMl = 250` per glass; the count is derived at the display boundary). The donut chart keeps its four sections (D-4) — Protein / Net Carbs / Fiber / Fat — and tapping a section focuses it. The focus view shows `Macro · X g · Y% of consumed calories` in the ring's center (S-041): percent is the section's calorie contribution per D-4 (protein×4, netCarbs×4, fat×9), and Fiber is informational (`g`) since it contributes zero calories. There is no `of target` text anywhere in the focus view. Below the ring, the screen shows the scrollable, grouped **Foods I Eat** browse card (D-1 / Phase 2): rows are bucketed by `groupId` resolved through `FoodLibraryState`'s group cache, sections sorted by FoodGroup name (alpha, case-insensitive) with `Ungrouped` last, and each row is a `LogFoodRow` (see widget catalog) whose checkbox toggles the food in/out of today's log via `NutritionState.logConsumedFoodAt` (which freezes the food's sodium onto the snapshot per D-7). The **Foods I Eat** `Card` header hosts a pencil `IconButton` (key `food_library_manage_pencil`) that opens `AddFoodScreen`. On `initState` the screen loads today's target, today's consumed foods, today's water volume, and the food library in parallel (each is fired and not awaited so the others are not gated on it); the same four loads are re-fired on return from `NutritionTargetScreen`. The water load keeps the calorie-ring card's tracker in sync with the persisted day-log volume — the same immediate-persistence contract the consumed foods follow. |
| `AddFoodScreen` | `lib/features/nutrition/add_food_screen.dart` | Three-tab flow for managing the **global managed library** (the catalog) and the user's **My Foods** collection. **Library** (default) — bundles a search `TextField` (key `catalog_search_field`) over the alphabetical catalog list; each row has a 40×40 image thumbnail on the left (key `food_catalog_thumb_<id>`, always present — placeholder when no image), the food name + per-reference macros in the middle, and a state-dependent trailing action on the right — a primary "Add" `FilledButton` when the catalog food is NOT in the user's personal library, a 40×40 red `theme.colorScheme.error` square `FilledButton` with a white `Icons.delete_outline` (no text label) when it IS. Tapping either action stays on the screen (multi-add / multi-remove in a single visit); remove also calls `NutritionState.unlogFoodToday` first if the food is in today's consumed log. Tapping the row surface (outside the trailing Add / Remove button) opens `EditFoodScreen` for the catalog food. **My Foods** (D-2 / S-031) — lists every user-created catalog food (`FoodLibraryState.userCreatedCatalogFoods`) plus any legacy library-only customs (`isCatalog == false`, pre-D-2 rows) so they remain manageable until the user deletes them. The tab does NOT show bundled (default) catalog foods. Each row has a 40×40 thumbnail (key `food_user_thumb_<id>`), name + macros, and a 40×40 red trash `FilledButton` (key `delete_user_food_<id>`). Row tap opens `EditFoodScreen` for the user-created catalog food, or a legacy-library shim that routes to `updateCustomFood` for pre-D-2 rows. Delete (D-2 / S-032 / S-033) order: `unlogFoodToday(libraryId)` if logged → `removeFood(libraryId)` (matched by identity via `libraryIdFor`) → `deleteCatalogFood(id)`. Bundled catalog foods cannot be hard-deleted (`isBundledCatalogFood` guard). **+ New Item** — a form (image, name, category, unit type, reference, per-reference macros including **Fiber** and **Sodium** as optional fields) that creates a new food in the **catalog** (D-2 / S-030): on save, the draft is written to the catalog via `FoodLibraryState.createCatalogFood` and then immediately copied into the user's personal library via `FoodLibraryState.addCatalogFoodToLibrary`. If the catalog write fails, the form stays open and a snackbar reports the error. If the library-add fails, the catalog row is preserved (the user can re-add from My Foods) and a snackbar surfaces the error; the form still pops. Past `ConsumedFood` snapshots remain byte-identical (the snapshot model freezes name, macros, and reference at log time). Save pops back to the nutrition page. The image picker at the top of the form mirrors the avatar flow on `ProfileScreen` (camera + gallery, no-op on web). **Categories** — manage the food groups that organize the library; each row has an inline `TextField` (key `category_name_<id>`) for renaming on `onEditingComplete` / `onSubmitted` and a trash `IconButton` (key `category_delete_<id>`) on the right. Deleting a non-empty group opens a confirmation dialog with a destination dropdown (Ungrouped + every other active group, Ungrouped default); on confirm the group's foods are reassigned and the group is archived via `deleteFoodGroupReassigningFoods`. Deleting an empty group is silent (no confirmation). A "+ New Category" `OutlinedButton.icon` (key `new_category_button`) at the bottom creates a new group with the default name. The synthetic "Ungrouped" row at the bottom of the list is informational (food count) and cannot be renamed or deleted. |
| `EditFoodScreen` | `lib/features/nutrition/edit_food_screen.dart` | Edit a single **catalog** food. Opened from a row tap in the **Library** tab of `AddFoodScreen`. Hosts the shared `FoodForm` widget (see widget catalog) pre-populated with the food's name, group, unit type, reference, macros, image, and notes. Save delegates to `FoodLibraryState.updateCatalogFood` and pops on success. The catalog is the **global managed library** (the row's `isCatalog == true`); edits propagate to the personal library (which points back to the catalog row by identity for logging). Past `ConsumedFood` snapshots are unaffected (the snapshot model freezes name, macros, and reference at log time and does not include the image). |
| `NutritionTargetScreen` | `lib/features/nutrition/nutrition_target_screen.dart` | Set today's **calorie** target (D-3 / S-040). The form is a single `TextFormField` (key `calories_field`) — the previous four-field form (calories + protein + carbs + fat) and the live `implied_calories_readout` helper have been removed. The screen title is `Daily Calorie Target`. Pre-fills from `NutritionState.getTodayTarget()` (calories value, treated as `null` when 0 or negative). Save builds a macros-0 `NutritionTarget(calories: x, protein: 0, carbs: 0, fat: 0)` and persists via `NutritionState.saveNutritionTarget` (→ `saveNutritionTargetForDate` with forward-propagation). The persisted `NutritionTarget` keeps its protein/carbs/fat fields for schema/back-compat but they are 0 going forward. |
| `SessionOverviewScreen` | `lib/features/session/session_overview_screen.dart` | Exercise list for current session, add/remove exercises |
| `WorkoutSessionScreen` | `lib/features/session/workout_session_screen.dart` | Core workout tracking (list view + detail view). Split into 4 Dart `part` files: main coordinator, `workout_session_timer_mixin.dart` (timer state/logic), `workout_session_list_view.dart` (list-view builders), `workout_session_detail_view.dart` (detail-view builders). Detail view uses an inline set-progress row (`remove · label · add`) plus a back / start-or-log / forward action row. The remove button shows a minus icon (`Icons.remove`) when multiple sets exist; when only **one set remains** it swaps to a trash-can icon (`Icons.delete_outline`, same colour) and its tooltip changes to "Remove exercise" — confirming will remove the entire exercise from the session. Timer control lives on the timer display itself, and the session clock stays at `00:00` until the first exercise is added. |
| `SessionSummaryScreen` | `lib/features/session/session_summary_screen.dart` | Post-workout summary, PRs, save-as-routine. Also reused for **historical** sessions reached from the calendar (tap a past day with one entry → `SessionSummaryScreen`). Accepts an optional `openedFromCalendar: true` + `originatingCalendarState` to differentiate the two flows: when set, the embedded calendar card renders the **historical session's month** (not today), the "Open Calendar" button **pops back** instead of pushing a fresh `CalendarScreen`, and "Discard" deletes the historical record and returns to the originating calendar / day list. When omitted (post-workout flow), the calendar card renders the current month, "Open Calendar" pushes a fresh calendar, and "Discard" returns to the home hub via `popUntil(isFirst)`. |
| `MyRoutinesScreen` | `lib/features/routine/my_routines_screen.dart` | List of saved routines |
| `RoutineSetupScreen` | `lib/features/routine/routine_setup_screen.dart` | Create/edit routines (dual view) |
| `ExerciseEditorScreen` | `lib/features/exercise/exercise_editor_screen.dart` | Create/edit custom exercises with modality-aware capability/discipline filtering; accepts optional `contextModality` for session-prefill |
| `ExercisePickerScreen` | `lib/features/exercise/exercise_picker_screen.dart` | Full-screen exercise search and selection with modality ranking, discipline/muscle filters, and inline "New Exercise" creation; opened via `OmniNavigator.push<Exercise>`; returns selected `Exercise` on pop |
| `ProfileScreen` | `lib/features/profile/profile_screen.dart` | Identity, avatar, and body measurement tracking |
| `SettingsScreen` | `lib/features/settings/settings_screen.dart` | Calendar start-of-week, weight/distance units, timer alert preferences, notification-permission row for rest and effort alerts, feeling survey toggle, appearance theme selector, and a low-emphasis version footer |
| `StatsScreen` | `lib/features/stats/stats_screen.dart` | Read-only stats: all-time sessions, total training time, current streak, scrollable Strength e1RM/volume trends and Cardio pace/duration trends selected from a current-state window (active training period or last N training days — see [Stats screen doc](stats_screen.md#selection-window-current-state-window)), all-time Recent PRs, and a full-history scrollable NUTRITION card with Calories / Macros segmented toggle |
| `OnboardingScreen` | `lib/features/onboarding/onboarding_screen.dart` | First-launch 3-page swipeable intro. Page 1: app pitch. Page 2: modality tiles with accent colors and one-liners. Page 3: calendar features + Get Started button. Completion sets `onboarding_complete` preference key via `repository.setPreferenceBool` and calls `pushReplacement` to `HomeScreen`. |
| `OmniSplashScreen` | `lib/features/splash/omni_splash_screen.dart` | Brand splash (currently disabled) |

### Empty / Placeholder Directories
- `lib/features/workout/` — contains only `.gitkeep`. All workout UI lives in `lib/features/session/`.

---

## Dependency Injection Pattern

All state and service objects are created in `main.dart` and passed through the widget tree via constructors. There is no DI framework.

```
main.dart
  → WorkoutState(repository)
  → HomeState(repository)          ← now receives repository for hint persistence
  → RoutineState(repository)
  → CalendarState(repository)
  → PeriodState(repository)
  → ProfileState(repository)
  → SettingsState(repository)     ← persisted app theme + weight/distance unit preferences via repository preferences
  → NutritionState(repository)
  → FoodLibraryState(repository)   ← groups + foods cache, powers the Food Library browse card on `NutritionScreen`
  → TimerAlertService()
  → RestNotificationService()
  → RoutineSessionService(repository)
  → SessionSummaryService(repository)
  → MyApp(..., nutritionState: nutritionState, foodLibraryState: foodLibraryState)
    → HomeScreen(..., nutritionState: nutritionState, foodLibraryState: foodLibraryState)
      → (passes relevant subset to child screens; `NutritionScreen` requires both)
```

### Key Injection Rules
- State classes depend only on `WorkoutRepository` interface (never concrete implementations)
- Services depend only on `WorkoutRepository` interface
- Screens receive state/service objects via constructor parameters
- No global state singletons are used in the active screen graph

---

## Dialog Inventory

| Dialog | File | Purpose |
|--------|------|---------|
| `MetricChooserDialog` | `lib/widgets/pickers/metric_chooser_dialog.dart` | Choose tracking method for an exercise (Free Training / General fallback) |
| `ModalityPickerDialog` | `lib/widgets/pickers/modality_picker_dialog.dart` | Pick a modality for an exercise added to a null-modality session; returns `(bool, String?)` record or `null` (cancelled) |

---

## Active Session Resume Logic

When the user returns to the home screen with an active session:
- **Modality tiles**: If the active session's modality matches the tile, tapping resumes the session (navigates to `WorkoutSessionScreen`)
- **My Routines tile**: If the active session has `intent == 'routine'`, tapping navigates directly to `WorkoutSessionScreen`

Cold-start persistence resume:
- On first frame of `HomeScreen`, when `workoutState.hasActiveSession == false`, state checks storage for in-progress sessions.
- If one exists, an `AlertDialog` titled `Unfinished Session` is shown.
- `Continue` restores the historical session and pushes `WorkoutSessionScreen`.
- `Discard` uses one confirmation tap (`Discard` -> `Confirm Discard`) and deletes by id.
- System back-dismiss returns `null` and preserves the stored session (no delete side effect).
- If multiple dangling sessions exist, only the most recent is surfaced; older ones are cleaned up by state.

When tapping a different modality tile while a session is active:
- A confirmation dialog appears: "Start New Session? Current session will not be saved."
- Confirming ends the current session and creates a new one

---

## Related Documentation

- [App Philosophy](app_philosophy.md) — Home screen tile layout and UX constraints
- [Modality Tracking](modality_tracking.md) — Session creation and modality resolution
- [Session Summary](session_summary.md) — Post-workout summary screen

---

**Document Version**: 1.7
**Last Updated**: June 7, 2026
