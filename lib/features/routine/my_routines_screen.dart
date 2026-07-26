import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../state/routine/routine_state.dart';
import '../../state/settings/settings_state.dart';
import '../../state/workout/workout_state.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import 'routine_setup_screen.dart';
import 'widgets/demo_routine_badge.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_bottom_cta.dart';
import '../session/workout_session_screen.dart';

/// Screen displaying list of saved workout routines
/// Allows user to view, start, edit, or delete routines
class MyRoutinesScreen extends StatefulWidget {
  final RoutineState routineState;
  final WorkoutState? workoutState; // Optional for starting session
  final RoutineSessionService routineSessionService;
  final SessionSummaryService sessionSummaryService;
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;

  MyRoutinesScreen({
    super.key,
    required this.routineState,
    this.workoutState,
    required this.routineSessionService,
    required this.sessionSummaryService,
    required this.settingsState,
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

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
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: const OmniBackHeader(title: 'My Routines'),
      // Primary bottom CTA — the shared `OmniBottomCTA` is the single
      // source of truth for full-width, safe-area-anchored primary actions
      // (see `.github/agents/docs/widget_catalog.md` — `OmniBottomCTA`).
      // Replaces the legacy `FloatingActionButton` so the routines screen
      // matches the unified bottom-CTA pattern used elsewhere (calendar
      // day list, food library, etc.).
      bottomNavigationBar: OmniBottomCTA(
        label: '+ New Routine',
        onPressed: () => _createNewRoutine(context),
      ),
      body: SafeArea(
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
                          color: OmniTheme.colors.textDominant.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.folder_open,
                        size: 60,
                        color: OmniTheme.colors.textDominant.withOpacity(0.6),
                      ),
                    ),
                    SizedBox(height: 32),
                    Text(
                      'No Routines Yet',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: OmniTheme.colors.textDominant,
                      ),
                    ),
                    SizedBox(height: 16),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32.0),
                      child: Text(
                        'Create your first routine to get started',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: OmniTheme.colors.textDominant.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              // Bottom inset reserves clearance for the host's shared
              // `OmniBottomCTA` (same contract as the calendar day list
              // — see `OmniTheme.formBottomCTAClearance`). Without this,
              // the last routine card would sit under the CTA on long
              // lists.
              padding: const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                OmniTheme.formBottomCTAClearance,
              ),
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
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              routine.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (routine.isBuiltInDemo) ...[
                            SizedBox(width: 8),
                            const DemoRoutineBadge(),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        'Created ${_formatDate(DateTime.fromMillisecondsSinceEpoch(routine.createdAtMs))}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      trailing: PopupMenuButton(
                        color: theme.colorScheme.surface.withOpacity(0.8),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
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
    );
  }

  void _createNewRoutine(BuildContext context) async {
    OmniNavigator.push(
      context,
      (_) => RoutineSetupScreen(
        routineState: widget.routineState,
        workoutState: widget.workoutState,
        settingsState: widget.settingsState,
      ),
    ).then((_) {
      widget.routineState.loadRoutines();
    });
  }

  void _editRoutine(BuildContext context, String templateId) async {
    OmniNavigator.push(
      context,
      (_) => RoutineSetupScreen(
        routineState: widget.routineState,
        workoutState: widget.workoutState,
        templateId: templateId,
        settingsState: widget.settingsState,
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
            'Starting a routine will start a new session. Current session will not be saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
      final manifest = await widget.routineSessionService
          .buildSessionFromTemplate(templateId);

      // Step 2: Create new workout session with routine metadata
      await widget.workoutState!.createNewSession(
        modality: null, // Mixed modality for routines
        title: manifest.template.name,
        intent: 'routine',
        routineTemplateId: manifest.template.id,
        includeDefaultSegment: false,
      );

      // Step 3: Load session data
      await widget.workoutState!.loadSessionData();

      // Step 4: Populate session from manifest
      await widget.workoutState!.populateSessionFromManifest(manifest);

      // Navigate to workout session
      OmniNavigator.popUntil(context, (route) => route.isFirst);
      OmniNavigator.push(
        context,
        (_) => WorkoutSessionScreen(
          workoutState: widget.workoutState!,
          routineState: widget.routineState,
          sessionSummaryService: widget.sessionSummaryService,
          settingsState: widget.settingsState,
          timerAlertService: widget.timerAlertService,
          restNotificationService: widget.restNotificationService,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error starting routine: $e')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, String templateId) async {
    final plannedCount = await widget.routineState
        .countPlannedSessionsForTemplate(templateId);

    if (!context.mounted) return;

    final baseMessage = 'This action cannot be undone.';
    final warningMessage =
        'This routine has $plannedCount planned session(s). Deleting it will also remove those planned sessions.';
    final contentText = plannedCount > 0
        ? '$warningMessage\n\n$baseMessage'
        : baseMessage;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Routine?'),
        content: Text(contentText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.routineState.deleteRoutine(templateId);
    }
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
