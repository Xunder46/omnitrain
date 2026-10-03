# Service & Utility Classes

**Scope.** The service and utility classes that are neither session, nutrition,
nor app state: `lib/core/services/`, `lib/core/utils/`, and the cross-cutting
pieces those classes own, including the shared Stats formatters
(`lib/features/stats/widgets/native_value_format.dart`). The watch↔phone live
mirroring surface, the platform transport it rides on and the watch's own runtime
and sensor layer are in [The Watch Surface](watch_surface.md).

> Part of [State Management & Services](../state_management.md). Return to the
> index for the full class list and dependency graph.

---

## Service Classes

Services contain business logic that doesn't belong in state classes. They depend only on `WorkoutRepository` — no state classes, no UI.

### `CrashReportingService`

**File**: `lib/core/services/crash_reporting_service.dart`
**Depends on**: Sentry SDK only (no `WorkoutRepository` — crash reports are diagnostic, not domain data).

| Member | Purpose |
|--------|---------|
| `bootstrap(reporter, enabled, buildMetadata)` | Installs Flutter-side error sinks when `enabled: true`. Idempotent — re-entry is a no-op. |
| `buildMetadata(...)` | Returns the public allow-list `{appVersion, osVersion, deviceModel}`. The default-device helper reads platform info via `Platform.operatingSystem*`. |
| `recordError(error, stackTrace, metadata)` | Forwards to the underlying reporter if reporting is active. Always rebuilds metadata via the allow-list — call-site tags cannot widen the payload. |
| `SentryCrashReporter` | `CrashReporter` implementation backed by `sentry_flutter`. Disables `sendDefaultPii`, auto-breadcrumbs, auto-session-tracking; `beforeSend` re-applies the allow-list on every event. |
| `defaultDeviceMetadata(appVersion)` | Pure-Dart helper for the startup metadata snapshot. |

**Lifecycle**: `_runStartup` does not touch this service. Bootstrap runs in `main()` immediately after `WidgetsFlutterBinding.ensureInitialized()` and before `runApp`, with `enabled: kReleaseMode`. Debug and profile builds never install the sinks and never call the SDK.

**Privacy contract** (enforced in `crash_reporting_service.dart` header):
- Allow-list is the single source of truth — `buildMetadata` builds the return map from named args; any `extra` keys are silently dropped.
- `sendDefaultPii: false` strips IP / device-id / request cookies at the SDK boundary.
- `enableAutoSessionTracking = false`, `enableAutoNativeBreadcrumbs = false` block auto-breadcrumbs and session telemetry.
- The pre-release gate (`scripts/pre_release_check.sh`) re-asserts the Sentry wiring at archive time so a broken configuration cannot ship to the App Store / Play Store. The wiring the gate enforces and the tests that verify it: the `sentry_flutter` runtime dependency and `sentry_dart_plugin` symbol-upload dev-dependency are declared in `pubspec.yaml`; `bootstrap` is actually awaited from `lib/main.dart`; the debug-build guard (`kReleaseMode`) prevents debug builds from shipping telemetry; no `SENTRY_AUTH_TOKEN` (or any credential-shaped `--dart-define`) is compiled into the shipped Android binary; `SENTRY_PROJECT` exported in both the iOS and Android workflow jobs names the single `omnitrain` Sentry project; the iOS release artifact actually contains the DSN string (artifact inspection, not a workflow-text check); Android release minified with the `:app:uploadSentryMapping` hook; iOS Release config keeping dSYMs. The Android notification protections (`proguard-rules.pro` `-keep` for `com.dexterous.flutterlocalnotifications.**`, `keep.xml` raw-resource declarations) take effect in the produced `seeds.txt` / AAB / APK. Verified by `test/pre_release_gate_upload_destination_test.dart`, `test/pre_release_gate_ios_artifact_test.dart`, and `test/pre_release_gate_notification_and_build_test.dart`.

### `RoutineSessionService`

**File**: `lib/core/services/routine_session_service.dart`
**Depends on**: `WorkoutRepository`

Orchestrates template-to-session conversion.

| Method | Returns | Purpose |
|--------|---------|---------|
| `buildSessionFromTemplate(templateId)` | `RoutineSessionManifest` | Loads template hierarchy and builds a pure-data manifest for session population |

