# Evidence — watch auto-sync PR 3 (17c): a deletion on the phone reaches the wrist

Plan: `2026-10-06-17c-watch-auto-sync-pr3-plan.md`
Review: `2026-10-06-17c-watch-auto-sync-pr3-plan.review.md`

Executors append here. The plan keeps one-line Progress entries; measured output lives here.

## How to read this file

- **Paste real counts.** A command that hung, timed out (gateway exit 124) or was killed is reported
  as such — a hang is a failure, not an inconclusive result.
- **"Compiles" is not "passes".** `gateway.sh lint` green is not a test run.
- **A bug-fix test must be shown red without the fix.** Every red→green row below carries the
  `prove-red` or the manual revert that produced the red.

## Baselines

Base branch: `develop`. Rebase point (commit): `<fill in>`. Recorded by: `<phase 1 executor>`.

| Check | Command | Result | Date |
|---|---|---|---|
| lint | `.github/copilot/scripts/macos/gateway.sh lint` | `196 issues, 0 errors` — matches the brief's quoted baseline; whichever count this line prints, it is compared against the count the *first* executor records here | 2026-10-07 |
| test | `.github/copilot/scripts/macos/gateway.sh test` | `+4036 ~1: All tests passed!` (4036 passed, 1 skipped, 0 failed), recorded **with** the Phase 1 change in the tree — no base-commit full-suite run exists for this PR, so this row is the post-change reference the later phases compare against | 2026-10-07 |
| swift | `.github/copilot/scripts/macos/gateway.sh swift-test` | not run — Phase 1 changes no `.swift` file | 2026-10-07 |
| invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | nothing (I-2 holds) | 2026-10-07 |

## Doc sizes (before the Phase 3 edits)

| File | Size | Note |
|---|---|---|
| `docs/watch_session_sync.md` | `<record>` | must stay under 52 KB (~64 KiB hard) |
| `docs/state_management/watch_surface.md` | `<record>` | idem |
| `watch/sync_protocol/PROTOCOL.md` | `<record>` | not a `docs/` file, but keep it tight |

## Phase 1 — the phone announces its deletions (@developer)

