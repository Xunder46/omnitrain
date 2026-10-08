/// The watch session inbox: where everything the phone learns about a wrist
/// session waits until it becomes history.
///
/// Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`
/// (Stats PR 2), D-132 – D-139, D-142.
///
/// Every wrist effort entry, effort rating and session end — from an
/// `observations_up` or from a wrist `session_snapshot` — is staged in the
/// repository as it arrives (`WatchInboxEntry`, put-if-absent by `entryId`),
/// before any other consumer answers the message. So are the phone's own
/// annotations on a wrist session: the live corrections and deletions it sends
/// ([WatchInboxStagingTransport]) and its own effort rating
/// ([recordPhoneRating]). `WatchSessionImporter` turns what is staged into
/// history once the session's `session_end` is staged, and this class then
/// acknowledges what was applied with a `receipt` — never on mere arrival, so
/// the wrist keeps owing an entry the phone has not yet made history of.
///
/// Staging first is what makes the import durable: a phone that stops between
/// arrival and import imports at its next start ([resume]), and a redelivered
/// or altered copy never replaces what was staged.
library;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/platform/watch_delivery.dart';
import '../../core/services/watch_session_importer.dart';
import '../../core/sync_protocol/message_validator.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import 'live_session_mirror_state.dart';
import 'watch_nutrition_log_bridge.dart';

/// What [WatchSessionInbox.receive] did with a message.
enum WatchInboxOutcome {
  /// At least one entry was staged for the first time.
  staged,

  /// Everything it carried was already staged: a redelivery. What was applied
  /// is acknowledged again, and nothing else happens.
  unchanged,

  /// Conformant, and carrying nothing the inbox stages: reference data, a
  /// nutrition quick-log, session structure.
  ignored,

  /// This build could not read the message. Nothing was staged.
  refused,

  /// Staging or applying failed. What was staged stays staged, and is applied
  /// by the next message for its session or at the next start.
  failed,
}

/// What one message did to the inbox.
class WatchInboxResult {
  const WatchInboxResult({
    required this.outcome,
    this.stagedEntryIds = const [],
    this.receiptedEntryIds = const [],
  });

  final WatchInboxOutcome outcome;

  /// The entries this message staged for the first time.
  final List<String> stagedEntryIds;

  /// The entries the phone's receipt named in answer.
  final List<String> receiptedEntryIds;
}

/// What a phone screen may do to a wrist session's history: record the phone's
/// own effort rating for it (D-138, D-139).
///
/// [WatchSessionInbox] is the one implementation. Screens receive this narrow
/// type rather than the inbox, so staging and applying what the wrist sends
/// stay out of their reach.
abstract interface class WatchSessionRatings {
  /// Records [rating] as the phone's own for the wrist session
  /// [watchSessionId]; see [WatchSessionInbox.recordPhoneRating].
  Future<bool> recordPhoneRating(String watchSessionId, int rating);
}

/// What an Edit Session Discard may do to a wrist session's inbox: recover
/// the entries that arrived while the screen was open (D-802, D-804).
///
/// [WatchSessionInbox] is the one implementation. The restore receives this
/// narrow type rather than the inbox, so nothing else about staging and
/// applying what the wrist sends is in its reach.
abstract interface class WatchLateEntryRecovery {
  /// Recovers the session's inbox rows that were applied after
  /// [appliedAtSnapshot] was read: un-marks exactly those rows and runs one
  /// ordinary import pass, which re-materialises them (D-802, D-804).
  ///
  /// Writes nothing else — no row is created, deleted or edited by the
  /// recovery itself. A session with no such row is left untouched.
  Future<void> recoverEntriesAppliedSince(
    String watchSessionId,
    Set<String> appliedAtSnapshot,
  );
}

