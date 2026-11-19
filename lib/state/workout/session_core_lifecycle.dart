part of 'session_core.dart';

const _wristActivityKinds = {
  WatchInboxEntry.kindSet,
  WatchInboxEntry.kindTimed,
  WatchInboxEntry.kindRound,
  WatchInboxEntry.kindHold,
};

extension SessionCoreLifecycleMethods on SessionCore {
  /// Ends the current session and, unless the watch saves its own workout for
  /// it, writes it to Health (plan 89c1): [writeToHealth] false is the wrist's
  /// own end (D-1); a session the wrist is running is read here, at the
  /// phone's end, before the wrist can hear of it (D-2).
  /// [atMs] is the instant the session ended when the caller knows it — the
  /// wrist's own end (D-14604); omitted, the phone's clock decides. Either way
  /// the end is never stored before the start (D-153).
  Future<void> endSession({required bool writeToHealth, int? atMs}) async {
    if (_currentSession == null) return;
    if (_currentSession!.endedAtMs != null) return;

    final wristSavesWorkout =
        _wristRunsSession?.call(_currentSession!.id) ?? false;

    _clearError();

    try {
      // D-10: Finish always finishes. A failing drop leaves the placeholders
      // where they are and never turns the end into an error.
      // D-11 (plan 218): a session the watch had a part in drops its planned
      // sets too, but keeps every exercise: a late wrist set for a removed
      // exercise would be lost. The wrist's own end, a session the wrist
      // runs, and a session with a staged wrist row all count as the watch's
      // part.
      try {
        final wristHadAHand =
            !writeToHealth ||
            wristSavesWorkout ||
            (await _repository.getWatchInboxEntriesForSession(
              _currentSession!.id,
            )).any((row) => row.origin == WatchInboxEntry.originWatch);
        if (!wristHadAHand) {
          await _dropUnloggedSets();
          await _dropNeverStartedTimers();
        } else {
          // Plan 218: a workout the watch took part in drops its planned sets
          // too, but keeps every exercise (a late wrist set for a removed
          // exercise would be lost) and waits for the import passes already
          // queued (a wrist set's row is written before its rest).
          final queue = _afterPendingWristImports;
          if (queue == null) {
            await _dropUnloggedSets(keepEfforts: true);
            await _dropNeverStartedTimers(keepEfforts: true);
          } else {
            await queue(() async {
              await _dropUnloggedSets(keepEfforts: true);
              await _dropNeverStartedTimers(keepEfforts: true);
            });
          }
        }
      } catch (_) {}
      await _timerManager.persistActiveRounds();
      await _timerManager.persistActiveTimedEntries();

      final now = atMs ?? _clock().millisecondsSinceEpoch;
      await _timerManager.persistOpenRests(now);
      final updatedSession = TrainingSession(
        id: _currentSession!.id,
        ownerUserId: _currentSession!.ownerUserId,
        routineTemplateId: _currentSession!.routineTemplateId,
        startedAtMs: _currentSession!.startedAtMs,
        // D-153: an end can never be stored before its start, whatever the
        // clock says (a start ahead of `now` is clamped up, not overtaken).
        endedAtMs: math.max(_currentSession!.startedAtMs, now),
        title: _currentSession!.title,
        note: _currentSession!.note,
        locationText: _currentSession!.locationText,
        modality: _currentSession!.modality,
        intent: _currentSession!.intent,
        perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
        sessionFeeling: _currentSession!.sessionFeeling,
        qualityRating: _currentSession!.qualityRating,
        isRolling: _currentSession!.isRolling,
        createdAtMs: _currentSession!.createdAtMs,
        updatedAtMs: now,
      );

      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;

      // D-13408: store the active-energy estimate before listeners hear the
      // session ended, so the summary reads it. Shielded twice (settle never
      // throws; a throw here must not flip the end into an error).
      try {
        await _activeEnergy?.settle(updatedSession.id);
      } catch (_) {}

      _notify();
    } catch (e) {
      _setError('Failed to end session: $e');
      return;
    }

    // Plan 251: the plan this routine workout fulfils. Outside the persistence
    // try/catch and shielded on its own: a failure here never turns the end
    // into an error.
    final endedSession = _currentSession;
    if (endedSession != null) {
      try {
        await _onSessionEnded?.call(endedSession);
      } catch (_) {}
    }

    // Platform health write. Deliberately outside the persistence
    // try/catch above: the session is already saved and the service is
    // contract-bound never to throw, so nothing here can flip the
    // session into an error state.
    final completedSession = _currentSession;
    if (completedSession != null && writeToHealth && !wristSavesWorkout) {
      await _healthSync?.onSessionCompleted(completedSession);
    }
  }

