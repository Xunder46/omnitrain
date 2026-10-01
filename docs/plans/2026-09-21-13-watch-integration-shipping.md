# Feature: Watch ↔ Mobile Integration — Shipping the Complete System

> **Tier 4 — Consolidation (cleanup/completion).** Watch↔Phone sync protocol
> and implementation verified to exist; now closing the three missing links and
> the human infrastructure prerequisite.
>
> Platforms: iOS / watchOS only this cycle. Wear OS is deferred to a separate
> cloning job — see "Deferred: Wear OS / Android".
> Validates against: `watch/sync_protocol/PROTOCOL.md`, shared protocol fixtures.
> Last reconciled against source: 2026-09-21.

## Overview

Plans 05–12 delivered the sync protocol, reconciliation engines on both watch
platforms, the wrist's logging surfaces, session start paths, live mirroring on
the phone, and nutrition quick-log. The code is there, the tests pass, the
protocol is the contract — but three pieces are missing that block end-to-end
work:

1. **No transport exists**: `WatchMirrorTransport` and `WatchSyncTransport` are
   interfaces with only test doubles. No real MethodChannel, WCSession, or Wear
   OS data-layer implementation. `pubspec.yaml` has no connectivity package.

2. **Nothing wired in production**: `MyApp.liveSession` is always `null` in
   `main.dart`. The live-session mirror, nutrition log bridge, and phone's
   manage bridge are constructed only in debug harnesses. The home-screen entry
   point and the live session screen are dead in the shipping app.

3. **Phone never builds `routines_down`**: Only `buildFoodsDown` exists in
   `WatchReferenceSync`. The watch's primary offline path (start-from-routine)
   has no phone-side producer. `WatchSyncOrchestrator.requestRoutines` has
   nothing to answer it. A hand-written literal in the debug harness is the
   only `routines_down` payload in the repo.

This plan closes those three, resolves the outstanding protocol gap around
modality encoding in routines, audits the two-engine reconciliation logic for
drift, and names every piece of manual human work (Xcode project creation,
entitlements, provisioning) required to build and ship a real watchOS app.

## Resolved Decisions (Ledger)

### D-2: Production DI wiring — main.dart constructs real transport
**Derived from default; vetoable before first handoff.**

- On iOS with a watch OS build: `main.dart` constructs a `WatchConnectivityTransport`
  (or `_MethodChannelTransport`) and passes it into:
  - `LiveSessionMirrorState` (phone-side live sync)
  - `WatchNutritionLogBridge` (phone-side nutrition quick-log receipt)
  - `WatchIncomingRouter` (phone-side message dispatch)
  - These are then passed into `MyApp` as `liveSession` (currently always null).
- On Android or web or desktop (no watch): transport is a no-op (`_NoWatchTransport`)
  that succeeds all sends silently. This keeps the environment-safety contract
  from CLAUDE.md intact.
- Platform detection: check for `kIsWeb`, `defaultTargetPlatform`, or
  `Platform.isIOS` from `dart:io`. The app already uses `Platform.isIOS`
  elsewhere.
- This leaves untouched: the debug harness (`live_session_mirror_debug_main.dart`)
  continues to wire its own debug doubles for QA.

### D-3: `routines_down` producer — build from real routines
**User decisions on Q-3 and Q-5 supersede this. See D-6 and D-7.**

