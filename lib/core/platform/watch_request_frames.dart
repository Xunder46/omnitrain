/// The frames the radio carries that are not protocol messages.
///
/// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md` (D-2). Split
/// out of `watch_transport.dart` by plan 280 (D-28005) so the wrist app can
/// build and read these frames without linking the phone's transport — both
/// sides still share one definition, which is the point.
///
/// PROTOCOL.md is explicit that a request is a transport concern: "The request
/// is a transport concern and carries no message of its own; the answer MUST be
/// a `session_snapshot`." Asking for the routines the same way keeps one
/// vocabulary for both.
library;

import '../sync_protocol/wire_timestamps.dart';

abstract final class WatchTransportRequest {
  /// Watch → phone: send the routines, optionally only what changed since.
  static const String routines = 'routines';

  /// Either direction: send your session state.
  static const String snapshot = 'snapshot';

  /// The request [frame] is, or null when it is a protocol message instead.
  ///
  /// One test decides which: a protocol envelope always carries `type`, and a
  /// request never does.
  static String? nameOf(Map<String, Object?> frame) {
    if (frame['type'] is String) return null;
    final request = frame['request'];
    return request is String ? request : null;
  }

  /// The wrist's sync request frame.
  ///
  /// [exercisesVersion] is the version of the exercise list the wrist holds, and
  /// is added only when it says one — a wrist holding nothing omits the key
  /// rather than naming an empty version, the same way a first sync omits
  /// `since` (D-3833).
  ///
  /// [holdsBests] says the wrist holds a bests frame, and adds `holdsBests:
  /// true` only when it is true — a wrist holding nothing omits the key rather
  /// than sending `false` (87c, D-2).
  ///
  /// [wantsWater] asks for the day's water count, and adds `wantsWater: true`
  /// only when it is true — omitted otherwise, never `false` (plan 94, D-9).
  static Map<String, Object?> routinesFrame({
    DateTime? since,
    String? exercisesVersion,
    bool holdsBests = false,
    bool wantsWater = false,
  }) {
    final stamp = since == null ? null : utcIso(since);
    final version = exercisesVersion == null || exercisesVersion.isEmpty
        ? null
        : exercisesVersion;
    return {
      'request': routines,
      'since': ?stamp,
      'exercisesVersion': ?version,
      if (holdsBests) 'holdsBests': true,
      if (wantsWater) 'wantsWater': true,
    };
  }

  /// The exercise-list version [frame] names, or null when it names none.
  ///
  /// A request from a wrist that holds no list — or one whose key is not a
  /// non-empty string — names no version, and the phone answers with the whole
  /// list (D-3833, D-3834).
  static String? exercisesVersionOf(Map<String, Object?> frame) {
    final version = frame['exercisesVersion'];
    return version is String && version.isNotEmpty ? version : null;
  }

  /// The held-routines stamp [frame] names, or null when it names none.
  ///
  /// The wrist names the `generatedAt` of the routines copy it holds as
  /// `since`; anything unreadable — absent, empty, not a string, not a date —
  /// is "names none", and the phone answers with everything.
  static DateTime? sinceOf(Map<String, Object?> frame) {
    final since = frame['since'];
    if (since is! String || since.isEmpty) return null;
    return DateTime.tryParse(since)?.toUtc();
  }

  /// Whether [frame] says the wrist holds a bests frame.
  ///
  /// Only the boolean `true` counts as held: a string, a number, `false` and an
  /// absent key are all "not held", so the phone sends the frame as it always
  /// has (87c, D-2).
  static bool holdsBestsOf(Map<String, Object?> frame) =>
      frame['holdsBests'] == true;

  /// Whether [frame] asks for the day's water count (`water_down`).
  ///
  /// Only the boolean `true` counts as asked: a string, a number, `false`, null
  /// and an absent key are all "not asked", the [holdsBestsOf] rule (plan 94,
  /// D-9).
  static bool wantsWaterOf(Map<String, Object?> frame) =>
      frame['wantsWater'] == true;

  static Map<String, Object?> snapshotFrame() => const {'request': snapshot};
}