  /// Plan 157a: Finish keeps only the sets that were logged (D-1..D-7).
  ///
  /// A `set` entry is logged exactly when an `EntryRest` sits at its position
  /// + 1 (the session screen's `_isSetLogged`); one carrying the skip marker is
  /// kept (it counts for nothing). Every other `set` entry is a planned set
  /// nobody did and goes, highest position first so the rests below it never
  /// move. A set exercise left with no entry is removed. Quiet: no listener is
  /// told here, `endSession` notifies once.
  ///
  /// [keepEfforts] (plan 218) leaves an exercise with no set in place: for a
  /// workout the watch took part in, so a late wrist set still has an exercise
  /// to land in.
  ///
  /// A session the watch had a part in keeps its exercises (plan 218); see
  /// endSession.
  Future<void> _dropUnloggedSets({bool keepEfforts = false}) async {
    for (final effortList in _efforts.values) {
      for (final effort in List<SegmentEffort>.of(effortList)) {
        if (effort.effortKind != 'set') continue;
        // D-9: the store is the truth (the watch importer writes a wrist set's
        // rest straight to it); refresh the caches before deciding anything.
        final rows = List<EffortObservation>.of(
          await _repository.getEffortObservations(effort.id),
        );
        _observations[effort.id] = rows;
        _timerManager.setEntryRests(
          effort.id,
          await _repository.getEntryRests(effort.id),
        );

        final groups = EntryRows.setGroups(rows);
        final marked = {
          for (final rest in _timerManager.getEntryRests(effort.id))
            rest.entryIndex,
        };
        var kept = groups.length;
        var dropped = 0;
        for (var position = groups.length - 1; position >= 0; position--) {
          final group = groups[position];
          final skipped = group.rowFor(MetricIds.reps)?.valueBool ?? false;
          if (_setIsLogged(marked, position) || skipped) continue;

          final doomed = {for (final row in group.rows) row.id};
          for (final id in doomed) {
            await _repository.deleteObservation(id);
          }
          rows.removeWhere((row) => doomed.contains(row.id));
          await _timerManager.rekeyEntryRestsAfterDelete(effort.id, position);
          kept--;
          dropped++;
        }

        if (!keepEfforts && dropped > 0 && kept == 0) {
          await _repository.deleteEffort(effort.id);
          _observations.remove(effort.id);
          _timerManager.removeEffort(effort.id);
          effortList.removeWhere((e) => e.id == effort.id);
        }
      }
    }
  }

