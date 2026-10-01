# Service & Utility Classes

**Scope.** The service and utility classes that are neither session, nutrition,
nor app state: `lib/core/services/`, `lib/core/utils/`, and the cross-cutting
pieces those classes own. It also covers the watch↔phone live mirroring surface
(`lib/state/watch/`, `lib/watch/start/watch_sync_orchestrator.dart`,
`lib/core/sync_protocol/`), the platform transport that surface rides on
(`lib/core/platform/`), and the watch's own runtime layer (`lib/watch/`,
mirrored file for file by `watch/watchos/Sources/WatchSessionEngine/`), which are
service-shaped rather than screen state.

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

---

## Watch ↔ Phone Live Session Mirroring

The watch clients are built from the same protocol and the
same fixtures as the phone; the protocol itself is `watch/sync_protocol/PROTOCOL.md`.

### The two reconcilers, and why there are two

| Codebase | Reconciler |
|----------|-----------|
| Phone (Flutter) | `SyncSessionReconciler` — `lib/core/sync_protocol/session_reconciler.dart`, owned by `LiveSessionMirrorState` |
| Wear OS (Flutter) and watchOS (Swift) | `WatchSessionEngine.applyMessage` / `applyMessage(_:)` — `lib/watch/session/watch_session_engine.dart`, `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` |

There are two because the two ends converge on the same state from different
storage: the phone's session lives in memory and its reconciler is a pure
function over the message stream, while the watch's must survive a kill on an
append-only store. The apply *rules* are the same on both — they are the
fixtures' `expected` blocks, and the contract is that both implementations
converge on them. A cheaper-looking single reconciler would have to be the
intersection of two storage models, which is neither.

Verified by `test/live_mirroring_test.dart` and by watchOS
`WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`, which replay
every reconciliation fixture in `watch/sync_protocol/fixtures/manifest.json`
through both.

### `LiveSessionMirrorState`

**File**: `lib/state/watch/live_session_mirror_state.dart`

The phone's view of a session that a watch is running, or that both are. It is
a `ChangeNotifier` wrapping the reference reconciler: validate the envelope,
apply it, then `notifyListeners()`. Phone-originated messages are applied
locally *before* they go to the transport, because the session the user is
looking at has to be the session the watch is told about.

**A snapshot naming another session is a new workout, not a disagreement.** It
replaces the held session wholesale, entries included, clears
`completedRecord`, and is never answered; re-assertion is for a snapshot of the
held session only (PROTOCOL.md, "Idempotency and reconciliation"). Answering it
would pull the wrist back to a session it had finished, and merging would file
one workout's entries under another. Verified by `test/live_mirroring_test.dart`
(`S-251`); same-session re-assertion by its `S-008` group.

**Session-scoped entries are held, not counted.** The mirror keeps the wrist's
`effort_rating` and `session_end` entries (`sessionScopedKinds`), because a
snapshot it re-asserts must carry every entry. `effortEntries` and
`effortEntriesOf` are what a surface lists and counts as logged work. Verified
by `test/live_session_capture_entries_test.dart` (`S-254`).

`WatchMirrorTransport` is the phone's half of the transport contract: `send`
and `requestSnapshot`. Per-platform carriers (WatchConnectivity, the Wear OS
data layer) implement it; it is fire-and-forget with retries, and the protocol's
idempotency is what makes at-least-once delivery safe. There is deliberately no
reachability flag on it — a send that cannot be carried yet is the transport's
to buffer, not a decision the session logic should make.

Verified by `test/live_mirroring_test.dart` (`S-008`, `S-010`).

#### The same object is the phone's manage-bridge (item 10)

A live session can be *driven* from the phone, not merely watched, and the
mirror is where every one of those edits originates. Its named operations —
`addExercise`, `removeExercise`, `reorderExercises`, `moveExercise`,
`swapExercise`, `correctEntry`, `deleteEntry`, `pushExercise`,
`completeSession` — apply the change locally, then hand the protocol message to
the transport. They exist so no screen has to know a `structure_change` from an
`exercise_push`: a searched catalog exercise is a push (it carries its own
position), while managing the ladder is a change. Both are the phone's to
originate — the watch never does (PROTOCOL.md, authority rules 1 and 2).

