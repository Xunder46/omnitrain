# Feature: 68 — an outdoor run recorded on the watch shows its route map in Apple Fitness

> Status: Iteration 1 active. Owner answers pending (Q1–Q9 below); every D-x built on a default is marked **(default, Qn)** and may be vetoed before the phase that uses it starts.
> Next handoff: @developer (Phase 1)
> Base: `7912d738` on `claude_develop` (plans 61/62 are now committed there; the tree still carries another session's uncommitted `lib/core/platform/watch_transport.dart`, `test/watch_transport_test.dart`, `watch/sync_protocol/PROTOCOL.md` — this plan touches none of them). Never create or switch branches; git belongs to the governor.
> Binding conventions: `docs/global_conventions.md`; `.github/copilot/pr-scope-budget.md`; `docs/state_management/watch_sensors.md` (the doc this plan amends).
> Track: watch client only (`watch/watchos/`, `ios/OmniTrain Watch App/`). No phone code, no sync contract, no Dart wrist twin.

## Overview

| What you do | Now | After 68 |
|---|---|---|
| Run outdoors with the watch app (a run, ride or row exercise), finish | Fitness/Health shows the workout, no map | Fitness shows the workout **with the route map**; Health > Workouts > the workout > Route |
| Treadmill run (GPS sees you standing in one spot) | no map | no map (D-5) |
| Location access refused, or GPS never gets a fix | workout saved, no distance | unchanged: workout saved, no map, the existing "No distance, Location access is off" line |
| Lifting / holds / sports / a routine whose Health type is not Running | no map | no map (D-1) |
| First launch after updating | — | Health's permission sheet appears once more on the Start screen, now also listing **Workout Routes** (and Workouts under read) |
| Watch app killed mid-run, relaunched | the first part is saved as its own workout; the rest becomes a second workout | same, plus a best-effort map for each part (D-9, owner device check) |
| OmniTrain on the phone (session summary, history) | no map | no map (D-13) |

Researched platform facts (Apple docs, fetched 2026-10-24 from `developer.apple.com/tutorials/data/documentation/healthkit/...json`):
- F-1 "Creating a workout route": the app "must request permission to read and share both `HKWorkout` and `HKWorkoutRoute` samples" and must have Core Location permission; "Don't add any locations whose accuracy is greater than 50 meters. For best results, try to keep the time between locations to 3 seconds or less"; "After saving the workout, add any remaining locations to the route builder and call `finishRoute(with:metadata:completion:)`".
- F-2 `HKWorkoutRouteBuilder` (watchOS 4+): "use `seriesBuilder(for:)` to instantiate … Instantiating a `HKWorkoutRouteBuilder` directly is discouraged." `HKWorkoutBuilder.seriesBuilder(for:)` is watchOS 5+.
- F-3 `finishRoute(with:metadata:completion:)`: "You must call [it] before the system deallocates the builder. Failure to do so results in a loss of all route data"; "This method fails if you haven't added any location data"; it invalidates the builder.
- F-4 `insertRouteData(_:completion:)`: locations "may be inserted in any order; the builder sorts them by date when finalizing".
- F-5 `HKSeriesBuilder.discard()`: "Invalidates the builder and discards the collected data. Any further calls to the builder raise an exception."
- F-6 `recoverActiveWorkoutSession`: HealthKit "attempts to restore the previous workout session"; whether a recovered builder still holds the route points inserted by the killed process is **not documented — owner device check ODC-6**.
- F-7 Unverified, owner device checks: GPS fixes keep arriving with the wrist down during the workout (plan 19f relies on the workout keeping the app alive, no background-location mode; `ios/OmniTrainWatchApp-Info.plist` has only `workout-processing`) — ODC-2; Fitness draws the map for an `.outdoor` `running` workout — ODC-1.

Code facts (read 2026-10-24):
- The Health workout is `HKWorkoutSession` + `HKLiveWorkoutBuilder` in `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` (`begin(_:outdoors:)` l.96, `end()` l.150, `inProgressActivityTypes()` l.182, `resolveAuthorization()` l.260). `outdoors` is `WatchGpsPolicy.isRequired(session)` at open (`WatchPlatformWorkout.start`, l.261). The workout is never paused.
- GPS: `CoreLocationRawSource` (app target) → `WatchTrackedLocation.fixes()` (package; 10 s freshness gate) → `WatchDistanceTracker` → `WatchSensorRecorder` stores cumulative metres only. **No coordinate is kept anywhere; no route is stored** (`WatchSensorRecording.swift` l.46 comment; `docs/state_management/watch_sensors.md` l.182). The store already holds the `WatchTrackedLocation` (`init(location:)`, l.87), so no `ContentView.swift` change is needed.
- Health types today: share `workoutType`, `activeEnergyBurned`; read `heartRate`, `stepCount`, `activeEnergyBurned`. No distance is saved to Health (Q9).
- A treadmill run is an exercise with the `distance` capability (`lib/mock/seed_data.dart` `exercise-treadmill-run`), so it already opens an `.outdoor` Running workout and runs GPS. Pre-existing; not fixed here (D-5 keeps it map-free).

## Questions for the owner (one round; answer "all defaults" or "all defaults except Qn")

1. **Which workouts get a map?** Default: only watch workouts Health saves as an **outdoor Running** workout (today every run, ride, row or walk exercise saves as Running). Sports matches (saved as "Other") and lifting do not. Alternative: also outdoor sports sessions.
2. **Treadmill / standing in one place:** Default: no map when the whole workout never got more than **50 m** from where GPS first found you (a treadmill, a gym, a run that never started). A 400 m track run still gets its map.
3. **Bad GPS or location refused:** Default: the workout saves as today, just without a map (or with a straight line across a stretch where GPS dropped out); the watch shows **no new message** — the existing "No distance, Location access is off" line already covers a refusal.
4. **Permission sheet and wording:** Default: after the update Health asks once more (Start screen) and lists Workout Routes; the Health sheet sentence becomes "OmniTrain saves the workouts you finish on the watch, with the route of an outdoor run, to Health so they count toward your activity rings."
5. **App killed mid-run:** Default: best effort — the watch tries to save the map recorded so far with the part of the run Health recovers; the watch keeps no extra copy of the points. If Apple did not keep them, that part has no map.
6. **Rests, walking back, paused timers:** Default: the map covers the whole workout while GPS is on — rests and paused timers included, drawn as one continuous line (like Apple's Workout app when you never pause it).
7. **Privacy trim of start/end (home address):** Default: no trimming. The map lives only in your Health data; sharing it is your choice in Health.
8. **Map inside OmniTrain (phone summary):** Default: no — map only in Fitness/Health. A map in OmniTrain means sending thousands of points to the phone: a separate plan if wanted.
9. **Distance and pace in Fitness:** Today the watch saves no distance to Health, so Fitness shows the map but no distance/pace for the run. Default: not in this PR; a follow-up plan decides which number Fitness gets (Apple's own measurement or OmniTrain's, which can differ by a few percent).

## Resolved Decisions (Ledger)

- **D-1 (default, Q1)** A route is recorded only for a workout the store opened with activity name `running` **and** `outdoors == true` **and** route sharing authorized (D-7). Every other open (any other name, indoor, route sharing refused) records no route and creates no route builder.
- **D-2** Points come only from the existing location subscription: the route sees exactly the raw fixes `WatchTrackedLocation.fixes()` lets through its freshness gate (before the distance tracker judges them). The route never subscribes to the source itself, never starts the radio, never asks for location permission. So GPS still starts only when the session's current exercise counts distance (latch unchanged), and a refused permission means no points.
- **D-3** A point is accepted when, in this order: (a) latitude in [-90, 90] and longitude in [-180, 180], both finite; (b) horizontal accuracy finite, ≥ 0 and ≤ **50 m** (F-1); (c) timestamp ≥ the workout's begin instant; (d) timestamp strictly later than the last accepted point; (e) speed from the last accepted point (haversine metres / seconds) ≤ `WatchDistanceTracker.maxSpeedMetersPerSecond` (20 m/s), the first accepted point exempt. A rejected fix never becomes the reference. No movement floor, no smoothing. Duplicate deliveries are dropped by (d).
- **D-4** Accepted points go to Health in batches of exactly **10**, handed out when the 10th pending point is accepted; at close the remainder (0–9) is handed out. Never more than 10 points held in memory by the watch; no full route is kept.
- **D-5 (default, Q2)** At close the verdict is **save** when accepted count ≥ 2 and the largest great-circle distance of any accepted point from the first accepted point is ≥ **50 m** (50.0 exactly saves); otherwise **discard**. When D-1 opened nothing, the verdict is **none**. Distance math is the one haversine `WatchDistanceTracker` already owns (made module-visible; no second formula).
- **D-6** `end()` ordering: close the route first (no point is inserted after close), `endCollection`, `finishWorkout`; then if the verdict is save and `finishWorkout` returned a workout: insert the remainder, then `finishRoute(with: workout, metadata: nil)`; otherwise `discard()`. Every route error is swallowed: the workout save never depends on the route. After finish or discard the route builder is never called again (F-5).
- **D-7** The one authorization request (D-1503; S-3109 "exactly one read list") adds `HKSeriesType.workoutRoute()` to share, and `HKSeriesType.workoutRoute()` + `HKObjectType.workoutType()` to read (F-1). The existing gate (workout-type sharing) is unchanged. D-1's "route sharing authorized" is `authorizationStatus(for: HKSeriesType.workoutRoute()) == .sharingAuthorized`, read in `begin`.
- **D-8** The route builder is `builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder` on the live builder, after `beginCollection` succeeds; `HKWorkoutRouteBuilder(healthStore:` is never written (F-2).
- **D-9 (default, Q5)** When `end()` closes a workout recovered by `inProgressActivityTypes()`, after `finishWorkout` the store asks the recovered builder for its route series builder and calls `finishRoute(with:metadata: nil)`; failure (e.g. no points, F-3) is swallowed. D-5 cannot apply (the points are not known) — known limit.
- **D-10** `WatchRawFix` gains optional `altitudeMeters`, `verticalAccuracyMeters`, `speedMetersPerSecond`, `courseDegrees` (default nil; every existing initializer call compiles unchanged; the distance tracker ignores them). `CoreLocationRawSource` fills them from `CLLocation` as given (negative = invalid passes through). The store builds each `CLLocation` with `init(coordinate:altitude:horizontalAccuracy:verticalAccuracy:course:speed:timestamp:)`; a nil becomes altitude 0 with vertical accuracy -1, course -1, speed -1.
- **D-11 (default, Q6)** No route segmentation: rests, paused timers and GPS gaps produce one continuous route; the workout is not paused by this plan.
- **D-12 (default, Q7)** No start/end trimming.
- **D-13 (default, Q8)** Route points leave the watch only into HealthKit: no sync message, no phone model, no OmniTrain map; `watch/sync_protocol/` untouched. Supersedes the "route maps out of scope" line of `docs/plans/2026-07-13-11-d-watch-sensor-recording-plan.md` for the Health route only.
- **D-14 (default, Q3)** No new on-watch message; `WatchLoggingState.sensorNotices` unchanged.
- **D-15 (default, Q9)** No distance saved to Health in this PR.
- **D-16 (default, Q4)** Governor edits the three `INFOPLIST_KEY_NSHealthUpdateUsageDescription` lines of the watch target in `ios/Runner.xcodeproj/project.pbxproj` (Debug/Release/Profile, today l.~665/717/767) to the Q4 sentence. Governor action; guarded by S-9821.

## Feature Invariants

- The workout's save, the session's logging and its sync never depend on the route (store rule 1, `HealthKitWorkoutStore.swift` header).
- No extra radio time: the route adds no location subscription (D-2).
- The route builder is never called after `finishRoute` or `discard()` (F-5: an exception is a crash).
- `WatchSessionEngine` imports no OS location or HealthKit type (`WatchTrackedLocation.swift` header rule); all route rules live there and are `swift test`-able on macOS.
- `WatchTrackedLocation(source:)` and `HealthKitWorkoutStore.init(location:)` keep their shapes (read as text by S-3110 / `WatchSensorSourceSourceTests` l.302, l.572, l.607).

## Requirements and Acceptance Criteria

- AC-1 An outdoor running workout with ≥ 2 accepted points spread ≥ 50 m saves a route → S-9801, S-9807b, S-9811, S-9812, S-9818, S-9819, ODC-1.
- AC-2 No other workout gets a route builder → S-9814, S-9820.
- AC-3 Noisy, duplicate, stale, out-of-order and teleport fixes never enter the route → S-9803..S-9806, S-9815.
- AC-4 Treadmill / no fix / one fix → no route, workout saved → S-9807a/c, S-9808, S-9809, S-9819, ODC-3, ODC-4.
- AC-5 Memory bounded on a multi-hour run → S-9812, ODC-7.
- AC-6 Permission request carries the route types; one read list → S-9817, ODC-8.
- AC-7 Kill/recovery best effort → S-9822, ODC-6.
- AC-8 Nothing reaches the phone; docs say what is stored → S-9823, residue sweep.

## Existing-Functionality Impact

| Touched surface | Readers (grep 2026-10-24) | Effect | Guarded by |
|---|---|---|---|
| `WatchRawFix` (new optional fields) | `grep -rln WatchRawFix watch ios lib`: `CoreLocationRawSource.swift`, `WatchDistanceTracker.swift`, `WatchTrackedLocation.swift`, `WatchDistanceTrackerTests.swift`, `WatchSensorSourceSourceTests.swift` | additive, defaults nil; no Dart twin (`grep -rli rawfix lib test` → none) | D-10, S-9816, dependents green (S-9824) |
| `WatchTrackedLocation.fixes()` (tee) | `HealthKitSensorFeed.location()`, `ContentView.swift` l.172 (constructs; not edited), `WatchDistanceTrackerTests` (S-3206 x3), `WatchSensorSourceSourceTests` l.302/607 | distance stream unchanged; observer sees fresh raw fixes | D-2, S-9815, S-3206 tests |
| `WatchDistanceTracker` haversine visibility | only its own `accept` (`grep -rn "meters(from" watch`) | private → internal | S-9807 edge values |
| `HealthKitWorkoutStore` auth request | `WatchSensorSourceSourceTests` S-3109 (one read list), S-8812 (energy share/read), `WatchHealthAccessWiringSourceTests` S-8908 (`requestAccess`) | additive types | D-7, S-9817, S-9824 |
| `HealthKitWorkoutStore.begin/end/inProgressActivityTypes` | `WatchPlatformWorkout` (start/end/recover), `WatchWorkoutStoreSourceTests` S-1509 (name table, untouched) | route opened/closed inside the same calls | D-6, D-8, D-9, S-9818..S-9822 |
| `CoreLocationRawSource.didUpdateLocations` | `WatchSensorSourceSourceTests` S-3310 (no Always, no background updates, no HealthKit) | fills 4 more fields | S-9821 + S-3310 green |
| `docs/state_management/watch_sensors.md` l.182 "No route or map is stored" | docs index `docs/README.md` l.87 | becomes false: rewritten | P2 item 7, docs contract tests |
| `docs/watch-app-setup-and-qa.md` | — | **not touched**: 63,759 B, above the 52 KB split band; QA steps for this plan live in watch_sensors.md (ODC list). A QA-doc step waits for that doc's split (not this plan) | ordering note |
| Phone, sync contract, Dart wrist (`lib/watch`) | `grep -rni "route" watch/sync_protocol/PROTOCOL.md` → only "Routes an arriving message" sense | unaffected | D-13 |

Standing invariant checks: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` stays empty (no Dart change); `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` passes after the doc edit.

## UI Standards Impact

None: no OmniTrain screen changes. (The permission sheet is Apple's.)

## Scenarios

Package tests use a fresh keeper per test; "fix(t, lat, acc)" means `WatchRawFix(latitude: lat, longitude: 4.0, horizontalAccuracyMeters: acc, timestamp: T0 + t s)` with `T0 = Date(timeIntervalSince1970: 1_800_000_000)`; the workout begin instant is `T0` unless stated. 1° latitude = 6,371,008.8 × π/180 = 111,195.08 m, so Δlat 0.00006 = 6.672 m, 0.0002 = 22.239 m, 0.00017 = 18.903 m, 0.00044 = 48.926 m, 0.00045 = 50.038 m. "open(o, a, s)" = outdoors, activity name, route sharing allowed.

### S-9801: an outdoor run records, batches and saves
- Fixture: open(true, "running", true); 12 fixes, fix(i, 52.0 + i×0.00006, 5) for i = 0…11.
- Expected: offers 1–9 hand out nothing; offer 10 hands out fixes 0–9; offers 11–12 nothing; close hands out fixes 10–11 and verdict **save** (spread 11 × 6.672 = 73.4 m). Accepted count 12.
- Edge case of: none

### S-9803: accuracy gate
- Fixture: open(true,"running",true); fix(i, 52.0 + i×0.00006, acc_i), accuracies in order [-1, 0, 50, 50.01, NaN, 120]; plus fix(6, 91.0, 5) and fix(7, NaN-lat, 5).
- Expected: accepted count 2 (acc 0 and 50 only); close verdict **discard** (6.672 m spread).
- Edge case of: S-9801

### S-9804: duplicates and out-of-order
- Fixture: fix(5, 52.0, 5), fix(5, 52.00006, 5), fix(4, 52.00012, 5), fix(6, 52.00012, 5).
- Expected: accepted are the 1st and the 4th only; count 2.
- Edge case of: S-9801

### S-9805: nothing before the workout began
- Fixture: begin instant T0; fix(-1, 52.0, 5), fix(0, 52.00006, 5).
- Expected: first rejected, second accepted; count 1.
- Edge case of: S-9801

### S-9806: teleport (speed gate)
- Fixture arm a: fix(0, 52.0, 5), fix(1, 52.0002, 5) [22.24 m/s], fix(2, 52.00017, 5) [18.90 m over 2 s from the first].
- Fixture arm b: fix(0, 52.0, 5), fix(1, 52.00017, 5) [18.90 m/s].
- Expected: arm a accepts 1st and 3rd (count 2, the rejected 2nd never became the reference); arm b accepts both.
- Edge case of: S-9801

### S-9807: treadmill / standing in place (spread rule)
- Fixture arm a: 300 fixes fix(2i, 52.0 + c_i, 10), c cycling [0, 0.0002, 0.0004, 0.0002] (max 11.12 m/s, max spread 44.48 m).
- Arm b: arm a plus fix(600, 52.00045, 10) (27.8 m in 2 s from 52.0002; spread 50.038 m).
- Arm c: arm a plus fix(600, 52.00044, 10) (spread 48.926 m).
- Expected: a → all 300 accepted, verdict **discard**; b → **save**; c → **discard**.
- Edge case of: S-9801

### S-9808: no GPS fix at all
- Fixture: open(true,"running",true), no offers, close.
- Expected: nothing handed out, count 0, verdict **discard** (the store then calls `discard()`, never `finishRoute`, F-3).
- Edge case of: S-9807

### S-9809: one fix only
- Fixture: fix(0, 52.0, 5), close.
- Expected: verdict **discard**, close hands out fix 0 (the store discards it).
- Edge case of: S-9808

### S-9810: location revoked mid-run
- Fixture (keeper): 30 fixes fix(i, 52.0 + i×0.00006, 5), i = 0…29, then close. Fixture (tee): `ScriptedRawFixSource` (`WatchDistanceTrackerTests.swift` l.41) yields the same 30 raw fixes then finishes.
- Expected: keeper hands out 3 batches of 10, remainder 0, **save** (spread 193.5 m); tee observer saw 30 fixes and the distance stream finished.
- Edge case of: S-9801

### S-9811: pause / GPS gap
- Fixture: 60 fixes fix(i, 52.0 + i×0.00006, 5), i = 0…59; then gap: fix(359, 52.00354 + 0.0036, 5) (400.3 m in 300 s = 1.33 m/s); then 59 fixes 1 s apart continuing +0.00006 each.
- Expected: all 120 accepted, 12 batches, remainder 0, **save**; one route, no break.
- Edge case of: S-9801

### S-9812: very long run
- Fixture: 10,800 fixes fix(i, 52.0 + i×0.00003, 5), i = 0…10,799 (3 h at 3.34 m/s).
- Expected: exactly 1,080 hand-outs, each of exactly 10; no hand-out larger than 10; close remainder 0; **save** (spread 10,799 × 3.336 = 36,024 m). Runs in-memory under the normal suite timeout.
- Edge case of: S-9801

### S-9813: closed keeper refuses; reopen starts fresh
- Fixture: S-9801 then a further fix(12, 52.00072, 5); then open(true,"running",true) with begin T0 and fix(0, 52.0, 5).
- Expected: the post-close fix is refused and changes nothing; after reopen count is 1 (the earlier timestamp is accepted: state reset).
- Edge case of: S-9801

### S-9814: activation matrix (Q1)
- Fixture: S-9801's 12 fixes offered after each of open(false,"running",true), open(true,"other",true), open(true,"traditionalStrengthTraining",true), open(true,"flexibility",true), open(true,"crossTraining",true), open(true,"running",false).
- Expected: each → count 0, nothing handed out, verdict **none**. Only open(true,"running",true) records (S-9801).
- Edge case of: none

### S-9815: the tee sees fresh raw fixes, adds no subscription
- Fixture: `ScriptedRawFixSource` with clock C: f0 at C−11 s (stale), f1 at C (tracker origin), f2 at C+1 s 1 m away (under the tracker's floor), f3 at C+2 s 10 m away; accuracy 5.
- Expected: the observer receives f1, f2, f3 (not f0); the distance stream yields only f3's total (unchanged); the source counted exactly one subscription per `fixes()` call, with or without an observer; with no observer S-3206 tests stay green.
- Edge case of: none

### S-9816: rich fields pass through unchanged
- Fixture: raw fix with altitude 12.5, vertical accuracy 3, speed 3.3, course 90; and one built with the old 4-argument init.
- Expected: the observer receives the four values as given; the old-init fix has all four nil.
- Edge case of: S-9815

### S-9817..S-9822: app-target source guards (new `WatchRouteSourceTests.swift`; comment-stripped text, statements not substrings)
- S-9817 `HealthKitWorkoutStore.swift`: the one `requestAuthorization` call — share part contains `HKSeriesType.workoutRoute()` and still `HKObjectType.workoutType()`; read part contains `HKSeriesType.workoutRoute()` and `HKObjectType.workoutType()`; exactly one `read:`.
- S-9818 the store contains `seriesBuilder(for: HKSeriesType.workoutRoute())` and `authorizationStatus(for: HKSeriesType.workoutRoute())`; does not contain `HKWorkoutRouteBuilder(healthStore:`.
- S-9819 in `end()`'s body, `finishWorkout()` occurs before `finishRoute(with:`; `discard()` occurs in the store; `insertRouteData` occurs in the store.
- S-9820 the route is opened only on the keeper's answer: the store's `begin` body references the package keeper's open call with the `outdoors` argument and the activity name (no store-local `"running"` comparison: the rule lives in the package).
- S-9821 `CoreLocationRawSource.swift` reads `location.altitude`, `location.verticalAccuracy`, `location.speed`, `location.course`; S-3310 still green. The pbxproj's three watch `INFOPLIST_KEY_NSHealthUpdateUsageDescription` lines carry the D-16 sentence (red until the governor's edit; run after it).
- S-9822 `end()` contains a route finish for the recovered builder path (D-9) inside a swallowed `try?`/`do-catch`.

### S-9823: docs say what is stored
- Fixture: `docs/state_management/watch_sensors.md`.
- Expected: no sentence still says no route is stored; a "Route in Apple Fitness" section names D-1, D-3 (50 m), D-5 (50 m spread), D-13 and the ODC list; size stays under 52 KB (26,042 B today).

### S-9824: dependents stay green
- `swift test --filter` each of: `WatchDistanceTrackerTests`, `WatchSensorSourceSourceTests`, `WatchWorkoutStoreSourceTests`, `WatchHealthAccessWiringSourceTests`, `WatchOutdoorWorkoutTests`, `WatchGpsByExerciseTests`, `WatchHandDistanceTests`, `WatchEffortDistanceTests`, `WatchSensorRecordingTests`; then the full package.

(S-9802 deliberately unused. S-9825..S-9830 reserved for remediation.)

## Iteration 1

### Phase 1: route rules and the GPS tee in the package (@developer)
1. [ ] Add the four optional fields to `WatchRawFix` with nil defaults (D-10) — `watch/watchos/Sources/WatchSessionEngine/WatchDistanceTracker.swift` · `WatchRawFix`
2. [ ] Make the haversine module-visible and reuse it (D-5) — same file · `WatchDistanceTracker.meters(from:to:)`
3. [ ] New lock-safe keeper: open / offer / close, verdict none·save·discard, accepted count, batches of 10 (D-1, D-3, D-4, D-5) — new `watch/watchos/Sources/WatchSessionEngine/WatchRouteKeeper.swift` · `WatchRouteKeeper`
4. [ ] Add a route observer to the tracked location: called with each raw fix that passed the freshness gate, before the tracker; no new subscription; `init(source:)` unchanged (D-2) — `WatchTrackedLocation.swift` · `WatchTrackedLocation.fixes()`
5. [ ] Rewrite the "Route geometry is out of scope" comment: the package stores no route; Health gets one through the keeper — `WatchSensorRecording.swift` · `WatchLocationFix` doc comment
6. [ ] Tests S-9801, S-9803..S-9814 — new `watch/watchos/Tests/WatchSessionEngineTests/WatchRouteKeeperTests.swift`
7. [ ] Tests S-9815, S-9816, S-9810 (tee arm) — new `watch/watchos/Tests/WatchSessionEngineTests/WatchRouteTeeTests.swift`
8. [ ] Baseline (full `swift test` count before any edit), red→green for S-9807 (spread ≥ → >), S-9806 (speed gate removed), S-9804 (strict → non-strict), S-9812 (batch 10 → 11) — `2026-10-24-68-run-route-map-plan.evidence.md`

**Done Criteria** (run until green): gateway `swift-test` (Claude Code: `bash .claude/scripts/macos/with-timeout.sh 900 swift test --package-path watch/watchos --filter WatchRouteKeeperTests`, then `--filter WatchRouteTeeTests`, then each S-9824 filter, then the full package); pasted pass/fail counts; four mutants killed.
**Predicted Files**: `WatchDistanceTracker.swift`, `WatchRouteKeeper.swift` (new), `WatchTrackedLocation.swift`, `WatchSensorRecording.swift` (comment only), `WatchRouteKeeperTests.swift` (new), `WatchRouteTeeTests.swift` (new), the plan's evidence file, this plan (Progress, Assumption Log). Nothing in `ios/`, `lib/`, `docs/` other than the plan folder.

### Phase 2: Health route on the wrist (@developer), after Phase 1
1. [ ] Fill altitude, vertical accuracy, speed, course (D-10) — `ios/OmniTrain Watch App/CoreLocationRawSource.swift` · `locationManager(_:didUpdateLocations:)`
2. [ ] Add the route and workout types to the one request (D-7); refresh the header and `resolveAuthorization` comment — `HealthKitWorkoutStore.swift` · `resolveAuthorization()`
3. [ ] In `begin`, after `beginCollection`: read route share status, open the keeper (D-1), obtain the route builder (D-8) only when the keeper opened, set the tracked location's observer once — `HealthKitWorkoutStore.swift` · `begin(_:outdoors:)`
4. [ ] Insert each handed-out batch as `CLLocation`s (D-10, D-4), errors swallowed, never after close — same file (a small app-target helper file is allowed: `ios/OmniTrain Watch App/HealthKitRouteRecorder.swift`)
5. [ ] `end()`: D-6 ordering; recovered path D-9 — `HealthKitWorkoutStore.swift` · `end()`, `inProgressActivityTypes()`
6. [ ] Source guards S-9817..S-9822 — new `watch/watchos/Tests/WatchSessionEngineTests/WatchRouteSourceTests.swift`
7. [ ] Docs + residue sweep: rewrite `docs/state_management/watch_sensors.md` l.182 and add a "Route in Apple Fitness" section with D-1/D-3/D-5/D-13 and the ODC list (S-9823); residue grep `grep -rn "No route or map is stored\|Route geometry is out of scope" docs watch ios` → 0 hits
**Governor actions (not the implementer's):** D-16 pbxproj edit, then `xcodebuild` for target "OmniTrain Watch App", sdk watchsimulator (HealthKit/CoreLocation code compiles only there); then rerun S-9821.
**Done Criteria**: `swift test --package-path watch/watchos --filter WatchRouteSourceTests`, each S-9824 filter, full package; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`; invariant grep; residue grep 0; governor `xcodebuild` succeeded. Mutants: drop `workoutRoute` from share (S-9817), swap `finishWorkout`/`finishRoute` order (S-9819).
**Predicted Files**: `ios/OmniTrain Watch App/CoreLocationRawSource.swift`, `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`, optional `ios/OmniTrain Watch App/HealthKitRouteRecorder.swift`, `WatchRouteSourceTests.swift` (new), `docs/state_management/watch_sensors.md`, evidence file, this plan; governor: `ios/Runner.xcodeproj/project.pbxproj`. Not `ContentView.swift`, not `WatchLoggingState.swift`, not `PROTOCOL.md`, not `docs/watch-app-setup-and-qa.md`.

## Owner device checks (real watch, after Phase 2; simulator cannot show Fitness maps)
- ODC-1 Outdoor run ≥ 10 min → iPhone Fitness shows "Outdoor Run" with a map; Health > Browse > Activity > Workouts > the run > Workout Route.
- ODC-2 Same run with the wrist down most of the time → the map follows the streets (no long straight cuts). If it does not, distance is affected too: report, do not patch here.
- ODC-3 Treadmill run → no map. ODC-4 Location refused → workout saved, no map, the existing "No distance" line.
- ODC-5 Decline only Workout Routes in the Health sheet → workout saved, no map.
- ODC-6 Force-quit the watch app mid-run, relaunch, finish → note whether the first part's workout has a map (D-9 outcome).
- ODC-7 A run of 2 h or more → full map; the app stays responsive.
- ODC-8 First launch after update → the Health sheet lists Workout Routes once. ODC-9 Outdoor sports session → no map.

## Files Affected
Phase 1: the package files above. Phase 2: the app-target files, the new source-guard test, `watch_sensors.md`, pbxproj (governor). Read-only dependents: `HealthKitSensorFeed.swift`, `ContentView.swift`, `WatchPlatformWorkout.swift`, `WatchSensorRecording.swift` (logic), the S-9824 test files.

## Notes
- Dependency graph: Phase 1 → Phase 2 (the store calls the keeper and the observer). No re-ordering offered: Phase 2 cannot compile without Phase 1, and nothing is visible before Phase 2.
- Intermediate state after Phase 1: the observer exists with no subscriber in the app; behaviour on the wrist is unchanged; full `swift test` green.
- Size: one track, 2 phases, about 300 lines of production code (keeper ~120, tee ~20, store ~120, raw source ~10). Within budget; no series index.
- Follow-ups (not this PR): Health distance for runs (Q9); a QA-doc step once `docs/watch-app-setup-and-qa.md` is split below 52 KB; treadmill runs opening as outdoor workouts (pre-existing, Code facts).

## Progress
- [x] Phase 1 — built 2026-10-24, uncommitted
- [x] Phase 2 — built 2026-10-24, uncommitted (owner device checks open)

## Assumption Log
- The route finish calls live in `HealthKitRouteRecorder.swift`, so the source
  guard for the order reads `end()` in the store (`routeRecorder.close()` before
  `openSession.end()` before `finishWorkout()` before `routeRecorder.finish(`).
- For a recovered workout the route builder is asked for BEFORE the workout is
  finished (safer than after; Apple says a finished builder raises on further
  calls) and finished after.

## Feedback