  /// Plan 257: Finish also drops the intervals, holds and rounds nobody
  /// started, the way [_dropUnloggedSets] drops the sets nobody logged (D-25701).
  ///
  /// An entry whose timer state is `notStarted` goes through the manager's own
  /// delete (which re-indexes the entries after it and deletes the entry's rows)
  /// and its rest is re-keyed, the order [deleteEntry] uses. The walk is from
  /// the last entry to the first so the indexes still to visit never move. A
  /// running or paused entry is never dropped. An exercise left with no entry
  /// is removed unless [keepEfforts] (a workout the watch took part in keeps its
  /// exercises, as for sets). Quiet apart from the manager's own change
  /// notifications: `endSession` notifies once at the end.
  Future<void> _dropNeverStartedTimers({bool keepEfforts = false}) async {
    for (final effortList in _efforts.values) {
      for (final effort in List<SegmentEffort>.of(effortList)) {
        final kind = effort.effortKind;
        if (kind != 'timed' && kind != 'drill' && kind != 'round') continue;

        var dropped = 0;
        if (kind == 'round') {
          final rounds = _timerManager.getRoundsForEffort(effort.id);
          for (var i = rounds.length - 1; i >= 0; i--) {
            if (rounds[i].state != RoundState.notStarted) continue;
            if (await _timerManager.deleteRound(effort.id, i)) {
              await _timerManager.rekeyEntryRestsAfterDelete(effort.id, i);
              dropped++;
            }
          }
        } else {
          final timed = _timerManager.getTimedInstancesForEffort(effort.id);
          for (var i = timed.length - 1; i >= 0; i--) {
            if (timed[i].state != TimedState.notStarted) continue;
            if (await _timerManager.deleteTimedEntry(effort.id, i)) {
              await _timerManager.rekeyEntryRestsAfterDelete(effort.id, i);
              dropped++;
            }
          }
        }

        final left = kind == 'round'
            ? _timerManager.getRoundsForEffort(effort.id).length
            : _timerManager.getTimedInstancesForEffort(effort.id).length;
        if (!keepEfforts && dropped > 0 && left == 0) {
          await _repository.deleteEffort(effort.id);
          _observations.remove(effort.id);
          _timerManager.removeEffort(effort.id);
          effortList.removeWhere((e) => e.id == effort.id);
        }
      }
    }
    // D-10: a failing drop leaves the placeholder where it is and is never an
    // error. The manager's deletes report a failure on the error channel, so it
    // is cleared here (`endSession` cleared it before the drop started).
    _clearError();
  }

  /// Plan 157a D-2 / plan 217: a set at [position] is logged exactly when an
  /// `EntryRest` sits at position + 1 ([marked] holds the rests' entry
  /// indexes). The drop and [completedExerciseCount] share this one rule.
  bool _setIsLogged(Set<int> marked, int position) =>
      marked.contains(position + 1);

  /// Plan 217: how many of the session's exercises the user did, for the
  /// Finish confirmation. A `set` exercise counts when at least one of its
  /// sets is logged (a skip-marked set alone does not count); a `timed`,
  /// `drill` or `round` exercise counts when any of its instances has been
  /// started. Reads the in-memory caches, like the screen does.
  int completedExerciseCount() {
    var count = 0;
    for (final effortList in _efforts.values) {
      for (final effort in effortList) {
        if (effort.effortKind == 'set') {
          final groups = EntryRows.setGroups(
            _observations[effort.id] ?? const <EffortObservation>[],
          );
          final marked = {
            for (final rest in _timerManager.getEntryRests(effort.id))
              rest.entryIndex,
          };
          for (var position = 0; position < groups.length; position++) {
            if (_setIsLogged(marked, position)) {
              count++;
              break;
            }
          }
        } else if (effort.effortKind == 'round') {
          if (_timerManager
              .getRoundsForEffort(effort.id)
              .any((round) => round.state != RoundState.notStarted)) {
            count++;
          }
        } else {
          if (_timerManager
              .getTimedInstancesForEffort(effort.id)
              .any((timed) => timed.state != TimedState.notStarted)) {
            count++;
          }
        }
      }
    }
    return count;
  }

