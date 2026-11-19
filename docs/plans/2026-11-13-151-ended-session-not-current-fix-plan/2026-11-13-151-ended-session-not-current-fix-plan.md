# Plan 151 — an ended session that is not current stays ended

**Status**: Phase 1 Complete, Phase 2 **Blocked (scope)**
**Owner**: lead | **Developer**: developer agent
**Evidence**: [.evidence.md](2026-11-13-151-ended-session-not-current-fix-plan.evidence.md)

## Problem

The convergence investigation of 2026-11-13 (`docs/plans/2026-11-12-146c-earlier-discard-wins-plan/
2026-11-12-146c-earlier-discard-wins-plan.evidence.md`, `## Investigation 2026-11-13`) confirmed,
reproduced and minimised two defects in the wrist engine twin and the real Swift engine:

- **A1** — a session the wrist has ended is resurrected when a stale phone `active` snapshot for it
  arrives while the wrist holds something else. Seed 111, four actions: wrist starts, a wrist frame is
  refused, wrist finishes, wrist starts again → `session 1 was completed on the wrist and reports
  active again`.
- **A2** — one cross-session `newestSnapshotAt` refuses a drained snapshot whole, entries included,
  once another session's newer snapshot has been applied. Seed 857, five actions → `session 1: the
  wrist never held entry-sx-ex-run-1-1`.

## Decisions

- **D-15101** A snapshot naming a session the wrist has already ended (a stored terminal row for that
  session) never changes a row: it merges its entries by `entryId` and nothing else — no row, status,
  structure, revision, position or timer — whatever the wrist currently holds (another live workout,
  another ended one, or nothing current). The current session's own ended row keeps the D-14601
  behaviour it already had.
  - Options: (a) extend the D-78 guard only, (b) refuse the snapshot whole, (c) merge entries only.
    (c) is D-14605's already-stated rule applied to the case whose held state is not "active with a
    non-empty ladder"; (b) would lose the phone's late sets.
- **D-15102** Both engines carry the same rule in the same place: after the stale-snapshot check and
  next to the D-78 guard, keyed on `existing == null && holdsTerminalRow(sessionId)` — Dart
  `WatchSessionEngine._applySnapshot`, Swift `WatchSessionEngine.applySnapshotExclusive`.
- **D-15103** *Not implemented — Blocked (scope).* The per-session newest-snapshot marker. Plan 63 D-1's
  device-wide stamp and its exact source line are asserted by two existing Swift tests
  (`WatchStaleSnapshotTests.testS9312AnOlderSnapshotOfAnotherWorkoutIsRefusedToo`,
  `WatchInboundLaneWiringSourceTests`), so the item needs a plan-63 decision, not a local edit.

## Scenarios

| Id | Fixture | Expected outcome |
|---|---|---|
| S-15101a | engine store: session 1 ended, session 2 ended; late `active` snapshot for session 1 with a new entry | session 1 keeps its `completed` row, revision and ladder; the entry merges; no new row |
| S-15101b | engine store: session 1 ended, session 2 live with an empty ladder; late snapshot for session 1 | session 1 stays `completed`; the entry merges |
| S-15101c | engine store: session 1 ended, session 2 live with a ladder (D-78); late snapshot for session 1 | session 1 stays `completed`; the entry merges (guard already green) |
| S-15101d | engine store: both sessions ended; late snapshot for session 1 | the current session does not become session 1 and never reads `active` |
| S-15101e | harness replay of the Phase 4 four-action trace (wrist start, refused wrist frame, wrist finish, wrist start) | the run converges, no absorbing violation |
| S-15101f | fresh engine, live wrist workout with a ladder, snapshot for a session it never stored | refused whole: no row, no entry (D-78 unchanged) |
| S-15102 | harness replay of the Phase 4 five-action A2 trace | **skipped** — D-15103 blocked |

## Phases

1. **An ended, non-current session keeps its end.** D-15101, D-15102; both engines; S-15101a..f.
2. **Per-session newest-snapshot marker.** D-15103 — **Blocked (scope)**: two plan-63 tests pin the
   device-wide stamp and its literal source line; re-planning needed before either can change.

## Progress

- [x] Phase 0 tests first: Dart `test/watch_ended_session_not_current_test.dart` (6 tests, 5 red, 1
      guard green) and Swift `WatchEndedSessionNotCurrentTests.swift` (4 tests, 4 red) — Complete
- [x] D-15101/D-15102 in the Dart twin and the Swift engine — Complete
- [x] PROTOCOL.md version row; `docs/state_management/watch_surface_wrist.md` rule paragraph — Complete
- [x] Phase 2 — **Blocked (scope)**: see D-15103 and Open Items
- [x] 200-seed sweep re-measured: 184/200 converge everywhere, shipping divergers 12 → 10 (seeds 111
      and 152 gone); ratchet left at 14 (A-145-02) — Complete
- [ ] Shared fixture `ended_session_not_current.json` — Open Item 2 (walker cannot assert a
      non-current row today)

## Open Items

1. Plan 63's `testS9312AnOlderSnapshotOfAnotherWorkoutIsRefusedToo` and
   `WatchInboundLaneWiringSourceTests` (S-9315) must be re-based in a plan-63 amendment before a
   per-session `newestSnapshotAt` can land; the A2 trace (S-15102) stays skipped until then.
2. The shared fixture `ended_session_not_current.json` was not added: both walkers compare only the
   current session's structure, so a fixture whose point is a non-current row cannot be asserted
   through them without a schema extension. Needs a decision on the walker shape.
3. `test/watch_convergence_random_test.dart` `S-14509 a drain-only heal` is now red: no seed in the 200
   sample needs the re-offer once the resurrection is prevented. Not edited — the measurement needs a
   decision (see the evidence file).

## Existing-Functionality Impact

| Surface | Reader | Effect |
|---|---|---|
| `_applySnapshot` / `applySnapshotExclusive` | D-78, D-14605, D-14601, D-127 paths | unchanged for the current session and for sessions with no terminal row |
| `_applyLifecycle` / `applyLifecycleExclusive` | `guardSession` binding | unchanged — a lifecycle for a non-current session never reaches the body |
| `ended_is_final.json`, `lifecycle_started.json`, `lifecycle_completed.json` | Dart + Swift fixture walkers | unchanged (current-session paths) |
| `WatchStaleSnapshotTests` S-9311..S-9314, `WatchInboundLaneWiringSourceTests` | Swift | unchanged — item 2 not implemented |

## Assumption Log

- **A-151-01** The A1 replay uses `RefuseLiveFrame(from: wrist)` with no `type`, as the Phase 4 log
  recorded it; the typed variant (`session_lifecycle`) reproduces the same defect.
- **A-151-02** A session with a terminal row is treated as ended for every snapshot, including one
  whose payload status is terminal too: the current-session path keeps D-14601, so only the
  non-current case changed, and re-sending the identical ending merges entries instead of re-writing
  an identical row (the row it would write changes nothing observable).
