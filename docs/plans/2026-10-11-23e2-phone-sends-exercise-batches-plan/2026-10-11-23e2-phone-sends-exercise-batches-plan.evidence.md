# Evidence — plan 23e2 (the phone sends the exercise list in batches)

Base commit `35b317292bf40eb06b2182de6895fa911945866a` (`.work/2026-10-11-23e2/base.txt`).
Builder reports: `.work/crew/2026-10-11-23e2/report-{P0,P1,P2,docs}.md`.

## Baselines (governor-measured; not re-measured by the builders)

| Check | Before | After (last observed) |
|---|---|---|
| `flutter test` (full suite) | `+4278 ~1` | `01:57 +4294 ~1: All tests passed!` (report-P2; the `~1` is the pre-existing skip) |
| `swift test --package-path watch/watchos` | 550 / 0 failures | `Executed 550 tests, with 0 failures (0 unexpected)` (report-P0) |
| `flutter analyze` | 196 issues | `196 issues found` (report-P1 and report-P2; pre-existing infos only) |

## Phase P0 — the shared request-frame contract (report-P0)

- `watch/contract/watch_start_paths_contract.json` gains
  `"routinesExercises": {"request": "routines", "exercisesVersion": "v1-2-004dbda823a1b308"}`
  between `routinesSince` and `snapshot`; the three existing entries untouched. The file's own
  `description` ("three request frames" / "two ways it asks for routines") was updated to four / three,
  which the fourth entry made false; no test reads it.
