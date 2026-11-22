
# Plan 299 evidence

Base commit `14b879a2` (plan 301). Windows PC: the full suite is red in the baseline; evidence is the touched files, `flutter analyze`, both APKs and the emulator.

## Builds

- The crew's builders may not write under `android/` (as in plan 298): the lead wrote the Kotlin, the manifest and gradle edits. No crew run.
- Compile fixes: the channel setup `init` had to move below `locationStream` (a property used before it was initialised); nothing else. Play services location 21.3.0 downloaded and compiled.
- Found on the emulator and fixed before the tests: the first probe read 222019.5 m after five simulated fixes 55 m apart. The fused provider's first fix was a long way from the rest (the emulator's earlier position); the tracker took it as a step. Two guards were added: a fix older than 10 s is dropped, and a step that implies more than 15 m/s re-anchors without adding. The plan's decision and scenario text was changed to match.

## Checks (observed)

- `flutter test test/wear_distance_native_test.dart test/wear_heart_rate_native_test.dart`: `+10: All tests passed!` (the heart-rate guards S-29801 and S-29802 were updated: the location call now routes to the location question and the prompt answer goes through a dispatcher).
- `flutter analyze` (whole repo): `174 issues found.` (baseline 174, 0 errors).
- `flutter build apk --debug --flavor phone` and `--flavor wear -t lib/watch/wear_main.dart`: both built.

## Emulator (S-29906), `OmniWear_Small`, Wear OS 5, headless

- A throwaway Dart entry (deleted) showing `WearSensorSource`'s location answer and stream:
  - With the permission revoked, the system prompt appeared from the Kotlin path ("Allow OmniTrain to access this device's location?", a precise-location toggle, and "Only this time" / "Don't allow" buttons); "Only this time" gave `perm: granted`.
  - First run with five fixes 55 m apart: `222019.5 m` (the glitch above); after the guards: `15.1 m` over 10 fixes (the 55 m jumps in 2 to 4 s are over 15 m/s, correctly not distance).
  - A walking-pace run (`adb emu geo fix`, 0.00005 degrees, about 5.5 m, every 2 s, 14 fixes): the reading went from `15.1 m` to `91.3 m`, +76.2 m for about 77 m walked.
- Not run: the full real-app flow (a started run with distance), a real GPS, the unit conversion on screen, the Wear OS 6 behaviour.

## Mutation pass (lead; in place, backup outside the tree, restored and compared after each)

27 mutants over `WearSensors.kt`, `DistanceTracker.kt`, the wear manifest and gradle against the source guards: no GPS check; the granted shortcut removed; never prompting; coarse not requested; every ask re-prompting; the location code equal to the heart-rate code; the answer not routed; the grant result inverted; the waiting list not cleared; listening without the permission; the wrong priority; the interval changed; no minimum step; stale fixes accepted; the total not posted to the main thread; cancel keeping the total; updates never removed; the channel not registered; any accuracy accepted; the speed guard removed; an out-of-order fix accepted; the anchor time not moved; reset keeping the total; the speed limit loosened; each location permission undeclared; the dependency leaking to the phone. **27 of 27 killed.** These prove the text and its order, not behaviour; the behaviour proof is the emulator run.