`reorderExercises` takes a whole order and `moveExercise` is the one-place case
of it, because the protocol carries the ladder rather than a pair of indices;
the arithmetic therefore belongs to the ladder's owner, not to a screen.

`completedRecord` is the merge point: `completeSession` reports the lifecycle
once, snapshots the converged session, and returns the same record on a second
call, so one session closes as one record however many times Finish is tapped.
The entries in it are the reconciler's — ordered by wall-clock `loggedAt`, so
ordering does not depend on which device logged what.

Two rules the bridge depends on, both already in `PROTOCOL.md`:

- **A phone holding no ladder has no shape to assert.** A snapshot of the held
  session is adopted, not answered, while the phone's own ladder is empty —
  answering with an empty ladder would wipe the wrist's. (A session started on
  the wrist names a session the phone does not hold, so the switch rule above
  adopts it.)
- **A correction is addressed by `entryId`, never by the slot.** What a slot
  holds can change under a logged entry, and history records what happened.

Verified by `test/phone_manage_bridge_test.dart` (structure events against the
protocol's own schemas and against the shape
`watch/sync_protocol/fixtures/valid/structure_change.json` pins; interleaved
observations merging into one ordered record) and by
`test/interaction_flow_test.dart` (`Phone manage-bridge for live sessions`).

### `WatchSyncOrchestrator`

**Files**: `lib/watch/start/watch_sync_orchestrator.dart`,
`watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`

Routes arriving messages to their owner — reference data to the start paths or
the nutrition state, session state to the engine — and owns the connect
exchange that `PROTOCOL.md`'s "Idempotency and reconciliation" section
specifies. Verified by `test/live_mirroring_test.dart` (`S-009`) and by watchOS
`WatchLiveMirroringTests.testJoiningAsksForASnapshotRatherThanOfferingOne`.

### `WatchNutritionState`

**Files**: `lib/watch/nutrition/watch_nutrition_state.dart`,
`watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift`

The wrist's quick-log: the food list the phone sent down, the food and portion
the user has picked, and the observation confirming them produces. It owns no
storage of its own — the synced list is a `WatchFoodCatalogRecord`, the
wrist's own usage is derived from `WatchSessionEngine.nutritionLog`, and the
log itself goes through `WatchSessionEngine.logNutrition`, so a quick-log is an
observation rather than a parallel pipeline.

A quick-log is the one log on the wrist that needs no session: eating is not a
training event, and `observations_up` requires a `sessionId`, so a log taken
with no workout running carries the day's nutrition-log id
(`WatchNutritionSession`) while one taken mid-session rides that session. It is
not acknowledged by a snapshot: the phone's mirror does not hold a nutrition
session, so the entry never comes back that way, and confirmation comes from
the `receipt` message the phone sends instead. The portion control's detents
and bounds are not the wrist's to choose:
`watch/contract/watch_nutrition_contract.json` carries them and both clients'
suites assert against it.

Verified by `test/watch_nutrition_quick_log_test.dart` (S-001 to S-006) and by
watchOS `WatchNutritionQuickLogTests`.

### The wrist's food list, and why its order is the phone's rule

The watch shows the phone's Foods I Eat list in the phone's order — categories
alphabetically, foods the phone files under nothing last, foods alphabetically
inside each — because the phone owns the catalog and the cut of it the user
eats. That rule lives once, in `lib/core/utils/foods_i_eat_order.dart`, as the
`foodsIEatSections` function the phone's `NutritionScreen` renders; the wrist's
`deriveWatchFoodList` applies the same rule to the synced rows and then lifts
what the wrist itself logged most recently to the front, the same shape
`deriveFallbackExercises` uses for the offline exercise list.

