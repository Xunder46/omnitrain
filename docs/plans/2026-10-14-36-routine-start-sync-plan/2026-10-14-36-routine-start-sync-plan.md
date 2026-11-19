# Plan 36 — Routine start sync, PR 36a: the phone tells the watch only what it logged, and a watch set fills the phone's next planned set

Status: SEEDED by the lead. Base commit `4b7a002` (branch `claude_develop`; was `942fee0` when seeded, the owner then committed the unrelated units work). The tree also holds the earlier, unrelated, uncommitted
work of this session (watch units + Xcode fixes: `ios/**`, `watch/sync_protocol/**` units fields, `WatchUnitsTests.swift`,
`WatchPhonePreferences.swift`, `WatchLoggingState.swift`, `lib/core/utils/watch_reference_sync.dart`, `lib/state/watch/watch_sync_request_handler.dart`,
`test/rest_ping_contract_test.dart`, `test/watch_sync_request_handler_test.dart`, `docs/theme_and_settings.md`): do not touch, do not absorb.

Owner answers (2026-10-14): (1) a routine started on the phone shows the watch the planned sets and presets, nothing logged; (2) a set logged on the
watch marks the phone's planned set done, moves to the next, one shared rest timer; (3) a routine started on the watch uses the phone's current version
of the routine; (4) order: phone-started first. This plan is 36a only; 36b and 36c are listed under "Not in this plan".

## Goal and acceptance

Bug as the owner saw it (real devices): start a routine on the phone; the watch shows the routine's sets "as if logged" (menu says "N logged"); logging a
set on the watch adds one more set; the phone shows that set as not logged until Next is tapped on the rest screen, which lets the user log it again
and starts a second rest timer.

- A1. A phone session whose set rows exist only as planned values (routine presets, or the default row a new exercise gets) sends the watch NO `set` entries
  for them. The watch menu shows no "N logged" for that exercise.
- A2. A set counts as logged on the phone exactly when a rest record exists at the NEXT entry index (the rule of `WorkoutSessionScreen._isSetLogged`); only
  such sets are sent as entries. Logging set 1 on the phone sends exactly that one entry.
- A3. A set the watch logs for a slot that already holds planned (unlogged) rows FILLS the first unlogged row in place (its values become the wrist's
  reps and load) instead of appending a new row; the row count of the exercise does not change. When every row is logged it appends, as today.
