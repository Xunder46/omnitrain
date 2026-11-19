# Feature: 126 — pausing or resuming a shared timer on the watch pauses or resumes it on the phone (bug fix)

> Status: Iteration 1 ready to seed (planned 2026-11-05, no code yet). One owner question, Q1, with a default the plan builds against.
> Next handoff: @crew-builder-app (Phase 0, red tests) — but only after plan 121b's Phase 1 has landed (see "Sequencing").
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Builds on: `docs/plans/2026-10-19-43-shared-running-timer-plan/` (owner rule O-2: pausing a shared timer pauses both devices; resume and stop likewise), `docs/plans/2026-10-20-43b2-shared-timer-phone-receives-plan/` (D-1 target, D-2 adoption), `docs/plans/2026-10-20-43b3-shared-timer-phone-sends-plan/` (phone→wrist), and `docs/plans/2026-11-05-121b-stale-watch-timer-adopted-into-next-interval-plan/` (read-only context; NOT edited here).
> Evidence: `...-plan.evidence.md`; review: `...-plan.review.md` (both beside this file, created by the first writer).
> Origin: found while planning 121b ("Noticed, not planned"). Owner treats it as a bug. Re-validate every line number: another session edits the tree.

## Goal and acceptance

**What the owner sees today (the bug).** A timer (interval, hold or round) runs on both devices. You press Pause on the watch: the watch shows paused, the phone keeps counting. Resume on the watch: same, the phone never learns. The reverse direction already works (Pause on the phone pauses the watch, S-6212 / S-6328). This holds whether the phone or the watch started the timer.

**After 126.** Pause or Resume on either device reaches the other. After a wrist pause the phone's interval shows paused with the same paused-at and the same accumulated pause; after a wrist resume it runs again with the same accumulated pause. Nothing is echoed back. A copy of an interval the phone already logged is still ignored, even when the wrist pauses or resumes it (121b stays true).

**Cause (verified 2026-11-05).** `lib/state/workout/timer_manager.dart` `_adoptRemoteTimed` (~:355) and `_adoptRemoteRound` (~:391): once the target interval is in progress, `remote.startedAtMs >= old.startedAtMs` returns false. A pause or resume keeps the start, so the wrist's frame (same start, new `pausedAt` / `accumulatedPauseMs`) is refused. The chain upstream is fine: `WatchTimerAdoption._adoptOnce` (`lib/state/watch/watch_timer_adoption.dart` ~:117-163) skips a frame only when its sorted JSON equals `_applied[kind]`, and a pause or resume changes `pausedAt` / `accumulatedPauseMs`, so the frame IS handed on; `WorkoutState.adoptRemoteWorkTimer` (`session_core_io.dart` ~:270) just forwards the refusal. So the fix is one layer: the state rule. Remembering the refused frame as applied (`_applied[kind] = encoded` after a false) is intended and stays.

**Phone→wrist, checked for symmetry (no change).** `WatchTimerPush._pushOnce` (`watch_timer_push.dart` ~:232) sends a changed phone timer unless the mirror already holds the identical one or one with an EARLIER start; a pause keeps the start, so it travels (pins S-6212, S-6328, S-7302 exist). On the wrist, Swift `adoptTimer` (`Sources/WatchSessionEngine/WatchSessionEngine.swift` ~:829) drops a phone frame only when the held start is strictly earlier; a same-start frame is appended and the newest row wins (last write wins, no emit back). After 126 the phone adopting the wrist's pause makes the phone's composed timer equal the mirror's, so `_WristHolds.identical` suppresses an echo.

**Wire:** no change. The `timer_state` frame already carries `pausedAt`, `accumulatedPauseMs`, `state` (PROTOCOL.md "Timer state"). No Swift change expected; Phase 0 greps `watch/watchos/Tests` for an existing test that a same-start phone frame with a `pausedAt` replaces the wrist's row, and adds one pin only if none exists.

## Sequencing with plan 121b

