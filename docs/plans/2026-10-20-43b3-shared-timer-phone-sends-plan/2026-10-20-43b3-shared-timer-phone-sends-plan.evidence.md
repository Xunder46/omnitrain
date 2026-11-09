# Evidence — plan 43b3 (the phone sends its timers)

Proof date: 2026-10-20 (lead). Docs and evidence: docs keeper, 2026-10-20.

## Baselines

- `flutter analyze`: 181 issues before and after (lead; no new notices).
- Full `flutter test`, `swift test` and the watch app build: re-run by the lead at the end of the plan (pending when this evidence was written).
- Docs contract: `flutter test test/docs_indexing_contract_test.dart` — 13 tests, all passed (docs keeper, 2026-10-20), including `no documentation file is within the warning band of the ceiling`, so `watch_surface.md` stayed under the band after its addition.

## Test table (scenario → test → file)

The push tests run the shipping graph (`createWatchSync`) over a fake radio with the real Dart wrist engine applying every frame.

| Scenario | Test | File |
|---|---|---|
| S-6201 `inProgressWorkTimers()`: an active timed interval lists one `elapsed` timer with the right fields; paused carries `pausedAtMs` and a resume its accumulated pause; notStarted and finished list nothing; a drill lists `hold`; a round lists `round` with `plannedDurationMs`; two efforts in progress list only the newer start; kinds are ordered by wire kind; a `set` effort lists nothing; an inactive session lists nothing | group `WorkoutState.inProgressWorkTimers (Mock)`: `S-6201 an active timed interval lists one elapsed timer`, `a paused interval carries pausedAtMs and a resume its pause`, `notStarted and finished intervals list nothing`, `a drill effort lists a hold timer`, `a round lists a round timer with its planned duration in ms`, `two timed efforts in progress list only the newer start`, `kinds are ordered by wire kind name`, `a set effort lists nothing`, `a session that is not active lists nothing` (9 tests) | `test/in_progress_work_timers_test.dart` |
| S-6211 a started interval travels as one `timer_state` frame, with its slot, running state and `startedAt`; a second pass with no change sends nothing; a hold and a round carry their kind and length | group `S-6211 a started interval travels as one timer_state frame`: `S-6211 the interval is sent once, with its slot, running state and startedAt, it validates, and the wrist starts its timer from it`, `S-6211 a hold and a round carry their kind and length` | `test/watch_timer_push_test.dart` |
| S-6212 pause then resume travel with their bookkeeping, and the wrist reads them back | group `S-6212 a pause and a resume travel with their bookkeeping`: `S-6212 pausing sends the paused stamp and resuming sends the pause accumulated so far, which the wrist reads back` | `test/watch_timer_push_test.dart` |
| S-6213 logging the interval sends `{elapsed: null}` once, the wrist stops the timer, and a delivered clear is not sent twice | group `S-6213 finishing the interval clears it on the wrist`: `S-6213 the finished interval is sent as a cleared elapsed timer, and the wrist stops the timer it had` | `test/watch_timer_push_test.dart` |
| S-6214 the wrist's own timer is not overwritten or echoed: a later phone start for the same slot sends nothing; a timer the mirror already holds equal to the phone's sends nothing; a timer both sides hold field for field is not sent; the same instant with the phone paused is sent; an earlier wrist timer for ANOTHER exercise does not stop the phone's start | group `S-6214 the wrist's earlier timer is not overwritten or echoed`: `S-6214 a phone start later than the timer the wrist holds for the same slot sends nothing`, `S-6214 a timer the mirror already holds equal to the phone's own sends nothing`, `S-6214 a timer the wrist already holds exactly as the phone has it is not sent`, `S-6214 the same instant with the phone paused is sent`, `S-6214 an earlier wrist timer for ANOTHER exercise does not stop the phone's start from being sent` (5 tests) | `test/watch_timer_push_test.dart` |
| S-6215 an undelivered frame is re-offered at the next pass and stops once delivered | group `S-6215 an undelivered frame is re-offered`: `S-6215 the first send answers not-delivered, the next pass offers it again, and once delivered it stops` | `test/watch_timer_push_test.dart` |
| S-6216 the negative guards: an inactive session sends nothing and clears the ledger; a `set` effort contributes no frame; an unbound push sends nothing until bound | group `S-6216 the negative guards`: `S-6216 an inactive session sends nothing and clears the ledger`, `S-6216 a set effort contributes no timer frame`, `S-6216 an unbound push sends nothing` | `test/watch_timer_push_test.dart` |
| S-6217 (D-2b) a new interval replacing a delivered one: the clear is its own frame before the new timer, and the wrist ends on the new timer | group `S-6217 a new interval replacing a delivered one`: `S-6217 the replaced interval is cleared in its own frame before the new one, and the wrist ends on the new timer` | `test/watch_timer_push_test.dart` |

Count: 9 + 14 = 23 tests across the two files.

## Mutations

Per the lead's proof (2026-10-20): 17 mutations of `WatchTimerPush` and `LiveSessionMirrorState.sendTimers` were applied by hand. 14 made a named test red at once. The 3 the first round did not reach — the same-state echo arm of D-3b, the slot-equality line of the echo guard, and the ledger removal after a delivered clear — went red after a tests-only gap round. All mutants were restored byte for byte. The per-mutation list was kept in the lead's run; it was not handed to this run and is not reproduced here.

## Design additions recorded at build (2026-10-20, in the plan's Decision Ledger)

- **D-2b** — a new interval started right after the previous one finished inside one debounce window sends TWO frames in order: `{kind: null}` then the new timer, because the wrist (43b1 D-4) ignores a later start while it still holds the earlier, not-stopped timer of the same kind and slot. An undelivered frame stops the pass; nothing after it is sent.
- **D-3b** (precise echo rule) — a kind is skipped when the mirror (only when `mirror.sessionId` is the phone's session) holds the same slot, not stopped, and either every one of state, startedAt, pausedAt, accumulatedPauseMs equals ours (instants compared, not strings) or its startedAt is EARLIER than ours. A skipped kind is not recorded as delivered, so a pause on the phone after an adopted earlier start still goes out.

## Dropped phase

- **P3 (Swift, S-6221) dropped.** 43b1's S-6004/S-6005 (`watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift`) already cover the wrist-side rules — a message timer for another slot is hidden, the earlier start wins — and the shipping-graph tests in `test/watch_timer_push_test.dart` apply every frame the push builds through the real Dart wrist engine, so the end-to-end behaviour is covered without copying a fixture into a Swift test.

## Pending

- `crew-reviewer` review of the built code and the docs.
- Owner device checks (the plan's two owner checks: same-exercise start/pause/log, and both-devices start with the earlier start standing).
- The lead's end-of-plan full `flutter test`, `swift test` and watch app build re-runs.
