# Feature: 64 — a set you log on the phone is not lost when the watch sends something a moment later

> Status: BUILT, PROVED, DOCUMENTED AND REVIEWED 2026-10-23 (uncommitted; owner device check open); the defect was PROVEN on the current code (repro below). Owner: watch audit 3 (2026-10-23), fix order item 8 ("first a test to show whether a phone edit can be counted as sent when it never reached the watch; fix only if the test shows it does"). Series: with 63, 65, 66a, 66b. Base commit: `.work/2026-10-23-64/base.txt` (the tree also carries uncommitted plans 61 and 62). Working branch: the one checked out (`claude_develop`); never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 64 |
|---|---|---|
| Log or edit a set on the phone while the watch is mid-workout, and within about a quarter of a second the watch sends anything (it logged its own set, a rest, a sync request) | the phone's edit is silently marked "already sent" and never goes to the watch; the watch keeps the old state until the NEXT phone change | the edit goes to the watch right after the watch's message is handled |
| The watch sends something and the phone had nothing waiting | nothing is sent back (the rows the watch just brought in are not echoed) | unchanged |
| A previous push did not reach the watch (out of range) and the watch's next message arrives | the phone counts the unsent state as sent | the unsent state is offered again at once (the message proves the radio works) |
| Very first message of a session (the phone has never pushed) | nothing is pushed back | unchanged |

What you will not see change: nothing on screen except that the watch now matches the phone after a quick edit. Known and left: an edit made while the frame is being applied (the few milliseconds between the check and the apply) can still be absorbed; it needs the frame handler to hold the phone's edits, which is plan-sized on its own. Two units (63's one-frame-at-a-time lane) make this window smaller, not zero.

## The proof (done by the lead, 2026-10-23, on the unmodified code)

