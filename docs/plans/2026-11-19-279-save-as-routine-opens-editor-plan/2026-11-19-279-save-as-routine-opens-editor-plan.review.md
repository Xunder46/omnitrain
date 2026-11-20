# Review: 279 save-as-routine-opens-editor · P1-P4 · 8ec6f42..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 4 · tests: not re-run (brief forbids; lead's counts below)
Diff vs Predicted Files: conforms (all 22 plan files present; every other file in the diff belongs to plans 277/278 per the brief and was ignored)

## Findings

1. [Minor] lib/features/session/session_summary_screen.dart:537-556 — `_openRoutineEditorFromSession` deviates from the plan's exact text (P3a): it checks `blocks.isEmpty` instead of `draft.exercises.isEmpty` and builds the draft only after the guard. Provably equivalent — the builder never emits an empty block (`flushRun` skips empty loose runs; empty session blocks are skipped), so `blocks` is empty iff `exercises` is — but the exact-text rule exists so a later `no_write` phase can rely on the given text. Fix: none needed in code; note the deviation in the evidence file. Guard: S-27914 (`test/save_as_routine_flow_test.dart`) pins the no-exercise branch.
2. [Minor] docs/plans/2026-11-19-279-...evidence.md (P3a section) — P3a.7 promised one evidence line per deleted sheet case, including "the case at `test/header_standardization_test.dart:755`". The evidence names only `save_as_routine_labels_test.dart`; the header file is unmentioned and untouched. Read this run (:724-763): that case only asserts the three menu labels and never taps `Save as Routine`, so leaving it is correct — but a maintainer comparing plan to evidence sees a named case silently skipped. Fix: one evidence line stating the `:755` case stays because it never opens the sheet.
3. [Minor] plan Assumption Log is empty after a complex build, while the plan's Open question 3 promised "the implementer records that [the S-27916 synthetic orphan fixture, no live writer — D-27909] in the Assumption Log at build time". The fact is recorded in the evidence file instead (P1a section). Fix: copy that one entry into the plan's Assumption Log; nothing else changes.
4. [Minor] plan Progress section — all 25 checkboxes unchecked although P1-P3 shipped and P4's rows are applied. Fix: tick them.

## Answers to the brief's five questions

1. Nothing stale survives. Save: `saveRoutine()` (routine_state.dart:337) writes, sets `_isNewRoutine = false` and re-captures the baseline (:357-358), so the next exit is clean; the in-memory template that remains is replaced by whichever loader the next entry runs (`createNewRoutine` clears segments/efforts/targets and rebuilds — My Routines > New starts blank, S-27912; `loadRoutineForEditing` for Edit). Back clean: `_attemptExit` → `clearCurrentRoutine()` → `_clearInMemoryState()` (routine_state.dart:1254-1283) clears everything. Back after edits: dialog → `discardCurrentRoutineAndClearDraft()`, which also clears everything. Guarded by S-27907/S-27908/S-27909/S-27912 and the S-27910 tests.
2. No net stored-row change. Clean exit touches memory only. The edited-discard path runs `_persistDraftForDiscard()` (createTemplate) immediately followed by `deleteTemplate(id)` — a transient write, pre-existing machinery shared with the My Routines > New flow (`_isNewRoutine` is true there too, autosave disabled by the same screen), net effect none; no segments/efforts/targets were ever persisted by the seed, so nothing is orphaned. `createRoutineFromSessionDraft` itself writes nothing (asserted by S-27908a: template ids unchanged, no segments stored).
3. Correct. `loadHistoricalSession` restores `_currentSession` and the block manager from `getSessionBlocks` (session_core_io.dart:56-116), and `_openRoutineEditorFromSession` reads `workoutState.currentSession` + `buildTemplateDraftBlocks()` at tap time, so the calendar-opened summary drafts the historical session's blocks. Guarded by S-27913 (fixture goes through `loadHistoricalSession` and `openedFromCalendar: true`).
4. None. Grep over lib/ and test/ this run: `saveRoutineFromDraft` and `_openSaveAsRoutineSheet` have zero matches; the only lib constructor is the full `blocks:` form (session_summary_screen.dart:547). The `exercises:` shorthand survives in tests only (`test/save_as_routine_blocks_test.dart:811`, pinned by S-27902b).
5. No. The diff adds no widget, button, IconButton or colour literal — only a push, an `OmniMessage`, a text branch and deletions (the deleted sheet was itself the raw-container offender). Deleted imports leave no unused references (analyze 174 issues, 0 errors, baseline 176).

## Checks seen (from the brief, not re-run)

