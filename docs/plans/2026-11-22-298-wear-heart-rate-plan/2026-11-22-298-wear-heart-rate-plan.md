# Plan 298 — The Wear wrist reads the heart rate: the Health Services client (plan 280 item 9, part 2 of 3)

Plan 297 wired the Dart sensor layer and fixed the channel contract (`omnitrain/wear_sensors/methods` with `heartRatePermission` and `locationPermission`, event channel `omnitrain/wear_sensors/heart_rate`); until now no native half answers, so every Wear build reports "unavailable". This plan is the native half for heart rate: a Kotlin client over Health Services' `MeasureClient` with the body-sensor runtime permission. Distance (plan 299) and the platform workout (plan 300) stay out. Wear flavor only: the phone flavor gets a no-op registrar and no new dependency. No Dart, wire, schema or Swift change. Base commit: `.work/2026-11-22-298-wear-heart-rate/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On a Wear watch that has a heart-rate sensor, starting a workout asks for the body-sensor permission once the user has not decided; on yes the logging surface's sensor line shows `NN bpm` updating while the workout runs and the heart rate is stored with the session (so the Workout done screen's `Avg HR` row appears); on no, or on a watch with no sensor, nothing changes and logging is unaffected. Closing the workout stops the platform subscription.

Acceptance: S-29801..S-29805 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the Wear debug APK and the phone debug APK both build; S-29806 observed on the Wear emulator with Health Services synthetic data (permission prompt, then bpm on screen through the real channel); Docs delta applied.

## Feature invariants

- Logging never depends on a sensor: every native failure answers `unavailable` or ends the stream, never throws into Dart.
- The phone flavor is unchanged: no Health Services dependency, no body-sensor permission, a registrar that returns nothing.
- One subscription per workout: `onListen` registers, `onCancel` unregisters; a second listen replaces the first.
- The permission name is the one the platform version wants: `android.permission.BODY_SENSORS` below API 36, `android.permission.health.READ_HEART_RATE` from API 36.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29801 | The client lives in the app module, not a plugin: `WearSensors` in `android/app/src/wear/kotlin/dev/sasha/omnitrain/`, a `SensorBridge` interface in `src/main`, and a `registerSensors(activity, engine)` function declared once per flavor (`src/wear` builds `WearSensors`, `src/phone` returns null). `MainActivity` calls it in `configureFlutterEngine` and forwards `onRequestPermissionsResult`. | plan 297 D-29701; `MainActivity.kt` |
| D-29802 | `heartRatePermission` first asks `MeasureClient.getCapabilitiesAsync()`: a sensor-less watch answers `unavailable`. Granted answers `granted` without a prompt; otherwise it calls `Activity.requestPermissions` (the framework call: `FlutterActivity` is not an `androidx` `ComponentActivity`, which is why the `health` plugin fails to register on Wear) and answers `granted` or `denied` from the result; calls that arrive while a prompt is open wait on the same answer. | plan 297 evidence (the `health` plugin `ClassCastException`) |
| D-29803 | `locationPermission` answers `unavailable` (plan 299); the location event channel is not registered. | plan 297 D-29701 |
| D-29804 | The heart-rate event channel registers a `MeasureCallback` for `DataType.HEART_RATE_BPM` on listen (only when the permission is held; otherwise it ends the stream) and sends each reading's last value as a double on the main thread; cancel unregisters. | Health Services `MeasureClient` |
| D-29805 | The wear manifest declares `android.permission.BODY_SENSORS` and `android.permission.health.READ_HEART_RATE`; the dependency is `androidx.health:health-services-client:1.0.0` for the wear flavor only. | Wear OS 6 moved heart rate to the health permission group |
| D-29806 | Not in scope: ambient/always-on sampling, background heart rate, the `ExerciseClient` workout (plan 300), calories, distance (plan 299), an explanatory screen before the system prompt. | plan 280 item 9 |

## Input-reality checklist

1. **Writers.** The platform writes readings; Dart's recorder stores them (plan 297). Two heart-rate permission calls can overlap (a session start and a restore): both wait on one prompt.
2. **Units.** Beats per minute as a double.
3. **Lifecycle.** The prompt backgrounds the app and resumes it: the Dart call waits on the method channel result. A kill drops the callback with the process. A rotation or recreate of the activity re-registers the channels (the stream restarts on the next listen).
4. **Settings changing while open.** The user revokes the permission in system settings mid-workout: the platform stops the callback; the Dart stream goes quiet; the next workout asks again.
5. **Time.** Readings arrive about once a second while the sensor is on; Health Services may report availability changes (acquiring, off wrist): unavailable readings send nothing.
6. **Load.** One callback; one number per reading; the recorder stores each (existing cost).
7. **Wording.** The prompt text is the system's.
8. **Slot competition.** None. The system prompt shows over the logging surface once per undecided workout start.

## Scenarios

Source guards (`test/wear_heart_rate_native_test.dart`, new; plain `test()` reading the Kotlin, gradle and manifest text with CRLF normalised; no Kotlin harness exists):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29801 | `WearSensors.heartRatePermission` | asks `getCapabilitiesAsync`, answers `unavailable` when `HEART_RATE_BPM` is not supported, answers `granted` when `checkSelfPermission` is granted, else requests the SDK-dependent permission | a sensor-less watch prompts, or a held permission prompts again |
| S-29802 | `onRequestPermissionsResult` | ignores other request codes (returns false), answers every waiting call `granted` or `denied` from the first grant result, clears the waiting list | a prompt answers one caller only, or another request code is swallowed |
| S-29803 | the event channel's `onListen` and `onCancel` | listen ends the stream without the permission, otherwise registers a `MeasureCallback` for `HEART_RATE_BPM`; the callback posts the last value as a double to the sink; cancel unregisters and clears the sink | a stream with no permission, a reading dropped or not on the main thread, or a leaked callback |
| S-29804 | `MainActivity`, the two registrars | `MainActivity` stores the bridge from `registerSensors(this, flutterEngine)` and forwards `onRequestPermissionsResult` before `super`; the phone registrar returns null; the wear registrar builds `WearSensors`; the channel names in `WearSensors` equal `WearSensorSource`'s constants | the phone flavor changes, the prompt answer never arrives, or the Kotlin and Dart names drift |
| S-29805 | the wear manifest, the phone manifest and `build.gradle.kts` | the wear manifest declares both permissions; the phone manifest declares neither; the dependency is declared for `wearImplementation` only | the permission is missing (the prompt never shows) or the phone app gains a dependency |

Emulator (lead, observed, S-29806): the Wear debug APK on `OmniWear_Small` with a throwaway Dart entry that shows the `WearSensorSource` heart-rate stream: the system permission prompt appears on the first ask; after granting, with Health Services synthetic data switched on (`adb shell am broadcast -a "whs.USE_SYNTHETIC_PROVIDERS" com.google.android.wearable.healthservices`, then `whs.synthetic.user.START_WALKING`), bpm values appear on screen; stopping the stream stops the callback. The probe entry is deleted after.

Guard families the lead proves by mutation: the capability answer, the granted shortcut, the SDK threshold, the result mapping and the waiting list, the request-code check, the permission gate on listen, the data type, the last-value read, the main-thread post, the unregister, the forwarding in `MainActivity`, both manifests, the dependency flavor.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — the Kotlin client, the registrars, MainActivity, manifests and gradle** (`crew-builder-watch`; scope `android/app/src/main/kotlin/dev/sasha/omnitrain/SensorBridge.kt` (new), `.../MainActivity.kt`, `android/app/src/wear/kotlin/dev/sasha/omnitrain/WearSensors.kt` (new), `.../SensorsRegistrar.kt` (new, wear), `android/app/src/phone/kotlin/dev/sasha/omnitrain/SensorsRegistrar.kt` (new, phone), `android/app/src/wear/AndroidManifest.xml`, `android/app/build.gradle.kts`). Exact code in the brief. About 150 lines. The lead compiles it (`flutter build apk` for both flavors) and fixes API mismatches the compiler finds.
2. **P2 — tests** (lead): the guard file.
3. **P3 — docs** (lead), then **Lead:** analyze, both APKs, the emulator proof, the mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | The heart rate comes from Health Services' `MeasureClient` | S-29803 |
| docs/wear_os_app.md | ADDED | - | `test/wear_heart_rate_native_test.dart` | S-29801 |
| docs/wear_os_app.md | MODIFIED | The wrist has no heart-rate source yet (the live feed is plan 280 item 9) | The wrist reads the heart rate from Health Services (plan 298) | S-29803 |

`## The sensors` says "Not built: the Health Services heart-rate client (plan 298)": the keeper-free edit updates that sentence to say it is built and what stays unbuilt (distance, the platform workout). Owner check 17 is added for a real watch (the prompt, the live number, the Avg HR on the summary).

## Assumption Log

- Health Services' `MeasureClient` delivers `HEART_RATE_BPM` as `SampleDataPoint<Double>` readings inside a `DataPointContainer`; the emulator's synthetic provider produces them (platform contract; S-29806 observes it).
- API 36 (Wear OS 6) uses `android.permission.health.READ_HEART_RATE` for heart rate instead of `BODY_SENSORS`; the emulator is API 34, so the API 36 branch is not exercised here: owner check 17 on a Wear OS 6 watch.
- `MeasureCallback`'s registration callbacks are optional (Java default methods); if the compiler says otherwise the lead adds them.
- The earlier emulator crash was tied to writing data-layer items, not to sensors; a probe entry that never writes a data item does not trigger it.

## Progress

- [x] P1 the Kotlin client and its wiring (lead-written: the watch builder may not write under `android/`; Guava added after the first compile)
- [x] P2 tests (lead; S-29801..S-29805, 5 source guards)
- [x] P3 docs (`docs/wear_os_app.md`: three sentences changed or added, a tests bullet, owner check 17)
- [x] Verify and prove: analyze 174 / 0; both APKs build; 21 of 21 mutants killed; S-29806 observed on the emulator (prompt, grant, denial, live synthetic readings)
- [ ] (owner) check 17 in `docs/wear_os_app.md` on a real watch (Wear OS 5 and 6)
- [ ] Next: plan 299 (distance), plan 300 (platform workout); and a layout plan for the logging surface's bezel clipping
