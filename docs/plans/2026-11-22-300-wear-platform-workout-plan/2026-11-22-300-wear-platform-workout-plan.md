# Plan 300 — The Wear wrist registers its workout with the platform (plan 280 item 9, part 4 of 4)

Plans 297 to 299 gave the Wear wrist its heart rate and distance. Both still depend on the app staying alive: with the wrist down, a Wear app that is not part of a platform workout is a background app the system may stop, which silently ends the readings. The Apple wrist solves this with an `HKWorkoutSession`; the shared Dart layer already has the seam (`WatchPlatformWorkout` and the `WatchPlatformWorkoutStore` interface, started and stopped with the sensors by `WatchSessionSensors`, and `recoverInProgress` at launch) and Wear plugs in a store that does nothing (plan 297 D-29703). This plan replaces it: a Kotlin client over Health Services' `ExerciseClient` that starts a real exercise of the right type and ends it with the workout, a foreground service of type `health` with an ongoing notification so the process is kept, and recovery of an exercise a killed process left behind. Wear flavor only. Base commit: `.work/2026-11-22-300-wear-platform-workout/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On a Wear watch, starting a workout (the first session that becomes active) registers an exercise with Health Services of the type the workout's exercises call for (running for distance work, strength training for lifts, stretching for holds, otherwise a generic workout) and starts a foreground service whose ongoing notification says a workout is in progress; ending the workout (End, Discard, or the phone ending it) ends the exercise and stops the service; a killed app's stranded exercise is ended at the next launch before the restored session registers a fresh one. With the body-sensor permission refused, or Health Services unable to start, nothing is registered and nothing the user sees changes: logging never depends on the platform workout.

Acceptance: S-30001..S-30010 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the Wear and phone debug APKs build; S-30011 observed on the Wear emulator (the exercise appears in Health Services and the service runs while a workout is begun; both end with it); Docs delta applied.

## Feature invariants