- 40 one-line mutants over this plan's production code: all killed except two named equivalents (`topOf` by orderIndex alone — `createEffort` normalizes orderIndex to topLevelOrderIndex for loose efforts; one cosmetic spacing line).
- New test files: 31 + 7 + 7 = 45 tests green (Mock and Hive for the state file).
- `flutter analyze` 174 issues, 0 errors (baseline 176). ui_standards, navigation-contract and docs-contract tests green at the last run; plan-lint clean.

## Assumption Log rulings

- S-27916 orphan-`blockId` synthetic fixture (no live writer; `deleteSessionBlock` cascade-deletes linked efforts): ratified as recorded — but move it from the evidence file into the plan's Assumption Log (finding 3).
- `topOf`/cosmetic-spacing mutant equivalents: ratified (brief-established, not re-verified).
- Audit snapshot `docs/docs-audit-2026-07-26.md:88` keeps the stale sheet wording: ratified (dated record; plan Open question 2).

## Scenario coverage

S-27901 → test/save_as_routine_blocks_test.dart `S-27901 named session blocks become routine blocks in the session's order` (Mock + Hive; saved through saveRoutine)
S-27902 → blocks test `S-27902 a session with only loose exercises drafts one Main Block` (Mock + Hive)
S-27903 → blocks test `S-27903 loose runs between blocks become Main Block and Main Block 2` (Mock + Hive; tie order pinned by `S-27903b`)
S-27904 → blocks test `S-27904 per-set targets survive into the editor routine` (Mock + Hive)
S-27905 → blocks test `S-27905 an empty session block is left out; a block holding one exercise stays` (Mock + Hive)
S-27906 → blocks test `S-27906 reordered session blocks draft in the moved order` (Mock + Hive; in-block order by `S-27901b`)
S-27907 → test/routine_setup_from_session_test.dart `S-27907 opening shows the draft name and blocks and stores nothing` + flow `S-27907c` ×2 (focus modality)
S-27908 → routine test `S-27908 back with no edits pops without a dialog and stores nothing` + flow `S-27910c`
S-27909 → routine test `S-27909 back after an edit asks, Keep editing stays, Discard pops without storing`
S-27910 → routine test `S-27910 saving stores the routine with its blocks and pops to the host` (+ rename case) + flow `S-27910`, `S-27910b` (Done still ends), `S-27910c`
S-27911 → routine test `S-27911 system back pops a clean editor and asks after an edit`
S-27912 → routine test `S-27912 My Routines entries stay blank and keep the routines-list wording`
S-27913 → flow `S-27913 a historical summary opens the editor with its blocks`
S-27914 → flow `S-27914 a session with no exercise shows a message and opens no editor`
S-27915 → blocks test `S-27915 a watch-adopted session drafts one Main Block` (+ `S-27915b` legacy top/index split, Mock + Hive)
S-27916 → blocks test `S-27916 an effort whose blockId names no session block counts as loose...` (Mock + Hive)
S-27917 → blocks test `S-27917 two session blocks with the same name are never merged or renamed` (Mock + Hive)
No scenario without a test.

## Docs delta

- docs/session_summary.md `The draft is editable...` -> applied (opens the routine editor; names S-27901..S-27905, S-27910, S-27913, S-27914, S-27908, S-27909, S-27911, S-25802 — all seen in the test files this run)
- docs/session_summary.md `Routine saved` message row -> applied (`returns to the summary`; the editor's `Routine saved successfully` is the one message)
- docs/session_summary.md OmniBottomCTA/sheet-surface row -> applied (removed)
- docs/session_summary.md `- saveRoutineFromDraft` row -> applied (removed)
- docs/session_summary.md `2. buildTemplateDraftExercises from WorkoutState` row -> applied (removed, list renumbered)
- docs/session_summary.md `persisted through saveRoutineFromDraft` row -> applied (`The editor's Save persists the routine; until then nothing is written`)
- docs/state_management/services_and_utils.md `saveRoutineFromDraft(draft, {focusModality})` -> applied (row removed)
- docs/state_management/workout_state.md `Returns List<SessionTemplateExercise> for save-as-routine` -> applied (`buildTemplateDraftBlocks()`; the kept flat getter documented, names S-27901..S-27906, S-27915-S-27917, S-1311-S-1315 — all verified present)
- docs/data_models.md `Draft for save-as-routine` -> applied (SessionTemplateBlock wording)
- docs/my_routines.md ADDED pre-filled-editor paragraph -> applied (names S-27901 and S-27910, both exist)
- docs/navigation_and_screens.md ADDED `Save as Routine opens RoutineSetupScreen` -> applied (names S-27910)
- docs/navigation_and_screens.md ExercisePickerScreen pushed-from row -> applied (sheet reference removed)
- docs/widget_catalog/session_widgets.md pushed-from row -> applied (sheet reference removed)
- Doc edits not named by the table: none found in the diff.

## Standards seen, not fixed

None. No allowlist entry added, no ratchet raised, no raw piece introduced by this plan's diff.
