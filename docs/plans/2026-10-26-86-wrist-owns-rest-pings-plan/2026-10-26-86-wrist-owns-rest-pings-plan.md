# Feature: 86 — while the watch is running the same workout, only the watch pings the rest (the phone's background notification stays quiet)

> Status: BUILT AND PROVED 2026-10-26 (uncommitted). Review major fixed (a switch to another active session hands the pings back; only an ended mirror session cancels and forgets; test S-15611b, shown red without the fix). Five mutations each turned their own guard red. Earlier status: SEEDED 2026-10-26 (lead), architect complete 2026-10-26. Base commit: `.work/2026-10-26-86/base.txt` = `f0d0d0853351dfcee04873455bf79d27b1ba7535`. Team: the crew. Owner decision (chat, 2026-10-26, audit finding W5): "agreed" to the lead's recommendation: quiet the phone's background rest notification while the watch is reachable and running the same session; no new setting, no protocol change. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## What the owner sees

| Moment | Today | After |
|---|---|---|
| Phone in the pocket or locked, watch on the wrist, same workout, a rest runs | the watch taps at each boundary AND the phone posts a notification (sound, and iOS may mirror it to the watch): two or three cues per boundary | the watch taps; the phone posts nothing |
| Phone open on the workout screen, watch on the wrist | the watch taps and the phone plays its in-app ping | unchanged (you are looking at the phone; its in-app ping stays) |
| No watch, or the watch is not connected, or the watch is not running this workout | the phone's notification pings | unchanged |
| The watch drops out of reach in the middle of a rest (wrist app closed, out of range) | n/a | the phone takes the remaining pings over at once, on the same boundaries (from the rest's start), so a rest is never silent |
| The watch comes back in reach in the middle of a rest | n/a | the phone's remaining notifications are withdrawn |
| Rest ping interval Off | no pings | no pings |

(owner) On a real watch + phone: start a workout on the phone with the watch app running it, set Rest Ping to 30 s, lock the phone, log a set: the watch taps at 30 s and the phone stays silent. Then turn the watch to Airplane Mode (or close its app) in the middle of a rest: the phone's notification arrives at the next boundary.

## Decision Ledger

- D-1 One decision rule, pure and testable, `bool wristOwnsRestPings({required bool linkConnected, required bool mirrorActive, required String? mirrorSessionId, required String? phoneSessionId})` = `linkConnected && mirrorActive && mirrorSessionId != null && mirrorSessionId == phoneSessionId`. `linkConnected` = `WatchLinkState.phase == WatchLinkPhase.connected` (`lib/state/watch/watch_link_state.dart:43-52`); `mirrorActive`/`mirrorSessionId` = `LiveSessionMirrorState.isActive` / `.sessionId` (`live_session_mirror_state.dart:133,145`); `phoneSessionId` = the phone's current session id (`WorkoutState.currentSession?.id`). Reason for all four terms: reachable means the wrist app is alive and will ping (it pings only for a rest it holds, plan 61/22), the mirror says the wrist holds THIS session and its rest (plan 50a pushes the phone's open rest to the wrist).
- D-2 `RestNotificationService` (`lib/core/utils/rest_notification_service.dart`, `scheduleRestPings` `:268`, `cancelRestNotifications`) gets a settable gate, `bool Function()? wristOwnsPings` (null = never quiet, the default and what every existing test sees). `scheduleRestPings` ALWAYS remembers the request it was given (`restStartMs`, `intervalSecs`, `soundId`, `playSound`) and, when the gate answers true, cancels what is scheduled and schedules nothing. `cancelRestNotifications` forgets the remembered request (a rest that ended must not be re-scheduled on a reconnect). A new method `Future<void> reevaluate()` re-runs the remembered request through the same path: gate true -> cancel; gate false -> schedule the boundaries still in the future (the existing `fireAtMs <= nowMs` skip, `:284-286`); no remembered request -> nothing. New names avoid nothing in particular on the phone side (the Swift append-only verb guard does not apply to Dart).
- D-3 Wiring (`lib/main.dart`, where `restNotificationService` is created `:154,355` and `watchSync` `:370`): after both exist, set `restNotificationService.wristOwnsPings = () => wristOwnsRestPings(...)` reading the link, the mirror and the workout state at call time, and call `reevaluate()` whenever the link state changes or the mirror's state changes (listeners on `WatchLinkState` and `LiveSessionMirrorState`, both `ChangeNotifier`s; the architect confirms and names the exact objects reachable from `main`, and where `WorkoutState` is available). No listener when there is no watch graph (`watchSync == null`): the gate stays null.
- D-4 In-app ping unchanged: `workout_session_global_timer.dart` `_checkRestPings` (`:32-59`) and `TimerAlertService.fireRestPingAlert` are not touched. The wrist's own ping and the phone's `shouldFireRestPing` rule are not touched.
- D-5 Not in scope: a setting for where pings go; any wire field; the effort-timer expiry notification (`scheduleEffortTimerExpiry`, a different cue); Android (the same service runs there; the rule applies to any platform whose link reports connected, which on Android is never today).
- D-6 Risk recorded, not removed: "connected" is a snapshot. If the wrist app dies without the link reporting it, the phone stays quiet until the next link change. Mitigation: the link/mirror listeners (D-3) re-evaluate on every change, and the phone's in-app ping still fires when the screen is open.
- D-7 Serialisation (architect, answers brief question (e): NOT safe unguarded). Each pass of `scheduleRestPings` awaits up to 50 plugin cancels (`:276`), the exact-alarm probe (`_refreshExactAlarmCapability`) and up to 50 plugin schedules; a link/mirror listener can fire `reevaluate()` mid-pass, and a gate flip mid-pass could otherwise leave the phone scheduling after a cancel (a ping the wrist owns) or interleaving two passes over the same ids. Smallest guard: one chained future in the service, `Future<void> _restPingQueue = Future.value()`, and `scheduleRestPings`, `reevaluate()` and `cancelRestNotifications` all enqueue their body onto it. The internal `await cancelRestNotifications()` at `rest_notification_service.dart:276` must call the raw, unqueued body (a private `_cancelRestNotificationsNow()`), or the queued pass would await a queue entry that waits for itself and hang. External callers are unchanged: every `unawaited(widget.restNotificationService.cancelRestNotifications())` site keeps compiling and keeps its meaning.
- D-8 Wiring home and seam (architect; refines D-3). New `lib/state/watch/watch_rest_ping_wiring.dart` with `void bindRestPingGate({required RestNotificationService service, required WatchLinkState? link, required LiveSessionMirrorState? mirror, required WorkoutState workoutState})`. It sets `service.wristOwnsPings` to a closure that reads, at call time: `link?.phase == WatchLinkPhase.connected`, `mirror?.isActive`, `mirror?.sessionId`, `workoutState.currentSession?.id` — and adds itself as a listener on each non-null state. On a **link** change it always calls `unawaited(service.reevaluate())` (the takeover, S-15610). On a **mirror** change it keeps the previous gate in a field: when the previous gate was true and the mirror no longer reports an active session matching the phone's (`!mirror.isActive || mirror.sessionId != workoutState.currentSession?.id`), the owned rest is over — it calls `unawaited(service.cancelRestNotifications())`, which forgets the request (D-2), so no phantom ping is re-scheduled for a rest the wrist finished (S-15611); otherwise `unawaited(service.reevaluate())`. `main.dart` calls it after the `bindWorkoutState` block (`:395-400`), before `MyApp` is built; with `watchSync == null` both states are null, no listener is added and the gate stays null (D-3). No `WorkoutState` listener: the phone's own rest-open paths (`workout_session_timer_mixin.dart:543,577`, `workout_session_screen.dart:370,992`) read the gate fresh when they schedule, so a phone-only session needs no push.

