# Review: plan 136 · P1 · ff398e1a7ec18409d9fc8c890bf35d2fde656e69 (working tree)

Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 2 · tests: not run (brief forbids; the lead's numbers stand: new file 8 tests green, four files 142 passed, mutation 6/7 killed)
Diff vs Predicted Files: conforms (brief scopes everything to the two files; only those two were read for the diff)

## Answers to the brief's four questions

### 1. The `_stale` bookkeeping (a re-offer never repeats, a later wrist rest is not blocked, session change resets) — OK

(a) **Writer vs reader, same tolerance — OK.** The write (`watch_timer_push.dart:425-435`): after `_send(session.id, clears)` returns delivered, per kind either `_stale[kind] = _adopted.remove(kind)` or `_stale[kind] = reconciled[kind]`; for the plan-136 step `reconciled['rest'] = superseded` and `superseded` is the mirror's own copy verbatim (`slotId: held['sessionExerciseId'], startedAt: held['startedAt']`, `watch_timer_push.dart:393-397` with `_wristRestSupersededBy` at 702-707). The reader (`watch_timer_push.dart:690-695`) compares `_restStartWithinTolerance(stale.startedAt, held['startedAt'])` — the same `_restStartWithinTolerance` (abs diff ≤ 500 ms, symmetric, 733-739) the neighbouring readers use. Since the stale record is the mirror's own start string, the comparison is trivially true for the cleared copy, and it also recognises the millisecond-later wrist counterpart of an adopted rest (the case `_wristHolds` documents at 556-558). One asymmetry noted, not a finding: `_wristHolds`' stale guard (553-562) also compares `stale.slotId == held['sessionExerciseId']`; `_wristRestSupersededBy` compares only the start. A rest never carries a slot anywhere in this file (`_composeWanted`'s rest block has no `sessionExerciseId`, and the mirror only holds what the wrist's frames name), so both sides are null in practice and the omission cannot change a verdict; had it been kept, nothing would differ.

(b) **A later wrist rest is not blocked — OK.** The stale guard is a start comparison within 500 ms (`watch_timer_push.dart:690-695`). A wrist rest started after the cleared one differs from the stale start by at least the cleared rest's own span, far beyond 500 ms, so the guard does not fire and the copy is evaluated by the instant rule (698-707). An old stale entry is never a permanent veto: nothing is keyed by copy identity, only by near-equal starts.

(c) **`_stale` resets with the session — OK.** Both ledger-reset branches in `_pushOnce` clear it: the no-session branch (`watch_timer_push.dart:300-307`, `_stale.clear()` at 305) and the session-id change branch (310-316, `_stale.clear()` at 313), the same maps `_delivered`/`_adopted`/`_owed` clear with.

### 2. A phone timer only PAUSED or RESUMED (same start) — OK

A pause or resume changes `state`, `pausedAt` and `accumulatedPauseMs`; it does not change `startedAtMs`. `TimerManager.resumeTimedEntry` keeps the instance's start (sets `state`/`pausedAtMs`/pause duration only, `timer_manager.dart:1069-1096`; same for `resumeRound` 695-722), and `_composeWanted` reads `startedAtMs` straight into `startedAt` (`watch_timer_push.dart:466-496`). So the step's decision input never moves across the rest's start by a pause/resume.

What happens on that flush: `wanted` still has no `rest`, the mirror rest is untouched by the step; if the clear was delivered, `_stale['rest']` (425-435) makes `_wristRestSupersededBy` return null — no repeat (guarded by S-13604, `test/watch_rest_cleared_on_phone_timer_test.dart:384-408`); if the clear was never delivered, the pause-triggered full flush re-offers it — the desired D-13601 behaviour; and even a duplicate `rest: null` is a wrist-side no-op (`_stopTimerFromMessage` refuses to stop a newest timer that is already stopped, `watch_session_engine.dart:815-821`). No wrong firing has a path.

### 3. Clears-only pass clearing a newer wrist rest whose mirror copy shows an earlier start — Major

Yes, there is a path, and it is the memory the D-13601 re-offer itself keeps. The step runs in every pass including a clears-only one (clearsOnly filters only `next`, `watch_timer_push.dart:399-424`; the step at 390-397 already ran). `flushClears` fires on every inbound wrist frame (`watch_sync_wiring.dart:414-417`) and on link recovery (439-445). The wrist side of `{rest: null}` stops the newest rest of the kind blind: `_timerActionFor` maps a named null to stop "either way" (`watch_session_engine.dart:740-749`) and `_stopTimerFromMessage` appends a stop to whatever the newest rest row is, with no start comparison (815-845) — a rest is deliberately exempt from the work kinds' earlier-start-wins guard (786-797).

Chain: phone interval starts 09:03 while the mirror holds wrist rest R1 (09:00, not stopped) → the step offers the clear; the radio refuses it (unreachability is the case S-13605 itself exercises) → `_stale` stays empty (only written after a delivered clear, 425-435) → the wrist, out of reach, ends R1 and starts R2 (09:05) and those report frames never reach the phone → link recovers → `flushClears` → the mirror still holds R1 → the step's instant comparison sees 09:03 after 09:00 and re-sends `rest: null` → the wrist stops R2, the newer rest D-13603 promises never to clear. Two smaller windows in the same shape: wholly-lost wrist frames within reach (the transport's designed-for failure), and the link-recovery race where `flushClears` (416→442) can run before the wrist's reconnect snapshot corrects the mirror.