Original plan was to build `routines_down` proactively on phone launch and
encode modality in payload. User decisions change both the trigger (watch-initiated,
not phone-initiated) and the effort-kind handling (reflect routine's declared kind,
not phone's capability derivation). See D-6 and D-7 below.

### D-6: Watch reflects routine's declared effort kind (supersedes D-3)
**User decision on Q-3: "the watch needs to reflect what is set up on the routine properly."**

- For routine-started sessions, the watch honours the `effortKind` the phone
  sent in `routines_down` and stops re-deriving it from capabilities.
- Capability derivation survives only where there is no routine to reflect:
  free workouts and pushed-exercise paths (no wire-declared effort kind).
- Concretely: `WatchLoggingState.effortKind` (`lib/watch/logging/watch_logging_state.dart:272`,
  walking `_kindPrecedence` at `:145` through `ModalityConfig.effortKindFromMetric`)
  must prefer the routine's declared kind when the slot came from a routine.
- Swift client must match; `watch/contract/watch_start_paths_contract.json`
  proves they agree. The Plank row there (effort `effortKind: "timed"`) currently
  diverges — under this decision the wrist renders `timed`, not `drill`.
- Resolves plan 08's open item 2 (Plank modality disagreement).
- Test coverage: `watch/contract/watch_start_paths_contract.json` fixture
  (shared by both clients) asserts effort kinds match.

### D-7: Sync is watch-initiated; phone responds (supersedes D-3 trigger)
**User decision on Q-5: "User initiates from the watch, they should see a label stating there is no auto sync."**

- No sync on phone launch. No phone-side automatic trigger. No background sync.
- The wrist has an explicit user action that requests reference data, answered
  by `WatchSyncOrchestrator.requestRoutines`, which today has no producer on
  the phone.
- **The watch UI must carry a visible label telling the user there is no automatic sync.**
  This is a stated product requirement, not an implementation detail. It must
  survive into both watch clients (Wear clone job inherits it). Done Criterion:
  label is rendered and visible in tests (S-010 below).
- Phone builds and sends `routines_down` **in response to a watch request**,
  not on a phone-side schedule. Phase 4 is rewritten to implement this (watch
  asks, phone answers, label is shown).

### D-1: Transport approach — `watch_connectivity` pub package + interface abstraction
**User decision on Q-1: use the pub package; keep interfaces free of package type.**

- iOS: `watch_connectivity` pub package wrapping the native `WCSession`.
  MethodChannel for app-level transport initialization and error handling.
- Keep `WatchSyncTransport` (watch side) and `WatchMirrorTransport` (phone side)
  free of any package type so hand-rolled `MethodChannel` + `WCSession`
  implementation can replace it without touching a single caller. Reversible,
  and it gets to device fast.
- If package does not expose what protocol needs (ordering, file transfer for
  large payloads, reachability), swap the implementation behind the interface
  rather than reopening the decision.
- Delivery semantics: fire-and-forget with automatic retries (handled by the
  platform layer), at-least-once delivery, in-order per message type. Duplicates
  are idempotent (protocol-layer guarantee via `eventId`/`changeId`).

### D-4: Two-engine reconciliation — add cross-stack conformance harness
**User decision on Q-4: conformance harness now (default was right).**

Do not unify implementations now. Risks of unifying now: late-cycle refactor,
potential for introducing bugs in the most critical path. Shared fixtures plus
`watch/contract/*.json` already force agreement; cross-stack test makes a
divergence fail loudly instead of silently. Unify only if the harness catches
real drift.

- Both `SyncSessionReconciler` (phone) and `WatchSessionEngine` (watch) implement
  the same apply rules: insert, remove, reorder, swap, correct, delete.
- New test: `test/watch_reconciliation_cross_stack_test.dart` — run a fixture
  (session snapshot + event stream) through both engines in lockstep, assert
  that their structure state (exercises, positions, revisions) converges
  identically.
- The fixture set is the existing protocol reconciliation suite, reused. If
  protocol changes, both tests auto-update.
- Mark the `SyncSessionReconciler` and `WatchSessionEngine` ladder logic with a
  comment pointing at this test, so future drifts are caught immediately.
- Decision boundary: if the cross-stack test ever fails on a new fixture, the
  plan is in place to catch it and the implementer has no choice but to fix both
  in lockstep.

### D-5: Sensor recording seam — blocked on watch app target
**Rationale: cannot implement until human creates the watchOS app target.**

- `WatchPlatformWorkoutStore` currently has only `_NoPlatformWorkout` (debug).
- The real implementation requires HealthKit integration (native iOS APIs), which
  lives in the watchOS app target's code, not in the Swift Package library.
- This decision records that the decision to implement is blocked, not a design
  choice. See the "Manual Human Work" section below.

## Feature Invariants

- **Protocol is normative**: `watch/sync_protocol/PROTOCOL.md` is the single
  source of truth for wire format and authority rules. All code diverges at
  pain.
- **Hive ↔ Mock parity (phone)**: `HiveWorkoutRepository` and
  `MockWorkoutRepository` both sit behind `WorkoutRepository`. Any change to
  watch sync paths must preserve this.
- **Platform safety (CLAUDE.md contract)**: the app builds and tests on web and
  desktop. `main.dart`'s transport wiring must not crash on a platform with no
  watch. The debug harness's transport is a test double; production uses a
  platform-aware no-op on non-iOS.
- **Snapshot merge does not lose entries**: `_applySnapshot` merges existing
  entries by `entryId` rather than replacing, so watch-logged entries that the
  snapshot does not carry are not lost.

## Requirements

1. Real message transport between phone and watch, bidirectional, fire-and-forget
   with platform retries, idempotent by protocol (eventId/changeId).
2. Production DI wiring so `MyApp.liveSession` is non-null on iOS and calls the
   live-mirroring and nutrition-bridge paths.
3. Phone-side producer for `routines_down`, responding to watch-initiated requests
   (not proactive phone-side triggers). Watch must include explicit user action
   to request routines, with visible UI label stating "no automatic sync" (D-7).
4. Watch reflects routine's declared effort kind, not derived from capabilities,
   so Plank and other multi-capability exercises render correctly per the routine's
   intent (D-6).
5. Cross-stack reconciliation conformance test so engine drifts between phone and
   watch are caught by CI.
6. Manual prerequisite work documented so a human engineer knows exactly what to
   do in Xcode: create the watchOS app target, wire entitlements, add HealthKit
   capabilities, background modes, and health description strings.

## Acceptance Criteria

- [ ] A message sent from phone to watch arrives exactly once and is applied
      idempotently (S-001, now with real transport).
- [ ] Watch user taps "Request routines," phone receives request, builds and sends
      `routines_down`, watch persists. Routine-started session reflects declared
      effort kind, not inferred from capabilities (S-004, D-6).
- [ ] Watch UI displays "no automatic sync" label on routine picker screen
      (S-010, D-7).
- [ ] Plank exercise in isometric routine renders timed-effort UI (not hold-timer),
      reflecting the phone routine's declared `effortKind: "timed"` (S-004, D-6).
- [ ] The watch advances to the next exercise when the phone removes the current
      one (S-009 from plan 09, now with real transport).
- [ ] A food quick-logged on the wrist appears in the phone's nutrition log
      (plan 12 AC-1, now with real transport).
- [ ] The phone's live-session mirror is wired in production DI and non-null on
      iOS.
- [ ] The app still builds and tests on web and desktop (environment safety).
- [ ] Cross-stack reconciliation test passes: both engines converge on identical
      structure state for every protocol fixture.

## Scenarios

### S-001: Real transport delivers a message end-to-end (phone→watch)
- Fixture: Phone and watch are paired; app is running on both; transport is
  connected.
- Trigger: Phone user logs a set while the session is live.
- Flow: `LiveSessionMirrorState.send(observations_up)` → `WatchSyncTransport.send`
  (on watch side) → platform queueing → network delivery → watch receives →
  `WatchSyncOrchestrator.receive` → `WatchSessionEngine.applyMessage`.
- Expected outcome: Watch shows the entry within 2 seconds. `eventId` is present
  and idempotent.
- Edge case of: plan 09 S-001, now with real transport.

### S-002: Real transport delivers a message end-to-end (watch→phone)
- Fixture: Phone and watch are paired and running; session is live on the watch.
- Trigger: User logs a set on the watch.
- Flow: `WatchSessionEngine.logEntry` → `WatchSyncOrchestrator.send(observations_up)`
  → platform transport → phone receives → `WatchIncomingRouter.receive` →
  `LiveSessionMirrorState.receive` → session is updated.
- Expected outcome: Phone shows the entry within 2 seconds. Re-sending the same
  event is a no-op.
- Edge case of: plan 09 S-001 (from watch side).

### S-003: `routines_down` is built and sent in response to watch request
- Fixture: Phone holds three routines (Chest+Back, Cardio, Yoga); each carries
  exercises with modality-specific capabilities (reps for Chest, time for Yoga).
- Trigger: Watch user requests routines (taps "Sync" or equivalent user action).
- Flow: Watch sends request → phone receives via `WatchIncomingRouter` → handler
  calls `WatchReferenceSync.buildRoutinesDown` → phone builds payload → sends
  `routines_down` via transport.
- Expected outcome: Watch receives payload; deserializes to `WatchRoutineRecord`
  rows; can present routines on the start screen; can begin a session from a
  routine.
- Edge case of: offline starting (watch has cached routine from prior request).
- Flow note: the request branch answers `snapshot` as well as `routines`, which
  is its own scenario — see S-011.

### S-011: The phone answers a request for its session
- Fixture: A session is live on the wrist; the phone holds it through
  `LiveSessionMirrorState`. `WatchTransportRequest.snapshot` is the request.
- Trigger: The wrist asks the phone for its session — `WatchSyncOrchestrator`
  does this on the path where it needs the phone's structure, and the phone's
  own mirror can ask too.
- Flow: Wrist sends `{request: snapshot}` → phone's transport classifies it as a
  request, not a protocol message (`WatchTransportRequest.nameOf`) → the handler
  runs `_sendSnapshot` → the mirror's ladder goes out as a `session_snapshot`.
- Expected outcome: The wrist receives the phone's session, and the phone did not
  act on a message it was never sent. A phone holding **no ladder** answers
  nothing: an empty snapshot would replace the ladder the wrist is working
  through.
- Edge case of: S-003 (the other request the same branch serves).
- **Register provenance:** added by the developer during review, not by the
  Conductor — the branch was implemented and then found untested, so this records
  what exists rather than planning anything new. A Conductor should confirm the
  numbering does not collide with a later plan's register.

### S-004: Watch reflects routine's declared effort kind (D-6)
- Fixture: Phone routine has Plank in an isometric segment with `effortKind: "timed"`
  in `routines_down`; watch receives the routine.
- Trigger: Watch user opens the routine picker and selects Plank.
- Flow: Watch reads `effortKind` from the synced routine row → UI renders
  timed-input (not hold-timer, not rep/weight) → user logs time duration.
- Expected outcome: Watch UI reflects the phone routine's declared effort kind,
  not derived from Plank's capabilities. Plank is rendered as timed, resolving
  the modality disagreement flagged in plan 08.
- Edge case of: none.

### S-005: Watch app target prerequisites are documented in human-readable form
- Fixture: A developer who has not built watchOS apps before. Requires a Mac
  with Xcode and an Apple Developer team.
- Trigger: Developer reads `docs/watch-app-setup-and-qa.md`.
- Flow: Developer follows §3: installs the watchOS runtime, adds the target,
  verifies the bundle-identifier relationship, adds HealthKit and
  `WKBackgroundModes`, links the Swift package, writes the entry point.
- Expected outcome: **the watch app launches on the simulator and shows the
  start surface**, which is the only outcome that proves the steps were
  sufficient.
- Edge case of: none.
- **Status: not satisfiable by an agent, and no test can pin it.** The outcome
  requires a human with Xcode and a signing identity; this repository has no
  watchOS simulator runtime installed, so even the build cannot be attempted
  here. The document is the deliverable (`§3` steps, `§5` QA levels); whether it
  is *sufficient* can only be established by the human following it. Verified
  to the extent possible by `test/docs_indexing_contract_test.dart` (the guide is
  inside the size ceiling and is indexed).

### S-006: Production DI wiring is platform-aware
- Fixture: App is built for iOS; watch is paired.
- Trigger: App launches; `main.dart` constructs DI graph.
- Flow: Platform check (iOS) → construct `WatchConnectivityTransport` →
  `LiveSessionMirrorState` with transport → passed to `MyApp.liveSession` →
  home screen renders live-session panel.
- Expected outcome: Live session is active in production; the same build on web
  or Android has a no-op transport and skips the panel.
- Edge case of: web or desktop.

### S-007: `routines_down` payload includes every exercise a routine references
- Fixture: Routine has Exercise A, B, C; Exercise A is also in Routine 2.
- Trigger: Phone builds `routines_down`.
- Flow: Payload enumerates Routine 1 (A, B, C) and Routine 2 (A). Fallback
  exercises list contains (A, B, C) — no duplicate A.
- Expected outcome: Validator asserts fallback covers all referenced exercises.
  No semantic_violation.
- Edge case of: none.

### S-008: Cross-stack reconciliation — snapshot merge
- Fixture: Protocol fixture `reconciliation/snapshot_then_events.json`.
- Trigger: Both phone `SyncSessionReconciler` and watch `WatchSessionEngine`
  process the same fixture.
- Flow: Apply snapshot → apply event stream → compare structure state.
- Expected outcome: Both engines' session state is identical (exercises, slots,
  positions, revision).
- Edge case of: none.

### S-009: Cross-stack reconciliation — remove current exercise
- Fixture: Protocol fixture `reconciliation/remove_current_exercise.json`.
- Trigger: Same fixture on both `SyncSessionReconciler` and `WatchSessionEngine`.
- Flow: Remove event arrives; current position is on the removed exercise.
- Expected outcome: Both engines advance position identically. No divergence.
- Edge case of: none.

### S-010: Watch UI labels "no automatic sync" (required by D-7)
- Trigger: User opens the watch app's routine picker or reference-data screen.
- Fixture: Watch has no active sync request to phone; user must explicitly request.
- Flow: Screen is displayed; label is visible stating there is no automatic sync.
- Expected outcome: Text is shown and visible in the watchOS (SwiftUI) client,
  informing the user they must initiate sync. The Wear (Flutter) client inherits
  this requirement when the cloning job runs; it is not built here.
