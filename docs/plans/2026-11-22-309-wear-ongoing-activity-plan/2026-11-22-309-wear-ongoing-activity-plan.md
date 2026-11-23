# Plan 309 — A running workout shows as a tappable chip on the Wear watch face (Ongoing Activity; plan 280 leftover)

**Status: built 2026-11-22. The probe showed the notification permission IS needed, so the third prompt was added (the plan's recommended answer); it is one call to remove.** Base commit: `e04f3c96` (branch `claude_develop`). Analyze baseline: 174 issues, 0 errors.

## Overview

Plan 300 keeps the workout alive with a foreground service and a plain ongoing notification. On a Wear watch that is not enough to be findable: leave the app (raise the wrist, swipe to the watch face) and nothing on the face says a workout is running, nor offers a way back. The Wear platform has an API for exactly this, the Ongoing Activity (`androidx.wear:wear-ongoing`): the app attaches an ongoing activity to the notification its foreground service already posts, and the watch face and the recents list then show a small chip with an icon and a status line that opens the app when tapped. The Apple watch has the equivalent built in (its workout session is the thing the watch face shows), so this is the Wear counterpart of something the Apple wrist gets for free.

What the user sees: start a workout on the watch, go to the watch face: a chip with the workout's icon and `Strength training 12:34` (the activity name and a running stopwatch). Tap it and the app opens on the workout. End the workout and the chip goes. Nothing changes inside the app. Kotlin and resources only (the wear flavor): no Dart, wire or phone change.

## Goal and acceptance

Acceptance: S-30901..S-30906 green and each guard red without its change; `flutter analyze` at most 174 issues, 0 errors; both flavors build; the chip observed on the emulator's watch face (or, if the emulator does not render chips, the ongoing-activity record read back from the system), recorded in the evidence file; Docs delta applied. Not provable without a real watch: owner check 24.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-30901 | Dependencies for the wear flavor only: `androidx.wear:wear-ongoing` and `androidx.core:core` (the Ongoing Activity builder takes a `NotificationCompat.Builder`, and the service builds a framework `Notification.Builder` today). Exact versions chosen at build time from what resolves, none newer than the library's current stable. | `build.gradle.kts` wear block |
| D-30902 | `WorkoutService` builds its notification with `NotificationCompat.Builder` (ongoing, category workout, the open-the-app intent it already has), attaches `OngoingActivity.Builder(context, NOTIFICATION_ID, builder)` with a static icon, the same open intent as its touch intent and a status, applies it, then posts the result with `startForeground` as today. The service type (`health`), the channel and the not-sticky start are unchanged. | `WorkoutService.kt`; Ongoing Activity API |
| D-30903 | The status is a template `#type# #time#`: a text part (the activity name) and a stopwatch part counting from the moment the service started, which is the moment the exercise started (plan 300 starts the service when the Health Services exercise has started). The name is passed by `WearWorkout.begin` as an intent extra: the Health Connect name the Dart side sent (`exercise_type_strength_training`) turned into `Strength training` (strip the prefix, underscores to spaces, capitalised); an unknown or missing name reads `Workout`. | `WearWorkout.kt` `startService`; plan 300 D-30002 |
| D-30904 | A static icon resource for the chip (`ic_workout`, a plain vector in `src/wear/res/drawable`): the launcher icon is a full-colour adaptive icon and does not suit the chip. The same drawable is the notification's small icon. | Ongoing Activity icon guidance |
| D-30905 | Permission: the chip is tied to a posted notification. Since Android 13 a notification needs the notification permission, and the wear manifest already declares `POST_NOTIFICATIONS` (merged in) but the wrist never asks for it. The first build step is a probe on the emulator: start a workout with the permission denied and with it granted and read back whether the chip (or its record) exists. If it shows without the permission, nothing more is built. If it needs it, the wrist asks for it with the same one-question-at-start pattern as plans 298 and 306 (`activeEnergyPermission`'s twin, asked by the store right after the calories question), and the owner decides below whether that third prompt is worth it. | owner question 1 |
| D-30906 | Not in scope: live heart rate or calories in the chip (the status would need periodic updates), a paused state, the rest countdown, a watch tile or complication, Wear OS 6's richer progress notification styles. | |

## Input-reality checklist

- **Writers/units.** One service instance, one notification id; the stopwatch part is the platform's, counting from a fixed instant, so the app does not tick.
- **Lifecycle.** Started when the exercise starts, stopped when it ends (plan 300); `START_NOT_STICKY`, so a killed process does not resurrect a chip for a workout that is no longer tracked. The stopwatch counts from the service's own start, so a service started again for a recovered workout restarts at zero (the workout's real clock is the app's, not the chip's): accepted and written in the docs.
- **Settings changing while open.** The notification permission revoked mid-workout removes the chip, nothing else.
- **Time.** The stopwatch uses the elapsed-realtime clock, so a clock change cannot move it.
- **Load.** None: no updates are posted after the first.
- **Wording.** `<Activity name> <m:ss>`; `Workout` for an unknown type.
- **Slot competition.** On the watch face the chip competes with the face's own slots and other apps' chips; the platform decides.
- **Readers that wait.** None.

## Scenarios

| ID | Fixture | Expect |
|---|---|---|
| S-30901 | source guards: dependencies | the wear block declares both libraries, the phone flavor neither |
| S-30902 | source guards: the service | `NotificationCompat.Builder`, ongoing, category workout; `OngoingActivity.Builder(...)` with the notification id, static icon, touch intent and status; `.apply(this)` before `startForeground`; the health service type and the not-sticky start unchanged |
| S-30903 | source guards: the status | the `#type# #time#` template, a text part and a stopwatch part from the service's start, in that order |
| S-30904 | the label function over a table of names | `exercise_type_strength_training` gives `Strength training`, `exercise_type_running` `Running`, `exercise_type_other_workout` `Other workout`, empty or missing or odd input `Workout` (a pure Kotlin function mirrored as a Dart table test through source text, since there is no Kotlin harness) |
| S-30905 | source guard: `WearWorkout.startService` | passes the name as an extra, and the service reads the same key |
| S-30906 | resources | `ic_workout.xml` exists, parses as a vector drawable, is white on transparent |
| S-30907 | emulator | the probe of D-30905 and the chip (or its record) observed; recorded in the evidence file |

Mutation pass by the lead over the source guards.

## Phases

0. Docs only, first: `docs/wear_os_app.md` is 52.0 KB against a 52.4 KB indexing band, so "The sensors" section moves whole to `docs/wear_os_app_sensors.md` (indexed in `docs/README.md`, with a pointer where it was) and the chip's paragraph goes there. Its tests keep passing (the docs contract is the same).
1. The probe (D-30905) on the emulator before any code is committed: a throwaway change to the service, the permission denied and granted, record what the system holds (`dumpsys notification`, the watch face).
2. The build: dependencies, the service, the label, the icon, the extra, tests, mutation, docs, commit.
3. If the probe says the permission is needed and the owner agrees: its question in the Dart store and `WearSensors` (the twin of plan 306's calories question), with its own tests.

## Docs delta

`docs/wear_os_app_sensors.md` (new, moved section + the chip), `docs/wear_os_app.md` (pointer), `docs/README.md` (index row), owner check 24: start a workout, go to the watch face, see the chip with the activity and a running time, tap it and land on the workout, end the workout and the chip goes.

## Owner question (behaviour)

1. **Is a possible third system prompt acceptable?** The first workout already asks for heart rate and physical activity. If the system only shows the chip when notifications are allowed, the chip would need a third question ("Allow OmniTrain to send you notifications?"). Recommended: yes if the probe shows it is needed, because a chip you cannot see is the whole feature; if the probe shows the chip appears without it, no prompt is added and this question never arises. If you would rather not add a prompt, the chip shows only for users who allowed notifications some other way.

## Progress

| Item | Status |
|---|---|
| seed | Done |
| owner question 1 | Open (only if the probe needs it) |
| phase 0 docs split, probe, build, tests, mutation (32/32), emulator, docs | Done (evidence file) |
| commit | Done |
| owner check 24 | Open |
