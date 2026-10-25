# Feature: 71 — a workout you start on the phone and follow on the watch brings the watch's heart rate to the phone

> Status: Iteration 1 active. No owner question (a heart-rate number appearing where it was missing). Two tracks, one contract amendment: phone importer, then watch + contract. The phone summary screen refreshing when the numbers arrive late is plan 72.
> Next handoff: `crew-builder-app` (Phase 1, phone), then `crew-builder-watch` (Phase 2, wrist + contract).
> Base: `c1b1c5f0` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Binding: `docs/global_conventions.md`; `.github/copilot/pr-scope-budget.md`; `watch/sync_protocol/PROTOCOL.md`.

## Overview

| What you do | Now | After 71 |
|---|---|---|
| Start a workout on the phone, the watch follows and records heart rate, you finish on either device | The watch's own summary shows Avg HR; the phone's session summary and history never get it | The watch sends its heart-rate summary for the followed workout; the phone stores it and the summary shows it |
| Start and finish on the watch | Phone gets the summary | Unchanged |
| The phone workout was deleted from history before the watch's numbers arrive | — | Nothing is re-created; the numbers are dropped |

Code facts (scouts + lead, 2026-10-24):
- Wrist: `WatchSessionEngine.captureSessionEnd` (`WatchSessionEngine.swift` l.1572-1595) returns early unless `origin.source == Self.wristSource` (`"watch"`, l.99); so a session the phone started (creation row source `"phone"`) never gets a `session_end`. The sensor samples ARE recorded for any active session (`WatchSensorCoordinator.apply`, no source guard) and a HealthKit workout opens for any active session. `isEndAcknowledgedWhereOwed` (l.1705-1708) holds the prune gate only for wrist-created sessions.
- Phone: `WatchSessionImporter.apply` (`lib/core/services/watch_session_importer.dart` l.133-215): held session (`phoneOwnsSession` true, i.e. the phone's live `currentSession`) → `_mergeHeld`, which already attaches the wrist's summary when its end is news (l.~277-284) and never touches the session row; a session in history but not held → the general import path, which for an existing session tops up the rating, attaches the summary AND merges the wrist's effort rows into the phone's segment (`_segmentId` reuses the phone's first segment); a session that is gone → `_createSession` for a `completed` end (a deleted phone session would be re-created).
- Wire: `session_end` is a closed entry (`watch/sync_protocol/schemas/envelope.schema.json` entry properties l.~270-318; Swift `SyncProtocolValidator.captureFieldKinds` l.78-88; Dart `MessageValidator._captureFieldKinds` l.134-144); PROTOCOL.md l.370-380 says a followed session gets no end.

## Decision Ledger

- **D-1** The wrist appends the `session_end` for ANY session it saw end (completed or abandoned), not only wrist-created ones: `captureSessionEnd`'s `origin.source == Self.wristSource` line is removed. `entryId`/`eventId` stay `end-<sessionId>`; the "one per session" rule (`knowsObservation`) stays.
- **D-2** New optional field `followed` on a `session_end` entry only: the boolean `true`, present exactly when the session's creation row source is not `"watch"`; omitted otherwise (a wrist-created end is byte-for-byte what it is today). Schema: `"followed": { "enum": [true], "description": "..." }`; Swift `captureFieldKinds` and Dart `_captureFieldKinds` gain `followed` → `['session_end']`; a `followed` anywhere else is rejected by the same semantic layer as `status`. Additive: no protocol version change.
- **D-3** `isEndAcknowledgedWhereOwed` is unchanged: a followed session's end is an ordinary unconfirmed observation, so the observation gate already holds the session until the phone acknowledges it; sessions that ended before this plan have no end and are pruned exactly as before. Its doc comment is updated.
- **D-4** Phone importer: when the end row's payload has `followed == true` (and `phoneOwnsSession` is false) the importer takes a dedicated branch `_applyFollowedEnd` and nothing else: no session is created, no effort row is merged, the end row is the only row marked applied and acknowledged. A completed end for a session still in history attaches the session-scope `SensorSummary` (the same call `_mergeHeld` uses); an abandoned end, an end for a session no longer in history, and an end already applied attach nothing. The held case (`phoneOwnsSession` true) keeps `_mergeHeld`, which already does the right thing.
- **D-5** `WatchSessionImport` gains `bool sensorSummaryAttached` (default false), true when the pass wrote a session-scope summary (followed branch, `_mergeHeld`, and the general path alike). Plan 72 reads it; this plan only sets it. Implemented with a `summaryWritten` flag on `_Pass` set by `_attachSessionSummary` when the repository wrote.
- **D-6** Not changed: the per-set heart-rate blocks of a followed session (`setBlockHeartRates` are attached only by the general path, which a followed end never takes: known limit, the session-level average and maximum are what the summary shows); effort-rating flow; what a followed session's wrist-logged sets do (they merge while the session is held, as today).
- **D-7** Waiting readers: the wrist's end-of-session replay in `WatchSyncOrchestrator.sync` ("replays a session end") — read before building P2: it replays a session end only for wrist-created sessions or for all? (`grep -n "sessionEnd\|replay" WatchSyncOrchestrator.swift`); P2 states the answer in its report and the lead decides.

## Feature Invariants

- A wrist-created session's `session_end` is unchanged on the wire (no `followed` key).
- The phone never creates a session from a followed end.
- At most one `session_end` per session on the wrist (S-9xxx family stays green).

## Scenarios (ids `S-101xx`; grep 2026-10-24: unused)

Phone (Mock AND Hive via `test/helpers/repository_harness.dart`, plain `test()`), using `WatchInboxEntry` rows staged as `test/watch_session_merge_test.dart` does:
- **S-10101 a followed completed end for a session in history attaches the heart rate and nothing else.** Fixture: phone session `phone-s1` in history with 2 efforts; staged end row `end-phone-s1` (`followed: true`, `status: completed`, `avgHeartRateBpm: 133`, `maxHeartRateBpm: 171`, window = the session's own start/end) plus one unapplied wrist set row for slot `a` (reps 9). `apply('phone-s1', phoneOwnsSession: false)`. Expected: exactly one session-scope `SensorSummary` (133/171); the session's efforts and entry count unchanged; the end row applied; the wrist set row still UNAPPLIED; result `appliedEntryIds` names the end only, `sensorSummaryAttached == true`. Fails today: the general path merges the set row and attaches via a different route (and would create the session when absent).
- **S-10102 a followed end for a deleted session creates nothing.** Fixture: no session `phone-gone`; end row followed completed with HR. Expected: `getSession` still null; no summary; end row applied; `sensorSummaryAttached == false`. Fails today: `_createSession` re-creates it.
- **S-10103 a followed abandoned end attaches nothing and is consumed.**
- **S-10104 a followed end arriving twice attaches once** (second `apply` after the first marked it applied: summary count stays 1, `sensorSummaryAttached == false`).
- **S-10105 a held session with a followed end** (`phoneOwnsSession: true`): summary attached (existing `_mergeHeld` behaviour pinned), `sensorSummaryAttached == true`, session row untouched.
- **S-10106 a wrist-created end (no `followed`) still creates the session** (regression arm: the existing import tests cover it; name the one you rely on in the report).
- **S-10107 an end with `followed` true but no heart rate** (`avg`/`max` absent): the end row is consumed, nothing attached, `sensorSummaryAttached == false`.
- **S-10108 `_captureFieldKinds` accepts `followed` on `session_end` and rejects it on `set`** (validator unit test; uses an inline envelope built by copying `observations_up_session_capture.json`'s shape; the schema file change is P2, so this test is written in P2 where the schema exists — see P2).

Wrist (package tests, `WatchSessionEngineTests` style; copy the fixtures the D-120 tests use at `WatchSessionEngineTests.swift` l.1085-1110 and l.1354):
- **S-10111 a phone-started session ended by the phone's lifecycle message gets one `session_end`** with `followed == true`, `status completed`, `startedAt` of the phone's session, `avgHeartRateBpm`/`maxHeartRateBpm` from samples recorded inside its window (use a sample set unlike the D-120 test's: 121, 131, 141 → avg 131, max 141). The existing test at l.1354 (`XCTAssertNil(sessionEnd(engine), "D-120 a session the wrist joined from the phone gets none")`) is replaced by this expectation.
- **S-10112 ended by a phone snapshot with status `completed`**: one end, `endedAt` = the envelope's `sentAt`.
- **S-10113 abandoned by the phone**: one end, status `abandoned`, `followed` true.
- **S-10114 a second terminal message does not add a second end.**
- **S-10115 a wrist-created session's end has no `followed` key** (explicit absence assertion, both completed and abandoned).
- **S-10116 pruning**: a followed session with its end acknowledged is pruned; a followed session ended BEFORE this change (no end observation) is pruned as before (existing prune tests stay green).
- **S-10117 validators (Swift + Dart)**: valid fixture `observations_up_session_end_followed.json` conforms; invalid fixture `observations_up_followed_on_set.json` (a `set` event carrying `followed: true`) is rejected as `semantic_violation` (same code the sibling `observations_up_status_on_timed.json` shows), in both stacks' fixture walkers (`SyncProtocolFixturesTests.swift`, `test/sync_protocol_fixtures_test.dart` — they walk the directories; the builder confirms the invalid fixture's expected code from its sibling).

## Phase 1: phone (`crew-builder-app`)

1. [ ] `_End.followed` parse; `_applyFollowedEnd`; the `apply` branch; `_Pass.summaryWritten`; `WatchSessionImport.sensorSummaryAttached` (D-4, D-5) — `lib/core/services/watch_session_importer.dart` (exact code in the brief).
2. [ ] `_captureFieldKinds`: `'followed': ['session_end']` — `lib/core/sync_protocol/message_validator.dart` l.134-144.
3. [ ] Tests S-10101..S-10107 — new `test/watch_followed_end_import_test.dart`.
4. [ ] Doc sentence: `docs/watch_session_capture.md` l.~242 ("a session it joined from the phone, which the phone already holds") — find the paragraph, state that a followed session now sends its end with `followed: true` carrying only the heart rate.

**Done**: `flutter test test/watch_followed_end_import_test.dart test/watch_session_import_test.dart test/watch_session_merge_test.dart test/watch_session_finish_test.dart test/watch_capture_repository_parity_test.dart test/sync_protocol_fixtures_test.dart test/docs_indexing_contract_test.dart`; `flutter analyze` ≤ 180.

## Phase 2: wrist + contract (`crew-builder-watch`, after plan 70 is verified)

1. [ ] D-1, D-2 emission — `WatchSessionEngine.swift` `captureSessionEnd`, `sessionEndEvent` (add the `followed` key); update the doc comments at l.1565-1575 and l.1703-1704 (D-3).
2. [ ] Schema: `followed` property — `watch/sync_protocol/schemas/envelope.schema.json` (beside `modality`, l.~288); Swift `captureFieldKinds` (`SyncProtocolValidator.swift` l.78-88).
3. [ ] Fixtures `watch/sync_protocol/fixtures/valid/observations_up_session_end_followed.json` and `.../invalid/observations_up_followed_on_set.json` (S-10117).
4. [ ] `watch/sync_protocol/PROTOCOL.md` l.~370-380 amendment (new dated entry in the amendments list, following the 2026-10-09 `roundDurationSecs` precedent): the `session_end` paragraph says a followed session gets one too, with `followed: true`.
5. [ ] Tests S-10111..S-10116 (replace the D-120 negative test).
6. [ ] D-7 report line (orchestrator replay).
7. [ ] Report FIRST as a skeleton, then fill it.

**Done**: `swift test --package-path watch/watchos --filter WatchSessionEngineTests` (whole target; includes the append-only guard and the fixtures walker), `flutter test test/sync_protocol_fixtures_test.dart`.

## Owner device checks

- (owner) ODC-1 Start a workout on the phone with the watch on the wrist, finish it, open the session summary: the heart-rate row shows (it may appear a moment after opening: plan 72). A workout started on the watch still shows it.

## Progress
- [x] Phase 1
- [x] Phase 2

## Assumption Log
- Phase 2's builder could not edit `watch/sync_protocol/fixtures/manifest.json` (not in its scope: lead's omission); the lead added both entries. Two older tests encoded the retired D-120 rule (`WatchSensorRecordingTests.testS237ASessionTheWristJoinedOwesNoEnd` in two classes, and the wrist's reconciliation replay in `WatchLiveMirroringTests`): the lead updated them (the joined session now owes an end and its log is held until the end is acknowledged; the replay compares entries without the wrist's own `session_end`).
- D-7 answer: `WatchSyncOrchestrator.sync` replays a session end for any held terminal session (no source check): the followed end is covered unchanged.
- Mutants: C1..C4 and I1..I7 killed; I2 needed a new test (S-10104b: an applied end reaching the branch again).

## Feedback
