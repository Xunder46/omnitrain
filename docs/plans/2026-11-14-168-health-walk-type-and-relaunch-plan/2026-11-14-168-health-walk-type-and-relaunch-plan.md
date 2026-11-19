# Feature: a watch walk is saved to Apple Health as ONE walking workout across an app relaunch (plan 168)

> Status: Iteration 1 active (owner unavailable; defaults applied, marked below)
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md
> Sources: investigation `docs/plans/2026-11-14-166-walk-health-entry-investigation/2026-11-14-166-walk-health-entry-investigation.findings.md`; device log `docs/plans/2026-11-14-165-walk-duration-zero-investigation/2026-11-14-walk-device-log-excerpt.txt`. **The device log contradicts the investigation's "workout_adopted expected to be absent"**: adoption succeeded at the relaunch, and a second `HKWorkoutSession` began anyway one second later. This plan settles that.

## Overview

The owner's watch walk (session F138694B, 22:17:21–22:57:33 UTC, 40m12s) reached Apple Health as
ONE "Outdoor Run" of 0:15 — the 22:42:50–22:57:33 span. The relaunch log reads
`recovery_relaunch` (22:42:48) → `workout_adopted running` (22:42:49) → `workout_begin running`
(22:42:50) → second launch (22:43:00, no `recovery_relaunch`) → `workout_adopted running` →
exactly one `workout_end saving` (22:57:33).

The type is "Outdoor Run" because `WatchActivityTypes.forSession`
(`watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` l.188–190) asks the session's
**modality** first — `cardio_endurance` maps to `running` (`byModality`, l.63–66) — and never reaches
the exercises, whose Health kind the phone sent as `walking` for "Brisk Walk"
(`lib/core/utils/watch_reference_sync.dart` l.598–614; slot key written at
`lib/state/watch/watch_session_adoption_bridge.dart` l.589).

The 15 minutes happen because `recoverStrandedWorkout()` (`ios/OmniTrain Watch App/ContentView.swift`
l.386–388) runs **twice per relaunch**: the system's workout-recovery relaunch calls it
(`OmniTrainApp.swift` l.36–40) and `restore()` calls it first thing (l.359–361; the surface's
`.task { await host.restore() }` is at l.580–581). The first call adopts the stranded
`HKWorkoutSession` (`WatchPlatformWorkout.continueInProgress`, l.408–415: `adoptInProgress` returns
`"running"`, mapped through `byModality.values.first { $0.watchOs == name }`, so `running` is set
non-nil). The second call asks the same store again; the orphan has already been consumed, so
`adoptInProgress` answers nil, the coordinator falls through to
`WatchPlatformWorkout.recoverInProgress(saving: true)` (l.389–403) — which finds nothing, logs
nothing, but **unconditionally sets `running = nil` (l.402)** and clears `openedForSessionId` /
`adoptedBeforeRestore` (coordinator `recover`, l.554–568). The next apply — `restoreFinished` or a
`$revision` emission — then sees an active session, `running == nil`, a known type, and takes the
`.start` branch: `HealthKitWorkoutStore.begin` (l.115) opens a **new** `HKWorkoutSession` at
`Date()` = 22:42:50, and its replace rule `if session != nil { await end(saving: false) }` (l.123)
**silently discards the adopted builder** — the first 25 minutes. Nothing logs that discard, which
is why the log shows adopt → begin with no `workout_end`/`workout_recovered` between.

The second launch at 22:43:00 has no `recovery_relaunch` line, so only `restore()`'s recovery ran:
one adopt, no clobber, no `workout_begin`. Consistent.

