import 'package:flutter/foundation.dart';

/// The wrist's running active-energy total for the session it is running, as
/// the last `energy_live` frame said (plan 135 D-13520). Live only: nothing is
/// stored, and a frame that does not hold up is ignored without a sound.
class WatchLiveEnergy {
  final ValueNotifier<({String sessionId, double kcal, DateTime at})?> latest =
      ValueNotifier(null);

  void receive(Map<String, Object?> envelope) {
    if (envelope['type'] != 'energy_live' || envelope['origin'] != 'watch') {
      return;
    }
    final sessionId = envelope['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) return;
    final payload = envelope['payload'];
    if (payload is! Map) return;
    final kcal = payload['activeEnergyKcal'];
    if (kcal is! num || !kcal.isFinite || kcal < 0) return;
    final at = _parseAt(payload['at']);
    if (at == null) return;
    final held = latest.value;
    if (held != null && held.sessionId == sessionId && !at.isAfter(held.at)) {
      return;
    }
    latest.value = (sessionId: sessionId, kcal: kcal.toDouble(), at: at);
  }

  /// The instant the wrist says the reading was taken; anything that is not a
  /// valid UTC-instant string is no reading at all.
  DateTime? _parseAt(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    // The wire shape is `YYYY-MM-DDTHH:MM:SS(.sss)Z`: `tryParse` also takes a
    // space separator, which the schemas refuse.
    if (parsed == null || !parsed.isUtc) return null;
    return value.length > 10 && value[10] == 'T' ? parsed : null;
  }
}
