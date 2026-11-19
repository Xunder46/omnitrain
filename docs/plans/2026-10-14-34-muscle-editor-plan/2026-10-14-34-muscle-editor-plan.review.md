# Review: 2026-10-14-34-muscle-editor · phases A–E · 52ede35..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 6 · tests: 4636 passed / 1 skipped / 0 failed (`02:52 +4636 ~1: All tests passed!`, full `gateway.sh test`, this run)
Diff vs Predicted Files: conforms, with two brief-sanctioned notes: `docs/design_system.md` is not in Predicted Files E but the review brief explicitly asks to check its edits are limited to two places (verified: exactly two hunks — the OmniCardHeader table row for the exercise editor, and the unsaved-guard paragraph naming S-8); `docs/widget_catalog/session_widgets.md` is the catalog part page E3 points to via `docs/widget_catalog.md`. Untouched areas confirmed empty: `git-diff --stat -- lib/data lib/mock lib/watch watch scripts` printed nothing. No allowlist or ratchet changes (`test/ui_standards_contract_test.dart`, `test/helpers/ui_standards_allowlist.dart` absent from the diff).

## Findings
1. [Minor] lib/features/exercise/exercise_editor_screen.dart:377 and :609 — the two exit paths disagree while a save is in flight. `canPop: !_isDirty || _isSaving` lets the system back gesture pop silently during a save, while the header back (`onBack: () => _attemptExit()`) opens the unsaved-changes dialog because `_isDirty` is still true; and in that dialog, Discard pops the screen while the write still completes (the exercise is saved despite the "discard" label; no work is lost, but the label lies). Fix: make `_attemptExit` return early when `_isSaving`, or gate the dialog on `!_isSaving`. Guard: a test in the S-8 group that starts a gated save (S-14 Completer pattern), taps header back, and asserts no dialog appears.
2. [Minor] lib/features/exercise/exercise_editor_screen.dart:117-121 with lib/state/workout/exercise_library.dart:327-336 — if `getExerciseMuscleLinks` throws, the state catches, returns `[]` and only sets `state.error`, which the editor never surfaces; edit mode then opens with an empty picker and a Save would wipe the stored links. Requires a repository read failure, so nothing is lost in the normal path. Fix: in `_loadReferenceData`, when the returned list is empty but `workoutState.error != null`, show the load-failure message and keep the picker disabled, or route into the existing load-error path. Guard: a state test that makes the repo throw and asserts the editor shows the failure (S-5 group).
3. [Minor] test/muscle_editor_screen_test.dart (S-6 group) — the grid test pins cell count, geometry and the CAPABILITIES header, but not which modality label sits in which cell, so a reordering of `_modalityOptions` would pass. `_modalityOptions` is unchanged in this diff, so this is a latent gap only. Fix: assert `find.text('Arms')` sits before `find.text('Back')` in the grid (or pin the first cell's widget). Guard: one line in the existing S-6 test.
4. [Minor] lib/widgets/exercise/muscle_picker.dart (chips) — D-3 says "chips ≥40 dp tall" but no test asserts a chip height (the picker uses `materialTapTargetSize: MaterialTapTargetSize.padded`, which is not the same guarantee), and `docs/design_system.md` "Accessibility and shape" contains no chip-height rule the plan's citation could point to. Fix: either add a height assertion to the S-3 group and a named rule to design_system.md, or drop the ≥40 dp wording from D-3. Guard: a picker test reading the rendered chip size.
5. [Minor] docs/create_new_exercise.md (persistence-failure sentence) — "A persistence failure leaves the form open with the error surfaced" names no test, though one exists: test/interaction_flow_test.dart · 'a failed save shows plain copy, never the exception text' (asserts 'Could not save the exercise. Try again.'). Fix: cite that test in the sentence.
6. [Minor] docs/state_management/workout_state.md (second table, `getExerciseMuscleLinks` row) — the added row states behaviour with no test citation, while the first table's row for the same method cites S-2. Fix: cite test/muscle_editor_state_test.dart (S-2 group) in the second row too, or merge the rows.

## Assumption Log rulings
Phase A:
1. Non-const `MuscleSelection` constructor — ratify. Behaviour preserved; S-1 tests pin the copy and the model API.
2. `idsWith` sorts by role then orderIndex — ratify. S-1 tests pin the resulting order; matches `MuscleTaxonomy.normalize`.
3. `hashCode` as XOR of role hashes — ratify. Equality/map-key tests in S-1 pin the contract; XOR is the standard pattern for a two-slot set.
4. Load-failure copy 'Failed to load exercise muscle links: …' — ratify. Mirrors the existing `getExerciseMuscleGroups` failure copy; not user-facing (state error only).
5. Extra S-2 coverage (create secondary-only, editCustom round-trip) — ratify. Strengthens the scenario beyond the plan text.

Phase C:
1. Dropdown overflow fix (~5 lines in a file the phase already edits, outside the briefed edit list, reported in the builder report and plan) — ratify. Required for S-6/S-15's `takeException` assertions to pass on narrow test viewports; fix is inside a Predicted File.
2. `setEquals` import in the screen test — ratify. Test-only import needed by the S-13 assertion.
3. S-14 gated with a Completer instead of a bare pump — ratify. Stronger test (prover mutation 18 targets it and died RED).
4. PopScope reached via a local `editor` variable in the test — ratify. Test-only access pattern.
5. `_isDirty` compares raw controller text — ratify. S-13 pins the restore case; whitespace counting as an edit is conservative and cannot lose work.
6. Keys on the form Columns plus a post-frame `ensureVisible` — ratify. S-7 pins the scroll behaviour; keys are the minimal way to target the first error field.
7. `dart format` not run on the tracked editor file (the gateway format check is new-files-only) — ratify with note. The file was hand-formatted; I could not verify formatting mechanically this run (see Open questions).

## Scenario coverage
S-1 → test/muscle_selection_test.dart · group 'S-1 selection model' (14 tests: cycle, covered region, region removal, fromLinks dedupe/primary-wins, single-role invariant)
S-2 → test/muscle_editor_state_test.dart · group 'S-2 state API' (7 tests incl. create secondary-only, editCustom round-trip, failure copy)
S-3 → test/muscle_picker_test.dart · 4 tests (renders groups in taxonomy order, toggle on/off, covered region returns `this`, disabled chip)
S-4 → test/muscle_editor_screen_test.dart · group 'S-4 editor save rules' (3 tests: primary required, assists-only rejected, valid save calls updateCustomExercise with toLinks)
S-5 → test/muscle_editor_screen_test.dart · group 'S-5 edit mode' (loads stored links with roles; save-failure keeps the form dirty)
S-6 → test/muscle_editor_screen_test.dart · group 'S-6 modality grid and headers' (2 tests; see finding 3 for the label-order gap)
S-7 → test/muscle_editor_screen_test.dart · group 'S-7 scroll to the first error'
S-8 → test/muscle_editor_screen_test.dart · group 'S-8 unsaved guard' (4 tests) + group 'S-8 each dirty field asks on its own' (5 tests)
S-9 → test/pr8_exercise_library_test.dart · 'S-9: Edit opens the full editor and saves through it' (detail reloads and pops after save)
S-10 → test/screen_widget_test.dart:3534 · 'CAPABILITIES' header change (prover verdict: PROVEN, RED AT base for the right reason) + existing screen groups green in the full run
S-11 → test/muscle_editor_screen_test.dart · group 'S-11 legacy shape' (Mock half, staged via `putRawExerciseMuscleLinksForTest`; the Hive `List<String>` legacy read is guarded by test/muscle_links_storage_test.dart · 'S-4 reads the legacy shape straight out of the box as primary …', plan 33)
S-12 → test/muscle_picker_test.dart · 'S-12 a group id missing from groups is skipped and still named'
S-13 → test/muscle_editor_screen_test.dart · group 'S-13 dirty tracking' (raw-text compare, restore case)
S-14 → test/muscle_editor_screen_test.dart · group 'S-14 save in flight' (Completer-gated; button disabled, no double write)
S-15 → test/muscle_editor_screen_test.dart · group 'S-15 narrow viewport' (no overflow takeException at the narrow test viewport)

Untested paths noted (no finding, listed for the owner): editing a legacy custom exercise whose modality is null works by code reading (`_isModalityReadOnly` is false when modality is null) but has no test; `_onEdit`'s no-op when the editor returns null is covered only incidentally by S-9's happy path.
