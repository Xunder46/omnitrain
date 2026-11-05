# Evidence: 59 — Health and Location access up front, denial visible

## Baselines (2026-10-23)

- `swift test` in `watch/watchos` before this plan: 814 tests, 0 failures (plan 58 built).
- `flutter analyze`: 180 issues, all `info` in `test/`, 0 errors; Dart untouched.

## Phases

| Phase | Run | What | Builder's counts |
|---|---|---|---|
| P1 | crew-builder-watch, 5.7 min, 45 requests | recorder access fields, `WatchHealthAccess` + copy, `sensorNotices` on state and model, 14 tests (S-8901..S-8907) | `WatchSessionEngineTests` 828 tests, 0 failures (814 + 14); one compile error in its own first test run (a local shadowed a helper), fixed by it |
| P2 | crew-builder-watch, 2.8 min, 23 requests | logging view lines, Start-screen line, `requestAccess`, host `askHealthAccess` + `.task`, S-8908 (4 tests) | `WatchSessionEngineTests` 832 tests, 0 failures |
| P3 | crew-docs-keeper, 6.2 min, 35 requests | `watch_sensors.md`, `watch-app-setup-and-qa.md` (new QA step 26 `(owner)`) | did not run the suite (the gateway `test` is the full run) |

## Governor read-backs

- `swift test` (full): 832 tests, 0 failures after P2.
- `xcodebuild` (workspace `ios/Runner.xcworkspace`, scheme "OmniTrain Watch App", watchOS Simulator 42mm, scratch derived data): BUILD SUCCEEDED after P2.
- `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`: 42 passed.
- Cited test names in the new docs were checked against the sources (10 of 10 exist).

## Mutation pass (governor, scripted, `cmp` restore after each)

15 mutants, 15 killed: heart-rate access not stored; location access not stored; `stop()` keeps either access (2); heart-rate notice inverted; distance notice ignores the current exercise; notice order swapped; `answer` unavailable→off; `answer` granted branch swapped; notice shown when never asked; a lift asks for location; Start line condition; `askHealthAccess` task removed; logging notices not rendered; store `requestAccess` guard removed. A later pass (with plan 60, tests tightened in fix round 2) adds the init-storage and rendered-text mutants for the view files.

## Not verified (owner)

- The Health sheet over the Start screen on first launch, the grey lines on a real watch or a fresh watch simulator, and the Location behaviour at the first run (QA step 26).
- Apple does not report a refused *read* permission: a user who allows the workout but refuses only heart rate sees no line (stated in the plan).
