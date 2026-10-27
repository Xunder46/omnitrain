# Feature: 81 — a second wrist workout of the same exercise no longer takes over the first one's sets

> Status: BUILT AND PROVED 2026-10-26 (uncommitted). Mutations: dropping the token in `availableSlotId` / the routine create path, and dropping the `~` strip in `_routineFor`, each turn their guards red; the end-to-end repro (Mock and Hive) fails with the token off (efforts of the first session `[]`). Review: `*.review.md`. History damaged before this change is not repaired. Earlier status: SEEDED 2026-10-26 (lead); architect pass 2026-10-26 — every seeded entry kept verbatim; additions: D-9, S-15009/S-15010, Code pointers, Feature invariants, Existing-functionality impact, expanded phases, Progress, Open questions. Base commit: `.work/2026-10-26-81/base.txt`. Team: the crew. Owner report (chat, 2026-10-26): "I started a brisk walk on the watch, logged after 30 minutes and saw 2 sets instead of one. I started the same exercise again, logged after 12 seconds, and the phone showed 3 sets: the older two and the new one. Looks like the watch doesn't reset after the workout is finished and sends the data from before?" Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Root cause (reproduced by the lead on the current code, before any fix)

Not the watch's log: each logged entry has its own random id and a finished session's entries are sent once under their own session id. The defect is the slot id. A wrist-made session names its exercise slots `sx-<exerciseId>` (a picked exercise) or `sx-<templateEffortId>` (a routine run): the same text in every session. The phone's adoption of a wrist session uses the slot id AS the id of the effort row (`SegmentEffort.id`, a store-wide primary key: `watch_session_adoption_bridge.dart:1090`, `id: slot['sessionExerciseId'] as String`; Mock and Hive both `put` by id). So the second session's effort row REPLACES the first one's, and the rows hung under that id (sets, timed intervals, rests: all keyed by effort id) now belong to the second session. Evidence: `test/watch_second_session_same_exercise_repro_test.dart` (lead, failing on base): after workout 1 (two sets) and workout 2 (one set) the efforts of `s-w1` are `[]`, the efforts of `s-w2` are `[sx-ex-bench]`, and that one effort holds three sets (`obs-sx-ex-bench-0/1/2-reps`). The first "2 instead of 1" is the same bug with an earlier test workout of the same exercise. Both consequences are real: the new session shows the old sets, and the old session LOST its sets.
`PROTOCOL.md:205-208` only promises slot ids unique WITHIN a session; the phone's use of them as a global key is the bug. Not reached: sessions the phone starts (its slot ids are its own unique effort ids).

## What the owner sees

| Moment | Today | After |
|---|---|---|
| Second watch workout of an exercise you did before (picked from the list or run from a routine) | the phone shows the earlier workout's sets inside it (3 instead of 1) and the earlier workout loses them | each workout shows only its own sets; the earlier workout keeps its own |
| Repeating the same routine from the watch twice | same mix-up | no mix-up |
| Workouts started on the phone | fine | unchanged |
| History already damaged by this | | not repaired: the first workout's sets were overwritten on the phone and cannot be recovered (the watch has already forgotten acknowledged entries). New workouts are correct |

(owner) On a real watch: do Brisk Walk, log, End; do it again, log once; the phone shows 1 set in the second and the first still has its own.

## Decision Ledger

