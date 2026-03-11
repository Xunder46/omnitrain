# Data Models Reference

## Overview

All domain models live in `lib/data/models/models.dart` as pure Dart classes (no Flutter imports). Models follow these conventions:
- Immutable fields (`final`)
- `fromMap()` factory constructor for deserialization
- `toMap()` method for serialization
- No business logic (logic lives in state classes or extensions)

---

## Core Session Models

These models represent the runtime workout tracking hierarchy:

```
TrainingSession
 └─ SessionSegment
     └─ SegmentEffort (one per exercise in the segment)
         ├─ EffortObservation (for set/timed/drill efforts)
         └─ RoundInstance (for round efforts only)
```

### TrainingSession

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `title` | `String?` | Session name (e.g., "Morning Lift") |
| `modality` | `String?` | e.g., `cardio_endurance`, `resistance_lifting`, `null` (Free Training) |
| `intent` | `String?` | Session purpose: `routine`, or intent constants like `strength`, `hypertrophy` |
| `startedAtMs` | `int` | Epoch milliseconds when session began |
| `endedAtMs` | `int?` | Epoch ms when session ended (`null` while active) |
| `note` | `String?` | User-added session note |
| `routineTemplateId` | `String?` | Links to source `WorkoutTemplate` if started from a routine |

### SessionSegment

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `sessionId` | `String` | Parent session |
| `segmentType` | `String` | Block type (e.g., `mixed`) |
| `orderIndex` | `int` | Display ordering |

### SegmentEffort

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `segmentId` | `String` | Parent segment |
| `exerciseId` | `String?` | References `Exercise` |
| `effortKind` | `String` | `set`, `timed`, `round`, or `drill` |
| `modality` | `String?` | Optional modality context |
| `orderIndex` | `int` | Display ordering |
| `note` | `String?` | Per-exercise note |

### EffortObservation

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `effortId` | `String` | Parent effort |
| `metricId` | `String` | e.g., `metric-reps`, `metric-weight`, `metric-duration` |
| `entryIndex` | `int` | Which set/interval (0-based) |
| `valueReal` | `double?` | Decimal value (weight, distance) |
| `valueInt` | `int?` | Integer value (reps, duration seconds) |
| `valueText` | `String?` | Text value |
| `unitId` | `String?` | Unit reference (e.g., `unit-kg`) |
| `recordedAtMs` | `int` | Timestamp |

### RoundInstance

| Field | Type | Description |
|-------|------|-------------|
| `effortId` | `String` | Parent effort |
| `roundIndex` | `int` | 0-based position (ordering) |
| `plannedDurationSecs` | `int` | Target round length (default: 180) |
| `actualDurationSecs` | `int` | How long round actually ran (capped) |
| `state` | `RoundState` | Current lifecycle state |
| `startedAtMs` | `int` | Wall-clock epoch ms when started (0 = not started) |
| `pausedAtMs` | `int?` | Epoch ms of most recent pause |
| `totalPausedDurationMs` | `int` | Cumulative pause time |
| `finishedAtMs` | `int` | Epoch ms when round ended (0 = not finished) |
| `completed` | `bool` | `true` only when ended via natural countdown |

**Computed getters:**
- `elapsedMs` — derived from timestamps; 0 for notStarted; frozen when paused
- `remainingMs` — `(plannedDurationSecs * 1000 - elapsedMs).clamp(0, planned)`

**RoundState enum:** `notStarted` → `active` ⇄ `paused` → `finished` (terminal)

---

## Exercise & Taxonomy Models

### Exercise

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | Display name |
| `description` | `String?` | Optional description |
| `disciplineId` | `String?` | FK to `Discipline` |
| `isCustom` | `bool` | User-created vs seed data |
| `isArchived` | `bool` | Soft-delete flag |
| `capabilities` | `List<String>` | Capability flags (populated at query time, not stored on model) |
| `relevanceScore` | `double?` | Transient field for ranked sorting |

**Extension methods** (in `lib/core/utils/exercise_helpers.dart`):
- `supports(String capability)` — single capability check
- `supportsAny(List<String>)` — any-of check
- `copyWith({...})` — full copy constructor including `relevanceScore`

### Discipline

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | e.g., "Running", "Boxing" |
| `categoryId` | `String?` | FK to `SportCategory` |

### SportCategory

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | e.g., `category-cardio`, `category-martial-arts` |
| `name` | `String` | Display name |

### MuscleGroup

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | e.g., "Quads", "Chest" |
| `bodyRegion` | `String?` | Grouping (upper/lower/core) |

### Equipment

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | e.g., "Barbell", "Dumbbell" |

### Tag

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | Freeform tag |

### ExerciseAlias

| Field | Type | Description |
|-------|------|-------------|
| `exerciseId` | `String` | FK to Exercise |
| `alias` | `String` | Alternative name for search matching |

---

## Measurement Models

