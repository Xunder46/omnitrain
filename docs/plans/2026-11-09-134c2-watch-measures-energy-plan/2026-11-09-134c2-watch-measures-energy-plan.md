# Plan — 134c2: the watch measures the session's active energy and sends it on the session end

**Status**: built, reviewed and verified 2026-11-09; uncommitted. Real numbers need a real watch (owner device check, QA step 35). Evidence: `docs/plans/2026-11-09-134e-wrist-rest-calories-plan/2026-11-09-134e-wrist-rest-calories-plan.evidence.md` (one file for 134b to 134e).
**Binding conventions**: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`.
**Base commit**: `ff398e1a7ec18409d9fc8c890bf35d2fde656e69` (branch `claude_develop`; uncommitted 134a, 134b, 134c1, 134d are in the tree).
**Pattern followed**: the steps sensor (plan 19d: `WatchSensorKind.steps`, `WatchSensorSource.steps()`, `WatchSensorSummaries.steps`, `HealthKitSensorFeed.steps()`).
**Parent plan**: `docs/plans/2026-11-08-134-calories-burned-plan/2026-11-08-134-calories-burned-plan.md`.

## Overview

Owner decision 1 (2026-11-08): the watch's measured active energy always wins and is pushed to the phone. The watch already collects it (`HealthKitWorkoutStore.begin` enables `HKQuantityType(.activeEnergyBurned)` on the data source and asks Health for it) but nothing reads it back. This unit reads the builder's cumulative energy total into the wrist's own sample store, the way steps are read, and puts the session's total on the `session_end` as `activeEnergyKcal` (plan 134c1 made the phone accept and store it).

What the user sees: after a session the watch ran or followed, the phone's Session Summary shows its Calories pill without `~` (the watch's number), and the phone never estimates it. A session with no watch, or with Health refused, stays on the `~` estimate. Real numbers appear only on a real watch.

## Goal and acceptance

The wrist stores energy samples and sends one total per session. Acceptance: S-13470 .. S-13476.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13470 | New sample kind `WatchSensorKind.activeEnergy = "energy"`: the platform workout's active energy since it began, in kilocalories, cumulative (each sample supersedes the one before; a smaller value than its predecessor means the counter restarted). Added to Swift `WatchRecords.swift` (`:138-156`, `all` list), the Dart twin `lib/watch/session/watch_records.dart` (`:117-136`, vocabulary only, like `steps`) and `watch/contract/watch_sensor_contract.json` (`kinds` gains `"energy"`; `sampleUnits` gains `"energy": "cumulativeKilocalories"`; one sentence in `description`) | scout WIRE Q4; the contract is asserted by `WatchSensorRecordingTests.swift:574-575` and `test/watch_sensor_recording_test.dart:659-661` (both compare `WatchSensorKind.all` with the contract's `kinds`) |
| D-13471 | `WatchSensorSource` gains `func activeEnergyPermission() async -> WatchSensorPermission` and `func activeEnergy() -> AsyncStream<Double>`, with default implementations in a `public extension WatchSensorSource` (`.unavailable`; a stream that finishes at once) so every existing fake source keeps compiling. `WatchSensorRecorder.start` calls a new `startActiveEnergy()` (permission `== .granted`, then `consume(source.activeEnergy())` recording `WatchSensorKind.activeEnergy`), holds `energyTask`, and `stop()` cancels it. Energy feeds no readout in this unit (134e adds it) | `WatchSensorRecording.swift:52-66, 104-107, 150-153, 189-262` |
| D-13472 | `WatchSensorSummaries.activeEnergy(_ samples: [WatchSensorSampleRecord], from start: Date, through end: Date) -> Double?`: the same cumulative chain as `steps` (`:126-157`) over `WatchSensorKind.activeEnergy` samples (finite, `>= 0`): the chain starts at the last count before the window (or zero), adds each step forward, a smaller value than its predecessor is a restart (the new value is itself the energy since the restart). Returns nil when no sample lies inside the window, and nil when the total rounds to zero (a zero total is never sent); otherwise the total rounded to one decimal (`(total * 10).rounded() / 10`) | `WatchSensorSummaries.swift:126-157` |
| D-13473 | `WatchSessionEngine.sessionEndEvent` (`:1692-1743`) adds `event["activeEnergyKcal"] = kcal` right after the whole-session heart-rate merge, when `activeEnergy(samples, from: startedAt, through: end)` is non-nil; for a wrist-created end and a followed end alike (the existing `followed` key is untouched). Never on an entry, a set block or any other kind (the validators refuse it: 134c1) | `WatchSessionEngine.swift:1704-1743` |
| D-13474 | `HealthKitSensorFeed` (`ios/OmniTrain Watch App/HealthKitSensorFeed.swift`): `activeEnergyPermission()` identical to `stepsPermission()`; `activeEnergy()` a stream registered in `energyContinuations: [UUID: AsyncStream<Double>.Continuation]` exactly like `steps()` (`forgetEnergy(_:)`, `yieldEnergy(_:)` beside `forgetSteps`/`yieldSteps`); in `workoutBuilder(_:didCollectDataOf:)` a third branch `else if type == HKQuantityType(.activeEnergyBurned)` reading `workoutBuilder.statistics(for: type)?.sumQuantity()` and yielding `quantity.doubleValue(for: HKUnit.kilocalorie())`. The header comment's "two things the wire carries" becomes three. No new authorization: the store already asks to read `activeEnergyBurned` | `HealthKitSensorFeed.swift:109-112, 139-156, 168-217, 268-319`; scout WIRE Q4 (`HealthKitWorkoutStore.swift:132-137, 325-343`) |
| D-13475 | The Dart twin records nothing and computes nothing (like steps): only the vocabulary entry | `watch_records.dart:129-131` |
| D-13476 | Names of new functions in `watch/watchos/Sources` avoid the append-only guard's banned verbs (update, delete, remove, replace, edit, overwrite, write, clear, purge, wipe, reset, drop, truncate, erase, forget, modify, mutate, destroy, set); `forgetEnergy` lives in the app target, where `forgetSteps` already does | crew playbook (r), (ac) |

## Scenarios

Swift tests are plain XCTest in `watch/watchos/Tests/WatchSessionEngineTests/`; new file `WatchActiveEnergyTests.swift` copies the fixtures style of `WatchSensorSummaryTests.swift` (read its first 110 lines: how samples and a session are built) and of `WatchSensorRecordingTests.swift` (a fake source).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13470 | `WatchSensorSummaries.activeEnergy`: samples `[12.34, 55.5, 120.04]` kcal inside the window | 120.0 (the last cumulative value, rounded to one decimal) | no function |
| S-13471 | the chain rules, three cases: a sample 100.0 before the window and 160.0 inside; a restart, samples inside `[100.0, 40.0]`; invalid values, samples inside `[NaN, -3.0, 50.0]` | 60.0; 140.0 (the second value is itself the energy since the restart: 100 + 40); 50.0 (invalid values ignored) | the chain rules are new |
| S-13472 | no sample inside the window; a single sample `0.0`; a total of `0.04` | nil, nil, nil (a zero total is never sent) | each is a distinct "never zero" arm |
| S-13473 | a wrist-created session with energy samples `[40.0, 95.5]` and an ended status | its `session_end` event has `activeEnergyKcal` 95.5 and also passes the protocol validator (reuse how `WatchSensorSummaryTests` validates an end) | the end carried no energy key at all |
| S-13474 | the same without any energy sample | the event has no `activeEnergyKcal` key | a session with no measurement must not send a zero |
| S-13475 | a followed session (source `phone`) with energy samples | `followed: true` and `activeEnergyKcal` both present | the followed end had no energy handling |
| S-13476 | recorder: a fake source whose `activeEnergyPermission` is `.granted` and whose `activeEnergy()` yields `[30.0, 75.5]`; then `.denied`; then the default (a source that does not implement the new members) | two `energy` rows stored in order; no rows; no rows and no crash | no subscription |

Plus (not numbered, listed as guards): `WatchSensorSourceSourceTests.swift` gains one test that reads `HealthKitSensorFeed.swift` and asserts the exact statements of D-13474 (the `else if type == HKQuantityType(.activeEnergyBurned) {` line, the `.sumQuantity()` read, the `HKUnit.kilocalorie()` unit, `energyContinuations[id] = continuation`, and `func activeEnergy() -> AsyncStream<Double> {`), each as its own `XCTAssertTrue(source.contains(...))` with the full statement including its brace, not a substring such as `activeEnergy`. The kinds tests (`WatchSensorRecordingTests.swift:574`, `test/watch_sensor_recording_test.dart:659`) pass only with the Swift list, the Dart list and the JSON contract all updated.

## Phases (outline)

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 package | crew-builder-watch | `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`, `WatchSensorRecording.swift`, `WatchSensorSummaries.swift`, `WatchSessionEngine.swift`, `watch/contract/watch_sensor_contract.json`, `lib/watch/session/watch_records.dart`, new `watch/watchos/Tests/WatchSessionEngineTests/WatchActiveEnergyTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift` (the kinds assertion only: it needs no edit if it compares with the contract; report) | serial |
| P2 app target | crew-builder-watch | `ios/OmniTrain Watch App/HealthKitSensorFeed.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift` | after P1 |
| P3 docs | crew-docs-keeper | the Docs delta rows | after P2 |

### P1 (one crew-builder-watch run)

Write the report FIRST as a skeleton. Never run the full `flutter test` or the full `swift test`; run only the filters below.

1. New `WatchActiveEnergyTests.swift` with S-13470 .. S-13476 (red first: the new members do not exist so it fails to compile).
2. `WatchRecords.swift`, `lib/watch/session/watch_records.dart`, `watch_sensor_contract.json` per D-13470.
3. `WatchSensorRecording.swift` per D-13471; `WatchSensorSummaries.swift` per D-13472; `WatchSessionEngine.swift` per D-13473.
4. Run `bash .github/copilot/scripts/macos/gateway.sh swift-test --filter WatchActiveEnergyTests`, then `--filter WatchSensorRecordingTests`, `--filter WatchSensorSummaryTests`, `--filter WatchFollowedSessionEndTests`, `--filter WatchSessionEngineTests` (the append-only source guard: filtered runs of the other files never select it), and `bash .github/copilot/scripts/macos/gateway.sh test -- test/watch_sensor_recording_test.dart`. Paste counts.

### P2 (one crew-builder-watch run, after P1)

Write the report FIRST as a skeleton. The app target has no test target and `swift test` cannot compile it: the lead builds it with `xcodebuild`. Write the exact code below, nothing else.

1. `HealthKitSensorFeed.swift`: add `private var energyContinuations: [UUID: AsyncStream<Double>.Continuation] = [:]` beside `stepContinuations`; `func activeEnergyPermission() async -> WatchSensorPermission { guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }; return await authorization() ? .granted : .denied }` beside `stepsPermission()`; `func activeEnergy() -> AsyncStream<Double>` after `steps()`, a copy of it with `energyContinuations` and `forgetEnergy`; in the delegate callback after the step-count branch:
```swift
            } else if type == HKQuantityType(.activeEnergyBurned) {
                guard let quantity = workoutBuilder
                    .statistics(for: type)?
                    .sumQuantity()
                else { continue }

                yieldEnergy(quantity.doubleValue(for: HKUnit.kilocalorie()))
            }
