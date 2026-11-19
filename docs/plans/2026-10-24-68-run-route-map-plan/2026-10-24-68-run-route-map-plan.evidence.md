# 68 evidence

Built 2026-10-24 on base `af26d6ae`, uncommitted. The owner answered "yes" to the question "build with the plan's defaults, or change some first", so every default (Q1-Q9) stands.

## Crew runs
Phase 1: A (package production code), B (keeper tests, 16), C (tee tests, 6). Phase 2: D (watch app production code), E (source guards, 7), fix 1 (one guard tightened), G (docs keeper). No other fix round. Governor actions: the permission sentence in the project file (D-16), done by the lead.

## Observed by the lead
- Baseline before any edit (from run A's report): `WatchSessionEngineTests` 916 tests, 0 failures.
- Full package `swift test`: `Executed 945 tests, with 0 failures` (916 + 16 keeper + 6 tee + 7 source guards).
- `xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)"`: `** BUILD SUCCEEDED **` (the new `HealthKitRouteRecorder` compiled). The build rewrote `project.pbxproj` (objectVersion, package reference); reverted with `git checkout` and the one sentence change re-applied, as in the earlier lessons.
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`: `+42: All tests passed!`. Invariant grep (`hive_workout_repository` in `lib/state lib/features lib/widgets lib/core`): empty. No Dart file changed.
- Residue: `Route geometry is out of scope` is gone from `docs`, `watch`, `ios` outside `docs/plans`; `No route or map is stored` appears once, in the new sentence "…stored on the wrist's own log; the only route is the one handed to Health".

## Mutation pass (lead, in place, original restored and compared after each)
Package (16 of 16 killed): spread floor 50.05 (S-9807b), floor 48.9 (S-9807c), speed gate removed (S-9806a), later-than guard removed (S-9804), batch 11 (S-9801, S-9807), accuracy 50 refused (S-9803), accuracy 0 refused (S-9803), begin instant excluded (S-9805), offer ignores recording (S-9813, S-9814), close keeps recording (S-9813), open keeps the count (S-9813), outdoors not required (S-9814), sharing not required (S-9814), observer sees stale fixes (S-9815a), observer never called (S-9810, S-9815a, S-9816a), remainder dropped at close (S-9801, S-9803, S-9804).
App target (9 of 9 killed after one fix): route dropped from the share list (S-9817), final finish removed (S-9819), observer not registered (S-9820), permission sentence reverted once (S-9821), altitude not carried (S-9821), recovery flag not set (S-9822), close after the session ends (S-9819), second subscription (S-9818a). One mutant survived the first time (an extra early `routeRecorder.finish(` before the workout is saved: the guard looked only at the last call); fix 1 made the guard count exactly two calls and place them, and the mutant is now killed.
Note on S-9807: the exact 50.0 m boundary cannot be hit with decimal latitudes; the tests pin 50.038 (saves) and 48.926 (discards), and the mutants at 50.05 and 48.9 prove both sides.

## Not checked
Everything HealthKit does with the points: Fitness drawing the map, GPS with the wrist down, recovery after a kill, Health's permission sheet. These are the owner device checks ODC-1..ODC-9 listed in `docs/state_management/watch_sensors.md` ("Route in Apple Fitness"). No separate reviewer run; the lead read the diffs.
