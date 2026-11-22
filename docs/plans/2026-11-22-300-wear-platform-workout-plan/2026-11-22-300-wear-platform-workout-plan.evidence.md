
# Plan 300 evidence

Base commit `d63de764` (plan 299). Windows PC: the full suite is red in the baseline; evidence is the touched files, the Wear test set against the baseline list, `flutter analyze`, both APKs and the emulator.

## Builds

- P1 (the Dart store and the translation helper): `crew-builder-watch`, run `20261122-173009`, 1.2 min, no denial, no stop. Three files, as briefed. `dart format` on the two sensor files only (never on `wear_main.dart`, which a test greps).
- P2 (Kotlin: `WearWorkout`, `WorkoutService`, the registrar, the manifest, `heartRateGranted` made public): lead-written, the crew's builders may not write under `android/`. It compiled on the first try (every `ExerciseType` constant and the `ExerciseConfig` builder existed).

## Checks (observed)

- `flutter test` on the store, source, shell, native and heart-rate and distance guard files: all pass; the Wear set (`test/wear_*_test.dart`, `test/watch_logging*_test.dart`, `test/watch_sensor_recording_test.dart`) has 12 failures, 11 in the Windows baseline and one that is the pre-existing path-separator failure `wear_os_config_test` S-28132 (it compares `lib/watch/debug/` with backslash paths).
- Existing tests updated: the no-op store test S-29705 went with the no-op class; the shell test harness uses a local no-op store; S-29713 scans for `WearPlatformWorkoutStore(source: sensorSource)`; the heart-rate guard S-29804 matches the new registrar text.
- `flutter analyze` (whole repo): `174 issues found.` (baseline 174, 0 errors).
- `flutter build apk --debug --flavor phone` and `--flavor wear -t lib/watch/wear_main.dart`: both built.

## Emulator (S-30011), `OmniWear_Small`, Wear OS 5, headless

- A throwaway Dart entry (deleted) that called the store: `begin('running')` with the body-sensor permission held: `dumpsys activity services dev.sasha.omnitrain` showed `WorkoutService` with `isForeground=true`, `foregroundId=30001`, `types=00000100` (health) and the `omnitrain_workout` notification channel; Health Services showed `ExerciseApiService` bound from the app and its `RecordingService`; the probe's `inProgress` read `[exercise_in_progress]` six seconds in (and `[]` before). After `end()`: the service was gone and `inProgress` read `[]`.
- Force-stopping the probe mid-workout stopped the service with the process; on relaunch `inProgress` read `[]`: the emulator's Health Services ended the exercise when its owner died, so the recovery path (end what is stranded) was not exercised on a real stranded exercise.
- The real app (permission granted with `pm grant`, a restored session): the shell began the workout and the foreground service was running (`isForeground=true` count 1).
- Not run: wrist-down behaviour, Wear OS 6, a real watch (owner check 20).

## Mutation pass (lead; in place, backup outside the tree, restored and compared after each)

28 mutants: the permission gate, the type translation, the begin and end calls, the in-progress call and its filter, a failure escaping, the channel name, the translation helper's default and its first-match rule, the entry wiring; in Kotlin the permission check, the service ordering (only after a successful start, stopped after the end), GPS, the data type, auto-pause, the default and lift types, the in-progress status, the end route, the service's type, ongoing flag and stickiness, the registrar, and the manifest's service, its type and the health permission. **28 of 28 killed.** Two survived the first pass and were closed: the Dart channel name was pinned only against its own constant (a literal check now), and `end` had two `stopService()` calls of which one could go unseen (now both counted and the last must follow the listener). The Kotlin guards prove text and order, not behaviour; the behaviour proof is the emulator run.

## Found, not fixed

- `exercise_type_cross_training` and `exercise_type_football` have no closer Health Services type and register as a generic workout (the guard lists them as deliberate).

