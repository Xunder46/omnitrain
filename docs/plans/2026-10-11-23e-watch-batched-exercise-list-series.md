# Series 23e: the watch's exercise list travels in batches

Owner request (2026-10-11): custom exercises make the exercise list unbounded, and today the phone sends all of
it in ONE frame. Approved in principle (plain language): (1) the phone sends the list in batches of at most 100,
each small and re-sendable alone; (2) the wrist keeps what it has and switches to the new list only when EVERY
batch has arrived, so a half sync never leaves a broken list; (3) the wrist says which version of the list it
holds and the phone sends nothing when it matches, while adding, renaming or deleting a custom exercise changes
the version so the next Sync fetches it; (4) works from the Sync button, and the catch-up that runs when the phone
comes back in reach inherits it for free (it already calls the same sync); (5) the wrist keeps only the newest list;
(6) the Add Exercise screen gets a way to find an exercise once the list is long.

Facts measured before planning (so the numbers are not re-argued):
- Today `routines_down` carries the whole list in `fallbackExercises`: about 28 KB for the 252 seeded exercises
  (`test/watch_reference_sync_test.dart` S-3607), roughly 110-150 KB at 1,000 exercises. It travels with
  `sendMessage`; Apple's frame ceiling is not verified in this repo. A batch of 100 is about 11 KB.
- The phone ignores the request's `since` (`WatchSyncRequestHandler.handle(String request)` receives only the request NAME,
  `lib/state/watch/watch_sync_wiring.dart:234`), so every Sync re-sends everything.
- The wrist appends one catalog row per Sync and never trims (`WatchSessionStartPaths.applyRoutinesDown`).

## Order (each PR ships alone and leaves the app working)

| PR | Scope | Depends on | Track |
|---|---|---|---|
| 23e1 | Contract: new `exercises_down` message (batch of at most 100, a version, batch index/count/total) and `routines_down` allowed to carry no fallback list; wrist: stores batches, switches only on a complete set, prunes the rest, reports its version in the Sync request. The phone still sends the old full `routines_down`, so nothing changes for the user yet. | none | contract + watch |
| 23e2 | Phone sender: a content-derived list version, batching, nothing sent when the wrist's version matches, `routines_down` shrinks to the routines and the exercises they use; the request handler reads the version from the request frame. | 23e1 | phone |
| 23e3 | Add Exercise screen: a way to find an exercise in a long list (search or jump to a letter; owner to choose, plain-language options in that plan). | 23e1 | watch UI |

23e3 is independent of 23e2 and may be planned first if the owner prefers; 23e2 and 23e3 are planned when their turn comes,
against the code as it is by then (`.github/copilot/pr-scope-budget.md`, "Over budget at planning time").

## Decisions shared by the PRs (stable ids, never reused)

- D-3801 One new message `exercises_down` (phone to watch), not an overload of `routines_down`: `routines_down` keeps
  meaning "your routines and the exercises they use"; the whole list is `exercises_down`. Same shape of work as `foods_down`.
- D-3802 The version is an opaque string to the wrist (1 to 64 characters). The phone derives it from the CONTENT of
  the list (so a rename, a new custom exercise, a deletion or a changed period length changes it, and nothing needs an
  invalidation hook). The wrist never computes or compares versions; it stores and echoes the one it was sent.
- D-3803 The wrist reports the version of the list it has ACTIVE (complete) in the Sync request frame as `exercisesVersion`;
  a wrist with no list omits the key. A half-received list is never reported.
- D-3804 No protocol version bump, no legacy handling: additive message, relaxed minimum (single release, as plans 23c/23d).
- D-3805 The Wear/Dart wrist client (`lib/watch`) is not updated (documented divergence, as 23a to 23d): it ignores
  `exercises_down` and keeps reading the whole list from `routines_down` only while the phone still sends it (23e1);
  from 23e2 it simply has the routine exercises. Recorded in the plan that ships the phone change.
