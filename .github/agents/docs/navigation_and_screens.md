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
  → _initializeLocalTimezone() (one-shot, outside the retry loop)
  → CrashReportingService.bootstrap(enabled: kReleaseMode, ...)
  → runApp(StartupRoot(startupRunner: _runStartup))
```

Crash reporting is bootstrapped outside the `StartupRoot` retry loop
so a startup retry does not double-install the global error sinks. The
bootstrap itself is idempotent, but installing it before
`StartupRoot` keeps the retry behaviour predictable — a retry
re-runs `_runStartup` from the top without rerunning the bootstrap
(if the user reaches the failure screen, the SDK is already
initialised and primed to capture the next throw).

`StartupRoot` (defined in `lib/app/startup_root.dart`) is the top-level
widget that owns the startup attempt. Lifecycle is modelled as an explicit
`_StartupLifecycle` enum (`preparing` / `succeeded` / `failed`) and `build()`
renders the appropriate surface for each state. The three outcomes are
disjoint — a successful launch never passes through `failed`:

- **Preparing** — the first attempt starts from `initState`. While the runner
  is in flight, the neutral preparation surface
  (`lib/features/startup/startup_preparing_screen.dart`) is mounted. It is a
  single `CircularProgressIndicator` on the gradient background — no brand
  content, no failure copy. A healthy launch MUST NOT render the failure
  screen during this phase.
- **Succeeded** — runner returns a widget → `_runningApp` is set and that
  widget mounts as the running app. Only reachable from `preparing`.
- **Failed** — runner throws → diagnostics run and `StartupFailureScreen` is
  mounted with the Retry control enabled. Only reachable from `preparing`.
- **Retry** — Retry invokes the runner from the top. The lifecycle returns
  to `preparing` first, so the failure screen is replaced by the neutral
  preparation surface during the retry. Success mounts the app; another
  failure re-enters `failed` and re-enables Retry.

The lifecycle model is the PR 2 fix — previously the failure screen was
rendered during `preparing` as well, which caused a flash of failure content
on every healthy launch. See
`.github/agents/plans/2026-07-27-02-pr2-launch-quality-hotfix-plan.md`
scenarios S-001 and S-002 for the contract.

`runStartup` (in `lib/main.dart`) performs the same work the entry
point did previously:

```
_runStartup()
  → PreferencesServiceImpl.init()
  → repository = HiveWorkoutRepository(); await repository.initialize()
  → CatalogRefreshService.refresh()  (failures logged, do not block startup)
  → onboardingComplete = repository.getPreferenceBool('onboarding_complete')
  → ImageStorageService.create() on native (skipped on web)
  → Creates: WorkoutState, HomeState, RoutineState, CalendarState, PeriodState,
             ProfileState, SettingsState, NutritionState, FoodLibraryState,
             NutritionPrimerState, TimerAlertService, RestNotificationService,
             RoutineSessionService, SessionSummaryService
  → reads PackageInfo (fallback "0.0.0+0" on plugin failure)
  → returns MyApp(... all dependencies injected via constructor ...)