- D-1 Every slot id the WRIST mints gets a per-session suffix: `<base>~<token>`, where `<base>` is today's text (`sx-<exerciseId>`, `sx-<exerciseId>-2`, `sx-<effortId>`) and `<token>` is 8 characters taken from the session id when the session exists (picks into a live session: `engine.session!.sessionId`) and from the injected id factory (`newId()` first 8 characters, `WatchStartPaths.swift:297,329`) when slots are built before the session (`startFromRoutine`, `WatchStartPaths.swift:580`). Reason chosen: the phone, the protocol and the engine keep "effort id == slot id" (D-3 of plan 15a/15b), nothing on the phone needs a mapping table, and ids stay unique within a session (PROTOCOL.md:205). Rejected: a phone-side slot→effort map (touches the merge, mirror, auto-push, timers, projection: five subsystems); renaming at `createSession` (breaks ~570 tests that pass slots in).
- D-2 Swift: `WatchCatalogExercise.slotId` (`WatchRoutineRecords.swift:106`) stays the BASE id (plan 79 D-6 and `menuSlotId` fall back to it); a new `func slotId(token: String) -> String` returns `"\(slotId)~\(token)"`. `WatchRoutineEffort.slot` (`:211`) and `WatchRoutine.slots` (`:299`) take the token: `slots(token:)`. `availableSlotId(for:)` (`WatchStartPaths.swift:703`) builds its candidates from `slotId(token: <session token>)`, so the existing "-2" de-duplication within a session still works. `startFromRoutine` passes the token to both the create path and the fill-in-place path (`:573-577`). New names avoid the append-only verbs (crew rule r/ac): `slotId(token:)`, `slots(token:)`, `sessionToken`.
- D-3 Dart Wear twin, same change, same names: `lib/watch/start/watch_routine_catalog.dart:56,121,` `lib/watch/start/watch_session_start_paths.dart:193,214,238-248`.
- D-4 Phone decode: `_routineFor` (`watch_session_adoption_bridge.dart:871-882`) strips the suffix before looking the effort id up: effort id = text after `sx-` up to the LAST `~` when the slot id contains one. Without this, a routine run from the wrist would stop being recognised as a routine run (plan 36c). A slot id with no `~` (an older watch build, a phone-pushed id) decodes as today.
- D-5 No defence on the phone for an older watch that still sends plain `sx-` ids (the owner has one watch and it updates with the phone). Recorded in the Assumption Log; a guard that refuses to take an effort row from another session is a separate follow-up if wanted.
- D-6 `PROTOCOL.md` gets one non-breaking sentence under the slot-id rule (`:205-208`): "A sender SHOULD NOT reuse a slot id across sessions: a receiver MAY key stored rows by it." Not a version change. The envelope schema's description (`envelope.schema.json:103`) is unchanged. `PROTOCOL.md` is outside the docs keeper's ceiling: one-file docs-only run for `crew-builder-watch` (crew rule s).
- D-7 The lead's repro test becomes the plan's first guard: it is rewritten so the two sessions get their slot ids from the Dart twin (`WatchSessionStartPaths` + `WatchSessionEngine`, no hand-written ids), then their snapshots and entries go to the phone harness already in the file. It FAILS on the base (shown) and passes after P1.
- D-8 Not in scope: repairing damaged history; any change to how a phone-started session names slots; the rest-window `afterEntryId` ids (random per entry); the protocol version; `lib/state/watch/*` other than `_routineFor`.
- D-9 The token helper is one pure function per language: `sessionToken(from:)` in `WatchRoutineRecords.swift` and a top-level `sessionToken` in `lib/watch/start/watch_routine_catalog.dart`. It returns the FIRST 8 characters of the source id; an id shorter than 8 is used whole (`sessionToken(from: "s-w1") == "s-w1"`). Production session ids are UUIDs (`UUID().uuidString`: `WatchSessionEngine.swift:127`, `watch_session_engine.dart` `sessionIdFactory` default), so the token never contains `~` and D-4's last-`~` decode is safe. Token sources: the add paths and the fill-in-place branch take it from the live session's id (`engine.session!.sessionId`); the create branch of `startFromRoutine` takes it from the start paths' injected `newId()` because the engine mints the session id only inside `createSession` (`WatchSessionEngine.swift:307,334`; `watch_session_engine.dart:292-322`).

## Scenarios (exact fixtures; re-derive in the first run)

