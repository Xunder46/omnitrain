import 'package:flutter/material.dart';
import '../../state/workout/workout_state.dart';
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
    final nameController = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Exercise'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Exercise name',
            hintText: 'e.g. Squats',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(nameController.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final effortId = await widget.workoutState.addExercise(result);
        if (effortId.isNotEmpty) {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => WorkoutSessionScreen(workoutState: widget.workoutState, initialFocusId: effortId),
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

    final exercises = widget.workoutState.getExercisesWithSets();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Workout Session'),
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
                          final sets = exercise['sets'] as List<Map<String, dynamic>>;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(exercise['name'] as String),
                              subtitle: Text('${sets.length} set${sets.length != 1 ? 's' : ''}'),
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
