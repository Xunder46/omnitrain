# Plan 298 evidence

Base commit `2d1196d7`. Windows PC: the full suite is red in the baseline and was not run; evidence is the touched file, `flutter analyze`, both APKs and the emulator.

## Builds

- The crew's watch builder may not write under `android/` (its write ceiling is `watch/** lib/watch/** test/** docs/** .work/crew/** ios/OmniTrain Watch App/** packages/**`; the runner refused the scope). The write scope was not widened. The lead wrote the six Android files from the brief's exact code (the brief is in `.work/crew/`), then compiled and fixed what the compiler found. No crew run happened for this unit.
- One compile fix: Health Services' futures are Guava's `ListenableFuture`, which the client library does not export, so the wear flavor also takes `com.google.guava:guava:33.0.0-android`. The first compile otherwise passed (the `MeasureCallback` registration callbacks are optional, as assumed).

## Checks (observed)

- `flutter build apk --debug --flavor wear -t lib/watch/wear_main.dart`: built (Kotlin compiles, the Health Services dependency downloaded).
- `flutter build apk --debug --flavor phone`: built (the phone flavor compiles with the no-op registrar and no new dependency).
- `flutter test test/wear_heart_rate_native_test.dart`: `+5: All tests passed!`.
- `flutter analyze` (whole repo): `174 issues found.` (baseline 174, 0 errors).

## Emulator (S-29806), `OmniWear_Small`, Wear OS 5 (API 34), headless

- A throwaway Dart entry (deleted) showing `WearSensorSource`'s answer and stream, installed as the wear debug APK:
  - First launch with the permission revoked: the system prompt appeared from the Kotlin path ("Allow OmniTrain to access sensor data about your vital signs?", buttons "While using app" and "Don't allow").
  - "While using app", then Health Services synthetic data on (`whs.USE_SYNTHETIC_PROVIDERS`, `whs.synthetic.user.START_WALKING`): the screen showed `perm: granted`, `130 bpm`, `readings: 15` and kept counting.
  - Revoke, relaunch, "Don't allow": `perm: denied`, `- bpm`, `readings: 0`.
- The real app (permission granted with `pm grant`): a restored active session shows the logging surface with the heart-rate line present (`... bpm`), so the real shell started the sensors through the channel. The line's first characters are clipped by the round bezel (see Found).
- Not run: the full real-app flow from a started workout (the emulator has no exercises to pick and no phone), the Wear OS 6 permission name, and a real sensor.

## Mutation pass (lead; in place, backup outside the tree, restored and compared after each)

21 mutants over the Kotlin client, `MainActivity`, the registrar, the wear manifest and gradle against the five source guards: unsupported answering granted; the granted shortcut removed; never prompting; the API 36 threshold moved; every ask re-prompting; any request code accepted; the grant result inverted; the waiting list not cleared; only the first waiting caller answered; listening without the permission; first instead of last reading; the reading not posted to the main thread; the callback never unregistered; location answering granted; the sink kept after cancel; the activity registering no sensors; the prompt result not consumed; the wear registrar returning nothing; each permission undeclared; the dependency leaking to the phone. **21 of 21 killed.** These prove the text and its order, not behaviour; the behaviour proof is the emulator run above.

## Found, not fixed

- The logging surface's first lines are clipped by the round bezel at 192 dp (the exercise name and the `NN bpm` line start at the left edge, inside the clipped corner of the circle): the same defect plan 296 fixed on the Start screen with 16 dp of room above the first item. It needs its own plan (owner check 5's corner clipping, now seen).
- A free workout started with nothing synced has no exercise to pick; the shell starts the sensors when it next re-reads the session (an exercise add, a restore), not at the first tap on `Free workout`.