**Why a Swift test reproduces it off-device.** `ScriptedPlatformStore`
(`watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutCoordinatorTests.swift` l.44–196) already
models HealthKit's consume-once recovery: `adoptInProgress` answers `state.adopt` once and then nil,
and a successful adopt removes the name from `stranded`. So: recover #1 adopts; recover #2 falls
through; `running` is cleared; the next `refresh(activeSession)` begins again. The whole failure is
coordinator + platform logic in the package; the app target contributes only the (correct, already
tested) consume-once shape and the silent discard inside `begin`. Confidence: **high** on the
mechanism — every step is in source and the log matches line for line (one `workout_adopted`, no
`workout_recovered`, a begin 1 s later, one entry, 0:15 = relaunch→End); **medium** on the exact
HealthKit behaviour behind the second `adoptInProgress` returning nil (a second
`recoverActiveWorkoutSession()` in the same process returns nil or throws — not callable on macOS;
the log's single `workout_adopted` is the evidence). Phase 1's red test pins the rule; the
on-device walk relaunch stays an owner check.

With Phase 1 fixed, the adopted builder survives to the user's End: one `HKWorkout`, the type
HealthKit fixed at its original open (22:17:21), and `end(saving: true)` finishes that builder —
one entry spanning start to end, **if** HealthKit preserves a recovered session's original dates
when `finishWorkout()` runs (owner device check; not callable off-device). With Phase 2, that type
is `walking` instead of `running`.

## Resolved Decisions (Ledger)

- **D-16801** Recovery is once per open workout. `WatchWorkoutCoordinator.recover(_:)`
  (`WatchPlatformWorkout.swift` l.554) returns immediately when `platform.running != nil`: this
  process already holds a live workout, so there is nothing of a previous process left to recover,
  and the relaunch's second entry path (`restore()` after the delegate) must not undo the first
  call's adoption. Rationale: the two launch paths are documented to share one path (plan 89 D-3);
  the bug is that the second call clobbers the first's state
  (`recoverInProgress` l.402 clears `running` even when it ended nothing). The guard keeps every
  existing recovery behaviour: adopt → hold; adopt refused → end saved/discarded; nothing found →
  no-op (S-1510's second call still adds no end — see S-16803).
- **D-16802** `WatchPlatformWorkout.recoverInProgress(saving:)` clears `running` only when it
  actually ended something (`ended` non-empty). A store that reports nothing stranded must not
  unregister a workout this process holds. Hardening behind D-16801 (any future second caller hits
  this instead of a silent unregister). Both fixes are package logic, testable with
  `ScriptedPlatformStore` on macOS.
- **D-16803** *(supersedes the precedence half of plan 75 D-2 — plan 75 D-2's mapping itself stays)*
  The Health workout type is resolved in this order by `WatchActivityTypes.forSession`
  (`WatchPlatformWorkout.swift` l.188–190; the Dart mirror
  `lib/watch/sensors/watch_platform_workout.dart` gains the same function):
  1. the **exercises' agreed Health kind**, when at least one exercise carries a
     `healthActivity` the table maps to a distinct type — `cycling`, `rowing`, `walking`, `hiking`,
     `running` (the kinds `distanceType`, l.149–156, maps; a majority of the named kinds, a tie
     going to the earliest named one — the existing `forExercises` rule applied to the named
     subset);
  2. otherwise the **modality** (`byModality`), unchanged;
  3. otherwise (no modality — a Free workout) the existing capability majority `forExercises`
     (l.171–186), unchanged;
  4. nil while nothing is known; the lifecycle waits (l.441), unchanged.
  The type is fixed once at `start` (HealthKit cannot retype an `HKWorkoutSession`); an exercise
  added later never retypes it (S-16808, today's S-8808 rule). "Brisk Walk" in a Cardio routine
  therefore records as Outdoor Walk; a treadmill run inside the same routine still records as a run
  (its kind is `running`); a cardio routine of squats (no named kind) keeps today's running.
  **Owner to confirm (reverses plan 75 D-2's "modality decides").**
- **D-16804** The store's save outcome is visible. `HealthKitWorkoutStore` gains the diagnostics log
  as an init parameter (`WatchDiagnosticsLog?`, the same trailing-optional shape plan 142 uses) and
  notes: `workout_saved <name>` / `workout_save_failed <name>` around `finishWorkout()` in
  `end(saving:)` (the empty `catch` at l.227–229 today swallows the failure), and
  `workout_end` detail `discarded_held <name>` when `begin`'s replace rule (l.123) ends a session
  the store already held — the statement that destroyed the first 25 minutes in this very walk.
  App-target only; pinned by source-scan tests.
- **D-16805** `begin` collects and shares `.distanceWalkingRunning` (one `enableCollection` beside
  l.139–141, and the type added to `resolveAuthorization`'s `toShare` set), so a walk/run Health
  agrees with exists. **Route on adopt (`openRoute` in `adoptInProgress`) is a follow-up, not this
  plan**: `openRoute(on:startedAt:)` needs the workout's real start, which a recovered
  `HKWorkoutSession` does not hand over (`Date()` would label the course from the relaunch), and the
  app target has no execution seam to verify it. Owner to confirm the deferral.
- **D-16806** Verification seam. Decision logic stays in the package (`swift test` on macOS); the
  app-target diff is the thinnest wiring (an init parameter, two `note` statements, one
  `enableCollection`, one `toShare` entry), each pinned by a source-scan test in
  `watch/watchos/Tests/WatchSessionEngineTests/` reading
  `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` through `Fixtures.repositoryRoot` (the
  pattern of `WatchWorkoutStoreSourceTests.storeSource()`). What stays an owner device check: the
  kill-and-relaunch walk itself, and the saved workout's span/heart-rate completeness for a
  recovered builder (below).

## Feature Invariants

- **One Health workout per wrist session.** A session that stays live across relaunches produces
  exactly one `HKWorkout`, opened at the session's first `workout_begin`, ended at the session's
  completed End. Adoption, not a second begin, is what carries a kill across a relaunch
  (plans 140/150 — this plan removes the last thing that undid it).
- **The two launch paths share one recovery, and a second recovery never undoes the first**
  (D-16801; plan 89 D-3's "the launch's restore() and the system's workout-recovery relaunch both
  run this one path" is preserved, made idempotent).
- **Implementation parity**: `WatchActivityTypes` and its Dart mirror resolve the same session to
  the same type (the contract pins the modality table on both sides,
  `WatchSensorRecordingTests.testS007EveryMappedModalityNamesBothPlatforms`; the new precedence is
  pinned on both sides by S-16804–S-16807 and S-16810).

## Requirements

1. A walk inside a Cardio-modality routine records as Outdoor Walk when the phone named
   `walking` for its exercise; modality stays the fallback (D-16803).
2. A relaunch into a live session adopts the stranded workout exactly once and never re-opens a
   second `HKWorkoutSession` for the same session (D-16801/D-16802); the adopted builder is
   finished (not discarded) when the user Ends the session.
3. A failed `finishWorkout()` and a held-session discard are visible in the diagnostics log
   (D-16804); Health collects walking/running distance (D-16805).
4. The Dart mirror types sessions the same way the wrist does (D-16803).

## Acceptance Criteria (each maps to ≥ 1 scenario)

| Criterion | Scenarios |
|---|---|
| Adopted workout survives the relaunch's second recovery | S-16801, S-16802, S-16803 |
| A named walk kind beats the Cardio modality; unnamed keeps the modality | S-16804, S-16806 |
| Disagreements resolve by majority, ties by earliest | S-16805 |
| Free-workout and can't-retype behaviour unchanged | S-16807, S-16808 |
| The mirror agrees with the wrist | S-16810 |
| Save outcome and held-discard are logged; distance collected | S-16809 |
| Owner device walk: ONE Health entry, type Outdoor Walk, 0:40 from the original start | owner check (Notes) |

## Existing-Functionality Impact

| Touched surface | Existing readers (grep) | Effect | Guarded by |
|---|---|---|---|
| `WatchActivityTypes.forSession` (`WatchPlatformWorkout.swift` l.188) | `WatchPlatformWorkout.start` l.359; `WatchWorkoutLifecycle.action` l.441; `WatchRoutineFocusTests` l.210, l.396 (grep `forSession` over `watch/watchos`) | New first tier (named kinds). All existing tests stay green: `S-12560`'s fixtures (`twoEfforts` = bench `["sets"]` + plank `["hold","time"]`, l.119–121) and the squats routine (l.387) name no Health kind → modality fallback unchanged; `WatchHealthActivityTests` calls `forExercises` directly (unchanged function) | S-16804–S-16807; `testS8809AModalityWinsOverTheExercises` stays green (its lift names nothing) |
| `WatchPlatformWorkout.recoverInProgress` (l.389) | `WatchWorkoutCoordinator.recover` l.566 (grep `recoverInProgress`); S-1503/S-1510/S-1507 | `running = nil` moves inside the ended-something case; `recover`'s guard skips it entirely when a workout is open | S-16802, S-16803; S-1503/S-1507/S-1510 unchanged (nothing open in their fixtures) |
| `WatchWorkoutCoordinator.recover` (l.554) | `recoverInProgress(storedSession:)` l.511 (delegate + `restore()` paths); plan 150's `WatchWorkoutAdoptBeforeRestoreTests` | New first-line guard; adoption paths unchanged | S-16801; S-15002–S-15006 unchanged |
| `HealthKitWorkoutStore.begin/end/adoptInProgress` (app target) | `WatchWorkoutStoreSourceTests` (name table, source scan); host wiring `ContentView.swift` l.~186–190 | Additive only: diagnostics param, notes, one collection type, one share type. The name table is untouched (S-1509 stays exact) | S-16809 |
| Dart mirror `start` (`lib/watch/sensors/watch_platform_workout.dart` l.178) | `test/watch_sensor_recording_test.dart` l.524–569, l.791 (modality table + generic); `WatchSessionDebugSurface` l.162 | `forModality(session.modality)` → `forSession(session)`; every existing Dart assertion names no Health kind (fixtures carry `capabilities` only) → unchanged | S-16810; existing S-007/S-005 groups |
| Docs claims | `docs/state_management/watch_sensors.md` l.353–377 (adopt/recover paragraph), l.141–146 (type rules), l.505–507 ("majority rule lives in Swift alone"); `docs/state_management/watch_diagnostics.md` l.28–33 (kinds) | Updated in the phases that change the behaviour | residue sweep (Phase 4 item 7) |

## UI Standards Impact

None. No surface, copy or shared UI piece changes; the summary screen's type/notice logic is
untouched.

## Scenarios

### S-16801: the relaunch's second recovery keeps the adopted workout
- Fixture: a `Harness` engine with an active session (modality `cardio_endurance`, the walk's
  shape); `ScriptedPlatformStore(inProgress: ["running"], adoptsInProgress: "running")` — the
  one-shot adopt mirrors HealthKit's consumed orphan (after the first adopt, `stranded` is empty
  and a second `adoptInProgress` answers nil).
- Trigger: `coordinator.recoverInProgress(storedSession:)` twice (the delegate's path, then
  `restore()`'s), then `coordinator.restoreFinished(session:)` and one more `refresh(session)` —
  the relaunch's actual call order.
- Flow: first recover adopts; second recover must not clear the registration; the applies see
  `running != nil`.
- Expected outcome: `store.adopted == 1`, `store.begun == []`, `store.ended == 0`,
  `platform.running?.watchOs == "running"` after every call.
- Edge case of: none (new rule; supersedes no scenario — S-15002/15003 keep passing).

### S-16802: recovery with nothing stranded leaves a held workout open
- Fixture: the store of S-16801 after its successful adopt (`stranded` empty, `running` set).
- Trigger: `platform.recoverInProgress(saving: true)` called directly (bypassing D-16801's guard —
  the hardening D-16802 must hold on its own).
- Flow: `inProgressActivityTypes` answers `[]`; nothing is ended.
- Expected outcome: `store.ended == 0`, `store.calls` gains only `inProgressActivityTypes`,
  `platform.running?.watchOs == "running"`.
- Edge case of: S-16801.

### S-16803: an honest second recovery after a fall-through adds no end
- Fixture: `Harness` engine whose stored session is **completed** (not active);
  `ScriptedPlatformStore(inProgress: ["running"])`, no adopt.
- Trigger: `coordinator.recoverInProgress(storedSession:)` twice.
- Flow: first recover — stillActive false → fall-through → the orphan is ended (`saving: false`,
  D-3); `running` nil → second recover runs (D-16801's guard passes) and must find nothing.
- Expected outcome: `store.ended == 1` after both calls; no second `end` in `store.calls`; no
  `begin`.
- Edge case of: S-1510 (no session at all) — this one pins the completed-session branch.

### S-16804: a named walking kind beats the Cardio modality
- Fixture: active session, modality `cardio_endurance`, one exercise slot
  `["time","distance"]` with `healthActivity: "walking"` (the Brisk Walk fixture: seed
  `exercise-brisk-walk`, discipline-walking → the phone sends `walking`).
- Trigger: `coordinator.refresh(session)` (and directly `forSession`).
- Expected outcome: `store.begun == ["walking"]` — today `["running"]`; the red test fails before
  Phase 2's fix.
- Edge case of: S-8809 (unnamed variant, which stays green).

### S-16805: named kinds disagree — majority, ties earliest
- Fixture: modality `cardio_endurance`; first `[walk(walking), run(running), run(running)]`
  (majority running), second `[walk(walking), run(running)]` (1–1 tie, earliest = walk).
- Trigger: `forSession` of each.
- Expected outcome: `running`, then `walking`.
- Edge case of: S-16804.

### S-16806: exercises that name nothing keep the modality
- Fixture: modality `cardio_endurance` + one lift slot `["reps","sets","load"]` (no
  `healthActivity`); modality `sports` + the same lift.
- Trigger: `forSession` of each.
- Expected outcome: `running`, then `other` — exactly today's answers (the modality fallback).
- Edge case of: S-8809 (unchanged behaviour, re-pinned at coordinator level).

### S-16807: a Free workout keeps its exercise answer
- Fixture: modality `nil`, exercises `[walk(walking)]`; and modality `nil`,
  `[run slot with no healthActivity]`.
- Trigger: `forSession` of each.
- Expected outcome: `walking`, then `running` (capability default) — unchanged from today, now
  pinned through the new precedence.
- Edge case of: S-8802/S-8807.

### S-16808: a later named kind never retypes the open workout
- Fixture: free session beginning on `walk(walking)` (type fixed at open), then a `run(running)`
  exercise inserted.
- Trigger: `refresh` after the insert.
- Expected outcome: `store.begun.count == 1`, `platform.running?.watchOs == "walking"` — HealthKit
  cannot retype an open `HKWorkoutSession`; the type stays what the first known answer fixed.
- Edge case of: S-8808 (same rule, named-kind fixture).

### S-16809: the store logs the save outcome, the held discard, and collects distance
- Fixture: the app target's source text, read by a source-scan test
  (`WatchWorkoutStoreSourceTests.storeSource()` pattern — the target has no test target and
  `HKWorkoutActivityType` does not exist on macOS).
- Trigger: the new source-scan tests assert, inside `end(saving:)`'s saving branch, the
  `workout_saved`/`workout_save_failed` notes; inside `begin`'s replace branch, the
  `workout_end` `discarded_held` note; in `begin`'s collection block, `enableCollection` for
  `.distanceWalkingRunning`; in `resolveAuthorization`, the type in the share set; and in
  `WatchAppHost.init`, the store built with `diagnostics:`.
- Expected outcome: all present, each inside the right function's braces.
- Edge case of: none (new diagnostics; S-1509's name table untouched).

### S-16810: the Dart mirror answers what the wrist answers
- Fixture: the same three session shapes as S-16804, S-16806 and S-16807, built as Dart
  `WatchSessionRecord`s (exercises are maps with `capabilities`/`healthActivity`, the shape
  `watch_session_adoption_bridge.dart` l.589 writes).
- Trigger: `WatchActivityTypes.forSession` and `WatchPlatformWorkout.start` over
  `_FakePlatformStore` (`test/watch_sensor_recording_test.dart` l.107).
- Expected outcome: `walking` / `running`+`other` / `walking`+`running` — identical to the Swift
  answers.
- Edge case of: S-16804/S-16806/S-16807 (mirror side).

## Iteration 1

### Phase 1: the relaunch's second recovery no longer clobbers the adoption (@developer)
1. [ ] Red test S-16801 — `watch/watchos/Tests/WatchSessionEngineTests/WatchRelaunchRecoveryTests.swift` · `testS16801TheSecondRecoveryKeepsTheAdoptedWorkout` (new file; reuse `ScriptedPlatformStore` from `WatchWorkoutCoordinatorTests.swift` and the `adopted()` setup shape from `WatchWorkoutAdoptBeforeRestoreTests.swift`)
2. [ ] Red test S-16802 — same file · `testS16802RecoveryWithNothingStrandedLeavesAHeldWorkoutOpen`
3. [ ] Red test S-16803 — same file · `testS16803ASecondRecoveryAfterAFallThroughAddsNoEnd` (must pass BEFORE the fixes and stay green after — it guards the over-fix)
4. [ ] Fix D-16801 — `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` · `WatchWorkoutCoordinator.recover(_:)` (l.554): first statement `guard platform.running == nil else { return }`, comment naming S-16801 and the double launch path
5. [ ] Fix D-16802 — same file · `WatchPlatformWorkout.recoverInProgress(saving:)` (l.389–403): set `running = nil` only when `ended` is non-empty
6. [ ] Green: S-16801–S-16803 pass, and the full suite stays green — S-1503, S-1507, S-1510, S-15002–S-15006, S-14001–S-14005 are the neighbours to watch
7. [ ] Docs — `docs/state_management/watch_sensors.md` (40.2 KB, under the 52 KB band) · the "The workout is continued when it can be, recovered when it cannot." paragraph (l.353–377): add the once-per-open rule and cite `WatchRelaunchRecoveryTests`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (full,
900 s) — pass count up by 3, zero regressions; outside the gateway the focused filters are
`swift test --package-path watch/watchos --filter WatchRelaunchRecoveryTests` and
`--filter WatchWorkoutCoordinatorTests` / `--filter WatchWorkoutAdoptBeforeRestoreTests`;
`git-diff` shows only the two predicted files.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchRelaunchRecoveryTests.swift` (new),
`docs/state_management/watch_sensors.md`.

### Phase 2: the exercises' agreed Health kind wins when they name one (@developer)
1. [ ] Helper D-16803 — `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` · new `WatchActivityTypes.forNamedHealthKinds(_:)` (private): the `healthActivity` values of `session.exercises` that `distanceType(_:)` (l.149–156) maps distinctly (`cycling`, `rowing`, `walking`, `hiking`, `running`), majority with earliest tiebreak (the `forExercises` l.171–186 counting), nil when no exercise names one
2. [ ] Precedence — same file · `forSession(_:)` (l.188–190) becomes: named kinds → modality → (no modality) existing `forExercises`; update the doc comment to state the supersession of plan 75 D-2's precedence half
3. [ ] Tests S-16804, S-16805 — `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutTypeFromExercisesTests.swift` · `testS16804AWalkNamedByTheExerciseBeatsTheCardioModality`, `testS16805TheNamedKindsMajorityAndItsTie` (add a `walk(_:)`/`namedRun(_:)` slot helper carrying `"healthActivity"` beside the existing `slot`/`run` fixtures)
4. [ ] Tests S-16806, S-16807, S-16808 — same file · `testS16806UnnamedExercisesKeepTheModality`, `testS16807AFreeWorkoutKeepsItsExerciseAnswer`, `testS16808ALaterNamedKindNeverRetypesTheOpenWorkout`
5. [ ] Neighbours stay green: `testS8809AModalityWinsOverTheExercises`, `WatchRoutineFocusTests` S-12560 + the squats case (l.396), `WatchHealthActivityTests` (calls `forExercises`, untouched)
6. [ ] Docs — `docs/state_management/watch_sensors.md` · the type-rules paragraph (l.141–146) and the "lives in Swift alone" sentence (l.505–507, which Phase 3 finishes)

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (full) — up by 5, zero
regressions; focused filters `--filter WatchWorkoutTypeFromExercisesTests`,
`--filter WatchRoutineFocusTests`, `--filter WatchHealthActivityTests`; `git-diff` shows only the
predicted files.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutTypeFromExercisesTests.swift`,
`docs/state_management/watch_sensors.md`.

Phase 2 depends on nothing in Phase 1 (different function); the phases may run in either order.
Running Phase 2 first gives the visible type win sooner; running Phase 1 first removes the data
loss first.

### Phase 3: the Dart mirror moves with the rule (@developer)
1. [ ] Mirror D-16803 — `lib/watch/sensors/watch_platform_workout.dart` · `WatchActivityTypes` gains `forExercise({required List<String> capabilities, String? healthActivity})`, the named-kind subset helper and `forExercises(List<Map<String, Object?>>)`/`forSession(WatchSessionRecord)` with the same four-tier precedence (the file's header comment "The activity type comes from the modality" updated)
2. [ ] Caller — same file · `WatchPlatformWorkout.start` (l.178): `WatchActivityTypes.forSession(session) ?? generic` replaces `forModality(session.modality)`; `forModality` itself stays (its other readers are untouched)
3. [ ] Test S-16810 — `test/watch_sensor_recording_test.dart` · new group `S-16810 the mirror types a session like the wrist`: named walk + cardio modality → `walking`; unnamed lift + cardio → `running`; sports + lift → `other`; free + walk → `walking`; free + capability-only run → `running` (uses the existing `_FakePlatformStore`, l.107)
4. [ ] Docs — `docs/state_management/watch_sensors.md` · finish the l.505–507 sentence: the precedence now lives on both clients, pinned by `WatchWorkoutTypeFromExercisesTests` and the new Dart group

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test` (full `flutter test`, 900 s) —
up by 5, zero regressions; `.github/copilot/scripts/macos/gateway.sh lint` compared against the
repo's pre-existing notice count (no new issues); focused run outside the gateway
`flutter test test/watch_sensor_recording_test.dart`.
**Predicted Files**: `lib/watch/sensors/watch_platform_workout.dart`,
`test/watch_sensor_recording_test.dart`, `docs/state_management/watch_sensors.md`.

Phase 3 needs Phase 2's rule shape (it mirrors it); it does not need Phase 1.

### Phase 4: the store's outcome is visible, and Health gets its distance (@developer)
1. [ ] Diagnostics param D-16804 — `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` · `init(location:diagnostics:)` gains `diagnostics: WatchDiagnosticsLog?` (package type), stored
2. [ ] Outcome notes — same file · `end(saving: Bool)` (l.195): in the saving branch around `finishWorkout()` (l.226–228), note `workout_saved <name>` / `workout_save_failed <name>` (`Self.name(for: openSession.workoutConfiguration.activityType)`); the empty `catch` stops being silent
3. [ ] Held-discard note — same file · `begin(_:outdoors:)` (l.115): when the replace rule fires (`session != nil`, l.123), note `workout_end` detail `discarded_held <name>` before `await end(saving: false)`
4. [ ] Distance D-16805 — same file · `begin` adds `dataSource.enableCollection(for: HKQuantityType(.distanceWalkingRunning), predicate: nil)` beside l.139–141, and `resolveAuthorization`'s `toShare` set gains `HKQuantityType(.distanceWalkingRunning)`
5. [ ] Wiring — `ios/OmniTrain Watch App/ContentView.swift` · `WatchAppHost.init`: build the store as `HealthKitWorkoutStore(location: WatchTrackedLocation(source: CoreLocationRawSource()), diagnostics: diagnostics)` (the local `diagnostics` exists above that line)
6. [ ] Source-scan guard S-16809 — `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutStoreSourceTests.swift` · `testS16809TheStoreNotesTheSaveOutcomeAndTheHeldDiscard`, `testS16809TheStoreCollectsAndSharesDistance` (read `storeSource()`, assert each statement inside the right function's brace window; follow the file's window-scanning style)
7. [ ] Docs + residue sweep — `docs/state_management/watch_diagnostics.md` · "What is recorded" kinds list (l.28–33) gains the three note shapes; `docs/state_management/watch_sensors.md` · the collection sentence (l.155 region) gains distance; then the sweep: grep `docs/state_management/` and `lib/` + `watch/watchos/Sources` for stale "modality decides"/modality-first claims and `forSession` definitions — only the plan-75 historical plan may still carry the old wording

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (full — the source-scan
tests run here) and `.github/copilot/scripts/macos/gateway.sh lint`; `git-diff --name-only` shows
only the predicted files.
**Predicted Files**: `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`,
`ios/OmniTrain Watch App/ContentView.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutStoreSourceTests.swift`,
`docs/state_management/watch_diagnostics.md`, `docs/state_management/watch_sensors.md`.

## Files Affected (whole feature)

- `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` — Phases 1, 2
- `watch/watchos/Tests/WatchSessionEngineTests/WatchRelaunchRecoveryTests.swift` — new, Phase 1
- `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutTypeFromExercisesTests.swift` — Phase 2
- `lib/watch/sensors/watch_platform_workout.dart` — Phase 3
- `test/watch_sensor_recording_test.dart` — Phase 3
- `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`, `ios/OmniTrain Watch App/ContentView.swift` — Phase 4 (read-only dependencies of Phases 1–3: no)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutStoreSourceTests.swift` — Phase 4
- `docs/state_management/watch_sensors.md` — Phases 1, 2, 3, 4; `docs/state_management/watch_diagnostics.md` — Phase 4

## Notes

- **Phase graph**: 1 and 2 independent of each other; 3 needs 2; 4 independent of 1–3 (its store
  changes compile against today's package; the source-scan tests read text, not symbols). If the
  owner rejects D-16803, drop Phase 2 and rewrite Phase 3's item 1 to keep `forModality` as the
  caller — Phase 1 and Phase 4 stand alone.
- **Owner device checks** (the only parts no desktop run can reach): (a) the kill-and-relaunch
  walk — one Health entry, type Outdoor Walk, duration from 22:17:21 to End, one `workout_adopted`
  and no `workout_begin` after it in the log; (b) whether a recovered builder's `finishWorkout()`
  preserves the original start date in the saved `HKWorkout` (HealthKit's own arithmetic, not
  ours); (c) whether heart-rate collection survives the recovery (adopt re-enables only stepCount
  and activeEnergy at l.298–299 — the pre-kill beats are in the builder, the post-adopt ones may
  not be; if Fitness shows a heart-rate gap after the relaunch, that is the follow-up, not a
  regression of this plan).
- **Follow-ups listed, not planned here** (D-16805): `openRoute` on adopt; heart-rate re-enable on
  adopt; the investigation's remaining unknowns (where 1.61 mi came from; the Android/wear side of
  `byModality`).
- **Intermediate states**: after Phase 1 alone, the walk produces ONE entry, type still Outdoor
  Run (the modality rule), full duration if (b) holds. After Phase 2 alone, a fresh walk is typed
  Outdoor Walk but a relaunch still splits it. Neither intermediate state is a regression.
- No scratch files; no deletions or directory creation needed (the plan folder exists).

## Progress

- [x] Phase 1 — **Complete**. `recover(_:)` returns early when a workout is already running and
  `recoverInProgress` clears `running` only once it has ended something; 3 new tests, suite total
  1446/0.
- [x] Phase 2 — **Complete**. `forSession` is named Health kind → modality → exercise capability →
  nil; 5 new tests, `WatchWorkoutTypeFromExercisesTests` 16/16.
- [x] Phase 3 — **Complete**. The Dart mirror carries the same four tiers and `start` asks it;
  `test/watch_sensor_recording_test.dart` 41/41.
- [x] Phase 4 — **Complete**. Save outcome, held discard and `.distanceWalkingRunning` are in the
  store and wired; 2 source-scan tests, full `swift-test` 1446/0.

## Assumption Log

- **Fixtures use a fresh engine and store per case.** A `WatchSessionEngine` holds one live session
  (a second `createSession` returns the existing one), so a shared engine silently rewrote the
  scenario's fixture; each test now builds its own.
- **`HealthKitWorkoutStore` kept `init(location:)`.** `WatchSensorSourceSourceTests.testS3312`
  asserts that exact initializer text, and Phase 4's unpredicted red would have forced editing it.
  Instead `init(location:diagnostics:)` is the designated initializer and a `convenience
  init(location:)` forwards `nil`. Neighbour green, test untouched.
- **Phase 3's guard was proved by mutation, not `prove-red`.** The changed line already existed
  (`start`'s `forModality` call), so the proof is: original line recorded, call swapped to
  `forModality(session.modality)`, focused file RED, exact original restored, 41/41 green.
  Recorded in the evidence file.
- **The full Dart suite is red in another plan's files.** `watch_session_import_test.dart` (S-16703,
  16704, 16705), `watch_session_adoption_bridge_test.dart` (S-16706) and a compile error in
  `watch_convergence_harness_test.dart` (`_plan167Tests` missing) are in-flight plan-167 work; none
  imports `watch_platform_workout.dart`. Left alone and reported, not absorbed.
- **No lint baseline is recorded in this plan.** `gateway.sh lint` reports 183 pre-existing notices
  and none in the two Dart files this plan touches; that count is the comparison point.
- **No thread-sanitizer check exists.** `gateway.sh list` has no such check, so the brief's form
  could not be run; `swift-test` is the whole Swift gate.

## Feedback

[empty]