**Flow**:
1. Loads `WorkoutTemplate` → `TemplateSegment` → `TemplateEffort` → `TemplateTarget`
2. Loads all referenced `Exercise` entities
3. Returns `RoutineSessionManifest` (contains template + list of `SessionExerciseEntry`)

**Throws**: `Exception` if template not found or has no exercises

### `SessionSummaryService`
**File**: `lib/core/services/session_summary_service.dart`
**Depends on**: `WorkoutRepository`

Post-workout analytics.

| Method | Returns | Purpose |
|--------|---------|---------|
| `compareGroupsToPreviousSession(session, summary)` | `Map<String, GroupDelta>` | Finds the most recent previous session; computes per-group stats (strength volume, cardio/isometric duration, round counts); returns delta map keyed by `'strength'`, `'cardio'`, `'rounds'`, `'isometric'` |
| `computePRs(exerciseSummaries)` | `List<PRAchievement>` | Compares the session's per-exercise bests against the all-time best via `StatsProgressService.getAllTimeBestE1RM` (weight axis) and `StatsProgressService.getAllTimeBestReps` (reps axis). Collapses duplicate per-block entries to at most one record per exercise per session. Emits a weight-axis (`metricLabel: 'e1RM'`) PR for loaded exercises and a reps-axis (`metricLabel: 'reps'`) PR for bodyweight exercises — never both for the same exercise (`docs/plans/stats-summary-fix-pack-plan.md` PR 1 + Item 2). |
| `saveRoutineFromDraft(draft, {focusModality})` | `String` (template ID) | Persists a session-to-routine template |

---

---

### `HealthSyncService`

**File**: `lib/core/services/health_sync_service.dart`

Owns the two opt-in platform-health pipelines (Apple Health / Health Connect):
writing a completed session out, and reading body weight back in. Constructed
in `main.dart` and injected into `WorkoutState` (via `SessionCore`, which calls
`onSessionCompleted` after a successful session save) and into the app-lifetime
`AppLifecycleListener` (which calls `syncOnForeground`).

Layering rationale — the plugin boundary is deliberately narrow:

- `health_platform_service.dart` declares the plugin-free `HealthPlatformService`
  contract, the `HealthWorkoutDraft` / `HealthWeightSample` value types, and an
  `UnavailableHealthPlatformService` no-op.
- `health_platform_gateway.dart` conditionally exports the io gateway
  (`health_platform_gateway_io.dart`, backed by the `health` package) or a stub,
  mirroring `image_storage_service.dart`. The `health` package imports `dart:io`,
  so it must never enter the web compilation path.
- `health_modality_mapper.dart` maps session modality to the app-owned
  `HealthActivityKind`; the io gateway translates a kind to a platform activity
  type **per platform**, because several types (e.g. strength, flexibility)
  exist on exactly one platform and crossing them throws.

Invariants:

- Neither pipeline ever throws, prompts, or blocks: a missing permission or
  platform error surfaces as `false` / an empty list. Sessions and UI stay
  functional without the integration. Enforced by the try/catch blocks in
  `HealthSyncService` and `HealthPluginPlatformService`; verified by
  `test/health_platform_test.dart`.
- The write pipeline touches the platform at most once per session id, across
  restarts, via a JSON ledger preference key (`HealthPrefs.writtenSessionIdsKey`).
  Enforced in `onSessionCompleted`; verified by `test/health_platform_test.dart`.
- Imported body-weight rows use deterministic ids derived from the platform
  sample, so a repeated foreground read upserts instead of duplicating.
- Toggle state lives in the normal preference store (`HealthPrefs` keys), so a
  reinstall resets both toggles to off.

---

## Utility Classes

### `ObservationGrouper`

**File**: `lib/core/utils/observation_grouper.dart`

Groups flat observation lists by effort kind into structured per-set maps. Used by both session display and summary computation.

### `WorkoutSessionTimerMixin` (UI timer state)

**File**: `lib/features/session/workout_session_timer_mixin.dart`

`part of workout_session_screen.dart`. Mixed into `_WorkoutSessionScreenState`. Owns per-effort timer UI state and lifecycle — translating `TimerManager` state into local widget fields (`_effortRunning`, `_timedState`, `_roundState`, etc.).