Two implementations rather than one because the inputs differ: the phone has
`Food` and `FoodGroup` rows, the wrist has the protocol's row maps. The values
they must agree on are pinned by `watch/contract/watch_nutrition_contract.json`
— phone order, wrist order after a known log history, and the portion bounds —
which `test/watch_nutrition_quick_log_test.dart` (S-003) and watchOS
`WatchNutritionQuickLogTests.testTheWristDerivesTheContractsOrder` both read.
A change to the ordering on either platform therefore fails the other's suite.

### `WatchReferenceSync`

**File**: `lib/core/utils/watch_reference_sync.dart`

Builds the reference-data messages the phone sends down — `foods_down`,
`routines_down` and `preferences_down` — and nothing else. Building and carrying are separate jobs, so
it hands back an envelope and owns no transport; the foods' order is the phone's
own Foods I Eat order rather than a rule the wrist has to be told, and the energy
per serving comes from `calculateCalories` rather than being derived a second
time. It sits beside `foods_i_eat_order.dart` because it is a pure function over
the phone's models, with no state and no storage.

`buildRoutinesDown` returns **null** rather than an empty message when the phone
holds nothing the wrist could start. `routines_down` requires at least one
routine and at least one fallback exercise, so a phone that sent an empty list
would be sending a message the wrist must reject; a null is the honest answer to
"nothing to sync". It also skips an exercise with no capabilities, because
`sessionExercise` requires a non-empty `capabilities` array — a slot without one
would fail validation before any renderer saw it.

Two mappings in that builder are not mechanical, and both are the phone's
decision rather than the wire's:

- **Effort kind.** The app's `BlockTypes` vocabulary is larger than the wire's
  (`interval` is timed work, `amrap` is rounds, a `note` carries no exercise and
  never reaches here). The mapping is the phone's to make because the phone is
  the one that knows what the user built.
- **Targets.** A routine's targets are per metric *and per set*; the wire's
  `targets` is per effort, so the first set travels and the phone's own screen is
  where the rest stay. Durations are stored in seconds and travel in
  milliseconds; metrics the wire has no key for (RPE, rest, band assist) are not
  sent, because the schema carries no field for them.

`preferences_down` is its own message rather than a field on `routines_down`
because `buildRoutinesDown` answers null for a phone with no routines, and a
setting riding on it would then never reach the wrist. Its message id follows
its content as well as its `generatedAt`: the wrist keeps the newest copy and a
tie goes to the later-received one, so two different settings stamped in the
same millisecond must not share a delivery key.

Verified by `test/watch_reference_sync_test.dart` (S-003, S-004, S-007, S-253)
and `test/watch_nutrition_quick_log_test.dart` (S-003, for the foods half).

### The watch transport

**Files**: `lib/core/platform/watch_transport.dart`,
`lib/core/platform/watch_connectivity_channel.dart`,
`lib/core/platform/no_watch_transport.dart`,
`lib/core/utils/platform_watch_transport_factory.dart`

One object is both the watch's `WatchSyncTransport` and the phone's
`WatchMirrorTransport`, because they are one radio: `WatchTransport` extends both
and adds `onIncoming`, the single handler every arriving frame is handed to.

**The package boundary is `WatchMessageChannel` and nothing else.**
`watch_connectivity` is imported in exactly one file
(`watch_connectivity_channel.dart`); `WatchConnectivityTransport` is written
against the `WatchMessageChannel` interface, which is what lets a hand-rolled
`MethodChannel` + `WCSession` layer, or a Wear OS data-layer one, replace it
without touching a caller.

