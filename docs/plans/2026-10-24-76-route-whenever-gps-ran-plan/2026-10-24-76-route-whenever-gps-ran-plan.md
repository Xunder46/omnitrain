# Feature: 76 — a run's route map is saved whenever the watch recorded GPS and you moved at least 50 m, whatever the workout was saved as

> Status: Iteration 1 active. Owner answer (2026-10-24, asked and answered): "Save the map if you moved 50 m+" — whenever GPS ran outdoors and the route covers at least 50 m, Health gets the route whatever the workout type is. One track: watch client (`watch/watchos/`, `ios/OmniTrain Watch App/`).
> Next handoff: `crew-builder-watch` (one phase), then the lead's xcodebuild. Supersedes plan 68 D-1 only; everything else in plan 68 stands.
> Base: `c1b1c5f0` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Binding: `docs/global_conventions.md`; `.github/copilot/pr-scope-budget.md`; `docs/state_management/watch_sensors.md`.

## Overview

| What you do | Now | After 76 |
|---|---|---|
| A routine that starts with lifting and has an outdoor run in the middle | Health saves a Strength Training workout with no route | Same workout type, and the run's route is attached when the run covered at least 50 m |
| A Free workout that starts on a ride, then you lift | Cycling (after plan 75) or Run today, route kept | Unchanged |
| Treadmill, standing in one place | No map | No map (the 50 m rule, unchanged) |
| An outdoor sports session with a distance exercise | No map (saved as Other) | Map when you moved 50 m or more |
| Lifting only | No route | No route (no GPS points, nothing saved) |
| Route sharing refused in the Health sheet | No route | No route |

I cannot confirm on a simulator whether Fitness draws the map for a workout saved as Strength Training; the route is attached to the workout in Health either way. That is an owner device check (ODC-1).

Code facts (plan 68 as built, re-read 2026-10-24):
- `WatchRouteKeeper.open(outdoors:activityName:routeSharingAllowed:beganAt:)` (`watch/watchos/Sources/WatchSessionEngine/WatchRouteKeeper.swift` l.~44-62) records only when `outdoors && routeSharingAllowed && activityName == "running"` (D-1 of plan 68). `HealthKitRouteRecorder.open(on:outdoors:activityName:routeSharingAllowed:beganAt:)` (`ios/OmniTrain Watch App/HealthKitRouteRecorder.swift` l.38-60) forwards them; `HealthKitWorkoutStore.begin` → `openRoute(on:outdoors:activityName:startedAt:)` (l.~146, 165-181) reads route sharing and calls the recorder, then points the location tee at it.
- The tee only sees fixes while GPS runs, and GPS runs only while the current exercise covers `distance` (plan 40 latch), so a lifting-first workout opens its route builder with no points until the run starts; the 50 m spread and 2-point rules at close decide (S-9807..S-9809).
- `outdoors` is the workout's location type at open (the first exercise decides): an indoor-opened workout still gets a route builder now; HealthKit accepts a route on any workout. (If a device check shows it refuses, errors are swallowed and the workout still saves: plan 68 D-6.)

## Decision Ledger

- **D-1** The route records for every Health workout the store opens when route sharing is authorized: `recording = routeSharingAllowed`. The keeper's `open` loses its `outdoors` and `activityName` parameters (new signature `open(routeSharingAllowed:beganAt:)`); `HealthKitRouteRecorder.open` and `HealthKitWorkoutStore.openRoute` lose them too; `begin(_:outdoors:)` still passes `outdoors` to the HealthKit configuration only.
- **D-2** Every other rule of plan 68 stays: accuracy ≤ 50 m, timestamps after the workout began and increasing, speed gate, batches of 10, verdict `save` only for ≥ 2 points with a spread ≥ 50 m, else `discard`, close before the workout is finished, errors swallowed.
- **D-3** A workout that never got a GPS fix, or a lifting-only one, produces verdict `discard` (the existing S-9808 path: `discard()` on the route builder, never `finishRoute`). No new message on the watch.
- **D-4** Memory: still at most 10 points held. GPS cost: unchanged (no new subscription; plan 68 D-2).
- **D-5** Docs: `docs/state_management/watch_sensors.md` "Route in Apple Fitness" states the new rule; a line in plan 68's file notes D-1 is superseded by plan 76 (the builder adds it under its Notes). `grep -n "outdoor Running\|activityName ==" docs/state_management/watch_sensors.md` lists what to change.
- **D-6** Waiting readers: none.

## Scenarios (ids `S-106xx`; grep 2026-10-24: unused)

