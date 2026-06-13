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

## User Workflows

### 1. Accessing My Routines
```
HomeScreen → Tap "My Routines" tile (bottom-right, grey)
  → MyRoutinesScreen (list of saved routines)
```

The "My Routines" tile is a **special tile** on the home screen — it is not a modality tile. It navigates to the routine management screen rather than creating a session.

If the user has an active routine session (intent = `'routine'`), tapping the My Routines tile navigates directly to the active `WorkoutSessionScreen` instead.

### 2. Creating a Routine
```
MyRoutinesScreen → Tap FAB (+)
  → RoutineSetupScreen (new routine, no name)
    → Enter routine name
    → Tap (+) to add exercise
      → ExercisePickerDialog (no modality filter)
      → MetricChooserDialog (user picks tracking method)
    → Configure targets (reps, weight, duration, etc.)
    → Add/remove sets per exercise
    → Reorder exercises via drag handles
    → Tap "Save"
  → Returns to MyRoutinesScreen (routine appears in list)
```

### 3. Starting a Routine as a Session
```
MyRoutinesScreen → Tap a routine card
  → System builds session manifest via RoutineSessionService
    → Service queries repository for template + segments + efforts + targets + exercises
    → Returns RoutineSessionManifest (pure data structure)
  → WorkoutState creates new TrainingSession (intent: 'routine')
  → WorkoutState populates session from manifest
    → Pre-populates all exercises, sets, and target values
  → Navigates to WorkoutSessionScreen
  → User tracks workout as normal (log sets, adjust values)
```

If an active session exists, a confirmation dialog appears:
> "Starting a routine will start a new session. Current session will not be saved."

### 4. Editing a Routine
```
MyRoutinesScreen → Tap ⋮ menu on routine card → "Edit"
  → RoutineSetupScreen (pre-loaded with existing data)
    → Modify name, add/remove exercises, adjust targets
    → Tap "Save"
  → Returns to MyRoutinesScreen (updated)
```

### 5. Deleting a Routine
```
MyRoutinesScreen → Tap ⋮ menu on routine card → "Delete"
  → Confirmation dialog: "This action cannot be undone."
  → Confirm → Routine removed from list
```

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

#### Model Fields

**WorkoutTemplate**
| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `ownerUserId` | `String?` | Future: user ownership |
| `name` | `String` | Routine name (e.g., "Push Day") |
| `primaryDisciplineId` | `String?` | Optional discipline filter |
| `note` | `String?` | Optional notes |
| `createdAtMs` | `int` | Timestamp |
| `updatedAtMs` | `int` | Timestamp |

**TemplateEffort**
| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `templateSegmentId` | `String` | Parent segment |
| `orderIndex` | `int` | Display order (supports reordering) |
| `effortKind` | `String` | `set`, `timed`, `round`, or `drill` |
| `modality` | `String?` | Optional modality context |
| `exerciseId` | `String?` | References Exercise |
| `note` | `String?` | Optional notes |
| `createdAtMs` | `int` | Timestamp |

**TemplateTarget**
| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `templateEffortId` | `String` | Parent effort |
| `metricId` | `String` | e.g., `metric-reps`, `metric-weight`, `metric-duration` |
| `setIndex` | `int?` | Which set (0-based) |
| `unitId` | `String?` | e.g., `unit-kg`, `unit-seconds` |
| `targetMin` | `double?` | Used for weight values |
| `targetMax` | `double?` | Range targets (unused currently) |
| `targetInt` | `int?` | Used for reps, duration (seconds) |
| `targetText` | `String?` | Text-based targets (unused currently) |
| `createdAtMs` | `int` | Timestamp |

### Database Schema (SQLite)

```sql
app_workout_template
  ├── app_template_segment     (FK: template_id)
  │     └── app_template_effort  (FK: template_segment_id, exercise_id)
  │           └── app_template_target (FK: template_effort_id, metric_id, unit_id)
```

Foreign key cascade: deleting a template cascades through segments → efforts → targets.

Additionally, `app_plan_day_template` is a join table for future training plan scheduling.

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
  - Tap card → starts routine as session
  - ⋮ menu → Edit or Delete
- **FAB**: (+) button to create a new routine
- **Active session indicator**: If current session is a routine session (`intent == 'routine'`), the My Routines home tile glows active

### RoutineSetupScreen (`lib/features/routine/routine_setup_screen.dart`)

Dual-view screen for building/editing a routine.

#### List View (default)
- **Routine name field**: `TextField` at the top
- **Exercise list**: `ReorderableListView.builder` with drag handles
  - Each `ExerciseCard` shows: drag handle, exercise name, tracking label (e.g., "Track by Reps & Sets")
  - ⋮ menu: "Change Tracking" or "Remove"
  - Tap card → opens detail view for that exercise
- **Add button**: (+) in bottom-right corner
- **Bottom actions**: Cancel / Save buttons

#### Detail View (per-exercise)
- Navigated to by tapping an exercise card in list view
- Shows: exercise name, tracking label chip, metric editors, previous-set stats, set progress, and navigation controls
- **Metric editors**: Same `InlineMetricEditor` widget used in live sessions
  - `set` → Reps + Weight scrollers
  - `timed` → Extra Weight scroller only when the effort carries an extra-weight target; no duration editor is shown in routine setup
  - `round` → Round counter + Duration scroller
  - `drill` → Extra Weight scroller only; no hold-time editor is shown in routine setup
