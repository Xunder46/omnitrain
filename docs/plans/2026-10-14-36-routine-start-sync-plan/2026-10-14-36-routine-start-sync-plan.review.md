# Review: plan 36 (36a) routine start sync · Phases A–D · 4b7a002..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 3 · nit 0 · tests: +4697 ~1 (lead, not re-run per brief)
Diff vs Predicted Files: conforms · outside: none — `test/watch_transport_test.dart` (+5) is the
unrelated units work the brief names; `test/watch_session_adoption_bridge_test.dart` and
`test/watch_session_finish_test.dart` were in Phase A's predicted scope but are unchanged (no
set-entry or rest assertions in them; suite green without changes — ratified below).

## Findings

1. [Major] docs/watch_session_sync.md:349 — the new fill bullet claims "a history import always
   appends after the last row" and cites `S-11 the phone's own rows are the user's`, but S-11
   (test/watch_session_merge_test.dart:641) drives the held merge (router snapshot +
   observationsUp), not a history import; no test in its citation list asserts the history claim.
   A maintainer following the citation finds nothing about history imports. The real guard exists:
   `test/watch_session_import_test.dart:1848`, group `A-51 the user's own rows in an imported
   effort are never…` (A-51 a late wrist set is placed after the user's own set). Fix: cite the
   A-51 group for the history claim and keep S-11 for the held-merge append. Guard: none new —
   the citation fix only.
2. [Minor] test/watch_session_merge_test.dart — no test exercises the replay branch
   (`unfinishedPlaceOf`) under `fillPlanned` with planned rows present: a pass that placed a wrist
   set into a planned slot and did not finish, then replays. The code reads correct (the
   `unfinished ?? fill?.number` precedence keeps the set on its own rows, `fill` is null, the
   rest-open still runs and skips when rested), but a mutation flipping the precedence to
   `fill?.number ?? unfinished` would fill a planned row on replay and no test would fail. The
   existing replay tests (D-19 group) have no phone rows. Fix: none required for 36a; guard: a
   merge test where a half-finished pass stamped a planned slot, then the pass replays — the set
   re-lands on its own rows, no planned row is filled, one rest.
3. [Minor] lib/core/services/watch_session_importer.dart:930 — when the wrist retracts a set
   (S-337), the open rest its arrival opened stays: the phone shows a running rest timer for a set
   that no longer exists and reads the emptied spot as logged until the next set arrives. The docs
   record this under known limitations citing S-337, so it is accepted for 36a. Fix: none now;
   owner should plan the retraction cleanup (delete the arrival's open rest with the entry).
4. [Minor] docs/plans/2026-10-14-36-routine-start-sync-plan/…plan.md — the Assumption Log is
   empty after a complex phase. The evidence file records the fixture migrations, but two silent
   decisions are unlogged: `loggedSetNumbers` deviates from D-1's seeded formula with an
   `entryIndex >= 1` guard (prevents a rest at index 0 yielding -1; S-16's fixture rest at index 0
   exercises it), and the two predicted-but-unchanged Phase A test files. Fix: append both entries
   to the plan's log.

## Assumption Log rulings

- D-1 deviation (`entryIndex >= 1` guard in `loggedSetNumbers`): ratify — a rest at entryIndex 0
  would otherwise mark set -1 logged; S-16's fixture rest at index 0 guards it.
- S-325's fixture migration to a closed phone rest: ratify — the open case is unreachable under
  the new code: a phone open rest at i+1 marks set i logged, so the fill skips i and the wrist's
  set lands elsewhere; `recordRestStart` early-returns when the fill's rest already exists. The
  closed case is the only reachable one and S-325 guards it.
- Phase A's predicted files `test/watch_session_adoption_bridge_test.dart` and
  `test/watch_session_finish_test.dart` unchanged: ratify — neither has set-entry or rest
  assertions that the new projection semantics would break; the full suite is green.
- S-3515's old control (wrist set without a rest) replaced by a planned-row control: ratify —
  under D-6 a set arrival always leaves a rest at index+1, so the old state no longer arises; the
  new control is not vacuous.
- S-16's redelivery assertion ("a redelivery writes nothing") after the fill: verified this run —
  the fill's idempotence is exercised (test/watch_session_merge_test.dart:1367-1392).

## Scenario coverage

- S-3601 → test/watch_session_projection_test.dart · S-3601 a session of planned rows sends no entry
- S-3602 → test/watch_session_projection_test.dart · S-3602 only the set a rest follows is sent
- S-3603 → test/watch_session_projection_test.dart · S-3603 a logged set with no reps is still no entry
- S-3604 → test/watch_session_merge_test.dart · S-3604 (fill replaces the first unlogged row)
- S-3605 → test/watch_session_merge_test.dart · S-3605 (fill keeps the row count)
- S-3606 → test/watch_session_merge_test.dart · S-3606 (four sets in one message fill in step)
- S-3607 → test/watch_session_merge_test.dart · S-3607 (fill stamps the wrist's loggedAt)
- S-3608 → test/watch_session_merge_test.dart · S-3608 (fill's rest opens at index+1)
- S-3609 → test/watch_routine_round_trip_test.dart · S-3609 (fill, no echo, phone logs, wrist appends)
- S-3610 → test/watch_live_refresh_screen_test.dart · S-3610 (fill refreshes the screen)
- S-3611 → test/watch_session_merge_test.dart · S-11 the phone's own rows are the user's
- S-3612 → test/watch_session_merge_test.dart · S-9 (existing; not re-read this run, suite green)
- S-3613 → test/watch_session_merge_test.dart · S-323 / S-328 (retry dropped, entry unknown)
- S-3614 → test/watch_session_merge_test.dart · S-325 (phone's finished rest kept)
- S-3615 → test/watch_session_merge_test.dart · S-10 a redelivery, and a second set; S-16's
  redelivery assertion; finish receipts (test/watch_session_finish_test.dart S-4, not re-read)
- S-3616 → test/watch_session_merge_test.dart · S-3616 (skipped row is still filled)
- S-3617 → test/watch_live_refresh_screen_test.dart · S-3514 (user's position unchanged)
- S-3618 → test/watch_session_merge_test.dart · S-3618 (phone's open rest closed at the fill,
  Mock + Hive) — extra scenario added by B-fix-1 beyond the seed's list.

Checked, no finding: the only open rest `_applyRests` can overwrite at the wrist's spot is the
fill's own (analysis above under S-325's ruling); `fills` is kindSet-only (verified in
`_createEntry`'s switch); `PhoneEntries.project` has exactly one production caller (the adoption
bridge), and the required `loggedNumbers` parameter makes any other caller a compile error
(analyze 182 = baseline confirms).