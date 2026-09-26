/// The phone's view of a session that is running on the wrist.
///
/// Plan: `.github/agents/plans/2026-07-13-10-c2-phone-manage-bridge-live-sessions-plan.md`.
///
/// This is the phone doing the heavy lifting mid-workout: the ladder is the
/// phone's to own (PROTOCOL.md, authority rule 2), so add, remove, reorder, and
/// swap all originate here and stream to the wrist; the entries are the wrist's
/// to log, so the phone corrects and deletes rather than adding; and Finish
/// closes the session on both devices, leaving one merged record.
///
/// Everything the screen shows comes from [LiveSessionMirrorState], which is
/// also what carries every edit down. There is no local copy of the session
/// here — a second copy would be a second truth.
///
/// What it lists and counts as logged are the mirror's effort entries: the
/// wrist's session effort rating and session end describe the session rather
/// than work done in it (Stats PR 2, D-141; scenario S-254).
///
/// Only the device that ended a session asks how hard it was (D-104 c). The
/// phone's own Finish asks, through the Session Summary's rating sheet, and
/// the answer is the phone's own rating for the wrist session — staged until
/// the session is history, written to it once it is (D-138, D-139). A session
/// the wrist completed is shown closed, with nothing to finish and nothing to
/// ask: the wrist that ended it asks (`test/live_session_effort_rating_test.dart`).
library;

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/navigation/navigation.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/unit_formatter.dart';
import '../../state/settings/settings_state.dart';
import '../../state/watch/live_session_mirror_state.dart';
import '../../state/watch/watch_session_inbox.dart';
import '../../state/workout/workout_state.dart';
import '../../watch/session/watch_records.dart' show WatchSessionStatus;
import '../../widgets/dialogs/confirmation_dialog.dart';
import '../../widgets/inputs/numeric_field_with_done_bar.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_bottom_cta.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/layout/omni_surface.dart';
import '../../widgets/session/effort_rating_sheet.dart';
import '../exercise/exercise_picker_screen.dart';

class LiveSessionScreen extends StatelessWidget {
  const LiveSessionScreen({
    super.key,
    required this.liveSession,
    required this.workoutState,
    required this.settingsState,
    this.watchSessionRatings,
  });

  /// The phone's live session — the mirror of the session on the wrist.
  final LiveSessionMirrorState liveSession;

  /// The catalog the exercise search reads, and where a custom exercise can be
  /// created mid-session.
  final WorkoutState workoutState;

  /// The saved weight unit, for every load this screen shows or takes, and
  /// the Effort Rating setting the phone's Finish honours.
  final SettingsState settingsState;