  /// Plan 220 / plan 228: whether Finish would save a workout with nothing
  /// done in it: no exercise counts ([completedExerciseCount] is 0) and no
  /// wrist ACTIVITY row is staged for it (D-3: a `rest`, `effort_rating` or
  /// `session_end` row alone is not work). A workout the watch runs is
  /// decided after the import passes already queued (the seam `endSession`
  /// uses, plan 218), so a wrist set that has not landed yet still counts —
  /// the in-memory caches may not hold a set whose import pass is still
  /// queued. `_wristRunsSession` is not a reason to save the workout; it
  /// stays used by `endSession`.
  Future<bool> finishWouldSaveNothing() async {
    final session = _currentSession;
    if (session == null) return false;

    Future<bool> decide() async {
      if (completedExerciseCount() != 0) return false;
      final staged = await _repository.getWatchInboxEntriesForSession(
        session.id,
      );
      return !staged.any(
        (row) =>
            row.origin == WatchInboxEntry.originWatch &&
            _wristActivityKinds.contains(row.kind),
      );
    }

    // Plan 228: a wrist set's row is written before its rest, so the check
    // waits for the import passes already queued (the seam `endSession`
    // uses, plan 218) and reads the caches after both.
    final queue = _afterPendingWristImports;
    if (queue == null) return decide();
    var nothing = false;
    await queue(() async => nothing = await decide());
    return nothing;
  }

  /// Resets the session start timestamp to now.
  ///
  /// Called once when the first exercise is added to a live session so that
  /// the global elapsed timer begins counting from the moment training actually
  /// starts, rather than from when the empty session was created.
  ///
  /// A session that already has an end is history: a finished window is never
  /// reopened, so this writes nothing and the start stays where it was (D-153).
  Future<void> resetSessionTimerStart() async {
    if (_currentSession == null) return;

    _clearError();

    if (_currentSession!.endedAtMs != null) return;

    try {
      final now = _clock().millisecondsSinceEpoch;
      final updatedSession = TrainingSession(
        id: _currentSession!.id,
        ownerUserId: _currentSession!.ownerUserId,
        routineTemplateId: _currentSession!.routineTemplateId,
        startedAtMs: now,
        endedAtMs: _currentSession!.endedAtMs,
        title: _currentSession!.title,
        note: _currentSession!.note,
        locationText: _currentSession!.locationText,
        modality: _currentSession!.modality,
        intent: _currentSession!.intent,
        perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
        sessionFeeling: _currentSession!.sessionFeeling,
        qualityRating: _currentSession!.qualityRating,
        isRolling: _currentSession!.isRolling,
        createdAtMs: _currentSession!.createdAtMs,
        updatedAtMs: now,
      );

      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;
      _notify();
    } catch (e) {
      _setError('Failed to reset session timer start: $e');
    }
  }

  Future<void> discardCurrentSession() async {
    if (_currentSession == null) return;

    _clearError();

    final discarded = _currentSession!;
    try {
      // D-14603c: the timers a discard leaves running are stopped here, in
      // memory, before the row goes — a timer frame composed while the delete
      // is in flight can then only name stopped timers, and the row's own
      // rests are deleted with it.
      _timerManager.closeAllOpenRestsInSessionInMemory();
      await _repository.deleteSession(discarded.id);
      clearSession();
    } catch (e) {
      _setError('Failed to discard session: $e');
      return;
    }

    // Platform health delete (plan 89 D-4). Not awaited: the discard is
    // already complete and must not wait on the store; the service is
    // contract-bound never to throw.
    _healthSync?.onSessionDeleted(discarded);
  }

  /// Plan 230: what a confirmed "Start New Session?" does with the slot. A
  /// workout that is still open is really discarded (the store row goes, like
  /// the Discard button); a finished session shown in the slot is only
  /// released, never deleted.
  Future<void> discardUnfinishedSession() async {
    final current = _currentSession;
    if (current != null && current.endedAtMs == null) {
      await discardCurrentSession();
    } else {
      clearSession();
    }
  }

