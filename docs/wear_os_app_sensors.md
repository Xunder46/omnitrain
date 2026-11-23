# The Wear OS App: sensors

> Split from [The Wear OS App](wear_os_app.md) on 2026-11-22 to keep that page under the indexing band; the section below moved whole.

## The sensors

The wrist wires the session's sensors in the shell (plan 297, the Dart half of plan 280 item 9), and the platform side is built for the heart rate (plan 298), the distance (plan 299) and the workout itself (plan 300). `WearApp` takes the session's `WatchSessionSensors`; the shell starts them once when a session becomes active and stops them when none is, on every path that starts or ends a session, because each of those paths already passes through the shell's once-per-change `_syncTicker`: a session started from the Start screen or a routine, one the phone started, one restored at launch, an End or a Discard from the menu, and a session the phone ended. Starting and stopping run one at a time on one lane and each step gives up after 5 seconds, so a native call that never answers cannot keep a later session's sensors from starting. The heart-rate readings go through the recorder that already existed, into the session's own store, and the logging surface's sensor line shows the newest one (`91 bpm`). Logging never depends on a sensor: a refused, absent or failing source changes nothing the user sees (`test/wear_sensors_shell_test.dart`).

`WearSensorSource` (`lib/watch/sensors/wear_sensor_source.dart`) is the contract the native half will answer: a method channel `omnitrain/wear_sensors/methods` with `heartRatePermission` and `locationPermission`, each answering `granted`, `denied` or `unavailable` (a call asks the user first when the state is undetermined), and two event channels, `omnitrain/wear_sensors/heart_rate` (beats per minute) and `omnitrain/wear_sensors/location` (cumulative metres). Any failure, including no native half at all, reads as `unavailable` (`test/wear_sensor_source_test.dart`).

The heart rate comes from Health Services' `MeasureClient` (`WearSensors` in `android/app/src/wear/kotlin/`, plan 298): a watch with no heart-rate sensor answers `unavailable`; otherwise the first question asks the system for the body-sensor permission (`BODY_SENSORS`, or `READ_HEART_RATE` from Wear OS 6) unless it is already held, and answers `granted` or `denied`; with it, each reading is sent to Dart and the platform subscription ends with the workout. The phone build carries none of this. The Kotlin side has no test harness, so its guards are source checks (`test/wear_heart_rate_native_test.dart`), and on the emulator the prompt, the grant, the denial and live synthetic readings were seen. The distance comes from the fused location provider (`WearSensors` and `DistanceTracker` in `android/app/src/wear/kotlin/`, plan 299): a watch with no GPS answers `unavailable`; otherwise the first question asks the system for the location permission (fine and coarse together) unless it is held; with it, the stream asks for high-accuracy fixes every 2 seconds with a 3 metre minimum step and sends the running total in metres, which the existing sensor line shows in kilometres or miles. A fix with no accuracy or worse than 50 metres is ignored, so is one more than 10 seconds old (a cached fix from earlier), and a step that would need more than 15 metres a second is a new starting point rather than distance (the emulator's first fix once made the probe read 222 km). The Dart side subscribes only for an exercise with the `distance` capability, so a lift never wakes the radio. On the emulator the prompt, the grant, and a simulated walk (about 5.5 metres every 2 seconds adding up to the metres walked) were seen; the guards are source checks (`test/wear_distance_native_test.dart`). The platform workout is a Health Services exercise (`WearWorkout` and `WorkoutService` in `android/app/src/wear/kotlin/`, plan 300): when the session's sensors start the wrist asks the body-sensor permission (the heart-rate question, once) and, only if it is held, starts an exercise of the type the workout calls for (running for distance work, strength training for lifts, stretching for holds, otherwise a generic workout; the shared type table's watchOS name is translated to the Health Connect name by `WatchActivityTypes.wearFor`) with heart rate as its data type, then a foreground service of type `health` whose ongoing notification says `Workout in progress` and opens the app, so the system keeps the process while the wrist is down. Ending the workout, discarding it or the phone ending it ends the exercise and then stops the service; at launch the wrist first asks whether an exercise of its own is still running and ends it, before the restored session registers a fresh one. A refused permission or a Health Services failure registers nothing and changes nothing the user sees. On the emulator the exercise started, the foreground service ran as a health service with its notification channel, the exercise reported in progress, and both ended with `end`; the real app's restored session started the service; the emulator ended the exercise itself when the app was force-stopped, so a stranded exercise was not seen (`test/wear_platform_workout_store_test.dart`, `test/wear_workout_native_test.dart`).

The calorie count (plans 305 and 306) is on its own page: [The Wear OS App: calories](wear_os_app_calories.md).

## The watch-face chip (plan 309)

While a workout runs the watch face shows a small icon (a dumbbell) that opens the app when tapped, and the recents list shows a chip reading the activity and a running stopwatch (`Strength training 12:34`). It is the Wear Ongoing Activity API (`androidx.wear:wear-ongoing`, wear flavor only) attached to the notification the workout's foreground service already posts (plan 300): `WorkoutService` builds it with `NotificationCompat.Builder` (ongoing, workout category, opens the app), attaches `OngoingActivity.Builder(...)` with the white vector icon `ic_workout`, the same open intent as its touch intent and a status template `#type# #time#` (a text part and a stopwatch part counting from the moment the service started, on the elapsed-realtime clock), applies it, and posts the notification as before (type `health`, not sticky). The words come from the Health Connect name `WearWorkout.begin` passes as an intent extra: `exercise_type_strength_training` reads `Strength training`, a missing or unfamiliar name reads `Workout`. Nothing updates the chip after the first post, and a service started again for a recovered workout restarts its stopwatch at zero.

