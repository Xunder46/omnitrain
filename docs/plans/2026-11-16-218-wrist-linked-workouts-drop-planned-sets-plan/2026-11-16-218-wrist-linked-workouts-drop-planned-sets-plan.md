# Plan 218 — Workouts the watch took part in also drop their planned sets

Series: Stats pre-launch review, plan 157d (index `docs/plans/2026-11-13-157-stats-what-counts-series.md`). Phone only, but it touches the watch sync (`lib/state/watch`, `lib/core/services`, `lib/state/workout`). Status: BUILT (owner said go on 2026-11-16), reviewed (APPROVE WITH FIXES, fixed), verified, COMMITTED.

## Goal and acceptance

Since plan 157a, finishing a workout on the phone drops every planned set nobody logged, so Stats, the summary and the bests read only what was done. A workout the watch took part in is skipped (157a D-11): its planned-but-undone sets stay stored and count as done. After this change they are dropped at the end of such a workout too, without ever losing a set the wrist logs afterwards.

Acceptance: S-21801..S-21806 green, the ones marked "fails without" red at the base commit; `test/finish_drops_unlogged_sets_test.dart` S-15706, S-15712, S-15713 rewritten to the new rule; every other reader below green and unchanged; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- A workout started or ended with the watch: once it ends, the planned sets nobody logged are gone from it, like on the phone alone; the summary, volume and bests count only logged sets.
- An exercise with no logged set at all stays in the workout with no sets (the phone-only path removes it). Reason: the wrist can still send a set for it later, and a late set for a removed exercise is lost (the importer never re-creates an effort, `watch_session_importer.dart:426-428`).
- A set the wrist logs after the end still lands (it appends after the last row).
- To SEE it: plan three lifts on the phone, log one on the watch, end on the watch; open the finished workout: only the logged set is there.

## Scout findings (verified against code)

1. There is NO "the wrist is done" signal. The wrist re-offers stored observations on every reconnect (`watch_sync_orchestrator.dart:93,114-117`), so late sets can arrive for any ended session; the end itself can still move (`watch_session_adoption_bridge.dart:941,968-990`). So "prune after it settles" has no definition: the rule must be safe at ANY time.
2. A wrist set for an exercise that still has an effort never needs a planned row: with every row logged or none left it appends (`watch_session_importer.dart:1236-1253`, `_plannedSetToFill` returns null). Deleting planned rows loses nothing; deleting the EFFORT does (a live merge drops rows for a missing effort, `:426-428`).
3. Wrist-linked is not stored on the session. The inbox keeps applied rows for ever (`hive_workout_repository.dart:3313-3380`), which `endSession` already reads (`session_core_lifecycle.dart:29-34`).
4. Importer passes are chained among themselves (`WatchSessionInbox._settleChain`, `watch_session_inbox.dart:433-466`), but the bridge's end (`target.endSession(writeToHealth: false, ...)`, `watch_session_adoption_bridge.dart:985`) is NOT in that chain: the wrist sends one message per observation without waiting, so a prune in `endSession` could run between a merge pass writing a wrist set's row and its rest, read that set as unlogged and delete it. This is the central risk.
5. Edit mode: a user typing sets into an already finished workout has no rest on them (157a "typed sets count"), so a prune that re-runs after every import pass would delete them. The prune must run once at the end, never on a later pass.

## Decision Ledger (proposed, owner go-ahead pending)

| ID | Decision | Backed by |
|---|---|---|
| D-1 | The prune runs once per end, in both ends of a wrist-linked workout: the phone's own Finish (`endSession` with a staged wrist row or `wristRunsSession`) and the wrist's end applied by the bridge. Never on a later import pass (finding 5). | `session_core_lifecycle.dart:29-35`, `watch_session_adoption_bridge.dart:985` |
| D-2 | It is the same rule as 157a (a set is logged when a rest sits at position + 1, a skip-marked set stays) with ONE difference: it never deletes an effort (finding 2). `_dropUnloggedSets` takes `keepEfforts`; the phone-only path passes false, so its behaviour is unchanged. | `session_core_lifecycle.dart:98-143` |
| D-3 | The wrist's end prunes through the inbox's settle chain, queued behind every in-flight import pass, so a wrist set's row and rest are both written before the prune reads (finding 4): a new `WatchSessionInbox.pruneAfterEnd(sessionId)` that waits for the chain, then calls the held session's prune and refreshes it. The phone's own Finish of a wrist-linked session waits on the same chain before `endSession` runs its drop. | `watch_session_inbox.dart:433-466` |
| D-4 | Not a migration: workouts finished before this change keep their planned sets (no stored user data to repair; memory `stats-redesign-ships-as-one-release`). | scope |
| D-5 | Words and the keep-an-empty-exercise choice are the lead's recommendation; the owner decides (Open item 1). | scope |

