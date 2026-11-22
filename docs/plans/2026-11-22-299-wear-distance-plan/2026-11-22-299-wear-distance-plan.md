# Plan 299 — The Wear wrist measures distance: the fused-location client (plan 280 item 9, part 3 of 4)

Plan 297 wired the Dart side and fixed the location contract (`locationPermission` answering `granted`, `denied` or `unavailable`, and the event channel `omnitrain/wear_sensors/location` carrying cumulative metres since the session started); plan 298 built the heart-rate client and answers the location question `unavailable`. This plan answers it: a Kotlin client over Google's fused location provider that turns fixes into a running distance. The Dart side already subscribes only for an exercise that carries the `distance` capability (`WatchGpsPolicy`, plan 205), so a lift never wakes the radio. The platform workout stays out (plan 300). Wear flavor only. No Dart, wire, schema or Swift change. Base commit: `.work/2026-11-22-299-wear-distance/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On a Wear watch with GPS, starting a run or any exercise with a distance asks for the location permission once the user has not decided; on yes the logging screen's sensor line shows a distance that grows as the watch moves (in km or miles per the phone's unit setting, which the existing sensor line already applies) and the distance is stored with the session; on no, or on a watch with no GPS, nothing changes and logging is unaffected. Ending the workout or moving to an exercise without a distance stops the location updates.

Acceptance: S-29901..S-29905 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the Wear and phone debug APKs build; S-29906 observed on the Wear emulator (the prompt, a grant, then metres growing as simulated fixes move); Docs delta applied.

## Feature invariants

- Logging never depends on a sensor: every failure answers `unavailable` or ends the stream.
- The phone flavor is unchanged: no location dependency, no location permission.
- Distance is the sum of the steps between accepted fixes; a fix with no accuracy or worse than 50 m is ignored, and so is a fix more than 10 seconds old (a cached one); the first accepted fix starts the total at 0; each accepted fix after it adds the straight-line step from the one before, unless covering it would take more than 15 m/s: that jump is a new starting point, not distance (the emulator's first fix was 222 km from the rest and made the first probe read 222 km).
- One subscription per workout: `onListen` starts updates, `onCancel` removes them and forgets the last fix, so the next listen starts again from 0.
- A held permission is never asked for again; one prompt serves every waiting caller.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29901 | `WearSensors` answers `locationPermission`: no GPS feature (`FEATURE_LOCATION_GPS`) answers `unavailable`; `ACCESS_FINE_LOCATION` held answers `granted`; otherwise it asks for fine and coarse together (Android 12+ wants both in one request) with its own request code and answers `granted` when fine is granted, else `denied`. Heart-rate and location questions wait on separate lists. | plan 298 D-29802; Android 12 location rules |
| D-29902 | The location event channel `omnitrain/wear_sensors/location` is its own stream handler (an inner class): it ends the stream without the permission, else asks `FusedLocationProviderClient` for `PRIORITY_HIGH_ACCURACY` updates every 2 s with a 3 m minimum step, and sends the running total as a double on the main thread. | plan 297 D-29701 |
| D-29903 | The running total lives in a small `DistanceTracker`: `accept(latitude, longitude, accuracy, elapsedNanos)` ignores a missing or over-50 m accuracy and an out-of-order fix, starts at 0 on the first accepted fix, adds `Location.distanceBetween` of each later step unless it implies more than 15 m/s, and always moves the anchor to the fix; the stream also drops a fix more than 10 s old before it reaches the tracker. | feature invariants |
| D-29904 | The dependency is `com.google.android.gms:play-services-location:21.3.0` for the wear flavor only; the wear manifest declares `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`. | plan 298 D-29805 |
| D-29905 | Not in scope: route geometry, pace smoothing beyond the 3 m step, the platform workout (plan 300), ambient or background location, calories. | plan 280 item 9 |

## Input-reality checklist

1. **Writers.** The platform writes fixes; the recorder stores each total (plan 297). The location and heart-rate questions can overlap (a run starts both): each has its own waiting list and prompt.
2. **Units.** Metres as a double; the sensor line converts for display (existing).
3. **Lifecycle.** The prompt backgrounds the app and resumes it; a kill drops the updates with the process; an exercise change that leaves distance work cancels the stream (Dart); a new listen starts again from 0.
4. **Settings changing while open.** The user switches location off in system settings: updates stop, the total stays at its last value; the next workout asks again.
5. **Time.** Fixes arrive about every 2 s while moving; out of range or indoor fixes with poor accuracy are ignored.
6. **Load.** High-accuracy GPS is the battery cost, paid only for distance exercises and only while the stream is listened to.
7. **Wording.** The prompt text is the system's.
8. **Slot competition.** None.

## Scenarios

Source guards (`test/wear_distance_native_test.dart`, new; plain `test()` reading the Kotlin, gradle and manifest text with CRLF normalised; no Kotlin harness exists):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29901 | `WearSensors.locationPermission` | no GPS feature answers `unavailable`; a held fine permission answers `granted`; else it asks fine and coarse together; the call is routed from `"locationPermission"` | a GPS-less watch prompts, a held permission prompts again, or the call is unrouted |
| S-29902 | the prompt's answer | the location request code is distinct from the heart-rate one, every waiting location caller is answered from the fine result, the list is cleared, and another code returns false | a heart-rate answer resolves a location question, or one caller waits for ever |
| S-29903 | the location stream | listen ends the stream without the permission, then requests `PRIORITY_HIGH_ACCURACY` updates at 2000 ms with a 3 m minimum step and posts each total to the sink on the main thread; cancel removes the updates, clears the sink and resets the tracker | a stream with no permission, a total off the main thread, or a leaked update request |
| S-29904 | `DistanceTracker` | ignores a fix with no accuracy or accuracy over 50 m or out of order, starts at 0 on the first accepted fix, adds `Location.distanceBetween` of each step that implies at most 15 m/s, re-anchors on a faster one without adding it, and can be reset; the stream drops a fix more than 10 s old | a bad fix adds distance, a cached or glitched fix adds hundreds of kilometres, the total starts wrong, or a second workout starts from the last one's total |
| S-29905 | the wear manifest, the phone manifest and `build.gradle.kts` | the wear manifest declares fine and coarse location; the phone manifest neither; the dependency is `wearImplementation` only | the prompt never shows, or the phone app gains a permission or dependency |

Emulator (lead, observed, S-29906): the Wear debug APK on `OmniWear_Small` with a throwaway Dart entry showing the `WearSensorSource` location stream: the system location prompt appears on the first ask; after granting, simulated fixes (`adb emu geo fix <lon> <lat>` along a path) make the metres on screen grow by about the real step each time; a fix far from the others still adds its step. The probe entry is deleted after.

Guard families the lead proves by mutation: the GPS check, the granted shortcut, the request pair, the separate code, the waiting list, the permission gate, the priority, the interval and step, the main-thread post, the removal and the reset, the accuracy filter, the first-fix rule, the step sum, both manifests, the dependency flavor.

## Phases

1. **P1 — the Kotlin client** (lead-written: the crew's builders may not write under `android/`, as in plan 298; the exact code is in `.work/crew/2026-11-22-299-wear-distance/brief-lead-p1.md`): `DistanceTracker.kt` (new), `WearSensors.kt`, the wear manifest, `build.gradle.kts`. About 120 lines.
2. **P2 — tests** (lead): the guard file.
3. **P3 — docs** (lead), then the compile, both APKs, the emulator proof, the mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | The distance comes from the fused location provider | S-29903 |
| docs/wear_os_app.md | ADDED | - | `test/wear_distance_native_test.dart` | S-29901 |
| docs/wear_os_app.md | MODIFIED | Not built: distance (plan 299, the location question still answers `unavailable`) and the platform workout (plan 300) | Not built: the platform workout (plan 300) | S-29901 |

Owner check 19 is added for a real watch (the location prompt, a walk, the distance on the logging line and the summary).

## Assumption Log

- `FusedLocationProviderClient` on the Wear OS image works over Play services for Wear (`play-services-location` 21.x runs on Wear OS 3 and later); the emulator's `geo fix` feeds the fused provider.
- Location services are on by default on the emulator; if not, `adb shell settings put secure location_mode 3` turns them on and the probe notes it.
- A straight-line step between fixes under-counts a winding path by a little; accepted (no route geometry, plan 205).

## Progress

- [ ] P1 the Kotlin client
- [ ] P2 tests (S-29901..S-29905)
- [ ] P3 docs
- [ ] Verify and prove (both APKs, the emulator, mutation pass)
- [ ] (owner) check 19 in `docs/wear_os_app.md` on a real watch