- Logging never depends on a platform workout: every failure leaves `begin` as a no-op and `end` safe to call.
- One exercise at a time: a second `begin` ends the first (the Dart `WatchPlatformWorkout` already does that).
- The foreground service exists exactly while an exercise was started: started with it, stopped with it, never left running when the exercise failed to start.
- The phone flavor is unchanged: no service, no new permission.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-30001 | New Dart `WearPlatformWorkoutStore` (replaces the no-op in `wear_sensor_source.dart`) over `MethodChannel('omnitrain/wear_workout/methods')` with `begin(<Health Services type name>)`, `end()` and `inProgress()` (a list of names). `begin` first asks the heart-rate permission through the sensor source (the exercise needs the body-sensor permission, and the shell starts the workout before the recorder asks), and does nothing unless it is granted. Every platform failure reads as "nothing happened". | plan 297 D-29703; `WatchPlatformWorkoutStore` |
| D-30002 | The shared type table passes the watchOS name to `begin`; the Wear store translates it with a new `WatchActivityTypes.wearFor(String watchOs)` (the first type in the tables whose `watchOs` matches, else the generic one) to the Health Connect name (`exercise_type_running`), which Kotlin maps to Health Services' `ExerciseType`. | `watch_platform_workout.dart` 67-146, 385-391 |
| D-30003 | `WearWorkout` (Kotlin, wear flavor) maps the type name to `ExerciseType` (unknown names to `WORKOUT`), builds an `ExerciseConfig` with heart rate as its data type and GPS and auto-pause off (distance is plan 299's own client), starts the exercise, and only when that succeeds starts `WorkoutService`; `end` ends the exercise and stops the service; `inProgress` reports `OWNED_EXERCISE_IN_PROGRESS`. | Health Services `ExerciseClient` |
| D-30004 | `WorkoutService` is a foreground service of type `health` with a low-importance channel and an ongoing notification ("OmniTrain", "Workout in progress") that opens the app; it is `START_NOT_STICKY`. The wear manifest declares `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_HEALTH` and the service. | Android health foreground services |
| D-30005 | `WatchSessionSensors.recoverInProgress` already ends whatever the store reports at launch; the Wear store's `inProgress` answers one name when an owned exercise is running, so recovery calls `end()` once. | `watch_platform_workout.dart` 410-425 |
| D-30006 | Not in scope: the Ongoing Activity API chip on the watch face, calories and the Health Connect write (plan 280 notes it), pause and resume mapping, and GPS on the exercise. | plan 280 item 9 |

## Input-reality checklist

1. **Writers.** The shell is the only starter and stopper (plan 297's lane); recovery runs once at launch before the restore. `begin` and `end` can overlap only through that lane.
2. **Units.** None.
3. **Lifecycle.** A kill leaves the exercise and the service dies with the process: the next launch's recovery ends the exercise. The app moving to the background leaves both running (the point). The permission prompt for body sensors appears once, from the heart-rate question.
4. **Settings changing while open.** The user revokes the body-sensor permission mid-workout: Health Services ends the exercise; the next `end()` is a harmless no-op.
5. **Time.** Starting an exercise is asynchronous; `begin` answers after it started or failed. Starting the service is only done after a successful start.
6. **Load.** One exercise, one service, one notification.
7. **Wording.** The notification's two lines.
8. **Slot competition.** None.

## Scenarios

Store (`test/wear_platform_workout_store_test.dart`, new; channel mocks; plain `test()`):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-30001 | the sensor source answers `granted`; `begin('running')` | the methods channel gets `begin` with `exercise_type_running` | the type is not translated, or the call is not made |
| S-30002 | `begin('traditionalStrengthTraining')`, `begin('flexibility')`, `begin('somethingNew')` | `exercise_type_strength_training`, `exercise_type_flexibility` and the generic `exercise_type_other_workout` | a lift or a hold registers as the wrong type, or an unknown type is dropped |
| S-30003 | the sensor source answers `denied` and then `unavailable` | `begin` makes no channel call | a refused permission still starts an exercise |
| S-30004 | the channel throws a `PlatformException`, and (no mock) a `MissingPluginException`, on every call | `begin`, `end` and `inProgress` complete without throwing; `inProgress` is empty | a platform failure reaches the shell |
| S-30005 | the channel answers `['exercise_type_running']` to `inProgress` | `inProgressActivityTypes` returns that list; a non-list or null answer is an empty list | recovery cannot see a stranded exercise |
| S-30006 | `end()` | the channel gets `end` once | the exercise is never ended |
| S-30007 | `WatchActivityTypes.wearFor` | every watchOS name in the tables maps to its own wear name; an unknown or empty name maps to the generic one | a type maps to a neighbour's name |

Wiring (`test/wear_sensors_shell_test.dart`, extended): S-30008 the entry point passes `WearPlatformWorkoutStore(` (not the no-op) to `WatchPlatformWorkout`, and the shell test harness uses the real store over a mocked channel for one session: begin is called once when the session starts and `end` once when it ends.

Kotlin guards (`test/wear_workout_native_test.dart`, new; source reads, no harness):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-30009 | `WearWorkout` | `begin` returns without starting when the body-sensor permission is not held, maps names to `ExerciseType` with `WORKOUT` as the default, builds the config with `HEART_RATE_BPM` and GPS and auto-pause off, starts the service only after the start succeeded, `end` ends the exercise and stops the service, `inProgress` reports `OWNED_EXERCISE_IN_PROGRESS`; the channel name equals the Dart constant | a workout is started without the permission, the service runs for a failed start, or the names drift |
| S-30010 | `WorkoutService`, the wear manifest, the phone manifest, the registrar | the service starts foreground with `FOREGROUND_SERVICE_TYPE_HEALTH` and an ongoing notification, is `START_NOT_STICKY`; the wear manifest declares both permissions and the service with `foregroundServiceType="health"`; the phone manifest none; the wear registrar builds `WearWorkout` | the system kills the process, or the phone gains a service |

Emulator (lead, observed, S-30011): a throwaway Dart entry that asks the heart-rate permission, calls the store's `begin('running')`, waits, then `end()`: while begun `dumpsys activity services dev.sasha.omnitrain` shows `WorkoutService` as a foreground service and Health Services reports an owned exercise in progress; after `end()` both are gone; the entry is deleted afterwards.

Guard families the lead proves by mutation: the type table and its default, the permission gate, the service ordering (only after success), the end path, the in-progress status, the channel names, the manifests, the translation helper.

## Phases

1. **P1 — the Dart store and the translation helper** (`crew-builder-watch`; scope `lib/watch/sensors/wear_sensor_source.dart`, `lib/watch/sensors/watch_platform_workout.dart`, `lib/watch/wear_main.dart`). Exact code in the brief. About 70 lines.
2. **P2 — the Kotlin client, the service, the registrar, the manifest** (lead-written: the crew's builders may not write under `android/`). About 200 lines.
3. **P3 — tests** (lead): the three test files; **P4 — docs** (lead), then the compile, both APKs, the emulator proof, the mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | The platform workout is a Health Services exercise | S-30009 |
| docs/wear_os_app.md | ADDED | - | `test/wear_platform_workout_store_test.dart` | S-30001 |
| docs/wear_os_app.md | MODIFIED | Not built: the platform workout (plan 300): the wrist registers no workout with the platform | Not built: calories, the Health Connect write and the watch-face ongoing-activity chip | S-30009 |

Owner check 20 is added for a real watch (the ongoing notification, the sensors running with the wrist down, a killed app's exercise ended at relaunch).

## Assumption Log

- Health Services keeps an exercise's sensors running for an app with a foreground service while the screen is off; the emulator shows the exercise and the service but cannot show the wrist-down behaviour (owner check 20).
- The Health Services exercise needs the body-sensor permission only (no GPS, no step data type); `ACTIVITY_RECOGNITION` is not needed.
- An `ExerciseType` constant exists for each name the table can produce, or falls to `WORKOUT`: the compile checks the constants used.

## Progress

- [x] P1 the Dart store and helper (crew builder, 1.2 min)
- [x] P2 the Kotlin client, service, registrar, manifest (lead-written; compiled first try)
- [x] P3 tests (S-30001..S-30010; the existing sensor tests updated; 28 mutants)
- [x] P4 docs (`docs/wear_os_app.md`: the platform workout paragraph, two tests bullets, owner check 20)
- [x] Verify and prove: analyze 174 / 0; both APKs build; 28 of 28 mutants killed; S-30011 observed (service, in-progress, end, the real app)
- [ ] (owner) check 20 in `docs/wear_os_app.md` on a real watch