```
   `private func forgetEnergy(_ id: UUID)` and `private func yieldEnergy(_ kcal: Double)` as copies of `forgetSteps` / `yieldSteps`. Update the doc comments that say "two things the wire carries" and "`heartRate()` / `steps()`" to include active energy.
2. `WatchSensorSourceSourceTests.swift`: the guard test of the Scenarios section. Read the existing tests in that file (`testS3109...`, lines ~206-260) and copy how they load the feed source.
3. Run `--filter WatchSensorSourceSourceTests` and `--filter WatchSessionEngineTests`. Paste counts.

### P3 docs (one crew-docs-keeper run, after P2)

Run no test. The QA step goes into the numbered list under `### Level 3 — paired devices` of `docs/watch-app-setup-and-qa.md` as step 35 (after step 34, the last one).

## Readers to update (found by the lead)

| Reader | What it reads | Action |
|---|---|---|
| `WatchSensorRecordingTests.swift:574-575`, `test/watch_sensor_recording_test.dart:659-661` | `WatchSensorKind.all` against the contract's `kinds` | pass once all three lists agree |
| every fake `WatchSensorSource` in `watch/watchos/Tests` | the protocol | default extension keeps them compiling |
| exact-payload tests of a `session_end` (`WatchSensorSummaryTests` S-233/S-235 `summaryFields`, `WatchFollowedSessionEndTests`, `WatchSessionEngineTests:1111`, `test/watch_capture_contract_conformance_test.dart`) | the key set of an emitted end | unchanged: a fake source yields no energy; S-235 lists the keys a refused sensor must not produce: its list gains `activeEnergyKcal` (one string) |
| `lib/watch/**` (Dart twin) | `WatchSensorKind` | vocabulary only |