  Future<void> updateSessionNote(String note) async {
    if (_currentSession == null) return;

    _clearError();

    try {
      final now = _clock().millisecondsSinceEpoch;
      final updatedSession = TrainingSession(
        id: _currentSession!.id,
        ownerUserId: _currentSession!.ownerUserId,
        routineTemplateId: _currentSession!.routineTemplateId,
        startedAtMs: _currentSession!.startedAtMs,
        endedAtMs: _currentSession!.endedAtMs,
        title: _currentSession!.title,
        note: note,
        locationText: _currentSession!.locationText,
        modality: _currentSession!.modality,
        intent: _currentSession!.intent,
        perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
        sessionFeeling: _currentSession!.sessionFeeling,
        qualityRating: _currentSession!.qualityRating,
        isRolling: _currentSession!.isRolling,
        createdAtMs: _currentSession!.createdAtMs,
        updatedAtMs: now,
      );

      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;
      _notify();
    } catch (e) {
      _setError('Failed to update session note: $e');
    }
  }

  /// Moves the current session to start at [newStartedAtMs], keeping its
  /// length (a finished session's end moves with it). Returns false, and
  /// changes nothing, when there is no session, the new start is in the future,
  /// or the write fails (plan 267). Only the session's own start and end move;
  /// the moments recorded inside it keep their original times.
  Future<bool> updateSessionStart(int newStartedAtMs) async {
    final session = _currentSession;
    if (session == null) return false;
    final now = _clock().millisecondsSinceEpoch;
    if (newStartedAtMs > now) return false;
    _clearError();
    try {
      final ended = session.endedAtMs;
      final newEndedAtMs = ended == null
          ? null
          : newStartedAtMs + (ended - session.startedAtMs);
      final updatedSession = TrainingSession(
        id: session.id,
        ownerUserId: session.ownerUserId,
        routineTemplateId: session.routineTemplateId,
        startedAtMs: newStartedAtMs,
        endedAtMs: newEndedAtMs,
        title: session.title,
        note: session.note,
        locationText: session.locationText,
        modality: session.modality,
        intent: session.intent,
        perceivedSessionRpe: session.perceivedSessionRpe,
        sessionFeeling: session.sessionFeeling,
        qualityRating: session.qualityRating,
        isRolling: session.isRolling,
        createdAtMs: session.createdAtMs,
        updatedAtMs: now,
      );
      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;
      _notify();
      return true;
    } catch (e) {
      _setError('Failed to change session time: $e');
      return false;
    }
  }

  Future<void> updateSessionEndTime(int durationSecs) async {
    if (_currentSession == null) return;
    if (durationSecs <= 0) return;
    _clearError();
    try {
      final now = _clock().millisecondsSinceEpoch;
      final newEndedAtMs = math.max(
        _currentSession!.startedAtMs,
        _currentSession!.startedAtMs + (durationSecs * 1000),
      );
      final updatedSession = TrainingSession(
        id: _currentSession!.id,
        ownerUserId: _currentSession!.ownerUserId,
        routineTemplateId: _currentSession!.routineTemplateId,
        startedAtMs: _currentSession!.startedAtMs,
        endedAtMs: newEndedAtMs,
        title: _currentSession!.title,
        note: _currentSession!.note,
        locationText: _currentSession!.locationText,
        modality: _currentSession!.modality,
        intent: _currentSession!.intent,
        perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
        sessionFeeling: _currentSession!.sessionFeeling,
        qualityRating: _currentSession!.qualityRating,
        isRolling: _currentSession!.isRolling,
        createdAtMs: _currentSession!.createdAtMs,
        updatedAtMs: now,
      );
      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;

      // D-13408: an edited duration changes an estimate; a measured row stays.
      try {
        await _activeEnergy?.settle(updatedSession.id);
      } catch (_) {}

      _notify();
    } catch (e) {
      _setError('Failed to update session end time: $e');
    }
  }

