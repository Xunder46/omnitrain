# Review — 19b, a frame that did not get through is owed, never forgotten

Plan: `2026-10-08-19b-honest-delivery-plan.md`. Evidence: `2026-10-08-19b-honest-delivery-plan.evidence.md`.
This file is the Code Reviewer's; it stays empty until a phase runs. Append findings, never rewrite the
plan's or the evidence's text.

## What this review must check (the plan asks for all of these)

1. **Diff vs Predicted Files** — out-of-bounds files and untouched predicted files are both findings.
   Per file, the diff must match the phase item that predicts it (line ranges are the plan's estimate,
   not a promise; symbols are).
2. **Scenario conformance** — for each S-id in the phase's Done Criteria: the test exists, its fixture
   matches the plan's enumeration value-for-value, its expected outcome matches, and its red-at-base
   evidence is in the `.evidence.md`. A scenario asserted through a rule that cannot reach it on the
   fixture (a floor, a gate, a higher-priority signal) is a finding.
3. **Impact Check re-run** — every row of the plan's Impact table re-runs its own grep, and every named
   dependent's suites are green. An unlisted reader of a touched surface is a finding, not a shrug.
4. **Parity across the stacks** — the analogue here is the twin: `WatchSessionEngine` (Dart) and
   `WatchSessionEngine` (Swift) must produce the same replayed frame for the same stored row (S-212),
   and the two `sync` implementations must place the replay identically (S-216).
5. **Assumption Log adjudication** — RATIFY (promote to a D-x) or REVERT (open a remediation
   sub-phase). A RATIFY is required for: the doubles sweep's shape (D-200), the four rewritten existing
   cases (Phase 2 item 7), Phase 3's test-file choice, and any deviation from D-197's five sites.
6. **The deliberate AC-4 exception** (S-215) is read as designed: one extra `session_lifecycle` per
   catch-up while the wrist holds a terminal session, idempotent on the phone — not as a duplicate-frame
   defect. If the reviewer disagrees, it is a `## Feedback` line for the planner, not a remediation.
7. **Device-check honesty** — no agent claims a watch-app build or a paired run: `swift-test` covers the
   package only, and `ios/OmniTrain Watch App/ContentView.swift` is the governor's simulator build.
8. **Quantified defects** — every finding states the count, at least one example, and the root-cause line
   (`file:line` of the code that produced it). No "seems fragile".
9. **Every defect gets a structural guard** — a permanent test that makes the defect class impossible to
   reintroduce, inside a remediation sub-phase (`### Phase X.Y` in the plan, `BLOCKS Phase X closure`).

## Findings

F1–F9 in `## Code review 1 (19b)` below — **1 blocker** (F6), **1 major** (F1, pre-existing 19a → routed to a
follow-up plan), **7 minor** (F2–F5, F7–F9). Each line carries its `file:line`; F1, F2, F5 and F6 name the
guard that keeps the class out. Item 6 is read as designed, not as a defect: S-215's one extra
`session_lifecycle` per catch-up is idempotent on the phone (S-213/S-215 assert the no-op).

## Evidence re-run

| Checklist item | Check run | Result |
| --- | --- | --- |
| Full suite (4c) | `.github/copilot/scripts/macos/gateway.sh test` | exit 0 — `01:50 +4133 ~1: All tests passed!`; the plan's baseline for this PR |
| Watch package (4c) | `.github/copilot/scripts/macos/gateway.sh swift-test` | exit 0 — `Executed 348 tests, with 0 failures`; matches Progress |
| P2's guards at their base (2) | `prove-red 979a691 test test/watch_session_auto_push_test.dart` | RED — 9 assertion failures, all "the owed frame is not offered again": S-83 `:101`, S-203 `:140`, S-200 `:159,:170`, S-201 `:182,:194`, S-205 `:205`, S-211 `:220`, S-218 `:232` |
| P3's guards at their base (2) | `prove-red 0f7aaff test test/live_mirroring_test.dart` | RED — 3 assertion failures: S-216 order `:1388` (the recorded step log shows no replay), S-216 reachability, S-215 repeat `:1416` |
| P1 and engine guards at their base (2) | `prove-red 3f5ee04 test test/watch_transport_test.dart`; `prove-red 0f7aaff test test/watch_session_engine_test.dart` | RED, compile-level only (`watch_delivery.dart` absent; `replaySessionEnd` undefined) — proves the type, not the reason; the evidence file's mutation rows carry the assertion-level proof and the plan discloses the engine case |
| Diff vs Predicted Files (1) | `git-diff 3f5ee04 --name-status`, then `git-show` per phase | conforms per phase; the one unpredicted surface is `lib/state/watch/watch_incoming_router.dart` (F3 — the change is disclosed in the Assumption Log and evidence, only the ledger text is stale) |
| Docs (4d/4e) | reader sweep over every changed file against each doc's scope block | F5 (a pointer that no longer renders as one name), F6 (a contract line made false), F7 (remedy); no prohibited content added |

