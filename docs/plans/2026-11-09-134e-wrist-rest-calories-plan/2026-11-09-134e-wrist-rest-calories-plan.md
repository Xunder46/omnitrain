# Plan — 134e: calories burned so far, on the wrist's rest screen

**Status**: built, reviewed (watch review: 134c2 folder) and verified 2026-11-09; uncommitted. The 40 mm fit is an owner device check. Evidence: `docs/plans/2026-11-09-134e-wrist-rest-calories-plan/2026-11-09-134e-wrist-rest-calories-plan.evidence.md` (one file for 134b to 134e).
**Binding conventions**: `docs/global_conventions.md`, `docs/design_system.md` is the phone's; the wrist follows `docs/state_management/watch_surface.md`.
**Base commit**: `ff398e1a7ec18409d9fc8c890bf35d2fde656e69` (branch `claude_develop`; uncommitted 134a-134d are in the tree).
**Parent plan**: `docs/plans/2026-11-08-134-calories-burned-plan/2026-11-08-134-calories-burned-plan.md`.

## Overview

Owner (2026-11-08): on the watch, the rest screen shows the total calories burnt so far.

What the user sees on the wrist's rest screen: under the big rest clock, a small secondary line `142 kcal burned` (the Health workout's running total, a number the watch measured, so no `~`). It is hidden until the first energy reading exists (with Health refused, or before the first sample, the screen is exactly as today). Dimmed (Always On) the line updates once a minute with the clock.

This unit does NOT send a live total to the phone (the phone's active-session bar shows an estimate while a session runs, plan 134d; the wrist's measured total reaches the phone on the session end, plan 134c).

## Goal and acceptance

The line on the rest screen, from the stored energy samples. Acceptance: S-13480 .. S-13485.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13480 | `WatchSensorReadings` (`WatchSensorRecording.swift:77-95`) gains `public let activeEnergyKcal: Double?` (init parameter, default nil) and `WatchSensorRecorder.readings` fills it with `newest[WatchSensorKind.activeEnergy]?.value`: the newest stored cumulative sample of the current session, no other source (134c2 stores them) | `WatchSensorRecording.swift:135-144` |
| D-13481 | `WatchSensorLabels` (`WatchLoggingState.swift:153-175`) gains `public let activeEnergy: String?` (init parameter default nil); `WatchLoggingState.sensorLabels` (`:372-379`) fills it from the readings: `"\(Int(kcal.rounded())) kcal burned"` when `kcal >= 0.5`, else nil (nothing measured, or less than half a kilocalorie, shows nothing); new `public var activeEnergyLabel: String? { sensorLabels.activeEnergy }` beside `heartRateLabel` (`:403`) | `WatchLoggingState.swift:153-175, 372-403` |
| D-13482 | `WatchSpokenText` (`WatchSpokenText.swift:13`) gains `public static func activeEnergy(kilocalories: Int) -> String` returning `"\(kilocalories) kilocalories burned"` (`"1 kilocalorie burned"` for 1; never negative: `max(kilocalories, 0)`) | `WatchSpokenText.duration` as the model |
| D-13483 | `WatchRestView.body`: right after the `Text(elapsed)` block and before the second `Spacer(minLength: 0)`, inside the `VStack`, add exactly:
```swift
                if let burned = state.activeEnergyLabel {
                    Text(burned)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel("Calories burned")
                        .accessibilityValue(WatchSpokenText.activeEnergy(kilocalories: Int(state.readings.activeEnergyKcal?.rounded() ?? 0)))
                }
```
The view stays inside the existing `TimelineView`, so the value is re-read on the rest's own tick (every second, once a minute dimmed); no timer, no new state. Nothing else on the screen moves; the two `Spacer`s absorb the line's height | `WatchRestView.swift:68-110` |
| D-13484 | Names of new functions/properties in `watch/watchos/Sources` avoid the append-only guard's banned verbs (`activeEnergyLabel`, `activeEnergy(kilocalories:)` are fine) | crew playbook (r), (ac) |