- Edge case of: none.

## Iteration 1

### Phase 1: Transport implementation (iOS only)
**Handoff: @developer**

#### iOS (`watch_connectivity` + MethodChannel)
1. [ ] Add `watch_connectivity` to pubspec.yaml (pub.dev package wrapping WCSession)
2. [ ] Create `lib/core/platform/watch_transport.dart`:
   - `abstract interface class WatchSyncTransport` and `WatchMirrorTransport` are
     already defined in `lib/watch/start/` and `lib/state/watch/`.
   - Implement `WatchConnectivityTransport implements WatchSyncTransport, WatchMirrorTransport`.
   - Use `WatchConnectivity.messageStream` for inbound; `.sendMessage()` for outbound.
   - Handle reachability via `WatchConnectivity.isReachable`.
   - No app-layer queueing; rely on platform retries.
3. [ ] Create `lib/core/platform/no_watch_transport.dart`:
   - `_NoWatchTransport` — no-op stubs for non-iOS.
   - All sends complete silently (resolve futures immediately).
4. [ ] Add MethodChannel initialization in `ios/Runner/GeneratedPluginRegistrant.swift`
      (auto-generated by Flutter; ensure `watch_connectivity` is built).

#### Android / Wear OS — OUT OF SCOPE
Not built in this plan. The user's decision is to prove the Apple path on
hardware first and clone it afterwards. Do not add `flutter_wear_os` or a
`WearTransport` here. The only requirement Phase 1 carries forward is that the
transport interfaces stay free of any iOS-specific or package-specific type, so
the Wear implementation slots in later without reopening the contract.

#### Shared
1. [ ] Add `lib/core/utils/platform_watch_transport_factory.dart`:
   - Single source of truth for which transport to use.
   - Check `defaultTargetPlatform` or `Platform.isIOS`.
   - Return `WatchConnectivityTransport` on iOS and `_NoWatchTransport` on every
     other platform, Android included. Android gets a real transport when the
     Wear cloning job runs, not before.
2. [ ] Test harness (`lib/core/platform/test_watch_transport.dart`):
   - Mock the transport for unit tests.
   - Override in `test/helpers/` for suites that need controlled message delivery.

**Done Criteria** (run until green):
- `flutter analyze` on `lib/core/platform/` — no errors.
- `flutter test test/watch_transport_test.dart` — send/receive paths work in
  mock; no platform package errors.
- `flutter build ios --release` — no MethodChannel registration errors.
- `flutter build apk` — the Android build still succeeds with the null-object
  transport (no Wear implementation exists yet; this proves the environment-safety
  contract in CLAUDE.md is intact).

**Predicted Files**:
- `lib/core/platform/watch_transport.dart` (new)
- `lib/core/platform/no_watch_transport.dart` (new)
- `lib/core/utils/platform_watch_transport_factory.dart` (new)
- `pubspec.yaml` (add `watch_connectivity`)
- `test/watch_transport_test.dart` (new)
- `ios/Podfile` (dependency specification; auto-updated by `flutter pub get`)
- `ios/Runner.xcodeproj/project.pbxproj` (auto-updated by Flutter)

---

### Phase 2: Production DI wiring in main.dart
**Handoff: @developer**

1. [ ] Update `lib/main.dart`:
   - Import `platform_watch_transport_factory`.
   - After constructing the repo and state instances, add:
     ```dart
     final watchTransport = await platformWatchTransportFactory();
     final liveSession = watchTransport is _NoWatchTransport
       ? null
       : LiveSessionMirrorState(
           sessionId: workoutState.session?.id,
           repository: repository,
           transport: watchTransport,
         );
     ```
   - Pass `liveSession: liveSession` to `MyApp` constructor.
   - Wrap in try-catch: if transport construction fails, log and continue with null.

2. [ ] Update `lib/app.dart`:
   - Verify `MyApp.liveSession` field exists (it does; already declared at `:48`).
   - Verify home screen uses it (existing code at `:161`).

3. [ ] Wire `WatchIncomingRouter` on the phone side:
   - Create `lib/state/watch/watch_incoming_router.dart` if it does not exist
     (plan 12 added it; verify it exists).
   - Router receives all incoming messages and dispatches to:
     - `LiveSessionMirrorState.receive` (session-scoped, with session ID check)
     - `WatchNutritionLogBridge.receive` (nutrition quick-logs, regardless of session)
   - Both are non-nullable; the router asks both.

4. [ ] Update the transport callback (phone side):
   - `WatchConnectivityTransport._onMessage` (or platform equivalent) calls
     `WatchIncomingRouter.receive`.
   - Router's results are logged (success/rejection).

**Done Criteria** (run until green):
- `flutter analyze lib/main.dart lib/app.dart` — no errors.
- `flutter test test/main_di_test.dart` (or equivalent integration test) — DI
  graph constructs successfully; `liveSession` is non-null on mock iOS, null on
  mock web.
- `flutter run -d <iOS device>` — app launches; no crashes on transport
  initialization.

**Predicted Files**:
- `lib/main.dart` (modified)
- `lib/app.dart` (no changes expected; verify field is used)
- `lib/state/watch/watch_incoming_router.dart` (verify exists; no changes if
  already complete)
- `test/main_di_test.dart` (new or extended)

---

### Phase 3: `routines_down` producer in WatchReferenceSync
**Handoff: @developer**

1. [ ] Extend `lib/core/utils/watch_reference_sync.dart`:
   - Add `buildRoutinesDown` method.
   - Signature: `static Map<String, Object?> buildRoutinesDown(List<Routine> routines, List<Exercise> recentExercises)`.
   - Traversal:
     - For each routine: segments → efforts → encode each effort's metrics and
       modality.
     - Each effort row includes: `effortId`, `segmentId`, `routineId`, `exerciseId`,
       `modality`, `metrics` (e.g., `reps`, `loadKg`, `timeSeconds`).
     - Fallback: all exercises referenced + recent exercises (same logic as
       `buildFoodsDown`).
   - Shape: `{ routines: [...], fallbackExercises: [...] }` per schema.
   - Modality is read from `Exercise.modality` at sheet-build time, not inferred.

2. [ ] Verify schema: `watch/sync_protocol/schemas/messages/routines_down.schema.json`:
   - Should exist (plan 05 or later).
   - Effort rows carry `modality` as an enum string (e.g., `"resistance_lifting"`,
     `"isometric_stretching"`).
   - Validator rejects if an exercise is in routines but not in fallback
     (`semantic_violation` — plan 05 requirement).

3. [ ] Extend `buildAll` (or create it) as a public entry point:
   - Call `buildRoutinesDown` and `buildFoodsDown`.
   - Returns `{ routines_down: Map, foods_down: Map }` (or sends both).
   - Called from production (TBD: where exactly; see Phase 4).

4. [ ] Add unit tests:
   - `test/watch_reference_sync_test.dart` (extend if exists):
     - Fixture: phone-side routine structure (Chest, Cardio, Yoga).
     - Assert `buildRoutinesDown` produces correct payload shape.
     - Assert modality is present and matches input.
     - Assert fallback covers all references (no semantic_violation).
   - Parity test: phone `Routine` structure matches watch-deserialized `WatchRoutineRecord`.

**Done Criteria** (run until green):
- `flutter analyze lib/core/utils/watch_reference_sync.dart` — no errors.
- `flutter test test/watch_reference_sync_test.dart` — 5+ test cases pass (one
  happy path, one modality, one fallback coverage, one parity).
- Schema validation: `test/sync_protocol_fixtures_test.dart` — any hand-written
  `routines_down` fixtures in `watch/sync_protocol/fixtures/valid/` pass; any
  invalid fixtures are rejected with stated reasons.

**Predicted Files**:
- `lib/core/utils/watch_reference_sync.dart` (modified, add `buildRoutinesDown`)
- `test/watch_reference_sync_test.dart` (new or extended)
- `watch/sync_protocol/schemas/messages/routines_down.schema.json` (verify
  exists; no changes expected)

---

### Phase 4: Watch-initiated sync — phone responds to routine request (D-7)
**Handoff: @developer**

Per D-7: Watch initiates sync with explicit user action; phone responds.

#### Phone side

1. [ ] Wire `WatchSyncOrchestrator.requestRoutines` to have a handler:
   - When the watch sends a request for routines, the phone's incoming router
     must dispatch it to a handler.
   - Handler: build `routines_down` via `WatchReferenceSync.buildRoutinesDown`
     (from Phase 3) and send it via transport.
   - Add this handler to `lib/state/watch/watch_incoming_router.dart` (or create
     a corresponding handler if router architecture differs).