## Assumption Log adjudication

| Entry (phase) | Verdict | Why / the D-x it was promoted to |
| --- | --- | --- |
| The doubles sweep's shape, D-200 (P1) | RATIFY | The sweep is what makes `undelivered` reachable in tests without a radio; recommend promoting its shape to a numbered decision so the next PR reuses it |
| The projection test reads the frame rather than the report (P1) | RATIFY | Keeps the assertion about the wire, not the callback |
| No Swift production change; the Swift test logs the wire (P3/P4) | RATIFY | S-212 asserts the twin value-for-value, and `swift-test` is 348/0 |
| `_resetEndsSent` / `resetAttempted` — one reset attempt per pass (P2) | RATIFY · promote | The only guard against the reset and the tail landing twice; recommend making it D-204 |
| `answeredReset` suppresses the flush after a reset answer (P2/P3) | RATIFY · promote | No test names it, but mutation (e) reddens 5 cases (S-6, S-86, S-172, S-180, S-182), so its teeth are behavioural |
| `forgetBaseline()` on an undelivered push (P2) | RATIFY | Guards the tail-replay-after-silence pair |
| The four rewritten existing cases (P2 item 7) | RATIFY | Old/new pairs are quoted at `evidence:289-295` |
| S-213's file choice, `pr4_session_controls_test.dart` (P3) | RATIFY | Green at base by design (F9); the red guards sit on the wrist |
| Rating 8 → 4 to fit the contract JSON (P3) | RATIFY, with F8 | The fixture text still says 8 while `watch_effort_rating_contract.json` caps at 5 |
| No deviation from D-197's five owed sites (P2/P3) | RATIFY | S-217 pins the ended-session snapshot as the phone's own end |
| F1's missing terminal-status clause | → follow-up plan | A pre-existing 19a surface, not this PR's to fix, but it needs an owner and a guard |

No entry REVERTs; nothing is ESCALATEd.

## Remediation sub-phases opened

None inside 19b. F3–F8 are documentation and ledger edits in one round, and the two that carry behaviour
carry their guards with them (F5: extend `test/docs_indexing_contract_test.dart` to reject an inline-code
span with an unmatched inner backtick; F6: a contract test over `PROTOCOL.md`'s version-history table — a
clause a later row quotes as superseded must be marked in its own row).

The two items that need a plan leave this PR for a follow-up (they are pre-existing 19a surfaces, untouched
by 19b's diff), each with the guard that makes its defect class impossible to reintroduce:

1. **F1** — status gate on `watch_incoming_router.dart`'s rows 1–2. Guard:
   `test/watch_session_finish_test.dart`, "a terminal `W` announced while the phone holds `P` is not
   answered with `abandoned(W)`, and the wrist's row stays `completed`" (red at 19b's HEAD).
2. **F2** — one sender for the reset answer. Guard: an S-181-shaped frame count per receive, red before the
   fix.

## Verdict

**blocked — F6.** One clause of `watch/sync_protocol/PROTOCOL.md:564` was made false by this PR: it still
says a push the transport cannot carry is dropped rather than queued, sitting beside a citation this PR
refreshed to the test that proves the opposite. F5 (an unreadable verification pointer) and F7 (corrected
behavioural prose where deletion-plus-pointer is the remedy) ride the same one-round pass, with F3, F4 and
F8 as plan/evidence text fixes.

Nothing else blocks: every acceptance criterion is met, every scenario has a passing fixture-conformant
test, the diff matches Predicted Files except the disclosed router change, both suites are green under the
reviewer's own run (4133 ~1 Flutter, 348/0 Swift), and no code change is requested. F1 and F2 are
pre-existing 19a defects and belong to a follow-up plan, not to this PR.

## Code review 1 (19b)

Range reviewed: `3f5ee04..HEAD` (41d26fc). Findings F1.. (file:line, blocker / major / minor).
Appended as found; nothing above is rewritten.

### Findings

F1 (major — pre-existing 19a, routed to a follow-up plan) `lib/state/watch/watch_incoming_router.dart:141-151` — the row-2 reset answer (`reportLifecycleFor(named, abandoned)` + `sendState(p)`) fires whenever the wrist announces its own `W` while the phone holds a different `P`, with no clause on the status that announcement carries; the wrist's `_applyLifecycle` (`lib/watch/session/watch_session_engine.dart:606`, "the most recent status wins", writing a row stamped `parseUtcIso(envelope['sentAt'])`) then supersedes its own `completed` `W`, while the phone ignores that same end (`_adoption.onLifecycle` returns unless the phone holds exactly that id) — a wrist-finished session is lost on both sides. Reachable at 19a alone (its catch-up already announced `W`); 19b neither causes nor widens it (the new replay is one extra frame the phone ignores). Fix (follow-up, not this PR): gate the row-2 answer on the announced session not being terminal — 19b's replay now sends `session_lifecycle completed(W)` immediately before the snapshot, so the status is in hand — or adopt the terminal end before resetting. Guard: `test/watch_session_finish_test.dart` case "a terminal `W` announced while the phone holds `P` is not answered with `abandoned(W)`, and the wrist's row stays `completed`". → @planner.

