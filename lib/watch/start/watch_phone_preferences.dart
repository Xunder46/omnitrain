/// The phone's settings the wrist honours, as `preferences_down` last brought
/// them (plan 283a, D-28302).
///
/// Reference data like the routines and the food list: the wrist learns it when
/// it syncs, keeps every copy it accepts and reads the newest. Mirrors the Apple
/// client's `WatchPhonePreferences`.
library;

import '../../core/sync_protocol/message_validator.dart';
import '../logging/watch_metric_stepping.dart';
import '../session/watch_records.dart';
import '../session/watch_session_store.dart';

class WatchPhonePreferences {
  WatchPhonePreferences({
    required WatchSessionStore store,
    SyncProtocolValidator? validator,
    DateTime Function()? clock,
  }) : _store = store,
       _validator = validator,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final WatchSessionStore _store;
  final SyncProtocolValidator? _validator;
  final DateTime Function() _clock;

  final List<WatchPreferencesRecord> _copies = [];

  /// The copy that applies: the latest `generatedAt`, and on a tie the copy
  /// received later (the higher store sequence). Null until the phone has sent
  /// one.
  WatchPreferencesRecord? get current {
    WatchPreferencesRecord? best;
    for (final copy in _copies) {
      if (best == null) {
        best = copy;
        continue;
      }
      final byTime = copy.generatedAt.compareTo(best.generatedAt);
      if (byTime > 0 || (byTime == 0 && copy.sequence > best.sequence)) {
        best = copy;
      }
    }
    return best;
  }

  /// Whether a session the wrist ends asks for the effort rating. A wrist that
  /// has never heard from the phone does not know the setting, so it does not
  /// ask.
  bool get asksForEffortRating => current?.effortRatingPrompt ?? false;

  /// How often a rest pings, in seconds; 0 (Off) until the phone has said.
  int get restPingSeconds => current?.restPingSeconds ?? 0;

  /// The phone's theme accent `#RRGGBB`, or null.
  String? get accentColorHex => current?.accentColorHex;

  /// The units the wrist reads in, with the rest-ping interval: kilograms and
  /// kilometres and Off until a copy says otherwise (a copy that carried no
  /// unit reads as the default, never as the previous copy's).
  WatchUnitPreferences get units => WatchUnitPreferences(
    weightUnit: current?.weightUnit ?? 'kg',
    distanceUnit: current?.distanceUnit ?? 'km',
    restPingSeconds: restPingSeconds,
  );

  /// Reads every accepted copy back out of storage. Call on launch.
  Future<void> restore() async {
    final contents = await _store.readAll();
    _copies
      ..clear()
      ..addAll(contents.preferences);
  }

  /// Applies a `preferences_down` message; true when the copy it stored is now
  /// the one that applies.
  ///
  /// A message the wrist cannot read is refused with nothing stored. A copy
  /// older than the one that applies is understood and dropped. Anything else
  /// is stored (a copy stamped the same moment as the current one included, so
  /// the later-received of the two applies).
  Future<bool> applyPreferencesDown(Map<String, Object?> envelope) async {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (!decision.accepted) return false;
    if (envelope['type'] != 'preferences_down') return false;

    final messageId = envelope['messageId'];
    final payload = envelope['payload'];
    if (messageId is! String || payload is! Map) return false;

    final generatedAt = _instant(payload['generatedAt']);
    final asks = payload['effortRatingPrompt'];
    final restPing = payload['restPingSeconds'];
    if (generatedAt == null || asks is! bool || restPing is! int) return false;
    if (restPing < 0) return false;

    final applying = current;
    if (applying != null && generatedAt.isBefore(applying.generatedAt)) {
      return false;
    }

    final accent = payload['accentColorHex'];
    final weight = payload['weightUnit'];
    final distance = payload['distanceUnit'];

    final recordId = 'prefs-$messageId';
    final stored = await _store.append(
      WatchPreferencesRecord(
        recordId: recordId,
        recordedAt: _clock(),
        generatedAt: generatedAt,
        effortRatingPrompt: asks,
        restPingSeconds: restPing,
        accentColorHex: accent is String ? accent : null,
        weightUnit: weight is String ? weight : null,
        distanceUnit: distance is String ? distance : null,
      ),
    );
    if (!_copies.any((copy) => copy.recordId == stored.recordId)) {
      _copies.add(stored);
    }
    return current?.recordId == recordId;
  }

  /// A UTC instant from the wire, or null when it is not one.
  DateTime? _instant(Object? value) {
    if (value is! String) return null;
    try {
      return parseUtcIso(value);
    } on FormatException {
      return null;
    }
  }
}
