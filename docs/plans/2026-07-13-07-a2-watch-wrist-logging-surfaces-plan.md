# Feature: Wrist Logging Surfaces for All Effort Kinds

> **Tier 2 — Watch foundation. Launch-critical on both watch platforms.**
> Platforms: native watchOS (first) and Flutter Wear OS (to identical
> behaviour in the same working context).
> Depends on:
> - [watch-phone-sync-protocol](./watch-phone-sync-protocol-plan.md)
>   (item 5) — gate.
> - [watch-session-engine](./watch-session-engine-plan.md) (item 6) —
>   provides the persistence and timer derivation this UI consumes.
> Last reconciled against source: 2026-07-13.

## Overview

The phone renders four effort kinds during a session — sets (reps +
load), timed (duration, optional distance), rounds (round counter +
countdown), and holds / drills (hold duration + extra load) — and the
watch gets wrist-sized versions of all four, because the product
commitment is live tracking of any exercise through any modality. The
wrist hardware offers better input than the phone for the core
interaction: rotary input (Digital Crown, rotary bezel) for value
adjustment, and haptics for timer events that don't require looking.
The instrument-panel philosophy carries over intact — the log action
is primary and dominant, everything else secondary, legible mid-workout.

## Requirements

- Each of the four effort kinds (set, timed, round, hold / drill) can
  be logged end to end on both watch platforms, with emitted
  observations identical in shape to phone-logged equivalents.
- Value adjustment uses the platform's rotary hardware (Digital Crown
  / rotary input) as the primary mechanism, with touch fallback.
- The primary log action is the largest, most reachable control on
  every logging screen; logging must be possible in one glance and one
  confirm.
- Rest timers start after logging where the effort kind uses one, with
  a haptic at completion; round countdowns fire a haptic at round
  end. All timers derive from timestamps and remain correct when the
  app is backgrounded.
- Terminology follows the same modality configuration as the phone
  (for example "round" versus "period"), so the watch never
  contradicts the phone's language.
- Manual distance entry is supported for distance-capable work; GPS is
  a separate item and must not block manual entry.
- Screens are legible mid-workout: high contrast, large numerals,
  minimal chrome.
- Out of scope: session structure editing, exercise browsing /
  search, sensor data, phone mirroring.

## Acceptance Criteria

- [ ] Each of the four effort kinds can be logged end to end on both
      watch platforms.
- [ ] Resulting observations are identical in shape to phone-logged
      equivalents, validated against protocol fixtures.
- [ ] Rotary input adjusts reps, load, duration, and extra load with
      sensible stepping per metric.
- [ ] Rest and round timers fire haptics at the correct wall-clock
      moment even when the app was backgrounded, verified with the
      screen off.
- [ ] Logging a set requires no more than two deliberate interactions
      from the value screen.
- [ ] Modality terminology on the watch matches the phone for every
      seeded modality.
- [ ] Manual distance entry is available for distance-capable work;
      absence of GPS does not block it.
- [ ] No banned-framings strings appear in any new surface (per the
      instrument-panel philosophy).

## Scenarios

### S-001: Log a set (reps + load)
- Trigger: User is on a resistance exercise; the value screen is
  open.
- Precondition: Effort kind = set; metric ids = reps + load.
- Flow: Rotary adjusts reps → rotary adjusts load → user taps Log.
- Expected outcome: A set observation is persisted and emitted per
  the protocol; the next set is presented with sensible carry-over
  values (e.g. last weight).
- Edge case of: none

### S-002: Log timed work (duration, optional distance)
- Trigger: User is on a timed exercise; the value screen is open.
- Precondition: Effort kind = timed; metric ids = duration (and
  optionally distance).
- Flow: Rotary adjusts duration → rotary adjusts distance if
  applicable → user taps Log.
- Expected outcome: A timed observation is persisted and emitted per
  the protocol; the next effort presents a fresh duration value.
- Edge case of: none

### S-003: Log a round
- Trigger: User is on a round-based exercise.
- Precondition: Effort kind = round; modality config provides a
  round duration.
- Flow: Round countdown fires automatically → haptic on round end →
  user taps Log → round counter increments → next round begins or
  exercise completes.
- Expected outcome: A round observation is persisted and emitted per
  the protocol; the round counter and the next countdown are
  timestamp-derived so a backgrounded app still fires the haptic at
  the right wall-clock moment.
- Edge case of: none

### S-004: Log a hold / drill
- Trigger: User is on an isometric exercise.
- Precondition: Effort kind = hold / drill; metric ids = hold
  duration (+ optional extra load).
- Flow: Rotary adjusts hold duration → rotary adjusts extra load if
  applicable → user taps Log.
- Expected outcome: A hold observation is persisted and emitted per
  the protocol.
- Edge case of: none