- S-15001 (Dart end to end, the repro): Dart twin start paths create session W1 by picking exercise `ex-bench` (catalog entry with sets/reps/load), log two sets, end it; create session W2 the same way, log one set. Send both sessions' snapshots, entries and the end lifecycle to the phone harness of `test/watch_second_session_same_exercise_repro_test.dart`. Expect: `segment-<W1>` has one effort, `segment-<W2>` has one effort, the two effort ids differ, W1's effort holds 2 sets (observations indices 0 and 1), W2's holds 1 (index 0). Fails today with `[]`.
- S-15002 (Swift) `WatchStartPaths`: two sessions started one after the other (`startFreeWorkout`, `addExerciseToEnd` of the same exercise, End, again): the two slot ids are different and each equals `sx-<exerciseId>~<first 8 chars of that session's id>`. Adding the same exercise twice in ONE session gives `sx-<exerciseId>~<token>` then `sx-<exerciseId>-2~<token>` (the `-n` de-duplication part comes BEFORE the token; the token is always last, so D-4's "text up to the last `~`" decodes both).
- S-15003 (Swift) `startFromRoutine` twice with the same routine and an id factory returning two different values: the two sessions have no slot id in common; each slot id starts with `sx-<effortId>~`; the fill-in-place path (routine picked into an empty live session) uses that session's id token.
- S-15004 `WatchCatalogExercise.slotId` is unchanged (`sx-<exerciseId>`) and `slotId(token: "ab12cd34")` == `sx-<exerciseId>~ab12cd34`; `menuSlotId`'s fallback still works for a slot with no own id.
- S-15005 (Dart twin) the same as S-15002/3 for `WatchSessionStartPaths`.
- S-15006 (phone) `_routineFor`: a ladder whose slots are `sx-<effortId>~ab12cd34` for the efforts of one template is recognised as that template's run (planned rows written, as `test/watch_routine_adoption_test.dart` asserts for the plain ids); `sx-<effortId>` (no suffix) still recognised; `sx-` + empty, `sx-~tok`, `~tok` alone and a slot without the prefix are not.
- S-15007 (phone) an adopted wrist session with suffixed slot ids behaves as before for every later step: set merge into the held session (`_mergeHeld`), timer adoption, deletion: the existing suites with ids rewritten are NOT duplicated; only one merge case with suffixed ids is added.
- S-15008 source/contract: `PROTOCOL.md` contains the new SHOULD sentence; both validators and all fixtures unchanged (fixtures carry plain ids and stay valid).
- S-15009 (phone, decode robustness) `_routineFor` on `sx-eff-bench-2~ab12cd34` decodes to `eff-bench` (text after `sx-` up to the LAST `~`; the `-2` rides with the dropped tail), so a tokened id that also carries the engine's `-n` dedup suffix still resolves. Defensive: phone-minted template effort ids are unique (`teff-<now>-<n>`, `state/routine/routine_state.dart:581`), so routine slots never collide today; the case pins the last-`~` rule. Fails without D-4 under a naive first-`~` split (it would leave `-2` in the effort id).
- S-15010 (both languages, unit) `sessionToken(from: "s-w1") == "s-w1"` and `sessionToken(from: "3f2a1b4c-5678-90ab-cdef") == "3f2a1b4c"`: ids shorter than 8 characters pass through unchanged, longer ids are cut to 8. Two short ids (`s-w1`, `s-w2`) still give different tokens, which is what the repro's factories rely on.

Readers of the changed contracts (the architect re-greps): `WatchStartPathsTests` and every Swift/Dart test that asserts a slot id produced by the start paths (the scout counts 527 Swift and 571 Dart `sx-` matches, most of them hand-written fixtures that do NOT go through the start paths and are untouched; the ones that do are listed by the architect), `WatchMenu.swift:246` `menuSlotId`, `WatchRestLabels.swift:87-89,136` (the plan 79 nextSlotId reads the slot's own id), `docs/my_routines.md:137`, `docs/watch_session_sync/what_does_not_sync.md:301-302`, `docs/state_management/watch_surface.md:82-83`, `test/watch_routine_adoption_test.dart`, `watch/sync_protocol/PROTOCOL.md`.

## Code pointers (verified on the base by the architect, 2026-10-26)

Line numbers supersede the seed's where they differ (seed text kept verbatim above; corrections listed in Open questions).

- `watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift:106` — `public var slotId: String { "sx-\(exerciseId)" }`; `:126` — `"sessionExerciseId": sessionExerciseId ?? slotId,`; `:120` — `public func toSlot(`; `:209-211` — `public var slot: [String: Any] { catalogExercise.toSlot(sessionExerciseId: "sx-\(effortId)", ...)`; `:299` — `public var slots: [[String: Any]] { efforts.map(\.slot) }`.
- `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` — `:329` `idFactory: @escaping () -> String = { UUID().uuidString }`, `:335` `self.newId = idFactory`; `startFromRoutine` `:561`, fill-in-place branch `:570-577` (`for slot in routine.slots` at `:575`), create path `:580` (`engine.createSession(modality: nil, exercises: routine.slots)`); `startFreeWorkout` `:588`; `addExerciseToSession` `:612` (calls `availableSlotId` at `:615`); `addExerciseToEnd` `:679`; `availableSlotId(for:)` `:703-713` (base = `exercise.slotId`, dedup candidates `\(base)-\(suffix)` from 2).
- `lib/watch/start/watch_routine_catalog.dart` — `:56` `String get slotId => 'sx-$exerciseId';`; `:63` `toSlot({`; `:67` `'sessionExerciseId': sessionExerciseId ?? slotId,`; `:120-121` `get slot => catalogExercise.toSlot(sessionExerciseId: 'sx-$effortId', ...)`; `:204-205` `get slots => [for (final effort in efforts) effort.slot]`.
- `lib/watch/start/watch_session_start_paths.dart` — `:47-52` ctor (`_newId = idFactory ?? _uuid`); `startFromRoutine` `:176` (fill branch `:180-191`, create `:193`); `startFreeWorkout` `:202`; `addExerciseToSession` `:210-214` (`toSlot(sessionExerciseId: _availableSlotId(exercise))`); `_availableSlotId` `:235-250`.
- `lib/state/watch/watch_session_adoption_bridge.dart` — `:96` `const String _slotIdPrefix = 'sx-';`; `_adopt` `:793` (routine read `:801`, `targetsBySlot[slotId]` `:842`, `_everSeen` `:851`); `_routineFor` `:870-905` (decode loop `:876-882`: `startsWith(_slotIdPrefix)` then `substring(_slotIdPrefix.length)`); `targetsBySlot` built `:897-901` keyed by the ladder's OWN full slot id; `_createPlannedRows` `:919-946` (`effortId: slotId` — the full ladder id); `_reconcile` `:1020` (the add-only merge into the held session); `_effort` `:1085-1100` (`id: slot['sessionExerciseId'] as String` at `:1090`).
- Engine mint: `WatchSessionEngine.swift:127` (`sessionIdFactory` default `UUID().uuidString`), `:307/:317/:334` (`createSession` → `sessionId: newSessionId()`); `lib/watch/session/watch_session_engine.dart:292-322` (`createSession` mints `sessionId: _newSessionId()`).
- Validators/schema: `watch/sync_protocol/schemas/envelope.schema.json` — `sessionExerciseId` is `{"type": "string", "minLength": 1}` at `:112-114`, `:226-228`, `:346-348`, `:396-398` (no `pattern`, no `maxLength`); description `:103` unchanged per D-6. Both validators are generic JSON-Schema engines — `lib/watch/sync_protocol/message_validator.dart:939-964` and `watch/watchos/Sources/.../SyncProtocolValidator.swift:808-831` apply `minLength`/`maxLength`/`pattern` only when present — plus uniqueness-within-session checks (`message_validator.dart:413-422`, `SyncProtocolValidator.swift:297-307`). Neither restricts the charset: a `~token` suffix passes everywhere, and fixtures with plain ids stay valid (S-15008).

## Feature invariants

- I-81-1 Every slot id the wrist mints carries `~<token>`; the token is `sessionToken` of the session's id (live session) or of `newId()` (slots built before the session exists).
- I-81-2 `WatchCatalogExercise.slotId` stays the plain base `sx-<exerciseId>`; `menuSlotId` (`WatchMenu.swift:246`) and plan 79's `nextSlotId` (`WatchRestLabels.swift:136`) keep reading it.
- I-81-3 The `-n` dedup suffix sits before the token: the token is the last `~`-separated segment of the id (S-15002's exact strings).
- I-81-4 `_routineFor` decodes `sx-<effortId>~<tail>` to `<effortId>` and leaves an id without `~` unchanged (older watch builds, phone-pushed ids).
- I-81-5 Phone-started sessions never mint `sx-` ids (their effort ids are the phone's own, `watch_session_adoption_bridge.dart:515`); the iOS app target has zero matches for `sx-`/`slotId`/`sessionExerciseId` (grep recorded 2026-10-26).
- I-81-6 `WorkoutRepository` stays the only persistence dependency; the repro and the adoption tests run Mock AND Hive and give identical output for suffixed ids.

## Existing-functionality impact

| Touched surface | What already reads it (search run 2026-10-26) | Effect | Guarded by |
|---|---|---|---|
| `WatchRoutine.slots` / `WatchRoutineEffort.slot` / `WatchCatalogExercise.slotId` (Swift + Dart) | Production callers: `WatchStartPaths.swift:575,580,617,679`; `watch_session_start_paths.dart:188,193,214`. Test callers: `WatchSessionStartPathsTests.swift:191-192,669,1089-1100,1155-1158`; `WatchHealthActivityTests.swift:285,304,333,359`; `WatchConnectivityBridgeTests.swift:899`; `watch_session_start_test.dart:481,787,791,848,858-867,933`; `watch_reference_sync_test.dart:299` | Signatures gain the token; every listed caller updated in P1/P2; `toSlot`'s own fallback keeps the base id (its only no-id callers are tests) | S-15002..S-15005, S-15001 |
| Within-session id readers: `menuSlotId` (`WatchMenu.swift:246`), `WatchRestLabels.swift:87-89,136`, `WatchLoggingState.swift:568-626`, engine dedup (`WatchSessionEngine.swift:422-424`) | Compare a slot's own id with ids from the same session | Unaffected: tokened ids stay consistent within a session; dedup works on full ids | S-15002, S-15004, D-2 |
| Phone adoption keys: `_adopt` `targetsBySlot[slotId]` (`:842`), `targetsBySlot` build (`:897-901`), `_createPlannedRows` (`effortId: slotId`, `:933`) | Key rows by the ladder's OWN full slot id | Unaffected by suffixing: keys and lookups both use the full tokened id | S-15006, S-15007 |
| `_routineFor` (`watch_session_adoption_bridge.dart:870-905`) | Template-effort lookup for routine-run recognition (plan 36c) | CHANGES: strips `~<tail>` before the lookup; no-`~` ids decode as today | S-15006, S-15009, D-4 |
| Validators + envelope schema | `message_validator.dart:939-964`, `SyncProtocolValidator.swift:808-831`, `envelope.schema.json:112-114` | None: `sessionExerciseId` has no `pattern`/`maxLength`; `~` passes; fixtures unchanged | S-15008 |
| `ios/` app target | grep `sx-\|slotId\|sessionExerciseId` over `ios/` → zero matches | Unaffected | I-81-5 |
| Docs: `docs/my_routines.md:137`, `docs/watch_session_sync/what_does_not_sync.md:301-302`, `docs/state_management/watch_surface.md:82-83` | Sentences describing wrist slot ids | One-line updates in P5 | P5 |
| `watch/contract/watch_start_paths_contract.json` | Carries plain expected ids (`:89`, `:213`, `:301-304`, `:326`, `:328-333`) | NOT edited (not in any phase scope): tests derive token-appended expectations from the contract's plain ids | P1/P2 items |

## Phases

- P1 `crew-builder-watch` — Swift wrist (D-1, D-2, D-9; S-15002..S-15004, S-15010). Scope: `watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift`, `WatchStartPaths.swift`, tests `WatchStartPathsTests.swift` (existing: fix every red one, tests only) and new `WatchSlotTokenTests.swift`. Serial. The seed's scope grows by two test files the architect found red or non-compiling: `WatchHealthActivityTests.swift`, `WatchConnectivityBridgeTests.swift` (see Open questions 4).
  - Items:
    1. [ ] Add `sessionToken(from:)` (first 8 characters, shorter ids whole) — `watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift` · new free function
    2. [ ] Add `slotId(token:)` returning `"\(slotId)~\(token)"` (`slotId` stays the base); rename `slot` → `slot(token:)` passing `"sx-\(effortId)~\(token)"`; rename `slots` → `slots(token:)` mapping efforts — `WatchRoutineRecords.swift` · `WatchCatalogExercise`, `WatchRoutineEffort`, `WatchRoutine`
    3. [ ] Thread the token through both branches: fill-in-place `sessionToken(from: held.sessionId)`, create `sessionToken(from: newId())` — `WatchStartPaths.swift` · `startFromRoutine`
    4. [ ] `availableSlotId(for:)`: dedup the plain base exactly as today, then return `<free base>~<token>` (token from the live session's id, `newId()` fallback) so `sx-<id>-2~<token>` holds — `WatchStartPaths.swift` · `availableSlotId`
    5. [ ] New `WatchSlotTokenTests.swift` with the S-15002, S-15003, S-15004, S-15010 fixtures (injectable id factory; prove-red: the tokened assertions cannot hold on base) — `watch/watchos/Tests/WatchSessionEngineTests/WatchSlotTokenTests.swift` · new file
    6. [ ] Fix the red assertions to tokened expectations derived from the contract's plain ids — `WatchSessionStartPathsTests.swift` · `routineSlots` helper `:191-192`, assertions `:669`, `:1089-1100`, `:1155-1158`
    7. [ ] Mechanical `effort.slot` → `effort.slot(token: "testtoken")` (assertions read non-id keys only) — `WatchHealthActivityTests.swift` · `:285,304,333,359`
    8. [ ] Compare the picked slot against the tokened id instead of `bench.slotId` — `WatchConnectivityBridgeTests.swift` · `:899`
  - Done criteria: gateway `swift-test` green (`swift test --package-path watch/watchos`), including the new `WatchSlotTokenTests.swift`; `prove-red <base> swift-test` shows the S-15002/S-15003 guards failing on base.
  - Predicted files: the six above, nothing else.
  - Write scope: `"watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift"`, `"watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift"`, `"watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift"`, `"watch/watchos/Tests/WatchSessionEngineTests/WatchSlotTokenTests.swift"`, `"watch/watchos/Tests/WatchSessionEngineTests/WatchHealthActivityTests.swift"`, `"watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift"`.
- P2 `crew-builder-app` — Dart twin + phone + repro (D-3, D-4, D-7, D-9; S-15001, S-15005..S-15007, S-15009, S-15010). Scope: `lib/watch/start/watch_routine_catalog.dart`, `lib/watch/start/watch_session_start_paths.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`, `test/watch_second_session_same_exercise_repro_test.dart`, `test/watch_routine_adoption_test.dart`, the twin's existing start-path tests (the architect lists them). Runs in parallel with P1 (disjoint scopes; one of them may run the full suite, neither does: touched files only; Mock AND Hive for the repro).
  - Items:
    1. [ ] Add top-level `sessionToken` (mirror of D-9) — `lib/watch/start/watch_routine_catalog.dart` · new function
    2. [ ] Mirror the three renames: `slotId(token:)`, `slot(token:)` (`'sx-$effortId~$token'`), `slots(token:)` — `watch_routine_catalog.dart` · `WatchCatalogExercise`, `WatchRoutineEffort`, `WatchRoutine`
    3. [ ] Thread the token through both branches and dedup-then-token in the add paths — `lib/watch/start/watch_session_start_paths.dart` · `startFromRoutine`, `_availableSlotId`
    4. [ ] Decode: after stripping `sx-`, cut at the LAST `~` when present; no-`~` ids unchanged — `lib/state/watch/watch_session_adoption_bridge.dart` · `_routineFor`
    5. [ ] Rewrite the repro per D-7: both sessions via `WatchSessionStartPaths` + `WatchSessionEngine` (`sessionIdFactory: () => 's-w1'` / `'s-w2'`), sets logged through `WatchLoggingState.log()`, snapshots/entries/lifecycle fed to the phone harness already in the file; Mock AND Hive — `test/watch_second_session_same_exercise_repro_test.dart` · the S-15001 test
    6. [ ] Fix the red assertions to tokened expectations and add the S-15005 twin-token test — `test/watch_session_start_test.dart` · `:481`, `:787`, `:791`, `:848`, `:858-867`, `:933`
    7. [ ] Fix the routine-slots assertion to the tokened id — `test/watch_reference_sync_test.dart` · `:299`
    8. [ ] Add the S-15006 `_routineFor` cases (suffixed recognised with planned rows, plain still recognised, `sx-` + empty, `sx-~tok`, `~tok` alone, no prefix), the S-15009 decode case and one S-15007 merge case with suffixed ids — `test/watch_routine_adoption_test.dart` · `_routineFor` group
  - Done criteria: `flutter test test/watch_second_session_same_exercise_repro_test.dart test/watch_session_start_test.dart test/watch_reference_sync_test.dart test/watch_routine_adoption_test.dart` green (touched files only), repro green on Mock AND Hive; `prove-red <base> test` shows the repro failing on base (the lead already showed it; re-prove with the rewritten file).
  - Predicted files: the five above, nothing else.
  - Write scope: `"lib/watch/start/watch_routine_catalog.dart"`, `"lib/watch/start/watch_session_start_paths.dart"`, `"lib/state/watch/watch_session_adoption_bridge.dart"`, `"test/watch_second_session_same_exercise_repro_test.dart"`, `"test/watch_session_start_test.dart"`, `"test/watch_reference_sync_test.dart"`, `"test/watch_routine_adoption_test.dart"`.
- P3 `crew-builder-watch` — `PROTOCOL.md` sentence only (D-6). Scope `watch/sync_protocol/PROTOCOL.md`. Runs after P1 (the sentence describes the behaviour P1 ships; one-file docs-only run, crew rule s).
  - Items:
    1. [ ] Add the D-6 sentence under the slot-id rule (`PROTOCOL.md:205-208`): "A sender SHOULD NOT reuse a slot id across sessions: a receiver MAY key stored rows by it." — `watch/sync_protocol/PROTOCOL.md` · slot-id rule section
  - Done criteria: the sentence is present; no test reads `PROTOCOL.md` (docs-only change; `flutter analyze` issue count unchanged vs baseline if run).
  - Predicted files: `watch/sync_protocol/PROTOCOL.md`, nothing else.
  - Write scope: `"watch/sync_protocol/PROTOCOL.md"`.
- P4 lead — `xcodebuild` watch app, `swift test`, full `flutter test` (900 s), mutation pass in an isolated copy (drop the token in `availableSlotId`, drop the suffix strip in `_routineFor`), invariant grep. Serial, after P1 + P2.
  - Items: the lead's own checklist (mutations must turn S-15002 and S-15006 red; the invariant grep checks I-81-1..I-81-5).
  - Done criteria: gateway `build`, `swift-test`, `test` green on the merged tree; both mutations red; grep clean.
  - Predicted files: none (verification only).
  - Write scope: none (read-only; mutations in an isolated copy).
- P5 `crew-docs-keeper` (three docs lines above, the pager of watch docs), then `crew-reviewer`. After P4.
  - Items:
    1. [ ] Update the wrist slot-id sentence to the tokened form — `docs/my_routines.md` · `:137`
    2. [ ] Update the same sentence — `docs/watch_session_sync/what_does_not_sync.md` · `:301-302`
    3. [ ] Update "a slot id is the effort's own row id" to name the per-session token — `docs/state_management/watch_surface.md` · `:82-83`
  - Done criteria: each behaviour sentence names an existing test (S-15001..S-15010); docs stay below 52 KB per file.
  - Predicted files: the three docs, nothing else.
  - Write scope: `"docs/my_routines.md"`, `"docs/watch_session_sync/what_does_not_sync.md"`, `"docs/state_management/watch_surface.md"`.

Parallelism: P1 and P2 run in parallel (disjoint write scopes: the Swift watch package vs `lib/watch/` + `lib/state/watch/` + `test/`). P3 waits for P1 (describes shipped behaviour). P4 waits for P1 + P2 (full suites). P5 waits for P4 (documents what landed, then review).

## Assumption Log

- Old history cannot be repaired (D-8); said to the owner.
- Token source differs between the create path (id factory) and add paths (session id): both only need to differ between sessions.
- A wrist app older than this change keeps colliding (D-5). The phone is not defended.
- (architect) Production session ids are UUIDs, so the 8-character token never contains `~` and the last-`~` decode is safe; a template effort id containing `~` would break it, and phone-minted template effort ids are `teff-<now>-<n>` / `demo-teff-…` (`lib/state/routine/routine_state.dart:581`, `mock/demo_routines_seed.dart:576`), never containing `~`.
- (architect) `watch/contract/watch_start_paths_contract.json` is read-only for this plan; tests map its plain expected ids to tokened forms.

## Progress

| Item | Result |
|---|---|
| P1.1 `sessionToken(from:)` | pending |
| P1.2 `slotId(token:)` / `slot(token:)` / `slots(token:)` | pending |
| P1.3 `startFromRoutine` token threading | pending |
| P1.4 `availableSlotId` dedup-then-token | pending |
| P1.5 `WatchSlotTokenTests.swift` | pending |
| P1.6 `WatchSessionStartPathsTests` red fixes | pending |
| P1.7 `WatchHealthActivityTests` mechanical fixes | pending |
| P1.8 `WatchConnectivityBridgeTests:899` fix | pending |
| P2.1 Dart `sessionToken` | pending |
| P2.2 Dart `slotId(token:)` / `slot(token:)` / `slots(token:)` | pending |
| P2.3 Dart start paths token threading | pending |
| P2.4 `_routineFor` decode | pending |
| P2.5 repro rewrite (S-15001) | pending |
| P2.6 `watch_session_start_test` fixes + S-15005 | pending |
| P2.7 `watch_reference_sync_test:299` fix | pending |
| P2.8 `watch_routine_adoption_test` S-15006/07/09 cases | pending |
| P3.1 `PROTOCOL.md` sentence | pending |
| P4 lead verification + mutations | pending |
| P5 docs keeper, then reviewer | pending |

## Open questions

1. D-2 vs S-15002 tension: D-2 says `availableSlotId` "builds its candidates from `slotId(token: <session token>)`", which would put the `-2` AFTER the token (`sx-ex-bench~tok-2`); S-15002 expects `sx-<exerciseId>-2~<token>` with "the token is always last". Resolution chosen: dedup the plain base exactly as today, then append `~<token>` (satisfies S-15002's exact strings and D-4's stated rationale). D-4's last-`~` decode works for either order, so the phone side is unaffected. Seed text kept verbatim.
2. S-15007 names `_mergeHeld`; the actual merge symbol is `_reconcile` (`lib/state/watch/watch_session_adoption_bridge.dart:1020`). Seed text kept verbatim; builders read `_reconcile`.
3. Seed line numbers corrected (seed text kept verbatim): `WatchStartPaths.swift:573-577` → fill branch `:570-577`; `watch_session_start_paths.dart:238-248` → `_availableSlotId` `:235-250`; `watch_session_adoption_bridge.dart:871-882` → `_routineFor` `:870-905` (decode loop `:876-882`).
4. The seed's P1 scope misses two test files: `WatchHealthActivityTests.swift` calls `effort.slot` as a property (`:285,304,333,359`) and stops compiling once `slot` becomes `slot(token:)`; `WatchConnectivityBridgeTests.swift:899` asserts the session's picked slot id equals `bench.slotId` and goes red. Both added to P1 (test-only fixes).
5. `watch/contract/watch_start_paths_contract.json` carries plain expected slot ids (`:89`, `:213`, `:301-304`, `:326`, `:328-333`) and is in no phase's write scope; tests derive token-appended expectations from it rather than editing it. If the governor prefers the contract to carry tokened ids, that is a separate decision.
6. `ls` is not a permitted command in this run (only `gateway.sh`); directory listings used the `view` tool instead.
7. The repro rewrite reuses the phone-side harness wiring already present in `test/watch_second_session_same_exercise_repro_test.dart` as found; if P2 finds the wiring differs from D-7's assumption, the builder keeps the no-hand-written-ids rule and records the delta in the evidence file.
