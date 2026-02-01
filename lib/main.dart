import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workout Session',
      theme: ThemeData.dark(useMaterial3: true),
      home: const WorkoutSessionScreen(),
    );
  }
}

class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  // Dummy data
  final List<ExerciseData> _exercises = [
    ExerciseData(name: 'Bench Press', weight: 80, reps: 6, totalSets: 5),
    ExerciseData(name: 'Squats', weight: 100, reps: 8, totalSets: 4),
    ExerciseData(name: 'Deadlift', weight: 120, reps: 5, totalSets: 3),
    ExerciseData(name: 'Overhead Press', weight: 50, reps: 8, totalSets: 4),
    ExerciseData(name: 'Barbell Row', weight: 70, reps: 8, totalSets: 4),
    ExerciseData(name: 'Pull-ups', weight: 0, reps: 10, totalSets: 3),
  ];

  int _currentExerciseIndex = 0;
  int _currentSet = 1;
  final int _restSeconds = 72; // Static dummy countdown

  void _logSet() {
    setState(() {
      final exercise = _exercises[_currentExerciseIndex];
      if (_currentSet < exercise.totalSets) {
        _currentSet++;
      } else {
        // Move to next exercise
        if (_currentExerciseIndex < _exercises.length - 1) {
          _currentExerciseIndex++;
          _currentSet = 1;
        }
      }
    });
  }

  void _switchExercise(int delta) {
    setState(() {
      final newIndex = _currentExerciseIndex + delta;
      if (newIndex >= 0 && newIndex < _exercises.length) {
        _currentExerciseIndex = newIndex;
        _currentSet = 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercises[_currentExerciseIndex];
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! > 0) {
            _switchExercise(-1); // Swipe right = previous
          } else if (details.primaryVelocity! < 0) {
            _switchExercise(1); // Swipe left = next
          }
        },
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(theme),

              const SizedBox(height: 48),

              // Central focus area
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildWeightReps(exercise, theme),
                    const SizedBox(height: 32),
                    _buildSetProgress(exercise, theme),
                    const SizedBox(height: 24),
                    _buildSetIndicator(exercise, theme),
                    const SizedBox(height: 48),
                    _buildRestIndicator(theme),
                  ],
                ),
              ),

              // Primary action
              _buildPrimaryAction(theme),

              const SizedBox(height: 16),

              // Secondary controls
              _buildSecondaryControls(theme),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(Icons.arrow_back, color: theme.colorScheme.onSurface.withAlpha((0.5 * 255).round())),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _exercises[_currentExerciseIndex].name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Exercise ${_currentExerciseIndex + 1} / ${_exercises.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightReps(ExerciseData exercise, ThemeData theme) {
    return Text(
      exercise.weight > 0 ? '${exercise.weight} × ${exercise.reps}' : '${exercise.reps}',
      style: theme.textTheme.displayLarge?.copyWith(
        fontSize: 72,
        fontWeight: FontWeight.w300,
        letterSpacing: -2,
      ),
    );
  }

  Widget _buildSetProgress(ExerciseData exercise, ThemeData theme) {
    return Text(
      'SET $_currentSet / ${exercise.totalSets}',
        style: theme.textTheme.titleMedium?.copyWith(
        letterSpacing: 2,
        color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildSetIndicator(ExerciseData exercise, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(exercise.totalSets, (index) {
        final isCompleted = index < _currentSet - 1;
        final isCurrent = index == _currentSet - 1;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: isCurrent ? 14 : 10,
          height: isCurrent ? 14 : 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? theme.colorScheme.primary
                    : isCurrent
                      ? theme.colorScheme.primary.withAlpha((0.5 * 255).round())
                      : theme.colorScheme.onSurface.withAlpha((0.2 * 255).round()),
          ),
        );
      }),
    );
  }

  Widget _buildRestIndicator(ThemeData theme) {
    return Text(
      'REST ${(_restSeconds ~/ 60).toString().padLeft(2, '0')}:${(_restSeconds % 60).toString().padLeft(2, '0')}',
        style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurface.withAlpha((0.4 * 255).round()),
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildPrimaryAction(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton(
          onPressed: _logSet,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            'LOG SET',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryControls(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildIconButton(Icons.pause, theme),
        const SizedBox(width: 32),
        _buildIconButton(Icons.edit_outlined, theme),
        const SizedBox(width: 32),
        _buildIconButton(Icons.skip_next_outlined, theme),
      ],
    );
  }

  Widget _buildIconButton(IconData icon, ThemeData theme) {
    return IconButton(
      onPressed: () {},
      icon: Icon(icon),
      color: theme.colorScheme.onSurface.withAlpha((0.3 * 255).round()),
      iconSize: 24,
    );
  }
}

class ExerciseData {
  final String name;
  final double weight;
  final int reps;
  final int totalSets;

  ExerciseData({
    required this.name,
    required this.weight,
    required this.reps,
    required this.totalSets,
  });
}