class WatchSessionInbox implements WatchSessionRatings, WatchLateEntryRecovery {
  WatchSessionInbox({
    required WorkoutRepository repository,
    WatchMirrorTransport? transport,
    SyncProtocolValidator? validator,
    DateTime Function()? clock,
    String Function()? idFactory,
    Future<void> Function()? onHistoryChanged,
    void Function(Object error, StackTrace stack)? onFailure,
    bool Function(String sessionId)? phoneOwnsSession,
    Future<void> Function(String sessionId, List<String> effortIds)?
    onSessionRowsChanged,
  }) : _repository = repository,
       _transport = transport,
       _validator = validator,
       _clock = clock ?? _utcNow,
       _newId = idFactory ?? _uuid,
       _onHistoryChanged = onHistoryChanged,
       _onFailure = onFailure ?? _report,
       _phoneOwnsSession = phoneOwnsSession,
       _onSessionRowsChanged = onSessionRowsChanged,
       _importer = WatchSessionImporter(
         repository: repository,
         clock: clock ?? _utcNow,
       );

  static DateTime _utcNow() => DateTime.now().toUtc();

  static const Uuid _uuidV4 = Uuid();

  static String _uuid() => _uuidV4.v4();

  static void _report(Object error, StackTrace stack) {
    debugPrint('Watch session inbox: $error');
    debugPrintStack(stackTrace: stack);
  }

  final WorkoutRepository _repository;

  /// Where the receipt goes. Null leaves the wrist owing what it sent.
  final WatchMirrorTransport? _transport;
  final SyncProtocolValidator? _validator;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Called once for each message, annotation or start-up resume that changed
  /// history — the calendar's refresh in the shipping graph (D-142).
  final Future<void> Function()? _onHistoryChanged;
  final void Function(Object error, StackTrace stack) _onFailure;
  final WatchSessionImporter _importer;

  /// Whether a session id is one the phone owns as its own current session —
  /// the mirror adopted it off the wrist (D-2). Asked of the adoption bridge,
  /// which is the one place that question is answered. Null (a test, a build
  /// with no session state) imports every session the ordinary way.
  final bool Function(String sessionId)? _phoneOwnsSession;

  /// Called once per settled session whose merge wrote rows, with the efforts
  /// it wrote — the live session refresh (D-17). Null (a test, a build with no
  /// session state) refreshes nothing.
  final Future<void> Function(String sessionId, List<String> effortIds)?
  _onSessionRowsChanged;

  /// The fields each staged kind must carry to become history — the ones the
  /// `observations_up` schema requires of it. A snapshot entry is held only to
  /// the shared entry shape (Assumption A-3 of the plan), so an entry lacking
  /// them is not staged: a partial copy staged first would keep the whole one
  /// out, since staging never replaces a row.
  static const Map<String, List<String>> _requiredFields = {
    WatchInboxEntry.kindSet: ['sessionExerciseId', 'exerciseId', 'reps'],
    WatchInboxEntry.kindTimed: [
      'sessionExerciseId',
      'exerciseId',
      'startedAt',
      'endedAt',
    ],
    WatchInboxEntry.kindRound: [
      'sessionExerciseId',
      'exerciseId',
      'startedAt',
      'endedAt',
      'roundNumber',
    ],
    WatchInboxEntry.kindHold: [
      'sessionExerciseId',
      'exerciseId',
      'startedAt',
      'endedAt',
    ],
    WatchInboxEntry.kindEffortRating: ['rating'],
    WatchInboxEntry.kindSessionEnd: ['startedAt', 'endedAt', 'status'],
  };

  // ---------------------------------------------------------------------------
  // Incoming
  // ---------------------------------------------------------------------------

