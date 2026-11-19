# Plan 90 evidence

## Phase 1 - Dart side (2026-10-28)

### Baselines (before any edit)

- `flutter analyze`: 180 issues.
- Full `flutter test` on a copy of the working tree as found (the other session's uncommitted
  `seedFirstInterval` to `seedFirstEntry` rename included), copied to a scratch folder before any
  plan 90 edit: `+5813 ~2: All tests passed!`, exit 0. The "about 29 failing" the brief expected
  did not reproduce: that tree was green.

### Order of work

1. Contract skeleton first so tests compile and fail on behaviour, not on missing symbols:
   `HealthEffortOutcome`, `setWorkoutEffort` / `clearWorkoutEffort` on the contract, the
   unavailable service and the io gateway (both answer `unavailable` / false), the mapper
   returning null, `onSessionRated` empty, the inbox's `healthSync` parameter unused. The three
   existing fakes got the two methods (answering `unavailable` / false).
2. `test/health_effort_test.dart` written against S-90-1 to S-90-7.
3. Red run, then the implementation, then green.

### Red run (skeleton only): `flutter test test/health_effort_test.dart` -> `+10 -17: Some tests failed.`

| Test | Red | Green |
|---|---|---|
| S-90-1 1..5 give 2,4,6,8,10 | fail | pass |
| S-90-1 0, 6, negatives null | pass (guard: the stub answers null) | pass |
| S-90-2 toggle on: one call, exact span, score 8 | fail | pass |
| S-90-2 toggle off / no rating / no end: no call | pass (guards, proven by M2) | pass |
| S-90-3 second rating calls again; same rating twice | fail, fail | pass |
| S-90-4 leftAlone / unavailable / error: no retry | fail x3 | pass |
| S-90-4 noWorkout at 0, 20 s, 90 s, 5 min then stops | fail | pass |
| S-90-4 a found workout stops; newer rating cancels; other session untouched; toggle off stops | fail x4 | pass |
| S-90-5 ended loaded session; ended unloaded session (calendar edit) | fail, fail | pass |
| S-90-5 running session; only-if-unrated that does not land | pass (guards, proven by M3) | pass |
| S-90-5 wrist import rates a landed session; import creates the session with its rating | fail, fail | pass |
| S-90-5 wrist import with no rating | pass (guard) | pass |
| S-90-6 finished discard: clear then delete, exact span | fail | pass |
| S-90-6 running discard calls neither | pass (existing rule) | pass |
| S-90-7 unavailable service; no file outside the gateway names `omnitrain/health_effort` | pass (the contract is the skeleton; the scan is a guard) | pass |

Green: `flutter test test/health_effort_test.dart` -> `+27: All tests passed!`

### Mutation checks (each restored exactly, then re-run green `+27`)

| Id | Original line | Mutant | Result |
|---|---|---|---|
| M1 | `return rating * 2;` (`health_effort_mapper.dart`) | `return rating;` | 7 fail, incl. `S-90-1 1, 2, 3, 4, 5 give 2, 4, 6, 8, 10` |
| M2 | `if (!_isWriteEnabled()) return;` (first gate in `onSessionRated`) | line removed | 1 fail: `S-90-2 toggle off: no call` |
| M3 | `if (rated == null \|\| rated.endedAtMs == null) return;` (`session_core_lifecycle.dart`) | `if (rated == null) return;` | 1 fail: `S-90-5 rating a still-running session does not` |
| M4 | the `try { await _platform.clearWorkoutEffort(...) } catch` block in `onSessionDeleted` | block removed | 1 fail: `S-90-6 discarding a finished session calls clearWorkoutEffort then deleteWorkouts` |
| M5 (extra) | `ratingWritten = rating;` in the importer's `_createSession` | line removed | 1 fail: `S-90-5 an import that creates the session with its rating tells the sync service once` |

### Final runs

- Touched test files: `flutter test test/health_platform_test.dart test/watch_session_import_test.dart test/health_effort_test.dart` -> `+133: All tests passed!`
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` -> `+42: All tests passed!`
- `flutter analyze` -> `180 issues found.` (baseline 180; none in touched files)
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` -> empty
- Full `flutter test` (900 s wrapper) -> `04:14 +5842 ~2: All tests passed!`, exit 0 (baseline 5813 + 29 new).

### D-4 rating write sites (`grep -rn "session_feeling\|sessionFeeling" lib`)

