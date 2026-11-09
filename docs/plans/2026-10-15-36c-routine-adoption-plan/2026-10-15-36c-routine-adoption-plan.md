# Plan 36c — Routine start sync, PR 3: a routine started on the watch opens on the phone as that routine

Status: SEEDED by the lead. Base commit `e9c5207` (branch `claude_develop`; plans 36a `295dd71` and 36b (this base) are committed there). Tree clean at seed time.
Owner answers (2026-10-14): a routine started on the watch uses the phone's CURRENT version of the routine; it opens on the phone highlighted as the active routine, with its sets and presets, so the label reads "Set 1 of 3" and not "Set 1 of 0". Commits for plan 36 are authorised (`.work/2026-10-15-36c-routine-adoption/commit-ok.txt`); never push.

## Goal and acceptance

- A1. When the wrist's first snapshot carries slots that all belong to ONE routine template the phone holds (slot id `sx-<templateEffortId>`), the phone adopts the session as that routine: `TrainingSession.title` = the template's name, `intent` = `'routine'`, `routineTemplateId` = the template's id, `modality` stays null. The home screen then highlights the Routines tile (it reads `session.intent == 'routine'`, `lib/features/home/home_screen.dart:~538`) and not Free Training.
- A2. For every adopted `set` effort whose template effort the phone knows, the effort starts with the template's planned set rows from the phone's CURRENT template targets: one row per set (count = highest `setIndex` + 1, or 1 when the effort has no targets, as `RoutineSessionService._calculateSetCount`), reps and load from the template's targets for that set index (reps default 10 and load default 0 kg where a set has no target), no rests. The phone's session screen reads "Set 1 of N" with N the planned count.
- A3. The wrist's ladder stays the authority for structure: the efforts keep the wrist's slot ids and order; a template effort the wrist does not have is not added; a slot the matching template does not hold means no match (A5).
- A4. Non-`set` efforts (timed, drill, round) of a routine session are adopted as today (no planned rows), but the session still links to the routine. (Their planned rows are a later change.)
- A5. A ladder that matches no template (the routine was deleted on the phone, slots the wrist built from its catalog fallback `sx-<exerciseId>`, or a mix of routine and other slots) adopts EXACTLY as today: a free session, no title, no rows.
- A6. A later snapshot or a redelivery for the adopted session never duplicates rows or re-links (the existing "already adopted" paths; D-92/D-93 append-only growth is untouched).
- A7. With plans 36a/36b the adopted routine behaves like a phone-started one: nothing is logged, the wrist is sent `plannedSets` equal to the phone's rows, and a set logged on the wrist fills the first planned row.
- A8. No wire change, no schema change, no Swift change. `flutter analyze` not above 182; `flutter test` not below the count after 36b (`+4708 ~1`, plus new); `swift test` unchanged at 591.

## Decision Ledger

