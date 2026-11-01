# Feature: 93 — the wrist shows a Distance tile only while GPS measures the effort (undo plan 65's dial)

> Status: Iteration 1 active — Phase 1 complete 2026-11-01; Phase 2 not started.
> Next handoff: @code-reviewer (Phase 1), then @developer (Phase 2)
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md; docs/state_management/watch_surface_wrist.md; docs/distance_source.md
> Branch: the one checked out (`claude_develop`); never create or switch branches; never commit (the governor owns git).
> Shared tree (2026-11-01): another session holds 14 uncommitted phone-side files (`lib/state/workout/*`, `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/features/session/session_summary_screen.dart`, `lib/features/exercise/exercise_editor_screen.dart`, `docs/session_summary.md`, `docs/state_management/workout_state.md`, 7 test files) and two untracked `scripts/*.sh`. None is a predicted file here: do not edit, format, stage or revert them. Nothing under `watch/` is uncommitted; plan 65 is committed (`65a6a0de`).

## Overview

Owner decision (chat, 2026-11-01): remove the hand-dialled Distance tile plan 65 put on the wrist's timed-effort screen. The tile appears only while the watch's GPS has measured movement in the running effort, and it is read-only live information. With no GPS measurement a timed effort shows the clock and Start/Log, nothing else. A distance is entered or corrected afterwards on the phone's Session Summary DISTANCE row (`docs/session_summary.md#distance`, unchanged). The wire is unchanged: the phone still accepts `distanceSource: "entered"`; the wrist simply no longer produces it. Why: a `0.0 km` input beside the running clock confused the owner.

| What you do on the wrist | Today (plan 65) | After 93 |
|---|---|---|
| Open a run (distance exercise), before Start | Distance tile `0.0 km` with − / + | clock + Start only |
| Indoors / Location refused: Start, run, Log | tile dialable; dialled value sent as `entered` | clock + Log only; Log sends no distance; add it on the phone Summary |
| Outdoors: GPS measures movement mid-effort | tile turns read-only, shows the effort's GPS metres (grey − / +) | tile appears at that moment, read-only, no − / +; Log sends the metres as `gps` (unchanged) |
| Next effort of the same run | tile back at 0, dialable | no tile until GPS measures that effort |
| Hold, period, set, exercise without distance | no distance tile | unchanged |

## Resolved Decisions (Ledger)

Plan-local IDs; cite as "plan 93 D-n". Plan 65's D-1 and D-3 are superseded here; its D-2 (window-based measurement) is kept.

