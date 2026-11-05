# Feature: 43c — finishing an interval on either device logs it once

> Status: BUILT, PROVED AND REVIEWED (2026-10-20, review APPROVE WITH FIXES, the fixes applied); uncommitted. Full flutter +5227 ~2, analyze 181, swift 633/0. Evidence: `2026-10-20-43c-finish-once-plan.evidence.md` beside this file. Last of the shared-running-timer series (43a fill, 43b1 wire + wrist, 43b3 phone sends, 43b2 phone receives). Series outline: `docs/plans/2026-10-19-43-shared-running-timer-plan/`.
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base: working tree on `claude_develop` after 43b2 (uncommitted), base commit in `.work/2026-10-20-43c/base.txt`. Team: the crew. Architect step skipped on purpose (seeded by the lead from two scout sheets). Re-validate line numbers before briefing: plans 41 and 44 share the tree.
> Scout sheets: `.work/crew/2026-10-20-43c/scout-phone.md`, `scout-wrist.md`.

## Goal and acceptance

When you finish a cardio interval, a hold or a round, on the phone or on the watch, it is logged once and the other device's clock for it stops.

| Situation | Now | After 43c |
|---|---|---|
| Interval running on both (started on the phone, or on the watch and shown on the phone); you log on the watch while the phone is on ANOTHER interval of the same exercise (or the phone's running interval is not the first unfinished one) | the watch's entry fills the phone's FIRST unfinished interval, which may not be the running one | it fills the interval whose clock started at the same moment, and that phone clock stops |
| Interval started on the watch, shown on the phone; you log it ON THE PHONE | the phone logs it; the watch keeps its clock running and still offers Log, so a second Log makes a second entry | the watch's clock is cleared and offers Start again |
| The same, but the watch logged before the clear reached it (or while out of reach) | the watch's entry fills the phone's NEXT interval (a duplicate) | the phone keeps the entry it already has; the watch's copy is ignored on the phone (the phone's numbers stand) |
| Watch stops its clock without logging | — | unchanged: the phone's interval keeps running (technical choice, D-4) |

## Owner decisions (2026-10-19, in chat)

O-1 the timer belongs to the interval where it started; O-2 pause pauses both; O-3 the earlier start wins. 43c adds no product question.

## Decision Ledger

