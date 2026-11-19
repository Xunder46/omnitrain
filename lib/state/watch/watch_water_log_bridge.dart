// The phone's half of a glass of water tapped on the wrist.
//
// Plan: `docs/plans/2026-11-01-94-watch-water-logging-plan/`, D-3, D-8(b),
// D-13; scenarios S-94a-13 to S-94a-20.
//
// The wrist sends each tap as a one-glass change, never a total, so glasses
// tapped on both devices while they were apart all count. The phone applies a
// tap once — its id is kept with the day's volume — to the day the glass was
// tapped, acknowledges it, and answers with the count of the phone's today and
// the taps that count already includes, so the wrist can show an exact number.

library;

import 'package:uuid/uuid.dart';

import '../../core/sync_protocol/message_validator.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/watch_reference_sync.dart';
import '../../data/repositories/workout_repository.dart';
import '../../watch/session/watch_records.dart';
import '../nutrition_state.dart';
import 'live_session_mirror_state.dart';
import 'watch_nutrition_log_bridge.dart';

/// What [WatchWaterLogBridge.receive] did with a message.
enum WatchWaterLogOutcome {
  /// The message carried water taps, and the phone has taken each one on:
  /// applied now, applied before (a redelivery), or past the day's cap.
  applied,

  /// Conformant, and no water tap in it.
  ignored,

  /// This build could not read the message. Nothing was applied or answered.
  refused,
}

/// What one message did to the day's water.
class WatchWaterLogResult {
  const WatchWaterLogResult({
    required this.outcome,
    this.changedTapIds = const [],
    this.acknowledgedEntryIds = const [],
  });

  final WatchWaterLogOutcome outcome;

  /// The taps that changed the stored water in this call, in message order.
  final List<String> changedTapIds;

  /// The taps the receipt named: every tap the phone could read, whether it
  /// changed the water now or had already.
  final List<String> acknowledgedEntryIds;
}

/// Applies the wrist's `water_glass` taps to the phone's day water.
class WatchWaterLogBridge {
  WatchWaterLogBridge({
    required NutritionState nutrition,
    required WorkoutRepository repository,
    SyncProtocolValidator? validator,
    WatchMirrorTransport? transport,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) : _nutrition = nutrition,
       _repository = repository,
       _validator = validator,
       _transport = transport,
       _clock = clock ?? _utcNow,
       _newId = idFactory ?? _uuid;

  static DateTime _utcNow() => DateTime.now().toUtc();

  static const Uuid _uuidV4 = Uuid();

  static String _uuid() => _uuidV4.v4();

  final NutritionState _nutrition;

  /// Read for the count the answer carries; every write goes through
  /// [_nutrition], so the open Nutrition screen hears of it.
  final WorkoutRepository _repository;
  final SyncProtocolValidator? _validator;

  /// Where the receipt and the count go. Null in a test that only cares what
  /// was applied.
  final WatchMirrorTransport? _transport;

  final DateTime Function() _clock;
  final String Function() _newId;

  /// Applies every water tap in [envelope], in message order, then
  /// acknowledges them and sends the day's count (D-3, D-8(b)).
  ///
  /// A tap counts on the phone's local calendar day it was tapped, however
  /// late it arrives. A refused message applies, acknowledges and sends
  /// nothing.
  Future<WatchWaterLogResult> receive(Map<String, Object?> envelope) async {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (!decision.accepted) {
      return const WatchWaterLogResult(outcome: WatchWaterLogOutcome.refused);
    }

    final taps = _taps(envelope);
    if (taps.isEmpty) {
      return const WatchWaterLogResult(outcome: WatchWaterLogOutcome.ignored);
    }

    final changed = <String>[];
    final acknowledged = <String>[];
    for (final tap in taps) {
      final entryId = tap['entryId'];
      final loggedAt = tap['loggedAt'];
      final change = tap['glassChange'];
      // Unreadable without a validator to have refused it: not taken on, so
      // not acknowledged either.
      if (entryId is! String || loggedAt is! String) continue;
      if (change != 'add' && change != 'remove') continue;
      final tappedAt = DateTime.tryParse(loggedAt);
      if (tappedAt == null) continue;

      final applied = await _nutrition.applyWatchWaterTap(
        dateMs: OmniDateUtils.startOfDayMs(tappedAt.toLocal()),
        tapId: entryId,
        add: change == 'add',
      );
      if (applied) changed.add(entryId);
      acknowledged.add(entryId);
    }

    await _acknowledge(acknowledged);
    if (acknowledged.isNotEmpty) await _sendCount();

    return WatchWaterLogResult(
      outcome: acknowledged.isEmpty
          ? WatchWaterLogOutcome.ignored
          : WatchWaterLogOutcome.applied,
      changedTapIds: changed,
      acknowledgedEntryIds: acknowledged,
    );
  }

  /// Tells the wrist which taps the phone has taken on — the receipt shape the
  /// food quick-log already sends.
  Future<void> _acknowledge(List<String> entryIds) async {
    final transport = _transport;
    if (transport == null || entryIds.isEmpty) return;

    await transport.send(
      WatchNutritionLogBridge.receiptFor(
        entryIds: entryIds,
        sentAt: _clock(),
        messageId: _newId(),
      ),
    );
  }

  /// The count of the phone's today, read now. A read that throws sends
  /// nothing, and a frame the radio did not carry is not retried: the wrist
  /// asks for the count again on its next sync.
  Future<void> _sendCount() async {
    final transport = _transport;
    if (transport == null) return;

    final Map<String, Object?> frame;
    try {
      frame = await WatchReferenceSync.readWaterDown(
        repository: _repository,
        stepMl: _nutrition.waterStepMl,
        generatedAt: _clock(),
      );
    } catch (_) {
      return;
    }
    await transport.send(frame);
  }

  /// The water taps in [envelope], and nothing else.
  List<Map<String, Object?>> _taps(Map<String, Object?> envelope) {
    if (envelope['type'] != 'observations_up') return const [];
    final payload = envelope['payload'];
    if (payload is! Map) return const [];
    final events = payload['events'];
    if (events is! List) return const [];

    return [
      for (final event in events)
        if (event is Map && event['kind'] == WatchObservationKind.waterGlass)
          event.cast<String, Object?>(),
    ];
  }
}