- Swift S-3820 (`WatchConnectivityBridgeTests.swift:301`,
  `testS3820TheRoutinesRequestCarriesTheExerciseListVersionOnlyWhenThereIsOne`) now reads the version
  from the contract's `routinesExercises` entry and compares `routinesFrame(since: nil,
  exercisesVersion:)` against it; the nil-omits and since+version cases kept; the harness half (no list
  → no key; after `fixtures/valid/exercises_down_single_batch.json` → `v1-3-9f8e7d6c`) unchanged.
- `watch/sync_protocol/PROTOCOL.md`: the `routines_down` row and the coverage note now say the fallback
  list covers the routines' own exercises with the rest arriving as `exercises_down` batches; a new
  bullet (beside the `preferences_down` sync-request note) describes the request's optional
  `exercisesVersion` key; a new version-history row `| 1 (amended) | 2026-10-11 |` states the
  MUST-send-as-batches / MUST-stop-at-the-first-uncarried-batch / MAY-omit-when-the-version-matches
  rules and the tests that pin them. History rows that still say the catalog travels in `routines_down`
  are left as history.
- Checks seen: filtered Swift run `Executed 1 test, with 0 failures`, exit 0; full package
  `Executed 550 tests, with 0 failures`, exit 0; `git-diff --stat` over the three files 25+/9−.

## Phase P1 — the phone builds the batches and the small routines message (report-P1)

- D-3830: the catalog loop and the `if (referenced.isEmpty) return null;` are gone;
  `buildRoutinesDown` is `Future<Map<String, Object?>>` and always answers a message
  (`routines: []` + `fallbackExercises: []` for a phone with none).
- Handler: exactly the two lines — `_sendRoutines` sends the built message and returns true.
- D-3831: `buildExercisesDown({repository, generatedAt, batchSize = 100})`, `ArgumentError.value`
  outside 1..100, capability-less exercises skipped, `const []` when nothing is capable, envelopes
  `msg-exercises-<version>-<index>`; `_catalogExerciseJson` and `_catalogOrder` extracted so the batch
  order and the fallback order cannot drift.
- D-3832: `exercisesVersionOf` over the wire objects in wire order, two hashes over UTF-16 code units
  (5381×33, 52711×65599, masked to 32 bits), `v1-<count>-<h1><h2>`.
- Tests: the 23c group S-3604..S-3607 replaced by `S-3840..S-3843, S-3845, S-3846 the phone sends the
  list in batches` and `S-3844 the exercise list version`; `S-003 a phone with no routines still
  answers, with all lists empty` now expects an empty `fallbackExercises` (D-3830). 13 now-unnecessary
  `!` assertions removed.
- Checks seen: `gateway.sh test test/watch_reference_sync_test.dart` → `00:00 +27: All tests passed!`;
  batch wire sizes printed `8009 / 8009 / 4159 bytes` (under the 16,000 ceiling); `gateway.sh lint` →
  `196 issues found` (baseline exactly); full suite at that moment `+4283 ~1 -1` with the single
  failure in `test/watch_transport_test.dart`'s `S-003` (P2's file, left alone per scope).

## Phase P2 — request frame, handler sequence, wiring (report-P2)

- D-3833: `routinesFrame({DateTime? since, String? exercisesVersion})` adds the key only for a
  non-null, non-empty string; `exercisesVersionOf(frame)` reads it back (null for missing, empty or
  non-string). The Wear interface `requestRoutines({since})` untouched (D-3805).
- S-3856 in the existing `S-102` group of `test/watch_transport_test.dart`: the versioned frame equals
  the contract entry (version read from the JSON, never retyped), both keys with `since`, null/`''`
  omit, read-back cases; the "no type key" test covers the versioned frame too.
- D-3834: `handle(request, {exercisesVersion})` → preferences, `routines_down`, then the batches unless
  the request's version equals the built list's; one `send` per batch in index order, breaking at the
  first `WatchDelivery.undelivered`; still returns true.
- `test/watch_sync_request_handler_test.dart` (new): S-3850..S-3854 over a recording transport.
- Wiring: `await requests.handle(request, exercisesVersion: WatchTransportRequest.exercisesVersionOf(frame));`
  and S-3855 in `test/watch_session_projection_test.dart` (version named → no batch; no version → the
  batches travel).
- Existing tests re-pointed (plan-predicted): `S-003 a phone with no routines answers with its
  preferences, an empty routine list and the whole exercise list` now asserts the leading
  `['preferences_down','routines_down']`, only `exercises_down` after, and an empty `fallbackExercises`;
  `S-003 a seeded routine is built and sent when the wrist asks` takes the routines frame by type; the
  two `S-253` exact type lists became `take(2)`.
- Checks seen: handler file `00:00 +5: All tests passed!`; transport file `00:00 +33: All tests
  passed!`; projection + accent + rest-ping `00:00 +58: All tests passed!`; `gateway.sh lint` →
  `196 issues found`; full suite `01:57 +4294 ~1: All tests passed!`, exit 0.

## Governor read-backs

### Mutation table (`.work/2026-10-11-23e2/mutate.py`; the governor ran it — every mutation went red on the scenario named, and the touched files were restored byte-identical)

| Mutation | Scenario that went red |
|---|---|
| F1 routines_down carries the whole catalog again | S-3840, S-3841 |
| F2 version ignores names | S-3844 |
| F3 version ignores period length | S-3844 |
| F4 batch count drops the remainder | S-3843 |
| F5 skip-if-equal inverted | S-3850, S-3851, S-3852 |
| F6 no stop at the first undelivered batch | S-3853 |
| F7 wiring drops the version | S-3855 |
| F8 frame never carries the version | S-3856 |
| F9 exercisesVersionOf reads nothing | S-3856, S-3855 |
| F10 batches skip the first one | S-3851 |

### Independent vector re-derivation (D-3832)

The governor re-derived both version vectors with a throwaway script, independently of the Dart
implementation, and both match the plan and the test's literals:

- `[{id:'a',name:'Apple',caps:['sets','reps']},{id:'b',name:'Bike',caps:['time','distance'],roundDurationSecs:600}]`
  → `v1-2-004dbda823a1b308`
- the same with name `Bike!` → `v1-2-6a71268979e6d5bd`

This closes P1's open question (implementation and test agreeing on a possibly wrong constant).

## Prover verdicts

Not run: the governor proved the guards by mutation (table above).
