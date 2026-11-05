# Plan 23e2: the phone sends the exercise list in batches, and nothing when the watch already has it

Series: `docs/plans/2026-10-11-23e-watch-batched-exercise-list-series.md` (D-3801..D-3805 apply). Builds on plan 23e1 (committed: the wire message
`exercises_down`, the wrist that assembles batches and reports `exercisesVersion` in the Sync request frame). Base: `.work/2026-10-11-23e2/base.txt`.
Governor-seeded. Track: phone (`lib/core`, `lib/state`) plus the shared request-frame contract.

## Goal and acceptance (what the owner sees)

1. Tap Sync on the watch: the Add Exercise list is the same as today (every exercise, custom ones too), but it now arrives as 3 small messages of at most 100 exercises
   instead of one 28 KB message (252 seeded exercises; a user with 1,000 exercises sends 10).
2. Tap Sync again with nothing changed on the phone: the phone sends the preferences and the routines, and NO exercise list at all (the watch said which list it holds).
3. Add, rename or delete a custom exercise (or change one's period length or capabilities) on the phone, tap Sync: the new list is sent in full; before that nothing is sent.
4. If the radio drops a batch half-way, the watch keeps showing its old list; the next Sync sends the whole list again.
5. The routines message no longer carries the whole catalog: it carries the routines and the exercises they use. Delete your last routine on the phone and Sync: the watch drops it
   (today a phone with no routines sends no routines message and the watch keeps the old ones).
6. The Wear/Dart wrist client (not shipped as an app) offers only the routines' exercises from now on (D-3805; documented divergence).

## Decision ledger

- D-3830 `WatchReferenceSync.buildRoutinesDown` (`lib/core/utils/watch_reference_sync.dart:106`): `fallbackExercises` = the exercises the routines reference only (the `referenced` map filled by `_segmentsJson`);
  DELETE the loop at ~line 140 that adds every catalog exercise (the 23c rule D-3603); the method returns a message ALWAYS (`routines: []` and `fallbackExercises: []` for a phone with none): return type
  becomes `Future<Map<String, Object?>>`; the one caller `watch_sync_request_handler.dart:~90` drops its null check. Schema allows this since 23e1 (D-3812).
- D-3831 New `WatchReferenceSync.buildExercisesDown({required WorkoutRepository repository, required DateTime generatedAt, int batchSize = 100}) -> Future<List<Map<String, Object?>>>`:
  every exercise with at least one capability (`_ExerciseResolver.resolve`), in the order `_fallbackJson` uses (`compareFoodNames`, ties by id), shape = `catalogExercise` (exerciseId, name, capabilities,
  optional roundDurationSecs >= 1: reuse `_fallbackJson`'s item builder, do not copy it), chunked by `batchSize`; each batch a `phoneEnvelope(type: 'exercises_down', messageId: 'msg-exercises-<version>-<index>', sentAt: generatedAt, payload: {generatedAt, catalogVersion, batchIndex, batchCount, totalCount, exercises})`.
  Empty list (no capable exercise) returns `[]`. `batchSize` must be 1..100 (assert).
- D-3832 Version: public `static String exercisesVersionOf(List<Map<String, Object?>> exercises)` = `'v1-<count>-<h1><h2>'`, `<h1><h2>` two lowercase 8-digit hex words (zero padded). Canonical text = the exercises (exact wire objects, in wire order) each as
  `exerciseId|name|cap1,cap2|roundDurationSecs-or-empty`, joined by `\n`. Hash over the string's UTF-16 code units: `h1`: seed 5381, `h = (h * 33 + u) & 0xFFFFFFFF`; `h2`: seed 52711, `h = (h * 65599 + u) & 0xFFFFFFFF`.
  Arithmetic must stay below 2^53 (the app builds for web); no `crypto` dependency (none in pubspec). Vector (re-derived with a throwaway script):
  `[{id:'a',name:'Apple',caps:['sets','reps']},{id:'b',name:'Bike',caps:['time','distance'],roundDurationSecs:600}]` -> canonical `a|Apple|sets,reps|\nb|Bike|time,distance|600` -> `v1-2-004dbda823a1b308`;
  the same with name `Bike!` -> `v1-2-6a71268979e6d5bd`. The version depends on CONTENT only, so a rename, an added/removed exercise, a capability or period-length change changes it, and insertion order does not.
- D-3833 Request frame (Dart twin of Swift `routinesFrame(since:exercisesVersion:)`): `WatchTransportRequest.routinesFrame({DateTime? since, String? exercisesVersion})` (`lib/core/platform/watch_transport.dart:73`) adds `'exercisesVersion'` only when
  non-null and non-empty; new `static String? exercisesVersionOf(Map<String, Object?> frame)` returns the key when it is a non-empty String, else null. The Wear client's `WatchSyncTransport.requestRoutines({since})` interface
  stays as it is (D-3805): it never reports a version, so it is sent the full list every time. The shared contract `watch/contract/watch_start_paths_contract.json` `transportRequests` gains
  `"routinesExercises": {"request": "routines", "exercisesVersion": "v1-2-004dbda823a1b308"}`; the Dart test S-102 (`test/watch_transport_test.dart:837`) and the Swift S-3820 (`WatchConnectivityBridgeTests.swift:~301`, uses the contract) assert it. The 23e1 note D-3820 ends here.
- D-3834 `WatchSyncRequestHandler.handle(String request, {String? exercisesVersion})` (`lib/state/watch/watch_sync_request_handler.dart:56`); `_sendRoutines({String? exercisesVersion})` sends, in this order: preferences (unchanged), `routines_down`, then the batches
  unless `exercisesVersion` equals the version of the batches just built; batches are sent one at a time in index order and the loop STOPS at the first `WatchDelivery.undelivered` (the wrist keeps its old list; the next Sync resends all).
  The wiring passes it: `watch_sync_wiring.dart:236` `await requests.handle(request, exercisesVersion: WatchTransportRequest.exercisesVersionOf(frame));`. Existing callers `handler.handle(WatchTransportRequest.routines)` (tests) keep compiling.
- D-3835 Docs: `docs/state_management/watch_reference_data.md` ("Not yet changed (23e2)" becomes the present tense), `watch/sync_protocol/PROTOCOL.md` (a 2026-10-11 row: the phone MUST send the list as `exercises_down` batches, MAY omit it when the request's `exercisesVersion` equals the list's version, MUST stop at the first batch the radio did not carry;
  the request frame key), `docs/watch-app-setup-and-qa.md` owner step (Sync, Add Exercise; Sync again; add a custom exercise; Sync), the doc line in `docs/state_management/watch_surface.md` or wherever "whole exercise list in routines_down" is stated (grep `fallbackExercises`/`routines_down` in docs/ excluding docs/plans and docs/history; remove before adding).

## Scenarios (tests first; each must fail without the change)

Reference sync (`test/watch_reference_sync_test.dart`; the 23c group S-3604..S-3607 at ~line 325-450 is REPLACED by these, and the other tests that read `fallbackExercises` of a catalog message at ~255, 571, 620, 949 must be re-read: they exercise routines, keep them green or fix their expectation to "routine exercises only"):
- S-3840 no templates, three repository exercises (one custom, one without capabilities): `buildRoutinesDown` returns a message with `routines: []` and `fallbackExercises: []`, and it passes the validator and is accepted by the Dart wrist (`WatchRoutinesDown`).
- S-3841 one routine over exercise A; exercises B and C exist: `fallbackExercises` is exactly [A].
- S-3842 a phone with no exercises at all still answers a message (both lists empty).
- S-3843 the exercise list: 250 repository exercises (generated names, shuffled insertion order) -> 3 batches of 100, 100, 50; `batchIndex` 0..2, `batchCount` 3, `totalCount` 250, one shared `catalogVersion`, name order across batches, every batch passes the validator, every encoded batch under 16,000 bytes (print the sizes).
- S-3844 the version vector of D-3832 (both values), plus: same content in another insertion order -> same version; a rename -> different; a changed capability -> different; a changed `roundDurationSecs` -> different; one exercise removed -> different.
- S-3845 no capable exercise -> `[]`.
- S-3846 `batchSize` 0 and 101 are refused (assert/ArgumentError, state which).
Handler (`test/watch_sync_request_handler_test.dart` new, or the existing handler tests: grep the readers `test/rest_ping_contract_test.dart:300`, `test/watch_accent_contract_test.dart:135` for the fake transport/repository pattern):
- S-3850 a request carrying the current version: the transport receives preferences then routines_down and NO `exercises_down`.
- S-3851 a request with no version: preferences, routines_down, then the batches in index order (3 for 250 exercises).
- S-3852 a stale version: the batches are sent.
- S-3853 the fake transport answers `undelivered` for batch index 1: batch 2 is never attempted, `handle` still returns true.
- S-3854 end to end with the in-memory repository: Sync (no version) -> read the version from the batches; Sync with it -> no batches; add a custom exercise; Sync with the old version -> batches with a different version.
- S-3855 the wiring hands the frame's version on: a `routines` frame with `exercisesVersion` through the graph's `onIncoming` reaches the handler (extend the existing wiring test that sends a request frame; grep `routinesFrame` / `onIncoming` in test/).
Frame (`test/watch_transport_test.dart`):
- S-3856 `routinesFrame(exercisesVersion: v)` equals the contract entry `routinesExercises`; with `since` too both keys; null or empty omits it; `exercisesVersionOf` returns null for missing, empty, and non-string values; S-102 "no type key" still holds.
Existing guards that must keep passing: the 23d accent/preferences-first order tests (`test/watch_accent_contract_test.dart`), `test/rest_ping_contract_test.dart:300`.

## Phases (serial where noted)

| # | Agent | Scope | Items |
|---|---|---|---|
| P0 | crew-builder-watch | `watch/contract/**`, `watch/watchos/Tests/**`, `watch/sync_protocol/PROTOCOL.md` | contract entry `routinesExercises` + Swift S-3820 reads it + PROTOCOL.md row (D-3835). Parallel with P1 (disjoint). |
| P1 | crew-builder-app | `lib/core/utils/watch_reference_sync.dart`, `lib/state/watch/watch_sync_request_handler.dart`, `test/watch_reference_sync_test.dart` | D-3830..D-3832, S-3840..S-3846; plus the one-line null-check removal in the handler (~line 90) that the non-null return type forces |
| P2 | crew-builder-app | `lib/core/platform/watch_transport.dart`, `lib/state/watch/**`, `test/watch_transport_test.dart`, `test/watch_sync_request_handler_test.dart`, `test/*wiring*` | D-3833, D-3834, S-3850..S-3856, runs after P0 and P1 |
| P3 | crew-docs-keeper | `docs/**` | D-3835 docs, QA step, evidence |

## Verification (governor, observed)
`flutter analyze` (196), full `flutter test` (900 s), `swift test --package-path watch/watchos`, xcodebuild watch scheme, invariant grep. Mutations: routines_down carries the whole catalog again; the version ignores names; batch off by one (101 per batch); skip-if-equal inverted;
no stop at the first undelivered batch; wiring drops the version; frame always omits the key; handler sends batches before routines_down. (owner) Real devices: Sync, open Add Exercise (full list); Sync again (list unchanged, nothing resent: visible only in logs); add a custom exercise on the phone, Sync, it appears in Add Exercise.

## Progress

| Phase | Item | Result |
|---|---|---|
| P0 | 1. Contract entry `routinesExercises` in `watch/contract/watch_start_paths_contract.json` | done (report-P0) |
| P0 | 2. Swift S-3820 reads the contract entry | done (report-P0) |
| P0 | 3. `watch/sync_protocol/PROTOCOL.md` rows and the `exercisesVersion` request note | done (report-P0) |
| P1 | 1. D-3830 `buildRoutinesDown` returns the routines' exercises only, always a message | done (report-P1) |
| P1 | 2. Handler `_sendRoutines` drops the null check (two lines) | done (report-P1) |
| P1 | 3. D-3831 `buildExercisesDown` with batching and the shared order helper | done (report-P1) |
| P1 | 4. D-3832 `exercisesVersionOf` content version | done (report-P1) |
| P1 | 5. S-3840..S-3846 in `test/watch_reference_sync_test.dart` | done (report-P1) |
| P2 | 1. D-3833 `routinesFrame({since, exercisesVersion})` + `exercisesVersionOf(frame)` | done (report-P2) |
| P2 | 2. S-3856 frame tests in `test/watch_transport_test.dart` | done (report-P2) |
| P2 | 3. D-3834 handler sequence: preferences, `routines_down`, batches unless the version matches, stop at the first undelivered | done (report-P2) |
| P2 | 4. `test/watch_sync_request_handler_test.dart` S-3850..S-3854 | done (report-P2) |
| P2 | 5. Wiring hands the frame's version on; S-3855 in `test/watch_session_projection_test.dart` | done (report-P2) |
| P3 | D-3835 docs, owner QA step, evidence file | done (report-docs) |

## Assumption Log

- The D-3832 vectors were re-derived independently by the governor with a script and match the plan's
  `v1-2-004dbda823a1b308` / `v1-2-6a71268979e6d5bd`; P1's "implementation and test could agree on a wrong
  value" open question is closed.
- The Dart wrist client (`lib/watch/`) now receives only the routines' exercises in `routines_down`
  (D-3805 divergence): it never reports an `exercisesVersion`, so it is sent the full list every Sync.
- The handler builds the exercise batches on every Sync even when the request's version matches, because
  the version is computed from the content of the list just built; skipping the build would need a stored
  content hash, which costs one repository pass per Sync — accepted as is.
- P0: `PROTOCOL.md` has no section describing the routines request frame, so the `exercisesVersion`
  sentence sits next to the `preferences_down` sync-request note; move it if a transport section appears.
- P1: `test/watch_reference_sync_test.dart`'s header still maps `S-007` as "the fallback list covers every
  exercise"; the group it names is now "covers what the routines reference". Test-file comment, outside
  the docs scope — left as is.
- P2: the S-3856 tests sit inside the existing `S-102` group, so their names carry the `S-3856` prefix
  under an `S-102` group heading; and S-3850's "current version" is derived by the same
  `buildExercisesDown` the handler calls, so the version itself is pinned by S-3844 and S-3856, not S-3850.

## Feedback

The reviewer's findings live in `.review.md` beside this plan:
`docs/plans/2026-10-11-23e2-phone-sends-exercise-batches-plan/2026-10-11-23e2-phone-sends-exercise-batches-plan.review.md`.
