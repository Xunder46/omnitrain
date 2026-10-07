# Evidence — watch-auto-sync PR 2 (`17b`)

Plan: `2026-10-06-17b-watch-auto-sync-pr2-plan.md`. Implementers and the reviewer paste real command
output here; the plan holds no evidence.

## Baselines (before this PR, at the branch point `a45dd49`)

| Command | Result | Date |
|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` | 4013 passing, ~1 skipped, 0 failures | 2026-10-06 (17a's evidence) |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues, 0 errors (pre-existing info notices) | 2026-10-06 |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 315 passing, 0 failures | 2026-10-06 |

## Per-phase results

| Phase | Command | Result | Notes |
|---|---|---|---|
| 1 | gateway `test test/watch_session_adoption_bridge_test.dart test/watch_session_adoption_build_notify_test.dart test/watch_session_rest_timer_append_test.dart` | `+23: All tests passed!` (0 failed) | the first run of the same three files was `+14 -4` — see below |
| 1 | gateway `test test/watch_session_adoption_bridge_test.dart test/watch_session_adoption_build_notify_test.dart test/watch_session_rest_timer_append_test.dart test/watch_session_start_test.dart test/docs_indexing_contract_test.dart` | 64 passed, 0 failed | the plan's Done-Criteria set, after the docs paragraph landed |
| 1 | gateway `test` (full) | 4020 passed, ~1 skipped, 0 failed | baseline 4013 (~1 skipped) + 7 new Dart tests |
| 1 | gateway `lint` | 196 issues, 0 errors | same count as the baseline; `grep` over the log finds none in a touched file |
| 1 | gateway `swift-test` | not run — no Swift file changed | `git diff --stat`: 3 `lib/` files, 3 test files, 1 doc |

## Phase 1 — the phone accepts the wrist's additions (S-102…S-106, S-110, S-111)

Steps 1–10 done, plus the docs sentence in `docs/watch_session_sync.md`. `appendSessionSlots`
(`lib/state/workout/session_core_entry.dart:77`, exposed by `lib/state/workout/workout_state.dart`)
writes through `WorkoutRepository` and takes no reload path, so no timer is touched; `_reconcile` and
`_everSeen` live in `lib/state/watch/watch_session_adoption_bridge.dart`, and `consider`'s
`alreadyHeld` branch calls them only for a non-empty result.

One decision the plan left to the implementation (D-92's "never reorder"): an addition takes the
phone's **next free** `orderIndex` — its own highest + 1, incremented per addition — not the snapshot's
index. Taking the snapshot's index made a mid-ladder addition tie with an existing one and sort into
the middle of the ladder (`importedEfforts` read `['sl-1','sl-9','sl-2']`, which D-92 forbids).

### Red first — the first targeted run, before the last three defects were fixed

`+14 -4: Some tests failed.` The four failures, each with its cause:

| Red | Cause | Fix |
|---|---|---|
| `a second snapshot of the session the phone holds does not rewrite it` saw `['sl-1','sl-9','sl-2']` with order `[0,1,2]` | `_reconcile` took the snapshot's `orderIndex`, so the mid-ladder addition tied with an existing slot and sorted into the middle | additions take the phone's next free index (`nextOrderIndex`) |
| `test/watch_session_adoption_build_notify_test.dart` did not compile: `'SessionSegment' isn't a type` | the new S-103/S-111 helpers name `SegmentEffort` and the file did not import `package:omnitrain/data/models/models.dart` | the import was added |
| S-105 and S-106 hit a null-check on `(await phone.bridge.projectSession(null))!` | the fixture's capabilities were empty, so `_slotFor` returned `null` for every effort and `projectSession` found no slots. `test/helpers/repository_harness.dart:168 seedExercise` passes `capabilities` to the `Exercise` constructor, which `MockWorkoutRepository.createExercise` drops — capabilities live in the separate `_exerciseCapabilities` store that `getExerciseById` reads back | the bridge test's `_repository()` now calls `setExerciseCapabilities` for both seeded exercises, the way `test/helpers/watch_capture_import_harness.dart:85` does |

