# Plan 98 — phone ↔ watch live sync audit

Status: F-1 and F-2 built, mutation-proved and reviewed (2026-11-02), uncommitted. Owner approved fixing F-1 and F-2 ("Yes, fix both"); F-3 and F-4 are not in this plan.
Base commit: `cafc9a61`. Branch: `claude_develop`.

## Goal

The owner saw four things on a real phone + watch pair (2026-11-02). Find out, from code and from
reproductions against the shipping phone wiring (`createWatchSync`), which are real defects and why.

| # | What the owner saw |
|---|---|
| O-1 | Started a cardio timer on the phone. The watch showed 0 with Start available. |
| O-2 | A rest the watch was running kept running after the phone started another exercise's timer. |
| O-3 | The owner could finish that rest and start a new exercise timer on the watch while the phone's timer ran. |
| O-4 | Finished a session on the phone; the watch still let the owner finish it and log the effort, and none of it recorded. |
| O-5 | The watch's Smart Stack showed an "OmniTrain timer" running, about 30 s behind. |

## Findings

**F-1 (explains O-1, O-3). A phone timer the watch did not receive is never sent again, and a wrist
raise does not fetch it.** Evidence: probes A1, A2, A3 below fail on the current code.
- `timer_state` is live-only: sent while the watch is not reachable it answers `undelivered`, is not
  queued (`lib/core/platform/watch_transport.dart:346-358`; pinned by `test/watch_transport_test.dart`
  `S-6811`).
- The timer push runs only when the phone's own state notifies (`watch_timer_push.dart:205`) and, on a
  frame from the wrist, as `flushClears()`, which withholds every start (`watch_timer_push.dart:338`,
  plan 54 D-1). Nothing listens for the watch becoming reachable again (only the Settings status row
  does: `watch_link_state.dart:97`), and the app-resume sync (`watch_sync_wiring.dart:142`) sends the
  session, not the timers.
- The answer to a wrist raise (Sync) carries only timers the push already *delivered*
  (`deliveredTimers()`, `watch_sync_wiring.dart:265-272`). A start that was never delivered is absent,
  so the answer says "no timers" and the watch keeps 0 and Start (probe A1: the answer was
  `session_snapshot timers={}`).
- Once the watch shows Start, a start on the wrist makes a second clock. The phone keeps its earlier
  one (earlier start wins) and never tells the wrist, so two clocks run for one exercise (probe A3).
- No test drives "undelivered start, then the watch asks or becomes reachable"
  (`test/watch_timer_push_test.dart` S-6215 re-offers by calling `flush()` by hand).

**F-2 (explains O-2). Starting a timer on a different exercise does not end the rest on the watch,
even when the watch is reachable.** Evidence: probe B1 fails on the current code.
- The phone closes only the open rests of the exercise the timer starts on
  (`timer_manager.dart:537`, `906`, `closeAllOpenRestsInMemory` at `1414`). A rest still open on the
  previous exercise is the phone's "in-progress rest" (`timer_manager.dart:245`), so the push keeps
  composing it and sends no `{rest: null}`; the frame for the new timer names no `rest` key, and the
  watch leaves a kind alone when its key is absent (`WatchSessionEngine.swift:792-801`).
- The watch ends its own rest when the *watch* starts work (`WatchLoggingState.swift` `startWork`,
  plan D-1311). There is no equivalent for a work timer the phone starts.
- Same-exercise case: the clear exists (`S-7303`, `S-7304`) but is a live-only frame; when the watch is
  out of reach it is re-offered only at the next frame from the wrist or the next phone change.

**F-3 (explains O-4, partly). The phone's end of a session is told once and never owed.** Evidence:
code plus the existing test `S-217` ("a refused `completeSession()` frame is not re-offered"), which
records this as known behaviour.
- `_announceEnd` sends `completed` once through `completeSession()` and drops the pending end whatever
  the result (`watch_session_auto_push.dart:526-532`). After the end the phone composes no snapshot
  (`watch_session_adoption_bridge.dart:234` returns null for a session that is not active), so nothing
  follows. The comment at line 527 ("the next pass's snapshot carries it") is wrong; `S-217` says so.