### S-005: Rest timer with screen-off haptic
- Trigger: User logs a set; rest timer starts.
- Precondition: Effort kind uses a rest timer; watch is on the
  wrist with screen allowed to sleep.
- Flow: App backgrounded after logging → rest period elapses →
  timer fires.
- Expected outcome: Haptic fires at the correct wall-clock moment
  based on the timer's `startedAt` timestamp, not based on a local
  counter.
- Edge case of: S-001

### S-006: Manual distance entry without GPS
- Trigger: User is on a distance-capable exercise with no GPS fix.
- Precondition: GPS is unavailable (indoor, denied, or just not yet
  fixed) but the effort kind accepts manual distance.
- Flow: User adjusts distance via rotary → user taps Log.
- Expected outcome: Observation is persisted with the manual
  distance value; no GPS dependency.
- Edge case of: S-002

### S-007: Metric stepping matches metric semantics
- Trigger: User rotates the crown.
- Precondition: Metric id and unit preference.
- Flow: Rotary event → value increments.
- Expected outcome: Stepping follows the metric's own semantics and the
  saved unit preference: reps and rounds step by 1, load steps by 2.5 kg
  or 5 lb, duration steps by 5s, distance steps by a tenth of the
  display unit. The table is pinned in
  `watch/contract/watch_logging_contract.json`, which both clients read.
- Edge case of: S-001, S-002, S-004

### S-008: Terminology parity with the phone
- Trigger: User reads a watch logging surface.
- Precondition: Modality configuration exists on the phone.
- Flow: Compare watch terminology against the phone's modality
  configuration for the same modality.
- Expected outcome: Identical term used (e.g. "round" vs "period"
  chosen once and applied to both surfaces).
- Edge case of: S-001 … S-004

## Iteration 1

### DB Changes

None. Logging surfaces emit observations through the engine from item
6; no new persistence.

### Backend Changes

- A presentation-state layer that derives the value-screen state from
  the engine (current effort, current metric values, last-value
  carry-over) and routes user input through the engine's
  `appendObservation` API.
- Haptic scheduling built on top of the engine's timestamp-derived
  timer state. Haptic fires when `now >= timer.startedAt +
  timer.durationMs + accumulatedPauseMs`, regardless of foreground /
  background — a pause postpones the instant by exactly the pause
  bookkeeping the record carries.
- Metric-step resolution helper. The step table lives in
  `lib/watch/logging/watch_metric_stepping.dart` and is mirrored in
  `WatchMetricStepping.swift`, with both held to
  `watch/contract/watch_logging_contract.json`.

### Frontend Changes

- Four logging surfaces (set / timed / round / hold) per platform,
  consuming the engine. Largest, most reachable control = Log. High
  contrast; large numerals; minimal chrome.
- Rotary input: Digital Crown on watchOS; rotary / drag input on
  Wear OS. Touch fallback on both.
- Haptic integration: native `WKInterfaceDevice.current().play(_:)` on
  watchOS; Android `Vibrator` / `VibrationEffect` (or Flutter
  equivalent) on Wear OS.

### Implementation Steps

1. Define the value-screen state model and the rotary-step mapping
   per metric.
2. Build the four surfaces on watchOS first.
3. Port to Wear OS to identical behaviour in the same working context.
4. Wire haptic scheduling on both platforms; verify with a
   timestamp-driven test that fires at the correct wall-clock moment.
5. Wire protocol fixture validation for every emitted observation.
6. Run the shared fixture suite on both platforms.

### Platform Notes

- **watchOS (native)**: SwiftUI views; Digital Crown via
  `DigitalCrownRotation`. Haptics via `WKInterfaceDevice`.
- **Wear OS (Flutter)**: Flutter widgets; rotary input via the
  platform's rotary events (or drag fallback). Haptics via the
  Flutter haptic plugin.
- Visual styling on both platforms draws from the shared design
  tokens documented in `docs/design_system.md`; typography and
  spacing are token-driven so a theme update on one propagates to
  the other through the shared constants.

## Unit Tests Required

- `test/watch_logging_surfaces_test.dart` (Wear OS) — given a UI state,
  the emitted event matches the protocol fixtures for each effort
  kind (set, timed, round, hold).
- `test/watch_logging_timers_test.dart` — timestamp-based derivation
  of remaining time across simulated background / foreground
  transitions; assert haptic fires at the correct wall-clock moment.
- `test/watch_logging_stepping_test.dart` — metric stepping logic
  (increments per metric and unit preference).
- `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift`
  (watchOS) — same fixture-driven observation tests; same timer tests.
- `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`
  — same timestamp derivation tests.

## Progress

