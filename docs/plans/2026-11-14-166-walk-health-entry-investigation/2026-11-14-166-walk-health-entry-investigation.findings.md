# 166 — Why the walk reached Apple Health as a 15-minute "Outdoor Run"

Investigation of the owner's report of 2026-11-14 (watch-started Cardio workout, exercise
"Brisk Walk", one 40m 4s round, 1.61 mi, app killed at ~25-30 min, Fitness shows **one**
"Outdoor Run" of **0:15**). No product code was changed. No scratch file was created.

The folder the brief names (`docs/plans/2026-11-14-166-walk-health-entry-investigation/`) does not
exist in the working tree and this run cannot create directories, so this file sits beside it; move
it into the folder verbatim when the folder is made.

---

## Verdict table

| # | Question | Cause | Evidence | Confidence |
|---|---|---|---|---|
| 1 | Why the type is **Outdoor Run** | The session carries the modality `cardio_endurance` (the "Cardio" workout). `forSession` prefers the session's **modality** over its exercises, and `cardio_endurance` is in the table as **running**. "Brisk Walk"'s own Health kind (`walking`, sent by the phone) is only consulted for a session with **no** modality. | `WatchPlatformWorkout.swift` `WatchActivityTypes.byModality` (`"cardio_endurance"` → `"running"`, ~l.63-66); `forSession(_:)` (modality first, exercises second, ~l.188-194); `start(_:)` (~l.352-366) fixes the type on the `HKWorkoutSession` | **High** — the path is mechanical, and the wrist log's own `workout_begin <sessionId> running` line records the type it chose |
| 2 | Why the entry is **0:15** of ~40 min | The visible workout is the one the **relaunch** opened. After a kill HealthKit reports the stranded session as **ended**, `adoptInProgress()` refuses to continue anything not `.running`/`.paused`, so the next `apply` calls `begin` and creates a **new** `HKWorkoutSession` at the relaunch instant. The pre-kill builder is a separate workout at best. | `HealthKitWorkoutStore.adoptInProgress()` (`guard recovered.state == .running \|\| recovered.state == .paused else { pendingRecoveryName = name; return nil }`); `recover()` in `WatchWorkoutCoordinator` (ends instead of adopting); `apply` re-opens when `running == nil`; `begin` collects from `startDate = Date()` | **High** that the 0:15 entry is the post-relaunch span; **medium** on whether the first ~25 min were saved as a second entry or dropped (see §2) |
| 3 | Why the phone still shows whole-walk 75 kcal and 96/127 bpm | The watch's own sensor rows survive the kill (append-only store, plan 156), and the summaries are computed **over the session window, after the fact**: heart rate is a plain mean/max over every stored beat in `[sessionStart, sessionEnd]`; energy and steps **explicitly chain across a counter restart** ("A count smaller than the one before it means the counter restarted (a recovered workout)"). Health's builder, by contrast, only ever holds the run it collected. | `WatchSensorSummaries.heartRate`, `.steps`, `.activeEnergy`; `WatchSensorRecording.swift` header ("A kill mid-run therefore costs the user nothing") | **High** for HR and kcal, from source |
| 4 | Why the phone's distance (1.61 mi) is the whole walk | **Not settled.** Distance is the one reading that is *not* chained: `distanceMeters` is the newest stored `gps`/`distance` total, and a relaunch starts a new `WatchDistanceTracker` at 0 under the same session (the pace code says so outright: "A relaunch restarts the platform's cumulative total under the same session", S-15007). A 1.61 mi figure therefore cannot be the post-relaunch run alone. | `WatchSensorRecording.WatchSensorReadings.distanceMeters`; `WatchLoggingState.paceLabel` doc + `distanceWindow(for:)`; `WatchDistanceTracker` (no seeding) | **Low** — needs the entry payload or the Health export (§5) |
| 5 | Does Health see a distance/route at all | No distance and (after a relaunch) no route: `begin` enables collection for heart rate, step count and active energy **only** — never `.distanceWalkingRunning` — and `openRoute` is called at `begin` only, never in `adoptInProgress`. The distance course therefore comes from the phone or the wrist, not from Health's own builder. | `HealthKitWorkoutStore.begin(_:outdoors:)` (`enableCollection` × 3, `openRoute(on:startedAt:)`); `adoptInProgress()` (re-enables stepCount/activeEnergyBurned, no route) | **High** |

---

## 1. TYPE — how the type is chosen, and why this one was "running"

### Where the type comes from

`WatchPlatformWorkout.start(_:)` (~l.352-366) asks for the session's type and hands it to the store
once, at open: it resolves `WatchActivityTypes.forSession(session)` (falling back to the generic type),
calls `store.begin(activityType.watchOs, outdoors: WatchGPSPolicy.isRequired(session))`, and records
`workout_begin` with the chosen type as its detail.

