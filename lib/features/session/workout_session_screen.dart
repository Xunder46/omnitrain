import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/pickers/exercise_picker_dialog.dart';
import '../../widgets/pickers/metric_chooser_dialog.dart';
import '../../data/models/models.dart';
import '../../widgets/session/inline_metric_editor.dart';

class WorkoutSessionScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final String? initialFocusId;

  const WorkoutSessionScreen({super.key, required this.workoutState, this.initialFocusId});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  // Constants
  static const Duration _timerUpdateInterval = Duration(seconds: 1);

  List<Map<String, dynamic>> _exercises = [];
  int _currentExerciseIndex = 0;
  int _currentSet = 1;
  bool _isLoading = true;
  bool _showListView = true; // Toggle between list view and detail view - default to list
  bool _hasError = false;
  String _errorMessage = '';

  // Track skipped sets per effort (UI-only state)
  final Map<String, Set<int>> _skippedSets = {};

  late final Stopwatch _stopwatch;
  Timer? _ticker;
  String _elapsedFormatted = '00:00';

  // Per-effort timer state for timed and round exercises
  final Map<String, Timer?> _effortTimers = {};
  final Map<String, Stopwatch> _effortStopwatches = {};
  final Map<String, bool> _effortRunning = {};
  final Map<String, int> _effortElapsed = {}; // Elapsed seconds
  final Map<String, int> _effortElapsedBase = {}; // Base elapsed time when timer started (for offset)

  // Rest timer state
  Timer? _restTimer;
  Stopwatch? _restStopwatch;
  int _restElapsedSeconds = 0;
  String _restFormatted = '00:00';

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
      final exercises = widget.workoutState.getExercisesWithEntries();
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
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _logSet() {
    if (_exercises.isEmpty) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    final effortKind = exercise['effortKind'] as String? ?? 'set';

    // Get current entry data to persist
    final currentEntry = _currentSet <= entries.length
        ? entries[_currentSet - 1]
        : <String, dynamic>{};

    // For timer-based exercises, capture elapsed time
    if (effortKind == 'timed' || effortKind == 'drill') {
      currentEntry['duration'] = _effortElapsed[effortId] ?? 0;
    }

    // Persist entry values based on effort kind
    _persistEntryValues(effortId, _currentSet - 1, effortKind, currentEntry);

    // Haptic feedback on successful log
    if (!kIsWeb) {
      HapticFeedback.lightImpact();
    }

    // For timer-based exercises, stop and reset timer
    // User must explicitly start timer for next entry
    if (effortKind == 'timed' || effortKind == 'drill' || effortKind == 'round') {
      _pauseEffortTimer(effortId, _currentSet - 1);
      _effortStopwatches[effortId]?.reset();
      _effortElapsed[effortId] = 0;
    }

    // Start rest timer after logging a set
    _startRestTimer();

    // Advance to next set or next exercise
    setState(() {
      if (_currentSet < entries.length) {
        _currentSet++;
      } else {
        // Move to next exercise
        if (_currentExerciseIndex < _exercises.length - 1) {
          _currentExerciseIndex++;
          _currentSet = 1;
        } else {
          // All exercises complete - show finish option
          _showFinishDialog();
        }
      }
    });
  }

  void _previousSet() {
    if (_exercises.isEmpty || _currentSet <= 1) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final effortKind = exercise['effortKind'] as String? ?? 'set';

    // Stop timer for the current set if it's running
    if (effortKind == 'timed' || effortKind == 'drill' || effortKind == 'round') {
      final timerKey = '$effortId-${_currentSet - 1}';
      if (_effortRunning[timerKey] == true) {
        _pauseEffortTimer(effortId, _currentSet - 1);
      }
    }

    // Simply move back to previous set without clearing values
    setState(() {
      if (_currentSet > 1) {
        _currentSet--;
      }
    });
  }

  void _skipSet() {
    if (_exercises.isEmpty) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    final effortKind = exercise['effortKind'] as String? ?? 'set';

    // Stop timer if running
    if (effortKind == 'timed' || effortKind == 'drill' || effortKind == 'round') {
      final timerKey = '$effortId-${_currentSet - 1}';
      if (_effortRunning[timerKey] == true) {
        _pauseEffortTimer(effortId, _currentSet - 1);
      }
    }

    // Mark this set as skipped (don't log or fill the dot)
    _skippedSets.putIfAbsent(effortId, () => {}).add(_currentSet - 1);

    // Reset timer
    _effortElapsed[effortId] = 0;

    // Just advance to next set, don't auto-finish
    setState(() {
      if (_currentSet < entries.length) {
        _currentSet++;
      }
    });
  }

  /// Pre-fill the next set entry with values from the previous set
  /// Persist current entry values to the repository
  void _persistEntryValues(
    String effortId,
    int entryIndex,
    String effortKind,
    Map<String, dynamic> currentEntry,
  ) {
    switch (effortKind) {
      case 'set':
        // Persist reps and weight
        widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'reps',
          currentEntry['reps'] as int? ?? 0,
        );
        widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'weight',
          currentEntry['weight'] as double? ?? 0.0,
        );
        break;
      case 'timed':
        // Persist duration and distance
        widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'duration',
          _effortElapsed[effortId] ?? (currentEntry['duration'] as int? ?? 0),
        );
        widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'distance',
          currentEntry['distance'] as double? ?? 0.0,
        );
        break;
      case 'round':
        // Persist rounds and round duration
        widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'rounds',
          currentEntry['rounds'] as int? ?? 1,
        );
        widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'round-duration',
          currentEntry['round-duration'] as int? ?? 180,
        );
        break;
      case 'drill':
        // Persist hold duration and RPE
        widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'duration',
          _effortElapsed[effortId] ?? (currentEntry['duration'] as int? ?? 0),
        );
        widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'rpe',
          currentEntry['rpe'] as int? ?? 5,
        );
        break;
    }
  }

  void _showFinishDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout Complete'),
        content: const Text('All exercises completed! Finish this workout?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _showListView = true;
              });
            },
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () async {
              await widget.workoutState.endSession();
              if (mounted) {
                Navigator.pop(context);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Finish'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSet() async {
    if (_exercises.isEmpty) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;

    await widget.workoutState.addEntry(effortId);
    await _loadExercises();
  }

  Future<void> _deleteLastSet() async {
    if (_exercises.isEmpty) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final entries = exercise['entries'] as List<Map<String, dynamic>>;

    if (entries.isEmpty) return;

    // Delete the last entry
    await widget.workoutState.deleteEntry(effortId, entries.length - 1);
    await _loadExercises();

    // Adjust current set if needed
    setState(() {
      if (_currentSet > entries.length - 1) {
        _currentSet = (entries.length - 1).clamp(1, entries.length);
      }
    });
  }

  Future<void> _updateMetricValue(String effortId, int entryIndex, String metricKey, dynamic value) async {
    await widget.workoutState.updateEntryValue(effortId, entryIndex, metricKey, value);
    
    // Reload exercises to reflect updated values
    await _loadExercises();
    
    // Sync the local _effortElapsed state with the newly loaded value
    // This ensures the timer starts from the user-set value, not the old one
    if (_exercises.isNotEmpty && _currentExerciseIndex < _exercises.length) {
      final exercise = _exercises[_currentExerciseIndex];
      final entries = exercise['entries'] as List<Map<String, dynamic>>;
      if (entries.isNotEmpty && entryIndex < entries.length) {
        final entry = entries[entryIndex];
        final timerKey = '$effortId-$entryIndex';
        
        // Update _effortElapsed to match the newly persisted value
        if (metricKey == 'duration') {
          _effortElapsed[timerKey] = entry['duration'] as int? ?? 0;
          _effortElapsedBase[timerKey] = entry['duration'] as int? ?? 0;
        }
      }
    }
  }

  void _toggleEffortTimer(String effortId) {
    final entryIndex = _currentSet - 1;
    final timerKey = '$effortId-$entryIndex';
    if (_effortRunning[timerKey] == true) {
      _pauseEffortTimer(effortId, entryIndex);
    } else {
      if ((_effortElapsed[timerKey] ?? 0) == 0) {
        _startEffortTimer(effortId, entryIndex);
      } else {
        _resumeEffortTimer(effortId, entryIndex);
      }
    }
  }

  void _startEffortTimer(String effortId, int entryIndex) {
    final timerKey = '$effortId-$entryIndex';
    if (_effortRunning[timerKey] == true) return;

    // Stop rest timer when starting to work
    _stopRestTimer();

    _effortRunning[timerKey] = true;
    
    // Store the current elapsed value as the base (so timer counts up from this point)
    _effortElapsedBase[timerKey] = _effortElapsed[timerKey] ?? 0;
    
    _effortStopwatches.putIfAbsent(timerKey, () => Stopwatch()).start();

    _effortTimers[timerKey]?.cancel();
    _effortTimers[timerKey] =
        Timer.periodic(_timerUpdateInterval, (_) {
          setState(() {
            // Total elapsed = base value + time elapsed since timer started
            _effortElapsed[timerKey] = (_effortElapsedBase[timerKey] ?? 0) + (_effortStopwatches[timerKey]?.elapsed.inSeconds ?? 0);
          });
        });
  }

  void _pauseEffortTimer(String effortId, int entryIndex) {
    final timerKey = '$effortId-$entryIndex';
    _effortRunning[timerKey] = false;
    _effortStopwatches[timerKey]?.stop();
    _effortTimers[timerKey]?.cancel();
    
    // Save the elapsed time as the new duration value
    // Only for timed and drill (which show elapsed time counting UP)
    // NOT for round (which shows remaining time counting DOWN)
    if (_exercises.isNotEmpty && _currentExerciseIndex < _exercises.length) {
      final exercise = _exercises[_currentExerciseIndex];
      final effortKind = exercise['effortKind'] as String? ?? 'set';
      
      if (effortKind == 'timed' || effortKind == 'drill') {
        final elapsedTime = _effortElapsed[timerKey] ?? 0;
        final metricKey = effortKind == 'drill' ? 'duration' : 'duration';
        _updateMetricValue(effortId, entryIndex, metricKey, elapsedTime);
      }
      // For 'round', do NOT save - the countdown value shouldn't overwrite the duration
    }
  }

  void _resumeEffortTimer(String effortId, int entryIndex) {
    final timerKey = '$effortId-$entryIndex';
    _effortRunning[timerKey] = true;
    
    // Store the current elapsed value as the new base (so timer continues from current value)
    _effortElapsedBase[timerKey] = _effortElapsed[timerKey] ?? 0;
    
    // Reset stopwatch to track time since resume
    _effortStopwatches[timerKey]?.reset();
    _effortStopwatches[timerKey]?.start();

    _effortTimers[timerKey]?.cancel();
    _effortTimers[timerKey] =
        Timer.periodic(_timerUpdateInterval, (_) {
          setState(() {
            // Total elapsed = base value + time elapsed since timer resumed
            _effortElapsed[timerKey] = (_effortElapsedBase[timerKey] ?? 0) + (_effortStopwatches[timerKey]?.elapsed.inSeconds ?? 0);
          });
        });
  }

  void _jumpToSet(int setNumber) {
    setState(() {
      _currentSet = setNumber;
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
    final modality = widget.workoutState.currentSession?.modality;
    
    final selectedExercise = await showDialog<Exercise>(
      context: context,
      builder: (context) => ExercisePickerDialog(
        workoutState: widget.workoutState,
        sessionModality: modality,
      ),
    );

    if (selectedExercise != null) {
      String? chosenMetric;
      
      // If Free Training (null modality), show metric chooser
      if (modality == null) {
        chosenMetric = await showDialog<String>(
          context: context,
          builder: (context) => MetricChooserDialog(exercise: selectedExercise),
        );
        
        if (chosenMetric == null) return; // User cancelled metric selection
      }
      
      String effortId = '';
      try {
        effortId = await widget.workoutState.addExerciseToSession(
          selectedExercise,
          chosenMetric: chosenMetric,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add exercise: $e')),
          );
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

  void _startRestTimer() {
    _restStopwatch?.stop();
    _restStopwatch = Stopwatch()..start();
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _restElapsedSeconds = _restStopwatch?.elapsed.inSeconds ?? 0;
          final mm = (_restElapsedSeconds ~/ 60).toString().padLeft(2, '0');
          final ss = (_restElapsedSeconds % 60).toString().padLeft(2, '0');
          _restFormatted = '$mm:$ss';
        });
      }
    });
  }

  void _stopRestTimer() {
    _restTimer?.cancel();
    _restStopwatch?.stop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    // Cancel all effort timers
    for (final timer in _effortTimers.values) {
      timer?.cancel();
    }
    for (final stopwatch in _effortStopwatches.values) {
      stopwatch.stop();
    }
    // Cancel rest timer
    _restTimer?.cancel();
    _restStopwatch?.stop();
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

    if (_hasError) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error Loading Session',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha((0.7 * 255).round()),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _loadExercises,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Error Loading Session',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _loadExercises,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
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
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    final effortKind = exercise['effortKind'] as String? ?? 'set';
    final currentEntry = entries.isNotEmpty && _currentSet <= entries.length
        ? entries[_currentSet - 1]
        : (effortKind == 'set' ? {'reps': 0, 'weight': 0.0} : {'duration': 0});

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          // Left swipe = skip set; right swipe = previous set (only in detail view)
          if (details.primaryVelocity! > 200) {
            // Right swipe with sufficient velocity = previous set
            _skipSet();
          } else if (details.primaryVelocity! < -200) {
            // Left swipe with sufficient velocity = skip set
            _previousSet();
          }
        },
        onVerticalDragEnd: (details) {
          // Up swipe = next exercise; down swipe = previous exercise
          if (details.primaryVelocity! < -200) {
            // Swipe up = next exercise
            _switchExercise(1);
          } else if (details.primaryVelocity! > 200) {
            // Swipe down = previous exercise
            _switchExercise(-1);
          }
        },
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(theme),

                  const SizedBox(height: 48),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildMetricWidget(exercise, currentEntry, effortKind, theme),
                            const SizedBox(height: 24),
                            _buildSetProgress(entries.length, effortKind, theme),
                            const SizedBox(height: 16),
                            _buildPreviousSetStats(exercise, effortKind, theme),
                            const SizedBox(height: 16),
                            _buildSetIndicator(entries.length, effortKind, theme),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSetControls(theme),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
            // Rest timer overlay in lower half (hide when exercise timer is running)
            if (_restElapsedSeconds > 0 && !(_effortRunning['${exercise['id']}-${_currentSet - 1}'] ?? false))
              Positioned(
                left: 0,
                right: 0,
                bottom: 125,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withAlpha((0.2 * 255).round()),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.self_improvement,
                          size: 24,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _restFormatted,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
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
      body: Stack(
        children: [
          SafeArea(
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
                            final entries = ex['entries'] as List<dynamic>? ?? [];
                            final effortKind = ex['effortKind'] as String? ?? 'set';
                            
                            String subtitle;
                            switch (effortKind) {
                              case 'set':
                                subtitle = '${entries.length} set${entries.length != 1 ? 's' : ''}';
                                break;
                              case 'timed':
                                final totalDuration = entries.fold<int>(0, (sum, e) => sum + ((e['duration'] as int?) ?? 0));
                                final minutes = totalDuration ~/ 60;
                                final seconds = totalDuration % 60;
                                subtitle = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} total';
                                break;
                              case 'round':
                                subtitle = '${entries.length} round${entries.length != 1 ? 's' : ''}';
                                break;
                              case 'drill':
                                subtitle = '${entries.length} hold${entries.length != 1 ? 's' : ''}';
                                break;
                              default:
                                subtitle = '${entries.length} ${entries.length != 1 ? 'entries' : 'entry'}';
                            }
                            
                            return ListTile(
                              title: Text(ex['name'] as String),
                              subtitle: Text(subtitle),
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
          // Rest timer overlay (hide when exercise timer is running)
          if (_restElapsedSeconds > 0 && !(_effortRunning['${_exercises[_currentExerciseIndex]['id']}-${_currentSet - 1}'] ?? false))
            Positioned(
              left: 0,
              right: 0,
              bottom: 125,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withAlpha((0.2 * 255).round()),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.self_improvement,
                        size: 24,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _restFormatted,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExercise,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildMetricWidget(
    Map<String, dynamic> exercise,
    Map<String, dynamic> entryData,
    String effortKind,
    ThemeData theme,
  ) {
    final effortId = exercise['id'] as String;
    final entryIndex = _currentSet - 1;

    switch (effortKind) {
      case 'set':
        final reps = entryData['reps'] as int? ?? 0;
        final weight = entryData['weight'] as double? ?? 0.0;
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineMetricEditor(
              metricType: 'reps',
              currentValue: reps,
              unitLabel: 'REPS',
              onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'reps', value),
            ),
            const SizedBox(height: 16),
            InlineMetricEditor(
              metricType: 'weight',
              currentValue: weight,
              unitLabel: 'LBS',
              onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'weight', value),
            ),
          ],
        );

      case 'timed':
        final duration = entryData['duration'] as int? ?? 0;
        final timerKey = '$effortId-$entryIndex';
        final displayValue = (_effortRunning[timerKey] ?? false) ? (_effortElapsed[timerKey] ?? 0) : duration;
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: displayValue,
              unitLabel: _effortRunning[timerKey] ?? false ? 'ELAPSED' : 'TIME',
              onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'duration', value),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _effortRunning[timerKey] ?? false ? 'RUNNING' : 'STOPPED',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _effortRunning[timerKey] ?? false
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        );

      case 'round':
        final rounds = entryData['rounds'] as int? ?? 1;
        final roundDuration = entryData['round-duration'] as int? ?? 180;
        final timerKey = '$effortId-$entryIndex';
        final elapsed = _effortElapsed[timerKey] ?? 0;
        final remaining = (roundDuration - elapsed).clamp(0, roundDuration);
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Round count (read-only, controlled by add/delete buttons)
            Text(
              'ROUND $rounds',
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w300,
                letterSpacing: -2,
              ),
            ),
            const SizedBox(height: 32),
            // Scrollable round duration control
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: _effortRunning[timerKey] ?? false ? remaining : roundDuration,
              unitLabel: _effortRunning[timerKey] ?? false ? 'TIME REMAINING' : 'DURATION',
              onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'round-duration', value),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _effortRunning[timerKey] ?? false ? 'RUNNING' : 'STOPPED',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _effortRunning[timerKey] ?? false
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        );

      case 'drill':
        final duration = entryData['duration'] as int? ?? 0;
        final rpe = entryData['rpe'] as int? ?? 5;
        final timerKey = '$effortId-$entryIndex';
        final displayValue = (_effortRunning[timerKey] ?? false) ? (_effortElapsed[timerKey] ?? 0) : duration;
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: displayValue,
              unitLabel: _effortRunning[timerKey] ?? false ? 'ELAPSED' : 'HOLD TIME',
              onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'duration', value),
            ),
            const SizedBox(height: 16),
            InlineMetricEditor(
              metricType: 'rpe',
              currentValue: rpe,
              unitLabel: 'RPE',
              onValueChanged: (value) => _updateMetricValue(effortId, entryIndex, 'rpe', value),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _effortRunning[timerKey] ?? false ? 'RUNNING' : 'STOPPED',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _effortRunning[timerKey] ?? false
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        );

      default:
        return Text(
          '—',
          style: theme.textTheme.displayLarge,
        );
    }
  }

  Widget _buildSetProgress(int totalEntries, String effortKind, ThemeData theme) {
    String label;
    switch (effortKind) {
      case 'set':
        label = 'Set $_currentSet of $totalEntries';
        break;
      case 'timed':
        label = 'Interval $_currentSet of $totalEntries';
        break;
      case 'round':
        final modality = widget.workoutState.currentSession?.modality;
        final isWorkoutLabel = modality == 'sports' ? 'Period' : 'Round';
        label = '$isWorkoutLabel $_currentSet of $totalEntries';
        break;
      case 'drill':
        label = 'Hold $_currentSet of $totalEntries';
        break;
      default:
        label = 'Set $_currentSet of $totalEntries';
    }
    
    return Text(
      label,
      style: theme.textTheme.titleMedium?.copyWith(
        letterSpacing: 2,
        color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildPreviousSetStats(
    Map<String, dynamic> exercise,
    String effortKind,
    ThemeData theme,
  ) {
    // Only show if we're not on the first set
    if (_currentSet <= 1) {
      return const SizedBox.shrink();
    }

    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    if (_currentSet - 2 >= entries.length) {
      return const SizedBox.shrink();
    }

    final previousEntry = entries[_currentSet - 2];
    String statsText = '';

    switch (effortKind) {
      case 'set':
        final prevReps = previousEntry['reps'] as int? ?? 0;
        final prevWeight = previousEntry['weight'] as double? ?? 0.0;
        statsText = 'Previous: $prevReps reps @ ${prevWeight.toStringAsFixed(1)} lbs';
        break;
      case 'timed':
        final prevDuration = previousEntry['duration'] as int? ?? 0;
        final prevDistance = previousEntry['distance'] as double? ?? 0.0;
        final mins = prevDuration ~/ 60;
        final secs = prevDuration % 60;
        statsText = 'Previous: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} @ ${prevDistance.toStringAsFixed(1)} m';
        break;
      case 'round':
        final prevRounds = previousEntry['rounds'] as int? ?? 1;
        final prevRoundDur = previousEntry['round-duration'] as int? ?? 180;
        final mins = prevRoundDur ~/ 60;
        final secs = prevRoundDur % 60;
        statsText = 'Previous: $prevRounds rounds @ ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        break;
      case 'drill':
        final prevDuration = previousEntry['duration'] as int? ?? 0;
        final prevRpe = previousEntry['rpe'] as int? ?? 5;
        final mins = prevDuration ~/ 60;
        final secs = prevDuration % 60;
        statsText = 'Previous: ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} hold @ RPE $prevRpe';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Text(
      statsText,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
        fontStyle: FontStyle.italic,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSetIndicator(int totalSets, String effortKind, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Set dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(totalSets, (index) {
            final isCompleted = index < _currentSet - 1;
            final isCurrent = index == _currentSet - 1;
            final isSkipped = _skippedSets[_exercises[_currentExerciseIndex]['id']]?.contains(index) ?? false;
            
            return GestureDetector(
              onTap: () => _jumpToSet(index + 1),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: isCurrent ? 14 : 10,
                height: isCurrent ? 14 : 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted && !isSkipped
                      ? theme.colorScheme.primary
                      : isCurrent
                        ? theme.colorScheme.primary.withAlpha((0.5 * 255).round())
                        : theme.colorScheme.onSurface.withAlpha((0.2 * 255).round()),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSetControls(ThemeData theme) {
    if (_exercises.isEmpty) return const SizedBox.shrink();

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final effortKind = exercise['effortKind'] as String? ?? 'set';
    final isTimerBased = effortKind == 'timed' || effortKind == 'round' || effortKind == 'drill';
    final timerKey = '$effortId-${_currentSet - 1}';
    final isTimerRunning = _effortRunning[timerKey] ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Previous set button
        _buildArrowButton(
          icon: Icons.arrow_back,
          label: 'Previous Set',
          isEnabled: _currentSet > 1,
          onPressed: _currentSet > 1 ? _previousSet : null,
          theme: theme,
          isPrimary: false,
        ),
        
        // Center controls (add, delete, play/pause)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Play/pause icon - only for timer-based exercises
            if (isTimerBased) ...[
              _buildIconButton(
                isTimerRunning ? Icons.pause : Icons.play_arrow,
                theme,
                () => _toggleEffortTimer(effortId),
                tooltip: isTimerRunning ? 'Pause' : 'Start',
              ),
              const SizedBox(width: 24),
            ],
            // Add entry/set button
            _buildIconButton(
              Icons.playlist_add,
              theme,
              _addSet,
              tooltip: 'Add set',
            ),
            const SizedBox(width: 24),
            // Delete last set button
            _buildIconButton(
              Icons.delete_outline,
              theme,
              _deleteLastSet,
              tooltip: 'Delete Last Set',
            ),
          ],
        ),

        // Log/checkmark button (right side) - CRITICAL ACTION
        _buildArrowButton(
          icon: Icons.check,
          label: 'Log Set',          
          isEnabled: true,
          onPressed: _logSet,
          theme: theme,
          isPrimary: true,
        ),
      ],
    );
  }

  Widget _buildArrowButton({
    required IconData icon,
    required String label,
    required bool isEnabled,
    required VoidCallback? onPressed,
    required ThemeData theme,
    required bool isPrimary,
  }) {
    return Tooltip(
      message: label,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
        ),
        child: Material(
          shape: const CircleBorder(),
          color: isEnabled
              ? (isPrimary ? theme.colorScheme.primary : theme.colorScheme.onSurface.withAlpha((0.1 * 255).round()))
              : theme.colorScheme.onSurface.withAlpha((0.05 * 255).round()),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                icon,
                size: isPrimary ? 28 : 24,
                color: isEnabled
                    ? (isPrimary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()))
                    : theme.colorScheme.onSurface.withAlpha((0.2 * 255).round()),
              ),
            ),
          ),
        ),
      ),
    );
  }





  Widget _buildIconButton(
    IconData icon,
    ThemeData theme,
    VoidCallback onPressed, {
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
        iconSize: 28,
      ),
    );
  }
}