This is a harness defect in an existing helper, not a behaviour of the change under test; the helper
was **not** edited (the harness is shared with other files, and fixing it there would change them).

### Which new tests are red against the code before Phase 1, and which need a mutation

Before this change, `consider`'s `alreadyHeld` branch returned without touching anything, so every
scenario whose outcome is "the ladder grows, once, and something is notified" is red on the old code:
S-102, S-110 and S-111 — mutation (a) reproduces exactly that state, and all three go red under it.
The other four assert that something does *not* happen — a converged ladder changes nothing (S-104), a
renamed slot survives (S-105), a foreign session is refused (S-106), a removed slot does not come back
(S-103) — and each passes trivially on code that never appends. Their red is the mutation the brief
names for each: (e′) for S-104, (d) for S-105, (f) for S-106, and (b) for S-103.

### Mutations — every new guard, shown red, then restored exactly

Each mutation was applied alone against the three Phase 1 test files (`+23` green otherwise), and the
exact original line was restored and the files re-run green after each. No mutation was left applied.

| # | Mutation (original → mutant) | What went red | Observed |
|---|---|---|---|
| a | the `_reconcile` call site: `if (additions.isNotEmpty) {` → `if (false && additions.isNotEmpty) {` | S-110, S-102, `a second snapshot …`, S-103, S-111 | `+18 -5: Some tests failed.` |
| b | the ever-seen half: `if (held.contains(slotId) \|\| !seen.add(slotId)) continue;` → `if (held.contains(slotId)) continue;` | S-103 (its stale-copy half) | 1 red |
| c | `appendSessionSlots` reloads: `_notify();` → `await loadSessionData();` | S-110, S-102 | `+15 -2`, `notifications 3 != 1` |
| d | the match key: `final slotId = slot['sessionExerciseId'];` → `final slotId = slot['name'];` | S-105 and three more | `+12 -4` |
| e | the ladder half: `if (held.contains(slotId) \|\| !seen.add(slotId)) continue;` → `if (!seen.add(slotId)) continue;` | **nothing** — S-104 stays green | the `held.contains(slotId)` half is redundant: `seen.addAll(held)` runs before the loop, so `seen` already holds the phone's own ids |
| e′ | the whole guard line deleted (`-      if (held.contains(slotId) \|\| !seen.add(slotId)) continue;`) | S-104 — the phone's own efforts were re-ordered to 2/3 | 1 red |
| f | S-106 needs two lines at once: `_reconcile`/`appendSessionSlots` called **before** the `refusedConflict` guard, **and** `appendSessionSlots`'s `if (efforts.isEmpty \|\| _currentSession?.id != sessionId) return;` reduced to `if (efforts.isEmpty) return;` | S-106 | 1 red, `Expected: <0> Actual: <2>` |

Reading (e) and (e′) together: the guard as a whole is what S-104 proves, and either single half
still covers the case (the other half plus `_adopt`'s `_everSeen` seeding). (b) shows the ever-seen
half alone is what keeps a removed slot from coming back; the `held.contains` half adds no
independently observable behaviour — it is kept because it states the rule directly and the pair is
cheaper than the reasoning that they are equivalent. Mutation (f) is two lines because the single-line
variant is green: `appendSessionSlots` refuses a foreign session id on its own.

### The test the plan predicted

`test/watch_session_adoption_bridge_test.dart` — `a second snapshot of the session the phone holds
does not rewrite it` — was the file the impact table (row `WatchSessionAdoptionBridge.consider`
`alreadyHeld`) and Predicted Files both name. Its ladder assertions now read `['sl-1','sl-2','sl-9']`
with order `[0,1,2]`: the frame it sends carries a slot the phone has never seen, which D-92 appends,
and every assertion about the phone's own two slots is unchanged. No other existing test in the repo
changed, and none went red for an unpredicted reason.

### Residue sweeps

`grep` for each mutant spelling under `lib/` and `test/` finds no residue: `additionsM`, `false &&`,
`slot\['name'\] ??`, and no deleted guard line. `git diff --stat` on the phase shows the 3 production
files, the 3 test files and `docs/watch_session_sync.md`, and nothing else.
