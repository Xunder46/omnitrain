# Modality-Aware Workout Tracking

## Business Context

### Problem Statement
The original application was hardcoded for strength training (reps/sets/weight), making it inflexible for athletes across different sports and training modalities. Users could not effectively track running sessions, martial arts rounds, or isometric holds within the same app.

### Solution
A **modality-aware system** where exercises adapt their tracking method based on the workout type. The same exercise (e.g., squats) can be tracked by:
- **Time** in a cardio session (e.g., "3 minutes of air squats")
- **Reps & Sets** in a resistance session (e.g., "3×10 @ 135 lbs")
- **Hold Duration** in an isometric session (e.g., "3×30s wall squat holds")

### Business Value
1. **Universal Appeal**: Single app supports runners, lifters, martial artists, yogis, and sports athletes
2. **Reduced Friction**: No need to switch apps or manually configure tracking methods
3. **Data Integrity**: Exercises maintain consistent identity while adapting presentation
4. **User Retention**: Athletes can track their entire training life in one place

---

## Feature Overview

### Supported Modalities
Five training modalities are available as home screen tiles, covering the full spectrum of athletic training:

1. **Cardio / Endurance** - Continuous time-based activities (running, cycling, swimming)
2. **Resistance / Lifting** - Set-based strength training with reps and load
3. **Sports** - Unified tile covering martial arts and sports. Time + round-based tracking (boxing, MMA, soccer, basketball)
4. **Isometric / Stretching** - Static hold durations (planks, yoga, stretching)
5. **Free Training** (null modality) - User chooses tracking method per exercise

> **Feb 2026**: The previous separate "Martial Arts" and "Sports" tiles were unified into a single "Sports" tile.
> **Apr 2026**: `martial_arts` fully retired — the constant, compat guard, and `category-martial-arts` record were removed. Boxing, BJJ, and Muay Thai disciplines now live under `category-sports`. The `sports` modality maps to `['category-sports']` only.

Additionally, **My Routines** is a special (non-modality) tile on the home screen that navigates to saved workout templates. See [My Routines](my_routines.md) for details.

> Modality accent colors are centralized in `lib/core/constants/modality_colors.dart`. New UI components should import from that file rather than hardcoding modality colors.

### Exercise Capability System
Exercises are tagged with **capabilities** (flags indicating what they can track):
- `time` - Continuous duration
- `hold` - Isometric hold duration
- `reps` - Repetition counting
- `sets` - Set grouping
- `load` - External weight/resistance
- `distance` - Distance covered
- `rounds` - Round/period segments

**Example**: Barbell Squat supports `[reps, sets, load, time]`
- In resistance session → tracked as "3×10 @ 135 lbs"
- In cardio session → tracked as "5:00 continuous squats"

### Effort Kinds
Internal classification for UI rendering:
- **set** - Reps + weight pairs (strength training)
- **timed** - Duration + distance + optional extra weight (cardio; enables loaded carries and weighted cardio)
- **round** - Rounds + round duration (martial arts/sports)
- **drill** - Hold duration + extra weight (isometric/stretching)

---

## Resolving an Effort Kind

A session started from a modality tile resolves its effort kind from
`ModalityConfig` directly. A null-modality session (Free Training, or a routine
without a focus modality) resolves it in two steps: `ModalityPickerDialog` picks
a modality, and only if the user picks "General" does `MetricChooserDialog` ask
for a tracking method. Cancelling adds nothing.

