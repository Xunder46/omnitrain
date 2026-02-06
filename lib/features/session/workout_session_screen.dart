import 'dart:async';
import 'package:flutter/material.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/pickers/exercise_picker_dialog.dart';
import '../../data/models/models.dart';

class WorkoutSessionScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final String? initialFocusId;

  const WorkoutSessionScreen({super.key, required this.workoutState, this.initialFocusId});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  List<Map<String, dynamic>> _exercises = [];
  int _currentExerciseIndex = 0;
  int _currentSet = 1;
  final int _restSeconds = 72;
  bool _isLoading = true;
  bool _showListView = true; // Toggle between list view and detail view - default to list

  late final Stopwatch _stopwatch;
  Timer? _ticker;
  String _elapsedFormatted = '00:00';

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    setState(() => _isLoading = true);
    try {
      if (!widget.workoutState.hasSession) {
        await widget.workoutState.createNewSession();
      }
      await widget.workoutState.loadSessionData();
      final exercises = widget.workoutState.getExercisesWithSets();
      setState(() {
        _exercises = exercises;
        final initialId = widget.initialFocusId;
        if (initialId != null && initialId.isNotEmpty) {
          final idx = _exercises.indexWhere((e) => e['id'] == initialId);
          if (idx != -1) {
            _currentExerciseIndex = idx;
            _currentSet = 1;
            _showListView = false; // Show detail view when focusing a specific exercise
          }
        }

        if (_currentExerciseIndex >= _exercises.length && _exercises.isNotEmpty) {
          _currentExerciseIndex = 0;
          _currentSet = 1;
        }
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading exercises: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load exercises: $e')),
        );
      }
    }
  }

  void _logSet() {
    setState(() {
      if (_exercises.isNotEmpty) {
        final exercise = _exercises[_currentExerciseIndex];
        final sets = exercise['sets'] as List<Map<String, dynamic>>;
        if (_currentSet < sets.length) {
          _currentSet++;
        } else {
          if (_currentExerciseIndex < _exercises.length - 1) {
            _currentExerciseIndex++;
            _currentSet = 1;
          }
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

  Future<void> _addExercise() async {
    final selectedExercise = await showDialog<Exercise>(
      context: context,
      builder: (context) => ExercisePickerDialog(workoutState: widget.workoutState),
    );

    if (selectedExercise != null) {
      String effortId = '';
      try {
        effortId = await widget.workoutState.addExercise(selectedExercise.name);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add exercise: $e')));
        }
      }

      await _loadExercises();

      if (effortId.isNotEmpty) {
        final idx = _exercises.indexWhere((e) => e['id'] == effortId);
        if (idx != -1) {
          setState(() {
            _currentExerciseIndex = idx;
            _currentSet = 1;
            _showListView = false;
          });
        }
      }
    }
  }

  Future<void> _addSet() async {
    if (_exercises.isNotEmpty) {
      final exercise = _exercises[_currentExerciseIndex];
      final effortId = exercise['id'] as String;
      await widget.workoutState.addSet(effortId);
      await _loadExercises();
    }
  }

  void _tick() {
    final elapsed = _stopwatch.elapsed;
    final mm = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    if (mounted) {
      setState(() {
        _elapsedFormatted = '$mm:$ss';
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_showListView) {
      return _buildListView(theme);
    }

    if (_exercises.isEmpty) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'No exercises yet',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _addExercise,
                  child: const Text('Add First Exercise'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final exercise = _exercises[_currentExerciseIndex];
    final sets = exercise['sets'] as List<Map<String, dynamic>>;
    final currentSetData = sets.isNotEmpty && _currentSet <= sets.length
        ? sets[_currentSet - 1]
        : {'reps': 0, 'weight': 0.0};

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! > 0) {
            _switchExercise(-1);
          } else if (details.primaryVelocity! < 0) {
            _switchExercise(1);
          }
        },
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(theme),

              const SizedBox(height: 48),

              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildWeightReps(currentSetData, theme),
                    const SizedBox(height: 32),
                    _buildSetProgress(sets.length, theme),
                    const SizedBox(height: 24),
                    _buildSetIndicator(sets.length, theme),
                    const SizedBox(height: 48),
                    _buildRestIndicator(theme),
                  ],
                ),
              ),

              _buildPrimaryAction(theme),

              const SizedBox(height: 16),

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
          IconButton(
            icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
            onPressed: () {
              // If in detail view, return to list view
              // If in list view, pop navigation (exit to home)
              if (!_showListView) {
                setState(() {
                  _showListView = true;
                });
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _showListView ? 'Exercises' : (_exercises.isNotEmpty ? _exercises[_currentExerciseIndex]['name'] as String : ''),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _showListView ? '${_exercises.length} exercise${_exercises.length != 1 ? 's' : ''}' : (_exercises.isNotEmpty ? 'Exercise ${_currentExerciseIndex + 1} / ${_exercises.length}' : ''),
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

  Widget _buildListView(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(theme),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.timer, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.9)),
                        const SizedBox(width: 8),
                        Text(_elapsedFormatted, style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _exercises.isEmpty
                  ? Center(child: Text('No exercises', style: theme.textTheme.headlineSmall))
                  : ListView.separated(
                      itemCount: _exercises.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final ex = _exercises[index];
                        final sets = ex['sets'] as List<dynamic>? ?? [];
                        return ListTile(
                          title: Text(ex['name'] as String),
                          subtitle: Text('${sets.length} set${sets.length != 1 ? 's' : ''}'),
                          onTap: () {
                            setState(() {
                              _currentExerciseIndex = index;
                              _currentSet = 1;
                              _showListView = false;
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExercise,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildWeightReps(Map<String, dynamic> setData, ThemeData theme) {
    final weight = setData['weight'] as double;
    final reps = setData['reps'] as int;
    return Text(
      weight > 0 ? '${weight.toStringAsFixed(1)} × $reps' : '$reps',
      style: theme.textTheme.displayLarge?.copyWith(
        fontSize: 72,
        fontWeight: FontWeight.w300,
        letterSpacing: -2,
      ),
    );
  }

  Widget _buildSetProgress(int totalSets, ThemeData theme) {
    return Text(
      'SET $_currentSet / $totalSets',
        style: theme.textTheme.titleMedium?.copyWith(
        letterSpacing: 2,
        color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildSetIndicator(int totalSets, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSets, (index) {
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
        _buildIconButton(Icons.pause, theme, () {}),
        const SizedBox(width: 32),
        _buildIconButton(Icons.playlist_add, theme, _addSet),
      ],
    );
  }

  Widget _buildIconButton(IconData icon, ThemeData theme, VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      color: theme.colorScheme.onSurface.withAlpha((0.3 * 255).round()),
      iconSize: 24,
    );
  }
}
