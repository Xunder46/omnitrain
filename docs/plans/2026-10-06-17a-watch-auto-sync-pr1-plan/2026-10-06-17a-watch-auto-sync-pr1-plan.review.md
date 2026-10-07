# Review — watch-auto-sync PR 1 (`17a`)

Plan: `2026-10-06-17a-watch-auto-sync-pr1-plan.md`. The reviewer (@code-reviewer) writes findings here;
one-line Progress items stay in the plan.

## Checks (each needs evidence, not a claim)

| # | Check | Expected | Actual |
|---|---|---|---|
| 1 | Diff versus the phase's Predicted Files — out-of-bounds files **and** untouched predicted files are both findings | | ⚠️ 28 files, +2992/−276 (`47c0f50..HEAD`). All inside §Files Affected except `PROTOCOL.md` (governor) and the series index (A-16) — both recorded. Untouched-but-predicted: `test/watch_transport_test.dart` (its "if it names the label" never fired — F2), `test/live_mirroring_test.dart` (A-11). **The brief's `b14b7d6..HEAD` also contains plan-16's three commits (already reviewed)** |
| 2 | Every Done Criteria command run, counts pasted | | ✅ Observed: `gateway.sh test` → `01:42 +4004 ~1: All tests passed!`, exit 0 (log `.work/gateway/test-20261006-201208-82676.log:4634`). Per-phase counts in the evidence file (`swift-test` 315/0, `lint` 196/0) — swift-test not re-run by me |
| 3 | Per-S-x test and fixture conformance — the fixture names the held *different* session where the refusal is tested (S-77, S-78), and the adversarial rows (S-79's phone-written vs wrist-written timer) | | ✅ S-77's Dart fixture holds `s-2`; Swift S-77/S-78 build foreign-named sessions; S-79 has the phone-written (`tms-`) and wrist-written rows in both stacks; S-83 drives a real failing radio; S-84 seeds a real finished row and calls the real `loadHistoricalSession`. ❌ no scenario covers a **second** session in one app run (F1), and none covers the refused-adoption case's end rule (F6) |
| 4 | Impact Check rows re-run: every grep in the plan's table re-executed; every named dependent's tests green; an unlisted reader is a finding | | ⚠️ 3 drifts (F2): `test/watch_transport_test.dart:99` reads no `noAutoSyncLabel`; `projectedSession()` now has two production readers, not one; the `loadHistoricalSession` row omits `watch_session_adoption_bridge.dart:437`. Every named dependent's tests are green (full suite) |
| 5 | Two engines, one rule set: each D-78/D-79/D-80 rule present with identical refusal semantics in `WatchSessionEngine.swift` and `lib/watch/session/watch_session_engine.dart` | | ✅ D-78 refusal block: Swift `:448-466` / Dart `:461-466`, same three conditions, same "return before any store". `guardSession` Swift `:1479` / `_guardSession` Dart `:663` (four callers each). `senderWroteTimer` Swift `:1488` / Dart `:672` (`tms-`). `adoptTimers` Swift `:646` / Dart `:647`. ⚠️ `captureSessionEnd` has no Dart twin (A-8, pre-existing) → F5 |
| 6 | Append-only preserved: no refusal writes a row; no stored row is rewritten | | ✅ Both engines return before any append; S-77/S-78 assert no stored row and no emission; the S-35 re-statement path leaves the held record unrewritten |
| 7 | No echo loop: a wrist frame never produces a frame (D-82), and a phone push is never a reply | | ✅ `watch_sync_wiring.dart` awaits `rebaseline()` after every incoming frame; `sendState` never applies locally, so a push is never an answer. S-80/S-81 assert it. ⚠️ one leak window (F3); ⚠️ the refused-adoption case answers an applied frame with a lifecycle (F6) |
| 8 | `lib/state/` imports no concrete repository (`HiveWorkoutRepository` invariant) | | ✅ grep clean under `lib/state lib/features lib/widgets lib/core`; only `lib/main.dart` (the DI site) |
| 9 | PROTOCOL.md amendment is additive, dated 2026-10-06, and each rule names the test that proves it | | ✅ Additive (two dated rows, `:529`, `:530`), no schema or version change, and every named test exists (grepped, both stacks). ❌ `:426-436` over-claims (F1) |
| 10 | Docs: no sentence claims sync is manual; every behaviour sentence names a real test; the touched docs stay under the 52 KB band | | ⚠️ Sweeps clean apart from two intended hits (`watch-app-setup-and-qa.md:389` asserts the label is gone; `watch_session_sync.md:234` names the true residue). `:130-139` over-claims (F1). Sizes: the 64 KiB gate (`test/docs_indexing_contract_test.dart`) is green; raw byte sizes need a shell (Open questions) |
| 11 | Assumption Log adjudication — every entry RATIFIED (promoted to a D-x) or REVERTED with a remediation sub-phase | | ✅ A-1…A-14 RATIFIED (A-12 with a note), A-15/A-16 recorded, A-8 → F5 — see below |

## Code review 1 — PR 17a (Phases 1, 2, 3A, 3B)

Range `47c0f50..HEAD`, 28 files, +2992/−276. Full suite: `4004 passed, 1 skipped, 0 failed` (exit 0).
Layers in scope: `lib/state/watch/`, `lib/watch/`, `watch/watchos/`, `watch/sync_protocol/`, `test/`,
`docs/`. Skipped: `lib/data/` (models and repositories untouched), `lib/features/` (one string
removed in `lib/watch/start/` only), `lib/widgets/`, `lib/core/`.

## Findings

### F6 — blocker · `abandoned` is announced for a session the phone never held

`lib/state/watch/watch_session_auto_push.dart:124-131` (`row == null` ⇒
`reportLifecycle(abandoned)`) · `lib/state/watch/watch_incoming_router.dart:97,100` (the mirror applies
the frame *before* the bridge considers it) · `lib/state/watch/watch_session_adoption_bridge.dart:424-427`
(D-10 refuses the adoption and writes no row) · `lib/state/watch/live_session_mirror_state.dart:484`
(the lifecycle is sent, naming the mirror's session).

Sequence: the phone holds its own active session P; the wrist is running its own session X and sends a
snapshot for it. The mirror applies X (so `isActive` is true and `sessionId` is X), then the bridge
returns `refusedConflict` — the documented, tested D-10 outcome — and **no row for X is ever stored**.
The next `WorkoutState` notification (any set logged in P) runs `_announceEnd`: `getSession(X)` is
null, which D-81 reads as "the phone discarded it", so the phone sends `abandoned` for X. The wrist
holds X, so D-79's `guardSession` lets it through: the wrist's live session is ended by the phone, and
the wrist captures a `session_end` for a workout the user never finished — a phantom abandoned session
in the phone's history at the next import. `row == null` is overloaded: it means "discarded" only for a
session the phone adopted.

**Fix:** gate both announcements on the phone having held the session — pass
`adoption.holdsSession` (already wired as `phoneOwnsSession` in
`lib/state/watch/watch_sync_wiring.dart:143`) into the push and require it for `sessionId` before
reading the row; a session the phone refused is the wrist's own business and is announced nothing.
Add **S-86 — a refused adoption announces nothing** and its test (phone in P, wrist in X, a
notification ⇒ no `session_lifecycle` frame, the wrist's X still active).

→ **@developer** · structural guard: the S-86 test, which fails today.

### F1 — major · the end announcement fires once per app run, not once per session

`lib/state/watch/watch_session_auto_push.dart:120` (`_announceEnd` keys on `_mirror.isActive` and
`_mirror.sessionId`) · `lib/state/watch/live_session_mirror_state.dart:340` (`sendState` never applies
locally) · `:504` (`_sendOwn` is the only path that advances the mirror, and only the push's own
lifecycle goes through it).

The mirror's session changes only when a wrist frame names a new one, and the wrist sends a snapshot
only inside its Sync action (A-16's own finding). So after the first session ends, the mirror holds
that session as `completed` for the rest of the process: the phone's next session Y is pushed as a
snapshot (the composition path does not read the mirror) and the wrist adopts it, but Y's end or
discard is never announced. The wrist is left holding a session the phone has closed, exactly what
D-81 exists to prevent, until the user taps Sync.

Two contract sentences state the general case and are therefore false:

- `watch/sync_protocol/PROTOCOL.md:426-436` — "The phone MUST report its own finish … `completed` …
  `abandoned`, **once each**".
- `docs/watch_session_sync.md:130-139` — "the push that follows reports the session's own `completed`
  lifecycle … so the wrist ends its copy rather than holding a session the phone has closed".

No scenario in the register covers a second session in one run; S-72, S-73 and S-84 all drive one.
D-81 is scoped to "the mirrored session X", so the *decision* is not violated — the *contract prose*
is.

**Fix (one of two, decided by the planner/owner — the reviewer does not choose):**

1. Make the phone's own push advance its mirror (apply the snapshot envelope it just sent), or key the
   announcement on the phone's own projected session id with the mirror's as the fallback; add
   **S-85 — a second session's end is announced too** and its test in
   `test/watch_session_auto_push_test.dart` (two sessions to completion in one process, two
   `session_lifecycle` frames, each naming its own session).
2. Narrow both sentences to "the session the wrist is in" and move the general case to PR 2's index —
   the false general claim must not survive either way (4d: delete the prose and point at the test).

→ **@developer** (option 1) or **@planner** (option 2) · structural guard: the S-85 test, which fails
today.

### F2 — warning · three Impact-Check rows are stale

Plan `:192`, `:194`, `:592` (the `loadHistoricalSession` row, `:197`).

- `:192` cites `test/watch_transport_test.dart:99` as a reader of `noAutoSyncLabel`; the file is
  untouched and a grep finds no such string in it. The row's own conditional ("if it names the label")
  never fired, and the evidence file does not record that.
- `:194` claims "exactly one production reader" of `projectedSession()`; the push adds two more
  (`watch_session_auto_push.dart:80,93`) beside `watch_sync_request_handler.dart:102`.
- `:197` lists three `loadHistoricalSession` callers and omits
  `watch_session_adoption_bridge.dart:437` (and the `workout_state.dart:135` facade). Rated warning,
  not critical: that reader is pre-existing, its behaviour is unchanged, and it is guarded by S-84 —
  so the surface is not unguarded, the row is merely incomplete.

→ **@planner** · guard: each row's own grep, re-run at the next review (4g). No test can guard prose.

### F3 — minor · D-82 can leak one push when the adoption's write lands late

`lib/state/watch/watch_sync_wiring.dart` (the `await push.rebaseline()` after `router.receive(frame)`)
· `lib/state/watch/watch_session_adoption_bridge.dart:435-437`.

`rebaseline()` stores the payload composed at that moment; the adoption's `loadHistoricalSession` and
`_catchUpSessionRow` writes notify `WorkoutState` afterwards, and the pending window then pushes a
payload the rebaseline never saw. Harmless in content (the wrist already holds that session), but it
is the one case D-82's "re-baselined rather than answered" does not hold.

→ **@developer** · guard: a test whose adoption completes after the frame handler returns, asserting
no frame is sent.

### F4 — minor · `flush()` is unguarded and can double-report

`lib/state/watch/watch_session_auto_push.dart:108` (`unawaited(flush())`), `:74-84`, `:120-131`.

`_getSession` is not wrapped: a repository read failure escapes as an unhandled async error and
silently skips the push — D-83 scopes "must not disturb the phone" to the transport only. Separately,
two overlapping flushes can both pass the `_mirror.isActive` test before either memoises, sending a
duplicate `completed`; the wrist's rule makes that a no-op (S-81), so it is bounded, not a storm.

→ **@developer** · guard: a test with a throwing `getSession` (phone undisturbed, no unhandled error)
and one with two overlapping flushes (exactly one lifecycle).

### F5 — escalate · AC-11 is not literally true

`docs/plans/…-plan.md:180` (AC-11, "Every rule above is in both engines") vs A-8:
`captureSessionEnd` is Swift-only, pre-existing, and D-78's ordering has nothing to precede in Dart;
the observable outcomes match.

→ **@planner** · narrow AC-11 to "every rule's outcome" or file the Dart twin in PR 2. No code fix.

## Remediation sub-phases opened

One round, critical plus cheap mechanical, per `.github/copilot/pr-scope-budget.md` §1 "At review":

- **R-1 (F1)** — decide option 1 or 2; if 1, implement and add S-85 + its test; if 2, narrow
  `PROTOCOL.md:426-436` and `docs/watch_session_sync.md:130-139` and record the move in the series
  index. Guard: the S-85 two-session test (red before the fix).
- **R-2 (F2)** — correct the three plan rows; add the transport-test sweep result to the evidence
  file. Guard: 4g re-run.
- **R-3 (F3)** — late-adoption test. Guard: that test.
- **R-4 (F4)** — throwing-`getSession` test and overlapping-flush test. Guard: those tests.
- **R-5 (F6, critical)** — gate `_announceEnd` on the phone holding the session (`adoption.holdsSession`),
  add S-86 + its test. Same seam as R-1, so one round covers both. Guard: the S-86 test (red before
  the fix).

## Assumption Log adjudication

- **A-1…A-4, A-6, A-7, A-9…A-11, A-13, A-14 — RATIFIED.** Each is consistent with D-75…D-84, is
  recorded in the evidence file, and changes no outcome. A-4's `Future<WatchSessionRecord?>` is the
  right way to say "nothing was inserted"; A-9's deferred doc correction landed in Phase 3B.
- **A-5 — RATIFIED.** The file is inside §Files Affected (`:603`) and Phase 3's own step 8; the
  "outside Predicted Files" wording is true only of Phase 1's list. No action.
- **A-8 — RATIFIED as an escalation**, not a silent gap: it is the reason AC-11 is not literally true
  (F5). Promote it to a numbered decision ("the wrist's end-capture is deliberately Swift-only") or
  open the Dart twin in PR 2.
- **A-12 — RATIFIED with a note.** The developer chose the coherent half of a contradictory scenario
  clause rather than escalating it. The choice is right (a payload kept for a retry D-83 forbids is
  dead state), but the scenario text should be corrected so the contradiction is not inherited.
- **A-15 — RATIFIED.** Two `completed` frames are honest and the second is the mirror's G1 answer; the
  test says so in a comment.
- **A-16 — RATIFIED.** Widening the index's cells is exactly the recorded-move discipline the budget
  asks for. Its finding — the wrist sends a snapshot only inside the Sync action — is the mechanism
  behind F1.

## Open questions (defaults taken)

1. `swift-test` was not re-run by me (900 s budget, and it compiles the watch package). Default: trust
   the evidence file's 315/0 plus the green full Dart suite. Re-run it if the F1 fix touches Swift.
2. Raw doc byte sizes cannot be measured without a shell. Default: the 64 KiB gate test is the
   authority, and it is green.
3. The brief's range includes plan-16's three commits. Default: reviewed the 17a-only range
   (`47c0f50..HEAD`) and noted the overlap rather than re-reviewing plan 16.

## Round summary

Critical: 1 (F6) | Major: 1 (F1) | Warnings: 1 (F2) | Minors: 2 (F3, F4) | Escalations: 1 (F5).
Substantive findings: 5 — inside the budget's six, so no split; one fix round (R-1…R-5), each with a
structural guard. Routing: F6, F3, F4 → @developer; F1 (option 2), F2, F5 → @planner.
**VERDICT: CHANGES_REQUESTED**
