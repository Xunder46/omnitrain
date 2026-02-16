import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/services/routine_session_service.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import '../../state/routine/routine_state.dart';
import '../../state/workout/workout_state.dart';
import 'routine_setup_screen.dart';
import '../session/workout_session_screen.dart';

/// Screen displaying list of saved workout routines
/// Allows user to view, start, edit, or delete routines
class MyRoutinesScreen extends StatefulWidget {
  final RoutineState routineState;
  final WorkoutState? workoutState; // Optional for starting session
  final RoutineSessionService routineSessionService;

  const MyRoutinesScreen({
    super.key,
    required this.routineState,
    this.workoutState,
    required this.routineSessionService,
  });

  @override
  State<MyRoutinesScreen> createState() => _MyRoutinesScreenState();
}

class _MyRoutinesScreenState extends State<MyRoutinesScreen> {
  @override
  void initState() {
    super.initState();
    widget.routineState.loadRoutines();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('My Routines'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createNewRoutine(context),
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.add),
      ),
      body: OmniGradientBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: widget.routineState,
            builder: (context, child) {
              final theme = Theme.of(context);

              if (widget.routineState.isLoading) {
                return Center(child: CircularProgressIndicator());
              }

              final routines = widget.routineState.routines;

              if (routines.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: OmniTheme.textPrimary.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.folder_open,
                          size: 60,
                          color: OmniTheme.textPrimary.withOpacity(0.6),
                        ),
                      ),
                      SizedBox(height: 32),
                      Text(
                        'No Routines Yet',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: OmniTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 16),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32.0),
                        child: Text(
                          'Create your first routine to get started',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: OmniTheme.textPrimary.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: routines.length,
                itemBuilder: (context, index) {
                  final routine = routines[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Card(
                      color: theme.colorScheme.surface.withOpacity(0.8),
                      elevation: 4,
                      child: ListTile(
                        contentPadding: EdgeInsets.all(12),
                        onTap: () => _startRoutine(context, routine.id),
                        leading: Icon(
                          Icons.fitness_center,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                        title: Text(
                          routine.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          'Created ${_formatDate(DateTime.fromMillisecondsSinceEpoch(routine.createdAtMs))}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        trailing: PopupMenuButton(
                          color: theme.colorScheme.surface.withOpacity(0.8),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 20, color: theme.colorScheme.primary),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                              onTap: () => _editRoutine(context, routine.id),
                            ),
                            PopupMenuItem(
                              child: Row(
                                children: [
                                  Icon(Icons.delete, size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete'),
                                ],
                              ),
                              onTap: () => _confirmDelete(context, routine.id),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _createNewRoutine(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutineSetupScreen(
          routineState: widget.routineState,
          workoutState: widget.workoutState,
        ),
      ),
    ).then((_) {
      widget.routineState.loadRoutines();
    });
  }

  void _editRoutine(BuildContext context, String templateId) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutineSetupScreen(
          routineState: widget.routineState,
          workoutState: widget.workoutState,
          templateId: templateId,
        ),
      ),
    ).then((_) {
      widget.routineState.loadRoutines();
    });
  }

  void _startRoutine(BuildContext context, String templateId) async {
    if (widget.workoutState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: Workout state not available')),
      );
      return;
    }

    if (widget.workoutState!.hasActiveSession) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start New Session?'),
          content: const Text(
            'Starting a routine will start a new session. Current session will be saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                )),
              ),
              child: const Text('Start New'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    try {
      // Step 1: Build session manifest from template (via service)
      final manifest = await widget.routineSessionService.buildSessionFromTemplate(templateId);

      // Step 2: Create new workout session with routine metadata
      await widget.workoutState!.createNewSession(
        modality: null, // Mixed modality for routines
        title: manifest.template.name,
        intent: 'routine',
        routineTemplateId: manifest.template.id,
      );

      // Step 3: Load session data
      await widget.workoutState!.loadSessionData();

      // Step 4: Populate session from manifest
      await widget.workoutState!.populateSessionFromManifest(manifest);

      // Navigate to workout session
      Navigator.popUntil(context, (route) => route.isFirst);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkoutSessionScreen(workoutState: widget.workoutState!),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting routine: $e')),
      );
    }
  }

  void _confirmDelete(BuildContext context, String templateId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2a2a2a),
        title: Text('Delete Routine?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This action cannot be undone.',
          style: TextStyle(color: Colors.grey[300]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.routineState.deleteRoutine(templateId);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}