  /// Stages what [envelope] carries, applies what can be applied, and
  /// acknowledges it.
  ///
  /// The router hands every message here before the mirror or the nutrition
  /// bridge sees it (D-132). This never throws: a failure is reported, and
  /// what was staged is applied later.
  Future<WatchInboxResult> receive(Map<String, Object?> envelope) async {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (!decision.accepted) {
      return const WatchInboxResult(outcome: WatchInboxOutcome.refused);
    }

    final events = _stageable(envelope);
    if (events.isEmpty) {
      return const WatchInboxResult(outcome: WatchInboxOutcome.ignored);
    }

    try {
      final receivedAtMs = _nowMs();
      final staged = <String>[];
      final sessions = <String>{};
      for (final (sessionId, event) in events) {
        final entry = _entryFor(sessionId, event, receivedAtMs);
        if (entry == null) continue;
        sessions.add(sessionId);
        if (await _repository.stageWatchInboxEntry(entry)) {
          staged.add(entry.entryId);
        }
      }

      final receipted = await _settle(
        sessions,
        redelivered: [for (final (_, event) in events) event['entryId']],
      );
      return WatchInboxResult(
        outcome: staged.isEmpty
            ? WatchInboxOutcome.unchanged
            : WatchInboxOutcome.staged,
        stagedEntryIds: staged,
        receiptedEntryIds: receipted,
      );
    } catch (error, stack) {
      _onFailure(error, stack);
      return const WatchInboxResult(outcome: WatchInboxOutcome.failed);
    }
  }

  /// Applies every staged session whose `session_end` has not been applied —
  /// an import the phone had not run when it last stopped (D-132). Called
  /// once, at start.
  Future<void> resume() async {
    try {
      await _settle(await _repository.getWatchSessionIdsWithUnappliedEnd());
    } catch (error, stack) {
      _onFailure(error, stack);
    }
  }

  // ---------------------------------------------------------------------------
  // The phone's own annotations
  // ---------------------------------------------------------------------------

  /// Records the phone's own effort rating for the wrist session
  /// [watchSessionId] (D-138, D-139).
  ///
  /// Written straight to the session when it is already history, through the
  /// repository's rating update, and — because that changes what the calendar
  /// shows — the rest of history is told; staged as the phone's own rating
  /// otherwise, so the import uses it instead of the wrist's. Answers whether
  /// the rating was recorded: a rating off the scale, or a second phone rating
  /// for a session not yet imported, is not.
  @override
  Future<bool> recordPhoneRating(String watchSessionId, int rating) async {
    if (rating < 1 || rating > 5) return false;
    try {
      if (await _repository.getSession(watchSessionId) != null) {
        await _repository.updateSessionFeeling(watchSessionId, rating);
        await _onHistoryChanged?.call();
        return true;
      }
      final now = _nowMs();
      final stored = await _repository.stageWatchInboxEntry(
        WatchInboxEntry(
          entryId: WatchInboxEntry.phoneRatingId(watchSessionId),
          watchSessionId: watchSessionId,
          kind: WatchInboxEntry.kindPhoneRating,
          origin: WatchInboxEntry.originPhone,
          payload: {'rating': rating},
          receivedAtMs: now,
        ),
      );
      await _settle({watchSessionId});
      return stored;
    } catch (error, stack) {
      _onFailure(error, stack);
      return false;
    }
  }

