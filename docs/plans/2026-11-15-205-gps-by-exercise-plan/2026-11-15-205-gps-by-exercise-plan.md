# Feature: 205 — GPS and the Health "outdoor" flag follow the exercise, not the modality

> Status: SEEDED by the governor 2026-11-15; APPROVED by the owner 2026-11-15 ("only the distance capability should decide GPS"; the Sports and stationary-bike consequences stand; a per-exercise GPS marker is a later idea). Architect step skipped (A-1).
> Next handoff: crew-builder-watch
> Binding conventions: `docs/global_conventions.md`, `docs/state_management/watch_sensors.md`, `watch/contract/watch_sensor_contract.json`, `.github/copilot/pr-scope-budget.md`
> Related plans: 4800-series (GPS by exercise, D-4800), 12561/12571 (Focus stamps GPS), 170 (Health kind by discipline), 201-204 (this round)
> Track: watch client (Swift engine, Dart twin, one contract file). No wire change, no phone change.

## Goal and acceptance

Independent review, 2026-11-15: "Every Cardio and Sports workout turns GPS on, whatever the exercise. Boxing or a stationary bike asks for location, marks the Health workout as outdoor and spends battery." Owner decision, 2026-11-15: **the exercise decides, not the modality**; an indoor flag on exercises comes later.

Today `WatchGpsPolicy.isRequired(session)` is true when the session's modality can cover distance (Cardio, Sports) OR the current exercise has the `distance` capability. After this change only the second half remains: GPS (the Location permission, the fix subscription, the outdoor Health workout) is on exactly when the exercise the user is on has the `distance` capability.