## Scenarios

New `watch/watchos/Tests/WatchSessionEngineTests/WatchRestEnergyTests.swift`; copy how `WatchSensorRecordingTests.swift` builds a recorder over a fake source and a session, and how `WatchRestLabelsTests.swift` builds a `WatchLoggingState` (read the first 120 lines of each).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13480 | a session with `energy` samples `[40.0, 95.5]` stored through the recorder (a fake source with `activeEnergyPermission` `.granted`, from 134c2) | `recorder.readings.activeEnergyKcal` is 95.5; with no sample it is nil | the readings carried no energy |
| S-13481 | `WatchLoggingState.sensorLabels.activeEnergy` for 95.5, 0.3, 1234.4, 0.5 and no sample | `"96 kcal burned"`, nil, `"1234 kcal burned"`, `"1 kcal burned"` (0.5 rounds up), nil | no label |
| S-13482 | `WatchLoggingState.activeEnergyLabel` equals `sensorLabels.activeEnergy` for the same session | equal | no accessor |
| S-13483 | `WatchSpokenText.activeEnergy(kilocalories:)` for 96, 1, 0, -4 | `"96 kilocalories burned"`, `"1 kilocalorie burned"`, `"0 kilocalories burned"`, `"0 kilocalories burned"` | no helper |
| S-13484 | a source-text guard on `WatchRestView.swift` (read the file text as `WatchRestLabelsTests` does for its guard at ~line 444): the exact statement `if let burned = state.activeEnergyLabel {` including its brace; the exact `Text(burned)`; the exact `.accessibilityLabel("Calories burned")`; and ORDER: the index of `Text(elapsed)` is less than the index of `if let burned = state.activeEnergyLabel {`, which is less than the index of `Text(labels.next)` | all hold | the line is not on the screen |
| S-13485 | the existing rest source guards still pass: `WatchRestPingWiringSourceTests` (slices the `WatchRestView(` source), `WatchAccessibilitySourceTests` (lines 28, 58), `WatchRestLabelsTests`, `WatchRestAdvanceTests`, `WatchRestIsCountUpTests` | unchanged | n/a: the readers of the view's text, all listed so a changed slice fails loudly |

The simulator shows no energy (no workout sensors): the rendered look at 40 mm and 45 mm is an owner device check (QA step 35 of 134c2 covers it).

## Phases (outline)

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 package | crew-builder-watch | `watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift`, `WatchLoggingState.swift`, `WatchSpokenText.swift`, `WatchRestView.swift`, new `watch/watchos/Tests/WatchSessionEngineTests/WatchRestEnergyTests.swift` | serial (needs 134c2) |
| P2 docs | crew-docs-keeper | the Docs delta rows | after P1 |

### P1 (one crew-builder-watch run)

Write the report FIRST as a skeleton. Never run the full `swift test` or `flutter test`.

1. New `WatchRestEnergyTests.swift` with S-13480 .. S-13484 (red first: the members do not exist, so it fails to compile).
2. `WatchSensorRecording.swift` per D-13480; `WatchLoggingState.swift` per D-13481; `WatchSpokenText.swift` per D-13482; `WatchRestView.swift` per D-13483 (the exact code above; the view compiles only for watchOS, so `swift test` cannot see it: the lead builds it with `xcodebuild`). The package targets watchOS 9: use only what the existing file already uses.
3. Run `bash .github/copilot/scripts/macos/gateway.sh swift-test --filter WatchRestEnergyTests`, then `--filter WatchRestLabelsTests`, `--filter WatchRestAdvanceTests`, `--filter WatchRestPingWiringSourceTests`, `--filter WatchAccessibilitySourceTests`, `--filter WatchRestIsCountUpTests`, `--filter WatchSensorRecordingTests`, and `--filter WatchSessionEngineTests` (the append-only guard). Paste counts.

### P2 docs (one crew-docs-keeper run)