The resolution order is (a) **the session's modality**, and only when there is none (b) **the
exercises**:

- `forModality(_:)` → `WatchActivityTypes.byModality[modality]`, where `"cardio_endurance"` maps to
  `"running"` (~l.63-66). `cardio_endurance` is a *category* modality — it covers running, cycling,
  rowing and walking — so the mapping is a default, not a statement about this walk.
- `forExercises(_:)` (~l.173-186) takes the **majority** of the exercises' Health kinds and breaks a
  tie with the earliest. `distanceType(_:)` (~l.149-156) then maps those names onto
  `HKWorkoutActivityType`; anything it does not know (including nil) falls through to **running**.
- The exercise's Health kind is the phone's `healthActivityOf(disciplineId:exerciseId:capabilities:)`
  (`lib/core/utils/watch_reference_sync.dart`, ~l.598-614): the walking discipline gives `walking`,
  except the built-in Hike and Rucking, which give `hiking`. "Brisk Walk" is
  `exercise-brisk-walk`, `disciplineId: 'discipline-walking'`, capabilities `['time','distance']`
  (`lib/mock/seed_data.dart`), so the phone sends **`walking`** for it.

### The start path the owner took

`WatchStartView` offers "Free workout" and the routines; the four modality buttons are not built.
`startFreeWorkout()` calls `createSession(modality: nil)`, while `startFromRoutine(_:)` starts with
`modality: routine.startModality` (`WatchStartPaths.swift`), which is the routine's **Focus** whenever
the wrist knows that modality (`WatchRoutineRecords.swift`, `startModality`). The phone's Focus for a
Cardio routine is `cardio_endurance` — "Cardio / Endurance"
(`lib/core/constants/modality_display.dart`); sessions started elsewhere are backfilled from the
template's Focus (`lib/core/services/routine_session_modality_backfill.dart`).

So: **a "Cardio" workout carries `modality: cardio_endurance`**, and `forSession` never looks at the
exercises. The walk is typed **running** the moment the workout opens. Had the same walk been started
as a Free workout, the type would have come from the exercise and would have been `walking` — the
inconsistency is the modality rule, not the exercise data.

Note the phone disagrees with itself here: the summary's title is "Walk"/"Brisk Walk" while the
modality is Cardio, and only the modality reaches HealthKit.

### The type is fixed before the exercise is known, and cannot be changed later

- HealthKit fixes the activity type in `HKWorkoutConfiguration` at `HKWorkoutSession` creation
  (`HealthKitWorkoutStore.begin`, configuration built ~l.126-131, session ~l.140). There is no retype
  path anywhere in the store: the builder's `metadata` is the only thing a later finish controls, and
  it does not change `workoutActivityType`.
- An exercise chosen *after* the workout opened cannot retype it: `WatchWorkoutCoordinator.apply`
  only starts a workout when one is not already running, and `openedForSessionId` keeps it that way.
- For a Free workout this is harmless in a different way: `WatchWorkoutLifecycle.action` returns
  `.none` while a session has neither modality nor exercises, so no workout opens, and the first
  exercise's Health kind decides the type. With a modality, a workout opens at Start — before any
  exercise exists.

## 2. DURATION — 15 minutes of ~40

### What the code does

At the relaunch, `ContentView.restore()` (~l.358-378) runs `recoverStrandedWorkout()` **before**
`engine.restore()`. That calls `WatchPlatformWorkout.recoverInProgress(saving:)` via
`WatchWorkoutCoordinator.recover`, which adopts only when two things hold:

1. the wrist's own stored session is still **active** (`engine.storedSession()` — a real store read,
   `store.readAll().sessions.max { $0.sequence < $1.sequence }`, so it is not a cold-start artifact), and
2. `store.adoptInProgress()` returns a name.

(2) is where a killed workout is refused: HealthKit hands back the stranded session, but its state is
no longer `.running`/`.paused`, and `adoptInProgress` stores it in `pendingRecoveryName` and returns
`nil`. The coordinator then **ends** it rather than continuing it — adoption is tried first and only
when the stored session is still active, and `recoverInProgress(saving: stillActive)` is the fallback.

`recoverInProgress(saving:)` logs `workout_recovered <type> saving|discarded` and clears `running`.
It also states the design plainly: "A kill cannot be caught, so the only reliable moment to notice an
orphaned workout is the next start".