- **S-10601 (keeper) route sharing alone decides.** Fixture: `open(routeSharingAllowed: true, beganAt: T0)` returns true; 12 fixes `fix(i, 52.0 + i×0.00006, 5)` (the S-9801 set) → offers 1-9 hand out nothing, offer 10 hands out 0-9, close hands out 10-11, verdict `save`. `open(routeSharingAllowed: false, ...)` returns false; the same 12 fixes hand out nothing; verdict `none`.
- **S-10602 (keeper) the old activation matrix moves.** The S-9814 test (`WatchRouteKeeperTests.swift`) asserted six rows that gave `none` (indoor, `other`, strength, flexibility, cross training, sharing false). Now only the sharing-false row stays `none`; the other five are replaced by one test: the keeper takes no activity or location argument (compile-level: the call has only the two parameters) and each of five former "no" cases (represented now by nothing) records. The builder rewrites S-9814 to match and states what it removed.
- **S-10603 (keeper) a lifting-first workout, run in the middle.** Fixture: `open(routeSharingAllowed: true, beganAt: T0)`; no offer for the first 900 s; then 12 fixes starting at `T0 + 900 s` (`fix(900 + i, 52.0 + i×0.00006, 5)`). Expected: all 12 accepted (timestamps after the begin instant), verdict `save`, 12 points handed out in total.
- **S-10604 (keeper) a lifting-only workout.** `open(true…)`, no offers, close → verdict `discard`, count 0 (S-9808 stays green).
- **S-10605 (keeper) treadmill still discards**: S-9807 arms a/b/c unchanged and green.
- **S-10606 (source guards, app target; exact statements).** `WatchRouteKeeper.swift` contains `recording = routeSharingAllowed` and does NOT contain `activityName == "running"` nor `outdoors &&`; `HealthKitRouteRecorder.swift` `open(` has parameters `on workout`, `routeSharingAllowed`, `beganAt` and no `outdoors`/`activityName`; `HealthKitWorkoutStore.swift` `openRoute(` has no `outdoors`/`activityName` parameter, its body contains `routeSharingAllowed: sharing`, and `begin` still contains `configuration.locationType = outdoors ? .outdoor : .unknown`. The old plan-68 guards that asserted the old arguments (`WatchRouteSourceTests.swift` S-9818/S-9820: grep `outdoors` and `activityName` in it) are rewritten to these statements; the builder lists every changed assertion.
- **S-10607 (docs)** `watch_sensors.md` no longer says the route needs a Running workout.

## Phase 1 (`crew-builder-watch`, one run, 6 items)

1. [ ] D-1 keeper — `WatchRouteKeeper.swift`.
2. [ ] D-1 recorder — `HealthKitRouteRecorder.swift`; store — `HealthKitWorkoutStore.swift` `begin`/`openRoute`.
3. [ ] Update plan-68 tests: `WatchRouteKeeperTests.swift` (every `open(` call: 4 + S-9814 matrix), `WatchRouteTeeTests.swift` (if it calls `open`), `WatchRouteSourceTests.swift` (guards naming `outdoors`/`activityName`); grep `open(outdoors` across `watch/watchos/Tests` and list every call site.
4. [ ] New tests S-10601, S-10603, S-10604 (keeper), S-10606 (guards) — in `WatchRouteKeeperTests.swift` / `WatchRouteSourceTests.swift`.
5. [ ] Docs D-5.
6. [ ] Report FIRST as a skeleton.

**Done**: `swift test --package-path watch/watchos --filter WatchRouteKeeperTests`, `--filter WatchRouteTeeTests`, `--filter WatchRouteSourceTests`, `--filter WatchSensorSourceSourceTests`, `--filter WatchSessionEngineTests` (whole target + append-only guard; no new function names expected), `flutter test test/docs_indexing_contract_test.dart`. The app-target code (`HealthKitRouteRecorder`, `HealthKitWorkoutStore`) compiles only under xcodebuild: the lead builds it.

## Owner device checks

- (owner) ODC-1 A routine that starts with lifting and has an outdoor run: after finishing, Health > Workouts > the workout > Route exists; Fitness shows (or does not show) the map: tell me which.
- (owner) ODC-2 Lifting only: no route, no error.

## Progress
- [x] Phase 1

## Assumption Log
- Built by the LEAD, not the crew: the provider returned `429 Go usage limit exceeded` on two runs in a row (0 requests), so the change (about 30 lines + test rewrites) was made by hand, verified with the whole Swift package (1022 tests) and xcodebuild, and mutated (E1, E2 killed). Flagged to the owner.

## Feedback
