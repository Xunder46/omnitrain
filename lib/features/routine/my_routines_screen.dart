import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../core/services/routine_session_service.dart';
import '../../core/services/session_summary_service.dart';
import '../../data/models/models.dart';
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
import '../../widgets/dialogs/confirmation_dialog.dart';

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
                // PR 6 — intent split.  The card body opens the routine
                // editor (no session created); the trailing Start button
                // is a distinct, non-overlapping hit region that creates
                // the session in one tap.  No more overflow menu — the
                // destructive delete action lives in the editor's app
                // bar where the user can see the routine name they are
                // about to remove.
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RoutineCard(
                    routine: routine,
                    // Demo routines ship with the app, so their createdAtMs
                    // is whenever the catalog happened to seed on this
                    // device. Showing it reads as "you created this on
                    // <date>", which the user never did.
                    formattedDate: routine.isBuiltInDemo
                        ? null
                        : 'Created ${_formatDate(DateTime.fromMillisecondsSinceEpoch(routine.createdAtMs))}',
                    onOpen: () => _editRoutine(context, routine.id),
                    onStart: () => _startRoutine(context, routine.id),
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
      final confirmed = await ConfirmationDialog.showTwoChoice(
        context: context,
        title: 'Start New Session?',
        body: const Text(
          'Your current session will be discarded and cannot be recovered.',
        ),
        dismissLabel: 'Cancel',
        confirmLabel: 'Start New',
        dismissKey: const Key('routine-start-new-cancel'),
        confirmKey: const Key('routine-start-new-confirm'),
        isDestructive: true,
      );

      if (!confirmed) return;
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

/// Show the destructive delete-routine confirmation dialog. Used by the
/// header delete action on `RoutineSetupScreen` — PR 6 / S-002 keeps the
/// wording identical regardless of where it is invoked from. Returns
/// `true` when the user confirmed the delete.
Future<bool> showDeleteRoutineDialog(
  BuildContext context, {
  required RoutineState routineState,
  required String templateId,
  required String routineName,
}) async {
  final plannedCount =
      await routineState.countPlannedSessionsForTemplate(templateId);
  if (!context.mounted) return false;

  final bodyText = plannedCount > 0
      ? 'This routine has $plannedCount planned session'
            '${plannedCount == 1 ? '' : 's'} that will also be removed. This action cannot be undone.'
      : 'This action cannot be undone.';

  return await ConfirmationDialog.showTwoChoice(
    context: context,
    title: 'Delete "$routineName"?',
    body: Text(bodyText),
    dismissLabel: 'Cancel',
    confirmLabel: 'Delete',
    dismissKey: const Key('routine-delete-cancel'),
    confirmKey: const Key('routine-delete-confirm'),
    isDestructive: true,
  );
}

/// Renders a single routine card with a body hit-region that opens the
/// editor and a separate, non-overlapping Start button that creates the
/// session. The card deliberately does NOT render an overflow menu —
/// destructive delete lives in the editor's app bar (PR 6 / S-001).
class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.formattedDate,
    required this.onOpen,
    required this.onStart,
  });

  final WorkoutTemplate routine;

  /// Metadata line under the title, or `null` to omit it entirely — demo
  /// routines have no meaningful creation date to show.
  final String? formattedDate;
  final VoidCallback onOpen;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('routine-card'),
      color: theme.colorScheme.surface.withOpacity(0.8),
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card body hit region — opens the routine editor (PR 6 / S-001).
            // PR 6 / S-006 — the body owns the full horizontal budget
            // minus the play glyph. Routine names of typical length
            // render in full on a 320-dp surface (the regression being
            // fixed).
            //
            // PR 6 / S-007 — the body extends fully to the start
            // control's hit region so there is no dead zone between
            // the two.
            //
            // PR 6 / S-008 — the Demo badge is back on the TITLE row,
            // not the metadata line. With the start control reduced
            // to a 56-dp tap region around a 28-dp glyph (S-006 +
            // S-007), the title row now has enough horizontal budget
            // to host the badge next to the routine name without
            // crowding it. The metadata line returns to a simple
            // `Row` with just the date text.
            Expanded(
              child: InkWell(
                key: const Key('routine-card-body'),
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.fitness_center,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title line — name + optional Demo badge
                            // (S-008). The badge is a Row sibling of
                            // the title text. The Row's default
                            // cross-axis-centre alignment keeps the
                            // badge vertically centred with the title
                            // text. The title text sits in an
                            // `Expanded` (FlexFit.tight) so the badge's
                            // right edge is pinned to the title row's
                            // right edge regardless of how long the
                            // routine name happens to be — `Flexible`
                            // (loose) would shrink-fit the row to the
                            // Text's natural width and pull the badge
                            // inwards on short names.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    routine.name,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (routine.isBuiltInDemo) ...[
                                  const SizedBox(width: 8),
                                  const DemoRoutineBadge(compact: true),
                                ],
                              ],
                            ),
                            // Metadata line — simple Row with just the
                            // date text. No Stack, no Positioned, no
                            // reserved space — the badge lives on the
                            // title row now (S-008). Omitted entirely for
                            // demo routines, spacing included, so the card
                            // closes up instead of leaving a blank line.
                            if (formattedDate != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                formattedDate!,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.7),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // PR 6 / S-006 / S-007 — the start control is a bare play
            // glyph:
            //   * no text label, no fill, no border
            //   * accent colour from the theme (colorScheme.primary)
            //   * vertically centred within the row, not stretched
            //   * tap region is 56×56 dp (comfortably larger than the
            //     28 dp visible glyph — S-007 contract). The SizedBox
            //     pin the layout size even when the row is rendered
            //     inside a tight `IntrinsicHeight` constraint.
            //   * tap region smaller than the row body — the row body
            //     covers most of the card, so tapping the body opens
            //     the routine while tapping the glyph starts it.
            //   * the body's right edge sits flush with the start
            //     control's left edge, so there is no dead zone
            //     between them (S-007 contract).
            //
            // Locator: `Key('routine-card-start')` and semantic label
            // `tooltip: 'Start routine'` for tests + accessibility.
            SizedBox(
              key: const Key('routine-card-start'),
              width: 56,
              height: 56,
              child: IconButton(
                tooltip: 'Start routine',
                icon: Icon(
                  Icons.play_arrow,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: onStart,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
