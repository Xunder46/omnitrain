# Plan — 135: the watch's calories reach the phone while the session runs

**Status**: seeded 2026-11-09 by the lead; scouts done (pointer sheets `.work/crew/2026-11-09-135/sheet-wire.md`, `sheet-phone.md`).
**Binding conventions**: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`, `docs/design_system.md`.
**Base commit**: `ff398e1a7ec18409d9fc8c890bf35d2fde656e69` (branch `claude_develop`; a mixed uncommitted tree: plans 134a-134e, the Summary pen buttons, plan 136; scope every diff to this plan's files).
**Parent plans**: 134 (a-e) in `docs/plans/2026-11-08-134-calories-burned-plan/` and its five siblings, `2026-11-09-134c1`, `134c2`, `134d`, `134e`. The cardio estimate (owner item 2) is NOT in this plan: it is plan 137 (see Assumption Log A-3).

## Overview

Owner (2026-11-09, real device), in their words: "Even though I was wearing a watch, the phone was still estimating my calories, and it kept doing so even when I stopped and was resting. The phone should be receiving calories from the watch when available." And: "[holds routine] it was showing the estimate, although saved actual from the watch. The actual was 40 and the estimate was 18." And on the wrist: "the watch started counting calories only during the rest timer after I already did 2 sets ... it started with 1". And: "I don't think the line will fit especially during cardio + distance exercises" (the `kcal burned` line stays on the rest screen only).

What the user sees today: while a session runs the phone's Calories chip shows a guess (`~100 kcal`) that climbs with the clock, even during rests and even with the watch worn; the watch's real number reaches the phone only when the session ends.

What the user sees after this plan: while the watch measures, the phone's Calories chip shows the watch's own running number, no `~`, and it stays where it is while you rest (it moves only when the watch reports a new total). With no watch number the chip is exactly as today (`~` estimate, or `—`). On the wrist the rest line keeps coming from the same Health total, and it now catches up when the wrist is raised (it did not before).

Wrist-side finding (part b of the owner seeds), from the code: the workout and the energy subscription start with the session (`WatchSensorRecording.start`: `platform.start` then `recorder.start`), so nothing delays the START of recording. But `HealthKitSensorFeed` reads energy only from the builder's callback (`didCollectDataOf`, `HealthKitSensorFeed.swift:230`); heart rate has a 3-second pull and an app-active read for exactly the case "callback missed while the wrist was down", energy has neither. So a missed callback leaves the wrist's number stale until Health's next callback. `1 kcal` as the first shown value can still be Health's genuine low early total for stationary holds: only a device settles that (QA step 36).

## Goal and acceptance

(a) A live, best-effort `energy_live` frame from the wrist to the phone; the phone's open-session Calories chip prefers it. (b) The wrist reads the builder's energy on the heart-rate pull and on wrist raise too. Acceptance: S-13501 .. S-13516.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13501 | New message type `energy_live`, watch to phone, LIVE only: it is never durable (`WatchConnectivityBridge.isDurable` keeps its `default: return false`, so it travels by `sendMessage` only while the phone is reachable and a lost frame is simply gone; the next reading replaces it). Envelope: the standard envelope with `type: "energy_live"`, `origin` const `"watch"`, `sessionId` required (the wrist's session id, which is also the phone's id once adopted). Payload closed: `{activeEnergyKcal: number, at: timestamp}` — `activeEnergyKcal` finite, `>= 0`; `at` the UTC timestamp of the reading (the wire shape of every instant). No other keys | sheet-wire Q1, Q3; `WatchConnectivityBridge.swift` `isDurable`; `OmniTrainWatchConnectivity.swift:99-121` |
| D-13502 | Contract files (P1, crew-builder-watch): `watch/sync_protocol/schemas/messages/energy_live.schema.json` (copy `session_started.schema.json` for the origin const, `timer_state.schema.json` for the closed payload), `schemas/envelope.schema.json` type enum (after `timer_state`), `fixtures/valid/energy_live.json`, `fixtures/invalid/energy_live_negative.json` (kcal `-1`) and `fixtures/invalid/energy_live_phone_origin.json`, three rows in `fixtures/manifest.json` (copy the invalid rows' `expectedCode`/`expectedReasonContains` style from `invalid/session_started_missing_session.json`), `PROTOCOL.md` (table row, one note, one additive version-history row), `SyncProtocolValidator.swift` `messageTypes` (:50-66). Readers found: `test/sync_protocol_fixtures_test.dart:138-190` (manifest lists every fixture; every type needs a schema and a valid fixture), `SyncProtocolFixturesTests.swift` (walks the manifest). No semantic rule: `semanticRejections` falls to `default` | sheet-wire Q1, Q2 |
| D-13503 | Dart validator: `lib/core/sync_protocol/message_validator.dart:106-122` `messageTypes` gains `'energy_live'` (P2, crew-builder-app). The Dart side reads the same schema files | sheet-wire Q1 b2 |
| D-13510 | The wrist sender: `WatchSessionEngine` gains `public func announceEnergy(kilocalories: Double, at: Date)` (verb `announce`: the append-only guard bans update/set/write/reset...). It builds `energy_live` for the CURRENT session id when the session is active and calls `emit` (the existing path to the forwarder; `timerState(...)` at `WatchSessionEngine.swift:2122-2140` is the model); the envelope's `messageId` is `msg-energy-<sessionId>-<at in epoch milliseconds>` and `sentAt` is `at`. No stored row, nothing replayed after a crash | sheet-wire Q3 |
| D-13511 | Throttle, inside `announceEnergy`, state kept in the engine (`energyAnnouncedKcal`, `energyAnnouncedAt`, `energyAnnouncedSession`, in memory only): send when nothing was announced yet for this session id, OR the value is LOWER than the last announced (a restarted counter, 134c2 D-13470), OR it is at least 0.5 kcal above the last announced AND at least 5 seconds after it; else send nothing. A non-finite or negative value sends nothing. The numbers are the lead's defaults (about one frame per 5 s at most); listed to the owner | cadence of the heart-rate pull (3 s) and a rest of tens of seconds |
| D-13512 | The recorder hook (P3): in `WatchSensorRecorder.startActiveEnergy()` (`WatchSensorRecording.swift:266`) the consumer closure calls `record(...)` and then `await self?.engine.announceEnergy(kilocalories: kilocalories, at: <the clock the record used>)`. `record` itself stays generic | sheet-wire Q4 |
| D-13513 | The wrist pull (P3, app target `ios/OmniTrain Watch App/`): `HealthKitSensorFeed` gains `func refreshActiveEnergy(from builder: HKLiveWorkoutBuilder?)` reading `builder?.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()` in kilocalories and yielding through a new `yieldEnergyIfChanged(_:)` that yields only when the value differs from the last yielded one (so a 3 s pull does not store a row every 3 s). It is called (1) from the existing pull loop `startPull()` (:288-303) beside `refreshHeartRate()`, using the builder the feed already holds (`heartRateBuilder`), and (2) from `HealthKitWorkoutStore.refreshHeartRate()` (:241-243), which `ContentView.swift:535-542` calls on `scenePhase == .active`. No new permission. Names avoid the banned verbs (`refresh` is fine in the app target anyway) | sheet-wire Q5; D-3108/D-3113 in the heart-rate pull |
| D-13520 | Phone state: new `lib/state/watch/watch_live_energy.dart`, `class WatchLiveEnergy` with `final ValueNotifier<({String sessionId, double kcal, DateTime at})?> latest = ValueNotifier(null)` and `void receive(Map<String, Object?> envelope)`: accepts only `type == 'energy_live'` and `origin == 'watch'`, a non-empty string `sessionId`, a finite number `>= 0` and a parsable `at` (use `lib/core/sync_protocol/wire_timestamps.dart`); a frame whose `at` is older than the current `latest` for the SAME session id is ignored; a different session id replaces. Anything else is ignored silently (never throws) | sheet-phone P1, P3; precedent `WorkoutState.wristSummary` |
| D-13521 | Wiring, not the router: in `createWatchSync`'s `resolved.onIncoming((frame) async { ... })` handler (`watch_sync_wiring.dart:~380`) the FIRST statement becomes `if (frame['type'] == 'energy_live') { liveEnergy.receive(frame); return; }`, so an energy frame never reaches the router, the inbox, the mirror or adoption, and never triggers the push-side work every other wrist frame does afterwards (`push.rebaseline()`, `push.flush()`, `timerPush.flushClears()`: a heartbeat every 5 s must not cause phone-to-wrist traffic). `createWatchSync` builds one `WatchLiveEnergy` and exposes it as `WatchSyncGraph.liveEnergy`. `WatchIncomingRouter` is untouched | sheet-phone P1; `watch_sync_wiring.dart:380-402` (the lead read what runs after `router.receive`) |
| D-13522 | `WorkoutState` (constructor `workout_state.dart:40-96`) gains an optional `ValueListenable<({String sessionId, double kcal, DateTime at})?>? wristEnergy` stored and exposed as a getter; `lib/main.dart:398-407` passes `wristEnergy: watchSync?.liveEnergy.latest` | sheet-phone P3 |
| D-13523 | Screen (P2): `_WorkoutSessionScreenState` (`workout_session_screen.dart:166-170`) gains `double? _wristKcal` and a listener on `widget.workoutState.wristEnergy` (added in `initState`, removed in `dispose`; one initial read) that sets `_wristKcal` to `latest.kcal` when `latest.sessionId == currentSession.id`, else null. `_tick` (`workout_session_global_timer.dart:9-36`) sets `_liveKcal = _wristKcal ?? _computeLiveKcal()`. `_liveCaloriesLabel` (`workout_session_list_view.dart`) returns `'${_wristKcal!.round()} kcal'` (no `~`) when `_wristKcal != null`, else the existing label. A measured number shows even with no body weight on file (measured wins over `—`). A value `0` shows `0 kcal`. The chip's geometry, key and the edit-mode / rolling hiding rules do not change | sheet-phone P4; owner decision "watch measured wins" |
| D-13524 | NOT in this plan: storing the last live value as a `measured` row when the end frame is lost (the importer writes nothing without a `session_end`, sheet-phone P6): recorded as a known gap; the final Summary number still comes from `session_end` (134c1) | sheet-phone P6 |
| D-13525 | NOT in this plan: any energy line on the wrist exercise screens (owner: it will not fit with cardio plus distance); and no `0 kcal burned` before the first reading: the rest line stays hidden below 0.5 kcal, exactly as 134e | owner, 2026-11-09 |

## Scenarios

Fixtures: kcal `42.5` unless said; session id `s-13501`; instants re-derived by a throwaway script (the builders use fixed `DateTime.utc(2026, 11, 9, 12, 0, 0)` and offsets).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13501 | `fixtures/valid/energy_live.json` through the Dart validator AND the Swift fixture walk | accepted by both | the type does not exist |
| S-13502 | `invalid/energy_live_negative.json` and `invalid/energy_live_phone_origin.json` | both refused with the codes stated in the manifest, by Dart and Swift | n/a: guards of D-13501 (mutate: drop `minimum 0`; drop the origin const) |
| S-13503 | Dart: `WatchLiveEnergy.receive` with a valid frame for `s-13501` | `latest.value` is `(sessionId: 's-13501', kcal: 42.5, at: ...)` | no holder exists |
| S-13504 | `receive` guards, one test each: origin `phone`; wrong type; kcal `-1`; kcal `NaN`; kcal a string; missing `at`; empty sessionId | `latest` stays null and nothing throws | n/a: one arm per mutant (two-arm rule (y)) |
| S-13505 | two frames for the same session, the second with an OLDER `at` and a different kcal; then a frame for another session | the older one is ignored; the other session replaces | n/a: guard of D-13520 (mutate `isAfter`) |
| S-13506 | the graph's incoming handler (`createWatchSync` over the Mock harness of `test/watch_timer_push_test.dart`): an `energy_live` frame from the wrist after a phone change is owed | `liveEnergy.latest` reflects it AND the phone sent no frame to the wrist because of it (no `push.flush`/`flushClears` side effect), the mirror is unchanged | the frame went through the router and then the flush calls |
| S-13507 | `createWatchSync` over the Mock harness: an incoming `energy_live` frame on the transport | `graph.liveEnergy.latest.value` reflects it; the validator did not reject it (no `rejected` answer sent to the wrist) | the validator refused the unknown type |
| S-13508 | screen (Mock harness of `test/session_live_calories_test.dart`): resistance session, 80 kg, 1800 s (estimate `~100 kcal`), then `latest.value = (sessionId: <this session>, kcal: 42.5)` and one tick | the chip reads `42 kcal` (no `~`), `omni_session_live_calories_value` | no measured source |
| S-13509 | the same, 3 more ticks (a rest: the clock advances) | the chip still reads `43 kcal`; it does not climb | the estimate keeps running |
| S-13510 | no body weight on file, then a wrist value | the chip reads `43 kcal` (not `—`); and with a frame for ANOTHER session id the chip reads `—` | n/a: guard of D-13523 (mutate the id check) |
| S-13511 | engine (Swift, `WatchSessionEngineTests`): active session, `announceEnergy(kilocalories: 10, at: t)` then `(10.2, t+1)`, `(10.6, t+2)`, `(11.0, t+6)`, `(4.0, t+7)`, then NaN and -1 | emitted kcal values in order: 10, 11.0, 4.0 (first; ≥ 0.5 and ≥ 5 s; a lower value at once); nothing for 10.2, 10.6, NaN, -1; every envelope passes `SyncProtocolValidator` as `energy_live` | no sender |
| S-13512 | engine with NO active session (none, then completed) | `announceEnergy` emits nothing | n/a: guard (mutate: drop the status check) |
| S-13513 | the envelope: `messageId` `msg-energy-s-13501-<epoch ms of at>`, `origin` `watch`, `sentAt` equals `at`, payload keys exactly `activeEnergyKcal` and `at` | as stated | no builder |
| S-13514 | recorder: a fake `WatchSensorSource` whose `activeEnergy()` yields `[30.0, 75.5]` (permission granted) over an active session, with an `onEmit` capture | two `energy` sample rows stored AND the capture holds the `energy_live` frames per D-13511 | the closure did not announce |
| S-13515 | source-text guard `WatchSensorSourceSourceTests` on `HealthKitSensorFeed.swift` (copy the 134c2 D-13474 guard): the exact statements `func refreshActiveEnergy(from builder: HKLiveWorkoutBuilder?) {`, `.sumQuantity()`, `HKUnit.kilocalorie()`, `func yieldEnergyIfChanged(` and that `startPull()`'s body contains `refreshActiveEnergy(`; and `HealthKitWorkoutStore.swift` `refreshHeartRate()` contains `sensorFeed.refreshActiveEnergy(from: builder)` | each statement incl. its brace (rule (ao)) | the app target has no pull |
| S-13516 | `isDurable` for `energy_live` | false (a refused `sendMessage` is reported and dropped, never queued) | n/a: guard of D-13501 (existing `isDurable` test file; mutate: add the type to the durable case) |

## Phases

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 wire | crew-builder-watch | `watch/sync_protocol/**` (schema, envelope, fixtures, manifest, PROTOCOL.md), `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift` | first, serial |
| P2 phone | crew-builder-app | `lib/core/sync_protocol/message_validator.dart`, `lib/state/watch/watch_live_energy.dart` (new), `lib/state/watch/watch_sync_wiring.dart`, `lib/state/workout/workout_state.dart`, `lib/main.dart`, `lib/features/session/workout_session_screen.dart`, `lib/features/session/workout_session_global_timer.dart`, `lib/features/session/workout_session_list_view.dart`, `test/watch_live_energy_test.dart` (new), `test/session_live_calories_test.dart` | after P1; parallel with P3 (disjoint) |
| P3 wrist | crew-builder-watch | `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `WatchSensorRecording.swift`, `watch/watchos/Tests/WatchSessionEngineTests/**` (new `WatchEnergyLiveTests.swift`, the source guard), `ios/OmniTrain Watch App/HealthKitSensorFeed.swift`, `HealthKitWorkoutStore.swift` | after P1; parallel with P2 |
| P4 docs | crew-docs-keeper | the Docs delta files | after P2 and P3 |

Parallel rule: P2 and P3 write disjoint scopes, neither needs the other's output (P3's Swift fixture walk needs P1's fixtures, P2's Dart fixture test needs P1's fixtures); only the lead runs the full suites afterwards.

### P1 wire (crew-builder-watch, 7 items)

1. [ ] Add the three fixtures and their manifest rows (S-13501, S-13502); red: the Dart/Swift fixture walks list them but the type is unknown.
2. [ ] Add `schemas/messages/energy_live.schema.json` and the envelope type enum entry.
3. [ ] Add `'energy_live'` to the Swift `messageTypes` (`SyncProtocolValidator.swift:50-66`).
4. [ ] PROTOCOL.md: table row after `timer_state`, a note (live only, never durable, latest wins, the wrist's session id, throttled by the sender but the receiver never relies on it), one additive version-history row dated 2026-11-09.
5. [ ] `swift test` filtered to `SyncProtocolFixturesTests`; report the line.

The Dart validator list is P2 (lib/core is not in this builder's ceiling): until P2 the Dart fixture test is red by design (`gives every message type a schema and a valid fixture` fails for lack of the Dart type). Done: the Swift fixture walk green; the Dart walk green after P2.

### P2 phone (crew-builder-app, 8 items; skeleton report first)

1-2. [ ] Red tests: `test/watch_live_energy_test.dart` S-13503..S-13507 (Mock only, plain `test()`); S-13508..S-13510 in `test/session_live_calories_test.dart` (copy the file's harness; screen tests tap no preference writes).
3. [ ] D-13503 validator list.  4. [ ] D-13520 `WatchLiveEnergy`.  5. [ ] D-13521 wiring.  6. [ ] D-13522 `WorkoutState` + `main.dart`.  7. [ ] D-13523 screen.  8. [ ] Green: the two new test files, `test/sync_protocol_fixtures_test.dart`, `test/live_mirroring_test.dart`, `test/watch_timer_push_test.dart`.

### P3 wrist (crew-builder-watch, 7 items; skeleton report first)

1-2. [ ] Red tests: `WatchEnergyLiveTests.swift` S-13511..S-13514, S-13516; source guard S-13515 (exact statements, rule (ao)). 3. [ ] D-13510/D-13511 `announceEnergy`. 4. [ ] D-13512 recorder hook. 5. [ ] D-13513 feed + store. 6. [ ] `swift test --filter WatchSessionEngineTests` (rule (r): filtered runs never select the append-only guard, so also the whole target once).

Done lists name the exact gateway forms. Never run the full `flutter test` in any builder run.

## Input-reality checklist

1. **Writers and units**: the only writer of `energy_live` is the wrist's recorder (kcal, cumulative since the workout began, from Health's `activeEnergyBurned` sum). Receivers: the phone router. Units are kilocalories end to end; the chip rounds with `.round()` at the screen only; the wire carries the unrounded double.
2. **Lifecycle**: no frame before the first reading; frames only while the wrist session is active; a session that ends stops them; the phone holder keeps the last value per session id and the screen shows it only for the session it is open on; a new session id replaces it. A lost frame costs nothing. After a phone restart the holder is empty until the next frame (the chip shows the estimate).
3. **Settings**: none (no setting gates the chip; the Effort Rating toggle is unrelated).
4. **Time**: only comparisons of `at`; the phone never reads its own clock for the frame; the wrist's `at` is its own clock (the two devices' clocks are never compared).
5. **Load**: at most one frame per 5 s while energy rises; each frame is one small `sendMessage`; the wrist pull adds one `statistics` read per 3 s while a heart-rate listener lives and one on wake; a 3 s pull stores a row only when the value changed (D-13513).
6. **Words**: the chip reads `43 kcal` for 42.6 (measured, no `~`), `~100 kcal` (estimate), `—` (nothing); no new strings. Docs: the "always an estimate" sentence and the QA step (owner).
7. **Competition**: the Summary's final number still comes from `session_end` and replaces whatever the chip showed (the measured row, 134c1); a Free Training session's estimate stepping at the end is replaced by the live measured number while the wrist runs. The wrist's rest line and the phone chip read the same Health total but are independent surfaces; a frame can lag the rest line by up to 5 s. Readers that WAIT for the frame: none (nothing waits; no spinner, no timeout).
8. **Existing premises pinned by tests** (grep done): `test/session_live_calories_test.dart` S-13445..S-13449 and `test/active_energy_live_test.dart` pin the estimate and stay valid (no measured value there); `watch_transport_test` exact-payload assertions concern `preferences_down`, not this type; `test/sync_protocol_fixtures_test.dart` and `SyncProtocolFixturesTests.swift` list fixtures whole (D-13502).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/modality_based_exercise_ui.md | MODIFIED | `The live figure is always an estimate: a Free Training` | `The live figure is the watch's own number once the wrist has sent one (plan 135, no `~`), otherwise an estimate: a Free Training` | S-13508 |
| docs/modality_based_exercise_ui.md | MODIFIED | `chip never shows a measured total — a watch's measured figure arrives with the` | `chip shows the wrist's running total as soon as an `energy_live` frame arrives, and the Summary's figure arrives with the` | S-13509 |
| docs/state_management/watch_surface.md | ADDED | - | `WatchLiveEnergy` | S-13503, S-13506 |
| docs/state_management/watch_sensors.md | ADDED | - | `announceEnergy` | S-13511 |
| docs/watch_session_sync.md | ADDED | - | `energy_live` | S-13507 |
| docs/watch-app-setup-and-qa.md | ADDED | - | `Live calories on the phone` | S-13514 |

(`watch/sync_protocol/PROTOCOL.md` is written in P1 by crew-builder-watch: it is outside the keeper's `docs/**` ceiling.)

## Progress

| Item | What | Status |
|---|---|---|
| P1 | wire contract files, Swift validator list | Planned |
| P2 | phone holder, wiring, screen | Planned |
| P3 | wrist sender, recorder hook, feed pull | Planned |
| P4 | docs rows 1-6 and the QA step | Planned |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | The 5 s / 0.5 kcal throttle is the lead's default; a different cadence is a one-constant change | no owner view on cadence |
| A-2 | A new live message type is the least invasive carrier: no existing live frame (`timer_state`, `session_snapshot`) has a place for a sensor number without changing its meaning | sheet-wire Q3 |
| A-3 | The cardio fallback estimate (flat MET 7.0 is too high for walking: 25 min at about 75 kg reads about 190 kcal against the treadmill's 120) is plan 137: a pace-based MET needs the session's distance and duration read inside `settle` and a decision on the live chip (which has no distance), so it does not belong in this wire plan. With the watch worn, this plan makes the watch's number win during the session as well | scope budget; sheet-phone P5 |
| A-4 | `1 kcal` as the first value shown on the wrist may be Health's genuine early total for stationary holds; this plan removes the one code cause found (no pull on wake), the rest needs a device | HealthKit semantics cannot be run here |
| A-5 | The architect phase is skipped: the seed carries exact decisions, fixtures and pointers; scope guard run by the lead | cost discipline |
