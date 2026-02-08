import 'package:flutter/material.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/pickers/exercise_picker_dialog.dart';
import '../../widgets/pickers/metric_chooser_dialog.dart';
import '../../core/constants/modality_display.dart';
import '../../data/models/models.dart';
import 'workout_session_screen.dart';

class SessionOverviewScreen extends StatefulWidget {
  final WorkoutState workoutState;

  const SessionOverviewScreen({super.key, required this.workoutState});

  @override
  State<SessionOverviewScreen> createState() => _SessionOverviewScreenState();
}

class _SessionOverviewScreenState extends State<SessionOverviewScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeSession();
  }

  Future<void> _initializeSession() async {
    setState(() => _isLoading = true);
    try {
      if (!widget.workoutState.hasSession) {
        await widget.workoutState.createNewSession();
      }
      await widget.workoutState.loadSessionData();
    } catch (e) {
      print('Error initializing session: $e');
    } finally {
      setState(() => _isLoading = false);
    }
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
        
        if (chosenMetric == null) return; // User cancelled
      }
      
      try {
        final effortId = await widget.workoutState.addExerciseToSession(
          selectedExercise,
          chosenMetric: chosenMetric,
        );
        if (effortId.isNotEmpty) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WorkoutSessionScreen(
              workoutState: widget.workoutState,
              initialFocusId: effortId,
            ),
          ));
        }
        await _initializeSession();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add exercise: $e')),
          );
        }
      }
    }
  }

  void _startWorkout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Container(),
      ),
    );
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

    final exercises = widget.workoutState.getExercisesWithEntries();
    final modality = widget.workoutState.currentSession?.modality;
    final modalityName = ModalityDisplay.getName(modality);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Workout Session'),
            Text(
              modalityName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exercises',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${exercises.length} exercise${exercises.length != 1 ? 's' : ''} planned',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: exercises.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.fitness_center,
                              size: 64,
                              color: theme.colorScheme.onSurface.withAlpha((0.3 * 255).round()),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No exercises yet',
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add your first exercise to get started',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: exercises.length,
                        itemBuilder: (context, index) {
                          final exercise = exercises[index];
                          final entries = exercise['entries'] as List<Map<String, dynamic>>;
                          final effortKind = exercise['effortKind'] as String? ?? 'set';
                          
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
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(exercise['name'] as String),
                              subtitle: Text(subtitle),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () {
                                  // TODO: Implement delete exercise
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addExercise,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Exercise'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: exercises.isNotEmpty ? _startWorkout : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Start Workout'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