- [x] TDD: tests authored, red run recorded
- [x] Phase 1 — Data Layer (N/A — engine from item 6; the only data change is two additive protocol fields, below)
- [x] Phase 2 — Logic & UI (state + four surfaces + haptics)
- [x] Phase 3 — Code Review (no criticals; warnings actioned, plan errors corrected — see Feedback)
- [x] Behaviour parity verified across watchOS + Wear OS

## Feedback

_(empty — fold contents into a new `## Iteration N` block if blocked.)_

### Phase 0 Complete ✓

Red run recorded. The three Wear OS test files
(`test/watch_logging_stepping_test.dart`, `test/watch_logging_timers_test.dart`,
`test/watch_logging_surfaces_test.dart`) fail entirely on missing
implementation — `lib/watch/logging/` does not exist and `UnitFormatter` has no
unit-string conversion helpers — rather than on anything in the harness. The
event-shape assertions in `watch_logging_surfaces_test.dart` validate against the
shared schemas in `watch/sync_protocol/schemas/`, read from the repository.

### Phase 2 Complete ✓

Implementation done. All Phase 0 tests green on both platforms: Dart 42 new
cases (full suite 2574 passed / 1 skipped); Swift 37 new cases over
`WatchLoggingTimersTests` and `WatchLoggingSurfacesTests` (module total 55/55),
plus a `swiftc -typecheck` pass against the watchOS 26 SDK for the platform-only
view and a web build of the Wear OS entry point. Ready for Code Reviewer.

**One additive protocol change.** A set's load, a hold's extra load, and manual
distance had no field to travel in, so `$defs.entry` gained `distanceMeters` and
`extraLoadKg` (optional, with `minimum`/no bound respectively), a new valid
fixture `fixtures/valid/observations_up_distance_and_load.json` pins the shape,
and `PROTOCOL.md` records the rule that GPS never gates an entry. Nothing was
removed or retyped: v1 clients that never read these fields are unaffected,
which is why this is not a version bump.

**Documented divergence.** Native rotation is not implementable in this
module's test harness — `DigitalCrownRotation` and `WKInterfaceDevice` exist only
on watchOS — so the SwiftUI view is compiled only into a watch target while the
rule it drives (`WatchLoggingModel`, `WatchMetricStepping`,
`WatchTimerHaptics`) is platform-independent and covered by `swift test`.

### Phase 3 Code Review — findings actioned (2026-09-20)

Review raised no criticals. The plan's own errors were corrected in place
rather than treated as implementation defects:

1. **S-007 named two sources that do not exist.** `MetricDefinition`
   (`lib/data/models/models.dart`) has no `step` field, and `SettingsState` has
   no weight or distance increment preference. The scenario now states the
   behaviour directly and points at the pinned contract. A per-user increment
   preference is still unowned — see the open item below.
2. **S-005's haptic formula had the wrong sign.** Corrected to
   `+ accumulatedPauseMs`.
3. **`Unit Tests Required` listed paths that were never created.** Corrected to
   the delivered paths under `watch/watchos/Tests/WatchSessionEngineTests/`.

**Actioned:**

- **Mirror constants are now pinned.** `watch/contract/watch_logging_contract.json`
  carries the stepping table, the conversion constants, the metric-key list, the
  capability→effort-kind precedence and the round terminology. Both suites read
  it: the Flutter one pins its canonical owners (`UnitFormatter`,
  `ModalityDisplay`, `ModalityConfig`) against it, the watchOS one pins its
  mirrors. A change on either platform now fails the other's tests.
- **Dead declarations removed:** `SilentWatchHaptics`, `SilentHaptics`,
  `WatchLoggingView.pointsPerDetent`. The screen's `haptics:` parameter is now
  exercised instead of merely existing — a widget test injects a recording
  channel, logs a set, advances the clock past the rest countdown and asserts the
  resumed surface hands the owed haptic to the injected channel.
- **Banned-framings audit widened** to `lib/watch/debug/` and
  `WatchLoggingView.swift`, which is what "any new surface" means. Both were
  already clean.
- **`Package.swift`'s header corrected** — the UI ships in the package.
- **Layout literals named:** `surfaceInset`, `surfaceInsetCompact`,
  `stepIconSize` on the Flutter side, `crownRangeDetents` and `surfaceInset` on
  the Swift side, each carrying the wrist-scale rationale. The primary CTA keeps
  `minimumSize` over the prescribed `SizedBox` wrapper, and says why.
- **Test gaps filled:** `OmniDateUtils.formatClock` (four cases including the
  hour rollover and the past-due clamp), the Dart sub-detent rotary carry, and
  `completionInstant`'s null branch.

**Open — needs an owner, not a code change:**

- Does the user get to choose their load increment? The plan assumed a
  `SettingsState` preference that does not exist, and the contract now hardcodes
  2.5 kg / 5 lb. If that should be configurable, it is a settings feature with
  its own scenarios, not a watch item.
