# Plan 307 — A workout the Wear wrist ran reaches Health Connect, written by the phone (plan 280 leftover; the Apple wrist's plans 58 and 89c1)

**Status: owner answered 2026-11-22: match the Apple watch where possible, otherwise the defaults below. Being built.** Base commit: `3cabf1d8` (branch `claude_develop`). Analyze baseline: 174 issues, 0 errors.

## Overview

The Apple wrist saves its own workout to Apple Health (it runs an `HKWorkoutSession`, typed, with heart rate and energy), and the phone deliberately does NOT write a second one for a session the wrist ran (plan 89c1: `SessionCore.endSession` skips the write when `wristRunsSession`, and the adoption bridge ends a wrist-completed session with `writeToHealth: false`). That rule is platform-blind. The Wear wrist saves nothing to Health Connect (Health Services' `ExerciseClient` records to its own store, not to Health Connect; plan 300 only registers the workout with the platform). So today **a workout run on a Wear watch reaches Health Connect nowhere**: the wrist does not write it and the phone skips it.

The fix is on the phone, not on the wrist:

- The phone already owns everything a Health write needs on Android: the opt-in setting, the Health Connect permission flow, the written ledger, delete on discard (plan 89), rewrite when the end moves (plan 146c), and the rating write. A second writer on the watch would duplicate the workout and split the ledger.
- Health Connect is a phone-side store. As far as is known it is not available to apps on a Wear OS 5 watch, so a wrist-side write would only ever work on Wear OS 6 watches and would need its own permission flow on the wrist.
- The numbers the workout should carry are already on the phone: the wrist's measured energy lands in `SessionEnergy` (`source: measured`, plan 134c) from the `session_end` entry the Wear wrist now sends (plan 305).

So: on an Android phone, a session the wrist ran is written by the phone like any phone session, with the wrist's measured calories when it has them.

What the user sees: with "Write workouts to Health" on, a workout finished on the Wear watch appears in Health Connect (type from the session's modality, start and end from the session, title) once the phone has the workout, with its calories. It is not instant on the wrist: it appears when the phone receives the end, which can be later if the watch was away from the phone. A workout with no measured calories is written without them. A deleted session's workout is removed as today.

## Goal and acceptance

Acceptance: S-30701..S-30709 green and each guard red without its change; `flutter analyze` at most 174 issues, 0 errors; the iOS behaviour is byte-for-byte unchanged (the Apple wrist still writes, the phone still skips); Docs delta applied. Not provable without a watch and Health Connect: owner check 23.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-30701 | Who writes: the phone writes a Wear-run session's workout; the Wear wrist writes nothing to Health Connect. | plan 89c1; Health Services does not write to Health Connect |
| D-30702 | The skip rule becomes platform-aware. A new injected `wristSavesOwnWorkout` (true when the phone is iOS, false on Android) gates both skip sites: `SessionCore.endSession` computes `wristSavesWorkout = wristSavesOwnWorkout && wristRunsSession(id)`, and the adoption bridge's wrist `completed` passes `writeToHealth: !wristSavesOwnWorkout`. `main.dart` wires `Platform.isIOS`. Every other behaviour of `endSession` (dropping unlogged sets, the wrist-had-a-hand rule for planned sets) keeps using `wristRunsSession` unchanged: only the Health write is platform-aware. A phone-ended session the wrist follows writes once on Android. | `session_core_lifecycle.dart` 22 and 60; `watch_session_adoption_bridge.dart` (`completed` branch); `main.dart` 427 |
| D-30703 | `HealthWorkoutDraft` gains optional `energyKcal`. `HealthSyncService.onSessionCompleted` reads the session's `SessionEnergy` and sets it only for `source == measured` (an estimate is never written to a health store as if measured); the Android gateway passes it as `totalEnergyBurned` (whole kilocalories, rounded; the plugin writes a `TotalCaloriesBurnedRecord`, which is exactly what Health Services' total, resting burn included, is: the number needs no correction here). iOS passes none (a phone-written iOS workout has no measured energy). | `health_platform_service.dart` 16; `health_platform_gateway_io.dart` 220; plugin `writeWorkoutData` |
| D-30704 | The energy can arrive after the write: the wrist's `completed` ends the session first, and the `session_end` entry with `activeEnergyKcal` is imported a moment later (or after the watch next reaches the phone). When an import attaches or changes a session's measured energy and the ledger names the session as written, `HealthSyncService` rewrites the workout once with the energy (the delete-then-write-then-restore-on-failure shape of `rewriteWorkout`, D-15404), keyed so the same energy never rewrites twice. Hooked where plan 90 and plan 146c already call into the service from `WatchSessionInbox`. | `watch_session_importer.dart` `_attachMeasuredEnergy`; `health_sync_service.dart` `rewriteWorkout` |
| D-30705 | Permission: the manifest adds `android.permission.health.WRITE_TOTAL_CALORIES_BURNED`, and the Android write permission request asks for `WORKOUT` and `TOTAL_CALORIES_BURNED` together. Health Connect inserts the exercise session and the calories record in one call, so a missing calories permission fails the whole write: the gateway therefore retries once WITHOUT energy when a write that carried energy returns false, so a user who granted only the old permission still gets the workout (without calories) until they toggle the setting off and on. | plugin `insertRecords(list)` is all-or-nothing; manifest 32 |
| D-30706 | The type is unchanged in this plan: the phone's modality mapping. Matching the Apple wrist's typing (modality table, per-exercise Health kinds, capability majority for a Free workout) is plan 308, built on the same pure rule the Dart wrist already holds, so the phone can reproduce exactly what the wrist registered without a wire change. | `health_modality_mapper.dart`; `watch_platform_workout.dart` |
| D-30707 | Not in scope: heart-rate samples, distance and route in Health Connect; the ongoing-activity chip (plan 308); an on-watch Health Connect write on Wear OS 6; the Apple side; deleting a workout the phone did not write. | |

## Input-reality checklist

- **Writers/units.** The phone is the only writer on Android; the ledger plus the per-process set keep one workout per session. Energy in whole kilocalories (the plugin takes an `int`).
- **Lifecycle.** The wrist may finish while the phone app is closed: the end is imported at next launch and written then, with the session's real start and end. A phone that never receives the end never writes (the same as any session not saved).
- **Settings changing while open.** "Write workouts" off at the moment of the end: nothing is written and the energy rewrite is skipped; turning it on later does not backfill (as today).
- **Time.** Start and end come from the session; the energy window is the session's.
- **Load.** One write per session, at most one rewrite when energy arrives late.
- **Wording.** No new user-visible words; the permission sheet is the system's.
- **Slot competition.** The Health Connect sheet lists one more line (calories) for new enablers.
- **Readers that wait.** None.

## Scenarios

| ID | Fixture | Expect |
|---|---|---|
| S-30701 | Android phone, wrist `completed` for the held session | exactly one `writeWorkout` with the session's span, modality type and title; the ledger names it |
| S-30702 | iOS phone, the same | no write (unchanged) |
| S-30703 | Android phone ends a session the wrist is running | one write; iOS: none |
| S-30704 | `endSession` planned-set handling with `wristRunsSession` true on Android | unchanged (still keeps the wrist's part), proving only the Health rule moved |
| S-30705 | session with measured energy 312.4 at write time; with an estimate; with none | draft carries 312 / null / null |
| S-30706 | workout written without energy, then measured energy 312.4 imported | one rewrite carrying 312; the same energy imported again rewrites nothing; a failed rewrite restores the previous span; setting off: nothing |
| S-30707 | gateway on Android with energy | `totalEnergyBurned` 312; a first write returning false is retried once without energy; both false is a plain failure; iOS passes none |
| S-30708 | permission request on Android | asks `WORKOUT` and `TOTAL_CALORIES_BURNED` for write; iOS unchanged |
| S-30709 | manifest guard | `WRITE_TOTAL_CALORIES_BURNED` declared in the phone manifest |

Mutation pass by the lead over each guard (the platform flag at both sites, the measured-only rule, the rounding, the rewrite key, the retry, the permission list).

## Phases (one PR, about 150 lines of source plus tests)

1. Phone Dart: the flag and both skip sites, `energyKcal` on the draft and the service, the rewrite-on-late-energy, the gateway retry and the permission list, the manifest line (`lib/state/workout/`, `lib/state/watch/`, `lib/core/services/health_*`, `lib/main.dart`, `android/app/src/main/AndroidManifest.xml`). No wrist, Kotlin or wire change.
2. Tests and mutation; docs.

The readers to list before building (grep at build time): every caller of `endSession` and of `wristRunsSession`, every `HealthWorkoutDraft(` construction (the service's three paths and the tests), every implementation of `HealthPlatformService` (the io gateway, the unavailable one, test doubles).

## Docs delta

`docs/theme_and_settings.md` (the Health write-back paragraph), `docs/state_management/services_and_utils.md` (`HealthSyncService`), `docs/wear_os_app_calories.md` (where the calories go), `docs/wear_os_app.md` owner check 23: a Wear workout with calories appears once in Health Connect; with the setting off nothing; the workout appears when the phone receives it.

## Owner answers (2026-11-22)

"If possible match the Apple watch, otherwise your defaults."

1. **The phone writes Wear workouts**: yes (default).
2. **Calories**: matching Apple's active-only energy is not possible: Health Services' `ExerciseClient` offers only the total including resting burn, and an estimated resting burn subtracted would be a guess shown as a measurement. Default taken: the wrist shows the platform's total and Health Connect gets it as its total-calories record, which is what it is.
3. **Type**: match Apple. This plan keeps the coarse phone mapping so the core write ships; plan 308 matches the Apple wrist's typing.

## Progress

| Item | Status |
|---|---|
| seed | Done |
| owner answers | Done (match Apple where possible, else defaults) |
| build, tests, mutation (23 of 24, one equivalent), docs | Done (evidence file) |
| commit | Done |
| owner check 23 | Open |
| plan 308 (match the Apple typing) | Not started |