- D-1 Recognising the routine (technical decision: no new wire field). New private `Future<_AdoptedRoutine?> _routineFor(List<Map<String, Object?>> slots)` in `WatchSessionAdoptionBridge`: null when `slots` is empty or any slot id does not start with `sx-`; the effort ids are the slot ids without `sx-` (scout Y Q2: the wrist builds `'sx-$effortId'` from the phone's template effort id, `lib/core/utils/watch_reference_sync.dart:~311`; nothing else parses a slot id); for each template of `await _repository.getTemplates()` in the order returned, collect its effort ids through `getTemplateSegments(template.id)` then `getTemplateEfforts(segment.id)`; the first template whose effort-id set contains EVERY stripped id wins; read each matched effort's `await _repository.getTemplateTargets(effortId)`. `_AdoptedRoutine` is a small private record `({WorkoutTemplate template, Map<String, List<TemplateTarget>> targetsBySlot})` keyed by slot id.
- D-2 `_adopt` (`lib/state/watch/watch_session_adoption_bridge.dart:~747`): compute `final routine = await _routineFor(_slots(converged));` before creating the session; the `TrainingSession(...)` gets `title: routine?.template.name`, `intent: routine == null ? null : 'routine'`, `routineTemplateId: routine?.template.id` (named parameters exist: `lib/data/models/models.dart:~192-199`; the phone-start path sets the same triple, `lib/features/routine/my_routines_screen.dart:~196-203`). Nothing else about the session row changes.
- D-3 Planned rows: in `_adopt`'s effort loop, after `createEffort`, when `routine != null` and the slot's effort kind resolves to `BlockTypes.set` (use the same resolution `_effort` uses, `_effortKind(slot)`), call a new private `_createPlannedRows(effortId, slot, targets, atMs)`: `setCount` as in `RoutineSessionService._calculateSetCount`; for each set index `i` in `0..<setCount` the reps value is the `metric-reps` target whose `setIndex ?? 0 == i` (value = `targetInt ?? targetMin ?? targetMax`, rounded to int) else 10, the load the `metric-weight` target for `i` (double) else 0.0 (the pick rule of `populateSessionFromManifest`, `lib/state/workout/session_core_io.dart:~325-345`); write `LoggedEntryRows.setObservations(effortId: effortId, entryIndex: i, reps: reps, weightKg: weight, exerciseHasLoad: <exercise capabilities contain 'load', through await _repository.getExerciseById(exerciseId)>, atMs: atMs)` through `_repository.createObservation` (the repository path `_adopt` already uses; NOT `WorkoutState.addEntry`/`updateEntryValue`, which work on in-memory efforts the bridge has not loaded).
- D-4 Template data wins (owner answer 3): presets and set counts come from the phone's template as it is now, not from anything the wrist sent; the wrist's own routine copy (which carries no set counts, scout X Q1) is never consulted.
- D-5 Not in this plan: planned rows for timed/drill/round efforts; routine efforts appended later to an already-adopted EMPTY wrist session (the wrist's `startFromRoutine` absorb branch, `WatchStartPaths.swift:533`); a wire `routineId` (the inference of D-1 replaces it; revisit only if two templates can ever share effort ids, which template effort ids prevent).

## Readers of what this plan changes

- `_adopt` and everything that reads an adopted session: `test/watch_session_adoption_bridge_test.dart` (S-1 group `:308` asserts adopted effort ids = slot ids and "D-7 a wrist free session is Free Training" ~`:330`: those fixtures use slots named `sl-1`, `sl-2` (no `sx-` prefix) so they stay free-session guards), `test/watch_session_projection_test.dart`, `test/watch_session_merge_test.dart`, `test/watch_session_finish_test.dart`, `test/watch_live_refresh_screen_test.dart`, `test/watch_routine_round_trip_test.dart`, `test/watch_session_start_test.dart` (builds `sx-eff-*` ids ~`:848-867`): any test that adopts a snapshot whose slots are `sx-<id>` AND also seeds a template with those effort ids now adopts as a routine session; re-grep `sx-` in `test/` and read each hit.
- Home highlight: `lib/features/home/home_screen.dart:~536-551` (reads `intent`), `test/interaction_flow_test.dart:169`.
- Docs: `docs/watch_session_sync.md` (D-2 "the wrist's session is where a wrist session belongs", the D-7 free-training sentence, "What does not sync"), `docs/my_routines.md` (the template-to-session section), `docs/watch_session_capture.md` if it says a wrist-started session is always free.

## Core scenarios (exact fixtures)

Fixture T: template `routine-push` named "Push A" with one segment and two efforts: `eff-bench` (exercise `ex-bench`, effort kind `set`, capabilities include `load`) with targets set 0: reps 8 / 40 kg, set 1: reps 8 / 40 kg, set 2: reps 6 / 42.5 kg (`metric-reps` as `targetInt`, `metric-weight` as `targetMin`); and `eff-plank` (exercise `ex-plank`, effort kind `timed`) with no targets. The wrist snapshot: slots `sx-eff-bench` and `sx-eff-plank` (the wrist's slot shape: sessionExerciseId, exerciseId, name, capabilities, effortKind), no entries. (Seed the template like `_seedRoutine`, `test/watch_transport_test.dart:185`, plus `createTemplateTarget`.)

- S-3640 (new `test/watch_routine_adoption_test.dart`) Adoption links the routine: after the router receives the snapshot, `currentSession` has `routineTemplateId == 'routine-push'`, `title == 'Push A'`, `intent == 'routine'`, `modality == null`; efforts are `sx-eff-bench` then `sx-eff-plank` (ids = slot ids, order kept). Fails today: all three fields are null.
- S-3641 Planned rows: effort `sx-eff-bench` holds three set groups (`EntryRows.setGroups(await repository.getEffortObservations('sx-eff-bench'))`): number 0/1/2 with reps 8, 8, 6 and weight 40.0, 40.0, 42.5; `getEntryRests` is empty; the effort `sx-eff-plank` holds no set rows (A4). Fails today: zero rows ("Set 1 of 0").
- S-3642 The phone's CURRENT template: edit the template between the wrist's start and the adoption (change set 2 to reps 5 / 45 kg, add a third effort `eff-row` the wrist does not have): the adopted rows carry 8, 8, 5 and 45.0; no effort `sx-eff-row` exists. Fails without D-4's source of truth (a version that read the wrist would show 6 / 42.5).
- S-3643 An effort with no targets (`eff-plank` made kind `set` in a variant fixture with no targets): one row, reps 10, weight 0.0.
- S-3644 Unmatched ladders adopt as today: (a) no template seeded; (b) slots `sx-ex-bench` (catalog fallback id, no template effort of that id); (c) one routine slot `sx-eff-bench` plus a slot `sx-ex-extra`: each adopts a free session: `title`, `intent`, `routineTemplateId` null and no rows. Guard also: the existing S-1 group (slots `sl-1`, `sl-2`).
- S-3645 Highlight rule: with the adopted session `session.intent == 'routine'`; `hasActiveSession` is true (the tile logic in `home_screen.dart` reads exactly these two; one widget or state assertion of `intent`, no new screen test unless trivial).
- S-3646 Round trip with 36a/36b: after adoption, `projectSession` returns the slot `sx-eff-bench` with `plannedSets` `[{reps:8,loadKg:40},{reps:8,loadKg:40},{reps:6,loadKg:42.5}]` and `entries == []`; a wrist set (reps 9, 41 kg) fills row 0 (3 rows, not 4) and opens a rest at index 1.
- S-3647 Redelivery: the same snapshot delivered twice, and a later snapshot with a higher revision and the same slots, leave exactly 3 rows and one session (no duplicate effort, no second link).
- S-3648 A deleted routine: the snapshot arrives after the template was deleted on the phone: free session as today (same as S-3644 (a) but the template existed earlier).

Why they fail without the change: S-3640 null link; S-3641 zero rows; S-3642 stale values; S-3646 `plannedSets` absent (no rows) and the wrist set appends.

## Phase outline

- Phase P1 — `crew-builder-app`; scope `lib/state/watch/watch_session_adoption_bridge.dart,test/watch_routine_adoption_test.dart,test/watch_session_adoption_bridge_test.dart`: D-1, D-2, D-3 + S-3640..S-3648, and the re-read of every `sx-` reader the impact table finds (migrations only inside the two test files; a red test elsewhere: STOP and report). Red first.
- Phase D — `crew-docs-keeper`; `docs/watch_session_sync.md,docs/my_routines.md` (+ `docs/watch_session_capture.md` only if it states the old rule) + the plan's evidence file.
- After D: lead mutations (architect's proof list), reviewer, commit.

## Code pointers (current lines)

- `lib/state/watch/watch_session_adoption_bridge.dart`: `consider :~624`, `_adopt :~747-780`, `_effort :~864-881` (the effort row: id = slot id, `_effortKind(slot)`), `_slots(converged)`, constructor `:109-118` (repository only), `_slotFor :471`.
- `lib/core/services/routine_session_service.dart`: `buildSessionFromTemplate :22-80`, `_calculateSetCount :97-108`. `lib/state/workout/session_core_io.dart:265-350` `populateSessionFromManifest` (value pick rule).
- `lib/core/utils/logged_entry_rows.dart:46` `setObservations(...)`; `lib/core/constants/metric_ids.dart:47` `metricIdToKey`. `lib/data/repositories/workout_repository.dart:164-182` template API (`getTemplates`, `getTemplateSegments`, `getTemplateEfforts`, `getTemplateTargets`). `lib/data/models/models.dart:~192-199` `TrainingSession` fields; `:848` `TemplateTarget`.
- `lib/core/utils/watch_reference_sync.dart:~126` (`'routineId': template.id`), `:~311` `_segmentsJson` (effortId), `watch/watchos/.../WatchRoutineRecords.swift:187` and `lib/watch/start/watch_routine_catalog.dart:120` (`sx-<effortId>`).
- Tests: `test/watch_session_adoption_bridge_test.dart:191-199` `_slot`, `:308` S-1; `test/watch_transport_test.dart:185` `_seedRoutine`; `test/watch_routine_round_trip_test.dart` (36a, `_phone` pattern); `test/watch_session_merge_test.dart:148 _phone`.

## Architect expansion (2026-10-15)

### Claim checks (every file quoted was read this run)

- (a) VERIFIED with one correction — the constructor takes `routineTemplateId`, `title`, `intent` as named parameters (`lib/data/models/models.dart:211,214,218`) and `toMap`/`fromMap` persist all three (`:249,:256,:230,:237`); Hive stores sessions as `toMap()` maps (`_sessionsBox.put(session.id, session.toMap())`, `hive_workout_repository.dart:990-997`), Mock stores the object (`mock_workout_repository.dart:493-500`). Correction: there is NO `TrainingSession.copyWith` (grep over `lib/`: copyWith on WorkoutTemplate :721, RoundInstance :1184, TimedInstance :1378, EntryRest :1731 — none on TrainingSession); D-2 does not need it, the triple goes into the constructor. See Open questions 1.
- (b) VERIFIED — `_effortKind` (`watch_session_adoption_bridge.dart:889-908`): a declared `effortKind` present in `_declaredKinds` (:63) wins; otherwise the first capability in `_kindPrecedence` (:82: hold, rounds, reps, sets, load, time, distance) through `ModalityConfig.effortKindFromMetric` (`modality_config.dart:243-261`: reps/sets/load → 'set'), fallback `BlockTypes.set` (`block_types.dart:17` = 'set'). For capabilities `["sets","reps","load"]` the first precedence hit is `reps` → 'set'. `_effort` resolves the row's kind with the same `_effortKind(slot)` (:870), so D-3's gate and the row agree.
- (c) VERIFIED — `getTemplates()` returns every template with no `isBuiltInDemo` filter (`hive_workout_repository.dart:1953-1956`, `mock_workout_repository.dart:1210-1212`); `isBuiltInDemo` exists on WorkoutTemplate (`models.dart:675`); `_segmentsJson` builds `'effortId': effort.id` from `getTemplateEfforts(segment.id)` (`watch_reference_sync.dart:311`) — the exact ids the wrist prefixes with `sx-` (`watch_routine_catalog.dart:120`).
- (d) VERIFIED, answer: KEEPS — `LoggedEntryRows.setObservations` (`logged_entry_rows.dart:46-86`) always writes the `weight` row; `exerciseHasLoad: false` ADDITIONALLY writes an `_extraWeightKg` row (default 0.0, :80-82), and its doc covers "or is not known" (a null `getExerciseById`). The phone's own `addEntry` passes the same rule from capabilities (`session_core_entry.dart:~205-210`), so an adopted no-load effort gets the same rows a phone-started one would.
- (e) VERIFIED — `consider` (`watch_session_adoption_bridge.dart:624-741`): `existing == null` → `_adopt` (:725) then `loadHistoricalSession` (:730-733); a redelivery (`existing != null`) skips `_adopt`; the held-session path returns `alreadyHeld` via `_reconcile` (:652-663) before `_adopt`. `_everSeen[sessionId]` is set at :779, the END of `_adopt`, so a refused session is never marked seen. `loadHistoricalSession` (`session_core_io.dart:56-64`) sets `_currentSession` from the stored row, so `currentSession.intent` is readable by the home tile.

### Feature invariants (this plan only; project-wide rules stay in docs/global_conventions.md)

- I-1 Recognition is inference only: no wire field, no schema change; the slot-id shape `sx-<templateEffortId>` is the only signal (D-1; scout Y Q2: nothing else parses a slot id).
- I-2 Template data wins (D-4): planned rows come from the phone's CURRENT template targets; the wrist's routine copy is never consulted (S-3642).
- I-3 An unmatched ladder adopts EXACTLY as today: null title/intent/routineTemplateId, no rows (A5; guarded by S-3644 and the S-1 group, `watch_session_adoption_bridge_test.dart:308`).
- I-4 Adoption writes rows once: `_adopt` runs only when `existing == null` (:725) and `_everSeen` is set at its end (:779), so redelivery and later snapshots never duplicate (A6; S-3647).
- I-5 Planned rows only for `set` kind, resolved by the same `_effortKind(slot)` the effort row uses (D-3; S-3641's timed effort gets none).
- I-6 Adopted rows are byte-identical to the phone's own add: same `LoggedEntryRows.setObservations`, same defaults (reps 10 / weight 0.0, `session_core_entry.dart:~205-210`), same `exerciseHasLoad` rule (claim d).
- I-7 Mock and Hive give identical output (conventions; the S-1 Mock/Hive pattern, `watch_session_adoption_bridge_test.dart:372`).

### Existing-functionality impact

| Touched surface | What already reads it (search run this run) | Effect | Guarded by |
| --- | --- | --- | --- |
| `_adopt` gains the routine triple + planned rows (D-2/D-3) | Grep `sx-` in `test/`: 465 matches / 29 files. Only two watch test files seed templates (`watch_transport_test.dart:185` `_seedRoutine`, `watch_reference_sync_test.dart:137`) and neither's slot ids match its seeded effort ids (`routine-push-a-eff` vs `sx-bench`/`sx-plank`/`sx-squat`/`sx-pushed`) → NO existing test adopts an `sx-` snapshot that matches a seeded template; no test migrations expected. Direct `consider(` callers: adoption_bridge :525/:590/:853/:976/:1007, finish :590/:1072, pr4 :696/:812 (slots `sl-w1`, `u-squat` — no `sx-` prefix); production caller `watch_incoming_router.dart:131` only. `sx-` hits in merge/round-trip/live-refresh/finish/auto-push are wrist ENTRY ids or phone-created slot ids, not adoption slots | Adoption snapshots with `sx-` slots that match a seeded template change verdict; every existing fixture stays free-session | S-3640..S-3644, S-3648 |
| Home tile highlight (`home_screen.dart:536-551`) | Grep `intent` over `test/watch_*.dart` → 0 hits: no test pins an adopted session's title/intent/routineTemplateId; `interaction_flow_test.dart:169` pins a Resistance tile (phone-started) | The Routines tile becomes active for adopted routine sessions; no existing assertion breaks | S-3645 |
| Docs | `docs/watch_session_sync.md:732-733` is the only live sentence saying a wrist-started session opens free ("plan 36c takes that. No test pins the wrist-started case."); `docs/watch_session_capture.md` states no free/intent rule (grep → 0 hits); `docs/my_routines.md` has no wrist mention (grep → 0 hits) | Phase D rewrites :732-733 and adds the wrist-start sentence to `my_routines.md`'s template-to-session section | — |

### Edge scenarios (after S-3648)

- S-3649 The template effort's exercise is missing from the phone's library (deleted while the template remains): `getExerciseById` returns null → `exerciseHasLoad` false (the slot's own `capabilities` are the fallback D-3 names) → the extra-weight row per claim d's "not known" rule — the same rows the phone's own `addEntry` writes for an unknown exercise (`session_core_entry.dart:~205-210` `?? false`). Fails without naming the fallback (a crash or a divergent row set).
- S-3650 Two templates containing the same stripped ids: cannot happen — `app_template_effort.id` is `TEXT NOT NULL PRIMARY KEY` (`scripts/sqlite_schema.sql:490-491`), one effort row → one `template_segment_id` → one template, so D-1's "first template wins" tie-break never fires between two matching templates (D-5's revisit condition stays closed).
- S-3651 A built-in demo template matches: `getTemplates()` is unfiltered (claim c) and demo rows are startable (`docs/my_routines.md:233`), so the session adopts with the demo template's id/name — desired, no special case.
- S-3652 The phone already holds ANOTHER active session: `refusedConflict` (bridge :672-676) returns before `_adopt`, so `_routineFor` never runs and nothing is created or linked. Guard: the existing conflict tests (`watch_session_adoption_bridge_test.dart:526,:854`).
- S-3653 A target with `setIndex` null maps to row 0 via `setIndex ?? 0` (the same null-as-0 `_calculateSetCount` uses, `routine_session_service.dart:97-108`); two targets for one metric, one null and one 0, both match row 0 — the first in `getTemplateTargets` order wins (D-3 does not order them; the builder takes first-match and logs it in the Assumption Log).
- S-3654 A set-index gap (targets at 0 and 2 only): count = 3, row 1 gets the defaults reps 10 / load 0.0 (D-3's else branch) — the same shape a phone-started session shows for a gapped template.

### Phases

- Phase P1 — `crew-builder-app`; scope `lib/state/watch/watch_session_adoption_bridge.dart,test/watch_routine_adoption_test.dart,test/watch_session_adoption_bridge_test.dart` (serial):
  1. [ ] Red: new `test/watch_routine_adoption_test.dart` with fixture T: S-3640 (triple null today), S-3641 (zero rows today), S-3643, S-3644 (a)(b)(c), S-3648 — `test/watch_routine_adoption_test.dart`
  2. [ ] D-1: `_routineFor` + the `_AdoptedRoutine` record — `lib/state/watch/watch_session_adoption_bridge.dart` · `_routineFor`
  3. [ ] D-2: the triple into `TrainingSession(...)` in `_adopt` — `watch_session_adoption_bridge.dart` · `_adopt` (:747-780)
  4. [ ] D-3: `_createPlannedRows` after `createEffort`, gated on `_effortKind(slot) == BlockTypes.set` — `watch_session_adoption_bridge.dart` · `_createPlannedRows`
  5. [ ] S-3642 (current template), S-3645 (intent assertion), S-3646 (round trip with 36a/36b), S-3647 (redelivery), S-3649, S-3653, S-3654 — `test/watch_routine_adoption_test.dart`
  6. [ ] Re-read the S-1 group and the direct-`consider` callers the impact table lists; migrate only inside the two test files in scope — `test/watch_session_adoption_bridge_test.dart`
  - Done criteria: `flutter test test/watch_routine_adoption_test.dart test/watch_session_adoption_bridge_test.dart` green (900 s timeout); S-3640/S-3641 proven red at base; `flutter analyze` not above 182.
  - Predicted files: the three in scope, nothing else.
- Phase D — `crew-docs-keeper` (after P1); scope `docs/watch_session_sync.md,docs/my_routines.md` (+ the plan's evidence file):
  1. [ ] Rewrite `docs/watch_session_sync.md:732-733`: a wrist-started routine opens as that routine, naming S-3640/S-3641
  2. [ ] Add the wrist-start sentence to `docs/my_routines.md`'s template-to-session section (:160-190), naming S-3640
  3. [ ] Confirm `docs/watch_session_capture.md` states nothing now false (grep run: no free/intent rule) — no edit expected
  4. [ ] Write the plan's `.evidence.md`: baselines, red→green rows, mutation results
  - Done criteria: every behaviour sentence names an existing test; docs stay below 52 KB.

Parallelism: P1 serial (one production file, one builder). D waits for P1 (its sentences name P1's tests).

### Proof list (mutation per guard, by line and substring)

- S-3640: drop `intent: routine == null ? null : 'routine'` from `_adopt` → the tile rule sees no intent; drop `title: routine?.template.name` → title null; drop `routineTemplateId: routine?.template.id` → the link is null (three separate mutations).
- S-3641: in `_createPlannedRows`, `maxSetIndex + 1` → `maxSetIndex` → two rows instead of three; the else-10 reps → else-0 → S-3643 sees reps 0; the else-0.0 load → else-1.0 → weight 1.0.
- D-1: pass the raw slot id instead of the stripped id to `getTemplateTargets` → every row falls to defaults (S-3641 fails); drop the every-id containment check (match on the first slot only) → S-3644(c)'s mixed ladder links.
- S-3642: read the targets before the edit window / from a cached copy → stale 6 / 42.5 (S-3642 fails).
- S-3647: move `_everSeen[sessionId] = …` before `_adopt`'s row writes, or drop the `existing == null` gate → duplicate rows (S-3647 fails).
- S-3649: `exerciseHasLoad: true` unconditionally → a no-load effort loses its extra-weight row (diverges from the phone's own add).

## Progress / Assumption Log / Feedback / Open questions

(empty — architect fills the progress table; builders write the Assumption Log and Feedback.)

### Progress

| Item | Result |
| --- | --- |
| P1 items 1–6 | pending |
| D items 1–4 | pending |

### Assumption Log

- A-1 The seed's test pointers re-read this run and match: `watch_session_adoption_bridge_test.dart:191-199` `_slot`, `:308` S-1, `watch_transport_test.dart:185` `_seedRoutine`, `watch_session_merge_test.dart:148` `_phone`.

### Feedback

Review: `2026-10-15-36c-routine-adoption-plan.review.md` (the lead's review; APPROVE WITH FIXES, all applied).
- [x] 1 (major): tests ran on Mock only; now `Mock` and `Hive` groups (`_adoptionTests(open, close)`). The Hive run found a store-order dependence in the null-set-index tie-break (Open question 3).
- [x] Tie-break made store-independent: an explicit set index beats a null one, then the lowest target id (`_plannedValue`); `S-3653`, `S-3653b`, `S-3653c` pin it under both stores; lead mutations R11/R12 fail them.
- [x] 5 (doc gap): known limits bullet added to `docs/watch_session_sync.md`.
- [ ] 2, 3, 4 (minor): accepted, recorded in the review.

### Open questions

1. Claim (a)'s "copyWith" is WRONG: no `TrainingSession.copyWith` exists anywhere in `lib/` (grep: copyWith on WorkoutTemplate `models.dart:721`, RoundInstance :1184, TimedInstance :1378, EntryRest :1731 — none on TrainingSession). D-2 does not need it (the triple goes into the constructor). "Hive adapter fields" is also imprecise: sessions are stored as `toMap()` maps (`hive_workout_repository.dart:990-997`), not a generated adapter. Proposed correction: "named parameters exist and toMap/fromMap persist them; Hive stores toMap() maps". The decision is kept.
2. The seed's reader list names `test/watch_session_projection_test.dart` and `test/watch_session_start_test.dart` (`sx-eff-*` ~:848-867): re-read this run — projection tests build phone-side sessions (no adoption), start_test :848-867 is the wrist-side Dart twin of `startFromRoutine` (no phone bridge); both unaffected, listed here so the builder does not re-chase them.
3. RESOLVED: D-3 now says which target wins when targets compete for one row: an explicit set index beats a null one, then the lowest id (the Hive parity run showed the first-listed rule depended on the store's order). See Feedback.