Executor: developer agent, 2026-10-07. Base commit `8d00fab`.

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | `WatchSessionAdoptionBridge:heldWristEntryIds` | done | `watch_session_adoption_bridge.dart:273` — `originWatch` + `kindSet` inbox rows whose stamp still claims a group (`PhoneEntries.claimedBy`, the projection's own predicate); each slot's groups resolved once and cached per call |
| 2 | `LiveSessionMirrorState:deleteEntryAs` | done | `live_session_mirror_state.dart:466`, beside `deleteEntry` (`:461`); `applyStructureChange(..., {String? changeId})` (`:362`) now takes the id and falls back to `_newId()`, so `deleteEntry` keeps minting its own |
| 3 | `WatchSessionAutoPush:_announced` + `_pushOnce` order | done | `watch_session_auto_push.dart:201-220`: compose → `_remember` → `_announceEnd` → `_announceDeletions` → baseline compare → `sendState` |
| 4 | `WatchSessionAutoPush:_announceDeletions` | done | `:242-274`: `held` = payload entry ids ∪ `await _heldWristEntryIds(sessionId)`; `previous.difference(held)`, sorted ascending, one `deleteEntryAs(id, changeId: 'del-$id')` each; other sessions dropped from the ledger |
| 5 | constructor + `createWatchSync` seam | done | optional named `heldWristEntryIds`, defaulting to a `const {}` no-op; `watch_sync_wiring.dart` passes `adoption.heldWristEntryIds` |
| 6 | S-35 flip in `watch_session_projection_test.dart` | done | `S-35 an edit reaches the wrist and a delete is announced` — the file runs 4 passed / 0 failed; the delete frame is asserted (`changeId == 'del-entry-slot-bench-1'`, one `delete_entry`, session `sess-1`) and the wrist applies it |
| 7 | S-120, S-121, S-122, S-123, S-126(first half) | done | 6 new `test()` cases in `test/watch_session_auto_push_test.dart`; the whole file: **31 passed, 0 failed** |
| 8 | evidence + Progress | done | this section; plan Progress + Assumption Log updated |

Done Criteria run:

```
.github/copilot/scripts/macos/gateway.sh lint
  -> 196 issues, 0 errors; none of them in the four lib files or the two test files this phase changed
     (the count is the plan's quoted baseline)

.github/copilot/scripts/macos/gateway.sh test test/watch_session_auto_push_test.dart \
    test/watch_session_projection_test.dart test/watch_session_adoption_bridge_test.dart \
    test/phone_manage_bridge_test.dart test/watch_session_import_test.dart
  -> 116 passed, 0 failed (full output: .work/gateway/test-20261007-042435-10008.log)

.github/copilot/scripts/macos/gateway.sh test test/watch_session_auto_push_test.dart
  -> 31 passed, 0 failed

.github/copilot/scripts/macos/gateway.sh test   (full suite, run because the standing rules ask for it;
                                                 the plan schedules the full suite for the end of Phase 3)
  -> 01:42 +4036 ~1: All tests passed!  (4036 passed, 1 skipped, 0 failed; the plan schedules the
     full suite for the end of Phase 3, but the standing rules ask for one at the end of every phase.
     Full output: .work/gateway/test-20261007-042641-11621.log)

grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core
  -> nothing (I-2)
```

Red→green table:

| Scenario | Red command / revert | Red output | Green output |
|---|---|---|---|
| S-35, S-120, S-121, S-122 | `.github/copilot/scripts/macos/gateway.sh prove-red 8d00fab test test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart` | `RED AT 8d00fab (exit 1)` — `S-35 … [E]`; `S-120 … Expected: an object with length of <1> / Actual: []`; `S-121 … Expected: <2> / Actual: []`; `S-122 … Bad state: No element` (`List.single` — no frame at all) | 31 + 4 passed, 0 failed |
| S-123 | mutation: `..[sessionId] = held;` → `..[sessionId] = const <String>{};` **and** `previous.difference(held)` → `held.difference(previous)` (see the note below) | `S-123 … Expected: empty / Actual: [ 10 structure_change frames, one per held id, re-sent every pass ]` — the delete-everything defect | `S-123` green after restoring both lines exactly |

`prove-red`'s own verdict line:

```
gateway: prove-red: RED AT 8d00fab (exit 1). It proves the guard only if an assertion fails for the
reason the test guards; a compile or load error means the test could not run there (use a mutation
instead).
```

Two of the new cases **cannot** be red at the base, and that is honest rather than passing-by-luck:

- **S-123** asserts *no* frame on the first pass; absence is already true at the base. Its guard is
  shown by the mutation above.
- **S-126** (first half) asserts the *wrist* refuses a foreign-session frame. That guard is the
  engine's existing `_guardSession` (PR 2, `watch_session_engine.dart:675`), which this phase does
  not touch: it is a boundary regression test, so `prove-red` is N/A rather than GREEN-at-base
  proof of a new guard.

Mutations (each recorded, applied one at a time, original line restored exactly, green re-run after
each restore — never left applied):

| # | Scenario the mutation targets | Original line | Mutant | Verdict |
|---|---|---|---|---|
| a | S-120, S-121 | `final vanished = previous.difference(held).toList()..sort();` | `final vanished = held.difference(previous).toList()..sort();` | RED: `S-120 … Expected: an object with length of <1> / Actual: [3 frames — one per held id, incl. the two the wrist must keep]` |
| b | S-120's ledger seed | `..[sessionId] = held;` | `..[sessionId] = const <String>{};` | RED: `S-120 … Expected: an object with length of <1> / Actual: []` — an empty ledger never notices the vanished set |
| b′ | S-123 | both lines above mutated together (see the note) | — | RED: `S-123 … Expected: empty / Actual: [10 frames]` |
| c | S-122 | `return held;` (`heldWristEntryIds`) | `return const <String>{};` | RED: `S-122 … Bad state: No element` — with no held wrist ids the phone cannot name the set the wrist logged |
| d | S-120's ordering (D-111) | `await _announceDeletions(composedId, composed);` before the baseline compare | the same call moved to *after* `await _mirror.sendState(composed);` | RED: `S-120 … Expected: a value less than <3> / Actual: <4>` — the deletion now lands after the snapshot of its own pass |

Not observable, stated plainly:

- **The plan's S-123 mutation text is not achievable on its own.** "Seed from an empty set instead of
  from `held`" is only observable once the difference direction is also inverted (mutation b′). With
  the direction correct, an empty seed and a `held` seed behave identically on the first pass
  (`{} − held` is empty either way); with the seed correct, the inverted direction announces the
  whole held set, which is what b′ shows. Both halves are the same defect, and b′ is the smallest
  faithful reproduction of it.
- **The per-session keying of `_announced` is not distinguishable by the suite.** Flattening the
  lookup (`_announced[sessionId] ?? const {}` → `_announced.values.expand((s) => s).toSet()`) leaves
  every test green, `S-85` included: the ids are slot-scoped, so a stale entry from another session
  can never name the held session's entries. The keying is kept as a cheap invariant, not as a
  guarded rule — flagged in the plan's Assumption Log for the reviewer to drop or to demand a
  fixture for.

## Phase 2 — the Dart twin keeps the deletion (@developer)

Executor: developer agent, 2026-10-07. Base commit `0413112`.

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | `WatchSessionRecord.deletedEntryIds` | done | `watch_records.dart:181` (constructor, `const []` default), `:214` field + doc, `:239`-`:252` `withDeletedEntryIds`, `:270` the JSON write, `:287`-`:288` the JSON read (`(json['deletedEntryIds'] as List?) ?? const []`, so a row written before this phase reads back as `[]`); `withSequence` carries it like every other field |
| 2 | the union on the appended session row | done | `watch_session_engine.dart:1144`-`:1153` — the union is written in `_appendSessionRow`, not in `_applyStructureChange` alone: `restore()` reads the *newest* session row, and any lifecycle row appended after a delete is newer than the structure change's (`{...row.deletedEntryIds, ..._deletedEntryIds}`); `_applyDeletion` keeps the in-memory set in step (`:1008`-`:1009`) |
| 3 | `restore()` seeds the lens | done | `:156`-`:158` — `_deletedEntryIds ..clear() ..addAll(_session?.deletedEntryIds ?? const [])` |
| 4 | `_storeSnapshotEntry` clear + replace | done | `:791` clears for a carried id (the scoped D-113.2, mutation b), `:793`-`:801` the whole-entry replacement when `loggedAt` differs (D-113.3), `:803`-`:808` the unchanged field merge otherwise, `:227`-`:235` the `entries` getter's replacement arm before the merge arm; the tombstone state is settled in `_applySnapshot`'s loop (`:500`-`:503`) *before* its row is appended (`:512`), because that row is what `restore()` reads the lens from |
| 5 | S-124, S-125, S-126 (second half) | done | 5 new `test()` cases in `test/watch_session_engine_test.dart`: S-124 ×2 (`:1446` — a restart over the same store; the lens on the rows written after it), S-125 ×2 (`:1542` — the reused id; an id the wrist never held), S-126 ×1 (`:1632` — a foreign-session delete, a repeated frame); the file alone: **36 passed, 0 failed** |
| 6 | regression suites + Progress | done | `watch_session_engine_test.dart` + `watch_session_projection_test.dart`: **68 passed, 0 failed**; the four delete/late-entry/import/push suites: **141 passed, 0 failed**; full suite and lint below; this section and the plan's Progress/Assumption Log |

Done Criteria run:

```
.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_edit_restore_late_entry_test.dart test/watch_session_import_test.dart test/watch_session_auto_push_test.dart
  -> 141 passed, 0 failed (full output: .work/gateway/test-20261007-045424-43073.log)

.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart
  -> 36 passed, 0 failed

.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_projection_test.dart
  -> 68 passed, 0 failed (run after restoring both mutations exactly, and after the D-113.2 scoping)

.github/copilot/scripts/macos/gateway.sh test   (full suite)
  -> 01:41 +4042 ~1: All tests passed!   (4042 passed, 1 skipped, 0 failed)
     The Baselines row reads +4036 ~1, so exactly the six new cases of Phase 2 moved it (five here,
     one in the push suite) and nothing else. Full output:
     .work/gateway/test-20261007-045232-38350.log

.github/copilot/scripts/macos/gateway.sh lint
  -> 196 issues, 0 errors — the plan's recorded baseline count, and no issue is in a file this phase
     touched (checked by grepping the lint log for the four paths)
```

Red→green table:

| Scenario | Red command / revert | Red output | Green output |
|---|---|---|---|
| S-124 (both cases) | `.github/copilot/scripts/macos/gateway.sh prove-red 0413112 test test/watch_session_engine_test.dart` — at the base, `restore()` seeds no lens and no row carries one | `RED AT 0413112 (exit 1)` — `S-124 the deleted set stays hidden across a restart [E] Expected: ['entry-bench-2'] / Actual: ['entry-bench-1','entry-bench-2']` (`test/watch_session_engine_test.dart:1482`), and the same for `S-124 the lens rides on the rows written after it` (`:1532`) | 36 passed, 0 failed |
| S-125 (both cases) | the same `prove-red`, plus mutation a for the replacement branch alone | `S-125 … the reused id [E] Expected: ['entry-bench-1','entry-bench-2'] / Actual: ['entry-bench-1']` (`:1604`) and `S-125 an id the wrist never held is shown [E] Expected: ['entry-bench-2'] / Actual: []` (`:1672`) — the base clears no tombstone, so the reused id stays swallowed; mutation a then isolates the D-113.3 half (`:1611`, the dead set's Load surviving the replacement) | 68 passed, 0 failed |

`prove-red`'s own verdict line:

```
gateway: prove-red: RED AT 0413112 (exit 1). It proves the guard only if an assertion fails for the
reason the test guards; a compile or load error means the test could not run there (use a mutation
instead).
```

S-126's second half **cannot** be red at the base: it asserts the wrist refuses a foreign-session
delete frame, which is the engine's existing `_guardSession` (PR 2, untouched here), so it is a
boundary regression test — `prove-red` is N/A rather than a green-at-base pass.

Mutations (each recorded, applied one at a time, original lines restored exactly, green re-run after
each restore — never left applied):

| # | Scenario the mutation targets | Original line | Mutant | Verdict |
|---|---|---|---|---|
| a | S-125's replacement branch (D-113.3) | `final held = _heldPayload(entryId); if (held != null && held['loggedAt'] != entry['loggedAt']) { _entryCorrections[entryId] = entry; _replacedEntryIds.add(entryId); return; }` | the whole block deleted, leaving the field merge | RED: `S-125 the wrist shows the new set's own fields [E] Expected: null / Actual: <60>` (`test/watch_session_engine_test.dart:1611`) — the dead set's Load survives on the new set |
| b | the D-113.2 scoping (the existing S-35 guard) | `final held = _heldPayload(entryId); if (held != null && held['loggedAt'] == entry['loggedAt']) return; _deletedEntryIds.remove(entryId);` | `_deletedEntryIds.remove(entry['entryId']! as String);` — the literal D-113.2, clearing for every carried id | RED: `S-35 a re-statement of a deleted id stays deleted [E] Expected: ['entry-slot-bench-0'] / Actual: ['entry-slot-bench-0','entry-slot-bench-1']` (`test/watch_session_projection_test.dart:1205`); exactly 1 failure in a 68-test run |
| c | the auto-push ledger drop (the brief's extra item) | `..removeWhere((id, _) => id != sessionId)` (`lib/state/watch/watch_session_auto_push.dart:257`) | `..removeWhere((id, _) => false)` | RED: `D-114 leaving a session and coming back re-seeds the ledger [E]` — the return pass announced one `structure_change` for `del-entry-sx-1-2`; the file is absent from the final `git-diff --stat` |

Docs: **no docs this phase**, by the plan's own Interphase note — the durable-lens sentences cover
both twins and land with the Swift twin in Phase 3.

## Phase 3 — the Swift twin, PROTOCOL, docs (@developer)

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Swift `WatchSessionRecord.deletedEntryIds` + file store | | |
| 2 | Swift engine: write/restore/clear/replace | | |
| 3 | Swift S-124, S-125, S-126 | | |
| 4 | PROTOCOL amendment (dated) | | |
| 5 | `docs/watch_session_sync.md` rule + D-117 sentences + size | | |
| 6 | `docs/state_management/watch_surface.md` + Progress | | |

Done Criteria run (then the full suite):

```
.github/copilot/scripts/macos/gateway.sh lint
.github/copilot/scripts/macos/gateway.sh swift-test
.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart test/docs_indexing_contract_test.dart
.github/copilot/scripts/macos/gateway.sh test
```

Final counts vs baseline: `<fill in — full flutter test and swift test, compared row by row with the
Baselines table>`.

## Parity check (I-1)

| Frame sequence | Dart twin `entries` | Swift twin `entries` | Equal? |
|---|---|---|---|
| snapshot(2 entries) → delete(1) → restore | | | |
| snapshot(2) → delete(2) → snapshot(2 re-created under a reused id) | | | |

## Out-of-bounds writes found by the reviewer

`<reviewer fills — any file changed that is not in the phase's Predicted Files, and any predicted
file left untouched>`