  /// Moves the end already stored on the held session to [atMs] when that is
  /// later (D-14604): an ended workout keeps the status of the first ending and
  /// takes the latest instant either side has. A session that has not ended, a
  /// row this phone does not hold, and an instant at or before the end already
  /// stored are all left alone — the settle is what a moved end owes.
  Future<void> catchUpEndedSession(int atMs) async {
    final session = _currentSession;
    if (session == null) return;
    final heldEndMs = session.endedAtMs;
    if (heldEndMs == null) return;
    final endMs = math.max(heldEndMs, atMs);
    if (endMs == heldEndMs) return;

    _clearError();
    late final TrainingSession updatedSession;
    try {
      updatedSession = TrainingSession(
        id: session.id,
        ownerUserId: session.ownerUserId,
        routineTemplateId: session.routineTemplateId,
        startedAtMs: session.startedAtMs,
        endedAtMs: endMs,
        title: session.title,
        note: session.note,
        locationText: session.locationText,
        modality: session.modality,
        intent: session.intent,
        perceivedSessionRpe: session.perceivedSessionRpe,
        sessionFeeling: session.sessionFeeling,
        qualityRating: session.qualityRating,
        isRolling: session.isRolling,
        createdAtMs: session.createdAtMs,
        updatedAtMs: _clock().millisecondsSinceEpoch,
      );

      await _repository.updateSession(updatedSession);
      _currentSession = updatedSession;

      // D-13408: a longer span changes an estimate; a measured row stays.
      try {
        await _activeEnergy?.settle(updatedSession.id);
      } catch (_) {}

      _notify();
    } catch (e) {
      _setError('Failed to catch up the session end: $e');
      return;
    }

    // D-14634: the moved end moves the session's Health workout with it. The
    // service is contract-bound never to throw and rewrites only a workout
    // the phone itself wrote (D-14636), so this stays outside the catch above.
    await _healthSync?.rewriteWorkout(
      updatedSession,
      previousEndedAtMs: heldEndMs,
    );
  }

  Future<void> updateSessionFeeling(
    String sessionId,
    int feeling, {
    bool onlyIfUnrated = false,
  }) async {
    if (feeling < 1 || feeling > 5) return;

    _clearError();

    try {
      if (onlyIfUnrated) {
        final stored = await _repository.getSession(sessionId);
        if (stored?.sessionFeeling != null) return;
      }
      await _repository.updateSessionFeeling(sessionId, feeling);

      if (_currentSession?.id == sessionId) {
        final now = _clock().millisecondsSinceEpoch;
        _currentSession = TrainingSession(
          id: _currentSession!.id,
          ownerUserId: _currentSession!.ownerUserId,
          routineTemplateId: _currentSession!.routineTemplateId,
          startedAtMs: _currentSession!.startedAtMs,
          endedAtMs: _currentSession!.endedAtMs,
          title: _currentSession!.title,
          note: _currentSession!.note,
          locationText: _currentSession!.locationText,
          modality: _currentSession!.modality,
          intent: _currentSession!.intent,
          perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
          sessionFeeling: feeling,
          qualityRating: _currentSession!.qualityRating,
          isRolling: _currentSession!.isRolling,
          createdAtMs: _currentSession!.createdAtMs,
          updatedAtMs: now,
        );
      }

      _notify();
    } catch (e) {
      _setError('Failed to update session feeling: $e');
      return;
    }

    await _sendRatingToHealth(sessionId);
  }

  /// Plan 90 D-4: a saved rating of a finished session becomes its Fitness
  /// workout's effort. Not awaited past the read: the service retries for
  /// minutes and is contract-bound never to throw. A running session has no
  /// workout yet and asks nothing.
  Future<void> _sendRatingToHealth(String sessionId) async {
    final healthSync = _healthSync;
    if (healthSync == null) return;
    TrainingSession? rated;
    try {
      rated = _currentSession?.id == sessionId
          ? _currentSession
          : await _repository.getSession(sessionId);
    } catch (_) {
      // The rating is saved; a failed read only means no effort is sent.
      return;
    }
    if (rated == null || rated.endedAtMs == null) return;
    healthSync.onSessionRated(rated);
  }