- In production the frame is durable: an unreachable watch gets it through the OS queue
  (`watch_transport.dart:242-248`). The OS may deliver it late; the watch applies it on arrival with no
  age check (`WatchSessionEngine.swift:682`), and until then it stays active and accepts logging
  (`WatchLoggingState.swift:310` `canLog` only checks the watch's own copy).
- Healing path that works: a wrist raise asks for a Sync and the phone answers with the session as
  completed. Probe C1 PASSES: with the frame lost, the Sync answer ends the wrist's session. So O-4
  needs the watch to have stayed away from a raise-sync (not reachable at the raise, or the app kept in
  front) or the queued frame to be late. This cannot be told apart from code.
- What the phone does with what the wrist logs afterwards: sets merge into the ended session while the
  phone still holds it (`S-14`); the wrist's own Finish and effort answer change nothing on the phone
  (`watch_session_adoption_bridge.dart:766`, `S-89c1-5`), by design. So "went nowhere" for the finish and
  the effort is expected; for sets it depends on the phone having left the summary screen.

**F-4 (O-5). Not an exercise timer.** The watch opens an `HKWorkoutSession` for the whole session
(`WatchPlatformWorkout.swift:400`, `HealthKitWorkoutStore.swift:125`); that is what the system shows in
the Smart Stack. The app publishes no widget or complication (grep: none). Its clock is the workout's,
not the exercise timer's, so it can differ from the phone's by any amount.

## Not proven here (needs the owner or a device log)

- Whether the watch was reachable when each phone action happened. F-1 and the clear in F-2 assume it
  was not (wrist down). F-2's cross-exercise case does not depend on it. If the watch was in front and
  reachable for O-1, F-1 does not explain it and the next step is a log from both devices.
- How late the OS delivers a queued `session_lifecycle` (F-3).

## Evidence

Probes run against `createWatchSync` with a fake radio, the phone `WorkoutState` and the real wrist
engine twin (`test/watch_timer_push_test.dart` harness). Full probe source and run output:
`2026-11-02-98-phone-watch-live-sync-audit-plan.evidence.md`. Results on the base commit:

| Probe | Question | Result |
|---|---|---|
| A1 | Start while unreachable; wrist asks Sync | FAIL: answer carries `timers={}` |
| A2 | Start while unreachable; reachable again, nothing else | FAIL: no frame is sent |
| A3 | Wrist starts its own beside the phone's | FAIL: phone never corrects the wrist |
| B1 | Rest open on exercise A; timer starts on B (reachable) | FAIL: no `rest: null` is sent |
| C1 | Phone finishes, frame lost; wrist asks Sync | PASS: the wrist's session ends |

## Proposed fixes (not started)

1. F-1: the answer to a Sync carries the timers the phone wants the wrist to run now (composed from
   state, as `_pushOnce` does), and a wrist frame re-offers a start the wrist has never held; the
   watch becoming reachable runs one full pass. Keep plan 54 D-1a's protection: never re-send a start
   for a timer the wrist already ended. Technical; owner approval not needed beyond the plan.
2. F-2: a work timer started on any exercise ends the session's open rest on the phone and on the
   wrist. **Owner decision (behaviour):** confirm that is what a user expects.
3. F-3: make the phone's end owed (re-offer until the wrist shows it ended or answers), and have the
   watch refuse to take a log for a session it has not heard from the phone about for a long time, or
   re-ask the phone before accepting Finish. **Owner decision (behaviour):** what the watch should show
   when the phone has ended the session (a notice and a summary, or silently back to Start).
4. Add a "Sync diagnostics" line so the next report names reachability and the last frame heard.

## Assumption log

- Probes use a fake radio where `unreachable` answers `undelivered` for every frame, which is the real
  behaviour for `timer_state` and (via the OS queue) a delayed one for `session_lifecycle`.
- Scout sheets were spot-checked: sheet C's claim that the importer writes an *open* rest from a wrist
  report is wrong (`watch_session_importer.dart:1286-1291` skips rests with no end); the phone's open
  rest comes from the wrist set's arrival (plan D-6). The conclusions above do not rely on it.

## Fix phases (owner approved F-1, F-2)

Owner decision (2026-11-02): starting a timer on any exercise ends a rest that is still running.

### Decision ledger

- **D-1 (F-2).** Any work timer that starts on the phone (`startTimedEntry`, `startRound`) or is adopted
  from the wrist (`_adoptRemoteTimed`, `_adoptRemoteRound`) closes the open rests of EVERY effort of the
  session, not only its own. Today `closeAllOpenRestsInMemory(effortId)` closes one effort's. The
  per-effort helper stays (its other callers and `closeAllOpenRests` are unchanged); a new
  `closeAllOpenRestsInSessionInMemory()` in `timer_manager.dart` closes every key of `_entryRests`.
  Then `inProgressRest()` is null, the push's existing sweep sends `{rest: null}` (`watch_timer_push.dart:331`)
  and the wrist ends its rest. No wire change.
- **D-2 (F-1).** `WatchTimerPush` remembers a start it offered and the radio did not carry
  (`_owed`, per wire kind). A clears-only pass (`flushClears`, the wrist-frame trigger) keeps the starts
  whose kind is in `_owed` and withholds every other start, so plan 54 D-1a (never restart a timer the
  wrist ended) still holds: a wrist-ended timer was delivered or adopted, never owed. `_owed` is cleared
  for a kind when its frame is delivered, when the phone no longer wants that kind, and with the ledger on
  a session change. Its doc comment and `flushClears`'s say so.
- **D-3 (F-1).** The watch becoming reachable runs `timerPush.flushClears()` once, from the link-change
  stream of the transport (`WatchLinkSource.linkChanges`, `info.reachable == true`), wired in
  `createWatchSync` where the link state is built. A failure goes to `onFailure`.
- **D-4.** No change to the Sync answer: the owed start follows it in the same wrist-frame handler
  (`watch_sync_wiring.dart:359-362`), the wrist applies the answer's empty timers (nothing phone-written
  to stop) and then the start.