The next `apply` for the restored active session sees `platform.running == nil` and calls `.start`,
so `store.begin` opens a **new** `HKWorkoutSession` whose collection starts `at: Date()` — the relaunch
instant. When the owner Ends the walk, that builder's `end(saving: true)` finishes it: the entry is the
relaunch-to-End span, which is what "0:15" is.

Two candidate explanations for the pre-kill ~25 minutes, both consistent with the code:

- **(a) It was saved as a separate, earlier workout** under the same session and the owner only saw
  one entry. `saving` is `stillActive` — true here — and `end(saving: true)` does
  `endCollection(at: Date())` + `finishWorkout()`. If HealthKit honours that on an ended session, an
  Outdoor Run of ~0:25 exists next to the 0:15. `HKWorkout` samples are distinct objects, so the two
  minutes would not merge.
- **(b) It was dropped silently.** The same call's `catch` swallows a failed finish ("a saved workout
  is a bonus, a workout left open is a lie"), and plan 150's evidence already recorded a recovered
  builder whose `finishWorkout()` threw. Nothing in the log distinguishes "saved" from "failed":
  `workout_end` records the *intent* (`saving`/`discarded`), not the outcome.

An adopted builder, by contrast, keeps the original workout (that is the point of plan 140/150's
adoption), so had adoption succeeded the single entry would have read ~0:40. It reads 0:15, which is
itself the evidence that adoption did not happen.

### What the device log would show

Read the wrist's diagnostics for that session, in order:

- `workout_begin <sessionId> running` — confirms §1's type.
- `recovery_relaunch` (`OmniTrainApp.swift`) — the system relaunched the app for a pending workout
  rather than the owner tapping it; absence means an ordinary cold start.
- `workout_adopted <name>` — adoption; expected to be absent.
- `workout_recovered running saving|discarded` — which branch the stranded builder took.
- `workout_begin <sessionId> running` **again**, a second time inside the same session — the
  relaunch's new builder; this is the 0:15 entry.
- exactly one `workout_end saving` and no `workout_end discarded` — the End of the walk.

## 3. CALORIES, HEART RATE, DISTANCE — where the phone's numbers come from

The wrist keeps its own readings in the same append-only store as everything else, so a kill costs
nothing (plan 156 / `WatchSensorRecording.swift` header). At session end it summarises them **over the
whole session window**:

- **Heart rate** — `WatchSensorSummaries.heartRate(samples, from:through:excluding:)` is a mean and a
  maximum over every stored beat inside the window: AVG 96 / MAX 127 are the walk's own numbers, taken
  before the kill as well as after. Health's builder, restarted at the relaunch, holds beats for 15
  minutes of that.
- **Active energy** — `.activeEnergy` chains the platform's cumulative kilocalorie counter start to
  finish and treats a smaller count as "the counter restarted (a recovered workout)", adding the new
  count instead of subtracting. 75 kcal is therefore the whole walk by construction, from rows the
  wrist wrote itself.
- **Steps** — same chain, same restart rule.
- **Distance** — the exception. `WatchSensorReadings.distanceMeters` is the newest stored total, and
  the total restarts at 0 with each run of the tracker; the logging layer knows it ("A relaunch
  restarts the platform's cumulative total under the same session", `WatchLoggingState.paceLabel`,
  S-15007) and pairs each counter run with its own window. So the wrist's distance after the relaunch
  covers only the new run, and the importer writes exactly what the entry carried
  (`lib/core/services/watch_session_importer.dart`: `distanceMeters`, with `distanceSource` measured
  or hand-entered).

**Why the phone and the Fitness app disagree.** The three chained readings being whole-walk and
Health's being 15-minute is expected, not a contradiction: they come from different stores. The 1.61 mi
is the one number the code says should **not** be whole-walk, so it is the one to explain before
trusting the rest (§5).

Also worth knowing for Health's own numbers: the builder never collects a distance type (see the
verdict table, row 5), and a route only exists for a workout this process opened (`openRoute` at
`begin`), so a saved 15-minute run has no course and no Health-computed distance.

## 4. Defects and the smallest fix for each