  /// Adopts a rating the wrist's import already wrote (D-1): updates the live
  /// [currentSession] when it is that session and notifies. Writes nothing.
  Future<void> adoptSessionFeeling(String sessionId, int feeling) async {
    if (feeling < 1 || feeling > 5) return;
    if (_currentSession?.id != sessionId) return;
    if (_currentSession!.sessionFeeling == feeling) return;

    final now = _clock().millisecondsSinceEpoch;
    _currentSession = TrainingSession(
      id: _currentSession!.id,
      ownerUserId: _currentSession!.ownerUserId,
      routineTemplateId: _currentSession!.routineTemplateId,
      startedAtMs: _currentSession!.startedAtMs,
      endedAtMs: _currentSession!.endedAtMs,
      title: _currentSession!.title,
      note: _currentSession!.note,
      locationText: _currentSession!.locationText,
      modality: _currentSession!.modality,
      intent: _currentSession!.intent,
      perceivedSessionRpe: _currentSession!.perceivedSessionRpe,
      sessionFeeling: feeling,
      qualityRating: _currentSession!.qualityRating,
      isRolling: _currentSession!.isRolling,
      createdAtMs: _currentSession!.createdAtMs,
      updatedAtMs: now,
    );
    _notify();
  }

  Future<void> updateSessionRpe(String sessionId, double rpe) async {
    if (rpe < 1.0 || rpe > 10.0) return;

    _clearError();

    try {
      if (_currentSession?.id == sessionId) {
        final now = _clock().millisecondsSinceEpoch;
        final updatedSession = TrainingSession(
          id: _currentSession!.id,
          ownerUserId: _currentSession!.ownerUserId,
          routineTemplateId: _currentSession!.routineTemplateId,
          startedAtMs: _currentSession!.startedAtMs,
          endedAtMs: _currentSession!.endedAtMs,
          title: _currentSession!.title,
          note: _currentSession!.note,
          locationText: _currentSession!.locationText,
          modality: _currentSession!.modality,
          intent: _currentSession!.intent,
          perceivedSessionRpe: rpe,
          sessionFeeling: _currentSession!.sessionFeeling,
          qualityRating: _currentSession!.qualityRating,
          isRolling: _currentSession!.isRolling,
          createdAtMs: _currentSession!.createdAtMs,
          updatedAtMs: now,
        );

        await _repository.updateSession(updatedSession);
        _currentSession = updatedSession;
      }

      _notify();
    } catch (e) {
      _setError('Failed to update session RPE: $e');
    }
  }

  /// The `entryId` of every applied inbox row of the current session: the
  /// watermark an edit snapshot taken now would carry (D-801).
  ///
  /// Read before the session's rows are loaded, so the watermark can only be
  /// a subset of what the snapshot's rows reflect. An empty set when there is
  /// no current session.
  Future<Set<String>> appliedWatchEntryIds() async {
    final session = _currentSession;
    if (session == null) return <String>{};

    final rows = await _repository.getWatchInboxEntriesForSession(session.id);
    return {
      for (final row in rows)
        if (row.appliedAtMs != null) row.entryId,
    };
  }

  SessionEditSnapshot? snapshotSessionState({
    Set<String>? watchEntryIdsAppliedAtSnapshot,
  }) {
    if (_currentSession == null) return null;

    return SessionEditSnapshot(
      sessionId: _currentSession!.id,
      watchEntryIdsAppliedAtSnapshot: watchEntryIdsAppliedAtSnapshot,
      segments: List<SessionSegment>.from(_segments),
      efforts: {
        for (final entry in _efforts.entries)
          entry.key: List<SegmentEffort>.from(entry.value),
      },
      observations: {
        for (final entry in _observations.entries)
          entry.key: List<EffortObservation>.from(entry.value),
      },
      roundInstances: {
        for (final entry in _timerManager.roundInstancesSnapshot.entries)
          entry.key: List<RoundInstance>.from(entry.value),
      },
      timedInstances: {
        for (final entry in _timerManager.timedInstancesSnapshot.entries)
          entry.key: List<TimedInstance>.from(entry.value),
      },
      entryRests: {
        for (final entry in _timerManager.entryRestsSnapshot.entries)
          entry.key: List<EntryRest>.from(entry.value),
      },
      exerciseCache: Map<String, Exercise>.from(_exerciseCache),
      sensorSummaries: List<SensorSummary>.from(_sensorSummaries),
    );
  }