- **D-1 (supersedes plan 65 D-1) The tile rule.** For an effort with `effortKind == timed` on an exercise whose `capabilities` contain `"distance"`, `WatchLoggingState.fields` is `[distance field]` exactly when `isMeasured(WatchMetricKey.distance)` is true — `isMeasuringDistance` (location subscription running) AND `windowDistanceMeters() > 0` (the running work clock's own window, plan 65 D-2, code unchanged) — and `[]` otherwise. An unmeasured distance field is never produced on any surface. Consequences that follow without extra code, each pinned by a scenario: no tile before Start (no running clock → window 0); none after Log or on the rest screen (clock stopped → `workTimer` nil; the rest view does not render `fields`); none on the next effort until its own window measures movement; once shown it stays while the subscription runs (the window chain only adds non-negative increments); if the subscription stops mid-effort the tile goes and the Log carries no distance (D-3 says the same). Threshold is strictly `> 0` m, so the first metres may read `0.0`. **Derived — vetoable by the owner before Phase 1.** Mechanic free: filter in `fields`, in `metricKeys`, or empty `metricKeysByKind[timed]` plus an explicit measured-distance append.
- **D-2 The tile's value and unit.** Value = `windowDistanceMeters()` (the effort's own metres, never `readings.distanceMeters`'s session total); `isMeasured == true`; label `Distance`; display through the existing `displayValue` / `unitLabel` (`"%.1f"` of metres ÷ `WatchMetricStepping.metresPerUnit(units.distanceUnit)`, `km` or `mi`). No new conversion code (global conventions: units rule).
- **D-3 (supersedes plan 65 D-3) The Log payload.** `windowPayload(loggedAt:coversDistance:)` returns to GPS-only: when `coversDistance && isMeasuringDistance` and `windowMeters(from: startedAt, through: loggedAt) > 0`, the event carries `distanceMeters` = that value and `distanceSource: "gps"`; otherwise neither key. The `entered` branch and its comments are deleted, and no file under `watch/watchos/Sources` contains the literal `"entered"` (S-16013). Feature invariant I-1 below follows.
- **D-4 Crown and button: no model change.** `WatchLoggingModel.armedMetricKey` already filters out measured fields, so a timed surface arms nothing with or without the tile; a tile appearing mid-effort never takes the Crown, `turn(to:)` and `stepArmed(_:)` are no-ops, and `primaryTitle` / `primaryAction` (which read only `isTimedWork` / `isWorkRunning`) are unaffected. `WatchLoggingModel.swift` is not a predicted file.
- **D-5 The read-only tile's look.** In `WatchLoggingView`, a field with `isMeasured == true` renders as its tile alone: no − / + step buttons around it, no tap-to-arm, no `.isButton` accessibility trait; its accessibility label stays `"<label> <displayValue> <unitLabel>"`. Unmeasured rows, the two-tile layout and the shared pair are unchanged (keep `stepArmed(` at exactly 2 call sites and the `"Less \(label)"` / `"More \(label)"` strings: `WatchLoggingStatusTests` ~l.340-360 scans them). Why: with D-1 every visible distance tile is measured, so the grey − / + would always be dead controls that read as an input — the owner's complaint. **Derived — vetoable by the owner before Phase 2.**
- **D-6 Dead code: remove only what exists solely for the dial.** Delete: the `entered` branch in `windowPayload` and the plan-65 comments describing the dial. Keep: `dialled` storage (reps, weight, extra weight, period length use it); the `adjust` measured-field guard (generic); `WatchMetricStepping` distance `step` / `fineStep` / `clamp` (they predate plan 65, mirror `lib/watch/logging/watch_metric_stepping.dart` value for value, and are pinned by `WatchLoggingTimersTests` ~l.619-674 and `WatchFineCrownTests` ~l.79); distance `displayValue` / `unitLabel` (the read-only tile needs them). New function names in `watch/watchos/Sources` must not start with the append-only guard's verbs `update|delete|remove|replace|edit|overwrite|write|clear` (`WatchSessionEngineTests` "S-004 append-only enforcement", ~l.320-412).
- **D-7 Wire and phone: no change.** `watch/sync_protocol/schemas/envelope.schema.json`, `SyncProtocolValidator.swift`, the fixtures and the phone importer (`lib/core/services/watch_session_importer.dart`) are untouched; `entered` stays valid, and a plan-65 build's stored `entered` event still flows through the wrist pipeline and imports (S-16014). `watch/sync_protocol/PROTOCOL.md` ~l.193-196: replace plan 65's sentence ("The wrist sends the distance GPS measured … never both.") with: "The watchOS wrist sends a distance only when GPS measured movement inside the effort's own window (`distanceSource` `gps`); it has no distance dial, so a distance GPS did not measure is entered afterwards on the phone's Session Summary. `entered` stays valid on the wire: a wrist build from before 2026-11-01 sends it for a dialled distance, and the phone stores it as sent." Keep the sentence before it ("Distance is entered by hand whenever the watch has no fix …"): it is the protocol-level rule and still holds.
- **D-8 Dart wrist twin (`lib/watch`): no change.** It never had plan 65's dial; it derives timed rows from `EffortDefaults` (dialled duration and distance, sent without a source, which the phone stores as `entered`); it is imported only by `lib/state/watch/live_session_mirror_debug_main.dart` and tests (grep below); Wear OS is deferred. The divergence predates plan 65 and is unchanged.
- **D-9 Tests.** Delete `WatchHandDistanceTests.swift` (every test in it pins the dial); new `WatchGpsDistanceTileTests.swift` holds S-16001..S-16013 except S-16012's restored S-006 half. Existing tests change as listed in "Existing tests that pinned plan 65" — intent kept, never loosened.
- **D-10 Docs.** `docs/state_management/watch_surface_wrist.md` is 52,233 bytes; the warning band of `test/docs_indexing_contract_test.dart` is 52,429 (0.80 × 64 KiB). Rewrite the plan-65 paragraph ("**A timed effort on a distance exercise offers a Distance row.**", ~l.361-373) in place; the file must end each phase at ≤ 52,233 bytes (`wc -c`). `docs/watch-app-setup-and-qa.md` step 27 rewritten (Phase 2, text intent in the phase). No other doc changes (proof in the Impact table).
- **D-11 Phone hint: not in this plan.** The optional Session Summary hint for a wrist effort that arrived without distance is owner question Q1 (default "not now"). A "yes" becomes its own plan; this plan does not wait for it.

## Feature Invariants

- **I-1** For a distance-capable timed exercise, at any instant with the work clock running: the tile is shown with value V ⇔ a Log at that instant carries `distanceMeters` V and `distanceSource: "gps"`. Asserted in S-16006 and S-16007 by logging at the checked instant.
- **I-2** The watchOS wrist never emits `distanceSource: "entered"`; the wire and the phone keep accepting it.
- **I-3** Plan 65 D-2 stays: the measured value is the effort's own window from the baseline sample (newest `gps` sample at or before Start, S-3214/S-3217), never the session total.

## Requirements

- R-1 Timed effort, distance-capable exercise: no tile unless GPS measured movement in the running effort's window (D-1).
- R-2 The tile, when shown, is read-only live information in the phone's unit, without − / + (D-2, D-5).
- R-3 The tile never takes the Crown or moves the primary button's role (D-4).
- R-4 A Log without GPS movement carries no distance; with movement it carries the GPS metres as `gps` (D-3).
- R-5 Wire, phone import and Session Summary unchanged; legacy `entered` still imports (D-7).

## Acceptance Criteria

- AC-1 Before Start, with or without GPS running, a run shows no tile → S-16001, S-16002, S-16003.
- AC-2 No movement in the window (still watch, refused access, no recorder) → no tile and no distance in the Log → S-16002, S-16003, S-16004, S-16005, S-16012.
- AC-3 First movement mid-effort makes the tile appear read-only with the effort's metres; the Crown stays unarmed; Log carries `gps` → S-16006.
- AC-4 The next effort of the same exercise starts with no tile and measures its own window → S-16007.
- AC-5 No tile on an exercise without distance, a hold or a period, even with movement → S-16008, S-16009.
- AC-6 Units: miles and km display of the same metres → S-16010.
- AC-7 The measured tile has no − / + → S-16011. No `"entered"` producer remains → S-16013.
- AC-8 Legacy `entered` events still pass the wrist pipeline and import on the phone → S-16014.

## Existing-Functionality Impact

| Touched surface | Readers (grep that found them) | Effect | Guarded by |
|---|---|---|---|
| `WatchLoggingState.fields` | `grep -rn '\.fields' watch/watchos/Sources` → `WatchLoggingView.swift` l.287, l.373; `WatchLoggingModel.swift` l.49, l.58; inside the state: `adjust` l.938, `value(of:)` l.1173; `ios/OmniTrain Watch App` none (`grep -rn '\.fields\|isMeasured' "ios/OmniTrain Watch App"` empty); 27 test assertions (`grep -rn 'fields.isEmpty\|fields.count\|fields.map' watch/watchos/Tests`) | timed + distance: `[]` unless measured. `value(of:)` is read only for set and drill payloads, never for timed | S-16001..S-16009; existing-test table below |
| `windowPayload` (only producer of `distanceSource`) | `grep -rn 'distanceSource' watch/watchos/Sources` → `WatchLoggingState.swift` l.1093/1096, `SyncProtocolValidator.swift` l.81/367-387 (accepts any source beside metres) | `entered` no longer produced | S-16004, S-16005, S-16012, S-16013, S-16014 |
| `dialled` storage | `grep -n 'dialled\[' WatchLoggingState.swift` → `field(for:)`, `adjust`, `log` clear, `windowPayload` | only the `windowPayload` read goes; others serve reps/weight/extra/period | existing `WatchDialledPerExerciseTests` (S-6410..S-6413) green |
| `WatchMetricStepping` distance | `grep -rn 'WatchMetricKey.distance' watch/watchos/Tests` → `WatchLoggingTimersTests` l.619-674, `WatchFineCrownTests` l.79-80 | none (kept, D-6) | those tests green unchanged |
| `WatchLoggingView.row(_:)` / `tile(_:)` | every single-row surface: period length before Start, hold extra weight, timed distance; `isMeasured` is true only for `distance` (`WatchLoggingState.isMeasured`) | only measured rows change | S-16011; `WatchLoggingStatusTests` view scan; `WatchAccessibilitySourceTests`; `WatchExercisePageFitTests` green |
| Rest screen | `grep -rn 'fields' watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift` empty | none | — |
| Dart twin `lib/watch` | `grep -rln 'watch/logging/watch_logging_state.dart' lib test \| grep -v '^lib/watch/'` → `lib/state/watch/live_session_mirror_debug_main.dart` + 9 tests | none (D-8) | no Dart file changes |
| Phone import / Summary | `test/distance_source_import_test.dart` S-876 (stores `entered` 3000 m), S-877 (sourceless 2500 m → `entered`); `test/session_summary_distance_test.dart` S-817 (fill an empty entry), S-818c (watch-imported session), S-3213 (hint `Tap a row to enter or correct it.`) | a wrist run without GPS arrives without distance → its row reads `—`, tap to enter: already the shipped behaviour | those tests green, unchanged |
| `PROTOCOL.md` ~l.193-196 | protocol readers; not under `docs/` (no size ceiling) | sentence replaced (D-7) | — |
| `docs/state_management/watch_surface_wrist.md` | `grep -rln 'isMeasuringDistance\|distanceSource\|timed surface\|plan 65' docs \| grep -v docs/plans` → this file, `watch-app-setup-and-qa.md`, `watch_sensors.md`, `distance_source.md` | paragraph rewritten (D-10) | `test/docs_indexing_contract_test.dart` |
| `docs/state_management/watch_sensors.md` l.375-382 ("a window that moved nothing … carry neither") | — | becomes accurate again; no edit | — |
| `docs/distance_source.md` l.94-97, l.174 (`entered` = typed or dialled; sourceless watch distance) | — | still true for the phone and legacy events; no edit | — |
| `docs/watch-app-qa-wrist-logging.md` step 6 ("no duration, distance, rounds or length row"), step 29 (40 mm fit) | — | step 6 accurate again; step 29 unchanged (step 27 carries the tile's 40 mm check) | — |
| Standing invariants | hive import sweep (no `lib/` change); docs/UI contracts; append-only verbs (D-6); rest count-up rule (untouched); units rule (D-2) | — | Done Criteria |

Known, not changed: (a) the header's grey status line already shows the whole workout's GPS distance and pace (`WatchLoggingModel.sensorLine`, session total); with the tile the screen shows two distances that differ from the second effort on — owner question Q2, default keep. (b) A timed effort on an exercise WITHOUT the distance capability in a cardio session still logs GPS metres when GPS runs (`metricPayload` → `windowPayload(coversDistance: true)`, D-2205); it shows no tile; S-16008 does not assert its payload.

## UI Standards Impact

Watch views are SwiftUI outside `docs/design_system.md`'s Flutter shared pieces; no Flutter UI changes. The phone Summary's DISTANCE card (`SessionDistanceCard`) is unchanged. No allowlist entry, no ratchet change.

## Scenarios

Shared fixture **F-RUN**: `Harness()` with its injected `TestClock` at T0; `engine.createSession(modality: "cardio_endurance", exercises: [sx-run])` where sx-run = `{"sessionExerciseId": "sx-run", "exerciseId": "ex-run", "name": "Run", "capabilities": ["time", "distance"]}`; `FakeSensorSource` with location granted unless stated; `WatchSensorRecorder(engine:source:clock:)` started on the session; `WatchLoggingState(engine:clock:sensors: recorder)` with km units unless stated; `WatchLoggingModel(state:haptics: RecordingHaptics())` where the Crown is asserted. `source.fix(m)` stores one `gps` sample of cumulative `m` metres at the clock's current instant. Await each sample's storage before asserting (the readout, or the count of stored `gps` samples when the readout cannot change).

### S-16001: before Start there is no tile
- Fixture: F-RUN; `fix(800)` at T0 (a stale sample). Second variant: same session, `WatchLoggingState` with `sensors: nil`.
- Trigger: build the surface; no Start.
- Flow: read `fields`, `model.armedMetricKey`, `model.primaryTitle`.
- Expected outcome: both variants: `effortKind == timed`, `fields == []`, `armedMetricKey == nil`, `primaryTitle == "Start"`. (Base: `[distance]` — red.)
- Edge case of: none

### S-16002: a sample exactly at the Start instant is the baseline
- Fixture: F-RUN, no sample before Start.
- Trigger: `startWork()` at T0; `fix(800)` at T0 (clock not moved); advance 600 s, no more samples.
- Flow: read `fields` at T0+600; `log()`.
- Expected outcome: `fields == []` (window = 0: the T0 sample is the baseline); the event has neither `distanceMeters` nor `distanceSource`.
- Edge case of: S-16001

### S-16003: stale pre-Start samples never count
- Fixture: F-RUN; `fix(800)` at T0.
- Trigger: advance 300 s; `startWork()` at T0+300; advance 1200 s, no samples.
- Flow: read `fields` at T0+300 and T0+1500; `log()` at T0+1500.
- Expected outcome: `fields == []` both times (baseline 800, nothing after it); the event has neither key.
- Edge case of: S-16001

### S-16004: a still watch with samples inside the window measures 0
- Fixture: F-RUN; `fix(800)` at T0.
- Trigger: advance 300 s, `startWork()` (T0+300); advance 60, `fix(800)` (T0+360); advance 60, `fix(800)` (T0+420).
- Flow: await 3 stored `gps` samples; read `fields`; `log()` at T0+420.
- Expected outcome: window = (800−800)+(800−800) = 0 → `fields == []`; `isMeasuringDistance == true`; the event has neither key.
- Edge case of: none

### S-16005: Location refused
- Fixture: F-RUN with `source.locationGrant = .denied`.
- Trigger: `startWork()` at T0; advance 600 s; `adjust(WatchMetricKey.distance, detents: 25)`; `model.turn(to: 3 * WatchLoggingModel.pointsPerDetent)`; `model.stepArmed(1)`.
- Flow: read `isMeasuringDistance`, `fields`, `sensorNotices`; `log()` at T0+600.
- Expected outcome: `isMeasuringDistance == false`; `fields == []` before and after the dial attempts; `sensorNotices` contains `WatchSensorNoticeCopy.noDistance` (unchanged); the event has neither key.
- Edge case of: none

### S-16006: first movement mid-effort shows the tile, read-only, without taking the Crown
- Fixture: F-RUN; `fix(300)` at T0.
- Trigger: advance 60, `startWork()` (T0+60); advance 600 → T0+660, then `fix(1534)` at T0+660.
- Flow: at T0+660 before the fix: `fields == []`. After the fix lands: read the field, `model.armedMetricKey`, `model.primaryTitle`; `model.turn(to: 3 * pointsPerDetent)`; `model.stepArmed(1)`; `state.adjust(distance, detents: 10)`; re-read; advance 600; `log()` at T0+1260.
- Expected outcome: `fields.map(\.metricKey) == [distance]`, `isMeasured == true`, `value == 1234` (1534 − 300), `displayValue == "1.2"`, `unitLabel == "km"`; `armedMetricKey == nil` before and after the turn; value stays 1234 after turn/step/adjust; `primaryTitle == "Log"`. Event: `distanceMeters == 1234`, `distanceSource == "gps"` (I-1: equals the tile).
- Edge case of: none

### S-16007: the next effort of the same exercise starts with no tile and measures its own window
- Fixture: F-RUN, no sample before T0.
- Trigger: effort 1: `startWork()` T0; advance 600, `fix(500)` (T0+600); advance 600, `log()` (T0+1200). Rest: advance 200, `fix(650)` (T0+1400); advance 100 → T0+1500. Effort 2: `startWork()` T0+1500; advance 60, `fix(850)` (T0+1560); advance 600, `log()` (T0+2160).
- Flow: read `fields` at T0+1500 before Start, right after Start, and at T0+1560 after the fix; read `recorder.readings.distanceMeters`.
- Expected outcome: effort 1 event 500 `gps`; at T0+1500 before Start `fields == []` (a stopped clock measures nothing, although 650 m were covered since effort 1's Start); right after Start `fields == []` (baseline 650); at T0+1560 tile `value == 200` (850 − 650) while `readings.distanceMeters == 850`; effort 2 event 200 `gps`.
- Edge case of: S-16006

### S-16008: an exercise without the distance capability never shows the tile
- Fixture: F-RUN but the slot is sx-row = `{"sessionExerciseId": "sx-row", "exerciseId": "ex-row", "name": "Row", "capabilities": ["time"]}` (GPS still runs: cardio modality).
- Trigger: `startWork()` T0; advance 60; `fix(400)`.
- Flow: read `fields`.
- Expected outcome: `fields == []` before Start and after the movement. Payload not asserted (Known (b)).
- Edge case of: none

### S-16009: a hold and a period never show the tile, even with movement
- Fixture: (a) `modality: "sports"`, slot sx-period `{"sessionExerciseId": "sx-period", "exerciseId": "ex-period", "name": "Period", "capabilities": ["time", "rounds", "distance"]}`; (b) `modality: "isometric_stretching"`, slot sx-plank `{"sessionExerciseId": "sx-plank", "exerciseId": "ex-plank", "name": "Plank", "capabilities": ["hold", "time", "distance"]}`; each its own `Harness`, recorder started.
- Trigger: each: read `fields`; `startWork()`; advance 60; `fix(400)`; read `fields`.
- Expected outcome: (a) `effortKind == round`; before Start `[roundDuration]`, after Start `[]` (D-3404). (b) `effortKind == drill`; `[extraWeight]` before and after. Neither ever contains `distance`.
- Edge case of: none

### S-16010: the tile reads in the phone's unit
- Fixture: F-RUN, no sample before T0; two states on the same engine and recorder: `units: WatchUnitPreferences(distanceUnit: "miles")` and the default km.
- Trigger: `startWork()` (either state) at T0; advance 600; `fix(1609.344)`.
- Flow: read the distance field on both; `log()` from the miles state.
- Expected outcome: miles: `displayValue == "1.0"` (1609.344 ÷ 1609.3445 ≈ 0.99999997), `unitLabel == "mi"`; km: `"1.6"`, `"km"`; both `value == 1609.344`; event `distanceMeters == 1609.344` (accuracy 0.001), `distanceSource == "gps"`.
- Edge case of: S-16006

### S-16011: a measured tile has no − / + (structural guard)
- Fixture: the text of `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift`, comment lines stripped (the `engineSource` pattern of `WatchAccessibilitySourceTests`).
- Trigger: scan.
- Expected outcome: the single-row path renders a measured field as its tile only (no `stepButton` reached for it) and the `.isButton` trait is applied only to unmeasured tiles; exact anchors are the implementer's, but the test MUST fail on the base commit. Existing scans (`stepArmed(` count 2, `"Less \(label)"`, `"More \(label)"`) stay green.
- Edge case of: none

### S-16012: nothing dialled on the wrist reaches the log
- Fixture: F-RUN without a recorder (`sensors: nil`), plus the model.
- Trigger: `startWork()` T0; advance 120; `adjust(distance, detents: 5)`; `model.turn(to: 3 * pointsPerDetent)`; `model.stepArmed(1)`; `log()`.
- Expected outcome: `fields == []` throughout; event has neither key; the package validator reports no rejection. The plain-state half is the restored `WatchLoggingSurfacesTests.testS006AManualDistanceNeverReachesTheObservation`; the Crown half lives in the new file.
- Edge case of: S-16005

### S-16013: no source file produces `entered` (structural guard)
- Fixture: every `.swift` file under `watch/watchos/Sources`, comment lines stripped.
- Trigger: scan for the literal `"entered"`.
- Expected outcome: zero hits. Red on base (`WatchLoggingState.swift` l.1096).
- Edge case of: none

### S-16014: a legacy `entered` event still flows and imports (existing tests, no new test)
- Fixture: `watch/sync_protocol/fixtures/valid/observations_up_distance_source.json` events `e-ds-gps` (timed, 5000, `gps`), `e-ds-entered` (timed, 3000, `entered`), `e-ds-est` (timed, 4200, `estimated`); phone `test/distance_source_import_test.dart` S-876/S-877 fixtures.
- Trigger: run the existing tests.
- Expected outcome: `SyncProtocolFixturesTests.testEveryValidFixtureConforms` and `…testEveryValidObservationsEventFlowsThroughTheEmissionPipeline` green; phone S-876 stores `(3000.0, entered)` among the three; S-877 stores `(2500.0, entered)` and `(0.0, null)`.
- Edge case of: none

### Existing tests that pinned plan 65 (D-9)

| Test | Change | Intent kept |
|---|---|---|
| `WatchHandDistanceTests.swift` (all 13) | file deleted | replaced by S-16001..S-16013 |
| `WatchLoggingSurfacesTests.testS9503ADialledDistanceReachesTheObservation` | restore as `testS006AManualDistanceNeverReachesTheObservation`: keep `adjust(distance, detents: 5)`, assert `distanceMeters` and `distanceSource` nil, `rejections.isEmpty`; header map line back to S-006; ~l.657-660 comment drops "plan 65's other way in" | a dial never reaches the log |
| `WatchSensorRecordingTests.testS004WithoutAFixTheTimedSurfaceOffersAnUnmeasuredDistanceRow` | back to `testS004WithoutAFixTheTimedSurfaceOffersNoDistanceRow`: `fields.isEmpty`; restore the pre-Start `adjust(distance, detents: 15)`; log assertions unchanged | no fix → no row, no distance |
| `WatchSensorRecordingTests.testAMeasuredDistanceIsWhatTheObservationCarries` | before Start `fields.isEmpty` and the dial does nothing; after the in-window fix: `[distance]`, measured, 3200, `adjust` leaves 3200; log `gps` 3200 unchanged | measured → read-only, carried as `gps` |
| `WatchCrownArmingTests` measured-row test (~l.165-212) | assertions unchanged; comment only | a measured row is never armed |
| `WatchCrownArmingTests.testS6408…` cardio half | no recorder: `arm(distance)` and `arm(reps)` both refused, `armedMetricKey == nil`, 0 notifications | a refused arm publishes nothing |
| `WatchCaptureContractTests.testS1303ATimedSurfaceHasNoLengthToDial` | `fields.isEmpty` (the `full` case has no `gps` op); doc comment | no length row to dial |
| `WatchLoggingStatusTests` l.138, l.173; `WatchTimedWorkTests` l.142, l.770; `WatchBodyweightLoadTests` l.93 | assertions and time-only fixtures unchanged; "plan 65:" comments rewritten to the D-1 rule | unchanged |

### Mutations (implementer records in evidence; reviewer re-runs a sample)

Carried from plan 65 (adapted): M1 `measuredValue` → `readings.distanceMeters` (S-16007 red); M2 tile shown on `isMeasuringDistance` alone (S-16003, S-16004 red); M3 baseline dropped, `cumulativeMeters` → 0 (S-16003, S-16006 red); M4 `covered > 0` → `>= 0` in `windowPayload` (S-16004 red); M5 distance added to drill/round keys (S-16009 red); M6 miles conversion removed from `displayValue` (S-16010 red); M7 tile never shown (S-16006 red). New: M8 unmeasured field shown again (S-16001 red); M9 `windowDistanceMeters` reads a stopped clock (S-16007 red); M10 `armedMetricKey` stops filtering measured fields (S-16006 red); M11 `entered` branch restored (S-16013 red — behaviourally equivalent otherwise, which is why it is deleted); M12 − / + rendered around a measured tile (S-16011 red). Retired with the code: plan 65's `entered` string, `entered > 0`, dial-read-after-clear.

## Iteration 1

### Phase 1: the GPS-only tile rule, the payload, the tests (@developer)

1. [x] Apply D-1 and rewrite the doc comment above `metricKeysByKind` — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` · `fields` / `metricKeys` / `metricKeysByKind`
2. [x] Apply D-3 and D-6: delete the `entered` branch and every plan-65 dial comment (l.~241, ~754, ~1072-1087) — same file · `windowPayload(loggedAt:coversDistance:)`
3. [x] Create S-16001..S-16010, S-16012 (Crown half), S-16013; delete `WatchHandDistanceTests.swift` — `watch/watchos/Tests/WatchSessionEngineTests/WatchGpsDistanceTileTests.swift`
4. [x] Edit the existing tests per the D-9 table (except the comment-only rows) — `WatchLoggingSurfacesTests.swift`, `WatchSensorRecordingTests.swift`, `WatchCrownArmingTests.swift`, `WatchCaptureContractTests.swift`
5. [x] Comment sweep: `grep -rn "plan 65" watch/watchos` returns nothing — rewrite to the D-1 rule in `WatchLoggingStatusTests.swift`, `WatchTimedWorkTests.swift`, `WatchBodyweightLoadTests.swift`, `WatchCrownArmingTests.swift`, `WatchSensorRecordingTests.swift`, `WatchCaptureContractTests.swift`, `WatchLoggingSurfacesTests.swift`
6. [x] Replace the plan-65 sentence per D-7 — `watch/sync_protocol/PROTOCOL.md` ~l.193-196
7. [x] Rewrite the plan-65 paragraph per D-10 (rule of D-1/D-2/D-3/D-4, "plan 93", `WatchGpsDistanceTileTests.swift` S-16001..S-16013); `wc -c` ≤ 52,233 — `docs/state_management/watch_surface_wrist.md` ~l.361-373
8. [x] Evidence: baseline `swift-test` count before editing; red on base for S-16001, S-16006 (tile before movement), S-16013 (stash the source change, run, restore); M1-M11 table; final counts — `<plan>.evidence.md`

**Done Criteria** (run until green; Copilot uses `gateway.sh swift-test …` / `gateway.sh test …` for the same commands):
- `bash .claude/scripts/macos/with-timeout.sh 900 swift test --package-path watch/watchos --filter WatchGpsDistanceTileTests`
- `bash .claude/scripts/macos/with-timeout.sh 900 swift test --package-path watch/watchos --filter 'WatchLoggingSurfacesTests|WatchSensorRecordingTests|WatchCrownArmingTests|WatchCaptureContractTests|WatchLoggingStatusTests|WatchTimedWorkTests|WatchBodyweightLoadTests|WatchEffortDistanceTests|WatchGpsByExerciseTests|WatchDialledPerExerciseTests|SyncProtocolFixturesTests'`
- `bash .claude/scripts/macos/with-timeout.sh 900 swift test --package-path watch/watchos` (full: the append-only guard and the view scans run only here) — 0 failures; count = baseline − 13 + new tests
- `bash .claude/scripts/macos/with-timeout.sh 900 flutter test test/distance_source_import_test.dart test/session_summary_distance_test.dart test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`
- `grep -rn '"entered"' watch/watchos/Sources` empty; `grep -rn "plan 65\|WatchHandDistanceTests\|testS9503" watch/watchos docs/state_management` empty; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty; `wc -c docs/state_management/watch_surface_wrist.md` ≤ 52233

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`; `watch/watchos/Tests/WatchSessionEngineTests/WatchGpsDistanceTileTests.swift` (new); `…/WatchHandDistanceTests.swift` (deleted); `…/WatchLoggingSurfacesTests.swift`, `…/WatchSensorRecordingTests.swift`, `…/WatchCrownArmingTests.swift`, `…/WatchCaptureContractTests.swift`, `…/WatchLoggingStatusTests.swift`, `…/WatchTimedWorkTests.swift`, `…/WatchBodyweightLoadTests.swift`; `watch/sync_protocol/PROTOCOL.md`; `docs/state_management/watch_surface_wrist.md`; this plan; `<plan>.evidence.md`. Nothing else.

### Phase 2: the read-only tile's look and the owner QA step (@developer)

1. [ ] Apply D-5 — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift` · `row(_:)`, `tile(_:)`
2. [ ] Add S-16011 (red on base) — `WatchGpsDistanceTileTests.swift`
3. [ ] Add "drawn without − / +" to the Phase 1 paragraph, cutting words elsewhere in it to stay ≤ 52,233 bytes — `docs/state_management/watch_surface_wrist.md`
4. [ ] Rewrite step 27 — `docs/watch-app-setup-and-qa.md` l.700-711. Title: "A run shows its distance only once GPS has measured it — (owner)." Content: Free workout, add a run or row, Start: only the clock and Log, no tile, the Crown changes nothing (S-16001, S-16012); indoors or with Location refused, Log, sync, phone Session Summary DISTANCE row reads `—`, tap it, enter 5.00 km, the session shows 5.00 km (`test/session_summary_distance_test.dart` S-817); outdoors on a real watch the tile appears within the first tens of metres, no − / +, this effort's distance, and the next effort starts with no tile (S-16006, S-16007, S-16011); the phone shows the metres with no "est." mark (`gps`); 40 mm: when the tile appears the Log button stays fully on screen. Replace every `WatchHandDistanceTests` / `testS9503` reference.
5. [ ] Evidence: S-16011 red on base, M12, final counts — `<plan>.evidence.md`

**Done Criteria**: the full `swift test` command of Phase 1 green; `bash .claude/scripts/macos/with-timeout.sh 900 flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green; `grep -rn "WatchHandDistanceTests\|testS9503\|S-950[0-9]\|S-9510" docs watch --exclude-dir=plans` empty; `wc -c docs/state_management/watch_surface_wrist.md` ≤ 52233. The governor runs the watch app `xcodebuild` (views compile only for watchOS).

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift`; `…/WatchGpsDistanceTileTests.swift`; `docs/state_management/watch_surface_wrist.md`; `docs/watch-app-setup-and-qa.md`; this plan; `<plan>.evidence.md`. Nothing else.

## Files Affected

Production: `WatchLoggingState.swift` (P1), `WatchLoggingView.swift` (P2) — under 60 changed lines together. Tests: new `WatchGpsDistanceTileTests.swift`; deleted `WatchHandDistanceTests.swift`; seven edited test files (P1). Docs: `PROTOCOL.md`, `watch_surface_wrist.md`, `watch-app-setup-and-qa.md`. Read-only dependents (must stay green, not edited): `WatchLoggingModel.swift`, `WatchRestView.swift`, `SyncProtocolValidator.swift`, `lib/core/services/watch_session_importer.dart`, `lib/watch/**`, `test/distance_source_import_test.dart`, `test/session_summary_distance_test.dart`.

## Notes

- Dependency graph: P1 → P2 (S-16011 lives in P1's new file). Re-order (P2 first) is possible if S-16011 moves to `WatchAccessibilitySourceTests`; no benefit, so serial.
- Intermediate state after P1: an outdoor run's tile shows with greyed − / +, exactly as today's measured tile; P2 removes them. The PR ships both.
- No legacy handling on the wrist: a stored `entered` event from a plan-65 build is re-sent and accepted unchanged (S-16014); nothing reads `distanceSource` on the wrist.
- Scope budget: one track (watch) plus a contract docs sentence riding with its consumer; 2 phases; 11 decisions; 14 scenarios; no missing prerequisite. Within budget.
- Verification by the governor: `xcodebuild` of the watch app; owner device check = QA step 27 (a real outdoor run, an indoor run, the 40 mm layout when the tile appears). A simulator look is off by default; the simulator's Features → Location → City Run can show the tile appearing if the owner asks.

## Open Items (owner)

- Q1 (pending, default applied: not now) — phone hint for wrist efforts that arrived without distance. Not in any phase (D-11).
- Q2 (pending, default applied: keep) — the grey line's session distance beside this effort's tile.
- Vetoable derived decisions: D-1 threshold `> 0` m (the first metres may read `0.0`); D-5 no − / + around the GPS tile.

## Progress

- [x] Phase 1 — **Complete**: D-1 filter in `metricKeys`, `entered` branch deleted; 12 new tests red on base (9 red), green; full `swift test` 1138/0 failures (1140 − 14 + 12); flutter +81 all passed; M1-M11 killed except M5b (equivalent); doc 52209 B. Evidence file.
- [ ] Phase 2 — not started

## Assumption Log

- A-1 (P1) `WatchHandDistanceTests` held 14 tests, not 13: Done Criteria count is 1140 − 14 + 12 = 1138.
- A-2 (P1) D-1 mechanic: `metricKeys` drops `distance` unless `isMeasured`; one line, so `fields`, `adjust`, the model and `value(of:)` all see it.
- A-3 (P1) M5 round half is equivalent (no Start window, `fields` empty while a period runs); M3 cannot redden S-16003 (no in-window sample). Detail in evidence.

## Feedback
