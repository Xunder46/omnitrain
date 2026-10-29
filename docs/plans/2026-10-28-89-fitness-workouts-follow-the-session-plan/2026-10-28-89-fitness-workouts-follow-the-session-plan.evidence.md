# Plan 89 evidence

## Phase 3 - phone delete follows discard (D-4, D-5, D-6)

### D-5 - the plugin's delete predicate (read before any code)

Source: `~/.pub-cache/hosted/pub.dev/health-13.3.1/ios/Classes/HealthDataOperations.swift:192-266`
(`delete(call:result:)`, reached from `case "delete"` in `SwiftHealthPlugin.swift:166`).

```swift
let samplePredicate = HKQuery.predicateForSamples(withStart: dateFrom, end: dateTo, options: .strictStartDate)
let ownerPredicate = HKQuery.predicateForObjects(from: HKSource.default())
// HKSampleQuery(sampleType, AND(samplePredicate, ownerPredicate)) -> healthStore.delete(samples)
```

What `.strictStartDate` expands to, observed by compiling a 6-line Swift program against the
macOS HealthKit SDK (scratchpad only, not in the repo) and printing each option's predicate:

| options | NSPredicate |
|---|---|
| none | `endDate >= start AND startDate < end AND ...` (overlap) |
| `.strictStartDate` (the plugin) | `startDate >= start AND startDate < end` |
| `.strictEndDate` | `endDate >= start AND endDate < end AND startDate < end ...` |
| both | `startDate >= start AND endDate < end AND startDate < end` (containment) |

Finding: **neither overlap nor containment - start-in-window, half-open `[start, end)`, own source only.**
- Previous neighbour A (10:00-10:45) when deleting B `[10:45, 11:30)`: A starts before 10:45 - never matched.
- Next neighbour C starting exactly at B's end (11:30): `startDate < end` is false - never matched.
- So a back-to-back neighbour cannot be deleted. Not a STOP condition; built as planned.
- Better than containment for this app: a duration edit after the write-back (`updateSessionEndTime`)
  moves only the end, and the workout still matches by its start.

Residual risks (reported, not fixed):
1. **Source filter.** `HKSource.default()` on the phone is the iPhone app (`dev.sasha.omnitrain`); a
   workout the watch app saved has the watch app's source (`dev.sasha.omnitrain.watchkitapp`), so the
   plugin's query never selects it. The phone delete removes only workouts **the phone wrote**. This
   contradicts the plan's first Assumption Log entry for this path; S-89-6(c) on a watch-run session
   is expected to leave the watch's workout in Fitness. Reaching it needs a native delete (89c-like).
2. **User-edited overlap.** `updateSessionEndTime` has no ceiling against the next session; a session
   whose duration was edited to run past the next session's start would, on delete, take that next
   session's phone-written workout. Needs two sessions made to overlap by hand.
3. **Zero-length session** (`endedAtMs == startedAtMs`): `[s, s)` is empty, so its phone-written
   workout would stay. Only possible if a session ends in the same millisecond it starts.
4. **Android** (`android/.../HealthDataOperations.kt:193`): `deleteRecords(WORKOUT, TimeRangeFilter.between(start, end))`.
   The KDoc says inclusive-exclusive; how Health Connect matches an interval record (by start, or
   overlap) is not documented on the pages read. Not verified; Health Connect also deletes only the
   caller's own records.

### D-6 - is a watch-run session written to Health twice? (read-only)

Yes, when the phone's Write workouts toggle is on and the phone holds the session when it ends:
- The watch saves its own `HKWorkout` for every session its engine runs (`WatchWorkoutCoordinator.apply`
  -> `platform.end()` -> `finishWorkout()`; Phase 1 keeps that for `completed`).
- The phone writes its own copy from `SessionCore.endSession` -> `HealthSyncService.onSessionCompleted`.
  A wrist `completed` lifecycle for the session the phone holds goes through
  `WatchSessionAdoptionBridge.onLifecycle` -> `target.endSession()` (`watch_session_adoption_bridge.dart:770`),
  so it is written again. A phone-started session that the watch also tracked is the same.
