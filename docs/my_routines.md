# My Routines — Feature Documentation

## Overview

**My Routines** allows users to create, save, edit, and replay reusable workout templates. A routine defines a list of exercises with per-set target values (reps, weight, duration, etc.) that can be loaded into a live workout session with a single tap. This eliminates repetitive setup for recurring training patterns.

### Business Context

#### Problem
Athletes repeat the same workouts regularly (e.g., "Push Day", "5K Intervals", "Boxing Rounds"). Without routines, they must manually add exercises and configure tracking every session — violating the app's ≤10-second-to-start principle.

#### Solution
A **template system** that lets users design a workout once and replay it as many times as needed. When started, the routine pre-populates a live session with all exercises, sets, and target values ready for tracking.

#### Business Value
1. **Faster session starts**: One tap to load a full workout
2. **Consistency**: Same exercises, same targets, every time
3. **Progressive overload**: Edit targets over time (increase weight, add sets)
4. **Cognitive simplicity**: Users don't have to think about setup, just execute

---

## Editing and Deleting

### Editing a Routine

Tapping a routine card body opens `RoutineSetupScreen` without creating a session. The card's play control is the only path that builds the manifest and starts an active session. The card renders no overflow menu; the destructive delete action lives in the editor header.

Header back, system back, and bottom Cancel all funnel through the same
`_attemptExit` guard. The guard compares the working state against the
`RoutineSnapshot` baseline captured at editor entry (or at the last
successful save). Only continue when the routine has been touched — the
fields covered are name, description, focus modality, segments
(add/remove/rename/retype/reorder), efforts per segment
(add/remove/reorder/change tracking/rest), and targets per effort
(per-set metric values, add/remove set). Untouched routines exit
without prompting.

Confirmation copy, layout, and button shapes mirror the completed-session
edit confirmation: title "Unsaved changes", body "You have unsaved
edits. Save them or discard to return to the routines list.", and the
`Discard` / `Save` row uses `OmniTheme.buttonUtilityRadius`. The
header-bar close icon is the "Keep editing" affordance. When detail is
open, system back first returns to the list (same as the AppBar's back
arrow) before the guard engages.

### Deleting a Routine

Deleting a routine removes the template and any `PlannedSession` rows that reference it. **Completed sessions, their `routineTemplateId`, all efforts, observations, rest records, and analytics / PRs are preserved by design** — analytics read from `TrainingSession` and its child rows directly and never join through the template.

Verified by `test/pr6_routine_session_entry_navigation_test.dart` (`S-002 routine delete preserves history`).

---

## Technical Architecture

### Data Model

The routine system uses a **template hierarchy** that mirrors the session hierarchy:

```
WorkoutTemplate (routine)
 └─ TemplateSegment (exercise grouping — typically 1 "mixed" segment per routine)
     └─ TemplateEffort (one per exercise, with effortKind and exerciseId)
         └─ TemplateTarget (one per metric per set — e.g., reps=10, weight=135 for set 0)
              ├─ → MetricDefinition (via metricId)
              └─ → UnitModel (via unitId, optional)
```

#### Template ↔ Session Parallel

| Template Entity | Session Entity | Purpose |
|----------------|----------------|---------|
| `WorkoutTemplate` | `TrainingSession` | Top-level container |
| `TemplateSegment` | `SessionSegment` | Exercise grouping |
| `TemplateEffort` | `SegmentEffort` | Single exercise with tracking type |
| `TemplateTarget` | `EffortObservation` | Per-set metric values |

### Database Schema

The template hierarchy cascades on delete: removing a template removes its segments, their efforts, and those efforts' targets. `app_plan_day_template` is a join table reserved for training-plan scheduling. The canonical schema lives in `scripts/sqlite_schema.sql`.

### State Management

**`RoutineState`** (`lib/state/routine/routine_state.dart`) is the central `ChangeNotifier` for routine template CRUD operations (create, read, update, delete).