### MetricDefinition

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | e.g., `metric-reps`, `metric-weight` |
| `name` | `String` | Display name |
| `dataType` | `String` | `int`, `real`, `text` |
| `defaultUnitId` | `String?` | FK to `UnitModel` |

### UnitModel

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | e.g., `unit-kg`, `unit-seconds` |
| `name` | `String` | Display name |
| `abbreviation` | `String` | Short form (e.g., "kg", "s") |
| `metricId` | `String?` | Which metric this unit belongs to |

### MetricApplicability

Junction model mapping which metrics apply to which effort kinds.

| Field | Type | Description |
|-------|------|-------------|
| `metricId` | `String` | FK to MetricDefinition |
| `effortKind` | `String` | `set`, `timed`, `round`, `drill` |
| `isRequired` | `bool` | Whether the metric is mandatory for this effort kind |
| `displayOrder` | `int` | Rendering order |

---

## Template Models

Used by the My Routines feature for reusable workout templates:

```
WorkoutTemplate (routine)
 └─ TemplateSegment
     └─ TemplateEffort (one per exercise)
         └─ TemplateTarget (one per metric per set)
```

### WorkoutTemplate

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `ownerUserId` | `String?` | Future: user ownership |
| `name` | `String` | Routine name (e.g., "Push Day") |
| `primaryDisciplineId` | `String?` | Optional discipline filter |
| `focusModality` | `String?` | Optional modality hint |
| `note` | `String?` | Optional notes |
| `createdAtMs` | `int` | Timestamp |
| `updatedAtMs` | `int` | Timestamp |

### TemplateSegment

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `templateId` | `String` | Parent template |
| `segmentType` | `String` | Usually `mixed` |
| `orderIndex` | `int` | Display ordering |

### TemplateEffort

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `templateSegmentId` | `String` | Parent segment |
| `orderIndex` | `int` | Display order (supports drag reordering) |
| `effortKind` | `String` | `set`, `timed`, `round`, or `drill` |
| `modality` | `String?` | Optional modality context |
| `exerciseId` | `String?` | FK to Exercise |
| `restSeconds` | `int?` | Rest duration between sets |
| `restType` | `String?` | Rest type classification |
| `note` | `String?` | Optional notes |
| `createdAtMs` | `int` | Timestamp |

### TemplateTarget

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `templateEffortId` | `String` | Parent effort |
| `metricId` | `String` | e.g., `metric-reps`, `metric-weight` |
| `setIndex` | `int?` | Which set (0-based) |
| `unitId` | `String?` | Optional unit |
| `targetMin` | `double?` | Used for weight values |
| `targetMax` | `double?` | Range targets (unused currently) |
| `targetInt` | `int?` | Used for reps, duration (seconds) |
| `targetText` | `String?` | Text-based targets (unused currently) |
| `createdAtMs` | `int` | Timestamp |

---

## Session Summary Models

Used by the post-workout summary screen (not persisted):

| Class | File | Purpose |
|-------|------|---------|
| `SessionSummary` | `lib/core/models/session_summary.dart` | Computed session stats |
| `ExerciseSummary` | same | Per-exercise stats |
| `PRAchievement` | same | New personal records |
| `VolumeComparison` | same | Delta vs previous session |
| `SessionTemplateDraft` | same | Draft for save-as-routine |
| `SessionTemplateExercise` | same | Exercise entry in draft |
| `TemplateTargetDraft` | same | Target entry in draft |

See [Session Summary](session_summary.md) for details.

---

## Relationship Diagram

```
SportCategory ←── Discipline ←── Exercise ──→ MuscleGroup (junction)
                                    │          Exercise ──→ Equipment (junction)
                                    │          Exercise ──→ Tag (junction)
                                    │          Exercise ──→ ExerciseAlias
                                    │          Exercise ──→ Capability (junction table)
                                    ↓
TrainingSession → SessionSegment → SegmentEffort → EffortObservation
                                       │            → RoundInstance (round efforts only)
                                       └──→ Exercise (FK)

WorkoutTemplate → TemplateSegment → TemplateEffort → TemplateTarget
                                       └──→ Exercise (FK)

MetricDefinition ←── UnitModel
       └──→ MetricApplicability (junction to effort kinds)
```

---

## Code References

| Concern | File |
|---------|------|
| All domain models | `lib/data/models/models.dart` |
| Session summary models | `lib/core/models/session_summary.dart` |
| Routine manifest models | `lib/core/models/routine_session_manifest.dart` |
| Exercise extensions | `lib/core/utils/exercise_helpers.dart` |
| SQLite schema | `scripts/sqlite_schema.sql` |

---

## Related Documentation

- [My Routines](my_routines.md) — Template model usage
- [Modality Tracking](modality_tracking.md) — Session/effort creation flow
- [DB Integration](db_integration.md) — Database schema and persistence

---

**Document Version**: 1.0
**Last Updated**: February 28, 2026