2. [ ] Update docs:
   - `docs/state_management/services_and_utils.md` — note that
     `WatchReferenceSync.buildRoutinesDown` is called on-demand in response to
     watch request, not proactively on phone launch.

#### Watch side

3. [ ] Ensure watch app entry point includes a UI label stating "no automatic sync":
   - `WatchStartScreen` or the routine picker must display a label informing the
     user that routines are not automatically synced; user must request them.
   - Label is visible in both watchOS (SwiftUI) and Wear OS (Flutter) clients.
   - This is a requirement per D-7 and S-010.

4. [ ] Verify `WatchSyncOrchestrator.requestRoutines` sends the request:
   - Ensure the request is wired to a user-initiatable action (e.g., "Sync
     routines" button).
   - Request is sent to phone transport.

5. [ ] Watch side (`lib/watch/start/watch_sync_orchestrator.dart`):
   - Verify `case 'routines_down'` exists in message dispatch.
   - Route to `WatchSessionStore` to persist the payload.

**Done Criteria** (run until green):
- `flutter analyze` — no errors.
- `flutter test test/watch_session_engine_test.dart` — watch-side routing of
  `routines_down` works (apply, persist to store).
- UI test or visual inspection: watch home/picker screen shows "no automatic
  sync" label.
- End-to-end: device run on iOS with watch paired, user taps "Request routines"
  button, phone receives request, sends `routines_down`, watch persists.

**Predicted Files**:
- `lib/state/watch/watch_incoming_router.dart` (modified, add request handler)
- `lib/watch/start/watch_start_screen.dart` or analogous (modified, add label)
- `docs/state_management/services_and_utils.md` (modified, update docs)
- `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` (modified, add label)

---

### Phase 5: Cross-stack reconciliation conformance test
**Handoff: @developer**

1. [ ] Create `test/watch_reconciliation_cross_stack_test.dart`:
   - Load the existing protocol fixtures from `watch/sync_protocol/fixtures/reconciliation/`.
   - For each fixture:
     - Construct a `SyncSessionReconciler` on the phone side.
     - Construct a `WatchSessionEngine` in memory (Dart, not native Swift).
     - Apply the same snapshot and event stream to both.
     - Assert identical structure state:
       - Exercise list (exerciseId, sessionExerciseId, index).
       - Current position.
       - Revision counter.
       - Timer state (if applicable).
     - Assert no exceptions on either side.

2. [ ] If any divergence is found, this phase opens a remediation sub-phase to
   unify the logic (unlikely; both were written from the same protocol spec).

3. [ ] Mark both `SyncSessionReconciler` and `WatchSessionEngine` with a comment:
   ```dart
   // Cross-stack conformance verified by test/watch_reconciliation_cross_stack_test.dart
   // Do not change these rules without running that test.
   ```

**Done Criteria** (run until green):
- `flutter test test/watch_reconciliation_cross_stack_test.dart` — all fixtures pass.
- No divergences found.
- Comment is in place on both implementations.

**Predicted Files**:
- `test/watch_reconciliation_cross_stack_test.dart` (new)
- `lib/core/sync_protocol/session_reconciler.dart` (add comment)
- `lib/watch/session/watch_session_engine.dart` (add comment)

---

### Phase 6: Plan 05 Phase 3 / Release-ready gate
**Handoff: @dba (coordinator) — verification and administrative closure**

1. [ ] Verify plan 05 is updated:
   - Phase 3 is complete.
   - Release-ready is checked.
   - All watch code is now gated (plan 05's gate applies to plans 06–12).

2. [ ] Run the full watch test suite:
   - `flutter test test/sync_protocol_fixtures_test.dart` (plan 05 tests).
   - `flutter test test/watch_session_engine_test.dart` (plan 06).
   - `flutter test test/watch_nutrition_quick_log_test.dart` (plan 12).
   - `flutter test test/watch_reconciliation_cross_stack_test.dart` (new, phase 5).
   - `swift test` in `watch/watchos` (plans 05–12 watchOS equivalents).

3. [ ] Verify CI gate is in place:
   - `.github/workflows/` has a step that runs all the above.
   - The full suite is part of `pre_release_check.sh` or equivalent.

**Done Criteria** (run until green):
- All watch suites pass.
- CI gate is configured.
- Plan 05 is marked complete.

**Predicted Files**:
- `2026-07-13-05-pr4-watch-phone-sync-protocol-plan.md` (update status)
- `.github/workflows/*.yml` (if CI gate needs changes; likely not)

---

### Phase 7: Manual Human Work — watchOS App Target Creation
**Handoff: @human (engineer with Xcode access)**

This section is not executed by an agent. It documents every step a human must
take to build the real watchOS app.

#### Prerequisites
- Xcode 15+ (or current supported version for Swift 5.9).
- Apple Developer Account with team ID.
- iOS provisioning profile for the main app.
- watchOS simulator runtime installed (`xcrun simctl list runtimes` should show
  a watchOS entry; if not, Xcode → Settings → Platforms → Download watchOS).
- At least one physical Apple Watch for testing (paired via Settings app).

#### Steps (in order)

**Step 0 (agent-executable, before Xcode):** Update the Swift Package to support watchOS
- Edit `watch/watchos/Package.swift`.
- Change `platforms: [.macOS(.v13)]` to `platforms: [.macOS(.v13), .watchOS(.v9)]`
  (or appropriate watchOS version).
- This allows the watch target to link `WatchSessionEngine`.

**Step 1 (human):**

1. **Create the watchOS App Target**
   - In Xcode, open `ios/Runner.xcodeproj`.
   - In Xcode, File → New → Target.
   - Select "watchOS → App".
   - Name: `Runner Watch` (or `OmniTrain Watch`).
   - Ensure "Include Complication Kit" is OFF (not needed).
   - Add to project: `Runner`.
   - Create.

2. **Configure Bundle Identifier and Team**
   - Select the `Runner Watch` target.
   - Go to Build Settings.
   - Search for "Bundle Identifier".
   - Xcode's template should auto-generate a watch-app bundle ID with the
     `.watchkitapp` suffix (e.g., if main is `com.example.omnitrain`, watch is
     `com.example.omnitrain.watchkitapp`). **Do not manually change this suffix;**
     use what Xcode generates.
   - Verify the watch app's Info.plist contains `WKCompanionAppBundleIdentifier`
     set to the main app's bundle ID (e.g., `com.example.omnitrain` exactly).
   - Set Team ID to the same as the main app.

3. **Create App Groups** (optional, conditional on D-1 transport choice)
   - If D-1 specifies shared-container message queueing, create App Groups:
     - Main app (`Runner` target):
       - Signing & Capabilities → + Capability → App Groups.
       - Add group: `group.com.example.omnitrain` (use your bundle ID).
     - Watch app (`Runner Watch` target):
       - Signing & Capabilities → + Capability → App Groups.
       - Add the same group.
   - **Purpose**: allows both apps to share files in a common container, used by
     `WCSession` for message delivery queuing.
   - **Note**: If using the standard `watch_connectivity` pub package, App Groups
     are not strictly necessary; `WCSession` handles buffering natively. Skip this
     step if transport implementation does not require it.

4. **Verify Bundle ID Relationship (for WCSession)**
   - `WCSession` pairing is automatic based on bundle-ID prefix matching. No
     Xcode capability is required.
   - Verify: Watch app's bundle ID is a subdomain of the main app's (e.g., main
     is `com.example.omnitrain`, watch is `com.example.omnitrain.watchkitapp`).
   - If pairing fails at runtime, check:
     - `WKCompanionAppBundleIdentifier` in watch's Info.plist matches main app
       exactly.
     - Both apps are signed with the same Apple Developer account.
     - Watch is paired via Settings → General → Bluetooth on the iPhone.

5. **Create Provisioning Profiles**
   - On [developer.apple.com](https://developer.apple.com):
     - Create a new Identifiers entry for the watch app's bundle ID
       (e.g., `com.example.omnitrain.watchkitapp`).
     - Capabilities: If you created App Groups (step 3), add that capability.
       App Intents and other features can be added as needed.
     - Create a new Provisioning Profile (watchOS, distribution or development
       depending on your needs).
     - Download and double-click to install on your Mac.
   - In Xcode, Preferences → Accounts → select team → Download Manual Profiles.

6. **Add HealthKit Entitlements and Background Modes (required for sensor recording in Phase 8)**
   - `Runner Watch` target → Signing & Capabilities.
   - + Capability → HealthKit. Select "Read" and "Write".
   - + Capability → Background Modes. Select "Workout Processing" — this prevents
     the app from suspending when the watch drops and is critical for continuous
     session recording.
   - In `ios/Runner Watch/Info.plist`, add health description strings:
     ```xml
     <key>NSHealthShareUsageDescription</key>
     <string>OmniTrain needs access to your health data to record workout sessions on your watch.</string>
     <key>NSHealthUpdateUsageDescription</key>
     <string>OmniTrain records workout activity and effort data from your workouts.</string>
     ```
   - (Adapt the strings to match your app's user-facing language.)

7. **Wire the Swift Package Dependency**
   - `Runner Watch` target → Build Phases → Link Binary With Libraries.
   - Add `WatchSessionEngine` (the Swift Package from `watch/watchos/`).
   - (Xcode may auto-detect this; verify it is there.)

8. **Create the App Entry Point**
   - Create `ios/Runner Watch/WatchApp.swift`:
     ```swift
     import SwiftUI
     import WatchSessionEngine

     @main
     struct OmniTrainWatchApp: App {
         var body: some Scene {
             WindowGroup {
                 WatchStartView()
             }
         }
     }
     ```
   - (Adapt `WatchStartView()` to your implementation.)

9. **Build and Test on Simulator**
   - In Xcode, select a simulator (e.g., "Apple Watch Series 8 42mm").
   - Product → Build.
   - No crashes on launch (if you see crashes, check simulator logs).

10. **Test on Physical Device**
    - Pair a watch via the Settings app on a real iPhone.
    - In Xcode, select the iPhone + watch from the device menu.
    - Product → Build and Run.
    - Watch app should launch.

#### Checklist for the Coordinator

- [ ] `watch/watchos/Package.swift` has been updated to include watchOS platform.
- [ ] watchOS target `Runner Watch` exists in `ios/Runner.xcodeproj`.
- [ ] Bundle identifier follows Xcode's convention (e.g., `<main>.watchkitapp`).
- [ ] Watch app's Info.plist contains `WKCompanionAppBundleIdentifier` = main app bundle ID exactly.
- [ ] App Groups entitlement (if needed by transport) is present on both main and watch targets.
- [ ] HealthKit and Background Modes capabilities are present on watch target.
- [ ] Health description strings are added to watch's Info.plist.
- [ ] Provisioning profiles are downloaded and installed (correct bundle IDs).
- [ ] `WatchSessionEngine` Swift Package is linked.
- [ ] `WatchApp.swift` entry point exists.
- [ ] Build succeeds on simulator and device.
- [ ] Tests pass: `xcodebuild test -scheme Runner Watch -destination 'platform=watchOS Simulator'`.

Added by `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md` (Stats PR 2, O-1) —
the app shell's part of wrist capture, which PR 2 built as package code with no shell to host it:

- [ ] The shell hosts the End control (`WatchEndSessionView`) and the effort-rating prompt
  (`WatchEffortRatingView`), both bound to `WatchEffortRatingState` (PR 2 D-119).
- [ ] An owed prompt is presented at launch, before any other surface (PR 2 D-117; the owed prompt
  is stored, `WatchRatingPromptRecord`).
- [ ] `pruneConfirmed` and `pruneSettledSensorSamples` are scheduled only while no session is
  active. Pruning a running session's confirmed rows changes values the wrist derives from them,
  such as the next round number (PR 2 F-10).
- [ ] The protocol schemas are bundled for the Swift validator.
- [ ] `preferences_down` is carried over the transport to `WatchSyncOrchestrator`, which routes it
  to `WatchPhonePreferences` (PR 2 D-113).
- [ ] The engine and its store are written by one actor. This one is a package change, not only a
  shell change: the recorder's per-stream tasks and its write chain (`WatchSensorWrites`, and
  `consume(_:onElement:)` above it, in `WatchSensorRecording.swift`) run without actor isolation,
  so the UI and that chain can still write at once (PR 2 A-35; PR 2 review F-11).
- [ ] The durable store reloads payload integers as integers (a reload-then-validate test): the wrist
  validates its own emissions, which refuse whole-number doubles, so a store that widens them breaks every
  resend after a relaunch (PR 2 re-review N9).

#### Notes for the Developer

- MethodChannel communication: the watch app will send/receive messages via
  `WCSession` automatically (bridged by the `watch_connectivity` pub package on
  the Flutter side).
- App Groups: both the Flutter app and the native watch app read/write to
  `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`.
  This is where the Flutter app can place reference data (routines, foods) for
  the watch app to pick up without a message.
- Certificates: provisioning profiles expire; test builds can use development
  profiles; TestFlight and App Store require distribution profiles.

---

### Phase 8: Sensor Recording — blocked on Phase 7
**Handoff: blocked, opens only after Phase 7 is human-complete.**

Once the watchOS app target exists:

1. [ ] Implement `WatchPlatformWorkoutStore` in Swift.
   - Use HealthKit `HKWorkoutBuilder` to record samples.
   - Samples are app-internal; no sync to HealthKit back-end.

2. [ ] Wire into `WatchSessionEngine._recordSensorSample`.

Added by `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md` (Stats PR 2, O-2):

3. [ ] Bind `WatchSensorSource`'s steps permission and cumulative steps stream to the live workout
   builder's step count, and its heart-rate stream to HealthKit (PR 2 D-106, D-125).
4. [ ] Measure sample delivery latency against log time. PR 2 computes an entry's heart rate and
   steps when it is logged (D-121); if late samples drop a material slice of the window, add a
   grace wait before computing.
5. [ ] Verify the step counter's restart after a workout recovery is read as a new count (D-125).
6. [ ] On-device verification of the summaries needs a way to inspect the imported
   `SensorSummary` rows: the phone has no display for them yet (Stats pack O-2).

This phase is documented here for completeness but does not proceed until the
watchOS app target is built and running.

---

## Deferred: Wear OS / Android

**Scope decision (Q-2):** This plan ships iOS/watchOS only. Wear OS is deferred to
a follow-on plan after the Apple path is proven. This section records ground truth
so the cloning job is efficient.

### Why deferred

- Building both simultaneously would add complexity to this plan and dual Device
  setups to testing (watchOS simulator + Wear emulator or physical watches).
- The Dart side (`lib/watch/`) and Swift side (`watch/watchos/`) are already
  contract-tested against each other via `watch/contract/*.json` fixtures, so
  behavior parity is proven before implementation.
- Proving the Apple path first allows the Wear implementation to clone without
  re-solving the sync-protocol or reconciliation engine questions.

### Ground truth for the follow-on plan

**Android / Gradle structure:**
- `android/settings.gradle.kts` currently contains only `include(":app")`.
- No Wear OS module exists; will need to be created in a follow-on plan.
- `android/app/src/main/AndroidManifest.xml` has no
  `<uses-feature android:name="android.hardware.type.watch" />` feature.

**Dart / Wear client:**
- `lib/watch/` is the Wear OS client library (Dart, contract-tested against Swift).
- No production Dart entry point exists; only four debug harnesses:
  - `lib/state/watch/live_session_mirror_debug_main.dart`
  - `lib/watch/debug/watch_logging_debug_main.dart`
  - `lib/watch/debug/watch_session_debug_main.dart`
  - `lib/watch/debug/watch_start_debug_main.dart`
- The follow-on plan will create `lib/watch/wear/wear_main.dart` (production
  entry point) and a Gradle Wear module.

**Sensor path (Wear):**
- `lib/watch/sensors/watch_platform_workout.dart` documents the sensor seam.
- Wear OS implementation will use Health Connect (or Google Fit for older
  devices), per `watch/contract/watch_sensor_contract.json` (which names
  `WatchActivityType.wear` and `EXERCISE_TYPE_*`).
- `WatchPlatformWorkoutStore` will be implemented for Android/Wear after it is
  done for watchOS/Swift.

**Contract fixtures:**
- `watch/sync_protocol/fixtures/` — protocol conformance (reused by Wear).
- `watch/contract/watch_nutrition_contract.json` — nutrition syncing contract.
- `watch/contract/watch_sensor_contract.json` — sensor recording contract (names
  Wear's sensor types).

### What the follow-on plan will do

1. Create `android/wear/` module and Gradle structure.
2. Add `<uses-feature android:name="android.hardware.type.watch" />` to manifest.
3. Create `lib/watch/wear/wear_main.dart` (production entry point).
4. Implement `WearTransport` (Dart, wrapping platform APIs).
5. Implement `WatchPlatformWorkoutStore` for Wear OS (Health Connect or Google Fit).
6. Wire production DI similar to Phase 2, but for Wear instead of iOS.
7. Test on Wear emulator and physical Wear OS devices.

---

## Manual Human Work (Apple Xcode / watchOS)

**This is Apple-only.** See Phase 7 above for the complete watchOS checklist.
Wear OS is deferred; see "Deferred: Wear OS" section.

**Agent prerequisite (Phase 7 Step 0):** `watch/watchos/Package.swift` must be
updated to include watchOS platform before Xcode work begins. This is
agent-executable and happens automatically in the handoff.

**Human steps (Phase 7, steps 1–10):**
- Create watchOS app target in Xcode.
- Configure bundle ID (using Xcode's `.watchkitapp` suffix), team, and
  WKCompanionAppBundleIdentifier.
- Create provisioning profiles with correct bundle IDs.
- Add HealthKit, Background Modes (workout-processing), and health description
  strings.
- Wire Swift Package dependency.
- Create app entry point.
- Test on simulator and device.

**Why it cannot be fully automated:**
- Xcode project files (`.pbxproj`) are plain text (NeXT plist format), but they
  are generated, densely cross-referenced by UUID, and easily corrupted by
  hand-editing, so Xcode is the safe editor.
- Provisioning profiles require authenticated access to the Apple Developer
  portal.
- Physical device testing requires human pairing of watch and iPhone.
- Signing and certificate management are inherently human.

**Hands-on time**: ~30 minutes for an engineer familiar with iOS development;
~2 hours for a first-timer (provisioning profile issues are common).

---

## Implementer Notes — Issues to Resolve

**1. Plank fixture's target may be invalid against the product model**

The user states: *"Effort targets don't belong to exercises, the only way to set
a target is to track any exercise through Sports modality, Cardio and Isometric
modalities are a count up, there is no target per se."*

The docs back this: `docs/my_routines.md` describes `TemplateTarget`
as a routine-level, per-metric-per-set value, not an exercise property.

But `watch/contract/watch_start_paths_contract.json` gives isometric Plank
`targets: {"holdMs": 60000}`, which contradicts "isometric is count-up, no target."

**Resolve this against the docs and the model before building on the fixture.** If
the fixture is wrong, fixing it changes what both watch suites assert, so it is a
real piece of work and needs its own scenario.

**2. `targets` field is required on every effort, but not all modalities carry targets**

`watch/sync_protocol/schemas/messages/routines_down.schema.json` marks `targets`
as required on every effort. If cardio and isometric genuinely carry no targets,
the schema forces an empty object `{}` on them.

**Confirm that is intentional**, or note it as a protocol item to revisit.

**3. Docs gap — count-up behavior not documented**

The count-up rule for cardio and isometric modalities — stated by the user as
product behavior — is not written down. `grep -i "count up\|count-up\|no target"`
across `docs/modality_tracking.md` and `constants_reference.md`
returns nothing.

Per CLAUDE.md's per-phase doc-update rule, whichever phase touches effort kinds
(likely Phase 4 or Phase 5) should record this behavior: "Cardio and isometric
modalities do not carry effort targets; they are count-up modalities."

---

## Files Affected (whole feature)

### Transport Layer (new)
- `lib/core/platform/watch_transport.dart`
- `lib/core/platform/no_watch_transport.dart`
- `lib/core/utils/platform_watch_transport_factory.dart`

### DI Wiring (modified)
- `lib/main.dart`
- `lib/app.dart` (verify only)

### Reference Data Producer (extended)
- `lib/core/utils/watch_reference_sync.dart`

### Test Infrastructure (new)
- `test/watch_transport_test.dart`
- `test/watch_reference_sync_test.dart` (extended)
- `test/watch_reconciliation_cross_stack_test.dart`

### Documentation (modified)
- `docs/state_management/services_and_utils.md`

### Plan Files (updated)
- `2026-07-13-05-pr4-watch-phone-sync-protocol-plan.md` (Phase 3 closure)
- `2026-09-21-13-watch-integration-shipping.md` (this file)

### Xcode Project (Phase 7 — human work)
- `ios/Runner.xcodeproj/project.pbxproj` (add watch target)
- `ios/Runner Watch/WatchApp.swift` (new)

---

## Notes

### Phase dependency graph

```
Phase 1 (Transport) → Phase 2 (DI wiring)
                   ↘ Phase 3 (routines_down)
                    ↘ Phase 4 (sync trigger)
                     ↘ Phase 5 (cross-stack test)
                      ↘ Phase 6 (gate closure)
                       Phase 7 (manual watchOS target)
                        ↘ Phase 8 (sensor recording)
```

All phases except 7 can run in parallel up to Phase 6. Phase 7 is blocking Phase
8 but independent of Phases 1–6. Phase 7 also includes a Step 0 (agent-executable)
that updates `watch/watchos/Package.swift` before the human Xcode work begins.

### Intermediate States

**After Phase 1**: Transport interface is implemented but untested on device.

**After Phase 2**: DI wiring is in place; `MyApp.liveSession` is non-null on
iOS; the app still builds and tests on web.

**After Phase 3**: `routines_down` builder exists; no sync is triggered yet.

**After Phase 4**: Production sync is live; the watch receives routines on each
app launch.

**After Phase 5**: Cross-stack reconciliation test is in place; CI will catch
engine drifts.

**After Phase 6**: Plan 05 is formally closed; all watch code is gated.

**After Phase 7 Step 0** (agent, pre-human): `watch/watchos/Package.swift` now
supports watchOS platform; watch target can link the library.

**After Phase 7** (human-complete): watchOS app target is built, provisioned,
and tested on simulator and device.

**After Phase 7**: watchOS app target is built and tested on real hardware.

**After Phase 8**: Sensor recording is live (future work; not in this plan).

### Legacy Handling

Debug harness (`lib/watch/debug/watch_start_debug_main.dart`) continues to work
unchanged. It constructs its own test-double transports and remains available
for QA.

### Assumptions made in this plan (vetoable)

1. **D-1**: `watch_connectivity` pub package for iOS transport is preferred
   (wrapping WCSession); if it is retired or unsuitable, the decision is
   hand-rolled MethodChannel + native WCSession layer. This assumes the package
   is maintained. Wear OS is deferred and will use a different transport (Wear
   Data Layer or equivalent) in a follow-on plan.

2. **D-2**: Platform detection via `Platform.isIOS` is acceptable for DI. The
   app already uses this pattern elsewhere.

3. **D-3**: Modality encoding in `routines_down` payload is the right level of
   specificity (per effort, not per exercise). This assumes the protocol schema
   supports it.

4. **D-4**: A conformance test is sufficient for preventing engine drift; no
   need to unify the implementations now. This assumes the protocol fixtures
   are comprehensive enough to catch divergence.

5. **Phase 7 is human work**: No automation. This assumes the engineer has Xcode
   and Apple Developer account access.

---

## Progress

**Pre-implementation baseline (2026-09-21):**
- Dart test suite: `flutter test` = 2778 passed, 1 skipped, 0 failed
- watchOS test suite: `swift test` in `watch/watchos/` = 146 passed, 0 failed
- These are the baseline values against which to detect phase regressions.
- **Note**: watchOS simulator runtime must be installed before Phase 7
  begins; this machine lacks it (`xcrun simctl list runtime` shows iOS 26.4
  only).

**Iteration 1 status (2026-09-21): Phases 1–5 Complete; Phase 6 partially
blocked (see Feedback); Phase 7 Step 0 Complete, human steps discovered to be
already in progress.**

### Phase 1 — Transport implementation ✓
- [x] `watch_connectivity` added to `pubspec.yaml` (pinned `^0.2.8` — 0.2.9+
      requires Dart SDK ≥ 3.12 and this toolchain is 3.11.5)
- [x] `lib/core/platform/watch_transport.dart` — `WatchMessageChannel`,
      `WatchTransport`, `WatchConnectivityTransport`, `WatchTransportRequest`
- [x] `lib/core/platform/watch_connectivity_channel.dart` — the only file that
      imports the package
- [x] `lib/core/platform/no_watch_transport.dart` — `NoWatchTransport`
- [x] `lib/core/utils/platform_watch_transport_factory.dart` —
      `createPlatformWatchTransport`
- [x] `test/watch_transport_test.dart` — 16 tests green (11 at first pass; 5
      added in the review round to close the acceptance-criteria gaps)
- Note: the plan's predicted three files became four; the package import is
      isolated in its own file rather than sitting in `watch_transport.dart`, so
      `watch_transport.dart` stays package-free.
- Note: no `MethodChannel` registration was needed in
      `GeneratedPluginRegistrant.swift`; Flutter generates it from the plugin.

### Phase 2 — Production DI wiring ✓
- [x] `lib/state/watch/watch_sync_wiring.dart` — `createWatchSync`,
      `watchSessionPlaceholder` (the `WatchSync` wrapper was deleted in the
      review round — see A-14)
- [x] `lib/state/watch/watch_sync_request_handler.dart` — the request branch
      (separate from `WatchIncomingRouter`; see Assumption Log)
- [x] `lib/main.dart` — builds the graph, passes
      `liveSession: watchSync?.mirror`, reports construction failure through
      `debugPrint` + `CrashReportingService`-adjacent startup logging
- [x] `lib/app.dart` — unchanged, field was already declared and used
- [x] `test/watch_transport_test.dart` covers the DI decision (S-006)

### Phase 3 — `routines_down` producer ✓
- [x] `WatchReferenceSync.buildRoutinesDown` — takes the repository and
      assembles from storage on demand
- [x] `test/watch_reference_sync_test.dart` — 8 tests green, payload judged by
      the shared schema validator and read back through `WatchRoutinesDown`
- Note: `buildAll` was not created. Nothing calls for both lists at once, and
      the foods half has its own caller.

### Phase 4 — Watch-initiated sync ✓
- [x] Phone answers `WatchTransportRequest.routines` (Phase 2's handler)
- [x] Watch label + sync action: `WatchStartScreen` gained `onRequestSync` and
      `NoAutomaticSyncHint`; watchOS gained `WatchStartSurfaceCopy` +
      `WatchNoAutomaticSyncHint`
- [x] The label's text and the action's label are pinned in
      `watch/contract/watch_start_paths_contract.json` (`startSurface`), so both
      clients fail together if either drifts
- [x] D-6 delivered here: the routine's declared `effortKind` travels on the slot
      (`envelope.schema.json` `sessionExercise`), the wrist renders it, and
      `effortKindParity` now means "the rule for a slot with no declared kind"

### Phase 5 — Cross-stack conformance ✓
- [x] `test/watch_reconciliation_cross_stack_test.dart` — 13 tests green over
      all 12 reconciliation fixtures; no divergence found
- [x] Both engines carry the pointer comment

### Phase 6 — Plan 05 closure — Complete
- [x] Full watch suites run: fixtures 100%, session engine 100%, nutrition
      100%, cross-stack 100%, watchOS `swift test` 148/148
- [x] Dart suite: **2817 passed, 1 skipped, 0 failed** (baseline was 2778)
- [x] **Gate suites green** — `pre_release_gate_ios_artifact_test.dart` +
      `pre_release_gate_notification_and_build_test.dart`, 20/20
- [x] Gate script fixed: the two app-identity checks were reading the whole
      `project.pbxproj`, so the watch app target (added in Phase 7) made them
      report the watch app's own bundle id and `TARGETED_DEVICE_FAMILY = 4` as
      iPhone-app regressions. Both checks are now scoped to the Runner app's
      configuration lists (`runner_pbxproj_settings`), which is what their
      messages always claimed. See Assumption Log A-12.
- [x] `./scripts/pre_release_check.sh --fast` on this host reports one remaining
      blocking error — "no IPA at build/ios/ipa/*.ipa" — which is correct and
      expected: it refuses to pass an artifact check when no archive has been
      built. It clears on the machine that runs `flutter build ipa` before
      archiving.
- [ ] Plan 05's Phase 3 / release-ready box not updated — needs the DBA
      handoff in this phase.

### Phase 7 — watchOS app target
- [x] **Step 0 (agent)**: `watch/watchos/Package.swift` declares
      `platforms: [.macOS(.v13), .watchOS(.v9)]`; `swift test` still green
- Discovered mid-phase: a human has already created the target —
      `ios/OmniTrain Watch App/` exists (staged: `OmniTrainApp.swift`,
      `ContentView.swift`, `Assets.xcassets`), `Runner.xcodeproj` carries 16
      references to it, and `INFOPLIST_KEY_WKCompanionAppBundleIdentifier =
      dev.sasha.omnitrain` is set in all three build configurations. Remaining
      human steps (Swift Package link, HealthKit, background modes, provisioning,
      replacing the template `ContentView`) are still open.

### Phase 8 — Sensor recording
Not started; correctly blocked on Phase 7's remaining human steps.

---

## Assumption Log

**A-1 (Phase 1): `watch_connectivity` is pinned to `^0.2.8`, not `^0.2.10`.**
The plan named the latest version, but 0.2.9+ requires Dart SDK ≥ 3.12 and this
toolchain is 3.11.5. `^0.2.8` resolves and is API-compatible with what the
transport uses. Revisit when the SDK moves.

**A-2 (Phase 1): the platform package is imported in exactly one file.** The
plan's predicted `lib/core/platform/watch_transport.dart` would have held the
import; splitting `WatchConnectivityChannel` into its own file makes the
"interface free of package type" decision (D-1) structural rather than a
convention — `flutter analyze` fails if the import spreads.

**A-3 (Phase 1): requests are frames with no `type`.** PROTOCOL.md says a request
"is a transport concern and carries no message of its own". Rather than invent a
wire type (`routines_request`), `WatchTransportRequest` encodes requests as
`{request: <name>}` and `nameOf` decides which kind a frame is by the presence of
`type`. No schema, fixture, or validator change.

**A-4 (Phase 2): the mirror's placeholder has a valid but unheld session id.**
An empty `sessionId` was the first attempt and it broke the protocol: every
envelope the phone builds carries that id, and the schema requires a non-empty
string. `s-phone-unjoined` names no wrist session, so the mirror's existing
"not my session" rule ignores incoming session-scoped messages until a real
snapshot is adopted. Status stays `abandoned` so no session-less phone is
offered as live on the home panel.

**A-5 (Phase 2): the request branch lives in its own class, not in
`WatchIncomingRouter`.** The plan put it in the router; a request is not a
protocol message and the router's contract is explicitly about protocol
messages. `WatchSyncRequestHandler` keeps both honest, and
`watch_sync_wiring.dart` is the one place that decides which of the two a frame
goes to.

**A-6 (Phase 3): `buildRoutinesDown` returns null rather than an empty message.**
`routines_down` requires `minItems: 1` for both `routines` and
`fallbackExercises`, so a phone with nothing to send has no conformant message to
send. Null is the honest signal, and the caller (Phase 4's handler) sends
nothing.

**A-7 (Phase 3): capabilities come from `getExerciseCapabilities`, not from the
`Exercise` row.** The plan's signature implied `List<Exercise>`, but capabilities
live in their own table; `_ExerciseResolver` reads them once per exercise per
message and drops exercises that have none (the wrist cannot render an effort for
one).

**A-8 (Phase 4 / D-6): the declared effort kind travels on the slot, not in the
routine.** `routines_down.effort.effortKind` already existed but is the *plan's*
kind; what the wrist needed is the kind attached to the *slot it is logging*,
because that is what `WatchLoggingState` resolves from. Adding an optional
`effortKind` to `sessionExercise` was the smaller change and leaves every
existing fixture valid.

**A-9 (Phase 4 / D-6): `effortKindParity` in the contract now means "no declared
kind".** Its six rows are unchanged — they are still what a capability set
resolves to — but both suites' parity tests now assert them only for slots with
no declared kind, and `routineSession.expectedSlots` pins the declared-kind case
(including Plank → `timed`, which closes plan 08's open item 2 and the
`Plank: timed → drill` divergence that was previously recorded as accepted).

**A-10 (Phase 4): the plan's "After Phase 4: the watch receives routines on each
app launch" is superseded by D-7.** Nothing syncs on launch. The wrist's user
asks; the phone answers.

**A-11 (Phase 5): entries are excluded from the cross-stack comparison.**
`SyncSessionReconciler` absorbs `observations_up` because both devices' entries
merge in its model, while `WatchSessionEngine` is the device that *produced*
them and never applies its own. Comparing entry sets would fail every fixture
that carries a watch observation, for a reason that is not structural drift.
Ladder order, position, revision, status, and timer kinds are compared in full,
and the fixtures where the wrist does receive entries (via snapshot) are what
exercise that path.

**A-12 (Phase 6): two gate checks are now scoped to the Runner app's
configuration lists.** §6 (bundle identifier) and §11f (iPhone-only) both read
the whole `ios/Runner.xcodeproj/project.pbxproj`, which stops being "the iPhone
app" the moment a second target exists. `runner_pbxproj_settings` reads only the
configurations owned by `PBXNativeTarget "Runner"` and `PBXProject "Runner"`
(whose defaults Runner inherits), which is what §6's own message — "All **Runner**
configs must use the same bundle ID" — already claimed. The check's strength is
unchanged for the app: §6 still requires exactly one distinct bundle id across
all three Runner configs, and §11f still fails on any non-`1` family among them.
The scope is derived from the comment on each configuration list rather than a
hardcoded target name or id, so a renamed or re-created Runner target is picked
up; and if the scope comes back empty the script fails loudly rather than
passing both checks by having nothing to look at.

**Known gap this opens:** the watch app's own bundle identity is now unverified.
Before, §6 failing on two distinct ids was the only signal that a second target
existed — unhelpful, but it would have caught a typo in
`dev.sasha.omnitrain.watchkitapp`, and nothing does now. A wrong watch bundle id
breaks the companion relationship silently, which is the failure that would make
the whole feature refuse to install. The script already asserts
`INFOPLIST_KEY_WKCompanionAppBundleIdentifier = dev.sasha.omnitrain` in all
three watch configs, but not that the watch id is `<runner-id>.watchkitapp`.
Worth a follow-up check — not implemented here because it is new coverage for a
new target rather than repair of a regression, and it belongs to whoever scopes
the watch target's own invariants.

**A-13 (review round): Implementer Note 3's premise is contradicted by the
code, so nothing was documented.** The note asked for "cardio and isometric do
not carry effort targets; they are count-up modalities" to be written into
`modality_tracking.md`. `_buildMetricWidget` in
`lib/features/routine/routine_setup_screen.dart` gives `timed` an extra-weight
target and `drill` a hold-shaped one, and `set` and `round` their metric rows —
so all four kinds carry targets, and none is count-up-with-no-target. The note
is also where the Plank fixture disagreement in Note 1 came from: the fixture's
`targets: {"holdMs": 60000}` is consistent with what the editor writes.

**A-14 (review round): `WatchSync` is deleted.** It held one field, `mirror`,
and a `transport` nothing read — `main.dart` read `.mirror` and no test read
either. `createWatchSync` now returns the `LiveSessionMirrorState`, which is
what both callers wanted, and the wrapper is gone rather than documented as
useful.

---

## Feedback

**Resolved.** No blocking item remains in Phase 6.

The earlier note here blamed the gate-suite failures on an uncommitted
`pubspec.yaml`. **That diagnosis was wrong** and the commit made on the strength
of it was unnecessary. The gate suites do not run against the working tree: they
copy the repo, `git init` + commit it, and run the script there — so uncommitted
`pubspec.yaml` state never reaches them, and §4 was never the failing check.

The real cause was two app-identity checks reading the whole
`ios/Runner.xcodeproj/project.pbxproj`. Adding the watch app target gave that
file a second `PRODUCT_BUNDLE_IDENTIFIER` and three `TARGETED_DEVICE_FAMILY = 4`
values, so:

- §6 saw two distinct bundle ids where it had seen one;
- §11f saw a non-`1` device family where it had seen none.

Both are correct values for a watch app and neither is an iPhone-app
regression. The checks now read only the Runner app's configuration lists.
`pre_release_gate_ios_artifact_test.dart` +
`pre_release_gate_notification_and_build_test.dart` are 20/20.

**Lesson worth keeping:** the gate tests exercise a committed copy, so a red gate
suite can never be explained by "my work is uncommitted". Reproduce first.

**Not done, and deliberately so:** updating plan 05's Phase 3 / release-ready
box, which is this phase's `@dba` handoff.

---

### Iteration 1 review — addressed

The four documentation blockers and the four acceptance-criteria gaps from the
review are closed. What changed:

**Documentation (all four blockers):**

1. `services_and_utils.md` — "the four-member channel interface" → names
   `WatchMessageChannel`. The count is gone.
2. `services_and_utils.md` — "the wire's four words" → "the wire's" with the same
   examples. The count is gone.
3. `services_and_utils.md` — "the three request methods (`requestRoutines`,
   `requestSnapshot`, `send`)" → "the request calls". Both the count and the
   method list are gone.
4. `modality_tracking.md` — the "Only `set` and `round` efforts carry a target"
   section is **deleted, not repaired**. Checking `routine_setup_screen.dart`
   showed the premise was wrong: `_buildMetricWidget` gives a `timed` effort an
   extra-weight target and a `drill` effort a `hold`-shaped one, so all four kinds
   carry targets and none is "count-up with no target". Documenting it would have
   recorded a rule the code contradicts. The `services_and_utils.md` cross-link to
   that section went with it. See Assumption Log A-13 — and note that this
   resolves Implementer Note 3 in the opposite direction from how it was written.

Also fixed: `modality_tracking.md` gained the scope block it never had (it had
content added, which §4.1 makes a blocker), and `services_and_utils.md`'s scope
block now declares `lib/core/platform/`.

**Acceptance-criteria gaps — four new tests in `test/watch_transport_test.dart`:**

- **AC-6 (wrist quick-log reaches the phone's day log).** `S-002 a food
  quick-logged on the wrist lands in the phone's day log` — the wrist logs
  through its real `WatchNutritionState` over the real transport, and the phone's
  own `NutritionState.consumedToday` is where the row has to appear.
- **AC-6 (the receipt is a frame, not a return value).** `S-002 the phone's
  receipt comes back over the same radio` — asserts `link.phone.sent` holds the
  `receipt`, so the bridge's transport use is real.
- **The phone's snapshot branch.** `S-003 the wrist can ask the phone for its
  session` and `...a phone with no ladder answers a snapshot request with
  silence` — the second drives `_mirror.exercises.isEmpty`, which nothing did.
- **AC-5/AC-9 (S-009 over the transport).** `S-009 the wrist advances when the
  phone removes the current slot` — the wrist is on the middle slot, the phone
  issues a real `removeExercise`, and the wrist's ladder, position, and stored
  history are asserted. This is the first test in which a structural change
  travels as a message rather than as a fixture replayed into both engines.

**Negative checks (a passing test proves nothing until it can fail).** Both new
assertion groups were verified by breaking the code they cover:

- Forcing `_sendSnapshot` to return false → the snapshot test fails.
- Cutting `router.receive(frame)` out of the inbound dispatch → the nutrition
  test fails.
- Both mutations reverted; suite green.

**Dead code:** `WatchSync` is deleted rather than repaired. It was a one-field
wrapper around the mirror and nothing read the field. `createWatchSync` now
returns the `LiveSessionMirrorState` it builds, which is what both `main.dart`
and the tests actually wanted. `main.dart` reads `watchMirror` directly.

**Simplify pass on the newly-touched code:**

- `NoAutomaticSyncHint` and `SearchOnPhoneHint` were the same `Row` twice;
  extracted `WatchHintRow`, which owns the icon size the two were duplicating.
- `_wireEffortKind`'s `set`/`note` cases were redundant with its `default`;
  deleted.
- `WatchTransportRequest.routinesFrame` used `if (x != null)` where every other
  map in the tree uses the null-aware element; aligned.
- `number * 1000` → `Duration.millisecondsPerSecond`, matching
  `watch_logging_state.dart`.
- `buildRoutinesDown` now delegates its fallback-list projection to
  `_fallbackJson`.
- `watch_start_screen.dart`'s header cited only plan 08; it now cites both.

**S-005's register entry** was rewritten: it named a MethodChannel transport that
D-1 replaced, and it had no satisfiable outcome for an agent. It now states the
outcome a human can check (the watch app launches on the simulator) and records
why no test can pin it.

**Still open, and not fixable here:** the five scope blocks outside this change's
documents. 33 of 38 documents under `docs/` still declare no scope.
That is pre-existing and repo-wide, and fixing it is its own job.

---

### Iteration 1 review, round 2 — addressed

All six findings closed. The code was not touched this round; every change is
prose or plan text.

**The two falsifications:**

1. `docs/watch-app-setup-and-qa.md` — `liveSession: watchSync?.mirror` →
   `liveSession: watchMirror`, matching `lib/main.dart:410`.
2. `state_management/services_and_utils.md` — the reason the builder skips a
   capability-less exercise is now the schema's, not the wrist's: `sessionExercise`
   requires `capabilities` with `minItems: 1`, so such a slot fails validation
   before any renderer sees it. The old wording was a D-6 casualty — it claimed
   the wrist must consult capabilities, which is exactly what D-6 stopped it
   doing for routine slots.

**The two missing verification pointers:** `WatchSyncRequestHandler` and
`createWatchSync` now each carry a "Verified by" line naming the cases that pin
them (S-003 for the request branch, S-006 for the platform decision, S-001 for
why the placeholder id must be valid rather than empty).

**The two incompletes:** the transport section's pointer now lists S-003 and
S-009 alongside S-001/S-002/S-006.

**D-6 is now documented.** New section in `modality_tracking.md`, "A routine's
slot carries the kind the routine declared" — the rule, the reason it exists, and
the fact that it is a fallback rather than a replacement (a slot with no declared
kind still resolves from capabilities, so free workouts and pushed exercises are
unchanged). It points at S-004 on both clients by name, including the wrist's
`testS004APlankDeclaredTimedRendersAsATimedEffort` — named specifically because
that file already carries a four-test S-004 family from an earlier plan, so "S-004"
alone would have been ambiguous.

**S-011 added to the register.** The review found the phone's `snapshot` branch
implemented and tested but absent from the register, which is the reverse of the
usual failure. The entry is marked with its provenance — a developer wrote it
during review to record behaviour that already existed, not the Conductor. If the
numbering collides with a later plan's register, that plan should renumber.

**Worth carrying forward:** this round is the fourth time a documentation claim in
this iteration was found to be false or unpinned. The pattern is not carelessness
in any one round — it is that prose is being edited in the same pass as the code
that falsifies it, and nobody re-reads the previous round's prose after the
current round's refactor. Whoever touches this doc set next should start by
re-reading everything the *last two* rounds wrote, not just the current one.


