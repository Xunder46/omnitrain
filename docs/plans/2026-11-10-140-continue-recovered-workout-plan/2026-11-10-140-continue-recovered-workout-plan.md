# Plan — 140: a workout the watch app left running is continued after a relaunch

**Status**: built by the crew 2026-11-10, verified by the lead (Swift 1304 passed, watch app `xcodebuild` BUILD SUCCEEDED); uncommitted. Owner device check: QA step 37.
**Base commit**: `b78112ef` (branch `claude_develop`).
**Parent plan**: plan 89 (the launch recovery ended the stranded workout, saved when the session was still active, then opened a new one).

## Overview

Owner (2026-11-10, real device): the watch app was killed and relaunched mid-session. Apple Fitness showed TWO workouts (12 min with 28 kcal, 20 min with 54 kcal) for one session, the Health energy counter restarted, and the phone's live calories jumped (5, 1, 25, 47). The relaunch ended the interrupted workout (saved, because the session was still active) and opened a new one.

What the user sees after this plan: the relaunched app takes over the workout Health still has running, so one session is one Fitness workout and its totals include the time the app was gone. When the workout cannot be continued (not live, or the store cannot adopt it) the old behaviour stays.

## Goal and acceptance

Acceptance: S-14001 .. S-14005 (package tests) plus the app-target source guards; the app target compiles (`xcodebuild`).

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-14001 | `WatchPlatformWorkoutStore` gains `adoptInProgress() async -> String?` (default nil in the protocol extension): the `watchOs` name of a workout a previous process left RUNNING that the store took over, else nil | `WatchPlatformWorkout.swift` |
| D-14002 | `WatchPlatformWorkout.continueInProgress()` calls it and sets `running` (an unknown name registers as the generic type); `WatchWorkoutCoordinator.recover` continues when the persisted session is still active and falls back to ending as before otherwise | `WatchPlatformWorkout.swift` `recover` |
| D-14003 | `HealthKitWorkoutStore.adoptInProgress()` recovers the session, keeps it and its builder, points the sensor feed at it again (`delegate`, step and energy collection, heart-rate read) and answers its type when the state is running or paused; any other state is held for the ordinary recovery (`pendingRecoveryName`) | `HealthKitWorkoutStore.swift` |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-14001 | stored session active, store adopts | no `end`, no second `begin`, `running` set | the launch recovery always ended it |
| S-14002 | stored session active, store does not adopt | `end(saving: true)` as before | n/a: guard of the fallback |
| S-14003 | stored session not active | adoption never asked, stranded workout discarded | n/a: guard |
| S-14004 | after an adopted recovery the session completes | the workout ends once, saved | n/a: guard |
| S-14005 | after an adopted recovery another session id goes active | the adopted workout is discarded and the new one begins | n/a: guard |

## Phases

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 | crew-builder-watch | `WatchPlatformWorkout.swift`, `HealthKitWorkoutStore.swift`, watch tests | with plan 141 P1 (disjoint) |

## Progress

| Item | Status |
|---|---|
| P1 built, Swift 1304 passed, xcodebuild succeeded | Done |
| docs | Done (lead) |
| device check QA step 37 | Open (owner) |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | The HealthKit calls (`recoverActiveWorkoutSession`, `associatedWorkoutBuilder`, `dataSource?.enableCollection`) behave as Apple documents for a recovered session; only a device settles it | simulator has no workout recovery |
| A-2 | An adopted type unknown to `byModality` registers as the generic type in the package; Health keeps the real type | the store answers Health's own name |
| A-3 | The architect phase is skipped and no independent review was run for this small unit; the lead read the diff and ran the suites | cost discipline |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_sensors.md | MODIFIED | `**The workout is recovered, not resumed.**` | `adoptInProgress` | S-14001 |
| docs/rest_tracking.md | MODIFIED | `a recovered workout the Health counter restarts, so the on-screen line restarts` | `a workout the watch continues after a relaunch (plan 140) the Health counter` | S-14001 |