- `SessionCore.updateSessionFeeling`: hooked (summary sheet, calendar summary, the adoption bridge's catch-up).
- `WatchSessionImporter._topUpRating` and `_createSession`: hooked through the inbox, once per pass with `appliedRating`. `_createSession` did not report its rating before; it now does (Assumption Log).
- `WatchSessionInbox.recordPhoneRating` writes straight to the repository: not hooked. Its only consumer is the `WatchSyncGraph.ratings` handle, which nothing in `lib/` calls today (tests only).
- `adoptSessionFeeling` only mirrors; the repositories and seed data are not rating sources.

### Docs sizes (bytes, after)

`docs/session_summary.md` 22138, `docs/theme_and_settings.md` 9378,
`docs/state_management/services_and_utils.md` 34307, `docs/state_management/watch_surface.md` about 50.8 K.

## Phase 2 - native piece (2026-10-29)

### HealthKit names confirmed against the iOS 26.4 SDK headers

`iPhoneOS26.4.sdk/System/Library/Frameworks/HealthKit.framework/Headers`, all `API_AVAILABLE(ios(18.0), ...)`:

| Plan name (Assumption Log) | SDK | Difference |
|---|---|---|
| workout effort type | `HKQuantityTypeIdentifierWorkoutEffortScore` (Swift `.workoutEffortScore`), `HKTypeIdentifiers.h:64`, "appleEffortScore, Discrete" | the plan named no identifier; note a second type `HKQuantityTypeIdentifierEstimatedWorkoutEffortScore` (the watch's automatic estimate) exists and is NOT used, so a related estimate is neither read as "another source's value" nor deleted |
| unit `appleEffortScore` | `+[HKUnit appleEffortScoreUnit]` (Swift `.appleEffortScore()`), `HKUnit.h:281` | none |
| `relateWorkoutEffortSample` | `-[HKHealthStore relateWorkoutEffortSample:withWorkout:activity:completion:]`, `HKHealthStore.h:428` (Swift `relateWorkoutEffortSample(_:with:activity:completion:)`) | takes an optional `HKWorkoutActivity` (nil used); an `unrelateWorkoutEffortSample:fromWorkout:...` also exists (not needed: the own sample is deleted) |
| `predicateForWorkoutEffortSamplesRelated` | `+[HKQuery predicateForWorkoutEffortSamplesRelatedToWorkout:activity:]`, `HKQuery.h:191`, `NS_SWIFT_NAME(predicateForWorkoutEffortSamplesRelated(workout:activity:))` | takes `activity:` (nil) |
| delete own samples | `-[HKHealthStore deleteObjects:withCompletion:]` (`HKHealthStore.h:176`, iOS 9, Swift async `delete(_:)`); own source by `HKSource.default()` bundle id, as the plugin's delete (`health-13.3.1/ios/Classes/HealthDataOperations.swift:225`) | none |

### Order of work

1. Gateway skeleton (constructor `isIOS` / `effortChannel`, `healthEffortChannelName`), stubs still answering `unavailable`.
2. `test/health_effort_native_test.dart` (S-90-8 + gateway group).
3. Red run, then the Swift, AppDelegate, project entry, Info.plist, gateway body, green.

### Red run (no Swift, stub gateway, old plist): `flutter test test/health_effort_native_test.dart` -> `+3 -6: Some tests failed.`

| Test | Red | Green |
|---|---|---|
| S-90-8 the Runner registers channel omnitrain/health_effort | fail (no file) | pass |
| S-90-8 every method answers behind #available(iOS 18.0, *), else unavailable | fail (no file) | pass |
| S-90-8 Info.plist and entitlements gain no key; the update text mentions effort | fail (text has no "effort") | pass |
| gateway: set sends the exact span and score and maps every answer | fail | pass |
| gateway: clear sends the exact span; true only when cleared | fail | pass |
| gateway: a platform error or a missing channel never escapes | pass (guard: stub) | pass |
| gateway: Android (not iOS) never calls the effort channel | pass (guard, proven by M7) | pass |
| gateway: switching Write workouts on asks for effort first | fail | pass |
| gateway: the read permission request does not ask for effort | pass (guard) | pass |

Green: `+9: All tests passed!`

### Mutation checks (each restored exactly, `cmp` clean, re-run green `+9`)

| Id | Original | Mutant | Result |
|---|---|---|---|
| M6 | `guard #available(iOS 18.0, *) else {` (`HealthEffortChannel.swift`, `handle`) | `guard true else {` | 1 fail: `S-90-8 every method answers behind #available...` |
| M7 | `if (!_isIOS) return null;` (`_invokeEffort`) | line removed | 1 fail: `Android (not iOS) never calls the effort channel` |
| M8 | `await _invokeEffort('requestAuthorization');` (`requestWritePermission`) | line removed | 1 fail: `switching Write workouts on asks for effort first` |
| M9 | update text `saves your finished workouts, and the effort you rate them, to` | `saves your finished workouts to` | 1 fail: `S-90-8 Info.plist ... mentions effort` |

### Build

- `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` -> `** BUILD FAILED **`, exit 65: every error is in `watch/watchos/Sources/WatchSessionEngine` ("only available in iOS 13.0 or newer"). `-sdk iphonesimulator` forces the embedded watch target onto the iOS SDK; not this change.
- Without `-sdk`: `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratchpad>/dd CODE_SIGNING_ALLOWED=NO build` -> `** BUILD SUCCEEDED **`, exit 0. `HealthEffortChannel.swift` and `AppDelegate.swift` compiled in target `Runner` (arm64 + x86_64), no warning in either; the `OmniTrain Watch App` target compiled and linked for `Debug-watchsimulator` in the same build. `project.pbxproj` unchanged by the build (diff stays the 4 added lines).

### Final runs

- Touched tests: `flutter test test/health_effort_native_test.dart test/health_effort_test.dart test/health_platform_test.dart test/watch_session_import_test.dart` -> `+142: All tests passed!`
- `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` -> `+42: All tests passed!`
- `flutter analyze` -> `180 issues found.` (baseline 180; none in touched files)
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` -> empty
- Full `flutter test` (900 s wrapper) -> `03:41 +5851 ~2: All tests passed!`, exit 0 (Phase 1's 5842 + 9 new).
- Nothing about HealthKit behaviour is shown by any of this: the source scan pins structure, the gateway tests pin the Dart side of the channel, the build proves it compiles. Only the owner's S-90-9 device checks can show Fitness receives the value.
