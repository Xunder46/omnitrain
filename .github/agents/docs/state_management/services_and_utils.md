# Service & Utility Classes

**Scope.** The service and utility classes that are neither session, nutrition,
nor app state: `lib/core/services/`, `lib/core/utils/`, and the cross-cutting
pieces those classes own. It also covers the watch↔phone live mirroring surface
(`lib/state/watch/`, `lib/watch/start/watch_sync_orchestrator.dart`,
`lib/core/sync_protocol/`) and the watch's own runtime layer (`lib/watch/`,
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
| `computePRs(exerciseSummaries)` | `List<PRAchievement>` | Compares the session's per-exercise bests against the all-time best via `StatsProgressService.getAllTimeBestE1RM` (weight axis) and `StatsProgressService.getAllTimeBestReps` (reps axis). Collapses duplicate per-block entries to at most one record per exercise per session. Emits a weight-axis (`metricLabel: 'e1RM'`) PR for loaded exercises and a reps-axis (`metricLabel: 'reps'`) PR for bodyweight exercises — never both for the same exercise (`.github/agents/plans/stats-summary-fix-pack-plan.md` PR 1 + Item 2). |
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

- **A phone holding no ladder has no shape to assert.** When a snapshot arrives
  reporting a different session and the phone's own ladder is empty, the phone
  adopts the snapshot instead of answering with an empty one — otherwise joining
  a wrist-started session would wipe it.
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

Routes arriving messages to their owner — reference data to the start paths,
session state to the engine — and owns the connect exchange that
`PROTOCOL.md`'s "Idempotency and reconciliation" section specifies. Verified by
`test/live_mirroring_test.dart` (`S-009`) and by watchOS
`WatchLiveMirroringTests.testJoiningAsksForASnapshotRatherThanOfferingOne`.

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

## Watch Sensors and the Platform Workout

Both watch clients run the same layer: `lib/watch/sensors/`
and `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` +
`WatchSensorRecording.swift`.

### Structure

| Concern | Owner |
|---------|-------|
| The OS-level workout registration | `WatchPlatformWorkout`, over a `WatchPlatformWorkoutStore` the app target implements |
| What the device's sensors read | `WatchSensorRecorder`, over a `WatchSensorSource` the app target implements |
| Starting and stopping both together | `WatchSessionSensors` |
| Whether a session records GPS | `WatchGpsPolicy`, reading the modality's capability profile |
| Modality → platform workout type | `WatchActivityTypes` |

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
every entry it produced has been acknowledged, its raw log has done its job. The
distance that reached the phone is already the logged effort's `distanceMeters` —
the protocol's own field — so no message type was added and the phone holds one
source of truth for how far the user went. A session still running, or one with an
entry still awaiting a receipt, keeps its log, which is what keeps the live
readout and the settled distance across a kill.

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
`WatchSensorRecordingTests.testAReadingIsStoredWithoutBeingSentAnywhere`.
- **Two prunes, both gated on having nothing to lose.** The store's public surface
is exactly `append`, `readAll`, `pruneConfirmed` and `pruneSensorSamples`;
confirmed observations go first, and a session's sensor log goes only after the
session is over and all of its entries are acknowledged. Verified by
`test/watch_session_engine_test.dart` (`S-004 append-only enforcement at the
storage API`) and by watchOS
`WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule`.
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

---

> **Doc freshness** — Last reconciled against source: 2026-09-20. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