- A4. At the moment the wrist's set is imported the phone also holds an OPEN rest at that row's index + 1 (start = the set's `loggedAt`, end null), so the phone shows the set
  as LOGGED at once and offers no Log button for it, with the one rest running from the wrist's log time. When the wrist's own `rest` entry for that set later arrives
  it CLOSES that open rest (start/end from the entry); it never creates a second rest at the same index.
- A5. The filled row is stamped like every imported wrist row (created stamp = the wrist entry's `loggedAt`), so the projection's claim rule still recognises
  it as the wrist's own and does not send it back under a phone id (no echo, no double count on the wrist).
- A6. Timed, hold and round slots, nutrition, rating and the session end are unchanged. Wire format and schemas are unchanged.
- A7. `flutter analyze` not above the baseline recorded in Progress; no new `ui_standards` allowlist entries.

## Decision Ledger

- D-1 "Logged" is one rule, shared. New pure helper `loggedSetNumbers(List<EntryRest> rests) => {for (final r in rests) r.entryIndex - 1}` in `lib/core/utils/entry_rows.dart` (class `EntryRows`, next to `setGroups`), and `WorkoutSessionScreen._isSetLogged` for `effortKind == 'set'` is left as is (not refactored in this PR; a comment points at the helper). Reason: no refactor of the screen under a sync fix.
- D-2 `PhoneEntries.project` (`lib/core/sync_protocol/phone_entries.dart:62`) gains a required `Set<int> loggedNumbers` and skips every group whose `number` is not in it. `group.number` is the 0-based entry index (entry id `entry-<slot>-<number>`, observation ids `obs-<slot>-<number>-reps`).
- D-3 `WatchSessionAdoptionBridge._entriesFor` (`lib/state/watch/watch_session_adoption_bridge.dart:~265`, the `PhoneEntries.setKind` case) reads `await _repository.getEntryRests(effort.id)` and passes `loggedNumbers: EntryRows.loggedSetNumbers(rests)`. No other projection kind changes.
- D-4 Fill in place (importer). `_placeAroundUserRows` (`lib/core/services/watch_session_importer.dart:757`) has three callers: the held merge (`:349`, inside `_mergeHeld`) and two history-import paths (`:505`, `:666`). It gains a named parameter `bool fillPlanned = false`; ONLY the held-merge call (`:349`) passes `true`. When `fillPlanned` and the entry is a `set`, the entry's index is the number of the FIRST existing row group of the effort (from `rows`, the `_EffortRows` read) that has no rest at number + 1 (`await _repository.getEntryRests(effortId)`); when there is none it appends at `next++` as today. The two history paths are unchanged, so "no wrist entry ever lands on, moves, edits or deletes a row the user made" still holds for imported history (S-3611).
- D-5 A fill replaces the planned row: for the chosen index the importer first deletes that row group's observation rows (`_repository.deleteObservation(row.id)` for each row of the group, found through `EntryRows.setGroups(await _repository.getEffortObservations(effortId))`), then writes the wrist's rows through the existing `_createEntry(key, entry, effortId, index)` (`:937`), which stamps the rows with the entry's `loggedAt` (so A5 holds with no extra code) and uses the same deterministic ids (`obs-<effort>-<index>-reps/-weight`). No new repository method; the delete-then-create order avoids a duplicate id in the Mock repository. The entry is recorded in `_placed[entry.entryId]` at that index so `_applyRests` keys the rest at index + 1.
- D-6 Open rest on import. After placing a wrist `set` entry the importer calls `_repository.createEntryRest(EntryRest(id: 'rest-<effort>-<index+1>', ..., restStartMs: loggedAtMs, restEndMs: null, ...))` when no rest exists at index + 1. `_applyRests` (`:~835`): when a rest exists at that index and is open (`restEndMs == null`) and the wrist's `rest` entry names that set, it is closed with the entry's `endedAt` via `_repository.updateEntryRest(rest.copyWith(restEndMs: endedAtMs, updatedAtMs: ...))`; a closed rest is left alone (the phone's own rest wins, as today).
- D-7 The phone's in-memory rest cache (`TimerManager._entryRests`) is refreshed by the existing watch refresh path (`WorkoutState.refreshHeldEfforts`, tested by `S-16` in `test/watch_session_merge_test.dart` and `test/watch_live_refresh_screen_test.dart`). No new refresh hook; Phase B proves it with the existing screen test pattern.
- D-8 No wire change in this PR: planned sets are NOT sent yet (that is 36b, the watch's presets). Docs: `docs/watch_session_sync.md` states the new rule; `watch/sync_protocol/PROTOCOL.md` is untouched.

## Readers of what this plan changes

- Callers of `PhoneEntries.project`: `lib/state/watch/watch_session_adoption_bridge.dart` (only); tests: `test/watch_session_projection_test.dart` (S-31, S-33, S-34, S-36, S-37, S-39, S-40, S-43, S-59, S-60, S-140…S-143; its fixtures build set rows with `LoggedEntryRows.setObservations` at `:~274` and WITHOUT rests: every one of them must add a rest at number+1 for each set it expects to be projected).
- `projectSession` readers (auto-push, snapshot answers): `test/watch_session_auto_push_test.dart`, `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_finish_test.dart`, `test/watch_live_refresh_screen_test.dart`, `test/watch_session_merge_test.dart`, `lib/state/watch/watch_sync_wiring.dart` (re-grep `projectSession` and `setObservations` before the phase).
- Importer readers: `test/watch_session_merge_test.dart` (S-9, S-10, S-11, S-16: fixtures where the phone has NO rows stay appends; any fixture where the phone has planned rows and a wrist set arrives changes to a fill), `test/watch_session_rest_timer_append_test.dart`, `test/watch_session_importer_test.dart` if present (re-grep `WatchSessionImporter`), `test/watch_session_inbox_test.dart` if present.
- Docs: `docs/watch_session_sync.md` (sections "D-11" answer composition and the "S-9 / merge" rows), `docs/watch_session_capture.md` only if it states that the phone sends all its set rows.

## Core scenarios (exact fixtures)

Fixture F: a live phone session, one slot `sl-1` (exercise `exercise-bench`, kind set), three planned rows `0,1,2`, each reps 10, weight 40.0 kg; no rests. (Build with `LoggedEntryRows.setObservations(effortId: 'sl-1', entryIndex: n, reps: 10, weightKg: 40.0, exerciseHasLoad: true)` for n = 0,1,2, the helper `_phoneRows` of `test/watch_session_merge_test.dart:350` is the pattern.)

- S-3601 (projection, `test/watch_session_projection_test.dart`) F with no rests: `projectSession` returns `entries == []` (before this PR: 3 `set` entries ids `entry-sl-1-0..2`). Fails without D-2/D-3 because `_entry` accepts reps >= 1.
- S-3602 F plus one rest at index 1 (set 0 logged): entries == exactly `[entry-sl-1-0]`, reps 10, loadKg 40.0. F plus rests at 1 and 2: entries `entry-sl-1-0`, `entry-sl-1-1`.
- S-3603 F with a rest at index 1 and row 0 reps 0 (skipped): still no entry (the `reps < 1` rule stays).
- S-3604 (merge, `test/watch_session_merge_test.dart`) F, the wrist sends `observations_up` set `reps 8, loadKg 42.5`, `loggedAt` = T: rows count stays 3; row 0 holds reps 8 / weight 42.5 (observation ids `obs-sl-1-0-reps`, `obs-sl-1-0-weight`, no `obs-sl-1-3-*`); `getEntryRests('sl-1')` has exactly one rest, index 1, `restStartMs == T`, `restEndMs == null`.
- S-3605 Second wrist set (reps 8, 42.5) fills row 1 (not row 3); rests at index 1 and 2.
- S-3606 Three wrist sets fill rows 0..2; a fourth appends row 3 (rows count 4); rests at 1, 2, 3, 4.
- S-3607 The phone user logs set 0 on the phone (rest at index 1 exists, closed or open) and then the wrist logs a set: it fills row 1.
- S-3608 After S-3604, the wrist's `rest` entry (`afterEntryId` = the wrist's set entry id, `startedAt` T, `endedAt` T+60 s): the rest at index 1 now has `restEndMs == T+60s`; `getEntryRests` still has ONE rest at index 1. Redelivery of the same rest entry changes nothing.
- S-3609 (round trip, new `test/watch_routine_round_trip_test.dart`) F, a wrist set fills row 0, then `projectSession`: entries == [] (the wrist's own set is claimed by its stamp and is not echoed; no entry id `entry-sl-1-0` rides back). Phone logs set 1 (rest at index 2): entries == `[entry-sl-1-1]`.
- S-3610 (screen) with the pattern of `test/watch_live_refresh_screen_test.dart`: F on the session screen, a wrist set arrives; the screen shows set 1 as LOGGED (no Log button for it) and the rest strip is running; it shows no second set row ("Set 2 of 3" not "of 4").
- S-3611 History is untouched: an imported effort the user added rows to (`_placeAroundUserRows` path, `test/watch_session_merge_test.dart` existing S-11) still appends after the last row.

Why they fail without the change: S-3601/2/3 see 3 entries today; S-3604 sees 4 rows today and no rest; S-3606 sees rest only for wrist rows; S-3608 sees a second closed rest or none; S-3609 sees an echo if the fill keeps the old stamp (mutation: skip the restamp).

## Phase outline

- Phase A — `crew-builder-app`; scope `lib/core/utils/entry_rows.dart,lib/core/sync_protocol/phone_entries.dart,lib/state/watch/watch_session_adoption_bridge.dart,test/watch_session_projection_test.dart,test/watch_session_auto_push_test.dart,test/watch_session_adoption_bridge_test.dart,test/watch_session_finish_test.dart`: D-1, D-2, D-3 + S-3601, S-3602, S-3603; migrate the readers' fixtures (add the rests the fixtures need). Parallel with B (disjoint files).
- Phase B — `crew-builder-app`; scope `lib/core/services/watch_session_importer.dart,test/watch_session_merge_test.dart,test/watch_session_rest_timer_append_test.dart`: D-4, D-5, D-6 + S-3604, S-3605, S-3606, S-3607, S-3608, S-3611. Only A or B runs the full suite (B touched-files only if A is live).
- Phase C — `crew-builder-app`; scope `test/watch_routine_round_trip_test.dart,test/watch_live_refresh_screen_test.dart`: S-3609, S-3610 (after A and B). Production code only if S-3610 shows the screen does not refresh; then stop and report to the lead.
- Phase D — `crew-docs-keeper`; `docs/watch_session_sync.md` (+ `docs/watch_session_capture.md` if it states the old rule), evidence into the plan's `.evidence.md`.
- After D: prover brief (mutations only), the lead applies them, reviewer, then simulator look is NOT needed (no screen changes) but the owner checks on devices (owner).

## Code pointers (current lines)

- `lib/core/sync_protocol/phone_entries.dart:62` `project(...)`; `:434-458` `_entry` (`if (reps < 1) return null;`); `group.number` doc at `lib/core/utils/entry_rows.dart:20` `SetRows`, `:158 setGroups`.
- `lib/state/watch/watch_session_adoption_bridge.dart:204 projectSession`, `:~265` `case PhoneEntries.setKind: return PhoneEntries.project(...)`.
- `lib/features/session/workout_session_screen.dart:751-769` `_isSetLogged` (`rests.any((r) => r.entryIndex == nextEntryIndex)`), `:946-960` the rest start on log (`recordRestStart(effortId, _currentSet)`), `:517-` `_resyncExercisesFromState` (D-3506).
- `lib/core/services/watch_session_importer.dart:134` `if (phoneOwnsSession) return _mergeHeld(...)`, `:234` `_mergeHeld`, `:757-784` `_placeAroundUserRows` (`var next = rows.lastIndex + 1;`), `:~835` `_applyRests` (creates a closed `EntryRest` at `placed.index + 1`, skips when one exists at that index).
- `lib/data/repositories/workout_repository.dart:256-262` `getEntryRests`, `createEntryRest`, `updateEntryRest`.
- `lib/state/workout/timer_manager.dart:693` `recordRestStart` (open rest at the next index, closes older open rests), `:736` `recordRestEnd`.
- Tests: `test/watch_session_merge_test.dart:148 _phone`, `:215 _snapshot`, `:234 _set`, `:341 _ids`, `:350 _phoneRows`, `:437` S-9, `:574` S-11, `:1101` S-16.

## Not in this plan

- 36b: the watch shows planned sets and presets (wire field `plannedSets` on a slot, the wrist's logging defaults and "Set k of N").
- 36c: a routine started on the watch becomes a routine session on the phone (title, intent, `routineTemplateId`, planned entries and presets from the phone's own current template; the wire carries the routine id).
- The Dart wrist client `lib/watch/**` (Wear OS) is not changed.

## Progress / Assumption Log / Feedback / Open questions

(empty — architect fills the progress table; builders write the Assumption Log and Feedback.)

## Architect expansion (2026-10-14)

### Feature invariants (this plan only; project-wide rules stay in docs/global_conventions.md)

- I-1 A set is logged exactly when a rest exists at its index + 1 (`WorkoutSessionScreen._isSetLogged`, `lib/features/session/workout_session_screen.dart:751`); projection (D-2/D-3) and the fill choice (D-4) read that same rule through rests, never through reps.
- I-2 Imported rows stay indistinguishable from phone-logged rows: `LoggedEntryRows` ids and the entry's `loggedAt` stamp (`docs/watch_session_capture.md:116`); the fill writes through `_createEntry`, never a hand-built row.
- I-3 History import never lands on, moves, edits or deletes a user row (`docs/watch_session_capture.md:87`); only the held merge fills (D-4).
- I-4 Mock and Hive `createObservation` both upsert by id (mock :740, hive :1413), so Mock-first tests see the store behaviour the runtime has.
- I-5 Widget tests run Mock-first; no Hive harness or real `Future.delayed` inside `testWidgets`.

### Existing-functionality impact

| Touched surface | What already reads it (search run this run) | Effect | Guarded by |
| --- | --- | --- | --- |
| `PhoneEntries.project` gains `loggedNumbers` (D-2) | Production caller: only `watch_session_adoption_bridge.dart` `_entriesFor` (grep `PhoneEntries.project(`). Tests reach it via `projectSession`: 20 matches in 5 files (adoption_bridge ×14, projection ×3, live_refresh_screen, finish, merge wiring). | Every projection test building set rows without rests and expecting them projected goes red until the fixture adds a rest at number+1: projection_test `seedSets` users S-31 (:1148), S-32 (:1220), S-35 (:1258, :1337, :1965, :2135), S-33 (:1408), S-34 (:1447, :1838, :1871), S-37 (:1499), S-38 (:1538), S-39 (:1661), S-40 (:1697), S-59 (:1742), S-60 (:1790), S-31 two-sets (:1934), S-43 (:2209), parity (:2281); S-36 (:1480, empty) unaffected. | S-3601, S-3602 |
| `addEntry` session path | `lib/state/workout/session_core_entry.dart:~212` creates observations only, NO rest (read this run). | Tests that push or project a set logged through `addEntry` need `recordRestStart` in the fixture: auto_push `pushPhoneSet` (:438) and its call sites' assertions; live_refresh S-3510's own writes. | S-3602; Phase A items 6–7 |
| `_placeAroundUserRows` fill (D-4/D-5) | Callers: held merge `_mergeHeld` :349, history :505 and :666. `_EffortRows` (:1273) matches rows by stamp (`indexOf`, `unfinishedPlaceOf`, `holdsUserRows`, `lastIndex`). | Held-merge fixtures where the phone holds rows change from append to fill; history paths unchanged. Merge tests with NO phone rows (S-9 :437, S-10, S-19, S-14, D-17, D-19, S-12, S-13, S-16 :1101, S-320 group) stay appends. S-11 (:574) and S-325 hold phone rows: Open questions 1–2. | S-3604..S-3607, S-3611, S-3612 |
| `_applyRests` (D-6) | Merge D-210 group (S-320 ×3, S-325, S-338, S-337, S-328) — closed-rest-wins; `_isSetLogged` reads rests at index+1. | New: an OPEN rest at the index is closed by the wrist's `rest`; closed rests and the existing-rest skip are unchanged. | S-3608, S-3613, S-3614 |
| Rest cache refresh (D-7) | `refreshEfforts` (`lib/state/workout/session_core_io.dart:218`) already calls `setEntryRests(await getEntryRests)`; `refreshHeldEfforts` (bridge :175) reaches it; `_resyncExercisesFromState` (screen :517) fills no `_loggedSetKeys` and leaves `_currentSet` alone (read this run). | No production change expected; the screen shows the wrist set LOGGED from the imported rest. | S-3610, S-3617 |
| Docs | `docs/watch_session_sync.md` rows :24, :64, :328, :377 + "What does not sync". `docs/watch_session_capture.md` does NOT state the phone sends all set rows (grepped "set row\|all its\|logged\|rest" this run) → untouched. | Phase D only. | — |

### Edge scenarios (after S-3611)

- S-3612 Wrist set for a slot with NO rows (fixture: F's effort with zero rows): appends at 0 as today, rest at 1. D-4's "no group without a rest" falls through to `next++`. Guard: existing S-9 (`test/watch_session_merge_test.dart:437`) stays green.
- S-3613 The wrist's `rest` arrives BEFORE its set (`afterEntryId` names no placed entry): dropped as today (`_applyRests` `placed == null` continue, D-215/S-323). Guard: existing S-323/S-328 in the D-210 group.
- S-3614 The phone's own CLOSED rest already sits at index+1 when the wrist's `rest` arrives: left alone (phone's rest wins, D-216). Guard: existing S-325.
- S-3615 Redelivery: the same wrist set delivered twice after it was applied is acknowledged, not re-imported ("Why applied rows are kept", capture doc); the fill runs once. Guard: existing receipt assertions (`test/watch_session_finish_test.dart:392` S-4 `receiptedEntryIds`).
- S-3616 Skipped planned row mid-slot: F with row 0 reps 0 and no rest (skipped), rows 1–2 planned; the wrist's set FILLS row 0 (first group with no rest at number+1 — a skipped row is not logged), rest at 1. Fails without D-4 (appends at 3). Guard: new test, Phase B item 7.
- S-3617 (report only) The phone's `_currentSet` after a wrist set: `_resyncExercisesFromState` (screen :517) changes neither `_currentSet` nor the detail index; the user stays on their set and the label re-reads ("Set 2 of 4", S-3514). No code change planned; Phase C asserts it.

### Phases

Phase A — `crew-builder-app` — Write scope (`--scope`): `lib/core/utils/entry_rows.dart,lib/core/sync_protocol/phone_entries.dart,lib/state/watch/watch_session_adoption_bridge.dart,test/watch_session_projection_test.dart,test/watch_session_auto_push_test.dart,test/watch_session_adoption_bridge_test.dart,test/watch_session_finish_test.dart`
1. [ ] Add `loggedSetNumbers(List<EntryRest>)` next to `setGroups` — lib/core/utils/entry_rows.dart · `EntryRows` (D-1)
2. [ ] Add required `loggedNumbers` and skip unlogged groups — lib/core/sync_protocol/phone_entries.dart · `PhoneEntries.project` (D-2)
3. [ ] Read rests and pass `loggedNumbers` in the setKind case — lib/state/watch/watch_session_adoption_bridge.dart · `_entriesFor` (D-3)
4. [ ] S-3601/S-3602/S-3603 red at base, then green — test/watch_session_projection_test.dart · new S-36xx group
5. [ ] Add rests to every fixture that expects projected sets (list in the impact table) — test/watch_session_projection_test.dart · `seedSets` :274, `stageImportedSet`, `phoneSets` :1130
6. [ ] Add `recordRestStart` after every `addEntry` whose set a projection must show — test/watch_session_auto_push_test.dart · `pushPhoneSet` :438
7. [ ] Same for the bridge and finish fixtures — test/watch_session_adoption_bridge_test.dart · `_seedPhoneSession` :246; test/watch_session_finish_test.dart · `_set` :258
Done Criteria: gateway `flutter analyze` issue count ≤ the Progress baseline; `flutter test test/watch_session_projection_test.dart test/watch_session_auto_push_test.dart test/watch_session_adoption_bridge_test.dart test/watch_session_finish_test.dart` green (900 s timeout).
Predicted Files: exactly the Write scope.

Phase B — `crew-builder-app` — Write scope: `lib/core/services/watch_session_importer.dart,test/watch_session_merge_test.dart,test/watch_session_rest_timer_append_test.dart`
1. [ ] `fillPlanned` named param; only the held-merge call :349 passes true — lib/core/services/watch_session_importer.dart · `_placeAroundUserRows` :757 (D-4)
2. [ ] Fill: first group with no rest at number+1; delete its rows; `_createEntry` at that index; record `_placed` — lib/core/services/watch_session_importer.dart · `_placeAroundUserRows`/`_createEntry` :937 (D-5)
3. [ ] Open rest on import; close an open rest on the wrist's `rest` — lib/core/services/watch_session_importer.dart · `_applyRests` :~835 (D-6)
4. [ ] S-3604..S-3607 red at base, then green — test/watch_session_merge_test.dart · new S-36xx group (`_phoneRows` :350)
5. [ ] S-3608 close + redelivery — test/watch_session_merge_test.dart · D-210 group
6. [ ] S-3611: S-11's fixture gains rests at 1 and 2 so the wrist set still appends (Open question 1) — test/watch_session_merge_test.dart · S-11 :574
7. [ ] S-3616 skipped-row fill — test/watch_session_merge_test.dart · S-36xx group
8. [ ] Migrate S-110/S-320 fixtures (rests where a set must read logged) — test/watch_session_rest_timer_append_test.dart
Done Criteria: `flutter test test/watch_session_merge_test.dart test/watch_session_rest_timer_append_test.dart` green; S-9, S-10, S-16, S-320, S-325, S-337, S-338 still green.
Predicted Files: exactly the Write scope.

Phase C — `crew-builder-app` — Write scope: `test/watch_routine_round_trip_test.dart,test/watch_live_refresh_screen_test.dart`
1. [ ] New round-trip file: S-3609 fill → project (no echo) → phone logs set 1 → one entry — test/watch_routine_round_trip_test.dart · new
2. [ ] S-3610 screen: wrist set shows LOGGED, rest strip runs, no second row — test/watch_live_refresh_screen_test.dart · S-3514/S-3515 pattern
3. [ ] S-3617: `_currentSet` and detail index unchanged after the merge — test/watch_live_refresh_screen_test.dart · S-3514
Done Criteria: `flutter test test/watch_routine_round_trip_test.dart test/watch_live_refresh_screen_test.dart` green. If S-3610 needs production code, STOP and report to the lead (seed rule).
Predicted Files: exactly the Write scope.

Phase D — `crew-docs-keeper` — Write scope: `docs/watch_session_sync.md,docs/plans/2026-10-14-36-routine-start-sync-plan/2026-10-14-36-routine-start-sync-plan.evidence.md`
1. [ ] Update the `projectSession` structure row (:24), the D-31/D-33/D-34 section (:64), the S-9 merge rows (:328, :377) and "What does not sync" — docs/watch_session_sync.md
2. [ ] Every new behaviour sentence names an existing test (S-36xx) — docs/watch_session_sync.md
3. [ ] Evidence into `.evidence.md` — plan folder
Done Criteria: file < 52 KB; no behaviour sentence without a test name.

Parallelism: A and B in parallel (disjoint write scopes). C waits for both (S-3609 needs B's fill and A's projection rule). D last. Only A or B runs the full suite (seed rule).

### Proof (prover brief input; prove-red at base commit 4b7a002 unless a mutation is named)

- S-3601 red at base: `projectSession` returns 3 entries for F (D-2 absent).
- S-3604 red at base: 4 rows, no rest (D-4/D-5/D-6 absent).
- S-3608 red at base: no rest at index 1 at all (D-6 absent).
- S-3609 red at base: the 3 planned rows are projected, so entries != [] (D-2 absent).
- M1 "skip the restamp": in `_createEntry` (importer :937) write `atMs: at + 1` on the fill path → S-3609 sees the echo `entry-sl-1-0` → proves A5/D-5's stamp rule.
- M2 "append instead of fill": ignore `fillPlanned` in `_placeAroundUserRows` → S-3604 sees 4 rows → proves D-4.
- M3 "do not close the open rest": skip the close branch in `_applyRests` → S-3608 sees `restEndMs == null` → proves D-6.
- M4 "project unlogged sets": ignore `loggedNumbers` in `project` → S-3601 sees 3 entries → proves D-2/D-3.
- M5 "fill a logged row": drop the rest condition from the fill's group choice → S-3607 fills row 0 though the phone logged it → proves I-1 inside D-4.

### Progress

| Item | Status |
| --- | --- |
| Phase A items 1–7 | pending |
| Phase B items 1–8 | pending |
| Phase C items 1–3 | pending |
| Phase D items 1–3 | pending |

Baseline `flutter analyze` issue count: 182 (lead, 2026-10-14, base `4b7a002`).

### Assumption Log

- `EntryRows.loggedSetNumbers` adds an `entryIndex >= 1` guard to D-1's formula: a rest at index 0 follows no set (it would name set -1). Ratified by the reviewer; S-16's fixture rest at index 0 exercises it.
- Phase A's predicted `test/watch_session_adoption_bridge_test.dart` and `test/watch_session_finish_test.dart` needed no change (no set-entry or rest assertions); suite green. Ratified.
- B-fix-1 added S-3618 (the wrist's set closes the phone's older open rest): the seed said "one rest running" (A4) but not how; this is the mechanism.
- S-3515's old control (a wrist set with no rest) cannot arise any more (D-6 always leaves a rest at index + 1), so it was rebuilt on a planned never-logged row. Ratified.

### Feedback

Review: `2026-10-14-36-routine-start-sync-plan.review.md` (APPROVE WITH FIXES, 0 blocker, 1 major, 3 minor).
- [x] Finding 1 (major): history-import claim cited the wrong test; now cites `A-51 a late wrist set is placed after the user’s own set` (`test/watch_session_import_test.dart`).
- [ ] Finding 2 (minor): no test for the replay branch (`unfinishedPlaceOf`) under `fillPlanned` with planned rows present. Recorded as a known gap, not fixed in 36a.
- [ ] Finding 3 (minor): dropping a set leaves the open rest its arrival opened (documented limit, S-337). Needs its own small change later.
- [x] Finding 4 (minor): Assumption Log filled (above).

### Open questions

1. S-11 (`test/watch_session_merge_test.dart:574`): the phone holds rows 0–1 with no rests; under D-4 the held merge would FILL row 0, breaking S-3611's "still appends". The fixture must gain rests at 1 and 2 (Phase B item 6) — a fixture change to a seeded scenario, flagged here.
2. S-325 (phone row 0 + open rest at 1; the wrist's set shares row 0's stamp): expected under D-4 — row 0 is logged (rest at 1), so the fill skips it and the set appends at 1; the rest rule then keeps the phone's own rest (D-216). Phase B item 5 re-verifies; flagged because the stamp match in `_EffortRows.indexOf` could read differently.
3. Claim (b) verdict: Mock `createObservation` upserts (`_observations[observation.id] = observation`, `lib/data/repositories/mock_workout_repository.dart:740-744`); Hive too (`_observationsBox.put`, `lib/data/repositories/hive_workout_repository.dart:1413-1417`). D-5's delete-then-create is not required to avoid a duplicate-id error on either store; kept as seeded (it makes the replace explicit and is harmless).
4. Claim (d) verdict: verified. `stampOf` = earliest `createdAtMs` of the group (`lib/core/sync_protocol/phone_entries.dart:325-333`); `_createEntry` stamps every row with the entry's `loggedAt` (`watch_session_importer.dart:937-975`), so the filled row keeps the wrist's stamp and `claimedBy` still claims it — A5 holds with no extra code, as D-5 says.
5. `docs/watch_session_capture.md` does not state that the phone sends all its set rows (grepped this run) → the seed's "only if" resolves to: Phase D does not touch it.
6. `flutter analyze` baseline: not measured this run; Phase A's Done Criteria needs the lead to record it in Progress first.
