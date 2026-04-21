import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/pickers/exercise_picker_dialog.dart';
import '../../widgets/pickers/modality_picker_dialog.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/modality_display.dart';
import '../../data/models/models.dart';
import '../../state/routine/routine_state.dart';
import '../../core/services/session_summary_service.dart';
import 'workout_session_screen.dart';

class SessionOverviewScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final RoutineState routineState;
  final SessionSummaryService sessionSummaryService;
  final SettingsState settingsState;

  const SessionOverviewScreen({
    super.key,
    required this.workoutState,
    required this.routineState,
    required this.sessionSummaryService,
    required this.settingsState,
  });

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
      barrierColor: Colors.black.withOpacity(0.78),
      builder: (context) => ExercisePickerDialog(
        workoutState: widget.workoutState,
        sessionModality: modality,
      ),
    );

    if (selectedExercise != null) {
      String? effortKindOverride;

      // If Free Training or Routine session (null modality), ask user to pick a modality
      if (modality == null) {
        final modalityResult = await showDialog<(bool, String?)>(
          context: context,
          builder: (context) => const ModalityPickerDialog(),
        );

        if (!context.mounted || modalityResult == null) {
          return; // user cancelled
        }

        final (_, pickedModality) = modalityResult;
        effortKindOverride =
            ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set';
      }

      try {
        final effortId = await widget.workoutState.addExerciseToSession(
          selectedExercise,
          effortKindOverride: effortKindOverride,
        );
        if (effortId.isNotEmpty) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WorkoutSessionScreen(
                workoutState: widget.workoutState,
                routineState: widget.routineState,
                sessionSummaryService: widget.sessionSummaryService,
                settingsState: widget.settingsState,
                initialFocusId: effortId,
              ),
            ),
          );
        }
        await _initializeSession();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to add exercise: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: OmniTheme.colorsForTheme(
          widget.settingsState.appTheme,
        ).backgroundTop,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final exercises = widget.workoutState.getExercisesWithEntries();
    final modality = widget.workoutState.currentSession?.modality;
    final modalityName = ModalityDisplay.getName(modality);

    final themeColors = OmniTheme.colorsForTheme(widget.settingsState.appTheme);

    return Scaffold(
      backgroundColor: themeColors.backgroundTop,
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
        backgroundColor: themeColors.backgroundTop,
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
                  color: themeColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${exercises.length} exercise${exercises.length != 1 ? 's' : ''} planned',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(
                    (0.6 * 255).round(),
                  ),
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
                              color: theme.colorScheme.onSurface.withAlpha(
                                (0.3 * 255).round(),
                              ),
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
                                color: theme.colorScheme.onSurface.withAlpha(
                                  (0.6 * 255).round(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: exercises.length,
                        itemBuilder: (context, index) {
                          final exercise = exercises[index];
                          final entries =
                              exercise['entries'] as List<Map<String, dynamic>>;
                          final effortKind =
                              exercise['effortKind'] as String? ?? 'set';

                          String subtitle;
                          switch (effortKind) {
                            case 'set':
                              subtitle =
                                  '${entries.length} set${entries.length != 1 ? 's' : ''}';
                              break;
                            case 'timed':
                              final totalDuration = entries.fold<int>(
                                0,
                                (sum, e) =>
                                    sum + ((e['duration'] as int?) ?? 0),
                              );
                              final minutes = totalDuration ~/ 60;
                              final seconds = totalDuration % 60;
                              subtitle =
                                  '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} total';
                              break;
                            case 'round':
                              final effortId = exercise['id'] as String;
                              final completedRounds = widget.workoutState
                                  .getRoundsForEffort(effortId)
                                  .where(
                                    (round) =>
                                        round.completed &&
                                        round.startedAtMs > 0 &&
                                        round.finishedAtMs != null,
                                  )
                                  .length;
                              subtitle =
                                  '$completedRounds round${completedRounds != 1 ? 's' : ''}';
                              break;
                            case 'drill':
                              subtitle =
                                  '${entries.length} hold${entries.length != 1 ? 's' : ''}';
                              break;
                            default:
                              subtitle =
                                  '${entries.length} ${entries.length != 1 ? 'entries' : 'entry'}';
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: themeColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: themeColors.surfaceBorder,
                              ),
                            ),
                            child: ListTile(
                              title: Text(exercise['name'] as String),
                              subtitle: Text(subtitle),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final effortId = exercise['id'] as String;
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Remove Exercise'),
                                      content: Text(
                                        'Remove ${exercise['name']} from this workout?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && mounted) {
                                    await widget.workoutState
                                        .removeExerciseFromSession(effortId);
                                    await _initializeSession();
                                  }
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            OmniTheme.buttonBorderRadius,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: exercises.isNotEmpty
                          ? () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => WorkoutSessionScreen(
                                    workoutState: widget.workoutState,
                                    routineState: widget.routineState,
                                    sessionSummaryService:
                                        widget.sessionSummaryService,
                                    settingsState: widget.settingsState,
                                  ),
                                ),
                              );
                              await _initializeSession();
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            OmniTheme.buttonBorderRadius,
                          ),
                        ),
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