**Nothing is queued in the app layer.** A send the radio refuses is reported
through the transport's `onFailure` and dropped; what the peer still owes is
re-sent from storage on the next sync (PROTOCOL.md, "Idempotency and
reconciliation"). The transport is fire-and-forget by design — a queue here would
be a second source of truth about what has been delivered.

**A request is not a message.** PROTOCOL.md says so normatively, and
`WatchTransportRequest` is where that lives: a frame with no `type` is a request
(`routines` or `snapshot`), and a frame with one is a protocol message.
`WatchConnectivityTransport` implements the request calls over that one
vocabulary, so adding a request does not add a wire type.

**Platform choice happens once**, in `createPlatformWatchTransport`: iOS gets
`WatchConnectivityTransport`, and web, desktop, and Android get `null` — Android
until the Wear OS client is built. It reads `defaultTargetPlatform` rather than
`dart:io`'s `Platform`, because this file is compiled for web too, and a failure
to construct answers null rather than refusing to start the app.

Verified by `test/watch_transport_test.dart` (S-001, S-002, S-003, S-006, S-009)
over an in-memory two-ended channel.

### `WatchSyncRequestHandler`

**File**: `lib/state/watch/watch_sync_request_handler.dart`

Answers the frames that are requests rather than protocol messages: `routines`
is answered with `preferences_down` first and always, then with `routines_down`
when the phone holds any, both built through `WatchReferenceSync`; `snapshot`
re-asserts the phone's session. It is separate from `WatchIncomingRouter`
because the two answer different kinds of frame, and merging them would make a
transport detail a protocol one.

**Nothing here answers a request the wrist has not made.** There is no phone-side
schedule and no launch-time push, which is why the preferences ride every
`routines` request: a setting changed on the phone reaches the wrist at the
wrist's next sync. The value is `SettingsState`'s own toggle, never a re-read of
the stored preference. A phone holding no routines sends no `routines_down`,
and one holding no session answers a `snapshot` request with nothing: the wrist
keeps the copy it has, and an empty answer would be a state it never asked for.

Verified by `test/watch_transport_test.dart` (the `S-003` and `S-253` groups).

### `createWatchSync` — the phone's watch graph

**File**: `lib/state/watch/watch_sync_wiring.dart`

The one place the phone's watch graph is built: transport, `WatchSessionInbox`,
`LiveSessionMirrorState` (whose transport stages the phone's corrections in the
inbox), `WatchIncomingRouter` (inbox + mirror + nutrition bridge), and
`WatchSyncRequestHandler` (which reads the wrist-facing settings from
`SettingsState`), with the transport's inbound handler dispatching between the
last two. It resumes any import the phone had not run when it last stopped;
see [Watch Session Capture](../watch_session_capture.md). It returns a
`WatchSyncGraph` — the mirror, and the inbox behind the one capability a screen
needs, `WatchSessionRatings` — or null when the platform has no watch, which is
what keeps the environment contract intact: `main.dart` passes `liveSession` and
`watchSessionRatings` to `MyApp` only when this answered.

Two construction details are load-bearing:

- The mirror starts from `watchSessionPlaceholder` — a **valid but unheld**
  session id with status `abandoned` and no ladder. The id is not empty because
  every envelope the phone builds carries it and the protocol requires a
  non-empty `sessionId`; the status is `abandoned` so nothing offers a
  session-less phone as live, and the missing ladder means the first real shape
  arrives from the wrist (a session started there) rather than being asserted.

Verified by `test/watch_transport_test.dart` (S-006) for the platform decision
and the null answer, and by its S-001 cases for the placeholder: a phone whose
id the wrist does not hold is a phone whose pushes the wrist ignores, which is
why the id is valid rather than empty.

### `WatchIncomingRouter`

**File**: `lib/state/watch/watch_incoming_router.dart`

The one place a message arriving from a wrist is handed to its owners:
`WatchSessionInbox`, `LiveSessionMirrorState` and `WatchNutritionLogBridge`.
Each is asked about every message, and each answers for itself which messages
are its own — the inbox by entry kind, the mirror by session identity, the day
log by observation kind — so a message that belongs to several is not forced to
pick one, and a caller does not have to know that a quick-log can be session
news and food intake at once. Verified by
`test/watch_nutrition_quick_log_test.dart` (S-002), whose cases cover a
standalone quick-log, a session's own message, and a quick-log taken with a
session running.

The inbox is asked first, so what a wrist session will become in history is
durable before anything else can answer the message; see
[Watch Session Capture](../watch_session_capture.md). Verified by
`test/watch_session_import_test.dart` (`S-261`).

### `WatchNutritionLogBridge`

**File**: `lib/state/watch/watch_nutrition_log_bridge.dart`

The phone's half of a quick-log: it turns the wrist's `nutrition_quick_log`
events into the phone's own day log through `NutritionState.logConsumedFoodAt`.
A quick-log is filed by the phone's rule, not the bridge's — one row per food
per day means a redelivered message updates the row it made the first time, so
"exactly once" needs no ledger of its own. A food the library no longer holds is
reported rather than guessed at: with no food there are no macros to freeze onto
a row.

It is also the sender of the `receipt` that acknowledges those observations —
including the ones it could not place, since what a receipt asserts is that the
phone holds the observation, not that the day log changed. It answers a message
it refused to read with nothing at all. What the wrist does with the receipt is
`WatchSessionEngine.confirmObservations` — an append of its own, so a relaunch
can still tell what it may drop — and `pruneConfirmed`, which is the only way
the observation box gives rows back. Both are exercised by
`test/watch_nutrition_quick_log_test.dart` ("the phone’s receipt is what lets the
watch drop the row", "a food the phone cannot place is not owed forever") and by
`WatchNutritionQuickLogTests.testThePhonesReceiptIsWhatLetsTheWatchDropTheRow`.

The other half of the same problem is on the mirror: `LiveSessionMirrorState`
ignores any message it consumes whose `sessionId` is not the session it holds
(`session_snapshot` excepted), because a quick-log taken with no workout running
names the day, and filing a meal under a workout is worse than dropping it.

### Invariants

- **Nothing is written twice.** A structure change is keyed by `changeId`, and
every row the watch writes from a message carries an id derived from that
message, so re-delivery is a store-level no-op. Verified by
`test/live_mirroring_test.dart` (`S-007 forced redelivery produces no
duplicates`) and by watchOS
`WatchLiveMirroringTests.testReplayingTheStreamTwiceConvergesIdentically`.
- **The watch store stays append-only.** A phone correction is a *projection*
(`WatchSessionEngine.entries`), not an edit: the stored observation row is never
rewritten. Verified by `test/watch_session_engine_test.dart` (`S-004 append-only
enforcement at the storage API`).
- **An incoming message has one gate.** `SyncProtocolValidator.evaluateOrAccept`
(Dart) and `SyncProtocolValidator.incomingRejections` (Swift) own the version
check and the conformance verdict, including the case of a receiver that carries
no schemas — a receiver that cannot read is not a receiver that should refuse.
Every receiver that takes a message from a peer goes through it: the live
mirror, the nutrition log bridge, the watch session inbox, and each engine's
`_requireConformingIncoming`
/ `requireConformingIncoming`, which differ only in what they do with a
refusal. Verified by `test/sync_protocol_fixtures_test.dart` (`the receiver
gate`), which exercises the shared gate directly, including its no-schema
branch; the per-receiver outcomes are covered by
`test/live_mirroring_test.dart` and `test/watch_session_engine_test.dart`.
- **Outbound is a different question from inbound.** The gate above judges what
a peer sent. What this build is willing to *send* is `requireConformant`, and it
asks `validateEnvelope` directly because the version on an envelope this build
wrote is not in doubt. Every message the app builds goes through one builder,
`phoneEnvelope` (`lib/core/sync_protocol/phone_envelope.dart`), so its producers
cannot spell the envelope's fields differently — `buildFoodsDown`,
`snapshotEnvelope`, the mirror's own messages and `receiptFor`. The QA harness at
`lib/watch/debug/watch_start_debug_main.dart` is the exception: its two seeds are
`const` fixtures standing in for a transport no desktop run has, and a `const`
cannot call a function. Verified by the protocol fixture suites.

## Watch Sensors and the Platform Workout

Both watch clients run the same layer: `lib/watch/sensors/`
and `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` +
`WatchSensorRecording.swift`. The steps sensor and the summaries computed from the
readings (`WatchSensorSummaries.swift`) exist only in the watchOS package:
`lib/watch/` records no steps and computes no summaries.

### Structure

| Concern | Owner |
|---------|-------|
| The OS-level workout registration | `WatchPlatformWorkout`, over a `WatchPlatformWorkoutStore` the app target implements |
| What the device's sensors read | `WatchSensorRecorder`, over a `WatchSensorSource` the app target implements |
| Writing the readings one at a time | `WatchSensorWrites`, inside `WatchSensorRecorder` |
| Starting and stopping both together | `WatchSessionSensors` |
| Whether a session records GPS | `WatchGpsPolicy`, reading the modality's capability profile |
| Modality → platform workout type | `WatchActivityTypes` |
| What is computed from the readings before they may go | `WatchSensorSummaries`, pure functions over stored rows, called by `WatchLoggingState.log` for an entry and by `WatchSessionEngine` for a `session_end` |

`WatchSensorSource` and `WatchPlatformWorkoutStore` are the seam the OS bindings
sit behind, and they are why this layer is testable: `HKWorkoutSession`,
`HKLiveWorkoutBuilder` and `CLLocationManager` exist only in an app target, so
neither `swift test` nor a Dart suite can reach them directly. The
implementations in the tree are the two suites' fakes and the QA harness's own
defaults: `test/watch_sensor_recording_test.dart`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift`, and
`lib/watch/debug/watch_session_debug_surface.dart`, which takes both seams as
constructor parameters and passes a no-permission source and a no-op store when it
is given none. Which app target provides the real bindings, and what that means
for acceptance criterion 2, is recorded in
[the documentation audit](../docs-audit-2026-07-26.md) §8.6.

### Rationale

**Sensor readings are stored rows, not fields.** A heart rate or a distance is
appended to the watch's own store like everything else, and the live readout is
derived from the newest stored row. A value held in memory would be the one thing
on the wrist that a kill loses, and the whole watch design exists to avoid that.

**Sensor rows are dropped with the session, not with a receipt.** Observations
are gated on the phone's receipt because the phone is their destination. A
reading's destination is the session that produced it: once a session is over and
every entry it produced — and, for a session the wrist created, its `session_end`
— has been acknowledged, its raw log has done its job. The distance that reached
the phone is already the logged effort's `distanceMeters` — the protocol's own
field — so no message type was added and the phone holds one source of truth for
how far the user went. A session still running, or one with an entry still
awaiting a receipt, keeps its log, which is what keeps the live readout and the
settled distance across a kill.

**Summaries are computed on the wrist, once, before the readings may go.** The
phone never receives a raw reading, and the wrist prunes its readings once the
phone holds the session, so anything derived from them has to be derived first and
carried by an event the phone already imports. An entry's heart rate, and a timed
entry's steps, are computed when it is logged, over the window the event itself
states; the session's heart rate and each set block's are computed into the
`session_end`, because a set has no window of its own — it carries only the moment
it was logged. Nothing is recomputed afterwards: the stored event is what is re-sent,
so the phone never sees one entry with two sets of values.

**One writer.** Every sensor streams on a task of its own, and because steps are
recorded in every session the user allows it for, at least two streams run at
once. The engine and its store are built for one writer, so the recorder chains
its writes (`WatchSensorWrites`) rather than letting a second always-on sensor
become a second concurrent writer.

**The workout is recovered, not resumed.** A kill cannot be caught, so the next
launch ends whatever the health store still reports as running rather than trying
to adopt it. The session it belonged to is already over as far as the process is
concerned, and its logged entries are in storage either way. Verified by
`test/watch_sensor_recording_test.dart` (`S-005`) and by watchOS
`WatchSensorRecordingTests.testS005TheNextLaunchEndsTheWorkoutTheKillLeftBehind`.

### Invariants

- **GPS activation derives from the modality's capability profile, never from its
name.** A modality added later is handled without touching the policy, and one
that merely sounds like distance work does not wake the radio. Verified by
`test/watch_sensor_recording_test.dart` (`S-008`) and by watchOS
`WatchSensorRecordingTests.testS008TheGpsDecisionFollowsTheCapabilityProfile`.
- **A denied permission or absent hardware never blocks logging.** The
subscription is skipped and nothing else changes; sensor fields are simply
absent. Verified by `S-006` in both sensor suites.
- **Both clients read one vocabulary.** The sample kinds, the modality → workout
type table and the capability profile the GPS decision depends on live in
`watch/contract/watch_sensor_contract.json`, and both suites assert against it, so
a change on one platform fails the other's tests.
- **A reading is stored, never sent.** Sensor rows are written through the same
append entry point as every other row and emit nothing; the measured distance
reaches the phone inside the logged effort. Verified by
`test/watch_sensor_recording_test.dart` (`a reading is stored without being sent
anywhere`) and by watchOS
`WatchSensorRecordingTests.testAReadingIsStoredWithoutBeingSentAnywhere` and
`WatchSensorRecordingTests.testS239AppendingAStepCountEmitsNothing`.
- **The summary fields are the only values derived from readings on the wire,
and none is ever recomputed.** They are the heart-rate, steps, pause and set-block
fields `watch/sync_protocol/PROTOCOL.md` lists under "Session capture"; a re-send
carries the stored event, whatever readings arrived later. Verified by watchOS
`WatchSensorSummaryTests.testS238ALateReadingNeverRewritesWhatWasSent` and
`WatchCaptureContractTests`, which replays
`watch/contract/watch_capture_contract.json` and compares every event.
- **Nothing measured is absent, never zero.** A window with no qualifying reading
gets no pair and no step total, and a reading a summary could not send — below the
protocol's heart-rate minimum, negative, or not a number — is not a reading. A
summary therefore never makes its event unsendable. Verified by watchOS
`WatchSensorSummaryTests.testS235WithTheSensorsDeniedNoEventCarriesASummary` and
`WatchSensorSummaryTests.testAReadingBelowOneBeatPerMinuteIsNotAHeartRate`.
- **Steps change nothing else.** With steps permission refused, every other sensor
behaves exactly as with it granted. Verified by watchOS
`WatchSensorRecordingStepsDeniedTests`, which runs the whole sensor suite again with
steps denied, and `WatchSensorRecordingTests.testS239StepsPermissionChangesNothingButTheStepsRecorded`.
- **Two prunes, both gated on having nothing to lose.** The store's public surface
is exactly `append`, `readAll`, `pruneConfirmed` and `pruneSensorSamples`;
confirmed observations go first, and a session's sensor log goes only after the
session is over, all of its entries are acknowledged and — for a session the
wrist created — its `session_end` is acknowledged, pruned or not. Verified by
`test/watch_session_engine_test.dart` (`S-004 append-only enforcement at the
storage API`) and by watchOS
`WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule` and
the `S-237` cases in `WatchSensorRecordingTests`.
- **Timers travel as wall-clock timestamps.** A countdown is never sent;
either end derives it, which is what keeps a timer correct through a
suspension or a reconnect. Verified by `test/live_mirroring_test.dart`
(`S-005 the timer's end moment is the same on both devices`).
- **A message a receiver cannot read is refused whole.** Nothing is applied, and
the refuser answers with its own snapshot so the peer converges from real state
instead of from a stream it could not interpret. Verified by
`test/live_mirroring_test.dart` (the two `a message the receiver cannot read`
cases) and by watchOS
`WatchLiveMirroringTests.testAVersionMismatchIsRefusedAndAnsweredWithASnapshot`.

### Vocabulary

- **Snapshot exchange** — the connect/reconnect handshake defined in
`PROTOCOL.md` under "Idempotency and reconciliation".
- **Correction vs. observation** — an observation is an append by whoever logged
it and is never edited; a correction is the phone's edit to an existing entry,
which the watch reflects without rewriting its own history.
- **Reflection** — a watch's copy of session structure or timer state, which it
holds but does not originate. `PROTOCOL.md` authority rules 1 and 2 are what
make the distinction consequential.
- **Session end, set block** — defined in
[Watch Session Capture](../watch_session_capture.md), which owns what the wrist
sends for the import.

---

> **Doc freshness** — Last reconciled against source: 2026-09-20. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