**Note**: As of Phase 1 refactoring (Feb 2026), `RoutineState` no longer depends on `WorkoutState`. Session creation is now handled by `RoutineSessionService` and orchestrated by the UI.

#### Key State Fields
| Field | Type | Purpose |
|-------|------|---------|
| `_routines` | `List<WorkoutTemplate>` | All saved routines |
| `_currentTemplate` | `WorkoutTemplate?` | Routine being created/edited |
| `_currentSegment` | `TemplateSegment?` | Active segment (usually one per routine) |
| `_currentEfforts` | `List<TemplateEffort>` | Exercises in current routine |
| `_currentTargets` | `List<TemplateTarget>` | Per-set targets for current routine |

#### Key Methods

| Category | Methods |
|----------|---------|
| **CRUD** | `loadRoutines()`, `createNewRoutine(name)`, `updateRoutineName(name)`, `saveRoutine()`, `deleteRoutine(id)`, `loadRoutineForEditing(id)` |
| **Exercises** | `addExerciseToRoutine(exercise, effortKind)`, `removeExerciseFromRoutine(id)`, `reorderExercises(old, new)`, `updateEffortKind(id, kind)` |
| **Targets** | `setTargetValue(...)`, `getEffortTargets(id)`, `addSetForEffort(id, kind)`, `removeLastSetForEffort(id)` |

**Note**: Session creation (`startRoutineAsSession`) was removed in Phase 1 refactoring (Feb 15, 2026). This responsibility is now handled by `RoutineSessionService` (see Service Layer section below).

### Service Layer

**`RoutineSessionService`** (`lib/core/services/routine_session_service.dart`) orchestrates template-to-session conversion without depending on state classes.

#### Purpose
- **Decouples** `RoutineState` from `WorkoutState`
- Provides **pure business logic** for building session manifests
- Ensures **testability** (no state dependencies)
- Maintains **web compatibility** (uses repository interface only)

#### Key Method

**`buildSessionFromTemplate(String templateId)`**

**Returns**: `Future<RoutineSessionManifest>`

**Flow**:
1. Loads `WorkoutTemplate` from repository
2. Loads all `TemplateSegment` entities for template
3. Loads all `TemplateEffort` entities for each segment
4. Loads all `TemplateTarget` entities for each effort
5. Loads all referenced `Exercise` entities
6. Constructs a `RoutineSessionManifest` containing:
   - The template metadata
   - List of `SessionExerciseEntry` objects (exercise + effort kind + set count + targets)

**Throws**: `Exception` if template not found or has no exercises

#### Manifest Data Structures

**`RoutineSessionManifest`** (`lib/core/models/routine_session_manifest.dart`)

Pure data structure (no logic) for passing template-derived session data:

| Field | Type | Description |
|-------|------|-------------|
| `template` | `WorkoutTemplate` | Source template |
| `exercises` | `List<SessionExerciseEntry>` | Exercise list with targets |

**Helper Methods**:
- `totalExercises` → `int`
- `isEmpty` → `bool`
- `getTargetsForSet(int setIndex)` → `List<TemplateTarget>`

**`SessionExerciseEntry`**

| Field | Type | Description |
|-------|------|-------------|
| `exercise` | `Exercise` | Exercise entity |
| `effortKind` | `String` | Tracking type (`set`, `timed`, etc.) |
| `setCount` | `int` | Number of sets |
| `targets` | `List<TemplateTarget>` | Per-set metric targets |
| `restSeconds` | `int?` | Rest duration |
| `restType` | `String?` | Rest type |

#### Integration Pattern

```dart
// UI orchestrates service + state (no state-to-state coupling)
final manifest = await routineSessionService.buildSessionFromTemplate(templateId);
await workoutState.createNewSession(
  title: manifest.template.name,
  intent: 'routine',
  routineTemplateId: manifest.template.id,
);
await workoutState.loadSessionData();
await workoutState.populateSessionFromManifest(manifest);
```

