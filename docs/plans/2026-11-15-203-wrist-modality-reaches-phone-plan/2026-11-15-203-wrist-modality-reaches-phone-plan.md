# Feature: 203 — a workout started from a watch modality button shows as that modality on the phone (phone reads, contract wording)

> Status: SEEDED by the governor 2026-11-15; the architect step is skipped (A-1). Defaults marked **owner to confirm**.
> Next handoff: crew-builder-app (P1), crew-builder-watch (P2 contract)
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`, `docs/watch_session_sync.md`, `.github/copilot/pr-scope-budget.md`
> Related plans: 176 (the modality grid), 125d (the phone names its modality to the wrist), 122/125 (routine Focus), 204 (the wrist-side sender: Swift engine and Dart twin, the next plan)
> Track: phone (`lib/state/watch/`) plus the contract's wording and one fixture. The wrist's sending side is plan 204: until it ships, this change is dormant (a snapshot without `modality` behaves exactly as today).

## Goal and acceptance

Independent review, 2026-11-15: "A Cardio workout started on the watch still shows as Free Training on the phone." The phone adopts a running wrist workout from the wrist's `session_snapshot`; the adopted session's modality comes from the matching routine only (`watch_session_adoption_bridge.dart` `_adopt`, `modality: routine?.template.focusModality`), and the reconciler drops the snapshot's `modality` key before adoption sees it.

After this change (with plan 204 on the wrist): a workout started from the Cardio, Resistance, Sports or Isometric button is adopted on the phone as that modality, so its summary, calendar entry, colour and Home tile say Cardio (etc.) instead of Free Training. A workout the wrist started from a routine keeps working: the wrist's own value wins, as it already does when the phone imports a finished wrist workout (`S-12516 the wrist's end.modality wins`).

Acceptance: the phone scenarios below fail on the old code; the contract text and one new fixture conform on both stacks; `flutter test` (full) and `swift test --filter SyncProtocolFixturesTests` green with observed counts; docs contracts green.

## Decision Ledger

