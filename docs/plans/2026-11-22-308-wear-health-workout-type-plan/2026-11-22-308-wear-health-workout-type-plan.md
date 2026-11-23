# Plan 308 — A Wear workout is typed in Health Connect the way the Apple watch types its own (follows plan 307)

Owner (2026-11-22): "if possible match the Apple watch". Plan 307 made the phone write a Wear-run workout to Health Connect but typed it by the phone's coarse modality mapping, so a Free or cardio session is written as Other, where the Apple watch registers Running, Strength Training, Walking, Cycling and so on (plans 58, 75, 170). The Apple rule is a pure function the Dart wrist already holds (`WatchActivityTypes`: the Health kind each exercise names, else its modality's type, else, for a Free workout, the capability majority), and the phone already knows every input (it names the kind per exercise itself when it sends the catalog). So the phone can reproduce exactly what the wrist registered, with no wire change. Base commit: `c0c5d952`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On Android, a workout the wrist ran is written to Health Connect with the type the wrist's own rule gives for that session: a routine whose exercises name a Health kind gets the majority kind (Running, Cycling, Swimming, Rowing, Walking, Hiking, strength, yoga, boxing and the rest of the table), otherwise its modality's type; a Free workout gets the type of its first exercise (the wrist fixes the type when the first exercise opens the workout and never retypes it). Types Health Connect has no entry for (stretching, flexibility, soccer) are written as Other, as the phone already does for flexibility. A phone-only session, and every iOS write, is typed exactly as before.

Acceptance: S-30801..S-30807 green and each guard red without its change; `flutter analyze` at most 174 issues, 0 errors; no new failures against a clean checkout in the neighbouring suites; Docs delta applied. Not provable without a watch and Health Connect: owner check 24.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-30801 | `WatchActivityTypes.forModalityAndExercises(modality, exercises)` (new, pure, in `watch_platform_workout.dart`): the body of `forSession` over a modality and slot maps (`capabilities`, `healthActivity`); `forSession` delegates to it, so the wrist's behaviour is byte-for-byte unchanged and there is ONE rule. | `forSession`, plan 170 D-17003 |
| D-30802 | `HealthWorkoutDraft` gains optional `activityTypeName`: a Health Connect exercise name (`exercise_type_running`) from the wrist's table. The Android gateway maps it through one table to the plugin's `HealthWorkoutActivityType` and falls back to the kind mapping for a name it does not map or on iOS. | `health_platform_gateway_io.dart` |
| D-30803 | The table (Wear name to plugin type): running RUNNING, biking BIKING, swimming SWIMMING_POOL, rowing ROWING, walking WALKING, hiking HIKING, strength_training STRENGTH_TRAINING, calisthenics CALISTHENICS, yoga YOGA, boxing BOXING, martial_arts MARTIAL_ARTS, cross_training HIGH_INTENSITY_INTERVAL_TRAINING (the phone's existing mapping for conditioning), tennis, badminton, table_tennis, squash, volleyball, basketball, baseball, cricket, golf, rugby, american_football, rock_climbing to their namesakes; flexibility, stretching, football and other_workout to OTHER (the plugin has no entry; same as the phone's flexibility today). | plugin `workoutTypeMap`; `pluginActivityTypeFor` |
| D-30804 | `HealthSyncService` types a session this way only when the wrist ran it: `onSessionCompleted(session, {wristRan})` (SessionCore passes `wristRuns` or "this is the wrist's own end"); the later paths (`rewriteWorkout`, `onEnergyAttached`) use the remembered answer, else whether the phone holds any watch-origin inbox row for the session. The inputs: the session's modality and its efforts' exercises in session order (segment order, then effort order), each as `capabilities` plus the Health kind the phone names (`WatchReferenceSync.healthActivityOf`, the same function that builds the catalog the wrist received). For a session with no modality only the FIRST exercise is used (the wrist's rule: the type is fixed when the workout opens). | Apple plan 58 D-2; `watch_reference_sync.dart` |
| D-30805 | The existing Yoga rule for a phone-only session is untouched; for a wrist-run session the wrist's table already yields Yoga for a yoga discipline, so the two agree. Exercises the user deleted since read as no exercise (no vote), as an exercise the wrist did not know. | `health_sync_service.dart` `_activityKindOf` |
| D-30806 | Not in scope: carrying the wrist's actual chosen type over the wire (exact even for an exercise added mid-session), a type chosen by the Apple watch (it writes its own), heart rate, distance and route. | |

## Scenarios

| ID | Fixture | Expect |
|---|---|---|
| S-30801 | `forModalityAndExercises` against `forSession` over a spread of modalities and slot lists | identical answers for every case, and `null` for a Free workout with no exercises |
| S-30802 | gateway table: every distinct `wear` name in the wrist's tables | maps to a type or is listed as deliberately Other; an unknown name and iOS use the kind mapping |
| S-30803 | Android, wrist ran a Free session whose first exercise is a run / a lift / a hold / a plain timed one | the draft names running / strength / flexibility / other |
| S-30804 | Free session, run first then lifts | running (first exercise only); lifts first then a run: strength |
| S-30805 | routine with modality `cardio_endurance` whose exercises name cycling, cycling, running | biking (majority of named kinds); with none named: running (the modality's type) |
| S-30806 | phone-only session and the same session on iOS | typed as before (kind mapping), no `activityTypeName` |
| S-30807 | the late paths: the energy replacement and a moved end of a wrist-run session | the replaced workout carries the same type as the first write; a restart (no memory) still types it through the inbox rows |

## Phases

One PR: the pure function, the draft field, the gateway table, the service's typing, the call-site flag, tests, mutation, docs. Readers to list at build time: every caller of `onSessionCompleted`, every `HealthWorkoutDraft(` construction, every user of `WatchActivityTypes.forSession`.

## Docs delta

`docs/wear_os_app_calories.md` (rename the section's "Not done" paragraph into what is built), `docs/wear_os_app.md` owner check 24 is folded into check 23's wording (the type shown in Health Connect).

## Progress

| Item | Status |
|---|---|
| seed | Done |
| build, tests, mutation (19 of 20, one equivalent under the in-memory repository), docs | Done (evidence file) |
| commit | Done |
| owner check 23 (type shown in Health Connect) | Open |
