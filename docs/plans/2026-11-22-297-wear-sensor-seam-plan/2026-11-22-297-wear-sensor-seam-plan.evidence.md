# Plan 297 evidence

Base commit `e1faa678`. Windows PC: the full suite is red in the baseline and was not run; evidence is the touched and neighbouring files, `flutter analyze`, the APK and a smoke on the emulator.

## Builds

- P1: `crew-builder-watch`, run `20261122-152414`, 1.9 min, no denial, no stop. Three files, as briefed (the new source file, the shell wiring, the entry point). `dart format` also reflowed two unrelated spots (the theme scheme in `wear_app.dart` and the diagnostics line in `wear_main.dart`).
- Lead edits after the builder: the 5 s step timeout in the sensor lane (found by the tests, below), the tests, the docs, the mutation pass.

## Finding that changed the design

The first shell test of a second session hung: under the test's fake clock a `StreamSubscription.cancel()` of a controller-based stream never completes unless its `onCancel` returns a completed Future (probed: single-subscription with `onCancel: () => Future.value()` completes; with a void `onCancel`, a broadcast controller or a sync controller it does not). The same shape in production is a native `cancel` that never answers, which would have blocked every later session's sensors behind the stuck stop. The sensor lane now gives each start or stop 5 seconds (`_sensorStepTimeout`), and S-29714 guards it with a fake whose cancel never answers.

## Checks (observed)

- `flutter test test/wear_sensor_source_test.dart test/wear_sensors_shell_test.dart`: `+19: All tests passed!` (source file 7 tests, shell file 12).
- `flutter analyze` (whole repo): `174 issues found.` (baseline 174, 0 errors).
- `flutter build apk --debug --flavor wear -t lib/watch/wear_main.dart`: built.
- Emulator `OmniWear_Small` (headless): the new build installs, launches and runs with the sensor source answering "unavailable"; the radio's `not_reachable` lines are the unpaired state. No crash.
- Seen on the emulator and not caused by this plan: at launch the `health` plugin logs `ClassCastException: dev.sasha.omnitrain.MainActivity cannot be cast to androidx.activity.ComponentActivity` from `HealthPlugin.onAttachedToActivity` (non-fatal; the plugin never registers on the Wear flavor). The native heart-rate plan (298) needs an activity for the permission prompt, so it must not rely on that plugin.

## Mutation pass (lead; in place, backup outside the tree, restored and compared after each)

20 mutants over the three files: each permission mapping (granted, denied, a failure, an unknown answer); heart rate and location asking each other's method; stream errors reaching the listener; non-numbers passing the filter; the location channel renamed; the store reporting a stranded workout; the ticker no longer syncing sensors; no once-per-session memo; never stopping on a non-active session; the stop branch keeping the old id; steps not awaited; the step timeout removed; launch recovery removed; the logging state getting no recorder; dispose not stopping; the entry point passing no sensors. **20 of 20 killed.** The first pass left two alive, closed by tests: the channel-name literals were not pinned (they are the contract with the native half) and a repeated stop per tick was invisible (now `stops` is counted by a subclass and must be 1).

## Not verified here

- Anything native: no heart rate or distance can appear on a watch until plans 298 and 299 land.