**Key fields added (toolbar rework)**:
- `_inProgressKeys` (`Set<String>`) — tracks `effortId-entryIndex` keys whose timer has been started at least once and not yet finished. Enforces the global in-progress lock: only one timer can be active at a time.

**Key behaviors**:
- `_restoreTimerStateFromPersisted`: populates `_inProgressKeys` for any persisted `active`/`paused` state on session restore.
- `_toggleEffortTimer` (for `notStarted → active` transition): checks `_getAnotherInProgressKey`; if blocked, shows SnackBar `"Another set is still in progress. Pause or finish it before starting a new timer."` and returns early.
- `_resetTimerState`: removes key from `_inProgressKeys` (called after manual set log/finish flows).
- `_handleEffortTimerExpired` (round flow): removes the current round key from `_inProgressKeys` before calling `completeRound`, so the next round is immediately startable after auto-expiry.

**Navigation and running timers** (in `workout_session_screen.dart`):
- `_previousSet()`, `_jumpToSet()`, and `_switchExercise()` do **not** pause a running timer. The periodic tick and the scheduled expiry notification stay live, and `_handleEffortTimerExpired` finishes the entry (and opens the next rest) regardless of which set the user is looking at.
- These three sites used to call a `_pauseEffortTimer` helper. That helper is gone: pausing left the entry in a state with no Resume control while its key still held the in-progress lock, so the user could neither resume it nor start any other timer.

### `TimerAlertService`

**File**: `lib/core/utils/timer_alert_service.dart`

Audio-backed service for effort timer completion, rest-ping reminders, and settings previews.

Key behavior:

- `initialize()` configures `audio_session` on native platforms and preloads the bundled MP3 assets through `just_audio`
- `fireEffortTimerAlert(soundId)` plays the selected effort-timer sound and adds heavy haptic feedback on native platforms
- `fireRestPingAlert(soundId)` plays the selected rest-ping sound and adds light haptic feedback on native platforms
- `playPreview(soundId)` is used by the Settings sound picker to audition a sound immediately
- web does not attempt playback; it exits safely with debug logging instead

### `RestNotificationService`

**File**: `lib/core/utils/rest_notification_service.dart`

Platform notification scheduler for both rest pings and one-shot effort-timer expiry alerts.

Key behavior:

- `initialize()` configures local notifications plugin initialization and Android sound channels
- `scheduleRestPings(restStartMs, intervalSecs, soundId)` schedules future interval notifications (IDs `100-149`) via timezone-aware `zonedSchedule`
- `scheduleEffortTimerExpiry(fireAtMs, soundId)` schedules a single effort-expiry notification (ID `200`) used by round/timed/drill timer expiry
- scheduling uses `tz.local`, with local timezone set during app bootstrap in `main.dart` before app start
- `cancelRestNotifications()` cancels the reserved ID range and is used on rest-end / finish / dispose paths
- `cancelEffortTimerNotification()` cancels the reserved effort-expiry ID and is used on pause/manual-advance/finish/dispose paths
- foreground session scheduling uses silent notifications (`playSound: false`) and lifecycle backgrounding re-schedules audible notifications to avoid duplicate in-app + OS audio while still alerting when backgrounded/locked
- `requestPermission()` and `hasPermission()` support the Settings permission row flow
- Settings reads permission status only after `notificationPermissionAsked == true`, so the first-time row remains `Not yet asked` until contextual request
- `noop()` provides a safe no-op fallback for tests and non-wired construction paths
- web is fully no-op (all methods return early)

---

## Previously Undocumented Services & Utilities

Added on 2026-07-26. These exist in `lib/core/` and are wired into the app,
but had no entry in this doc.

### `CatalogSource` / `BundledCatalogSource`

**Files**: `lib/core/services/catalog_source.dart`,
`lib/core/services/bundled_catalog_source.dart`

`CatalogSource` is the interface `CatalogRefreshService` reads from, so the
data backing a catalog refresh can be swapped (e.g. for a server-provided
catalog) without touching the version-check logic. `BundledCatalogSource` is
the default implementation: pure reads of the compile-time `SeedData` /
`FoodCatalogSeed` constants plus the seeded demo routines. Its getters have
no side effects and are safe to call repeatedly.

See [DB Integration](../db_integration.md) for the refresh/version flow.

### `DemoRoutinesValidator`

**File**: `lib/core/services/demo_routines_validator.dart`