Throwaway test (kept as the template for S-9401: `/private/tmp/claude-501/-Users-irinakutsenko-Developer-omnitrain/aa1f8995-6b0e-4f96-9e21-5fd730b3358e/scratchpad/zz_repro_64_test.dart`, a copy of `test/watch_session_auto_push_test.dart` with one test added before `group('S-70`): wrist starts `s-1`, `graph.autoPush.bindWorkoutState(phoneState)`, the phone logs a set (`logSet(_firstSlot, …)`, debounce window open, nothing sent), the wrist logs a set on the other slot, `radio.fromWrist(wristFrames.last)`, `_settle()`, `graph.autoPush.flush()`. Result: **FAILED**: `Expected: contains 'entry-sx-1-1'  Actual: []` — no `session_snapshot` carried the phone's set. Cause: `lib/state/watch/watch_sync_wiring.dart` `resolved.onIncoming` calls `push.rebaseline()` after every handled frame; `WatchSessionAutoPush.rebaseline` (`lib/state/watch/watch_session_auto_push.dart`) sets `_baseline = _encode(<the phone's CURRENT composed session>)`, which already contains the phone's unsent edit, so the `push.flush()` that follows finds `encoded == _baseline` and sends nothing.

## Decision Ledger

- D-1 Fix at the call, not inside `rebaseline`: take the baseline from the frame only when the phone had nothing unsent BEFORE the frame was applied. `WatchSessionAutoPush` (`lib/state/watch/watch_session_auto_push.dart`) gains `Future<bool> hasUnsentChange()`: composes `_mirror.projectedSession()`; answers `false` when it composes nothing, `false` when `_baseline == null` (the phone has never pushed: the first payload after a wrist frame is not pushed back, as today), else `_encode(composed) != _baseline`; swallows an `Exception` as `false` exactly as `rebaseline` does. The doc comment says what "unsent" means (composed state differs from the last state the radio carried or that a wrist frame baselined).
- D-2 `lib/state/watch/watch_sync_wiring.dart`, the `resolved.onIncoming` closure (current: `final request = …; var answeredReset = false; if (request != null) {…} else {…} await push.rebaseline();`): first statement `final owedBefore = await push.hasUnsentChange();`; `await push.rebaseline();` becomes `if (!owedBefore) await push.rebaseline();`. Everything after it (the `if (!answeredReset) { await push.flush(); await timerPush.flushClears(); }`) is unchanged: with a pending edit the flush now sees `encoded != _baseline` and sends.
- D-3 `rebaseline()` itself is unchanged (its other caller is the harness in `test/watch_session_finish_test.dart:499`); its doc comment gains one sentence naming D-2's guard.
- D-4 Behaviour for a wrist frame that is an `answeredReset` (D-176 reset): unchanged; the reset path already offers the state itself.
- D-5 Not in this plan: serialising the handler against phone edits, the in-flight-pass race the scout noted (`rebaseline` while an earlier pass's send is still in the air): reachable only when a debounce pass is mid-send and a frame arrives; with D-1 `hasUnsentChange` before the frame still reads the pre-send baseline, so the worst case is one redundant push, not a loss.

## Readers listed

- `rebaseline` callers: `watch_sync_wiring.dart` (the closure) and `test/watch_session_finish_test.dart:499` (calls it by hand; unchanged).
- Tests that pin "a wrist frame is not answered with a push": `test/watch_session_auto_push_test.dart` S-80/S-81 groups (the S-81 case "the same snapshot twice writes nothing new on the wrist" must stay green: there nothing is owed before the frame), `test/rating_first_answer_push_test.dart`, `test/watch_session_projection_test.dart` (~l.2192-2241), `test/watch_timer_push_test.dart`. The builder re-runs all four.
- The harness for the new tests is in `test/watch_session_auto_push_test.dart`: `_PhoneRadio` (knobs `failing`, `unreachable`, `throwing`), `startGraph()`, `wristStartsSession()`, `pushPhoneSet()`, `logSet(...)`, `_atIso`, `_entryIds`, `_payload`, `radio.ofType`. New tests go in a new group at the END of that file (the builder's scope names it).
- Scenario ids S-9401..S-9410 checked free (grep `S-94` in `test docs watch lib`, 2026-10-23).

## Core scenarios

All in `test/watch_session_auto_push_test.dart`, new group `S-9400 an edit the phone has not pushed survives a wrist frame`. Plain `test()`, not `testWidgets`.
- S-9401 the proof above, as a permanent test: the phone's set rides a `session_snapshot` after the wrist's frame is handled (fails on the current code, as shown above).
- S-9402 the frame is a REQUEST, not an observation: `radio.fromWrist(WatchTransportRequest.routinesFrame(since: null))` (a ROUTINES request; a `snapshotFrame()` request would be answered with the phone's own session snapshot and pass without the fix): same expectation, the phone's set rides a `session_snapshot` after the request is handled.
- S-9403 control: nothing owed before the frame (phone logs a set, `autoPush.flush()` delivers it, THEN the wrist logs a set): after handling, NO new `session_snapshot` is sent (the wrist's own rows are not echoed). Passes before and after the change; it guards the rebaseline's purpose.
- S-9404 control: `_baseline == null` (the very first frame of the session, the phone has pushed nothing, nothing edited): no snapshot is sent (S-80 intent).
- S-9405 an earlier push the radio did not carry (`radio.unreachable = true` during `autoPush.flush()` of a phone set; then `unreachable = false`; then the wrist's frame arrives): the unsent set is sent now (the state "owed from a failed push" is also an unsent change).
- S-9406 two arms of the edit: (a) a phone set logged before the frame (S-9401), (b) a phone set DELETED before the frame (the phone's deletion is announced as the existing deletion frame or a snapshot without the entry; the test asserts whichever the existing delete tests assert, naming the frame type).
- S-9407 `hasUnsentChange` directly: false with no session; false when `_baseline == null`; true after a phone edit; false after a delivered push; false after `rebaseline()`. A value unlike the defaults: reps 7, load 41.5.

## Phases

- P1 `crew-builder-app` (5 items, one concern): D-1, D-2, D-3 and S-9401..S-9407. Scope: `lib/state/watch/watch_session_auto_push.dart`, `lib/state/watch/watch_sync_wiring.dart`, `test/watch_session_auto_push_test.dart`. Brief: report first as a skeleton; never the full suite; quote the current closure lines; Done: `flutter test test/watch_session_auto_push_test.dart test/rating_first_answer_push_test.dart test/watch_session_projection_test.dart test/watch_timer_push_test.dart test/watch_session_finish_test.dart`, `flutter analyze` on the touched files, the invariant grep. Plan 62 also edits `watch_sync_wiring.dart` (the `since:` argument, uncommitted): the builder edits only the closure's `rebaseline` lines.
- P2 `crew-docs-keeper`: the doc that owns the auto-push (`docs/state_management/` page that mentions `rebaseline`/"auto-push"; grep) gets one paragraph: a wrist frame no longer swallows an unsent phone edit. Run no test.

## Verify (governor)

`flutter test` full, `flutter analyze` count, invariant grep. Proof: S-9401 FAILS on the base commit (done, above) and passes after; re-confirm by stashing nothing: mutate D-2 back (`if (!owedBefore)` -> unconditional) and watch S-9401, S-9402, S-9405, S-9406 fail. Mutations: `hasUnsentChange` returns false always; returns `true` when `_baseline == null` (S-9404 must fail); compare uses `==`; the guard reads `owedBefore` AFTER the frame (read moved below the apply); `flush()` skipped on `owedBefore`. Simulator: the iOS simulator does not carry watch traffic: owner check (log a set on the phone while the watch is logging its own).

## Progress

Done 2026-10-23: P1 (9 min) + fix 1 (S-205 re-pinned: the owed snapshot is now re-offered after the frame, the wrist's own row is still not echoed; deviation from the Readers list, which had not named S-205) + P2 docs. Lead: full `flutter test` +5483 ~2 green, analyze 180 (baseline 181), five mutants red, one equivalent (`composed == null` with a baseline: `rebaseline` is a no-op then). Reviewed: APPROVE, no findings (`*.review.md`). Owner check (owner): log a set on the phone while the watch is logging its own; the phone's set reaches the watch right after.
