# Exercise Info and Notes Sheets - Feature Documentation

## Overview

WorkoutSessionScreen includes two exercise-scoped bottom sheets in detail mode:

- Exercise Info sheet: read-only reference content (image + ordered how-to steps)
- Exercise Notes sheet: editable notes with debounced auto-save and header indicator

Both features are additive and stay inside the workout session flow. No full-screen navigation is introduced.

---

## User Workflow

```
WorkoutSessionScreen (detail mode)
  -> Header actions
     -> Info icon (i)
        -> Exercise Info bottom sheet
     -> Notes icon (edit)
        -> Exercise Notes bottom sheet
           -> Type note text
           -> 500ms debounce auto-save
           -> Header dot indicator appears when note exists
```

---

## UI Entry Points

### Header actions

In detail mode, the header renders two icon actions:

- `exercise-info-button` -> opens `_showExerciseInfoSheet(...)`
- `exercise-note-button` -> opens `_showExerciseNoteSheet(...)`

The header actions are wrapped in `ListenableBuilder(listenable: workoutState)` so the notes indicator updates reactively after note saves/deletes.

### Notes indicator

When a cached note exists, a small primary-color dot is shown on the note icon:

- key: `exercise-note-indicator`
- condition: `workoutState.hasExerciseNote(exerciseId)`

---

## Detail-Entry Sequencing Guarantee

To prevent stale note-dependent UI on first detail paint, `_focusExerciseDetail(...)` enforces this order:

1. Await `loadExerciseNote(exerciseId)`
2. Verify request is still current (`_focusRequestId` guard)
3. Only then switch to detail mode (`_showListView = false`)

This sequencing ensures the header indicator state is correct the first time detail actions render, including initial-focus restore paths.

---

## Exercise Info Sheet

### Behavior

The info sheet (`_showExerciseInfoSheet`) is a modal bottom sheet with:

- optional hero image (`exercise.imageAssetPath`)
- exercise name
- ordered how-to list (`exercise.howToSteps`)
- empty state: "No information available yet" when no image/steps exist

### Rendering details

- Uses `showModalBottomSheet` with `isScrollControlled: true`
- Transparent modal background and rounded top corners
- Includes drag handle and bottom safe-area padding
- Image load failures are safely ignored with `errorBuilder`

The sheet is display-only and does not mutate state.

---

## Exercise Notes Sheet

### State and lifecycle

`_ExerciseNoteSheet` is a local stateful widget with:

- `TextEditingController` initialized from cached note text
- `_debounce` timer for write throttling
- `_hasUnsavedChanges` flag

On `dispose()`, `_forceSave()` is called so pending edits are flushed before teardown.

### Auto-save strategy

- Typing triggers `_onChanged(...)`
- Existing debounce timer is canceled
- New save is scheduled after 500ms
- Save call: `workoutState.saveExerciseNote(exerciseId, text, sessionId: currentSessionId)`

If text is empty, state layer delete behavior is invoked (upsert/delete semantics handled by `WorkoutState`).

### UX details

- Multiline text field with autofocus
- Character counter appears only when text length > 500 (`len/inf` style)
- Keyboard-safe bottom padding uses `viewInsets.bottom + safeArea + 16`

---

## Data and Persistence Model

### Model

`ExerciseNote` is a pure data model with:

- deterministic id: `note-{exerciseId}`
- `exerciseId`, `note`, optional `lastSessionId`
- `createdAtMs`, `updatedAtMs`

### Repository contract

`WorkoutRepository` exposes:

- `getExerciseNote(exerciseId)`
- `saveExerciseNote(note)`
- `deleteExerciseNote(exerciseId)`

This keeps implementation backend-agnostic for web and native paths.

### State-layer guarantees (`WorkoutState`)

- `loadExerciseNote(exerciseId)`
  - skips when cached
  - dedupes overlapping loads via `_exerciseNoteLoadInFlight`
- `saveExerciseNote(exerciseId, text, sessionId)`
  - serializes overlapping saves per exercise via `_exerciseNoteSaveInFlight`
  - last queued write wins for rapid edits
  - queue entries are session-scoped and cleared by `clearSession()`

---

## Test Coverage

Primary tests:

- `test/exercise_notes_sheet_test.dart`
  - indicator appears/disappears after save and clear
  - adding exercise hydrates existing note into detail header
  - detail entry waits for note load before rendering header actions
  - rapid detail taps keep latest focus target
- `test/workout_state_note_serialization_test.dart`
  - overlapping save queue serialization
  - cache-fast second load after first latency-bound load
  - in-flight load dedupe per exercise id
  - save queue lifecycle behavior with `clearSession()`

---

## Architecture Notes

- No model/schema/repository-interface changes were required for Iteration 5
- Feature is platform-agnostic in shared layers
- Header correctness depends on note cache hydration before detail-mode transition

---

## Related Documentation

- [Modality-Based Exercise UI](modality_based_exercise_ui.md)
- [State Management and Services](state_management.md)
- [Data Models](data_models.md)
- [DB Integration](db_integration.md)

---

**Document Version**: 1.0
**Last Updated**: March 30, 2026