## Scenarios (fixtures follow `test/finish_drops_unlogged_sets_test.dart` and `test/watch_session_finish_test.dart`)

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-21801 | A staged wrist row for the session (as S-15712), 3 planned sets with set 0 logged; the phone's `endSession()`. | Two placeholders gone, set 0 and its rest stay, the effort stays. Mock and Hive. | the planned sets stay (157a D-11 skip) |
| S-21802 | The wrist-runs-the-session case of S-15713 with an exercise that has only placeholders; `endSession()`. | Its sets are gone, the effort stays with no sets. | the sets stay; the mutation that deletes the effort also fails it |
| S-21803 | The wrist's own end (S-15706 fixture: `endSession(writeToHealth: false, atMs:)`). | Planned sets gone, logged set intact, `endedAtMs` is the given instant. | the planned sets stay |
| S-21804 | S-21803, then a late wrist set for the same exercise arrives through the importer (the staged-row path of `watch_session_finish_test` S-4 "end before the logged sets"). | The set is stored, logged (rest at its position + 1), appended after the last row, nothing lost. | guards D-2: with the effort deleted the importer drops the set (`:426-428`); passes at base for another reason, so it is a guard (mutation: delete the effort) |
| S-21805 | Interleaving: a merge pass for a wrist set is paused between its row write and its rest write (a repository subclass that holds `createEntryRest`); the wrist's end arrives meanwhile. | After the pass finishes the set exists with its rest; the prune ran after, and kept it. | a prune that does not wait for the chain reads the set as unlogged and deletes it (mutation: call the prune outside the chain) |
| S-21806 | An already finished wrist-linked workout is loaded, the user types a set (no rest), then a late wrist set arrives and its pass settles. | The typed set is still there (the prune did not run on the later pass). | guards finding 5; passes at base, kills the mutation that prunes after every pass |

## Input-reality checklist

1. Writers and units: no new stored value; rows deleted only through the existing `deleteObservation`; rests re-keyed through the existing shared rule (`EntryRows.restsAfterDelete`).
2. Lifecycle: once per end. Both ends can happen (the phone ends, the wrist later confirms its own end): the second finds an ended session and returns before the drop (157a D-1 guard), so nothing is pruned twice. A session the phone does not hold is imported as history from wrist rows only and has no planned sets.
3. Settings: none.
4. Time: the end instant logic is untouched (D-153).
5. Cost: one pass over the session's set efforts, as 157a.
6. Words: no new copy.
7. Concurrency: named in finding 4 and S-21805; the chain is the only dispatcher.

## Phases (outline; not started)