**WorkoutState.populateSessionFromManifest()**

New method in `WorkoutState` that consumes a `RoutineSessionManifest`:

**Flow**:
1. For each `SessionExerciseEntry` in manifest:
   - Adds exercise to session with explicit `effortKind`
   - Creates additional sets (entries) beyond the first
   - Applies target values from `TemplateTarget` entities
2. Notifies listeners when complete

**Throws**: `Exception` if no active session exists

### Repository Layer

**Interface**: `WorkoutRepository` (`lib/data/repositories/workout_repository.dart`)

Template-related methods:
| Method | Return Type |
|--------|-------------|
| `getTemplates()` | `Future<List<WorkoutTemplate>>` |
| `getTemplateById(id)` | `Future<WorkoutTemplate?>` |
| `createTemplate(template)` | `Future<String>` |
| `updateTemplate(template)` | `Future<void>` |
| `deleteTemplate(id)` | `Future<void>` |
| `getTemplateSegments(templateId)` | `Future<List<TemplateSegment>>` |
| `createTemplateSegment(segment)` | `Future<String>` |
| `getTemplateEfforts(segmentId)` | `Future<List<TemplateEffort>>` |
| `createTemplateEffort(effort)` | `Future<String>` |
| `getTemplateTargets(effortId)` | `Future<List<TemplateTarget>>` |
| `createTemplateTarget(target)` | `Future<String>` |
| `updateTemplateTarget(target)` | `Future<void>` |
| `deleteTemplateTarget(id)` | `Future<void>` |
| `deleteTemplateTargetsForEffort(effortId)` | `Future<void>` |

**Implementation**: `MockWorkoutRepository` — in-memory `Map<String, T>` stores. Delete operations cascade manually.

---

## UI Architecture

### Screen Hierarchy

```
HomeScreen
  └─ MyRoutinesScreen                  (list of saved routines)
       └─ RoutineSetupScreen           (create or edit a routine)
            ├─ List View               (exercise overview + reorder)
            └─ Detail View             (per-exercise, per-set target editing)
```

### MyRoutinesScreen (`lib/features/routine/my_routines_screen.dart`)

- **Empty state**: Circle icon + "No Routines Yet" + "Create your first routine" message
- **List state**: `ListView.builder` with `Card` widgets per routine
  - Each card shows: exercise icon, routine name, creation date (relative: "today", "3 days ago")
  - Built-in demo routines carry a subtle "Demo" badge (via `DemoRoutineBadge`) sourced from `OmniTheme` typography + `colorScheme.primary` tokens. The badge is purely informational; demo rows are still editable, startable, and deletable like user rows.
- **Primary bottom CTA**: `OmniBottomCTA(label: '+ New Routine', ...)` anchored via `Scaffold.bottomNavigationBar` — the shared full-width, safe-area-anchored footer action (see [widget_catalog.md → OmniBottomCTA](widget_catalog.md)). The list's bottom padding uses `OmniTheme.formBottomCTAClearance` so the last routine card clears the CTA. Replaces the legacy `FloatingActionButton` so the routines screen matches the unified bottom-CTA pattern used by the calendar day list, food library, etc.
- **Active session indicator**: If current session is a routine session (`intent == 'routine'`), the My Routines home tile glows active

### Built-in Demo Routines