- D-1 Target of a watch interval entry in the live merge (`lib/core/services/watch_session_importer.dart`, the loop calling `_unfinishedInstanceToFill` ~:841-848, `fillPlanned` only). Order: (1) the effort's in-progress (`active`/`paused`) interval whose `startedAtMs` is within 1000 ms of the entry's `startedAtMs` ("the shared start"; 1000 ms because the start crosses the wire as an ISO string and a Swift Date round trip can move the last millisecond); (2) else the first in-progress interval; (3) else the first not-finished interval (43a's rule, unchanged); (4) else append. Applies to `timed`, `hold` (TimedInstance) and `round` (RoundInstance). Today `_unfinishedInstanceToFill` takes the first instance whose state is not `finished`.
- D-2 Duplicate rule (same file, same loop, before D-1): when the effort already holds a FINISHED interval of the entry's kind whose `startedAtMs` is within 1000 ms of the entry's start (both > 0) and whose id is not the entry's own instance id (`timedInstanceIdFor` / `roundInstanceIdFor`), the entry is the second report of an interval the phone already logged: nothing is written, `changed` is not set, `_placed[entry.entryId]` points at the phone's interval (index = its `entryIndex` / `roundIndex`, position = index) so a rest that follows it still lands, and the loop moves on. The phone's numbers stand (the same rule as the rating, D-138). Why the own-id exemption: a half-written earlier pass leaves a finished instance of the entry's own id (S-5011); the entry must finish THAT, not be dropped as a duplicate.
- D-3 Clearing the watch's clock when the PHONE finishes an interval that the watch's timer started (`lib/state/watch/watch_timer_push.dart`). Today a clear (`{kind: null}`) is sent only for a kind the push itself delivered (`_delivered`); a timer the watch started and the phone adopted is skipped as "the wrist holds it" (`_watchHoldsIt`), so it is never in `_delivered` and no clear follows when the phone logs it. New memory `_adopted[kind]` = (slot id, startedAt string) recorded when the mirror holds the phone's timer identically (not the "earlier start" arm). A pass retires an adopted kind when the phone no longer wants a timer of that kind with that slot and start (interval logged, or replaced by another): if the mirror still holds that exact timer (same slot, same start, not stopped) a `{kind: null}` frame is sent (before any new frame for the kind, as D-2b of 43b3); if the mirror no longer holds it (the watch logged or stopped first) nothing is sent and the memory is dropped. After a delivered clear the push remembers that mirror copy as stale (`_stale[kind]`), because the mirror holds only what the WATCH reported and the watch does not echo a stop it received from the phone (Swift S-333): without this a later, newer phone interval would be skipped for ever as "the wrist holds an earlier timer". `_wristHolds` ignores a mirror timer equal to the stale one. An undelivered clear leaves everything as it was, so the next notification offers it again (43b3 D-2 rule).
- D-4 A remote `stopped` timer stays ignored on the phone (43b2 A-2). Reason: the watch stops its work clock only by Log (the entry arrives and 43a/D-1 finish the interval) or by the phone's own clear (no echo); a stop frame that arrives before its entry would otherwise end an interval with nothing logged. Limit stated: a watch clock stopped without a log (none exists today) would leave the phone's running.
- D-5 Both devices log within moments: the first entry to reach the phone's data wins. Watch first: its entry fills the interval (D-1), the phone's later Log finds the interval finished and does nothing (`Invalid timed transition`, no new entry). Phone first: the watch's entry is ignored on the phone (D-2); the watch's own list keeps both its entry and the phone's, because the phone has no way to retract a watch entry without a new message (limit: delete one on the watch if it happens; owner informed).
- D-6 The wrist: a `timer_state` naming a work kind as `null` already stops it and the button reads Start (`adoptTimers` ~Swift :696, scout wrist Q1), but no Swift test pins a WORK kind (only `rest`). Add the test only (P3); no Swift production change.
- D-7 Not in scope: any wire change, any screen change, any change to the wrist app, the phone-side "ignore stopped" rule, deleting the watch's duplicate entry from the phone.

## Code pointers (current text)

`watch_session_importer.dart`: loop ~:834-849 `for (final entry in now) { if (placed.contains(entry.entryId)) continue; final unfinished = rows.unfinishedPlaceOf(entry); final fills = ...; final fill = ...; final interval = unfinished == null && fillPlanned && (entry.wireKind == WatchInboxEntry.kindTimed || ... kindHold || ... kindRound) ? await _unfinishedInstanceToFill(effortId, entry.wireKind) : null; final index = unfinished ?? fill?.number ?? interval?.index ?? next++;`. `_unfinishedInstanceToFill` ~:1013: round branch `for (final round in await _repository.getRoundInstances(effortId)) { if (round.state == RoundState.finished) continue; return (...); } return null;`; timed branch loops `position` over `getTimedInstances(effortId)` skipping `TimedState.finished`, builds `distances`/`extraWeights` companions and returns the record `(instanceId, index, rowNumber, rows)`. `TimedInstance.startedAtMs` is 0 while `notStarted`; a phone-finished instance KEEPS `startedAtMs` (`finishTimedEntry` / `endRoundEarly` copyWith).
`watch_timer_push.dart`: `_pushOnce` ~:140-214, `_watchHoldsIt` ~:219-242 (quoted in the brief).
Tests to model on: `test/watch_timed_fill_test.dart` (Mock/Hive openers `_openMock`/`_openHive`, `_phoneIntervals`, `_timed`, `observationsUp`; the importer scenarios S-5001..S-5011 pin first-unfinished), `test/watch_timer_push_test.dart` (the shipping graph over a fake radio and the real Dart wrist engine).

## Core scenarios (ids checked: no S-63xx exists in lib, test, docs, watch)

Importer (`test/watch_finish_once_test.dart`, groups Mock and Hive, plain `test()`; fixture: effort `sx-run`, timed instances idx 0..2 as stated, wrist entry `startedAt` = S):
- S-6301 idx0 notStarted, idx1 active (start S), wrist timed entry start S: idx1 becomes the wrist's finished record, idx0 stays notStarted. Fails without: idx0 is filled.
- S-6302 same with idx1 `paused`. (Arm: paused counts as in progress.)
- S-6303 a hold entry on a drill effort and a round entry on a round effort, same shape (idx0 notStarted, idx1 active at S).
- S-6304 no start match: idx0 notStarted, idx1 active (start S - 10 min), entry start S: the in-progress idx1 is filled (arm 2: in-progress beats first-unfinished).
- S-6305 two in-progress (idx1 active start S1, idx2 paused start S2; written directly), entry start S2: idx2 filled; entry start S1+5 min (matches neither): idx1 filled (arm 1 beats arm 2; arm 2 takes the first).
- S-6306 tolerance: entry start S+400 ms matches idx2 started at S; entry start S+5000 ms does not (falls to arm 2).
- S-6307 nothing in progress: idx0 notStarted, idx1 notStarted: idx0 filled (43a rule intact); all finished: appended (43a rule intact).
- S-6311 duplicate: idx0 finished by the phone (start S, window 2 min), idx1 notStarted; the wrist entry with start S arrives: no instance changes (idx0 keeps its own duration, idx1 notStarted, instance count 2), no new rows; a redelivery of the same message is the same. Fails without: idx1 filled.
- S-6312 duplicate for a hold (drill) and a round.
- S-6313 not a duplicate: idx0 finished with start S - 30 s, idx1 notStarted; entry start S fills idx1.
- S-6314 start tolerance on the duplicate: finished idx0 start S + 400 ms is a duplicate of entry S; finished idx0 start S + 5000 ms is not (entry fills idx1).
- S-6315 the own-id exemption: a finished instance that carries the entry's own instance id with the entry's start and un-stamped rows (the half-written pass of S-5011) is finished in place, not ignored (S-5011 already does this; the scenario is that it stays green).
- S-6316 a rest following a duplicate lands on the phone's interval (the wrist's `afterEntryId` rest is placed after the phone's idx0, no rest written when the phone already has its own).
Push (`test/watch_timer_push_test.dart`, new group, shipping graph + real wrist engine):
- S-6321 the wrist starts an `elapsed` timer (slot `sx-run`), the phone adopts, the phone finishes the interval (`finishTimedEntry`): after `flush()` exactly one frame `timers: {elapsed: null}`; the wrist engine's `elapsed` timer is stopped. Fails without: no frame.
- S-6322 arm "mirror stopped": same, but the wrist's own stopped row (its Log) reached the mirror before the phone finished: no frame.
- S-6323 arm "different start": the mirror holds an `elapsed` timer for the same slot with a different start (the wrist began the next interval): no frame, and the wrist's new timer is not touched.
- S-6324 arm "other slot": the mirror holds an `elapsed` timer for slot `sx-other` with the same start (a frame via `_wristTimerFrame`): no frame.
- S-6325 an undelivered clear (`radio.unreachable`) is offered again at the next notification and then stops.
- S-6326 stale mirror: after S-6321 the phone starts its own next interval (later start): the frame carrying it IS sent (the wrist ends running it). Fails without the stale memory.
- S-6327 replacement in one pass: the phone finishes the adopted interval and starts another in one window: two frames, `{elapsed: null}` first, then the new timer.
Swift (`WatchTimedWorkTests`): S-6331 a phone `timer_state` for the wrist's slot makes `isWorkRunning` true; then a `timer_state` `{elapsed: null}` makes it false and `primaryTitle` read Start (the wrist's own clock, started by the wrist, is stopped by the same frame: pins the by-kind clear semantics); `{hold: null}` and `{round: null}` likewise.

