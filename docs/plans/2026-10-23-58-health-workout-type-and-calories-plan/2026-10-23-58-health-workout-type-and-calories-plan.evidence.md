# Evidence: 58 — Health workout type and calories

## Baselines (2026-10-23, base 83c933a8)

- `swift test` in `watch/watchos`: 802 tests, 0 failures (plan 56 evidence).
- `flutter analyze`: 180 issues, all `info` in `test/` (deprecated test APIs), 0 errors; Dart is untouched by this plan.

## Phases

| Phase | Run | What | Builder's counts |
|---|---|---|---|
| Scouts (2) | crew-scout x2, 2.6 and 2.9 min | what the wrist knows at workout open; silent-failure map (also feeds plans 59/60) | sheets spot-checked (4 quotes against files, all matched) |
| P1 | crew-builder-watch, 4.8 min, 32 requests | `forExercise`/`forExercises`/`forSession`, lifecycle waits for an unknown type, 11 new tests | `--filter WatchSessionEngineTests` 813 tests, 0 failures; two readers broke as predicted (`WatchGpsByExerciseTests` S-4807/S-4813, `WatchSensorRecordingTests` S-007) and were changed to follow the new rule, nothing weakened |
| P2 | crew-builder-watch, 1.6 min, 18 requests | active energy shared, read and collected; S-8812 | `WatchSensorSourceSourceTests` 17/0, `WatchWorkoutStoreSourceTests` 1/0 |
| P3 | crew-docs-keeper, 10.6 min, 28 requests | `watch_sensors.md`, `watch-app-setup-and-qa.md` (new QA step 25 `(owner)`) | its own full `flutter test` run: 5437 passed, 2 skipped |
| Review | crew-reviewer, 3.8 min, 27 requests | verdict APPROVE, no findings (see `.review.md`) | |

## Governor read-backs

- `swift test` (full, watch/watchos): 814 tests, 0 failures (802 + 11 + 1).
- `xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)"` with a scratch derived-data path: BUILD SUCCEEDED. (A `-target` build without the workspace fails with "unable to resolve module dependency: WatchSessionEngine" and leaves `watch/watchos/build/`; remove it. Use the workspace form.)
- Invariant grep (`import .*hive_workout_repository` in `lib/state lib/features lib/widgets lib/core`): empty (builder P1/P2 and docs keeper reports).
- Diff vs Predicted Files: exactly the 8 predicted files plus the docs.

## Mutation pass (governor, scripted, restore checked with `cmp` after each)

13 mutants, 13 killed. `M1` first-exercise-decides; `M2` tie to the last exercise; `M3` hold test removed; `M4` distance test off; `M5` strength list replaced (the first variant did not compile, a compiling variant was used); `M6` lifecycle starts when type unknown; `M7` modality no longer wins; `M8` start uses the old modality rule; `M9` missing capabilities default changed; `S1` energy out of the share list; `S2` out of the read list; `S3` `enableCollection` line removed; `S4` workout type out of the share list. No prover run was made: the lead's pass covers the unit's guards directly (saved one run).

## Not verified (owner, real watch)

- The type Apple Health shows (Strength Training / Running) and Move-ring credit after a strength workout (QA step 25).
- Simulator seeding of a routine and a Free workout to watch the begin log: not done in this unit; the package tests (S-8807/S-8808) cover when the workout opens.
