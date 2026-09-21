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

## Screen Graph

Which screen reaches which. Behaviour at each edge is verified by the feature tests, not
described here.

```
HomeScreen
  ├── modality tiles / Free Training  → WorkoutSessionScreen → SessionSummaryScreen
  │                                       ├── SessionOverviewScreen  (edit session)
  │                                       └── CalendarScreen
  ├── My Routines tile                → MyRoutinesScreen → RoutineSetupScreen
  │                                       └── ExercisePickerScreen
  ├── NutritionSummaryCard            → NutritionScreen
  │                                       ├── NutritionTargetScreen
  │                                       └── AddFoodScreen → EditFoodScreen
  └── maintenance sheet
        ├── CalendarScreen            → DaySessionListScreen
        │                             → PeriodListScreen → CreatePeriodScreen
        │                             → SessionSummaryScreen
        ├── StatsScreen
        ├── ExerciseLibraryScreen     → ExerciseLibraryDetailScreen
        │                             → ExerciseDetailViewScreen
        ├── ProfileScreen             → AvatarCropSheet
        └── SettingsScreen
```

`ExercisePickerScreen` is pushed from `SessionOverviewScreen`, `WorkoutSessionScreen`,
`RoutineSetupScreen`, and the save-as-routine sheet on `SessionSummaryScreen`; it returns the
selected `Exercise` on pop. `ModalityPickerDialog` and `MetricChooserDialog` are the null-modality
resolution path — see [Modality Tracking](modality_tracking.md).

The maintenance sheet is rendered by `_buildMaintenanceGrid` in
`lib/features/home/home_screen.dart`, which is the only implementation. A second,
never-instantiated `HubSheet` widget was deleted along with its test once it was
confirmed unused. Nutrition is **not** a maintenance-sheet destination — it is
reached from the `NutritionSummaryCard` below the tile grid.