Severity, and why not a Blocker: the code implements D-13601/D-13603 as decided; what degrades is the protection's premise — the mirror being current — and this file already trusts the mirror to that degree in pre-existing readers (`_wristHolds`' earlier/identical answers, 43b3 D-3; `_loggedWristTimer`). The phone has no currency signal to do better from the phone side alone. Harm is bounded: the newer rest stops one pass early and its window still travels as a rest observation, so nothing is lost, but the user's rest ends when it should not. Smallest fix (one of): (i) narrow the re-offer — send the rest-superseded clear only on a full pass (a phone-state trigger), accepting that a refused first clear waits for the next phone change; or (ii) keep the re-offer and record the residual in the Assumption Log plus one sentence in `docs/watch_session_sync/what_does_not_sync.md` (the docs phase is still pending, so the sentence can ride P2). No test can assert the stale-mirror case honestly from the phone side; S-13602 guards only the current-mirror case, which is why no test gap is charged for it here.

### 4. S-13601..S-13608 coverage — all eight asserted; two text-level gaps (Minor)

Every scenario has its own test: S-13601 314-336 (asserts the `rest`→null frame exists and the wrist engine's rest ends), S-13602 337-358, S-13603 359-383, S-13604 384-408, S-13605 409-437, S-13606 438-456, S-13607 457-474, S-13608 475-490, all in `test/watch_rest_cleared_on_phone_timer_test.dart`. Gaps:

1. [Minor] `test/watch_rest_cleared_on_phone_timer_test.dart:429-433` — the plan's S-13605 row also claims "the interval start is not re-sent twice"; the test asserts only the clear count (`timerFrames().where(clearsRest).length, 1`) and nothing about the `elapsed` start frames across the two passes. The mutant the row names (read the clear from `next` instead) is still killed by the clear-count assertion, so the row's guard stands; only the second clause of the expectation is unevidenced. Fix: one added expect on the `elapsed` frames, or drop the clause from the plan row.
2. [Minor] `test/watch_rest_cleared_on_phone_timer_test.dart:463` — the plan's S-13607 fixture says "starts an interval on another effort"; the test starts it on the same slot `startTimedEntry(_slotId, 0)`. The asserted behaviour (exactly one `rest: null` across both flushes, D-13601 not doubling the existing S-9924 clear) is protected either way, but the fixture does not match the row's text. Fix: a second slot in the harness seed, or change the plan row to "same effort" — not chased further per the brief's scope.

## Assumption Log rulings

- A-1 (the owner's rest was wrist-owned): ratified — the probe R1 evidence and S-9924's existing coverage are the backing; view matches.
- A-3 (mutation pass, the surviving `!clears.containsKey('rest')` equivalent mutant): ratified — I read the condition at `watch_timer_push.dart:395`; the map key and null value are identical on either side.
- A-2 (architect phase skipped): ratified for a one-production-file unit with a probe-carried fixture basis.

## Scenario coverage

S-13601 → test/watch_rest_cleared_on_phone_timer_test.dart · S-13601 the clear is its own frame and the wrist's rest ends
S-13602 → same file · S-13602 no frame clears the newer wrist rest (current mirror only; the stale-mirror exposure is finding 3)
S-13603 → same file · S-13603 no frame clears the ended rest
S-13604 → same file · S-13604 later passes and a stale mirror copy send no second clear
S-13605 → same file · S-13605 the clear is sent when the wrist is back in reach (the "start not re-sent twice" clause unasserted: finding 1)
S-13606 → same file · S-13606 the clear is sent for a paused mirror rest
S-13607 → same file · S-13607 exactly one rest:null frame travels (fixture on the same slot, not "another effort": finding 2)
S-13608 → same file · S-13608 the phone runs its own rest beside a running interval

## Docs delta

| Doc | Change | Status |
|---|---|---|
| docs/watch_session_sync/what_does_not_sync.md | MODIFIED | pending (P2 in flight; if taken, fold finding 3's residual sentence into this row) |
| docs/rest_tracking.md | ADDED | pending (P2 in flight) |
| docs/state_management/watch_surface.md | ADDED | pending (P2 in flight) |

No doc edit outside the table is implicated by the diff.
