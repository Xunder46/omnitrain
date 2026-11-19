# Feature: 74 — the phone stops re-reading all its foods, routines and exercises every time the wrist is raised

> Status: Iteration 1 active. No owner answer needed: nothing a user sees changes (the same data reaches the watch, only the phone's idle work goes). One track: phone (`lib/`).
> Next handoff: `crew-builder-data` (Phase 1), then `crew-builder-app` (Phase 2).
> Base: `c1b1c5f0` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Binding: `docs/global_conventions.md`; `.github/copilot/pr-scope-budget.md`; the repository pattern (state depends on `WorkoutRepository` only).

## Overview

| What you do | Now | After 74 |
|---|---|---|
| Raise your wrist, nothing changed on the phone | The phone reads every food, food group, routine (with every segment, effort and target), every exercise and each exercise's capabilities from storage — twice for the routines — and then sends nothing | The phone asks storage one cheap question ("did any of that change?"), reads nothing, sends nothing |
| Log a food, edit a routine, add an exercise on the phone, then raise your wrist | Watch gets the new data | Same: the change is noticed and re-read once |
| Change a setting (rest ping, units, accent, effort question) | Watch gets it | Same (settings are in memory and are still compared every time) |

Code facts (scouts + lead, 2026-10-24):
- Handler: `lib/state/watch/watch_sync_request_handler.dart` `WatchSyncRequestHandler._sendRoutines` (l.~108-165) and `_bundle` (l.~175): reloads foods (`loadFoodGroups`, `loadFoods`), builds a probe bundle at 1970 to get a content signature, may build the stamped bundle a second time, then `WatchReferenceSync.buildExercisesDown` (re-reads `getExercises` + `getExerciseCapabilities` per exercise) on every request just to compare the version string.
- No change counter exists on `WorkoutRepository`. `HiveWorkoutRepository` keeps each kind in its own box (`_exercisesBox`, `_exerciseCapabilitiesBox`, `_templatesBox`, `_templateSegmentsBox`, `_templateEffortsBox`, `_templateTargetsBox`, `_foodGroupsBox`, `_foodsBox`, `_foodCatalogBox`; about 60 scattered write sites); `MockWorkoutRepository` keeps maps (about 50 write sites). `HiveWorkoutRepository.initialize()` (l.176-250) opens the boxes and has no close method. 24 test classes `extends MockWorkoutRepository`; only Hive and Mock `implements WorkoutRepository`.
- Hive boxes expose `box.watch()` (a broadcast `Stream<BoxEvent>`, one event per put/delete, one per key on `clear`). Delivery is a microtask after the write; the awaiting caller's continuation is queued after it, so the counter has moved by the time `await box.put(...)` returns. Phase 1's Hive test proves it for each kind; if it does not hold, stop and report.

## Decision Ledger

- **D-1** `WorkoutRepository` gains `int? get referenceRevision;` — "A number that differs whenever any food, food group, catalog food, template, template segment/effort/target, exercise or exercise-capability row was written since it was last read; null means the repository cannot tell, so a caller must re-read." (`workout_repository.dart`, beside the data-version members at l.~709).
- **D-2** `MockWorkoutRepository` answers `null` (never lets a caller skip a read; no write-site edits). Tests that need a skip use a small subclass that overrides the getter (the 24 existing subclasses are untouched).
- **D-3** `HiveWorkoutRepository` answers an `int` counter `_referenceRevision`, bumped by one `box.watch()` listener on each of the nine boxes named above. The listeners are created at the end of `initialize()` (before `_initialized = true`), after cancelling any left from an earlier `initialize()` call. No write site is edited. Events from the migration run inside `initialize()` count; the value is only ever compared for equality, never interpreted.
- **D-4** Handler (exact code in Phase 2): reads `referenceRevision` once at the start of `_sendRoutines`. When it is non-null and equals the revision stored with `_held`, storage cannot have changed: foods are NOT reloaded, the probe routines/foods are NOT rebuilt, the held reference text is reused. The preferences (in memory in `SettingsState`, not covered by the revision) are rebuilt and compared every request. A reload that throws stores a null revision, so the next request reads again.
- **D-5** Stamp rules are unchanged: the stamp renews exactly when the content of the three frames differs from the last answer (a different preferences text, or a different routines/foods text). S-9201..S-9212 stay green untouched.
- **D-6** The exercise list: when the wrist names the version it holds, and the revision equals the revision recorded when that version was computed, the answer is "nothing to send" with no read. Otherwise the batches are built and the version recorded with the revision, exactly as today. A wrist holding nothing (null version) is always sent the list.
- **D-7** Out of scope: persisting the revision across launches (a relaunched phone reads once, like S-9212); a per-kind revision; caching built frames (a wrist that lacks the bundle still triggers one stamped build).
- **D-8** Readers waiting for a message this skips (lead's rule as): the wrist's "sync progress" spinner (plan 55) ends on the arrival of the preferences/routines frames or the exercise list; this plan changes nothing about which frames are sent, only whether storage is read to decide. No new silence.

## Scenarios (ids `S-104xx`; grep 2026-10-24: unused)

- **S-10401 (Hive, plain `test()`) every written kind moves the revision.** Fixture: `HiveWorkoutRepository` via `test/helpers/repository_harness.dart` (temp dir, path_provider stub). Record `r0 = repo.referenceRevision`. Then, one at a time, each followed by `await` and a read of the getter: `createFood`, `updateFood`, `archiveFood`, `createFoodGroup`, `createExercise`, `setExerciseCapabilities(id, ['time','distance'])`, `createTemplate`, `createTemplateSegment`, `createTemplateEffort`, `createTemplateTarget`, `deleteTemplate`. Expected: after each call the revision differs from the value before that call (use a fresh before-value per step). Fails without D-3: the getter is a constant or does not exist.
- **S-10402 (Hive) writes that are not reference data leave it alone.** Fixture: record revision; `createSession`-style write (use an existing simple session or body-measurement write helper from `repository_harness.dart`), a preference write. Expected: revision unchanged.
- **S-10403 (Hive) two reads with no write between return the same number; a second `initialize()` over the same storage does not stack listeners** (call `initialize()` twice, write one food, expect the revision to move by exactly 1... the number is compared only for inequality elsewhere, so assert `after != before` and `after - before == 1` here, the one place the step is pinned).
- **S-10404 (Mock) the Mock answers null before and after writes.**
- **S-10405 (handler, Mock subclass `_RevisionedRepo` with a settable `revision` and call counters on `getFoods`, `getTemplates`, `getExercises`) the idle raise reads nothing.** Fixture: a phone with 2 foods, 1 routine, 2 exercises; first request (`since: null, exercisesVersion: null`) sends the three frames and the exercise list. Second request naming the stamp and the version, revision unchanged. Expected: zero further calls to `getFoods`, `getFoodGroups`, `getTemplates`, `getTemplateSegments`, `getExercises`, `getExerciseCapabilities`; nothing sent. Fails today: every counter grows.
- **S-10406 a changed revision re-reads once and re-sends.** Fixture: as S-10405, then add a food through the repository and bump `revision`; request again naming the old stamp and version. Expected: foods reloaded once; the three frames are sent with a NEW stamp; the exercise list is built once (version equal: not sent).
- **S-10407 a settings change with the revision standing still still re-sends.** Fixture: as S-10405, revision unchanged, then change `SettingsState` rest-ping interval; request naming the stamp. Expected: the three frames are sent with a new stamp; `getFoods`/`getTemplates` counters did NOT grow.
- **S-10408 a null revision (the Mock itself) behaves exactly as today** (reads every time). The existing `watch_sync_changed_only_test.dart` and `watch_sync_request_handler_test.dart` suites run on `MockWorkoutRepository` and must pass unchanged; this is their proof.
- **S-10409 a failed food read does not freeze the cache.** Fixture: `_ThrowingOnceRepository`-style: revision stands still, the food read throws once on the first request. Expected: the second request reads again (counter grows) because the revision was not stored.
- **S-10410 an exercise change moves the list.** Fixture: as S-10405, then `updateExercise` + bump; request naming the old version. Expected: batches built; version differs; the list is sent.
- **S-10411 the revision is read once per request and before any read** (source guard on `_sendRoutines`: the statement `final revision = _repository.referenceRevision;` appears before `loadFoodGroups`). Reads taken after a write that lands mid-request store the older number, so the next request re-reads.

## Phase 1: the repository member (`crew-builder-data`)

1. [ ] `WorkoutRepository.referenceRevision` (D-1) — `lib/data/repositories/workout_repository.dart`.
2. [ ] Mock: D-2 — `mock_workout_repository.dart`.
3. [ ] Hive: counter + listeners (D-3) — `hive_workout_repository.dart` (`initialize()`).
4. [ ] Tests S-10401..S-10404 — new `test/repository_reference_revision_test.dart` (plain `test()`, Hive via the harness; run Mock-first; never `testWidgets`).
5. [ ] Docs: one sentence in `docs/data_models.md` or the repository doc that names the member (find where `getDataVersion` is documented; if nowhere, `docs/db_integration.md`).

**Done**: `flutter test test/repository_reference_revision_test.dart` plus the sibling repository tests `test/watch_capture_repository_parity_test.dart`, `test/food_library_persistence_test.dart`; `flutter analyze` count not above the plan baseline (record it in the evidence file first). Never the full suite.

## Phase 2: the handler (`crew-builder-app`, after Phase 1)

1. [ ] `_sendRoutines`, `_held`, `_exercisesHeld` as D-4..D-6 (exact code in the brief) — `lib/state/watch/watch_sync_request_handler.dart`.
2. [ ] Tests S-10405..S-10411 — new `test/watch_sync_idle_reads_test.dart`, copying the setup helpers of `test/watch_sync_changed_only_test.dart` (named in the brief).
3. [ ] Docs: the "foods are read back from storage on every request" sentence in the handler's doc comment and `docs/state_management/watch_surface.md` (find with grep `read back from storage`) now say "unless the repository's revision stands still".

**Done**: the two new test files, `test/watch_sync_changed_only_test.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_transport_test.dart`, `test/watch_accent_contract_test.dart`, `test/rest_ping_contract_test.dart`; then the lead runs the full suite.

## Progress
- [x] Phase 1
- [x] Phase 2

## Assumption Log
- Builder deviation accepted: S-10407 asserts one food reload when a settings change makes the bundle go out (the send path reloads, as before the plan); the plan text said none.
- Mutants H1..H10 and the nine box listeners killed after two tests-only additions (S-10410a/b arms, `createCatalogFood` in S-10401); H5 (`exercisesVersion != null`) is equivalent (a String never equals null).

## Feedback