  /// Where the phone's own effort rating for the session goes (D-139). Null
  /// where no watch graph was built, and then Finish asks nothing — there is
  /// nowhere to put the answer.
  final WatchSessionRatings? watchSessionRatings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: liveSession,
      builder: (context, _) {
        // The session as it closed: the record the phone's own Finish made,
        // or — when the wrist completed it — the session as the mirror holds
        // it (D-139).
        final record =
            liveSession.completedRecord ??
            (liveSession.status == WatchSessionStatus.completed
                ? liveSession.state
                : null);

        return Scaffold(
          key: const Key('live_session_screen'),
          backgroundColor: OmniTheme.colorsForTheme(
            settingsState.appTheme,
          ).backgroundTop,
          appBar: const OmniBackHeader(
            title: 'Watch Session',
            subtitle: 'Managing the session on your wrist',
          ),
          body: record == null
              ? _buildLiveBody(context)
              : _CompletedSession(record: record),
          bottomNavigationBar: record == null
              ? OmniBottomCTA(
                  label: 'Finish',
                  buttonKey: const Key('live_session_finish'),
                  onPressed: () => _finish(context),
                )
              : null,
        );
      },
    );
  }

  /// The phone's own Finish: closes the session on both devices, then — when
  /// the phone ended a running session with something logged in it, and the
  /// Effort Rating setting is on — asks how hard it was, with the question the
  /// Session Summary's automatic prompt asks, which only an answer closes.
  ///
  /// A session with nothing logged is never history (D-133), so it is not
  /// asked about, as the wrist does not ask about one (D-117; A-62 of the
  /// Stats PR 2 plan).
  Future<void> _finish(BuildContext context) async {
    final sessionId = liveSession.sessionId;
    final asks = liveSession.isActive && liveSession.effortEntries.isNotEmpty;
    await liveSession.completeSession();

    final ratings = watchSessionRatings;
    if (!asks || ratings == null || sessionId == null) return;
    if (!settingsState.showFeelingSurvey || !context.mounted) return;
    await EffortRatingSheet.show(
      context,
      mustAnswer: true,
      // A wrist session carries no modality (D-135), and the one being
      // finished is being finished now.
      startedAt: DateTime.now(),
      onRated: (rating) async {
        // The answer is given, so the question closes whatever the inbox
        // made of it; a failure is the inbox's to report.
        await ratings.recordPhoneRating(sessionId, rating);
        return true;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // The live session
  // ---------------------------------------------------------------------------

  Widget _buildLiveBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _buildStatusPanel(context),
        const SizedBox(height: 20),
        _buildExerciseSection(context),
        const SizedBox(height: 24),
        _buildLoggedSection(context),
      ],
    );
  }

  Widget _buildExerciseSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OmniCardHeader(title: 'EXERCISES'),
        OmniSurface(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var index = 0; index < liveSession.exercises.length; index++)
                _buildExerciseRow(context, index),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('live_session_add_exercise'),
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            onPressed: () => _openPicker(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add exercise'),
          ),
        ),
      ],
    );
  }

  Widget _buildLoggedSection(BuildContext context) {
    final entries = liveSession.effortEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OmniCardHeader(title: 'LOGGED'),
        if (entries.isEmpty)
          OmniSurface(
            child: Text(
              'Nothing logged yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: OmniTheme.colors.textSecondary,
              ),
            ),
          )
        else
          OmniSurface(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final entry in entries) _buildEntryRow(context, entry),
              ],
            ),
          ),
      ],
    );
  }

  /// Where the session is and how much has been logged — the two facts a user
  /// lifts the phone to check.
  Widget _buildStatusPanel(BuildContext context) {
    final name = liveSession.currentExercise?['name'] as String?;
    final theme = Theme.of(context);
    final exerciseCount = liveSession.exercises.length;
    final position = exerciseCount == 0
        ? 'No exercises'
        : '${liveSession.currentExerciseIndex.clamp(0, exerciseCount - 1) + 1} '
              'of $exerciseCount';

    return OmniSurface(
      child: Row(
        children: [
          Icon(Icons.watch, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Waiting for the wrist',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: OmniTheme.colors.textDominant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$position · ${liveSession.effortEntries.length} logged',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseRow(BuildContext context, int index) {
    final slot = liveSession.exercises[index];
    final slotId = slot['sessionExerciseId']! as String;
    final isCurrent = index == liveSession.currentExerciseIndex;
    final theme = Theme.of(context);

    return ListTile(
      key: Key('live_session_slot_$slotId'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Text(
        '${index + 1}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: isCurrent
              ? theme.colorScheme.primary
              : OmniTheme.colors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      title: Text(
        slot['name']! as String,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          color: isCurrent
              ? theme.colorScheme.primary
              : OmniTheme.colors.textDominant,
        ),
      ),
      trailing: PopupMenuButton<String>(
        key: Key('live_session_slot_menu_$slotId'),
        tooltip: 'Manage ${slot['name']}',
        onSelected: (action) => _handleSlotAction(
          context,
          index: index,
          slotId: slotId,
          action: action,
        ),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'insert_above',
            child: Text('Insert exercise above'),
          ),
          PopupMenuItem(
            value: 'move_up',
            enabled: index > 0,
            child: const Text('Move up'),
          ),
          PopupMenuItem(
            value: 'move_down',
            enabled: index < liveSession.exercises.length - 1,
            child: const Text('Move down'),
          ),
          const PopupMenuItem(value: 'swap', child: Text('Swap exercise')),
          const PopupMenuItem(value: 'remove', child: Text('Remove exercise')),
        ],
      ),
    );
  }

  Future<void> _handleSlotAction(
    BuildContext context, {
    required int index,
    required String slotId,
    required String action,
  }) {
    switch (action) {
      case 'insert_above':
        return _openPicker(context, insertAtIndex: index);
      case 'move_up':
        return liveSession.moveExercise(index, -1);
      case 'move_down':
        return liveSession.moveExercise(index, 1);
      case 'swap':
        return _openPicker(context, swapSlotId: slotId);
      case 'remove':
        return liveSession.removeExercise(slotId);
      default:
        return Future<void>.value();
    }
  }

  Widget _buildEntryRow(BuildContext context, Map<String, Object?> entry) {
    final entryId = entry['entryId']! as String;
    final slotId = entry['sessionExerciseId'] as String?;
    final theme = Theme.of(context);

    return ListTile(
      key: Key('live_session_entry_$entryId'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        _entrySummary(entry),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: OmniTheme.colors.textDominant,
        ),
      ),
      subtitle: Text(
        _exerciseNameFor(slotId),
        style: theme.textTheme.bodySmall?.copyWith(
          color: OmniTheme.colors.textSecondary,
        ),
      ),
      trailing: IconButton(
        key: Key('live_session_delete_entry_$entryId'),
        tooltip: 'Delete entry',
        icon: Icon(
          Icons.delete_outline,
          color: OmniTheme.colors.textSecondary,
          size: 20,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
          ),
        ),
        onPressed: () => _deleteEntry(context, entryId),
      ),
      onTap: entry['kind'] == 'set'
          ? () => _correctEntry(context, entry)
          : null,
    );
  }

  /// What an entry reads as. A set is its reps and its load, in the saved
  /// weight unit — the two numbers the user is checking when they pick the
  /// phone up mid-set.
  String _entrySummary(Map<String, Object?> entry) {
    final reps = entry['reps'];
    final load = entry['loadKg'];
    final loadLabel = load is num
        ? UnitFormatter.formatWeight(load.toDouble(), settingsState)
        : null;
    if (reps is num && loadLabel != null) return '${reps.toInt()} × $loadLabel';
    if (reps is num) return '${reps.toInt()} reps';

    final startedAt = entry['startedAt'];
    final endedAt = entry['endedAt'];
    if (startedAt is String && endedAt is String) {
      final ms = DateTime.parse(endedAt).difference(DateTime.parse(startedAt));
      return OmniDateUtils.formatClock(ms.inMilliseconds);
    }
    return 'Logged';
  }

  String _exerciseNameFor(String? slotId) {
    if (slotId == null) return 'Session';
    for (final slot in liveSession.exercises) {
      if (slot['sessionExerciseId'] == slotId) return slot['name']! as String;
    }
    return 'Removed exercise';
  }

  // ---------------------------------------------------------------------------
  // Edits the phone originates
  // ---------------------------------------------------------------------------

  /// Opens the full-catalog search, wired to the live session.
  ///
  /// [insertAtIndex] is where a pushed exercise lands, [swapSlotId] the slot it
  /// replaces instead. Which one the user picked is decided before the search on
  /// this screen, so the search itself only has to answer "which exercise".
  Future<void> _openPicker(
    BuildContext context, {
    int? insertAtIndex,
    String? swapSlotId,
  }) {
    return OmniNavigator.push<void>(
      context,
      (_) => ExercisePickerScreen(
        workoutState: workoutState,
        liveSession: liveSession,
        liveSessionInsertIndex: insertAtIndex,
        liveSessionSwapSlotId: swapSlotId,
      ),
    );
  }

  /// Fixes what a set recorded. The load is entered in the saved unit and
  /// stored in kilograms, the app's canonical unit.
  Future<void> _correctEntry(
    BuildContext context,
    Map<String, Object?> entry,
  ) async {
    var correction = const <String, Object?>{};

    final confirmed = await ConfirmationDialog.showTwoChoice(
      context: context,
      title: 'Correct Set',
      body: _CorrectionFields(
        entry: entry,
        settingsState: settingsState,
        onChanged: (value) => correction = value,
      ),
      dismissLabel: 'Cancel',
      confirmLabel: 'Save',
      dismissKey: const Key('live_session_correction_cancel'),
      confirmKey: const Key('live_session_correction_save'),
      isDestructive: false,
    );

    // A field the user cleared or broke leaves its metric out rather than
    // guessing at it, and a correction with nothing in it is not one.
    if (!confirmed || correction.isEmpty) return;
    await liveSession.correctEntry(entry['entryId']! as String, correction);
  }

  /// Deletes an entry, after asking — the wrist never deletes anything itself,
  /// so this is the one way history gets shorter.
  Future<void> _deleteEntry(BuildContext context, String entryId) async {
    final confirmed = await ConfirmationDialog.showTwoChoice(
      context: context,
      title: 'Delete Entry',
      body: const Text(
        'This entry is removed from the session on both devices.',
      ),
      dismissLabel: 'Cancel',
      confirmLabel: 'Delete',
      dismissKey: const Key('live_session_delete_entry_cancel'),
      confirmKey: const Key('live_session_delete_entry_confirm'),
      isDestructive: true,
    );

    if (!confirmed) return;
    await liveSession.deleteEntry(entryId);
  }
}

/// The correction dialog's fields.
///
/// Stateful so the controllers live exactly as long as the fields they feed: a
/// controller disposed while its `TextField` is still mounted is a framework
/// error, and the dialog outlives the call that opened it.
class _CorrectionFields extends StatefulWidget {
  const _CorrectionFields({
    required this.entry,
    required this.settingsState,
    required this.onChanged,
  });

  /// The entry being corrected, as the wrist reported it.
  final Map<String, Object?> entry;

  /// Where the weight unit comes from — loads are shown and entered in the
  /// saved unit and stored in kilograms.
  final SettingsState settingsState;

  /// Called with the correction the fields currently describe.
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<_CorrectionFields> createState() => _CorrectionFieldsState();
}

class _CorrectionFieldsState extends State<_CorrectionFields> {
  late final TextEditingController _repsController;
  late final TextEditingController _loadController;

  @override
  void initState() {
    super.initState();
    final reps = widget.entry['reps'];
    final load = widget.entry['loadKg'];
    _repsController = TextEditingController(
      text: reps is num ? '${reps.toInt()}' : '',
    );
    _loadController = TextEditingController(
      text: load is num
          ? UnitFormatter.formatWeightValue(
              load.toDouble(),
              widget.settingsState,
            )
          : '',
    );
    _publish();
  }

  @override
  void dispose() {
    _repsController.dispose();
    _loadController.dispose();
    super.dispose();
  }

  /// Reads the fields into the correction the protocol carries: reps as
  /// entered, and the load converted back to kilograms.
  void _publish() {
    final correction = <String, Object?>{};

    final reps = int.tryParse(_repsController.text.trim());
    if (reps != null && reps >= 1) correction['reps'] = reps;

    final load = double.tryParse(_loadController.text.trim());
    if (load != null && load >= 0) {
      correction['loadKg'] = UnitFormatter.toCanonicalWeight(
        load,
        widget.settingsState,
      );
    }

    widget.onChanged(correction);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NumericFieldWithDoneBar(
          key: const Key('live_session_correction_reps'),
          controller: _repsController,
          decoration: const InputDecoration(labelText: 'Reps'),
          onChanged: (_) => _publish(),
        ),
        const SizedBox(height: 12),
        NumericFieldWithDoneBar(
          key: const Key('live_session_correction_load'),
          controller: _loadController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText:
                'Load (${UnitFormatter.weightLabel(widget.settingsState)})',
          ),
          onChanged: (_) => _publish(),
        ),
      ],
    );
  }
}

/// The session as it closed: what the two devices logged, merged into one.
class _CompletedSession extends StatelessWidget {
  const _CompletedSession({required this.record});

  final Map<String, Object?> record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = LiveSessionMirrorState.effortEntriesOf(record['entries']);
    final exercises = (record['exercises'] as List?) ?? const [];

    return Padding(
      key: const Key('live_session_completed'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: OmniSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Session complete',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: OmniTheme.colors.textDominant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${entries.length} logged across ${exercises.length} '
              '${exercises.length == 1 ? 'exercise' : 'exercises'} — '
              'everything both devices recorded, in order.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: OmniTheme.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