What the owner sees:
- Boxing (a Sports discipline, no `distance`), any Sports exercise (no seeded Sports exercise has `distance`), jump rope and stair climber (Cardio, no `distance`): no location prompt, no GPS line, Health records an indoor workout, less battery.
- Running, walking, cycling, rowing, swimming: unchanged (they carry `distance`).
- **Accepted, owner to confirm:** stationary bike, treadmill, elliptical, rower and assault bike carry `distance` too, so they stay GPS and outdoor until an indoor flag exists (a later plan). And because no seeded Sports exercise carries `distance`, **no Sports workout uses GPS any more, soccer included** (today every Sports workout does). A Cardio-Focus routine made only of strength exercises (squats) no longer asks for location either (plan 12571's "documented consequence" ends); its Health type is unchanged (Running, plan 170).

Acceptance: the scenarios below fail on the old code; `swift test` whole target, the two Dart watch-sensor test files and the full suite green with observed counts; the watch target builds (lead).

## Decision Ledger

| ID | Decision | Where |
|---|---|---|
| D-20501 | `WatchGpsPolicy.isRequired(_ session:)` becomes `coversDistance(current exercise's capabilities)`; the modality arm is deleted. `isRequired(_ modality:)` and `capabilitiesByModality` have no production caller outside it and are deleted with their pins. `distanceCapability` and `coversDistance` stay (used by `forExercise` and the "No distance" notice). | `WatchPlatformWorkout.swift` (~266-309) |
| D-20502 | The Health workout's outdoor flag is still fixed once, at begin, by the first exercise (`WatchPlatformWorkout.start` ~424; `outdoors` never changes mid-session, `watch_sensors.md:120-130`). A later distance exercise still starts location late (`startLocationIfNeeded`), as for a free workout today. Start paths: a modality-button start, a routine start and an adopted phone session already hold their exercise(s) when the workout begins (scout sheet 5, Q2), so the first exercise decides for all of them. | unchanged callers |
| D-20503 | **Contract:** `watch/contract/watch_sensor_contract.json` loses `gpsModalities` (the derived list of GPS modalities) and `modalityCapabilities` (the capability profile only the deleted modality rule read); `gpsCapability` and the `exerciseGpsCases` list stay. | `watch_sensor_contract.json:12`, readers `WatchSensorRecordingTests.swift`, `test/watch_sensor_recording_test.dart` |
| D-20504 | **Dart twin parity:** `WatchSensorRecording.start(session)` decides by the current exercise's capabilities through `WatchGpsPolicy.coversDistance`; `WatchGpsPolicy.isRequired(String? modality)` is deleted. The twin is a developer harness: it decides once, at `start`, by the exercise the session is on (it has no `sessionChanged` late start, so a Free session with no exercise yet never starts GPS in the twin: known harness limit, not changed). | `lib/watch/sensors/watch_sensor_recording.dart:133`, `watch_platform_workout.dart:342-355` |
| D-20505 | **Not changed:** the Health workout TYPE (`WatchActivityTypes.forSession`: healthActivity, then modality, then exercise majority), the "No distance, Location access is off" notice (already exercise-based), the phone, the wire. | — |

## Input-reality checklist (answered)

1. **Writers.** An exercise's `capabilities` come from the phone's catalog (`exercises_down`, routine slots, session slots); the `distance` capability is written by the seed and by the exercise editor. A custom exercise without it never asks for GPS. No stored value is added.
2. **Lifecycle.** A session already running when the watch app updates keeps its already-begun workout; a relaunch mid-session recovers by the existing path (`recovery_relaunch`), which re-reads the exercise. A routine with no exercise yet (empty held session) decides when the first exercise lands.
3. **Settings.** Location permission denied: the existing notice shows only while the current exercise covers distance (unchanged).
4. **Time.** None.
5. **Cost.** One capability list read per refresh (already done for the exercise half).
6. **Words.** Docs and the QA doc state the modality rule: the Docs delta rows. No on-screen string changes.
7. **Competition.** Modality vs exercise: the exercise now always decides; a Cardio exercise with `distance` after a no-distance one starts location late (S-20507).

## Feature invariants

- GPS is on if and only if the current exercise has `distance` (D-20501, S-20501..S-20506).
- The outdoor flag is fixed at begin (D-20502, S-20506).
- The Health type does not change (D-20505, S-20504).

## Existing-functionality impact

| Touched surface | What reads it (scout sheet 5, Q4/Q5) | Effect | Guarded by |
|---|---|---|---|
| `isRequired(_ modality:)` pins | Swift: `WatchSensorRecordingTests.swift:531-568` (3 tests), `WatchOutdoorWorkoutTests.swift:60-96` `testS3300OutdoorsFollowsTheCapabilityProfile` (sessions with a modality and NO exercise expect Cardio/Sports `true`), `WatchRoutineFocusTests.swift:399` `testS12571…` ("documented consequence: GPS asked"); Dart: `test/watch_sensor_recording_test.dart:584-661` (group S-008), `test/watch_routine_focus_start_test.dart:387-392` and `:554`, `test/watch_snapshot_focus_wrist_test.dart:377-382` | Rewritten to the exercise rule (modality-only expectations become `false`; the "no exercise yet" case stays `false`) | S-20501..S-20509 |
| `WatchGpsByExerciseTests` | pins the exercise rule (S-4807, S-4809, S-4812, S-4813, S-4806, S-4800) | Stay green; `S-4806 a distance modality starts with no exercise at all` (`:464-477`) is rewritten (a modality alone no longer starts GPS) | S-20501 |
| `watch_sensor_contract.json` | `gpsModalities` read by the two S-008 contract tests | Key removed; tests rewritten | S-20508 |
| Docs | `watch_sensors.md:31, 36, 218-223, 490-493`, `my_routines.md:505`, `distance_source.md:176-181`, `watch-app-qa-wrist-logging.md:473-477, 495-496` | Docs delta | S-20501.. |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-20501 | A session with modality `sports` and the Boxing exercise `["time","rounds"]`; `WatchGpsPolicy.isRequired(session)` and `WatchPlatformWorkout.start` | `false`, `store.begin(..., outdoors: false)` | the modality alone returns true |
| S-20502 | Modality `cardio_endurance`, exercise Brisk Walk `["time","distance"]` | `true`, `outdoors: true` | passes today — pin |
| S-20503 | Modality `cardio_endurance`, exercise Stationary Bike `["time","distance"]` | `true` (accepted consequence, pinned so a later indoor flag changes it knowingly) | passes today — pin |
| S-20504 | Cardio-Focus routine of one squat `["reps","sets","load"]` (the S-12571 fixture) | `isRequired == false`; the Health type is still Running | `true` today |
| S-20505 | Modality `sports`, exercise Soccer `["time","rounds"]` | `false` | `true` today |
| S-20506 | Free workout (modality nil): before the first pick `false`; after picking a run `true`; the outdoor flag taken at begin never changes after a later pick of a lift | as today | passes today — pins D-20502 |
| S-20507 | Cardio session on jump rope `["time"]`, then the user moves to Running `["time","distance"]` | location starts at the move (`startLocationIfNeeded`), `outdoors` stays `false` | n/a — pins the late start with no modality help |
| S-20508 | `watch_sensor_contract.json` has no `gpsModalities` key; the contract `exerciseCases` still decide `coversDistance` on both stacks | as stated | the key exists |
| S-20509 | Dart twin: `WatchSensorRecording.start` over a cardio session on jump rope does not request location permission; over a run it does | as stated | the twin reads the modality |

## Phases

**P1 — Swift and the contract (owner: crew-builder-watch; scope `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift`, `WatchOutdoorWorkoutTests.swift`, `WatchRoutineFocusTests.swift`, `WatchGpsByExerciseTests.swift`, `watch/contract/watch_sensor_contract.json`, report).** Items: D-20501, D-20503; rewrite the listed pins; add S-20501..S-20508 (one new test file if the pins do not fit). Runs `swift-test --filter` on each class and the whole target.

**P2 — Dart twin (owner: crew-builder-watch; scope `lib/watch/sensors/watch_sensor_recording.dart`, `lib/watch/sensors/watch_platform_workout.dart`, `test/watch_sensor_recording_test.dart`, `test/watch_routine_focus_start_test.dart`, `test/watch_snapshot_focus_wrist_test.dart`, report; parallel with P1: Flutter vs Swift).** Items: D-20504; rewrite the pins; S-20509.

**P3 — docs (owner: crew-docs-keeper).** Execute the Docs delta; the keeper's brief lists renamed tests (playbook rule (bv)).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_sensors.md | MODIFIED | `to a distance modality (Cardio, Sports) turns GPS on at its start, before any` | `itself: the exercise the user is on decides, so a routine whose Focus is` | S-20501, S-20504 |
| docs/state_management/watch_sensors.md | MODIFIED | `- **GPS activation derives from the modality's capability profile and the current` | `- **GPS activation derives from the current exercise's capabilities, never from` | S-20501, S-20505 |
| docs/state_management/watch_sensors.md | MODIFIED | `reading the modality's capability profile and the current exercise's capabilities` | `reading the current exercise's capabilities` | S-20501 |
| docs/my_routines.md | MODIFIED | `a Cardio-focus routine of strength exercises registers as Running with GPS on` | `a Cardio-focus routine of strength exercises registers as Running with no GPS` | S-20504 |
| docs/distance_source.md | MODIFIED | `through the tracker when the session's modality or the exercise the user is` | `through the tracker when the exercise the user is on is allowed to use Location` | S-20502, S-20501 |
| docs/watch-app-qa-wrist-logging.md | MODIFIED | `Cardio Focus makes the watch ask for location, say "Intervals" and register` | `Health and Free Training on the calendar; a Cardio Focus of squats asks for` | S-20504 |
| docs/watch-app-qa-wrist-logging.md | MODIFIED | `"Periods" and asks for location only if you never answered; Health shows` | `"Periods" and asks for no location (no Sports exercise carries distance); Health shows` | S-20505 |
| docs/watch-app-qa-wrist-logging.md | ADDED | - | `**GPS follows the exercise — (owner, plan 205).**` | S-20501 |

(The architect/keeper copies each Old marker from the doc this run and re-checks the sweep: `grep -rIn "GPS" docs | grep -i "modality"` excluding plans/history/releases; `distance_source.md:176-181` and the QA doc's old Focus/Sports lines at `:473-477` and `:495-496` are read and either get a row or are reported as stale claims.)

## Progress

- [x] Seeded by the governor 2026-11-15 (scout sheet 5 read).
- [x] P1 Swift and contract
- [x] P2 Dart twin
- [x] P3 docs
- [x] Prove, review, report

## Assumption Log

| # | Assumption | Source | Status |
|---|---|---|---|
| A-1 | The architect step is skipped: the seed names files, symbols and fixtures. | lead | open |
| A-2 | **Owner to confirm:** no Sports workout uses GPS after this (no seeded Sports exercise has `distance`), and stationary bike / treadmill stay GPS until an indoor flag exists. | scout sheet 5 Q6 | open |
