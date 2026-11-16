# Feature: 204 — the wrist names its session's modality in its snapshot (Swift engine and Dart twin)

> Status: SEEDED by the governor 2026-11-15; the architect step is skipped (A-1). Defaults marked **owner to confirm**.
> Next handoff: crew-builder-watch
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`, `docs/state_management/watch_surface_wrist.md`, `.github/copilot/pr-scope-budget.md`
> Related plans: 203 (the phone reads the key; the contract wording and fixture are its P2), 176 (the modality grid), 125d (the phone names its modality to the wrist: the receiving rule)
> Track: watch client only (Swift engine, Dart twin). Depends on nothing in 203 to build; the two together make the owner-visible change.

## Goal and acceptance

The wrist's session row holds a `modality` (the grid's key, a routine's Focus, or the phone's, stamped on first hearing), but the wrist's own `session_snapshot` to the phone omits it, so the phone adopts a Cardio workout as Free Training (plan 203 explains the phone side).

After this change the wrist's `session_snapshot` payload carries `modality` exactly when its session row holds one, spelled the way the row holds it; a Free workout (no modality) sends none. The key is never null and never empty (the schema's rule, already declared: `session_snapshot.schema.json` `modality`, minLength 1).

Acceptance: the scenarios below fail on the old code; the Swift whole target (`WatchSessionEngineTests`) and the Dart watch tests named below are green with observed counts; the watch target compiles (lead, `xcodebuild`).

## Decision Ledger

| ID | Decision | Where |
|---|---|---|
| D-20401 | **`sessionSnapshot(messageId:)` adds `modality` to the payload when `session.modality` is a non-empty string.** The payload literal becomes a `var payload: [String: Any]` with the seven existing keys unchanged, then `if let modality = session.modality, !modality.isEmpty { payload["modality"] = modality }`. No other key moves; the envelope is unchanged. | `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (`sessionSnapshot`, ~line 322) |
| D-20402 | **The Dart twin does the same** so the harness and the contract stay one behaviour: `WatchSessionEngine.sessionSnapshot` in the twin adds `'modality'` under the same condition. | `lib/watch/session/watch_session_engine.dart` (~line 295) |
| D-20403 | **Not changed:** what the wrist does with an incoming `modality` (first hearing only, D-12591/D-12592), `createSession`, the validators, the schema (already declares the key), the phone. The wrist's snapshot echo of a phone-stamped modality is harmless: the phone's reconciler ignores the key and the phone's session already holds it. | — |
| D-20404 | **New Swift function names avoid the append-only guard's verbs** (update, delete, remove, replace, edit, overwrite, write, clear, purge, wipe, reset, drop, truncate, erase, forget, modify, mutate, destroy, set): this change adds no function. | — |

## Input-reality checklist (answered)

1. **Writers.** The row's `modality` is written by `createSession(modality:)` (grid key via `startModalityWorkout`, `routine.startModality`, nil for a free workout) and by the phone-snapshot first-hearing stamp (`knownModality`); every writer filters to the grid's `byModality` keys (scout sheet 4, Q4). The key is read verbatim.
2. **Lifecycle.** A session with no modality (a free workout, a routine with no Focus) sends no key; a relaunch rebuilds the row from storage with its modality (persisted `"modality"` field), so the key survives a relaunch.
3. **Settings.** None.
4. **Time.** None.
5. **Cost.** One optional dictionary entry per snapshot.
6. **Words.** The contract paragraph and the amendment row are plan 203's P2; the wrist docs have no sentence about the snapshot's key set (the Docs delta says so).
7. **Competition.** None.

## Feature invariants

- The key is present only when the row holds a non-empty modality, never null (D-20401, S-20402).
- Every other payload key is exactly what it was (D-20401, S-20403).
- The emitted snapshot still conforms to the schema on both stacks (S-20403, S-20405).

## Existing-functionality impact

| Touched surface | What reads it (search run 2026-11-15, scout sheet 4 Q3) | Effect | Guarded by |
|---|---|---|---|
| The wrist's emitted snapshot | Swift: `WatchConnectivityBridgeTests.swift:631` compares the engine's snapshot with the frame the bridge sent (self-comparison, plist round trip); `WatchLiveMirroringTests.swift:225-232` reads fields. Dart: no test compares the emitted payload whole; `test/watch_timer_push_test.dart:1933` copies and mutates one field | An added key round-trips unchanged; no break expected | S-20403 |
| The phone's reception | The phone reads the key only after plan 203; until then the reconciler ignores it | None | — |
| Snapshot schema gate | `WatchSessionEngine.swift:342` `try? requireConformant(envelope)`; twin `watch_session_engine.dart:295` `_requireConformant(envelope)`: `modality` is declared | Conforms | S-20403, S-20405 |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-20401 | Swift: `createSession(modality: "cardio_endurance", exercises: [one slot])`; `engine.sessionSnapshot()` | `payload["modality"] as? String == "cardio_endurance"` | the payload has no such key |
| S-20402 | Swift: `createSession(modality: nil, ...)` | the payload has no `modality` key at all (`payload.keys` does not contain it; not NSNull) | passes today — pin |
| S-20403 | Swift: the S-20401 snapshot | the seven existing keys (`sessionId`, `revision`, `status`, `currentExerciseIndex`, `exercises`, `entries`, `timers`) are present and the validator accepts the envelope (`SyncProtocolValidator` over the snapshot; the file's own conformance helper) | n/a — pins no regression |
| S-20404 | Swift: a wrist with no session hears a phone snapshot naming `modality: "sports"` (first hearing creates the row); then `engine.sessionSnapshot()` | the wrist's own snapshot carries `modality == "sports"`; a LATER phone snapshot naming `"cardio_endurance"` does not change it | the key is not emitted |
| S-20405 | Dart twin: the S-20401 and S-20402 cases through `lib/watch/session/watch_session_engine.dart`'s `sessionSnapshot()`; conformance through the twin's validator | as S-20401/S-20402/S-20403 | the twin omits the key |
| S-20406 | Swift relaunch: create with a modality, build a second engine over the same store, `restore()`, `sessionSnapshot()` | still carries the modality | n/a — pins storage round trip |

## Phases

**P1 — Swift (owner: crew-builder-watch; scope `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSnapshotWristModalityTests.swift` (NEW), `.work/crew/2026-11-15-204/report-watch-p1.md`; after plan 202's Swift runs).** Items: D-20401; the test file with S-20401..S-20404 and S-20406.

**P2 — Dart twin (owner: crew-builder-watch; scope `lib/watch/session/watch_session_engine.dart`, `test/watch_snapshot_wrist_modality_send_test.dart` (NEW), `.work/crew/2026-11-15-204/report-watch-p2.md`; may run beside P1: disjoint files, Flutter vs Swift).** Items: D-20402; the test with S-20405.

**P3 — docs: none** (see Docs delta).

## Docs delta

Docs delta: none - the contract paragraph and the amendment row for this key are plan 203's P2 (`PROTOCOL.md`), and no doc under `docs/` describes the key set of the wrist's snapshot (grep `phone to watch only` over `docs/` found none outside plans).

## Progress

- [x] Seeded by the governor 2026-11-15.
- [x] P1 Swift
- [x] P2 Dart twin
- [x] Prove, review, report

## Assumption Log

| # | Assumption | Source | Status |
|---|---|---|---|
| A-1 | The architect step is skipped: the seed names files, symbols and fixtures. | lead | open |
| A-2 | Owner-visible only together with plan 203; QA step is plan 203's. | lead | open |