- A wrist session imported later (the phone was not holding it) goes through `watch_session_importer.dart`,
  which writes the rows itself and never calls `onSessionCompleted`: one entry (the watch's).
- The ledger dedupes by session id on the phone only; it cannot see the watch's workout.

### Baselines

- `flutter analyze`: 180 issues before any edit; 180 after.
- Test files found: the health sync tests live in `test/health_platform_test.dart` (no
  `health_sync_service_test.dart` exists); other `HealthPlatformService` fakes in
  `test/watch_session_import_test.dart` (+1 method) and the `_ThrowingReadPlatform` in the same health file.

### Red -> green (`flutter test test/health_platform_test.dart --plain-name "plan 89"`)

Red run with the interface stubbed (`onSessionDeleted` empty, gateways `throw UnimplementedError()`):
`00:00 +2 -9: Some tests failed.`

| Test | Red | Green |
|---|---|---|
| S-89-4 a written session asks the store to delete its span once and leaves the ledger | fail (`Actual: []`) | pass |
| S-89-4 a session the phone never wrote still asks the store | fail | pass |
| S-89-4 a store that refuses leaves the discard successful | fail | pass |
| S-89-4 a store that throws leaves the discard successful | fail | pass |
| S-89-4 the discard does not wait for the store | fail | pass |
| S-89-4 with Write workouts off nothing reaches the store | pass (guard; proven by M4) | pass |
| S-89-5 deleting B of back-to-back A and B asks for exactly B and keeps A | fail | pass |
| S-89-5 deleting A of back-to-back A and B keeps B | fail | pass |
| S-89-5 a rolling session spanning a day is passed its own span only | fail | pass |
| D-4 discarding a session still in progress asks nothing of the store | pass (guard; proven by M5) | pass |
| D-4 the no-op gateway reports the delete as not done | fail (`UnimplementedError`) | pass |

Green: `00:00 +11: All tests passed!`

The fake store applies the plugin's observed rule (`start >= windowStart && start < windowEnd`),
not the plan's "containment rule": it is the real behaviour and it is the one that can tell a
widened end apart (containment would keep B either way).

### Mutation checks (each restored to the exact original and re-run green)

| # | Mutation (original line) | Result |
|---|---|---|
| M1 | `DateTime.fromMillisecondsSinceEpoch(endedAtMs)` -> `endedAtMs + 60000` | 7 failed, 4 passed; with the store assertion first, "deleting A keeps B" fails on the store alone: `Expected: [10:45] Actual: []` (B's workout deleted) |
| M2 | `DateTime.fromMillisecondsSinceEpoch(session.startedAtMs)` -> `startedAtMs - 60000` | 7 failed (exact-window asserts; the start rule cannot reach A, as expected) |
| M3 | `} catch (e) { debugPrint('Health workout delete skipped: $e'); }` -> `} finally {}` | "a store that throws" fails: `Exception: platform delete exploded` |
| M4 | drop `if (!_isWriteEnabled()) return;` | "Write workouts off" fails: one delete request |
| M5 | `if (endedAtMs == null) return;` -> `endedAtMs = session.endedAtMs ?? now` | "still in progress" fails: one delete request |
| M6 | `_healthSync?.onSessionDeleted(discarded);` -> `await ...` | "does not wait" fails: `Expected: true Actual: <false>` |

After restore: `flutter test test/health_platform_test.dart test/watch_session_import_test.dart
test/health_platform_mapper_test.dart test/ui_standards_contract_test.dart
test/docs_indexing_contract_test.dart` -> `00:01 +143: All tests passed!`

Full suite (`with-timeout.sh 900 flutter test`, exit 0, 4 min 16 s): `04:16 +5800 ~2: All tests passed!`
(5800 passed, 2 skipped, 0 failed; no hang). `flutter analyze`: 180 issues (baseline 180).

Invariant grep `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`: empty (exit 1).

### Proposed S-89-6 device-check text (for the governor to place in the QA doc)

> Phone Settings > Write workouts ON for (b)-(c2).
> (b) Start a session on the phone, add a set, discard it on the phone. Fitness: nothing new.
> (c1) Start and finish a short session on the phone **with the watch app closed**. Fitness: one
> OmniTrain workout. Open it in Session Summary, Discard session. Within a few seconds the workout
> leaves Fitness (Health > Workouts > Show All Data, source OmniTrain).
> (c2) Run a short session on the watch and finish it there. Fitness: note how many OmniTrain
> workouts appear (two expected while Write workouts is on - one per device, D-6). Delete the session
> on the phone. Expected from source: the phone's copy goes, the watch's copy stays (the phone can
> only delete what the phone saved). Report what you see.

## Phases 1-2 - the wrist discards, force-quit recovery (D-1, D-2, D-3)

Restored by the governor 2026-10-28 from the watch agent's hand-back; the agent's own section was overwritten when the Phase 3 agent created this file. Numbers are the agent's, except the lines marked "governor".

- Baseline: `Executed 1127 tests, with 0 failures`.
- Red: the 13 new tests (`WatchFitnessFollowsSessionTests.swift` 10, `WatchFitnessFollowsSessionSourceTests.swift` 3) do not compile on the untouched code. With the new methods added but today's behaviour (everything saves, nothing discards, no recovery hook): `Executed 1140 tests, with 14 failures` (10 test cases); the 1127 old tests passed. Three new tests pass by design (finished session saves, recovery of an active session saves, nothing stranded ends nothing).
- Mutations (each restored, `cmp` identical): always save, 3 S-89-1 tests fail; remove the recovery hook, `testS89_3TheAppDeclaresTheWorkoutRecoveryDelegate` fails; recovery always saves (extra), 3 S-89-2 tests fail.
- Final: `Executed 1140 tests, with 0 failures (0 unexpected)`, twice (agent). Governor re-run: `Executed 1140 tests, with 0 failures (0 unexpected)`.
- Governor: `xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App" -destination 'generic/platform=watchOS Simulator' build` -> `BUILD SUCCEEDED`.
- Docs/UI contracts: `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` passed; hive import grep empty.
- Not verified: anything on a real watch (S-89-6 a, b, d). Risks W-1 (a recovery relaunch that also restores the active session may open a new workout at once and turn the light back on), W-2 (a workout whose stored session is `completed` is discarded if the app is killed between Finish and the save), W-3, W-4 are in the plan's Assumption Log.
