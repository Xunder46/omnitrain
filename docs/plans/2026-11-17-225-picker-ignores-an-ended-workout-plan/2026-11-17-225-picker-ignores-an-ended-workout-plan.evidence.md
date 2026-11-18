# Plan 225 — evidence (lead, 2026-11-17)

## Repro on the base commit (before any build)

`swift test --filter WatchEndedSessionPickerTests` (lead-written test, base `9e1e5a65` + plan 223's uncommitted view files):
`Executed 3 tests, with 28 failures (0 unexpected)`. S-22501 red 12/12 (in-session rows offered; only Goblet Squat available; ranks by `resistance_lifting`), S-22503 red 16/16 (both picks return the ended record, 2 rows appended, 2 frames sent), S-22502 green (regression guard). Every case red both without and with a relaunch, for a discarded and a finished workout.

## After P1

- `swift test --filter WatchEndedSessionPickerTests`: 3 tests, 0 failures (builder and lead).
- `swift test` whole package (lead): `Executed 1594 tests, with 0 failures (0 unexpected)`.
- Watch app: `xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)"` → `** BUILD SUCCEEDED **`.
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`: +54, all passed. Invariant grep: no hits.

## Mutation pass (lead, isolated copy of `watch/` + watch app + pbxproj in the scratchpad)

Baseline GREEN (`WatchEndedSessionPickerTests|testS19911|testS19922|testS20113`).
a `liveSession` ignores status: KILLED · b `pickerRows` reads `engine.session`: KILLED · c `listModality` reads `engine.session`: KILLED · d `selectExercise` guard removed: KILLED · e `availablePickerExercises` reads `engine.session`: KILLED · f `startModalityWorkout` adds to any held session: KILLED (S-22502).

## Lead review

Diff matches the brief line for line; no other `engine.session` read changed. Readers re-checked: the menu (`WatchMenu.swift:251`, `:323`) runs only over a live workout; the picker view's start-mode `.available` route is unchanged; S-19911/S-19922 green. No findings.