```
> Note: `CrashReportingService.bootstrap` is intentionally **not** part of
> `_runStartup`. It runs before `runApp` (in `main()` itself) and is
> idempotent — the retry loop in `StartupRoot` re-runs `_runStartup`
> without re-installing the global error sinks.
**File**: `lib/app.dart`

`MyApp` is a `StatelessWidget` that:
- Builds the theme via `buildTheme()`
- Sets `MaterialApp.home` based on the `showOnboarding` flag (read through the Hive-backed repository preference `onboarding_complete` in `_runStartup`):
  - Fresh install (`onboarding_complete` absent or `false`) → `OnboardingScreen`
  - Returning user (`onboarding_complete = true`) → `HomeScreen`
- Passes all dependencies via constructor

```
StartupRoot → (fresh install, onboarding_complete absent/false) → OnboardingScreen → [Get Started] → HomeScreen
StartupRoot → (returning user, onboarding_complete = true)       → HomeScreen
StartupRoot → (startup failure)                                  → StartupFailureScreen → [Retry] → re-runs _runStartup
```

---

## Complete Screen Flow

```
HomeScreen
  │
  ├── Modality Tile (Cardio / Resistance / Sports / Isometric)
  │      → creates session → WorkoutSessionScreen
  │            ├── first empty load schedules ExercisePickerScreen automatically
  │            │     └── selected exercise returns to focused detail view
  │            ├── Add Exercise → ExercisePickerScreen (page push)
  │            │     └── [ModalityPickerDialog] (null modality only)
  │            │           └── [MetricChooserDialog] (General only)
  │            ├── Add Block → creates a session block in place
  │            ├── finish → **pushReplacement** → SessionSummaryScreen
  │            │     ├── Edit Session → SessionOverviewScreen (push)
  │            │     ├── Save as Routine → bottom sheet
  │            │     ├── Open Calendar → CalendarScreen (push)
  │            │     ├── Discard → popUntil(isFirst)
  │            │     └── Done → popUntil(isFirst)
  │            └── back → SessionSummaryScreen
  │
  ├── My Routines Tile ──→ (if routine session active) → WorkoutSessionScreen
  │                     ──→ (else) → MyRoutinesScreen
  │                                    │
  │                                    ├── Tap routine card → start session → WorkoutSessionScreen
  │                                    ├── FAB (+) → RoutineSetupScreen (new)
  │                                    └── ⋮ menu → Edit → RoutineSetupScreen (existing)
  │                                               → Delete → confirmation dialog
  │                                                  │
  │                                    RoutineSetupScreen
  │                                      └── Add Exercise → ExercisePickerScreen (page push)
  │
  ├── Free Training Tile ──→ Free Training start sheet
  │                            ├── Rolling Session toggle
  │                            └── Start Session ──→ WorkoutSessionScreen
  │                                  ├── empty first load auto-opens ExercisePickerScreen
  │                                  └── empty finish discards the session and returns to HomeScreen
  │
  ├── NutritionSummaryCard (below the tile grid) ──→ NutritionScreen
  │      (first-ever tap shows NutritionPrimerSheet, then pushes)
  │                                   ├── ring-card edit icon → NutritionTargetScreen
  │                                   └── Food Library card pencil icon → AddFoodScreen
  │                                                                     │
  │                                                                     ├── Library tab row tap → EditFoodScreen
  │                                                                     └── + New Item tab → creates a new catalog food
  │
    └── Maintenance sheet (drag up, or tap the logo)
      ├── Calendar ──→ CalendarScreen
      │                   ├── tap a day with 1 session → SessionSummaryScreen
      │                   │                                (openedFromCalendar: true)
      │                   ├── tap a day with >1 session → DaySessionListScreen
      │                   │                                 ├── tap completed → SessionSummaryScreen
      │                   │                                 └── continue → WorkoutSessionScreen
      │                   └── periods entry ──→ PeriodListScreen
      │                                           ├── FAB (+) → CreatePeriodScreen (new)
      │                                           └── tap a period → CreatePeriodScreen (edit)
      ├── Stats ──→ StatsScreen
      ├── Profile ──→ ProfileScreen
      │                   └── avatar tap → AvatarCropSheet (pushed as a route)
      └── Settings ──→ SettingsScreen
