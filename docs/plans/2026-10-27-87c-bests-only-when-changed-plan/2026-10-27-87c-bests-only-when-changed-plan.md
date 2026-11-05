# Feature: 87c — the phone sends the watch its bests only when they changed

> Status: BUILT 2026-10-28, awaiting review (phone half committed 2c64ffa5). Series: `docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md`. Follows 87a (`bests_down`, d0189d6d) and 87b (the wrist's banner, 403d96d9). Nothing in this PR is visible on screen: it makes the "New PR" feature cheaper.

## Goal and acceptance

Since 87a the phone walks the whole workout history and sends the full `bests_down` frame (about 20 to 30 KB at the 300-exercise cap, an estimate) on EVERY routines request, including the idle raise that plan 74 made read nothing. The owner asked that the watch stay light on battery, work and memory. 87c makes both the phone's walk and the radio frame happen only when needed.

Acceptance: (1) a wrist that holds the bests, asking again with no workout written in between, is sent no `bests_down` and the phone reads NO history for that request; (2) a completed workout (or any history write) between two requests makes the next request send the new frame; (3) a history write that leaves the bests identical (an in-progress set) costs one walk and no frame; (4) a wrist that does not say it holds the bests (an older wrist, a reinstalled one, one that lost its copy) is sent the frame on every request exactly as today; (5) a frame the radio did not carry is sent again at the next request; (6) the wrist side only adds one key to its routines request and changes nothing else; (7) everything 87a and 87b pinned still holds.

## Design (technical, decided by the governor; the owner's constraint is "light on the watch")

The phone remembers what it last delivered, and the wrist says whether it holds a frame. No hash and no stamp on the wire, no change to the frame, no change to the wrist's store: the wrist's own copy is the truth about "holds", the phone's memory is the truth about "unchanged".

## Decision Ledger

- D-1 Send rule (phone, `WatchSyncRequestHandler._sendRoutines`, `lib/state/watch/watch_sync_request_handler.dart:148`, bests block at :213-219): the phone sends `bests_down` UNLESS ALL of: the request says the wrist holds bests (D-2), the phone's last `bests_down` was delivered (`WatchDelivery.delivered`, `lib/core/platform/watch_delivery.dart:19`), and the bests are unchanged since that frame (D-3 or D-4). Anything else sends, in the same position as today (last, after the exercise list, independent of `since` and the bundle stamp: 87a D-4).
- D-2 Wire: the wrist's routines request MAY carry `holdsBests: true`. It is omitted, never `false` and never null, when the wrist holds no bests frame (the pattern of `since` and `exercisesVersion`: `WatchTransportRequest.routinesFrame`, `lib/core/platform/watch_transport.dart:98`; Swift `WatchTransportRequest.routinesFrame`, `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift:97`). The phone reads it as held ONLY when the value is the boolean `true`; a string, a number, `false` or null means "not held". A request carries no `type` key (PROTOCOL.md:133-138). Additive; no version change (PROTOCOL.md version-history row in the style of the 2026-10-23 amendments).
- D-3 Cheap path: new `int? get historyRevision` on `WorkoutRepository` (`lib/data/repositories/workout_repository.dart:715` sits `referenceRevision`; same contract: a number that differs whenever a row was written, only compared for equality, null = cannot tell). `HiveWorkoutRepository` bumps it from box listeners on the boxes `StatsProgressService._loadHistory` reads for bests (`lib/core/services/stats_progress_service.dart:100`): sessions, segments, efforts, observations (planner: confirm the exact boxes against `getAllTimeBests`, and whether timed and round instances matter; sensor summaries do not), set up where `_listenForReferenceWrites` sets up the reference listeners (`lib/data/repositories/hive_workout_repository.dart:258`, counter at :179, getter at :2547). `MockWorkoutRepository` answers null (`lib/data/repositories/mock_workout_repository.dart:1858`). Read ONCE at the start of the request, before any read, so a write that lands during the request leaves the remembered number older than the data and the next request reads again (plan 74, D-4).
- D-4 Remembered state in the handler, like `_held` and `_exercisesHeld` (`watch_sync_request_handler.dart:71-77`): `({int? revision, String entriesText})? _bestsHeld`, set ONLY after a `bests_down` was delivered, where `entriesText` is `jsonEncode` of the frame's `bests` entries (they are already ordered by exerciseId and unrounded, 87a D-9..D-11, so equal bests give equal text; `generatedAt` is NOT part of it). A phone that relaunched holds none and sends once (as S-9212 does for the bundle).
- D-5 Request logic, in order: (a) wrist does not say it holds -> send (walk, build, send). (b) holds, `_bestsHeld` present, `revision != null` and equal to `_bestsHeld.revision` -> send nothing and read NOTHING (no `StatsProgressService` is even created). (c) otherwise walk and build; if the wrist holds and `_bestsHeld` is present and the entries text equals `_bestsHeld.entriesText` -> send nothing, but update the remembered revision to the one read at the start (so the next request takes (b)). (d) otherwise send; on `delivered` remember (revision read at the start, entries text); on anything else forget (`_bestsHeld = null`) so the next request sends.
- D-6 The bundle (`preferences_down`, `foods_down`, `routines_down`) and the exercise list are untouched; the bests frame stays last; a failed bests send never changes `_sendRoutines`' return value (87a S-87a-7).
- D-7 Wrist (Swift): `WatchSyncOrchestrator.sync` (`watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift:94`) passes `holdsBests: bests?.hasFrame ?? false` to `WatchSyncTransport.requestRoutines` (protocol at :36), `WatchConnectivityBridge.requestRoutines` (:163) puts the key in the frame only when true. `WatchPersonalBests.hasFrame` exists (87b). Every `WatchSyncTransport` implementer and test double is an impact row (planner greps). The Dart twin's `requestRoutines({DateTime? since})` (`lib/watch/start/watch_sync_orchestrator.dart:31`) does not send `exercisesVersion` either: unless a parity test forces it, it stays as it is (planner: report under Open questions).
- D-8 Out of scope: the `bests_down` frame and its schema, the wrist's store, detection, banner (87a, 87b); the bundle and exercise-list skipping (plan 74); an age rule; a wrist-side hash.
- D-9 Known cost of the design, accepted: if the wrist stored the frame badly while the radio said delivered, it stays without bests until the next history change or a phone relaunch. A frame the phone builds always passes the wrist's validator, and the wrist's own `holdsBests` makes a wrist that has nothing ask again.

## Core scenarios (re-derive every number in the first run)

Fixture: the 87a history H (bench-press 100 x 5 and 100 x 3 in session 1, 90 x 8 in session 2, squat 140 x 5, push-up 0 x 12; session 3 in progress) and a repository subclass with a settable `historyRevision` and a counter of history reads (the `_RevisionedRepo` pattern of `test/watch_sync_idle_reads_test.dart:132`).

- S-87c-1 Idle raise: request 1 (`holdsBests: true`, revision 5) sends one `bests_down` and counts N history reads (N > 0); request 2, same revision 5, `holdsBests: true`: no `bests_down` and the history read counter does not move. Red today: the frame is sent every request and the history is walked every request.
- S-87c-2 A completed workout between requests: revision 5 -> 6 and the entries differ (a new best): request 2 sends one frame whose entries are the new bests; request 3 at revision 6 sends nothing and reads nothing.
- S-87c-3 A write that leaves the bests identical (an in-progress set, revision 5 -> 6, entries equal): request 2 walks once (counter +N), sends nothing; request 3 at revision 6 reads nothing.
- S-87c-4 The wrist does not hold (key absent, `false`, `"true"`, `1`, null): every request sends the frame and walks, even at an unchanged revision.
- S-87c-5 Not carried: the transport answers `undelivered` for the first frame; request 2 (holds true, same revision) sends it again; after a `delivered` answer the next one is skipped. `queued` is treated as not delivered.
- S-87c-6 A new handler (phone relaunch) sends once for a wrist that holds.
- S-87c-7 Repository without a revision (`historyRevision` null, as the Mock): a wrist that holds is walked every request and sent a frame only when the entries text changed.
- S-87c-8 Hive `historyRevision` moves on a write to a session, segment, effort and observation row and does NOT move on a food or routine write (`referenceRevision` is the other counter and does not move on a session write).
- S-87c-9 Request parsing and building (Dart `WatchTransportRequest`): `holdsBestsOf(frame)` true only for the boolean `true`; `routinesFrame(holdsBests: true)` includes the key, `false` or omitted does not.
- S-87c-10 Wrist: `routinesFrame(since:exercisesVersion:holdsBests:)` carries the key only when true; the orchestrator sends it true after a `bests_down` was applied and absent before; a wrist that has restored a stored frame after a relaunch sends it true.
- S-87c-11 What 87a and 87b pinned still passes unchanged: `test/watch_sync_changed_only_test.dart` S-9201..S-9212 and S-9202, `test/watch_sync_idle_reads_test.dart` (the old requests carry no `holdsBests`, so they still receive the frame: planner lists each and confirms none loosens).

Mutation checks the planner must name: skip the `holdsBests` test (S-4); skip the revision comparison (S-1); skip the entries-text comparison (S-3); remember on any delivery result, not only `delivered` (S-5); read the revision after the walk instead of before (a test that bumps the revision inside the walk, S-2); wrist always sends the key (S-10).

## Phase outline (each at most 8 items; planner expands)

1. Phone (developer): `WorkoutRepository.historyRevision` (interface, Hive listeners, Mock null, every test subclass that needs it), `WatchTransportRequest.holdsBestsOf` / `routinesFrame(holdsBests:)`, `watch_sync_wiring.dart:318-324` passes it, handler rule D-4/D-5. Scenarios S-1 to S-9.
2. Wrist and contract (developer): Swift `routinesFrame`, `WatchSyncTransport.requestRoutines`, bridge, orchestrator, every double; PROTOCOL.md request note and version-history row, `watch/contract/watch_start_paths_contract.json` (the request sample at :352) if the contract tests walk it. Scenarios S-10, S-11. `swift test` runs.
3. Docs (developer): `docs/state_management/watch_reference_data.md` ("The bests close every answer": now "close every answer that needs them"), the doc that owns the request frame, the phone repository doc for `historyRevision`, QA step 36 (owner: sync twice with no workout in between, then beat a best: the banner still fires), plan and index statuses.

Phases 1 to 3 are one PR: two tracks (phone with the contract riding on the wrist consumer), one soft signal.

## Code pointers

Handler `watch_sync_request_handler.dart:71-77 _held/_exercisesHeld, :148 _sendRoutines, :213-219 the bests block, :230 _sendExerciseList (the version-skip pattern to copy)`; transport `lib/core/platform/watch_transport.dart:98 routinesFrame, :118 exercisesVersionOf`; wiring `lib/state/watch/watch_sync_wiring.dart:318-324`; repository `workout_repository.dart:715`, `hive_workout_repository.dart:179,258-285,2547`, `mock_workout_repository.dart:1858`; test pattern `test/watch_sync_idle_reads_test.dart:132 _RevisionedRepo`; Swift `WatchConnectivityBridge.swift:93-100,163`, `WatchSyncOrchestrator.swift:36,94-99`, `WatchPersonalBests.swift hasFrame`; protocol text `watch/sync_protocol/PROTOCOL.md:133-139`.

---

Everything below this line is the planner's expansion (2026-10-27). The seeded content above is unchanged.

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `WorkoutRepository` (new abstract getter `historyRevision`) | `implements WorkoutRepository`: exactly `HiveWorkoutRepository` (hive_workout_repository.dart:40) and `MockWorkoutRepository` (mock_workout_repository.dart:49); every test fake `extends MockWorkoutRepository` (~24 classes, e.g. `DelayedNoteRepository`, `DelayedRestMockRepository`, `_RevisionedRepo`) and inherits Mock's answer | Non-breaking: both implementers are edited in Phase 1A; `extends` subclasses inherit `null` | S-87c-7, S-87c-8 |
| `WatchTransportRequest.routinesFrame` (Dart) | built by `WatchConnectivityTransport.requestRoutines` (watch_transport.dart:295-296, the Dart twin's transport) and pinned by exact-equality tests S-102/S-3856 (`test/watch_transport_test.dart:1591-1660`) | The key is added ONLY when `holdsBests: true` is passed; every existing call omits it, so today's frames are byte-identical | S-87c-9, S-87c-11 |
| `WatchSyncRequestHandler.handle` | ONE production call site (`watch_sync_wiring.dart:320`); test callers in `watch_sync_request_handler_test.dart` (×30), `watch_sync_changed_only_test.dart` (×39), `watch_sync_idle_reads_test.dart` (×14), `rest_ping_contract_test.dart:314`, `watch_accent_contract_test.dart:148,162` — none passes `holdsBests` | New optional named parameter defaulting to `false` = "wrist does not hold" → D-5(a) → every existing request walks and sends exactly as today; no existing assertion loosens (checked suite by suite, see S-87c-11) | S-87c-4, S-87c-11 |
| The bests block in `_sendRoutines` | sends unconditionally today (watch_sync_request_handler.dart:213-219); the wrist's `bests_down` handling (87a/87b) reads the frame, not the send rule | Gated by D-5; frame content, position (last) and failure isolation (D-6) unchanged | S-87c-1..S-87c-5, S-87c-11 |
| `WatchSyncTransport.requestRoutines` (Swift protocol) | implementers/doubles: `WatchConnectivityBridge` (WatchConnectivityBridge.swift:163), `WireLog` (WatchConnectivityBridgeTests.swift:201), `GatedTransport` (:1311), `GatedRequestTransport` (:1365), `RecordingTransport` (WatchSessionStartPathsTests.swift:50) — grep `func requestRoutines` over `watch/watchos` finds exactly these | Signature gains `holdsBests: Bool`; all five conformers updated in Phase 2 (mechanic) | S-87c-10, S-87c-16 |
| `watch/contract/watch_start_paths_contract.json` `transportRequests` | walked with EXACT-equality assertions on both stacks: Dart `test/watch_transport_test.dart:116` (`_contract()`), Swift `WatchConnectivityBridgeTests.swift:136` (`bridgeContract()`) | Existing rows stay byte-identical; a NEW row `routinesBests` is added (D-15) and asserted by one new test per stack | S-87c-11, S-87c-16 |
| The Dart twin (`lib/watch/start/watch_sync_orchestrator.dart:31`, `NoWatchTransport.requestRoutines` :32, `WatchConnectivityTransport.requestRoutines` :295) | the twin's frames are pinned key-less by S-102/S-103 exact equality; the divergence is documented (`docs/state_management/watch_reference_data.md`, "The Dart watch client never reports a version (D-3805)") | UNCHANGED (D-7 answered under Open questions q-c) | S-87c-11 |
| `StatsProgressService.getAllTimeBests` | called by the handler's bests block (the only production caller of the walk in the sync path) and by stats screens | Unchanged; it is now called at most once per request and not at all on the D-5(b) skip | S-87c-1, S-87c-3 |
| Plan 74's reference listeners | `_listenForReferenceWrites` (hive_workout_repository.dart:258-285), counter :179, getter :2547; `referenceRevision` declared at workout_repository.dart:715 | Untouched; the new `_listenForHistoryWrites` mirrors it and the two counters stay independent (S-87c-8 asserts a session write does not move `referenceRevision`) | S-87c-8 |
| `docs/state_management/watch_surface_wrist.md` | 52200 B against the 52428 B warning band | NOT edited (the brief forbids additions there); the wrist-side rule is documented in `watch/sync_protocol/PROTOCOL.md` instead | Phase 3 |
| `docs/watch_session_sync.md` | grep: names no request-frame key and no bests | NOT edited | — |

## UI Standards Impact

None — nothing in this PR is visible on screen (the seeded header says so). No file under `lib/features/` is in Files Affected; no widget, screen, route or copy changes. `docs/design_system.md` is not read.

## Feature Invariants (this feature only)

- The bests frame's bytes never change: 87c adds no key to `bests_down` and reorders nothing (D-8; guarded by every S-87a test staying green).
- A skip must never hide a real change: the revision is read before any history read, and the remembered revision is the one read at the start (D-5, S-87c-12).
- The two revision counters are independent: a history write moves only `historyRevision`, a reference write only `referenceRevision` (S-87c-8).
- Old wrists and the Dart twin never send `holdsBests`, and the phone must treat that exactly as today (D-5(a), S-87c-4, S-87c-11).

## Appended scenarios

### S-87c-12: a write that lands during the walk is not hidden
- Fixture: the S-87c-1 repository, plus `getAllSessions` overridden to bump `historyRevision` by one on every call (simulating a write landing mid-request); one session with a 100 kg × 5 bench set; a second, heavier 110 kg × 5 set written between request 1 and request 2.
- Trigger: request 1 `routines` + `holdsBests: true`, delivered → (5, T1) remembered. Request 2: the revision read at the start is 6 ≠ 5 → walk; during the walk the override bumps the counter to 7; the walked data includes the 110 kg set → T2 ≠ T1 → frame sent, (6, T2) remembered. Request 3: revision 7 ≠ 6 → walk again, T2 == T2 → nothing sent.
- Expected outcome: request 2 sends one `bests_down`; request 3 walks (the history-read counter grows) but sends nothing. The mutation "read the revision after the walk" remembers (7, T2) at request 2, so request 3 would skip the walk — the counter assertion fails.
- Edge case of: S-87c-2 (this is the seeded mutation check "read the revision after the walk, S-2").

### S-87c-13: an undelivered frame is re-sent, then goes quiet
- Fixture: the S-87c-1 repository at revision 5; `_RecordingTransport` (test/watch_sync_changed_only_test.dart pattern) with `undeliveredBests = true` for request 1 only.
- Trigger: request 1 `routines` + `holdsBests: true` → frame built, `undelivered` → nothing remembered; request 2 (no writes, holds true) → `_bestsHeld == null` → walk and send, `delivered` → remembered; request 3 (no writes) → D-5(b) skip.
- Expected outcome: exactly two `bests_down` frames; request 3 sends nothing and reads nothing.
- Edge case of: S-87c-5 + S-87c-6 (the forget→re-send→skip chain end to end).

### S-87c-14: a request without `holdsBests` always sends, even with remembered state
- Fixture: the S-87c-1 repository at revision 5; `_bestsHeld` already remembered (5, T) from a prior delivered holds-request.
- Trigger: a request with the key absent, then one with `holdsBests: false`, then one with `holdsBests: "true"` (a string).
- Expected outcome: all three walk and send the frame (D-5(a)); after each delivery the remembered pair is refreshed.
- Edge case of: S-87c-4.

### S-87c-15: the Hive history listeners count every event kind on the four boxes
- Fixture: the plan-74 Hive harness (`test/repository_reference_revision_test.dart` pattern): the repository initialized with the four boxes seeded (2 sessions, 2 segments, 2 efforts, 2 observations) and `timed_instances` populated.
- Trigger: put one more session (+1); `putAll` two segment rows (+2); delete one effort (+1); `clear` the observations box (+1 per key); put a timed instance row (+0); put a food (+0); put an exercise (+0, and `referenceRevision` moves instead).
- Expected outcome: `historyRevision` moves by exactly the listened-box event count and not at all for `timed_instances`, foods or exercises; `referenceRevision` moves only for the reference writes.
- Edge case of: S-87c-8 (the seeded scenario names the boxes; this one names the event kinds and the negative cases).

### S-87c-16: the wrist's `sync()` derives the flag from its bests state
- Fixture: `GatedRequestTransport` (WatchConnectivityBridgeTests.swift:1365) with `bests` nil, then with a restored frame (`WatchPersonalBests.hasFrame` true, WatchPersonalBests.swift:74).
- Trigger: `sync()` in both states.
- Expected outcome: `requestRoutines` is called with `holdsBests: true` when the wrist holds a frame and `false` when it does not; the built frame carries the key only in the true case (D-2: omitted, never false/null).
- Edge case of: S-87c-10.

### S-87c-17: end to end, the second idle raise reads no history
- Fixture: the `watch_sync_idle_reads_test.dart` harness with `_RevisionedRepo` (:132) extended by `historyRevision` (settable) and a history-read counter; the wrist's raise frame carrying `holdsBests: true` after the first answer was applied.
- Trigger: raise 1 → the wiring passes `holdsBests: true` → one `bests_down`, N history reads; raise 2 with no write in between.
- Expected outcome: raise 2 sends no `bests_down` and the history-read counter does not move; S-10405's `transport.types == ['bests_down']` stays green because the harness's own request frames carry no `holdsBests` key (D-12 default false → D-5(a)).
- Edge case of: S-87c-1 (the same rule through the real wiring, not a direct `handle` call).

Mutation-check mapping (the seeded list, each with its killing test): skip the `holdsBests` test → S-87c-4; skip the revision comparison → S-87c-1; skip the entries-text comparison → S-87c-3 and S-87c-7 (the Mock has no revision, so only the text can stop the second send); remember on any delivery result → S-87c-5 and S-87c-13; read the revision after the walk → S-87c-12; wrist always sends the key → S-87c-16 and the S-102 exact-equality pins. The seeded S-87c-1..11 stay as written; S-87c-12..17 are their edge arms.

## Iteration 1 — expanded phases

### Phase 1A: phone data layer — interface, Hive listeners, Mock, transport (@dba)
1. [x] Add the abstract getter `int? get historyRevision;` directly beside `referenceRevision` — `lib/data/repositories/workout_repository.dart` · `WorkoutRepository` (after :715) — done, same contract wording as `referenceRevision`.
2. [x] Add the counter field `int _historyRevision = 0;` beside `_referenceRevision` (:179) and the getter `int? get historyRevision => _historyRevision;` beside the reference getter (:2547) — done.
3. [x] Add `_listenForHistoryWrites()` mirroring `_listenForReferenceWrites()` (:258-285): one cancel-then-recreate listener per box `_sessionsBox`, `_segmentsBox`, `_effortsBox`, `_observationsBox`, each `onData((_) => _historyRevision++)`; call it from `initialize()` immediately after `_listenForReferenceWrites()` and before `_initialized = true` (seed/migration events count, as for the reference counter) — done, own `_historyListeners` list.
4. [x] Add `int? get historyRevision => null;` beside `referenceRevision => null` (:1858) — done.
5. [x] Add the optional named parameter `bool holdsBests = false` to `routinesFrame`, adding the key `holdsBests: true` only when true (a false/omitted flag leaves the frame byte-identical to today's), and add `static bool holdsBestsOf(Map<String, Object?> frame) => frame['holdsBests'] == true;` beside `sinceOf` (:128) — done.
6. [x] Test S-87c-15: a new group in the plan-74 Hive harness file (or a sibling file reusing its harness) asserting the per-box, per-event-kind behaviour and the two counters' independence — done, `S-87c-15 Hive: the four history boxes move the number` (2 tests; mutation-proved).
7. [x] Test S-87c-9: a new group beside the `exercisesVersionOf`/`sinceOf` tables (:1680-1760) — done, `S-87c-9 the request says whether the wrist holds the bests` (3 tests; 2 mutations proved).


**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (issue count vs the ~180 pre-existing info notices: no new error or warning), `.github/copilot/scripts/macos/gateway.sh test` (full suite, 900 s timeout; plain `test()` only in the new groups — no `testWidgets`, no real `Future.delayed`).
**Predicted Files**: `lib/data/repositories/workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`, `lib/core/platform/watch_transport.dart`, `test/repository_reference_revision_test.dart`, `test/watch_transport_test.dart`.

### Phase 1B: phone handler + wiring + handler tests (@developer)
1. [x] Add the field `({int? revision, String entriesText})? _bestsHeld;` beside `_held`/`_exercisesHeld` (:71-77) — `lib/state/watch/watch_sync_request_handler.dart` · `WatchSyncRequestHandler`
2. [x] Add the optional named parameter `bool holdsBests = false` to `handle` — `lib/state/watch/watch_sync_request_handler.dart` · `WatchSyncRequestHandler.handle` (:96)
3. [x] Rewrite the bests block of `_sendRoutines` (:213-219) per D-5: the block's FIRST statement reads `final historyRevision = _repository.historyRevision;` (before any history read); branch (a) no flag → build and send as today; (b) flag + `_bestsHeld != null` + `historyRevision != null` + equal → return with no `StatsProgressService` created and no read; (c) flag + `_bestsHeld != null` + otherwise → walk, build the entries text (`jsonEncode` of the frame's `bests` entries, WITHOUT `generatedAt`), equal → send nothing and store `(historyRevision, text)`; different → send; (d) flag + `_bestsHeld == null` → walk and send; remember `(historyRevision, text)` ONLY on `WatchDelivery.delivered`, else `_bestsHeld = null`; a throwing walk sends nothing and remembers nothing (today's behaviour) — `lib/state/watch/watch_sync_request_handler.dart` · `_sendRoutines`
4. [x] Pass `holdsBests: WatchTransportRequest.holdsBestsOf(frame)` at the single production call site — `lib/state/watch/watch_sync_wiring.dart` · the inbound request handler (:318-324)
5. [x] Handler tests S-87c-1..S-87c-7, S-87c-12, S-87c-13, S-87c-14 in a new group beside S-87a-6..13, using a `MockWorkoutRepository` subclass with a settable `historyRevision` and a history-read counter (extract the `_RevisionedRepo` pattern of `test/watch_sync_idle_reads_test.dart:132` into `test/helpers/` if both files need it — mechanic) — `test/watch_sync_request_handler_test.dart` · new `test('S-87c-...')` group
6. [x] Wiring test S-87c-17: extend `_RevisionedRepo` (:132) with `historyRevision` + a history-read counter and add the scenario beside S-10405 (:266-296); confirm S-10405 and the rest of the file need no loosening — `test/watch_sync_idle_reads_test.dart` · `_RevisionedRepo`, new `test('S-87c-17 ...')`
7. [x] Verify-only: `test/watch_sync_changed_only_test.dart` S-9201..S-9212 (S-9202's "exactly one `bests_down`") and `test/watch_sync_request_handler_test.dart` S-3850..S-3857/S-7101..S-7105/S-87a-6..13 pass WITHOUT edits, because their `handle` calls carry no `holdsBests` (D-5(a)); if any fails, the D-5(a) branch is wrong — fix the branch, never the assertion
8. [x] Update the handler's header doc comment (it describes the bests block as unconditional) — `lib/state/watch/watch_sync_request_handler.dart` · file header

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`, `.github/copilot/scripts/macos/gateway.sh test`. If a Mock group is red, fix it before re-running the file (a red Mock group can leave its Hive group hanging — repo quirk).
**Predicted Files**: `lib/state/watch/watch_sync_request_handler.dart`, `lib/state/watch/watch_sync_wiring.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_sync_idle_reads_test.dart`, optionally `test/helpers/` (extracted repository double).

### Phase 2: wrist + contract (@developer)
1. [x] Add `holdsBests: Bool` to `WatchTransportRequest.routinesFrame` (key added only when true, D-2) — `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift` · `WatchTransportRequest.routinesFrame` (:97) — done.
2. [x] Extend the protocol method to `requestRoutines(since:exercisesVersion:holdsBests:)` — `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift` · `WatchSyncTransport.requestRoutines` (:36) — done.
3. [x] Pass `holdsBests: bests?.hasFrame ?? false` at the call — same file · `WatchSyncOrchestrator.sync` (:94-103) — done.
4. [x] Forward the flag into the frame builder — `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift` · `WatchConnectivityBridge.requestRoutines` (:163) — done.
5. [x] Update the four test doubles to the new signature, recording the flag — `WireLog` (watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift:201), `GatedTransport` (:1311), `GatedRequestTransport` (:1365), `RecordingTransport` (watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift:50) — done, each with `requestedHoldsBests`.
6. [x] Add the contract row `routinesBests` to `transportRequests` (:346-356): a routines request frame with `holdsBests: true` and no `since`/`exercisesVersion`; the existing `routines`/`routinesSince`/`routinesExercises` rows stay byte-identical — `watch/contract/watch_start_paths_contract.json` — done, one added line; the three existing rows are byte-identical.
7. [x] Swift test S-87c-16 + the contract pin: the bridge's frame for a holds-request equals the `routinesBests` row and for a not-holding request equals the `routines` row (NSDictionary exact equality, S-102 style), and `sync()` passes the flag per the bests state — `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift` · new `test('S-87c-16 ...')`/contract test beside S-102/S-103 — done, 2 tests (`testS87c16TheRoutinesRequestCarriesHoldsBestsOnlyWhenTheWristHoldsOne`, `testS87c16TheSyncPassesWhetherTheWristHoldsABestsFrame`); mutations M1–M3 red.
8. [x] Dart contract test: the Dart-built `routinesFrame(holdsBests: true)` equals the new `routinesBests` row (the same `_contract()` reader, :116) — `test/watch_transport_test.dart` · new test beside S-102/S-3856 — done (`S-87c-16 a wrist that holds the bests says so`), plus the wiring test S-87c-18 in `test/watch_session_projection_test.dart` (A-87c-8); mutation M4 red.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (900 s), `.github/copilot/scripts/macos/gateway.sh lint`, `.github/copilot/scripts/macos/gateway.sh test`.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`, `watch/contract/watch_start_paths_contract.json`, `test/watch_transport_test.dart`.

### Phase 3: docs + QA + statuses (@developer)
1. [x] `docs/state_management/watch_reference_data.md`: the request-frame section names `holdsBests` (a `true` only, omitted otherwise, read only as the boolean `true`, the `routinesBests` contract row); "The bests close every answer that needs them" states D-5 in owner terms with `historyRevision` and names S-87c-1, 3, 4, 5 and 18 — done
2. [x] `docs/db_integration.md`: a `historyRevision` row beside `referenceRevision` — same contract wording (equality only, null = cannot tell), the four listened boxes, the Mock's null, the S-87c-15 tests — done
3. [x] `docs/state_management/watch_surface.md`: the phone-side skip rule beside the plan-74 revision text, and the "Last, always" sentence corrected to "Last, … unless the wrist says it holds that frame" — done
4. [x] `docs/watch-app-qa-wrist-logging.md`: step 36 after 87b's step 35 — two syncs with no workout between, then beat a best and sync again — done
5. [x] `watch/sync_protocol/PROTOCOL.md`: the request rules name `holdsBests` with D-2's exactness rule, the bests bullet no longer says "every routines request", and a version-history row dated 2026-10-28 — done
6. [x] `docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md`: the 87b and 87c rows and the header moved to their real state — done
7. [x] Residue sweep: `holdsBests`/`historyRevision` readers all present; the "always travels" wording corrected in `watch_surface_wrist.md` (F3), `watch_surface.md` and PROTOCOL.md — done
8. [x] Progress, Assumption Log and the evidence file updated — done

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`, `.github/copilot/scripts/macos/gateway.sh test`, `.github/copilot/scripts/macos/gateway.sh swift-test`; the four edited `docs/` files stay under the 52 KB band (the implementer measures byte sizes; the planner cannot — see Open questions q-h); `test/docs_indexing_contract_test.dart` green.
**Predicted Files**: the five docs/protocol files above, `docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md`, this plan file, the evidence file.

## Files Affected (whole feature)

Production: `lib/data/repositories/workout_repository.dart`, `lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`, `lib/core/platform/watch_transport.dart`, `lib/state/watch/watch_sync_request_handler.dart`, `lib/state/watch/watch_sync_wiring.dart`, `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`.
Contract/protocol: `watch/contract/watch_start_paths_contract.json`, `watch/sync_protocol/PROTOCOL.md`.
Tests: `test/repository_reference_revision_test.dart`, `test/watch_transport_test.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_sync_idle_reads_test.dart`, optionally a new `test/helpers/` file, `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`.
Docs: `docs/state_management/watch_reference_data.md`, `docs/db_integration.md`, `docs/state_management/watch_surface.md`, `docs/watch-app-qa-wrist-logging.md`, `docs/plans/2026-10-26-87-wrist-new-pr-banner-index.md`.
Read-only dependents (must stay green, no edit): `test/watch_sync_changed_only_test.dart`, `test/rest_ping_contract_test.dart`, `test/watch_accent_contract_test.dart`, `test/watch_reference_sync_test.dart`, the ~24 `extends MockWorkoutRepository` test fakes, `lib/watch/start/watch_sync_orchestrator.dart`, `lib/core/platform/no_watch_transport.dart`, `lib/core/services/stats_progress_service.dart`.

## Notes

- Dependency graph: 1A → 1B → 2 → 3. Phase 2's Swift work needs only the contract row decision (D-15), but its Dart contract test (item 8) needs 1A's frame builder, so the phases stay sequential. Phase 3 needs everything.
- Intermediate state after 1B: the phone can skip, but no wrist sends the key yet — end-to-end behaviour is unchanged (every real request takes D-5(a)). After Phase 2 the full feature works. This makes 1B safe to ship alone if the wrist work slips.
- Legacy handling: an older wrist build, a reinstalled wrist and the Dart twin never send `holdsBests` → D-5(a) → today's behaviour, byte-identical frames (S-87c-4, S-87c-11).
- The `generatedAt` exclusion (D-4) is what makes S-87c-7 possible: on the Mock (revision always null) only the entries text can stop the second send, so S-87c-7 doubles as the kill-test for "include `generatedAt` in the text".
- The bests block runs at the END of `_sendRoutines`, after the bundle and the exercise list; only the bests block reads history, so reading `historyRevision` as the block's first statement satisfies "before any read" (D-3/plan 74 D-4). A write landing between the request's start and the block only makes the remembered revision older — safe by construction.
- Full `flutter test` takes minutes (900 s gateway timeout). Run Mock-first when iterating; a red Mock group can leave its Hive group hanging behind it.

## Progress

- [x] Phase 1A (phone data layer) — @dba — Complete 2026-10-27 (evidence: `.evidence.md`)
- [x] Phase 1B (handler + wiring + tests) — @developer — Complete 2026-10-27 (34 handler tests, 9 idle tests, full suite 5779 passed / 2 skipped; evidence: `.evidence.md`)
- [x] Phase 2 (wrist + contract) — @developer — Complete 2026-10-27 (2 Swift tests, 2 Dart tests; swift 1124 passed / 0 failures; full suite 5781 passed / 2 skipped; lint 180; evidence: `.evidence.md`)
- [x] Phase 3 (docs + QA + statuses) — @developer — Complete 2026-10-28 (docs and PROTOCOL rows; evidence: `.evidence.md`)
- [x] Review fix 3 (F4 PROTOCOL wording, F5/F6 Swift comments) — @developer — Complete 2026-10-28 (docs test 13 passed; swift 1124 passed / 0 failures; evidence: `.evidence.md` "Review fix 3")
- [ ] Review (evidence table, per-S conformance, impact re-grep) — @code-reviewer

## Assumption Log

- A-87c-1 The remembered text is `jsonEncode` of the frame's `bests` entries only, excluding `generatedAt` (D-4 says this; pinned here as the exact rule). Options: the whole frame's json / the entries list / a hash of the entries. Chose the entries list: `generatedAt` changes every walk and would defeat the comparison; the frame's other keys are constant. Vetoable before Phase 1B.
- A-87c-2 On a D-5(c) text-equal skip the remembered revision is updated to the one read at the start (the seeded D-5(c) wording, made concrete): safe because the text was just re-verified equal, and a write landing mid-walk still forces a re-walk since the stored value is the start-read (S-87c-12). Options: keep the older revision (also safe, converges slower). Vetoable before Phase 1B.
- A-87c-3 The Hive listeners cover exactly `sessions`, `segments`, `efforts`, `observations` — the boxes `getAllTimeBests` consumes (stats_progress_service.dart:2264+ reads sessions, segments, efforts, observations; `_loadHistory`'s timed/round instances and sensor summaries contribute nothing to bests). A write to an unlistened box cannot change the bests, so not bumping is correct and keeps the skip honest. Vetoable before Phase 1A.
- A-87c-4 The contract gains a NEW `routinesBests` row instead of extending the existing `routines` row: the existing rows are pinned by exact-equality tests on both stacks (S-102/S-3856 Dart, S-102/S-103/S-3820 Swift), and plan 23e2 added `routinesExercises` the same way. Vetoable before Phase 2.
- A-87c-5 `WatchConnectivityTransport.requestRoutines` (watch_transport.dart:295) gains no `holdsBests` parameter: it serves the Dart twin, which never holds bests (D-7, answered under Open questions q-c). Vetoable before Phase 1A.
- A-87c-6 S-87c-15's "clear the observations box (+1 per key)" is exercised through the repository's public `deleteObservationsForEffort` (one `deleteAll`, one event per key), because the group writes through the public API rather than a raw box handle. Options: reach `Hive.box('observations').clear()` in the test / per-key `deleteObservation` calls. Chose the public `deleteAll` path: same semantics the listener relies on, no bypass of the repository contract. Ratified/reverted by the reviewer.

- A-87c-7 S-10411 (plan 74's source scan) searched the exact `_sendRoutines` signature text, which D-5's `required bool holdsBests` parameter necessarily breaks; the needle is now `'Future<bool> _sendRoutines({'` and every assertion (five positions) is unchanged. Options: stop and report / widen to the method's prefix. Chose the widen: the guard's subject (the revision read precedes any read) is untouched and S-87c-12 covers the new block. Ratify/revert by the reviewer.
- A-87c-8 The wiring's `holdsBestsOf(frame)` pass has no scenario of its own in 1B: the `radio.fromWrist` harness lives in `test/watch_session_projection_test.dart`, outside 1B's Predicted Files, and S-87c-17 covers the seam at handler level. Options: add a wiring-level test now / defer. Deferred to Phase 2, whose Predicted Files are still open. Ratify/revert by the reviewer.
- A-87c-9 Two watch docs said the bests are sent whatever happened to the bundle, which D-5 makes false; corrected in place (25 changed lines across `watch_reference_data.md` and `watch_surface.md`) rather than left standing for the doc phase. Options: leave them / fix now. Chose fix now because a doc sentence the change falsifies is the kind that outlives the plan. The rest of the watch doc sweep stays with the phase that owns it. Ratify/revert by the reviewer.
- A-87c-10 S-87c-16's relaunch arm builds a SECOND `WatchPersonalBests` over the same store, `restore()`s it and gives it a fresh orchestrator, rather than reusing the first holder: the relaunch is the claim (the held copy survives), and `WatchPersonalBestsTests`' S-87b-11 relaunch tests use the same shape. The Swift contract pin sits in the S-102 group beside the other exact-equality pins; the flag arm sits beside it in `WatchConnectivityBridgeTests`.
- A-87c-11 PROTOCOL.md's version-history row is dated 2026-10-28, not the 2026-10-27 the Phase 3 item predicted: the protocol change landed with Phase 2 (which ran past midnight) and the row states the day it was written, like every other row in that table. Options: backdate 2026-10-27 (inconsistent with when the row was authored) or today (chosen).
- A-87c-12 `watch_surface_wrist.md` sat 229 B under the 80 % warning band (52200 B vs `round(65536 × 0.8) = 52429`), so F3's reword is paid for by shortening four phrases in the same paragraph rather than by growing the file: the sentence keeps its claim and the assertion in `test/docs_indexing_contract_test.dart` stays green. Options: split the page (a structure change outside a docs-wording phase) or trim prose in the edited paragraph (chosen).
- A-87c-13 The stale Swift doc comment "The phone sends the bests last on every request" (`WatchSessionEngineTests/WatchSyncProgressTests.swift`) is left for a Swift-touching phase: this phase is docs-only, and a test-file comment is neither `docs/` nor a file its brief names. Recorded in the Residue sweep so it cannot be lost. Fixed with its `WatchSyncProgress.swift` twin in Review fix 3 (F5/F6): comments only.

## Open questions

Answered from source during planning; each carries its evidence. None blocks the handoff.

- **q-a (seeded D-3's planner note) — which boxes, and do timed/round instances matter?** `StatsProgressService._loadHistory` (stats_progress_service.dart:100) reads seven repositories (getAllSessions, getSegmentsBySession, getEffortsBySegment, getObservationsByEffort, getTimedInstancesByEffort, getRoundInstancesByEffort, getSensorSummariesBySession), but `getAllTimeBests` (:2264+) consumes only sessions, segments, efforts and observations — timed/round instances and sensor summaries contribute nothing to the bests. So the listeners go on `sessions`, `segments`, `efforts`, `observations` only (A-87c-3). `box.watch()` event semantics: one event per put/delete, one per key on `clear` — the behaviour plan 74's reference listeners rely on (plan 74 D-3); `putAll` fires per key (the seed and migration paths use `putAll`, hive_workout_repository.dart:385,585-657, and their events count, as plan 74 documents for migrations). S-87c-15 pins all of this.
- **q-b — does the new abstract getter break any implementer?** No. `implements WorkoutRepository` matches exactly `HiveWorkoutRepository` (hive_workout_repository.dart:40) and `MockWorkoutRepository` (:49); every test fake `extends MockWorkoutRepository` and inherits Mock's `null` (the `referenceRevision => null` pattern at mock_workout_repository.dart:1858). Grep over `lib/` and `test/` found no third implementer.
- **q-c (seeded D-7's planner note) — does the Dart twin need the key?** No. `lib/watch/start/watch_sync_orchestrator.dart:31` declares `requestRoutines({DateTime? since})` and its caller (:92) passes only `since` — it never sends `exercisesVersion` either, a divergence already documented in `docs/state_management/watch_reference_data.md` ("The Dart watch client never reports a version (D-3805)"). No parity test forces the twin to carry the key: the twin's frames are pinned KEY-LESS by the S-102/S-103 exact-equality contract tests (`test/watch_transport_test.dart:1591-1660`). The twin stays unchanged (A-87c-5).
- **q-d — who calls `handle`, and does the new parameter break them?** One production call site (`watch_sync_wiring.dart:320`); test callers in `watch_sync_request_handler_test.dart` (×30), `watch_sync_changed_only_test.dart` (×39), `watch_sync_idle_reads_test.dart` (×14), `rest_ping_contract_test.dart:314`, `watch_accent_contract_test.dart:148,162`. With `bool holdsBests = false` every existing call means "not held" → D-5(a) → unchanged behaviour; no assertion loosens (S-87c-11).
- **q-e — can the contract sample be extended in place?** No — the `transportRequests` rows are walked with EXACT-equality assertions on both stacks (Dart `_contract()` at test/watch_transport_test.dart:116 with S-102 :1591-1611 and S-3856 :1645-1660; Swift `bridgeContract()` at WatchConnectivityBridgeTests.swift:136 with S-102/S-103/S-3820). Adding `holdsBests` to an existing row breaks those pins. The safe shape is a NEW `routinesBests` row (D-15, A-87c-4), the precedent of plan 23e2's `routinesExercises`.
- **q-f — where exactly is the revision read, and can a skip hide a change?** The block's first statement, before any history read (Phase 1B item 3), the plan-74 pattern (`final revision = _repository.referenceRevision;` first, guarded by S-10411 at test/watch_sync_idle_reads_test.dart:466-487). A write landing between the read and the walk leaves the remembered revision OLDER than the data → the next request re-walks (S-87c-12 kills the "read after the walk" mutation). A write landing after the walk bumps the counter above the remembered start-read → the next request re-walks too. No skip can hide a real change.
- **q-g — is `queued` possible for `bests_down`, and what does "not delivered" mean?** `bests_down` is not in `_queueable` (watch_transport.dart:225-232), so the real transport can only answer `delivered` or `undelivered` for it (WatchDelivery, lib/core/platform/watch_delivery.dart:19); test doubles could answer `queued`. D-5's "on anything else forget" treats `queued` as not delivered — the seeded wording is correct and S-87c-5 pins it.
- **q-h — doc scope and sizes.** `docs/state_management/watch_reference_data.md` owns both the request-frame section (:146-160) and the bests section (:222+) — both edited. `docs/db_integration.md:201` documents `referenceRevision` — the `historyRevision` row goes beside it. `docs/state_management/watch_surface.md:560,570` gets the phone-side rule. `docs/watch-app-qa-wrist-logging.md` step 35 (:327) is 87b's banner step — 87c adds step 36. `watch/sync_protocol/PROTOCOL.md:133-139` + the version-history table (:730-765) get the amendment. NOT edited: `docs/state_management/watch_surface_wrist.md` (52200 B, inside the 52428 B warning band — the brief forbids additions) and `docs/watch_session_sync.md` (grep: names no request key and no bests). The planner cannot measure byte sizes (no shell beyond the gateway); the implementer measures before and after each doc edit (the 87a precedent, its Open question 5).