- **D-5 (reader check).** Readers of `flushClears`: `watch_sync_wiring.dart:361` only; tests
  `S-8406`, `S-8407`, `S-8408` in `test/watch_timer_push_test.dart`. Readers of
  `closeAllOpenRestsInMemory(String)`: `workout_state.dart:402` and `timer_manager.dart:1452`
  (`closeAllOpenRests`), both unchanged.

### Scenarios (ids S-9921..S-9930, free: `grep S-99` max was S-9916)

| id | scenario | fails today because |
|---|---|---|
| S-9921 | rest open on A; `startTimedEntry` on B closes it (in memory and in the repository) | closes only B's |
| S-9922 | same for `startRound` on B | same |
| S-9923 | same for a wrist timer adopted into B | same |
| S-9924 | wire: rest on A was delivered; timer on B starts → a frame `{rest: null}` goes first, then the `elapsed` frame; the wrist engine ends its rest | no clear is sent |
| S-9925 | start refused (unreachable), then the wrist asks (snapshot request) → the owed start is sent after the answer; the wrist engine runs it | start withheld |
| S-9926 | start refused; the wrist starts its own later `elapsed` for the same slot (frame to the phone) → the phone sends its earlier start | no correction |
| S-9927 | NOT owed stays withheld: a start the radio carried, the wrist then stopped → a wrist frame sends no start (54 D-1a); and a start never attempted is not sent by a wrist frame | (guard; passes today, must keep passing) |
| S-9928 | a start refused, then the phone no longer wants it (interval finished) → nothing is sent on the next wrist frame or reachability | (guard) |
| S-9929 | link change `reachable: true` sends the owed start; `reachable: false` sends nothing | no listener |
| S-9930 | two arms of S-9925: the owed start is a timer for kind `round` or `hold` too (one test per kind not needed: one `round`) | |

### Phases

| phase | agent | write scope | serial/parallel |
|---|---|---|---|
| P1 | crew-builder-app | `lib/state/workout/timer_manager.dart`, `test/timer_start_closes_session_rests_test.dart` (new) | first |
| P2 | crew-builder-app | `lib/state/watch/watch_timer_push.dart`, `lib/state/watch/watch_sync_wiring.dart`, `test/watch_timer_push_test.dart` | after P1 (S-9924 needs D-1) |
| P3 | crew-docs-keeper | `docs/**` | after P2 |
| P4 | crew-reviewer | review file | after P3 |

### Added during the build

- **D-6.** A clears-only pass no longer cancels the pending debounce window (`_flush`): the watch coming into
  reach inside the 250 ms after a timer start would otherwise lose that start. Found by the lead reading
  `_flush`; proved red first (S-9934).
- **D-7 (review blocker).** `_owe` never marks a timer owed when the mirror holds that very timer (same slot,
  same start) as stopped: a wrist-ended timer must not be restarted by a later wrist frame. Guards S-9927c
  (stopped copy) and S-9927d (a new interval after it is still owed).
- **S-9930b** (round arm of S-9925, review major). **S-9931..S-9934** were added by mutation findings.
- Review: `...-plan.review.md` (1 blocker, 1 major, 2 minor — all four fixed).
- Not in this plan: F-3 (the phone's end of a session is told once and not owed) and F-4 (the Smart Stack
  clock is the workout's). Both need an owner decision on what the watch shows.
