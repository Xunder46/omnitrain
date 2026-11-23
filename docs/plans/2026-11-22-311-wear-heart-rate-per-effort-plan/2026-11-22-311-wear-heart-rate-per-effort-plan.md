# Plan 311 — The Wear wrist sends heart rate on each timed, round and hold entry, and a round's paused time (series 310-314) — OUTLINE, not yet seeded for building

Status: outline. Depends on plan 310 (the `heartRate` and `blockSpans` summaries). Complete the Decision Ledger, fixtures and Docs delta (and run `plan-lint.ps1 before`) before the first brief.

## What the review found

The Apple wrist stamps each effort it logs with what it measured over that effort's own window, at log time (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` `sensorSummary(of:)` 1360-1397 and `metricPayload` 1211-1250): a timed entry gets `avgHeartRateBpm`/`maxHeartRateBpm` (and steps, which the Wear wrist cannot measure); a hold gets the heart-rate pair; a round gets the pair over its window with the time its countdown was paused left out, plus `pausedMs` (the countdown's pause, capped at the window). A set carries nothing. The Dart wrist (`lib/watch/logging/watch_logging_state.dart`, `metricPayload`) sends none of it: no heart rate on any effort and no `pausedMs` on a round (`grep -rn pausedMs lib/watch` finds nothing). The phone reads all of it for any wrist.

## Goal (draft)

A timed, hold or round entry logged on a Wear watch carries the heart-rate pair over its own window when readings exist; a round leaves its paused stretches out of the pair and carries `pausedMs` when it was paused; nothing is sent when nothing was measured. Sets stay bare.

## Decisions to take when seeding (technical, mine)

- Port `WatchSensorSummaries.pauses(of:startedAt:windowEnd:)` and `pausedMs(countdown, windowStart:, windowEnd:)` and add an `excluding` parameter to `heartRate` (half-open pause intervals `[start, end)`), from `WatchSensorSummaries.swift` 199-252.
- A `sensorSummary` step in the Dart `WatchLoggingState.log` path, computed at log time over the event's own `startedAt`/`endedAt`, using the engine's stored samples and `timerRows(round)` (check the Dart engine exposes the round timer's rows, or add the accessor).
- Guard against drift for good: replay `watch/contract/watch_capture_contract.json` (the shared capture contract, which the Swift suite already replays and the Dart wrist has never been held to) through the Dart engine, case by case, for the heart-rate and pause cases (`watch_capture_contract_conformance_test.dart` is the phone-side reader to copy from). If a case cannot be replayed in one phase, split it into its own plan.
- Out of scope: steps (no Wear step source); anything on the phone.

## Owner questions

None expected: the Apple behaviour is the contract ("match the Apple watch where possible").