Run no test. The QA step 35 of 134c2 is extended by one sentence (see the Docs delta).

## Readers to update (found by the lead)

| Reader | What it reads | Action |
|---|---|---|
| `WatchRestLabelsTests.swift` (~444), `WatchRestAdvanceTests.swift`, `WatchRestPingWiringSourceTests.swift` (~122), `WatchAccessibilitySourceTests.swift` (28, 58) | slices and statements of `WatchRestView.swift` | S-13485: run unchanged; a failure means the new lines moved a slice |
| every `WatchSensorReadings(...)` construction in tests | the struct's initialiser | the new parameter has a default, so none changes |
| every `WatchSensorLabels(...)` construction | the struct's initialiser | default parameter, none changes |
| `lib/watch/**` | the Dart twin of the rest screen (`watch_rest_screen.dart`, mounted by no runtime harness) | untouched: the Dart twin shows no sensor values today |

## Input-reality checklist

1. **Writers/units**: the energy samples of 134c2, in kilocalories, cumulative; the line shows the newest sample of the current session only.
2. **Lifecycle**: hidden with no sample (Health refused, first seconds, a lift with no workout energy yet); after a recovered workout the Health counter restarts, so the line restarts from the new counter while the total sent on the end keeps the chain (plan 134c2 D-13472): an accepted limitation, listed below.
3. **Settings**: none.
4. **Time**: re-read on the screen's own tick; dimmed, once a minute.
5. **Cost**: `sensorLabels` is one pass over the session's samples, called once per tick (the logging surface already does this each second).
6. **Words** (owner-visible): `142 kcal burned`; VoiceOver `Calories burned`, `142 kilocalories burned`.
7. **Competition**: the rest screen has the caption, what was just done, the clock, what is next and the Next button; the line takes a few points below the clock from the two `Spacer`s. At 40 mm the available height is the owner device check.

## Feature invariants

- The line is a measured value: never `~`, never an estimate.
- No energy sample, no line.

## Existing-functionality impact

| Touch | What reads it today | Effect | Guarded by |
|---|---|---|---|
| `WatchSensorRecording.swift` `WatchSensorReadings` | the logging model, coordinator tests | one defaulted field | S-13480, the recorder suites |
| `WatchLoggingState.swift` `WatchSensorLabels`, `sensorLabels` | the logging surface's status line | one defaulted field; the status line ignores it | S-13481, `WatchLoggingModel` suites |
| `WatchRestView.swift` | the host (`ContentView.swift:480`), five source-guard suites | one conditional block | S-13484, S-13485 |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | After a recovered workout the live line restarts from the new counter | the readout reads the newest stored sample; the chain is the end total's job |
| A-2 | No live watch-to-phone feed in this unit | the wire has no live sensor frame; a new frame type is a separate plan |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/rest_tracking.md | ADDED | - | `**Calories so far.**` | S-13480, S-13481, S-13484 |
| docs/state_management/watch_sensors.md | ADDED | - | `activeEnergyKcal` | S-13480 |

The `rest_tracking.md` paragraph goes in "The Wrist's Rest": the rest screen shows the Health workout's running total under the clock as `N kcal burned`, hidden until the first reading, a measured number (no tilde), updated on the screen's own tick. The `watch_sensors.md` marker is satisfied by a sentence in the active-energy paragraph 134c2 adds ("the live readout reads the newest stored sample as `WatchSensorReadings.activeEnergyKcal`").

Stale-term sweep (2026-11-09): `grep -rIn "rest screen\|Wrist's Rest" docs` found `docs/rest_tracking.md:302-317` as the only description of the wrist rest screen's contents.

## Progress

| Item | What | Status |
|---|---|---|
| P1.1 | red `WatchRestEnergyTests.swift` | Planned |
| P1.2 | readings, labels, spoken text, rest view | Planned |
| P1.3 | green filters; the lead's `xcodebuild` | Planned |
| P2 | Docs delta rows | Planned |