F2 (minor — pre-existing 19a, follow-up) `lib/state/watch/live_session_mirror_state.dart:246-259` re-asserts `P` in the same receive in which the router sent `sendState(p)` (`watch_incoming_router.dart:149`), so `P` reaches the wrist twice per reset answer under two `messageId`s. Fix: one sender for that answer — `answeredReset` (F3) already tells the wiring the reset was written. Guard: an S-181-shaped frame count. → @planner (with F1).

F3 (minor — ledger stale) `docs/plans/2026-10-08-19b-honest-delivery-plan/2026-10-08-19b-honest-delivery-plan.md:31` (D-203 "unchanged by 19b") and `:100` (Impact row "Untouched by design") both name `lib/state/watch/watch_incoming_router.dart` as unmodified; the diff changed it (`watch_incoming_router.dart:33-64,121,150,166`; `watch_sync_wiring.dart:235,239,249`). The change is disclosed in the Assumption Log (`:204`) and pinned by evidence mutation (e) (`...plan.evidence.md:117`, 5 failures when the flush is made unconditional), so only the text is wrong. Fix: name `answeredReset` as the router's sole 19b change in D-203 and in the row. → @planner.

F4 (minor — wording) `...plan.evidence.md:205` and `...plan.md:224` call the `PROTOCOL.md` citation "a test name that exists nowhere": the name existed at base (the S-83 case in `test/watch_session_auto_push_test.dart`) and was renamed by this PR's own Phase 2 — `:1024` now reads "…reported per attempt…, and the same state is offered again". The citation fix was required; the reason should read "renamed by Phase 2". → @planner.

F5 (minor — broken verification pointer, introduced here) `docs/watch_session_sync.md:478` wraps a test name that itself contains backticks in a code span, so the span ends early and the S-203 citation no longer renders as one name; the same shape sits at `...plan.evidence.md:100,196,294`. Fix: drop the outer backticks (or quote it plainly). Guard (cheap): extend `test/docs_indexing_contract_test.dart` to fail on an inline-code span carrying an unmatched inner backtick. → @developer.

F6 (blocker — a document this PR made false) `watch/sync_protocol/PROTOCOL.md:564`: the 2026-10-06 "phone's own push" row still reads "a push the transport cannot carry is dropped rather than queued", while that same row's citation was updated by this PR to `S-83 a failed send is reported per attempt, changes nothing, and the same state is offered again` — a test proving the opposite of the row's own clause; the supersession is declared only in the next row (`:569`), which a reader who lands on the push rules may never reach, and the refreshed citation makes the row read as maintained. Fix: strike the clause and mark it superseded in place (or keep the old citation in that row and carry the new name only in the new row). Guard: a contract test over the version-history table — a clause a later row quotes as superseded must carry an inline marker in its own row. → @developer.

F7 (minor — remedy, not falsity) `docs/state_management/watch_surface.md:99`, `:181`, `:326`: three sentences that had gone false were edited into corrected behavioural prose ("is not marked sent…", "Nothing is queued in the app layer"). The page is no longer false and the "Verified by" lists were extended, but the standing remedy for stale behavioural prose is deletion plus the pointer, not a corrected description that will decay the same way. Fix: delete the restated prose, keep the pointers. → @developer.

F8 (minor — plan fixture) `...plan.md:58,61` fixtures say "rating 8"; `watch/contract/watch_effort_rating_contract.json` caps a rating at 5, so the tests use 4 (Assumption Log `:214`). Fix: write the corrected fixture into the scenario text, not only into the log. → @planner.

F9 (minor — guard inventory, no action) S-213 (`test/pr4_session_controls_test.dart`) is green at base by design: it pins the phone's *unchanged* consumption of the replayed frame, and Phase 3's red guards live on the wrist (`test/live_mirroring_test.dart` S-215/S-216 — red at `0f7aaff` in my own re-run, 3 assertion failures) with the two mutation rows in the evidence file. No new behaviour of this PR is pinned only by a green-at-base test; recorded because the plan declares the negative guard openly.

### Checks I ran