## Scenarios (exact fixtures; re-derive in the first run)

Harness: the service already has test seams (`_zonedScheduleOverride`, `_cancelOverride`, `_nowProvider`, and the `isWeb`
parameter — field `_isWebOverride` — of `withPlugin`; see how `test/rest_pings_watch_end_test.dart` and the rest-notification service tests construct it).

- S-15601 `wristOwnsRestPings`: true only for (connected, active, `s-1`, `s-1`); false for each single deviation (not connected; mirror not active; mirror session null; mirror `s-2` vs phone `s-1`; phone session null).
- S-15602 gate true: `scheduleRestPings(restStartMs: now-5000, intervalSecs: 30, ...)` schedules nothing and cancels (fake cancel override called for the 50 ping ids or the service's own `cancelRestNotifications`); fails today (it schedules).
- S-15603 gate null or false: the same call schedules the future boundaries exactly as today (30 s, 60 s, ...; ids `restPingBaseId + n - 1`).
- S-15604 `reevaluate()` after the gate flips true -> false at `now = start + 70 s` with a 30 s interval: schedules only the boundary at 90 s onwards (60 s is in the past); after it flips false -> true: cancels, schedules nothing.
- S-15605 `reevaluate()` with nothing remembered, or after `cancelRestNotifications()`, does nothing (no schedule, no cancel storm).
- S-15606 interval 0: nothing scheduled whatever the gate says (existing rule), and `reevaluate()` keeps it so.
- S-15607 wiring: with the link connected and the mirror holding the phone's session, a rest-start through the real screen path (`test/rest_pings_watch_end_test.dart` harness) schedules nothing; after the link goes not-reachable the remaining pings are scheduled. If that harness cannot drive the link, the architect names the smallest real-object test (the wiring function under test with fakes of the three readers).
- S-15608 foreground unchanged: `_checkRestPings` still fires `fireRestPingAlert` with the gate true (existing test stays green).
- S-15609 (wiring, `test/rest_ping_gate_wiring_test.dart`) the gate is read at call time. Fixture: `MockWorkoutRepository` seeded with session `s-1`; `workoutState.loadHistoricalSession('s-1')` (the same call the adoption bridge makes, `watch_session_adoption_bridge.dart:723`); a real `WatchLinkState` over a `_Source implements WatchLinkSource` fake copied from `test/watch_link_state_test.dart:32`, reporting paired + installed + reachable; a real `LiveSessionMirrorState` over a fake `WatchMirrorTransport` that has received a `session_snapshot` naming `s-1`, status `active`; the service via `RestNotificationService.withPlugin` with `zonedScheduleOverride`, `cancelOverride` and `nowProvider` pinned to `DateTime.utc(2026, 10, 26, 12)`. Expected: after `bindRestPingGate`, `service.wristOwnsPings!()` is true; after the source emits a not-reachable `WatchLinkInfo` it is false; after the mirror receives a snapshot naming `s-2` (phone still `s-1`) it is false; with `link: null, mirror: null` (the `watchSync == null` shape) the gate stays null.
- S-15610 (wiring, same file) the listeners drive the takeover. Fixture as S-15609; while the gate is true the test calls `scheduleRestPings(restStartMs: nowMs - 70000, intervalSecs: 30, soundId: 'soft_chime')` (remembered, nothing scheduled); then the source emits not-reachable. Expected: exactly 48 schedules — boundaries at rest start + 90 s … + 1500 s (30 s and 60 s are in the past at the pinned `now`), ids `restPingBaseId + n - 1` = `102..149`; then the source emits reachable again → 50 cancels, 0 schedules.
- S-15611 (wiring, same file) no phantom ping after the wrist ends the session. Fixture as S-15610 with the request remembered under a true gate; then the wrist's `session_lifecycle` `completed` for `s-1` arrives through `LiveSessionMirrorState.receive`. Expected: the wiring cancels and forgets; a later link flap to not-reachable schedules nothing (0 schedules, and the cancel count does not grow from a re-schedule).

Readers of the changed contract (the architect re-greps): every caller of `scheduleRestPings` (`workout_session_timer_mixin.dart:543,577`, `workout_session_screen.dart:370,992`), `cancelRestNotifications` callers (`workout_session_finish.dart:85`, mixin `:670,:752`, screen `:271,351,365,884,1414,1471,1843`), tests `test/rest_pings_watch_end_test.dart`, `test/rest_ping_contract_test.dart`, `test/rest_notification_service*_test.dart`, `docs/rest_tracking.md` (the sentence "both devices ping per the one Rest Ping setting"), `docs/theme_and_settings.md`, `docs/state_management/watch_surface.md`.

## Feature invariants

- The gate is additive: a null gate is byte-identical behaviour to today, for every caller and every existing test (S-15603, S-15608).
- A rest is never silent: when the phone stops owning the pings mid-rest it re-schedules the remaining boundaries from the rest's own start (S-15610); the wrist's own ping rule is untouched (D-4).
- A rest the wrist finished is never re-pinged by the phone (S-15611, D-8's cancel-on-end).
- The effort-timer expiry notification is outside the gate (D-5): `scheduleEffortTimerExpiry` and `cancelEffortTimerNotification` are not modified.

## Existing-functionality impact (architect re-grep, this run)

| Touched surface | What already reads it (search result) | Effect | Guarded by |
|---|---|---|---|
| `RestNotificationService.scheduleRestPings` (`rest_notification_service.dart:268`) | callers `workout_session_timer_mixin.dart:543,577`, `workout_session_screen.dart:370,992` (grep, 4 sites, no others in `lib/`) | gate null → unchanged path; gate true → remember + cancel + schedule nothing | S-15602, S-15603 |
| `RestNotificationService.cancelRestNotifications` (`:616`) | callers `workout_session_finish.dart:85`, mixin `:670,:752`, screen `:271,351,365,884,1414,1471,1843` (grep, 10 sites) | visible behaviour unchanged (still cancels ids 100..149); additionally forgets the remembered request | S-15605 |
| Tests constructing the service | `test/rest_notification_service_test.dart` (24 `withPlugin` sites), `FakeRestNotificationService` (`test/helpers/fake_rest_notification_service.dart` — extends the service, overrides `scheduleRestPings`/`cancelRestNotifications`, so it never gates), `startup_failure_screen_test.dart:48,59` (`super.noop()` subclasses) | none sees a behaviour change: the gate defaults to null and the fake's overrides bypass it | S-15603, S-15608 |
| Foreground in-app ping | `_checkRestPings` (`workout_session_global_timer.dart:32-59`) → `TimerAlertService.fireRestPingAlert` (`:57`) | untouched | S-15608 |
| `docs/rest_tracking.md:330` | the sentence "both devices ping per the one Rest Ping setting" | rewritten in P4 | P4 |

## Code pointers (current lines, read this run)

- `RestNotificationService` (`lib/core/utils/rest_notification_service.dart`): class `:7`; constructors `RestNotificationService()` `:60`, `.noop()` `:73`, `.withPlugin` `:87` (test seams: `isWeb` → `_isWebOverride`, `nowProvider`, `zonedScheduleOverride`, `cancelOverride`, `requestPermissionOverride`, `hasPermissionOverride`, `reportErrorOverride`, `reportInfoSignalOverride`, `pluginInitializeOverride`, `androidChannelCreateOverride`); `scheduleRestPings` `:268` (internal `await cancelRestNotifications()` `:276`, interval guard `:278`, loop `:284`, past-boundary skip `:286`); `cancelRestNotifications` `:616` (loops ids `restPingBaseId .. restPingBaseId + maxRestPings - 1` = `100..149`); `scheduleEffortTimerExpiry` `:341`; `restPingBaseId = 100`, `maxRestPings = 50` `:8-9`.
- `main.dart`: factory type `:56-57`; `_initializeRestNotificationServiceSafely` `:150`, factory invoked `:154`; parameter `createRestNotificationService` `:240-241`; service created `:355-359` — **before** `watchSync` `:370`, so a setter is needed (D-3 confirmed); `workoutState` `:386-389`; `bindWorkoutState` block `:395-400`; `MyApp` return `:412+` with `restNotificationService:` `:436`, `onWatchResume: watchSync?.sync` `:440`, `watchLinkState: watchSync?.link` `:442`.
- `WatchSyncGraph` (`lib/state/watch/watch_sync_wiring.dart`): class `:68`; `mirror` `:81`; `link` (`WatchLinkState?`) `:114`; `createWatchSync` answers null on web/desktop/Android or when the transport cannot be set up.
- `WatchLinkState` (`lib/state/watch/watch_link_state.dart`): `extends ChangeNotifier` `:19`; `phase` `:43-52` (`connected` ⇔ `info.reachable` with paired + installed); `_onInfo` → `notifyListeners()` `:111-114` (every `linkChanges` event and every `refresh()`); `_onHeard` → `notifyListeners()` `:117-120`. A reachability flip arrives as a `linkChanges` event, so the listener fires. Answer to (b): yes.
- `LiveSessionMirrorState` (`lib/state/watch/live_session_mirror_state.dart`): `extends ChangeNotifier`; `sessionId` `:133`, `isActive` `:145` (status == `WatchSessionStatus.active`); `notifyListeners` sites `:255` (`receive` — covers a snapshot that adopts/switches a session and a `session_lifecycle` that ends it), `:587` (`deleteEntryAs`), `:604` (`completeSession`), `:660` (`reportLifecycleFor`), `:738` (`_sendOwn`). Answer to (b): the mirror notifies on both adopt and end; no extra hook needed. A message that names no mirrored session returns `ignored` before `:255`, so a phone-only session gets no mirror notifies and no spurious reevaluates.
- `WorkoutState` (`lib/state/workout/workout_state.dart`): `extends ChangeNotifier` `:18`; `currentSession` `:69` (`TrainingSession?`); `loadHistoricalSession` `:159` → `session_core_io.dart:56-67` sets `_currentSession` — the seam the wiring test uses.
- Session-id equality, answer to (c): yes in both directions. Wrist follows a phone-started session: the phone's projection names `'sessionId': session.id` (`watch_session_adoption_bridge.dart:278`), the wrist adopts that id and its snapshots come back under it, so the mirror's `sessionId` equals `currentSession.id`. Phone adopts a wrist-started session: `consider` `:662` → `_adopt` `:795` creates the session with `id: sessionId` (`:804`) and `loadHistoricalSession(sessionId)` `:723` puts it in `currentSession`. Existing precedent for the same equality: `holdsSession` `:186-188`.

## Phases

- P1 `crew-builder-app` — service + decision rule + tests (D-1, D-2, D-7; S-15601..S-15606). Serial.
  1. [ ] Add the pure rule — `lib/core/utils/wrist_rest_ping_rule.dart` · `wristOwnsRestPings` (D-1 signature verbatim; no state imports).
  2. [ ] Add the gate field, its setter `wristOwnsPings` (`bool Function()?`, null default) and the remembered-request field — `lib/core/utils/rest_notification_service.dart` · `RestNotificationService` (D-2).
  3. [ ] Remember the request and short-circuit on a true gate in `scheduleRestPings` — same file · `scheduleRestPings` (D-2); the internal cancel calls the raw body (D-7).
  4. [ ] Forget the request in the cancel; rename the body `_cancelRestNotificationsNow` and queue the public method — same file · `cancelRestNotifications` (D-2, D-7).
  5. [ ] Add `Future<void> reevaluate()` re-running the remembered request through the same path — same file · `reevaluate` (D-2).
  6. [ ] Chain the three entries through `Future<void> _restPingQueue` — same file · `_restPingQueue` (D-7).
  7. [ ] New `test/wrist_rest_ping_rule_test.dart` — S-15601 as a table test (true only for connected+active+`s-1`+`s-1`; false for each single deviation).
  8. [ ] New `test/rest_ping_gate_test.dart` — S-15602..S-15606, copying the `withPlugin` harness of `test/rest_notification_service_test.dart:27`. Fixtures: `nowProvider` pinned to `DateTime.utc(2026, 10, 26, 12)`; S-15602 gate true, `restStartMs: nowMs - 5000, intervalSecs: 30` → 0 schedules, 50 cancels; S-15603 gate null → 50 schedules, ids `100..149` (first boundary `nowMs + 25 s`, all future); S-15604 `restStartMs: nowMs - 70000` → reevaluate at the pinned now schedules 48 (ids `102..149`), then gate true → 50 cancels, 0 schedules; S-15605 reevaluate with nothing remembered and after `cancelRestNotifications()` → 0 schedules, no extra cancels; S-15606 `intervalSecs: 0` → 0 schedules at either gate, and `reevaluate()` keeps it so.

  Done Criteria: `flutter test test/wrist_rest_ping_rule_test.dart test/rest_ping_gate_test.dart test/rest_notification_service_test.dart` green; `flutter analyze` no new issues vs the plan baseline; prove-red at `f0d0d085` — the S-15602 test fails at base (today the call schedules) and the S-15604 file fails to compile at base (no `reevaluate`), which is the red for a new API.
  Predicted Files: `lib/core/utils/rest_notification_service.dart`, `lib/core/utils/wrist_rest_ping_rule.dart`, `test/rest_ping_gate_test.dart`, `test/wrist_rest_ping_rule_test.dart`.
  Write scope: `"lib/core/utils/rest_notification_service.dart" "lib/core/utils/wrist_rest_ping_rule.dart" "test/rest_ping_gate_test.dart" "test/wrist_rest_ping_rule_test.dart"`.

- P2 `crew-builder-app` — wiring in `lib/main.dart` (D-3, D-8; S-15607, S-15609..S-15611). Serial after P1 (needs the setter and `reevaluate`).
  1. [ ] New `lib/state/watch/watch_rest_ping_wiring.dart` · `bindRestPingGate` (D-8: gate closure, link listener → `reevaluate`, mirror listener with the previous-gate memory → cancel-on-end or `reevaluate`).
  2. [ ] Call `bindRestPingGate` after the `bindWorkoutState` block (`lib/main.dart:395-400`), before `MyApp` — `main` (D-3).
  3. [ ] New `test/rest_ping_gate_wiring_test.dart` — S-15609 and S-15610 with the fixtures written above (real `WatchLinkState` over the `_Source` fake copied from `test/watch_link_state_test.dart:32`, real mirror over a fake `WatchMirrorTransport`, `MockWorkoutRepository` + `loadHistoricalSession('s-1')`, service via `withPlugin`).
  4. [ ] S-15611 in the same file — the phantom-ping guard (wrist `session_lifecycle` `completed` → cancel + forget → later link flap schedules nothing).
  5. [ ] Regression: `test/rest_pings_watch_end_test.dart` and `test/rest_ping_contract_test.dart` stay green unchanged (S-15608). Their harness has no `WatchLinkState` — `CaptureTransport` implements `WatchMirrorTransport` only (`test/helpers/watch_capture_import_harness.dart:100`) — so the screen path cannot see the gate; this is the answer to S-15607's fallback question: the wiring test above is the smallest real-object test.

  Done Criteria: `flutter test test/rest_ping_gate_wiring_test.dart test/rest_pings_watch_end_test.dart` green; `flutter analyze` no new issues vs baseline; prove-red at `f0d0d085` — S-15610's takeover test fails at base (no listener → nothing scheduled after the flip).
  Predicted Files: `lib/state/watch/watch_rest_ping_wiring.dart`, `lib/main.dart`, `test/rest_ping_gate_wiring_test.dart`.
  Write scope: `"lib/state/watch/watch_rest_ping_wiring.dart" "lib/main.dart" "test/rest_ping_gate_wiring_test.dart"`.

  Parallelism: P1 and P2 are serial (P2 compiles against P1's API). P3 waits for both; P4 waits for P3.
- P3 lead — full `flutter test`, `flutter analyze`, mutation pass (gate ignored; `reevaluate` no-op; the session-id term dropped), invariant grep.
- P4 `crew-docs-keeper` — `docs/rest_tracking.md` (the cross-device sentence), the QA list in `docs/watch-app-setup-and-qa.md` (a new step after the latest, `(owner)`), then `crew-reviewer`.

## Assumption Log

- Plan 61's wrist ping runs with the wrist down because the workout session keeps the wrist app alive; this plan relies on "reachable implies the wrist app is alive".
- The foreground double (phone in-app ping + wrist tap while the phone is open) is accepted as the owner agreed to the recommendation.
- (architect) D-8's cancel-on-end reads the mirror's status, not the rest's: a wrist frame that ends the session is assumed to also end its open rest (the wrist closes a rest when the set is logged or the session finishes — plan 61/22).
- (architect) `MockWorkoutRepository` + `loadHistoricalSession('s-1')` is accepted as the way the wiring test puts a known session id into `WorkoutState.currentSession` without driving the full screen; it is the same call the adoption bridge makes (`watch_session_adoption_bridge.dart:723`).
- (architect) Every wrist frame on a watch-led session triggers a `reevaluate()` pass of up to 50 no-op plugin cancels — bounded, and the same cost a `scheduleRestPings` call pays today. A "gate unchanged and true → skip" short-circuit in the wiring would be cheaper; out of scope.

## Progress

| Item | Status |
|---|---|
| Seed verified against the code (all cited files/lines) | done |
| D-7, D-8 added; S-15609..S-15611 added | done |
| P1 expanded (8 items, scope, fixtures, Done Criteria) | done |
| P2 expanded (5 items, scope, fixtures, Done Criteria) | done |
| P1 implementation | pending `crew-builder-app` |
| P2 implementation | pending `crew-builder-app` |
| P3 full test + mutation pass | pending lead |
| P4 docs + review | pending `crew-docs-keeper` |

## Open questions

- Chattiness (see Assumption Log): if the lead wants the per-frame `reevaluate()` skipped when the gate is unchanged and true, that is a follow-up decision, not this plan.

## Architect notes (corrections to the seed)

- `watch_link_state.dart:44-52` → `:43-52` (the `phase` getter starts at 43).
- `rest_notification_service.dart:290-291` → `:284-286` (loop `:284`, past-boundary skip `:286`).
- `workout_session_global_timer.dart:32-61` → `:32-59` (`fireRestPingAlert` at `:57`).
- The test seam is the `isWeb` parameter of `withPlugin` (field `_isWebOverride`), not `isWebOverride`.
- `cancelRestNotifications` is at `rest_notification_service.dart:616` (the seed gave no line).
- Brief answers: (a) yes — service `:355-359` before `watchSync` `:370`, `workoutState` `:386`, all reachable before `MyApp`; a setter is needed (D-3 confirmed). (b) yes — both notify on the changes that matter (`watch_link_state.dart:114,120`; `live_session_mirror_state.dart:255`); no extra hook. (c) yes — both directions equal (`watch_session_adoption_bridge.dart:278,723,795,804`). (d) no existing test sees a behaviour change with the gate null; new tests copy the `withPlugin` harness of `test/rest_notification_service_test.dart:27`. (e) not safe unguarded — D-7 is the smallest guard.
