# Evidence — plan 50a (the phone's rest reaches the watch)

Proof date: 2026-10-21 (lead: unit tests, mutation pass). Docs and evidence: docs keeper, 2026-10-21.

## Test table (scenario → test → file)

The push tests run the shipping graph over a fake radio with the real Dart wrist engine applying every frame; the rest scenarios live in `test/watch_timer_push_test.dart` beside the work-timer groups (the harness is shared by import, so no separate file was needed).

| Scenario | Test (group · test) | File |
|---|---|---|
| S-7301 an open phone rest travels as one `timer_state` frame with no slot and no planned length; the newest open rest across the efforts is the one composed | `S-7301 the phone's open rest reaches the wrist` · `S-7301 an open rest travels as one timer_state frame with no slot and no planned length`, `S-7301 the newest open rest across the phone's efforts is the one composed` | `test/watch_timer_push_test.dart` |
| S-7302 pausing sends the paused stamp; resuming sends the accumulated pause | `S-7302 a pause and a resume travel with their bookkeeping` · `S-7302 pausing sends the rest's paused stamp and resuming sends the pause accumulated so far` | same file |
| S-7303 closing the rest (the next set) sends `{rest: null}` once | `S-7303 closing the rest clears it on the wrist` · `S-7303 the next set closes the rest and one frame with a null rest stops the wrist's` | same file |
| S-7304 the wrist's own rest started within 2000 ms is the same rest (nothing sent); the phone closing it sends the clear | `S-7304 the wrist's own rest a moment later is the same rest` · `S-7304 a running rest the wrist started 800 ms after ours is identical, so nothing is sent`, `S-7304 closing the rest the wrist is holding sends the clear` | same file |
| S-7305 the wrist ended its own rest first: the close clears nothing | `S-7305 the wrist ended its own rest first` · `S-7305 a mirror rest that is already stopped is not cleared when the phone's rest closes` | same file |
| S-7306 a rest outside the tolerance is a different rest: ours is sent | `S-7306 a rest started outside the tolerance is a different rest` · `S-7306 the mirror's rest started 5 s earlier does not stop ours being sent` | same file |
| S-7307 an undelivered rest frame is re-offered | `S-7307 a rest frame the radio did not carry is owed` · `S-7307 an undelivered rest frame leaves the ledger as it was and is offered again` | same file |
| S-7308 end to end in the real Dart wrist engine: resting from the phone's instant, stopped by the clear | `S-7308 the real wrist engine rests from the phone instant` · `S-7308 after the frame the engine is resting and counts up from T; the clear stops it` | same file |
| S-7309 work timers unaffected: an elapsed timer and a rest travel as one frame | `S-7309 work timers are unaffected` · `S-7309 an elapsed timer and a rest in one pass travel as one frame with both kinds` | same file |
| S-7310 a snapshot the phone composes carries the delivered rest | `S-7310 a snapshot the phone composes carries the delivered rest` · `S-7310 the rest the phone delivered rides the next projected snapshot` | same file |

Count: 12 tests across 10 groups (S-7301 has two tests).

## Verified

- The tests above green (lead, 2026-10-21).
- Governor mutation pass over the series: 12 of 12 mutants red.
- `TimerManager.inProgressRest` / `InProgressRest` and `WorkoutState.inProgressRest()` exist in the working tree (seen this run).

## Not verified

- The two devices live: the Simulator could not be driven. Owner checks: rest both ways, including the phone's pause freezing the watch's rest.

## Docs

- `docs/state_management/watch_surface.md`, `WatchTimerPush` paragraph: the push now composes the phone's open rest as a `rest` timer (no slot, no planned length, `{rest: null}` on close, the 2000 ms same-rest rule) and cites S-7301..S-7310.
- `docs/rest_tracking.md`, "The Wrist's Rest": the rest travels both ways while it runs, with the cross-device rules and both test citations.