- **126 lands after 121b Phase 1 (and preferably after 121b P2).** 121b adds the "logged-timer" refusal at the top of `adoptRemoteTimer` (a remote whose start is within `_sameStartToleranceMs` of a FINISHED interval of the effort is refused, whatever the other intervals' states) and keeps the "same start = refuse" rule for in-progress targets. 126 relaxes only the second, and only below that guard. Built the other way round, the stale-copy scenarios of this plan (S-12612, S-12613) would be red for the wrong reason and 121b's S-12157/S-12159 pins could be broken unseen.
- **Files both touch** (re-read before editing; keep groups self-contained):
  - `lib/state/workout/timer_manager.dart`: 121b edits `adoptRemoteTimer`, `needsIntervalFor` and adds the predicate; 126 edits only the bodies of `_adoptRemoteTimed` / `_adoptRemoteRound` (the `old.state != notStarted && remote.startedAtMs >= old.startedAtMs` block) and adds one helper beside them.
  - `test/watch_timer_adoption_test.dart`: 121b appends group `S-1217x`; 126 appends group `S-1263x` after it.
  - `docs/state_management/workout_state.md` (the `adoptRemoteWorkTimer` rule row ~:245) and `docs/watch_session_capture.md` (~:366-380): 121b P2 rewrites that row and adds a sentence; 126 P2 appends one clause and one sentence. Read the file after 121b before editing.
  - Not edited by 126 but must stay green: `test/stale_watch_timer_adoption_test.dart` (121b's new file; S-12157 and S-12159 are the pins closest to this rule), `test/remote_work_timer_state_test.dart` (S-6102b, S-6102c, S-6104).
- Plan 121a (wrist side, a hold stuck after a phone log) may change what the wrist re-reports; 126 holds whatever it re-reports.

## Decision Ledger

- **D-1 Same interval.** A remote whose start is within `_sameStartToleranceMs` (inclusive, both directions) of the start of the effort's IN-PROGRESS (active or paused) target is that interval's own update, not a rival. The wire start can differ by a millisecond through the ISO round trip, and 43c A-2 already argues no two distinct intervals start within that window. Beyond the tolerance nothing changes: a later start is refused, an earlier one overwrites (O-3, S-6102a).
- **D-2 When a same-interval update is newer (the order key).** The wire has no version counter, but the pause bookkeeping only ever moves one way: each resume ADDS to `accumulatedPauseMs`. So the remote is newer than the phone's interval when (a) `remote.accumulatedPauseMs > old.totalPausedDurationMs` (a resume, or a whole pause/resume cycle, happened), or (b) the accumulated pauses are equal, the phone's interval is running and the remote is paused (a pause). Everything else is refused: equal accumulated pause with the phone paused and the remote running is the stale pre-pause copy (it must NOT resume a timer the user just paused); a smaller accumulated pause is older; identical bookkeeping is the same state (no write, S-6102c).
- **D-3 What a newer same-interval update writes.** State (`paused` / `active`), `pausedAtMs`, `totalPausedDurationMs`, `updatedAtMs`; rounds keep their planned length, timed keep `targetDurationSecs`. The phone keeps its OWN start unless the remote start is strictly earlier (then the earlier start wins as today, O-3: S-12159 of 121b stays green). An earlier start whose bookkeeping is not newer takes the start only. The write returns true (the session core bumps the refresh revision and notifies once).
- **D-4 No rest is closed.** A pause or resume is not a start: it does not run `closeAllOpenRestsInSessionInMemory()` (that stays on the start/overwrite paths). Derived, vetoable; reason: a rest open beside a running interval (another exercise's rest) belongs to someone else's log.
- **D-5 Tie-break when both devices act within moments (Q1 default).** Both pause: the phone keeps its own pause stamp (equal accumulated pause, both paused → refused by D-2). The wrist, which stores the phone's pause frame last-write-wins, then shows the phone's stamp, so both converge on the phone's. Both resume: the later resume has the larger accumulated pause, so the phone takes it; the wrist ends on the phone's own earlier resume. The two clocks can then differ by the gap between the two presses (about a second at most) until either device next pauses from the phone side. Accepted and recorded; a true fix needs a version counter on the wire (rejected here: protocol change for a sub-second-scale race).
- **D-6 The 121b hole stays closed.** The stale-copy refusal runs first (121b D-1) and covers every interval state of the effort, so a paused or resumed copy of a FINISHED interval is refused before this rule can see it. This rule reads only the in-progress target's own start, so it cannot be reached by a finished interval's start unless two intervals started within one tolerance window (excluded by 43c A-2; named as an accepted limit, same as 121b's).
- **D-7 Unchanged.** 43b2 D-1 target choice; not-started target adoption (S-6104); stopped remote ignored (43c D-4); the grow rule; `WatchTimerAdoption` remembers a refused frame and does not retry it; the phone→wrist comparison in `WatchTimerPush`; the Swift engine. The rest timer is out of scope: `WatchTimerAdoption._wireKinds` is `round`, `hold`, `elapsed` only, so a rest paused on the wrist never reaches the phone (see "Noticed, not planned").

## Feature Invariants

- A pause or resume made on one device is visible on the other with equal `pausedAt` and equal accumulated pause (single-device case).
- A finished interval, and the intervals after it, are never touched by a remote whose start belongs to the finished one (pause, resume or run).
- A refusal is invisible: no write, no revision bump, no notification, no rest closed.
- Mock and Hive hold identical rows after every state scenario (stored rows asserted, not only memory).
- No echo: after the phone adopts a wrist pause/resume, `WatchTimerPush` sends nothing for that kind.

## Requirements and Acceptance Criteria

- AC-1 A wrist pause or resume of an interval the phone is running reaches the phone, for `elapsed`, `hold` and `round`, started on either device — S-12601..S-12604, S-12631..S-12634.
- AC-2 Only genuine progress is accepted: stale, older, identical and tied copies change nothing — S-12605..S-12609, S-12611.
- AC-3 The stale-copy hole of 121b stays closed — S-12612, S-12613, S-12639.
- AC-4 Two devices acting at once, a redelivery and an app restart behave as D-5 / D-2 say — S-12636..S-12638, S-12640.
- AC-5 Nothing else moves — S-12610, S-12614, S-12615, and every existing S-6101..S-6106, S-6111..S-6118, S-6212, S-6328, S-12151..S-12174.

## Existing-Functionality Impact

| Touched surface | Readers (grep, re-run) | Effect | Guarded by |
|---|---|---|---|
| `TimerManager._adoptRemoteTimed` / `_adoptRemoteRound` | `grep -rn "_adoptRemote" lib` → `adoptRemoteTimer` only | an in-progress target within the tolerance takes newer pause bookkeeping | S-12601.. |
| `TimerManager.adoptRemoteTimer` | `session_core_io.dart` only | none (121b's guard runs first) | S-12612, S-12613 |
| `WorkoutState.adoptRemoteWorkTimer` | `watch_timer_adoption.dart:151`; tests `remote_work_timer_state_test.dart`, `timer_start_closes_session_rests_test.dart`, `stale_watch_timer_adoption_test.dart` (121b), `widget_test.dart:688` | none for those fixtures: they carry no pause bookkeeping on an equal start | Done Criteria runs them |
| `WatchTimerAdoption` | behaviour via the facade only | none (code unchanged) | `watch_timer_adoption_test.dart`, `watch_timer_adoption_screen_test.dart` |
| `WatchTimerPush` | tests `watch_timer_push_test.dart` | none (code unchanged); the no-echo property is new | S-12631.. |
| Docs | `workout_state.md` (~27.8 KB), `watch_session_capture.md` (~36.3 KB), re-measure after 121b | one clause, one sentence | P2 |

Layer boundary (state only), repository parity, "Timestamps are source data" (the rule compares persisted starts and bookkeeping): PASS by design. No schema, seed, model or wire change.

## UI Standards Impact

None: no screen, widget or copy changes. The phone's timer screens already render paused/running from the instance.

## Scenarios

State scenarios live in a new file (Mock and Hive groups). Fixtures: `P` = the phone interval's start (`_startAt` pattern of `test/remote_work_timer_state_test.dart`); `PS = P + 30000` (a pause stamp); `A0 = 0`, `A1 = 4000` (accumulated pause). Default fixture "running": `timed` effort, idx0 active at P, `totalPausedDurationMs` 0. "Paused": idx0 paused with `pausedAtMs` PS, accumulated 0. "Nothing changed" = `changed == false`, memory AND repository rows equal, `watchRefreshRevision` unchanged, 0 notifications, open rest still open.

| S-id | Fixture → trigger | Expect | Red today because |
|---|---|---|---|
| S-12601 | running; remote `elapsed` P, paused PS, acc A0 | idx0 paused, pausedAt PS, acc A0, changed true | same start refused |
| S-12602 | paused (PS, A0); remote `elapsed` P, running, acc 4000 | idx0 active, pausedAt null, acc 4000 | refused |
| S-12603 | round [r0 active at P]: (a) pause, (b) resume | r0 paused/active with the remote bookkeeping, planned length kept | refused |
| S-12604 | `drill` hold: pause then resume | same as S-12601/2 | refused |
| S-12605 | running; pause with start P±400, P+1000, P−1000 inclusive | paused; start stays P when remote is later, becomes remote's when earlier | refused |
| S-12606 | (a) running acc 4000, remote paused acc 0; (b) paused (PS, 4000), remote running acc 4000 (pre-pause copy); (c) paused (PS, 4000), remote running acc 1000 | nothing changed each | (a)(c) refused today, pass both ways; (b) passes both ways: guards M2/M3 |
| S-12607 | paused (PS, A0); remote paused at PS−5000 and at PS+5000, acc A0 | nothing changed (phone's stamp stays, D-5) | pin, guards M4 |
| S-12608 | running acc 0; (a) remote running acc 4000 → accepted (missed cycle), (b) remote running acc 0 → nothing changed (S-6102c) | as stated | (a) refused today |
| S-12609 | paused (PS, A0); remote paused PS+60000 with acc 4000 | paused at PS+60000, acc 4000 | refused |
| S-12610 | S-12601 plus an open rest on another effort | pause adopted, rest stays open (D-4) | red (refused); guards M7 |
| S-12611 | S-12601 twice | true then false; one write | red |
| S-12612 | [idx0 finished S0, idx1 notStarted]; remote `elapsed` S0 running acc 4000 (resume after the phone logged) | nothing changed | pin (121b): guards the ordering |
| S-12613 | [idx0 finished S0, idx1 active P]; remote `elapsed` S0 PAUSED | nothing changed, idx1 keeps P and running | pin (121b S-12157, paused variant: the dangerous one) |
| S-12614 | running; remote paused at P+20000 (later) → nothing changed (S-6102b); remote paused at P−20000 → overwritten paused at P−20000 | as stated | pin, guards M5 |
| S-12615 | running; remote running P−500, acc 0 (121b S-12159) | start becomes P−500, changed true | pin, guards M6 |

Graph scenarios (`test/watch_timer_adoption_test.dart`, group `S-1263x`, the file's harness: shipping graph over a fake radio, real `WatchSessionEngine` on the wrist, `engine.pauseTimer(kind:)` / `resumeTimer(kind:)`, `deliver(lastTimerFrame())`, `graph.timerAdoption.flush()`; the push scenarios bind `graph.timerPush` and use `applyPhoneTimers()` as `test/watch_timer_push_test.dart` does; the wrist clock is moved with `wristClock` so a pause has a measurable length):

| S-id | Scenario | Expect |
|---|---|---|
| S-12631 | Started on the PHONE (`startTimedEntry`), pushed and applied on the wrist; the wrist pauses; deliver; flush | phone idx paused, `pausedAtMs` and `totalPausedDurationMs` equal the wrist row's; `sentOfType('timer_state')` unchanged after a push flush (no echo). Red today |
| S-12632 | Then the wrist resumes after a 12 s pause | phone idx active, `pausedAtMs` null, accumulated = wrist's (about 12000); no echo. Red today |
| S-12633 | Started on the WRIST (`wristStartsElapsed`), adopted; wrist pause, then resume | same results as S-12631/2. Red today |
| S-12634 | S-12631..S-12633 for a hold (`drill`) and a round (`_roundSlot`) | same. Red today |
| S-12635 | Loop: wrist pause → phone paused; phone resume (`resumeTimedEntry`) → pushed → wrist `timerFor(.elapsed)` running with equal accumulated pause | both sides equal. First half red today; second half is the S-6212 pin in this chain |
| S-12636 | Both pause at once: phone pauses at tP and its frame is applied on the wrist; the wrist's own pause stamp tW is delivered afterwards — run with tW < tP and tW > tP | phone keeps tP; the wrist row ends on tP (D-5); no further frame is sent |
| S-12637 | Both resume at once: tR1 on the phone, tR2 on the wrist, tR2 later | the phone's accumulated pause is the wrist's (larger); asserts the phone only, names the known gap (D-5) |
| S-12638 | Restart with empty memory: wrist paused earlier and the phone is already paused with the same bookkeeping; rebuild the graph (`timerAdoption.dispose()`; `startGraph()`); deliver `snapshot()` | no write, revision unchanged. Variant: the phone resumed meanwhile (larger accumulated pause) and the snapshot carries the wrist's older paused copy | refused; the phone is not regressed |
| S-12639 | The phone logs the interval (`finishTimedEntry`), the wrist (clear never delivered) resumes, then pauses, its copy | `[finished, notStarted]` throughout, idx1 never started. (121b S-12171 is the paused-only twin) |
| S-12640 | Redelivery: the same wrist pause frame twice, then a snapshot with a new revision, then the resume | one write for the pause, one for the resume; the repeats change nothing |

## Phases (Iteration 1)

### Phase 0: red tests first (@crew-builder-app)
1. [ ] Create the state test, Mock and Hive groups, plain `test()`, harness copied from `test/remote_work_timer_state_test.dart` — `test/wrist_pause_resume_adoption_test.dart` · header comment mapping S-12601..S-12615
2. [ ] Write S-12601..S-12615 as fixtured, asserting memory AND stored rows — same file
3. [ ] Add group `S-1263x a wrist pause or resume reaches the phone` with S-12631..S-12640 — `test/watch_timer_adoption_test.dart` (append after 121b's group; do not touch 121b's tests)
4. [ ] Grep `watch/watchos/Tests` for a test that a same-start phone `timer_state` carrying `pausedAt` replaces the wrist's newest row; if absent, add one pin (S-12641) in the nearest engine adoption test file (Swift test only, no engine change). Record the finding in evidence.
5. [ ] Run and record the red/green table in evidence. Expected RED on today's code (121b landed): S-12601, S-12602, S-12603, S-12604, S-12605, S-12608a, S-12609, S-12610, S-12611, S-12631, S-12632, S-12633, S-12634, S-12635 (first half), S-12636, S-12637, and the first half of S-12640. Expected GREEN (pins, pass both ways): S-12606, S-12607, S-12608b, S-12612, S-12613, S-12614, S-12615, S-12638 (no-regress variant), S-12639. Any mismatch: fix the fixture, never the expectation, or log it in the Assumption Log and stop.
6. [ ] Record the `flutter analyze` issue count baseline in evidence.

**Done Criteria** (observed, counts pasted): `flutter test test/wrist_pause_resume_adoption_test.dart` → exactly the expected red set, in both groups; `flutter test test/watch_timer_adoption_test.dart --plain-name "S-1263"` → expected red set only. If the Hive group hangs behind a red Mock group, run `--plain-name "Mock"` and `"Hive"` separately (AGENTS.md known hang).
**Predicted Files**: the two test files, one Swift test file at most, plan Progress, evidence.

### Phase 1: the same-interval rule (@crew-builder-app)
1. [ ] Add one private helper deciding "newer progress" from D-2 (pure: old pause bookkeeping vs remote) — `lib/state/workout/timer_manager.dart` · beside `_targetIndex`
2. [ ] `_adoptRemoteTimed`: replace the single `remote.startedAtMs >= old.startedAtMs` refusal for an in-progress target by D-1 / D-2 / D-3 / D-4; far starts keep today's behaviour exactly — same file
3. [ ] `_adoptRemoteRound`: the same, keeping `plannedDurationSecs` — same file
4. [ ] Update the `adoptRemoteTimer` doc comment (the "in-progress target is replaced only when the remote started earlier" sentence) — same file
5. [ ] Run Done Criteria; record red→green in evidence.

**Done Criteria**: `flutter test test/wrist_pause_resume_adoption_test.dart` all green (both groups); `flutter test test/watch_timer_adoption_test.dart test/watch_timer_push_test.dart test/watch_timer_adoption_screen_test.dart test/remote_work_timer_state_test.dart test/timer_start_closes_session_rests_test.dart test/stale_watch_timer_adoption_test.dart` all green; `swift test` in `watch/watchos` only if P0 step 4 added a Swift pin (governor runs it); `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green; `flutter analyze` count not above the baseline; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty. Never the full suite (governor, once).
**Predicted Files**: `lib/state/workout/timer_manager.dart` only (about 35 production lines), plan Progress, evidence. If any other `lib/` file is needed, stop and report.

### Phase 2: docs (@crew-docs-keeper)
1. [ ] In the `adoptRemoteWorkTimer` rule row add: an in-progress interval takes a newer pause or resume of the same start, and refuses an older, equal or tied one (marker below) — `docs/state_management/workout_state.md` · ~:245 (the row 121b rewrote)
2. [ ] One sentence in the adoption paragraph: a wrist pause or resume of a timer the phone already runs reaches the phone, the phone's own stamp wins a simultaneous pause, with `S-12631`..`S-12640` — `docs/watch_session_capture.md` · ~:366-380

**Done Criteria**: `flutter test test/docs_indexing_contract_test.dart` green; both files under 52 KB (sizes in evidence).
**Predicted Files**: the two docs, plan Progress, evidence.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/workout_state.md` | MODIFIED | a start the phone already logged | a newer pause or resume of the same start | S-12601, S-12606 |
| `docs/watch_session_capture.md` | ADDED | - | a wrist pause or resume reaches the phone | S-12631 |

## Verification (owners)

- **Implementer** — Done Criteria with pasted counts; P0 red observed before P1 exists.
- **crew-prover (mutations, after P1; each must turn a named test red, restore after each):** M1 keep the old refusal for in-progress targets (rule off) → S-12601; M2 drop the "equal accumulated pause, phone paused, remote running = stale" refusal → S-12606b; M3 use `>=` instead of `>` on the accumulated-pause comparison → S-12606b / S-12608b; M4 let a paused-vs-paused tie take the remote's stamp → S-12607, S-12636; M5 widen "same interval" to ignore the tolerance (any in-progress start) → S-12614; M6 stop honouring an earlier start inside the tolerance → S-12615; M7 close open rests on a same-interval update → S-12610; M8 write the remote's start over the phone's when the remote is later → S-12605; M9 skip the write for rounds (timed only) → S-12603; M10 drop the 121b guard order (run this rule before the logged-timer refusal) → S-12612, S-12613, S-12639; M11 return true on a refusal → S-12606 (revision); M12 compare only the pause stamp, not the accumulated pause → S-12602, S-12609. Equivalent by construction (name, do not test): rounding of the start inside the tolerance.
- **crew-reviewer** — diff vs Predicted Files; impact greps re-run; Mock/Hive parity of stored rows; confirm the 121b tests ran green on the final tree; Assumption Log.
- **Governor** — full suite once, `flutter analyze` count.

## Owner device checks (owner)

- (owner) Cardio exercise, two intervals. Start interval 1 on the phone; the watch shows it running. Pause it on the watch: the phone shows it paused at the same moment. Resume on the watch: the phone runs again and both show the same time.
- (owner) The same, but start it on the watch first.
- (owner) Repeat with a stretching hold and a sports round.
- (owner) Pause on the phone, resume on the watch (and the reverse): both follow.
- (owner) Log interval 1 on the phone. Then pause and resume the watch's old clock: the phone's interval 2 stays "not started" and the rest keeps counting.
- (owner) Press Pause on both devices at nearly the same moment: both end up paused; the phone's pause time wins. Press Resume on both at once: both run; the two clocks may differ by about a second until the next pause (accepted, Q1).
- (owner) Force-quit and reopen the phone app while the watch is paused: the phone's interval is still paused, the time does not jump.

## Questions

- **Q1 (default taken, not blocking).** When both devices pause (or resume) within about a second of each other, the phone's own pause stamp wins on a pause and both devices agree; on a simultaneous resume the later resume wins on the phone and the two clocks can stay about a second apart until the next pause. Veto if you want the watch's value to win, or if a second of drift on a double resume is not acceptable (then a wire change is a separate plan).

## Files Affected

`lib/state/workout/timer_manager.dart`; `test/wrist_pause_resume_adoption_test.dart` (new); `test/watch_timer_adoption_test.dart`; `docs/state_management/workout_state.md`; `docs/watch_session_capture.md`; at most one Swift test in `watch/watchos/Tests`. Read-only dependents (must stay green): `lib/state/workout/session_core_io.dart`, `lib/state/watch/watch_timer_adoption.dart`, `lib/state/watch/watch_timer_push.dart`, `test/watch_timer_push_test.dart`, `test/watch_timer_adoption_screen_test.dart`, `test/remote_work_timer_state_test.dart`, `test/timer_start_closes_session_rests_test.dart`, `test/stale_watch_timer_adoption_test.dart`.

## Notes

- Order: P0 → P1 → P2, serial, after 121b P1. Do not commit P0 alone.
- Track: phone (state), plus at most one Swift pin test. No wire, no engine, no screen change. Size: about 35 production lines, about 500 test lines, 3 phases: within budget.
- Known limit (accepted, same family as 121b): two distinct intervals starting inside one tolerance window would be treated as one by the same-interval rule.

## Noticed, not planned

- A rest paused or resumed on the wrist never reaches the phone (`WatchTimerAdoption._wireKinds` has no `rest`); the phone→wrist direction works (S-7302). Own plan if the owner wants "pause pauses both" for rests.
- The wrist applies phone timer frames last-write-wins by arrival, so an out-of-order or redelivered older phone pause frame could regress the wrist's newer state; the phone has the accumulated-pause order key now, the wrist does not. Needs a device observation first.
- A wire version counter would remove the simultaneous-action drift (D-5); not worth a protocol change today.

## Progress

- [x] P0 red tests (state file 24 pass / 22 red; graph group 9 red, 27 pass; S-12636 passes today by construction)
- [x] P1 same-interval rule (timer_manager.dart only)
- [x] P2 docs (two sentences, written by the governor)
- [x] Mutations M1-M5, M7-M9, M11, M12 killed (governor, in place); M6 and M10 pinned by 121b S-12159 / the untouched guard order
- [x] Review (crew-reviewer): 1 blocker (stale doc comment) and 1 major (row shape omitted accumulated pause/planned length) fixed

## Assumption Log

- No Swift pin added (P0 step 4): the engine is unchanged and S-12635's second half already runs a phone pause/resume frame through the real engine.
- S-12631/32/35 stamp the wrist's pause in whole milliseconds, as the Swift wrist does; a microsecond stamp read as an echo.

## Feedback

[empty]