Validates the bundled demo routine templates against a rule set and returns a
`DemoRoutinesValidationResult` (`isValid` + a human-readable `failures` list).
Surfaced at startup when the bundled catalog fails validation, and dumped in
full by `scripts/pre_release_check.sh` in production mode. Also driven
standalone by `tools/validate_demo_routines.dart`.

### `StartupFailureDiagnosticWriter`

**File**: `lib/core/services/startup_failure_diagnostic_writer.dart`
(conditional export → `_io.dart` on native, `_stub.dart` on web)

Persists the most recent startup failure to a fixed file in app-private
storage on native targets so a failed launch can be diagnosed after the fact.
Web selects a no-op stub. Consumed by the startup path that renders
`StartupFailureScreen`.

### `OmniDateUtils`

**File**: `lib/core/utils/date_utils.dart`

Static date helpers for calendar and session grouping, plus the shared clock
format for durations (`startOfDayMs`, day/month bucketing, and related
conversions). All operations are **local-time
safe** — they build `DateTime` values from local components rather than UTC,
which is what keeps day-rollover and calendar bucketing correct.

### `FuzzySearch`

**File**: `lib/core/utils/fuzzy_search.dart`

`FuzzySearch.filterAndRank(query, exercises)` filters and ranks the exercise
list for the picker's search field, returning the original list unchanged for
an empty query. This is the search layer that sits in front of the relevance
scoring described in [Exercise Ranking](../exercise_ranking.md).

### `StatsProgressService`

**File**: `lib/core/services/stats_progress_service.dart`

The read-side aggregation service behind the Stats screen. It depends only on
the `WorkoutRepository` interface, and it caches one history snapshot per
instance, so a screen calling several `compute*` methods pays for the bulk
reads once instead of re-walking the history per figure. That cache is also why
a caller that needs fresh data after a write constructs a new instance.

`computeTotals()` is the all-time headline pair — completed sessions and their
duration. A rolling session counts as a completed session but contributes no
time, and the streak is deliberately not computed here because
`CalendarState.streakDays` owns that rule. Verified by
`test/screen_widget_test.dart`.

`computeExerciseMetrics({fromMs, toMs})` returns one summary per exercise
trained inside the range, carrying the section it sits in and the value that
section is read by; null bounds mean all history. Two of its rules are the ones
`computeProgressData` and `SessionSummaryBuilder` already own, and it exists so
they cannot drift:

- **The axis is a property of the exercise, not of the range or the day.** An
  exercise is on the reps axis when any bodyweight set appears anywhere in its
  history, so a range holding only loaded sets does not move it onto the weight
  axis and one series never mixes metrics.
- **The round predicate is `SessionSummaryBuilder`'s** — finished, started, and
  with an end stamp — rather than the stored `completed` flag, because a round
  stopped early still happened.

Verified by `test/exercise_metric_service_test.dart` (S-904 … S-911).

`progressionSamples()` returns one sample per completed session and exercise that
logged a `set` effort in it — whatever the session's modality, so a set logged in
a Cardio session still counts — ordered by exercise and then by session start,
valued by the same native-value rule and axis classification
`computeExerciseMetrics` uses and served from the same cached snapshot, so the
Progression Rate costs no extra repository read. An exercise-session whose value
is the axis's zero fallback is returned like any other; excluding it from the
rate is the pure math's rule, not the walk's.

Verified by `test/progression_samples_service_test.dart`.

`computeInstrumentSections({required StatsWindow window})` returns the window's
sections and rows, built from two `computeExerciseMetrics` calls — the window
itself, and the immediately preceding range of the same calendar length, so a
row's change compares like with like. It is the window's sections-and-rows read,
and nothing it produces is persisted.

- **Section order is by work done, not by declaration.** A section's rank is the
  number of distinct days in the window on which an effort of that kind was
  logged, descending; ties keep `ExerciseSection`'s declaration order. This
  supersedes `computeProgressData`'s fixed order for this list only.
- **Row order** is the count of days carrying a readable value, descending, then
  name, then id. A row appears for every exercise the window yields, including one
  whose value is the zero fallback; that row carries no readable value, so its
  rank is zero and it sorts last.
