/// The Wear wrist's session menu: the ladder as rows, the jump, End and
/// Discard (plan 281).
///
/// The Dart counterpart of `WatchMenu.swift`. It writes no session structure of
/// its own: a jump is the engine's `selectExercise`, Add Exercise is the start
/// paths' `addExerciseToEnd`, End and Discard are the engine's own
/// `finishSession` and `abandonSession`, End going through the effort-rating
/// state when the shell wires one (plan 285). It never removes or edits an
/// exercise or an entry (D-28102), and it mints no ids.
library;

import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import '../start/watch_routine_catalog.dart';
import '../start/watch_session_start_paths.dart';
import 'watch_effort_rating_state.dart';

/// The menu's fixed copy, named like the Swift `WatchMenuCopy`.
abstract final class WatchMenuCopy {
  static const String menuLabel = 'Menu';
  static const String addExerciseLabel = 'Add Exercise';
  static const String finishLabel = 'End Session';
  static const String discardLabel = 'Discard Session';
  static const String lockedCaption = 'An effort is running';

  static const String confirmTitle = 'Finish Workout?';
  static const String confirmBody =
      'This action will save and close the workout session.';
  static const String confirmCancel = 'Cancel';
  static const String confirmFinish = 'Finish';

  static const String discardConfirmTitle = 'Discard session?';
  static const String discardConfirmBody =
      'This will permanently delete this session and all its data. You will return to the start screen.';
  static const String discardConfirmCancel = 'Cancel';
  static const String discardConfirmDiscard = 'Discard';
}

/// One row of the menu: a slot on the ladder, how many efforts it holds, and
/// whether the session is sitting on it.
class WatchMenuRow {
  const WatchMenuRow({
    required this.slotId,
    required this.name,
    required this.loggedCount,
    required this.isCurrent,
  });

  /// The slot's `sessionExerciseId`: what a jump names.
  final String slotId;

  /// The slot's exercise name, verbatim.
  final String name;

  /// The efforts logged against the slot, after the phone's corrections and
  /// deletions. A rest is not an effort and is never counted.
  final int loggedCount;

  /// Whether the session's position is this slot.
  final bool isCurrent;

  /// The subtitle the row shows, or null when the slot holds no effort yet.
  /// Never `0 logged`.
  String? get countLabel => loggedCount > 0 ? '$loggedCount logged' : null;
}

/// The menu over a live session. A plain class: the screen rebuilds it on its
/// own one-second refresh, and `rows` is read fresh on every access.
class WatchMenuState {
  WatchMenuState({required this.engine, required this.paths, this.rating});

  final WatchSessionEngine engine;
  final WatchSessionStartPaths paths;

  /// The effort-rating state End goes through when the shell wires one (plan
  /// 285, D-28503): it finishes the session and notes an owed rating. Left null
  /// End is the engine's own `finishSession`, as before.
  final WatchEffortRatingState? rating;

  bool get _isActive => engine.session?.status == WatchSessionStatus.active;

  /// The ladder as rows right now, in the session's own order. A slot the
  /// catalog cannot read (no exercise id or name) is skipped.
  List<WatchMenuRow> get rows {
    final session = engine.session;
    if (session == null || session.exercises.isEmpty) return const [];
    final entries = engine.entries;
    final current = session.currentExerciseIndex.clamp(
      0,
      session.exercises.length - 1,
    );
    final rows = <WatchMenuRow>[];
    for (var index = 0; index < session.exercises.length; index++) {
      final slot = session.exercises[index];
      final exercise = WatchCatalogExercise.fromSlot(slot);
      if (exercise == null) continue;
      final slotId = (slot['sessionExerciseId'] as String?) ?? exercise.slotId;
      final count = entries
          .where(
            (entry) =>
                WatchObservationKind.efforts.contains(entry.kind) &&
                entry.payload['sessionExerciseId'] == slotId,
          )
          .length;
      rows.add(
        WatchMenuRow(
          slotId: slotId,
          name: exercise.name,
          loggedCount: count,
          isCurrent: index == current,
        ),
      );
    }
    return rows;
  }

  /// Whether a work clock (elapsed, hold or round) is running, so a jump would
  /// change the exercise out from under the effort being logged (D-28105). A
  /// running rest is not work and never locks.
  bool get isLocked {
    for (final kind in const [
      WatchTimerKind.elapsed,
      WatchTimerKind.hold,
      WatchTimerKind.round,
    ]) {
      final timer = engine.timerFor(kind);
      if (timer != null && timer.state != WatchTimerState.stopped) return true;
    }
    return false;
  }

  /// Whether the session holds a logged effort: efforts only, read from the
  /// engine's projected `entries` so an entry the phone deleted does not count
  /// (D-28106).
  bool get hasLoggedEfforts => engine.entries.any(
    (entry) => WatchObservationKind.efforts.contains(entry.kind),
  );

  /// Whether End has something to save: a logged effort, or a work clock
  /// running (which the phone started: the wrist starts none of its own), so a
  /// wrist Discard cannot abandon the phone's copy (D-28106).
  bool get hasWorkToSave => hasLoggedEfforts || isLocked;

  /// Moves the session to the slot [slotId] names. False, and nothing changes,
  /// when a work clock is running, the session is not active, or the slot is
  /// gone by the time the tap lands.
  Future<bool> jump(String slotId) async {
    if (!_isActive || isLocked) return false;
    return await engine.selectExercise(slotId) != null;
  }

  /// Adds [exercise] at the end of the ladder and keeps the user where they
  /// were. False, and nothing changes, when the session is not active.
  Future<bool> addExercise(WatchCatalogExercise exercise) async {
    if (!_isActive) return false;
    await paths.addExerciseToEnd(exercise);
    return true;
  }

  /// End Session: finishes the workout when there is something to save, and is
  /// a discard when there is not (the phone's own empty finish). With a rating
  /// state the finish goes through it, which may owe the effort rating. A
  /// session that is not active changes nothing.
  Future<void> finish() async {
    if (!_isActive) return;
    if (!hasWorkToSave) {
      await discard();
      return;
    }
    final rating = this.rating;
    if (rating != null) {
      await rating.end();
    } else {
      await engine.finishSession();
    }
  }

  /// Throws the session away through the engine's own abandonment: the session
  /// ends `abandoned` and the phone hears the lifecycle it already applies.
  /// Logged entries stay in history. Not behind [isLocked]: a session the user
  /// cannot finish is exactly the one they need a way out of.
  Future<WatchSessionRecord?> discard() async {
    if (!_isActive) return null;
    return engine.abandonSession();
  }
}
