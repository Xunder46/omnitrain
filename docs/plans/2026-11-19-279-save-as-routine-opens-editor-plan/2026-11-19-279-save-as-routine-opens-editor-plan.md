# Plan 279 — Save as Routine opens the routine editor, with the session's blocks

Owner list item 3 (2026-11-19): "Save as routine ignores any blocks the exercises were added to and saves everything into one Main block. When a user clicks Save as Routine, open the routine creation screen populated with the session's details, preserving the blocks and the order; the back button in this case goes back to the session summary instead of the routines list."
Phone only. No wire, watch, storage or schema change.
Base commit: `.work/2026-11-19-279-save-as-routine/base.txt` (the owner's summary change is committed there). Analyze baseline: 176 issues, 0 errors.

## Goal and acceptance

On the session summary (post-workout and historical, from the overflow menu) `Save as Routine` opens the routine editor (the same screen as My Routines > New) already filled in:

- Name: `<Modality> - <date>` as the old sheet suggested; focus modality = the session's modality.
- One routine block per session block, in the order the session screen shows them, each with the session block's name; exercises in the block's order, each with its per-set targets as today.
- Exercises that were not in any block: each run of them between blocks becomes a block named `Main Block` (a second run `Main Block 2`, and so on). A session with no blocks gives one `Main Block`, exactly as today.
- Empty session blocks are left out.

Nothing is saved until the user presses Save in the editor. Back (header arrow, system back, bottom Cancel) goes back to the summary: with no edits it leaves at once; after edits it asks `Unsaved changes` and the text says the summary, not the routines list. Save goes back to the summary too (the summary stays open, Done still finishes the workout). The old name-and-exercise bottom sheet is gone. My Routines > New / Edit are unchanged, including the text of their unsaved-changes dialog.

A session with no exercise at all does not open the editor: a message says `This workout has no exercises to save`.

Acceptance: S-27901..S-27914 green, each guard red without the change; `flutter analyze` at most 176 issues, 0 errors; `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart`, `test/navigation_contract_enforcement_test.dart` green; no new red in the full suite; Docs delta applied.

## Feature invariants

- One persistence dependency: the draft→template conversion builds in-memory rows only; the repository is written once, by `RoutineState.saveRoutine()` (D-27903). `WorkoutRepository` stays the only persistence dependency of state and features.
- `MockWorkoutRepository` and `HiveWorkoutRepository` give identical drafts; every P1 scenario runs on both harnesses (S-27901..S-27906).
- Weights are stored in canonical kg; only the editor renders them in the user's unit through `settingsState` (D-27904).
- Screen-level navigation goes through `OmniNavigator.push` — never `MaterialPageRoute` or `PageRouteBuilder` (`docs/navigation_contract.md`).
- Editor entry from the summary captures a clean baseline, so an untouched editor exits without prompting (D-27903).
- Docs behaviour sentences name an existing test; each docs file stays under 52 KB.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-27901 | `SessionTemplateDraft` gains `blocks: List<SessionTemplateBlock>` (`name`, `exercises`); the flat `exercises` stays as a getter over the blocks so no reader breaks. New `SessionTemplateBlock` in the same file. | `lib/core/models/session_summary.dart` `SessionTemplateDraft`, `SessionTemplateExercise` |
| D-27902 | `SessionSummaryBuilder` builds the blocks: new `buildTemplateDraftBlocks()` next to `buildTemplateDraftExercises()` (the latter keeps its targets logic, which the block builder reuses per effort; do not copy it). It needs the session's `SessionBlock`s and each effort's `blockId`, `blockOrderIndex`, `topLevelOrderIndex`; WorkoutState passes them in. Displayed order = top-level order of blocks and loose efforts together (`topLevelOrderIndex ?? orderIndex`), efforts inside a block by `blockOrderIndex`. | `lib/state/workout/session_summary_builder.dart:214` `buildTemplateDraftExercises`; `lib/state/workout/session_core_entry.dart:800-895` (the order rules); `lib/state/workout/session_core.dart:216` `getSessionBlocks`; `lib/data/models/models.dart` `SessionBlock`, `SegmentEffort` |
| D-27903 | `RoutineState.createRoutineFromSessionDraft(SessionTemplateDraft)`: like `createNewRoutine` it builds the in-memory template, one `TemplateSegment` per draft block (`segmentType 'main'`, the block's name, `orderIndex` = position), `TemplateEffort`s and `TemplateTarget`s, then `captureBaseline()` so an unedited editor has no unsaved changes; it writes nothing (the screen disables autosave; `saveRoutine()` writes). Ids come from the state's `_newId`. | `lib/state/routine/routine_state.dart` `createNewRoutine`, `captureBaseline`, `saveRoutine`, `_newId` |
| D-27904 | `RoutineSetupScreen` gets `final SessionTemplateDraft? fromSessionDraft`. In `_loadRoutine`: if set, call `createRoutineFromSessionDraft` and fill the name from the draft; else today's two branches. The unsaved-changes body text is `You have unsaved edits. Discard them to return to the summary.` when it is set. Back, system back, Cancel and Save already pop one route: because the summary pushes the editor, they return to the summary. | `lib/features/routine/routine_setup_screen.dart` `RoutineSetupScreen`, `_loadRoutine`, `_attemptExit`, `_showUnsavedChangesDialog`, `_saveRoutine` |
| D-27905 | The summary's `case 'save'` now does `OmniNavigator.push` to `RoutineSetupScreen(routineState, workoutState, settingsState, fromSessionDraft)` (never `MaterialPageRoute`). The draft is built from the current `_draftExercises` source at tap time (`workoutState` blocks), so it reflects an edited summary. The editor's own `Routine saved successfully` message is the only message (the summary no longer shows `Routine saved`). | `lib/features/session/session_summary_screen.dart:544` `_openSaveAsRoutineSheet`, ~`:779` menu; `docs/navigation_contract.md` |
| D-27906 | Remove the dead path: `_openSaveAsRoutineSheet` and its sheet UI, `SessionSummaryService.saveRoutineFromDraft` (+ `lib/core/services/session_summary_service.dart` import fallout), and the tests that only exercised them are rewritten or deleted with a line in the evidence file (`test/services_test.dart` group `saveRoutineFromDraft`; `test/save_as_routine_labels_test.dart` S-25801..S-25804; the routine-name-field case in `test/capitalization_defaults_test.dart:267`; the save case in `test/header_standardization_test.dart:755`). Replace with tests for the new flow; keep each deleted guard's intent where it still applies (S-25804 Done still finishes the workout). | scout sheet Q1/Q6; `grep -rn "saveRoutineFromDraft\|_openSaveAsRoutineSheet" lib test` |
| D-27907 | A session whose draft has no exercise: show `OmniMessage` `This workout has no exercises to save` and do not navigate. | owner-confirm default |
| D-27908 | Block naming for loose runs: `Main Block`, `Main Block 2`, ... (owner-confirm default). Session blocks keep their own names even if duplicated. | `session_core_io.dart:360` `populateSessionFromManifest` (names come from `templateSegment.name ?? 'Block n'`) |
| D-27909 | An effort whose `blockId` names no session block counts as loose and joins the surrounding run. Defensive: `deleteSessionBlock` cascade-deletes linked efforts (`workout_repository.dart:433`, `mock_workout_repository.dart:2128`, `hive_workout_repository.dart:2949`), so no live writer produces one today. | grep `deleteSessionBlock` lib/ this run |
| D-27910 | Displayed-order rule mirrors `moveExercise` (`session_core_entry.dart:800-895`): blocks and loose efforts sorted by `topLevelOrderIndex ?? orderIndex`, efforts inside a block by `blockOrderIndex ?? orderIndex`, remaining ties by effort/block `id`. The real writers (`moveExercise`, `populateSessionFromManifest`, `reorderSessionBlocks`) renumber 0..n-1, so ties are legacy-only. | `lib/state/workout/session_core_entry.dart` `moveExercise` |

## Scenarios (core; the architect adds, never removes)

Fixtures are sessions built through the real block API of the harness (`addSessionBlock`, `assignEffortToBlock`) or `populateSessionFromManifest`, never hand-written rows with a block id no writer would produce.

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-27901 | Block `Upper` [Bench Press, Row], block `Legs` [Back Squat] | draft blocks `Upper` [Bench, Row], `Legs` [Squat]; after Save the repository holds 2 segments named `Upper`, `Legs` (`orderIndex` 0,1) with efforts at `orderIndex` 0,1 / 0 | one `Main Block` |
| S-27902 | Only loose exercises [A, B] | one `Main Block` [A, B] (today's result, guarded) | a regression splits or drops the loose run and no test catches it |
| S-27903 | Loose A, block `Upper` [B], loose C (top-level order A, Upper, C) | `Main Block` [A], `Upper` [B], `Main Block 2` [C] | everything lands in one `Main Block` |
| S-27904 | Per-set targets survive: Bench 3 sets (8 x 60 kg, 8 x 60 kg, 6 x 65 kg) | the editor's routine has target rows for set 0..2 with those values (canonical kg) and the editor shows them in the user's unit | targets collapse to one default row |
| S-27905 | An empty session block, and a block holding one exercise | the empty block is left out; a block holding one exercise stays | empty blocks become empty segments |
| S-27906 | Reordered blocks (block `Legs` moved above `Upper` in the session) | routine segments in the moved order | segments come in creation order, not the order the session shows |
| S-27907 | Editor opened from the summary | name field = `<Modality> - <date>`, focus modality = session modality, nothing stored (`getTemplates()` unchanged) until Save | the sheet saved on its own button; here asserts no write on open |
| S-27908 | Back with no edits | back on the summary, no dialog, no routine stored | a dirty baseline raises the dialog on a clean editor |
| S-27909 | Back after renaming | `Unsaved changes` dialog whose body says `return to the summary`; Discard → on the summary, nothing stored; Keep editing stays | the dialog text says `routines list`, or no dialog at all |
| S-27910 | Save | editor closes onto the summary, routine stored with the blocks, summary still open; a later Done still ends the workout (the old S-25803/S-25804 intents) | the sheet's save left no block structure; Done broke after the sheet |
| S-27911 | System back gesture (`PopScope`) in the seeded editor | behaves as the header arrow | only the header arrow honours the unsaved-changes guard |
| S-27912 | My Routines > New (no `fromSessionDraft`) | blank `Main Block`, dialog text still `return to the routines list`; Edit unchanged | the new branch leaks into the My Routines entries |
| S-27913 | Historical summary (`openedFromCalendar: true`, session loaded through `loadHistoricalSession`) | opens the editor with its blocks | the block manager holds no blocks for a historical session |
| S-27914 | A session with no exercises | no navigation, message shown | an empty editor opens with no explanation |
| S-27915 | Watch-adopted session (the adoption bridge sets `topLevelOrderIndex`, never `blockId` — `watch_session_adoption_bridge.dart:1584`) | one `Main Block` holding all exercises in `topLevelOrderIndex ?? orderIndex` order | a blockId-only builder yields no blocks for watch sessions |
| S-27916 | Effort whose `blockId` names no session block (synthetic builder fixture; no live writer — see D-27909) | the effort counts as loose and joins the surrounding `Main Block` run | a null block name, or a crash in the mapping |
| S-27917 | Two session blocks both named `Upper` | two segments named `Upper` (names are never de-duplicated, D-27908) | today's code collapses everything to one `Main Block` |

Mock and Hive harness for S-27901..S-27906 and S-27915 (a stored session read back from Hive keeps blocks). S-27916 runs on the Mock harness at the builder level only.

## Input-reality checklist

1. Writers: session blocks are written by `addSessionBlock`/`assignEffortToBlock`/`updateSessionBlock`/`reorderSessionBlocks` (`lib/state/workout/session_core.dart:216-228`), by `populateSessionFromManifest` for a routine start, and by the watch importer (`lib/state/watch/watch_session_adoption_bridge.dart:1584` sets `topLevelOrderIndex`; check whether it ever sets `blockId`); weights are stored in canonical kg.
2. Lifecycle: rolling, imported (watch) and historical sessions are read from the repository (`loadHistoricalSession` sets the block manager from `getSessionBlocks`); an effort whose `blockId` names a deleted block must fall back to loose (state the check and test it); a cloned block gets a new name.
3. Settings: preferred weight unit changes the editor's display only (S-27904); nothing stored changes.
4. Time: `<date>` in the default name is the session's start day (`_formatDate`), not today.
5. Cost: the draft is built once per tap (and still once at summary open for the existing readers); no per-row repository read.
6. Words: stale terms to sweep in `docs/`: `Save as Routine`, `saveRoutineFromDraft`, `buildTemplateDraftExercises`, `Routine saved`, `SessionTemplateDraft` (see Docs delta).
7. Competition: the summary overflow menu keeps its order; `Save as Routine` still sits where it is.

Answers verified in code this run:

1. Writers — verified: `addSessionBlock`/`assignEffortToBlock`/`updateSessionBlock`/`reorderSessionBlocks` delegate to `SessionBlockManager` (`lib/state/workout/session_core.dart:216-228`); `populateSessionFromManifest` creates one `SessionBlock` per manifest segment with exercises (`session_core_io.dart:360`); the watch adoption bridge sets `topLevelOrderIndex` and **never sets `blockId`** (grep over `watch_session_adoption_bridge.dart`: only `topLevelOrderIndex: orderIndex` at :1584) → a watch session is one loose run (S-27915). Weights are stored in canonical kg.
2. Lifecycle — `loadHistoricalSession` restores the block manager from `getSessionBlocks` (`session_core_io.dart:~113`), so historical sessions keep their blocks (S-27913). Orphan `blockId` cannot be produced by a live writer: `deleteSessionBlock` cascade-deletes linked efforts in both repositories and the block manager (`workout_repository.dart:433`, `mock_workout_repository.dart:2128`, `hive_workout_repository.dart:2949`, `session_block_manager.dart:115`) — S-27916 is defensive. A cloned block gets a fresh id and a new name via `cloneSessionBlock`; nothing in the draft reads block ids, only names and order.
3. Settings — preferred weight unit changes the editor's display only (`RoutineSetupScreen._fromCanonicalWeight`/`_toCanonicalWeight`, `routine_setup_screen.dart`); nothing stored changes (S-27904).
4. Time — `<date>` is the session's `startedAtMs` day formatted as `_formatDate` (`session_summary_screen.dart:1429`, e.g. `Nov 19`), not today (S-27907). No week/midnight/clock-change sensitivity: the draft carries no clock-derived value besides the name.
5. Cost — the draft is built once per tap (`buildTemplateDraftBlocks`); the seed's "still once at summary open for the existing readers" no longer holds: `_draftExercises` has exactly one reader, the removed sheet (grep: `session_summary_screen.dart:111,145,280,553`), so P3a deletes the field and the entry-time build (see Open questions).
6. Words — stale-term sweep over `docs/` (excluding `docs/plans`, `docs/history`, `docs/releases`) run this run: hits in `session_summary.md` (:15, :418, :455, :494, :519-527), `data_models.md` (:363), `state_management/services_and_utils.md` (:70), `state_management/workout_state.md` (:198), `navigation_and_screens.md` (:150, :194), `widget_catalog/session_widgets.md` (:654), `README.md` (:64), `docs-audit-2026-07-26.md` (:88). Rows below cover every hit whose sentence the change makes false; `README.md` :64 and `navigation_and_screens.md` :194 use `save-as-routine` as the feature name and stay true; `docs-audit-2026-07-26.md` is a dated audit snapshot (see Open questions).
7. Competition — the overflow menu order is untouched (`session_summary_screen.dart:794-800`); only the `save` case body changes. No other menu entry wants the same slot.

## Existing-functionality impact

| Touched surface | What already reads it (searched this run) | Effect | Guarded by |
|---|---|---|---|
| `SessionTemplateDraft` constructor gains required `blocks` | `session_summary_screen.dart:711` (deleted in P3a), `session_summary_service.dart:333` (method deleted in P3a), `test/services_test.dart:1786,1845,1866` (group deleted in P3a) | every construction site is deleted or rewritten inside this PR — no external reader breaks | D-27901, S-27901; P3a Done |
| `buildTemplateDraftExercises()` (kept) | `session_core.dart:238`, `workout_state.dart:200`, `session_summary_screen.dart:145,280` (call sites deleted in P3a); tests: `state_test.dart` (9 uses, :1984-2346), `session_summary_distance_test.dart:957` | behaviour unchanged; the flat getter must stay byte-equal, so the block builder reuses the extracted target logic instead of copying it | D-27902; P1 Done re-runs both test files |
| `saveRoutineFromDraft` (removed) | lib caller: only `session_summary_screen.dart:720`; tests: `services_test.dart` group :1781 | method + group deleted; no lib reader remains (grep `saveRoutineFromDraft` lib test this run) | D-27906, S-27910 |
| `RoutineSetupScreen` constructor (additive param) | `my_routines_screen.dart:140,153`; 18 test files construct it: `routine_back_to_exercise`, `crown_control_tap_to_edit`, `routine_detail_screen`, `screen_widget`, `interaction_flow`, `header_standardization`, `timed_emphasis_redesign`, `empty_routine_cannot_cost_the_running_workout`, `save_failure`, `pr2_launch_quality_hotfix`, `resistance_emphasis_redesign`, `move_exercise_to_block`, `exercise_detail_emphasis_tier`, `tap_hint_learned`, `capitalization_defaults`, `tap_to_edit_unification`, `sports_emphasis_redesign`, `routine_unsaved_changes_guard` (all `test/*.dart`) | optional `fromSessionDraft` — the null branch keeps today's two branches verbatim | D-27904, S-27912; P2 Done re-runs the guard tests |
| Summary overflow menu `case 'save'` | 37 test files construct `SessionSummaryScreen`; only 3 tap `Save as Routine`: `save_as_routine_labels_test.dart`, `header_standardization_test.dart:755`, `capitalization_defaults_test.dart:267` | the 3 files are deleted/rewritten in P3a; the other 34 never tap `save` | D-27906; P3a/P3b Done |
| `OmniNavigator.push` contract | `test/navigation_contract_enforcement_test.dart` (walks `lib/`, flags `MaterialPageRoute(`/`PageRouteBuilder(`) | the new push uses `OmniNavigator.push` — no route object constructed outside `lib/core/navigation/` | D-27905; P3b Done runs the contract test |

## Readers of shared contracts

Every reader of a symbol or literal this plan adds or changes (grep by symbol AND literal, lib + test, this run). Each sits in the named phase's scope.

| Contract | lib readers | test readers | Phase |
|---|---|---|---|
| `SessionTemplateBlock` (new), `SessionTemplateDraft.blocks` | `session_summary_builder.dart`, `session_summary_screen.dart` (P3a), `routine_state.dart`, `session_summary_service.dart` (until P3a deletes the method) | `save_as_routine_blocks_test.dart` (P1), `services_test.dart:1786,1845,1866` (deleted P3a), `save_as_routine_flow_test.dart` (P3b) | P1, P2, P3 |
| `buildTemplateDraftBlocks` (new) | `session_summary_builder.dart`, `session_core.dart`, `workout_state.dart`, `session_summary_screen.dart` (P3a) | `save_as_routine_blocks_test.dart`, `save_as_routine_flow_test.dart` | P1, P3 |
| `buildTemplateDraftExercises` (kept) | `session_core.dart:238`, `workout_state.dart:200`, `session_summary_screen.dart:145,280` (call sites deleted P3a) | `state_test.dart`, `session_summary_distance_test.dart:957` | P1 pins it, P3a removes the screen call sites |
| `createRoutineFromSessionDraft` (new) | `routine_state.dart`, `routine_setup_screen.dart` (`_loadRoutine`) | `save_as_routine_blocks_test.dart`, `routine_setup_from_session_test.dart` | P1, P2 |
| `fromSessionDraft` (new screen param) | `routine_setup_screen.dart`, `session_summary_screen.dart` (P3a) | `routine_setup_from_session_test.dart`, `save_as_routine_flow_test.dart` | P2, P3 |
| `_openSaveAsRoutineSheet`, `_draftExercises` (removed) | `session_summary_screen.dart:544,111,145,280,553` — no other reader | the 3 sheet test files | P3a |
| `saveRoutineFromDraft` (removed) | `session_summary_service.dart:332`, `session_summary_screen.dart:720` | `services_test.dart:1781` group | P3a |

## Phases (serial; `crew-builder-app`)

- **P1 draft and routine state** (scope `lib/core/models/session_summary.dart`, `lib/state/workout/session_summary_builder.dart`, `lib/state/workout/workout_state.dart` and the one file that exposes blocks to the builder, `lib/state/routine/routine_state.dart`, `test/save_as_routine_blocks_test.dart`): D-27901..D-27903; S-27901..S-27906. Mock and Hive.
- **P2 editor screen** (scope `lib/features/routine/routine_setup_screen.dart`, `test/routine_setup_from_session_test.dart`): D-27904; S-27907..S-27909, S-27911, S-27912.
- **P3 summary wiring and removal** (scope `lib/features/session/session_summary_screen.dart`, `lib/core/services/session_summary_service.dart`, the tests named in D-27906, `test/save_as_routine_flow_test.dart`): D-27905..D-27907; S-27910, S-27913, S-27914. A screen-test file with design latitude ends `no_write`: give the production edit as exact text in P3a and the new test file as P3b.
- **P4 docs** (`crew-docs-keeper`): the Docs delta table.

Expanded phases (the seeded outline above stays as written; each expanded phase is one agent run; no phase runs in parallel — P2 needs P1's state method, P3 needs P2's screen param, P4 records what P1-P3 shipped).

### P1 — draft and routine state (owner `crew-builder-app`)

- Write scope: `lib/core/models/session_summary.dart`, `lib/state/workout/session_summary_builder.dart`, `lib/state/workout/session_core.dart`, `lib/state/workout/workout_state.dart`, `lib/state/routine/routine_state.dart`, `test/save_as_routine_blocks_test.dart`
- Predicted files: exactly the write scope.
- Tests added: `test/save_as_routine_blocks_test.dart` — Mock group S-27901..S-27906, S-27915, S-27917; Hive group of the same fixtures.
- Items:
  1. [ ] Add `SessionTemplateBlock` (`name`, `exercises`) and give `SessionTemplateDraft` a `blocks` field, with the flat `exercises` as a getter over the blocks — `lib/core/models/session_summary.dart` · `SessionTemplateDraft`, `SessionTemplateBlock` (new)
  2. [ ] Extract the per-effort target logic into a private helper both builders call; `buildTemplateDraftExercises` keeps its exact behaviour — `lib/state/workout/session_summary_builder.dart` · `buildTemplateDraftExercises`, `_targetsForEffort` (new)
  3. [ ] Add `buildTemplateDraftBlocks(session, blocks)` (D-27902, D-27908, D-27910): blocks and loose efforts in top-level order, efforts inside a block by `blockOrderIndex`, loose runs named `Main Block`, `Main Block 2`, ...; default name `'<Modality> - <Mon d>'` from the session's start day (same format as `session_summary_screen.dart` `_formatDate`) — `lib/state/workout/session_summary_builder.dart` · `buildTemplateDraftBlocks` (new)
  4. [ ] Expose it over the current session and `_blockManager.getSessionBlocks()` — `lib/state/workout/session_core.dart` · `SessionCore.buildTemplateDraftBlocks` (new)
  5. [ ] Pass it through — `lib/state/workout/workout_state.dart` · `WorkoutState.buildTemplateDraftBlocks` (new)
  6. [ ] Add `createRoutineFromSessionDraft(SessionTemplateDraft)` (D-27903): one `TemplateSegment` per draft block (`segmentType 'main'`, block name, `orderIndex` = position), `TemplateEffort`/`TemplateTarget` ids from `_newId`, then `captureBaseline()` and no autosave scheduling — `lib/state/routine/routine_state.dart` · `createRoutineFromSessionDraft` (new)
  7. [ ] Mock group: S-27901..S-27906, S-27915, S-27917 fixtures built through `addSessionBlock`/`assignEffortToBlock` (S-27915 through the adoption shape: `topLevelOrderIndex` only, no `blockId`) — `test/save_as_routine_blocks_test.dart` · new
  8. [ ] Hive group: the same fixtures stored and read back through `loadHistoricalSession`, drafts identical to Mock — `test/save_as_routine_blocks_test.dart` · new (Hive seeded in `setUp`, never opened inside `testWidgets`)
- Done criteria: `gateway.sh test -- test/save_as_routine_blocks_test.dart test/state_test.dart test/session_summary_distance_test.dart` — 0 failures (the two existing files pin the untouched flat getter).
- Guard proofs: `gateway.sh prove-red 8ec6f42 test -- test/save_as_routine_blocks_test.dart` — red at the base commit (no `SessionTemplateBlock`, no `buildTemplateDraftBlocks`). S-27902 is a pinned regression: the lead's mutation is reordering one loose pair inside `buildTemplateDraftBlocks` only — S-27902 goes red, S-27901 stays green.

### P2 — editor screen (owner `crew-builder-app`; after P1)

- Write scope: `lib/features/routine/routine_setup_screen.dart`, `test/routine_setup_from_session_test.dart`
- Predicted files: exactly the write scope.
- Tests added: `test/routine_setup_from_session_test.dart` — S-27907, S-27908, S-27909, S-27911, S-27912 (Mock-first).
- Items:
  1. [ ] Add `final SessionTemplateDraft? fromSessionDraft` — `lib/features/routine/routine_setup_screen.dart` · `RoutineSetupScreen`
  2. [ ] `_loadRoutine` third branch (D-27904): when set, call `createRoutineFromSessionDraft`, fill `_nameController` with `draft.name` and `_selectedFocusModality` with `draft.focusModality`; the two existing branches stay verbatim — `lib/features/routine/routine_setup_screen.dart` · `_loadRoutine`
  3. [ ] `_showUnsavedChangesDialog` body `You have unsaved edits. Discard them to return to the summary.` when `fromSessionDraft != null`, else today's text — `lib/features/routine/routine_setup_screen.dart` · `_showUnsavedChangesDialog`
  4. [ ] Tests S-27907..S-27909, S-27911, S-27912 (S-27912 asserts the no-draft branch: blank `Main Block`, dialog body still `return to the routines list`) — `test/routine_setup_from_session_test.dart` · new
- Done criteria: `gateway.sh test -- test/routine_setup_from_session_test.dart test/routine_unsaved_changes_guard_test.dart test/routine_detail_screen_test.dart` — 0 failures.
- Guard proofs: `gateway.sh prove-red 8ec6f42 test -- test/routine_setup_from_session_test.dart` — red at the base commit (no `fromSessionDraft` param → compile red). S-27912 cannot be red (it pins an unchanged path); its guard is the existing routine-guard tests staying green plus the new file's no-draft case.

### P3a — summary wiring and removal, production edit (owner `crew-builder-app`; after P2)

- Write scope: `lib/features/session/session_summary_screen.dart`, `lib/core/services/session_summary_service.dart`, `test/services_test.dart`, `test/save_as_routine_labels_test.dart`, `test/header_standardization_test.dart`, `test/capitalization_defaults_test.dart`
- Predicted files: exactly the write scope.
- The production edit is given as exact text (the screen-test file in P3b ends `no_write` for this part):

```dart
case 'save':
  _openRoutineEditorFromSession();
  break;
```

```dart
void _openRoutineEditorFromSession() {
  final session = widget.workoutState.currentSession;
  if (session == null) return;
  final draft = widget.workoutState.buildTemplateDraftBlocks();
  if (draft.exercises.isEmpty) {
    OmniMessage.show(context, 'This workout has no exercises to save');
    return;
  }
  OmniNavigator.push(
    context,
    (_) => RoutineSetupScreen(
      routineState: widget.routineState,
      workoutState: widget.workoutState,
      settingsState: widget.settingsState,
      fromSessionDraft: draft,
    ),
  );
}
```

- Items:
  1. [ ] Replace the `case 'save'` body with the exact text above — `lib/features/session/session_summary_screen.dart` · the `build` switch (~`:769`)
  2. [ ] Add `_openRoutineEditorFromSession()` with the exact text above — `lib/features/session/session_summary_screen.dart` · new method
  3. [ ] Delete `_openSaveAsRoutineSheet` and its sheet UI — `lib/features/session/session_summary_screen.dart` · `_openSaveAsRoutineSheet` (~`:544-746`)
  4. [ ] Delete `_draftExercises` and its two build calls; drop imports that become unused — `lib/features/session/session_summary_screen.dart` · `_draftExercises` (`:111`, `:145`, `:280`)
  5. [ ] Delete `saveRoutineFromDraft` and any import fallout — `lib/core/services/session_summary_service.dart` · `SessionSummaryService.saveRoutineFromDraft`
  6. [ ] Delete the `saveRoutineFromDraft` group and its three `SessionTemplateDraft` constructions — `test/services_test.dart` · group at `:1781`
  7. [ ] Delete or rewrite the sheet-only cases with one line each in the evidence file: S-25801/S-25802/S-25803 in `test/save_as_routine_labels_test.dart`, the case at `test/header_standardization_test.dart:755`, the case at `test/capitalization_defaults_test.dart:267` (S-25804's intent moves to P3b) — those test files
- Done criteria: `gateway.sh test -- test/services_test.dart test/save_as_routine_labels_test.dart test/header_standardization_test.dart test/capitalization_defaults_test.dart` — 0 failures; `gateway.sh lint` — at most 176 issues, 0 errors (baseline from the brief).
- Guard proofs: the deleted files are not guards; the new behaviour's guard is P3b's file (red at base).

### P3b — new flow test (owner `crew-builder-app`; after P3a)

- Write scope: `test/save_as_routine_flow_test.dart`
- Predicted files: exactly the write scope.
- Tests added: S-27910, S-27913, S-27914 (Mock harness; Mock-first widget tests).
- Items:
  1. [ ] S-27910: tap `Save as Routine` → editor opens pre-filled; Save → back on the summary, routine stored with its blocks, then a later Done ends the workout and leaves (the old S-25803/S-25804 intents) — `test/save_as_routine_flow_test.dart` · new
  2. [ ] S-27913: historical summary (`openedFromCalendar: true`, session loaded through `loadHistoricalSession`) opens the editor with its blocks — `test/save_as_routine_flow_test.dart` · new
  3. [ ] S-27914: a session with no exercises shows `This workout has no exercises to save` and does not navigate — `test/save_as_routine_flow_test.dart` · new
- Done criteria: `gateway.sh test -- test/save_as_routine_flow_test.dart test/navigation_contract_enforcement_test.dart test/ui_standards_contract_test.dart` — 0 failures.
- Guard proofs: `gateway.sh prove-red 8ec6f42 test -- test/save_as_routine_flow_test.dart` — red at the base commit (the sheet opens instead of the editor; the no-exercise message does not exist).

### P4 — docs (owner `crew-docs-keeper`; after P3)

- Write scope: the docs files named in the Docs delta table.
- Predicted files: exactly those docs.
- Tests added: none; verified by `gateway.sh test -- test/docs_indexing_contract_test.dart`.
- Items: part a = Docs delta rows 1-7, part b = rows 8-14 (each item is one row's change).
- Done criteria: `gateway.sh test -- test/docs_indexing_contract_test.dart` — 0 failures.
- Guard proof: `test/docs_indexing_contract_test.dart` pins that each doc sentence names an existing test — the reworded sentences carry the tests this plan adds.

## Docs delta (seed rows; the architect completes it from the stale-term sweep)

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/session_summary.md` | MODIFIED | `The draft is editable — name, exercise order,` | `Save as Routine opens the routine editor` | D-27904, S-27907 |
| `docs/session_summary.md` | MODIFIED | `keeps the summary open with a `Routine saved` message (plan 258,` | `returns to the summary` | S-27910 |
| `docs/session_summary.md` | REMOVED | `The Save button is the shared primary bottom action (`OmniBottomCTA`), and the sheet's surface runs to` | `-` | D-27906 |
| `docs/session_summary.md` | REMOVED | `- saveRoutineFromDraft` | `-` | D-27906 |
| `docs/state_management/services_and_utils.md` | REMOVED | `saveRoutineFromDraft(draft, {focusModality})` | `-` | D-27906 |
| `docs/state_management/workout_state.md` | MODIFIED | `Returns `List<SessionTemplateExercise>` for save-as-routine` | `buildTemplateDraftBlocks()` | D-27902, S-27901 |
| `docs/data_models.md` | MODIFIED | `Draft for save-as-routine` | `SessionTemplateBlock` | D-27901 |
| `docs/my_routines.md` | ADDED | - | `The editor can open pre-filled from a finished session` | D-27904 |
| `docs/navigation_and_screens.md` | ADDED | - | `Save as Routine opens RoutineSetupScreen` | D-27905, S-27910 |
| `docs/session_summary.md` | REMOVED | `2. buildTemplateDraftExercises from WorkoutState` | `-` | D-27906 |
| `docs/session_summary.md` | MODIFIED | `additions and removals — before it is persisted through `saveRoutineFromDraft`. Each exercise line` | `The editor's Save persists the routine; until then nothing is written` | D-27904, S-27907 |
| `docs/navigation_and_screens.md` | MODIFIED | `RoutineSetupScreen`, and the save-as-routine sheet on `SessionSummaryScreen`; it returns the` | `RoutineSetupScreen`; it returns the` | D-27906 |
| `docs/widget_catalog/session_widgets.md` | MODIFIED | `RoutineSetupScreen`, and the save-as-routine sheet on` | `RoutineSetupScreen` | D-27906 |

## Open items for the owner

1. Defaults taken: loose runs are named `Main Block` / `Main Block 2` (D-27908); a workout with no exercise shows a message instead of an empty editor (D-27907); the summary no longer shows its own `Routine saved` message (the editor's `Routine saved successfully` is the one message).

## Progress

One line per item, all unchecked at handoff.

- [x] P1.1 `SessionTemplateBlock` + `SessionTemplateDraft.blocks` with flat `exercises` getter — `lib/core/models/session_summary.dart`
- [x] P1.2 extract `_targetsForEffort` — `lib/state/workout/session_summary_builder.dart`
- [x] P1.3 `buildTemplateDraftBlocks(session, blocks)` — `lib/state/workout/session_summary_builder.dart`
- [x] P1.4 `SessionCore.buildTemplateDraftBlocks` — `lib/state/workout/session_core.dart`
- [x] P1.5 `WorkoutState.buildTemplateDraftBlocks` — `lib/state/workout/workout_state.dart`
- [x] P1.6 `createRoutineFromSessionDraft` — `lib/state/routine/routine_state.dart`
- [x] P1.7 Mock group S-27901..S-27906, S-27915, S-27917 — `test/save_as_routine_blocks_test.dart`
- [x] P1.8 Hive group, same fixtures read back — `test/save_as_routine_blocks_test.dart`
- [x] P2.1 `fromSessionDraft` param — `lib/features/routine/routine_setup_screen.dart`
- [x] P2.2 `_loadRoutine` third branch — `lib/features/routine/routine_setup_screen.dart`
- [x] P2.3 `_showUnsavedChangesDialog` summary body — `lib/features/routine/routine_setup_screen.dart`
- [x] P2.4 S-27907..S-27909, S-27911, S-27912 — `test/routine_setup_from_session_test.dart`
- [x] P3a.1 `case 'save'` exact text — `lib/features/session/session_summary_screen.dart`
- [x] P3a.2 `_openRoutineEditorFromSession()` exact text — `lib/features/session/session_summary_screen.dart`
- [x] P3a.3 delete `_openSaveAsRoutineSheet` — `lib/features/session/session_summary_screen.dart`
- [x] P3a.4 delete `_draftExercises` — `lib/features/session/session_summary_screen.dart`
- [x] P3a.5 delete `saveRoutineFromDraft` — `lib/core/services/session_summary_service.dart`
- [x] P3a.6 delete `saveRoutineFromDraft` test group — `test/services_test.dart`
- [x] P3a.7 delete/rewrite the 3 sheet test files, evidence lines — those test files
- [x] P3b.1 S-27910 — `test/save_as_routine_flow_test.dart`
- [x] P3b.2 S-27913 — `test/save_as_routine_flow_test.dart`
- [x] P3b.3 S-27914 — `test/save_as_routine_flow_test.dart`
- [x] P4a Docs delta rows 1-7 — `docs/session_summary.md`, `docs/state_management/*`, `docs/data_models.md`
- [x] P4b Docs delta rows 8-14 — `docs/my_routines.md`, `docs/navigation_and_screens.md`, `docs/widget_catalog/session_widgets.md`, `docs/session_summary.md`

## Assumption Log

| ID | Assumption | Resolution |
|---|---|---|
| A-1 | S-27916 (an effort whose `blockId` names no session block) uses a synthetic fixture: no live writer produces it (`deleteSessionBlock` cascade-deletes linked efforts). | Recorded; guard kept |
| A-2 | `_openRoutineEditorFromSession` tests `blocks.isEmpty` instead of `draft.exercises.isEmpty` (equivalent: the builder never emits an empty block). | Ratified by the review |

(Empty at handoff. Entries of at most 3 lines each; detail goes to the evidence file.)

## Feedback

None yet. Review findings go to `docs/plans/2026-11-19-279-save-as-routine-opens-editor-plan/2026-11-19-279-save-as-routine-opens-editor-plan.review.md`; this section holds only a pointer to it and the fix checklist. The evidence file path is `docs/plans/2026-11-19-279-save-as-routine-opens-editor-plan/2026-11-19-279-save-as-routine-opens-editor-plan.evidence.md` (both created by the governor, not by this planning run).

## PR scope budget check

- Hard limits: plan stays under 800 lines; 4 implementation phases (P1, P2, P3a/P3b as one phase split for the `no_write` rule, P4); one track (phone only); 10 ledger decisions; 17 scenarios. Under budget — no split needed.

## Open questions

1. The seed's Input-reality 5 says the draft is "still once at summary open for the existing readers" — code shows `_draftExercises` has exactly one reader, the sheet this plan removes (`session_summary_screen.dart:111,145,280,553`; grep this run). P3a therefore deletes the field and the entry-time build, and `docs/session_summary.md:418` loses its list item (new REMOVED Docs delta row). The seeded D-27905 wording is kept; the build simply happens at tap.
2. `docs/docs-audit-2026-07-26.md:88` says `SessionSummaryScreen → ExercisePickerScreen (from inside the save-as-routine sheet)`. It is a dated point-in-time audit snapshot, not a behaviour doc; editing it would falsify the record of what the audit found. No Docs delta row was added; the owner may prefer deleting or annotating the line.
3. S-27916's orphan `blockId` cannot be produced by a live writer (`deleteSessionBlock` cascade-deletes linked efforts — `workout_repository.dart:433`, `mock_workout_repository.dart:2128`, `hive_workout_repository.dart:2949`). The guard is kept (D-27909) and tested with a synthetic builder fixture; the implementer records that in the Assumption Log at build time.
4. The editor's own `_attemptExit`/`_showUnsavedChangesDialog`/`_saveRoutine` already pop exactly one route, so pushing the editor over the summary returns to the summary in both the post-workout and historical flows (verified `routine_setup_screen.dart` `_saveRoutine`, `_attemptExit`; scout Q4). No navigation code beyond the push is planned; if the historical flow's back stack differs in a widget test, that surfaces as a P3b finding.
5. `SessionTemplateDraft.blocks` is a required constructor field; all construction sites are inside this PR's phases (Impact table). If the builder reveals a caller the greps missed, the compile error lands in the phase that owns the file.
