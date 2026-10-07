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
| lint | `.github/copilot/scripts/macos/gateway.sh lint` | `<issues/errors — the brief quotes 196/0 at the base; 17b's evidence quotes different numbers, so record what this run prints>` | |
| test | `.github/copilot/scripts/macos/gateway.sh test` | `<passed / failed / skipped>` | |
| swift | `.github/copilot/scripts/macos/gateway.sh swift-test` | `<passed / failed>` | |
| invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | `<nothing / hits>` | |

## Doc sizes (before the Phase 3 edits)

| File | Size | Note |
|---|---|---|
| `docs/watch_session_sync.md` | `<record>` | must stay under 52 KB (~64 KiB hard) |
| `docs/state_management/watch_surface.md` | `<record>` | idem |
| `watch/sync_protocol/PROTOCOL.md` | `<record>` | not a `docs/` file, but keep it tight |

## Phase 1 — the phone announces its deletions (@developer)

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | `WatchSessionAdoptionBridge:heldWristEntryIds` | | |
| 2 | `LiveSessionMirrorState:deleteEntryAs` | | |
| 3 | `WatchSessionAutoPush:_announced` + `_pushOnce` order | | |
| 4 | `WatchSessionAutoPush:_announceDeletions` | | |
| 5 | constructor + `createWatchSync` seam | | |
| 6 | S-35 flip in `watch_session_projection_test.dart` | | |
| 7 | S-120, S-121, S-122, S-123, S-126(first half) | | |
| 8 | evidence + Progress | | |

Done Criteria run:

```
.github/copilot/scripts/macos/gateway.sh lint
.github/copilot/scripts/macos/gateway.sh test test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart test/watch_session_adoption_bridge_test.dart test/phone_manage_bridge_test.dart test/watch_session_import_test.dart
```

Red→green table:

| Scenario | Red command / revert | Red output | Green output |
|---|---|---|---|
| S-120 | `prove-red` with the `_announceDeletions` call removed from `_pushOnce` | | |
| S-123 | mutation: seed `_announced` from an empty set | | |

## Phase 2 — the Dart twin keeps the deletion (@developer)

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | `WatchSessionRecord.deletedEntryIds` | | |
| 2 | `_applyStructureChange` writes the union | | |
| 3 | `restore()` seeds the lens | | |
| 4 | `_storeSnapshotEntry` clear + replace | | |
| 5 | S-124, S-125, S-126(second half) | | |
| 6 | regression suites + Progress | | |

Red→green table:

| Scenario | Red command / revert | Red output | Green output |
|---|---|---|---|
| S-124 | `prove-red` with the `restore()` seeding reverted | | |
| S-125 | `prove-red` with the replacement branch reverted to the merge | | |

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
