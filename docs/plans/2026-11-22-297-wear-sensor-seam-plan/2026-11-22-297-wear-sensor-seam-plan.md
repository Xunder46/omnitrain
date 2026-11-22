# Plan 297 — The Wear wrist wires its sensors: the Dart half of live heart rate and distance (plan 280 item 9, part 1 of 3)

Item 9 of plan 280 (live sensors) is three pieces, and only the middle one needs a native toolchain. The Dart sensor layer already exists and is tested (`lib/watch/sensors/watch_sensor_recording.dart`: `WatchSensorSource`, `WatchSensorRecorder`, `WatchSessionSensors`; plan D-28010 names Health Services and the fused location provider as the Wear OS clients), and the logging screen already prints a heart-rate and distance line from stored samples. What is missing on Wear is the wiring: nothing builds a `WatchSessionSensors`, nothing starts it when a workout begins or stops it when it ends, and there is no `WatchSensorSource` that talks to the platform. This plan builds the Dart half and fixes the channel contract the Kotlin half (plans 298 heart rate, 299 distance) will implement. Until that half exists the real source answers "unavailable" and the wrist behaves exactly as today. Wrist Dart only (`lib/watch/`); no Kotlin, wire, schema, phone or Swift change. Base commit: `.work/2026-11-22-297-wear-sensor-seam/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

A running Wear session starts the sensors once and ends them once, on every path that starts or ends a session (the Start screen, a routine, a phone-started session adopted by the wrist, a restored session at launch, End and Discard from the menu, the phone ending it): while a session is active the recorder listens, a heart-rate beat the source reports is stored and shows on the logging screen's sensor line, and a session that ends cancels the subscriptions. A source that answers `denied` or `unavailable` (the state of every Wear build until plan 298) records nothing and changes nothing the user sees; a source that errors never crashes the app.

Acceptance: S-29701..S-29715 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the Wear debug APK builds; Docs delta applied.

## Feature invariants

- Logging never depends on a sensor: a failing, refusing or absent source never blocks, delays or fails a log, a start or an end (plan 280 D-28010; sensor plan S-006).
- A reading is stored, not held: the recorder's existing rule is untouched.
- Start and stop are idempotent per session: one start per session id, one stop per session, in order, never two at once (one lane).
- The channel names and method answers below are the contract the Kotlin half implements; they are fixed here.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29701 | New `WearSensorSource implements WatchSensorSource` (`lib/watch/sensors/wear_sensor_source.dart`) over `MethodChannel('omnitrain/wear_sensors/methods')` with calls `heartRatePermission` and `locationPermission`, each answering `'granted'`, `'denied'` or `'unavailable'`, and two `EventChannel`s: `omnitrain/wear_sensors/heart_rate` (numbers, beats per minute) and `omnitrain/wear_sensors/location` (numbers, cumulative metres). A permission call asks the user first when the state is undetermined (the native half owns the prompt); any other answer, a `PlatformException` or a `MissingPluginException` reads as `unavailable`. | `watch_sensor_recording.dart` 56-69; Apple `WatchSensorRecording.swift` |
| D-29702 | The two streams swallow platform errors (`handleError`) and drop any event that is not a number, so a source that errors never reaches the recorder's un-handled `listen`. | `WatchSensorRecorder._startHeartRate` 202-208 |
| D-29703 | New `WearPlatformWorkoutStore implements WatchPlatformWorkoutStore` that opens nothing and closes nothing (`inProgressActivityTypes` empty): the Health Services exercise session is plan 300; the Wear wrist registers no platform workout yet. | `WatchPlatformWorkoutStore` 357-365 |
| D-29704 | `WearApp` takes an optional `WatchSessionSensors? sensors`. `WearAppState._syncSensors()` runs at the top of `_syncTicker()` (the one place every start, restore, end, discard and phone-ended path already passes through): it starts the sensors for an active session whose id differs from the one already started, and stops them when no session is active. Start and stop are chained on one future lane, each step given up after 5 seconds (added when a hung cancel blocked the next session in the tests); a failure is reported through `debugPrint` and never thrown. | `wear_app.dart` 248-257, 222, 242, 270, 281, 287, 344 |
| D-29705 | `_logging` is built with `sensors: widget.sensors?.recorder`, so the existing sensor line reads the recorder. At launch `_boot` calls `sensors.recoverInProgress()` before `engine.restore()` (a no-op store today; the contract is the Apple one). | `watch_logging_state.dart` 128, 170 |
| D-29706 | `wear_main.dart` builds `WatchSessionSensors(platform: WatchPlatformWorkout(store: const WearPlatformWorkoutStore()), recorder: WatchSensorRecorder(engine: engine, source: WearSensorSource()))` and passes it. | `wear_main.dart` 53-89 |
| D-29707 | Not in scope: any Kotlin (plans 298 heart rate, 299 distance), the platform workout (plan 300), GPS policy changes, a permission explainer screen, and heart rate on the phone. | plan 280 item 9 |

## Input-reality checklist

1. **Writers.** The recorder writes sensor rows through the engine (existing); the shell is the only starter and stopper. Two paths can call `_syncTicker` at once (a frame and a tap): the lane and the per-session-id memo keep one start.
2. **Units.** Beats per minute and metres, as the recorder already stores them.
3. **Lifecycle.** Cold start with a restored active session starts sensors after restore; a session ended while the app is closed starts nothing; a kill drops the subscriptions and the next launch's restore starts them again (the readings already stored stay). A phone-ended session stops them.
4. **Settings changing while open.** None. A permission the user changes in system settings mid-session takes effect at the next session.
5. **Time.** None.
6. **Load.** One platform call per start, one subscription per sensor; samples are the recorder's existing cost.
7. **Wording.** None (the sensor line already exists).
8. **Slot competition.** None.

Readers: `grep -rn "WatchSessionSensors\|WatchSensorRecorder\|sensorSource" lib test`: the debug surface (unchanged), `test/watch_sensor_recording_test.dart` (unchanged), `test/wear_logging_layout_test.dart` (builds `WatchLoggingState` directly). `WearApp`'s new parameter is optional, so every existing `WearApp(` caller (tests, the desktop harness) is unchanged.

## Scenarios

Source (`test/wear_sensor_source_test.dart`, new; channel mocks; plain `test()` plus `testWidgets` only where a binding is needed):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29701 | the methods channel answers `'granted'`, `'denied'`, `'unavailable'` | `heartRatePermission` and `locationPermission` map to the three enum values, each call naming its own method | a wrong mapping or the wrong method name |
| S-29702 | the channel answers null, an unknown string, and throws a `PlatformException`, and (no mock) a `MissingPluginException` | every case reads as `unavailable` | an error escapes or reads as granted |
| S-29703 | the heart-rate event channel sends `72`, `72.5`, `'x'`, `null`, then an error, then `80` | the stream yields `72.0`, `72.5`, `80.0` and never errors | a non-number reaches the recorder, or an error ends the stream |
| S-29704 | the location event channel sends `10`, `25.5` | `WatchLocationFix` values `10.0`, `25.5` | the location stream is wired to the wrong channel |
| S-29705 | `WearPlatformWorkoutStore` | `begin` and `end` complete, `inProgressActivityTypes` is empty | a stranded workout is reported |

Shell (`test/wear_sensors_shell_test.dart`, new; the harness of `wear_diagnostics_shell_test.dart`; a fake `WatchSensorSource` with stream controllers; explicit pumps, never `pumpAndSettle`; plain `await` of engine calls inside `runAsync` where a real delay is needed):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29706 | a granted fake; start a session through the engine and call `setState(_syncTicker)` the way `_started` does (via the Start screen's Free workout) | the heart-rate controller has a listener; a beat of 91 is stored (`engine.newestSensorSamples()`) and the logging screen's sensor line shows 91 | the sensors are never started |
| S-29707 | the same; finish the session from the menu | the controller's listener is cancelled; a later beat is not stored | the sensors outlive the workout |
| S-29708 | a session already active in the store before launch | after boot the controller has a listener | a restored session records nothing |
| S-29709 | the phone ends the session (a `session_lifecycle` completed frame through the transport) | the listener is cancelled | a phone-ended session keeps listening |
| S-29710 | a denied fake | no listener, no stored beat, the logging surface still logs a set | denial blocks logging or records |
| S-29711 | a fake whose `heartRatePermission` throws | the app stays up, no exception escapes, a set still logs | a throwing source crashes the shell |
| S-29712 | two sessions in a row (start, finish, start another) | two listeners over time, one at a time, each cancelled at its end; the second session's id is not skipped as "already started" | the memo keeps the first id, or two start at once |

A source scan (S-29713, in the shell test): `wear_main.dart` holds one `WearSensorSource()` and one `WearPlatformWorkoutStore()` and passes `sensors:`; `wear_app.dart` calls `_syncSensors()` inside `_syncTicker`.

Guard families the lead proves by mutation: each permission mapping, the error and non-number filters, the start-once memo, the stop on every non-active state, the lane, the launch recovery call, the logging state's `sensors:` argument, the entry wiring.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — source, store, shell wiring, entry point** (`crew-builder-watch`; scope `lib/watch/sensors/wear_sensor_source.dart` (new), `lib/watch/app/wear_app.dart`, `lib/watch/wear_main.dart`). Exact code in the brief. About 130 lines.
2. **P2 — tests** (lead): the two new files.
3. **P3 — docs** (lead), then **Lead:** analyze, the APK, the mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | ## The sensors | S-29706 |
| docs/wear_os_app.md | ADDED | - | `test/wear_sensors_shell_test.dart` | S-29706 |
| docs/wear_os_app.md | ADDED | - | `test/wear_sensor_source_test.dart` | S-29701 |

The sensors section says what exists (the wiring, the contract) and what does not (the native clients, plans 298 to 300), so no sentence promises a heart rate a watch cannot yet show. Docs delta stale-term sweep: `docs/wear_os_app.md` says the wrist has no heart-rate source ("The wrist has no heart-rate source yet (the live feed is plan 280 item 9)"): left true, with a pointer, because the source still reads `unavailable`.

## Assumption Log

- `WatchLoggingState` reads `sensors.readings` on every build, and the shell rebuilds once a second while a session is active, so a stored beat shows within a second without a new notifier.
- Every path that changes the active session already calls `setState(_syncTicker)` (grep of `wear_app.dart`: lines 222, 242, 270, 281, 287, 344), so one hook in `_syncTicker` covers them.
- `MethodChannel` calls with no handler throw `MissingPluginException`; an `EventChannel` with no handler errors on listen: both are swallowed here, so the Wear build without the native half runs as today.

## Progress

- [x] P1 source, store, shell wiring, entry point (crew builder, 1.9 min; the 5 s step timeout added by the lead after the tests found a hung `cancel`)
- [x] P2 tests (lead; S-29701..S-29715, 19 tests)
- [x] P3 docs (`docs/wear_os_app.md`: the sensors section and two test bullets; 40.7 KB)
- [x] Verify and prove: analyze 174 / 0; Wear APK builds; 20 of 20 mutants killed; emulator smoke
- [ ] Next: plan 298 (Kotlin heart rate: Health Services, BODY_SENSORS permission, synthetic data on the emulator), then 299 (distance), then 300 (platform workout)
