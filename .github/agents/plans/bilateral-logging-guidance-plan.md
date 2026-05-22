# Feature: Bilateral Logging Guidance on Exercise Info Screen

## Overview
Bilateral exercises (e.g., dumbbell curls done one arm at a time) cause logging confusion. The app's convention is to log both sides combined into one set (e.g., 15 lb × 10 reps each arm = logged as 30 lb × 10 reps). This guidance needs to appear on the exercise info sheet for any exercise flagged as bilateral.

## Data Model Gap (Resolved)

`bilateral` is now a defined capability and representative exercises are flagged with it.

Phase 1 filled the previously missing data-model signal so the UI can gate the logging guidance correctly.

## Requirements
- Add `bilateral` as a defined capability constant
- Flag appropriate seed exercises with `bilateral` (e.g., `exercise-dumbbell-curl`, `exercise-dumbbell-row`, `exercise-lateral-raise`, `exercise-rear-delt-fly`, `exercise-hammer-curl`, `exercise-preacher-curl`, `exercise-dumbbell-shoulder-press`, `exercise-seated-dumbbell-shoulder-press`, `exercise-arnold-press`, `exercise-dumbbell-split-squat`, `exercise-single-leg-rdl`, `exercise-step-up`)
- Surface a guidance note in the exercise info sheet **only** for bilateral exercises
- Note must include a concrete example: "15 lb × 10 reps each arm → log as 30 lb × 10 reps"
- Note must match the existing HOW TO PERFORM visual style (section label + content)
- Unit tests: bilateral exercise shows note; non-bilateral exercise does not; model serialization

## Acceptance Criteria
- [ ] `ExerciseCapability.bilateral` constant exists in `lib/core/constants/capability.dart`
- [ ] Schema comment in `scripts/sqlite_schema.sql` documents `bilateral` capability semantics
- [ ] Seed data flags a representative set of bilateral exercises with the `bilateral` capability
- [ ] Exercise info sheet displays a "LOGGING NOTE" section for bilateral exercises with a concrete example
- [ ] Exercise info sheet shows no such section for non-bilateral exercises
- [ ] Unit test: info sheet for bilateral exercise asserts the note widget is present
- [ ] Unit test: info sheet for non-bilateral exercise asserts the note widget is absent
- [ ] Unit test (optional but preferred): model-level round-trip serialization for capabilities including `bilateral`

---

## Implementation Plan

### Phase 1: Data Layer (@dba)

1. [ ] **Add `bilateral` constant** to `lib/core/constants/capability.dart`
   - Add `static const String bilateral = 'bilateral';` alongside existing constants
   - Add to `all` list
   - Add display name: `'Bilateral (Log Both Sides Combined)'`
   - Add description: `'Unilateral exercise done one side at a time; log both sides as a single combined value'`

2. [ ] **Document in SQLite schema** (`scripts/sqlite_schema.sql`)
   - Add a comment in the capability flags section explaining `bilateral` semantics:
     > `bilateral`: exercise is performed one side at a time; log total load × reps-per-side as one set

3. [ ] **Flag bilateral exercises in seed data** (`lib/mock/seed_data.dart`)
   - In `exerciseCapabilityRelationships`, add `'bilateral'` to the capability lists of:
     - `exercise-dumbbell-curl`
     - `exercise-hammer-curl`
     - `exercise-preacher-curl`
     - `exercise-dumbbell-row`
     - `exercise-lateral-raise`
     - `exercise-cable-lateral-raise`
     - `exercise-rear-delt-fly`
     - `exercise-front-raise`
     - `exercise-dumbbell-shoulder-press`
     - `exercise-seated-dumbbell-shoulder-press`
     - `exercise-arnold-press`
     - `exercise-dumbbell-split-squat` (arguably unilateral by design, include if appropriate)
     - `exercise-single-leg-rdl`
     - `exercise-step-up`
   - Use judgment: only include exercises where users hold one dumbbell per hand and alternate sides, not exercises that are inherently bilateral by nature (e.g., barbell curl uses both arms simultaneously, so no flag needed)

### Files Affected (Phase 1)
- `lib/core/constants/capability.dart`
- `scripts/sqlite_schema.sql`
- `lib/mock/seed_data.dart`

---

### Phase 2: UI (@developer)

#### Exercise Info Sheet
**Location**: `_showExerciseInfoSheet` in `lib/features/session/workout_session_global_timer.dart`

The method is an inline `showModalBottomSheet` builder. It currently shows:
1. Drag handle
2. Hero image (optional)
3. Exercise name
4. HOW TO PERFORM section (label + numbered steps) — shown if `hasSteps`
5. Empty state (shown if no image and no steps)

**Change**: Add a "LOGGING NOTE" section **before** the HOW TO PERFORM section (or after the name), shown only when `exercise.capabilities.contains(ExerciseCapability.bilateral)`.

**Visual style** (match HOW TO PERFORM):
```dart
// Section label — same style as 'HOW TO PERFORM'
Text(
  'LOGGING NOTE',
  style: theme.textTheme.labelSmall?.copyWith(
    color: theme.colorScheme.onSurface.withOpacity(0.45),
    letterSpacing: 2.0,
  ),
),
// Body text
Text(
  'This exercise is performed one side at a time. Log both sides as a single combined set. '
  'Example: 15 lb × 10 reps on each arm = log as 30 lb × 10 reps.',
  style: theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurface,
  ),
),
```

The empty state condition must also account for bilateral:
- Change `if (!hasImage && !hasSteps)` → `if (!hasImage && !hasSteps && !isBilateral)`

#### Unit Tests
**File**: new test file `test/exercise_info_sheet_bilateral_test.dart`
(or extend `test/screen_widget_test.dart` if that file already covers the info sheet)

Tests needed:
1. **Bilateral exercise shows note**: render the info sheet with an exercise whose `capabilities` includes `'bilateral'`; assert the `'LOGGING NOTE'` text and the example text are present.
2. **Non-bilateral exercise hides note**: render the info sheet with an exercise without `'bilateral'` in capabilities; assert `'LOGGING NOTE'` is absent.
3. **Model serialization** (if not already covered in `test/models_test.dart`): `Exercise.fromMap`/`toMap` round-trip with `capabilities` containing `'bilateral'`.

### Files Affected (Phase 2)
- `lib/features/session/workout_session_global_timer.dart` (UI change in `_showExerciseInfoSheet`)
- `test/exercise_info_sheet_bilateral_test.dart` (new test file)
- `test/models_test.dart` (add serialization test if not covered)

---

## Scenarios

### Happy Path
- User opens exercise info for Dumbbell Curl (bilateral)
- Info sheet shows: Drag handle → Name → LOGGING NOTE section with example → HOW TO PERFORM steps
- User opens exercise info for Barbell Bench Press (not bilateral)
- Info sheet shows: Drag handle → Hero image → Name → HOW TO PERFORM steps (no logging note)

### Edge Cases
- Exercise has `bilateral` but no `howToSteps`: note shows, empty state does not show
- Exercise has no image, no steps, and is not bilateral: empty state shows ("No information available yet")
- Exercise has no image, no steps, and IS bilateral: note shows, empty state does not show
- Newly created user exercise (no capabilities): no note shown (correct default behavior)

---

## Progress
- [x] Add `ExerciseCapability.bilateral` constant
- [x] Document in SQLite schema
- [x] Flag bilateral exercises in seed data
- [x] Add bilateral logging note UI to exercise info sheet
- [x] Add unit tests

### Phase 1 Status: Complete
### Phase 2 Status: Complete

## Feedback
<!-- Leave empty — specialists add notes here -->