## Phases

- P1 `crew-builder-app` — D-1, D-2 with S-6301..S-6316. Scope: `lib/core/services/watch_session_importer.dart`, new `test/watch_finish_once_test.dart`. Production code is given as exact text in the brief.
- P2 `crew-builder-app` — D-3 with S-6321..S-6327. Scope: `lib/state/watch/watch_timer_push.dart`, `test/watch_timer_push_test.dart`. Production code exact text in the brief. Parallel with P1 (disjoint scopes; neither runs the full suite) and P3.
- P3 `crew-builder-watch` — D-6 with S-6331, Swift test only. Scope: `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift`. Runs `swift test --filter WatchTimedWorkTests` and `--filter WatchSessionEngineTests`.
- P4 `crew-docs-keeper` — `docs/state_management/workout_state.md`, `docs/watch_session_capture.md`, this plan's evidence (not `docs/watch_session_sync.md`, not `docs/state_management/watch_surface.md`: both at the 80% band).
- Then the lead's mutations, `crew-reviewer`, full suite, `swift test`, xcodebuild of the watch app only if Swift production changed (it should not).

Size: about 110 production lines (importer ~60, push ~50), about 700 test lines, 4 phases, one track plus one Swift test file. Within budget.

## Owner checks (owner)

- (owner) Start an interval on the watch, then log it on the phone: the watch's clock disappears and it offers Start for the next interval.
- (owner) Start an interval on the phone, log it on the watch: the phone shows one finished interval, its clock stopped, no extra interval.
- (owner) Phone has two intervals; start the SECOND on the watch (phone on the second); log on the watch: the second fills, the first stays untouched.
- (owner, edge) Turn the watch's radio off (aeroplane mode), log on the phone, then log on the watch, then turn it on: the phone keeps one interval; the watch may list it twice (known limit D-5).

## Progress

| Phase | What | Result |
|---|---|---|
| P1 | importer D-1, D-2 | built |
| P2 | push D-3 | built |
| P3 | Swift test D-6 | built |
| P4 | docs | built |
| Fix round 1 | red tests for the mutations the first pass left green (S-6302b, S-6315, S-6328..S-6330, S-6341; one redundant condition removed) | built |
| Mutations | 35 lead mutations of the importer and the push, 3 of the Swift engine; every guard proven by a named test except the equivalent-by-construction ones listed in the evidence | proved |
| Review | `crew-reviewer`: APPROVE WITH FIXES, 3 minors | review file beside this plan |
| Fix round 2 | review minor 3 (an unfinished instance of the entry's own is finished, not shadowed by the duplicate rule; S-6317), minor 1 (stale comment) and minor 2 (docs sentence) | built, mutated, green |

## Assumption Log

- A-1 The wrist's Log of a running work interval writes `startedAt` = the timer's start (scout wrist Q2), and the phone's adoption copies the watch's start verbatim, so the two starts differ at most by the wire's rounding (hence the 1000 ms tolerance).
- A-2 A tolerance of 1000 ms cannot confuse two real intervals of one effort: an interval cannot be started, finished and the next started inside one second on either device.
- A-3 The watch has no path that stops a work clock without logging except the phone's clear and the session ending.