- **The change indicator** is the difference against the same exercise's value in
  the preceding range. It is absent when that range has no summary for the
  exercise, or holds a different metric — an exercise whose value is read a
  different way is not comparable. The preceding range is calendar arithmetic on
  the window's own day count, never a duration, so a DST transition cannot change
  its length.
- **Cadence and heart rate** come from the window's `SensorSummary` rows. Cadence
  is the summed steps over the timed instances that carry a step count, divided
  by those instances' summed minutes (Cardio only). Heart rate is the mean over
  the timed (Cardio) or round (Sports) instance summaries that carry a reading.
  Neither figure is produced when no summary carries it, and Resistance and
  Isometric rows never carry a heart rate.

The change a row shows is rendered by
`formatNativeChange(metric, delta, settings)` in
`lib/features/stats/widgets/native_value_format.dart`: an arrow and the signed
magnitude, or `'—'` when the delta is zero. The sign is the raw numeric sign of
the delta, with no per-metric inversion, and the magnitude is formatted by the
same per-metric rule as `formatNativeMetric`, so a change and the figure above it
read in one unit. `nativeSecondaryLabel` in the same file is the single source of
a secondary figure's name, so it cannot read two ways.

Verified by `test/instrument_list_service_test.dart` (S-1005, S-1007, S-1008,
S-1009, S-1010) and `test/instrument_change_format_test.dart`.

`computeMixLayer({required StatsWindow window, required DateTime now, required
String startOfWeek})` returns the Mix layer's whole payload — the measure, the
window's bar, the baseline's segments, the two counts and the weekly strip — or
`null` when the window holds no time at all. It is the only history walk behind
those figures: the window, the baseline and the strip are all served from the
one cached snapshot, so the surface pays for no extra repository read.

- **The measure is load only when the baseline is rated enough and the window is
  rated enough**; otherwise it is time. The baseline's segments are built in the
  load measure only, and only when the baseline's total load is above zero.
- **The baseline is the 12 calendar blocks before the window's start day** and
  never uses the start-of-week setting; that setting moves the strip's weeks and
  nothing else. The blocks are calendar arithmetic, so a DST transition cannot
  shift a boundary.
- **The strip is the 8 weeks ending with the week containing `now`**, oldest
  first, with the last week marked in progress. An empty week is present with a
  zero measure rather than dropped, a session belongs to the week it started in,
  and the strip is selected against each week's own bounds rather than the
  window, so changing the window moves the bar and leaves the strip alone.
- **The effort-to-modality mapping is the service's own** — the same
  `_sectionForKind` the Instruments list uses — so the two reads can never
  disagree about which modality an effort belongs to.

The rules themselves live in `lib/core/models/training_load.dart` and are
documented in [Training Load & Mix Definitions](../training_load.md).

Verified by `test/mix_layer_service_test.dart` (S-1501, S-1502, S-1503, S-1505,
S-1509, S-1510 A–E, S-1511 and its start-of-week twin, S-1513 and its
Sunday-start twin, S-1514, S-1515, S-1516, S-1517, and the Mock/Hive
value-for-value parity group).

`computeMixPeriod({required DateTime fromMs, required DateTime toMs})` returns
the same payload shape for an arbitrary period rather than a `StatsWindow`, and
is the entry point the Modality Mix Shift rule reads. It shares the one history
walk with `computeMixLayer` — the period, its baseline and the strip are served
from the same cached snapshot — and it carries no weekly strip, because the
period is not anchored to a week.

- **The period's bounds are the two instants it is given**, and its baseline is
  the `kTrainingLoadBaselineWeeks` calendar blocks before the period's start
  day, exactly as the window's is. The two reads therefore agree about the
  measure, the bar and the baseline for the same range.
- **The measure gate is the same one** — load only when the baseline is rated
  enough and the period is rated enough, otherwise time.

Verified by `test/modality_mix_period_service_test.dart` (S-1904a, S-1907,
S-1913, over both repository implementations).

---

### `SignalsService`

**File**: `lib/core/services/signals_service.dart` — see [Signals](../signals.md).
Verified by `test/signals_service_test.dart`.

---

## The Watch Surface

The watch↔phone live mirroring surface, the platform transport it rides on and
the watch's own runtime and sensor layer are documented in
[The Watch Surface](watch_surface.md).

---

> **Doc freshness** — Last reconciled against source: 2026-09-20. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