- `.github/copilot/scripts/macos/gateway.sh test` → `01:50 +4133 ~1: All tests passed!` (exit 0; matches the plan's baseline 4133 ~1).
- `.github/copilot/scripts/macos/gateway.sh swift-test` → `Executed 348 tests, with 0 failures` (exit 0; matches the Progress claim 348/0).
- `prove-red 3f5ee04 test test/watch_transport_test.dart` → RED at base, compile-level only (`watch_delivery.dart` absent), so it proves the type, not the reason; mutation rows (a)/(a′)/(a″) in the evidence file carry the assertion-level proof.
- `prove-red 979a691 test test/watch_session_auto_push_test.dart` → RED at `979a691`, 9 assertion failures, all the guarded shape (`Expected: an object with length of <1>/<2> / Actual: []`, the owed frame not re-offered): S-83 `:101`, S-203 `:140`, S-200 `:159,:170`, S-201 `:182,:194`, S-205 `:205`, S-211 `:220`, S-218 `:232`.
- `prove-red 0f7aaff test test/watch_session_engine_test.dart` → RED at base, compile-level only (`replaySessionEnd` undefined, `:2211,:2247,:2269,:2283`) — the plan's P3 evidence already discloses this and pins the orchestrator instead.
- `prove-red 0f7aaff test test/live_mirroring_test.dart` → RED at `0f7aaff`, 3 assertion failures for the guarded reasons: S-216 order (`:1388`, step log `['routines','send:observations_up','send:session_snapshot']` — no replay), the S-216 reachability gate, S-215 repeat (`:1416`, `Actual: []`).
- Reader sweep (file-search tool, since shell `grep` is denied here): `sendState(`/`deleteEntryAs(`/`reportLifecycleFor(` match the Impact table's readers; `replaySessionEnd` occurs exactly twice as a definition and twice as a call site (`WatchSyncOrchestrator.swift:102`, `watch_sync_orchestrator.dart:96`); `WatchDelivery` occurs in every transport implementer plus both helpers and the six test files the plan lists; `answeredReset` occurs in exactly two production files and in no test (its teeth are mutation (e)).

## Fix round 1 (developer, 2026-10-08 — documentation and plan text only)

No `lib/`, `test/` or `.swift` file changed. The round edits `watch/sync_protocol/PROTOCOL.md`,
`docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, this plan's `.md` and
`.evidence.md`, and this file. Evidence and the pasted check outputs are in the evidence file's
`## Fix round 1`.

- **F1 — RATIFIED as intended, no change.** Decided by the owner on 2026-10-08: the phone is the authority; when the phone holds a different session the wrist's old session is discarded, including one the wrist had itself finished, and the wrist-side status flip `completed → abandoned` changes nothing the owner keeps. The guard suggested above belongs to the follow-up plan with F2.
- **F2 — no action, recorded for a later PR.** Pre-existing 19a, minor: the phone answers one reset with two `P` snapshots that are identical in content under different `messageId`s, harmless by idempotence.
- **F3 — fixed.** D-203 and the Impact row now name `answeredReset` as `watch_incoming_router.dart`'s sole 19b change — the receipt flag that stops `createWatchSync`'s closure from flushing the 19a reset twice — and no longer list the router as unmodified; the row carries its readers (`watch_sync_wiring.dart:235,239,249`) and the tests mutation (e) reddens.
- **F4 — fixed.** The plan's Phase 4 entry and the evidence row now read "the name at base, renamed by Phase 2" (with the new name) where they claimed the citation existed nowhere / was dead.
- **F5 — fixed.** The outer code spans are dropped so each citation reads as one name: `docs/watch_session_sync.md:478`, and the evidence file's `:100`, `:104`, `:115`, `:196`, `:294` (`:104`/`:115` carry the same defect the three named rows have). The suggested inline-code contract guard is **not done: separate PR**.
- **F6 — fixed (blocker cleared).** `PROTOCOL.md:564`'s clause is struck in place, marked "superseded 2026-10-08" and pointing at the honest-delivery row below, so the row no longer contradicts its refreshed citation. No schema, validator, fixture or protocol-version change. The suggested version-history contract guard is **not done: separate PR**.
- **F7 — fixed.** Three restated passages deleted (`docs/state_management/watch_surface.md:99`, `:181`, `:326`); the diff is deletion-only, the `Verified by` pointers stay, and the page moves further under its ceiling. The invariant sentences the deleted prose hung off stay — both are true sentences and neither is a behaviour description.
- **F8 — fixed.** S-212, S-213 and S-216 each carry the "Amended 2026-10-08 (review 1, F8)" note, the fixture's rating being 4 against a contract that caps a rating at 5. Nothing renumbered.
- **F9 — no action.** Recorded as-is: S-213's green at base is the plan's declared negative guard.

Checks after the round: `test test/docs_indexing_contract_test.dart test/sync_protocol_fixtures_test.dart test/watch_reconciliation_cross_stack_test.dart` → `All tests passed!` (113/0, exit 0); `lint` → `196 issues found.` (exit 1 — the plan's baseline of 196 pre-existing info notices, 0 errors).


