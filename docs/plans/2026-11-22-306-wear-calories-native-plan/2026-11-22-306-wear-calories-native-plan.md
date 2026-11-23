# Plan 306 — Calories on the Wear wrist, the native half (plan 280 leftover; follows plan 305)

Plan 305 built the wrist's calorie logic in Dart behind an optional `WatchEnergySource` and fixed the contract: method `activeEnergyPermission` on `omnitrain/wear_sensors/methods` and `EventChannel('omnitrain/wear_sensors/energy')` of cumulative kilocalories. This plan builds the Kotlin that answers it from the platform workout plan 300 already runs (Health Services `ExerciseClient`), plus the one Dart change that makes it reachable (the workout must be started with calories in its data types, which needs the permission first). Base commit: `cffec705`. Analyze baseline: 174 issues, 0 errors. Lead-built (Kotlin is outside the crew's write ceiling; the gateway hangs for builders here).

**A fact to carry to the owner.** Health Services' `DataType.CALORIES_TOTAL` is "total calories burned (including basal rate and activity)" since the exercise began. It has no active-only calories in `ExerciseClient`, unlike Apple's active energy. So a Wear wrist's `kcal burned` and its `activeEnergyKcal` on `session_end` include the resting burn (about one kilocalorie a minute for an adult) and read higher than the same workout on an Apple wrist. The wire field is named `activeEnergyKcal`; this plan sends the platform's total there and says so in the docs. Subtracting an estimated resting burn would be a guess presented as a measurement, so it is not done; a product call for the owner.

## Goal and acceptance

On a Wear watch that supports calories for the exercise type and where the user allows physical-activity data: starting a workout asks (once) for the permission, the workout runs with calories included, and each platform update puts the cumulative total on the energy stream, which plan 305's recorder stores, announces and shows. When the permission is denied, or calories are unsupported, the workout runs as before with no calories. Logging never depends on any of this.

Acceptance: S-30601..S-30607; both flavors build; `flutter analyze` at most 174 issues, 0 errors; emulator observation recorded; Docs delta applied. Not provable without a real watch: owner check 22.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-30601 | `WearSensors` answers `activeEnergyPermission`: `unavailable` unless the exercise client's capabilities list `CALORIES_TOTAL` for the generic workout type; `granted` when `ACTIVITY_RECOGNITION` is held; else one system prompt (`requestPermissions`, request code 29803) whose answer is `granted` or `denied`; questions in flight share one prompt. `onRequestPermissionsResult` handles the new code. | plan 298 D-29802; Health Services permission rules |
| D-30602 | The wear manifest declares `android.permission.ACTIVITY_RECOGNITION`. | |
| D-30603 | New `EnergyStream` (Kotlin, wear flavor): the `EventChannel` handler for `omnitrain/wear_sensors/energy`; `emit(kcal)` posts the number to the main thread's sink and drops it when nobody listens. | plan 298 stream pattern |
| D-30604 | `WearWorkout.begin` reads the exercise client's capabilities first and builds the config's data types as heart rate plus `CALORIES_TOTAL` only when the permission is held and the type supports it (anything that fails falls back to heart rate only, as today); it registers an `ExerciseUpdateCallback` before starting (cleared again when the start fails), whose updates put `latestMetrics`' `CALORIES_TOTAL` total on the energy stream; `end` clears the callback. | plan 300 D-30003 |
| D-30605 | `registerSensors` builds the `EnergyStream`, hands it and `sensors.activityRecognitionGranted()` to `WearWorkout`. The phone flavor is untouched. | `SensorsRegistrar.kt` |
| D-30606 | Dart: `WearPlatformWorkoutStore.begin` asks the energy permission (when its source is a `WatchEnergySource`) right after the heart-rate one and before invoking `begin`, ignoring the answer (Kotlin reads the held permission itself): the shell starts the workout before the recorder asks, and the config is fixed at start. | `wear_sensor_source.dart` store |
| D-30608 | `WearSensorSource.activeEnergyPermission` remembers a `denied` answer for the life of the process: the workout asks before it starts and the recorder asks again, and the emulator showed Android prompting a second time after a first refusal. A permission granted later in Settings applies from the next launch. | emulator observation |
| D-30607 | Not in scope: a basal-rate subtraction, calories without an exercise (passive monitoring), the Health Connect write and the watch-face chip (plan 307). | |

## Input-reality checklist

- **Writers/units.** Updates arrive on the main executor about once a second as cumulative kilocalories (a `Double`); the Dart recorder owns storage and the rule of what is sent.
- **Lifecycle.** A recovered workout (the process died, Health Services ended it or kept it) restarts the counter; plan 305's chain already handles that. The callback is set at `begin` and cleared at `end`; a stream with no listener drops updates.
- **Settings changing while open.** A permission granted later applies at the next workout (the config is fixed at start).
- **Time.** Updates carry no time the wrist trusts; the recorder stamps the arrival instant.
- **Load.** One number a second over a channel, like heart rate.
- **Wording.** The system prompt is the platform's.
- **Slot competition.** One more system prompt on the first workout (after the heart-rate prompt); the channels are new, nothing else moves.
- **Readers that wait.** The permission call waits on the user's answer, like the others (the recorder's `start` waits; logging does not).

## Scenarios

| ID | Fixture | Expect |
|---|---|---|
| S-30601 | Dart store, source with energy and heart-rate `granted` | `begin` asks the energy permission once, after heart rate and before the native `begin` call; a source without energy asks nothing; heart rate denied: nothing asked, no native call |
| S-30602 | Kotlin source guards: `WearSensors` | method registered; capability check names `CALORIES_TOTAL`; the three answers; one shared prompt; request code handled in `onRequestPermissionsResult` |
| S-30603 | Kotlin source guards: `EnergyStream` | channel name equals Dart's `WearSensorSource.energyName`; emits on the main thread; drops with no sink |
| S-30604 | Kotlin source guards: `WearWorkout.begin` | data types are heart rate plus `CALORIES_TOTAL` only under the permission and capability; update callback set before the start and cleared on failure and in `end`; the callback reads `latestMetrics` `CALORIES_TOTAL` `.total` |
| S-30605 | Kotlin source guards: registrar and manifest | `EnergyStream` built and passed; `ACTIVITY_RECOGNITION` declared |
| S-30606 | build | both flavors build |
| S-30607 | emulator | the prompt shows, the grant gives `granted`, synthetic exercise data produces a growing number on the stream; denial gives `denied` and no number; observed and recorded in the evidence file |

Mutation pass by the lead over the Dart change and the source guards.

## Phases

Single phase by the lead.

## Docs delta

`docs/wear_os_app_calories.md` (the native half, the total-includes-resting-burn caveat, owner check 22 in `docs/wear_os_app.md` "Checks on a watch"), `docs/wear_os_app.md` sensors paragraph pointer reworded.

## Progress

| Item | Status |
|---|---|
| seed | Done |
| build, tests, emulator, mutation (23/23), docs | Done (evidence file) |
| commit | Done |
| owner check 22 | Open |