  Future<void> restoreSessionSnapshot(SessionEditSnapshot snapshot) async {
    _clearError();

    try {
      final currentEffortIds = <String>{
        for (final effortList in _efforts.values)
          for (final effort in effortList) effort.id,
      };
      final snapshotEffortIds = <String>{
        for (final effortList in snapshot.efforts.values)
          for (final effort in effortList) effort.id,
      };

      for (final effortId in currentEffortIds) {
        if (!snapshotEffortIds.contains(effortId)) {
          await _repository.deleteEffort(effortId);
        }
      }

      for (final segmentId in snapshot.efforts.keys) {
        for (final effort in snapshot.efforts[segmentId]!) {
          if (!currentEffortIds.contains(effort.id)) {
            await _repository.createEffort(effort);
            for (final obs in snapshot.observations[effort.id] ?? []) {
              await _repository.createObservation(obs);
            }
            for (final ri in snapshot.roundInstances[effort.id] ?? []) {
              await _repository.createRoundInstance(ri);
            }
            for (final ti in snapshot.timedInstances[effort.id] ?? []) {
              await _repository.createTimedInstance(ti);
            }
            // D-9: the effort's rests went with it (deleteEffort cascades), so
            // the snapshot's copies come back with the effort.
            for (final rest in snapshot.entryRests[effort.id] ?? []) {
              await _repository.createEntryRest(rest);
            }
          }
        }
      }

      for (final effortId in currentEffortIds) {
        if (!snapshotEffortIds.contains(effortId)) {
          continue;
        }

        await _repository.deleteObservationsForEffort(effortId);
        for (final obs in snapshot.observations[effortId] ?? []) {
          await _repository.createObservation(obs);
        }

        if (snapshot.roundInstances.containsKey(effortId)) {
          await _repository.deleteRoundInstancesForEffort(effortId);
          for (final ri in snapshot.roundInstances[effortId]!) {
            await _repository.createRoundInstance(ri);
          }
        }

        if (snapshot.timedInstances.containsKey(effortId)) {
          await _repository.deleteTimedInstancesForEffort(effortId);
          for (final ti in snapshot.timedInstances[effortId]!) {
            await _repository.createTimedInstance(ti);
          }
        }

        // D-9: a delete re-keyed this effort's rests (D-1), so the snapshot's
        // rests replace whatever the edit left.
        if (snapshot.entryRests.containsKey(effortId)) {
          await _repository.deleteEntryRestsForEffort(effortId);
          for (final rest in snapshot.entryRests[effortId]!) {
            await _repository.createEntryRest(rest);
          }
        }
      }

      // D-131 deleted the summaries of every target the edit or the deletes
      // above removed; the targets are back, so put their summaries back.
      // Put-if-absent leaves every summary that survived untouched.
      for (final summary in snapshot.sensorSummaries) {
        await _repository.createSensorSummary(summary);
      }

      // A watch entry that arrived while the screen was open is not in the
      // snapshot's rows, so the loops above just deleted it. Un-mark it and
      // run one ordinary import pass to bring it back (D-802, D-804, D-805).
      // After the loops, so they cannot delete what the pass re-creates, and
      // before the reload, so the screen shows the recovered rows.
      final watermark = snapshot.watchEntryIdsAppliedAtSnapshot;
      final recovery = _lateEntryRecovery;
      if (watermark != null && recovery != null) {
        await recovery.recoverEntriesAppliedSince(snapshot.sessionId, watermark);
      }

      _exerciseCache
        ..clear()
        ..addAll(snapshot.exerciseCache);

      await loadSessionData();
    } catch (e) {
      _setError('Failed to restore session snapshot: $e');
      rethrow;
    }
  }
}
