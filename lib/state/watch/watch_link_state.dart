import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/platform/watch_link_info.dart';
import '../../core/platform/watch_link_source.dart';
import '../../data/repositories/workout_repository.dart';

/// Where the watch stands, from the phone's side.
enum WatchLinkPhase { notPaired, appNotInstalled, notReachable, connected }

/// How the watch is doing, for the one status row in Settings (plan 47c).
///
/// Reads the pairing and reachability from a [WatchLinkSource], and remembers
/// the moment the phone last heard a frame from the watch (persisted through
/// the repository, written at most once per [persistEvery]).
class WatchLinkState extends ChangeNotifier {
  WatchLinkState({
    required WatchLinkSource source,
    required WorkoutRepository repository,
    DateTime Function()? clock,
    this.persistEvery = const Duration(seconds: 30),
  }) : _source = source,
       _repository = repository,
       _clock = clock ?? DateTime.now;

  static const String lastHeardKey = 'watch_last_heard_ms';

  final WatchLinkSource _source;
  final WorkoutRepository _repository;
  final DateTime Function() _clock;
  final Duration persistEvery;

  WatchLinkInfo? _info;
  DateTime? _lastHeard;
  DateTime? _lastPersistedAt;
  StreamSubscription<WatchLinkInfo>? _changes;
  StreamSubscription<DateTime>? _heard;
  bool _disposed = false;

  DateTime? get lastHeard => _lastHeard;

  WatchLinkPhase get phase {
    final info = _info;
    if (info == null) return WatchLinkPhase.notReachable;
    if (!info.paired) return WatchLinkPhase.notPaired;
    if (!info.appInstalled) return WatchLinkPhase.appNotInstalled;
    return info.reachable
        ? WatchLinkPhase.connected
        : WatchLinkPhase.notReachable;
  }

  String get statusLabel => switch (phase) {
    WatchLinkPhase.connected => 'Connected',
    WatchLinkPhase.notReachable => 'Not reachable',
    WatchLinkPhase.notPaired => 'Not paired',
    WatchLinkPhase.appNotInstalled => 'Watch app not installed',
  };

  String lastSyncedLabel(DateTime now) {
    final heard = _lastHeard;
    if (heard == null) return 'Never synced';
    final age = now.difference(heard);
    if (age < const Duration(minutes: 1)) return 'Last synced just now';
    if (age < const Duration(hours: 1)) {
      return 'Last synced ${age.inMinutes} min ago';
    }
    if (age < const Duration(days: 1)) {
      return 'Last synced ${age.inHours} h ago';
    }
    if (age < const Duration(days: 7)) return 'Last synced ${age.inDays} d ago';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = heard.toLocal();
    return 'Last synced ${local.day} ${months[local.month - 1]}';
  }

  Future<void> initialize() async {
    final stored = int.tryParse(
      await _repository.getPreferenceString(lastHeardKey) ?? '',
    );
    if (stored != null && stored > 0) {
      _lastHeard = DateTime.fromMillisecondsSinceEpoch(stored, isUtc: true);
    }
    _changes = _source.linkChanges.listen(_onInfo);
    _heard = _source.heard.listen(_onHeard);
    await refresh();
  }

  /// Re-reads the pairing. A failure keeps what was known.
  Future<void> refresh() async {
    try {
      _onInfo(await _source.linkInfo());
    } catch (_) {
      // The last answer stands.
    }
  }

  void _onInfo(WatchLinkInfo info) {
    if (_disposed) return;
    _info = info;
    notifyListeners();
  }

  void _onHeard(DateTime at) {
    if (_disposed) return;
    _lastHeard = at;
    notifyListeners();
    final now = _clock();
    final last = _lastPersistedAt;
    if (last != null && now.difference(last) < persistEvery) return;
    _lastPersistedAt = now;
    // The stamp is a convenience across a restart, so a failed write is dropped:
    // the throttle keeps a broken store from becoming a retry storm.
    unawaited(
      _repository
          .setPreferenceString(
            lastHeardKey,
            at.toUtc().millisecondsSinceEpoch.toString(),
          )
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    unawaited(_heard?.cancel());
    super.dispose();
  }
}