```

<a id="hub-discrepancy"></a>

> ### ⚠️ Unresolved: two hub implementations
>
> **Flagged 2026-07-26 (docs audit). Not resolved — do not "fix" either side
> without a product decision.**
>
> There are two maintenance-sheet implementations in the tree, and they do not
> agree:
>
> | | Items | Order | Wired up? |
> |---|---|---|---|
> | `_buildMaintenanceGrid` in `lib/features/home/home_screen.dart` | **4** | Calendar, Stats, Profile, Settings | **Yes** — this is what renders |
> | `HubSheet` in `lib/widgets/hub/hub_sheet.dart` | **5** | Calendar, Stats, Nutrition, Profile, Settings | **No** — never instantiated |
>
> `HubSheet` is fully built and unit-tested (`test/hub_interaction_test.dart`
> asserts all five destinations route through `OmniNavigator`), but grepping
> `lib/` for `HubSheet(` finds only its own constructor. `HomeScreen` renders
> `_buildMaintenanceGrid`; `_openHubSheet` merely snaps the existing
> `DraggableScrollableSheet` open.
>
> Consequences for anyone reading this doc:
> - The sheet a user actually sees has **no Nutrition entry**. Nutrition is
>   reached from the `NutritionSummaryCard` below the tile grid.
> - The item order above is the shipped order, taken from
>   `_buildMaintenanceGrid`. The previous version of this document listed the
>   `HubSheet` order (Calendar, Profile, Stats, Nutrition, Settings), which
>   matched neither implementation.
> - A passing `hub_interaction_test.dart` does **not** mean the hub works in
>   the app; the test renders `HubSheet` directly.
>
> Which side is correct is a product question this audit cannot answer: either
> `HubSheet` was meant to replace the inline grid and the wiring was missed, or
> it was abandoned and should be deleted along with its test. Resolve before
> relying on either as the hub contract.

Nutrition is entered from the `NutritionSummaryCard` on the home screen, which
lands on `NutritionScreen` (daily summary); the small edit icon on the
`CalorieRingCard` at the top of that screen pushes `NutritionTargetScreen`. The
legacy bottom "Edit Targets" button is gone. The legacy placeholder no longer
exists.

> **Corrected 2026-07-26 (docs audit).** This paragraph read "Both entry points
> (home strip, hub) land on `NutritionScreen`". There is only **one** shipped
> entry point — the home card. The hub route exists solely on the unwired
> `HubSheet`; see the flag above.

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
| `NutritionScreen` | `lib/features/nutrition/nutrition_screen.dart` | Daily nutrition summary (D-1 / S-042). The top of the page is a `CalorieRingCard` (D-7 / S-043) showing consumed calories vs the daily target (or consumed-only when no target is set); the card header hosts the **Today** title, a sodium daily-total chip (`Na N mg`, key `nutrition_sodium_total`) computed from `NutritionState.todayConsumedSodium` (D-7 freeze — null source sodium is treated as 0), and a labelled `OutlinedButton.icon` (key `nutrition_target_button`, PR 3 / S-002) whose text reflects the saved-target state — "Set target" when no target is saved, "Change target" when one is — that pushes `NutritionTargetScreen`. The bottom row of the same card hosts the **`WaterTrackerControl`** (key `water_tracker_control`) — a tap-only +/− stepper with a glass icon + `250 ml` annotation + glass count (key `water_tracker_count`) + plus / minus buttons (`water_tracker_plus` / `water_tracker_minus`); the control mirrors the sodium chip on the left and reads from `NutritionState.waterTodayGlasses` / `.waterTodayMl` (stored as milliliters at `kWaterGlassMl = 250` per glass; the count is derived at the display boundary). The donut chart keeps its four sections (D-4) — Protein / Net Carbs / Fiber / Fat — and tapping a section focuses it. The focus view shows `Macro · X g · Y% of consumed calories` in the ring's center (S-041): percent is the section's calorie contribution per D-4 (protein×4, netCarbs×4, fat×9), and Fiber is informational (`g`) since it contributes zero calories. There is no `of target` text anywhere in the focus view. Below the ring, the screen shows the scrollable, grouped **Foods I Eat** browse card (D-1 / Phase 2): rows are bucketed by `groupId` resolved through `FoodLibraryState`'s group cache, sections sorted by FoodGroup name (alpha, case-insensitive) with `Ungrouped` last, and each row is a `LogFoodRow` (see widget catalog) whose checkbox toggles the food in/out of today's log via `NutritionState.logConsumedFoodAt` (which freezes the food's sodium onto the snapshot per D-7). The **Foods I Eat** `Card` header hosts a pencil `IconButton` (key `food_library_manage_pencil`) that opens `AddFoodScreen`. On `initState` the screen loads today's target, today's consumed foods, today's water volume, and the food library in parallel (each is fired and not awaited so the others are not gated on it); the same four loads are re-fired on return from `NutritionTargetScreen`. The water load keeps the calorie-ring card's tracker in sync with the persisted day-log volume — the same immediate-persistence contract the consumed foods follow. |
| `AddFoodScreen` | `lib/features/nutrition/add_food_screen.dart` | Three-tab flow for managing the **global managed library** (the catalog) and the user's **My Foods** collection. **Library** (default) — bundles a search `TextField` (key `catalog_search_field`) over the alphabetical catalog list; each row has a 40×40 image thumbnail on the left (key `food_catalog_thumb_<id>`, always present — placeholder when no image), the food name + per-reference macros in the middle, and a state-dependent trailing action on the right — a primary "Add" `FilledButton` when the catalog food is NOT in the user's personal library, a 40×40 red `theme.colorScheme.error` square `FilledButton` with a white `Icons.delete_outline` (no text label) when it IS. Tapping either action stays on the screen (multi-add / multi-remove in a single visit); remove also calls `NutritionState.unlogFoodToday` first if the food is in today's consumed log. Tapping the row surface (outside the trailing Add / Remove button) opens `EditFoodScreen` for the catalog food. **My Foods** (D-2 / S-031) — lists every user-created catalog food (`FoodLibraryState.userCreatedCatalogFoods`) plus any legacy library-only customs (`isCatalog == false`, pre-D-2 rows) so they remain manageable until the user deletes them. The tab does NOT show bundled (default) catalog foods. Each row has a 40×40 thumbnail (key `food_user_thumb_<id>`), name + macros, and a 40×40 red trash `FilledButton` (key `delete_user_food_<id>`). Row tap opens `EditFoodScreen` for the user-created catalog food, or a legacy-library shim that routes to `updateCustomFood` for pre-D-2 rows. Delete (D-2 / S-032 / S-033) order: `unlogFoodToday(libraryId)` if logged → `removeFood(libraryId)` (matched by identity via `libraryIdFor`) → `deleteCatalogFood(id)`. Bundled catalog foods cannot be hard-deleted (`isBundledCatalogFood` guard). **+ New Item** — a form (image, name, group, unit type, reference, per-reference macros including **Fiber** and **Sodium** as optional fields) that creates a new food in the **catalog** (D-2 / S-030): on save, the draft is written to the catalog via `FoodLibraryState.createCatalogFood` and then immediately copied into the user's personal library via `FoodLibraryState.addCatalogFoodToLibrary`. If the catalog write fails, the form stays open and a snackbar reports the error. If the library-add fails, the catalog row is preserved (the user can re-add from My Foods) and a snackbar surfaces the error; the form still pops. Past `ConsumedFood` snapshots remain byte-identical (the snapshot model freezes name, macros, and reference at log time). Save pops back to the nutrition page. The image picker at the top of the form mirrors the avatar flow on `ProfileScreen` (camera + gallery, no-op on web). **Groups** — manage the food groups that organize the library; each row has an inline `TextField` (key `group_name_<id>`) for renaming on `onEditingComplete` / `onSubmitted` and a trash `IconButton` (key `group_delete_<id>`) on the right. Deleting a non-empty group opens a confirmation dialog with a destination dropdown (Ungrouped + every other active group, Ungrouped default); on confirm the group's foods are reassigned and the group is archived via `deleteFoodGroupReassigningFoods`. Deleting an empty group is silent (no confirmation). A "+ New group" `OutlinedButton.icon` (key `new_group_button`) at the bottom creates a new group with the default name. The synthetic "Ungrouped" row at the bottom of the list is informational (food count) and cannot be renamed or deleted. |
| `EditFoodScreen` | `lib/features/nutrition/edit_food_screen.dart` | Edit a single **catalog** food. Opened from a row tap in the **Library** tab of `AddFoodScreen`. Hosts the shared `FoodForm` widget (see widget catalog) pre-populated with the food's name, group, unit type, reference, macros, image, and notes. Save delegates to `FoodLibraryState.updateCatalogFood` and pops on success. The catalog is the **global managed library** (the row's `isCatalog == true`); edits propagate to the personal library through the durable `catalogId` linkage on each library row (a legacy value-based identity fallback is used only for older library rows that lack `catalogId`, and any legacy row found by identity is upgraded to durable linkage on propagation). Past `ConsumedFood` snapshots are unaffected (the snapshot model freezes name, macros, and reference at log time and does not include the image). |
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
| `StartupFailureScreen` | `lib/features/startup/startup_failure_screen.dart` | End-user startup-failure surface. Shows when `_runStartup` throws inside `StartupRoot`. Plain-language headline ("Something went wrong while starting OmniTrain."), a short secondary line inviting a retry, and a full-width `FilledButton` labeled "Retry" that calls back into `StartupRoot` to re-run the entire startup sequence. No developer terminology is rendered — no "console", "log", "error", or raw exception text. The Retry button is disabled (with `onPressed: null`) while a retry attempt is in flight, to prevent concurrent startups. The screen uses the canonical Abyssal Neon theme tokens via the default failure theme passed in by `StartupRoot`; the user's saved theme is unavailable at this point in the lifecycle because `SettingsState` has not yet been constructed. |

### Calendar & Period Screens

Added 2026-07-26 (docs audit) — these four screens exist and are reachable in
production but had no inventory row. `CalendarScreen` was referenced elsewhere
in this document; the other three were not mentioned anywhere in the docs.

| Screen | File | Purpose |
|--------|------|---------|
| `CalendarScreen` | `lib/features/calendar/calendar_screen.dart` | Month calendar with training-period banding and per-day session markers. Pushed from the home maintenance sheet (Calendar item) and from `SessionSummaryScreen`'s "Open Calendar". Pushes `PeriodListScreen` (periods entry point), `DaySessionListScreen` (tap a day with multiple sessions), and `SessionSummaryScreen` directly (tap a day with exactly one session). See [Calendar & Periods](calendar_periods.md). |
| `DaySessionListScreen` | `lib/features/calendar/day_session_list_screen.dart` | List of the sessions recorded on one calendar day. Pushes `SessionSummaryScreen` for a completed session and `WorkoutSessionScreen` to resume/continue one. |
| `PeriodListScreen` | `lib/features/period/period_list_screen.dart` | Lists training periods with their date ranges. Pushes `CreatePeriodScreen` for both the create and the edit flow. Backed by `PeriodState`. |
| `CreatePeriodScreen` | `lib/features/period/create_period_screen.dart` | Create / edit a training period (name, date range, focus modalities, colour). Validation — including the non-overlap guard — runs through `PeriodState.validate`, which returns field-level `nameError` / `dateError` / `overlapError`. |

### Non-Production Screens

These screen classes exist in `lib/` but are **not reachable from any
production navigation path**. Listed here so the inventory matches the source
tree, and so nobody assumes they are live surfaces.

| Screen | File | Status |
|--------|------|--------|
| `ExerciseDetailScreen` | `lib/features/exercise/exercise_detail_screen.dart` | Thin compatibility wrapper — its `build` returns `WorkoutSessionScreen(initialFocusId: effortId, …)`. Kept so older imports keep compiling. No production call site; exercised only by `test/screen_widget_test.dart`. |
| `MaintenancePlaceholderScreen` | `lib/features/home/maintenance_placeholder_screen.dart` | Dead code. Zero references anywhere in `lib/` or `test/`. Every maintenance-sheet destination is now a real screen, so the placeholder it existed to serve is gone. |

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
  → NutritionPrimerState(repository) ← once-per-install seen flag for the Daily Nutrition primer sheet; persisted via `primer_seen_nutrition`
  → TimerAlertService()
  → RestNotificationService()
  → RoutineSessionService(repository)
  → SessionSummaryService(repository)
  → MyApp(..., nutritionState: nutritionState, foodLibraryState: foodLibraryState, nutritionPrimerState: nutritionPrimerState)
    → HomeScreen(..., nutritionState: nutritionState, foodLibraryState: foodLibraryState, nutritionPrimerState: nutritionPrimerState)
      → (passes relevant subset to child screens; `NutritionScreen` requires nutritionState + foodLibraryState + nutritionPrimerState)
```

The Daily Nutrition primer (see [`widget_catalog/nutrition_widgets.md`](widget_catalog/nutrition_widgets.md) → `NutritionPrimerSheet`) auto-shows on the first-ever tap of the home `NutritionSummaryCard` via a `showModalBottomSheet` over the home screen; dismissal flips `NutritionPrimerState.shouldShowPrimer` to `false` and pushes `NutritionScreen`. The header "?" on `NutritionScreen` reopens the same sheet at any time without mutating the seen state.

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
- A confirmation dialog appears: "Start New Session? Current session will be saved."
- Confirming clears the current in-memory session selection and creates a new session

> **Scheduled, not current:** PR 6 removes the first-load picker auto-open and
> leaves the user on the neutral empty session with equally weighted Add Exercise
> and Add Block choices. Routine-populated sessions continue to bypass the empty
> state.

---

## Related Documentation

- [App Philosophy](app_philosophy.md) — Home screen tile layout and UX constraints
- [Modality Tracking](modality_tracking.md) — Session creation and modality resolution
- [Session Summary](session_summary.md) — Post-workout summary screen

---

**Document Version**: 1.8
**Last Updated**: July 27, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-07-27. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
