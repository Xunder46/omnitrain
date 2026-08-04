# Crash Reporting — Per-Signature Rate Limit

## Overview

OmniTrain currently forwards every error to Sentry with no ceiling. A single repeating failure recently produced ~15,000 reports from 24 users in 2 weeks, exhausting the monthly reporting budget and suppressing any genuine crash during that window. This change introduces a per-signature throttle that stops transmission past a configurable threshold and resumes after a cooldown, attaching the suppressed-occurrence count to the resumed report so high-frequency problems remain visible.

## Requirements

- Throttle applies **per failure signature** (not globally) — a noisy failure must never prevent an unrelated genuine failure from being reported.
- Threshold and cooldown are **named, configurable** values.
- Suppressed occurrences are counted **locally only** (not persisted across launches).
- After the cooldown elapses, the next transmission carries the **exact suppressed count** since the last transmission.
- Privacy contract: outgoing reports carry `appVersion`, `osVersion`, `deviceModel`, `errorContext`, plus the new `suppressedOccurrences` figure — nothing else.
- The wrapper still does no I/O / no report forwarding when `enabled: false` (debug/profile builds).
- `recordInfoSignal` is **not** throttled — those are low-severity signals explicitly excluded from the crash stream.

## Acceptance Criteria

- [ ] A signature repeated beyond the threshold stops being transmitted; exactly `threshold` reports are sent.
- [ ] Two distinct signatures throttle **independently**.
- [ ] First report after cooldown carries a `suppressedOccurrences` count equal to the number dropped since the previous transmission.
- [ ] Throttle state is reset on `resetForTests()` (does not survive a service reset).
- [ ] A signature reported below the threshold is never throttled and never carries a `suppressedOccurrences` figure.
- [ ] Threshold and cooldown are referenced from named configuration values; changing them changes observed behavior with no other edits.
- [ ] Allow-list output: `appVersion`, `osVersion`, `deviceModel`, `errorContext`, `suppressedOccurrences` (when > 0).

## Scenarios

### S-001: Single signature stops at threshold
- Trigger: `recordError` called with the same `errorContext` N times where N > threshold
- Precondition: Bootstrap completed in release mode
- Flow: Each call invokes the rate limiter; first `threshold` calls return `(true, 0)`; subsequent calls return `(false, _)`
- Expected outcome: `reporter.capturedErrors.length == threshold`
- Edge case of: none

### S-002: Two distinct signatures throttle independently
- Trigger: `recordError` called for signature A and signature B both past threshold
- Precondition: Bootstrap completed in release mode
- Flow: Each signature has its own counter; throttling A does not affect B
- Expected outcome: Both signatures transmit `threshold` reports each; neither blocks the other
- Edge case of: none

### S-003: Cooldown resumes with suppressed count
- Trigger: Signature hits threshold, additional `K` occurrences are dropped, cooldown elapses, next occurrence arrives
- Precondition: Threshold reports already sent; K drops counted; clock advanced past cooldown
- Flow: Rate limiter returns `(true, K)` on the post-cooldown call
- Expected outcome: Transmitted report metadata includes `suppressedOccurrences == K`
- Edge case of: S-001

### S-004: Service reset clears throttle state
- Trigger: Throttle state reaches threshold; `resetForTests()` is called; same signature reported again
- Precondition: A signature has been throttled
- Flow: Reset clears internal counter map; next call starts from zero
- Expected outcome: New report is transmitted with `suppressedOccurrences` absent
- Edge case of: S-001

### S-005: Below-threshold traffic is unthrottled
- Trigger: `recordError` called fewer times than threshold
- Precondition: Bootstrap completed
- Flow: Every call returns `(true, 0)`; no `suppressedOccurrences` tag attached
- Expected outcome: All calls forwarded; no metadata key named `suppressedOccurrences` ever present
- Edge case of: none

## Iteration 1

### DB Changes
None.

### Backend Changes

1. **`lib/core/services/crash_reporting_service.dart`**
   - Add `CrashReportThrottleConfig` class with `threshold` (default `100`) and `cooldown` (default `15 minutes`). Bootstrap accepts an optional `throttleConfig` parameter.
   - Add private `_CrashReportRateLimiter` class with:
     - `consider(signature) -> ({bool shouldSend, int suppressedSinceLast})`
     - Injectable `DateTime Function() clock` for deterministic tests.
     - `reset()` method.
   - `recordError`: derive signature from `${error.runtimeType}|${errorContext ?? ''}`; consult limiter; if shouldSend, attach `suppressedOccurrences` to cleaned metadata when > 0.
   - `bootstrap`: instantiate the limiter; expose via `resetForTests()` so test reset clears throttle state too.
   - Add `'suppressedOccurrences'` to `_allowedTagKeys` so `beforeSend` keeps it.

2. **`lib/main.dart`**
   - No behavioral changes needed; default threshold/cooldown apply. (Optional: surface as `--dart-define` later.)

### Frontend Changes
None.

### Implementation Steps
1. Add TDD red tests for rate limiter scenarios.
2. Update existing `recordError allow-list` test that assumes unconditional forwarding (assert forwarding below threshold only).
3. Implement `_CrashReportRateLimiter` + `CrashReportThrottleConfig`.
4. Wire rate limiter into `recordError`; update `_allowedTagKeys`.
5. Update `resetForTests` to clear throttle state.
6. Run `flutter test` — confirm green.

## Progress

- [x] Phase 0: Plan authored
- [x] Phase 1: Constants (in service file)
- [x] Phase 2.5: Red tests written and confirmed failing (5 compile errors)
- [x] Phase 2: Implementation
- [x] Phase 2: Green tests confirmed (16/16 crash_reporting_test; full suite: 2116 pass, 7 pre-existing failures in energy_tile_test.dart)
- [x] Phase 3: Code review

### Phase 2 Complete ✓

### Phase 3 Complete ✓

## Feedback

## Assumption Log

- **Signature derivation**: `${runtimeType}|${errorContext ?? ''}`. Runtime type groups same-class exceptions; errorContext groups call sites. The same exception type from different call sites yields distinct signatures — preferable since the fix surface differs.
- **Default threshold**: 100 occurrences per signature. Tuned to budget: at current Sentry plan, 100 reports × 24 users × N distinct signatures still leaves headroom.
- **Default cooldown**: 15 minutes. Short enough that the dashboard reflects regression within a quarter-hour; long enough that the budget is protected across a typical release cycle.
- **`recordInfoSignal` is not throttled** — those signals are explicitly low-severity / informational, already excluded from the crash stream.

### Phase 0 Complete ✓