- Weight labels respect the active `SettingsState` unit preference when available
- **Set navigation**: Previous Set / Next Set arrows, set dots indicator
- **Set management**: inline controls now flank the centered progress label
  - remove-set button on the left
  - `Set/Interval/Round/Hold X of Y` label in the middle
  - add-set button on the right
- Remove-set is only enabled on the final entry when more than one set exists; add-set is capped by `WorkoutConstants.maxEntriesPerEffort`
- **Previous set stats**: Shows last set's values for reference (e.g., "Previous: 10 reps @ 135.0 lbs")
- **Swipe gestures**:
  - Horizontal: Navigate between sets
  - Vertical: Navigate between exercises

This detail view was intentionally brought into closer parity with the live `WorkoutSessionScreen` so routine editing and live execution share the same mental model.

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

Unlike modality-driven sessions, routines always show the `MetricChooserDialog` (since routines have no modality preset):

1. Tap (+) → `ExercisePickerDialog` (no modality filter, all exercises shown)
2. Select exercise → `MetricChooserDialog` (user picks tracking method based on exercise capabilities)
3. Returns `effortKind` derived from `ModalityConfig.effortKindFromMetric(chosenMetric)`
4. Exercise added to routine with chosen tracking type

---

## Home Screen Integration

The "My Routines" tile is positioned in the bottom-right of the home screen grid (row 3, column 2):

| Row | Column 1 | Column 2 |
|-----|----------|----------|
| 1 | Cardio / Endurance | Resistance / Lifting |
| 2 | Sports | Isometric / Stretching |
| 3 | Free Training | **My Routines** |

### Tile Configuration
```dart
HomeTileConfig(
  key: 'my_routines',
  label: 'My Routines',
  iconData: Icons.folder_open,
  gradientColors: [Color(0xFF252525), Color(0xFF1C1C1C)],  // Neutral grey
  accentColor: Color(0xFF9E9E9E),
  modality: null,  // Special tile, not a workout modality
)
```

### Active State Detection
The My Routines tile glows active when the current session's `intent == 'routine'` (regardless of what modality any of the exercises may have been mapped to).

### Tap Behavior
- **No active routine session**: Navigate to `MyRoutinesScreen`
- **Active routine session**: Navigate directly to `WorkoutSessionScreen` (resume tracking)

---

## Key Design Decisions

### 1. Routines Are Modality-Agnostic
**Decision**: Routines do not have a preset modality. Each exercise in a routine independently chooses its tracking type via the metric chooser.

**Rationale**: A single routine may mix tracking types (e.g., "Circuit Day" with timed cardio + rep-based strength + hold-based stretching). Forcing a modality would limit flexibility.

### 2. Single Segment Per Routine
**Decision**: Each routine gets one `TemplateSegment` of type `'mixed'`.

**Rationale**: Segment grouping (e.g., "Warm-up", "Main Set", "Cool-down") is deferred to a future version. MVP prioritizes getting exercises into routines quickly.

### 3. Session Intent = 'routine'
**Decision**: Sessions created from routines carry `intent: 'routine'` to distinguish them from ad-hoc sessions.

**Rationale**: Enables the home screen to correctly highlight the My Routines tile when a routine session is active, rather than highlighting a modality tile.

### 4. Metric Chooser Always Shown
**Decision**: The metric chooser dialog always appears when adding exercises to a routine (unlike modality sessions where the tracking method is auto-determined).

**Rationale**: Without a modality context, the system cannot infer the tracking method. The user must explicitly choose.

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

## Future Enhancements

### Phase 2

1. **Routine duplication**: Clone an existing routine to create a variation
2. **Segment grouping**: Split routine into Warm-up / Main / Cool-down segments
3. **Routine categories/tags**: Organize routines by type (Push, Pull, Legs, etc.)
4. **Last-used values**: Display what the user actually lifted last time vs. what the target says
5. **Routine scheduling**: Assign routines to days of the week via training plans (`app_plan_day_template`)

### Phase 3

1. **Shared routines**: Export/import routines between users
2. **Coach-assigned routines**: Coaches create routines for athletes
3. **Progressive overload suggestions**: Auto-suggest target increases based on history
4. **Routine analytics**: Track completion rate and adherence per routine

---

## Related Documentation

- [App Philosophy](app_philosophy.md) — Core design principles and entity model
- [Modality Tracking](modality_tracking.md) — Modality-aware workout tracking system
- [Modality-Based Exercise UI](modality_based_exercise_ui.md) — Adaptive workout session screen
- [Design System](design_system.md) — Visual identity and component patterns
- [DB Integration](db_integration.md) — Database setup and validation

---

## Architecture Evolution

### Phase 1: Service Layer Decoupling (Feb 15, 2026)

**Problem**: `RoutineState` directly imported and orchestrated `WorkoutState` methods, creating tight coupling that made testing difficult and violated separation of concerns.

**Solution**: Introduced `RoutineSessionService` as an intermediary:
- **RoutineState**: Template CRUD only (no session creation logic)
- **RoutineSessionService**: Template → manifest conversion (pure business logic)
- **WorkoutState**: Manifest → session population (session management only)
- **UI**: Orchestrates service + state (explicit flow)

**Benefits**:
- ✅ Clean separation of concerns (templates vs. sessions)
- ✅ Improved testability (no state mocking required)
- ✅ Web/native compatibility (service uses repository interface)
- ✅ Reusable manifest structures (can be used for APIs, exports, etc.)

---

**Document Version**: 1.1
**Last Updated**: February 15, 2026
**Author**: Automated documentation generated from codebase analysis