  /// Stages the phone's corrections and deletions of wrist entries in
  /// [envelope] — a `structure_change` the phone is about to send — so they
  /// reach history however the session's entries arrive (D-137).
  ///
  /// [WatchInboxStagingTransport] calls this before the message leaves.
  Future<void> stagePhoneChanges(Map<String, Object?> envelope) async {
    if (envelope['type'] != 'structure_change') return;
    final sessionId = envelope['sessionId'];
    final payload = envelope['payload'];
    if (sessionId is! String || sessionId.isEmpty || payload is! Map) return;
    final changeId = payload['changeId'];
    final changes = payload['changes'];
    if (changeId is! String || changeId.isEmpty || changes is! List) return;

    try {
      final now = _nowMs();
      var stagedAny = false;
      for (var index = 0; index < changes.length; index++) {
        final change = changes[index];
        if (change is! Map) continue;
        final kind = switch (change['kind']) {
          'correct_entry' => WatchInboxEntry.kindPhoneCorrection,
          'delete_entry' => WatchInboxEntry.kindPhoneDeletion,
          _ => null,
        };
        final entryId = change['entryId'];
        if (kind == null || entryId is! String || entryId.isEmpty) continue;
        final stored = await _repository.stageWatchInboxEntry(
          WatchInboxEntry(
            entryId: WatchInboxEntry.phoneChangeId(changeId, index),
            watchSessionId: sessionId,
            kind: kind,
            origin: WatchInboxEntry.originPhone,
            payload: Map<String, dynamic>.from(change),
            receivedAtMs: now,
          ),
        );
        stagedAny = stagedAny || stored;
      }
      // A change to a session already in history edits it now.
      if (stagedAny) await _settle({sessionId});
    } catch (error, stack) {
      _onFailure(error, stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Recovering what arrived during an Edit Session
  // ---------------------------------------------------------------------------

  /// Un-marks the session's late rows and runs one ordinary import pass
  /// (D-802, D-804).
  ///
  /// The late rows are the applied ones whose `entryId` is not in
  /// [appliedAtSnapshot] — the watermark the edit snapshot recorded. One
  /// rule, no origin or kind filter: a late wrist entry, a late phone
  /// correction and a late phone deletion are all recovered the same way.
  /// Nothing is written when there is no late row.
  @override
  Future<void> recoverEntriesAppliedSince(
    String watchSessionId,
    Set<String> appliedAtSnapshot,
  ) async {
    try {
      final rows = await _repository.getWatchInboxEntriesForSession(
        watchSessionId,
      );
      final late = [
        for (final row in rows)
          if (row.appliedAtMs != null && !appliedAtSnapshot.contains(row.entryId))
            row.entryId,
      ];
      if (late.isEmpty) return;

      await _repository.clearWatchInboxApplied(late);
      await _settle({watchSessionId});
    } catch (error, stack) {
      _onFailure(error, stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Applying and acknowledging
  // ---------------------------------------------------------------------------

  /// Chains every [_settle] pass after the one before it, so two frames for
  /// one session — or for two different ones — never settle at once (F-2).
  /// The wrist sends one message per stored observation without waiting for
  /// the last one's handler, and [receive], [resume], [recordPhoneRating]
  /// and [stagePhoneChanges] each call [_settle] on their own, so nothing
  /// upstream of it can serialise them for it.
  Future<void> _settleChain = Future<void>.value();

  /// Applies [sessionIds], then acknowledges what was applied: what these
  /// passes applied, and any of [redelivered] applied before — a wrist that
  /// re-sends an entry did not get the receipt for it.
  ///
  /// Queued behind whatever pass [_settle] is already running, so this pass
  /// reads the inbox only after every earlier one has finished writing to
  /// it — never concurrently, whatever order the calls arrive in.
  ///
  /// Returns the entry ids this pass receipted. Whether history changed is not
  /// part of the answer: [_settleNow] refreshes it itself, so a caller can
  /// neither forget to nor double it (review V-3).
  Future<List<String>> _settle(
    Iterable<String> sessionIds, {
    List<Object?> redelivered = const [],
  }) {
    final result = _settleChain.then(
      (_) => _settleNow(sessionIds, redelivered: redelivered),
    );
    // The chain must keep moving even when this pass fails, or one failure
    // would stall every settle queued after it. The failure itself still
    // reaches this call's own caller through the returned future.
    _settleChain = result.then((_) {}, onError: (_, _) {});
    return result;
  }

  Future<List<String>> _settleNow(
    Iterable<String> sessionIds, {
    List<Object?> redelivered = const [],
  }) async {
    final receipted = <String>[];
    var changed = false;
    for (final sessionId in sessionIds) {
      final pass = await _importer.apply(
        sessionId,
        phoneOwnsSession: _phoneOwnsSession?.call(sessionId) ?? false,
      );
      receipted.addAll(pass.appliedEntryIds);
      changed = changed || pass.historyChanged;
      // The merge wrote rows into the phone's own live session: refresh exactly
      // the efforts it wrote, before anything downstream sees the receipt
      // (D-17). A pass that wrote nothing names no effort and refreshes nothing.
      if (pass.changedEffortIds.isNotEmpty) {
        await _onSessionRowsChanged?.call(sessionId, pass.changedEffortIds);
      }
    }
    for (final entryId in redelivered) {
      if (entryId is! String || receipted.contains(entryId)) continue;
      final row = await _repository.getWatchInboxEntry(entryId);
      if (row != null &&
          row.origin == WatchInboxEntry.originWatch &&
          row.appliedAtMs != null) {
        receipted.add(entryId);
      }
    }

    final transport = _transport;
    if (transport != null && receipted.isNotEmpty) {
      await transport.send(
        WatchNutritionLogBridge.receiptFor(
          entryIds: receipted,
          sentAt: _clock(),
          messageId: _newId(),
        ),
      );
    }
    if (changed) await _onHistoryChanged?.call();
    return receipted;
  }

  // ---------------------------------------------------------------------------
  // What is staged
  // ---------------------------------------------------------------------------

  /// The wrist entries [envelope] carries that the inbox stages, with the
  /// session each belongs to: the events of an `observations_up`, and the
  /// entries of a wrist `session_snapshot`. Nutrition quick-logs are the
  /// nutrition bridge's alone.
  static List<(String, Map<String, Object?>)> _stageable(
    Map<String, Object?> envelope,
  ) {
    final payload = envelope['payload'];
    if (payload is! Map) return const [];

    final String? sessionId;
    final Object? entries;
    switch (envelope['type']) {
      case 'observations_up':
        sessionId = envelope['sessionId'] as String?;
        entries = payload['events'];
      case 'session_snapshot' when envelope['origin'] == 'watch':
        sessionId = payload['sessionId'] as String?;
        entries = payload['entries'];
      default:
        return const [];
    }
    if (sessionId == null || sessionId.isEmpty || entries is! List) {
      return const [];
    }

    return [
      for (final entry in entries)
        if (entry is Map && _isStageable(entry))
          (sessionId, entry.cast<String, Object?>()),
    ];
  }

  static bool _isStageable(Map<Object?, Object?> entry) {
    final entryId = entry['entryId'];
    final required = _requiredFields[entry['kind']];
    if (entryId is! String || entryId.isEmpty || required == null) {
      return false;
    }
    for (final field in required) {
      if (entry[field] == null) return false;
    }
    return true;
  }

  /// The staged row for [event], or null when the model refuses it (A-15).
  static WatchInboxEntry? _entryFor(
    String sessionId,
    Map<String, Object?> event,
    int receivedAtMs,
  ) {
    try {
      return WatchInboxEntry(
        entryId: event['entryId']! as String,
        watchSessionId: sessionId,
        kind: event['kind']! as String,
        origin: WatchInboxEntry.originWatch,
        payload: Map<String, dynamic>.from(event),
        receivedAtMs: receivedAtMs,
      );
    } on ArgumentError {
      return null;
    }
  }

  int _nowMs() => _clock().toUtc().millisecondsSinceEpoch;
}

/// The mirror's transport, with the phone's corrections and deletions of wrist
/// entries staged in [WatchSessionInbox] before each message leaves (D-137).
///
/// A decorator rather than a hook on the mirror, so the mirror keeps one job
/// — the live session — and the inbox sees exactly what the wrist is sent.
class WatchInboxStagingTransport implements WatchMirrorTransport {
  WatchInboxStagingTransport({
    required WatchMirrorTransport inner,
    required WatchSessionInbox inbox,
  }) : _inner = inner,
       _inbox = inbox;

  final WatchMirrorTransport _inner;
  final WatchSessionInbox _inbox;

  @override
  Future<WatchDelivery> send(Map<String, Object?> envelope) async {
    await _inbox.stagePhoneChanges(envelope);
    return _inner.send(envelope);
  }

  @override
  Future<void> requestSnapshot() => _inner.requestSnapshot();
}