1. **P0 lead**: read how `WatchIncomingRouter.receive` interleaves `inbox.receive`, the mirror and the adoption bridge for two messages (the exact point a prune can run between a merge's row and rest writes), and write the interleaving probe (S-21805) against today's code.
2. **P1 builder-app**: `_dropUnloggedSets(keepEfforts:)`, the endSession branch, the inbox method and the bridge call, S-21801..S-21803 with the three 157a tests rewritten.
3. **P2 builder-watch or builder-app (separate run)**: S-21804..S-21806.
4. **P3 lead**: docs, mutation pass, review, full suite.

## Readers

`test/finish_drops_unlogged_sets_test.dart` (S-15706, S-15712, S-15712b, S-15713), `test/watch_session_finish_test.dart` (S-4 pair, `a set logged on the watch lands in the session the phone holds`), `test/watch_session_merge_test.dart` (S-3604..S-3607, S-3616), `test/watch_session_import_test.dart` (A-51), `test/watch_session_end_owed_test.dart`.

## Mutation list (lead)

(a) the prune also deletes the effort; (b) the wrist end calls the prune outside the chain; (c) the prune runs after every import pass; (d) the phone-only path loses its effort removal; (e) the wrist-linked check is dropped so every end keeps placeholders.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/rest_tracking.md` | MODIFIED | A session the watch had a part in keeps its planned sets, because | also drops its planned sets, but never an exercise | S-21801, S-21803 |
| `docs/session_summary.md` | MODIFIED | is not stored at Finish of a session the watch had no part in | except in a session the watch had a part in | S-21802 |
| `docs/watch_session_sync.md` | MODIFIED | it appends after the last row, and | a held session that has already ENDED appends too | S-21806 |
| `docs/state_management/workout_state.md` | MODIFIED | (those sessions keep their planned sets) | `keepEfforts` | S-21802 |

Stale-term sweep (`grep -rIn "keeps its planned sets" docs`): `rest_tracking.md:126`; `lib/state/workout/session_core_lifecycle.dart:23` comment and the two test names are code, listed in Readers.

## Open items

1. (owner) Go-ahead. This is a watch-sync change with a real interleaving risk and no way for me to check it on the watch itself; the benefit is that wrist-ended workouts read like phone-only ones in Stats. Recommendation: build it, but with the owner's device check (QA step) afterwards.
2. (owner) An exercise with no logged set stays as an empty exercise in a watch-linked workout (phone-only removes it). Recommendation: keep it empty; the alternative loses a late wrist set for it.
3. Sessions finished before this change keep their planned sets (no migration).
4. The prune does not run for a session the phone never held (wrist-only history import has no planned sets).

6. Found while building (S-21806): a late wrist set REPLACED a rest-less set typed into a finished workout (the merge read it as a planned row); fixed by the importer appending in an ended workout (`fillPlannedSets`, with the rest the arrival opens kept). The same loss existed before for an exercise whose every other set was logged.
7. Readers changed by the new rule: `test/workout_state_clock_seam_test.dart` (its fixture put a rest at index 0, which marks nothing logged; now 1), `test/watch_session_merge_test.dart` S-14 (the end goes through the app's `endSession`), and the watch replay corpus `watch/sync_protocol/fixtures/replay/trace-kills.json` regenerated (the phone's receipt and its end announcement swapped order because the end now waits for the queue; the watch package's 1580 Swift tests pass on it).
8. (review nuances, not fixed) a second end that arrives while the first sits in the queue enqueues a second drop (it finds nothing and deletes no exercise); the plan's "never on a later pass" holds because the drop lives only in `endSession`.
9. (owner) Device check: end a workout on the watch with planned sets you did not do; open it on the phone: only the logged sets, no extra rows; then log a set on the watch after the end if you can.

## Predicted files

`session_core_lifecycle.dart` (+25), `watch_session_inbox.dart` (+25), `watch_session_adoption_bridge.dart` (+6), `workout_state.dart` (+4), tests: one new file, three rewritten tests, two docs.

## Progress

- [x] Seeded and scouted
- [x] Owner go-ahead (2026-11-16)
- [x] P0: the wrist's end is not in the inbox chain; fixed by injecting the chain into the state
- [x] P1 (state, queue, wiring, 7 tests), P2 (3 tests), fix 1 (importer: an ended workout appends), fix 2 (S-14 fixture), lead's mutation pass (7 mutants, all killed), review, full suite

## Assumption Log

- 2026-11-16: base commit `d35346f8` on `claude_develop`; other sessions' `docs/plans/2026-11-15-208-fuel-burned-per-day-plan/` and `test/stats_gallery_render_test.dart` are outside this plan.
- 2026-11-16: scenario ids S-218xx; grep over `test`, `docs`, `lib`, `watch` found none in the five-digit form (checked below).
- 2026-11-16: "prune once at each end, never on a later pass, never delete the effort" is the lead's reading of the scout sheet (no settled signal exists).

## Feedback

(none yet)
