# Fix: 48 — the auto-push S-144 test no longer depends on the real clock

> Status: BUILT AND PROVED 2026-10-21 (20 consecutive runs of the file green, formerly about 1 in 3 red; full flutter +5379 ~2; the finish-clock mutation turns S-7001 red) (owner: "fix the S-144 flaky test with an injected clock, as its own small unit"). Base: `.work/2026-10-21-48/base.txt`.
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md

## Cause (found by the lead, 2026-10-21)

`test/watch_session_auto_push_test.dart` S-144 starts and finishes a phone timed entry and a round back to back. `TimerManager.startTimedEntry`/`finishTimedEntry` (and the round pair) stamp with `DateTime.now()`. `PhoneEntries._window` (`lib/core/sync_protocol/phone_entries.dart:392`) carries no window when `finishedAtMs <= startedAtMs`, so when both stamps fall in the same millisecond the entry (`entry-sx-4-0`) is left out of the snapshot and the assertion on the wrist's entry ids fails: about one run in three.

## Decisions

- D-1 Use the clock seam `TimerManager` already has (`DateTime Function()? clock`, default `DateTime.now`, `timer_manager.dart:118`, so far used for ids and stamps only): `startTimedEntry`, `finishTimedEntry`, `startRound`, `completeRound` read `_clock()` instead of `DateTime.now()` (only those four methods; behaviour with the default clock is identical). `WorkoutState` gains an optional `DateTime Function()? clock` constructor parameter passed to `TimerManager`.
- D-2 The S-144 test builds `phoneState` with a ticking clock: real time, but strictly increasing by at least 1 ms per read, so a finish is always after its start.
- D-3 Out of scope: the other 19 `DateTime.now()` reads in `TimerManager`; any change to `PhoneEntries` (the omission rule is correct: a window of no length is no window).

## Scenarios (ids S-7001.. checked free)

- S-7001 `TimerManager` with a frozen clock: `startTimedEntry` then `finishTimedEntry` stamp `startedAtMs` and `finishedAtMs` from the injected clock (both equal the frozen instant); same for `startRound` / `completeRound` (`startedAtMs` and `finishedAtMs`). Red before D-1 (they read the real clock). One test per method (four).
- S-7002 S-144 and its sibling cases in `test/watch_session_auto_push_test.dart` pass with the ticking clock on 20 consecutive runs of the file (the governor runs the loop).
- Mutation for the lead: put `DateTime.now()` back in `finishTimedEntry` -> S-7001 red.