| ID | Decision | Where |
|---|---|---|
| D-20301 | **The router hands the wrist's modality to adoption; `convergedState()` is unchanged.** `WatchIncomingRouter.receive` already holds the raw envelope when it calls `_adoption?.consider(_mirror.state)` (`watch_incoming_router.dart` ~line 151). It reads `envelope['payload']['modality']` for a `session_snapshot` (a String, non-empty; anything else is null) and passes it as `consider(converged, wristModality: <value>)`. The reconciler, `_mirror.state` and the mirror's outgoing snapshot echo are untouched (the key must not ride the phone's own snapshots: the schema documents it phone to wrist there and no pinned test compares that payload). | `lib/state/watch/watch_incoming_router.dart`, `lib/state/watch/watch_session_adoption_bridge.dart` |
| D-20302 | **`consider` and `_adopt` gain an optional named `String? wristModality`** (default null, so every existing call and test compiles). `_adopt` writes `modality: _knownModality(wristModality) ?? routine?.template.focusModality`. `_knownModality(String?)` returns the key only when `ModalityConfig.forModality(key) != null` (an unknown or empty key is null, so a newer wrist cannot plant a key the phone cannot render). **The wrist's own value wins over the routine's Focus** (as the importer does, S-12516). | `watch_session_adoption_bridge.dart` (`consider` ~line 748, `_adopt` ~line 1195) |
| D-20303 | **Adoption is create-only for modality too:** a session the phone already holds is never rewritten from a later snapshot (the importer's rule, S-12521). The `session_started` path (`_startSessionRow`, ~line 1147, `modality: template?.focusModality`) is NOT changed: the wrist sends no modality on `session_started`; a session first created there keeps today's behaviour. (accepted; owner to confirm if that path matters: the wrist's first frames are a lifecycle plus a snapshot, never `session_started`, per the owner's 2026-11-15 log.) | — |
| D-20304 | **Contract wording only, no schema shape change.** `session_snapshot.schema.json` already declares optional `modality` (minLength 1, no enum). Its `description` says "phone to watch only": reworded to "either direction; the wrist names the modality its session row holds, the phone names its own". `PROTOCOL.md` lines ~219-226 (the `session_snapshot` rules) are reworded the same way and the amendment table gets a 2026-11-15 row. One new valid fixture `fixtures/valid/session_snapshot_modality_from_wrist.json` (an `origin: "watch"` snapshot carrying `"modality": "cardio_endurance"`) registered in `manifest.json`. No version change: only what is documented widens; nothing a v1 client sends becomes invalid. | `watch/sync_protocol/schemas/messages/session_snapshot.schema.json`, `PROTOCOL.md`, `fixtures/valid/`, `manifest.json` |
| D-20305 | **Not changed:** the phone's effort-kind resolution for adopted wrist slots (`_effortKind`, ~line 1577: "a wrist snapshot carries no modality, so a slot nothing decides logs sets"); the wrist's logging screen choice; the importer; `convergedState()`. The owner's next batch (the logging screen follows the modality) owns those. | — |

## Input-reality checklist (answered)

1. **Writers.** The only writer of the key on this wire is the wrist's snapshot (plan 204); the phone reads it once, at adoption. The wrist writes only `byModality` keys (`WatchActivityTypes.knownModality`); the phone re-checks with `ModalityConfig.forModality` (an older wrist sends nothing).
2. **Lifecycle.** A session adopted earlier as Free stays Free (create-only; an owner can edit the session's modality on the phone as today). A session the phone already ended (`fate`) is never adopted (router branch above `consider`). A rolling/imported session is not touched.
3. **Settings.** None.
4. **Time.** None.
5. **Cost.** One map read per snapshot that reaches `consider`; no new I/O.
6. **Words.** `Free Training` is the null-modality label (`session_summary_builder.dart:193`); nothing new is shown. Docs: the Docs delta.
7. **Competition.** Wrist modality vs routine Focus: the wrist wins (D-20302, S-20304). Wrist modality vs a session the phone started itself: that session is the phone's own, never adopted.

## Feature invariants

- With no `modality` in the wrist's snapshot the adopted session is byte-for-byte what it is today (D-20302, S-20302).
- An unknown, empty or non-string key never reaches a stored session (D-20302, S-20303).
- The phone's outgoing snapshots and `convergedState()` are unchanged (D-20301).

## Existing-functionality impact

| Touched surface | What reads it (search run 2026-11-15) | Effect | Guarded by |
|---|---|---|---|
| `WatchSessionAdoptionBridge.consider` | One caller, `watch_incoming_router.dart:151`; tests call it directly with a converged map: `test/pr4_session_controls_test.dart:705,821`, `test/watch_session_finish_test.dart:673,1155`, `test/watch_session_adoption_bridge_test.dart:322` | The new parameter is optional and named: unchanged | S-20302 |
| `WatchIncomingRouter.receive` | `test/watch_incoming_router_test.dart` (the builder greps `WatchIncomingRouter(` in `test/`) | Reads one more payload key on a snapshot | S-20301 |
| `S-12204` tests (`test/watch_routine_adoption_test.dart:612,633`) | A no-focus routine adopts with null; a focused routine with its Focus: both fed snapshots without `modality` | Unchanged | S-20302 |
| Fixtures | `test/sync_protocol_fixtures_test.dart` (`S-001` walks the valid register; `S-002/S-004` compare `convergedState()` to `expected` for reconciliation fixtures only); Swift `SyncProtocolFixturesTests` walks the same manifest | The new valid fixture is conformance-walked on both stacks; no reconciliation fixture changes | S-20306 |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-20301 | The adoption-bridge harness of `test/watch_session_adoption_bridge_test.dart`: a wrist `session_snapshot` envelope for an unknown session with a free-style ladder (no routine matches) and `payload.modality == 'cardio_endurance'`, delivered through `WatchIncomingRouter.receive` | the repository's session row has `modality == 'cardio_endurance'` | adoption reads only the routine |
| S-20302 | Same, no `modality` key | the row's `modality` is null | passes today — pin |
| S-20303 | Same, with `modality` = `'curling'`, then `''`, then `5` (a number) in three runs | `modality` null each time | n/a today — pins D-20302 |
| S-20304 | A wrist snapshot whose ladder matches a routine whose Focus is `resistance_lifting`, with `payload.modality == 'cardio_endurance'` | `modality == 'cardio_endurance'` and `routineTemplateId` still set (the routine still links) | the routine's Focus is used |
| S-20305 | A session the phone already holds (adopted by an earlier snapshot without modality); a later snapshot carries `modality: 'cardio_endurance'` | the held session's modality is unchanged (null) | n/a — pins create-only |
| S-20306 | `fixtures/valid/session_snapshot_modality_from_wrist.json` | conforms on the Dart walk (`S-001`) and the Swift walk (`testEveryValidFixtureConforms`) | the fixture does not exist |
| S-20307 | Source guard on `watch_incoming_router.dart`: the exact statements that return null for a non-snapshot type and pass `wristModality: _wristModality(envelope)` to `consider` (whole statements, crew rule (ao)) | as stated | the router passes nothing |

## Phases

**P1 — the phone reads it (owner: crew-builder-app; scope `lib/state/watch/watch_incoming_router.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`, `test/watch_session_wrist_modality_test.dart` (NEW), `.work/crew/2026-11-15-203/report-app-p1.md`; runs now, in parallel with plan 202's Swift run).**
Items: D-20301, D-20302, the new test file with S-20301..S-20305 and S-20307, run under Mock AND Hive if the harness offers both (crew rule (i)).

**P2 — the contract wording and the fixture (owner: crew-builder-watch; scope `watch/sync_protocol/schemas/messages/session_snapshot.schema.json`, `watch/sync_protocol/PROTOCOL.md`, `watch/sync_protocol/fixtures/valid/session_snapshot_modality_from_wrist.json` (NEW), `watch/sync_protocol/fixtures/manifest.json`, `.work/crew/2026-11-15-203/report-watch-p2.md`; serial, after plan 202's Swift run).** Items: D-20304; run `swift-test --filter SyncProtocolFixturesTests` and `gateway.sh test -- test/sync_protocol_fixtures_test.dart`.

**P3 — docs (owner: crew-docs-keeper; scope `docs/watch_session_sync.md`, `docs/watch-app-qa-wrist-logging.md`; after P1 and P2).** Execute the Docs delta (the contract's own PROTOCOL.md edit is P2's).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/watch_session_sync.md | ADDED | - | `an adopted wrist workout takes the wrist's own modality first, then the routine's Focus` | S-20301, S-20304, S-20302 |
| docs/watch-app-qa-wrist-logging.md | ADDED | - | `**A Cardio workout from the watch shows as Cardio on the phone — (owner, plans 203 and 204).**` | S-20301 |

## Progress

- [x] Seeded by the governor 2026-11-15 (scout sheet 4 read).
- [x] P1 phone reads it
- [x] P2 contract wording and fixture
- [x] P3 docs
- [x] Prove, review, report

## Assumption Log

| # | Assumption | Source | Status |
|---|---|---|---|
| A-1 | The architect step is skipped: the seed names files, symbols and fixtures. | lead | open |
| A-2 | Wrist wins over routine Focus, as `S-12516` does for the importer. | lead, owner to confirm | open |
| A-3 | The `session_started` path keeps today's behaviour (D-20303). | scout sheet 4 + owner's log | open |