| Defect | Smallest location | The user-visible consequence | Owner decision |
|---|---|---|---|
| A walk inside a Cardio-modality session is recorded as a run | `WatchPlatformWorkout.forSession(_:)` — let the exercises' agreed Health kind win when they name one, and keep the modality as the fallback (`WatchPlatformWorkout.swift` ~l.188-194; the Dart mirror `lib/watch/sensors/watch_platform_workout.dart` carries the same table and must move with it) | A Brisk Walk would appear as an Outdoor Walk; a treadmill run inside the same routine still appears as a run, because its own kind is `running` | **Yes**: this reverses plan 75 D-2's "modality decides" rule. Alternative with no rule change: put a Health kind on the *routine* instead of the category modality — bigger, and it still needs the exercise to be honoured when it disagrees |
| A killed workout is split in two, the second part typed by whatever the session says | Nowhere cheap: `HKWorkoutSession`'s type and start are fixed, and the relaunch cannot continue an ended one | Plan 150 already chooses "end the stranded workout", so the entry the owner opens is the post-relaunch piece | **Yes, a product decision**: (i) accept split entries and make the first part's save reliable and visible (log the `finishWorkout()` result instead of swallowing it, at `HealthKitWorkoutStore.end(saving:)`); (ii) don't open a second `HKWorkoutSession` when the launch is a `recovery_relaunch` continuation, leaving Health with the first part only; or (iii) at End, `discardWorkout()` the builder and save the wrist's own `HKWorkout` (correct type, full duration, route from the kept points) — the only option that yields one Health entry matching the phone's summary, at the cost of the live-session "Fitness" link and a route builder of our own |
| Health's workout has no distance and no route | `begin`: add `.distanceWalkingRunning` to `enableCollection`; `adoptInProgress()`: call `openRoute` so an adopted run keeps its map | A walk/run in Fitness shows a course and a distance that Health agrees with | No — but it only matters while a builder is the record |
| A failed save is invisible | `HealthKitWorkoutStore.end(saving:)`: turn the empty `catch` into a `diagnostics` note | Support can tell "discarded" from "failed" | No |
| The modality is a *category* (Cardio), yet it silently types a workout | same row as the first | as above | same |

## 5. What could not be determined from the repository

1. **Whether the session really carried `modality: cardio_endurance`.** Everything follows from it.
   Check the routine's Focus on the phone, the imported session's modality, and the wrist log's
   `workout_begin … running` line. If it turns out the session had no modality, then the type came
   from `forExercises` and the exercise the wrist held at the moment the workout opened was not "Brisk
   Walk" (or its `healthActivity` never arrived) — a different, narrower defect worth its own
   investigation.
2. **Whether the first ~25 minutes were saved as a second workout or dropped** — §2 (a) vs (b). Needs
   all Health workouts for that day (Fitness app "Show All Workouts" or an export), or the device log's
   `workout_recovered … saving` line plus the absence of a second `workout_end`.
3. **Where 1.61 mi came from.** Needs the watch entry that carried it: its `distanceMeters` and
   `distanceSource`. A measured whole-walk distance contradicts a restarted tracker and would mean the
   process was suspended rather than killed (or that the app resumed a stored total, which the code
   does not do). The other candidates are a hand-entered distance and a phone-side figure.
4. **The kill method and its timing.** A force-quit, a crash and a watchOS-initiated relaunch leave
   different HealthKit state (`.ended` vs a recoverable live session). The exact minute matters too:
   0:15 should equal `end − relaunch`, not `40 − kill`.
5. **The Android/wear side.** Only the watchOS client was read; the `wear` half of
   `WatchActivityTypes.byModality` is untouched by this report.

## 6. Sources read

- `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` (`byModality`, `distanceType`,
  `forExercise`, `forExercises`, `forSession`, `start`, `end`, `recoverInProgress`,
  `continueInProgress`, `WatchWorkoutLifecycle`, `WatchWorkoutCoordinator`)
- `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`, `WatchRoutineRecords.swift`
- `watch/watchos/Sources/WatchSessionEngine/WatchSensorSummaries.swift`,
  `WatchSensorRecording.swift`, `WatchLoggingState.swift`, `WatchDistanceTracker.swift`,
  `WatchSessionEngine.storedSession()`
- `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` (`begin`, `adoptInProgress`, `end(saving:)`,
  `inProgressActivityTypes`, `activityType(for:)`, `name(for:)`), `ContentView.swift` (`restore`,
  `recoverStrandedWorkout`), `OmniTrainApp.swift` (`recovery_relaunch`)
- `lib/core/utils/watch_reference_sync.dart` (`healthActivityOf`), `lib/mock/seed_data.dart`
  ("Brisk Walk"), `lib/core/constants/modality_display.dart`,
  `lib/core/services/routine_session_modality_backfill.dart`,
  `lib/core/services/watch_session_importer.dart`, `lib/watch/sensors/watch_platform_workout.dart`
- `docs/plans/2026-10-24-75-health-type-per-exercise-plan/…` (why `cardio_endurance` → running, and
  the `healthActivity` design), `docs/plans/2026-11-12-150-watch-crash-fix-plan/…evidence.md`
  (adopt/discard evidence), `docs/plans/2026-11-14-160-watch-own-workout-reaches-phone-plan/…`

No scratch file was created, so nothing had to be removed; no Dart or Swift source was edited, so no
test or check result is affected by this run.