**The chip needs the notification permission.** On Android 13 and later the system blocks the workout's notification without it, and no icon or chip shows (observed on the emulator: denied gives a running service and no chip; granted gives the notification, its Ongoing Activity data and the icon on the watch face, and a tap opens the app). So the third question of a first workout, after heart rate and physical activity, is "Allow OmniTrain to send you notifications?": `WearPlatformWorkoutStore.begin` asks `notificationPermission` (a separate optional `WatchNotificationSource`, implemented by `WearSensorSource`; the Kotlin answer is `granted` at once before Android 13) after the calories question and before the workout starts. A refusal is remembered for the process and the workout, its heart rate and its calories all work without the chip. Taking this prompt out is the removal of that one call.

Not done: live heart rate or calories in the chip, a paused state, the rest countdown, a watch tile or complication.

Verified by `test/wear_ongoing_activity_test.dart` (plan 309): the dependencies (wear flavor only), the service's builder, activity, status and order, the words, the extra, the icon, the store's asking order and the remembered refusal, and source guards on the Kotlin answer and the manifest (there is no Kotlin test harness). Owner check 24 in [The Wear OS App](wear_os_app.md) "Checks on a watch".

The session end carries the heart rate: when the workout ends, the
`session_end` entry gains the average and the maximum over the whole session —
every stored heart-rate reading from the session's start to its end, both ends
included, with a reading below 1 bpm or not a number ignored — and
one pair for each set block. A set block is the sets logged for one exercise
slot: it spans from the last effort logged before its first set (or the
session's start, when none is logged) to its last set; a block with no reading
in its span is left out; a session with no readings sends none of it (never a
zero). A session the wrist created and one the phone ended carry it alike, and
the phone already reads these fields for any watch
(`lib/core/services/watch_session_importer.dart`), so nothing changes there.
`test/wear_heart_rate_session_end_test.dart` proves it: the window, the 1 bpm
floor, the non-number and the other kinds by S-31001 `the window keeps the
readings at both ends and ignores the rest` and `each non-qualifying reading
alone gives null`; the set block and its span by S-31003 `blocks come out in
the order they began, each over its span` and S-31004 `the tie at 10:20 breaks
by entryId, and each block leads from its own effort`; the pair and the block
pairs on the entry by S-31005 `a wrist-created session with readings over
every span`; the absences by S-31006 `a session with no heart-rate samples
sends none of the keys` and `readings outside every block span keep the
session pair only`; the followed end and the phone's deletions by S-31007 `a
followed session carries the pair and followed: true` and `a set the phone
deleted is not a block member`; the validator's acceptance by S-31008 `a
session_end the engine builds passes its own validator` and `a hand-built pair
above its maximum is refused`; the pair's bounds and the session's isolation
by S-31009 `equal readings average to exactly their value` and `an earlier
session's sets and a skewed reading never reach the next session's end`. `test/wear_heart_rate_per_effort_test.dart` (plan 311) proves what follows.

Each timed, round and hold entry carries its own heart rate — the average and
the maximum over that entry's own window, measured from the readings stored at
the moment it is logged and never again; a set carries none; an entry with no
reading in its window carries none (`S-31105 a timed effort carries its
window's heart rate` `readings inside the window land on the entry`,
`a window nothing was measured over adds nothing` and `a set has no window of
its own and carries nothing`; `S-31106 a hold carries its window's heart rate
too` `the pair sits beside the extra load the hold carried`).

a round leaves its paused stretches out — the round's heart rate skips the
stretches its countdown was paused (a pause lasts from the moment it began to
the moment the countdown ran again; the instant it resumes counts again:
`S-31101 the pause interval is half-open` `readings inside the pause are left
out, the resume instant is kept`, the pauses read from the timer's rows by
`S-31102 the pauses of one timer, read from its rows` `a pause ends where the
timer next ran again`), and the round also carries `pausedMs`, the time the
countdown spent paused — an open pause counted up to the round's end, never
longer than the round, absent when zero or when no countdown ran
(`S-31103 a round's pausedMs` `an accumulated pause alone is what it
accumulated`, `an open pause is counted up to the window's end` and `the pause
is never longer than the window`; `S-31107 a round leaves its paused stretches
out` `a paused round keeps only the readings outside the pause and sends
pausedMs`, `a never-paused round counts every reading and sends no pausedMs`
and `a round paused for the whole window sends no pair and a full pause`;
`S-31109 the corners the mutation pass found` `rows handed over out of order
read the same pauses`, `a later resume wins over the paused row's own stop`,
`an open pause is counted up to the stop, not to the window's end` and
`a negative accumulated pause counts as none`). The engine hands the summary
a timer's rows (`S-31104 the engine's timerRows` `one timer kind of the
current session, in append order`), and the emission validator accepts every
logged entry and refuses a `pausedMs` above its window (`S-31108 the emission
validator accepts every logged entry` `the entries of S-31105..S-31107 pass
the shared schemas` and `a round whose pausedMs exceeds its window is
refused`). Steps are not sent (the Wear wrist has no step source).

> **Doc freshness** - Derived from `lib/watch/` and `android/app/src/wear/` on 2026-11-22. If a claim here disagrees with the source, the source wins.