Changing modality while a session is active starts a **new** session rather than
re-mapping the existing one — re-mapping would leave the logged efforts in an
ambiguous state. See [Key Design Decisions](#key-design-decisions).

---

## Technical Architecture

### Data Layer

#### Schema (SQLite)
```sql
CREATE TABLE app_exercise_capability (
  exercise_id TEXT NOT NULL,
  capability TEXT NOT NULL,
  PRIMARY KEY (exercise_id, capability)
);
```

#### Models
```dart
class Exercise {
  final List<String> capabilities; // ['reps', 'sets', 'load', 'time']
  
  bool supports(String capability) => capabilities.contains(capability);
  bool supportsAny(List<String> caps) => caps.any(supports);
}
```

#### Repository Interface
```dart
abstract class WorkoutRepository {
  Future<List<String>> getExerciseCapabilities(String exerciseId);
  Future<void> setExerciseCapabilities(String exerciseId, List<String> capabilities);
  Future<List<Exercise>> getExercisesRankedForModality(
    String? modality,
    {String? searchText, String? disciplineId, List<String>? muscleGroupIds}
  );
}
```

### State Layer

#### Modality Configuration
```dart
class ModalityConfig {
  final String? primaryMetric;     // Main tracking method
  final List<String> secondaryMetrics;  // Additional metrics
  final String effortKind;         // UI rendering mode
  
  static const Map<String?, ModalityConfig> configs = {
    'cardio_endurance': ModalityConfig(
      primaryMetric: 'time',
      secondaryMetrics: ['distance', 'rounds'],
      effortKind: 'timed',
    ),
    'resistance_lifting': ModalityConfig(
      primaryMetric: 'reps',
      secondaryMetrics: ['sets'],
      effortKind: 'set',
    ),
    // ... other modalities
  };
}
```

#### Session State
```dart
class WorkoutState extends ChangeNotifier {
  TrainingSession? _currentSession;
  ModalityConfig? _currentModalityConfig;
  
  Future<void> createNewSession({String? modality}) {
    _currentModalityConfig = ModalityConfig.forModality(modality);
    // Creates session with modality field
  }
  
  Future<String> addExerciseToSession(Exercise exercise, {String? chosenMetric, String? effortKindOverride}) {
    // Determine effort kind:
    // 1. effortKindOverride (set from ModalityPickerDialog for null-modality sessions)
    // 2. _currentModalityConfig.effortKind (set sessions)
    // 3. ModalityConfig.effortKindFromMetric(chosenMetric) (General/Free Training fallback)
    String effortKind;
    if (effortKindOverride != null) {
      effortKind = effortKindOverride;
    } else if (_currentModalityConfig != null) {
      effortKind = _currentModalityConfig!.effortKind;
    } else if (chosenMetric != null) {
      effortKind = ModalityConfig.effortKindFromMetric(chosenMetric);
    }
    // Creates SegmentEffort with appropriate effortKind
  }
  
  Future<void> addEntry(String effortId) {
    // Creates observations based on effort kind:
    // - 'set'   → reps + weight observations
    // - 'timed' → duration + distance + extra-weight observations (3 companions)
    // - 'round' → RoundInstance record (NOT observations — see "Round-Based Tracking" section)
    // - 'drill' → duration + extra weight observations
  }

  // Round duration resolution order in addEntry() for effortKind == 'round':
  //   1. Last round in current effort (inherit user-adjusted duration)
  //   2. previousValues['round-duration'] hint (template/session context)
  //   3. Exercise.defaultRoundDurationSecs (sport-specific default)
  //   4. WorkoutConstants.defaultRoundDurationSecs (global fallback = 180)

  // Round-specific lifecycle methods:
  Future<void> addRound(String effortId, {int plannedDurationSecs = WorkoutConstants.defaultRoundDurationSecs});
  Future<void> startRound(String effortId, int roundIndex);              // notStarted → active
  Future<void> pauseRound(String effortId, int roundIndex);              // active → paused
  Future<void> resumeRound(String effortId, int roundIndex);             // paused → active (folds pause duration)
  Future<void> endRoundEarly(String effortId, int roundIndex);           // active|paused → finished (derives elapsed from timestamps)
  Future<void> completeRound(String effortId, int roundIndex);           // active → finished (completed=true, natural countdown)
  Future<void> updateRoundPlannedDuration(String effortId, int roundIndex, int plannedDurationSecs);
  Future<void> deleteRound(String effortId, int roundIndex);
  Future<List<RoundInstance>> getRoundsForEffort(String effortId);
}
```

### Exercise Defaults for Sports Rounds

`Exercise` now supports an optional `defaultRoundDurationSecs` field (serialized as
`default_round_duration_secs`). This enables sport-specific defaults such as soccer
halves, hockey periods, or rugby halves instead of forcing a universal 3-minute round.

- `null` means: use app-wide fallback (`WorkoutConstants.defaultRoundDurationSecs = 180`).
- Non-null means: use exercise-specific default when creating new round entries.

Important behavior:
- Existing `RoundInstance` rows are not rewritten retroactively.
- New rounds created after this change use the duration resolution order above.

### UI Layer

#### Metric Chooser (Free Training)
```dart
class MetricChooserDialog extends StatelessWidget {
  final Exercise exercise;
  
  Widget build() {
    // Show only capabilities the exercise supports
    return Dialog(
      child: Column(
        children: exercise.capabilities.map((capability) =>
          _MetricOption(
            capability: capability,
            onTap: () => Navigator.pop(context, capability),
          )
        ).toList(),
      ),
    );
  }
}
```

#### Adaptive Session Display
```dart
Widget _buildMetricDisplay(Map<String, dynamic> entry, String effortKind) {
  switch (effortKind) {
    case 'set':
      return Text('${entry['weight']} × ${entry['reps']}');
    case 'timed':
      return Text('${formatDuration(entry['duration'])}');
    case 'round':
      return Text('Round ${entry['rounds']}');
    case 'drill':
      return Text('Hold ${formatDuration(entry['duration'])}');
  }
}
```

---

## Implementation Details

### Constants & Utilities

#### Exercise Capabilities
```dart
class ExerciseCapability {
  static const String time = 'time';
  static const String hold = 'hold';
  static const String reps = 'reps';
  static const String sets = 'sets';
  static const String load = 'load';
  static const String distance = 'distance';
  static const String rounds = 'rounds';
}
```

#### Metric IDs
```dart
class MetricIds {
  static const String reps = 'metric-reps';
  static const String weight = 'metric-weight';
  static const String duration = 'metric-duration';
  static const String distance = 'metric-distance';
  static const String rounds = 'metric-rounds';
  static const String roundDuration = 'metric-round-duration';
  static const String rpe = 'metric-rpe';
  static const String extraWeight = 'metric-extra-weight'; // Drill companion: negative = band assist, positive = added load
}
```

#### Observation Grouper
```dart
class ObservationGrouper {
  static List<Map<String, dynamic>> groupByEffortKind(
    String effortKind,
    List<dynamic> observations,
  ) {
    switch (effortKind) {
      case 'set': return _groupSetObservations(observations);
      case 'timed': return _groupTimedObservations(observations);
      // ⚠ LEGACY (Phase 2 complete): Round efforts now use RoundInstance records.
      // WorkoutState.getExercisesWithEntries() no longer calls this for 'round'.
      // Retained for backward compatibility with any pre-Phase-2 persisted data only.
      case 'round': return _groupRoundObservations(observations);
      case 'drill': return _groupDrillObservations(observations);
    }
  }
}
```

#### WorkoutConstants
```dart
// lib/core/constants/workout_constants.dart
class WorkoutConstants {
  /// Default planned duration for round-based exercises (3 minutes).
  static const int defaultRoundDurationSecs = 180;

  /// Safety cap multiplier for wall-clock round duration.
  /// Actual duration is clamped to plannedDurationSecs * this value
  /// to guard against device sleep, pause-time rounding, and clock skew.
  static const int roundActualDurationCapFactor = 2;
}
```

#### RoundInstance
```dart
// Part of lib/data/models/models.dart
enum RoundState { notStarted, active, paused, finished }

class RoundInstance {
  final String effortId;              // Parent SegmentEffort ID
  final int roundIndex;               // 0-based position (used for ordering)
  final int plannedDurationSecs;      // Target round length (e.g. 180)
  final int actualDurationSecs;       // How long the round actually ran (capped)
  final RoundState state;             // Current lifecycle state (finished is terminal)
  final int startedAtMs;              // Wall-clock epoch ms when timer started (0 = notStarted)
  final int? pausedAtMs;              // Epoch ms of most recent pause (null when not paused)
  final int totalPausedDurationMs;    // Cumulative pause time folded in on each resumeRound
  final int finishedAtMs;             // Wall-clock epoch ms when round ended (0 = not finished)
  final bool completed;               // true only when ended via completeRound (natural countdown)

  // Computed getters
  int get elapsedMs;    // Derived from timestamps; 0 for notStarted; frozen when paused
  int get remainingMs;  // (plannedDurationSecs * 1000 - elapsedMs).clamp(0, planned)
}
```

> **Why wall-clock timestamps?** Round timers use `DateTime.now().millisecondsSinceEpoch` rather than a `Stopwatch`. This makes elapsed time background-resilient: if the app is suspended, the timer continues ticking because elapsed = `now - startedAtMs` instead of depending on Dart's isolate uptime.

### Seed Data Example
40 exercises with hand-curated capabilities:

```dart
static final Map<String, List<String>> exerciseCapabilityRelationships = {
  // Running exercises - continuous time + distance
  'exercise-easy-run': ['time', 'distance'],
  'exercise-interval-run': ['time', 'distance', 'rounds'],
  
  // Strength exercises - reps/sets/load + time (for cardio context)
  'exercise-barbell-squat': ['reps', 'sets', 'load', 'time'],
  'exercise-bench-press': ['reps', 'sets', 'load', 'time'],
  
  // Boxing exercises - time + rounds
  'exercise-heavy-bag-rounds': ['time', 'rounds'],
  'exercise-sparring': ['time', 'rounds'],
  
  // Isometric exercises - hold + time + sets
  'exercise-plank-hold': ['hold', 'time', 'sets'],
  'exercise-wall-sit': ['hold', 'time', 'sets'],
};
```

---

## Web Compatibility Strategy

### Hive Repository (Current — Web/Native)

The current implementation uses `HiveWorkoutRepository` (Hive boxes) for persistence across all platforms. A `MockWorkoutRepository` also exists for in-memory testing.

---

## Key Design Decisions

### 1. Capabilities as Flags (Not Join Table to Modality)
**Decision**: Each exercise has capability flags independent of modalities.

**Rationale**:
- Exercises aren't locked to one modality
- Barbell squats can be used in cardio OR resistance sessions
- User can override tracking method in Free Training
- Avoids combinatorial explosion (40 exercises × 6 modalities = 240 relationships)

### 2. Separate `time` and `hold` Capabilities
**Decision**: Treated as distinct capabilities despite both being duration-based.

**Rationale**:
- Different user intent (continuous movement vs static position)
- Different UI language ("5:00 run" vs "30s plank hold")
- Enables precise exercise recommendations per modality

### 3. Per-Exercise Metric Chooser (Free Training)
**Decision**: In Free Training mode, show chooser for each exercise added.

**Rationale**:
- User may want to track different exercises differently
- Example: "Squats by time" + "Push-ups by reps" in same session
- Matches real training patterns (circuit training, functional fitness)

### 4. Warning on Modality Change
**Decision**: Show dialog when switching modalities with active session.

**Rationale**:
- Prevents accidental data loss
- Changing modality mid-session creates ambiguous data structure
- MVP: Start new session. Future: Prompt to re-map exercises.

### 5. Sports as Segmented Time (Not Custom)
**Decision**: Sports modality uses `time` + `rounds` like martial arts.

**Rationale**:
- Most sports have time-based segments (periods, halves, quarters)
- Avoids premature specialization for specific sports
- Label customization ("Periods" vs "Rounds") handled in UI layer

---

## Anti-Patterns Avoided

### ❌ Exercise-Modality Join Table
Would create rigid 1:N relationship, preventing exercises from appearing in multiple modalities.

### ❌ Hard Filtering Exercises by Modality
Would hide exercises that don't "perfectly" match, frustrating users who want flexibility.

### ❌ Global Metric Choice for Session
Would force all exercises in a session to use same tracking method, breaking circuit training workflows.

### ❌ Modality as Exercise Property
Would require duplicate exercises for different contexts (e.g., "Cardio Squats" vs "Strength Squats").

---

## Testing & Validation

### Acceptance Criteria (All Met)
✅ 5 modality tiles + 1 My Routines tile on home screen (6 total)  
✅ Session created with modality field  
✅ Exercise picker shows relevance-scored sorted list  
✅ Metric chooser appears in Free Training and My Routines  
✅ Adaptive UI displays for all 4 effort kinds  
✅ Warning dialog on modality change with active session  
✅ Zero errors across entire codebase  
✅ Web-compatible (MockWorkoutRepository)  
✅ No platform-specific code in shared layer  

---

## Deployment Notes

### Performance Considerations
- Exercise capability lookups are O(1) map operations
- Ranking algorithm is O(n) where n = filtered exercise count (typically <100)
- No N+1 queries - capabilities loaded with exercises in single repository call
- Observation grouping is O(n) where n = observation count per effort (typically <20)

---

## References

### Code Locations
- **Constants**: `lib/core/constants/` (capability.dart, modality_config.dart, metric_ids.dart, modality_display.dart, modality.dart, block_types.dart, intent.dart, workout_constants.dart, effort_defaults.dart)
- **Models**: `lib/data/models/models.dart` (Exercise with capabilities field)
- **Repositories**: `lib/data/repositories/` (workout_repository.dart, mock_workout_repository.dart)
- **State**: `lib/state/workout/workout_state.dart` (WorkoutState with modality awareness)
- **UI**: `lib/features/` (home_screen.dart, session_overview_screen.dart, workout_session_screen.dart)
- **Widgets**: `lib/widgets/pickers/` (metric_chooser_dialog.dart, modality_picker_dialog.dart); the exercise picker is a full screen at `lib/features/exercise/exercise_picker_screen.dart`
- **Utilities**: `lib/core/utils/observation_grouper.dart`
- **Schema**: `scripts/sqlite_schema.sql` (app_exercise_capability table)
- **Seed Data**: `lib/mock/seed_data.dart`, `scripts/sqlite_seed.sql`

### Related Documentation
- [App Philosophy](app_philosophy.md) — Core design principles and entity model
- [DB Integration](db_integration.md) — Database schema and patterns
- [Session Summary](session_summary.md) — Post-workout analytics
- [Navigation & Screens](navigation_and_screens.md) — Screen flow and DI pattern
- [State Management](state_management.md) — WorkoutState and service classes
- [Data Models](data_models.md) — Full model reference
- [Constants Reference](constants_reference.md) — All constant definitions
- [My Routines](my_routines.md) - Reusable workout template system


---

> **Doc freshness** — Last reconciled against source: 2026-07-26. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