## Input-reality checklist

1. **Writers/units**: HealthKit's cumulative `activeEnergyBurned` for the workout, in kilocalories (D-13474), the only writer of energy samples; the phone never writes a measured row except from the wire.
2. **Lifecycle**: samples are stored rows like steps (a kill loses nothing), pruned with the others after the phone's receipt; a recovered workout restarts the cumulative counter: handled by the restart rule (S-13471); denied Health: no samples, no key, the phone estimates; a session that ends before the first energy sample: no key.
3. **Settings**: none; the Health permission is the existing single request.
4. **Time**: the window is the session's start to its end, pauses excluded by the platform's own accounting (the builder pauses with the workout).
5. **Cost**: one more stream task per session, one yield per builder callback.
6. **Words**: none on the wire.
7. **Competition**: a wrist and a phone running the same session: the wrist's measured total replaces the phone's estimate when its end arrives (134c1).

## Feature invariants

- A zero total is never sent; a value is never sent on anything but a `session_end`.
- The wrist stores readings, never holds them (rule 1 of `WatchSensorRecording.swift`).

## Existing-functionality impact

| Touch | What reads it today | Effect | Guarded by |
|---|---|---|---|
| `WatchRecords.swift` / Dart twin / contract | both kinds tests | one more kind | the two kinds tests |
| `WatchSensorRecording.swift` | the coordinator, every fake source | protocol members with defaults, one task | S-13476, the recorder suites |
| `WatchSessionEngine.swift` `sessionEndEvent` | every session end | one optional key | S-13473..S-13475, the end suites |
| `HealthKitSensorFeed.swift` | the watch app only (no test target) | one branch, one stream | the source guard; the lead's `xcodebuild` |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | One rounded total on the end is enough: no per-entry or per-block energy | the owner asked for a per-session number |
| A-2 | The simulator produces no energy samples; the real numbers are an owner device check (QA step 35) | the iOS simulator has no workout sensors |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/session_summary.md | MODIFIED | `- **The watch does not send measured energy yet.** Until plan 134c the watch` | `- **The watch sends its measured energy.** A session the watch ran or followed` | S-13473, S-13475 |
| docs/session_summary.md | REMOVED | writes no energy row of its own, so every value on this screen today comes | - | S-13473 |
| docs/session_summary.md | REMOVED | from the phone's estimate, `~`-marked; the measured case above is the one a | - | S-13473 |
| docs/session_summary.md | REMOVED | later unit fills (see [Watch Session Capture](watch_session_capture.md)). | - | S-13473 |
| docs/watch_session_capture.md | MODIFIED | The session's and each set block's heart rate | The session's active energy total, its heart rate and each set block's heart rate | S-13473 |
| docs/state_management/watch_sensors.md | MODIFIED | `statistics to beats per minute and cumulative steps, and delegates its two` | `statistics to beats per minute, cumulative steps and cumulative active energy, and delegates its two` | S-13476 |
| docs/state_management/watch_sensors.md | ADDED | - | `**Active energy is a stored cumulative reading.**` | S-13470, S-13471, S-13472 |
| docs/watch-app-setup-and-qa.md | ADDED | - | `**A wrist-measured session shows its calories without a tilde — (owner).**` | S-13473 |

The keeper rewrites the session_summary.md bullet so the first line carries the New marker and the removed lines are gone (the bullet continues: a phone-only session stays on the `~` estimate; `see [Watch Session Capture](watch_session_capture.md)`). The `watch_sensors.md` ADDED paragraph states the restart rule and the never-zero rule in the file's own style. The capture-doc row's table line keeps its other cell as it is.

Stale-term sweep (2026-11-09): `grep -rIn "does not send measured energy\|two things the wire carries\|beats per minute and cumulative steps" docs lib watch ios` outside plans/history/releases found `docs/session_summary.md:106-109` and `docs/state_management/watch_sensors.md:58`, and `HealthKitSensorFeed.swift`'s header (handled in P2).

## Progress

| Item | What | Status |
|---|---|---|
| P1.1 | red `WatchActiveEnergyTests.swift` | Planned |
| P1.2 | kind (Swift, Dart twin, contract) | Planned |
| P1.3 | recorder, summary function, session end | Planned |
| P1.4 | green P1 filters | Planned |
| P2.1 | feed code | Planned |
| P2.2 | source guard test | Planned |
| P2.3 | green P2 filters; the lead's `xcodebuild` | Planned |
| P3 | Docs delta rows and QA step 35 | Planned |