`MyRoutinesScreen` ships a curated set of built-in demo templates the
first time the app is launched (and on every subsequent launch where the
device's stored catalog version is older than the bundled one). Demos
follow the same versioned refresh pipeline used for bundled exercises
and the food catalog:

- Eight templates covering resistance (Push/Pull/Leg/Dumbbell Arms),
  bodyweight circuit (Bodyweight Circuit), cardio (Easy Run — 30 min),
  sports (Heavy Bag — 5×3), and isometric / mobility (Mobility Flow)
  modalities.
- Demo ids are namespaced under `demo-template-…` so they cannot collide
  with user-created routines (which use `template-{ms}`).
- User edits are respected on refresh — the
  `WorkoutRepository.isSeedEntryTouched(SeedEntryType.routineTemplate,
  demoTemplateId)` tombstone is set whenever the user mutates or
  deletes a demo, and the refresh skips the entry on the next bump.
- Validation at startup (`lib/main.dart::_validateBundledDemoRoutines`)
  and at archive time (`scripts/pre_release_check.sh` →
  `tools/validate_demo_routines.dart`) confirms every demo's exercise
  references resolve to the bundled catalog and that every effort
  carries the targets its kind requires.

### RoutineSetupScreen (`lib/features/routine/routine_setup_screen.dart`)

Dual-view screen for building/editing a routine.

#### List View (default)

Lists the routine's segments and their exercises, supports reordering, and opens the detail view for a chosen exercise. Per-exercise tracking can be overridden here.

#### Detail View (per-exercise)

Edits per-set target values for one exercise using the same `InlineMetricEditor` primitive the live session uses, so routine editing and live execution share one mental model. Which editors appear depends on effort kind: routine setup exposes no duration target for `timed` and no hold-time target for `drill`. Weight labels respect the active `SettingsState` unit preference. Remove-set is enabled only on the final entry when more than one set exists; add-set is capped by `WorkoutConstants.maxEntriesPerEffort`.

#### Smart Defaults for Targets
When adding a set, targets auto-fill from the previous set:
- `set`: Copy reps + weight from previous set
- `timed`: Carry forward extra weight when present; the routine builder does not expose a duration target
- `round`: Copy round duration
- `drill`: Copy extra weight; the routine builder does not expose a hold-time target

When adding a new exercise, default targets depend on effort kind:
- `set`: 10 reps, 0 weight
- `timed`: no visible metric editor unless an extra-weight target is present
- `round`: 180 seconds (3 min), 1 round
- `drill`: 0.0 extra weight

### Exercise Addition Flow (Routine Context)

> **Focus Modality inheritance rule**: when a routine has a Focus Modality,
> new exercises silently inherit it. Changing the focus on a routine with
> already-added exercises does NOT retroactively alter them — only exercises
> added after the change inherit the new focus.

Routines have an optional Focus Modality and do not filter the picker library. When a focus is set, a newly added exercise takes that modality's effort kind directly; when the routine is Mixed (`null`), `ModalityPickerDialog` resolves it. "Change Tracking" remains an explicit per-exercise override in either case.

Changing Focus Modality does not rewrite existing efforts; only exercises added afterward inherit the new value.

---

## Home Screen Integration

The "My Routines" tile is positioned in the bottom-right of the home screen grid (row 3, column 2):

| Row | Column 1 | Column 2 |
|-----|----------|----------|
| 1 | Cardio / Endurance | Resistance / Lifting |
| 2 | Sports | Isometric / Stretching |
| 3 | Free Training | **My Routines** |

### Active State Detection
The My Routines tile glows active when the current session's `intent == 'routine'` (regardless of what modality any of the exercises may have been mapped to).

### Tap Behavior
- **No active routine session**: Navigate to `MyRoutinesScreen`
- **Active routine session**: Navigate directly to `WorkoutSessionScreen` (resume tracking)

---

## Key Design Decisions

### 1. Optional Focus Modality
**Decision**: A routine may set a Focus Modality or remain Mixed (`null`). The picker still shows the full exercise library.

**Rationale**: Focus Modality supplies a low-friction default effort kind for newly added exercises while Mixed routines can choose per exercise. Existing exercises are not retroactively rewritten when focus changes.

### 2. Multiple Segments (Blocks) Per Routine
**Decision**: A routine holds one or more `TemplateSegment` rows, each with a
name and a segment type.

> **Corrected 2026-07-26 (docs audit).** This section previously read *"Single
> Segment Per Routine — each routine gets one `TemplateSegment` of type
> `'mixed'`"*, with the rationale that *"segment grouping (e.g. Warm-up, Main
> Set, Cool-down) is deferred to a future version"*. **That grouping has
> shipped** — and with very nearly the labels the doc used as its example of
> what was deferred.

`RoutineSetupScreen` renders one card per segment, offers an **Add Block**
button (`_addSegment`), lets segments be reordered
(`RoutineState.reorderSegments`), and names an unnamed segment
`Block {index + 1}`. The available segment types are:

| Type | Typical use |
|------|-------------|
| `warmup` | Warm-up |
| `main` | Main set (the default for `RoutineState.addSegment`) |
| `accessory` | Accessory work |
| `finisher` | Finisher |
| `cooldown` | Cool-down |

Source: `_segmentTypes` in `lib/features/routine/routine_setup_screen.dart`
and `RoutineState.addSegment({String? name, String segmentType = 'main'})`.

### 3. Session Intent = 'routine'
**Decision**: Sessions created from routines carry `intent: 'routine'` to distinguish them from ad-hoc sessions.

**Rationale**: Enables the home screen to correctly highlight the My Routines tile when a routine session is active, rather than highlighting a modality tile.

### 4. Focus Default with Per-Exercise Override
**Decision**: Focused routines derive the initial tracking kind without another prompt; Mixed routines ask for a modality. "Change Tracking" can override either result per exercise.

**Rationale**: Preserve quick setup when intent is known without removing mixed-modality routines or explicit correction.

### 5. Copy-From-Previous Set Defaults
**Decision**: New sets auto-fill from the previous set's targets.

**Rationale**: Most exercises use the same weight/duration across sets. Auto-filling reduces configuration effort while still allowing per-set customization.

---

## Code References

| Concern | File |
|---------|------|
| **Service Layer** | |
| Session manifest service | `lib/core/services/routine_session_service.dart` |
| Manifest data models | `lib/core/models/routine_session_manifest.dart` |
| **State Management** | |
| Routine CRUD state | `lib/state/routine/routine_state.dart` |
| Workout session state | `lib/state/workout/workout_state.dart` |
| **UI Screens** | |
| Routine list screen | `lib/features/routine/my_routines_screen.dart` |
| Routine setup screen | `lib/features/routine/routine_setup_screen.dart` |
| Home screen routing | `lib/features/home/home_screen.dart` |
| Home tile config | `lib/core/constants/home_tiles.dart` |
| **Data Layer** | |
| Repository interface | `lib/data/repositories/workout_repository.dart` |
| Hive implementation (current) | `lib/data/repositories/hive_workout_repository.dart` |
| Mock implementation (testing) | `lib/data/repositories/mock_workout_repository.dart` |
| Domain models | `lib/data/models/models.dart` |
| SQLite schema | `scripts/sqlite_schema.sql` |
| **Constants** | |
| Metric IDs | `lib/core/constants/metric_ids.dart` |
| Effort defaults | `lib/core/constants/effort_defaults.dart` |
| Modality config | `lib/core/constants/modality_config.dart` |

---

## Related Documentation

- [App Philosophy](app_philosophy.md) — Core design principles and entity model
- [Modality Tracking](modality_tracking.md) — Modality-aware workout tracking system
- [Modality-Based Exercise UI](modality_based_exercise_ui.md) — Adaptive workout session screen
- [Design System](design_system.md) — Visual identity and component patterns
- [DB Integration](db_integration.md) — Database setup and validation

---

## Architecture Invariant — Template / Session Decoupling

`RoutineState` must not depend on `WorkoutState`. Template CRUD belongs to `RoutineState`; template-to-manifest conversion belongs to `RoutineSessionService`; manifest-to-session population belongs to `WorkoutState`. The UI orchestrates the three. Violating this reintroduces the state-to-state coupling that made routine session creation untestable.

---

**Document Version**: 1.2
**Last Updated**: July 27, 2026
**Author**: Automated documentation generated from codebase analysis


---

> **Doc freshness** — Last reconciled against source: 2026-07-27. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
