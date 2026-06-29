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

## User Workflows

### 1. Structured Workout (Modality-Driven)
```
User → Selects "Resistance / Lifting" tile
     → Creates new session with modality=resistance_lifting
     → Adds "Barbell Squat" from exercise picker
     → System shows "Recommended for this workout" section
     → Tracks as 3 sets × 10 reps @ 135 lbs
```

### 2. Free Training / Routine (User-Driven)
```
User → Selects "Free Training" tile (modality=null) or starts a Routine session
     → Adds an exercise from the picker
     → System opens ModalityPickerDialog
          Specific modality picked:
              effortKind derived from ModalityConfig (no MetricChooserDialog needed)
          "General" / null picked:
              System shows MetricChooserDialog → user picks tracking method
          Cancelled:
              Exercise not added
     → Tracks with the derived effort kind
```

### 3. Modality Change Mid-Session
```
User → Has active Resistance session
     → Taps "Cardio / Endurance" tile
     → System shows warning dialog:
        "Changing modality will start a new session.
         Current session will not be saved."
     → User confirms → New cardio session created
```

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

**Exercise Ranking Logic**:
- If modality is set (e.g., `cardio_endurance`), get its primary metric (`time`)
- Partition exercises into:
  - **Recommended**: Supports primary metric (e.g., squat supports `time`)
  - **Others**: All other exercises
- Return recommended exercises first, then others (both sorted alphabetically)

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

#### Exercise Picker with Ranking
```dart
class ExercisePickerDialog extends StatefulWidget {
  final String? sessionModality;  // Pass current session modality
  
  Widget _buildExerciseList() {
    if (hasModality && primaryMetric != null) {
      // Partition into recommended vs others
      for (exercise in exercises) {
        if (exercise.supports(primaryMetric)) {
          recommended.add(exercise);
        } else {
          others.add(exercise);
        }
      }
    }
    // Render with section headers
  }
}
```

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

```dart
class HiveWorkoutRepository implements WorkoutRepository {
  final Map<String, List<String>> _exerciseCapabilities = {};
  
  Future<void> initialize() async {
    // Load from SeedData.exerciseCapabilityRelationships
    for (final entry in SeedData.exerciseCapabilityRelationships.entries) {
      _exerciseCapabilities[entry.key] = List.from(entry.value);
    }
  }
  
  Future<List<Exercise>> getExercisesRankedForModality(String? modality, ...) async {
    // In-memory ranking logic
    final primaryMetric = _getModalityConfig(modality)?['primaryMetric'];
    
    for (exercise in exercises) {
      final caps = _exerciseCapabilities[exercise.id] ?? [];
      final exerciseWithCaps = exercise.copyWith(capabilities: caps);
      
      if (caps.contains(primaryMetric)) {
        recommended.add(exerciseWithCaps);
      } else {
        others.add(exerciseWithCaps);
      }
    }
    
    return [...recommended, ...others];
  }
}
```

### Future SQLite Repository (Native — Planned)
Schema is ready. Implementation will:
1. Join `app_exercise` with `app_exercise_capability` table
2. Use same ranking algorithm as mock
3. Zero UI changes needed - repository interface abstraction provides compatibility

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

## Future Enhancements

### Phase 2 (Completed — February 2026)
✅ **Round-Based Tracking Refactor**: `round` efforts store `RoundInstance` records (not observations). Full lifecycle methods in `WorkoutState`. Wall-clock timestamps for background resilience.
✅ **RoundState Enum + Strict Transitions**: `RoundInstance` carries a `RoundState` field (`notStarted` → `active` ⇄ `paused` → `finished`). `finished` is terminal. `WorkoutState._isValidRoundTransition()` enforces all transitions. Elapsed time is derived from timestamps at read time via `RoundInstance.elapsedMs` — never stored as a counter.
✅ **Pause Support for Rounds**: `pauseRound()` and `resumeRound()` added to `WorkoutState`. Each pause start is stamped to `pausedAtMs`; on resume, `(now - pausedAtMs)` is folded into `totalPausedDurationMs` and `pausedAtMs` is cleared. The elapsed formula subtracts `totalPausedDurationMs` so paused time is never counted as work. UI-level rapid-tap guard (`_pendingRoundTransitions` set) prevents concurrent duplicate transitions.
✅ **Delete Exercise from Session**: `removeExerciseFromSession` implemented in `WorkoutState`.

### Phase 2 (Still Deferred)
1. **User-Created Exercise Capabilities**: UI to tag custom exercises with capabilities
2. **Mid-Session Modality Re-mapping**: Preserve exercises when changing modality, prompt for new tracking method
3. **Capability Auto-Detection**: Suggest capabilities based on exercise name/description (ML-assisted)

### Phase 3 (Research)
1. **Hybrid Modalities**: Mix effort kinds in one session (e.g., "Crossfit" with both timed and set-based)
2. **Progressive Overload Tracking**: Detect when user increases weight/time/reps over sessions
3. **Template Modality Hints**: Templates suggest ideal modality based on exercise composition

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
✅ Schema ready for native (SqliteWorkoutRepository)  
✅ No platform-specific code in shared layer  

### Manual Test Scenarios
1. **Resistance Workout**: Add "Barbell Squat" → Verify tracks as reps/sets/weight
2. **Cardio Workout**: Add same "Barbell Squat" → Verify appears in "Recommended" → Tracks as time/distance
3. **Free Training**: Add "Plank Hold" → Choose "Track by Hold Time" → Verify 3×30s holds tracked
4. **Modality Switch**: Start resistance session → Add exercise → Tap cardio tile → Verify warning → Confirm → New session created
5. **Exercise Ranking**: Open picker in cardio session → Verify running exercises in "Recommended", strength exercises in "Others"

---

## Deployment Notes

### Environment Requirements
- **Web**: MockWorkoutRepository (in-memory storage)
- **iOS/Android**: SqliteWorkoutRepository (future - schema ready)

### Migration Path
1. Deploy web version with mock repository (current)
2. Implement SqliteWorkoutRepository with same interface
3. Update app initialization to inject SQLite repository on native platforms
4. Zero UI changes needed - repository abstraction ensures compatibility

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
- **Widgets**: `lib/widgets/pickers/` (exercise_picker_dialog.dart, metric_chooser_dialog.dart)
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

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
