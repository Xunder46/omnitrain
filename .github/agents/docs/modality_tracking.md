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

> **Feb 2026**: The previous separate "Martial Arts" and "Sports" tiles were unified into a single "Sports" tile. The `sports` modality now maps to both `category-martial-arts` and `category-sports` for exercise ranking. The `martial_arts` modality constant remains in code for backward compatibility but is no longer a home screen tile.

Additionally, **My Routines** is a special (non-modality) tile on the home screen that navigates to saved workout templates. See [My Routines](my_routines.md) for details.

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
- **timed** - Duration + distance (cardio)
- **round** - Rounds + round duration (martial arts/sports)
- **drill** - Hold duration + RPE (isometric/stretching)

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

### 2. Free Training (User-Driven)
```
User → Selects "Free Training" tile (modality=null)
     → Adds "Barbell Squat" from exercise picker
     → System shows metric chooser dialog
     → User picks "Track by Time"
     → Tracks as 8:00 continuous work
```

### 3. Modality Change Mid-Session
```
User → Has active Resistance session
     → Taps "Cardio / Endurance" tile
     → System shows warning dialog:
        "Changing modality will start a new session.
         Current session will be saved."
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
  
  Future<String> addExerciseToSession(Exercise exercise, {String? chosenMetric}) {
    // Determine effort kind from modality or chosen metric
    String effortKind;
    if (_currentModalityConfig != null) {
      effortKind = _currentModalityConfig!.effortKind;
    } else if (chosenMetric != null) {
      effortKind = ModalityConfig.effortKindFromMetric(chosenMetric);
    }
    // Creates SegmentEffort with appropriate effortKind
  }
  
  Future<void> addEntry(String effortId) {
    // Creates observations based on effort kind:
    // - 'set' → reps + weight observations
    // - 'timed' → duration + distance observations
    // - 'round' → rounds + round-duration observations
    // - 'drill' → duration + RPE observations
  }
}
```

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
      case 'round': return _groupRoundObservations(observations);
      case 'drill': return _groupDrillObservations(observations);
    }
  }
}
```

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

### Mock Repository (Development/Web)
```dart
class MockWorkoutRepository implements WorkoutRepository {
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

### Future SQLite Repository (Native)
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

### Phase 2 (Deferred)
1. **User-Created Exercise Capabilities**: UI to tag custom exercises with capabilities
2. **Delete Exercise from Session**: Remove exercises after adding them
3. **Mid-Session Modality Re-mapping**: Preserve exercises when changing modality, prompt for new tracking method
4. **Capability Auto-Detection**: Suggest capabilities based on exercise name/description (ML-assisted)

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
- **Constants**: `lib/core/constants/` (capability.dart, modality_config.dart, metric_ids.dart, modality_display.dart)
- **Models**: `lib/data/models/models.dart` (Exercise with capabilities field)
- **Repositories**: `lib/data/repositories/` (workout_repository.dart, mock_workout_repository.dart)
- **State**: `lib/state/workout/workout_state.dart` (WorkoutState with modality awareness)
- **UI**: `lib/features/` (home_screen.dart, session_overview_screen.dart, workout_session_screen.dart)
- **Widgets**: `lib/widgets/pickers/` (exercise_picker_dialog.dart, metric_chooser_dialog.dart)
- **Utilities**: `lib/core/utils/observation_grouper.dart`
- **Schema**: `scripts/sqlite_schema.sql` (app_exercise_capability table)
- **Seed Data**: `lib/mock/seed_data.dart`, `scripts/sqlite_seed.sql`

### Related Documentation
- [App Philosophy](app_philosophy.md) - Core design principles and entity model
- [DB Integration](db_integration.md) - Database schema and patterns
- [My Routines](my_routines.md) - Reusable workout template system