Nutrition is entered from the `NutritionSummaryCard` on the home screen, which
lands on `NutritionScreen` (daily summary); the small edit icon on the
`CalorieRingCard` at the top of that screen pushes `NutritionTargetScreen`. The
legacy bottom "Edit Targets" button is gone. The legacy placeholder no longer
exists.

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
| `HomeScreen` | `lib/features/home/home_screen.dart` | Modality tile grid, the nutrition summary card, the live-session entry point while a watch session is active, and the maintenance sheet. Owns day-rollover for the nutrition target. |
| `NutritionScreen` | `lib/features/nutrition/nutrition_screen.dart` | Daily nutrition summary: calorie ring, macro donut, sodium and water totals, and the grouped "Foods I Eat" browse card. |
| `AddFoodScreen` | `lib/features/nutrition/add_food_screen.dart` | Three-tab management surface for the global food catalog, the user's My Foods collection, and food groups. |
| `EditFoodScreen` | `lib/features/nutrition/edit_food_screen.dart` | Edit a single catalog food. Edits propagate to personal library rows through the durable `catalogId` linkage; past `ConsumedFood` snapshots are unaffected. |
| `NutritionTargetScreen` | `lib/features/nutrition/nutrition_target_screen.dart` | Set today's calorie target. Persists through `NutritionState` with forward-propagation to future dates that still hold the old value. |
| `SessionOverviewScreen` | `lib/features/session/session_overview_screen.dart` | Exercise list for current session, add/remove exercises |
| `LiveSessionScreen` | `lib/features/session/live_session_screen.dart` | The session running on the wrist, managed from the phone. Reads and writes `LiveSessionMirrorState` — there is no second copy of the session here. Reachable from the home panel's live-session entry point (`lib/widgets/session/live_session_entry_point.dart`, shown only while a watch session is active). Renumbering, correction and deletion are the screen's own affordances; adding and swapping route through `ExercisePickerScreen`. Hidden in builds with no watch sync, which pass no `LiveSessionMirrorState`. |
| `WorkoutSessionScreen` | `lib/features/session/workout_session_screen.dart` | Core workout tracking (list view + detail view), split across part files: main coordinator, timer mixin, list-view builders, detail-view builders. Also hosts the session discard action and the rest overlay. |
| `SessionSummaryScreen` | `lib/features/session/session_summary_screen.dart` | Post-workout summary, PRs, save-as-routine. Also reused for **historical** sessions reached from the calendar (tap a past day with one entry → `SessionSummaryScreen`). Accepts an optional `openedFromCalendar: true` + `originatingCalendarState` to differentiate the two flows: when set, the embedded calendar card renders the **historical session's month** (not today), the "Open Calendar" button **pops back** instead of pushing a fresh `CalendarScreen`, and "Discard" deletes the historical record and returns to the originating calendar / day list. When omitted (post-workout flow), the calendar card renders the current month, "Open Calendar" pushes a fresh calendar, and "Discard" returns to the home hub via `popUntil(isFirst)`. |
| `MyRoutinesScreen` | `lib/features/routine/my_routines_screen.dart` | List of saved routines |
| `RoutineSetupScreen` | `lib/features/routine/routine_setup_screen.dart` | Create/edit routines (dual view) |
| `ExerciseEditorScreen` | `lib/features/exercise/exercise_editor_screen.dart` | Create/edit custom exercises with modality-aware capability/discipline filtering; accepts optional `contextModality` for session-prefill |
| `ExercisePickerScreen` | `lib/features/exercise/exercise_picker_screen.dart` | Full-screen exercise search and selection with modality ranking and discipline/muscle filters; opened via `OmniNavigator.push<Exercise>` and returns the selected `Exercise` on pop — or nothing, when given a `liveSession`, in which case it writes into the wrist's session instead. `liveSessionInsertIndex` and `liveSessionSwapSlotId` choose between joining the ladder at a position and replacing what a slot holds. Custom exercises are marked as such. |
| `ExerciseLibraryScreen` | `lib/features/exercise/exercise_library_screen.dart` | Read-only management surface for the user's exercise catalog, reachable from the maintenance sheet. Never offers an add-to-workout action — the library is for management, not selection. |
| `ExerciseLibraryDetailScreen` | `lib/features/exercise/exercise_library_detail_screen.dart` | Management surface for one exercise. Built-in rows offer copy; custom rows offer edit and remove. Removal is reference-aware: zero references hard-delete, any reference retires (`isArchived = true`). |
| `ExerciseDetailViewScreen` | `lib/features/exercise/exercise_detail_view_screen.dart` | Read-only exercise details: description, discipline, capabilities split into tracking methods and movement properties, and muscles. Sections collapse when empty. Reused in management contexts with the add action suppressed. |
| `ProfileScreen` | `lib/features/profile/profile_screen.dart` | Identity, avatar, and body measurement tracking |
| `SettingsScreen` | `lib/features/settings/settings_screen.dart` | Calendar start-of-week, weight/distance units, timer alert preferences, notification-permission row for rest and effort alerts, feeling survey toggle, platform-health toggles (`Write workouts`, `Read body weight`) with denied-state pointer to system settings, appearance theme selector, and a low-emphasis version footer |
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
  → SettingsState(repository, preferencesService, healthPlatform: createHealthPlatformService())
                                 ← persisted app theme + unit preferences; health toggles resolve OS permission via the platform health gateway
  → HealthSyncService(platform, repository, settingsState, profileState)
                                 ← platform-health write/read pipelines; write hooked into session completion, read fired by the app-lifetime AppLifecycleListener on resume
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

The live watch session is threaded the same way and is **optional** at every level: `MyApp` and `HomeScreen` take a `LiveSessionMirrorState?`, and null means "this build has no watch sync", not "no session". A consumer handed null shows nothing and reserves no space for it, which is why a watch-less build lays out identically. Verified by `test/screen_widget_test.dart` (`shows no entry point without a live watch session`).

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

## Active Session Resume

Resuming an active session is driven by matching, not by navigation history: a modality tile
resumes when the active session's modality matches it, and the My Routines tile resumes when the
active session has `intent == 'routine'`.

Cold-start resume reads in-progress sessions from storage on the home screen's first frame. Two
invariants govern it:

- **Dismissing the resume prompt is not a delete.** System back-dismiss must preserve the stored
  session; only an explicit confirmed discard deletes it.
- **Only the most recent dangling session is surfaced**; older ones are cleaned up by state.

Verified by `test/interaction_flow_test.dart`.

---

## Related Documentation

- [App Philosophy](app_philosophy.md) — Home screen tile layout and UX constraints
- [Modality Tracking](modality_tracking.md) — Session creation and modality resolution
- [Session Summary](session_summary.md) — Post-workout summary screen

---

**Document Version**: 1.9
**Last Updated**: September 20, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-09-20. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
